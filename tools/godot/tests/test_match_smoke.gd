extends SceneTree

const Smoke = preload("res://diagnostics/match_smoke.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")

var _checks: Array[Dictionary] = []
var _completed: bool = false


func _initialize() -> void:
	create_timer(10.0).timeout.connect(func() -> void:
		if not _completed:
			quit(1))
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--test-process-owner"):
		await create_timer(1.0).timeout
	var driver: Smoke = Smoke.new()
	root.add_child(driver)
	if OS.get_cmdline_user_args().has("--test-invalid-host"):
		_completed = true
		driver.run(null, null)
		return
	var empty_state: Snapshot = Snapshot.new()
	if Smoke.PROJECT_VERSION != "0.5.0-preview" \
			or driver._mode(empty_state) != Smoke.MICRO_1V1 or driver._ai_ids(empty_state) == [-1] \
			or typeof(empty_state.get("selected_actor_id")) != TYPE_INT \
			or typeof(empty_state.get("ai_intent_actor_ids")) != TYPE_ARRAY:
		print("FUTSAL_SMOKE_HELPER_DEPENDENCY " + JSON.stringify({
			"ok": false, "pending": ["MatchSnapshot.mode", "MatchSnapshot.ai_actor_ids",
				"MatchSnapshot.selected_actor_id", "MatchSnapshot.ai_intent_actor_ids", "Hicks 0.5.0-preview driver"],
			"scope": "player-control helper contracts unavailable; no unit or runtime acceptance",
		}))
		driver.free()
		_completed = true
		quit(3)
		return
	_check("driver is pause-safe", driver.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("constructing driver does not start smoke work", not driver.is_processing())
	_check("driver cannot start a drill before default proof", driver._start_drill(Setup.new()) == ERR_UNCONFIGURED)
	_check("refused early drill made no start call", driver._driver_start_calls == 0)
	var started: Snapshot = _state()
	started.phase = Snapshot.Phase.PLAYING
	started.tick = 10
	started.actor(0).last_command_sequence = 10
	_check("already PLAYING default is required", driver._default_started(started))
	var micro: Snapshot = _state(Smoke.MICRO_1V1)
	micro.phase = Snapshot.Phase.PLAYING
	_check("micro composition is valid only in its explicit mode", driver._composition_matches(micro, Smoke.MICRO_1V1))
	_check("four-actor micro cannot satisfy the preview default guard", not driver._default_started(micro))
	for mode: int in [Smoke.MICRO_1V1, Smoke.PREVIEW_5V5]:
		var keeper: Snapshot = _state(mode, 2)
		keeper.phase = Snapshot.Phase.PLAYING
		_check("selected HOME keeper remains a valid dynamic composition in mode %d" % mode,
			driver._composition_matches(keeper, mode))
		_check("selected HOME keeper cannot masquerade as default zero in mode %d" % mode,
			not driver._default_started(keeper))
	_check("preview requires ten exact actor identities", driver._ids_for_mode(Smoke.PREVIEW_5V5) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	_check("unknown mode cannot choose a fallback composition", driver._ids_for_mode(99).is_empty())
	var invalid: Snapshot = _state()
	invalid.phase = Snapshot.Phase.PLAYING
	invalid.actor(8).role = Snapshot.Role.KEEPER
	_check("additional preview athletes must remain field players", not driver._default_started(invalid))
	invalid = _state()
	invalid.phase = Snapshot.Phase.PLAYING
	var incomplete_ai: Array[int] = [1, 2, 3]
	invalid.set("ai_actor_ids", incomplete_ai)
	_check("default preview cannot silently leave six AI disabled", not driver._default_started(invalid))
	var advanced: Snapshot = _state()
	advanced.phase = Snapshot.Phase.PLAYING
	advanced.tick = 11
	advanced.seconds_remaining = 118.98
	advanced.actor(0).last_command_sequence = 11
	_check("untouched tick clock and command progression is accepted", driver._default_advanced(started, advanced))
	started.phase = Snapshot.Phase.READY
	_check("a host that never auto-started is rejected", not driver._default_started(started))
	_check("a later start cannot repair the untouched baseline", not driver._default_advanced(started, advanced))
	started.phase = Snapshot.Phase.PLAYING
	advanced.tick = 10
	_check("PLAYING label without ticks fails startup proof", not driver._default_advanced(started, advanced))
	advanced.tick = 11
	advanced.seconds_remaining = started.seconds_remaining
	_check("PLAYING label without clock advancement fails startup proof", not driver._default_advanced(started, advanced))
	advanced.seconds_remaining = 118.98
	advanced.actor(0).last_command_sequence = 10
	_check("missing default human command feed fails startup proof", not driver._default_advanced(started, advanced))
	advanced.actor(0).last_command_sequence = 11
	advanced.phase = Snapshot.Phase.PAUSED
	_check("a paused default cannot satisfy startup proof", not driver._default_advanced(started, advanced))
	_check("a null default cannot satisfy startup proof", not driver._default_started(null))
	var before: Snapshot = _state()
	var after: Snapshot = _state()
	_check("identical paused snapshots are frozen", driver._frozen(before, after))
	after.tick += 1
	_check("clock tick mutation is detected", not driver._frozen(before, after))
	after = _state()
	after.seconds_remaining -= 0.1
	_check("remaining-time mutation is detected", not driver._frozen(before, after))
	after = _state()
	after.ball_position.x += 0.01
	_check("native ball motion is detected", not driver._frozen(before, after))
	after = _state()
	after.ball_angular_velocity.x += 0.01
	_check("ball rotation velocity is covered by pause proof", not driver._frozen(before, after))
	for id: int in 10:
		after = _state()
		after.actor(id).position.z += 0.01
		_check("pause proof covers actor %d" % id, not driver._frozen(before, after))
	after = _state()
	after.actors.pop_back()
	_check("pause cannot silently remove a preview body", not driver._frozen(before, after))
	after = _state(Smoke.MICRO_1V1)
	_check("pause cannot silently replace the composition", not driver._frozen(before, after))
	after = _state()
	after.actor(0).last_command_sequence += 1
	_check("accepted input during pause is detected", not driver._frozen(before, after))
	after = _state(Smoke.PREVIEW_5V5, 2)
	_check("pause proof cannot hide a selected-identity change", not driver._frozen(before, after))
	var press: InputEventKey = driver._key(KEY_D, true)
	var release: InputEventKey = driver._key(KEY_D, false)
	_check("physical keyboard events use device zero and distinct release", press.device == 0
		and press.physical_keycode == KEY_D and press.pressed and not release.pressed and press != release)
	var axis: InputEventJoypadMotion = driver._axis(JOY_AXIS_LEFT_X, 0.0)
	_check("raw joypad release returns to neutral", axis.device == 0 and axis.axis_value == 0.0)
	var button: InputEventJoypadButton = driver._button(JOY_BUTTON_START, true)
	_check("Start is a raw device-zero button", button.device == 0 and button.button_index == JOY_BUTTON_START and button.pressed)
	var image: Image = Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	_check("blank synthetic image cannot pass content check", not driver._has_pixel_variation(image))
	image.fill_rect(Rect2i(300, 200, 1200, 600), Color.WHITE)
	_check("content check detects a varied synthetic test image", driver._has_pixel_variation(image))
	driver.free()
	_completed = true
	_report_result()


func _finalize() -> void:
	if not _completed:
		_check("native helper suite reached completion before shutdown", false)
		_report_result()


func _report_result() -> void:
	var failed: int = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"])).size()
	print("FUTSAL_SMOKE_HELPER_TESTS " + JSON.stringify({
		"ok": failed == 0, "passed": _checks.size() - failed, "total": _checks.size(), "checks": _checks,
		"scope": "driver helper unit tests; NOT a playable-main or GPU proof",
		"process_id": OS.get_process_id(), "executable": OS.get_executable_path(),
	}))
	quit(0 if failed == 0 else 1)


func _state(mode: int = Smoke.PREVIEW_5V5, selected_actor_id: int = 0) -> Snapshot:
	var state: Snapshot = Snapshot.new()
	state.phase = Snapshot.Phase.PAUSED
	state.seconds_remaining = 119.0
	state.set("mode", mode)
	var intent: Array[int] = [0, 1, 2, 3]
	if mode == Smoke.PREVIEW_5V5:
		intent.append_array([4, 5, 6, 7, 8, 9])
	var ai_ids: Array[int] = intent.duplicate()
	ai_ids.erase(selected_actor_id)
	state.set("selected_actor_id", selected_actor_id)
	state.set("ai_intent_actor_ids", intent)
	state.set("ai_actor_ids", ai_ids)
	for id: int in (10 if mode == Smoke.PREVIEW_5V5 else 4):
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.human_controlled = id == selected_actor_id
		actor.team_id = Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.position = Vector3(id, 0.0, 0.0)
		state.actors.append(actor)
	return state


func _check(name: String, passed: bool) -> void:
	_checks.append({"name": name, "passed": passed})
	if not passed:
		print("FAIL " + name)
