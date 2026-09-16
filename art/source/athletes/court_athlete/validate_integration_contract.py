"""Read-only source and export-guard checks; no GLB, render or game writes.

Run with Blender --background --factory-startup --disable-autoexec
--python-exit-code 1 --python this_file.py.
"""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import struct
import sys
import tempfile
import zlib
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))

import build_athlete as build
import atlas_tools as atlas
import contact_locators as contacts
import export_athlete as exporter
import inspect_athlete as inspection
import rig_material_contract as driver
import mesh_tools as mt
import audit_publication as publication
import normalize_skin_normal as encoding


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_guard_tests():
    results = []

    def check(label, function, reject=False):
        try:
            function()
        except ValueError:
            if not reject:
                raise
        else:
            if reject:
                raise AssertionError("Expected rejection: " + label)
        results.append(label)

    nodes = []
    for side in ("L", "R"):
        for chain in (("Thigh", "Shin", "Foot", "Toe"),
                      ("UpperArm", "Forearm", "Hand", "Palm")):
            start = len(nodes)
            for i, name in enumerate(chain):
                nodes.append({"name": name + "_" + side,
                              "children": [start + i + 1] if i < 3 else []})
    skeleton = {"nodes": nodes, "skins": [{"joints": list(range(len(nodes)))}]}
    check("direct chains and Palm joints", lambda: exporter.validate_helper_joints(skeleton))
    missing = copy.deepcopy(skeleton)
    missing["skins"][0]["joints"].remove(7)
    check("missing Palm joint rejected", lambda: exporter.validate_helper_joints(missing), True)
    reparent = copy.deepcopy(skeleton)
    reparent["nodes"][6]["children"] = []
    reparent["nodes"][5]["children"].append(7)
    check("indirect Palm chain rejected", lambda: exporter.validate_helper_joints(reparent), True)

    color = {"accessors": [{"type": "VEC4", "count": 4, "componentType": 5126, "bufferView": 0}],
             "bufferViews": [{"buffer": 0, "byteLength": 64}]}
    values = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    binary = struct.pack("<16f", *values)
    check("float RGBA", lambda: exporter.validate_color0(color, binary, 0, 4))
    check("fake white COLOR_0 rejected", lambda: exporter.validate_color0(
        color, struct.pack("<16f", *([1.0] * 16)), 0, 4), True)
    rgb = copy.deepcopy(color)
    rgb["accessors"][0]["type"] = "VEC3"
    check("missing alpha rejected", lambda: exporter.validate_color0(rgb, binary, 0, 4), True)
    check("short buffer rejected", lambda: exporter.validate_color0(color, binary[:32], 0, 4), True)
    check("non-finite weights rejected", lambda: exporter.validate_color0(
        color, struct.pack("<16f", float("nan"), *([0.0] * 15)), 0, 4), True)
    for component, scalar, maximum in ((5121, "B", 255), (5123, "H", 65535)):
        integer = copy.deepcopy(color)
        integer["accessors"][0].update(componentType=component, normalized=True)
        encoded = struct.pack("<16" + scalar, *[v * maximum for v in values])
        integer["bufferViews"][0]["byteLength"] = len(encoded)
        check(f"normalized {component} RGBA",
              lambda: exporter.validate_color0(integer, encoded, 0, 4))
    integer["accessors"][0]["normalized"] = False
    check("non-normalized integer weights rejected",
          lambda: exporter.validate_color0(integer, encoded, 0, 4), True)
    interleaved = copy.deepcopy(color)
    interleaved["bufferViews"][0].update(byteOffset=8, byteLength=84, byteStride=20)
    interleaved["accessors"][0]["byteOffset"] = 4
    packed = b"prefix00pad0" + b"".join(
        binary[i:i + 16] + b"pad0" for i in range(0, 64, 16))
    check("accessor offset and interleaved stride",
          lambda: exporter.validate_color0(interleaved, packed, 0, 4))
    too_short = copy.deepcopy(color)
    too_short["bufferViews"][0]["byteLength"] = 32
    check("out-of-view accessor rejected",
          lambda: exporter.validate_color0(too_short, binary, 0, 4), True)
    frame = {
        "accessors": [
            {"type": "VEC3", "count": 1, "componentType": 5126, "bufferView": 0},
            {"type": "VEC4", "count": 1, "componentType": 5126, "bufferView": 1}],
        "bufferViews": [{"byteLength": 12}, {"byteOffset": 12, "byteLength": 16}]}
    attributes = {"NORMAL": 0, "TANGENT": 1}
    check("unit orthogonal tangent frame", lambda: exporter.validate_tangent_frames(
        frame, struct.pack("<7f", 0, 1, 0, 1, 0, 0, 1), attributes, 1))
    check("zero tangent rejected", lambda: exporter.validate_tangent_frames(
        frame, struct.pack("<7f", 0, 1, 0, 0, 0, 0, 1), attributes, 1), True)
    check("parallel tangent rejected", lambda: exporter.validate_tangent_frames(
        frame, struct.pack("<7f", 0, 1, 0, 0, 1, 0, 1), attributes, 1), True)
    check("non-unit normal rejected", lambda: exporter.validate_tangent_frames(
        frame, struct.pack("<7f", 0, 2, 0, 1, 0, 0, 1), attributes, 1), True)
    def png_header(width, height, depth, color_type):
        return (b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR"
                + struct.pack(">IIBBBBB", width, height, depth, color_type, 0, 0, 0) + b"\0" * 4)
    check("RGBA8 2048 normal header", lambda: exporter.validate_skin_normal_header(
        png_header(2048, 2048, 8, 6)))
    check("RGB8 normal rejected", lambda: exporter.validate_skin_normal_header(
        png_header(2048, 2048, 8, 2)), True)
    check("normal resolution drift rejected", lambda: exporter.validate_skin_normal_header(
        png_header(1024, 1024, 8, 6)), True)
    check("normal bit depth drift rejected", lambda: exporter.validate_skin_normal_header(
        png_header(2048, 2048, 16, 6)), True)
    return results


