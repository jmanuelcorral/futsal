"""Read-only publication audit of this asset; writes JSON evidence, never assets.

Run with Blender --background --factory-startup --disable-autoexec
--python-exit-code 1 --python this_file.py. No downloads, renders or exports.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))

import atlas_tools as atlas
import export_athlete as exporter
import normalize_skin_normal as encoding

EXPECTED_SOURCE = "34b519c921b5101974e40cdd70ff6d576e6544ff032f28feb8f6d054ccc9b53f"
EXPECTED_GLB = "72bb973ced0b5cb44d6871c23c9e1a8c3fb35db85adc7bc66673f74a61becc66"
# Pillow inspection confirmed that this AO metadata contains only X/YResolution=72.
AO_DPI_EXIF_SHA256 = "bac3a1a58a16fd3148097ebe3f45648d02a89abcae7be4c8d625e0a926782b62"
SENSITIVE_PATTERNS = {
    "personal_home_path": re.compile(r"(?i)([a-z]:[\\/]+(?:users|documents and settings)[\\/]+|/(?:home|Users)/)"),
    "private_quality_image": re.compile(r"(?i)athlete-quality-user[0-9_-]*\.png|\.dream-loop[\\/]+references[\\/]+[^\"'\r\n]+\.png"),
    "private_key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "credential_token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16})\b"),
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strings(value, location):
    if isinstance(value, str):
        yield location, value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from strings(item, f"{location}.{key}")
    elif isinstance(value, (list, tuple)):
        for index, item in enumerate(value):
            yield from strings(item, f"{location}[{index}]")


def scan_strings(items):
    return [{"location": location, "category": category}
            for location, value in items
            for category, pattern in SENSITIVE_PATTERNS.items() if pattern.search(value)]


def png_chunks(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path.name}")
    offset, chunks, metadata = 8, [], []
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8].decode("ascii")
        if offset + size + 12 > len(data):
            raise ValueError(f"Truncated PNG chunk: {path.name}")
        chunks.append(kind)
        if kind in {"tEXt", "zTXt", "iTXt", "eXIf"}:
            digest = hashlib.sha256(data[offset + 8:offset + 8 + size]).hexdigest()
            metadata.append({
                "kind": kind, "sha256": digest,
                "reviewed_harmless_DPI_only": kind == "eXIf" and path.name.endswith("_ao.png")
                and digest == AO_DPI_EXIF_SHA256,
            })
        offset += size + 12
    if not chunks or chunks[-1] != "IEND":
        raise ValueError(f"Missing PNG end: {path.name}")
    return {"chunks": chunks, "metadata": metadata}


def main():
    source = HERE / "court_athlete.blend"
    glb = exporter.DESTINATION / "court_athlete.glb"
    if sha256(source) != EXPECTED_SOURCE or sha256(glb) != EXPECTED_GLB:
        raise ValueError("Publication cleanup must preserve the reviewed source and GLB")
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    masters = {item["file"]: item["sha256"] for item in manifest["textures"]}
    for name, digest in masters.items():
        if sha256(HERE / "maps" / name) != digest:
            raise ValueError(f"Authored map changed: {name}")
    before = encoding.glb_snapshot(glb)
    exported = exporter.inspect_glb(glb)

    text_values = []
    checked_text_files = []
    for directory in (HERE, exporter.DESTINATION):
        for path in sorted(directory.rglob("*")):
            if path.is_file() and path.suffix in (".py", ".json", ".import"):
                label = str(path.relative_to(REPO))
                text = path.read_text(encoding="utf-8")
                text_values.append((label, text))
                if path.suffix == ".json":
                    text_values.extend(strings(json.loads(text), label))
                checked_text_files.append(label)
    raw = glb.read_bytes()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    text_values.extend(strings(json.loads(raw[20:20 + json_length]), "GLB"))

    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    file_references = list(bpy.utils.blend_paths(absolute=False, packed=True))
    weak_references = [
        {"datablock": block.name, "path": block.library_weak_reference.filepath}
        for block in bpy.data.user_map() if getattr(block, "library_weak_reference", None)]
    expected_base = (REPO / ".dream-loop" / "downloads" / "human-base-meshes-v1.4.1"
                     / Path(provenance["blend_member"])).resolve()
    weak_paths = {Path(bpy.path.abspath(item["path"])).resolve() for item in weak_references}
    file_reference_checks = [
        value.startswith("//") and (
            (Path(bpy.path.abspath(value)).resolve().parent == (HERE / "maps").resolve()
             and Path(bpy.path.abspath(value)).name in masters)
            or Path(bpy.path.abspath(value)).resolve() in weak_paths)
        for value in file_references]
    for block in bpy.data.user_map():
        text_values.append((f"blend.{block.bl_rna.identifier}.name", block.name))
        for key in block.keys():
            value = block[key]
            if hasattr(value, "to_dict"):
                value = value.to_dict()
            text_values.extend(strings(value, f"blend.{block.name}.{key}"))
    text_values.extend((f"blend.reference[{index}]", value)
                       for index, value in enumerate(file_references))
    driver_count = sum(len(block.animation_data.drivers)
                       for block in bpy.data.user_map()
                       if getattr(block, "animation_data", None))
    image_checks = []
    for image in bpy.data.images:
        path = Path(bpy.path.abspath(image.filepath)).resolve()
        valid = (image.source == "FILE" and image.filepath.startswith("//")
                 and path.parent == (HERE / "maps").resolve() and path.name in masters)
        empty_stub = (image.type == "RENDER_RESULT" and image.source == "VIEWER"
                      and tuple(image.size) == (0, 0) and len(image.pixels) == 0
                      and not image.packed_file and path == (HERE / "maps").resolve())
        packed_matches = not image.packed_file or (
            valid and hashlib.sha256(image.packed_file.data).hexdigest() == masters[path.name])
        image_checks.append({"name": image.name, "portable_master": valid,
                             "empty_render_result_stub": empty_stub,
                             "packed": bool(image.packed_file), "packed_matches_master": packed_matches})
    expected_objects = {"CourtAthlete", "AthleteSkinMesh", "AthleteKitMesh", "AthleteGearMesh",
                        "CC0_DanUlrich_RealisticMale_High", "AnatomicalWeightReference"}
    base_mesh = bpy.data.objects["CC0_DanUlrich_RealisticMale_High"].data
    base_digest = hashlib.sha256()
    for vertex in base_mesh.vertices:
        base_digest.update(struct.pack("<3f", *vertex.co))
    for face in base_mesh.polygons:
        base_digest.update(struct.pack("<I", len(face.vertices)))
        base_digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
    source_semantics = encoding.digest(encoding.source_snapshot())
    historical = json.loads((HERE / "normal_encoding_manifest.json").read_text(encoding="utf-8"))
    png_metadata = {
        str(path.relative_to(REPO)): png_chunks(path)
        for directory in (HERE / "maps", exporter.DESTINATION)
        for path in sorted(directory.glob("*.png"))}
    pixels = {}
    for name in exporter.PBR_MAP_NAMES:
        _, original = atlas.data_png_pixels(HERE / "maps" / name)
        _, imported = atlas.data_png_pixels(exporter.DESTINATION / ("court_athlete_" + name))
        pixels[name] = {
            "master_RGB_sha256": original["rgb_top_down_sha256"],
            "extracted_RGB_sha256": imported["rgb_top_down_sha256"],
            "RGBA8_opaque": original["color_type"] == imported["color_type"] == 6
            and original["alpha_min"] == original["alpha_max"] == 255
            and imported["alpha_min"] == imported["alpha_max"] == 255,
        }
    findings = scan_strings(text_values)
    checks = {
        "source_GLB_and_master_hashes_preserved": sha256(source) == EXPECTED_SOURCE and sha256(glb) == EXPECTED_GLB,
        "source_semantics_unchanged": source_semantics == historical["source_semantics_sha256"],
        "all_23_GLB_accessors_and_semantics_unchanged": before == historical["runtime_after"],
        "only_selected_base_and_own_authoring_objects": {obj.name for obj in bpy.data.objects} == expected_objects,
        "selected_base_geometry_matches_provenance": base_digest.hexdigest() == provenance["body_mesh_fingerprint"]["sha256"],
        "base_is_Body_Male_Realistic_CC0_Dan_Ulrich": provenance["chosen_collection"] == "Body Male - Realistic"
        and provenance["author"] == "Dan Ulrich" and provenance["asset_license"] == "CC0",
        "no_external_libraries_scripts_or_actions": not bpy.data.libraries and not bpy.data.texts and not bpy.data.actions,
        "no_drivers_movie_clips_or_sounds": driver_count == 0 and not bpy.data.movieclips and not bpy.data.sounds,
        "portable_maps_and_reviewed_weak_base_reference": bool(file_references)
        and all(file_reference_checks) and weak_paths == {expected_base},
        "all_source_images_known_masters": bool(image_checks)
        and all((item["portable_master"] or item["empty_render_result_stub"])
                and item["packed_matches_master"] for item in image_checks),
        "PNG_metadata_absent_or_reviewed_harmless_DPI": all(
            item["reviewed_harmless_DPI_only"]
            for record in png_metadata.values() for item in record["metadata"]),
        "no_sensitive_text_findings": not findings,
        "nine_embedded_PBR_maps_match_masters": len(exported["embedded_pbr_maps"]) == 9,
        "nine_Godot_extracted_maps_preserve_RGB_and_opaque_RGBA8": all(
            item["RGBA8_opaque"] and item["master_RGB_sha256"] == item["extracted_RGB_sha256"]
            for item in pixels.values()),
    }
    report = {
        "scope": "Read-only asset source/provenance/privacy audit; NOT art/FPS/release approval",
        "source_sha256": EXPECTED_SOURCE, "glb_sha256": EXPECTED_GLB,
        "checks": checks, "passed": sum(checks.values()), "total": len(checks),
        "sensitive_findings_redacted": findings, "checked_text_files": checked_text_files,
        "source_objects": sorted(obj.name for obj in bpy.data.objects),
        "source_images": image_checks, "source_file_reference_count": len(file_references),
        "weak_base_reference": {
            "count": len(weak_references), "external_libraries": len(bpy.data.libraries),
            "datablocks": [item["datablock"] for item in weak_references],
            "meaning": "Append provenance for the selected CC0 data, not a linked library. The full bundle is excluded.",
        },
        "source_base_mesh_fingerprint": base_digest.hexdigest(),
        "source_semantics_sha256": source_semantics, "glb_snapshot": before,
        "png_chunks": png_metadata, "pixels": pixels,
        "assets_written": False, "renders_or_exports": False, "paid_API_cost": 0,
        "independent_publication_review": "Pending Vasquez",
    }
    output = REPO / "build" / "publication" / "graphics05-assets" / "source-audit.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"report": str(output.relative_to(REPO)),
                      "checks": checks, "passed": report["passed"], "total": report["total"]}, indent=2))
    if not all(checks.values()):
        raise ValueError("Publication source audit has failed checks; inspect the redacted report")


if __name__ == "__main__":
    main()
