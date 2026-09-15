extends Node

const Simulation = preload("res://match/simulation/match_simulation.gd")
const Hud = preload("res://match/presentation/hud/match_hud.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Actor = preload("res://match/simulation/match_actor.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const PLAYABLE_SCENE: String = "res://match/match.tscn"
const PROJECT_VERSION: String = "0.4.0-preview"
const PROJECT_NAME: String = "Futsal — Laboratorio 5v5"
const MICRO_1V1: int = 0
const PREVIEW_5V5: int = 1
const DEV_MENU_SCRIPT: String = "res://match/presentation/development/match_dev_menu.gd"
const WATCHDOG_MSEC: int = 60000

var _simulation: Simulation
var _hud: Hud
var _host: Node
var _dev_menu: Node
var _checks: Array[Dictionary] = []
var _input_evidence: Array[Dictionary] = []
var _mode_changes: Array[Dictionary] = []
var _ai_changes: Array[Dictionary] = []
var _focus_changes: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _refusals: Array[Dictionary] = []
var _integration_errors: Array[Dictionary] = []
var _report: Dictionary = {}
var _started_msec: int = 0
var _running: bool = false
var _finished: bool = false
var _default_entrypoint_verified: bool = false
var _driver_start_calls: int = 0
var _complete: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	set_process(_running)


## Invoke once, after adding this node and starting the real main's components.
func run(simulation: Simulation, hud: Hud) -> void:
	if _running:
		push_error("Match smoke was started more than once.")
		get_tree().quit(2)
		return
	_running = true
	_started_msec = Time.get_ticks_msec()
	_simulation = simulation
	_hud = hud
	set_process(true)
	_execute.call_deferred()


func _process(_delta: float) -> void:
	if _running and not _finished and Time.get_ticks_msec() - _started_msec > _watchdog_msec():
		_check("wall-clock watchdog did not expire", false)
		_finish()


func _exit_tree() -> void:
	if _running and not _finished:
		_check("driver did not exit before completing the real match traversal", false)
		_finish(false)


func _execute() -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	_host = get_tree().current_scene
	_report = {
		"scope": "playable-preview-runtime-smoke",
		"project_name": String(ProjectSettings.get_setting("application/config/name")),
		"project_version": String(ProjectSettings.get_setting("application/config/version")),
		"input_schema_version": int(ProjectSettings.get_setting("futsal/preparation/input_schema_version")),
		"engine_version": String(Engine.get_version_info()["string"]),
		"main_scene": "" if _host == null else _host.scene_file_path,
		"configured_main_scene": String(ProjectSettings.get_setting("application/run/main_scene")),
		"process_id": OS.get_process_id(),
		"executable": OS.get_executable_path(),
		"editor_binary": OS.has_feature("editor"),
		"headless": headless,
		"display_server": DisplayServer.get_name(),
		"rendering_method": "headless" if headless else RenderingServer.get_current_rendering_method(),
		"rendering_driver": "dummy" if headless else RenderingServer.get_current_rendering_driver_name(),
		"gpu_name": "not measured (headless)" if headless else RenderingServer.get_video_adapter_name(),
		"gpu_api": "" if headless else RenderingServer.get_video_adapter_api_version(),
		"gpu_validated": false,
		"viewport_width": int(get_viewport().get_visible_rect().size.x),
		"viewport_height": int(get_viewport().get_visible_rect().size.y),
		"physics_engine": String(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"report_path": _argument("--report-path="),
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"input_method": "Input.parse_input_event; physical keys and raw joypad events, device 0",
		"limitations": [
			"Automatic routing evidence, not a physical controller or input-to-photon measurement.",
			"Full shots, selection negatives and terminal-result cases belong to the native integration suites.",
			"Mode/AI requests use the real development panel signals, not physical checkbox or selector activation.",
			"No game-feel, art approval or rendered-FPS claim.",
		],
	}
	if not _check("smoke driver is explicitly opted in", _explicitly_requested()):
		_finish()
		return
	if not _check("real configured preview main is current_scene", _host != null
			and _report["main_scene"] == PLAYABLE_SCENE and _report["configured_main_scene"] == PLAYABLE_SCENE):
		_finish()
		return
	if not _check("main uses the production script", _host.get_script() != null
			and _host.get_script().resource_path == "res://match/match.gd"):
		_finish()
		return
	if not _check("typed production authority and HUD belong to current_scene",
			is_instance_valid(_simulation) and is_instance_valid(_hud)
			and _host.is_ancestor_of(_simulation) and _host.is_ancestor_of(_hud)
			and _simulation.get_script() == Simulation and _hud.get_script() == Hud):
		_finish()
		return
	_check("preview name/version, pinned engine and native physics", _report["project_version"] == PROJECT_VERSION
		and _report["project_name"] == PROJECT_NAME
		and _report["input_schema_version"] == 3
		and _report["engine_version"] == "4.7.2-stable (official)"
		and _report["physics_engine"] == "Jolt Physics" and Engine.physics_ticks_per_second == 60)
	_check("viewport is 1920x1080", _report["viewport_width"] == 1920 and _report["viewport_height"] == 1080)
	_check("report uses an absolute current-run path", String(_report["report_path"]).is_absolute_path())
	if not _check("headless never requests a capture", not headless or _argument("--capture-path=").is_empty()):
		_finish()
		return
	for name: String in ["Score", "Clock", "ControlsContext", "EventText", "ModalTitle", "SelectedActor"]:
		if not _check("production HUD Label exists: " + name, _hud.get_node_or_null("%" + name) is Label):
			_finish()
			return
	for name: String in ["PauseOverlay", "ResumeButton", "RestartButton", "EventPanel"]:
		if not _check("production HUD Control exists: " + name, _hud.get_node_or_null("%" + name) is Control):
			_finish()
			return
	var camera: Camera3D = get_viewport().get_camera_3d()
	_check("production Camera3D is active", camera != null and camera.is_current() and _host.is_ancestor_of(camera))
	_report["camera_path"] = "" if camera == null else String(camera.get_path())
	_report["authority_path"] = String(_simulation.get_path())
	_report["hud_path"] = String(_hud.get_path())
	_simulation.event_raised.connect(_on_event)
	_simulation.command_rejected.connect(_on_rejection)
	_host.connect("integration_error", _on_integration_error)
	var untouched: Snapshot = _simulation.get_snapshot()
	_report["default_entrypoint"] = {"verified": false, "before": _startup_evidence(untouched)}
	if not _check("default host auto-started PLAYING before any driver setup", _default_started(untouched)):
		_finish()
		return
	await _frames(12)
	var initial: Snapshot = _simulation.get_snapshot()
	_report["default_entrypoint"]["after_wait"] = _startup_evidence(initial)
	if not _check("untouched default advances ticks, clock and human commands", _default_advanced(untouched, initial)):
		_finish()
		return
	if not _check("default main started PREVIEW_5V5 with ten real bodies and nine AI",
			_composition_matches(initial, PREVIEW_5V5)
			and _real_actor_ids() == _ids_for_mode(PREVIEW_5V5)
			and initial.selected_actor_id == 0
			and _ai_ids(initial) == _default_ai(PREVIEW_5V5)
			and _intent_ids(initial) == _ids_for_mode(PREVIEW_5V5)):
		_finish()
		return
	var actors: Array[Dictionary] = []
	for id: int in _ids_for_mode(PREVIEW_5V5):
		var actor: Snapshot.ActorSnapshot = initial.actor(id)
		if not _check("default live actor identity %d" % id, actor != null):
			_finish()
			return
		actors.append(_actor_evidence(actor))
		_check("default actor role/control %d" % id, actor.human_controlled == (id == Simulation.HUMAN_ID)
			and actor.role == (Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD)
			and actor.team_id == (Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY))
		if id != Simulation.HUMAN_ID:
			_check("default AI submits real commands %d" % id, actor.last_command_sequence >= 0)
	_report["loaded_actors"] = actors
	_report["mode"] = _mode(initial)
	_report["initial_ai_actor_ids"] = _ai_ids(initial)
	_report["initial_ai_intent_actor_ids"] = _intent_ids(initial)
	_report["initial_selected_actor_id"] = initial.selected_actor_id
	_report["initial_tick"] = initial.tick
	_check_hud("default game")
	var default_input: bool = await _drive_motion(
		"default keyboard D", &"move_right", _key(KEY_D, true), _key(KEY_D, false), 18)
	_report["default_entrypoint"]["after_input"] = _startup_evidence(_simulation.get_snapshot())
	_check("default input proof ran without driver start or host restart", _driver_start_calls == 0
		and not _events.any(func(event: Dictionary) -> bool: return event["reason"] == "training_start"))
	_default_entrypoint_verified = default_input and _refusals.is_empty() and _integration_errors.is_empty() \
		and _checks.all(func(check: Dictionary) -> bool: return bool(check["passed"]))
	_report["default_entrypoint"]["verified"] = _default_entrypoint_verified
	if not _check("default entrypoint passed before allowing any driver setup", _default_entrypoint_verified):
		_finish()
		return
	if not _development_contract():
		_finish()
		return
	if not await _exercise_ai(PREVIEW_5V5) or not await _change_mode(MICRO_1V1, "micro regression setup") \
			or not await _exercise_ai(MICRO_1V1):
		_finish()
		return
	var motion_drill: Setup = Setup.new()
	motion_drill.ai_actor_ids = []
	motion_drill.actor_positions[0] = Vector3(-8.0, 0.0, -4.0)
	motion_drill.ball_position = Vector3(0.0, 0.12, 6.0)
	if not _check("public start isolates input motion from AI goal pauses", _start_drill(motion_drill) == OK):
		_finish()
		return
	await _frames(8)
	await _drive_motion("keyboard D", &"move_right", _key(KEY_D, true), _key(KEY_D, false))
	await _drive_motion("keyboard W", &"move_forward", _key(KEY_W, true), _key(KEY_W, false))
	await _drive_motion("physical arrow Right", &"move_right", _key(KEY_RIGHT, true), _key(KEY_RIGHT, false))
	await _drive_motion("physical arrow Up", &"move_forward", _key(KEY_UP, true), _key(KEY_UP, false))
	await _drive_motion("joypad left X", &"move_left", _axis(JOY_AXIS_LEFT_X, -1.0), _axis(JOY_AXIS_LEFT_X, 0.0))
	await _drive_motion("joypad left Y", &"move_back", _axis(JOY_AXIS_LEFT_Y, 1.0), _axis(JOY_AXIS_LEFT_Y, 0.0))
	await _exercise_pause()
	await _exercise_goal_and_restart()
	if not await _change_mode(PREVIEW_5V5, "field focus scenarios"):
		_finish()
		return
	await _exercise_focus_preview()
	await _exercise_keeper_focus()
	await _exercise_gameplay()
	if not _check("requested gameplay extension completed", _additional_complete()):
		_finish()
		return
	if not await _change_mode(PREVIEW_5V5, "final preview restoration"):
		_finish()
		return
	if not OS.has_feature("editor"):
		for path: String in [
			"res://tests/test_bootstrap.gd", "res://tests/test_match_simulation.gd",
			"res://tests/test_match_hud.gd", "res://tests/test_match_integration.gd",
			"res://tests/test_match_preview.gd", "res://tests/test_match_dev_menu.gd",
			"res://tests/test_match_preview_integration.gd", "res://tests/test_match_visuals.gd",
			"res://tests/test_match_player_control.gd",
			"res://tests/test_match_camera.gd", "res://tests/test_match_gameplay_runtime.gd",
			"res://tests/test_match_aim_guide.gd", "res://tests/test_match_gestures.gd",
			"res://tests/test_match_ai_tactics.gd", "res://tests/test_match_rules.gd",
		]:
			_check("native test excluded from PCK: " + path, not ResourceLoader.exists(path))
		_check("provisional integration capture excluded from PCK", not ResourceLoader.exists("res://match/validation.png"))
		_check("opt-in driver ships in PCK", ResourceLoader.exists("res://diagnostics/match_smoke.gd"))
	_check("normal production path rejected no commands", _refusals.is_empty())
	await _capture_playing()
	_complete = true
	_finish()


func _explicitly_requested() -> bool:
	return OS.get_cmdline_user_args().has("--smoke-test")


func _exercise_gameplay() -> void:
	pass


func _additional_complete() -> bool:
	return true


func _watchdog_msec() -> int:
	return WATCHDOG_MSEC


func _report_marker() -> String:
	return "FUTSAL_MATCH_SMOKE"


func _drive_motion(
	label: String, action: StringName, press: InputEvent, release: InputEvent, held_frames: int = 36
) -> bool:
	var before: Snapshot = _simulation.get_snapshot()
	var selected: int = before.selected_actor_id
	var bound: bool = _check(label + " raw device-0 event matches binding",
		press.device == 0 and InputMap.event_is_action(press, action))
	_send(press)
	await _frames(held_frames)
	var moving: Snapshot = _simulation.get_snapshot()
	var moved: bool = _check(label + " moved authoritative human",
		before.phase == Snapshot.Phase.PLAYING and moving.phase == Snapshot.Phase.PLAYING
		and moving.selected_actor_id == selected and moving.tick > before.tick
		and moving.actor(selected).position.distance_to(before.actor(selected).position) > 0.3
		and moving.actor(selected).last_command_sequence > before.actor(selected).last_command_sequence)
	_send(release)
	await _frames(24)
	var stopped: Snapshot = _simulation.get_snapshot()
	await _frames(6)
	var after: Snapshot = _simulation.get_snapshot()
	var released: bool = _check(label + " release stops motion while commands continue",
		after.phase == Snapshot.Phase.PLAYING and after.selected_actor_id == selected
		and after.tick > moving.tick and after.actor(selected).velocity.length() < 0.08
		and after.actor(selected).position.distance_to(stopped.actor(selected).position) < 0.025
		and after.actor(selected).last_command_sequence > moving.actor(selected).last_command_sequence
		and not Input.is_action_pressed(action))
	_input_evidence.append({
		"control": label, "event_class": press.get_class(), "device": press.device,
		"selected_actor_id": selected,
		"before": _actor_evidence(before.actor(selected)), "pressed": _actor_evidence(moving.actor(selected)),
		"settled": _actor_evidence(stopped.actor(selected)), "released": _actor_evidence(after.actor(selected)),
		"driver_start_calls": _driver_start_calls,
	})
	var hud_matches: bool = _check_hud(label)
	return bound and moved and released and hud_matches


func _default_started(state: Snapshot) -> bool:
	return state != null and state.phase == Snapshot.Phase.PLAYING \
		and state.training_exercise == Setup.TrainingExercise.FREE_PLAY \
		and state.selected_actor_id == 0 and _intent_ids(state) == _ids_for_mode(PREVIEW_5V5) \
		and _composition_matches(state, PREVIEW_5V5) and _ai_ids(state) == _default_ai(PREVIEW_5V5)


func _default_advanced(before: Snapshot, after: Snapshot) -> bool:
	return _default_started(before) and _default_started(after) and after.tick > before.tick \
		and after.seconds_remaining < before.seconds_remaining \
		and after.actor(0).last_command_sequence > before.actor(0).last_command_sequence


func _startup_evidence(state: Snapshot) -> Dictionary:
	var human: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	var actors: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append(_actor_evidence(actor))
	return {"phase": Snapshot.Phase.keys()[state.phase], "tick": state.tick,
		"seconds_remaining": state.seconds_remaining, "driver_start_calls": _driver_start_calls,
		"human_sequence": -1 if human == null else human.last_command_sequence,
		"mode": _mode(state), "actor_count": state.actors.size(), "actors": actors,
		"selected_actor_id": state.selected_actor_id, "ball_owner_id": state.ball_owner_id,
		"physical_actor_ids": _real_actor_ids(), "ai_actor_ids": _ai_ids(state),
		"ai_intent_actor_ids": _intent_ids(state),
		"score": [state.score.x, state.score.y], "ball_position": _vector(state.ball_position),
		"ball_velocity": _vector(state.ball_velocity), "training_exercise": state.training_exercise,
		"human_control_context": state.human_control_context, "human_allowed_actions": state.human_allowed_actions,
		"selected_can_move": state.selected_can_move, "restart": _restart_evidence(state.restart),
		"accumulated_fouls": [state.accumulated_fouls.x, state.accumulated_fouls.y],
		"period_state": state.period_state, "extended_restart_id": state.extended_restart_id,
		"extended_kick_event_id": state.extended_kick_event_id}


func _restart_evidence(restart: Rules.RestartState) -> Dictionary:
	return {"id": restart.id, "kind": restart.kind, "stage": restart.stage,
		"awarded_team_id": restart.awarded_team_id, "taker_actor_id": restart.taker_actor_id,
		"spot": _vector(restart.spot), "offence_spot": _vector(restart.offence_spot),
		"border": restart.border, "spot_choice": restart.spot_choice, "has_spot_choice": restart.has_spot_choice,
		"stage_started_tick": restart.stage_started_tick, "placement_end_tick": restart.placement_end_tick,
		"ready_tick": restart.ready_tick, "deadline_tick": restart.deadline_tick,
		"minimum_opponent_distance": restart.minimum_opponent_distance,
		"direct_opponent_goal_allowed": restart.direct_opponent_goal_allowed,
		"requires_direct_shot": restart.requires_direct_shot, "other_actor_touched": restart.other_actor_touched,
		"launch_contact_id": restart.launch_contact_id}


func _ids_for_mode(mode: int) -> Array[int]:
	if mode == PREVIEW_5V5:
		return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	if mode == MICRO_1V1:
		return [0, 1, 2, 3]
	return []


func _default_ai(mode: int, selected: int = 0) -> Array[int]:
	var ids: Array[int] = _ids_for_mode(mode)
	ids.erase(selected)
	return ids


# Explicit reflection lets an incomplete producer fail the guard, not substitute G1.
func _mode(state: Snapshot) -> int:
	if state == null:
		return -1
	for property: Dictionary in state.get_property_list():
		if property["name"] == "mode":
			var value: Variant = state.get("mode")
			return int(value) if typeof(value) == TYPE_INT else -1
	return -1


func _ai_ids(state: Snapshot) -> Array[int]:
	var result: Array[int] = []
	if state == null:
		return result
	for property: Dictionary in state.get_property_list():
		if property["name"] == "ai_actor_ids":
			var value: Variant = state.get("ai_actor_ids")
			if typeof(value) != TYPE_ARRAY:
				return [-1]
			for id: Variant in value:
				if typeof(id) != TYPE_INT:
					return [-1]
				result.append(int(id))
			return result
	return [-1]


func _composition_matches(state: Snapshot, expected_mode: int) -> bool:
	var ids: Array[int] = _ids_for_mode(expected_mode)
	if state == null or ids.is_empty() or _mode(state) != expected_mode or state.actors.size() != ids.size() \
			or state.selected_actor_id not in ids or state.selected_actor_id % 2 != 0:
		return false
	for id: int in ids:
		var actor: Snapshot.ActorSnapshot = state.actor(id)
		if actor == null or actor.human_controlled != (id == state.selected_actor_id) \
				or actor.team_id != (Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY) \
				or actor.role != (Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD):
			return false
	var previous: int = -1
	for id: int in _intent_ids(state):
		if id <= previous or id not in ids:
			return false
		previous = id
	var effective: Array[int] = _intent_ids(state)
	effective.erase(state.selected_actor_id)
	return effective == _ai_ids(state)


func _intent_ids(state: Snapshot) -> Array[int]:
	return state.ai_intent_actor_ids.duplicate()


func _development_contract() -> bool:
	for node: Node in _host.find_children("*", "", true, false):
		if node.get_script() != null and node.get_script().resource_path == DEV_MENU_SCRIPT:
			if _dev_menu != null:
				return _check("one real production development menu exists", false)
			_dev_menu = node
	if not _check("real production development menu exists", _dev_menu != null):
		return false
	for method: StringName in [&"present", &"set_open", &"is_open", &"show_error"]:
		if not _check("development public method exists: " + method, _dev_menu.has_method(method)):
			return false
	for signal_name: StringName in [&"mode_requested", &"ai_actor_ids_requested", &"close_requested"]:
		if not _check("development signal is connected to real host: " + signal_name,
				_dev_menu.has_signal(signal_name) and _dev_menu.get_signal_connection_list(signal_name).any(
					func(connection: Dictionary) -> bool: return connection["callable"].get_object() == _host)):
			return false
	for method: StringName in [&"start_development_mode", &"set_ai_actor_ids"]:
		if not _check("production host method exists: " + method, _host.has_method(method)):
			return false
	_report["development_menu_path"] = String(_dev_menu.get_path())
	return _check("production core exposes live AI API", _simulation.has_method(&"set_ai_actor_ids"))


func _open_development(context: String) -> bool:
	_pause_input(true)
	await _frames(3)
	if not _check(context + " pause exposes the real HUD", _control("PauseOverlay").is_visible_in_tree()):
		return false
	var development_button: Button
	for node: Node in _hud.find_children("*", "Button", true, false):
		var candidate: Button = node as Button
		if candidate.is_visible_in_tree() and candidate.text.to_lower().contains("desarrollo"):
			development_button = candidate
			break
	if not _check(context + " visible Desarrollo button exists", development_button != null):
		return false
	development_button.grab_focus()
	_tap_key(KEY_ENTER)
	await _frames(3)
	return _check(context + " native Enter opens development without resuming",
		bool(_dev_menu.call(&"is_open")) and _simulation.get_snapshot().phase == Snapshot.Phase.PAUSED
		and not _control("PauseOverlay").is_visible_in_tree())


func _close_development(context: String) -> bool:
	_tap_key(KEY_ESCAPE)
	await _frames(3)
	if not _check(context + " Escape returns to pause, not gameplay", not bool(_dev_menu.call(&"is_open"))
			and _simulation.get_snapshot().phase == Snapshot.Phase.PAUSED
			and _control("PauseOverlay").is_visible_in_tree()):
		return false
	_pause_input(false)
	await _frames(6)
	return _check(context + " Start resumes after development", _simulation.get_snapshot().phase == Snapshot.Phase.PLAYING
		and not _control("PauseOverlay").is_visible_in_tree())


func _change_mode(target: int, purpose: String) -> bool:
	var context: String = "development mode %d / %s" % [target, purpose]
	if not _default_entrypoint_verified or not await _open_development(context):
		return false
	var before: Snapshot = _simulation.get_snapshot()
	var evidence: Dictionary = {"route": "production-dev-menu-signal", "requested_mode": target,
		"before": _startup_evidence(before)}
	_dev_menu.emit_signal(&"mode_requested", target)
	await _frames(12)
	var after: Snapshot = _simulation.get_snapshot()
	evidence["after"] = _startup_evidence(after)
	_mode_changes.append(evidence)
	return _check(context + " real signal starts exact mode with default AI",
		_composition_matches(after, target) and _real_actor_ids() == _ids_for_mode(target)
		and after.selected_actor_id == 0 and _intent_ids(after) == _ids_for_mode(target)
		and _ai_ids(after) == _default_ai(target) and after.phase == Snapshot.Phase.PLAYING
		and after.seconds_remaining > 119.0 and after.score == Vector2i.ZERO
		and not bool(_dev_menu.call(&"is_open")) and not _control("PauseOverlay").is_visible_in_tree()) \
		and _check_hud(context)


func _exercise_ai(mode: int) -> bool:
	var context: String = "development AI mode %d" % mode
	if not await _open_development(context + " off"):
		return false
	var before: Snapshot = _simulation.get_snapshot()
	var evidence: Dictionary = {"mode": mode, "route": "production-dev-menu-signal",
		"before": _startup_evidence(before)}
	var no_ai: Array[int] = []
	_dev_menu.emit_signal(&"ai_actor_ids_requested", no_ai)
	await _frames(3)
	var off: Snapshot = _simulation.get_snapshot()
	evidence["off"] = _startup_evidence(off)
	if not _check(context + " disabling AI preserves bodies, clock and accepted sequences",
			_composition_matches(off, mode) and _real_actor_ids() == _ids_for_mode(mode)
			and _ai_ids(off).is_empty() and _intent_ids(off).is_empty() and _frozen(before, off)):
		return false
	if not await _close_development(context + " off"):
		return false
	await _frames(36)
	var stopped: Snapshot = _simulation.get_snapshot()
	evidence["off_later"] = _startup_evidence(stopped)
	var stopped_commands: bool = stopped.tick > off.tick and stopped.seconds_remaining < off.seconds_remaining
	for id: int in _default_ai(mode, stopped.selected_actor_id):
		stopped_commands = stopped_commands and stopped.actor(id).last_command_sequence == off.actor(id).last_command_sequence \
			and stopped.actor(id).velocity.length() < 0.08
	if not _check(context + " disabled production AI stops commands and brakes without reset", stopped_commands):
		return false
	_pause_input(true)
	await _frames(3)
	_control("RestartButton").grab_focus()
	_tap_key(KEY_ENTER)
	await _frames(12)
	var restarted: Snapshot = _simulation.get_snapshot()
	evidence["restarted_off"] = _startup_evidence(restarted)
	if not _check(context + " actual HUD restart preserves mode and disabled AI",
			_composition_matches(restarted, mode) and _real_actor_ids() == _ids_for_mode(mode)
			and restarted.selected_actor_id == 0 and _intent_ids(restarted).is_empty()
			and _ai_ids(restarted).is_empty() and restarted.phase == Snapshot.Phase.PLAYING
			and restarted.seconds_remaining > 119.0 and restarted.score == Vector2i.ZERO):
		return false
	if not await _open_development(context + " on"):
		return false
	before = _simulation.get_snapshot()
	evidence["on_before"] = _startup_evidence(before)
	_dev_menu.emit_signal(&"ai_actor_ids_requested", _ids_for_mode(mode))
	await _frames(3)
	var enabled: Snapshot = _simulation.get_snapshot()
	evidence["on"] = _startup_evidence(enabled)
	if not _check(context + " enabling AI preserves bodies, clock and accepted sequences",
			_composition_matches(enabled, mode) and _real_actor_ids() == _ids_for_mode(mode)
			and _ai_ids(enabled) == _default_ai(mode, enabled.selected_actor_id)
			and _intent_ids(enabled) == _ids_for_mode(mode) and _frozen(before, enabled)):
		return false
	if not await _close_development(context + " on"):
		return false
	await _frames(24)
	var resumed: Snapshot = _simulation.get_snapshot()
	evidence["on_later"] = _startup_evidence(resumed)
	var active_commands: bool = resumed.tick > enabled.tick and resumed.seconds_remaining < enabled.seconds_remaining
	for id: int in _default_ai(mode, resumed.selected_actor_id):
		active_commands = active_commands and resumed.actor(id).last_command_sequence > enabled.actor(id).last_command_sequence
	_ai_changes.append(evidence)
	_input_evidence.append({"control": context, "event_class": "production panel request signal; not physical selector input",
		"open_close_controls": "Esc / focused Desarrollo Enter / Escape / Start", "device": 0})
	return _check(context + " all enabled production AI resumes fresh sequences", active_commands) and _check_hud(context)


func _start_drill(setup: Setup) -> Error:
	if not _default_entrypoint_verified:
		return ERR_UNCONFIGURED
	_driver_start_calls += 1
	return _simulation.start(setup)


func _exercise_pause() -> void:
	var drill: Setup = Setup.new()
	drill.ai_actor_ids = []
	drill.actor_positions[0] = Vector3(-8.0, 0.0, -4.0)
	drill.ball_position = Vector3(0.0, 1.0, 3.0)
	drill.ball_velocity = Vector3(4.0, 1.0, 0.0)
	if not _check("public start accepts moving-ball pause drill", _start_drill(drill) == OK):
		return
	await _frames(8)
	_send(_key(KEY_D, true))
	await _frames(12)
	var moving: Snapshot = _simulation.get_snapshot()
	_check("pause begins with moving ball and athlete", moving.ball_velocity.length() > 0.5
		and moving.actor(moving.selected_actor_id).velocity.length() > 0.5)
	for index: int in 2:
		var source: String = "Esc / Start" if index == 0 else "Start / Esc"
		_pause_input(index == 0)
		await _frames(3)
		var paused: Snapshot = _simulation.get_snapshot()
		_check(source + " production HUD pauses authority", paused.phase == Snapshot.Phase.PAUSED
			and _control("PauseOverlay").is_visible_in_tree() and _label("ModalTitle").text == "PAUSA")
		_send(_key(KEY_D, false))
		_send(_axis(JOY_AXIS_LEFT_X, 0.8))
		await _frames(24)
		_check(source + " freezes clock, ball and all active actors", _frozen(paused, _simulation.get_snapshot()))
		_send(_axis(JOY_AXIS_LEFT_X, 0.0))
		_pause_input(index != 0)
		await _frames(12)
		var resumed: Snapshot = _simulation.get_snapshot()
		_check(source + " resumes actual play and HUD", resumed.phase == Snapshot.Phase.PLAYING
			and not _control("PauseOverlay").is_visible_in_tree() and resumed.tick > paused.tick
			and resumed.seconds_remaining < paused.seconds_remaining)
		_check(source + " resumes native ball physics", resumed.ball_position.distance_to(paused.ball_position) > 0.05)
		_input_evidence.append({
			"control": source, "device": 0, "paused_tick": paused.tick, "resumed_tick": resumed.tick,
			"paused_clock": paused.seconds_remaining, "resumed_clock": resumed.seconds_remaining,
			"paused_ball": _vector(paused.ball_position), "resumed_ball": _vector(resumed.ball_position),
		})
		_check_hud(source)


func _exercise_goal_and_restart() -> void:
	var drill: Setup = Setup.new()
	drill.ai_actor_ids = []
	drill.ball_position = Vector3(19.7, 0.4, 0.0)
	drill.ball_velocity = Vector3(12.0, 0.0, 0.0)
	var goals_before: int = _goal_count()
	if not _check("public start accepts physical goal drill", _start_drill(drill) == OK):
		return
	await _frames(12)
	var goal: Snapshot = _simulation.get_snapshot()
	_check("real goal event updates authority and visible score", goal.score == Vector2i(1, 0)
		and _goal_count() == goals_before + 1 and _label("Score").text == "1 – 0")
	_check("real goal event reaches HUD feedback", _control("EventPanel").is_visible_in_tree()
		and _label("EventText").text.to_lower().contains("gol"))
	_pause_input(true)
	await _frames(3)
	_check("restart uses actual pause controls", _control("PauseOverlay").is_visible_in_tree()
		and get_viewport().gui_get_focus_owner() == _control("ResumeButton"))
	_tap_key(KEY_DOWN)
	_check("native Down focuses Restart", get_viewport().gui_get_focus_owner() == _control("RestartButton"))
	_tap_key(KEY_ENTER)
	await _frames(12)
	var restarted: Snapshot = _simulation.get_snapshot()
	_check("native Enter restarts the real match", restarted.phase == Snapshot.Phase.PLAYING
		and restarted.score == Vector2i.ZERO and restarted.seconds_remaining > 119.0
		and restarted.actor(0).spawn_position == Setup.new().actor_positions[0]
		and not _control("PauseOverlay").is_visible_in_tree())
	_check("restart preserves disabled AI from the goal drill",
		_composition_matches(restarted, MICRO_1V1) and _ai_ids(restarted).is_empty()
		and restarted.selected_actor_id == 0 and _intent_ids(restarted).is_empty()
		and _default_ai(MICRO_1V1).all(func(id: int) -> bool: return restarted.actor(id).last_command_sequence == -1))
	_input_evidence.append({
		"control": "Esc / Down / Enter restart", "device": 0,
		"score_before": [goal.score.x, goal.score.y], "score_after": [restarted.score.x, restarted.score.y],
		"seconds_after": restarted.seconds_remaining,
	})
	_check_hud("restart")


func _exercise_focus_preview() -> void:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	setup.actor_positions[0] = Vector3(-4, 0, -3)
	setup.actor_positions[1] = Vector3(8, 0, 5)
	setup.actor_positions[4] = Vector3(2, 0, -3)
	setup.actor_positions[8] = Vector3(-10, 0, -3)
	setup.actor_forwards[4] = Vector2.LEFT
	setup.ball_position = Vector3(0, 0.12, 8)
	if not await _prepare_focus_drill("preview off-ball neutral", setup):
		return
	var before: Snapshot = _simulation.get_snapshot()
	var event_start: int = _events.size()
	_tap_key(KEY_J)
	_check("native J does not optimistically select before the tick", _simulation.get_snapshot().selected_actor_id == 0)
	await _frames(2)
	_record_focus_case("preview_off_ball_neutral", "InputEventKey:J", before,
		_simulation.get_snapshot(), event_start, 4, "off_ball_switch")
	await _drive_motion("selected field D", &"move_right", _key(KEY_D, true), _key(KEY_D, false), 18)
	if not await _prepare_focus_drill("preview off-ball directed", setup):
		return
	before = _simulation.get_snapshot()
	event_start = _events.size()
	_tap_key(KEY_J)
	_send(_key(KEY_LEFT, true))
	await _frames(2)
	_send(_key(KEY_LEFT, false))
	_record_focus_case("preview_off_ball_directional", "InputEventKey:J then physical Left in one frame",
		before, _simulation.get_snapshot(), event_start, 8, "off_ball_switch")
	setup.ball_position = Vector3(-3.45, 0.12, -3)
	if not await _prepare_focus_drill("preview physical pass", setup):
		return
	before = _simulation.get_snapshot()
	event_start = _events.size()
	_send(_button(JOY_BUTTON_A, true))
	await _frames(2)
	_send(_button(JOY_BUTTON_A, false))
	_record_focus_case("preview_pass_field", "InputEventJoypadButton:A", before,
		_simulation.get_snapshot(), event_start, 4, "pass")
	for frame: int in 120:
		if _simulation.get_snapshot().ball_owner_id == 4:
			break
		await _frames(1)
	var received: Snapshot = _simulation.get_snapshot()
	_focus_changes[-1]["received"] = _startup_evidence(received)
	_check("preview selected receiver obtains possession only after physical flight",
		received.selected_actor_id == 4 and received.ball_owner_id == 4 and received.tick > before.tick + 2)
	_check_hud("preview physical reception")


func _exercise_keeper_focus() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = [2]
	setup.actor_positions[0] = Vector3(-12, 0, 0)
	setup.actor_forwards[0] = Vector2.LEFT
	setup.ball_position = Vector3(-12.55, 0.12, 0)
	if not await _prepare_focus_drill("micro manual keeper", setup):
		return
	var before: Snapshot = _simulation.get_snapshot()
	var event_start: int = _events.size()
	_tap_key(KEY_J)
	await _frames(2)
	_record_focus_case("micro_pass_keeper", "InputEventKey:J", before,
		_simulation.get_snapshot(), event_start, 2, "pass")
	for frame: int in 150:
		if _simulation.get_snapshot().ball_owner_id == 2:
			break
		await _frames(1)
	await _frames(45)
	var received: Snapshot = _simulation.get_snapshot()
	_focus_changes[-1]["received"] = _startup_evidence(received)
	_check("controlled keeper receives but does not automatically return",
		received.selected_actor_id == 2 and received.ball_owner_id == 2 and received.ai_actor_ids.is_empty()
		and not _events.slice(event_start).any(func(event: Dictionary) -> bool:
			return event["kind"] == Event.Kind.PASS and event["actor"] == 2))
	_check_hud("controlled keeper")
	before = received
	event_start = _events.size()
	_send(_button(JOY_BUTTON_A, true))
	await _frames(2)
	_send(_button(JOY_BUTTON_A, false))
	_record_focus_case("micro_keeper_manual_return", "InputEventJoypadButton:A", before,
		_simulation.get_snapshot(), event_start, 0, "pass")
	for frame: int in 150:
		if _simulation.get_snapshot().ball_owner_id == 0:
			break
		await _frames(1)
	received = _simulation.get_snapshot()
	_focus_changes[-1]["received"] = _startup_evidence(received)
	_check("manual keeper return reaches the controlled field player",
		received.selected_actor_id == 0 and received.ball_owner_id == 0 and received.ai_actor_ids == [2])
	setup.ball_position = Vector3(-17.95, 0.12, 0)
	if not await _prepare_focus_drill("micro keeper outside focus", setup):
		return
	before = _simulation.get_snapshot()
	event_start = _events.size()
	for frame: int in 180:
		if _simulation.get_snapshot().ball_owner_id == 0:
			break
		await _frames(1)
	_record_focus_case("micro_keeper_ai_return", "autonomous keeper; no human pass input", before,
		_simulation.get_snapshot(), event_start, 0, "keeper_ai")
	_check("keeper AI outside focus still returns physically", _simulation.get_snapshot().ball_owner_id == 0)


func _prepare_focus_drill(context: String, setup: Setup) -> bool:
	_release_gameplay_inputs()
	await _frames(2)
	if not _check(context + " uses production start after default proof", _start_drill(setup) == OK):
		return false
	await _frames(6)
	var state: Snapshot = _simulation.get_snapshot()
	return _check(context + " starts selected 0 with exact configured AI intent",
		state.selected_actor_id == 0 and state.ai_intent_actor_ids == setup.ai_actor_ids
		and _composition_matches(state, setup.mode) and _real_actor_ids() == _ids_for_mode(setup.mode))


func _record_focus_case(context: String, input: String, before: Snapshot, after: Snapshot,
		event_start: int, expected_id: int, reason: String) -> void:
	var relevant: Array[Dictionary] = _events.slice(event_start)
	var focus: Array[Dictionary] = relevant.filter(func(event: Dictionary) -> bool:
		return event["kind"] == Event.Kind.FOCUS_CHANGED)
	var passes: Array[Dictionary] = relevant.filter(func(event: Dictionary) -> bool:
		return event["kind"] == Event.Kind.PASS)
	var valid: bool = after.selected_actor_id == expected_id and _composition_matches(after, before.mode) \
		and after.ai_intent_actor_ids == before.ai_intent_actor_ids and after.score == before.score \
		and after.tick > before.tick and after.seconds_remaining < before.seconds_remaining
	if reason == "keeper_ai":
		valid = valid and focus.is_empty() and passes.size() == 1 \
			and passes[0]["actor"] == 2 and passes[0]["target"] == expected_id
	else:
		valid = valid and focus.size() == 1 and focus[0]["actor"] == before.selected_actor_id \
			and focus[0]["target"] == expected_id and focus[0]["reason"] == reason \
			and focus[0]["selected_actor_id"] == expected_id
		if reason == "pass":
			valid = valid and passes.size() == 1 and passes[0]["actor"] == before.selected_actor_id \
				and passes[0]["target"] == expected_id and passes[0]["id"] < focus[0]["id"] \
				and passes[0]["selected_actor_id"] == expected_id and after.ball_owner_id == -1
		else:
			valid = valid and passes.is_empty() and after.ball_owner_id == before.ball_owner_id
	_focus_changes.append({
		"case": context, "source_script": String(_host.get_script().resource_path), "input": input,
		"before_selected_actor_id": before.selected_actor_id, "after_selected_actor_id": after.selected_actor_id,
		"before_ball_owner_id": before.ball_owner_id, "after_ball_owner_id": after.ball_owner_id,
		"actor_count": after.actors.size(), "ai_intent_actor_ids": _intent_ids(after), "ai_actor_ids": _ai_ids(after),
		"expected_selected_actor_id": expected_id, "reason": reason,
		"before": _startup_evidence(before), "after": _startup_evidence(after), "events": relevant,
		"passed": valid,
	})
	_check(context + " confirms authoritative focus, intent and ordered events", valid)
	_check_hud(context)


func _release_gameplay_inputs() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
			KEY_J, KEY_K, KEY_L, KEY_SHIFT, KEY_CTRL, KEY_ESCAPE, KEY_ENTER, KEY_F1]:
		_send(_key(code, false))
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		_send(_axis(axis, 0.0))
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_START]:
		_send(_button(button, false))


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
	_check("final view is normal ten-actor PREVIEW PLAYING, not a modal", _final_preview(state))
	if bool(_report["headless"]):
		_check("headless makes no GPU claim", not bool(_report["gpu_validated"]))
		return
	var device_valid: bool = _report["rendering_method"] == "forward_plus" \
		and _report["rendering_driver"] == "vulkan" and RenderingServer.get_rendering_device() != null
	device_valid = device_valid and not String(_report["gpu_name"]).is_empty()
	if not _check("real Vulkan Forward+ device", device_valid):
		return
	var path: String = _argument("--capture-path=")
	if not _check("rendered smoke requires an absolute capture path", path.is_absolute_path()):
		return
	await RenderingServer.frame_post_draw
	state = _simulation.get_snapshot()
	_report["capture_phase"] = Snapshot.Phase.keys()[state.phase]
	_report["final_tick"] = state.tick
	_report["final_state"] = _startup_evidence(state)
	if not _check("captured frame is still ten-actor PREVIEW PLAYING without a modal", _final_preview(state)):
		return
	var image: Image = get_viewport().get_texture().get_image()
	var valid_image: bool = image != null and not image.is_empty() and image.get_size() == Vector2i(1920, 1080)
	if not _check("rendered viewport image is 1920x1080", valid_image):
		return
	var varied: bool = _has_pixel_variation(image)
	_check("rendered viewport contains nonuniform content", varied)
	var saved: Error = image.save_png(path)
	_check("actual viewport PNG saved", saved == OK)
	_report["capture_path"] = path
	_report["frames_drawn"] = Engine.get_frames_drawn()
	_report["gpu_validated"] = saved == OK and varied and state.phase == Snapshot.Phase.PLAYING
	_report["capture_hud_score"] = _label("Score").text


