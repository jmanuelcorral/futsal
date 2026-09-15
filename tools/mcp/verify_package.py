import hashlib
from importlib.metadata import distribution, version
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def verify_installed_package():
    pin = json.loads((Path(__file__).parent / "upstream.json").read_text())
    installed = distribution(pin["package"])
    if installed.version != pin["version"]:
        raise RuntimeError(f"Expected {pin['package']}=={pin['version']}; found {installed.version}.")
    checked = 0
    for source, expected in pin["gitBlobs"].items():
        if source == "addon.py":
            relative = Path("blender_mcp") / "bundled" / "addon.py"
        elif source == "LICENSE":
            relative = Path(f"blender_mcp-{pin['version']}.dist-info") / "licenses" / "LICENSE"
        else:
            relative = Path(*source.removeprefix("src/").split("/"))
        data = Path(installed.locate_file(relative)).read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        if actual != expected:
            raise RuntimeError(f"Installed package source mismatch: {source}")
        checked += 1
    return {
        "package": pin["package"],
        "version": installed.version,
        "upstreamCommit": pin["commit"],
        "verifiedGitBlobs": checked,
        "mcpSdkVersion": version("mcp"),
    }


if __name__ == "__main__":
    print(json.dumps(verify_installed_package(), indent=2))
