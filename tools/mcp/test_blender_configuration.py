"""Pin-safe addon migration and readiness checks without writing user preferences."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import uuid

ROOT = Path(__file__).resolve().parents[2]
EXCLUSIVE_BIND = (
    '            if os.name == "nt":\n'
    '                if not hasattr(socket, "SO_EXCLUSIVEADDRUSE"):\n'
    '                    raise RuntimeError("Windows exclusive socket binding is unavailable.")\n'
    "                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)"
).encode()
REUSE_BIND = b"            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)"


def load_configuration():
    handlers = ModuleType("bpy.app.handlers")
    handlers.persistent = lambda function: function
    bpy = Mock()
    bpy.app.background = False
    bpy.app.handlers.load_post = []
    bpy.types = SimpleNamespace()
    spec = importlib.util.spec_from_file_location("futsal_test_configuration", ROOT / "tools" / "blender" / "configure_blender.py")
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"addon_utils": Mock(), "bpy": bpy, "bpy.app.handlers": handlers}):
        spec.loader.exec_module(module)
    return module


class BlenderConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.config = load_configuration()
        self.work = ROOT / "tools" / "mcp" / "runtime" / f"configuration-test-{uuid.uuid4().hex}"
        self.work.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.work)
        self.target = self.work / "blender_mcp.py"
        self.preferences = self.work / "userpref.blend"
        self.preferences.write_bytes(b"original preferences")
        self.pref_backup = self.work / "userpref.blend.futsal-before-mcp.bak"
        self.addon_backup = self.target.with_suffix(".py.futsal-before-mcp.bak")
        self.config.RUNTIME = self.work
        self.config.addon_path = lambda: self.target
        self.config.bpy.utils.user_resource.return_value = str(self.work)
        self.config.enforce_policy = Mock()
        self.config.inspect_configuration = Mock(side_effect=lambda: {
            "addonPath": str(self.target),
            "addonSha256": hashlib.sha256(self.target.read_bytes()).hexdigest(),
        })

        def save_preferences():
            self.preferences.write_bytes(b"saved policy preferences")
            return {"FINISHED"}

        self.config.bpy.ops.wm.save_userpref.side_effect = save_preferences

    def previous_addon(self):
        current = self.config.policy_addon_bytes()
        self.assertEqual(current.count(EXCLUSIVE_BIND), 1)
        previous = current.replace(EXCLUSIVE_BIND, REUSE_BIND, 1)
        pin = json.loads((ROOT / "tools" / "mcp" / "upstream.json").read_text())
        self.assertEqual(
            pin["addonPolicy"]["upgradeFromSha256"],
            ["be11621dca5fce7d00d291837a03b3bfe7d6acdbc27d42d3d73c98ab66491483"],
        )
        self.assertEqual(hashlib.sha256(previous).hexdigest(), pin["addonPolicy"]["upgradeFromSha256"][0])
        return previous

    def test_policy_patch_and_previous_hash_are_exact(self):
        current = self.config.policy_addon_bytes()
        pin = json.loads((ROOT / "tools" / "mcp" / "upstream.json").read_text())
        self.assertEqual(hashlib.sha256(current).hexdigest(), pin["addonPolicy"]["installedSha256"])
        self.assertEqual(len(pin["addonPolicy"]["changes"]), 5)
        self.assertNotIn(b"socket.SO_REUSEADDR", current)
        self.previous_addon()

    def test_clean_install_is_idempotent_and_keeps_original_preferences(self):
        self.config.install()
        first = self.target.read_bytes()
        self.config.install()
        self.assertEqual(self.target.read_bytes(), first)
        self.assertEqual(first, self.config.policy_addon_bytes())
        self.assertEqual(self.pref_backup.read_bytes(), b"original preferences")
        self.assertFalse(self.addon_backup.exists())
        self.config.addon_utils.disable.assert_not_called()

    def test_previous_patch_upgrade_is_idempotent_and_keeps_existing_backups(self):
        self.target.write_bytes(self.previous_addon())
        self.addon_backup.write_bytes(b"original addon backup")
        self.pref_backup.write_bytes(b"original preferences backup")
        self.config.install()
        self.config.install()
        self.assertEqual(self.target.read_bytes(), self.config.policy_addon_bytes())
        self.assertEqual(self.addon_backup.read_bytes(), b"original addon backup")
        self.assertEqual(self.pref_backup.read_bytes(), b"original preferences backup")
        self.config.addon_utils.disable.assert_called_once_with("blender_mcp", default_set=False)

    def test_upstream_upgrade_backs_up_only_the_original_addon(self):
        source = ROOT / "tools" / "mcp" / ".venv" / "Lib" / "site-packages" / "blender_mcp" / "bundled" / "addon.py"
        self.target.write_bytes(source.read_bytes())
        self.config.install()
        self.config.install()
        self.assertEqual(self.target.read_bytes(), self.config.policy_addon_bytes())
        self.assertEqual(self.addon_backup.read_bytes(), source.read_bytes())

    def test_unknown_or_edited_previous_addon_is_not_overwritten(self):
        for data in (b"unrelated local addon", self.previous_addon() + b"\n# local edit\n"):
            with self.subTest(sha256=hashlib.sha256(data).hexdigest()):
                self.target.write_bytes(data)
                with self.assertRaisesRegex(RuntimeError, "Refusing to overwrite"):
                    self.config.install()
                self.assertEqual(self.target.read_bytes(), data)
                self.assertEqual(self.preferences.read_bytes(), b"original preferences")
                self.assertFalse(self.addon_backup.exists())
                self.assertFalse(self.pref_backup.exists())
                self.config.addon_utils.disable.assert_not_called()
                self.config.bpy.ops.wm.save_userpref.assert_not_called()

    @unittest.skipUnless(hasattr(socket, "SO_EXCLUSIVEADDRUSE"), "Requires the Windows socket option.")
    def test_failed_or_nonexclusive_listener_never_reports_readiness(self):
        ready, stop = self.work / "ready.json", self.work / "stop"
        for running, exclusive in ((False, 0), (True, 0)):
            with self.subTest(running=running, exclusive=exclusive):
                server = Mock(running=running)
                server.socket = Mock() if running else None
                if running:
                    server.socket.getsockname.return_value = ("127.0.0.1", 9876)
                    server.socket.getsockopt.return_value = exclusive
                module = SimpleNamespace(BlenderMCPServer=Mock(return_value=server))
                self.config.bpy.types = SimpleNamespace()
                self.config.inspect_configuration.return_value = {}
                self.config.inspect_configuration.side_effect = None
                with patch.object(self.config.importlib, "import_module", return_value=module):
                    with self.assertRaisesRegex(RuntimeError, "will not report readiness"):
                        self.config.serve(ready, stop)
                self.assertFalse(ready.exists())
                self.config.bpy.app.timers.register.assert_not_called()
                self.assertEqual(server.stop.call_count, int(running))

    @unittest.skipUnless(hasattr(socket, "SO_EXCLUSIVEADDRUSE"), "Requires the Windows socket option.")
    def test_exclusive_listener_reports_owned_pid_after_socket_checks(self):
        server = Mock(running=True)
        server.socket.getsockname.return_value = ("127.0.0.1", 9876)
        server.socket.getsockopt.return_value = 1
        module = SimpleNamespace(BlenderMCPServer=Mock(return_value=server))
        self.config.inspect_configuration.return_value = {}
        self.config.inspect_configuration.side_effect = None
        self.config.bpy.data.scenes = []
        ready, stop = self.work / "ready.json", self.work / "stop"
        with patch.object(self.config.importlib, "import_module", return_value=module):
            self.config.serve(ready, stop)
        self.assertEqual(json.loads(ready.read_text()), {"pid": os.getpid(), "host": "127.0.0.1", "port": 9876})
        server.socket.getsockopt.assert_called_once_with(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE)
        self.config.bpy.app.timers.register.assert_called_once()
        server.stop.assert_not_called()


if __name__ == "__main__":
    unittest.main()