func _final_preview(state: Snapshot) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	return _composition_matches(state, PREVIEW_5V5) and _real_actor_ids() == _ids_for_mode(PREVIEW_5V5) \
		and state.selected_actor_id == 0 and _intent_ids(state) == _ids_for_mode(PREVIEW_5V5) \
		and state.training_exercise == Setup.TrainingExercise.FREE_PLAY \
		and _ai_ids(state) == _default_ai(PREVIEW_5V5) and state.phase == Snapshot.Phase.PLAYING \
		and camera != null and camera.is_current() and _host.is_ancestor_of(camera) \
		and _label("SelectedActor").is_visible_in_tree() and _label("SelectedActor").text == _selected_text(state) \
		and not _control("PauseOverlay").is_visible_in_tree() and not bool(_dev_menu.call(&"is_open"))


func _check_hud(context: String) -> bool:
	var state: Snapshot = _simulation.get_snapshot()
	var total: int = ceili(state.seconds_remaining)
	var clock: String = "%02d:%02d" % [floori(float(total) / 60.0), total % 60]
	return _check(context + " visible HUD mirrors authority", _label("Score").is_visible_in_tree()
		and _label("Score").text == "%d – %d" % [state.score.x, state.score.y]
		and _label("Clock").text == clock
		and not _hud_mode_text(_mode(state)).is_empty()
		and _label("SelectedActor").is_visible_in_tree() and _label("SelectedActor").text == _selected_text(state)
		and _label("ControlsContext").text.begins_with(_context_caption(state)))


