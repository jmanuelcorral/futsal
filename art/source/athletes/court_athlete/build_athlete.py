"""Build the representative dressed athlete, ONLY in art/source.

Blender 4.5.13:
  blender --background --factory-startup --disable-autoexec --python-exit-code 1
          --python art/source/athletes/court_athlete/build_athlete.py

The only external input is the explicitly authorized, SHA256-pinned CC0 mesh.
No installed settings/add-ons are changed; no runtime or release files are written.
"""
from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import atlas_tools as atlas
import contact_locators as contacts
import garment_tools as garments
import mesh_tools as mt
import rig_material_contract as driver_contract

REPO = HERE.parents[3]
BASE = (REPO / ".dream-loop/downloads/human-base-meshes-v1.4.1/"
        "human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend")
MAPS = HERE / "maps"
BASE_HASH = "3c121505651140ceb4d69fd1d8923f7788ffadd81672f5be14845a5f2c75c137"
ZIP_HASH = "811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515"
SCALE = (1.720 - 0.022) / (1.684413194656372 + 0.005547828506678343)
LIFT = 0.022 + 0.005547828506678343 * SCALE
EYE_Z = 1.5737066268920898 * SCALE + LIFT
REVISION = "athlete-upgrade-r3"
PARTS = []
KIT_PARTS = []
GEAR_PARTS = []
GARMENT_REPORT = {}


def point(value):
    return Vector((value[0] * SCALE, value[1] * SCALE, value[2] * SCALE + LIFT))


def anatomy(value):
    return Vector((value[0] / SCALE, value[1] / SCALE, (value[2] - LIFT) / SCALE))


def cz(z):
    return z * SCALE + LIFT


def saturate(value):
    return min(1.0, max(0.0, value))


def smoothstep(a, b, value):
    t = saturate((value - a) / (b - a))
    return t * t * (3 - 2 * t)


