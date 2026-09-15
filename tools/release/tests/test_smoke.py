from __future__ import annotations

import copy
import json
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.release.build import HERE
from tools.release.common import ReleaseError, load_manifest, project_identity, read_json
from tools.release.process import ProcessResult
from tools.release.smoke import (
    CAPTURE_IDS, CAPTURE_KEYS, CASE_IDS, EXERCISES, FINE_AIM, GUI_METHOD, INPUT_METHOD, native_input,
    state, validate_producers, validate_report,
)

REPOSITORY = HERE.parents[1]


def actor(actor_id: int, selected: int) -> dict:
    return {"id": actor_id, "team": actor_id % 2, "role": 1 if actor_id in (2, 3) else 0,
            "human": actor_id == selected, "position": [0.0, 0.0, 0.0], "velocity": [0.0, 0.0, 0.0],
            "sequence": 5, "ball_in_hands": False, "ball_contact_reachable": True,
            "gesture_kind": 0, "gesture_started_tick": -1, "gesture_duration_ticks": 0,
            "gesture_direction": [0.0, 0.0, 0.0], "gesture_contact_position": [0.0, 0.0, 0.0]}


def fixture_state(mode: int = 1, tick: int = 1, exercise: int = 0) -> dict:
    ids = list(range(4 if mode == 0 else 10))
    return {"mode": mode, "tick": tick, "actor_count": len(ids), "physical_actor_ids": ids,
            "actors": [actor(value, 0) for value in ids], "selected_actor_id": 0,
            "ai_intent_actor_ids": ids, "ai_actor_ids": ids[1:], "driver_start_calls": 1,
            "training_exercise": exercise, "phase": "PLAYING", "human_sequence": tick,
            "ball_position": [0.0, 0.0, 0.0], "ball_velocity": [0.0, 0.0, 0.0],
            "seconds_remaining": 120 - tick / 60, "restart": {}, "score": [0, 0],
            "accumulated_fouls": [0, 0], "human_allowed_actions": [0, 1, 5, 2],
            "human_control_context": 1, "period_state": 0, "selected_can_move": True,
            "ball_owner_id": 0, "extended_restart_id": -1, "extended_kick_event_id": -1}


def input_records(case: str = "") -> list[dict]:
    base = {"case": case, "device": 0, "tick": 60}
    return [
        {**base, "class": "InputEventKey", "physical_keycode": 74, "pressed": True, "echo": False},
        {**base, "class": "InputEventJoypadButton", "button_index": 0, "pressed": True},
        {**base, "class": "InputEventJoypadMotion", "axis": 0, "axis_value": 0.5},
        {**base, "class": "InputEventMouseButton", "button_index": 1, "pressed": True, "position": [5.0, 5.0]},
        {**base, "class": "InputEventMouseMotion", "position": [5.0, 5.0], "relative": [1.0, 0.0]},
    ]


def poses(mode: int, tick: int) -> list[dict]:
    limb = {"basis_x": [1.0, 0.0, 0.0], "basis_y": [0.0, 1.0, 0.0], "basis_z": [0.0, 0.0, 1.0],
            "origin": [0.0, 0.0, 0.0], "visible": True}
    return [{"actor_id": value, "context_valid": True, "validation_error": "",
             "source_script": "res://match/presentation/athletes/athlete_view.gd",
             "context_before_tick": tick - 1, "context_tick": tick, "render_tick": float(tick - 1),
             "feet": [copy.deepcopy(limb), copy.deepcopy(limb)], "hands": [copy.deepcopy(limb), copy.deepcopy(limb)]}
            for value in range(4 if mode == 0 else 10)]


