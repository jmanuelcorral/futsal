extends "res://diagnostics/match_smoke.gd"
## --gameplay-smoke --report-path=<absolute>. Capturas aisladas junto al informe.

const MatchHost = preload("res://match/match.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Launch = preload("res://match/simulation/match_launch.gd")
const Adapter = preload("res://match/presentation/input/match_input.gd")
const Camera = preload("res://match/presentation/camera/broadcast_camera.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const CAPTURE_NAMES: Array[String] = [
	"corner_pos_x_neg_z", "corner_pos_x_pos_z", "corner_neg_x_neg_z", "corner_neg_x_pos_z",
	"live_charged_shot", "keeper_clearance_ready", "keeper_clearance_release",
	"dribble_left_contact", "dribble_right_contact", "dribble_pace_contact",
]
const RULE_NAMES: Array[String] = ["kick_in", "direct_free_kick", "penalty_fine_aim", "accumulated_spot_choice"]
const CORNER_EXERCISES: Array[Setup.TrainingExercise] = [
	Setup.TrainingExercise.CORNER_POS_X_NEG_Z, Setup.TrainingExercise.CORNER_POS_X_POS_Z,
	Setup.TrainingExercise.CORNER_NEG_X_NEG_Z, Setup.TrainingExercise.CORNER_NEG_X_POS_Z,
]

var _game: MatchHost
var _gameplay_started: bool = false
var _gameplay_complete: bool = false
var _gameplay_cases: Array[Dictionary] = []
var _gameplay_ids: Array[String] = []
var _capture_observations: Array[Dictionary] = []
var _saved_captures: Array[Dictionary] = []
var _native_gameplay_inputs: Array[Dictionary] = []
var _launch_requests: Array[Dictionary] = []
var _athlete_pose_samples: Array[Dictionary] = []
var _capture_directory: String = ""
var _manifest_path: String = ""
var _case_input_start: int = 0
var _case_event_start: int = 0
var _case_check_start: int = 0
var _case_initial: Dictionary = {}
var _case_label: String = ""
var _native_exercise_requests: Array[int] = []


func _explicitly_requested() -> bool:
	return OS.get_cmdline_user_args().has("--gameplay-smoke")


func _report_marker() -> String:
	return "FUTSAL_GAMEPLAY_SMOKE"


func _watchdog_msec() -> int:
	return 120000


func _additional_complete() -> bool:
	return _gameplay_complete and (bool(_report.get("headless", true)) or _render_complete())


func _exercise_gameplay() -> void:
	_game = _host as MatchHost
	_gameplay_started = true
	_report["scope"] = "playable-gameplay-runtime-smoke"
	_report["gameplay_driver_script"] = String(get_script().resource_path)
	_report["gui_input_method"] = "Viewport.push_input; local mouse coordinates, device 0"
	_report["aim_precision_controls"] = _game.get_aim_controls_hint()
	_report["aim_precision_max_degrees_per_second"] = rad_to_deg(Adapter.FINE_AIM_RADIANS_PER_SECOND)
	_report["watchdog_msec"] = _watchdog_msec()
	_report["limitations"] = [
		"Native event routing is not a physical-controller or input-to-photon measurement.",
		"The 20 gameplay PNGs are current viewport images, not a formal art or human-feel approval.",
		"Source/runtime checks do not replace native rules/tactics suites or independent artifact review.",
		"Legacy mode/AI smoke uses panel signals; gameplay exercise/guide controls use native keyboard/controller/mouse events.",
		"No rendered-FPS, latency or full-match tactical quality claim.",
	]
	if not _check("gameplay captures derive only from this report; no legacy --capture-path",
			_argument("--capture-path=").is_empty()) or not _prepare_capture_directory():
		return
	_game.command_submitted.connect(_record_launch_request)
	_dev_menu.connect(&"exercise_requested", func(exercise: int) -> void: _native_exercise_requests.append(exercise))
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		if not await _change_mode(mode, "gameplay capture setup m%d" % mode):
			return
		for index: int in CORNER_EXERCISES.size():
			if not await _corner_case(mode, index):
				return
		if not await _live_shot_case(mode) or not await _clearance_case(mode):
			return
		for gesture: int in 3:
			if not await _dribble_case(mode, gesture):
				return
		if not await _rule_cases(mode):
			return
	var expected: Array[String] = _expected_gameplay_ids()
	var actual: Array[String] = _gameplay_ids.duplicate()
	expected.sort()
	actual.sort()
	_gameplay_complete = expected == actual and _capture_observations.size() == 20
	_check("G31 all 28 finite gameplay cases and 20 required observation moments completed", _gameplay_complete)
	_check("G31 rendered run saves exactly 20 PNGs; headless claims none",
		_saved_captures.size() == (0 if bool(_report["headless"]) else 20))
	_case_label = "final_preview_restoration"


func _prepare_capture_directory() -> bool:
	var report_path: String = _argument("--report-path=")
	if not _check("G31 gameplay report path is absolute", report_path.is_absolute_path()):
		return false
	var parent: String = report_path.get_base_dir()
	var root_path: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var normalized_parent: String = parent.replace("\\", "/").to_lower()
	if not _check("G31 gameplay output stays outside runtime source/assets",
			normalized_parent != root_path and not normalized_parent.begins_with(root_path + "/")):
		return false
	_capture_directory = parent.path_join(report_path.get_file().get_basename() + "-gameplay-captures")
	if not _check("G31 fresh run owns its capture directory without overwriting earlier evidence",
			not DirAccess.dir_exists_absolute(_capture_directory)):
		return false
	if not _check("G31 create isolated report-sibling capture directory",
			DirAccess.make_dir_recursive_absolute(_capture_directory) == OK):
		return false
	_manifest_path = _capture_directory.path_join("manifest.json")
	return true


func _prepare_exercise(mode: Setup.Mode, exercise: Setup.TrainingExercise, label: String) -> bool:
	_case_label = label
	_case_input_start = _native_gameplay_inputs.size()
	_case_event_start = _events.size()
	_case_check_start = _checks.size()
	_launch_requests.clear()
	_release_gameplay_inputs()
	await _frames(2)
	if not _check(label + " preserves the current actual mode", _simulation.get_snapshot().mode == mode):
		return false
	var no_ai: Array[int] = []
	if not _check(label + " isolates the scenario through public AI intent", _game.set_ai_actor_ids(no_ai) == OK):
		return false
	_game.set_aim_guide_enabled(true)
	_tap_key(KEY_F1)
	await _frames(3)
	if not _check(label + " opens the real F1 modal without a second overlay",
			bool(_dev_menu.call(&"is_open")) and not _control("PauseOverlay").visible):
		return false
	var frozen: Snapshot = _simulation.get_snapshot()
	var guide_before: bool = _game.is_aim_guide_enabled()
	var requests_before: int = _native_exercise_requests.size()
	var selector: OptionButton = _dev_menu.get_node("%ExerciseSelector") as OptionButton
	if not _focus_control(selector, label + " exercise selector"):
		return false
	if not await _choose_exercise_popup(selector, exercise, mode == Setup.Mode.PREVIEW_5V5, label):
		return false
	var draft_state: Snapshot = _simulation.get_snapshot()
	if not _check(label + " selection is a draft, not a reset",
			selector.get_selected_id() == exercise and _frozen(frozen, draft_state)
			and draft_state.mode == frozen.mode and draft_state.training_exercise == frozen.training_exercise
			and draft_state.ai_intent_actor_ids == frozen.ai_intent_actor_ids
			and _native_exercise_requests.size() == requests_before and _game.is_aim_guide_enabled() == guide_before
			and bool(_dev_menu.call(&"is_open"))):
		return false
	_driver_start_calls += 1
	_click(_dev_menu.get_node("%ApplyExerciseButton") as Control)
	await _frames(4)
	var state: Snapshot = _simulation.get_snapshot()
	_check(label + " Apply emits exactly one native exercise request",
		_native_exercise_requests.size() == requests_before + 1)
	_check(label + " Apply confirms the requested production exercise",
		state.mode == mode and state.training_exercise == exercise)
	_check(label + " Apply closes the development modal",
		not bool(_dev_menu.call(&"is_open")))
	if not _check(label + " explicit Apply reaches the actual catalog authority",
			state.mode == mode and state.training_exercise == exercise
			and _native_exercise_requests.size() == requests_before + 1 and _native_exercise_requests[-1] == exercise
			and state.ai_intent_actor_ids.is_empty() and _composition_matches(state, mode)
			and _real_actor_ids() == _ids_for_mode(mode) and _game.is_aim_guide_enabled()
			and not bool(_dev_menu.call(&"is_open")) and not _control("PauseOverlay").visible):
		return false
	_case_initial = _startup_evidence(state)
	if exercise not in [Setup.TrainingExercise.FREE_PLAY, Setup.TrainingExercise.DRIBBLE_CUT,
			Setup.TrainingExercise.DRIBBLE_PACE_CHANGE]:
		return _check(label + " uses STOPPED/PLACEMENT rather than a ready-state teleport",
			state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.stage in [
				Rules.RestartStage.STOPPED, Rules.RestartStage.PLACEMENT])
	return _check(label + " starts live exercise with selected field 0",
		state.phase == Snapshot.Phase.PLAYING and state.selected_actor_id == 0)


func _choose_exercise_popup(selector: OptionButton, exercise: Setup.TrainingExercise, controller: bool, label: String) -> bool:
	var draft_before: int = selector.get_selected_id()
	var requests_before: int = _native_exercise_requests.size()
	var popup: PopupMenu = selector.get_popup()
	if controller:
		_send(_button(JOY_BUTTON_A, true))
		_send(_button(JOY_BUTTON_A, false))
	else:
		_tap_key(KEY_ENTER)
	await _frames(1)
	if not _check(label + " native accept opens the exercise popup", popup.visible and selector.item_count == 12):
		return false
	for step: int in selector.item_count:
		var focused: int = popup.get_focused_item()
		if focused >= 0 and popup.get_item_id(focused) == exercise:
			break
		if controller:
			_send(_button(JOY_BUTTON_DPAD_DOWN, true))
			_send(_button(JOY_BUTTON_DPAD_DOWN, false))
		else:
			_tap_key(KEY_DOWN)
		await _frames(1)
	var focused: int = popup.get_focused_item()
	if not _check(label + " native vertical navigation only highlights the requested preset",
			focused >= 0 and popup.get_item_id(focused) == exercise
			and selector.get_selected_id() == draft_before and _native_exercise_requests.size() == requests_before):
		return false
	if controller:
		_send(_button(JOY_BUTTON_A, true))
		_send(_button(JOY_BUTTON_A, false))
	else:
		_tap_key(KEY_ENTER)
	await _frames(1)
	return _check(label + " accepting a popup choice restores selector focus without applying",
		not popup.visible and selector.get_selected_id() == exercise
		and get_viewport().gui_get_focus_owner() == selector and _native_exercise_requests.size() == requests_before)


func _wait_ready(label: String) -> bool:
	for frame: int in 100:
		if _simulation.get_snapshot().restart.stage == Rules.RestartStage.READY:
			break
		await _frames(1)
	var state: Snapshot = _simulation.get_snapshot()
	var result: bool = state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.stage == Rules.RestartStage.READY
	result = result and state.restart.ready_tick >= 60 and state.restart.placement_end_tick <= state.restart.ready_tick
	if result:
		await _frames(2)
		_check_ready_feedback(label)
	return _check(label + " reaches READY after at least 60 ticks, without renderer ACK", result)


func _corner_case(mode: Setup.Mode, index: int) -> bool:
	var id: String = "m%d/%s" % [mode, CAPTURE_NAMES[index]]
	if not await _prepare_exercise(mode, CORNER_EXERCISES[index], id):
		return false
	var initial: Snapshot = _simulation.get_snapshot()
	if index == 2:
		_send(_axis(JOY_AXIS_LEFT_Y, -0.8))
		await _frames(2)
		var held: Command = _adapter().get_preview_command()
		var projection: Dictionary = _camera().get_input_projection()
		await _frames(42)
		var after: Command = _adapter().get_preview_command()
		_check(id + " held controller direction survives the real camera blend",
			held != null and after != null and held.aim.distance_to(after.aim) < 0.0001
			and _camera().get_input_projection()["serial"] == projection["serial"])
		_send(_axis(JOY_AXIS_LEFT_Y, 0.0))
		await _frames(2)
	if not await _wait_ready(id):
		return false
	_check(id + " only own corners use the completed contextual camera",
		_camera().get_camera_state()["mode"] == "corner" and _camera().get_camera_state()["transition_complete"]
		and _camera().get_camera_state()["transition_ticks_elapsed"] == 45
		and _simulation.get_snapshot().restart.id == initial.restart.id)
	_check_guide(id)
	_check_corner_frame(id)
	await _capture_moment(id)
	if index == 0:
		var before: Snapshot = _simulation.get_snapshot()
		var event_start: int = _events.size()
		_tap_key(KEY_J)
		await _frames(2)
		var event: Dictionary = _last_event(Event.Kind.PASS, before.selected_actor_id)
		_check(id + " accepted corner pass starts camera return", not event.is_empty()
			and _camera().get_camera_state()["mode"] == "returning"
			and _camera().get_camera_state()["accepted_return_event_id"] == event.get("id", -1))
		_assert_launch(id, event)
		if not event.is_empty():
			_record_focus_case(id + "/accepted_pass", "InputEventKey:J", before,
				_simulation.get_snapshot(), event_start, int(event["target"]), "pass")
		await _frames(45)
		_check(id + " broadcast return completes within 45 authority ticks",
			_camera().get_camera_state()["mode"] == "broadcast")
	elif index == 1:
		_send(_button(JOY_BUTTON_B, true))
		await _frames(6)
		_tap_key(KEY_F1)
		await _frames(2)
		var frozen: Snapshot = _simulation.get_snapshot()
		var pose: Transform3D = _camera().global_transform
		var passes: int = _events.filter(func(event: Dictionary) -> bool:
			return event["kind"] in [Event.Kind.PASS, Event.Kind.SHOT]).size()
		_click(_dev_menu.get_node("%AimGuideToggle") as Control)
		await _frames(8)
		_check(id + " F1 and guide toggle freeze restart, charge and camera",
			_frozen(frozen, _simulation.get_snapshot()) and _camera().global_transform.is_equal_approx(pose)
			and not _game.is_aim_guide_enabled() and not _arrow().visible and _adapter().get_preview_command() == null)
		_click(_dev_menu.get_node("%AimGuideToggle") as Control)
		_send(_button(JOY_BUTTON_B, false))
		_tap_key(KEY_ESCAPE)
		await _frames(2)
		_tap_key(KEY_ESCAPE)
		await _frames(4)
		_check(id + " explicit resume does not replay the cancelled shot",
			_simulation.get_snapshot().phase == Snapshot.Phase.RESTART_PAUSE
			and _camera().get_camera_state()["mode"] == "corner" and _adapter().shot_charge == 0.0
			and _game.is_aim_guide_enabled() and _events.filter(func(event: Dictionary) -> bool:
				return event["kind"] in [Event.Kind.PASS, Event.Kind.SHOT]).size() == passes)
	_seal_case(id)
	return true


func _live_shot_case(mode: Setup.Mode) -> bool:
	var id: String = "m%d/live_charged_shot" % mode
	if not await _prepare_exercise(mode, Setup.TrainingExercise.FREE_PLAY, id):
		return false
	_send(_key(KEY_K, true))
	await _frames(12)
	_check(id + " native hold charges an actual selected-player shot", _adapter().shot_charge > 0.1)
	_check_guide(id)
	var frozen: Dictionary = _startup_evidence(_simulation.get_snapshot())
	var samples: int = _adapter().sample_count
	var charge: float = _adapter().shot_charge
	for query: int in 6:
		var cached: Command = _adapter().get_preview_command()
		if not _check(id + " cached preview exists for pure query %d" % query, cached != null):
			return false
		var solution: Launch.Solution = _simulation.query_human_launch(cached)
		_check(id + " pure query resolves effective launch %d" % query, solution.error == OK)
		cached.aim = Vector2.LEFT
	_check(id + " repeated preview reads neither resample nor mutate authority",
		_startup_evidence(_simulation.get_snapshot()) == frozen and samples == _adapter().sample_count
		and charge == _adapter().shot_charge)
	await _capture_moment(id)
	_send(_key(KEY_K, false))
	await _frames(2)
	var event: Dictionary = _last_event(Event.Kind.SHOT, 0)
	_assert_launch(id, event)
	_check(id + " release launches without focus handoff or a stale guide",
		not event.is_empty() and _simulation.get_snapshot().selected_actor_id == 0
		and _adapter().get_preview_command() == null and not _arrow().visible)
	await _observe_pose_progress(id, event)
	_seal_case(id)
	return true


func _clearance_case(mode: Setup.Mode) -> bool:
	var prefix: String = "m%d/keeper_clearance" % mode
	if not await _prepare_exercise(mode, Setup.TrainingExercise.GOAL_CLEARANCE, prefix) or not await _wait_ready(prefix):
		return false
	var before: Snapshot = _simulation.get_snapshot()
	_check(prefix + " selects keeper 2 and a real ball held above the floor",
		before.selected_actor_id == 2 and before.actor(2).ball_in_hands and before.ball_owner_id == 2
		and before.ball_position.y > 0.5 and before.human_allowed_actions.has(Command.Action.KEEPER_THROW)
		and not before.human_allowed_actions.has(Command.Action.SHOOT) and not before.selected_can_move)
	_send(_key(KEY_K, true))
	await _frames(3)
	_send(_key(KEY_K, false))
	await _frames(2)
	_check(prefix + " wrong K input cannot shoot, switch focus or restart the deadline",
		_last_event(Event.Kind.SHOT, 2).is_empty() and _adapter().shot_charge == 0.0
		and _simulation.get_snapshot().restart.deadline_tick == before.restart.deadline_tick
		and _simulation.get_snapshot().tick > before.tick)
	_check(prefix + " actual forbidden foot input is visible beside the persistent fine-aim hint",
		_label("RestartFeedback").is_visible_in_tree()
		and _label("RestartFeedback").text == "J / A: lanzamiento del portero"
		and _label("RestartAimHint").is_visible_in_tree())
	_check_ready_feedback(prefix + " after refusal")
	_check_guide(prefix)
	await _capture_moment(prefix + "_ready")
	before = _simulation.get_snapshot()
	var event_start: int = _events.size()
	_send(_button(JOY_BUTTON_A, true))
	await _frames(2)
	_send(_button(JOY_BUTTON_A, false))
	var event: Dictionary = _last_event(Event.Kind.PASS, 2)
	_check(prefix + " A emits physical PASS with KEEPER_THROW launch kind",
		not event.is_empty() and event.get("launch_kind", -1) == Rules.LaunchKind.KEEPER_THROW
		and _simulation.get_snapshot().phase == Snapshot.Phase.PLAYING
		and not _simulation.get_snapshot().actor(2).ball_in_hands)
	_assert_launch(prefix, event)
	if not event.is_empty():
		_record_focus_case(prefix + "/manual_throw", "InputEventJoypadButton:A", before,
			_simulation.get_snapshot(), event_start, int(event["target"]), "pass")
	await _capture_moment(prefix + "_release", event)
	await _observe_pose_progress(prefix, event)
	_seal_case(prefix + "_ready")
	_seal_case(prefix + "_release")
	return true


func _dribble_case(mode: Setup.Mode, gesture: int) -> bool:
	var id: String = "m%d/%s" % [mode, CAPTURE_NAMES[7 + gesture]]
	var exercise: Setup.TrainingExercise = Setup.TrainingExercise.DRIBBLE_PACE_CHANGE if gesture == 2 \
		else Setup.TrainingExercise.DRIBBLE_CUT
	if not await _prepare_exercise(mode, exercise, id):
		return false
	var before: Snapshot = _simulation.get_snapshot()
	var controller: bool = (mode + gesture) % 2 == 1
	if controller:
		_send(_axis(JOY_AXIS_LEFT_X if gesture == 2 else JOY_AXIS_LEFT_Y, -1.0 if gesture == 0 else 1.0))
		_send(_button(JOY_BUTTON_X, true))
	else:
		_send(_key(KEY_RIGHT if gesture == 2 else (KEY_UP if gesture == 0 else KEY_DOWN), true))
		_send(_key(KEY_L, true))
	await _frames(2)
	var event: Dictionary = _last_event(Event.Kind.DRIBBLE, 0)
	var expected: Rules.GestureKind = Rules.GestureKind.PACE_CHANGE if gesture == 2 else Rules.GestureKind.CUT
	_check(id + " native L/X causes authoritative contact, ball velocity and finite recovery",
		not event.is_empty() and event.get("gesture_kind", -1) == expected
		and not _simulation.get_snapshot().actor(0).gesture_contact_position.is_zero_approx()
		and _simulation.get_snapshot().actor(0).gesture_kind == expected
		and _simulation.get_snapshot().actor(0).action_cooldown > 0.0
		and _simulation.get_snapshot().ball_position.distance_to(before.ball_position) > 0.01
		and _simulation.get_snapshot().ball_velocity.length() > 0.5)
	if gesture != 2:
		_check(id + " contact direction distinguishes both physical cuts",
			signf(_simulation.get_snapshot().actor(0).gesture_direction.z) == (-1.0 if gesture == 0 else 1.0))
	await _capture_moment(id, event)
	await _observe_pose_progress(id, event)
	var accepted: int = _events.slice(_case_event_start).filter(func(item: Dictionary) -> bool:
		return item["kind"] == Event.Kind.DRIBBLE).size()
	await _frames(14)
	_check(id + " retained button is one edge, never repeated dribbles",
		accepted == 1 and _events.slice(_case_event_start).filter(func(item: Dictionary) -> bool:
			return item["kind"] == Event.Kind.DRIBBLE).size() == 1)
	_release_gameplay_inputs()
	_seal_case(id)
	return true


func _rule_cases(mode: Setup.Mode) -> bool:
	var exercises: Array[Setup.TrainingExercise] = [Setup.TrainingExercise.KICK_IN,
		Setup.TrainingExercise.DIRECT_FREE_KICK, Setup.TrainingExercise.PENALTY_6M,
		Setup.TrainingExercise.ACCUMULATED_FREE_KICK]
	for index: int in exercises.size():
		var id: String = "m%d/%s" % [mode, RULE_NAMES[index]]
		if not await _prepare_exercise(mode, exercises[index], id) or not await _wait_ready(id):
			return false
		var before: Snapshot = _simulation.get_snapshot()
		_check_hud(id)
		if index == 0:
			_check(id + " kick-in remains local, not the former center reset",
				before.restart.kind == Rules.RestartKind.KICK_IN and absf(before.restart.spot.z) > 9.5)
			_tap_key(KEY_J)
			await _frames(2)
			_assert_launch(id, _last_event(Event.Kind.PASS, before.selected_actor_id))
		elif index == 3:
			_check(id + " seeded sixth count and real longitudinal spot choice are visible",
				before.accumulated_fouls.y == 6 and before.restart.has_spot_choice
				and _label("FoulTotals").text.contains("predefinido"))
			_send(_key(KEY_L, true))
			await _frames(2)
			var spot: Snapshot = _simulation.get_snapshot()
			_check(id + " L chooses offence spot without altering deadline",
				spot.restart.spot_choice == Rules.SpotChoice.OFFENCE_SPOT
				and spot.restart.spot.distance_to(spot.restart.offence_spot) < 0.001
				and spot.restart.deadline_tick == before.restart.deadline_tick)
			await _frames(8)
			_check(id + " choice does not repeat while held", _simulation.get_snapshot().restart.spot_choice == spot.restart.spot_choice)
			_send(_key(KEY_L, false))
			await _frames(2)
			_send(_button(JOY_BUTTON_X, true))
			_send(_button(JOY_BUTTON_X, false))
			await _frames(2)
			_check(id + " controller X returns to ten metres without renewing timer",
				_simulation.get_snapshot().restart.spot_choice == Rules.SpotChoice.TEN_METRE
				and _simulation.get_snapshot().restart.deadline_tick == before.restart.deadline_tick)
			_tap_key(KEY_J)
			await _frames(2)
			_check(id + " forbidden pass neither becomes a shot nor changes focus",
				_last_event(Event.Kind.PASS, before.selected_actor_id).is_empty()
				and _last_event(Event.Kind.SHOT, before.selected_actor_id).is_empty()
				and _simulation.get_snapshot().selected_actor_id == before.selected_actor_id
				and _simulation.get_snapshot().restart.deadline_tick == before.restart.deadline_tick)
			_check(id + " native forbidden pass has visible contextual feedback",
				_label("RestartFeedback").is_visible_in_tree()
				and _label("RestartFeedback").text == "Este saque exige un tiro")
		else:
			if index == 2:
				_check(id + " penalty has no four-second timer", before.restart.deadline_tick == -1)
				_send(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
				_send(_axis(JOY_AXIS_LEFT_X, 0.8))
				await _frames(9)
				var request: Command = _adapter().get_preview_command()
				_check(id + " LT and analog horizontal input adjust a fine stationary angle",
					request != null and request.aim.length() > 0.99 and absf(request.aim.y) > 0.02
					and _simulation.get_snapshot().actor(before.selected_actor_id).position == before.actor(before.selected_actor_id).position)
				_send(_axis(JOY_AXIS_TRIGGER_LEFT, 0.0))
				_send(_axis(JOY_AXIS_LEFT_X, 0.0))
			_send(_button(JOY_BUTTON_B, true))
			await _frames(9)
			_check_guide(id)
			_send(_button(JOY_BUTTON_B, false))
			await _frames(2)
			_assert_launch(id, _last_event(Event.Kind.SHOT, before.selected_actor_id))
			_check(id + " stopped shot does not fake a focus handoff", _simulation.get_snapshot().selected_actor_id == before.selected_actor_id)
		_record_gameplay_case(id, _observation())
	return true


func _capture_moment(id: String, accepted_event: Dictionary = {}) -> void:
	if not bool(_report["headless"]):
		await RenderingServer.frame_post_draw
	if not accepted_event.is_empty():
		_check_contact_pose(id, accepted_event)
	elif id.ends_with("keeper_clearance_ready"):
		_check_keeper_render_anchor(id)
	var observation: Dictionary = _observation()
	observation["case"] = id
	observation["accepted_event"] = accepted_event
	observation["capture_status"] = "not_rendered_headless"
	observation["filename"] = ""
	_check(id + " capture moment has the real game, correct composition and no modal",
		_composition_matches(_simulation.get_snapshot(), _simulation.get_snapshot().mode)
		and not bool(_dev_menu.call(&"is_open")) and not _control("PauseOverlay").visible
		and _label("SelectedActor").is_visible_in_tree())
	_check(id + " G31 HOST supplies current full-snapshot context to every rendered athlete",
		observation["athlete_presentations"].all(func(pose: Dictionary) -> bool:
			return (pose["context_valid"] and pose["context_tick"] == observation["tick"]
				and pose["validation_error"] == ""
				and pose["snapshot_ball"] == observation["state"]["ball_position"])))
	if not bool(_report["headless"]):
		var image: Image = get_viewport().get_texture().get_image()
		var device: bool = RenderingServer.get_current_rendering_method() == "forward_plus" \
			and RenderingServer.get_current_rendering_driver_name() == "vulkan" \
			and RenderingServer.get_rendering_device() != null
		if _check(id + " actual Vulkan viewport is unretouched 1920x1080", device and image != null
				and not image.is_empty() and image.get_size() == Vector2i(1920, 1080)):
			var path: String = _capture_directory.path_join(id.replace("/", "-") + ".png")
			var varies: bool = _has_pixel_variation(image)
			var saved: Error = image.save_png(path)
			_check(id + " native PNG written once with visible rendered content", saved == OK and varies)
			observation["capture_status"] = "saved" if saved == OK else "write_failed"
			observation["filename"] = path
			observation["width"] = image.get_width()
			observation["height"] = image.get_height()
			observation["render_valid"] = device and saved == OK and varies
			if saved == OK:
				observation["sha256"] = FileAccess.get_sha256(path)
				_saved_captures.append(observation.duplicate(true))
	_capture_observations.append(observation)
	_record_gameplay_case(id, observation)


func _observation() -> Dictionary:
	var state: Snapshot = _simulation.get_snapshot()
	var poses: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		poses.append(_athlete_pose(actor.actor_id))
	return {"state": _startup_evidence(state), "mode": state.mode, "exercise": state.training_exercise,
		"tick": state.tick, "phase": Snapshot.Phase.keys()[state.phase], "selected_actor_id": state.selected_actor_id,
		"restart": _restart_evidence(state.restart), "camera": _camera().get_camera_state(),
		"visible_home_options": _visible_home_options(state),
		"athlete_presentations": poses,
		"input": _native_gameplay_inputs.slice(_case_input_start),
		"events": _events.slice(_case_event_start), "guide": _guide_evidence(),
		"render_ball_position": _vector(_game.get_render_ball_position()),
		"interpolation_fraction": Engine.get_physics_interpolation_fraction(),
		"hud_selected": _label("SelectedActor").text, "hud_context": _label("ControlsContext").text,
		"hud_restart_title": _label("RestartTitle").text, "hud_restart_clock": _label("RestartClock").text,
		"hud_fouls": _label("FoulTotals").text}


func _record_gameplay_case(id: String, observation: Dictionary) -> void:
	_check("G31 finite unique gameplay case: " + id, not _gameplay_ids.has(id))
	_gameplay_ids.append(id)
	_gameplay_cases.append({"case": id, "source_script": String(_game.get_script().resource_path),
		"before": _case_initial, "after": observation, "passed": _checks.slice(_case_check_start).all(
			func(check: Dictionary) -> bool: return bool(check["passed"]))})


func _seal_case(id: String) -> void:
	for item: Dictionary in _gameplay_cases:
		if item["case"] == id:
			item["completion"] = _observation()
			item["passed"] = _checks.slice(_case_check_start).all(
				func(check: Dictionary) -> bool: return bool(check["passed"]))
			return


func _guide_evidence() -> Dictionary:
	var arrow: Node3D = _arrow()
	var shaft: MeshInstance3D = arrow.get_node("Shaft") as MeshInstance3D
	var head: MeshInstance3D = arrow.get_node("Head") as MeshInstance3D
	return {"path": String(arrow.get_path()), "visible": arrow.is_visible_in_tree(),
		"shaft_visible": shaft.is_visible_in_tree(), "head_visible": head.is_visible_in_tree(),
		"mesh_count": int(shaft.mesh != null) + int(head.mesh != null),
		"same_render_world_as_ball": arrow.get_world_3d() == (_game.get_node("BallView/BallMesh") as Node3D).get_world_3d(),
		"render_origin": _vector(arrow.global_position), "direction": _vector(arrow.global_basis.x),
		"physical_origin": _vector(arrow.get_meta("physical_origin", Vector3.ZERO)),
		"launch_velocity": _vector(arrow.get_meta("launch_velocity", Vector3.ZERO)),
		"power": arrow.get_meta("launch_power", 0.0), "executable": arrow.get_meta("executable", false),
		"effective_target_actor_id": arrow.get_meta("effective_target_actor_id", -1)}


func _check_guide(label: String) -> void:
	var request: Command = _adapter().get_preview_command()
	if not _check(label + " uses non-consuming cached input for the world guide", request != null):
		return
	var solution: Launch.Solution = _simulation.query_human_launch(request)
	var evidence: Dictionary = _guide_evidence()
	_check(label + " actual arrow meshes share the ball render world and follow its rendered origin",
		evidence["mesh_count"] == 2 and evidence["shaft_visible"] and evidence["head_visible"]
		and evidence["same_render_world_as_ball"]
		and _arrow().global_position.distance_to(_game.get_render_ball_position() + Vector3.UP * 0.035) < 0.0001)
	_check(label + " arrow direction, target and velocity match the execution resolver",
		solution.error == OK and _arrow().global_basis.x.dot(solution.direction) > 0.999
		and _arrow().get_meta("launch_velocity", Vector3.ZERO).distance_to(solution.velocity) < 0.001
		and _arrow().get_meta("effective_target_actor_id", -2) == solution.effective_target_actor_id)


func _check_ready_feedback(label: String) -> void:
	var panel: Control = _control("RestartFeedbackPanel")
	var hint: Label = _label("RestartAimHint")
	_check(label + " own READY shows actual persistent fine-aim instructions",
		panel.is_visible_in_tree() and hint.is_visible_in_tree() and hint.text == Adapter.FINE_AIM_HINT
		and hint.get_line_count() <= hint.max_lines_visible and hint.get_visible_line_count() == hint.get_line_count())
	var bounds: Rect2 = _feedback_screen_rect(panel)
	_check(label + " fine-aim and refusal surface stays inside the native viewport",
		get_viewport().get_visible_rect().encloses(bounds)
		and not bounds.has_point(get_viewport().get_visible_rect().get_center()))
	for name: String in ["RestartPanel", "SelectionPanel", "HelpPanel", "ChargePanel"]:
		_check(label + " feedback does not cover " + name,
			not bounds.intersects(_feedback_screen_rect(_control(name))))
	for name: String in ["RestartTitle", "RestartClock", "RestartDetail", "ControlsContext"]:
		_check(label + " feedback preserves readable " + name,
			_label(name).is_visible_in_tree() and not _label(name).text.is_empty())


func _feedback_screen_rect(control: Control) -> Rect2:
	return Rect2(control.get_global_transform_with_canvas() * Vector2.ZERO,
		control.size * control.get_global_transform_with_canvas().get_scale().abs())


func _check_corner_frame(label: String) -> void:
	var state: Snapshot = _simulation.get_snapshot()
	var actor: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	var camera: Camera = _camera()
	var visible: bool = true
	for point: Vector3 in [state.ball_position, actor.position, actor.position + Vector3.UP * Tuning.ACTOR_HEIGHT]:
		var at: Vector2 = camera.unproject_position(point) / get_viewport().get_visible_rect().size
		visible = visible and not camera.is_position_behind(point) and at.x > 0.03 and at.x < 0.97 \
			and at.y > 0.12 and at.y < 0.86
	_check(label + " ball and full taker silhouette are framed without extreme FOV",
		visible and camera.fov >= 45.0 and camera.fov <= 66.0
		and absf(camera.global_basis.x.y) < 0.001 and absf(camera.position.x) < 23.5
		and absf(camera.position.z) < 13.5 and camera.position.y > 2.5 and camera.position.y < 3.5)
	_check(label + " at least one complete HOME passing option remains visible", not _visible_home_options(state).is_empty())


func _visible_home_options(state: Snapshot) -> Array[int]:
	var ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id != Snapshot.Team.HOME or actor.actor_id == state.selected_actor_id:
			continue
		var visible: bool = true
		for point: Vector3 in [actor.position, actor.position + Vector3.UP * Tuning.ACTOR_HEIGHT]:
			var at: Vector2 = _camera().unproject_position(point) / get_viewport().get_visible_rect().size
			visible = visible and not _camera().is_position_behind(point) and at.x > 0.03 and at.x < 0.97 \
				and at.y > 0.12 and at.y < 0.86
		if visible:
			ids.append(actor.actor_id)
	return ids


func _assert_launch(label: String, event: Dictionary) -> void:
	if not _check(label + " native launch has an accepted event and a pre-execution solution",
			not event.is_empty() and not _launch_requests.is_empty()):
		return
	var item: Dictionary = _launch_requests[-1]
	var solution: Launch.Solution = item["solution"]
	var command: Command = item["command"]
	var velocity: Array = event["velocity"]
	var origin: Array = event["position"]
	_check(label + " accepted physical velocity and origin agree with the shared launch resolver",
		solution.error == OK and solution.executable
		and Vector3(velocity[0], velocity[1], velocity[2]).distance_to(solution.velocity) < 0.001
		and Vector3(origin[0], origin[1], origin[2]).distance_to(solution.origin) < 0.04
		and event["launch_kind"] == solution.launch_kind and event["actor"] == command.actor_id
		and is_equal_approx(float(event["shot_charge"]), command.shot_charge))
	_check(label + " an accepted kick clears the stopped-play feedback surface",
		not _control("RestartFeedbackPanel").is_visible_in_tree()
		and not _label("RestartAimHint").is_visible_in_tree() and _label("RestartFeedback").text.is_empty())
	_check_contact_pose(label, event)


func _check_contact_pose(label: String, event: Dictionary) -> void:
	if not _check(label + " G19/G31 has an accepted contact to inspect in the actual view", not event.is_empty()):
		return
	var pose: Dictionary = _athlete_pose(int(event["actor"]))
	var accepted_tick: int = event["tick"]
	_check(label + " G19/G31 HOST drives a visible gesture at the accepted physical contact",
		pose["context_valid"] and pose["context_tick"] == _simulation.get_snapshot().tick
		and pose["validation_error"] == "" and pose["contact_tick"] == accepted_tick
		and pose["gesture_kind"] == event["gesture_kind"] and pose["gesture_weight"] > 0.0
		and pose["render_tick"] >= float(accepted_tick) - 1.0
		and _pose_point(pose["contact_world"]).distance_to(_pose_point(event["contact_point"])) < 0.0001
		and pose["feet"].all(func(foot: Dictionary) -> bool: return bool(foot["visible"]))
		and pose["hands"].all(func(hand: Dictionary) -> bool: return bool(hand["visible"])))
	_athlete_pose_samples.append({"case": label, "event_id": event["id"], "accepted_tick": accepted_tick,
		"at_contact": pose})


func _observe_pose_progress(label: String, event: Dictionary) -> void:
	if event.is_empty():
		return
	var id: int = event["actor"]
	var first: Dictionary = _athlete_pose(id)
	await _frames(2)
	var second: Dictionary = _athlete_pose(id)
	_check(label + " HOST context, gesture age and real limb transforms advance after contact",
		first["context_valid"] and second["context_valid"] and second["context_tick"] == _simulation.get_snapshot().tick
		and second["context_tick"] > first["context_tick"] and second["render_tick"] > first["render_tick"]
		and second["gesture_progress"] > first["gesture_progress"]
		and second["contact_tick"] == event["tick"] and second["validation_error"] == ""
		and (first["feet"] != second["feet"] or first["hands"] != second["hands"]))
	_athlete_pose_samples.append({"case": label + "/progress", "event_id": event["id"],
		"at_contact": first, "advanced": second})


func _check_keeper_render_anchor(label: String) -> void:
	var state: Snapshot = _simulation.get_snapshot()
	var pose: Dictionary = _athlete_pose(state.selected_actor_id)
	var ball: Vector3 = _game.get_render_ball_position()
	var anchored: bool = true
	for hand: Dictionary in pose["hands"]:
		var distance: float = _pose_point(hand["origin"]).distance_to(ball)
		anchored = anchored and distance >= Tuning.BALL_RADIUS * 0.6 and distance <= Tuning.BALL_RADIUS + 0.06
	_check(label + " G31 real keeper hands surround the same interpolated BallView ball",
		state.actor(state.selected_actor_id).ball_in_hands and pose["context_valid"]
		and pose["context_tick"] == state.tick and pose["validation_error"] == "" and anchored)
	_athlete_pose_samples.append({"case": label, "ready_hands": pose, "render_ball_position": _vector(ball)})


func _athlete_pose(id: int) -> Dictionary:
	var view: Node3D = _game.get_node("Athletes/Athlete%d" % id) as Node3D
	var legs: Array = view.get("_legs")
	var arms: Array = view.get("_arms")
	var feet: Array[Dictionary] = []
	var hands: Array[Dictionary] = []
	for side: int in 2:
		feet.append(_mesh_transform(legs[side][3] as Node3D))
		hands.append(_mesh_transform(arms[side][2] as Node3D))
	return {"actor_id": id, "path": String(view.get_path()), "source_script": String(view.get_script().resource_path),
		"context_valid": view.get("_context_valid"), "context_before_tick": view.get("_context_before_tick"),
		"context_tick": view.get("_context_tick"), "context_phase": view.get("_context_phase"),
		"render_tick": view.get("_last_render_tick"), "validation_error": view.get("_last_validation_error"),
		"gesture_kind": view.get("_gesture_kind"), "gesture_weight": view.get("_gesture_weight"),
		"gesture_progress": view.get("_gesture_progress"), "contact_tick": view.get("_gesture_contact_tick"),
		"gesture_age_ticks": float(view.get("_last_render_tick")) - float(view.get("_gesture_contact_tick")),
		"contact_world": _vector(view.get("_gesture_contact_world")),
		"snapshot_ball": _vector(view.get("_ball_current")), "feet": feet, "hands": hands}


func _mesh_transform(node: Node3D) -> Dictionary:
	var transform: Transform3D = node.global_transform
	return {"path": String(node.get_path()), "visible": node.is_visible_in_tree(),
		"origin": _vector(transform.origin), "basis_x": _vector(transform.basis.x),
		"basis_y": _vector(transform.basis.y), "basis_z": _vector(transform.basis.z)}


func _pose_point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _record_launch_request(command: Command, result: Error) -> void:
	if result == OK and command.action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		_launch_requests.append({"command": command.copy(), "solution": _simulation.query_human_launch(command)})


func _last_event(kind: Event.Kind, actor: int) -> Dictionary:
	for index: int in range(_events.size() - 1, _case_event_start - 1, -1):
		if _events[index]["kind"] == kind and _events[index]["actor"] == actor:
			return _events[index]
	return {}


func _focus_control(control: Control, label: String) -> bool:
	for attempt: int in 18:
		if get_viewport().gui_get_focus_owner() == control:
			return true
		_tap_key(KEY_TAB)
	return _check(label + " can be focused by native Tab", false)


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.device = 0
	motion.position = at
	motion.global_position = at
	_send(motion)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.device = 0
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		_send(event)


func _send(event: InputEvent) -> void:
	if _gameplay_started:
		var item: Dictionary = {"class": event.get_class(), "device": event.device,
			"case": _case_label, "tick": _simulation.get_snapshot().tick}
		if event is InputEventKey:
			item["physical_keycode"] = event.physical_keycode
			item["pressed"] = event.pressed
			item["echo"] = event.echo
		elif event is InputEventJoypadButton:
			item["button_index"] = event.button_index
			item["pressed"] = event.pressed
		elif event is InputEventMouseButton:
			item["button_index"] = event.button_index
			item["pressed"] = event.pressed
			item["position"] = [event.position.x, event.position.y]
		elif event is InputEventMouseMotion:
			item["position"] = [event.position.x, event.position.y]
			item["relative"] = [event.relative.x, event.relative.y]
		elif event is InputEventJoypadMotion:
			item["axis"] = event.axis
			item["axis_value"] = event.axis_value
		_native_gameplay_inputs.append(item)
	if event is InputEventMouse:
		get_viewport().push_input(event, true)
	else:
		super(event)


func _adapter() -> Adapter:
	return _game.get_node("MatchInput") as Adapter


func _camera() -> Camera:
	return _game.get_node("BroadcastCamera") as Camera


func _arrow() -> Node3D:
	return _game.get_node("BallView/WorldAimGuide/Arrow") as Node3D


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.0, true, false, true).timeout


func _expected_gameplay_ids() -> Array[String]:
	var ids: Array[String] = []
	for mode: int in [0, 1]:
		for name: String in CAPTURE_NAMES + RULE_NAMES:
			ids.append("m%d/%s" % [mode, name])
	return ids


func _capture_playing() -> void:
	await _frames(4)
	var state: Snapshot = _simulation.get_snapshot()
	_report["final_tick"] = state.tick
	_report["capture_phase"] = Snapshot.Phase.keys()[state.phase]
	_report["final_actor_count"] = state.actors.size()
	_report["final_mode"] = _mode(state)
	_report["final_state"] = _startup_evidence(state)
	_report["final_hud_mode"] = _hud_mode_text(PREVIEW_5V5)
	_report["final_hud_selected"] = _label("SelectedActor").text
	_check("gameplay final view restores FREE_PLAY, selected 0, ten actors and nine AI", _final_preview(state)
		and _camera().get_camera_state()["mode"] == "broadcast" and not _arrow().visible)
	_report["frames_drawn"] = Engine.get_frames_drawn()
	_report["gpu_validated"] = not bool(_report["headless"]) and _render_complete()
	_check("gameplay finalization never substitutes a 21st PNG for a required moment",
		_capture_observations.size() == 20 and _saved_captures.size() == (0 if bool(_report["headless"]) else 20))


func _finish(release_inputs: bool = true) -> void:
	if _finished:
		return
	_report["gameplay"] = {
		"started": _gameplay_started, "complete": _gameplay_complete,
		"expected_cases": _expected_gameplay_ids(), "completed_cases": _gameplay_ids,
		"cases": _gameplay_cases, "native_inputs": _native_gameplay_inputs,
		"athlete_presentations": _athlete_pose_samples,
		"required_png_count": 20, "observed_moment_count": _capture_observations.size(),
		"saved_png_count": _saved_captures.size(),
		"capture_complete": not bool(_report.get("headless", true)) and _render_complete(),
		"capture_directory": _capture_directory, "capture_manifest_path": _manifest_path,
	}
	if not _manifest_path.is_empty():
		var manifest: Dictionary = {
			"schema_version": 1, "project_version": PROJECT_VERSION,
			"driver_script": String(get_script().resource_path), "main_scene": PLAYABLE_SCENE,
			"process_id": OS.get_process_id(), "editor_binary": OS.has_feature("editor"),
			"headless": bool(_report.get("headless", true)), "report_path": _argument("--report-path="),
			"capture_directory": _capture_directory, "required_png_count": 20,
			"saved_png_count": _saved_captures.size(), "observations": _capture_observations,
			"captures": _saved_captures, "functional_traversal_complete": _gameplay_complete,
		}
		var file: FileAccess = FileAccess.open(_manifest_path, FileAccess.WRITE)
		_check("gameplay manifest is written into this run's isolated directory", file != null)
		if file != null:
			file.store_string(JSON.stringify(manifest, "\t") + "\n")
			file.flush()
			_check("gameplay manifest bytes persisted without an I/O error", file.get_error() == OK and file.get_length() > 0)
			file.close()
	super(release_inputs)


func _render_complete() -> bool:
	return _saved_captures.size() == 20 and _saved_captures.all(
		func(item: Dictionary) -> bool: return bool(item.get("render_valid", false)))
