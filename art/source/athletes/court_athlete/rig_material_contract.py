"""Explicit source-only adaptation to Palm helpers and a data COLOR0 channel.

No integration/game files are read or written. No art render/bake/modeling pass.
Use --update-source on the existing source, or apply_driver_contract() in build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import contact_locators as contacts

MESH_NAMES = ("AthleteSkinMesh", "AthleteKitMesh", "AthleteGearMesh")


def geometry_fingerprint(obj):
    """Exclude the new color data; include shape/topology, UVs and joint weights."""
    digest = hashlib.sha256()
    for vertex in obj.data.vertices:
        digest.update(struct.pack("<3f", *vertex.co))
        weights = sorted((obj.vertex_groups[g.group].name, g.weight) for g in vertex.groups)
        digest.update(struct.pack("<I", len(weights)))
        for name, weight in weights:
            digest.update(name.encode("utf-8") + b"\0" + struct.pack("<f", weight))
    for polygon in obj.data.polygons:
        digest.update(struct.pack("<I?", len(polygon.vertices), polygon.use_smooth))
        digest.update(struct.pack("<" + "I" * len(polygon.vertices), *polygon.vertices))
    for layer in obj.data.uv_layers:
        digest.update(layer.name.encode("utf-8") + b"\0")
        for corner in layer.data:
            digest.update(struct.pack("<2f", *corner.uv))
    kinds = obj.data.attributes.get("surface_kind")
    if kinds:
        for item in kinds.data:
            digest.update(struct.pack("<i", item.value))
    return digest.hexdigest()


def add_palm_helpers(rig, contact_contract):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for side in ("L", "R"):
        name = "Palm_" + side
        existing = rig.data.edit_bones.get(name)
        if existing and (existing.use_deform or not existing.parent
                         or existing.parent.name != "Hand_" + side):
            raise ValueError(f"Refuse to repurpose an incompatible bone: {name}")
        bone = existing or rig.data.edit_bones.new(name)
        bone.parent = rig.data.edit_bones["Hand_" + side]
        bone.use_connect = False
        bone.use_deform = False
        # This helper's actual basis matches the recorded contact frame:
        # +Y = palmar up/outward normal; +Z = forward towards fingers.
        transform = Matrix(contact_contract["palms"][name]["transform_blender_rows"])
        bone.head = transform.translation
        bone.tail = transform.translation + transform.to_3x3().col[1] * 0.020
        bone.align_roll(transform.to_3x3().col[2])
        bone.length = 0.020
    bpy.ops.object.mode_set(mode="OBJECT")
    for side in ("L", "R"):
        bone = rig.data.bones["Palm_" + side]
        bone["semantic"] = "PALM CENTER, non-deforming contact helper; +Y outward, +Z finger-forward."
    bpy.context.view_layer.update()


def sample_mask_corners(kit, png):
    image = bpy.data.images.load(str(png), check_existing=False)
    image.colorspace_settings.name = "Non-Color"
    image.alpha_mode = "CHANNEL_PACKED"
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape((height, width, 4))
    uv = np.array([corner.uv[:] for corner in kit.data.uv_layers.active.data], dtype=np.float64)
    u = np.clip(uv[:, 0] * width - 0.5, 0, width - 1)
    v = np.clip(uv[:, 1] * height - 0.5, 0, height - 1)
    x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
    x1, y1 = np.minimum(x0 + 1, width - 1), np.minimum(y0 + 1, height - 1)
    fx, fy = (u - x0)[:, None], (v - y0)[:, None]
    values = ((pixels[y0, x0] * (1 - fx) + pixels[y0, x1] * fx) * (1 - fy)
              + (pixels[y1, x0] * (1 - fx) + pixels[y1, x1] * fx) * fy)
    totals = values.sum(1, keepdims=True)
    if np.any(totals <= 0):
        raise ValueError("Invalid zero-weight texel in the authored kit mask")
    values = (values / totals).astype(np.float32)
    bpy.data.images.remove(image)
    return values


def add_color0(kit, png):
    values = sample_mask_corners(kit, png)
    existing = kit.data.color_attributes.get("COLOR0")
    if existing and (existing.domain != "CORNER" or existing.data_type != "FLOAT_COLOR"):
        raise ValueError("Existing COLOR0 has an incompatible data layout; do not silently replace")
    layer = existing or kit.data.color_attributes.new("COLOR0", "FLOAT_COLOR", "CORNER")
    layer.data.foreach_set("color", values.ravel())
    index = list(kit.data.color_attributes).index(layer)
    kit.data.color_attributes.active_color_index = index
    kit.data.color_attributes.render_color_index = index
    kit["COLOR0_semantic"] = "Linear RGBA kit weights, NOT albedo or opacity. glTF COLOR_0."
    kit.data.update()
    return values


def validate_driver_contract(rig, skin, kit, gear, png):
    contact_contract = contacts.measure_contact_contract(rig, skin, gear)
    checks = {}
    for side in ("L", "R"):
        for chain in (("Thigh", "Shin", "Foot", "Toe"),
                      ("UpperArm", "Forearm", "Hand", "Palm")):
            for parent, child in zip(chain, chain[1:]):
                bone = rig.data.bones.get(child + "_" + side)
                checks[f"{child}_{side}_direct_parent_{parent}"] = bool(
                    bone and bone.parent and bone.parent.name == parent + "_" + side)
        palm = rig.data.bones.get("Palm_" + side)
        desired = Matrix(contact_contract["palms"]["Palm_" + side]["transform_blender_rows"])
        checks["Palm_" + side + "_non_deforming"] = bool(palm and not palm.use_deform)
        checks["Palm_" + side + "_center"] = bool(
            palm and (palm.head_local - desired.translation).length < 1e-6)
        checks["Palm_" + side + "_axes"] = bool(
            palm and max(abs(palm.matrix_local[i][j] - desired[i][j])
                         for i in range(3) for j in range(3)) < 1e-5)
    checks["bone_count_54"] = len(rig.data.bones) == 54
    checks["deforming_count_51"] = sum(b.use_deform for b in rig.data.bones) == 51
    layer = kit.data.color_attributes.get("COLOR0")
    checks["COLOR0_FLOAT_COLOR_CORNER"] = bool(
        layer and layer.data_type == "FLOAT_COLOR" and layer.domain == "CORNER")
    if layer is None:
        return {"checks": checks, "passed": sum(checks.values()), "total": len(checks)}
    actual = np.empty(len(layer.data) * 4, dtype=np.float32)
    layer.data.foreach_get("color", actual)
    actual = actual.reshape((-1, 4))
    expected = sample_mask_corners(kit, png)
    checks["COLOR0_matches_authored_PNG_samples"] = bool(np.max(abs(actual - expected)) < 1e-6)
    checks["COLOR0_linear_normalized"] = bool(np.max(abs(actual.sum(1) - 1)) < 1e-6)
    checks["COLOR0_finite_in_range"] = bool(np.isfinite(actual).all()
                                           and actual.min() >= 0 and actual.max() <= 1)
    checks["COLOR0_all_four_zones_present"] = bool(np.all(actual.max(0) > 0.99))
    checks["COLOR0_active_for_render"] = (
        kit.data.color_attributes[kit.data.color_attributes.render_color_index].name == "COLOR0")
    checks["skin_gear_outside_kit_mask"] = all(
        obj.data.color_attributes.get("COLOR0") is None for obj in (skin, gear))
    return {
        "checks": checks, "passed": sum(checks.values()), "total": len(checks),
        "color0": {"authoring_domain": "CORNER (split to per-vertex COLOR_0 in glTF)",
                   "corners": len(actual), "float_bytes_in_source": int(actual.nbytes),
                   "max_normalization_error": float(np.max(abs(actual.sum(1) - 1))),
                   "max_png_sample_error": float(np.max(abs(actual - expected))),
                   "channel_min": actual.min(0).tolist(), "channel_max": actual.max(0).tolist()},
    }


def apply_driver_contract(rig, skin, kit, gear, png):
    before_meshes = {obj.name: geometry_fingerprint(obj) for obj in (skin, kit, gear)}
    before_bones = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones
                    if bone.name not in ("Palm_L", "Palm_R")}
    contact_contract = contacts.measure_contact_contract(rig, skin, gear)
    add_palm_helpers(rig, contact_contract)
    add_color0(kit, png)
    after_meshes = {obj.name: geometry_fingerprint(obj) for obj in (skin, kit, gear)}
    if before_meshes != after_meshes:
        raise ValueError("Helper/color adaptation unexpectedly changed mesh topology, UVs or skin weights")
    rest_error = max(abs(rig.data.bones[name].matrix_local[i][j] - matrix[i][j])
                     for name, matrix in before_bones.items()
                     for i in range(4) for j in range(4))
    if rest_error > 1e-6:
        raise ValueError(f"Existing rest transforms changed beyond numeric tolerance: {rest_error}")
    report = validate_driver_contract(rig, skin, kit, gear, png)
    if report["passed"] != report["total"]:
        raise ValueError(json.dumps(report, indent=2))
    report["geometry_weights_uv_fingerprints_unchanged"] = after_meshes
    report["max_existing_rest_transform_component_delta"] = rest_error
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-source", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not args.update_source:
        raise SystemExit("Explicit --update-source required to change the source integration contract.")
    source = HERE / "court_athlete.blend"
    manifest_path = HERE / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    previous_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    if previous_hash != manifest["source_sha256"]:
        raise ValueError("Source differs from current manifest")
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    rig = bpy.data.objects["CourtAthlete"]
    skin, kit, gear = [bpy.data.objects[name] for name in MESH_NAMES]
    if manifest.get("integration_contract_version") == 2:
        # A repeat invocation must not rewrite the source or reattribute the r2
        # screenshots to the latest source hash. Build handles future art edits.
        report = validate_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
        if report["passed"] != report["total"]:
            raise ValueError(json.dumps(report, indent=2))
        print(json.dumps({"status": "already_v2_validated_no_writes",
                          "source_sha256": previous_hash, "validation": report,
                          "game_written": False, "integration_touched": False}, indent=2))
        return
    # Archive the pre-contract authoring candidate for its existing r2 images.
    # This is not a second runtime export or an art/exports tree.
    archived = REPO / ".dream-loop/athlete-upgrade/source-archive" / f"court_athlete-{previous_hash[:12]}.blend"
    archived.parent.mkdir(parents=True, exist_ok=True)
    if not archived.exists():
        shutil.copyfile(source, archived)
    if hashlib.sha256(archived.read_bytes()).hexdigest() != previous_hash:
        raise ValueError("Existing archived source differs; do not overwrite it")
    report = apply_driver_contract(rig, skin, kit, gear, HERE / "maps/kit_mask.png")
    import build_athlete as build
    import inspect_athlete as inspection
    source_checks = inspection.validate()
    if source_checks["passed"] != source_checks["total"]:
        raise ValueError(json.dumps(source_checks, indent=2))
    bones = build.skeleton_report(rig)
    contact_checks = contacts.validate_contract(bones["contact_contract"], rig, skin)
    if contact_checks["passed"] != contact_checks["total"]:
        raise ValueError(json.dumps(contact_checks, indent=2))
    bpy.context.scene["integration_contract_version"] = 2
    bpy.context.preferences.filepaths.save_version = 0  # This factory session only; never save preferences.
    bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
    current_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bones["contact_contract"]["source_sha256"] = current_hash
    contacts.save_json(HERE / "rig_manifest.json", bones)
    manifest["source_sha256"] = current_hash
    manifest["source_bytes"] = source.stat().st_size
    manifest["bone_count"] = 54
    manifest["deform_bone_count"] = 51
    manifest["integration_contract_version"] = 2
    manifest["status"] = "Palm_helpers_COLOR0_source_candidate_awaiting_game_isolation"
    manifest["contact_contract"] = {
        "file": "rig_manifest.json", "key": "contact_contract", "schema_version": 2,
        "source_sha256": current_hash, "validation": contact_checks,
    }
    manifest["texture_contract"]["kit_mask"] = "Linear data COLOR0 -> glTF COLOR_0, RGBA normalized; never opacity/albedo."
    manifest["texture_contract"]["kit_mask_binding"] = bones["contact_contract"]["kit_mask_binding"]
    manifest["driver_contract_adaptation"] = {
        "previous_source_sha256": previous_hash, "source_sha256": current_hash,
        "archived_authoring_candidate": str(archived.relative_to(REPO)),
        "validation": report, "current_source_structural_validation": source_checks,
        "game_exported": False, "game_tested": False,
        "art_round_consumed": False, "remaining_art_rounds": 1,
    }
    manifest["source_inspection"]["source_sha256"] = previous_hash
    manifest["source_inspection"]["evidence_scope"] = (
        "Prior r2 rendered source, archived under driver_contract_adaptation; no new renders. "
        "Mesh topology/positions/UVs/weights and all maps unchanged by the Palm/COLOR0 adaptation.")
    for item in manifest["meshes"]:
        item["color_attributes"] = (
            [{"name": "COLOR0", "type": "FLOAT_COLOR", "domain": "CORNER"}]
            if item["name"] == "AthleteKitMesh" else [])
    contacts.save_json(manifest_path, manifest)
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    provenance["adaptation"] = [
        ("Own 54-bone humanoid rig (51 deforming; Root/Palm_L/Palm_R helpers), skin weights, UV atlases and baked PBR maps"
         if item.startswith("Own 52-bone humanoid rig") else item)
        for item in provenance["adaptation"]]
    provenance["integration_contract"] = "Own rig: 54 bones, 51 deforming; Root and Palm_L/R helpers non-deforming. Own COLOR0 data copied from the authored PNG mask."
    contacts.save_json(HERE / "provenance.json", provenance)
    print(json.dumps({
        "source_sha256": current_hash, "source_bytes": source.stat().st_size,
        "bones": 54, "deforming": 51, "driver_contract": report,
        "source_checks": [source_checks["passed"], source_checks["total"]],
        "contact_checks": [contact_checks["passed"], contact_checks["total"]],
        "game_written": False, "integration_touched": False,
    }, indent=2), flush=True)


if __name__ == "__main__":
    main()