class SmokeFixture:
    """Datos sinteticos de unidad; nunca evidencia de un proceso Godot."""

    def __init__(self, root: Path, protocol: str, editor: bool) -> None:
        self.root = root
        self.report_path = root / "report.json"
        self.executable = root / "fixture-executable"
        self.contract = read_json(HERE / "smoke-contract.json")
        self.identity = project_identity(REPOSITORY / "game")
        self.engine = load_manifest(HERE / "manifest.json")["engine"]
        self.protocol = protocol
        self.editor = editor
        self.started = time.time_ns() - 100_000_000
        self.spec = self.contract["protocols"][protocol]["source" if editor else "export"]
        report = {key: None for key in self.spec["rootKeys"]}
        report.update({
            "checks": [{"name": name, "passed": True} for name in self.spec["checks"]],
            "passed": len(self.spec["checks"]), "total": len(self.spec["checks"]), "ok": True, "complete": True,
            "command_rejections": [], "integration_errors": [], "failures": [], "process_id": 12345,
            "project_version": self.identity["projectVersion"], "project_name": self.identity["projectName"],
            "input_schema_version": 3, "engine_version": self.engine["reportVersion"],
            "main_scene": self.identity["mainScene"], "configured_main_scene": self.identity["mainScene"],
            "scope": "playable-gameplay-runtime-smoke" if protocol == "gameplay" else "playable-preview-runtime-smoke",
            "display_server": "headless", "rendering_method": "headless", "rendering_driver": "dummy",
            "gpu_name": "not measured (headless)", "gpu_api": "", "gpu_validated": False,
            "viewport_width": 1920, "viewport_height": 1080, "physics_engine": "Jolt Physics",
            "physics_ticks_per_second": 60, "mode": 1, "final_mode": 1, "final_actor_count": 10,
            "initial_selected_actor_id": 0, "capture_phase": "PLAYING", "input_method": INPUT_METHOD,
            "editor_binary": editor, "headless": True, "executable": str(self.executable),
            "report_path": str(self.report_path), "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "wall_seconds": 1.0, "initial_tick": 13, "final_tick": 63, "driver_start_calls": 1,
            "default_entrypoint": {"verified": True, "before": fixture_state(tick=1),
                                   "after_wait": fixture_state(tick=13), "after_input": fixture_state(tick=31)},
            "loaded_actors": fixture_state(tick=13)["actors"],
            "initial_ai_actor_ids": list(range(1, 10)), "initial_ai_intent_actor_ids": list(range(10)),
            "final_state": fixture_state(tick=63),
            "mode_changes": [{"requested_mode": mode, "before": fixture_state(), "after": fixture_state(mode)}
                             for mode in self.spec["modeSequence"]],
            "focus_changes": [{"case": case, "before": fixture_state(), "after": fixture_state()}
                              for case in self.spec["focusCases"]],
            "inputs": [{"control": name} for name in ("keyboard D", "keyboard W", "joypad left X", "joypad left Y",
                       "Esc / Start", "Start / Esc", "Esc / Down / Enter restart",
                       "development AI mode 1", "development AI mode 0")],
            "ai_changes": [{}, {}], "events": [{"kind": 1, "tick": 60}, {"kind": 11, "tick": 60}],
            "authority_path": "/root/Match/Simulation", "camera_path": "/root/Match/BroadcastCamera",
            "hud_path": "/root/Match/HUD", "development_menu_path": "/root/Match/Development",
            "final_hud_selected": "CONTROL · ID 0\nCAMPO LOCAL", "final_hud_mode": "PREVIEW",
            "limitations": ["Synthetic unit fixture; not runtime evidence."],
        })
        self.manifest = None
        if protocol == "gameplay":
            capture_directory = root / "report-gameplay-captures"
            capture_directory.mkdir()
            report.update({"frames_drawn": 0, "watchdog_msec": 120000,
                           "gameplay_driver_script": "res://diagnostics/gameplay_smoke.gd",
                           "gui_input_method": GUI_METHOD, "aim_precision_controls": FINE_AIM,
                           "aim_precision_max_degrees_per_second": 30.0})
            cases = []
            for case_id in CASE_IDS:
                mode = int(case_id[1])
                exercise = EXERCISES[case_id.split("/")[1]]
                after = {
                    "case": case_id, "mode": mode, "tick": 63, "selected_actor_id": 0,
                    "exercise": exercise, "phase": "PLAYING", "restart": {},
                    "state": fixture_state(mode, 63, exercise), "camera": {}, "guide": {},
                    "accepted_event": {}, "render_ball_position": [0.0, 0.0, 0.0], "interpolation_fraction": 0.0,
                    "events": copy.deepcopy(report["events"]), "input": input_records(case_id),
                    "athlete_presentations": poses(mode, 63), "capture_status": "not_rendered_headless", "filename": "",
                    "hud_context": "LIVE", "hud_fouls": "0/0", "hud_restart_clock": "",
                    "hud_restart_title": "", "hud_selected": "ID 0", "visible_home_options": [],
                }
                name = case_id.split("/")[1]
                if name == "keeper_clearance_release":
                    after["accepted_event"] = copy.deepcopy(report["events"][0])
                elif name.startswith("dribble_"):
                    after["accepted_event"] = copy.deepcopy(report["events"][1])
                if case_id not in CAPTURE_IDS:
                    for field in CAPTURE_KEYS:
                        after.pop(field)
                case = {"case": case_id, "before": fixture_state(mode, 62, exercise), "after": after,
                        "passed": True, "source_script": "res://match/match.gd"}
                if "completion" in self.spec["caseKeys"][case_id]:
                    case["completion"] = copy.deepcopy(after)
                    for field in CAPTURE_KEYS:
                        case["completion"].pop(field, None)
                cases.append(case)
            report["gameplay"] = {
                "started": True, "complete": True, "capture_complete": False,
                "expected_cases": list(CASE_IDS), "completed_cases": list(CASE_IDS), "cases": cases,
                "native_inputs": input_records(), "athlete_presentations": [], "required_png_count": 20,
                "observed_moment_count": 20, "saved_png_count": 0, "capture_directory": str(capture_directory),
                "capture_manifest_path": str(capture_directory / "manifest.json"),
            }
            self.manifest = {
                "schema_version": 1, "process_id": 12345, "required_png_count": 20, "saved_png_count": 0,
                "headless": True, "editor_binary": editor, "functional_traversal_complete": True,
                "project_version": self.identity["projectVersion"], "driver_script": "res://diagnostics/gameplay_smoke.gd",
                "main_scene": self.identity["mainScene"], "report_path": str(self.report_path),
                "capture_directory": str(capture_directory), "captures": [],
                "observations": [copy.deepcopy(case["after"]) for case in cases if case["case"] in CAPTURE_IDS],
            }
        self.report = report

    def write(self, stderr: bytes = b"", extra_stdout: str = "", stdout_report: dict | None = None) -> ProcessResult:
        self.report_path.write_text(json.dumps(self.report, ensure_ascii=False) + "\n", encoding="utf-8")
        if self.manifest is not None:
            (self.root / "report-gameplay-captures" / "manifest.json").write_text(
                json.dumps(self.manifest, ensure_ascii=False) + "\n", encoding="utf-8")
        marker = "FUTSAL_GAMEPLAY_SMOKE" if self.protocol == "gameplay" else "FUTSAL_MATCH_SMOKE"
        stdout = ("Godot Engine v4.7.2.stable.official.ed1daf0bf\n"
                  + "".join("PASS " + check["name"] + "\n" for check in self.report["checks"])
                  + marker + " " + json.dumps(self.report if stdout_report is None else stdout_report, ensure_ascii=False)
                  + "\n" + extra_stdout)
        return ProcessResult(12345, 0, datetime.now(timezone.utc).isoformat(), self.started, 1.0,
                             stdout.encode("utf-8"), stderr, True, True, "")

    def validate(self, **kwargs: object) -> dict:
        return validate_report(self.write(**kwargs), self.report_path, self.executable,
                               protocol=self.protocol, editor=self.editor, identity=self.identity,
                               engine=self.engine, contract=self.contract)


