from __future__ import annotations

import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .common import (
    boolean, diagnostic_output, integer, json_equal, number, read_json, require,
    same_path, strict_json, text_digest,
)
from .process import ProcessResult

CAPTURE_CASES = (
    "corner_pos_x_neg_z", "corner_pos_x_pos_z", "corner_neg_x_neg_z", "corner_neg_x_pos_z",
    "live_charged_shot", "keeper_clearance_ready", "keeper_clearance_release",
    "dribble_left_contact", "dribble_right_contact", "dribble_pace_contact",
)
RULE_CASES = ("kick_in", "direct_free_kick", "penalty_fine_aim", "accumulated_spot_choice")
CASE_IDS = tuple(f"m{mode}/{case}" for mode in (0, 1) for case in (*CAPTURE_CASES, *RULE_CASES))
CAPTURE_IDS = tuple(f"m{mode}/{case}" for mode in (0, 1) for case in CAPTURE_CASES)
EXERCISES = dict(zip((*CAPTURE_CASES, *RULE_CASES), (2, 3, 4, 5, 0, 6, 6, 7, 7, 8, 1, 9, 10, 11)))
INPUT_METHOD = "Input.parse_input_event; physical keys and raw joypad events, device 0"
GUI_METHOD = "Viewport.push_input; local mouse coordinates, device 0"
FINE_AIM = "Saque propio · Ctrl + (A/D o ←/→) / LT + stick izq. lateral: ajuste fino"
ENVELOPE_KEYS = {
    "athlete_presentations", "camera", "events", "exercise", "guide", "hud_context",
    "hud_fouls", "hud_restart_clock", "hud_restart_title", "hud_selected", "input",
    "interpolation_fraction", "mode", "phase", "render_ball_position", "restart",
    "selected_actor_id", "state", "tick", "visible_home_options",
}
CAPTURE_KEYS = {"accepted_event", "capture_status", "case", "filename"}


def validate_producers(project: Path, contract: dict[str, Any], identity: dict[str, Any]) -> None:
    require(integer(contract["schemaVersion"], "contract.schemaVersion") == 1
            and contract["projectVersion"] == identity["projectVersion"]
            and integer(contract["inputSchemaVersion"], "contract.inputSchemaVersion") == identity["inputSchemaVersion"],
            "Oraculo de smoke no corresponde a version/schema actuales.")
    for name, expected in contract["producers"].items():
        require(text_digest(project / name) == expected,
                f"Productor {name} cambio: actualizar contrato con evidencia y revision, no durante build.")
    for protocol in ("legacy", "gameplay"):
        for variant in ("source", "export"):
            names = contract["protocols"][protocol][variant]["checks"]
            require(bool(names) and len(names) == len(set(names)), "Oraculo con checks duplicados/vacios.")


def godot_output(result: ProcessResult) -> str:
    require(result.ok, f"Proceso/EOF no validos: {result.error}")
    return diagnostic_output(result.stdout, result.stderr)[0]


def _list(value: Any, label: str) -> list[Any]:
    require(type(value) is list, f"Falta array {label}.")
    return value


def _object(value: Any, label: str) -> dict[str, Any]:
    require(type(value) is dict, f"Falta objeto {label}.")
    return value


def _vector(value: Any, size: int, label: str) -> None:
    require(type(value) is list and len(value) == size, f"Vector {label} invalido.")
    for item in value:
        number(item, label)


def _integer_list(value: Any, expected: list[int], label: str) -> None:
    _list(value, label)
    for item in value:
        integer(item, label)
    require(value == expected, f"IDs/orden incorrectos en {label}.")