func _context_caption(state: Snapshot) -> String:
	match state.human_control_context:
		Rules.ControlContext.LIVE:
			return "CON BALÓN" if state.ball_owner_id == state.selected_actor_id else "SIN BALÓN"
		Rules.ControlContext.RESTART_AIM:
			return "SAQUE PROPIO"
		Rules.ControlContext.RESTART_DEFEND:
			return "SAQUE RIVAL"
	return "CONTROLES EN ESPERA"


func _selected_text(state: Snapshot) -> String:
	return "CONTROL · ID %d\n%s LOCAL" % [state.selected_actor_id,
		"PORTERO" if state.actor(state.selected_actor_id).role == Snapshot.Role.KEEPER else "CAMPO"]


func _hud_mode_text(mode: int) -> String:
	for node: Node in _hud.find_children("*", "Label", true, false):
		var label: Label = node as Label
		var text: String = label.text.to_lower()
		if label.is_visible_in_tree() and (
				(mode == PREVIEW_5V5 and text.contains("5v5") and text.contains("experimental"))
				or (mode == MICRO_1V1 and text.contains("1v1") and text.contains("regresi"))):
			return label.text
	return ""


func _real_actor_ids() -> Array[int]:
	var ids: Array[int] = []
	if not is_instance_valid(_simulation):
		return ids
	for node: Node in _simulation.find_children("*", "CharacterBody3D", true, false):
		if node is Actor and node.get_script() == Actor:
			ids.append((node as Actor).actor_id)
	ids.sort()
	return ids


