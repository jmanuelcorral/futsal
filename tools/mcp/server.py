"""Project-scoped stdio entry point for the pinned upstream MCP server."""

import asyncio
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TOOLS = (
    "get_addon_status",
    "get_scene_info",
    "get_object_info",
    "get_viewport_screenshot",
    "execute_blender_code",
    "disable_telemetry",
)


def main():
    runtime = ROOT / "tools" / "mcp" / "runtime"
    work = runtime / "work"
    work.mkdir(parents=True, exist_ok=True)
    local = json.loads((ROOT / "tools" / "mcp" / "local.json").read_text(encoding="utf-8-sig"))
    os.environ.update(
        BLENDER_HOST="127.0.0.1",
        BLENDER_PORT="9876",
        DISABLE_TELEMETRY="true",
        BLENDER_MCP_SAFE_MODE="1",
        BLENDERMCP_ADDONS_DIR=str(Path(local["addonPath"]).parent),
        APPDATA=str(runtime / "appdata"),
        XDG_CONFIG_HOME=str(runtime / "config"),
        TEMP=str(work),
        TMP=str(work),
    )
    import tempfile

    tempfile.tempdir = str(work)
    consent_file = runtime / "config" / "blender-mcp" / "consent_prompt.json"
    consent_file.parent.mkdir(parents=True, exist_ok=True)
    consent_file.write_text(
        json.dumps({"prompt_version": 1, "action": "decline", "consent": False, "via": "futsal-local-policy"}),
        encoding="utf-8",
    )
    from verify_package import verify_installed_package

    package = verify_installed_package()
    from blender_mcp import server as upstream
    from blender_mcp.safe_mode import safe_mode_enabled
    from blender_mcp.telemetry import get_telemetry

    if get_telemetry().config.enabled or not safe_mode_enabled():
        raise RuntimeError("Required telemetry opt-out or safe-mode policy was not applied.")
    available = asyncio.run(upstream.mcp.list_tools())
    names = {tool.name for tool in available}
    if not set(TOOLS).issubset(names):
        raise RuntimeError("The pinned server does not expose the expected local tools.")
    for name in names - set(TOOLS):
        upstream.mcp.remove_tool(name)
    report = {
        **package,
        "upstreamToolCount": len(available),
        "exposedToolCount": len(TOOLS),
        "exposedTools": list(TOOLS),
        "telemetryEnabled": get_telemetry().config.enabled,
        "safeMode": safe_mode_enabled(),
        "host": "127.0.0.1",
        "port": 9876,
        "pid": os.getpid(),
    }
    (runtime / "server-policy.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("FUTSAL_MCP_POLICY " + json.dumps(report), file=sys.stderr, flush=True)
    upstream.main()


if __name__ == "__main__":
    main()