def state(value: Any, mode: int | None = None) -> dict[str, Any]:
    state_value = _object(value, "estado")
    if mode is not None:
        require(integer(mode, "expected mode") in (0, 1), "Modo esperado fuera del catalogo.")
    current_mode = integer(state_value["mode"], "mode")
    require(current_mode in (0, 1) and mode in (None, current_mode), "Modo de estado incorrecto.")
    ids = list(range(4 if current_mode == 0 else 10))
    integer(state_value["actor_count"], "actor_count")
    require(state_value["actor_count"] == len(ids), "Recuento fisico de actores incorrecto.")
    _integer_list(state_value["physical_actor_ids"], ids, "physical_actor_ids")
    actors = _list(state_value["actors"], "actors")
    require([actor["id"] for actor in actors] == ids, "IDs de actores incompletos/duplicados.")
    selected = integer(state_value["selected_actor_id"], "selected_actor_id")
    require(selected in ids and selected % 2 == 0, "Seleccion fuera de HOME.")
    for actor in actors:
        integer(actor["id"], "actor.id")
        integer(actor["team"], "actor.team")
        integer(actor["role"], "actor.role")
        require(actor["team"] == actor["id"] % 2 and actor["role"] == (1 if actor["id"] in (2, 3) else 0),
                "Rol/equipo del actor incorrecto.")
        boolean(actor["human"], actor["id"] == selected, "actor.human")
        for field in ("ball_in_hands", "ball_contact_reachable"):
            require(type(actor[field]) is bool, f"Actor sin booleano {field}.")
        for field in ("sequence", "gesture_started_tick"):
            integer(actor[field], "actor." + field, -1)
        for field in ("gesture_kind", "gesture_duration_ticks"):
            integer(actor[field], "actor." + field, 0)
        for field in ("position", "velocity", "gesture_direction", "gesture_contact_position"):
            _vector(actor[field], 3, "actor." + field)
    intent = _list(state_value["ai_intent_actor_ids"], "ai_intent")
    for actor_id in intent:
        integer(actor_id, "ai_intent.id")
    require(intent == sorted(set(intent)) and set(intent).issubset(ids), "Intencion IA invalida.")
    _integer_list(state_value["ai_actor_ids"], [item for item in intent if item != selected], "IA efectiva")
    for field in ("tick", "driver_start_calls", "training_exercise", "human_control_context", "period_state"):
        integer(state_value[field], "state." + field, 0)
    require(type(state_value["phase"]) is str and state_value["phase"] in
            ("READY", "PLAYING", "GOAL_PAUSE", "RESTART_PAUSE", "PAUSED", "FINISHED"),
            "state.phase debe ser el nombre literal de Phase, no su ordinal.")
    integer(state_value["human_sequence"], "human_sequence", -1)
    require(0 <= state_value["training_exercise"] <= 11, "Ejercicio fuera del catalogo.")
    for field in ("ball_position", "ball_velocity"):
        _vector(state_value[field], 3, field)
    number(state_value["seconds_remaining"], "seconds_remaining")
    for field in ("score", "accumulated_fouls"):
        values = _list(state_value[field], field)
        require(len(values) == 2, "Faltan contadores de ambos equipos.")
        for item in values:
            integer(item, field, 0)
    for item in _list(state_value["human_allowed_actions"], "human_allowed_actions"):
        integer(item, "human_allowed_actions.item", 0)
    require(type(state_value["selected_can_move"]) is bool, "selected_can_move no es booleano.")
    integer(state_value["ball_owner_id"], "ball_owner_id", -1)
    require(state_value["ball_owner_id"] in [-1, *ids], "Ball owner ausente.")
    for field in ("extended_restart_id", "extended_kick_event_id"):
        integer(state_value[field], field, -1)
    _object(state_value["restart"], "restart")
    return state_value


def native_input(value: Any) -> None:
    item = _object(value, "input")
    integer(item["device"], "input.device")
    require(item["device"] == 0, "Input no procede del dispositivo cero.")
    integer(item["tick"], "input.tick", 0)
    require(type(item["case"]) is str, "Falta identidad del input.")
    kind = item["class"]
    require(kind in ("InputEventKey", "InputEventJoypadButton", "InputEventJoypadMotion",
                     "InputEventMouseButton", "InputEventMouseMotion"), "Clase de input desconocida.")
    if kind == "InputEventJoypadMotion":
        integer(item["axis"], "input.axis", 0)
        require(-1 <= number(item["axis_value"], "input.axis_value") <= 1, "Eje fuera de rango.")
    elif kind == "InputEventMouseMotion":
        _vector(item["position"], 2, "mouse.position")
        _vector(item["relative"], 2, "mouse.relative")
    else:
        require(type(item["pressed"]) is bool, "pressed no es booleano.")
        if kind == "InputEventKey":
            integer(item["physical_keycode"], "physical_keycode", 1)
            boolean(item["echo"], False, "input.echo")
        else:
            integer(item["button_index"], "button_index", 0)
            if kind == "InputEventMouseButton":
                _vector(item["position"], 2, "mouse.position")