def embedded_map_tests(cache):
    raw = (exporter.DESTINATION / "court_athlete.glb").read_bytes()
    length = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + length])
    binary_size, kind = struct.unpack_from("<I4s", raw, 20 + length)
    assert kind == b"BIN\0"
    binary = raw[28 + length:28 + length + binary_size]
    records = exporter.embedded_map_records(doc, binary)
    exporter.validate_embedded_masters(records, HERE / "maps")
    cases = ["nine embedded maps match the canonical masters"]

    def reject(label, changed, data=binary):
        try:
            exporter.embedded_map_records(changed, data)
        except ValueError:
            cases.append(label)
        else:
            raise AssertionError("Expected rejection: " + label)

    external = copy.deepcopy(doc)
    external["images"][0]["uri"] = "textures/gear_normal.png"
    reject("external PNG URI rejected", external)
    external_buffer = copy.deepcopy(doc)
    external_buffer["buffers"][0]["uri"] = "external.bin"
    reject("external image buffer URI rejected", external_buffer)
    missing = copy.deepcopy(doc)
    missing["images"].pop()
    reject("missing embedded PNG rejected", missing)
    duplicate = copy.deepcopy(doc)
    duplicate["images"][0]["name"] = duplicate["images"][1]["name"]
    reject("duplicate image name rejected", duplicate)
    invalid_view = copy.deepcopy(doc)
    invalid_view["images"][0]["bufferView"] = -1
    reject("negative image view rejected", invalid_view)
    out_of_bounds = copy.deepcopy(doc)
    out_of_bounds["bufferViews"][doc["images"][0]["bufferView"]]["byteLength"] = len(binary) + 1
    reject("out-of-buffer image rejected", out_of_bounds)
    rgb = bytearray(binary)
    image_start = doc["bufferViews"][doc["images"][0]["bufferView"]].get("byteOffset", 0)
    rgb[image_start + 25] = 2
    reject("RGB8 embedded image rejected", doc, rgb)
    changed_records = copy.deepcopy(records)
    changed_records[0]["sha256"] = "0" * 64
    try:
        exporter.validate_embedded_masters(changed_records, HERE / "maps")
    except ValueError:
        cases.append("changed embedded pixels/payload rejected against master")
    else:
        raise AssertionError("Changed master payload was accepted")

    with tempfile.TemporaryDirectory(prefix="publication-check-", dir=cache) as directory:
        destination = Path(directory)
        staged = destination / ".court_athlete.pending.glb"
        staged.write_bytes(raw)
        exporter.publish_runtime_asset(staged, destination)
        assert {p.name for p in destination.iterdir()} == {
            "court_athlete.glb", "rig_manifest.json", "provenance.json"}
        assert (destination / "court_athlete.glb").read_bytes() == raw
        for name in ("rig_manifest.json", "provenance.json"):
            assert (destination / name).read_bytes() == (HERE / name).read_bytes()
        cases.append("runtime publisher emits only unchanged GLB and two metadata files, no textures")
    assert (exporter.DESTINATION / "court_athlete.glb").read_bytes() == raw
    return cases


