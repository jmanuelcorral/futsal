"""R3 tailoring: anatomical clearance, a stable overlap and connected turnbacks."""
from __future__ import annotations

import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import mesh_tools as mt


def boundary_loops(mesh):
    uses = {}
    for face in mesh.polygons:
        vertices = list(face.vertices)
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            uses.setdefault(tuple(sorted((a, b))), []).append((a, b))
    directed = [edges[0] for edges in uses.values() if len(edges) == 1]
    following = {}
    for a, b in directed:
        if a in following:
            raise ValueError("Garment boundary is not an oriented manifold loop")
        following[a] = b
    loops = []
    while following:
        start = min(following)
        current = start
        loop = []
        while True:
            loop.append(current)
            if current not in following:
                raise ValueError("Garment boundary is open or inconsistent")
            current = following.pop(current)
            if current == start:
                break
        if len(loop) < 3:
            raise ValueError("Degenerate garment opening")
        loops.append(loop)
    return loops


def opening_planes(mesh, loops, garment):
    result = {}
    for loop in loops:
        centre = sum((mesh.vertices[i].co for i in loop), Vector()) / len(loop)
        if garment == "jersey" and abs(centre.x) > 0.18:
            sign = 1 if centre.x > 0 else -1
            normal = Vector((0.111 * sign, -0.001, -0.237)).normalized()
        elif garment == "jersey" and centre.z > 1.38:
            normal = Vector((0, -0.010 / 0.064, 1)).normalized()
        else:
            normal = Vector((0, 0, 1))
        for index in loop:
            result[index] = (centre, normal)
    return result


def clearance_report(obj, tree, indices=None):
    indices = range(len(obj.data.vertices)) if indices is None else indices
    values = []
    for index in indices:
        position = obj.data.vertices[index].co
        hit, normal, _, _ = tree.find_nearest(position)
        if hit is None:
            raise ValueError("Anatomical clearance query found no surface")
        values.append((position - hit).dot(normal))
    return {"vertices": len(values), "min_signed_m": min(values),
            "inside_over_1mm": sum(value < -0.001 for value in values)}


def orient_garment(obj, tree):
    agreement = sum(face.area * face.normal.dot(tree.find_nearest(face.center)[1])
                    for face in obj.data.polygons)
    if agreement < 0:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    return agreement < 0


def fit_clearance(obj, tree, garment):
    mesh = obj.data
    loops = boundary_loops(mesh)
    expected = {"jersey": 4, "shorts": 3, "sock": 2}[garment]
    if len(loops) != expected:
        raise ValueError(f"{garment}: expected {expected} real openings, got {len(loops)}")
    planes = opening_planes(mesh, loops, garment)
    before = clearance_report(obj, tree)
    original = [vertex.co.copy() for vertex in mesh.vertices]
    hem_height = min(vertex.co.z for vertex in mesh.vertices)

    def required(position):
        if garment == "jersey":
            lower = max(0.0, min(1.0, (hem_height + 0.16 - position.z) / 0.11))
            # The anatomical A-pose leaves a narrow arm/torso gap. Its sewn
            # axillary fold needs fabric-scale ease, not two 7 mm air layers.
            if 0.15 < abs(position.x) < 0.205 and 1.19 < position.z < 1.28:
                return 0.0035
            return 0.007 + 0.022 * lower
        return 0.007 if garment == "shorts" else 0.0055

    for index, (centre, normal) in planes.items():
        mesh.vertices[index].co -= normal * (mesh.vertices[index].co - centre).dot(normal)
    for _ in range(8):
        maximum_error = 0.0
        for vertex in mesh.vertices:
            hit, normal, _, _ = tree.find_nearest(vertex.co)
            if hit is None:
                raise ValueError("Missing anatomical surface while fitting garment")
            error = required(vertex.co) - (vertex.co - hit).dot(normal)
            maximum_error = max(maximum_error, error)
            if error <= 0.00005:
                continue
            direction = normal.copy()
            if vertex.index in planes:
                plane_normal = planes[vertex.index][1]
                direction -= plane_normal * direction.dot(plane_normal)
            efficiency = direction.dot(normal)
            if efficiency < 0.05:
                raise ValueError(f"{garment}: clearance cannot follow the opening plane")
            vertex.co += direction * (error / efficiency)
            if (vertex.co - original[vertex.index]).length > 0.06:
                raise ValueError(f"{garment}: fitting would move fabric more than 6 cm")
        if maximum_error <= 0.00005:
            break
    mesh.update()
    after = clearance_report(obj, tree)
    shortfall = max(required(vertex.co) - (
        vertex.co - tree.find_nearest(vertex.co)[0]).dot(tree.find_nearest(vertex.co)[1])
        for vertex in mesh.vertices)
    if after["inside_over_1mm"] or shortfall > 0.00015:
        raise ValueError(f"{garment}: anatomical penetration remains after fitting: {after}")
    return {"before": before, "after": after, "openings": len(loops),
            "maximum_clearance_shortfall_m": shortfall,
            "fit_policy": ("7 mm jersey ease, 3.5 mm inside the narrow axillary fold, "
                           "up to 29 mm at the loose waist; shorts 7 mm, socks 5.5 mm"),
            "max_vertex_displacement_m": max(
                (v.co - original[v.index]).length for v in mesh.vertices)}


