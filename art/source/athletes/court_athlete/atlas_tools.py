"""CPU authoring/rasterization of original PBR maps on the athlete's UVs.

No image-generation service, downloaded texture, photograph or Blender-only
procedural shader is required at runtime. Albedo has no directional lighting.
"""
from __future__ import annotations

import hashlib
import struct
import zlib
from pathlib import Path

import bpy
import numpy as np


def write_png(path: Path, pixels, srgb=False):
    value = np.clip(pixels, 0.0, 1.0).copy()
    if srgb:
        color = value[..., :3]
        value[..., :3] = np.where(color <= 0.0031308, color * 12.92,
                                  1.055 * np.power(color, 1 / 2.4) - 0.055)
    byte = np.rint(value * 255).astype(np.uint8)
    write_png_bytes(path, byte)


def write_png_bytes(path: Path, byte):
    if byte.dtype != np.uint8:
        raise ValueError("PNG byte writer requires uint8 channels")
    height, width, channels = byte.shape
    if channels not in (3, 4):
        raise ValueError("PNG must have RGB or RGBA channels")

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))

    raw = b"".join(b"\0" + row.tobytes() for row in byte[::-1])
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8,
                                        6 if channels == 4 else 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def data_png_pixels(path):
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise ValueError("Expected a PNG image")
    width, height, depth, color_type, _, _, _ = struct.unpack_from(">IIBBBBB", raw, 16)
    if depth != 8 or color_type not in (2, 6):
        raise ValueError("Normal map must be RGB8 or RGBA8")
    image = bpy.data.images.load(str(path), check_existing=False)
    try:
        image.colorspace_settings.name = "Non-Color"
        image.alpha_mode = "CHANNEL_PACKED"
        pixels = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        if not np.isfinite(pixels).all():
            raise ValueError("Non-finite normal-map channel")
        byte = np.rint(np.clip(pixels, 0, 1) * 255).astype(np.uint8).reshape((height, width, 4))
    finally:
        bpy.data.images.remove(image)
    return byte, {
        "width": width, "height": height, "bit_depth": depth, "color_type": color_type,
        "png_sha256": hashlib.sha256(raw).hexdigest(), "png_bytes": len(raw),
        "rgb_top_down_sha256": hashlib.sha256(byte[::-1, :, :3].tobytes()).hexdigest(),
        "alpha_min": int(byte[..., 3].min()), "alpha_max": int(byte[..., 3].max()),
    }


def normalize_opaque_normal_png(path, destination=None):
    """Encoding-only conversion: preserve RGB8 exactly and append alpha 255."""
    byte, before = data_png_pixels(path)
    output = path if destination is None else destination
    opaque = before["color_type"] == 6 and before["alpha_min"] == before["alpha_max"] == 255
    if output != path or not opaque:
        byte[..., 3] = 255
        write_png_bytes(output, byte)
    _, after = data_png_pixels(output)
    if (after["rgb_top_down_sha256"] != before["rgb_top_down_sha256"]
            or after["width"] != before["width"] or after["height"] != before["height"]
            or after["color_type"] != 6 or after["alpha_min"] != 255 or after["alpha_max"] != 255):
        raise ValueError("RGBA8 normalization altered RGB, dimensions or opacity")
    return {"before": before, "after": after, "rgb_changed": False,
            "alpha_value": 255, "encoding_only": True, "rewritten": output != path or not opaque}


def smoothstep(a, b, x):
    value = np.clip((x - a) / (b - a), 0, 1)
    return value * value * (3 - 2 * value)


def runtime_map_links(folder, relink=False):
    """Resolve Blender // paths as Blender paths, never as Windows UNC shares."""
    checks = {}
    for prefix in ("skin", "kit", "gear"):
        material = bpy.data.materials["Athlete" + prefix.capitalize()]
        roles = [("Map_" + suffix, prefix + "_" + suffix + ".png")
                 for suffix in ("albedo", "normal", "orm")]
        if prefix == "kit":
            roles.append(("Kit_RGBA_Weights_Data_Not_Opacity", "kit_mask.png"))
        valid = True
        for node_name, filename in roles:
            node = material.node_tree.nodes.get(node_name)
            image = node.image if node and node.type == "TEX_IMAGE" else None
            expected = (folder / filename).resolve()
            if image is None or not expected.is_file():
                valid = False
                continue
            if relink:
                image.filepath = str(expected)
                image.reload()
                image.filepath = "//maps/" + filename
            source_directory = Path(bpy.data.filepath).parent if bpy.data.filepath else folder.parent
            actual = Path(bpy.path.abspath(image.filepath, start=str(source_directory))).resolve()
            probe = bpy.data.images.load(str(expected), check_existing=False)
            readable = min(probe.size) > 0 and len(probe.pixels) >= 4
            bpy.data.images.remove(probe)
            valid = valid and actual == expected and actual.is_file() and readable
        checks[prefix + "_runtime_maps_resolve"] = bool(valid)
    return checks


