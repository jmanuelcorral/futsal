"""Export DIRECTLY to the agreed game path, only after explicit isolation approval.

This script does not build, import, run, or approve Godot, and never modifies
match code, templates, presets, tooling or releases. Without the approval flag
it refuses to create even the destination directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
SOURCE = HERE / "court_athlete.blend"
DESTINATION = REPO / "game" / "assets" / "athletes" / "court_athlete"
PBR_MAP_NAMES = tuple(f"{prefix}_{suffix}.png"
                     for prefix in ("skin", "kit", "gear")
                     for suffix in ("albedo", "normal", "orm"))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mesh_vertex_signature(mesh):
    return [(tuple(vertex.co), tuple((group.group, group.weight) for group in vertex.groups))
            for vertex in mesh.vertices]


def mesh_corner_signature(mesh):
    color = mesh.color_attributes.get("COLOR0")
    return {
        (loop.vertex_index,
         tuple(tuple(layer.data[index].uv) for layer in mesh.uv_layers),
         tuple(color.data[index].color) if color else ())
        for index, loop in enumerate(mesh.loops)}


def separate_waistband_rim_normals(mesh):
    kinds = mesh.attributes.get("surface_kind")
    if not kinds:
        raise ValueError("Kit is missing its authored clothing surface identifiers")
    shorts = [face for face in mesh.polygons if kinds.data[face.index].value == 2]
    if not shorts:
        raise ValueError("Kit is missing the authored shorts surface")
    top = max(mesh.vertices[index].co.z for face in shorts for index in face.vertices)
    caps = [face for face in shorts
            if face.normal.z > 0.98
            and min(mesh.vertices[index].co.z for index in face.vertices) > top - 0.015]
    # A horizontal waistband rim cannot share its sidewall normal: that made
    # MikkTSpace project a valid UV derivative to zero. Split the real cap normal,
    # rather than inventing a tangent or modifying geometry/UVs.
    for face in caps:
        face.use_smooth = False
    mesh.update()
    return [face.index for face in caps]


def prepare_export_geometry(objects):
    reports = {}
    for obj in objects:
        mesh = obj.data
        flat_caps = separate_waistband_rim_normals(mesh) if obj.name == "AthleteKitMesh" else []
        mesh.calc_loop_triangles()
        triangle_count = len(mesh.loop_triangles)
        ngon_count = sum(len(polygon.vertices) > 4 for polygon in mesh.polygons)
        if ngon_count:
            before_vertices = mesh_vertex_signature(mesh)
            before_corners = mesh_corner_signature(mesh)
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new("ExportNgonTriangulation", "TRIANGULATE")
            modifier.min_vertices = 5
            modifier.ngon_method = "CLIP"
            modifier.keep_custom_normals = True
            # Apply before the armature, never baking a presentation pose.
            while obj.modifiers[0] != modifier:
                bpy.ops.object.modifier_move_up(modifier=modifier.name)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            mesh = obj.data
            if mesh_vertex_signature(mesh) != before_vertices:
                raise ValueError(f"Export triangulation changed positions/weights: {obj.name}")
            if mesh_corner_signature(mesh) != before_corners:
                raise ValueError(f"Export triangulation changed UV/COLOR0 corner data: {obj.name}")
        mesh.calc_loop_triangles()
        if len(mesh.loop_triangles) != triangle_count:
            raise ValueError(f"Export triangulation changed the triangle budget: {obj.name}")
        mesh.calc_tangents(uvmap=mesh.uv_layers.active.name)
        reports[obj.name] = {
            "ngons_triangulated_in_memory": ngon_count,
            "waistband_rim_faces_with_separate_flat_normals": flat_caps,
            "triangles": len(mesh.loop_triangles), "vertices": len(mesh.vertices),
            "positions_weights_uv_color_preserved": True,
            "tangents_calculated": True, "source_saved": False,
        }
    return reports


def float_vectors(doc, binary, index, vector_type, vertex_count):
    accessor = doc["accessors"][index]
    if (accessor["type"] != vector_type or accessor["count"] != vertex_count
            or accessor["componentType"] != 5126 or accessor.get("normalized", False)
            or "sparse" in accessor):
        raise ValueError(f"Unexpected {vector_type} float-vector layout")
    components = {"VEC3": 3, "VEC4": 4}[vector_type]
    size = components * 4
    view = doc["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", size)
    end = view.get("byteOffset", 0) + view["byteLength"]
    if (view.get("buffer", 0) != 0 or vertex_count < 1 or stride < size
            or start < view.get("byteOffset", 0) or end > len(binary)
            or start + (vertex_count - 1) * stride + size > end):
        raise ValueError("Float-vector accessor exceeds its buffer view")
    for vertex in range(vertex_count):
        yield struct.unpack_from("<" + "f" * components, binary, start + vertex * stride)


def validate_tangent_frames(doc, binary, attributes, vertex_count):
    normal_error = tangent_error = orthogonality_error = 0.0
    normals = float_vectors(doc, binary, attributes["NORMAL"], "VEC3", vertex_count)
    tangents = float_vectors(doc, binary, attributes["TANGENT"], "VEC4", vertex_count)
    for normal, tangent in zip(normals, tangents):
        if not all(math.isfinite(value) for value in (*normal, *tangent)):
            raise ValueError("Non-finite exported normal/tangent")
        normal_error = max(normal_error, abs(math.sqrt(sum(v * v for v in normal)) - 1))
        tangent_error = max(tangent_error, abs(math.sqrt(sum(v * v for v in tangent[:3])) - 1))
        orthogonality_error = max(
            orthogonality_error, abs(sum(n * t for n, t in zip(normal, tangent[:3]))))
        if abs(abs(tangent[3]) - 1) > 1e-5:
            raise ValueError("Invalid tangent handedness")
    if normal_error > 1e-4 or tangent_error > 1e-4 or orthogonality_error > 2e-4:
        raise ValueError(f"Invalid tangent frame: normal={normal_error}, "
                         f"tangent={tangent_error}, dot={orthogonality_error}")
    return {"vertices": vertex_count, "max_normal_length_error": normal_error,
            "max_tangent_length_error": tangent_error,
            "max_normal_tangent_dot": orthogonality_error}


def validate_skin_normal_header(data):
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("Skin normal must be an embedded PNG")
    width, height, depth, color_type, _, _, _ = struct.unpack_from(">IIBBBBB", data, 16)
    if (width, height, depth, color_type) != (2048, 2048, 8, 6):
        raise ValueError("Skin normal must retain 2048x2048 RGBA8 for Vulkan")
    return {"width": width, "height": height, "bit_depth": depth, "color_type": color_type}


def embedded_map_records(doc, binary):
    buffers = doc.get("buffers", [])
    if len(buffers) != 1 or "uri" in buffers[0]:
        raise ValueError("PBR images must use the GLB's single internal binary buffer")
    images = doc.get("images", [])
    if len(images) != len(PBR_MAP_NAMES) or {image.get("name") for image in images} != set(PBR_MAP_NAMES):
        raise ValueError("Expected exactly the nine named PBR images inside the GLB")
    records = []
    views = doc["bufferViews"]
    for image in images:
        index = image.get("bufferView")
        if ("uri" in image or image.get("mimeType") != "image/png"
                or not isinstance(index, int) or not 0 <= index < len(views)):
            raise ValueError("PBR images must be embedded PNG buffer views, not external files")
        view = views[index]
        start, size = view.get("byteOffset", 0), view["byteLength"]
        if view.get("buffer", 0) != 0 or start < 0 or size < 33 or start + size > len(binary):
            raise ValueError("Embedded PBR image exceeds the GLB binary buffer")
        data = binary[start:start + size]
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise ValueError("Embedded PBR image is not PNG")
        resolution = 1024 if image["name"].startswith("gear_") else 2048
        width, height, depth, color_type = struct.unpack_from(">IIBB", data, 16)
        if (width, height, depth, color_type) != (resolution, resolution, 8, 6):
            raise ValueError("Embedded PBR map must retain its authored resolution and RGBA8 encoding")
        records.append({
            "name": image["name"], "buffer_view": index,
            "source_master": "maps/" + image["name"],
            "godot_extracted_name": "court_athlete_" + image["name"],
            "bytes": size, "sha256": hashlib.sha256(data).hexdigest(),
        })
    return records


def validate_embedded_masters(records, maps):
    for record in records:
        if sha256(maps / record["name"]) != record["sha256"]:
            raise ValueError(f"Embedded PBR image differs from its master: {record['name']}")


def validate_helper_joints(doc):
    nodes = doc.get("nodes", [])
    indices = {node.get("name"): index for index, node in enumerate(nodes)}
    joint_indices = set(doc["skins"][0]["joints"])
    for side in ("L", "R"):
        for chain in (("Thigh", "Shin", "Foot", "Toe"),
                      ("UpperArm", "Forearm", "Hand", "Palm")):
            for parent, child in zip(chain, chain[1:]):
                parent_index = indices.get(parent + "_" + side)
                child_index = indices.get(child + "_" + side)
                if parent_index is None or child_index is None:
                    raise ValueError(f"Missing runtime chain joint: {parent}/{child}_{side}")
                if child_index not in nodes[parent_index].get("children", []):
                    raise ValueError(f"Runtime chain is not direct: {parent}->{child}_{side}")
        if indices["Palm_" + side] not in joint_indices:
            raise ValueError(f"Exporter discarded Palm_{side} as a Skeleton joint")


def validate_color0(doc, binary, accessor_index, vertex_count):
    accessor = doc["accessors"][accessor_index]
    if accessor["type"] != "VEC4" or accessor["count"] != vertex_count:
        raise ValueError("Kit COLOR_0 must contain RGBA for every exported vertex")
    if "sparse" in accessor:
        raise ValueError("Sparse mask accessor is not part of this export contract")
    component = accessor["componentType"]
    if component == 5126 and not accessor.get("normalized", False):
        scalar, size, divisor = "f", 4, 1.0
    elif component in (5121, 5123) and accessor.get("normalized", False):
        scalar, size, divisor = ("B", 1, 255.0) if component == 5121 else ("H", 2, 65535.0)
    else:
        raise ValueError("Unsupported/non-normalized COLOR_0 component format")
    view = doc["bufferViews"][accessor["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError("Unexpected external color buffer")
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", size * 4)
    end = view.get("byteOffset", 0) + view["byteLength"]
    if (vertex_count < 1 or stride < size * 4 or start < view.get("byteOffset", 0)
            or end > len(binary)
            or start + (vertex_count - 1) * stride + size * 4 > end):
        raise ValueError("COLOR_0 accessor exceeds its declared buffer view")
    maximum_error = 0.0
    channel_max = [0.0] * 4
    for index in range(vertex_count):
        offset = start + index * stride
        if offset + size * 4 > len(binary):
            raise ValueError("COLOR_0 reads beyond the GLB buffer")
        color = [v / divisor for v in struct.unpack_from("<" + scalar * 4, binary, offset)]
        if not all(math.isfinite(v) and 0 <= v <= 1 for v in color):
            raise ValueError("Kit COLOR_0 contains non-finite/out-of-range weights")
        error = abs(sum(color) - 1)
        # Float authoring is tighter; quantized export may round four channels.
        tolerance = 1e-5 if divisor == 1 else 2 / divisor
        if error > tolerance:
            raise ValueError("Kit COLOR_0 is not a normalized mask (possibly a fake white COLOR_0)")
        maximum_error = max(maximum_error, error)
        channel_max = [max(a, b) for a, b in zip(channel_max, color)]
    if min(channel_max) < 0.99:
        raise ValueError("A kit mask zone was lost in export")
    return {"vertices": vertex_count, "component_type": component,
            "max_channel_sum_error": maximum_error, "channel_max": channel_max}


def inspect_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("Malformed GLB header")
    chunk_size, chunk_kind = struct.unpack_from("<I4s", data, 12)
    if chunk_kind != b"JSON":
        raise ValueError("First GLB chunk is not JSON")
    doc = json.loads(data[20:20 + chunk_size])
    offset = 20 + chunk_size
    binary = b""
    while offset < len(data):
        length, kind = struct.unpack_from("<I4s", data, offset)
        if kind == b"BIN\0":
            binary = data[offset + 8:offset + 8 + length]
        offset += 8 + length
    names = {m["name"] for m in doc.get("materials", [])}
    if names != {"AthleteSkin", "AthleteKit", "AthleteGear"}:
        raise ValueError(f"Unexpected runtime materials: {names}")
    if len(doc.get("meshes", [])) != 3 or len(doc.get("skins", [])) != 1:
        raise ValueError("Export must contain three material meshes and one shared skin")
    validate_helper_joints(doc)
    if doc.get("animations") or doc.get("cameras"):
        raise ValueError("Unexpected animation/camera in athlete export")
    if "KHR_lights_punctual" in doc.get("extensionsUsed", []):
        raise ValueError("Unexpected source-inspection light in export")
    accessors = doc["accessors"]
    triangles = vertices = 0
    color_reports = []
    tangent_reports = []
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError("Athlete primitive is not triangulated")
            attributes = primitive["attributes"]
            required = {"POSITION", "NORMAL", "TANGENT", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"}
            if not required.issubset(attributes):
                raise ValueError(f"Missing attributes: {required.difference(attributes)}")
            if "WEIGHTS_1" in attributes or "JOINTS_1" in attributes:
                raise ValueError("More than four influences exported")
            tangent_reports.append({
                "mesh": mesh["name"],
                **validate_tangent_frames(
                    doc, binary, attributes, accessors[attributes["POSITION"]]["count"]),
            })
            material = doc["materials"][primitive["material"]]
            if material["name"] == "AthleteKit":
                if "COLOR_0" not in attributes:
                    raise ValueError("Kit's data COLOR_0 was discarded by exporter")
                if material.get("alphaMode", "OPAQUE") != "OPAQUE":
                    raise ValueError("Kit mask alpha was incorrectly exported as transparency")
                color_reports.append(validate_color0(
                    doc, binary, attributes["COLOR_0"],
                    accessors[attributes["POSITION"]]["count"]))
            triangles += accessors[primitive["indices"]]["count"] // 3
            vertices += accessors[attributes["POSITION"]]["count"]
    if triangles > 60000:
        raise ValueError("GLB exceeds the declared visible triangle ceiling")
    if not color_reports:
        raise ValueError("No AthleteKit primitive was validated")
    normal_images = [image for image in doc.get("images", []) if image.get("name") == "skin_normal.png"]
    if len(normal_images) != 1:
        raise ValueError("Expected exactly one portable skin-normal image")
    image_view = doc["bufferViews"][normal_images[0]["bufferView"]]
    image_offset = image_view.get("byteOffset", 0)
    skin_normal_encoding = validate_skin_normal_header(
        binary[image_offset:image_offset + image_view["byteLength"]])
    embedded_maps = embedded_map_records(doc, binary)
    validate_embedded_masters(embedded_maps, HERE / "maps")
    return {
        "triangles": triangles, "gltf_vertices_including_uv_normal_splits": vertices,
        "materials": sorted(names), "mesh_count": len(doc["meshes"]),
        "skin_count": len(doc["skins"]), "skin_joint_count": len(doc["skins"][0]["joints"]),
        "images_embedded": len(doc.get("images", [])),
        "kit_COLOR_0_validation": color_reports, "Palm_helpers_retained_as_joints": True,
        "tangent_frame_validation": tangent_reports,
        "skin_normal_PNG_encoding": skin_normal_encoding,
        "embedded_pbr_maps": embedded_maps,
        "extensions_used": doc.get("extensionsUsed", []),
        "generator": doc.get("asset", {}).get("generator"),
        "node_names": [n.get("name", "") for n in doc.get("nodes", [])],
    }


def publish_runtime_asset(staged_glb, destination):
    result = inspect_glb(staged_glb)
    staged_glb.replace(destination / "court_athlete.glb")
    for name in ("rig_manifest.json", "provenance.json"):
        shutil.copyfile(HERE / name, destination / name)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--permit-game-export", action="store_true")
    parser.add_argument("--approval", help="Explicit coordinator isolation confirmation, not an inferred release state")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not args.permit_game_export or not args.approval:
        raise SystemExit("REFUSED: wait for coordinator confirmation that candidate 0.4 is isolated.")
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    if sha256(SOURCE) != manifest["source_sha256"]:
        raise ValueError("Source changed since its manifest; validate/rebuild first")
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
    from atlas_tools import data_png_pixels, runtime_map_links
    map_links = runtime_map_links(HERE / "maps")
    if not all(map_links.values()):
        raise ValueError(f"Missing/wrong source PBR maps before game writes: {map_links}")
    _, normal_encoding = data_png_pixels(HERE / "maps" / "skin_normal.png")
    if (normal_encoding["color_type"] != 6 or normal_encoding["alpha_min"] != 255
            or normal_encoding["alpha_max"] != 255):
        raise ValueError("Source skin normal is not opaque RGBA8; normalize its encoding first")
    import rig_material_contract as driver_contract
    preflight = driver_contract.validate_driver_contract(
        bpy.data.objects["CourtAthlete"],
        *[bpy.data.objects[name] for name in driver_contract.MESH_NAMES],
        HERE / "maps/kit_mask.png")
    if preflight["passed"] != preflight["total"]:
        raise ValueError(f"Source integration contract failed before game writes: {preflight}")
    allowed = {"CourtAthlete", "AthleteSkinMesh", "AthleteKitMesh", "AthleteGearMesh"}
    for obj in list(bpy.data.objects):
        if obj.name not in allowed:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in bpy.data.objects:
        obj.hide_set(False)
        obj.hide_render = False
        obj.hide_viewport = False
        obj.select_set(True)
    rig = bpy.data.objects["CourtAthlete"]
    bpy.context.view_layer.objects.active = rig
    rig.data.pose_position = "REST"
    geometry_preparation = prepare_export_geometry(
        [bpy.data.objects[name] for name in driver_contract.MESH_NAMES])
    DESTINATION.mkdir(parents=True, exist_ok=True)
    glb = DESTINATION / "court_athlete.glb"
    staged_glb = DESTINATION / ".court_athlete.pending.glb"
    if staged_glb.exists():
        raise ValueError("Unexpected pending athlete export; inspect it rather than overwrite")
    options = {
        "filepath": str(staged_glb), "export_format": "GLB",
        "use_selection": True, "export_yup": True,
        "export_texcoords": True, "export_normals": True, "export_tangents": True,
        "export_materials": "EXPORT", "export_skins": True,
        "export_all_influences": False, "export_def_bones": False,
        "export_vertex_color": "NAME", "export_vertex_color_name": "COLOR0",
        "export_all_vertex_colors": False, "export_active_vertex_color_when_no_material": False,
        "export_animations": False, "export_cameras": False,
        "export_lights": False, "export_extras": True, "export_apply": False,
    }
    # Temporary staging stays in the final authorized directory. A rejected
    # export must not replace a valid athlete or leave a second runtime copy.
    try:
        bpy.ops.export_scene.gltf(**options)
        result = publish_runtime_asset(staged_glb, DESTINATION)
    finally:
        if staged_glb.exists():
            staged_glb.unlink()
    result.update({
        "approval": args.approval,
        "source_sha256": sha256(SOURCE), "glb_sha256": sha256(glb),
        "glb_bytes": glb.stat().st_size, "blender": bpy.app.version_string,
        "direct_destination": str(glb.relative_to(REPO)),
        "options": {k: v for k, v in options.items() if k != "filepath"},
        "export_only_geometry_preparation": geometry_preparation,
        "runtime_textures": [],
        "texture_storage": "Nine PBR PNGs embedded in GLB. Godot owns their extracted PNGs/imports beside the GLB. The exporter does not create a textures directory.",
        "note": "GLB embeds base PBR and linear mask COLOR_0; use the coordinator kit shader, not ordinary vertex-color albedo/opacity. PNG mask remains an authoring master only. No parallel PBR copies or art/exports tree.",
        "godot_import_tested": False, "gameplay_tested": False,
        "art_approved": False, "fps_measured": False,
    })
    (HERE / "export_manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    manifest["status"] = "GLB_exported_awaiting_Godot_integration_and_art_review"
    manifest["exported_to_game"] = True
    manifest["runtime_export"] = {
        "manifest": "export_manifest.json", "file": result["direct_destination"],
        "source_sha256": result["source_sha256"], "glb_sha256": result["glb_sha256"],
        "glb_bytes": result["glb_bytes"], "triangles": result["triangles"],
        "gltf_vertices": result["gltf_vertices_including_uv_normal_splits"],
        "skin_joints": result["skin_joint_count"], "approved_isolation": args.approval,
        "texture_storage": result["texture_storage"],
        "godot_import_tested": False, "art_approved": False, "fps_measured": False,
    }
    manifest["driver_contract_adaptation"]["game_exported"] = True
    driver_contract.contacts.save_json(HERE / "manifest.json", manifest)
    print("DIRECT_EXPORT_READY", json.dumps(result, indent=2), flush=True)


if __name__ == "__main__":
    main()