def anchor_waist(obj, garment):
    if garment not in ("jersey", "shorts"):
        return
    height = (min if garment == "jersey" else max)(v.co.z for v in obj.data.vertices)
    hips = obj.vertex_groups.get("Hips")
    if hips is None:
        raise ValueError("Inherited garment weights are missing Hips")
    for vertex in obj.data.vertices:
        distance = vertex.co.z - height if garment == "jersey" else height - vertex.co.z
        amount = max(0.0, min(1.0, (0.10 - distance) / 0.065))
        if amount == 0:
            continue
        weights = {entry.group: entry.weight * (1 - amount) for entry in vertex.groups}
        weights[hips.index] = weights.get(hips.index, 0.0) + amount
        for old in list(vertex.groups):
            obj.vertex_groups[old.group].remove([vertex.index])
        for group, weight in weights.items():
            if weight > 0:
                obj.vertex_groups[group].add([vertex.index], weight, "REPLACE")
    mt.limit_weights(obj)


def separate_shirt_from_waist(jersey, shorts, clearance=0.009):
    shorts.data.calc_loop_triangles()
    tree = BVHTree.FromPolygons(
        [v.co for v in shorts.data.vertices],
        [t.vertices for t in shorts.data.loop_triangles], all_triangles=True)
    top = max(v.co.z for v in shorts.data.vertices)
    affected = [v.index for v in jersey.data.vertices if v.co.z < top + 0.01]
    if not affected:
        raise ValueError("Jersey has no overlap with the shorts waist")
    for _ in range(6):
        worst = 0.0
        for index in affected:
            vertex = jersey.data.vertices[index]
            hit, normal, _, _ = tree.find_nearest(vertex.co)
            error = clearance - (vertex.co - hit).dot(normal)
            worst = max(worst, error)
            if error <= 0.00005:
                continue
            direction = Vector((normal.x, normal.y, 0))
            efficiency = direction.dot(normal)
            if efficiency < 0.05:
                # Above the open waist, the nearest surface may be its flat rim.
                if vertex.co.z >= top:
                    continue
                raise ValueError("Cannot resolve the cloth overlap laterally")
            vertex.co += direction * (error / efficiency)
        if worst < 0.00005:
            break
    jersey.data.update()
    tested = [index for index in affected if jersey.data.vertices[index].co.z < top - 0.001]
    gaps = [(jersey.data.vertices[index].co - tree.find_nearest(
        jersey.data.vertices[index].co)[0]).dot(tree.find_nearest(
            jersey.data.vertices[index].co)[1]) for index in tested]
    if not gaps or min(gaps) < clearance - 0.00015:
        raise ValueError("The jersey/shorts waist overlap did not reach its stated clearance")
    return {"target_lateral_gap_m": clearance, "overlap_vertices": len(affected),
            "minimum_tested_gap_m": min(gaps),
            "shirt_hem_z_m": min(v.co.z for v in jersey.data.vertices),
            "shorts_waist_z_m": top}


