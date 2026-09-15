"""Auditoria pasiva de pruebas archivadas; no reconstruye objetos/handles de proceso."""

from __future__ import annotations

import re
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any

from .common import boolean, diagnostic_output, digest, integer, json_equal, read_json, require
from .smoke import (
    CAPTURE_IDS, CASE_IDS, FINE_AIM, GUI_METHOD,
    assertion_names, mode_changes, native_input, observation, report_metadata, state,
)


def recorded_path(value: str) -> PureWindowsPath | PurePosixPath:
    require(type(value) is str and bool(value), "Falta ruta de la invocacion archivada.")
    path = PureWindowsPath(value) if re.match(r"^(?:[A-Za-z]:[\\/]|\\\\)", value) else PurePosixPath(value)
    require(path.is_absolute() and ".." not in path.parts, "Ruta archivada no absoluta o ambigua.")
    return path


def process_files(directory: Path, *, allow_tool_stderr: bool = False) -> tuple[dict[str, Any], str, str]:
    process = read_json(directory / "process.json")
    require(all((directory / name).is_file() and not (directory / name).is_symlink() and
                (directory / name).stat().st_size <= 32 * 1024 * 1024 for name in ("stdout.log", "stderr.log")),
            "Logs ausentes, no regulares o fuera del limite.")
    stdout_bytes = (directory / "stdout.log").read_bytes()
    stderr_bytes = (directory / "stderr.log").read_bytes()
    for field in ("outputComplete", "stdoutComplete", "stderrComplete"):
        boolean(process[field], True, "archived." + field)
    integer(process["processId"], "archived.processId", 1)
    integer(process["exitCode"], "archived.exitCode")
    for field in ("stdoutBytes", "stderrBytes"):
        integer(process[field], "archived." + field, 0)
    require(process["exitCode"] == 0 and process["error"] == "" and
            process["stdoutBytes"] == len(stdout_bytes) and process["stderrBytes"] == len(stderr_bytes),
            "Proceso archivado fallido, truncado o inconsistente.")
    require(type(process["arguments"]) is list and bool(process["arguments"]), "Faltan argumentos originales.")
    stdout, stderr = diagnostic_output(stdout_bytes, stderr_bytes, allow_tool_stderr=allow_tool_stderr)
    return process, stdout, stderr