func _frozen(before: Snapshot, after: Snapshot) -> bool:
	if before == null or after == null or before.actors.size() != after.actors.size() or _mode(before) != _mode(after) \
			or before.selected_actor_id != after.selected_actor_id \
			or before.tick != after.tick or before.seconds_remaining != after.seconds_remaining \
			or before.phase != after.phase or before.score != after.score \
			or before.ball_position != after.ball_position or before.ball_velocity != after.ball_velocity \
			or before.ball_rotation != after.ball_rotation or before.ball_angular_velocity != after.ball_angular_velocity \
			or before.human_control_context != after.human_control_context \
			or before.human_allowed_actions != after.human_allowed_actions or before.selected_can_move != after.selected_can_move \
			or before.accumulated_fouls != after.accumulated_fouls or before.period_state != after.period_state \
			or before.training_exercise != after.training_exercise \
			or _restart_evidence(before.restart) != _restart_evidence(after.restart):
		return false
	for actor: Snapshot.ActorSnapshot in before.actors:
		var id: int = actor.actor_id
		if after.actor(id) == null or before.actor(id).position != after.actor(id).position or before.actor(id).velocity != after.actor(id).velocity \
				or before.actor(id).human_controlled != after.actor(id).human_controlled \
				or before.actor(id).last_command_sequence != after.actor(id).last_command_sequence \
				or before.actor(id).ball_in_hands != after.actor(id).ball_in_hands \
				or before.actor(id).gesture_kind != after.actor(id).gesture_kind \
				or before.actor(id).gesture_started_tick != after.actor(id).gesture_started_tick:
			return false
	return true