def make_rig(collection):
    data = bpy.data.armatures.new("CourtAthleteSkeleton")
    rig = bpy.data.objects.new("CourtAthlete", data)
    collection.objects.link(rig)
    rig.show_in_front = True
    rig["asset_revision"] = REVISION
    rig["authoring_axes"] = "Z up, -Y forward; metres; feet on z=0"
    rig["runtime_authority"] = "Presentation only. Root motion never moves the physical actor."
    mt.active(rig)
    bpy.ops.object.mode_set(mode="EDIT")

    def add(name, head, tail, parent=None, deform=True, raw=True):
        bone = data.edit_bones.new(name)
        bone.head = point(head) if raw else head
        bone.tail = point(tail) if raw else tail
        if parent:
            bone.parent = data.edit_bones[parent]
        bone.use_deform = deform
        bone.use_connect = False
        bone.head_radius = 0.012
        bone.tail_radius = 0.008
        bone.envelope_distance = 0.02
        # Consistent +Y along the bone; roll resolved against Blender world +Y.
        bone.align_roll(Vector((0, 1, 0)))
        return bone

    add("Root", (0, 0, 0), (0, 0, 0.18), deform=False, raw=False)
    add("Hips", (0, 0.007, 0.900), (0, 0.001, 1.027), "Root")
    add("Spine", (0, 0.001, 1.027), (0, 0.003, 1.181), "Hips")
    add("Chest", (0, 0.003, 1.181), (0, 0.001, 1.373), "Spine")
    add("Neck", (0, 0.001, 1.373), (0, -0.041, 1.457), "Chest")
    add("Head", (0, -0.041, 1.457), (0, -0.047, 1.674), "Neck")

    finger_paths = {
        "Thumb": [(0.373, -0.080, 0.853), (0.356, -0.131, 0.834),
                  (0.356, -0.162, 0.817), (0.365, -0.173, 0.809)],
        "Index": [(0.401, -0.140, 0.819), (0.414, -0.151, 0.782),
                  (0.419, -0.162, 0.759), (0.419, -0.166, 0.742)],
        "Middle": [(0.408, -0.109, 0.815), (0.423, -0.120, 0.774),
                   (0.430, -0.135, 0.744), (0.433, -0.142, 0.718)],
        "Ring": [(0.407, -0.080, 0.815), (0.423, -0.085, 0.770),
                 (0.427, -0.101, 0.738), (0.427, -0.111, 0.713)],
        "Pinky": [(0.401, -0.054, 0.814), (0.419, -0.060, 0.775),
                  (0.424, -0.062, 0.746), (0.424, -0.063, 0.721)],
    }
    for side, sign in (("L", 1), ("R", -1)):
        def mirror(value):
            return (value[0] * sign, value[1], value[2])

        add("Clavicle_" + side, mirror((0.028, 0.000, 1.354)),
            mirror((0.173, 0.009, 1.326)), "Chest")
        add("UpperArm_" + side, mirror((0.173, 0.009, 1.326)),
            mirror((0.284, 0.008, 1.089)), "Clavicle_" + side)
        add("Forearm_" + side, mirror((0.284, 0.008, 1.089)),
            mirror((0.377, -0.058, 0.893)), "UpperArm_" + side)
        add("Hand_" + side, mirror((0.377, -0.058, 0.893)),
            mirror((0.408, -0.105, 0.812)), "Forearm_" + side)
        add("Thigh_" + side, mirror((0.096, 0.010, 0.884)),
            mirror((0.139, 0.004, 0.490)), "Hips")
        add("Shin_" + side, mirror((0.139, 0.004, 0.490)),
            mirror((0.175, 0.057, 0.080)), "Thigh_" + side)
        add("Foot_" + side, mirror((0.175, 0.057, 0.080)),
            mirror((0.220, -0.060, 0.027)), "Shin_" + side)
        add("Toe_" + side, mirror((0.220, -0.060, 0.027)),
            mirror((0.241, -0.130, 0.015)), "Foot_" + side)
        for finger, path in finger_paths.items():
            parent = "Hand_" + side
            for index in range(3):
                name = f"{finger}{index + 1:02}_{side}"
                bone = add(name, mirror(path[index]), mirror(path[index + 1]), parent)
                bone.head_radius = 0.004
                bone.tail_radius = 0.003
                bone.envelope_distance = 0.005
                parent = name
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def shirt(reference, collection):
    shoulder = Vector((0.173, 0.009, 1.326))
    direction = Vector((0.111, -0.001, -0.237)).normalized()
    sleeve_end = shoulder + direction * 0.148

    def keep(value):
        p = anatomy(value)
        return (1.010 < p.z < 1.416
                and (abs(p.x) < 0.192 or p.z > 1.193))

    obj = mt.extract("Jersey_Continuous", reference, collection, keep)
    mt.trim_small_components(obj)

    def border(vertex):
        p = anatomy(vertex.co)
        if p.z < 1.09:
            vertex.co.z = cz(1.014)
        elif p.z > 1.378:
            # A deliberate elliptical neckline instead of stepped scan rows.
            angle = math.atan2((p.y + 0.012) / 0.064, p.x / 0.076)
            vertex.co = point((0.076 * math.cos(angle),
                               -0.012 + 0.064 * math.sin(angle),
                               1.426 + 0.010 * math.sin(angle)))
        elif abs(p.x) > 0.195:
            sign = 1 if p.x > 0 else -1
            plane = Vector((sleeve_end.x * sign, sleeve_end.y, sleeve_end.z))
            axis = Vector((direction.x * sign, direction.y, direction.z))
            p -= axis * (p - plane).dot(axis)
            vertex.co = point(p)

    mt.edit_garment(obj, border, 0.0125, relax=8)
    # Ease around waist/ribcage, eliminating scan muscle relief in the fabric.
    for vertex in obj.data.vertices:
        p = anatomy(vertex.co)
        if abs(p.x) < 0.18 and p.z < 1.31:
            ease = smoothstep(1.32, 1.08, p.z)
            vertex.co.x *= 1 + 0.025 * ease
            vertex.co.y = (vertex.co.y + 0.018) * (1 + 0.055 * ease) - 0.018
    mt.subdivide(obj, 1)
    obj.data.update()
    frozen_normals = [vertex.normal.copy() for vertex in obj.data.vertices]
    for vertex, normal in zip(obj.data.vertices, frozen_normals):
        p = anatomy(vertex.co)
        # Few placed tension folds; quiet, unmarked chest/back print panels.
        waist = math.exp(-((p.z - 1.073) / 0.063) ** 2)
        side = smoothstep(0.075, 0.17, abs(p.x))
        amplitude = (0.0031 * waist * math.sin(p.x * 66 + p.z * 11)
                     + 0.0022 * side * math.exp(-((p.z - 1.20) / 0.12) ** 2)
                     * math.sin(p.z * 64 + abs(p.x) * 23))
        vertex.co += normal * amplitude
    mt.recalc(obj)
    mt.reduce_surface(obj, 0.70)
    mt.set_kind(obj, 1)
    classes = {}
    for face in obj.data.polygons:
        p = anatomy(face.center)
        if abs(p.x) > 0.19 and p.z < 1.345:
            classes[face.index] = "sleeve_l" if p.x > 0 else "sleeve_r"
        else:
            classes[face.index] = "front" if face.normal.y < 0 else "back"
    regions = {
        "front": (0.020, 0.535, 0.480, 0.985),
        "back": (0.520, 0.535, 0.980, 0.985),
        "sleeve_l": (0.020, 0.018, 0.295, 0.142),
        "sleeve_r": (0.325, 0.018, 0.600, 0.142),
    }
    mt.garment_uv(obj, classes, regions)
    GARMENT_REPORT["jersey"] = {
        "connected_components": len(mt.components(obj)), "uv_panels": regions,
        "print_blank_blender_bounds": {"x": [-0.085, 0.085], "z": [cz(1.12), cz(1.32)]},
        "print_note": "Front/back are fixed UV panels; fit labels to the recorded deformed surface, not to world axes.",
    }
    KIT_PARTS.append(obj)
    return obj