def publication_audit_tests(cache):
    personal = "C:" + "\\" + "Users" + "\\" + "Example" + "\\file"
    assert publication.scan_strings([("fixture", personal)])[0]["category"] == "personal_home_path"
    private_image = "athlete-" + "quality-user-20000101.png"
    assert publication.scan_strings([("fixture", private_image)])[0]["category"] == "private_quality_image"
    ao = HERE / "maps" / "gear_ao.png"
    reviewed = publication.png_chunks(ao)["metadata"]
    assert len(reviewed) == 1 and reviewed[0]["reviewed_harmless_DPI_only"]
    with tempfile.TemporaryDirectory(prefix="metadata-check-", dir=cache) as directory:
        raw = ao.read_bytes()
        chunk = b"tEXtComment\0unreviewed metadata"
        encoded = struct.pack(">I", len(chunk) - 4) + chunk + struct.pack(">I", zlib.crc32(chunk))
        sample = Path(directory) / "metadata_ao.png"
        sample.write_bytes(raw[:-12] + encoded + raw[-12:])
        assert not all(item["reviewed_harmless_DPI_only"]
                       for item in publication.png_chunks(sample)["metadata"])
    return 4


def isolated_source_tests(cache, source):
    before = encoding.source_snapshot()
    with tempfile.TemporaryDirectory(prefix="isolated-source-", dir=cache) as directory:
        isolated = Path(directory)
        folder = isolated / "art" / "source" / "athletes" / "court_athlete"
        (folder / "maps").mkdir(parents=True)
        shutil.copyfile(source, folder / source.name)
        for path in (HERE / "maps").glob("*.png"):
            shutil.copyfile(path, folder / "maps" / path.name)
        try:
            bpy.ops.wm.open_mainfile(filepath=str(folder / source.name), use_scripts=False)
            weak = [Path(bpy.path.abspath(block.library_weak_reference.filepath)).resolve()
                    for block in bpy.data.user_map() if getattr(block, "library_weak_reference", None)]
            assert weak and all(path.is_relative_to(isolated) and not path.exists() for path in weak)
            assert not bpy.data.libraries and not (isolated / ".dream-loop").exists()
            assert all(atlas.runtime_map_links(folder / "maps").values())
            assert encoding.source_snapshot() == before
            report = driver.validate_driver_contract(
                bpy.data.objects["CourtAthlete"],
                *[bpy.data.objects[name] for name in driver.MESH_NAMES], folder / "maps" / "kit_mask.png")
            assert report["passed"] == report["total"] == 27
        finally:
            bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    assert encoding.source_snapshot() == before
    return 3


