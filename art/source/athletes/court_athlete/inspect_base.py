"""Read Blender asset data without opening its scene or running embedded text."""
from pathlib import Path
import json
import bpy


REPO = Path(__file__).resolve().parents[4]
BASE = (REPO / ".dream-loop/downloads/human-base-meshes-v1.4.1/"
        "human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend")
OUT = REPO / ".dream-loop/athlete-upgrade/base_inventory.json"
OUT.parent.mkdir(parents=True, exist_ok=True)

report = {"blender_version": bpy.app.version_string, "source": str(BASE)}
with bpy.data.libraries.load(str(BASE), link=False) as (data_from, data_to):
    report["available_objects"] = list(data_from.objects)
    report["available_collections"] = list(data_from.collections)
    report["available_texts"] = list(data_from.texts)
    report["available_actions"] = list(data_from.actions)
    data_to.texts = data_from.texts
    data_to.objects = [name for name in data_from.objects
                       if "realistic" in name.lower() and "primitive" not in name.lower()]
    data_to.collections = ["Body Male - Realistic"]

report["text_data_not_executed"] = {t.name: t.as_string() for t in data_to.texts if t}
report["objects"] = []
report["selected_collection"] = [
    {"name": c.name, "objects": [o.name for o in c.all_objects],
     "asset_metadata": ({key: getattr(c.asset_data, key, None)
                         for key in ("author", "description", "license", "copyright")}
                        if c.asset_data else None)}
    for c in data_to.collections if c
]
for obj in data_to.objects:
    if obj is None:
        continue
    record = {
        "name": obj.name, "type": obj.type,
        "location": list(obj.location), "scale": list(obj.scale),
        "rotation_euler": list(obj.rotation_euler),
        "modifiers": [{"name": m.name, "type": m.type} for m in obj.modifiers],
        "vertex_groups": [g.name for g in obj.vertex_groups],
        "asset_metadata": ({key: getattr(obj.asset_data, key, None)
                            for key in ("author", "description", "license", "copyright")}
                           if obj.asset_data else None),
    }
    if obj.type == "MESH":
        mesh = obj.data
        mesh.calc_loop_triangles()
        record.update({
            "mesh": mesh.name, "vertices": len(mesh.vertices),
            "polygons": len(mesh.polygons), "triangles": len(mesh.loop_triangles),
            "uv_layers": [layer.name for layer in mesh.uv_layers],
            "bounds_local": [[min(v.co[i] for v in mesh.vertices),
                              max(v.co[i] for v in mesh.vertices)] for i in range(3)],
            "materials": [m.name if m else None for m in mesh.materials],
            "shape_keys": ([k.name for k in mesh.shape_keys.key_blocks]
                           if mesh.shape_keys else []),
            "attributes": [{"name": a.name, "domain": a.domain, "type": a.data_type}
                           for a in mesh.attributes],
        })
        if obj.name == "GEO-body_male_realistic":
            record["multires"] = [
                {"levels": m.levels, "sculpt_levels": m.sculpt_levels,
                 "total_levels": m.total_levels, "render_levels": m.render_levels}
                for m in obj.modifiers if m.type == "MULTIRES"]
            record["uv_bounds"] = [
                [min(v.uv[i] for v in mesh.uv_layers.active.data),
                 max(v.uv[i] for v in mesh.uv_layers.active.data)] for i in range(2)]
            import numpy as np
            np.savez_compressed(
                OUT.with_suffix(".npz"),
                vertices=np.array([v.co[:] for v in mesh.vertices]),
                faces=np.array([p.vertices[:] for p in mesh.polygons], dtype=object),
                uv=np.array([d.uv[:] for d in mesh.uv_layers.active.data]),
                face_material=np.array([p.material_index for p in mesh.polygons]))
    report["objects"].append(record)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps({"selected_collection": report["selected_collection"],
                  "selected_body": [o for o in report["objects"]
                                    if o["name"] == "GEO-body_male_realistic"],
                  "texts_read_not_executed": report["available_texts"],
                  "available_actions": report["available_actions"]},
                 indent=2, ensure_ascii=False))