def shorts(reference, collection):
    obj = mt.extract(
        "Shorts_OnePiece_Crotch", reference, collection,
        lambda value: 0.626 < anatomy(value).z < 1.044 and abs(anatomy(value).x) < 0.255)
    mt.trim_small_components(obj)

    def border(vertex):
        p = anatomy(vertex.co)
        if p.z > 0.98:
            vertex.co.z = cz(1.043)
        else:
            vertex.co.z = cz(0.638)

    mt.edit_garment(obj, border, 0.017, relax=10)
    for vertex in obj.data.vertices:
        p = anatomy(vertex.co)
        lower = smoothstep(0.91, 0.68, p.z)
        centre = (0.11 if p.x > 0 else -0.11)
        vertex.co.x = centre + (vertex.co.x - centre) * (1 + 0.18 * lower)
        vertex.co.y = -0.01 + (vertex.co.y + 0.01) * (1 + 0.10 * lower)
    mt.subdivide(obj, 1)
    frozen_normals = [vertex.normal.copy() for vertex in obj.data.vertices]
    for vertex, normal in zip(obj.data.vertices, frozen_normals):
        p = anatomy(vertex.co)
        fold = (0.0045 * math.exp(-((p.z - 0.96) / 0.08) ** 2)
                * math.sin(abs(p.x) * 79 + p.y * 29)
                + 0.003 * math.exp(-((p.z - 0.68) / 0.065) ** 2)
                * math.sin(p.y * 70 + p.x * 15))
        vertex.co += normal * fold
    mt.recalc(obj)
    mt.reduce_surface(obj, 0.70)
    mt.set_kind(obj, 2)
    classes = {face.index: ("front" if face.normal.y < 0 else "back")
               for face in obj.data.polygons}
    regions = {"front": (0.022, 0.185, 0.480, 0.487),
               "back": (0.520, 0.185, 0.978, 0.487)}
    mt.garment_uv(obj, classes, regions)
    component_count = len(mt.components(obj))
    if component_count != 1:
        raise ValueError(f"Shorts must be ONE continuous sewn volume, got {component_count}")
    GARMENT_REPORT["shorts"] = {
        "connected_components": component_count, "uv_panels": regions,
        "construction": "Continuous pelvis/gusset and two leg openings, not separate thigh tubes.",
    }
    KIT_PARTS.append(obj)
    return obj


def socks(reference, collection):
    result = []
    for side, sign, uv_region in (
            ("L", 1, (0.64, 0.017, 0.797, 0.143)),
            ("R", -1, (0.82, 0.017, 0.978, 0.143))):
        obj = mt.extract(
            "KnitSock_" + side, reference, collection,
            lambda value: 0.061 < anatomy(value).z < 0.391 and anatomy(value).x * sign > 0)

        def border(vertex):
            vertex.co.z = cz(0.390 if anatomy(vertex.co).z > 0.25 else 0.063)

        mt.edit_garment(obj, border, 0.0045, relax=2)
        mt.subdivide(obj, 1)
        mt.set_kind(obj, 3)
        mt.unwrap(obj, uv_region)
        KIT_PARTS.append(obj)
        result.append(obj)
    return result


