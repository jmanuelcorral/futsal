"""R3 encoding-only normalization: RGB8 normal -> opaque RGBA8.

--apply changes only skin_normal.png, its Blender image cache and technical
manifests. --verify-export compares the emitted GLB against the pre-change
geometry/rig/material snapshot. Neither mode models, renders or starts Godot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import atlas_tools as atlas
import build_athlete as build
import contact_locators as contacts
import inspect_athlete as inspection
import rig_material_contract as driver

NORMAL = HERE / "maps" / "skin_normal.png"
SOURCE = HERE / "court_athlete.blend"
GLB = REPO / "game" / "assets" / "athletes" / "court_athlete" / "court_athlete.glb"
REPORT = HERE / "normal_encoding_manifest.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def value_data(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bpy.types.ID):
        return {"datablock": value.name, "type": value.bl_rna.identifier}
    return list(value)


def source_snapshot():
    meshes = {}
    for name in driver.MESH_NAMES:
        obj = bpy.data.objects[name]
        colors = {}
        for attribute in obj.data.color_attributes:
            values = np.empty(len(attribute.data) * 4, dtype=np.float32)
            attribute.data.foreach_get("color", values)
            colors[attribute.name] = {
                "domain": attribute.domain, "type": attribute.data_type,
                "sha256": hashlib.sha256(values.tobytes()).hexdigest()}
        meshes[name] = {
            "geometry_weights_uv": driver.geometry_fingerprint(obj),
            "colors": colors, "transform": [list(row) for row in obj.matrix_local],
            "materials": [material.name for material in obj.data.materials],
        }
    rig = bpy.data.objects["CourtAthlete"]
    bones = [{
        "name": bone.name, "parent": bone.parent.name if bone.parent else None,
        "deform": bone.use_deform, "head": list(bone.head_local), "tail": list(bone.tail_local),
        "rest": [list(row) for row in bone.matrix_local],
        "pose_basis": [list(row) for row in rig.pose.bones[bone.name].matrix_basis],
    } for bone in rig.data.bones]
    materials = {}
    for name in ("AthleteSkin", "AthleteKit", "AthleteGear"):
        material = bpy.data.materials[name]
        nodes = {}
        for node in material.node_tree.nodes:
            item = {
                "type": node.bl_idname,
                "inputs": {socket.identifier: value_data(socket.default_value)
                           for socket in node.inputs if hasattr(socket, "default_value")},
            }
            for prop in ("operation", "mode", "space", "uv_map", "interpolation", "extension", "projection"):
                if hasattr(node, prop):
                    item[prop] = value_data(getattr(node, prop))
            if node.type == "TEX_IMAGE" and node.image:
                item["image"] = {
                    "name": node.image.name, "filepath": node.image.filepath,
                    "colorspace": node.image.colorspace_settings.name,
                    "alpha_mode": node.image.alpha_mode,
                }
            nodes[node.name] = item
        materials[name] = {
            "nodes": nodes, "diffuse_color": list(material.diffuse_color),
            "backface_culling": material.use_backface_culling,
            "links": sorted((link.from_node.name, link.from_socket.identifier,
                             link.to_node.name, link.to_socket.identifier)
                            for link in material.node_tree.links),
        }
    return {
        "meshes": meshes, "bones": bones, "materials": materials,
        "rig_transform": [list(row) for row in rig.matrix_local],
        "source_revision": bpy.context.scene.get("asset_revision"),
    }


def glb_snapshot(path):
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        raise ValueError("Expected GLB")
    length, kind = struct.unpack_from("<I4s", raw, 12)
    if kind != b"JSON":
        raise ValueError("GLB JSON chunk missing")
    doc = json.loads(raw[20:20 + length])
    offset = 20 + length
    size, kind = struct.unpack_from("<I4s", raw, offset)
    if kind != b"BIN\0":
        raise ValueError("GLB binary chunk missing")
    binary = raw[offset + 8:offset + 8 + size]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    widths = {5121: 1, 5123: 2, 5125: 4, 5126: 4}
    accessors = []
    for accessor in doc["accessors"]:
        if "sparse" in accessor:
            raise ValueError("Sparse data is not part of the athlete export")
        view = doc["bufferViews"][accessor["bufferView"]]
        element_size = components[accessor["type"]] * widths[accessor["componentType"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", element_size)
        data = b"".join(binary[start + i * stride:start + i * stride + element_size]
                        for i in range(accessor["count"]))
        accessors.append({
            **{key: accessor[key] for key in ("type", "componentType", "count", "normalized", "min", "max")
               if key in accessor}, "data_sha256": hashlib.sha256(data).hexdigest()})
    semantics = {key: item for key, item in doc.items()
                 if key not in ("buffers", "bufferViews", "images", "accessors")}
    images = {}
    for image in doc["images"]:
        view = doc["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = binary[start:start + view["byteLength"]]
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError("Expected embedded PNG")
        images[image["name"]] = {
            "width": struct.unpack_from(">I", data, 16)[0],
            "height": struct.unpack_from(">I", data, 20)[0],
            "depth": data[24], "color_type": data[25],
            "encoded_sha256": hashlib.sha256(data).hexdigest(),
        }
    return {"glb_sha256": hashlib.sha256(raw).hexdigest(),
            "geometry_rig_material_semantics": digest({"document": semantics, "accessors": accessors}),
            "accessor_count": len(accessors), "images": images}


def apply_normalization():
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    if manifest["revision"] != "athlete-upgrade-r3" or sha256(SOURCE) != manifest["source_sha256"]:
        raise ValueError("Encoding normalization requires the declared R3 source")
    if REPORT.exists():
        raise ValueError("Normalization is already recorded; verify it instead of rewriting history")
    previous_source = sha256(SOURCE)
    runtime_before = glb_snapshot(GLB)
    all_maps = {path.name: sha256(path) for path in (HERE / "maps").glob("*.png")}
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
    before = source_snapshot()
    conversion = atlas.normalize_opaque_normal_png(NORMAL)
    if conversion["before"]["width"] != 2048 or conversion["before"]["height"] != 2048:
        raise ValueError("The skin-normal master must remain 2048 square")
    material_image = bpy.data.materials["AthleteSkin"].node_tree.nodes["Map_normal"].image
    material_image.reload()
    if source_snapshot() != before:
        raise ValueError("Encoding normalization changed source geometry, rig, UVs, weights or material parameters")
    for name, expected in all_maps.items():
        if name != "skin_normal.png" and sha256(HERE / "maps" / name) != expected:
            raise ValueError(f"Unexpected modification of another map: {name}")
    structure = inspection.validate()
    if structure["passed"] != structure["total"]:
        raise ValueError(json.dumps(structure, indent=2))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE), compress=True)
    current_source = sha256(SOURCE)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
    if source_snapshot() != before:
        raise ValueError("Saved source did not preserve the geometry/rig/material snapshot")
    rig = bpy.data.objects["CourtAthlete"]
    bones = build.skeleton_report(rig)
    bones["contact_contract"]["source_sha256"] = current_source
    contacts.save_json(HERE / "rig_manifest.json", bones)
    report = {
        "classification": "R3 + technical opaque normal encoding; NOT R4",
        "source_before_sha256": previous_source, "source_after_sha256": current_source,
        "conversion": conversion, "all_three_meshes_all_54_bones_and_material_parameters_identical": True,
        "source_semantics_sha256": digest(before), "mesh_fingerprints": before["meshes"],
        "other_twelve_PNG_files_byte_identical": True,
        "source_structural_checks": structure, "runtime_before": runtime_before,
        "runtime_after": None, "live_GLB_unchanged_during_preparation": sha256(GLB) == runtime_before["glb_sha256"],
        "art_rounds_added": 0, "remaining_art_rounds": 0, "new_renders": 0,
        "godot_validation": "Coordinator must reimport the technically normalized hash; no warning suppression.",
    }
    contacts.save_json(REPORT, report)
    manifest["source_sha256"] = current_source
    manifest["source_bytes"] = SOURCE.stat().st_size
    manifest["status"] = "R3_technical_normal_encoding_ready_for_direct_export"
    manifest["contact_contract"]["source_sha256"] = current_source
    manifest["textures"] = [atlas.file_record(path) for path in sorted((HERE / "maps").glob("*.png"))]
    manifest["normal_encoding_normalization"] = {
        "report": REPORT.name, "normal_png": conversion["after"], "RGB_unchanged": True,
        "art_rounds_added": 0, "previous_source_sha256": previous_source,
        "classification": "R3 + technical normalization, not a new art pass",
    }
    manifest["r3"]["skin_and_gear_master_maps_unchanged"].pop("skin_normal.png")
    manifest["r3"]["skin_normal_RGB_preserved_RGBA8_alpha255"] = conversion
    manifest["source_inspection"]["encoding_only_successor_source_sha256"] = current_source
    manifest["source_inspection"]["encoding_note"] = (
        "Images keep their original rendered source hash. The successor changes PNG encoding only; RGB and all scene parameters are identical.")
    manifest["texture_contract"]["skin_normal_encoding"] = "RGBA8 opaque; RGB tangent normal preserved; alpha always 255."
    manifest["exported_to_game"] = False
    manifest["driver_contract_adaptation"]["game_exported"] = False
    contacts.save_json(HERE / "manifest.json", manifest)
    print("NORMAL_ENCODING_SOURCE_READY", json.dumps(report, indent=2), flush=True)


def verify_export():
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    after = glb_snapshot(GLB)
    before = report["runtime_before"]
    if after["geometry_rig_material_semantics"] != before["geometry_rig_material_semantics"]:
        raise ValueError("GLB geometry/UVs/weights/bones/rest/material parameters changed")
    for name, image in before["images"].items():
        current = after["images"][name]
        if name == "skin_normal.png":
            if (current["width"], current["height"], current["depth"], current["color_type"]) != (2048, 2048, 8, 6):
                raise ValueError("Exported skin normal is not RGBA8 2048")
        elif current != image:
            raise ValueError(f"Another embedded texture changed: {name}")
    report["runtime_after"] = after
    report["all_GLB_accessors_rig_rest_materials_and_other_eight_images_identical"] = True
    contacts.save_json(REPORT, report)
    print("NORMAL_ENCODING_GLB_VERIFIED", json.dumps(after, indent=2), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify-export", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.apply:
        apply_normalization()
    else:
        verify_export()


if __name__ == "__main__":
    main()