func _actor_evidence(actor: Snapshot.ActorSnapshot) -> Dictionary:
	return {"id": actor.actor_id, "team": actor.team_id, "role": actor.role, "human": actor.human_controlled,
		"position": _vector(actor.position), "velocity": _vector(actor.velocity), "sequence": actor.last_command_sequence,
		"ball_in_hands": actor.ball_in_hands, "ball_contact_reachable": actor.ball_contact_reachable,
		"gesture_kind": actor.gesture_kind, "gesture_started_tick": actor.gesture_started_tick,
		"gesture_duration_ticks": actor.gesture_duration_ticks,
		"gesture_direction": _vector(actor.gesture_direction), "gesture_contact_position": _vector(actor.gesture_contact_position)}


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _goal_count() -> int:
	return _events.filter(func(event: Dictionary) -> bool: return int(event["kind"]) == Event.Kind.GOAL).size()


func _on_event(event: Event) -> void:
	if event.kind != Event.Kind.BALL_CONTACT:
		var state: Snapshot = _simulation.get_snapshot()
		_events.append({"kind": event.kind, "id": event.event_id, "tick": event.tick, "actor": event.actor_id,
			"target": event.target_actor_id, "reason": String(event.reason), "score": [event.score.x, event.score.y],
			"selected_actor_id": state.selected_actor_id, "ball_owner_id": state.ball_owner_id,
			"position": _vector(event.position), "velocity": _vector(event.velocity),
			"launch_kind": event.launch_kind, "gesture_kind": event.gesture_kind,
			"contact_id": event.contact_id, "contact_point": _vector(event.contact_point),
			"foul_verdict": event.foul_verdict, "shot_charge": event.shot_charge,
			"restart": _restart_evidence(event.restart)})