def _presentation(value: Any, mode: int, tick: int) -> None:
    samples = _list(value, "athlete_presentations")
    require([item["actor_id"] for item in samples] == list(range(4 if mode == 0 else 10)),
            "Presentacion no incluye todos los actores fisicos.")
    for item in samples:
        integer(item["actor_id"], "athlete.actor_id", 0)
        boolean(item["context_valid"], True, "athlete.context_valid")
        require(item["validation_error"] == "" and
                item["source_script"] == "res://match/presentation/athletes/athlete_view.gd",
                "Error/origen de presentacion incorrecto.")
        integer(item["context_tick"], "context_tick", 0)
        integer(item["context_before_tick"], "context_before_tick", 0)
        require(item["context_before_tick"] <= item["context_tick"] <= tick, "Presentacion de un tick futuro.")
        require(0 <= number(item["render_tick"], "render_tick") <= tick, "Render tick futuro.")
        for field in ("feet", "hands"):
            limbs = _list(item[field], field)
            require(len(limbs) == 2, "Pose incompleta.")
            for limb in limbs:
                for basis in ("basis_x", "basis_y", "basis_z", "origin"):
                    _vector(limb[basis], 3, "limb." + basis)
                boolean(limb["visible"], True, "limb.visible")


def observation(value: Any, case_id: str, mode: int, *, captured: bool) -> dict[str, Any]:
    obs = _object(value, case_id)
    require(set(obs) == ENVELOPE_KEYS | (CAPTURE_KEYS if captured else set()),
            "Envelope de observacion/cierre no corresponde al productor.")
    require(obs["mode"] == mode and (not captured or obs["case"] == case_id), "Observacion de otro caso/modo.")
    current = state(obs["state"], mode)
    integer(obs["tick"], "observation.tick", 0)
    for field in ("mode", "exercise", "selected_actor_id"):
        integer(obs[field], "observation." + field, 0)
    require(obs["tick"] == current["tick"] and obs["selected_actor_id"] == current["selected_actor_id"],
            "Observacion no coincide con autoridad.")
    require(obs["phase"] == current["phase"] and json_equal(obs["restart"], current["restart"]),
            "Fase/reanudacion observadas no corresponden al estado.")
    require(obs["exercise"] == EXERCISES[case_id.split("/")[1]] == current["training_exercise"],
            "Ejercicio observado no coincide con el catalogo literal.")
    _object(obs["camera"], "camera")
    _object(obs["guide"], "guide")
    if captured:
        event = _object(obs["accepted_event"], "accepted_event")
        name = case_id.split("/")[1]
        if name in ("keeper_clearance_release", "dribble_left_contact", "dribble_right_contact", "dribble_pace_contact"):
            require(bool(event) and any(json_equal(event, item) for item in obs["events"]),
                    "Contacto aceptado ausente del historial del caso.")
            integer(event["kind"], "accepted_event.kind", 0)
            require(event["kind"] == (1 if name == "keeper_clearance_release" else 11),
                    "Tipo de contacto aceptado incorrecto.")
        else:
            require(event == {}, "La preparacion/carga no puede inventar contacto aceptado.")
    _vector(obs["render_ball_position"], 3, "render_ball_position")
    require(0 <= number(obs["interpolation_fraction"], "interpolation") <= 1, "Interpolacion invalida.")
    events = _list(obs["events"], "events")
    require(bool(events), "Faltan eventos productivos del caso.")
    for item in _list(obs["input"], "input"):
        native_input(item)
    _presentation(obs["athlete_presentations"], mode, obs["tick"])
    return obs