def shade(kind, position, uv, eye_z):
    x, y, z = position.T
    u, v = uv.T
    count = len(x)
    color = np.zeros((count, 3), np.float32)
    roughness = np.ones(count, np.float32) * 0.7
    mask = np.zeros((count, 4), np.float32)
    normal = np.zeros((count, 3), np.float32)
    normal[:, 2] = 1
    # Low-amplitude, deterministic pigment/weave variation, not baked light.
    broad = (np.sin(x * 37 + z * 11) * np.sin(y * 29 - z * 17)
             + 0.5 * np.sin(x * 71 + y * 41 + z * 53))
    if kind == 0:
        color[:] = (0.34, 0.183, 0.112)
        color *= (1 + broad[:, None] * 0.022)
        front = smoothstep(-0.095, -0.13, y)
        cheeks = (np.exp(-((abs(x) - 0.046) / 0.025) ** 2
                         - ((z - (eye_z - 0.028)) / 0.035) ** 2) * front)
        color[:, 0] += cheeks * 0.020
        color[:, 1] -= cheeks * 0.003
        # Restrained lips; no painted shadow, lashes or photoreal skin claim.
        lips = (np.exp(-(x / 0.026) ** 6
                       - ((z - (eye_z - 0.076)) / 0.0047) ** 4) * front * 0.6)
        color = color * (1 - lips[:, None]) + np.array((0.285, 0.112, 0.080)) * lips[:, None]
        palms = smoothstep(0.37, 0.42, abs(x)) * smoothstep(0.95, 0.84, z) * 0.08
        color += palms[:, None] * np.array((0.32, 0.25, 0.18))
        roughness = 0.605 + broad * 0.011
    elif kind in (1, 2, 3, 4):
        weave = np.sin(u * 2 * np.pi * 460) * np.sin(v * 2 * np.pi * 460)
        color[:] = 0.76
        color *= (1 + weave[:, None] * 0.003 + broad[:, None] * 0.008)
        roughness = 0.82 + weave * 0.005
        mask[:, kind - 1] = 1.0
        if kind == 1:
            # Narrow original axillary side panels; chest/back remain blank.
            side = (smoothstep(0.150, 0.177, abs(x))
                    * smoothstep(1.38, 1.29, z) * smoothstep(1.03, 1.11, z))
            mask[:, 0] = 1 - side
            mask[:, 1] = side
        if kind == 3:
            # Rib knit at the cuff; no thread-sized geometry or cloth simulation.
            weave = np.sin(u * 2 * np.pi * 220)
        normal[:, 0] = np.sin(u * 2 * np.pi * 460) * 0.015
        normal[:, 1] = np.sin(v * 2 * np.pi * 460) * 0.015
    elif kind in (5, 11):
        flow = np.sin((u * 740 + v * 69) * 2 * np.pi)
        color[:] = (0.021, 0.0125, 0.008)
        color *= 1 + flow[:, None] * 0.08 + broad[:, None] * 0.07
        roughness = 0.73 + flow * 0.015
        normal[:, 0] = flow * 0.073
        normal[:, 1] = np.sin(v * 2 * np.pi * 81) * 0.018
    elif kind in (6, 10):
        color[:] = (0.050, 0.076, 0.080) if kind == 6 else (0.32, 0.355, 0.34)
        color *= 1 + broad[:, None] * 0.015
        roughness[:] = 0.64 if kind == 6 else 0.72
        normal[:, 0] = np.sin(u * 2 * np.pi * 200) * 0.024
        normal[:, 1] = np.sin(v * 2 * np.pi * 200) * 0.024
    elif kind == 7:
        color[:] = (0.34, 0.245, 0.132)
        edge = smoothstep(0.018, 0.023, z)
        color = color * (1 - edge[:, None]) + np.array((0.56, 0.57, 0.53)) * edge[:, None]
        roughness[:] = 0.86
    elif kind == 8:
        color[:] = (0.69, 0.70, 0.65)
        roughness[:] = 0.86
    elif kind == 9:
        radius = np.sqrt((abs(x) - 0.0331) ** 2 + (z - eye_z) ** 2)
        eye_front = y < -0.125
        color[:] = (0.68, 0.655, 0.61)
        iris = (radius < 0.0055) & eye_front
        pupil = (radius < 0.00235) & eye_front
        limbus = (radius >= 0.0048) & iris
        angle = np.arctan2(z - eye_z, abs(x) - 0.0331)
        iris_pattern = 0.015 * np.sin(angle * 41) + 0.008 * np.sin(angle * 83)
        color[iris] = np.array((0.105, 0.070, 0.031)) + iris_pattern[iris, None]
        color[limbus] = (0.026, 0.022, 0.015)
        color[pupil] = (0.004, 0.005, 0.005)
        roughness[:] = 0.32
        roughness[iris] = 0.24
    else:
        raise ValueError(f"Unknown original surface kind {kind}")
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)
    return color.astype(np.float32), roughness, mask, normal * 0.5 + 0.5


