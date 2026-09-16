"""Build the final R3 clothes from the preserved source, without rebuilding anatomy.

Blender --background --factory-startup --disable-autoexec --python-exit-code 1
        --python rebuild_wardrobe.py -- --final-r3
No game, release, integration, rig-rest, skin or boot edits. No source copies.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import atlas_tools as atlas
import build_athlete as build
import contact_locators as contacts
import inspect_athlete as inspection
import mesh_tools as mt
import rig_material_contract as driver


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repair_r3_map_links():
    path = HERE / "court_athlete.blend"
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    if manifest["revision"] != "athlete-upgrade-r3" or sha256(path) != manifest["source_sha256"]:
        raise ValueError("Map-link repair requires the declared R3 source")
    bpy.ops.wm.open_mainfile(filepath=str(path), use_scripts=False)
    rig = bpy.data.objects["CourtAthlete"]
    meshes = [bpy.data.objects[name] for name in driver.MESH_NAMES]
    before = {obj.name: driver.geometry_fingerprint(obj) for obj in meshes}
    links = atlas.runtime_map_links(HERE / "maps", relink=True)
    if not all(links.values()):
        raise ValueError(f"Cannot resolve preserved material maps: {links}")
    structural = inspection.validate()
    if structural["passed"] != structural["total"]:
        raise ValueError(json.dumps(structural, indent=2))
    if {obj.name: driver.geometry_fingerprint(obj) for obj in meshes} != before:
        raise ValueError("Map-link repair changed R3 geometry")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    previous = manifest["source_sha256"]
    current = sha256(path)
    bones = build.skeleton_report(rig)
    bones["contact_contract"]["source_sha256"] = current
    contacts.save_json(HERE / "rig_manifest.json", bones)
    manifest["source_sha256"] = current
    manifest["source_bytes"] = path.stat().st_size
    manifest["contact_contract"]["source_sha256"] = current
    manifest["r3"]["source_structural_validation"] = structural
    manifest["r3"]["technical_map_link_repair"] = {
        "previous_source_sha256": previous, "source_sha256": current,
        "cause": "Blender // relative paths were incorrectly parsed as Windows UNC paths.",
        "all_mesh_geometry_weights_uv_and_COLOR0_unchanged": before,
        "map_pixels_changed": False, "art_round_added": False,
        "map_links": links,
    }
    contacts.save_json(HERE / "manifest.json", manifest)
    print("R3_MAP_LINKS_REPAIRED", current, json.dumps(links), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    operation = parser.add_mutually_exclusive_group(required=True)
    operation.add_argument("--final-r3", action="store_true")
    operation.add_argument("--repair-r3-map-links", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.repair_r3_map_links:
        repair_r3_map_links()
        return
    if not args.final_r3:
        raise SystemExit("Explicit --final-r3 is required for the last authorized art pass.")
    path = HERE / "court_athlete.blend"
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    previous_hash = sha256(path)
    if previous_hash != manifest["source_sha256"] or manifest["revision"] != "athlete-upgrade-r2":
        raise ValueError("R3 must start from the declared R2 source; do not create another art round.")
    feedback = (REPO / ".dream-loop" / "athlete-upgrade" / "builds"
                / "r2-capture-c496a18b506c4b1ca6ecbf733906aa3a" / "captures" / "manifest.json")
    feedback_hash = sha256(feedback)
    bpy.ops.wm.open_mainfile(filepath=str(path), use_scripts=False)
    rig = bpy.data.objects["CourtAthlete"]
    skin, gear = bpy.data.objects["AthleteSkinMesh"], bpy.data.objects["AthleteGearMesh"]
    preserved = {obj.name: driver.geometry_fingerprint(obj) for obj in (skin, gear)}
    rests = {bone.name: [list(row) for row in bone.matrix_local] for bone in rig.data.bones}
    preserved_maps = {record["file"]: record["sha256"] for record in manifest["textures"]
                      if not record["file"].startswith("kit_")}
    reference = bpy.data.objects["AnatomicalWeightReference"]
    old_kit = bpy.data.objects["AthleteKitMesh"]
    collection = old_kit.users_collection[0]
    work = bpy.data.collections.new("R3_Wardrobe_Authoring")
    bpy.context.scene.collection.children.link(work)
    build.RIG = rig
    build.KIT_PARTS.clear()
    build.GARMENT_REPORT.clear()
    print("R3: anatomical fit, shared waist weights and sewn turnbacks", flush=True)
    build.make_wardrobe(reference, work, mt.weight_reference(reference))
    material = bpy.data.materials["AthleteKit"]
    kit = mt.join_meshes(build.KIT_PARTS, "R3Kit_Work", rig, material)
    bpy.data.objects.remove(old_kit, do_unlink=True)
    kit.name = "AthleteKitMesh"
    kit.data.name = "AthleteKitMesh_Mesh"
    collection.objects.link(kit)
    work.objects.unlink(kit)
    bpy.data.collections.remove(work)
    meshes = [skin, kit, gear]
    stats = [build.mesh_stats(obj) for obj in meshes]
    triangles = sum(item["triangles"] for item in stats)
    if triangles > 60000:
        raise ValueError(f"R3 triangle budget exceeded before baking: {triangles}")
    if any(item["unweighted_vertices"] or item["max_influences"] > 4
           or item["max_normalization_error"] > 1e-5 for item in stats):
        raise ValueError("R3 inherited garment weights are invalid")
    print("R3_GEOMETRY", triangles, "triangles", len(kit.data.vertices), "kit vertices", flush=True)
    staged = REPO / ".dream-loop" / "athlete-upgrade" / "r3-master-work" / "maps"
    print("R3: bake only the five kit masters, preserving skin and gear PBR", flush=True)
    maps = atlas.rasterize(kit, staged, "kit", 2048, build.EYE_Z)
    atlas.setup_material(material, staged, "kit")
    atlas.bake_local_ao(kit, material, staged / "kit_ao.png", maps.pop("orm_work"))
    atlas.setup_material(material, staged, "kit")
    driver.add_color0(kit, staged / "kit_mask.png")
    checks = driver.validate_driver_contract(rig, skin, kit, gear, staged / "kit_mask.png")
    if checks["passed"] != checks["total"]:
        raise ValueError(json.dumps({"driver": checks}, indent=2))
    if {obj.name: driver.geometry_fingerprint(obj) for obj in (skin, gear)} != preserved:
        raise ValueError("Clothing rebuild changed skin, hands, face or boots")
    if {bone.name: [list(row) for row in bone.matrix_local] for bone in rig.data.bones} != rests:
        raise ValueError("Clothing rebuild changed the rig/Palm rest transforms")
    for name, digest in preserved_maps.items():
        if sha256(HERE / "maps" / name) != digest:
            raise ValueError(f"Clothing rebuild changed an unrelated master: {name}")
    for suffix in ("albedo", "normal", "orm", "ao", "mask"):
        name = "kit_" + suffix + ".png"
        shutil.copyfile(staged / name, HERE / "maps" / name)
    atlas.setup_material(material, HERE / "maps", "kit")
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)
        else:
            image.filepath = "//maps/" + Path(bpy.path.abspath(image.filepath)).name
    links = atlas.runtime_map_links(HERE / "maps", relink=True)
    if not all(links.values()):
        raise ValueError(f"R3 runtime PBR map links are invalid: {links}")
    structural = inspection.validate()
    if structural["passed"] != structural["total"]:
        raise ValueError(json.dumps(structural, indent=2))
    bpy.context.scene["asset_revision"] = build.REVISION
    bpy.context.scene["art_rounds_used"] = 3
    bpy.context.scene["remaining_art_rounds"] = 0
    rig["asset_revision"] = build.REVISION
    bpy.context.preferences.filepaths.save_version = 0
    mt.active(rig)
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    current_hash = sha256(path)
    bones = build.skeleton_report(rig)
    bones["contact_contract"]["source_sha256"] = current_hash
    contact_checks = contacts.validate_contract(bones["contact_contract"], rig, skin)
    if contact_checks["passed"] != contact_checks["total"]:
        raise ValueError(json.dumps(contact_checks, indent=2))
    contacts.save_json(HERE / "rig_manifest.json", bones)
    manifest.update({
        "revision": build.REVISION, "status": "r3_final_source_pending_self_inspection",
        "source_sha256": current_hash, "source_bytes": path.stat().st_size,
        "visible_triangles": triangles,
        "visible_vertices": sum(len(obj.data.vertices) for obj in meshes),
        "meshes": [build.mesh_stats(obj) for obj in meshes],
        "garments": build.GARMENT_REPORT,
        "textures": [atlas.file_record(file) for file in sorted((HERE / "maps").glob("*.png"))],
        "contact_contract": {
            "file": "rig_manifest.json", "key": "contact_contract", "schema_version": 2,
            "source_sha256": current_hash, "validation": contact_checks},
        "driver_contract_adaptation": {"validation": checks, "game_exported": False},
        "source_inspection": {"status": "pending final R3 source inspection", "art_approved": False},
        "r3": {
            "baseline_source_sha256": previous_hash,
            "integrated_feedback_manifest": str(feedback.relative_to(REPO)),
            "integrated_feedback_manifest_sha256": feedback_hash,
            "feedback_is_independent_verdict": False,
            "art_rounds_used": 3, "remaining_art_rounds": 0,
            "skin_and_gear_geometry_weights_uv_unchanged": preserved,
            "all_54_rest_transforms_and_Palm_unchanged": True,
            "skin_and_gear_master_maps_unchanged": preserved_maps,
            "only_kit_five_maps_regenerated": True,
            "skin_pore_or_gloss_compensation": False,
            "kit_micro_normal_amplitude": {"previous": 0.047, "current": 0.015},
            "source_structural_validation": structural,
            "game_import_and_art_review_of_R3": "pending",
            "scope": "Clothes only; no retarget, anatomy scaling, foot target, lighting, shader or physics edits.",
        },
        "limitations": [
            "Final authorized R3 pass; no independent artistic approval or FPS evidence.",
            "Clearance/closure in real retargeted motion must be reviewed on this R3 hash.",
            "R2 native test/capture results do not certify the changed R3 mesh.",
            "Retarget elbows, toe-out, sole height, skin tint/roughness and camera belong to coordination.",
            "No facial rig, new motion clips, LODs or cloth/hair simulation.",
        ],
    })
    manifest["map_rasterization"]["kit"] = maps
    manifest["texture_contract"]["kit_mask_binding"] = bones["contact_contract"]["kit_mask_binding"]
    contacts.save_json(HERE / "manifest.json", manifest)
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    provenance["r3_tailoring"] = "Own anatomical cloth clearance, connected turnbacks, inherited weights and quiet kit weave; source skin/gear/rig rest unchanged."
    contacts.save_json(HERE / "provenance.json", provenance)
    for suffix in ("albedo", "normal", "orm", "ao", "mask"):
        (staged / ("kit_" + suffix + ".png")).unlink()
    print("R3_SOURCE_READY", json.dumps({
        "source_sha256": current_hash, "triangles": triangles,
        "vertices": manifest["visible_vertices"], "bones": len(rests),
        "driver_checks": [checks["passed"], checks["total"]],
        "structure_checks": [structural["passed"], structural["total"]],
        "contact_checks": [contact_checks["passed"], contact_checks["total"]],
        "game_written": False, "art_rounds_remaining": 0,
    }, indent=2), flush=True)


if __name__ == "__main__":
    main()
