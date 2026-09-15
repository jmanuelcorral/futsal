"""Ephemeral geometry for a toolchain check, not a game asset or art reference."""

import argparse
import json
from pathlib import Path
import sys

import bpy


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend-path", required=True, type=Path)
    parser.add_argument("--glb-path", required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.ops.mesh.primitive_cube_add(size=2.0)
    probe = bpy.context.object
    probe.name = "PipelineProbe"
    probe.dimensions = (2.0, 4.0, 6.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    material = bpy.data.materials.new("PipelineProbeRed")
    material.use_nodes = True
    material.diffuse_color = (1.0, 0.0, 0.0, 1.0)
    shader = material.node_tree.nodes.get("Principled BSDF")
    if shader is None:
        raise RuntimeError("Blender Principled BSDF node missing.")
    shader.inputs["Base Color"].default_value = (1.0, 0.0, 0.0, 1.0)
    shader.inputs["Metallic"].default_value = 0.2
    shader.inputs["Roughness"].default_value = 0.65
    probe.data.materials.append(material)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.blend_path))
    result = bpy.ops.export_scene.gltf(
        filepath=str(args.glb_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    if result != {"FINISHED"} or not args.glb_path.is_file():
        raise RuntimeError(f"Actual Blender GLB export failed: {result}")
    with args.glb_path.open("rb") as stream:
        if stream.read(4) != b"glTF":
            raise RuntimeError("Export did not produce a binary glTF file.")
    print(
        "FUTSAL_PIPELINE_EXPORT "
        + json.dumps(
            {
                "blender_version": bpy.app.version_string,
                "scope": "synthetic-pipeline-check-not-art",
                "objects": len(bpy.context.scene.objects),
                "blender_dimensions_metres": list(probe.dimensions),
                "godot_expected_dimensions_metres": [2, 6, 4],
                "glb_bytes": args.glb_path.stat().st_size,
            }
        )
    )


if __name__ == "__main__":
    main()