def main():
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    source = HERE / "court_athlete.blend"
    assert sha256(source) == manifest["source_sha256"]
    for texture in manifest["textures"]:
        assert sha256(HERE / "maps" / texture["file"]) == texture["sha256"], texture["file"]
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    rig = bpy.data.objects["CourtAthlete"]
    skin, kit, gear = [bpy.data.objects[name] for name in driver.MESH_NAMES]
    report = driver.validate_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
    assert report["passed"] == report["total"] == 27
    structural = inspection.validate()
    assert structural["passed"] == structural["total"] == 19
    actual = build.skeleton_report(rig)["contact_contract"]
    actual["source_sha256"] = manifest["source_sha256"]
    stored = json.loads((HERE / "rig_manifest.json").read_text(encoding="utf-8"))["contact_contract"]
    assert actual == stored, "Generator hook does not reproduce the saved contact manifest"
    contact = contacts.validate_contract(actual, rig, skin)
    assert contact["passed"] == contact["total"] == 29

    rig.data.bones["Palm_L"].use_deform = True
    invalid = driver.validate_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
    assert not invalid["checks"]["Palm_L_non_deforming"]
    assert invalid["passed"] < invalid["total"]
    rig.data.bones["Palm_L"].use_deform = False
    layer = kit.data.color_attributes["COLOR0"]
    colors = np.empty(len(layer.data) * 4, dtype=np.float32)
    layer.data.foreach_get("color", colors)
    layer.data.foreach_set("color", np.ones_like(colors))
    invalid = driver.validate_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
    assert not invalid["checks"]["COLOR0_linear_normalized"]
    assert invalid["passed"] < invalid["total"]
    layer.data.foreach_set("color", colors)
    restored = driver.validate_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
    assert restored["passed"] == restored["total"]

    image = bpy.data.materials["AthleteSkin"].node_tree.nodes["Map_albedo"].image
    original_path = image.filepath
    image.filepath = "//maps/"
    assert not atlas.runtime_map_links(HERE / "maps")["skin_runtime_maps_resolve"]
    image.filepath = original_path
    assert all(atlas.runtime_map_links(HERE / "maps").values())

    mesh = bpy.data.meshes.new("TEST_ONLY_WeightReplacement")
    mesh.from_pydata([(0, 0, 1.6)], [], [])
    obj = bpy.data.objects.new("TEST_ONLY_WeightReplacement", mesh)
    bpy.context.scene.collection.objects.link(obj)
    try:
        obj.vertex_groups.new(name="StaleInheritedWeight").add([0], 1, "REPLACE")
        mt.transfer_weights(obj, mt.weight_reference(bpy.data.objects["AnatomicalWeightReference"]),
                            rig, fixed="Head")
        weights = [(obj.vertex_groups[g.group].name, g.weight) for g in mesh.vertices[0].groups]
        assert weights == [("Head", 1.0)], weights
    finally:
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    bary = mt.barycentric_double(
        (0.40004, 0.02006, 1.6), (0.4, 0.02, 1.6),
        (0.4002, 0.02, 1.6), (0.4, 0.0202, 1.6))
    assert max(abs(a - b) for a, b in zip(bary, (0.5, 0.2, 0.3))) < 1e-6

    cache = HERE.parents[3] / ".dream-loop" / "athlete-upgrade" / "normal-encoding"
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="encoding-check-", dir=cache) as directory:
        sample = Path(directory) / "normal.png"
        rgb = np.arange(16 * 16 * 3, dtype=np.uint8).reshape((16, 16, 3))
        atlas.write_png_bytes(sample, rgb)
        conversion = atlas.normalize_opaque_normal_png(sample)
        rgba, _ = atlas.data_png_pixels(sample)
        assert np.array_equal(rgba[..., :3], rgb) and np.all(rgba[..., 3] == 255)
        first_hash = sha256(sample)
        repeated = atlas.normalize_opaque_normal_png(sample)
        assert not repeated["rewritten"] and sha256(sample) == first_hash
        rgba[..., 3] = np.arange(256, dtype=np.uint8).reshape((16, 16))
        atlas.write_png_bytes(sample, rgba)
        atlas.normalize_opaque_normal_png(sample)
        opaque, _ = atlas.data_png_pixels(sample)
        assert np.array_equal(opaque[..., :3], rgb) and np.all(opaque[..., 3] == 255)

    guards = export_guard_tests()
    assert len(guards) == 21
    embedded = embedded_map_tests(cache)
    assert len(embedded) == 10
    publication_guards = publication_audit_tests(cache)
    isolated_checks = isolated_source_tests(cache, source)
    assert sha256(source) == manifest["source_sha256"], "Validation wrote the source"
    print(json.dumps({
        "source_sha256": manifest["source_sha256"],
        "driver_contract": [report["passed"], report["total"]],
        "structure": [structural["passed"], structural["total"]],
        "contacts": [contact["passed"], contact["total"]],
        "map_hashes_matching": len(manifest["textures"]),
        "source_negative_checks": 2, "export_guard_checks": len(guards),
        "tailoring_pipeline_regression_checks": 3,
        "normal_encoding_regression_checks": 3,
        "embedded_map_and_publication_checks": len(embedded),
        "embedded_map_and_publication_cases": embedded,
        "publication_privacy_metadata_guards": publication_guards,
        "isolated_source_without_upstream_checks": isolated_checks,
        "export_guard_cases": guards, "source_or_game_files_written": False,
        "temporary_fixture_files_written": True,
        "actual_GLB_export_or_Godot_test": False,
    }, indent=2), flush=True)


if __name__ == "__main__":
    main()