func _on_rejection(actor_id: int, code: Error, message: String) -> void:
	_refusals.append({"actor": actor_id, "code": code, "message": message})


func _on_integration_error(code: Error, message: String) -> void:
	_integration_errors.append({"code": code, "message": message})


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = 0
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	return event


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap_key(code: Key) -> void:
	_send(_key(code, true))
	_send(_key(code, false))


func _pause_input(keyboard: bool) -> void:
	if keyboard:
		_tap_key(KEY_ESCAPE)
	else:
		_send(_button(JOY_BUTTON_START, true))
		_send(_button(JOY_BUTTON_START, false))


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _control(name: String) -> Control:
	return _hud.get_node("%" + name) as Control


func _label(name: String) -> Label:
	return _hud.get_node("%" + name) as Label


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _has_pixel_variation(image: Image) -> bool:
	var reference: Color = image.get_pixel(0, 0)
	var varied: int = 0
	for y: int in range(54, image.get_height(), 54):
		for x: int in range(96, image.get_width(), 96):
			var pixel: Color = image.get_pixel(x, y)
			if absf(pixel.r - reference.r) + absf(pixel.g - reference.g) + absf(pixel.b - reference.b) > 0.1:
				varied += 1
	return varied >= 20


func _check(name: String, passed: bool) -> bool:
	_checks.append({"name": name, "passed": passed})
	print(("PASS " if passed else "FAIL ") + name)
	return passed