def _gameplay(report: dict[str, Any], report_path: Path, result: ProcessResult, editor: bool,
              specification: dict[str, Any]) -> None:
    gameplay = _object(report["gameplay"], "gameplay")
    boolean(gameplay["started"], True, "gameplay.started")
    boolean(gameplay["complete"], True, "gameplay.complete")
    boolean(gameplay["capture_complete"], False, "headless.capture_complete")
    require(gameplay["expected_cases"] == list(CASE_IDS) == gameplay["completed_cases"],
            "Se requieren los 28 casos literales completos; un subset no es valido.")
    cases = _list(gameplay["cases"], "gameplay.cases")
    require([case["case"] for case in cases] == list(CASE_IDS), "Casos faltantes, extra o duplicados.")
    observations = {}
    all_events = report["events"]
    for case in cases:
        case_id = case["case"]
        mode = int(case_id[1])
        require(sorted(case) == specification["caseKeys"][case_id], "Forma del caso incompleta o alterada.")
        boolean(case["passed"], True, case_id + ".passed")
        require(case["source_script"] == "res://match/match.gd", "Caso no productivo.")
        before = state(case["before"], mode)
        after = observation(case["after"], case_id, mode, captured=case_id in CAPTURE_IDS)
        require(after["tick"] >= before["tick"], "Caso retrocede ticks.")
        for event in after["events"]:
            require(any(json_equal(event, item) for item in all_events),
                    "El caso inventa un evento ausente del historial global.")
        if "completion" in case:
            completion = observation(case["completion"], case_id, mode, captured=False)
            require(completion["tick"] >= after["tick"], "Completion anterior a la observacion.")
        if case_id in CAPTURE_IDS:
            require(after["capture_status"] == "not_rendered_headless" and after["filename"] == "",
                    "Headless afirma una captura.")
            require(not set(after).intersection(("width", "height", "render_valid", "sha256")),
                    "Headless contiene metadata PNG.")
            observations[case_id] = after
    inputs = _list(gameplay["native_inputs"], "gameplay.native_inputs")
    require(bool(inputs), "No hay input nativo.")
    for item in inputs:
        native_input(item)
    require({item["class"] for item in inputs} == {
        "InputEventKey", "InputEventJoypadButton", "InputEventJoypadMotion",
        "InputEventMouseButton", "InputEventMouseMotion",
    }, "Falta una ruta de input real.")
    _list(gameplay["athlete_presentations"], "gameplay.athlete_presentations")
    for field, expected in (("required_png_count", 20), ("observed_moment_count", 20), ("saved_png_count", 0)):
        integer(gameplay[field], field)
        require(gameplay[field] == expected, f"Recuento incorrecto {field}.")
    capture_directory = report_path.parent / (report_path.stem + "-gameplay-captures")
    manifest_path = capture_directory / "manifest.json"
    require(same_path(gameplay["capture_directory"], capture_directory) and
            same_path(gameplay["capture_manifest_path"], manifest_path), "Capturas fuera del run propietario.")
    require(set(path.name for path in capture_directory.iterdir()) == {"manifest.json"},
            "Headless creo capturas u otros archivos inesperados.")
    require(manifest_path.stat().st_mtime_ns >= result.started_ns, "Manifiesto obsoleto.")
    manifest = read_json(manifest_path)
    for key, expected in (
        ("schema_version", 1), ("process_id", result.pid), ("required_png_count", 20), ("saved_png_count", 0),
    ):
        integer(manifest[key], "manifest." + key)
        require(manifest[key] == expected, "Identidad/recuentos de manifiesto incorrectos.")
    boolean(manifest["headless"], True, "manifest.headless")
    boolean(manifest["editor_binary"], editor, "manifest.editor_binary")
    boolean(manifest["functional_traversal_complete"], True, "manifest.complete")
    require(manifest["project_version"] == report["project_version"] and
            manifest["driver_script"] == "res://diagnostics/gameplay_smoke.gd" and
            manifest["main_scene"] == report["main_scene"] and
            same_path(manifest["report_path"], report_path) and
            same_path(manifest["capture_directory"], capture_directory), "Manifiesto de otro productor/run.")
    require(json_equal(manifest["captures"], []) and
            json_equal(manifest["observations"], [observations[key] for key in CAPTURE_IDS]),
            "El manifiesto no corresponde a las veinte observaciones reales.")


