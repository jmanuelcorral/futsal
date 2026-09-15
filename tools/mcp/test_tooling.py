import hashlib
import json
from pathlib import Path
import socket
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from mcp import StdioServerParameters

from server import ROOT, TOOLS
from start_blender import check_port_free, stop_owned_process, wait_until_ready
from verify_package import verify_installed_package


class ToolchainTests(unittest.TestCase):
    def test_installed_upstream_files_are_pinned(self):
        report = verify_installed_package()
        self.assertEqual(report["version"], "1.9.1")
        self.assertEqual(report["verifiedGitBlobs"], 10)
        self.assertEqual(report["mcpSdkVersion"], "1.30.0")

    def test_copilot_config_preserves_squad_and_restricts_blender(self):
        config = json.loads((ROOT / ".mcp.json").read_text())["mcpServers"]
        self.assertEqual(
            config["squad_state"],
            {
                "command": "npx",
                "args": ["-y", "@bradygaster/squad-cli@0.10.0", "state-mcp"],
                "env": {},
                "tools": ["*"],
            },
        )
        self.assertEqual(sorted(config["blender"]["tools"]), sorted(TOOLS))
        self.assertEqual(config["blender"]["env"]["DISABLE_TELEMETRY"], "true")
        self.assertEqual(config["blender"]["env"]["BLENDER_MCP_SAFE_MODE"], "1")
        self.assertNotIn("Users\\", json.dumps(config["blender"]))

    def test_generated_config_is_valid_stdio_and_uses_existing_absolute_paths(self):
        config = json.loads((Path(__file__).parent / "copilot.local.json").read_text(encoding="utf-8-sig"))
        blender = config["mcpServers"]["blender"]
        params = StdioServerParameters(command=blender["command"], args=blender["args"], env=blender["env"])
        self.assertTrue(Path(params.command).is_absolute())
        self.assertTrue(Path(params.command).is_file())
        self.assertTrue(Path(params.args[1]).is_absolute())
        self.assertTrue(Path(params.args[1]).is_file())
        self.assertEqual(sorted(blender["tools"]), sorted(TOOLS))

    def test_dream_loop_exact_bytes_and_license(self):
        directory = ROOT / ".github" / "skills" / "dream-loop"
        pin = json.loads((directory / "UPSTREAM.json").read_text())
        for name, expected in pin["files"].items():
            with self.subTest(file=name):
                data = (directory / name).read_bytes()
                blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                self.assertEqual(len(data), expected["bytes"])
                self.assertEqual(blob, expected["gitBlobSha1"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), expected["sha256"])

    def test_occupied_port_is_rejected_without_replacing_listener(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            try:
                listener.bind(("127.0.0.1", 9876))
            except OSError:
                self.skipTest("An existing session owns port 9876; it was not touched.")
            listener.listen(1)
            with self.assertRaisesRegex(RuntimeError, "already in use"):
                check_port_free()
            self.assertEqual(listener.getsockname(), ("127.0.0.1", 9876))

    def test_windows_preflight_fails_closed_without_exclusive_option(self):
        with patch("start_blender.os", SimpleNamespace(name="nt")):
            with patch("start_blender.socket", spec=["socket", "AF_INET", "SOCK_STREAM"]) as sockets:
                with self.assertRaisesRegex(RuntimeError, "exclusive socket binding is unavailable"):
                    check_port_free()
                sockets.socket.return_value.__enter__.return_value.bind.assert_not_called()

    def test_non_windows_preflight_uses_default_non_reuse_binding(self):
        with patch("start_blender.os", SimpleNamespace(name="posix")):
            with patch("start_blender.socket.socket") as factory:
                check_port_free()
                probe = factory.return_value.__enter__.return_value
                probe.bind.assert_called_once_with(("127.0.0.1", 9876))
                probe.setsockopt.assert_not_called()

    def test_readiness_requires_owned_pid(self):
        process = Mock(pid=12)
        process.poll.return_value = None
        ready_file = Mock()
        ready_file.is_file.return_value = True
        with patch("start_blender.read_json", return_value={"pid": 13, "host": "127.0.0.1", "port": 9876}):
            with self.assertRaisesRegex(RuntimeError, "owned process"):
                wait_until_ready(process, ready_file, 10)

    def test_readiness_requires_loopback(self):
        process = Mock(pid=12)
        process.poll.return_value = None
        ready_file = Mock()
        ready_file.is_file.return_value = True
        with patch("start_blender.read_json", return_value={"pid": 12, "host": "192.0.2.1", "port": 9876}):
            with self.assertRaisesRegex(RuntimeError, "loopback port"):
                wait_until_ready(process, ready_file, 10)

    def test_readiness_has_bounded_timeout(self):
        process = Mock()
        process.poll.return_value = None
        with patch("start_blender.time.monotonic", side_effect=[0, 11]):
            with self.assertRaises(TimeoutError):
                wait_until_ready(process, Mock(), 10)

    def test_early_process_exit_is_reported(self):
        process = Mock(pid=12, returncode=7)
        process.poll.return_value = 7
        with self.assertRaisesRegex(RuntimeError, r"exited during startup \(7\)"):
            wait_until_ready(process, Mock(), 10)

    def test_cleanup_prefers_graceful_stop_of_owned_process(self):
        process, stop_file = Mock(), Mock()
        process.poll.return_value = None
        stop_owned_process(process, stop_file)
        stop_file.touch.assert_called_once_with()
        process.wait.assert_called_once_with(timeout=10)
        process.terminate.assert_not_called()
        process.kill.assert_not_called()

    def test_cleanup_escalates_only_for_owned_process(self):
        process, stop_file = Mock(), Mock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("owned", 10), subprocess.TimeoutExpired("owned", 5), 0]
        stop_owned_process(process, stop_file)
        process.terminate.assert_called_once_with()
        process.kill.assert_called_once_with()
        self.assertEqual(process.wait.call_count, 3)

    def test_already_stopped_process_is_not_signalled(self):
        process, stop_file = Mock(), Mock()
        process.poll.return_value = 0
        stop_owned_process(process, stop_file)
        stop_file.touch.assert_not_called()
        process.terminate.assert_not_called()
        process.kill.assert_not_called()


if __name__ == "__main__":
    unittest.main()
