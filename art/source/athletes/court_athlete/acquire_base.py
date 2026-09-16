"""Fetch ONLY the explicitly authorized Blender Studio CC0 bundle.

No downloaded code is executed. Inspection precedes selective extraction.
Python standard library only; run from any cwd. See --help.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


SOURCE = Path(__file__).resolve().parent
REPO = SOURCE.parents[3]
CACHE = REPO / ".dream-loop" / "downloads"
NAME = "human-base-meshes-bundle-v1.4.1.zip"
URL = "https://download.blender.org/demo/asset-bundles/human-base-meshes/" + NAME
EXPECTED_BYTES = 50643039
PINNED_SHA256 = "811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inspect(archive: Path) -> dict:
    if archive.stat().st_size != EXPECTED_BYTES:
        raise ValueError("Unexpected bundle size; stop for review")
    digest = sha256(archive)
    if PINNED_SHA256 and digest != PINNED_SHA256:
        raise ValueError("Official bundle differs from the reviewed SHA256")
    inventory = []
    texts = {}
    seen = set()
    total = 0
    with zipfile.ZipFile(archive) as bundle:
        for info in bundle.infolist():
            path = PurePosixPath(info.filename)
            if (path.is_absolute() or "\\" in info.filename or ":" in info.filename
                    or "\x00" in info.filename or ".." in path.parts):
                raise ValueError(f"Unsafe archive path: {info.filename!r}")
            key = info.filename.rstrip("/").casefold()
            if key in seen:
                raise ValueError(f"Duplicate Windows path: {info.filename}")
            seen.add(key)
            for part in path.parts:
                if (part.endswith((" ", ".")) or re.match(
                        r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)",
                        part, re.IGNORECASE)):
                    raise ValueError(f"Unsafe Windows filename: {part}")
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ValueError(f"Symlink refused: {info.filename}")
            if info.flag_bits & 1:
                raise ValueError("Encrypted member refused")
            total += info.file_size
            if total > 1_000_000_000 or info.file_size > 500_000_000:
                raise ValueError("Extraction size budget exceeded")
            if info.file_size / max(1, info.compress_size) > 1000:
                raise ValueError("Suspicious compression ratio")
            inventory.append({
                "name": info.filename, "bytes": info.file_size,
                "compressed_bytes": info.compress_size, "crc32": f"{info.CRC:08x}",
            })
            if (not info.is_dir() and info.file_size < 200_000
                    and (path.suffix.lower() in (".txt", ".md", ".license")
                         or "license" in path.name.lower())):
                texts[info.filename] = bundle.read(info).decode("utf-8", errors="replace")
        bad = bundle.testzip()
        if bad:
            raise ValueError(f"CRC failure in {bad}")
    return {
        "package": "Human Base Meshes", "version": "1.4.1",
        "url": URL, "official_listing": "https://www.blender.org/download/demo-files/#assets",
        "archive_bytes": archive.stat().st_size, "archive_sha256": digest,
        "authorization": "User 2026-09-15 10:22: download/adapt/incorporate this CC0 bundle only.",
        "safety": {"paths": "passed", "windows_collisions": "passed", "symlinks": "none",
                   "crc": "passed", "autoexec": "never enabled", "scripts_executed": []},
        "uncompressed_bytes": total, "members": inventory, "license_texts": texts,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--extract-reviewed", nargs="+", metavar="MEMBER",
                        help="Extract only explicitly reviewed exact member names")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / NAME
    if args.download and not archive.exists():
        temporary = archive.with_suffix(".download")
        request = urllib.request.Request(URL, headers={"User-Agent": "Futsal-art-asset-acquisition/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                if urllib.parse.urlparse(response.url).hostname != "download.blender.org":
                    raise ValueError("Unexpected download host")
                with temporary.open("wb") as output:
                    received = 0
                    while chunk := response.read(1024 * 1024):
                        received += len(chunk)
                        if received > EXPECTED_BYTES:
                            raise ValueError("Download exceeds authorized package size")
                        output.write(chunk)
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    report = inspect(archive)
    (CACHE / "human-base-meshes-inspection.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.extract_reviewed:
        destination = CACHE / "human-base-meshes-v1.4.1"
        with zipfile.ZipFile(archive) as bundle:
            for name in args.extract_reviewed:
                info = bundle.getinfo(name)
                if info.is_dir() or Path(name).suffix.lower() not in (".blend", ".txt", ".md", ".license"):
                    raise ValueError(f"Not a reviewed data/license type: {name}")
                output = destination.joinpath(*PurePosixPath(name).parts)
                output.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(info) as src, output.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                print(f"EXTRACTED {output.relative_to(REPO)} SHA256={sha256(output)}")


if __name__ == "__main__":
    main()