def assertion_names(report: dict[str, Any], stdout: str, specification: dict[str, Any],
                    marker: str) -> list[str]:
    markers = re.findall(r"(?m)^(FUTSAL_[A-Z0-9_]+) (.+)$", stdout)
    require(len(markers) == 1 and markers[0][0] == marker, "Marker nativo ausente/extra/incorrecto.")
    require(json_equal(strict_json(markers[0][1]), report), "JSON de stdout y archivo difieren en valor/tipo.")
    require(sorted(report) == specification["rootKeys"], "Schema nativo cambio u omitio campos.")
    names = []
    for check in _list(report["checks"], "checks"):
        require(set(check) == {"name", "passed"} and type(check["name"]) is str, "Check no tipado.")
        boolean(check["passed"], True, check["name"])
        names.append(check["name"])
    require(names == specification["checks"] and len(set(names)) == len(names),
            "Falta/cambio/duplicacion de una asercion literal del recorrido completo.")
    require(re.findall(r"(?m)^PASS (.+)$", stdout) == names, "PASS impresos difieren del informe.")
    for key in ("passed", "total"):
        integer(report[key], key)
        require(report[key] == len(names), "Conteos no corresponden a checks reales.")
    for key in ("ok", "complete"):
        boolean(report[key], True, key)
    for key in ("command_rejections", "integration_errors", "failures"):
        require(type(report[key]) is list and report[key] == [], f"Hay {key} o falta su evidencia.")
    return names


def report_metadata(report: dict[str, Any], *, protocol: str, editor: bool,
                    identity: dict[str, Any], engine: dict[str, Any]) -> None:
    expected = {
        "project_version": identity["projectVersion"], "project_name": identity["projectName"],
        "input_schema_version": identity["inputSchemaVersion"], "engine_version": engine["reportVersion"],
        "main_scene": identity["mainScene"], "configured_main_scene": identity["mainScene"],
        "scope": "playable-gameplay-runtime-smoke" if protocol == "gameplay" else "playable-preview-runtime-smoke",
        "display_server": "headless", "rendering_method": "headless", "rendering_driver": "dummy",
        "gpu_name": "not measured (headless)", "gpu_api": "", "viewport_width": 1920, "viewport_height": 1080,
        "physics_engine": "Jolt Physics", "physics_ticks_per_second": 60, "mode": 1, "final_mode": 1,
        "final_actor_count": 10, "initial_selected_actor_id": 0, "capture_phase": "PLAYING",
        "input_method": INPUT_METHOD,
    }
    for key, value in expected.items():
        require(json_equal(report[key], value), f"Metadata incorrecta: {key}")
    boolean(report["editor_binary"], editor, "editor_binary")
    boolean(report["headless"], True, "headless")
    boolean(report["gpu_validated"], False, "gpu_validated")
    integer(report["process_id"], "process_id", 1)
    for field in ("driver_start_calls", "initial_tick", "final_tick"):
        integer(report[field], field, 0)
    if protocol == "gameplay":
        require(integer(report["frames_drawn"], "frames_drawn") == 0 and
                integer(report["watchdog_msec"], "watchdog_msec") == 120000,
                "GPU/watchdog inventados.")


def mode_changes(value: Any, expected: list[int]) -> None:
    changes = _list(value, "mode_changes")
    modes = [integer(_object(item, "mode change")["requested_mode"], "requested_mode") for item in changes]
    require(json_equal(modes, expected), "Falta un cambio real micro/preview.")
    for item in changes:
        state(item["before"])
        state(item["after"], item["requested_mode"])


