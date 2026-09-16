"""Local mesh/UV/skinning authoring helpers; no network or downloaded code."""
from __future__ import annotations

from math import pi
import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def active(obj):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def barycentric_double(point, a, b, c):
    # Small skin triangles need double intermediates, not float32 cancellation.
    e0 = [float(b[i]) - float(a[i]) for i in range(3)]
    e1 = [float(c[i]) - float(a[i]) for i in range(3)]
    offset = [float(point[i]) - float(a[i]) for i in range(3)]
    dot = lambda x, y: sum(u * v for u, v in zip(x, y))
    d00, d01, d11 = dot(e0, e0), dot(e0, e1), dot(e1, e1)
    d20, d21 = dot(offset, e0), dot(offset, e1)
    denominator = d00 * d11 - d01 * d01
    if abs(denominator) < 1e-20:
        raise ValueError("Degenerate anatomical reference triangle")
    v = (d11 * d20 - d01 * d21) / denominator
    w = (d00 * d21 - d01 * d20) / denominator
    return [1 - v - w, v, w]


def mesh_object(name, vertices, faces, collection, kind=0):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    set_kind(obj, kind)
    smooth(obj)
    return obj


def set_kind(obj, kind):
    attr = obj.data.attributes.get("surface_kind")
    if attr is None:
        attr = obj.data.attributes.new("surface_kind", "INT", "FACE")
    for item in attr.data:
        item.value = kind


def smooth(obj):
    for face in obj.data.polygons:
        face.use_smooth = True


def recalc(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def apply_modifier(obj, modifier):
    active(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def subdivide(obj, level=1):
    modifier = obj.modifiers.new("Tailored subdivision", "SUBSURF")
    modifier.subdivision_type = "CATMULL_CLARK"
    modifier.levels = level
    modifier.render_levels = level
    apply_modifier(obj, modifier)


def reduce_surface(obj, ratio):
    """QEM on already shaped, unbound apparel; face/hand topology is untouched."""
    modifier = obj.modifiers.new("Apparel surface budget", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    apply_modifier(obj, modifier)


def extract(name, reference, collection, keep):
    mesh = reference.data.copy()
    mesh.name = name + "_Mesh"
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    # Preserve source vertex-group indices through bmesh extraction.
    for group in reference.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    return obj


def edit_garment(obj, boundary_edit, inflate, relax=5):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(relax):
        bmesh.ops.smooth_vert(
            bm, verts=[v for v in bm.verts if not v.is_boundary],
            factor=0.42, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for vertex in bm.verts:
        if vertex.is_boundary:
            boundary_edit(vertex)
        vertex.co += vertex.normal * inflate
    # Offsetting by the source normal must not reintroduce jagged cut heights.
    for vertex in bm.verts:
        if vertex.is_boundary:
            boundary_edit(vertex)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    smooth(obj)


def components(obj):
    neighbors = [set() for _ in obj.data.vertices]
    for edge in obj.data.edges:
        a, b = edge.vertices
        neighbors[a].add(b)
        neighbors[b].add(a)
    remaining = set(range(len(neighbors)))
    result = []
    while remaining:
        pending = [remaining.pop()]
        group = []
        while pending:
            vertex = pending.pop()
            group.append(vertex)
            for other in neighbors[vertex]:
                if other in remaining:
                    remaining.remove(other)
                    pending.append(other)
        result.append(group)
    return sorted(result, key=len, reverse=True)


def trim_small_components(obj, minimum=20):
    groups = components(obj)
    remove = {i for group in groups if len(group) < minimum for i in group}
    if remove:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in remove], context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()


def tube(name, points, radius, collection, kind, sides=6, radii=None):
    """A small swept thread/edge, never used as an anatomical body part."""
    vertices, faces = [], []
    from math import cos, sin
    for index, coordinate in enumerate(points):
        point = Vector(coordinate)
        tangent = (Vector(points[min(index + 1, len(points) - 1)])
                   - Vector(points[max(index - 1, 0)])).normalized()
        first = tangent.cross(Vector((0, 0, 1)))
        if first.length < 0.01:
            first = tangent.cross(Vector((0, 1, 0)))
        first.normalize()
        second = tangent.cross(first).normalized()
        r = radius * (radii[index] if radii else 1.0)
        for j in range(sides):
            angle = j * 2 * pi / sides
            vertices.append(point + r * (cos(angle) * first + sin(angle) * second))
        if index:
            previous = (index - 1) * sides
            for j in range(sides):
                k = (j + 1) % sides
                faces.append((previous + j, previous + k,
                              index * sides + k, index * sides + j))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(points) - 1) * sides + j for j in range(sides)))
    result = mesh_object(name, vertices, faces, collection, kind)
    recalc(result)
    return result