def hair(reference, collection):
    def keep(value):
        p = anatomy(value)
        if p.z < 1.53:
            return False
        front = smoothstep(-0.015, -0.113, p.y)
        side = smoothstep(0.020, 0.07, abs(p.x))
        threshold = 1.560 + 0.069 * front + 0.020 * side
        threshold += 0.0020 * math.sin(p.x * 211 + p.y * 53)
        return p.z > threshold

    obj = mt.extract("ShortCrop_Scalp", reference, collection, keep)
    mt.trim_small_components(obj)

    def border(vertex):
        # Do not let a sampled scalp row make a 1cm sawtooth hairline.
        p = anatomy(vertex.co)
        front = smoothstep(-0.015, -0.113, p.y)
        side = smoothstep(0.020, 0.07, abs(p.x))
        p.z = 1.560 + 0.069 * front + 0.020 * side
        p.z += 0.0009 * math.sin(p.x * 211 + p.y * 53)
        vertex.co = point(p)

    mt.edit_garment(obj, border, 0.0032, relax=1)
    mt.subdivide(obj, 1)
    frozen_normals = [vertex.normal.copy() for vertex in obj.data.vertices]
    for vertex, normal in zip(obj.data.vertices, frozen_normals):
        p = anatomy(vertex.co)
        crown = smoothstep(1.600, 1.682, p.z)
        forward = smoothstep(0.035, -0.10, p.y)
        lift = 0.006 + crown * (0.009 + forward * 0.008)
        vertex.co += normal * lift
        vertex.co.x += crown * forward * 0.003
    mt.recalc(obj)
    mt.set_kind(obj, 5)
    mt.unwrap(obj, (0.015, 0.565, 0.475, 0.985))
    GEAR_PARTS.append(obj)
    tree = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    strands = []
    # A finite set of short, swept ridges in real geometry, not a floating cap.
    for index in range(25):
        x = -0.061 + (index % 9) * 0.0145
        y = -0.110 + (index // 9) * 0.042
        points = []
        for step in range(7):
            t = step / 6
            origin = Vector((x + 0.013 * t, y + 0.045 * t, 1.84))
            hit, normal, _, _ = tree.ray_cast(origin, Vector((0, 0, -1)))
            if hit is not None:
                points.append(hit + normal * (0.0008 + 0.0018 * math.sin(math.pi * t)))
        if len(points) >= 3:
            strand = mt.tube(
                f"ShortCrop_Flow_{index:02}", points, 0.00125, collection, 5, sides=5,
                radii=[0.25 + 0.75 * math.sin(math.pi * (i + .15) / len(points))
                       for i in range(len(points))])
            strands.append(strand)
    if strands:
        temporary = bpy.data.materials.new("TemporaryHair")
        # One UV area for the strand set, separate from the scalp.
        for strand in strands:
            mt.unwrap(strand)
        joined = mt.join_meshes(strands, "ShortCrop_FlowRidges", RIG, temporary)
        mt.unwrap(joined, (0.500, 0.915, 0.980, 0.983))
        GEAR_PARTS.append(joined)
    return obj


def shoe_transform(value, side):
    angle = math.radians(22)
    x, y, z = value
    sign = 1 if side == "L" else -1
    return Vector((sign * (0.175 * SCALE + math.cos(angle) * x - math.sin(angle) * y),
                   0.052 * SCALE + math.sin(angle) * x + math.cos(angle) * y, z))


def shoe_local(value, side):
    angle = math.radians(22)
    sign = 1 if side == "L" else -1
    x, y = value.x * sign - 0.175 * SCALE, value.y - 0.052 * SCALE
    return Vector((math.cos(angle) * x + math.sin(angle) * y,
                   -math.sin(angle) * x + math.cos(angle) * y, value.z))


SHOE_SECTIONS = [
    (-0.193, 0.007, 0.039), (-0.186, 0.026, 0.048),
    (-0.173, 0.043, 0.057), (-0.145, 0.053, 0.068),
    (-0.108, 0.057, 0.086), (-0.073, 0.057, 0.106),
    (-0.040, 0.053, 0.126), (-0.008, 0.049, 0.141),
    (0.023, 0.045, 0.135), (0.047, 0.042, 0.131),
    (0.065, 0.032, 0.120), (0.072, 0.010, 0.095),
]


def shoe_height(y):
    for (a, _, za), (b, _, zb) in zip(SHOE_SECTIONS, SHOE_SECTIONS[1:]):
        if a <= y <= b:
            return za + (zb - za) * (y - a) / (b - a)
    return 0.08


def shoes(collection):
    by_side = {}
    for side in ("L", "R"):
        parts = []
        vertices, faces = [], []
        radial = 28
        for index, (y, width, height) in enumerate(SHOE_SECTIONS):
            for j in range(radial):
                angle = j * 2 * math.pi / radial
                local = (math.cos(angle) * width, y,
                         0.026 + (math.sin(angle) + 1) * 0.5 * (height - 0.026))
                vertices.append(shoe_transform(local, side))
            if index:
                for j in range(radial):
                    k = (j + 1) % radial
                    faces.append(((index - 1) * radial + j, (index - 1) * radial + k,
                                  index * radial + k, index * radial + j))
        faces += [tuple(reversed(range(radial))),
                  tuple((len(SHOE_SECTIONS) - 1) * radial + j for j in range(radial))]
        upper = mt.mesh_object("IndoorShoe_Upper_" + side, vertices, faces, collection, 6)
        mt.recalc(upper)
        # The collar is a genuine opening into a heel cup, with a sock inside.
        bm = bmesh.new()
        bm.from_mesh(upper.data)
        remove = [v for v in bm.verts
                  if (shoe_local(v.co, side).y > -0.018
                      and shoe_local(v.co, side).z > 0.105
                      and abs(shoe_local(v.co, side).x) < 0.036)]
        bmesh.ops.delete(bm, geom=remove, context="VERTS")
        bm.to_mesh(upper.data)
        bm.free()
        mt.subdivide(upper, 1)
        mt.reduce_surface(upper, 0.48)
        mt.set_kind(upper, 6)
        parts.append(upper)
        # Low, rounded gum rubber sole, not a cleat or floating ellipsoid.
        outline = []
        for y, width, _ in SHOE_SECTIONS:
            outline.append((width + 0.0028, y))
        for y, width, _ in reversed(SHOE_SECTIONS):
            outline.append((-width - 0.0028, y))
        vertices, faces = [], []
        layers = ((0.000, 0.94), (0.004, 1.0), (0.017, 1.0), (0.025, 0.97))
        count = len(outline)
        for layer, (height, width_factor) in enumerate(layers):
            for x, y in outline:
                spring = 0.0045 * smoothstep(-0.128, -0.193, y)
                vertices.append(shoe_transform((x * width_factor, y, height + spring), side))
            if layer:
                for i in range(count):
                    j = (i + 1) % count
                    faces.append(((layer - 1) * count + i, (layer - 1) * count + j,
                                  layer * count + j, layer * count + i))
        faces.extend((tuple(reversed(range(count))),
                      tuple(3 * count + i for i in range(count))))
        sole = mt.mesh_object("IndoorShoe_GumSole_" + side, vertices, faces, collection, 7)
        mt.recalc(sole)
        bevel = sole.modifiers.new("Rubber edge bevel", "BEVEL")
        bevel.width = 0.0017
        bevel.segments = 2
        mt.apply_modifier(sole, bevel)
        mt.set_kind(sole, 7)
        parts.append(sole)
        # Sewn toe guard on the same last. One broad original panel, no branding.
        bm = bmesh.new()
        bm.from_mesh(upper.data)
        sign = 1 if side == "L" else -1
        bmesh.ops.bisect_plane(
            bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
            dist=1e-6, plane_co=shoe_transform((0, -0.112, 0), side),
            plane_no=Vector((-sign * math.sin(math.radians(22)),
                             math.cos(math.radians(22)), 0)),
            clear_outer=True, clear_inner=False)
        bmesh.ops.bisect_plane(
            bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
            dist=1e-6, plane_co=Vector((0, 0, 0.033)),
            plane_no=Vector((0, 0, -1)), clear_outer=True, clear_inner=False)
        panel_mesh = bpy.data.meshes.new("ToeGuard_" + side + "_Mesh")
        bm.to_mesh(panel_mesh)
        bm.free()
        panel = bpy.data.objects.new("IndoorShoe_ToeGuard_" + side, panel_mesh)
        collection.objects.link(panel)
        frozen_normals = [vertex.normal.copy() for vertex in panel.data.vertices]
        for vertex, normal in zip(panel.data.vertices, frozen_normals):
            vertex.co += normal * 0.0014
        mt.set_kind(panel, 10)
        mt.smooth(panel)
        parts.append(panel)
        parts += mt.boundary_thread(upper, collection, radius=0.0016, kind=10)
        parts += mt.boundary_thread(panel, collection, radius=0.0007, kind=8)
        # Five crossed lace stations following the instep's actual height.
        for station in range(5):
            y = -0.016 - station * 0.019
            for direction in (-1, 1):
                points = []
                for step in range(6):
                    t = step / 5
                    x = direction * (0.020 - 0.040 * t)
                    yy = y - 0.013 * t
                    zz = shoe_height(yy) - 0.005 + 0.005 * math.sin(t * math.pi)
                    points.append(shoe_transform((x, yy, zz), side))
                parts.append(mt.tube(
                    f"IndoorShoe_Lace_{side}_{station}_{direction}", points,
                    0.00115, collection, 8, sides=5))
        for loop_side in (-1, 1):
            points = []
            for step in range(13):
                t = step / 12 * 2 * math.pi
                local = (loop_side * (0.004 + 0.011 * (1 - math.cos(t))),
                         -0.026 + 0.009 * math.sin(t),
                         shoe_height(-0.026) + 0.006 + 0.002 * math.sin(t))
                points.append(shoe_transform(local, side))
            parts.append(mt.tube("IndoorShoe_LaceLoop_" + side, points,
                                 0.0010, collection, 8, sides=5))
        by_side[side] = parts
    return by_side


def weight_shoe(side):
    def override(position, weights):
        local = shoe_local(position, side)
        toe = smoothstep(-0.061, -0.160, local.y)
        return {"Foot_" + side: 1 - toe, "Toe_" + side: toe}
    return override


def make_wardrobe(reference, collection, source_weights):
    jersey = shirt(reference, collection)
    pant = shorts(reference, collection)
    sock_parts = socks(reference, collection)
    pieces = [(jersey, "jersey", (0.022, 0.502, 0.420, 0.523)),
              (pant, "shorts", (0.440, 0.502, 0.795, 0.523)),
              (sock_parts[0], "sock", (0.815, 0.502, 0.890, 0.523)),
              (sock_parts[1], "sock", (0.910, 0.502, 0.978, 0.523))]
    report = {}
    for obj, garment, _ in pieces:
        flipped = garments.orient_garment(obj, source_weights[2])
        fitting = garments.fit_clearance(obj, source_weights[2], garment)
        garments.anchor_waist(obj, garment)
        report[obj.name] = {"outward_component_winding_corrected": flipped,
                            "anatomical_fit": fitting}
    report["waist_overlap"] = garments.separate_shirt_from_waist(jersey, pant)
    for obj, garment, rectangle in pieces:
        report[obj.name]["connected_turnback"] = garments.connected_turnbacks(
            obj, garment, rectangle)
        mt.attach(obj, RIG)
        mt.limit_weights(obj)
    GARMENT_REPORT["r3_tailoring"] = report
    return jersey, pant, sock_parts


def runtime_skin(reference, collection):
    direction = Vector((0.111, -0.001, -0.237))
    origin = Vector((0.173, 0.009, 1.326))

    def keep(value):
        p = anatomy(value)
        if p.z < 0.365:
            return False
        if 0.674 < p.z < 1.041 and abs(p.x) < 0.255:
            return False
        if 1.028 < p.z < 1.382 and abs(p.x) < 0.179:
            return False
        q = Vector((abs(p.x), p.y, p.z))
        t = (q - origin).dot(direction) / direction.length_squared
        if abs(p.x) > 0.157 and 1.20 < p.z < 1.40 and t < 0.37:
            return False
        return True

    obj = mt.extract("AthleteSkinMesh", reference, collection, keep)
    mt.trim_small_components(obj, minimum=3)
    mt.set_kind(obj, 0)
    mt.pack_original_uv(obj)
    mt.smooth(obj)
    return obj


def mesh_stats(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    deform = {g.index for g in obj.vertex_groups if g.name != "Root"}
    influences, errors, unused = [], [], []
    for vertex in mesh.vertices:
        weights = [g.weight for g in vertex.groups if g.group in deform and g.weight > 1e-5]
        influences.append(len(weights))
        errors.append(abs(sum(weights) - 1))
        if not weights:
            unused.append(vertex.index)
    return {
        "name": obj.name, "vertices": len(mesh.vertices), "triangles": len(mesh.loop_triangles),
        "polygons": len(mesh.polygons), "connected_components": len(mt.components(obj)),
        "materials": [m.name for m in mesh.materials],
        "max_influences": max(influences), "unweighted_vertices": len(unused),
        "max_normalization_error": max(errors), "uv_layers": [u.name for u in mesh.uv_layers],
        "color_attributes": [{"name": a.name, "type": a.data_type, "domain": a.domain}
                             for a in mesh.color_attributes],
        "bounds_blender_m": [[min(v.co[i] for v in mesh.vertices),
                              max(v.co[i] for v in mesh.vertices)] for i in range(3)],
    }


def skeleton_report(rig):
    conversion = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
    bones = []
    for bone in rig.data.bones:
        parent_matrix = bone.parent.matrix_local if bone.parent else Matrix.Identity(4)
        local = parent_matrix.inverted() @ bone.matrix_local
        bones.append({
            "name": bone.name, "parent": bone.parent.name if bone.parent else None,
            "deform": bone.use_deform, "length_m": bone.length,
            "head_blender_m": list(bone.head_local), "tail_blender_m": list(bone.tail_local),
            "head_gltf_m": list((conversion @ bone.head_local.to_4d()).to_3d()),
            "tail_gltf_m": list((conversion @ bone.tail_local.to_4d()).to_3d()),
            "rest_armature_matrix_rows": [list(row) for row in bone.matrix_local],
            "rest_parent_local_matrix_rows": [list(row) for row in local],
        })
    report = {
        "axes": {"authoring_up": "+Z", "authoring_front": "-Y",
                 "gltf_up": "+Y", "gltf_front": "+Z",
                 "bone_longitudinal_axis": "+Y in Blender bone-local space",
                 "matrix_format": "Row-major JSON arrays; column-vector multiplication.",
                 "blender_to_gltf_rows": [list(row) for row in conversion]},
        "rest_pose": "Relaxed source A pose, outward feet; not a motion clip.",
        "root_motion": False, "bone_count": len(bones),
        "deform_bone_count": sum(b["deform"] for b in bones),
        "bones": bones,
        "presentation_adapter": {
            "root_facing": "Coordinator applies a single root yaw for MatchSnapshot -Z. Do not rotate individual meshes.",
            "hand_target": "PALM center, not wrist; use contact_contract.palms",
            "targets_old": {"hip_y": 0.89, "shoulder_abs_x": 0.215, "shoulder_y": 1.40,
                            "ankle_y": 0.08, "leg_segments": [0.415, 0.415],
                            "arm_segments": [0.285, 0.285]},
            "actual_lengths_left": {name: rig.data.bones[name + "_L"].length
                                    for name in ("UpperArm", "Forearm", "Thigh", "Shin", "Foot", "Toe")},
            "authority": "Never change physics/collisions to force these artistic proportions.",
        },
    }
    report["contact_contract"] = contacts.measure_contact_contract(
        rig, bpy.data.objects["AthleteSkinMesh"], bpy.data.objects["AthleteGearMesh"])
    return report


def main():
    global RIG
    if hashlib.sha256(BASE.read_bytes()).hexdigest() != BASE_HASH:
        raise ValueError("Source .blend SHA256 differs from the inspected CC0 bundle")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.users == 0 or collection.name == "Collection":
            bpy.data.collections.remove(collection)
    runtime = bpy.data.collections.new("CourtAthlete_Runtime")
    authoring = bpy.data.collections.new("CourtAthlete_Authoring_CC0")
    bpy.context.scene.collection.children.link(runtime)
    bpy.context.scene.collection.children.link(authoring)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.preferences.filepaths.save_version = 0  # Factory session only.
    with bpy.data.libraries.load(str(BASE), link=False) as (data_from, data_to):
        data_to.objects = ["GEO-body_male_realistic",
                           "GEO-body_male_realistic.eye.L", "GEO-body_male_realistic.eye.R"]
    high, eye_left, eye_right = data_to.objects
    source_mesh_digest = hashlib.sha256()
    for vertex in high.data.vertices:
        source_mesh_digest.update(struct.pack("<3f", *vertex.co))
    for face in high.data.polygons:
        source_mesh_digest.update(struct.pack("<I", len(face.vertices)))
        source_mesh_digest.update(struct.pack("<" + "I" * len(face.vertices), *face.vertices))
    original_x = high.location.x
    high.name = "CC0_DanUlrich_RealisticMale_High"
    authoring.objects.link(high)
    high.location = (0, 0, LIFT)
    high.scale = (SCALE,) * 3
    high.animation_data_clear()
    for modifier in high.modifiers:
        if modifier.type != "MULTIRES":
            raise ValueError("Unexpected downloaded modifier; review rather than execute")
        modifier.levels = 3
        modifier.render_levels = 3
    high.hide_render = True
    high.hide_set(True)
    reference_mesh = high.data.copy()
    reference_mesh.name = "AnatomicalWeightReference"
    reference = bpy.data.objects.new("AnatomicalWeightReference", reference_mesh)
    authoring.objects.link(reference)
    # Mesh-local coordinates are normalized once, before rigging.
    for vertex in reference.data.vertices:
        vertex.co = point(vertex.co)
    reference.data.update()
    RIG = make_rig(runtime)
    mt.active(reference)
    RIG.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    print("BIND: original continuous anatomy, bone heat, 52 actual bones", flush=True)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    mt.limit_weights(reference)
    reference_stats = mesh_stats(reference)
    if reference_stats["unweighted_vertices"]:
        raise ValueError(f"Bone heat left {reference_stats['unweighted_vertices']} unweighted vertices")
    source_weights = mt.weight_reference(reference)
    print("MODEL: jersey, one-piece gusseted shorts and socks", flush=True)
    jersey, pant, sock_parts = make_wardrobe(reference, runtime, source_weights)
    print("MODEL: short natural crop, eyes, indoor shoes and laces", flush=True)
    hair(reference, runtime)
    shoe_parts = shoes(runtime)
    for side, parts in shoe_parts.items():
        for item in parts:
            mt.unwrap(item)
            mt.transfer_weights(item, source_weights, RIG, override=weight_shoe(side))
        temp = bpy.data.materials.new("TemporaryShoe_" + side)
        joined = mt.join_meshes(parts, "IndoorShoe_" + side, RIG, temp)
        mt.unwrap(joined, (0.015, 0.02, 0.485, 0.53) if side == "L"
                  else (0.515, 0.02, 0.985, 0.53))
        GEAR_PARTS.append(joined)
    for eye, side, rectangle in (
            (eye_left, "L", (0.53, 0.57, 0.72, 0.79)),
            (eye_right, "R", (0.77, 0.57, 0.96, 0.79))):
        # Appended objects are not linked/evaluated: matrix_world can still be
        # identity. Compose the reviewed local transform explicitly.
        old_matrix = Matrix.LocRotScale(eye.location, eye.rotation_euler.to_quaternion(), eye.scale)
        mesh = eye.data.copy()
        for vertex in mesh.vertices:
            p = old_matrix @ vertex.co
            p.x -= original_x
            vertex.co = point(p)
        obj = bpy.data.objects.new("NaturalEye_" + side, mesh)
        runtime.objects.link(obj)
        mt.set_kind(obj, 9)
        mt.reduce_surface(obj, 0.45)
        mt.unwrap(obj, rectangle)
        GEAR_PARTS.append(obj)
    # Restrained eyebrow silhouettes on the brow ridge; no image-derived face.
    brow_parts = []
    for side, sign in (("L", 1), ("R", -1)):
        points = []
        for i in range(9):
            t = i / 8
            points.append(point((sign * (0.016 + 0.039 * t),
                                 -0.140 + 0.014 * t,
                                 1.599 + 0.008 * math.sin(t * math.pi) - 0.004 * t)))
        brow = mt.tube("Brow_" + side, points, 0.0017, runtime, 11, sides=5,
                       radii=[0.4, 0.8, 1, 1, 1, 0.9, 0.7, 0.5, 0.15])
        mt.unwrap(brow, (0.53, 0.825, 0.72, 0.88) if side == "L"
                  else (0.77, 0.825, 0.96, 0.88))
        brow_parts.append(brow)
        GEAR_PARTS.append(brow)
    skin = runtime_skin(reference, runtime)
    mt.attach(skin, RIG)
    for obj in KIT_PARTS:
        mt.attach(obj, RIG)
        mt.limit_weights(obj)
    for obj in GEAR_PARTS:
        if not obj.name.startswith("IndoorShoe_"):
            mt.transfer_weights(obj, source_weights, RIG, fixed="Head")
    materials = {name: bpy.data.materials.new(name)
                 for name in ("AthleteSkin", "AthleteKit", "AthleteGear")}
    skin.data.materials.clear()
    skin.data.materials.append(materials["AthleteSkin"])
    kit = mt.join_meshes(KIT_PARTS, "AthleteKitMesh", RIG, materials["AthleteKit"])
    gear = mt.join_meshes(GEAR_PARTS, "AthleteGearMesh", RIG, materials["AthleteGear"])
    meshes = [skin, kit, gear]
    for obj in meshes:
        mt.limit_weights(obj)
        if obj != kit:
            mt.recalc(obj)
            mt.smooth(obj)
    reversed_skin_faces = mt.orient_open_skin(skin, source_weights)
    print("ANATOMICAL_WINDING restored", reversed_skin_faces, "open-surface faces", flush=True)
    pre_bake_stats = [mesh_stats(obj) for obj in meshes]
    print("PRE_BAKE_GEOMETRY", json.dumps(pre_bake_stats), flush=True)
    if sum(s["triangles"] for s in pre_bake_stats) > 60000:
        raise ValueError("Geometry exceeds 60k budget; stop before further baking")
    reference.hide_render = True
    reference.hide_set(True)
    print("MAPS: own neutral albedo, data mask, micro normals and roughness", flush=True)
    map_reports = {}
    for obj, prefix, resolution in ((skin, "skin", 2048), (kit, "kit", 2048), (gear, "gear", 1024)):
        result = atlas.rasterize(obj, MAPS, prefix, resolution, EYE_Z)
        atlas.setup_material(obj.data.materials[0], MAPS, prefix)
        map_reports[prefix] = result
        print("RASTER", prefix, {k: v for k, v in result.items() if k != "orm_work"}, flush=True)
    print("BAKE: real source multiresolution -> skin tangent +Y normal, CPU", flush=True)
    map_reports["skin"]["normal_encoding"] = atlas.bake_scan_normal(
        skin, high, materials["AthleteSkin"], MAPS / "skin_normal.png")
    for obj, prefix in ((skin, "skin"), (kit, "kit"), (gear, "gear")):
        print("BAKE: local AO", prefix, "CPU; 1K master", flush=True)
        atlas.bake_local_ao(obj, obj.data.materials[0], MAPS / f"{prefix}_ao.png",
                            map_reports[prefix].pop("orm_work"))
        atlas.setup_material(obj.data.materials[0], MAPS, prefix)
    authoring.hide_render = True
    authoring.hide_viewport = True
    for obj in list(bpy.data.objects):
        if obj not in meshes and obj != RIG and obj not in (high, reference):
            bpy.data.objects.remove(obj, do_unlink=True)
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)
        else:
            image.filepath = "//maps/" + Path(bpy.path.abspath(image.filepath)).name
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)
    bpy.context.scene.render.engine = "CYCLES"
    bpy.context.scene.cycles.device = "CPU"
    bpy.context.scene.view_settings.view_transform = "AgX"
    bpy.context.scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.context.scene["asset_revision"] = REVISION
    bpy.context.scene["inspection_status"] = "Source candidate, not Godot evidence, not artistically approved."
    integration_checks = driver_contract.apply_driver_contract(
        RIG, skin, kit, gear, MAPS / "kit_mask.png")
    bpy.context.scene["integration_contract_version"] = 2
    map_links = atlas.runtime_map_links(MAPS)
    if not all(map_links.values()):
        raise ValueError(f"Runtime map paths are invalid: {map_links}")
    stats = [mesh_stats(obj) for obj in meshes]
    total_triangles = sum(s["triangles"] for s in stats)
    if total_triangles > 60000:
        raise ValueError(f"Visible athlete exceeds 60k hard budget: {total_triangles}")
    if any(s["unweighted_vertices"] or s["max_influences"] > 4
           or s["max_normalization_error"] > 1e-5 for s in stats):
        raise ValueError("Runtime mesh weights violate the integration contract")
    bones = skeleton_report(RIG)
    provenance = {
        "bundle": "Human Base Meshes v1.4.1",
        "official_page": "https://www.blender.org/download/demo-files/#assets",
        "official_archive": "https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip",
        "archive_bytes": 50643039, "archive_sha256": ZIP_HASH,
        "blend_member": "human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend",
        "blend_bytes": 49420489, "blend_sha256": BASE_HASH,
        "chosen_collection": "Body Male - Realistic", "author": "Dan Ulrich",
        "publisher": "Blender Studio and community contributions",
        "asset_license": "CC0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "license_scope": "CC0-1.0 applies to the upstream Body Male - Realistic base. No general reuse license is assigned to the project's own code/art adaptation; see THIRD_PARTY_NOTICES.md.",
        "asset_description_verbatim": "Realistic scan data model with multiresolution details",
        "chosen_objects": ["GEO-body_male_realistic",
                           "GEO-body_male_realistic.eye.L", "GEO-body_male_realistic.eye.R"],
        "body_mesh_datablock_original": "female_v006lowresUV",
        "body_mesh_fingerprint": {"format": "float32 LE xyz vertices, then uint32 LE face lengths/indices",
                                  "sha256": source_mesh_digest.hexdigest()},
        "license_evidence": [
            "Official page: Human Base Meshes v1.4.1, Blender Studio and community, CC0, requires 4.2+.",
            "Embedded README: All provided assets are public domain under the CC0 license.",
            "Body Male - Realistic AssetMetaData: author Dan Ulrich, license CC0."
        ],
        "upstream_text_discrepancy": "Unrelated embedded 'License' text mentions Rain Rig CC-BY 4.0. No Rain Rig, scene, script or animation is used; chosen collection explicitly declares CC0. Preserved for independent provenance review.",
        "upstream_has_rig_or_actions": False,
        "downloaded_code_executed": False,
        "adaptation": ["One scaled anatomical base with original face/ears/fingers retained",
                       "Own garment shaping, gusseted shorts, socks, crop, shoes, seams and laces",
                       "Own 54-bone humanoid rig (51 deforming; Root/Palm_L/Palm_R helpers), skin weights, UV atlases and baked PBR maps",
                       "Linear COLOR0 kit weights transferred from the authored PNG mask"],
        "private_reference": "User quality reference inspected locally only, not copied, bundled or uploaded.",
        "api_cost": 0,
    }
    (HERE / "provenance.json").write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n",
                                         encoding="utf-8")
    mt.active(RIG)
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / "court_athlete.blend"), compress=True)
    source_hash = hashlib.sha256((HERE / "court_athlete.blend").read_bytes()).hexdigest()
    bones["contact_contract"]["source_sha256"] = source_hash
    contacts.save_json(HERE / "rig_manifest.json", bones)
    manifest = {
        "revision": REVISION, "status": "r3_source_candidate_awaiting_final_self_inspection",
        "blender": bpy.app.version_string, "source": "court_athlete.blend",
        "source_sha256": source_hash,
        "visible_triangles": total_triangles,
        "visible_vertices": sum(s["vertices"] for s in stats),
        "bone_count": bones["bone_count"], "deform_bone_count": bones["deform_bone_count"],
        "material_count": 3, "materials": list(materials), "meshes": stats,
        "integration_contract_version": 2,
        "driver_contract_adaptation": {"validation": integration_checks, "game_exported": False},
        "garments": GARMENT_REPORT, "map_rasterization": map_reports,
        "textures": [atlas.file_record(path) for path in sorted(MAPS.glob("*.png"))],
        "texture_contract": {
            "albedo": "sRGB, neutral kit albedo; no baked lighting",
            "normal": "Tangent +Y/OpenGL, Non-Color",
            "orm": "linear R=restrained local AO; G=roughness; B=0 metallic",
            "kit_mask": "Linear data COLOR0 -> glTF COLOR_0, RGBA normalized; never opacity/albedo.",
            "kit_mask_binding": bones["contact_contract"]["kit_mask_binding"],
            "ao_master": "1K actual CPU local-AO bake, 6.5cm distance; packed into ORM",
        },
        "export_destination_only_after_permission": "game/assets/athletes/court_athlete/court_athlete.glb",
        "exported_to_game": False, "game_tested": False,
        "contact_contract": {
            "file": "rig_manifest.json", "key": "contact_contract", "schema_version": 2,
            "source_sha256": source_hash,
            "validation": "Run contact_locators.py --update-manifests for rest/posed locator checks.",
        },
        "animations": [],
        "limitations": [
            "R3 needs its own Godot import and final integrated review; R2 evidence is not R3 acceptance.",
            "Rig/skin deformation must be inspected in full-body stance and flexion before hand-off.",
            "Final R3 tailoring addresses R2 clothing penetration; real posed contact/coverage still needs integrated review.",
            "Inspect atlas overlap, especially sewn edges, in the native material adapter.",
            "No goalkeeper-specific clothing or animations, LODs, face rig, cloth/hair simulation.",
            "Camera/current-target adaptation belongs to coordinator, never physics/collisions.",
        ],
        "reproduction_command": "blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art/source/athletes/court_athlete/build_athlete.py",
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                                       encoding="utf-8")
    print("SOURCE_READY", json.dumps({key: manifest[key] for key in
                                    ("visible_triangles", "visible_vertices", "bone_count",
                                     "deform_bone_count", "material_count", "source_sha256")}), flush=True)


if __name__ == "__main__":
    main()