def smoke_files(directory: Path, summary: dict[str, Any], identity: dict[str, Any],
                engine: dict[str, Any], contract: dict[str, Any]) -> None:
    protocol = "gameplay" if summary["stage"].endswith("gameplay") else "legacy"
    editor = summary["stage"].startswith("source-")
    require(summary["protocol"] == protocol and summary["editorBinary"] is editor,
            "La etapa cambio de protocolo o binario.")
    specification = contract["protocols"][protocol]["source" if editor else "export"]
    process, stdout, _stderr = process_files(directory / "process")
    for key, value in summary["process"].items():
        require(json_equal(process[key], value), "Resumen de proceso distinto al original.")
    report_path = directory / "report.json"
    report = read_json(report_path)
    require(digest(report_path) == summary["reportSha256"], "El informe no coincide con su resumen.")
    marker = "FUTSAL_GAMEPLAY_SMOKE" if protocol == "gameplay" else "FUTSAL_MATCH_SMOKE"
    names = assertion_names(report, stdout, specification, marker)
    report_metadata(report, protocol=protocol, editor=editor, identity=identity, engine=engine)
    for field in ("passed", "total", "gameplayCases", "observedMoments", "savedPngs"):
        integer(summary[field], "archived.summary." + field, 0)
    require(summary["passed"] == summary["total"] == len(names), "Recuento archivado fabricado.")
    require(report["process_id"] == process["processId"], "PID de reporte distinto al registro original.")
    arguments = process["arguments"]
    require(arguments[1:6] == ["--headless", "--audio-driver", "Dummy", "--fixed-fps", "60"] and
            arguments[-3:] == ["--", "--gameplay-smoke" if protocol == "gameplay" else "--smoke-test",
                               "--report-path=" + report["report_path"]] and
            recorded_path(report["executable"]) == recorded_path(arguments[0]),
            "La CLI archivada no es el recorrido fijo nativo declarado.")
    if editor:
        require(len(arguments) == 11 and arguments[6] == "--path", "Falta ruta fuente original.")
    else:
        require(len(arguments) == 9, "El paquete se probo con argumentos adicionales.")
    default = report["default_entrypoint"]
    boolean(default["verified"], True, "archived.default.verified")
    before = state(default["before"], 1)
    waited = state(default["after_wait"], 1)
    after_input = state(default["after_input"], 1)
    require(before["tick"] < waited["tick"] < after_input["tick"] and
            waited["seconds_remaining"] < before["seconds_remaining"] and
            json_equal(report["loaded_actors"], waited["actors"]), "Default archivado sin avance real.")
    final = state(report["final_state"], 1)
    require(final["phase"] == "PLAYING" and final["selected_actor_id"] == 0, "No se restauro el main normal.")
    mode_changes(report["mode_changes"], specification["modeSequence"])
    require([change["case"] for change in report["focus_changes"]] == specification["focusCases"],
            "Falta micro/preview o transferencia de foco archivada.")
    for change in report["focus_changes"]:
        state(change["before"])
        state(change["after"])
    if protocol != "gameplay":
        require(summary["gameplayCases"] == 0 and summary["observedMoments"] == 0, "Resumen legacy inventa casos.")
        return
    require(summary["gameplayCases"] == 28 and summary["observedMoments"] == 20 and
            report["gui_input_method"] == GUI_METHOD and report["aim_precision_controls"] == FINE_AIM and
            report["aim_precision_max_degrees_per_second"] == 30.0 and report["frames_drawn"] == 0,
            "Protocolo GUI/gameplay archivado distinto.")
    gameplay = report["gameplay"]
    for field in ("started", "complete"):
        boolean(gameplay[field], True, "archived.gameplay." + field)
    boolean(gameplay["capture_complete"], False, "archived.headless.capture_complete")
    require(gameplay["expected_cases"] == gameplay["completed_cases"] == list(CASE_IDS) and
            [case["case"] for case in gameplay["cases"]] == list(CASE_IDS),
            "Un subset de casos no verifica el paquete.")
    observed = []
    for case in gameplay["cases"]:
        case_id = case["case"]
        mode = int(case_id[1])
        require(sorted(case) == specification["caseKeys"][case_id], "Caso archivado incompleto.")
        boolean(case["passed"], True, case_id)
        require(case["source_script"] == "res://match/match.gd", "El caso no procede del main.")
        state(case["before"], mode)
        after = observation(case["after"], case_id, mode, captured=case_id in CAPTURE_IDS)
        require(all(any(json_equal(event, item) for item in report["events"]) for event in after["events"]),
                "Eventos de otro recorrido.")
        if "completion" in case:
            completed = observation(case["completion"], case_id, mode, captured=False)
            require(completed["tick"] >= after["tick"], "Completion anterior al contacto.")
        if case_id in CAPTURE_IDS:
            require(after["capture_status"] == "not_rendered_headless" and after["filename"] == "",
                    "Headless fabricó PNG.")
            observed.append(after)
    for item in gameplay["native_inputs"]:
        native_input(item)
    require({item["class"] for item in gameplay["native_inputs"]} == {
        "InputEventKey", "InputEventJoypadButton", "InputEventJoypadMotion",
        "InputEventMouseButton", "InputEventMouseMotion",
    }, "Falta una clase de input nativo archivada.")
    for field in ("required_png_count", "observed_moment_count", "saved_png_count"):
        integer(gameplay[field], "archived.gameplay." + field, 0)
    require(gameplay["required_png_count"] == gameplay["observed_moment_count"] == 20 and
            gameplay["saved_png_count"] == 0, "Recuentos de observacion incorrectos.")
    manifest_directory = directory / "report-gameplay-captures"
    require({path.name for path in manifest_directory.iterdir()} == {"manifest.json"}, "Capturas headless inesperadas.")
    manifest = read_json(manifest_directory / "manifest.json")
    for field in ("schema_version", "process_id", "required_png_count", "saved_png_count"):
        integer(manifest[field], "archived.manifest." + field, 0)
    original_report = recorded_path(report["report_path"])
    original_directory = original_report.parent / (original_report.stem + "-gameplay-captures")
    require(recorded_path(gameplay["capture_directory"]) == recorded_path(manifest["capture_directory"]) == original_directory and
            recorded_path(gameplay["capture_manifest_path"]) == original_directory / "manifest.json" and
            recorded_path(manifest["report_path"]) == original_report, "Manifiesto archivado de otro run.")
    require(manifest["schema_version"] == 1 and manifest["process_id"] == report["process_id"] and
            manifest["project_version"] == identity["projectVersion"] and
            manifest["driver_script"] == "res://diagnostics/gameplay_smoke.gd" and
            manifest["main_scene"] == identity["mainScene"] and manifest["required_png_count"] == 20 and
            manifest["saved_png_count"] == 0 and json_equal(manifest["captures"], []) and
            json_equal(manifest["observations"], observed),
            "Manifiesto/observaciones archivadas incoherentes.")
    boolean(manifest["headless"], True, "archived.manifest.headless")
    boolean(manifest["editor_binary"], editor, "archived.manifest.editor_binary")
    boolean(manifest["functional_traversal_complete"], True, "archived.manifest.complete")