def validate_report(result: ProcessResult, report_path: Path, executable: Path, *, protocol: str,
                    editor: bool, identity: dict[str, Any], engine: dict[str, Any],
                    contract: dict[str, Any]) -> dict[str, Any]:
    stdout = godot_output(result)
    require(report_path.is_file() and report_path.stat().st_mtime_ns >= result.started_ns,
            "El proceso no produjo un informe nuevo.")
    report = read_json(report_path)
    marker = "FUTSAL_GAMEPLAY_SMOKE" if protocol == "gameplay" else "FUTSAL_MATCH_SMOKE"
    specification = contract["protocols"][protocol]["source" if editor else "export"]
    names = assertion_names(report, stdout, specification, marker)
    report_metadata(report, protocol=protocol, editor=editor, identity=identity, engine=engine)
    for field in ("authority_path", "camera_path", "development_menu_path", "hud_path",
                  "final_hud_mode", "final_hud_selected", "timestamp_utc"):
        require(type(report[field]) is str and bool(report[field]), f"Falta string {field}.")
    authority = report["authority_path"]
    require(authority.startswith("/root/") and authority.count("/") >= 3, "Autoridad no pertenece al main.")
    host = authority.rsplit("/", 1)[0]
    require(report["camera_path"] == host + "/BroadcastCamera" and
            all(report[field].startswith(host + "/") for field in ("hud_path", "development_menu_path")),
            "Camara/HUD/menu no pertenecen al main productivo.")
    require(report["final_hud_selected"] == "CONTROL · ID 0\nCAMPO LOCAL", "HUD final de otro foco.")
    require(bool(_list(report["limitations"], "limitations")), "Faltan limites de la evidencia.")
    require(report["process_id"] == result.pid and same_path(report["executable"], executable) and
            same_path(report["report_path"], report_path), "Informe no pertenece al Popen/executable/ruta originales.")
    timestamp = datetime.fromisoformat(report["timestamp_utc"].replace("Z", "+00:00"))
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    require(result.started_ns / 1e9 - 2 <= timestamp.timestamp() <= time.time() + 1,
            "Timestamp del informe fuera de esta invocacion.")
    require(0 < number(report["wall_seconds"], "wall_seconds") <= (121 if protocol == "gameplay" else 61),
            "Watchdog nativo excedido.")
    default = _object(report["default_entrypoint"], "default_entrypoint")
    boolean(default["verified"], True, "default.verified")
    before = state(default["before"], 1)
    after_wait = state(default["after_wait"], 1)
    after_input = state(default["after_input"], 1)
    require(after_wait["tick"] > before["tick"] and after_wait["seconds_remaining"] < before["seconds_remaining"]
            and after_input["tick"] > after_wait["tick"], "El default no avanzo realmente.")
    require(json_equal(report["loaded_actors"], after_wait["actors"]) and report["initial_tick"] == after_wait["tick"],
            "Actores/default de otra sesion.")
    _integer_list(report["initial_ai_actor_ids"], list(range(1, 10)), "initial_ai_actor_ids")
    _integer_list(report["initial_ai_intent_actor_ids"], list(range(10)), "initial_ai_intent")
    final = state(report["final_state"], 1)
    require(report["final_tick"] == final["tick"] and final["selected_actor_id"] == 0 and final["phase"] == "PLAYING",
            "No se restauro la preview final.")
    mode_changes(report["mode_changes"], specification["modeSequence"])
    focus = _list(report["focus_changes"], "focus_changes")
    require([item["case"] for item in focus] == specification["focusCases"], "Falta transferencia de foco.")
    for item in focus:
        state(item["before"])
        state(item["after"])
    require({item["control"] for item in report["inputs"]}.issuperset({
        "keyboard D", "keyboard W", "joypad left X", "joypad left Y",
        "Esc / Start", "Start / Esc", "Esc / Down / Enter restart",
        "development AI mode 1", "development AI mode 0",
    }), "Falta evidencia de teclado/mando/pausa/IA.")
    require(len(report["ai_changes"]) == 2 and bool(report["events"]), "Falta historial IA/eventos.")
    if protocol == "gameplay":
        require(report["gameplay_driver_script"] == "res://diagnostics/gameplay_smoke.gd" and
                report["gui_input_method"] == GUI_METHOD and report["aim_precision_controls"] == FINE_AIM,
                "Driver, GUI o controles de precision distintos.")
        require(abs(number(report["aim_precision_max_degrees_per_second"], "fine aim") - 30) < 0.00001,
                "Ajuste fino no coincide con el contrato.")
        _gameplay(report, report_path, result, editor, specification)
    return {
        "protocol": protocol, "editorBinary": editor, "passed": len(names), "total": len(names),
        "modes": [0, 1], "headless": True, "renderedValidated": False,
        "gameplayCases": 28 if protocol == "gameplay" else 0,
        "observedMoments": 20 if protocol == "gameplay" else 0, "savedPngs": 0,
    }