func _finish(release_inputs: bool = true) -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	if release_inputs:
		_release_gameplay_inputs()
	_check("all planned smoke phases completed", _complete)
	_check("no production rejection through finalization", _refusals.is_empty())
	_check("no production integration error through finalization", _integration_errors.is_empty())
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	_report["checks"] = _checks
	_report["passed"] = _checks.size() - failures.size()
	_report["total"] = _checks.size()
	_report["ok"] = failures.is_empty()
	_report["complete"] = _complete
	_report["failures"] = failures
	_report["inputs"] = _input_evidence
	_report["mode_changes"] = _mode_changes
	_report["ai_changes"] = _ai_changes
	_report["focus_changes"] = _focus_changes
	_report["events"] = _events
	_report["command_rejections"] = _refusals
	_report["integration_errors"] = _integration_errors
	_report["driver_start_calls"] = _driver_start_calls
	_report["wall_seconds"] = float(Time.get_ticks_msec() - _started_msec) / 1000.0
	var path: String = _argument("--report-path=")
	if not path.is_empty():
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write preview smoke report: %s (error %d)" % [path, FileAccess.get_open_error()])
			get_tree().quit(2)
			return
		file.store_string(JSON.stringify(_report, "\t") + "\n")
		file.close()
	print(_report_marker() + " " + JSON.stringify(_report))
	get_tree().quit(0 if failures.is_empty() else 1)
