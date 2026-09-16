"""Bounded CPU source inspection; these images are NOT game/FPS evidence.

Load the saved source, validate its bind contract, pose actual skinned geometry,
render three full-body views and one face/hand detail. No source/game mutation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE = HERE / "court_athlete.blend"
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--round", default="r1")
    parser.add_argument("--views", nargs="+", default=["front", "back", "flex"])
    parser.add_argument("--samples", type=int, default=24)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(args)


def point_camera(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def aim(rig, name, head, tail, orientation=None):
    bone = rig.data.bones[name]
    rotation = orientation
    if rotation is None:
        # Bone.vector is parent-relative; matrix_local/head_local are in
        # armature space. Mixing them incorrectly twists every articulated limb.
        rest_direction = bone.tail_local - bone.head_local
        rotation = rest_direction.normalized().rotation_difference((tail - head).normalized())
        rotation = rotation @ bone.matrix_local.to_quaternion()
    rig.pose.bones[name].matrix = Matrix.LocRotScale(head, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()
    if (rig.pose.bones[name].head - head).length > 0.00001:
        raise ValueError(f"Diagnostic pose head mismatch: {name}")
    if orientation is None and (rig.pose.bones[name].tail - tail).length > 0.0005:
        raise ValueError(f"Diagnostic pose tail mismatch: {name}")


def two_bone(origin, target, first, second, pole):
    delta = target - origin
    distance = min(delta.length, (first + second) * 0.9995)
    distance = max(distance, abs(first - second) + 0.0005)
    axis = delta.normalized()
    along = (first * first - second * second + distance * distance) / (2 * distance)
    perpendicular = pole - axis * pole.dot(axis)
    perpendicular.normalize()
    return origin + axis * along + perpendicular * math.sqrt(max(0, first * first - along * along))


def pose(rig, stress=False, rest=False):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    if rest:
        return {}
    pelvis = rig.pose.bones["Hips"]
    pelvis.matrix = Matrix.Translation((0, 0, -0.20 if stress else -0.075)) @ pelvis.matrix
    bpy.context.view_layer.update()
    spine = rig.pose.bones["Spine"]
    rotation = Quaternion(Vector((1, 0, 0)), math.radians(11 if stress else 6))
    origin = spine.head.copy()
    spine.matrix = (Matrix.Translation(origin) @ rotation.to_matrix().to_4x4()
                    @ Matrix.Translation(-origin) @ spine.matrix)
    bpy.context.view_layer.update()
    bends = {}
    for side, sign in (("L", 1), ("R", -1)):
        thigh, shin = "Thigh_" + side, "Shin_" + side
        hip = rig.pose.bones[thigh].head.copy()
        ankle = rig.data.bones["Foot_" + side].head_local.copy()
        if stress and side == "R":
            ankle += Vector((0, -0.22, 0.12))
        knee = two_bone(hip, ankle, rig.data.bones[thigh].length,
                        rig.data.bones[shin].length, Vector((0, -1, 0)))
        aim(rig, thigh, hip, knee)
        aim(rig, shin, knee, ankle)
        foot = rig.data.bones["Foot_" + side]
        foot_direction = foot.tail_local - foot.head_local
        aim(rig, "Foot_" + side, ankle, ankle + foot_direction,
            orientation=foot.matrix_local.to_quaternion())
        toe = rig.data.bones["Toe_" + side]
        toe_head = ankle + foot_direction
        aim(rig, "Toe_" + side, toe_head, toe_head + (toe.tail_local - toe.head_local),
            orientation=toe.matrix_local.to_quaternion())
        bends["knee_" + side + "_degrees"] = math.degrees((hip - knee).angle(ankle - knee))
        upper, forearm = "UpperArm_" + side, "Forearm_" + side
        shoulder = rig.pose.bones[upper].head.copy()
        wrist = Vector((sign * (0.36 if stress else 0.34), -0.31 if stress else -0.18,
                        1.27 if stress else 1.02))
        elbow = two_bone(shoulder, wrist, rig.data.bones[upper].length,
                         rig.data.bones[forearm].length, Vector((sign * 0.5, 1, 0)))
        aim(rig, upper, shoulder, elbow)
        aim(rig, forearm, elbow, wrist)
        hand = rig.data.bones["Hand_" + side]
        relative = rig.data.bones[forearm].matrix_local.to_quaternion().inverted() @ hand.matrix_local.to_quaternion()
        hand_rotation = rig.pose.bones[forearm].matrix.to_quaternion() @ relative
        aim(rig, "Hand_" + side, wrist, wrist + hand.vector, orientation=hand_rotation)
        bends["elbow_" + side + "_degrees"] = math.degrees((shoulder - elbow).angle(wrist - elbow))
    return bends


def preview_kit():
    # Local inspection-only palette mixing. Saved source/export retains image PBR
    # and its linear data mask for the coordinator's native Godot shader.
    material = bpy.data.materials["AthleteKit"]
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    texture = nodes["Kit_RGBA_Weights_Data_Not_Opacity"]
    separation = nodes.new("ShaderNodeSeparateColor")
    separation.mode = "RGB"
    links.new(texture.outputs["Color"], separation.inputs["Color"])
    colors = ((0.025, 0.102, 0.125), (0.024, 0.035, 0.043),
              (0.78, 0.765, 0.69), (0.39, 0.123, 0.061))
    weights = [separation.outputs[name] for name in ("Red", "Green", "Blue")] + [texture.outputs["Alpha"]]
    terms = []
    for color, weight in zip(colors, weights):
        scale = nodes.new("ShaderNodeVectorMath")
        scale.operation = "SCALE"
        scale.inputs[0].default_value = color
        links.new(weight, scale.inputs["Scale"])
        terms.append(scale.outputs["Vector"])
    total = terms[0]
    for term in terms[1:]:
        addition = nodes.new("ShaderNodeVectorMath")
        addition.operation = "ADD"
        links.new(total, addition.inputs[0])
        links.new(term, addition.inputs[1])
        total = addition.outputs["Vector"]
    multiply = nodes.new("ShaderNodeVectorMath")
    multiply.operation = "MULTIPLY"
    links.new(total, multiply.inputs[0])
    links.new(nodes["Map_albedo"].outputs["Color"], multiply.inputs[1])
    links.new(multiply.outputs["Vector"], shader.inputs["Base Color"])


def studio(samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    if hasattr(scene.cycles, "denoising_use_gpu"):
        scene.cycles.denoising_use_gpu = False
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0
    world = scene.world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.10, 0.115, 0.135, 1)
    background.inputs["Strength"].default_value = 0.55
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.001))
    ground = bpy.context.object
    ground.name = "INSPECTION_ONLY_Ground"
    material = bpy.data.materials.new("INSPECTION_ONLY_Ground")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.078, 0.090, 0.104, 1)
    shader.inputs["Roughness"].default_value = 0.86
    ground.data.materials.append(material)
    for name, position, power, size in (
            ("Key", (-3.2, -4.2, 4.5), 430, 4.0),
            ("Fill", (3.5, -0.5, 2.9), 180, 3.5),
            ("Back", (0.5, 3.5, 3.5), 240, 3.0)):
        data = bpy.data.lights.new("INSPECTION_ONLY_" + name, "AREA")
        data.energy = power
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new("INSPECTION_ONLY_" + name, data)
        scene.collection.objects.link(obj)
        obj.location = position
        point_camera(obj, (0, 0, 0.9))
    data = bpy.data.cameras.new("INSPECTION_ONLY_Camera")
    camera = bpy.data.objects.new("INSPECTION_ONLY_Camera", data)
    scene.collection.objects.link(camera)
    data.type = "ORTHO"
    data.ortho_scale = 2.01
    data.lens = 58
    scene.camera = camera
    return camera


def validate():
    meshes = [bpy.data.objects[name] for name in ("AthleteSkinMesh", "AthleteKitMesh", "AthleteGearMesh")]
    rig = bpy.data.objects["CourtAthlete"]
    checks = {}
    checks["one_rig"] = len([o for o in bpy.data.objects if o.type == "ARMATURE"]) == 1
    checks["root_non_deforming"] = not rig.data.bones["Root"].use_deform
    checks["no_actions"] = len(bpy.data.actions) == 0
    checks["no_source_camera_or_light"] = not any(o.type in ("CAMERA", "LIGHT") for o in bpy.data.objects)
    checks["rest_pose_identity"] = all(
        sum(abs(b.matrix_basis[i][j] - Matrix.Identity(4)[i][j])
            for i in range(4) for j in range(4)) < 1e-6 for b in rig.pose.bones)
    checks["object_transforms_applied"] = all(
        o.location.length < 1e-6 and o.rotation_euler.to_matrix().to_quaternion().angle < 1e-6
        and (o.scale - Vector((1, 1, 1))).length < 1e-6 for o in meshes + [rig])
    checks["three_materials"] = {m.name for o in meshes for m in o.data.materials} == {
        "AthleteSkin", "AthleteKit", "AthleteGear"}
    used_bones = set()
    unweighted = 0
    max_influences = 0
    normalization_error = 0
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
        for vertex in obj.data.vertices:
            weights = [g for g in vertex.groups if g.weight > 1e-5]
            max_influences = max(max_influences, len(weights))
            unweighted += not weights
            normalization_error = max(normalization_error, abs(sum(g.weight for g in weights) - 1))
            used_bones.update(obj.vertex_groups[g.group].name for g in weights)
    checks["influences_max_four"] = max_influences <= 4
    checks["weights_normalized"] = unweighted == 0 and normalization_error < 1e-5
    checks["geometry_hard_budget"] = triangles <= 60000
    checks["no_unused_deforming_bones"] = all(not bone.use_deform or bone.name in used_bones
                                             for bone in rig.data.bones)
    bounds = [[min(v.co[i] for obj in meshes for v in obj.data.vertices),
               max(v.co[i] for obj in meshes for v in obj.data.vertices)] for i in range(3)]
    checks["adult_height"] = 1.72 <= bounds[2][1] - bounds[2][0] <= 1.78
    checks["no_stray_meshes"] = max(abs(bounds[0][0]), abs(bounds[0][1])) < 0.60
    checks["soles_at_origin"] = abs(bounds[2][0]) <= 0.001
    from mathutils.bvhtree import BVHTree
    reference = bpy.data.objects["AnatomicalWeightReference"].data
    reference.calc_loop_triangles()
    source_tree = BVHTree.FromPolygons([v.co for v in reference.vertices],
                                      [t.vertices for t in reference.loop_triangles],
                                      all_triangles=True)
    inverted_skin_faces = 0
    for face in meshes[0].data.polygons:
        _, normal, _, _ = source_tree.find_nearest(face.center)
        inverted_skin_faces += face.normal.dot(normal) < 0
    checks["skin_winding_matches_anatomical_source"] = inverted_skin_faces == 0
    from atlas_tools import data_png_pixels, runtime_map_links
    checks.update(runtime_map_links(HERE / "maps"))
    _, normal_encoding = data_png_pixels(HERE / "maps" / "skin_normal.png")
    checks["skin_normal_RGBA8_opaque"] = (
        normal_encoding["color_type"] == 6
        and normal_encoding["width"] == normal_encoding["height"] == 2048
        and normal_encoding["alpha_min"] == normal_encoding["alpha_max"] == 255)
    return {"checks": checks, "passed": sum(checks.values()), "total": len(checks),
            "visible_triangles": triangles, "bounds_blender_m": bounds,
            "max_influences": max_influences, "normalization_error": normalization_error,
            "inverted_skin_faces": inverted_skin_faces,
            "unused_deforming_bones": [b.name for b in rig.data.bones if b.use_deform and b.name not in used_bones]}


def main():
    args = arguments()
    output = REPO / ".dream-loop/athlete-upgrade" / args.round
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
    report = validate()
    report.update({"kind": "Blender source self-inspection, NOT Godot/game/FPS evidence",
                   "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                   "renderer": "Cycles CPU", "samples": args.samples,
                   "resolution": [1024, 1024], "art_approved": False, "renders": []})
    print("SOURCE_CONTRACT", json.dumps(report), flush=True)
    if report["passed"] != report["total"]:
        (output / "source-inspection.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        raise ValueError("Source contract failed before rendering")
    preview_kit()
    camera = studio(args.samples)
    rig = bpy.data.objects["CourtAthlete"]
    for view in args.views:
        if view not in ("front", "back", "flex", "rest", "detail"):
            raise ValueError(f"Unknown bounded view: {view}")
        bends = pose(rig, stress=view == "flex", rest=view in ("rest", "detail"))
        camera.data.ortho_scale = 2.01
        target = (0, 0, 0.84 if view == "flex" else 0.89)
        camera.location = (2.5, -4.5, 2.2)
        if view == "back":
            camera.location = (2.3, 4.5, 2.2)
        if view == "detail":
            camera.data.ortho_scale = 0.47
            camera.location = (1.0, -4.0, 1.9)
            target = (0, -0.07, 1.59)
        point_camera(camera, target)
        filepath = output / ("source-" + view + ".png")
        bpy.context.scene.render.filepath = str(filepath)
        started = time.monotonic()
        bpy.ops.render.render(write_still=True)
        report["renders"].append({
            "file": str(filepath.relative_to(REPO)), "view": view,
            "camera_position_blender": list(camera.location),
            "camera_target_blender": list(target), "orthographic_scale": camera.data.ortho_scale,
            "sha256": hashlib.sha256(filepath.read_bytes()).hexdigest(),
            "offline_render_seconds": time.monotonic() - started,
            "pose_interior_joint_angles": bends,
        })
    (output / "source-inspection.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SOURCE_SELF_INSPECTION_DONE", str(output / "source-inspection.json"), flush=True)


if __name__ == "__main__":
    main()
