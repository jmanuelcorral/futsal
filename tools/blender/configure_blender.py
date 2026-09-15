"""Run only inside the pinned Blender, using --disable-autoexec."""

import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import shutil
import socket
import sys

import addon_utils
import bpy
from bpy.app.handlers import persistent

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "tools" / "mcp" / "runtime"
MODULE = "blender_mcp"
SERVICES = ("polyhaven", "hyper3d", "hunyuan3d", "sketchfab", "polypizza")


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def policy_addon_bytes():
    pin = json.loads((ROOT / "tools" / "mcp" / "upstream.json").read_text())
    source = ROOT / "tools" / "mcp" / ".venv" / "Lib" / "site-packages"
    data = (source / "blender_mcp" / "bundled" / "addon.py").read_bytes()
    if git_blob(data) != pin["gitBlobs"]["addon.py"]:
        raise RuntimeError("Bundled addon does not match the reviewed upstream commit.")
    replacements = (
        (
            'description="Allow collection of prompts, code snippets, screenshots, and trajectory data to help improve MCP for Blender",\n        default=True,',
            'description="Allow collection of prompts, code snippets, screenshots, and trajectory data to help improve MCP for Blender",\n        default=False,',
        ),
        (
            'description="Automatically start the MCP server when Blender loads",\n        default=True',
            'description="Automatically start the MCP server when Blender loads",\n        default=False',
        ),
        ("auto_start = scene.blendermcp_auto_start_server", "auto_start = False"),
        ("auto_start = True", "auto_start = False"),
        (
            "            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)",
            '            if os.name == "nt":\n'
            '                if not hasattr(socket, "SO_EXCLUSIVEADDRUSE"):\n'
            '                    raise RuntimeError("Windows exclusive socket binding is unavailable.")\n'
            "                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)",
        ),
    )
    for before, after in replacements:
        if data.count(before.encode()) != 1:
            raise RuntimeError("Reviewed addon policy patch no longer applies exactly.")
        data = data.replace(before.encode(), after.encode(), 1)
    if hashlib.sha256(data).hexdigest() != pin["addonPolicy"]["installedSha256"]:
        raise RuntimeError("Derived addon bytes do not match the reviewed local policy hash.")
    return data


def addon_path():
    return Path(bpy.utils.user_resource("SCRIPTS", path="addons", create=True)) / f"{MODULE}.py"


@persistent
def enforce_policy(_unused=None):
    prefs = bpy.context.preferences.addons.get(MODULE)
    if prefs is None:
        raise RuntimeError("Blender MCP addon is not enabled.")
    prefs.preferences.telemetry_consent = False
    for scene in bpy.data.scenes:
        scene.blendermcp_auto_start_server = False
        scene.blendermcp_port = 9876
        for service in SERVICES:
            setattr(scene, f"blendermcp_use_{service}", False)


def inspect_configuration():
    if bpy.app.version[:3] != (4, 5, 13):
        raise RuntimeError(f"Expected Blender 4.5.13, found {bpy.app.version_string}.")
    configured, loaded = addon_utils.check(MODULE)
    if not configured or not loaded:
        raise RuntimeError(f"Addon is not both saved-enabled and loaded: {(configured, loaded)}")
    if addon_path().read_bytes() != policy_addon_bytes():
        raise RuntimeError("Installed addon differs from the pinned source plus reviewed policy patch.")
    prefs = bpy.context.preferences.addons[MODULE].preferences
    if prefs.telemetry_consent:
        raise RuntimeError("Telemetry consent must be disabled in saved Blender preferences.")
    return {
        "blenderVersion": bpy.app.version_string,
        "addonEnabled": configured,
        "addonLoaded": loaded,
        "telemetryConsent": bool(prefs.telemetry_consent),
        "addonPath": str(addon_path()),
        "addonSha256": hashlib.sha256(addon_path().read_bytes()).hexdigest(),
        "protocolVersion": importlib.import_module(MODULE).ADDON_PROTOCOL_VERSION,
        "externalServices": {
            service: bool(getattr(bpy.context.scene, f"blendermcp_use_{service}"))
            for service in SERVICES
        },
    }


