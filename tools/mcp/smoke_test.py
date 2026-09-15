"""Exercise the production stdio server through the official MCP client SDK."""

import argparse
import asyncio
import base64
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import struct

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.types import Implementation

from server import ROOT, TOOLS

RUNTIME = ROOT / "tools" / "mcp" / "runtime"
PROMPT = "Verify the local Blender toolchain without changing scene objects."


def text_result(result):
    if result.isError:
        raise RuntimeError(f"MCP tools/call returned isError: {result.content}")
    parts = [item.text for item in result.content if item.type == "text"]
    if not parts:
        raise RuntimeError("Expected text content in the MCP tool result.")
    text = "\n".join(parts)
    if text.lstrip().lower().startswith(("error", "failed to ")):
        raise RuntimeError(text)
    return text


async def run_smoke(expect_default_scene=False):
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (RUNTIME / "smoke-result.json").unlink(missing_ok=True)
    checks = {}
    calls = 0

    def require(name, condition):
        checks[name] = bool(condition)
        if not condition:
            raise RuntimeError(f"Smoke check failed: {name}")

    config_path = Path(__file__).with_name("copilot.local.json")
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))["mcpServers"]["blender"]
    require("copilot_tool_allowlist", sorted(config["tools"]) == sorted(TOOLS))
    params = StdioServerParameters(
        command=config["command"],
        args=config["args"],
        cwd=str(ROOT),
        env=config["env"],
    )
    with (RUNTIME / "mcp-smoke.stderr.log").open("w", encoding="utf-8") as log:
        async with stdio_client(params, errlog=log) as (read, write):
            async with ClientSession(
                read,
                write,
                read_timeout_seconds=timedelta(seconds=20),
                client_info=Implementation(name="futsal-tooling-smoke", version="1.0.0"),
            ) as session:
                initialized = await session.initialize()
                require("initialize", initialized.serverInfo.name == "BlenderMCP")
                listed = await session.list_tools()
                names = sorted(tool.name for tool in listed.tools)
                require("tools_list_core_only", names == sorted(TOOLS) and not listed.nextCursor)

                async def call(name, arguments):
                    nonlocal calls
                    calls += 1
                    return await session.call_tool(name, arguments)

                addon = json.loads(text_result(await call("get_addon_status", {"user_prompt": PROMPT})))
                require("addon_protocol_current", addon["up_to_date"] and addon["protocol_version"] == 5)
                require("saved_telemetry_consent_off", addon["telemetry_consent"] is False)
                before = json.loads(text_result(await call("get_scene_info", {"user_prompt": PROMPT})))
                require("scene_info_valid", isinstance(before.get("object_count"), int) and "objects" in before)
                if expect_default_scene:
                    require(
                        "isolated_default_scene",
                        before["object_count"] == 3
                        and sorted(obj["name"] for obj in before["objects"]) == ["Camera", "Cube", "Light"],
                    )
                if before["objects"]:
                    name = before["objects"][0]["name"]
                    obj = json.loads(
                        text_result(await call("get_object_info", {"object_name": name, "user_prompt": PROMPT}))
                    )
                    require("object_info", obj.get("name") == name)
                code = (
                    "import bpy\nimport json\n"
                    "print(json.dumps({"
                    "'polyhaven': bpy.context.scene.blendermcp_use_polyhaven,"
                    "'hyper3d': bpy.context.scene.blendermcp_use_hyper3d,"
                    "'hunyuan3d': bpy.context.scene.blendermcp_use_hunyuan3d,"
                    "'sketchfab': bpy.context.scene.blendermcp_use_sketchfab,"
                    "'polypizza': bpy.context.scene.blendermcp_use_polypizza}))"
                )
                status = text_result(await call("execute_blender_code", {"code": code, "user_prompt": PROMPT}))
                prefix = "Code executed successfully: "
                require("readonly_code_execution", status.startswith(prefix))
                services = json.loads(status[len(prefix):].strip())
                require("all_five_external_services_off", len(services) == 5 and all(v is False for v in services.values()))
                rejected = text_result(
                    await call("execute_blender_code", {"code": "import os", "user_prompt": PROMPT})
                )
                require("safe_mode_blocks_os_import", rejected.startswith("Rejected by safe mode"))
                screenshot = await call("get_viewport_screenshot", {"max_size": 256, "user_prompt": PROMPT})
                images = [item for item in screenshot.content if item.type == "image"]
                require("viewport_image_content", not screenshot.isError and len(images) == 1)
                image = base64.b64decode(images[0].data, validate=True)
                require("viewport_png_signature", image[:8] == b"\x89PNG\r\n\x1a\n")
                width, height = struct.unpack(">II", image[16:24])
                require("viewport_png_dimensions", 0 < width <= 256 and 0 < height <= 256)
                after = json.loads(text_result(await call("get_scene_info", {"user_prompt": PROMPT})))
                require("scene_unchanged_no_duplicates", before == after)
                policy = json.loads((RUNTIME / "server-policy.json").read_text())
                require("telemetry_disabled_and_safe_mode", not policy["telemetryEnabled"] and policy["safeMode"])
                require("loopback_only", policy["host"] == "127.0.0.1" and policy["port"] == 9876)
                report = {
                    "verifiedAt": datetime.now(timezone.utc).isoformat(),
                    "protocolVersion": initialized.protocolVersion,
                    "serverInfo": initialized.serverInfo.model_dump(),
                    "mcpSdkVersion": policy["mcpSdkVersion"],
                    "upstreamToolCount": policy["upstreamToolCount"],
                    "exposedToolCount": len(names),
                    "tools": names,
                    "toolCalls": calls,
                    "checksPassed": sum(checks.values()),
                    "checksTotal": len(checks),
                    "checks": checks,
                    "addon": addon,
                    "sceneBefore": before,
                    "sceneAfter": after,
                    "externalServices": services,
                    "viewportScreenshot": {"width": width, "height": height, "bytes": len(image)},
                }
    (RUNTIME / "smoke-result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-default-scene", action="store_true")
    args = parser.parse_args()
    result = asyncio.run(asyncio.wait_for(run_smoke(args.expect_default_scene), timeout=120))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