class SmokeTests(unittest.TestCase):
    def test_all_four_complete_protocol_variants(self) -> None:
        for protocol in ("legacy", "gameplay"):
            for editor in (True, False):
                with self.subTest(protocol=protocol, editor=editor), TemporaryDirectory() as temporary:
                    fixture = SmokeFixture(Path(temporary), protocol, editor)
                    summary = fixture.validate()
                    self.assertEqual(summary["passed"], len(fixture.spec["checks"]))
                    self.assertEqual(summary["modes"], [0, 1])
                    self.assertFalse(summary["renderedValidated"])

    def test_reviewed_literals_include_all_checks_and_both_modes(self) -> None:
        contract = read_json(HERE / "smoke-contract.json")
        for protocol, totals in (("legacy", (201, 218)), ("gameplay", (1080, 1097))):
            for variant, total in zip(("source", "export"), totals):
                names = contract["protocols"][protocol][variant]["checks"]
                self.assertEqual(len(names), total)
                self.assertEqual(len(names), len(set(names)))
                self.assertIn("all planned smoke phases completed", names)
        self.assertEqual(len(CASE_IDS), 28)
        self.assertEqual(len(CAPTURE_IDS), 20)

    def test_boolean_counts_pid_source_and_headless_negatives(self) -> None:
        mutations = {
            "boolean-total": lambda report: report.update(total=True),
            "string-check": lambda report: report["checks"][0].update(passed="true"),
            "duplicate-check": lambda report: report["checks"].append(report["checks"][0]),
            "subset-check": lambda report: report["checks"].pop(),
            "wrong-pid": lambda report: report.update(process_id=999),
            "old-version": lambda report: report.update(project_version="0.3.0-preview"),
            "wrong-main": lambda report: report.update(main_scene="res://bootstrap/bootstrap.tscn"),
            "gpu-claim": lambda report: report.update(gpu_validated=True),
            "rejection": lambda report: report["command_rejections"].append({"code": 1}),
            "default-frozen": lambda report: report["default_entrypoint"]["after_wait"].update(tick=1),
            "default-false": lambda report: report["default_entrypoint"].update(verified=False),
            "phase-ordinal": lambda report: report["final_state"].update(phase=1),
            "missing-host-path": lambda report: report.update(authority_path=None),
            "actor-role": lambda report: report["final_state"]["actors"][2].update(role=0),
            "ai-intent-effective": lambda report: report["final_state"].update(ai_actor_ids=list(range(10))),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), TemporaryDirectory() as temporary:
                fixture = SmokeFixture(Path(temporary), "legacy", False)
                mutation(fixture.report)
                with self.assertRaises(ReleaseError):
                    fixture.validate()

    def test_unexpected_diagnostics_and_duplicate_marker_rejected(self) -> None:
        for stderr, stdout in ((b"WARNING: unexpected\n", ""), (b"", "ERROR: unexpected\n"),
                               (b"", "FUTSAL_MATCH_SMOKE {}\n")):
            with self.subTest(stderr=stderr, stdout=stdout), TemporaryDirectory() as temporary:
                fixture = SmokeFixture(Path(temporary), "legacy", True)
                with self.assertRaises(ReleaseError):
                    fixture.validate(stderr=stderr, extra_stdout=stdout)

    def test_report_stdout_cannot_disagree(self) -> None:
        with TemporaryDirectory() as temporary:
            fixture = SmokeFixture(Path(temporary), "legacy", True)
            result = fixture.write()
            fixture.report_path.write_text("{}", encoding="utf-8")
            with self.assertRaises(ReleaseError):
                validate_report(result, fixture.report_path, fixture.executable, protocol="legacy", editor=True,
                                identity=fixture.identity, engine=fixture.engine, contract=fixture.contract)

    def test_stdout_only_type_mutations_are_rejected_for_all_protocols(self) -> None:
        covered = 0
        for protocol in ("legacy", "gameplay"):
            for editor in (True, False):
                for field, value in (("mode", True), ("ok", 1), ("frames_drawn", False), ("headless", 1)):
                    if field == "frames_drawn" and protocol == "legacy":
                        continue
                    with self.subTest(protocol=protocol, editor=editor, field=field), TemporaryDirectory() as temporary:
                        fixture = SmokeFixture(Path(temporary), protocol, editor)
                        changed = copy.deepcopy(fixture.report)
                        changed[field] = value
                        with self.assertRaisesRegex(ReleaseError, "stdout y archivo difieren"):
                            fixture.validate(stdout_report=changed)
                        covered += 1
        self.assertEqual(covered, 14)

    def test_requested_modes_are_integers_even_when_file_and_stdout_agree(self) -> None:
        for protocol in ("legacy", "gameplay"):
            for editor in (True, False):
                with self.subTest(protocol=protocol, editor=editor), TemporaryDirectory() as temporary:
                    fixture = SmokeFixture(Path(temporary), protocol, editor)
                    fixture.report["mode_changes"][0]["requested_mode"] = bool(
                        fixture.report["mode_changes"][0]["requested_mode"])
                    with self.assertRaisesRegex(ReleaseError, "requested_mode"):
                        fixture.validate()

    def test_matching_file_and_stdout_still_require_scalar_semantic_types(self) -> None:
        covered = 0
        for protocol in ("legacy", "gameplay"):
            for editor in (True, False):
                for field, value in (("mode", True), ("ok", 1), ("frames_drawn", False), ("headless", 1)):
                    if field == "frames_drawn" and protocol == "legacy":
                        continue
                    with self.subTest(protocol=protocol, editor=editor, field=field), TemporaryDirectory() as temporary:
                        fixture = SmokeFixture(Path(temporary), protocol, editor)
                        fixture.report[field] = value
                        with self.assertRaises(ReleaseError):
                            fixture.validate()
                        covered += 1
        self.assertEqual(covered, 14)

    def test_manifest_nested_boolean_cannot_replace_numeric_observation(self) -> None:
        with TemporaryDirectory() as temporary:
            fixture = SmokeFixture(Path(temporary), "gameplay", False)
            fixture.manifest["observations"][0]["render_ball_position"][0] = False
            with self.assertRaisesRegex(ReleaseError, "veinte observaciones"):
                fixture.validate()

    def test_gameplay_full_subset_manifest_motion_and_shape_negatives(self) -> None:
        def subset(fixture: SmokeFixture) -> None:
            gameplay = fixture.report["gameplay"]
            gameplay["cases"] = gameplay["cases"][:14]
            gameplay["expected_cases"] = list(CASE_IDS[:14])
            gameplay["completed_cases"] = list(CASE_IDS[:14])
            gameplay["observed_moment_count"] = 10
            fixture.manifest["observations"] = fixture.manifest["observations"][:10]

        mutations = {
            "self-consistent-subset": subset,
            "duplicate-case": lambda f: f.report["gameplay"]["cases"].append(f.report["gameplay"]["cases"][0]),
            "false-case": lambda f: f.report["gameplay"]["cases"][0].update(passed=False),
            "missing-completion": lambda f: f.report["gameplay"]["cases"][0].pop("completion"),
            "bad-motion": lambda f: f.report["gameplay"]["native_inputs"][-1].update(relative=[0.0]),
            "bad-gui-method": lambda f: f.report.update(gui_input_method="emit_signal"),
            "missing-input-route": lambda f: f.report["gameplay"]["native_inputs"].pop(),
            "bad-device": lambda f: f.report["gameplay"]["native_inputs"][0].update(device=1),
            "png-claim": lambda f: f.report["gameplay"].update(saved_png_count=20),
            "bad-manifest-pid": lambda f: f.manifest.update(process_id=7),
            "manifest-substitute": lambda f: f.manifest["observations"].reverse(),
            "future-pose": lambda f: f.report["gameplay"]["cases"][0]["after"]["athlete_presentations"][0].update(render_tick=999),
            "missing-real-event": lambda f: f.report.update(events=[{"kind": 9, "tick": 0}]),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), TemporaryDirectory() as temporary:
                fixture = SmokeFixture(Path(temporary), "gameplay", False)
                mutation(fixture)
                with self.assertRaises(ReleaseError):
                    fixture.validate()

    def test_source_oracle_is_bound_to_unchanged_producers(self) -> None:
        contract = read_json(HERE / "smoke-contract.json")
        identity = project_identity(REPOSITORY / "game")
        validate_producers(REPOSITORY / "game", contract, identity)
        contract["producers"]["diagnostics/gameplay_smoke.gd"] = "0" * 64
        with self.assertRaises(ReleaseError):
            validate_producers(REPOSITORY / "game", contract, identity)

    def test_phase_is_string_and_motion_vectors_are_typed(self) -> None:
        valid = fixture_state()
        self.assertEqual(state(valid)["phase"], "PLAYING")
        valid["phase"] = 1
        with self.assertRaises(ReleaseError):
            state(valid)
        motion = input_records()[-1]
        native_input(motion)
        motion["relative"] = [True, 0]
        with self.assertRaises(ReleaseError):
            native_input(motion)


if __name__ == "__main__":
    unittest.main()