def install():
    target = addon_path()
    data = policy_addon_bytes()
    if target.exists() and target.read_bytes() != data:
        pin = json.loads((ROOT / "tools" / "mcp" / "upstream.json").read_text())
        existing = target.read_bytes()
        if (
            git_blob(existing) != pin["gitBlobs"]["addon.py"]
            and hashlib.sha256(existing).hexdigest() not in pin["addonPolicy"]["upgradeFromSha256"]
        ):
            raise RuntimeError(f"Refusing to overwrite an unrelated or locally edited addon: {target}")
        backup = target.with_suffix(".py.futsal-before-mcp.bak")
        if not backup.exists():
            shutil.copy2(target, backup)
        addon_utils.disable(MODULE, default_set=False)
    if not target.exists() or target.read_bytes() != data:
        target.write_bytes(data)
    bpy.utils.refresh_script_paths()
    addon_utils.modules(refresh=True)
    addon_utils.enable(MODULE, default_set=True, persistent=True)
    enforce_policy()
    config_dir = Path(bpy.utils.user_resource("CONFIG", create=True))
    preferences = config_dir / "userpref.blend"
    backup = config_dir / "userpref.blend.futsal-before-mcp.bak"
    if preferences.exists() and not backup.exists():
        shutil.copy2(preferences, backup)
    result = bpy.ops.wm.save_userpref()
    if result != {"FINISHED"} or not preferences.is_file():
        raise RuntimeError("Blender could not persist user preferences.")
    report = inspect_configuration()
    report["preferencesPath"] = str(preferences)
    report["automaticSocketStartup"] = False
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (RUNTIME / "addon-install.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("FUTSAL_ADDON_INSTALLED " + json.dumps(report), flush=True)


def verify():
    report = inspect_configuration()
    if any(report["externalServices"].values()):
        raise RuntimeError("An external integration is enabled.")
    addon_utils.enable("io_scene_gltf2", default_set=False)
    bpy.ops.export_scene.gltf.get_rna_type()
    RUNTIME.mkdir(parents=True, exist_ok=True)
    output = RUNTIME / f"gltf-probe-{os.getpid()}.glb"
    scene = bpy.data.scenes.new("FutsalToolingProbe")
    mesh = bpy.data.meshes.new("FutsalProbeMesh")
    mesh.from_pydata([(0, 0, 0), (1, 0, 0), (0, 1, 0)], [], [(0, 1, 2)])
    obj = bpy.data.objects.new("FutsalExportTriangle", mesh)
    scene.collection.objects.link(obj)
    try:
        with bpy.context.temp_override(scene=scene):
            result = bpy.ops.export_scene.gltf(
                filepath=str(output),
                export_format="GLB",
                use_active_scene=True,
                export_animations=False,
            )
        content = output.read_bytes()
        if result != {"FINISHED"} or content[:4] != b"glTF" or len(content) <= 20:
            raise RuntimeError("The glTF exporter did not produce a valid GLB.")
        json_length = int.from_bytes(content[12:16], "little")
        document = json.loads(content[20:20 + json_length])
        node_names = [node.get("name") for node in document.get("nodes", [])]
        if node_names != ["FutsalExportTriangle"]:
            raise RuntimeError("glTF probe unexpectedly exported objects outside its isolated scene.")
        report["gltfExport"] = {"operator": "export_scene.gltf", "bytes": len(content), "nodes": node_names}
    finally:
        output.unlink(missing_ok=True)
        bpy.data.scenes.remove(scene)
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    (RUNTIME / "blender-verification.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("FUTSAL_BLENDER_VERIFIED " + json.dumps(report), flush=True)


def serve(ready_file, stop_file):
    if bpy.app.background:
        raise RuntimeError("The upstream addon requires Blender's GUI event loop; do not use --background.")
    addon_utils.enable(MODULE, default_set=True, persistent=True)
    enforce_policy()
    report = inspect_configuration()
    module = importlib.import_module(MODULE)
    existing = getattr(bpy.types, "blendermcp_server", None)
    if existing and existing.running:
        raise RuntimeError("This Blender process already has a socket server; refusing to replace it.")
    server = module.BlenderMCPServer(host="127.0.0.1", port=9876)
    bpy.types.blendermcp_server = server
    server.start()
    if (
        not server.running
        or server.socket is None
        or server.socket.getsockname() != ("127.0.0.1", 9876)
        or (
            os.name == "nt"
            and (
                not hasattr(socket, "SO_EXCLUSIVEADDRUSE")
                or server.socket.getsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE) != 1
            )
        )
    ):
        if server.running:
            server.stop()
        raise RuntimeError(
            "Could not bind Blender MCP exclusively to 127.0.0.1:9876. "
            "Another session may own the port; this process will not report readiness."
        )
    for scene in bpy.data.scenes:
        scene.blendermcp_server_running = True
    if enforce_policy not in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.append(enforce_policy)

    def watch_stop_file():
        if stop_file.exists():
            server.stop()
            bpy.ops.wm.quit_blender()
            return None
        return 0.25

    bpy.app.timers.register(watch_stop_file, first_interval=0.25, persistent=True)
    report.update(pid=os.getpid(), host="127.0.0.1", port=9876)
    ready_file.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("FUTSAL_BLENDER_SOCKET_READY " + json.dumps(report), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("install", "verify", "serve"))
    parser.add_argument("--ready-file", type=Path)
    parser.add_argument("--stop-file", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    if args.mode == "install":
        install()
    elif args.mode == "verify":
        verify()
    elif args.ready_file and args.stop_file:
        serve(args.ready_file, args.stop_file)
    else:
        parser.error("serve requires --ready-file and --stop-file")


if __name__ == "__main__":
    main()
