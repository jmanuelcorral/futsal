"""Measure presentation contact locators from the existing athlete, without edits.

Blender CLI: --background --factory-startup --disable-autoexec
             --python-exit-code 1 --python .../contact_locators.py -- --update-manifests

No meshes, bones, maps, .blend files, game files or preferences are changed.
Palm targets are NOT wrists. Frame +Z is semantic forward; +Y is up/outward.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
from mesh_tools import barycentric_double
CONVERSION = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))


def save_json(path, value):
    temporary = path.with_suffix(path.suffix + ".pending")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def vec(value):
    return [float(x) for x in value]


def rows(matrix):
    return [vec(row) for row in matrix]


def frame(origin, forward, up):
    up = up.normalized()
    forward = (forward - up * forward.dot(up)).normalized()
    lateral = up.cross(forward).normalized()
    forward = lateral.cross(up).normalized()
    matrix = Matrix((lateral, up, forward)).transposed().to_4x4()
    matrix.translation = origin
    return matrix


def frame_record(matrix, bone):
    local = bone.matrix_local.inverted() @ matrix
    gltf = CONVERSION @ matrix

    def axes(transform):
        basis = transform.to_3x3()
        return {"lateral_x": vec(basis.col[0]), "up_y": vec(basis.col[1]),
                "forward_z": vec(basis.col[2])}

    return {
        "bone": bone.name,
        "position_bone_local_m": vec(local.translation),
        "position_blender_m": vec(matrix.translation),
        "position_gltf_m": vec(gltf.translation),
        "axes_bone_local": axes(local), "axes_blender": axes(matrix), "axes_gltf": axes(gltf),
        "transform_bone_local_rows": rows(local),
        "transform_blender_rows": rows(matrix),
        "transform_gltf_rows": rows(gltf),
    }


def build_tree(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    points = [vertex.co.copy() for vertex in mesh.vertices]
    triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
    return points, triangles, BVHTree.FromPolygons(points, triangles, all_triangles=True)


def palm_locator(rig, skin, side, points, triangles, tree):
    hand = rig.data.bones["Hand_" + side]
    wrist = hand.head_local.copy()
    knuckles = [rig.data.bones[name + "01_" + side].head_local.copy()
                for name in ("Index", "Middle", "Ring", "Pinky")]
    knuckle_center = sum(knuckles, Vector()) / 4
    forward = (knuckle_center - wrist).normalized()
    transverse = (knuckles[0] - knuckles[3]).normalized()
    outward = forward.cross(transverse).normalized()
    sign = 1 if side == "L" else -1
    if outward.dot(Vector((-sign, 0, 0))) < 0:
        outward.negate()
    # Inspected anatomical landmark, not a guessed offset from the ball.
    # At 55%, this particular scan hits the proximal thenar pad, not the
    # central palm. 80% reaches the central palmar hollow below that pad.
    center = wrist.lerp(knuckle_center, 0.80)
    surface, normal, triangle_index, _ = tree.ray_cast(center + outward * 0.070,
                                                       -outward, 0.14)
    dorsal, _, _, _ = tree.ray_cast(center - outward * 0.070, outward, 0.14)
    if surface is None or dorsal is None or normal.dot(outward) <= 0:
        raise ValueError(f"Could not identify the palmar surface of {side}")
    if (surface - center).length > 0.035 or (dorsal - surface).length > 0.045:
        raise ValueError(f"Palm probe needs review on side {side}: "
                         f"seed={vec(center)}, palmar={vec(surface)}, dorsal={vec(dorsal)}, "
                         f"seed_distance={(surface-center).length}, thickness={(dorsal-surface).length}")
    ids = triangles[triangle_index]
    bary = barycentric_double(surface, *(points[i] for i in ids))
    smoothed_normal = sum((skin.data.vertices[i].normal * factor for i, factor in zip(ids, bary)),
                          Vector()).normalized()
    weights = {}
    for index, factor in zip(ids, bary):
        for assignment in skin.data.vertices[index].groups:
            name = skin.vertex_groups[assignment.group].name
            weights[name] = weights.get(name, 0.0) + factor * assignment.weight
    result = frame_record(frame(surface, forward, smoothed_normal), hand)
    result.update({
        "name": "Palm_" + side, "kind": "locator_only_not_a_bone",
        "semantic": "CENTER OF PALMAR SKIN SURFACE, not wrist and not ball center/radius",
        "forward_definition": "+Z wrist-to-mean-MCP direction projected onto the central palm tangent plane",
        "up_definition": "+Y smoothed geometric outward palmar normal, NOT world up or the back of the hand",
        "authored_landmark": {
            "method": "80% wrist-to-mean-MCP projected onto central palmar skin; inspected against the actual hand, avoiding the proximal thenar pad",
            "mcp_mean_blender_m": vec(knuckle_center),
            "seed_center_blender_m": vec(center),
            "dorsal_surface_blender_m": vec(dorsal),
        },
        "wrist_to_palm_distance_m": (surface - wrist).length,
        "palm_local_thickness_m": (surface - dorsal).length,
        "surface_evidence": {
            "mesh": skin.name, "triangle_vertex_indices": list(ids),
            "barycentric_weights": vec(bary), "normal_blender": vec(normal),
            "smoothed_normal_blender": vec(smoothed_normal),
            "interpolated_skin_weights": weights,
        },
    })
    return result


def boot_measurement(rig, gear, side):
    foot = rig.data.bones["Foot_" + side]
    ankle = foot.head_local.copy()
    sign = 1 if side == "L" else -1
    # The modeled indoor-shoe last has this authoring yaw. It is horizontal;
    # Foot's bone +Y instead points down into the forefoot and is not this axis.
    angle = math.radians(22)
    forward = Vector((sign * math.sin(angle), -math.cos(angle), 0))
    contact_frame = frame(ankle, forward, Vector((0, 0, 1)))
    lateral = contact_frame.to_3x3().col[0]
    mesh = gear.data
    eligible = set()
    for vertex in mesh.vertices:
        side_weight = sum(g.weight for g in vertex.groups
                          if gear.vertex_groups[g.group].name in ("Foot_" + side, "Toe_" + side))
        if side_weight > 0.999:
            eligible.add(vertex.index)
    sole_ids = {i for face in mesh.polygons
                if mesh.attributes["surface_kind"].data[face.index].value == 7
                for i in face.vertices if i in eligible}
    if not eligible or not sole_ids:
        raise ValueError(f"No actual sole/boot geometry found for {side}")
    boot = [mesh.vertices[i].co.copy() for i in sorted(eligible)]
    sole = [mesh.vertices[i].co.copy() for i in sorted(sole_ids)]

    def ranges(values):
        return {
            "forward_from_ankle_m": [min((p - ankle).dot(forward) for p in values),
                                    max((p - ankle).dot(forward) for p in values)],
            "lateral_from_ankle_m": [min((p - ankle).dot(lateral) for p in values),
                                    max((p - ankle).dot(lateral) for p in values)],
            "height_above_ground_m": [min(p.z for p in values), max(p.z for p in values)],
        }

    outer_ranges, sole_ranges = ranges(boot), ranges(sole)
    toe = sole_ranges["forward_from_ankle_m"][1]
    heel = -sole_ranges["forward_from_ankle_m"][0]
    front = [p for p in sole if (p - ankle).dot(forward) >= toe - 0.003]
    rear = [p for p in sole if (p - ankle).dot(forward) <= -heel + 0.003]
    low_front = min(p.z for p in front)
    low_rear = min(p.z for p in rear)
    result = frame_record(contact_frame, foot)
    result.update({
        "name": "BootFrame_" + side, "kind": "locator_frame_only_not_a_bone",
        "forward_definition": "+Z towards the modeled toe, parallel to the sole plane",
        "up_definition": "+Y away from the floor, Blender +Z / glTF +Y at rest",
        "ankle_height_m": ankle.z,
        "shoe_outer_bounds_in_contact_frame": outer_ranges,
        "sole_bounds_in_contact_frame": sole_ranges,
        "sole_length_m": toe + heel,
        "sole_max_width_m": sole_ranges["lateral_from_ankle_m"][1] - sole_ranges["lateral_from_ankle_m"][0],
        "sole_toe_reach_from_ankle_m": toe,
        "outer_toe_reach_from_ankle_m": outer_ranges["forward_from_ankle_m"][1],
        "sole_heel_reach_from_ankle_m": heel,
        "outer_heel_reach_from_ankle_m": -outer_ranges["forward_from_ankle_m"][0],
        "toe_spring_lower_sole_height_m": low_front,
        "heel_lower_sole_height_m": low_rear,
        "geometry_evidence": {"mesh": gear.name, "boot_vertices": len(eligible),
                              "sole_vertices": len(sole_ids), "sole_surface_kind": 7},
        "old_presentation_targets_m": {"ankle_height": 0.08, "toe_reach": 0.195,
                                      "heel_reach": 0.075, "ground": 0},
        "delta_to_old_targets_m": {"ankle_height": ankle.z - 0.08,
                                  "toe_reach": outer_ranges["forward_from_ankle_m"][1] - 0.195,
                                  "heel_reach": -outer_ranges["forward_from_ankle_m"][0] - 0.075},
        "note": "Distances use the boot's own forward axis, not raw actor Z in this outward-foot rest pose. Do not rescale anatomy to hide these deltas.",
    })
    return result


def measure_contact_contract(rig, skin, gear):
    points, triangles, tree = build_tree(skin)
    kit = bpy.data.objects.get("AthleteKitMesh")
    color0 = kit.data.color_attributes.get("COLOR0") if kit else None
    helpers = all(rig.data.bones.get("Palm_" + side) for side in ("L", "R"))
    report = {
        "schema_version": 2 if helpers or color0 else 1, "units": "metres",
        "target_semantics": {
            "hand": "Palm_L/R center of palmar skin, NOT Hand_L/R bone head (wrist)",
            "ball_offset": "Ball radius/contact offset belongs to the existing action target resolver; do not apply it twice here.",
            "root_motion": "Presentation only; no physical actor, collision or ball authority changes.",
        },
        "frame_convention": {
            "forward": "frame +Z", "up": "frame +Y",
            "lateral": "frame +X = up cross forward; right-handed frame, not an anatomical left/right label",
            "matrix_format": "Row-major JSON arrays acting on column vectors",
            "bone_local": "Blender bone rest basis, also the un-rebased glTF joint basis. Not actor XYZ.",
            "importer_rebasis": "If Godot rebases bones, reconstruct local locator as imported_bone_global_rest.inverse() * transform_gltf, within the imported model root before its MatchSnapshot yaw.",
            "wrist_solver": "wrist_origin = desired_palm_center - posed_hand_basis * position_bone_local_m",
        },
        "palms": {f"Palm_{side}": palm_locator(rig, skin, side, points, triangles, tree)
                  for side in ("L", "R")},
        "feet": {f"Foot_{side}": boot_measurement(rig, gear, side) for side in ("L", "R")},
        "kit_mask_binding": {
            "representation": "PNG texture, NOT vertex COLOR0",
            "material": "AthleteKit", "uv_set": 0,
            "source_path": "maps/kit_mask.png",
            "runtime_path_after_permission": "game/assets/athletes/court_athlete/textures/kit_mask.png",
            "encoding": "RGBA8 UNORM", "color_space": "Non-Color/linear",
            "alpha_is_opacity": False, "channel_byte_sum": 255,
            "channels": {"R": "jersey primary", "G": "shorts + existing narrow secondary jersey side panels",
                         "B": "socks", "A": "bound trims"},
            "maps_retained": ["kit_albedo.png (sRGB neutral)", "kit_normal.png (+Y tangent)",
                              "kit_orm.png (linear R=AO G=roughness B=metallic)"],
        },
    }
    if helpers:
        for side in ("L", "R"):
            helper = rig.data.bones["Palm_" + side]
            report["palms"]["Palm_" + side].update({
                "kind": "non_deforming_Palm_bone_plus_Hand_relative_locator",
                "helper_bone": helper.name,
                "helper_parent_bone": helper.parent.name if helper.parent else None,
                "helper_deform": helper.use_deform,
                "helper_head_blender_m": vec(helper.head_local),
                "helper_rest_armature_matrix_rows": rows(helper.matrix_local),
                "bone_field_definition": "'bone' remains Hand_L/R, the anchor of transform_bone_local_rows; helper_bone is the new actual Palm joint.",
            })
    if color0:
        binding = report["kit_mask_binding"]
        binding.update({
            "representation": "Blender COLOR0 -> glTF COLOR_0 -> Godot COLOR, linear RGBA data",
            "encoding": "FLOAT_COLOR authoring; RGBA normalized per exported vertex",
            "attribute_name": "COLOR0", "gltf_attribute": "COLOR_0",
            "authoring_domain": color0.domain,
            "uv_set": None,
            "source_path": None,
            "runtime_path_after_permission": None,
            "png_authoring_master": "maps/kit_mask.png",
            "transfer_method": "Bilinear sampling of the existing PNG in UV0 at each mesh corner, then normalization; secondary jersey side panels preserved.",
            "channel_sum": 1.0,
            "generic_material_warning": "COLOR_0 is mask DATA, not ordinary albedo or opacity. Use the coordinator's kit shader; a generic glTF viewer may display mask colors.",
        })
        binding.pop("channel_byte_sum", None)
    return report


def validate_contract(contract, rig, skin):
    checks = {}
    errors = {}
    for group in ("palms", "feet"):
        for name, locator in contract[group].items():
            local = Matrix(locator["transform_bone_local_rows"])
            world = Matrix(locator["transform_blender_rows"])
            rest = rig.data.bones[locator["bone"]].matrix_local
            reconstruction = rest @ local
            error = max(abs(reconstruction[i][j] - world[i][j])
                        for i in range(4) for j in range(4))
            checks[name + "_bone_local_roundtrip"] = error < 1e-6
            basis = world.to_3x3()
            checks[name + "_orthonormal_right_handed"] = (
                abs(basis.determinant() - 1) < 1e-5
                and all(abs(basis.col[i].dot(basis.col[j]) - (1 if i == j else 0)) < 1e-5
                        for i in range(3) for j in range(3)))
            converted = CONVERSION @ world
            checks[name + "_gltf_conversion"] = max(
                abs(converted[i][j] - locator["transform_gltf_rows"][i][j])
                for i in range(4) for j in range(4)) < 1e-6
            fields_match = True
            for space, transform in (("bone_local", local), ("blender", world), ("gltf", converted)):
                fields_match &= (Vector(locator[f"position_{space}_m"]) - transform.translation).length < 1e-6
                for axis_index, axis_name in enumerate(("lateral_x", "up_y", "forward_z")):
                    fields_match &= (
                        Vector(locator[f"axes_{space}"][axis_name])
                        - transform.to_3x3().col[axis_index]).length < 1e-6
            checks[name + "_position_axes_match_matrix"] = bool(fields_match)
            errors[name + "_roundtrip_max_component"] = error
    for name, locator in contract["palms"].items():
        weights = locator["surface_evidence"]["barycentric_weights"]
        checks[name + "_inside_real_triangle"] = min(weights) >= -1e-5 and abs(sum(weights) - 1) < 1e-5
        checks[name + "_is_not_wrist"] = 0.025 < locator["wrist_to_palm_distance_m"] < 0.08
        offset = Vector(locator["position_bone_local_m"])
        target = Vector((0.51, 1.13, -0.42))
        for angle in (-1.1, -0.35, 0.55, 1.4):
            basis = Quaternion(Vector((0.2, 0.6, 0.7)).normalized(), angle).to_matrix()
            wrist = target - basis @ offset
            error = (wrist + basis @ offset - target).length
            checks[name + f"_preserves_palm_target_{angle}"] = error < 1e-6
    # A rest locator follows its bone. Quantify (do not hide) residual movement
    # of the actual skinned palm when the wrist alone bends.
    deformed_errors = {}
    for name, locator in contract["palms"].items():
        hand = rig.pose.bones[locator["bone"]]
        original = hand.matrix_basis.copy()
        ids = locator["surface_evidence"]["triangle_vertex_indices"]
        weights = locator["surface_evidence"]["barycentric_weights"]
        values = []
        try:
            for axis in ((1, 0, 0), (0, 0, 1)):
                for angle in (-35, 35):
                    hand.matrix_basis = Quaternion(Vector(axis), math.radians(angle)).to_matrix().to_4x4()
                    bpy.context.view_layer.update()
                    evaluated = skin.evaluated_get(bpy.context.evaluated_depsgraph_get())
                    actual = sum((evaluated.data.vertices[i].co * w for i, w in zip(ids, weights)), Vector())
                    locator_point = hand.matrix @ Vector(locator["position_bone_local_m"])
                    values.append((actual - locator_point).length)
        finally:
            hand.matrix_basis = original
            bpy.context.view_layer.update()
        deformed_errors[name] = {"max_surface_vs_bone_locator_m": max(values),
                                 "tested_local_wrist_angles_degrees": [-35, 35],
                                 "axes": ["bone local X", "bone local Z"],
                                 "note": "Diagnostic of linear skinning, not acceptance of live catches/throws."}
    helpers = [b for b in rig.data.bones if b.name in ("Palm_L", "Palm_R")]
    checks["rig_matches_declared_helper_variant"] = (
        len(helpers) in (0, 2) and len(rig.data.bones) == 52 + len(helpers)
        and all(not b.use_deform for b in helpers))
    return {"checks": checks, "passed": sum(checks.values()), "total": len(checks),
            "numerical_errors": errors, "skinned_palm_diagnostic": deformed_errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-manifests", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    source = HERE / "court_athlete.blend"
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    if source_hash != manifest["source_sha256"]:
        raise ValueError("Source changed since its manifest; do not attach stale measurements")
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    rig, skin, gear = [bpy.data.objects[name] for name in
                       ("CourtAthlete", "AthleteSkinMesh", "AthleteGearMesh")]
    contract = measure_contact_contract(rig, skin, gear)
    contract["source_sha256"] = source_hash
    validation = validate_contract(contract, rig, skin)
    if validation["passed"] != validation["total"]:
        raise ValueError(json.dumps(validation, indent=2))
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_hash:
        raise ValueError("Metadata-only operation unexpectedly changed the .blend")
    if args.update_manifests:
        rig_manifest = json.loads((HERE / "rig_manifest.json").read_text(encoding="utf-8"))
        rig_manifest["contact_contract"] = contract
        rig_manifest["presentation_adapter"]["hand_target"] = "PALM center, not wrist; use contact_contract.palms"
        save_json(HERE / "rig_manifest.json", rig_manifest)
        manifest["contact_contract"] = {
            "file": "rig_manifest.json", "key": "contact_contract", "schema_version": contract["schema_version"],
            "source_sha256": source_hash, "validation": validation,
        }
        manifest["texture_contract"]["kit_mask_binding"] = contract["kit_mask_binding"]
        save_json(HERE / "manifest.json", manifest)
    print(json.dumps({
        "source_sha256": source_hash,
        "palms_bone_local_m": {name: item["position_bone_local_m"]
                              for name, item in contract["palms"].items()},
        "boot_dimensions": {
            name: {key: item[key] for key in (
                "ankle_height_m", "sole_length_m", "sole_max_width_m",
                "outer_toe_reach_from_ankle_m", "outer_heel_reach_from_ankle_m",
                "toe_spring_lower_sole_height_m", "heel_lower_sole_height_m")}
            for name, item in contract["feet"].items()},
        "validation": validation, "blend_modified": False, "game_written": False,
    }, indent=2), flush=True)


if __name__ == "__main__":
    main()