def dilate(arrays, filled, steps=12):
    occupied = filled.copy()
    for _ in range(steps):
        previous = occupied.copy()
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            shifted = np.roll(previous, shift, axis=axis)
            if axis == 0:
                shifted[0 if shift == 1 else -1] = False
            else:
                shifted[:, 0 if shift == 1 else -1] = False
            update = ~occupied & shifted
            for array in arrays:
                array[update] = np.roll(array, shift, axis=axis)[update]
            occupied |= update


def rasterize(obj, folder, prefix, resolution, eye_z):
    mesh = obj.data
    mesh.calc_loop_triangles()
    uv = mesh.uv_layers.active.data
    kinds = mesh.attributes["surface_kind"].data
    albedo = np.ones((resolution, resolution, 4), np.float32)
    albedo[..., :3] = 0.2
    orm = np.ones_like(albedo)
    orm[..., 1] = 0.75
    orm[..., 2] = 0
    normal = np.ones_like(albedo)
    normal[..., :2] = 0.5
    mask = np.zeros_like(albedo)
    filled = np.zeros((resolution, resolution), bool)
    owners = np.zeros((resolution, resolution), np.uint16)
    skipped = 0
    for triangle in mesh.loop_triangles:
        tuv = np.array([uv[i].uv[:] for i in triangle.loops], np.float64)
        p = np.array([mesh.vertices[i].co[:] for i in triangle.vertices])
        minimum = np.maximum(0, np.floor(tuv.min(0) * resolution - 0.5).astype(int))
        maximum = np.minimum(resolution - 1, np.ceil(tuv.max(0) * resolution - 0.5).astype(int))
        if np.any(maximum < minimum):
            continue
        xx, yy = np.meshgrid(np.arange(minimum[0], maximum[0] + 1),
                             np.arange(minimum[1], maximum[1] + 1))
        tx, ty = (xx + 0.5) / resolution, (yy + 0.5) / resolution
        a, b, c = tuv
        denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(denominator) < 1e-12:
            skipped += 1
            continue
        w0 = ((b[1] - c[1]) * (tx - c[0]) + (c[0] - b[0]) * (ty - c[1])) / denominator
        w1 = ((c[1] - a[1]) * (tx - c[0]) + (a[0] - c[0]) * (ty - c[1])) / denominator
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-8) & (w1 >= -1e-8) & (w2 >= -1e-8)
        if not inside.any():
            continue
        xi, yi = xx[inside], yy[inside]
        point = (w0[inside, None] * p[0] + w1[inside, None] * p[1]
                 + w2[inside, None] * p[2])
        rgb, rough, rgba, n = shade(
            kinds[triangle.polygon_index].value, point,
            np.column_stack((tx[inside], ty[inside])), eye_z)
        albedo[yi, xi, :3] = rgb
        orm[yi, xi, 1] = rough
        normal[yi, xi, :3] = n
        mask[yi, xi] = rgba
        filled[yi, xi] = True
        owners[yi, xi] += 1
    if prefix == "kit":
        error = np.max(abs(mask[filled].sum(1) - 1.0))
        if error > 1e-5:
            raise ValueError(f"Kit mask is not normalized: {error}")
        # Empty texels are harmless main-color data, not transparent cloth.
        mask[~filled, 0] = 1.0
    dilate([albedo, orm, normal, mask], filled)
    write_png(folder / f"{prefix}_albedo.png", albedo, srgb=True)
    write_png(folder / f"{prefix}_orm.png", orm)
    write_png(folder / f"{prefix}_normal.png", normal)
    if prefix == "kit":
        # Four channels are weights, including alpha; never premultiply them.
        quantized = np.rint(mask * 255).astype(np.int16)
        flat = quantized.reshape((-1, 4))
        winner = flat.argmax(axis=1)
        flat[np.arange(len(flat)), winner] += 255 - flat.sum(axis=1)
        write_png(folder / "kit_mask.png", quantized.astype(np.float32) / 255)
    return {
        "resolution": [resolution, resolution],
        "uv_covered_pixels": int(filled.sum()),
        "uv_coverage_fraction": float(filled.mean()),
        "uv_multiple_coverage_pixels": int((owners > 1).sum()),
        "degenerate_uv_triangles": skipped,
        "padding_texels": 12,
        "albedo_directional_lighting": False,
        "orm_work": orm,
    }