def connected_turnbacks(obj, garment, rectangle, thickness=0.0014, depth=0.012):
    mesh = obj.data
    loops = boundary_loops(mesh)
    before_vertices = len(mesh.vertices)
    mesh.calc_loop_triangles()
    outer = BVHTree.FromPolygons([v.co for v in mesh.vertices],
                                [t.vertices for t in mesh.loop_triangles], all_triangles=True)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    original_vertices = list(bm.verts)
    uv_layer = bm.loops.layers.uv.active
    kinds = bm.faces.layers.int["surface_kind"]
    hem_layer = bm.faces.layers.int.new("hem_surface")
    deform = bm.verts.layers.deform.active
    if uv_layer is None or deform is None:
        raise ValueError("Garment turnbacks require UVs and inherited skin weights")
    left, bottom, right, top = rectangle
    width = (right - left) / len(loops)
    reports = []
    for loop_index, loop in enumerate(loops):
        centre_z = sum(mesh.vertices[i].co.z for i in loop) / len(loop)
        collar = garment == "jersey" and centre_z > 1.38
        ring0 = [original_vertices[i] for i in loop]
        rings = [ring0, [], []]
        lengths = [(mesh.vertices[b].co - mesh.vertices[a].co).length
                   for a, b in zip(loop, loop[1:] + loop[:1])]
        perimeter = sum(lengths)
        if perimeter <= 0:
            raise ValueError("Zero-length garment opening")
        for position, index in enumerate(loop):
            vertex = mesh.vertices[index]
            normal = vertex.normal.normalized()
            tangent = (mesh.vertices[loop[(position + 1) % len(loop)]].co
                       - mesh.vertices[loop[position - 1]].co).normalized()
            # Directed boundary edges keep the original fabric on their left.
            # This conormal also works at tessellated ears without an interior
            # vertex neighbour, unlike a neighbour-centroid shortcut.
            inside = normal.cross(tangent)
            if inside.length < 1e-6:
                raise ValueError("Degenerate garment return direction")
            inside.normalize()
            target, target_normal, _, _ = outer.find_nearest(vertex.co + inside * depth)
            coordinates = (vertex.co - normal * thickness,
                           target - target_normal * thickness)
            for ring, coordinate in zip(rings[1:], coordinates):
                added = bm.verts.new(coordinate)
                for group, weight in ring0[position][deform].items():
                    added[deform][group] = weight
                ring.append(added)
        progress = 0.0
        u_start = left + loop_index * width + 0.001
        u_width = width - 0.002
        for index, length in enumerate(lengths):
            following = (index + 1) % len(loop)
            u0 = u_start + u_width * progress / perimeter
            progress += length
            u1 = u_start + u_width * progress / perimeter
            for strip in range(2):
                face = bm.faces.new((
                    rings[strip][following], rings[strip][index],
                    rings[strip + 1][index], rings[strip + 1][following]))
                face[kinds] = 4 if collar and strip == 0 else {"jersey": 1, "shorts": 2, "sock": 3}[garment]
                face[hem_layer] = strip + 1
                face.smooth = strip == 1
                v0 = bottom + 0.001 + (top - bottom - 0.002) * strip / 2
                v1 = bottom + 0.001 + (top - bottom - 0.002) * (strip + 1) / 2
                for corner, uv in zip(face.loops, ((u1, v0), (u0, v0), (u0, v1), (u1, v1))):
                    corner[uv_layer].uv = uv
        reports.append({"boundary_vertices": len(loop), "perimeter_m": perimeter,
                        "collar_accent": collar})
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    mt.limit_weights(obj)
    if len(boundary_loops(mesh)) != len(loops) or len(mt.components(obj)) != 1:
        raise ValueError("Connected turnback changed the garment's sewn continuity")
    return {"openings": reports, "thickness_m": thickness, "return_depth_m": depth,
            "added_vertices": len(mesh.vertices) - before_vertices,
            "connected_components": 1, "independent_trim_objects": 0}