def boundary_thread(obj, collection, radius=0.0012, kind=4):
    """Sewn edge loops follow the continuous garment's real open boundaries."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    border = {edge for edge in bm.edges if edge.is_boundary}
    loops = []
    while border:
        edge = border.pop()
        start, current = edge.verts
        chain = [start.co.copy(), current.co.copy()]
        while current != start:
            options = [e for e in current.link_edges if e in border]
            if not options:
                break
            edge = options[0]
            border.remove(edge)
            current = edge.other_vert(current)
            chain.append(current.co.copy())
        if len(chain) > 4:
            loops.append(chain)
    bm.free()
    return [tube(f"{obj.name}_BoundSeam_{i:02}", points, radius,
                 collection, kind, sides=5) for i, points in enumerate(loops)]


def unwrap(obj, rectangle=(0.02, 0.02, 0.98, 0.98), smart=True):
    active(obj)
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    obj.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    if smart:
        bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.022)
    else:
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    fit_uv(obj, rectangle)


def fit_uv(obj, rectangle, loop_indices=None):
    uv = obj.data.uv_layers.active.data
    indices = list(range(len(uv))) if loop_indices is None else list(loop_indices)
    low = [min(uv[i].uv[c] for i in indices) for c in range(2)]
    high = [max(uv[i].uv[c] for i in indices) for c in range(2)]
    left, bottom, right, top = rectangle
    for i in indices:
        u, v = uv[i].uv
        uv[i].uv = (left + (u - low[0]) / max(high[0] - low[0], 1e-6) * (right - left),
                    bottom + (v - low[1]) / max(high[1] - low[1], 1e-6) * (top - bottom))


def pack_original_uv(obj):
    """Repack original separated UDIM charts; do not collapse overlapping tiles."""
    active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.008,
                           shape_method="CONCAVE", margin_method="FRACTION")
    bpy.ops.object.mode_set(mode="OBJECT")
    fit_uv(obj, (0.015, 0.015, 0.985, 0.985))


def garment_uv(obj, classes, rectangles):
    """Seam-defined sewing panels, then fixed, non-overlapping atlas regions."""
    active(obj)
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    obj.data.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    for edge in bm.edges:
        edge.seam = (len(edge.link_faces) != 2
                     or classes[edge.link_faces[0].index] != classes[edge.link_faces[1].index])
    bm.to_mesh(obj.data)
    bm.free()
    active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")
    for label, rectangle in rectangles.items():
        indices = [i for p in obj.data.polygons if classes[p.index] == label
                   for i in p.loop_indices]
        if indices:
            fit_uv(obj, rectangle, indices)


def attach(obj, rig):
    obj.parent = rig
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        modifier = obj.modifiers.new("CourtAthleteSkin", "ARMATURE")
        modifier.object = rig
        # Linear blend skinning matches the glTF/Godot deformation contract.
        modifier.use_deform_preserve_volume = False


def limit_weights(obj, maximum=4):
    for vertex in obj.data.vertices:
        weights = sorted([(g.group, g.weight) for g in vertex.groups if g.weight > 1e-5],
                         key=lambda pair: (-pair[1], pair[0]))[:maximum]
        total = sum(w for _, w in weights)
        for old in list(vertex.groups):
            obj.vertex_groups[old.group].remove([vertex.index])
        if total > 0:
            for index, weight in weights:
                obj.vertex_groups[index].add([vertex.index], weight / total, "REPLACE")


def weight_reference(reference):
    mesh = reference.data
    mesh.calc_loop_triangles()
    triangles = [tuple(t.vertices) for t in mesh.loop_triangles]
    points = [v.co.copy() for v in mesh.vertices]
    tree = BVHTree.FromPolygons(points, triangles, all_triangles=True)
    weights = [{reference.vertex_groups[g.group].name: g.weight for g in v.groups}
               for v in mesh.vertices]
    return points, triangles, tree, weights


def orient_open_skin(obj, reference):
    """Open calf rings have no signed volume: retain anatomical source winding."""
    _, _, tree, _ = reference
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    reversed_faces = 0
    for face in bm.faces:
        _, normal, _, _ = tree.find_nearest(face.calc_center_median())
        if face.normal.dot(normal) < 0:
            face.normal_flip()
            reversed_faces += 1
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return reversed_faces


def transfer_weights(obj, reference, rig, fixed=None, override=None):
    points, triangles, tree, source_weights = reference
    for bone in rig.data.bones:
        if bone.use_deform and bone.name not in obj.vertex_groups:
            obj.vertex_groups.new(name=bone.name)
    for vertex in obj.data.vertices:
        if fixed:
            weights = {fixed: 1.0}
        else:
            point, _, face, _ = tree.find_nearest(vertex.co)
            a, b, c = triangles[face]
            bary = barycentric_double(point, points[a], points[b], points[c])
            weights = {}
            for index, factor in zip((a, b, c), bary):
                for name, weight in source_weights[index].items():
                    weights[name] = weights.get(name, 0.0) + weight * max(0.0, factor)
        if override:
            weights = override(vertex.co, weights)
        weights = sorted(weights.items(), key=lambda item: (-item[1], item[0]))[:4]
        total = sum(weight for _, weight in weights)
        if total <= 1e-8:
            raise ValueError(f"Unweighted {obj.name} vertex {vertex.index}")
        for old in list(vertex.groups):
            obj.vertex_groups[old.group].remove([vertex.index])
        for name, weight in weights:
            obj.vertex_groups[name].add([vertex.index], weight / total, "REPLACE")
    attach(obj, rig)


def join_meshes(objects, name, rig, material):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
        obj.data.materials.clear()
        obj.data.materials.append(material)
        if not obj.data.uv_layers:
            raise ValueError(f"Missing UV: {obj.name}")
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    result.data.name = name + "_Mesh"
    result.data.materials.clear()
    result.data.materials.append(material)
    for face in result.data.polygons:
        face.material_index = 0
    attach(result, rig)
    limit_weights(result)
    return result