def load_image(path, data=False):
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = "Non-Color" if data else "sRGB"
    if data:
        image.alpha_mode = "CHANNEL_PACKED"
    return image


def setup_material(material, folder, prefix):
    material.use_nodes = True
    material.diffuse_color = (0.5, 0.5, 0.5, 1)
    material.use_backface_culling = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Metallic"].default_value = 0
    shader.inputs["Roughness"].default_value = 0.7
    shader.inputs["Specular IOR Level"].default_value = 0.28
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    for suffix, data in (("albedo", False), ("normal", True), ("orm", True)):
        texture = nodes.new("ShaderNodeTexImage")
        texture.name = "Map_" + suffix
        texture.image = load_image(folder / f"{prefix}_{suffix}.png", data)
        if suffix == "albedo":
            links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        elif suffix == "normal":
            normal = nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value = 1
            links.new(texture.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], shader.inputs["Normal"])
        else:
            channels = nodes.new("ShaderNodeSeparateColor")
            channels.mode = "RGB"
            links.new(texture.outputs["Color"], channels.inputs["Color"])
            links.new(channels.outputs["Green"], shader.inputs["Roughness"])
            links.new(channels.outputs["Blue"], shader.inputs["Metallic"])
            # Blender glTF exporter recognizes this exact AO input convention.
            group = bpy.data.node_groups.get("glTF Material Output")
            if group is None:
                group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
                group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
            ao = nodes.new("ShaderNodeGroup")
            ao.node_tree = group
            links.new(channels.outputs["Red"], ao.inputs["Occlusion"])
    if prefix == "kit":
        mask = nodes.new("ShaderNodeTexImage")
        mask.name = "Kit_RGBA_Weights_Data_Not_Opacity"
        mask.label = "Runtime adapter: RGBA normalized weights, NOT alpha blending"
        mask.image = load_image(folder / "kit_mask.png", True)
    return material


def bake_scan_normal(low, high, material, path, size=2048):
    from mesh_tools import active
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    nodes = material.node_tree.nodes
    image = bpy.data.images.new("Skin_Scan_Tangent_Bake", size, size, alpha=True)
    image.colorspace_settings.name = "Non-Color"
    target = nodes.new("ShaderNodeTexImage")
    target.image = image
    nodes.active = target
    active(low)
    high.hide_render = False
    high.hide_set(False)
    high.select_set(True)
    bpy.context.view_layer.objects.active = low
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.018
    scene.render.bake.max_ray_distance = 0.045
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_r = "POS_X"
    scene.render.bake.normal_g = "POS_Y"
    scene.render.bake.normal_b = "POS_Z"
    scene.render.bake.margin = 12
    bpy.ops.object.bake(type="NORMAL")
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    nodes.remove(target)
    bpy.data.images.remove(image)
    high.hide_render = True
    high.hide_set(True)
    scene.render.bake.use_selected_to_active = False
    return normalize_opaque_normal_png(path)


def bake_local_ao(obj, material, path, orm, distance=0.065):
    from mesh_tools import active
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    nodes, links = material.node_tree.nodes, material.node_tree.links
    output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
    original = output.inputs["Surface"].links[0].from_socket
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 16
    ao.inputs["Distance"].default_value = distance
    emission = nodes.new("ShaderNodeEmission")
    links.new(ao.outputs["AO"], emission.inputs["Color"])
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    image = bpy.data.images.new(obj.name + "_LocalAO", 1024, 1024, alpha=False)
    image.colorspace_settings.name = "Non-Color"
    target = nodes.new("ShaderNodeTexImage")
    target.image = image
    nodes.active = target
    active(obj)
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT")
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    raw = np.empty(1024 * 1024 * 4, dtype=np.float32)
    image.pixels.foreach_get(raw)
    values = raw.reshape((1024, 1024, 4))[..., 0]
    factor = orm.shape[0] // 1024
    values = np.repeat(np.repeat(values, factor, axis=0), factor, axis=1)
    # Local occlusion is intentionally restrained; no directional shadows.
    orm[..., 0] = 0.45 + 0.55 * values
    write_png(path.with_name(path.stem.replace("_ao", "_orm") + ".png"), orm)
    links.new(original, output.inputs["Surface"])
    nodes.remove(target)
    nodes.remove(emission)
    nodes.remove(ao)
    bpy.data.images.remove(image)


def file_record(path):
    return {"file": path.name, "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
