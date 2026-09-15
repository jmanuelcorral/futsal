extends SceneTree

const Simulation = preload("res://match/simulation/match_simulation.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Launch = preload("res://match/simulation/match_launch.gd")

const MODES: Array[Setup.Mode] = [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]
const EXERCISES: Array[Setup.TrainingExercise] = [
	Setup.TrainingExercise.FREE_PLAY, Setup.TrainingExercise.KICK_IN,
	Setup.TrainingExercise.CORNER_POS_X_NEG_Z, Setup.TrainingExercise.CORNER_POS_X_POS_Z,
	Setup.TrainingExercise.CORNER_NEG_X_NEG_Z, Setup.TrainingExercise.CORNER_NEG_X_POS_Z,
	Setup.TrainingExercise.GOAL_CLEARANCE, Setup.TrainingExercise.DRIBBLE_CUT,
	Setup.TrainingExercise.DRIBBLE_PACE_CHANGE, Setup.TrainingExercise.DIRECT_FREE_KICK,
	Setup.TrainingExercise.PENALTY_6M, Setup.TrainingExercise.ACCUMULATED_FREE_KICK,
]
const GROUPS: Array[String] = [
	"foul_tuning", "catalogue", "finishing_guards", "touch_and_query", "boundaries_and_mirror",
	"expiry_and_choices", "opponent_ready", "hand_ownership", "direct_goals", "release_episode_continuity",
	"separate_touches", "dribbles", "physical_fouls", "seventh_foul", "extensions",
	"extended_expiry", "world_isolation",
]

var _simulation: Simulation
var _scope: String = "initialization"
var _checks: Array[Dictionary] = []
var _names: Dictionary[String, bool] = {}
var _events: Array[Event] = []
var _scenarios: Array[Dictionary] = []
var _expected: Array[Dictionary] = []
var _negatives: Array[Dictionary] = []
var _unexpected: Array[Dictionary] = []
var _started_ms: int = 0
var _completed: bool = false
var _invalid_names: bool = false
var _selected_groups: Array[String] = GROUPS.duplicate()
var _diagnostics: Array[Dictionary] = []
var _last_progress_ms: int = 0
var _last_progress_frame: int = 0
var _pending_steps: int = 0
var _requested_steps: int = 0
var _physics_started_frame: int = 0
var _watchdog_failure: String = ""
var _watchdog_probe: bool = false


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_last_progress_ms = _started_ms
	_physics_started_frame = Engine.get_physics_frames()
	_last_progress_frame = _physics_started_frame
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if _watchdog_failure.is_empty() and not _completed:
		var idle_ms: int = Time.get_ticks_msec() - _last_progress_ms
		var unclaimed_steps: int = Engine.get_physics_frames() - _last_progress_frame
		if idle_ms > 30000 or unclaimed_steps > _pending_steps + 4 * Tuning.PHYSICS_HZ:
			_watchdog_failure = "No awaited-step progress: idle_ms=%d, physics_steps=%d, pending_budget=%d, scope=%s" % [
				idle_ms, unclaimed_steps, _pending_steps, _scope]
			push_error(_watchdog_failure)
			_report(2)
	return false


func _run() -> void:
	if not _configure_groups():
		return
	_simulation = Simulation.new()
	_simulation.event_raised.connect(func(event: Event) -> void: _events.append(event))
	_simulation.command_rejected.connect(_on_refusal)
	root.add_child(_simulation)
	await process_frame
	if _watchdog_probe:
		_scope = "intentional watchdog stalled-coroutine probe"
		_selected_groups.clear()
		await _frames(2)
		return
	_check("headless real Jolt at 60 Hz", DisplayServer.get_name() == "headless" and
		Engine.physics_ticks_per_second == 60 and ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics")
	_check("stable appended action/event values", Command.Action.SWITCH_TEAMMATE == 4 and Command.Action.DRIBBLE == 5 and
		Command.Action.KEEPER_THROW == 6 and Command.Action.CHOOSE_RESTART_SPOT == 7 and Event.Kind.FOCUS_CHANGED == 9 and
		Event.Kind.RESTART_CHANGED == 10 and Event.Kind.DRIBBLE == 11 and Event.Kind.FOUL == 12)
	_check("shared six-metre arcs do not enlarge the physical goal", Tuning.PENALTY_RADIUS == 6.0 and
		is_equal_approx(Tuning.GOAL_POST_CENTER_Z, 1.54) and is_equal_approx(Tuning.GOAL_POST_OUTER_Z, 1.58) and
		is_equal_approx(Tuning.PENALTY_STRAIGHT_LENGTH, 3.16) and Tuning.GOAL_WIDTH == 3.0 and Tuning.GOAL_HEIGHT == 2.0)
	for mode: Setup.Mode in MODES:
		if "foul_tuning" in _selected_groups:
			_foul_tuning(mode)
		if "catalogue" in _selected_groups:
			await _catalogue(mode)
		if "finishing_guards" in _selected_groups:
			await _finishing_guards(mode)
		if "touch_and_query" in _selected_groups:
			await _touch_and_query(mode)
		if "boundaries_and_mirror" in _selected_groups:
			await _boundaries_and_mirror(mode)
		if "expiry_and_choices" in _selected_groups:
			await _expiry_and_choices(mode)
		if "opponent_ready" in _selected_groups:
			await _opponent_ready(mode)
		if "hand_ownership" in _selected_groups:
			await _hand_ownership(mode)
		if "direct_goals" in _selected_groups:
			await _direct_goals(mode)
		if "release_episode_continuity" in _selected_groups:
			await _release_episode_continuity(mode)
		if "separate_touches" in _selected_groups:
			await _separate_touches(mode)
		if "dribbles" in _selected_groups:
			await _dribbles(mode)
		if "physical_fouls" in _selected_groups:
			await _physical_fouls(mode)
		var seventh_contact_ticks: int = -1
		if "seventh_foul" in _selected_groups:
			seventh_contact_ticks = await _seventh_foul(mode)
		if "extensions" in _selected_groups:
			await _extensions(mode)
		if "extended_expiry" in _selected_groups:
			await _extended_expiry(mode, seventh_contact_ticks)
	if "world_isolation" in _selected_groups:
		await _world_isolation()
	_scope = "completion"
	_check("every refusal matches an exact actor/code/message expectation", _expected.is_empty() and _unexpected.is_empty())
	_simulation.queue_free()
	await process_frame
	_completed = true
	_report()


func _configure_groups() -> bool:
	var specified: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--probe-watchdog" and not _watchdog_probe:
			_watchdog_probe = true
			continue
		if not argument.begins_with("--groups=") or specified:
			push_error("Use one --groups=name,... selector and optional --probe-watchdog")
			_report(2)
			return false
		specified = true
		_selected_groups.clear()
		for group: String in argument.trim_prefix("--groups=").split(",", false):
			if group not in GROUPS or group in _selected_groups:
				push_error("Unknown or duplicate gameplay test group: " + group)
				_report(2)
				return false
			_selected_groups.append(group)
		if _selected_groups.is_empty():
			push_error("Gameplay test selection cannot be empty")
			_report(2)
			return false
	if "extended_expiry" in _selected_groups and "seventh_foul" not in _selected_groups:
		_selected_groups.append("seventh_foul")
	return true


func _foul_tuning(mode: Setup.Mode) -> void:
	var defaults: Tuning = Tuning.new()
	if not _start("G28 foul tuning defaults and exported copy", _quiet(mode), defaults):
		return
	_check("agreed arcade foul defaults are published exactly", defaults.foul_challenge_window_ticks == 18 and
		defaults.foul_min_closing_speed == 0.8 and defaults.foul_reckless_closing_speed == 9.5)
	var copied: Tuning = defaults.duplicate(true) as Tuning
	_check("all three exported foul fields survive Resource duplication", copied != null and copied != defaults and
		copied.foul_challenge_window_ticks == 18 and copied.foul_min_closing_speed == 0.8 and copied.foul_reckless_closing_speed == 9.5)
	copied.foul_challenge_window_ticks = 60
	copied.foul_min_closing_speed = 4.0
	copied.foul_reckless_closing_speed = 20.0
	_check("resource copy edits do not change the supplied configuration", defaults.foul_challenge_window_ticks == 18 and
		defaults.foul_min_closing_speed == 0.8 and defaults.foul_reckless_closing_speed == 9.5)
	for specification: Dictionary in [
		{"name": "inclusive minima", "window": 1, "minimum": 0.1, "reckless": 2.0},
		{"name": "inclusive maxima", "window": 60, "minimum": 4.0, "reckless": 20.0},
		{"name": "strictly ordered neighbouring thresholds", "window": 18, "minimum": 4.0, "reckless": 4.000001},
	]:
		var candidate: Tuning = Tuning.new()
		candidate.foul_challenge_window_ticks = specification["window"]
		candidate.foul_min_closing_speed = specification["minimum"]
		candidate.foul_reckless_closing_speed = specification["reckless"]
		if not _start("G28 accepted foul tuning " + String(specification["name"]), _quiet(mode), candidate):
			return
		_check("legal tuning enters the actual requested world", _state().phase == Snapshot.Phase.PLAYING and
			_state().mode == mode and _state().accumulated_fouls == Vector2i.ZERO)
	var invalid_cases: Array[Dictionary] = [
		{"field": &"foul_challenge_window_ticks", "name": "below minimum", "value": 0, "low": 1.0, "high": 60.0},
		{"field": &"foul_challenge_window_ticks", "name": "above maximum", "value": 61, "low": 1.0, "high": 60.0},
		{"field": &"foul_min_closing_speed", "name": "below minimum", "value": 0.099, "low": 0.1, "high": 4.0},
		{"field": &"foul_min_closing_speed", "name": "above maximum", "value": 4.01, "low": 0.1, "high": 4.0},
		{"field": &"foul_min_closing_speed", "name": "NaN", "value": NAN, "low": 0.1, "high": 4.0},
		{"field": &"foul_min_closing_speed", "name": "infinite", "value": INF, "low": 0.1, "high": 4.0},
		{"field": &"foul_reckless_closing_speed", "name": "below minimum", "value": 1.99, "low": 2.0, "high": 20.0},
		{"field": &"foul_reckless_closing_speed", "name": "above maximum", "value": 20.01, "low": 2.0, "high": 20.0},
		{"field": &"foul_reckless_closing_speed", "name": "NaN", "value": NAN, "low": 2.0, "high": 20.0},
		{"field": &"foul_reckless_closing_speed", "name": "infinite", "value": INF, "low": 2.0, "high": 20.0},
	]
	for invalid: Dictionary in invalid_cases:
		var candidate: Tuning = Tuning.new()
		candidate.set(invalid["field"], invalid["value"])
		_scope = "G28 rejected foul tuning %s %s; mode=%d" % [invalid["field"], invalid["name"], mode]
		var before: Array = _fingerprint(_state())
		_simulation.tuning = candidate
		var message: String = "%s must be finite and within [%s, %s]" % [invalid["field"], invalid["low"], invalid["high"]]
		_allow_refusal("out-of-domain configuration", -1, ERR_INVALID_PARAMETER, message)
		_check("production start refuses invalid tuning without changing the active world", _simulation.start(_quiet(mode)) == ERR_INVALID_PARAMETER and
			_expected.is_empty() and before == _fingerprint(_state()))
	for reckless: float in [4.0, 3.9]:
		var candidate: Tuning = Tuning.new()
		candidate.foul_min_closing_speed = 4.0
		candidate.foul_reckless_closing_speed = reckless
		_scope = "G28 rejected foul threshold ordering %s; mode=%d" % [reckless, mode]
		var before: Array = _fingerprint(_state())
		_simulation.tuning = candidate
		_allow_refusal("unordered thresholds", -1, ERR_INVALID_PARAMETER, "Ordinary and reckless closing-speed thresholds must be ordered")
		_check("production reset rejects equal or reversed thresholds atomically", _simulation.reset(_quiet(mode)) == ERR_INVALID_PARAMETER and
			_expected.is_empty() and before == _fingerprint(_state()))


func _catalogue(mode: Setup.Mode) -> void:
	for exercise: Setup.TrainingExercise in EXERCISES:
		var setup: Setup = Setup.for_exercise(mode, exercise)
		if not _start("G01/G08/G30/G32 catalogue", setup):
			return
		var initial: Snapshot = _state()
		var count: int = 10 if mode == Setup.Mode.PREVIEW_5V5 else 4
		var bodies: Dictionary[int, bool] = {}
		for actor: Snapshot.ActorSnapshot in initial.actors:
			bodies[_body(actor.actor_id).get_rid().get_id()] = true
		_check("catalogue has actual distinct bodies and complete AI intention", bodies.size() == count and
			initial.actors.size() == count and initial.ai_intent_actor_ids.size() == count and initial.ai_actor_ids.size() == count - 1)
		_check("exercise and attack ends agree with goalkeeper spawns", initial.training_exercise == exercise and
			initial.actor(0).attack_direction == setup.attack_direction(0) and
			initial.actor(2).spawn_position.x * setup.attack_direction(0).x < 0.0 and
			initial.actor(3).spawn_position.x * setup.attack_direction(1).x < 0.0)
		_check_selected()
		var before: Array = _fingerprint(initial)
		var copied: Snapshot = initial.copy()
		copied.restart.deadline_tick = 0
		copied.restart.launch_contact_id = 999
		copied.restart.spot = Vector3(999, 999, 999)
		copied.ai_intent_actor_ids.clear()
		copied.human_allowed_actions.clear()
		copied.actor(0).gesture_kind = Types.GestureKind.CUT
		copied.actor(0).ball_in_hands = true
		copied.actors.clear()
		var setup_copy: Setup = setup.copy()
		setup_copy.ai_actor_ids.clear()
		setup_copy.actor_positions.clear()
		setup_copy.training_exercise = Setup.TrainingExercise.FREE_PLAY
		_check("new DTOs, arrays and catalogue copies cannot mutate authority", before == _fingerprint(_state()) and
			setup.training_exercise == exercise and setup.actor_positions.size() == count)
		if exercise in [Setup.TrainingExercise.FREE_PLAY, Setup.TrainingExercise.DRIBBLE_CUT, Setup.TrainingExercise.DRIBBLE_PACE_CHANGE]:
			_check("live exercises retain the original free-play entry", initial.phase == Snapshot.Phase.PLAYING and initial.restart.kind == Types.RestartKind.NONE)
			await _frames(4)
			_check("live catalogue advances physical simulation", _state().tick > initial.tick and _state().seconds_remaining < initial.seconds_remaining)
			continue
		_check("restart exercise starts at STOPPED without fabricated touches", initial.phase == Snapshot.Phase.RESTART_PAUSE and
			initial.restart.stage == Types.RestartStage.STOPPED and initial.last_touch_actor_id == -1 and initial.last_touch_tick == -1)
		_check("sixth exercise declares its seed instead of fake foul history", initial.accumulated_fouls ==
			(Vector2i(0, 6) if exercise == Setup.TrainingExercise.ACCUMULATED_FREE_KICK else Vector2i.ZERO) and _count(Event.Kind.FOUL) == 0)
		await _ready_restart()
		_check("own READY locks walking but exposes the taker's actions", _state().human_control_context == Types.ControlContext.RESTART_AIM and
			not _state().selected_can_move and _state().selected_actor_id == _state().restart.taker_actor_id)
		var placement: Event = _last(Event.Kind.RESTART_CHANGED, &"placement")
		var ready: Event = _last(Event.Kind.RESTART_CHANGED, &"ready")
		_check("placement consumes at least sixty actual authority ticks", placement != null and ready != null and
			ready.tick - placement.tick >= Tuning.RESTART_PLACEMENT_TICKS and _state().seconds_remaining == initial.seconds_remaining)
		_check("READY deadline uses its own clock and exempts the six-metre penalty",
			_state().restart.deadline_tick == (-1 if exercise == Setup.TrainingExercise.PENALTY_6M else _state().restart.ready_tick + 240))
		_check("disable generators for an unchanged launch comparison", _simulation.set_ai_actor_ids([]) == OK)
		var taker: int = _state().restart.taker_actor_id
		var stationary: Vector3 = _state().actor(taker).position
		var aiming: Command = _command(taker)
		aiming.move = Vector2.RIGHT
		aiming.aim = Vector2.RIGHT
		_check("own READY accepts aiming without walking", _simulation.submit_human_command(aiming) == OK)
		await _frames(16)
		_check("locked taker stays at the legal placement", _flat_distance(stationary, _state().actor(taker).position) < 0.001)
		var command: Command = _restart_command()
		var solution: Launch.Solution = _simulation.query_human_launch(command)
		_check("G17 ready query describes an executable physical launch", solution.error == OK and solution.executable and
			solution.origin.is_equal_approx(_state().ball_position) and solution.restart_id == _state().restart.id)
		var id: int = _state().restart.id
		_check("launch queues without changing focus or phase", _submit(command) == OK and
			_state().phase == Snapshot.Phase.RESTART_PAUSE and _state().selected_actor_id == taker)
		await _frames(1)
		var event: Event = _last(Event.Kind.SHOT if command.action == Command.Action.SHOOT else Event.Kind.PASS)
		_check("launch uses the same origin, velocity and power resolver", event != null and
			event.position.is_equal_approx(solution.origin) and event.velocity.is_equal_approx(solution.velocity) and
			event.target_actor_id == solution.effective_target_actor_id and event.launch_kind == solution.launch_kind)
		_check("accepted velocity survives thaw and enters PLAYING", _state().phase == Snapshot.Phase.PLAYING and
			_state().restart.id == id and _state().restart.stage == Types.RestartStage.IN_PLAY and _state().ball_velocity.length() > 1.0 and
			event != null and event.contact_id == _state().restart.launch_contact_id and event.restart.launch_contact_id == event.contact_id)
		if command.action != Command.Action.SHOOT and event != null and event.target_actor_id >= 0:
			_check("G11 pass focus precedes restart taken in the same tick", _index(Event.Kind.PASS) < _index(Event.Kind.FOCUS_CHANGED, &"pass") and
				_index(Event.Kind.FOCUS_CHANGED, &"pass") < _index(Event.Kind.RESTART_CHANGED, &"taken") and
				_state().selected_actor_id == event.target_actor_id and _state().ball_owner_id == -1)
		else:
			_check("shot or free launch does not fabricate focus", _state().selected_actor_id == taker)
		if exercise == Setup.TrainingExercise.GOAL_CLEARANCE:
			_check("G07 keeper releases the real hands anchor inside its area", event != null and
				event.launch_kind == Types.LaunchKind.KEEPER_THROW and event.position.y >= 0.7 and event.velocity.y > 0.0 and
				_state().ball_position.x < -14.0 and _state().phase == Snapshot.Phase.PLAYING)
	var before: Array = _fingerprint(_state())
	var invalid: Setup = Setup.for_exercise(mode, Setup.TrainingExercise.FREE_PLAY)
	invalid.set("training_exercise", 99)
	_allow_refusal("unknown exercise", -1, ERR_INVALID_PARAMETER, "Unknown catalogued training exercise")
	_check("unknown catalogue entry is rejected atomically", _simulation.start(invalid) == ERR_INVALID_PARAMETER and
		before == _fingerprint(_state()) and _expected.is_empty())


func _finishing_guards(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	var setup: Setup = _quiet(mode)
	setup.actor_positions[carrier] = Vector3.ZERO
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("G02 unselected HOME finishing", setup):
		return
	await _frames(4)
	_check("guard fixture has a physical nonselected HOME owner", _state().ball_owner_id == carrier and _state().selected_actor_id == 0)
	var before: Array = _fingerprint(_state())
	var shot: Command = _command(carrier)
	shot.action = Command.Action.SHOOT
	shot.aim = Vector2.RIGHT
	_reject_command("nonselected HOME shot", shot, ERR_UNAUTHORIZED, "Launch refused: allied_shot_forbidden")
	var disguised: Command = _command(carrier)
	disguised.action = Command.Action.PASS
	disguised.aim = Vector2.RIGHT
	_reject_command("free pass aimed through goal mouth", disguised, ERR_UNAUTHORIZED, "Launch refused: allied_disguised_shot_forbidden")
	_check("finishing refusals do not consume state or sequence", before == _fingerprint(_state()) and _count(Event.Kind.SHOT) == 0)
	setup.actor_positions[carrier] = Vector3(18.5, 0, 0)
	setup.ball_position = Vector3(19.05, 0.12, 0)
	if not _start("G02 HOME carry exclusion", setup):
		return
	await _frames(4)
	var move: Command = _command(carrier)
	move.move = Vector2.RIGHT
	move.sprint = true
	_reject_command("goalward HOME carry", move, ERR_UNAUTHORIZED, "Unselected HOME cannot deliberately carry into the goal mouth")
	move = _command(carrier)
	move.move = Vector2.LEFT
	move.close_control = true
	_check("retreat remains a legal real movement command", _submit(move) == OK)
	await _frames(6)
	_check("guard permits physical retreat without erasing accidental physics", _state().actor(carrier).position.x < 18.45 and _state().score == Vector2i.ZERO)
	for shooter: int in [0, 1]:
		setup = _quiet(mode)
		setup.actor_positions[shooter] = Vector3.ZERO
		setup.ball_position = Vector3(0.55 if shooter == 0 else -0.55, 0.12, 0)
		if not _start("G02 legal shooter %d" % shooter, setup):
			return
		await _frames(4)
		shot = _command(shooter)
		shot.action = Command.Action.SHOOT
		shot.aim = Vector2.RIGHT if shooter == 0 else Vector2.LEFT
		_check("human/AWAY production shot remains accepted", _submit(shot) == OK)
		await _frames(1)
		_check("human/AWAY shot creates physical motion without a focus event", _last(Event.Kind.SHOT) != null and
			_last(Event.Kind.SHOT).actor_id == shooter and _state().ball_velocity.length() > 5.0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	await _home_dribble_finishing(mode)
	await _home_dribble_revalidation(mode)
	await _legal_home_dribbles(mode)
	await _legal_dribble_goals(mode)
	await _mirrored_home_dribble(mode)
	await _accidental_home_goal(mode)


func _dribble_setup(mode: Setup.Mode, carrier: int, at: Vector3, forward: Vector2) -> Setup:
	var setup: Setup = _quiet(mode)
	setup.actor_positions[carrier] = at
	setup.actor_forwards[carrier] = forward
	setup.ball_position = at + Vector3(forward.x * 0.55, 0.12, forward.y * 0.55)
	return setup


func _home_dribble_finishing(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	for fixture: Dictionary in [
		{"name": "pace outside carry exclusion", "at": Vector3(16.9, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2.RIGHT},
		{"name": "neutral pace outside carry exclusion", "at": Vector3(16.9, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2.ZERO},
		{"name": "pace inside carry exclusion", "at": Vector3(18.5, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2.RIGHT},
		{"name": "cut from negative side outside exclusion", "at": Vector3(16.9, 0, -2), "forward": Vector2(0, 1), "aim": Vector2.RIGHT},
		{"name": "cut from positive side outside exclusion", "at": Vector3(16.9, 0, 2), "forward": Vector2(0, -1), "aim": Vector2.RIGHT},
	]:
		var setup: Setup = _dribble_setup(mode, carrier, fixture["at"], fixture["forward"])
		if not _start("G02 HOME forbidden dribble " + String(fixture["name"]), setup):
			return
		await _frames(4)
		_check("public fixture owns the reachable ball with HOME unselected and AI off", _state().ball_owner_id == carrier and
			_state().selected_actor_id == 0 and _state().actor(carrier).ball_contact_reachable and _state().ai_actor_ids.is_empty())
		var before: Array = _fingerprint(_state())
		var event_count: int = _events.size()
		var command: Command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = fixture["aim"]
		_reject_command("goal-directed physical dribble", command, ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish")
		_check("initial dribble refusal preserves state, sequence and events", before == _fingerprint(_state()) and _events.size() == event_count)
		await _frames(1)
		_check("refusal never releases an impulse or consumes gesture recovery", _count(Event.Kind.DRIBBLE) == 0 and
			_state().ball_owner_id == carrier and _state().actor(carrier).action_cooldown == 0.0 and
			_state().actor(carrier).gesture_kind == Types.GestureKind.NONE)
		command.aim = Vector2(0, 1) if fixture["forward"] == Vector2.RIGHT else Vector2.LEFT
		_check("same rejected sequence can queue a legal dribble on the next tick", _submit(command) == OK)
		await _frames(1)
		_check("retry produces one real cut rather than a stale forbidden impulse", _count(Event.Kind.DRIBBLE) == 1 and
			_last(Event.Kind.DRIBBLE).gesture_kind == Types.GestureKind.CUT and _state().ball_velocity.length() > 2.0 and _state().ball_owner_id == -1)
		await _frames(80)
		_check("no stale goalward impulse scores after the safe retry", _count(Event.Kind.GOAL) == 0 and _state().score == Vector2i.ZERO)
	for side: float in [-1.0, 1.0]:
		var setup: Setup = _dribble_setup(mode, carrier, Vector3(16.9, 0, side), Vector2(0, side))
		if not _start("G02 HOME cut with inherited velocity side=%s" % side, setup):
			return
		await _frames(4)
		var move: Command = _command(carrier)
		move.move = Vector2(0, -side)
		move.aim = Vector2(0, side)
		_check("public lateral movement builds actual cut inertia", _submit(move) == OK)
		await _frames(12)
		var state: Snapshot = _state()
		var nominal: Vector3 = Vector3(1, 0, 0.3 * side).normalized() * _simulation.tuning.dribble_cut_speed
		var flight: float = (Tuning.COURT_LENGTH * 0.5 - state.ball_position.x) / nominal.x
		_check("nominal cut misses but observed body inertia aims through the mouth", state.ball_owner_id == carrier and
			state.actor(carrier).velocity.z * side < -4.0 and
			absf(state.ball_position.z + nominal.z * flight) > Tuning.GOAL_WIDTH * 0.5 + Tuning.BALL_RADIUS and
			absf(state.ball_position.z + (nominal.z + state.actor(carrier).velocity.z * 0.25) * flight) < 1.35)
		var before: Array = _fingerprint(state)
		var command: Command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = Vector2.RIGHT
		_reject_command("inertia makes the real cut a finish", command, ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish")
		_check("inertial cut refusal is atomic", before == _fingerprint(_state()) and _count(Event.Kind.DRIBBLE) == 0)
		await _frames(1)
		_check("no cut impulse is hidden behind its nominal lateral direction", _count(Event.Kind.DRIBBLE) == 0 and _state().ball_owner_id == carrier)


func _home_dribble_revalidation(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	for side: float in [-1.0, 1.0]:
		var setup: Setup = _dribble_setup(mode, carrier, Vector3(16.9, 0, 1.75 * side), Vector2.RIGHT)
		if not _start("G02 HOME dribble turns goalward before contact side=%s" % side, setup):
			return
		await _frames(4)
		_check("current physical forward ray misses the goal before the queued turn", _state().ball_owner_id == carrier and
			absf(_state().ball_position.z) > Tuning.GOAL_WIDTH * 0.5 + Tuning.BALL_RADIUS and
			_state().actor(carrier).forward.is_equal_approx(Vector3.RIGHT))
		var command: Command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = Vector2(1, -0.4 * side).normalized()
		_check("safe current impulse is accepted before the native turn", _submit(command) == OK and
			_state().actor(carrier).last_command_sequence == command.sequence)
		_allow_refusal("changed physical heading at execution", carrier, ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish")
		await _frames(1)
		_check("execution revalidates the new heading before release and recovery", _expected.is_empty() and
			_state().actor(carrier).forward.z * side < -0.2 and _count(Event.Kind.DRIBBLE) == 0 and
			_state().ball_owner_id == carrier and _state().actor(carrier).action_cooldown == 0.0 and
			_state().actor(carrier).gesture_kind == Types.GestureKind.NONE and _state().actor(carrier).last_command_sequence == command.sequence)
		await _frames(80)
		_check("deferred refusal prevents a goal without rewriting physics or score", _count(Event.Kind.GOAL) == 0 and _state().score == Vector2i.ZERO)
		command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = Vector2(0, side)
		_check("execution refusal leaves recovery available to the next safe cut", _submit(command) == OK)
		await _frames(1)
		_check("new lateral intent releases the ball physically", _count(Event.Kind.DRIBBLE) == 1 and
			_last(Event.Kind.DRIBBLE).velocity.z * side > 2.0 and _state().ball_owner_id == -1)


func _legal_home_dribbles(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	for fixture: Dictionary in [
		{"name": "retreat inside exclusion", "at": Vector3(18.5, 0, 0), "forward": Vector2.LEFT, "aim": Vector2.ZERO, "axis": Vector3.LEFT, "kind": Types.GestureKind.PACE_CHANGE},
		{"name": "advance beside goal mouth", "at": Vector3(16.9, 0, 2.4), "forward": Vector2.RIGHT, "aim": Vector2.RIGHT, "axis": Vector3.RIGHT, "kind": Types.GestureKind.PACE_CHANGE},
		{"name": "negative cut inside exclusion", "at": Vector3(18.5, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2(0, -1), "axis": Vector3(0, 0, -1), "kind": Types.GestureKind.CUT},
		{"name": "positive cut inside exclusion", "at": Vector3(18.5, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2(0, 1), "axis": Vector3(0, 0, 1), "kind": Types.GestureKind.CUT},
	]:
		var setup: Setup = _dribble_setup(mode, carrier, fixture["at"], fixture["forward"])
		if not _start("G02 legal unselected HOME dribble " + String(fixture["name"]), setup):
			return
		await _frames(4)
		var before: Snapshot = _state()
		_check("legal fixture still has the unselected HOME owner", before.ball_owner_id == carrier and before.selected_actor_id == 0)
		var command: Command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = fixture["aim"]
		_check("non-finishing dribble is accepted rather than blanket banned", _submit(command) == OK)
		await _frames(1)
		var event: Event = _last(Event.Kind.DRIBBLE)
		_check("accepted gesture carries its real contact and directional impulse", event != null and event.contact_id >= 0 and
			event.gesture_kind == fixture["kind"] and event.velocity.dot(fixture["axis"]) > 2.0)
		await _frames(8)
		_check("ball physically travels in the legal direction without focus or teleport", (_state().ball_position - before.ball_position).dot(fixture["axis"]) > 0.3 and
			_flat_distance(before.actor(carrier).position, _state().actor(carrier).position) < 0.01 and
			_state().ball_owner_id == -1 and _state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0 and _state().score == Vector2i.ZERO)


func _legal_dribble_goals(mode: Setup.Mode) -> void:
	for fixture: Dictionary in [
		{"name": "selected field pace", "id": 0, "at": Vector3(16.9, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2.RIGHT, "kind": Types.GestureKind.PACE_CHANGE},
		{"name": "AWAY pace at opposite end", "id": 1, "at": Vector3(-16.9, 0, 0), "forward": Vector2.LEFT, "aim": Vector2.LEFT, "kind": Types.GestureKind.PACE_CHANGE},
		{"name": "selected HOME keeper pace", "id": 2, "at": Vector3(16.9, 0, 0), "forward": Vector2.RIGHT, "aim": Vector2.RIGHT, "kind": Types.GestureKind.PACE_CHANGE},
		{"name": "selected field cut from negative side", "id": 0, "at": Vector3(16.9, 0, -2), "forward": Vector2(0, 1), "aim": Vector2.RIGHT, "kind": Types.GestureKind.CUT},
		{"name": "selected field cut from positive side", "id": 0, "at": Vector3(16.9, 0, 2), "forward": Vector2(0, -1), "aim": Vector2.RIGHT, "kind": Types.GestureKind.CUT},
	]:
		var carrier: int = fixture["id"]
		var setup: Setup = _dribble_setup(mode, carrier, fixture["at"], fixture["forward"])
		if not _start("G02 legal physical dribble goal " + String(fixture["name"]), setup):
			return
		await _frames(4)
		if carrier == 2:
			var switch: Command = _command(0)
			switch.action = Command.Action.SWITCH_TEAMMATE
			switch.aim = _aim(_state().actor(0).position, _state().actor(carrier).position)
			_check("public off-ball switch selects the keeper, not an origin flag", _submit(switch) == OK)
			await _frames(1)
			_check("keeper becomes the actual current human", _state().selected_actor_id == carrier)
		_check("legal finisher owns the ball with no AI or goalkeeper in its path", _state().ball_owner_id == carrier and _state().ai_actor_ids.is_empty())
		var focus_events: int = _count(Event.Kind.FOCUS_CHANGED)
		var command: Command = _command(carrier)
		command.action = Command.Action.DRIBBLE
		command.aim = fixture["aim"]
		_check("selected HOME or AWAY retains the threatening dribble", _submit(command) == OK)
		await _frames(1)
		var event: Event = _last(Event.Kind.DRIBBLE)
		_check("legal finish comes from the actual dribble impulse", event != null and event.actor_id == carrier and
			event.gesture_kind == fixture["kind"] and event.contact_id >= 0 and event.velocity.length() > 4.0 and _state().ball_owner_id == -1)
		await _frames(80)
		var goal: Event = _last(Event.Kind.GOAL)
		_check("native complete-ball crossing proves the threatened goal is reachable", event != null and goal != null and
			goal.tick > event.tick and goal.actor_id == carrier and _count(Event.Kind.GOAL) == 1 and
			_state().score == (Vector2i(0, 1) if carrier == 1 else Vector2i(1, 0)) and
			_count(Event.Kind.SHOT) == 0 and _count(Event.Kind.PASS) == 0 and _count(Event.Kind.FOCUS_CHANGED) == focus_events)
		_scenarios[-1]["native_dribble_goal"] = {"actor_id": carrier, "dribble_tick": event.tick if event != null else -1,
			"velocity": str(event.velocity) if event != null else "", "goal_tick": goal.tick if goal != null else -1}


func _mirrored_home_dribble(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	var setup: Setup = _dribble_setup(mode, carrier, Vector3(-16.9, 0, 0), Vector2.LEFT)
	setup.training_exercise = Setup.TrainingExercise.CORNER_NEG_X_NEG_Z
	setup.actor_positions[0] = Vector3(-18, 0, -8)
	setup.ball_position = Vector3(-19.85, 0.12, -9.85)
	if not _start("G02 mirrored HOME dribble after a public corner and reception", setup):
		return
	await _ready_restart()
	var pass_command: Command = _command(0)
	pass_command.action = Command.Action.PASS
	pass_command.target_actor_id = carrier
	pass_command.aim = _aim(_state().ball_position, _state().actor(carrier).position)
	_check("mirrored corner enters live play with a real pass to the carrier", _submit(pass_command) == OK)
	await _frames(1)
	var switch: Command = _command(carrier)
	switch.action = Command.Action.SWITCH_TEAMMATE
	switch.aim = _aim(_state().actor(carrier).position, _state().actor(0).position)
	_check("public switch restores selection before the receiver owns the ball", _submit(switch) == OK)
	await _frames(1)
	for frame: int in range(90):
		if _state().ball_owner_id == carrier:
			break
		await _frames(1)
	var face: Command = _command(carrier)
	face.aim = Vector2.LEFT
	_check("received carrier can face the mirrored attacking goal", _submit(face) == OK)
	await _frames(12)
	_check("public mirrored fixture is outside exclusion with HOME unselected", _state().phase == Snapshot.Phase.PLAYING and
		_state().ball_owner_id == carrier and _state().actor(carrier).ball_contact_reachable and _state().selected_actor_id == 0 and
		_state().actor(carrier).position.x > -17.0 and _state().actor(carrier).attack_direction == Vector3.LEFT and
		_state().actor(carrier).forward.is_equal_approx(Vector3.LEFT) and
		absf(_state().ball_position.z) < Tuning.GOAL_WIDTH * 0.5 - Tuning.BALL_RADIUS)
	var before: Array = _fingerprint(_state())
	var command: Command = _command(carrier)
	command.action = Command.Action.DRIBBLE
	command.aim = Vector2.LEFT
	_reject_command("HOME finish toward the mirrored negative end", command, ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish")
	_check("mirrored refusal preserves physical state and sequence", before == _fingerprint(_state()))
	await _frames(1)
	_check("mirrored unselected carrier receives no dribble impulse", _count(Event.Kind.DRIBBLE) == 0 and _state().ball_owner_id == carrier)
	switch = _command(0)
	switch.action = Command.Action.SWITCH_TEAMMATE
	switch.aim = _aim(_state().actor(0).position, _state().actor(carrier).position)
	_check("actual human selection unlocks the same mirrored carrier", _submit(switch) == OK)
	await _frames(1)
	_check("same rejected dribble is legal for the newly selected HOME actor", _state().selected_actor_id == carrier and
		_submit(command) == OK)
	await _frames(1)
	var event: Event = _last(Event.Kind.DRIBBLE)
	_check("human mirrored dribble releases actual negative-X velocity", event != null and event.velocity.x < -7.0 and _state().ball_owner_id == -1)
	await _frames(80)
	var goal: Event = _last(Event.Kind.GOAL)
	_check("negative-end native dribble goal belongs to mirrored HOME", goal != null and goal.actor_id == carrier and
		goal.team_id == Snapshot.Team.HOME and _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	_scenarios[-1]["native_dribble_goal"] = {"actor_id": carrier, "dribble_tick": event.tick if event != null else -1,
		"velocity": str(event.velocity) if event != null else "", "goal_tick": goal.tick if goal != null else -1}


func _accidental_home_goal(mode: Setup.Mode) -> void:
	var carrier: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	var setup: Setup = _quiet(mode)
	setup.actor_positions[carrier] = Vector3(17, 0, 0)
	setup.ball_position = Vector3(18.4, 0.4, 0)
	setup.ball_velocity = Vector3(-31, 0, 0)
	if not _start("G02 accidental HOME body deflection remains a goal", setup):
		return
	await _frames(80)
	var contact: Event
	for event: Event in _events:
		if event.kind == Event.Kind.BALL_CONTACT and event.reason == &"athlete" and event.actor_id == carrier:
			contact = event
			break
	var goal: Event = _last(Event.Kind.GOAL)
	_check("real uncommanded body collision precedes the complete-ball crossing", contact != null and contact.actor_id == carrier and
		contact.contact_id >= 0 and goal != null and goal.tick > contact.tick and goal.actor_id == carrier)
	_check("physical accidental HOME goal is not erased by finishing policy", _state().score == Vector2i(1, 0) and
		_count(Event.Kind.GOAL) == 1 and _count(Event.Kind.DRIBBLE) == 0 and _count(Event.Kind.SHOT) == 0 and
		_count(Event.Kind.PASS) == 0 and _state().actor(carrier).last_command_sequence == -1 and _state().selected_actor_id == 0)
	_scenarios[-1]["native_deflection_goal"] = {"actor_id": carrier, "contact_tick": contact.tick if contact != null else -1,
		"goal_tick": goal.tick if goal != null else -1}


func _touch_and_query(mode: Setup.Mode) -> void:
	var setup: Setup = _quiet(mode)
	setup.actor_positions[0] = Vector3.ZERO
	setup.ball_position = Vector3(0.65, 0.12, 0)
	if not _start("G04/G16 controlled touch and pure query", setup):
		return
	_check("mere initial proximity is not an invented last touch", _state().last_touch_actor_id == -1 and _state().last_touch_tick == -1)
	await _frames(6)
	_check("actual bounded control produces a player touch", _state().ball_owner_id == 0 and _state().last_touch_actor_id == 0 and
		_events.any(func(event: Event) -> bool: return event.kind == Event.Kind.BALL_CONTACT and event.reason == &"controlled_touch" and event.contact_id >= 0))
	var invalid: Command = _command(0)
	invalid.move = Vector2(2, 0)
	_reject_command("diagnostic before pure queries", invalid, ERR_INVALID_PARAMETER, "Move must be a finite vector of length <= 1")
	var before: Array = _fingerprint(_state())
	var diagnostic: String = _simulation.last_error
	var nodes: int = _simulation.get_child_count()
	var request: Command = _command(0)
	request.action = Command.Action.SHOOT
	request.aim = Vector2(1, 0.2).normalized()
	request.shot_charge = 0.65
	var first: Launch.Solution = _simulation.query_human_launch(request)
	var repeatable: bool = first.error == OK and first.executable
	for repeat: int in range(32):
		var solution: Launch.Solution = _simulation.query_human_launch(request)
		repeatable = repeatable and solution.error == first.error and solution.velocity == first.velocity and solution.origin == first.origin
	_check("queries are repeatable, preserve diagnostics and create no worlds", repeatable and before == _fingerprint(_state()) and
		diagnostic == _simulation.last_error and nodes == _simulation.get_child_count())
	var foreign: Command = _command(1)
	foreign.action = Command.Action.SHOOT
	_check("query never exposes rival intent or changes last_error", _simulation.query_human_launch(foreign).error == ERR_UNAUTHORIZED and
		_simulation.last_error == diagnostic and before == _fingerprint(_state()))
	setup.ball_position = Vector3(0.55, 0.12, 0)
	setup.ball_velocity = Vector3(0, 6, 0)
	if not _start("G17 launch revalidates rising physical contact", setup):
		return
	for frame: int in range(12):
		await _frames(1)
		if _state().ball_position.y > 0.43:
			break
	request = _command(0)
	request.action = Command.Action.SHOOT
	_check("preview sees current reachable contact", _simulation.query_human_launch(request).executable and _state().ball_position.y <= 0.5)
	_check("current kick may be accepted before native ball rises away", _submit(request) == OK)
	_allow_refusal("lost contact at execution", 0, ERR_UNAVAILABLE, "Possession/contact was lost before the kick tick")
	await _frames(2)
	_check("stale guide cannot force a physical kick", _count(Event.Kind.SHOT) == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0 and _expected.is_empty())


func _boundaries_and_mirror(mode: Setup.Mode) -> void:
	for end_first: bool in [true, false]:
		var setup: Setup = _quiet(mode)
		setup.ball_position = Vector3(19.8, 0.4, 9.3) if end_first else Vector3(19.3, 0.4, 9.8)
		setup.ball_velocity = Vector3(20, 0, 10) if end_first else Vector3(10, 0, 20)
		if not _start("G04/G27 first boundary end_first=%s" % end_first, setup):
			return
		await _new_restart(-1, 30)
		_check("first complete physical crossing decides the border", _state().restart.border ==
			(Types.Border.POS_X if end_first else Types.Border.POS_Z) and _count(Event.Kind.GOAL) == 0)
		_check("unobserved actor proximity never substitutes last touch", _state().last_touch_actor_id == -1)
	for exercise: Setup.TrainingExercise in [Setup.TrainingExercise.CORNER_NEG_X_NEG_Z, Setup.TrainingExercise.CORNER_NEG_X_POS_Z]:
		var setup: Setup = _exercise(mode, exercise)
		if not _start("G06/G27 mirrored physical end", setup):
			return
		await _ready_restart()
		var restart_id: int = _state().restart.id
		var selection: int = _state().selected_actor_id
		var command: Command = _command(selection)
		command.action = Command.Action.SHOOT
		command.shot_charge = 1.0
		command.aim = Vector2.RIGHT
		_check("mirrored corner launches inward through production", _submit(command) == OK)
		await _new_restart(restart_id, 240)
		_check("mirrored attack ends award the opposite physical corner correctly", _state().restart.id > restart_id and
			_state().restart.kind == Types.RestartKind.CORNER and _state().restart.awarded_team_id == 1 and
			_state().restart.border == Types.Border.POS_X and _state().actor(0).attack_direction.x == -1.0)
		_check("AWAY award never steals human focus", _state().selected_actor_id == selection and _state().score == Vector2i.ZERO)


func _expiry_and_choices(mode: Setup.Mode) -> void:
	var exercises: Array[Setup.TrainingExercise] = [Setup.TrainingExercise.KICK_IN, Setup.TrainingExercise.CORNER_POS_X_NEG_Z,
		Setup.TrainingExercise.GOAL_CLEARANCE, Setup.TrainingExercise.DIRECT_FREE_KICK, Setup.TrainingExercise.ACCUMULATED_FREE_KICK]
	for exercise: Setup.TrainingExercise in exercises:
		var setup: Setup = _exercise(mode, exercise)
		if exercise == Setup.TrainingExercise.GOAL_CLEARANCE:
			setup.actor_positions[2] = Vector3(-18.5, 0, 5)
			setup.ball_position = Vector3(-18, 0.12, 5)
		if not _start("G09/G27/G28 expiry", setup):
			return
		await _ready_restart()
		var before: Snapshot = _state()
		var deadline: int = before.restart.deadline_tick
		_check("ready countdown is exactly 240 authority ticks", deadline - before.restart.ready_tick == 240)
		_check("pause during READY accepted", _simulation.set_paused(true) == OK)
		var frozen: Array = _fingerprint(_state())
		await _frames(8)
		_check("pause freezes deadline, physical anchor and authority ticks", frozen == _fingerprint(_state()))
		_check("resume keeps original deadline", _simulation.set_paused(false) == OK and _state().restart.deadline_tick == deadline)
		await _new_restart(before.restart.id, 250)
		var expected_kind: Types.RestartKind = Types.RestartKind.INDIRECT_FREE_KICK
		if exercise == Setup.TrainingExercise.KICK_IN:
			expected_kind = Types.RestartKind.KICK_IN
		elif exercise == Setup.TrainingExercise.CORNER_POS_X_NEG_Z:
			expected_kind = Types.RestartKind.GOAL_CLEARANCE
		_check("expiry awards its specific opposing restart", _state().restart.kind == expected_kind and _state().restart.awarded_team_id == 1)
		_check("expiry preserves score, foul count and human focus", _state().score == before.score and
			_state().accumulated_fouls == before.accumulated_fouls and _state().selected_actor_id == before.selected_actor_id and _count(Event.Kind.FOUL) == 0)
		if exercise == Setup.TrainingExercise.GOAL_CLEARANCE:
			var z: float = before.restart.spot.z
			var depth: float = sqrt(36.0 - pow(maxf(0.0, absf(z) - Tuning.GOAL_POST_OUTER_Z), 2.0))
			_check("hands timeout projects longitudinally onto the real curved area", is_equal_approx(_state().restart.spot.z, z) and
				is_equal_approx(_state().restart.spot.x, -20.0 + depth) and is_equal_approx(_state().restart.spot.y, Tuning.BALL_RADIUS))
		if exercise == Setup.TrainingExercise.DIRECT_FREE_KICK:
			await _ready_restart()
			var indirect_id: int = _state().restart.id
			await _new_restart(indirect_id, 250)
			_check("indirect timeout also changes team without adding a foul", _state().restart.kind == Types.RestartKind.INDIRECT_FREE_KICK and
				_state().restart.awarded_team_id == 0 and _state().accumulated_fouls == Vector2i.ZERO)
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.KICK_IN)
	if not _start("G09 exact deadline beats pending action", setup):
		return
	await _ready_restart()
	var deadline: int = _state().restart.deadline_tick
	await _frames(deadline - _state().tick - 1)
	var command: Command = _restart_command()
	var taker: int = command.actor_id
	var old_id: int = _state().restart.id
	_check("last observed pre-deadline input can be queued", _submit(command) == OK)
	_allow_refusal("deadline precedes pending kick", taker, ERR_UNAVAILABLE, "Restart deadline elapsed before the pending action")
	await _frames(1)
	_check("deadline tick expires before applying any kick", _state().restart.id > old_id and _count(Event.Kind.PASS) == 0 and
		_state().actor(taker).last_command_sequence == command.sequence and _expected.is_empty())
	if not _start("G22 sixth choice preserves deadline", _exercise(mode, Setup.TrainingExercise.ACCUMULATED_FREE_KICK)):
		return
	await _ready_restart()
	deadline = _state().restart.deadline_tick
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.PASS
	_reject_command("sixth requires SHOT, never PASS", command, ERR_UNAUTHORIZED, "Launch refused: launch_rule")
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.CHOOSE_RESTART_SPOT
	command.restart_spot_choice = Types.SpotChoice.OFFENCE_SPOT
	_check("legal longitudinal offence choice accepted", _submit(command) == OK)
	await _frames(1)
	_check("choice moves to declared offence without resetting any clock or sequence", _state().restart.spot == _state().restart.offence_spot and
		_state().restart.deadline_tick == deadline and _state().actor(command.actor_id).last_command_sequence == command.sequence and
		_state().accumulated_fouls == Vector2i(0, 6))
	if not _start("G09 penalty has no four-second expiry", _exercise(mode, Setup.TrainingExercise.PENALTY_6M)):
		return
	await _ready_restart()
	old_id = _state().restart.id
	await _frames(270)
	_check("six-metre penalty remains ready without an invented timeout", _state().restart.id == old_id and
		_state().restart.stage == Types.RestartStage.READY and _state().restart.deadline_tick == -1 and _state().accumulated_fouls == Vector2i.ZERO)


func _direct_goals(mode: Setup.Mode) -> void:
	for own: bool in [false, true]:
		var setup: Setup = _exercise(mode, Setup.TrainingExercise.KICK_IN)
		setup.actor_positions[2].z = 8.0
		setup.actor_positions[3].z = 8.0
		if not _start("G10 direct kick-in own=%s" % own, setup):
			return
		await _ready_restart()
		var old_id: int = _state().restart.id
		var selected: int = _state().selected_actor_id
		var command: Command = _command(selected)
		command.action = Command.Action.SHOOT
		command.shot_charge = 1.0
		command.aim = _aim(_state().ball_position, Vector3(-21 if own else 21, 0, 0))
		_check("direct-goal restriction is adjudicated after a real launch", _submit(command) == OK)
		await _new_restart(old_id, 200)
		_check("direct kick-in never creates an illegal score", _state().score == Vector2i.ZERO and _count(Event.Kind.GOAL) == 0 and
			_state().restart.kind == (Types.RestartKind.CORNER if own else Types.RestartKind.GOAL_CLEARANCE))
		_check("physical own/opponent goal consequence awards AWAY without changing focus", _state().restart.awarded_team_id == 1 and _state().selected_actor_id == selected)
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.DIRECT_FREE_KICK)
	setup.actor_positions[3] = Vector3(18.5, 0, 8)
	if not _start("G10/G24 direct free kick may score", setup):
		return
	await _ready_restart()
	var command: Command = _command(_state().selected_actor_id)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.aim = _aim(_state().ball_position, Vector3(21, 0, 0))
	_check("direct free kick is physically accepted", _submit(command) == OK)
	await _phase(Snapshot.Phase.GOAL_PAUSE, 120)
	_check("a permitted complete-ball goal scores once", _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	setup = _exercise(mode, Setup.TrainingExercise.DIRECT_FREE_KICK)
	setup.actor_positions[2].z = 8.0
	if mode == Setup.Mode.PREVIEW_5V5:
		setup.actor_positions[8].z = 8.0
	if not _start("G10 indirect from real expiry cannot score directly", setup):
		return
	await _ready_restart()
	var id: int = _state().restart.id
	await _new_restart(id, 250)
	await _ready_restart()
	id = _state().restart.id
	command = _command(_state().restart.taker_actor_id)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.aim = _aim(_state().ball_position, Vector3(-21, 0, 0.8))
	_check("opposing indirect uses its legal physical shooting command", _submit(command) == OK)
	await _new_restart(id, 200)
	_check("untouched indirect goal becomes the defending team's clearance", _state().score == Vector2i.ZERO and
		_count(Event.Kind.GOAL) == 0 and _state().restart.kind == Types.RestartKind.GOAL_CLEARANCE and _state().restart.awarded_team_id == 0)
	if not _start("G07/G10 own-goal hands release", _exercise(mode, Setup.TrainingExercise.GOAL_CLEARANCE)):
		return
	await _ready_restart()
	id = _state().restart.id
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.KEEPER_THROW
	command.aim = Vector2.LEFT
	_check("hands release uses real ball velocity even toward own goal", _submit(command) == OK)
	await _new_restart(id, 140)
	_check("direct own-goal throw awards a corner instead of a goal", _state().score == Vector2i.ZERO and
		_count(Event.Kind.GOAL) == 0 and _state().restart.kind == Types.RestartKind.CORNER and _state().restart.awarded_team_id == 1)


func _opponent_ready(mode: Setup.Mode) -> void:
	if not _start("G05/G12/G13 opponent READY and generator", _exercise(mode, Setup.TrainingExercise.KICK_IN)):
		return
	await _ready_restart()
	var id: int = _state().restart.id
	await _new_restart(id, 250)
	await _ready_restart()
	var state: Snapshot = _state()
	var taker: int = state.restart.taker_actor_id
	var taker_sequence: int = state.actor(taker).last_command_sequence
	var clock: int = state.restart.deadline_tick
	var spot: Vector3 = state.ball_position
	var accepted: bool = true
	for frame: int in range(20):
		var move: Command = _command(_state().selected_actor_id)
		move.move = _aim(_state().actor(move.actor_id).position, _state().restart.spot)
		move.sprint = true
		accepted = (_submit(move) == OK) and accepted
		await _frames(1)
	_check("rival READY allows real defense but constrains the five-metre distance", accepted and
		_state().human_control_context == Types.ControlContext.RESTART_DEFEND and _state().selected_can_move and
		_flat_distance(_state().actor(_state().selected_actor_id).position, _state().restart.spot) >= 5.0)
	_check("disabled taker never generates an action or loses the stationary ball", _state().phase == Snapshot.Phase.RESTART_PAUSE and
		_state().actor(taker).last_command_sequence == taker_sequence and _state().ball_position == spot and _count(Event.Kind.PASS) == 0)
	var old_selection: int = _state().selected_actor_id
	var command: Command = _command(old_selection)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("defender can switch through the same production command", _submit(command) == OK)
	await _frames(1)
	_check("defensive handoff preserves opposing taker, deadline and intention", _state().selected_actor_id != old_selection and
		_state().restart.taker_actor_id == taker and _state().restart.deadline_tick == clock and _state().ai_intent_actor_ids.is_empty())
	var selected: int = _state().selected_actor_id
	_check("enable only the actual opposing taker", _simulation.set_ai_actor_ids([taker]) == OK)
	await _phase(Snapshot.Phase.PLAYING, 70)
	_check("enabled AI takes a legal physical restart without stealing human focus", _last(Event.Kind.PASS) != null and
		_last(Event.Kind.PASS).actor_id == taker and _state().selected_actor_id == selected and
		_state().actor(taker).last_command_sequence > taker_sequence and _state().ai_intent_actor_ids == [taker])


func _hand_ownership(mode: Setup.Mode) -> void:
	for home: bool in [true, false]:
		var exercise: Setup.TrainingExercise = Setup.TrainingExercise.GOAL_CLEARANCE if home else Setup.TrainingExercise.CORNER_NEG_X_POS_Z
		if not _start("G07/G23 authoritative hands ownership home=%s" % home, _exercise(mode, exercise)):
			return
		if not home:
			await _ready_restart()
			await _new_restart(_state().restart.id, 250)
		var stopped: Snapshot = _state()
		var taker: int = stopped.restart.taker_actor_id
		_check("STOPPED has no fictional hands possession before placement", stopped.restart.kind == Types.RestartKind.GOAL_CLEARANCE and
			stopped.restart.stage == Types.RestartStage.STOPPED and stopped.ball_owner_id == -1 and
			stopped.actors.all(func(actor: Snapshot.ActorSnapshot) -> bool: return not actor.ball_in_hands))
		var observations: Array[Dictionary] = []
		var observer: Callable = func(event: Event) -> void:
			var current: Snapshot = _state()
			if current.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
				observations.append({"tick": current.tick, "stage": current.restart.stage, "owner": current.ball_owner_id,
					"taker": current.restart.taker_actor_id, "hands": current.actor(current.restart.taker_actor_id).ball_in_hands,
					"consistent": _hands_match_owner(current), "event_reason": String(event.reason)})
		_simulation.event_raised.connect(observer)
		await _frames(1)
		var placed: Snapshot = _state()
		_check("physical PLACEMENT already publishes its actual keeper as owner", placed.restart.stage == Types.RestartStage.PLACEMENT and
			placed.actor(taker).ball_in_hands and placed.ball_owner_id == taker and _hands_match_owner(placed))
		_check("placing the held ball is not a played touch or save", placed.last_touch_actor_id == -1 and
			placed.last_touch_tick == -1 and placed.restart.launch_contact_id == -1 and _count(Event.Kind.SAVE) == 0 and
			_count(Event.Kind.PASS) == 0 and placed.human_control_context == Types.ControlContext.DISABLED)
		_check("pause during hand placement is accepted", _simulation.set_paused(true) == OK)
		var frozen: Array = _fingerprint(_state())
		await _frames(3)
		_check("paused hand placement keeps matching owner and a genuinely frozen snapshot", frozen == _fingerprint(_state()) and
			_state().actor(taker).ball_in_hands and _state().ball_owner_id == taker and _hands_match_owner(_state()))
		_check("resume returns to the same hand placement", _simulation.set_paused(false) == OK)
		if home:
			await _ready_restart()
			_check("READY keeps the same hands owner without inventing contact history", _state().ball_owner_id == taker and
				_state().actor(taker).ball_in_hands and _state().last_touch_actor_id == -1)
		else:
			await _frames(45)
			_check("corner expiry remains coherent throughout the camera transition interval", _state().restart.stage == Types.RestartStage.PLACEMENT and
				_state().actor(taker).team_id == Snapshot.Team.AWAY and _state().ball_owner_id == taker and _hands_match_owner(_state()))
		_check("all public restart callbacks expose coherent current-frame hands ownership", not observations.is_empty() and
			observations.all(func(item: Dictionary) -> bool: return bool(item["consistent"])))
		_scenarios[-1]["hands_state_observations"] = observations.duplicate(true)
		_simulation.event_raised.disconnect(observer)
		_check("public reset during this context clears hands without stale keeper ownership", _simulation.start(_exercise(mode, Setup.TrainingExercise.FREE_PLAY)) == OK and
			_state().restart.kind == Types.RestartKind.NONE and _state().ball_owner_id == -1 and
			_state().actors.all(func(actor: Snapshot.ActorSnapshot) -> bool: return not actor.ball_in_hands))


func _hands_match_owner(state: Snapshot) -> bool:
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.ball_in_hands and (state.ball_owner_id != actor.actor_id or actor.role != Snapshot.Role.KEEPER):
			return false
	return true


func _release_episode_continuity(mode: Setup.Mode) -> void:
	if not _start("G10 original hands release remains continuous until real shape separation",
		_exercise(mode, Setup.TrainingExercise.GOAL_CLEARANCE)):
		return
	await _ready_restart()
	var taker: int = _state().restart.taker_actor_id
	var restart_id: int = _state().restart.id
	_check("hands fixture begins with actual sphere and keeper shape overlap", _state().actor(taker).ball_in_hands and _ball_overlaps_actor(taker))
	var command: Command = _command(taker)
	command.action = Command.Action.KEEPER_THROW
	command.aim = Vector2.LEFT
	_check("hands fixture releases through the production authority", _submit(command) == OK)
	await _frames(3)
	var release: Event = _last(Event.Kind.PASS)
	_scenarios[-1]["launch_contact_id"] = _state().restart.launch_contact_id
	_check("continuous physical release beyond t plus one is not a second touch", release != null and _ball_overlaps_actor(taker) and
		_state().phase == Snapshot.Phase.PLAYING and _state().restart.id == restart_id and _state().tick > release.tick + 1 and
		_state().restart.launch_contact_id == release.contact_id and not _state().restart.other_actor_touched)
	_check("pause preserves the active release without resetting its identity", _simulation.set_paused(true) == OK)
	var frozen: Array = _fingerprint(_state())
	await _frames(5)
	_check("paused release has no clock-based contact expiry", frozen == _fingerprint(_state()) and _ball_overlaps_actor(taker))
	_check("resume preserves the same physical flight", _simulation.set_paused(false) == OK)
	for frame: int in range(15):
		if not _ball_overlaps_actor(taker):
			break
		await _frames(1)
	_check("release reaches actual separation without inventing another restart", not _ball_overlaps_actor(taker) and
		_state().phase == Snapshot.Phase.PLAYING and _state().restart.id == restart_id)


func _separate_touches(mode: Setup.Mode) -> void:
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.KICK_IN)
	setup.actor_positions[0] = Vector3(3, 0, -8.9)
	var tuning: Tuning = Tuning.new()
	tuning.shot_min_speed = 5.0
	tuning.maximum_shot_lift = 4.0
	if not _start("G10 separate original-taker touch", setup, tuning):
		return
	await _ready_restart()
	var taker: int = _state().restart.taker_actor_id
	var id: int = _state().restart.id
	var command: Command = _command(taker)
	command.action = Command.Action.SHOOT
	command.aim = Vector2(0, 1)
	command.shot_lift = 1.0
	_check("first legal stroke does not manufacture a double touch", _submit(command) == OK)
	await _frames(2)
	var kick: Event = _last(Event.Kind.SHOT)
	_scenarios[-1]["launch_contact_id"] = _state().restart.launch_contact_id
	_check("original kick remains one permitted episode", kick != null and _state().restart.id == id and _state().phase == Snapshot.Phase.PLAYING and
		_state().restart.launch_contact_id == kick.contact_id and kick.restart.launch_contact_id == kick.contact_id)
	var accepted: bool = true
	for frame: int in range(100):
		if _state().restart.id != id:
			break
		command = _command(taker)
		command.move = _aim(_state().actor(taker).position, _state().ball_position)
		command.aim = command.move
		command.sprint = true
		accepted = (_submit(command) == OK) and accepted
		await _frames(1)
	var second_contact: Event
	for event: Event in _events:
		if event.kind == Event.Kind.BALL_CONTACT and event.actor_id == taker and event.reason == &"athlete" and kick != null and event.contact_id != kick.contact_id:
			second_contact = event
	if second_contact != null:
		_scenarios[-1]["native_second_contact"] = {"contact_id": second_contact.contact_id, "tick": second_contact.tick,
			"actor_id": second_contact.actor_id, "surface": String(second_contact.reason)}
	_check("a new native self-contact episode creates an indirect rather than another shot", accepted and _state().restart.id > id and
		_state().restart.kind == Types.RestartKind.INDIRECT_FREE_KICK and _state().restart.awarded_team_id == 1 and
		_state().last_touch_actor_id == taker and second_contact != null and second_contact.tick >= kick.tick and
		_state().last_touch_tick == second_contact.tick and _state().restart.launch_contact_id == -1)
	_check("double touch never increments accumulated fouls", _state().accumulated_fouls == Vector2i.ZERO and _count(Event.Kind.FOUL) == 0)
	setup = _exercise(mode, Setup.TrainingExercise.KICK_IN)
	setup.actor_positions[3].z = 8.0
	if not _start("G10 post is not another player", setup):
		return
	await _ready_restart()
	id = _state().restart.id
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.aim = _aim(_state().ball_position, Vector3(20, 0, Tuning.GOAL_POST_CENTER_Z))
	_check("post fixture uses a real restart shot", _submit(command) == OK)
	for frame: int in range(140):
		await _frames(1)
		if _last(Event.Kind.BALL_CONTACT, &"post") != null or _state().restart.id != id:
			break
	_check("native post contact leaves the player-touch restriction active", _last(Event.Kind.BALL_CONTACT, &"post") != null and
		_state().restart.id == id and not _state().restart.other_actor_touched and _state().score == Vector2i.ZERO)
	var receiver: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 2
	setup = _exercise(mode, Setup.TrainingExercise.KICK_IN)
	setup.actor_positions[0] = Vector3(3, 0, -8.9)
	setup.actor_positions[receiver] = Vector3(3, 0, -7)
	setup.actor_forwards[receiver] = Vector2(0, -1)
	setup.actor_positions[3].z = 8.0
	if not _start("G10 another real player lifts restriction", setup, tuning):
		return
	await _ready_restart()
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.SHOOT
	command.aim = Vector2(0, 1)
	_check("kick-in moves physically to a distinct teammate", _submit(command) == OK)
	for frame: int in range(120):
		await _frames(1)
		if _state().ball_owner_id == receiver and _state().restart.other_actor_touched:
			break
	_check("only actual reception/control lifts the restriction", _state().ball_owner_id == receiver and _state().restart.other_actor_touched and _state().last_touch_actor_id == receiver)
	command = _command(_state().selected_actor_id)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("human focuses the actual receiver without a synthetic pass", _submit(command) == OK)
	await _frames(1)
	_check("receiver has real human control", _state().selected_actor_id == receiver)
	command = _command(receiver)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.aim = _aim(_state().ball_position, Vector3(21, 0, 0))
	_check("received ball can now be legally shot", _submit(command) == OK)
	await _phase(Snapshot.Phase.GOAL_PAUSE, 180)
	_check("goal after another player touch is not wrongly disallowed", _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)


func _dribbles(mode: Setup.Mode) -> void:
	for direction: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2.ZERO, Vector2.RIGHT]:
		var setup: Setup = _quiet(mode)
		setup.actor_positions[0] = Vector3.ZERO
		setup.ball_position = Vector3(0.55, 0.12, 0)
		if not _start("G19 dribble direction=%s" % str(direction), setup):
			return
		await _frames(4)
		var before: Snapshot = _state()
		var command: Command = _command(0)
		command.action = Command.Action.DRIBBLE
		command.aim = direction
		_check("gesture edge is accepted at reachable physical contact", _submit(command) == OK)
		await _frames(1)
		var event: Event = _last(Event.Kind.DRIBBLE)
		var cut: bool = absf(direction.y) > 0.5
		_check("gesture metadata follows an actual impulse and contact tick", event != null and event.contact_id >= 0 and
			event.gesture_kind == (Types.GestureKind.CUT if cut else Types.GestureKind.PACE_CHANGE) and
			_state().actor(0).gesture_started_tick == event.tick and event.velocity.length() > 2.0)
		_check("dribble does not teleport athlete or guarantee ball ownership", _flat_distance(before.actor(0).position, _state().actor(0).position) < 0.01 and
			_state().ball_owner_id == -1 and _state().ball_position.distance_to(before.ball_position) < 0.3)
		if cut:
			_check("left/right cut changes the real transverse velocity", event != null and event.velocity.z * direction.y > 2.0)
		else:
			_check("pace change moves the real ball forward", event != null and event.velocity.x > 5.0)
		command = _command(0)
		command.action = Command.Action.DRIBBLE
		_reject_command("gesture cannot be replayed during recovery", command, ERR_BUSY, "Action is cooling down")
	var setup: Setup = _quiet(mode)
	setup.actor_positions[0] = Vector3.ZERO
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("G19 backward input is not a third gesture", setup):
		return
	await _frames(4)
	var before: Array = _fingerprint(_state())
	var command: Command = _command(0)
	command.action = Command.Action.DRIBBLE
	command.aim = Vector2.LEFT
	_reject_command("no backward third gesture", command, ERR_UNAVAILABLE, "Backward input does not define a third dribble")
	_check("backward refusal is atomic", before == _fingerprint(_state()) and _count(Event.Kind.DRIBBLE) == 0)
	setup.actor_positions[1] = Vector3(0.6, 0, 1.0)
	setup.actor_forwards[1] = Vector2(0, -1)
	if not _start("G19 cut recovery exposes the actual ball to interception", setup):
		return
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.DRIBBLE
	command.aim = Vector2(0, 1)
	_check("interceptable cut is accepted without an ownership guarantee", _submit(command) == OK)
	for frame: int in range(20):
		await _frames(1)
		if _state().ball_owner_id == 1 and _state().last_touch_actor_id == 1:
			break
	_check("opponent physically wins the ball during gesture recovery", _state().ball_owner_id == 1 and
		_state().last_touch_actor_id == 1 and _state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)


func _physical_fouls(mode: Setup.Mode) -> void:
	for label: String in ["ordinary", "gentle", "expired", "late", "late_window", "clean", "reckless", "penalty", "historical"]:
		var setup: Setup = _quiet(mode)
		var tuning: Tuning = Tuning.new()
		var ball_first: bool = label in ["clean", "reckless"]
		var fast: bool = label == "reckless"
		setup.actor_positions[0] = Vector3(18 if label == "penalty" else 0, 0, 0)
		setup.actor_positions[1] = Vector3(16.6 if label == "penalty" else (-0.84 if label == "clean" else (-1.28 if fast else -1.4)), 0, 0)
		if label == "gentle":
			setup.actor_positions[1] = Vector3(-0.59, 0, 0)
		elif label == "late_window":
			setup.actor_positions[1] = Vector3(-1.2, 0, 0)
		setup.actor_forwards[1] = Vector2.RIGHT
		setup.ball_position = Vector3(-0.45 if label == "clean" else -0.65, 0.44 if label == "clean" else 0.45, 0) if ball_first else Vector3(8, 0.8, -5)
		if label == "historical":
			setup.actor_forwards[1] = Vector2(0, 1)
			setup.ball_position = Vector3(-1.4, 0.12, 0.55)
		if ball_first:
			tuning.acceleration = 60.0
		if not _start("G20/G21/G28 physical %s" % label, setup, tuning):
			return
		var configured_window: int = tuning.foul_challenge_window_ticks
		tuning.foul_challenge_window_ticks = 1
		tuning.foul_min_closing_speed = 4.0
		tuning.foul_reckless_closing_speed = 20.0
		var historical_tick: int = -1
		if label == "historical":
			await _frames(5)
			var pass_command: Command = _command(1)
			pass_command.action = Command.Action.PASS
			pass_command.aim = Vector2(0, 1)
			_check("old-touch fixture releases actual possession with a legal pass", _state().ball_owner_id == 1 and _submit(pass_command) == OK)
			await _frames(22)
			var pass_event: Event = _last(Event.Kind.PASS)
			historical_tick = pass_event.tick if pass_event != null else -1
			_check("pass touch is real history rather than a fixture counter", pass_event != null and pass_event.contact_id >= 0 and
				pass_event.actor_id == 1 and _state().last_touch_tick == historical_tick and _state().ball_owner_id != 1)
		var accepted: bool = true
		var tackle_sent: bool = false
		var contacted: bool = false
		for frame: int in range(100):
			if fast:
				var victim: Command = _command(0)
				victim.move = Vector2.LEFT
				victim.aim = Vector2.LEFT
				victim.sprint = true
				accepted = (_submit(victim) == OK) and accepted
			var command: Command = _command(1)
			command.move = Vector2.RIGHT * (0.1 if label == "gentle" else 1.0)
			if label == "expired" and frame <= configured_window:
				command.move = Vector2.ZERO
			command.aim = Vector2.RIGHT
			command.sprint = fast
			command.close_control = not fast
			var challenge_now: bool = (frame == (4 if fast else 0)) if ball_first else _flat_distance(_state().actor(1).position, _state().actor(0).position) < 1.0
			if label in ["gentle", "expired", "late_window"]:
				challenge_now = frame == 0
			if label != "ordinary" and not tackle_sent and challenge_now:
				command.action = Command.Action.TACKLE
				tackle_sent = true
			accepted = (_submit(command) == OK) and accepted
			await _frames(1)
			contacted = _actor_contact(1, 0) or _actor_contact(0, 1)
			if contacted or _state().phase != Snapshot.Phase.PLAYING:
				break
		_check("collision scenario uses accepted production commands", accepted)
		_check("ACTOR_ACTOR evidence comes from a real kinematic collision", contacted)
		var foul: Event = _last(Event.Kind.FOUL)
		if label in ["ordinary", "gentle", "expired", "clean"]:
			_check("inactive, gentle or ball-first moderate body contact is not a foul", foul == null and _state().accumulated_fouls == Vector2i.ZERO)
			if label == "clean":
				_check("clean challenge includes an actual earlier ball strike", _last(Event.Kind.TACKLE) != null and _last(Event.Kind.TACKLE).success and _last(Event.Kind.TACKLE).contact_id >= 0)
			elif label == "expired":
				_check("physical challenge has really aged beyond the configured window", _last(Event.Kind.TACKLE) != null and
					_state().tick - _last(Event.Kind.TACKLE).tick > configured_window)
		else:
			_check("real contact carries one adjudicated offender/victim episode", foul != null and foul.actor_id == 1 and foul.target_actor_id == 0 and
				foul.contact_id >= 0 and foul.contact_point.is_finite() and _count(Event.Kind.FOUL) == 1)
			_check("physical verdict distinguishes late and reckless", foul != null and
				foul.foul_verdict == (Types.FoulVerdict.RECKLESS if fast else Types.FoulVerdict.LATE))
			if fast:
				_check("ball first never grants immunity from reckless closing contact", _last(Event.Kind.TACKLE) != null and
					_last(Event.Kind.TACKLE).success and _last(Event.Kind.TACKLE).contact_id >= 0)
			if label == "historical":
				_check("a touch before this challenge cannot make the later body-first impact clean", historical_tick >= 0 and
					_last(Event.Kind.TACKLE) != null and _last(Event.Kind.TACKLE).tick > historical_tick and not _last(Event.Kind.TACKLE).success)
			if label == "late_window":
				_check("physical evidence remains eligible after the gesture window but within the agreed challenge window", foul != null and
					_last(Event.Kind.TACKLE) != null and foul.tick - _last(Event.Kind.TACKLE).tick > tuning.tackle_contact_window_ticks and
					foul.tick - _last(Event.Kind.TACKLE).tick <= configured_window)
			_check("penalty has priority and does not count as an accumulated foul", _state().restart.kind ==
				(Types.RestartKind.PENALTY_6M if label == "penalty" else Types.RestartKind.DIRECT_FREE_KICK) and
				_state().accumulated_fouls == (Vector2i.ZERO if label == "penalty" else Vector2i(0, 1)))
			await _frames(5)
			_check("stoppage cannot count the same physical episode again", _count(Event.Kind.FOUL) == 1)


func _seventh_foul(mode: Setup.Mode) -> int:
	if not _start("G22/G28 seeded sixth then real seventh", _seventh_contact_setup(mode)):
		return -1
	await _ready_restart()
	var taker: int = _state().restart.taker_actor_id
	var command: Command = _restart_command()
	_check("sixth preset launches through the same authority", _submit(command) == OK)
	await _frames(1)
	var observation: Dictionary = await _provoke_seventh_foul(taker)
	_scenarios[-1]["physical_challenge"] = observation.duplicate()
	var produced: bool = observation["accepted"] and observation["challenged"] and observation["collision"] and _count(Event.Kind.FOUL) == 1
	_check("seventh fixture produces a new physical challenge, not a counter setter", produced)
	_check("seventh accumulated foul produces another direct-shot restart", _state().accumulated_fouls == Vector2i(0, 7) and
		_state().restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK and _state().restart.requires_direct_shot)
	return int(observation["live_ticks"]) if produced else -1


func _seventh_contact_setup(mode: Setup.Mode) -> Setup:
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.ACCUMULATED_FREE_KICK)
	if mode == Setup.Mode.PREVIEW_5V5:
		# Isolate the commanded 1-versus-taker collision; the unchanged catalogue also covers obstructed lanes.
		setup.actor_positions[9].z = -8.0
	return setup


func _provoke_seventh_foul(taker: int) -> Dictionary:
	var challenged: bool = false
	var accepted: bool = true
	var collision: bool = false
	var began_tick: int = _state().tick
	for frame: int in range(180):
		if _state().phase != Snapshot.Phase.PLAYING:
			break
		var command: Command = _command(1)
		command.move = _aim(_state().actor(1).position, _state().actor(taker).position)
		command.aim = command.move
		command.sprint = true
		if not challenged and _flat_distance(_state().actor(1).position, _state().actor(taker).position) < 1.1:
			command.action = Command.Action.TACKLE
			challenged = true
		accepted = (_submit(command) == OK) and accepted
		await _frames(1)
		collision = collision or _actor_contact(1, taker)
	var foul: Event = _last(Event.Kind.FOUL)
	return {"accepted": accepted, "challenged": challenged, "collision": collision, "started_tick": began_tick,
		"contact_tick": foul.tick if foul != null else -1, "live_ticks": foul.tick - began_tick if foul != null else -1}


func _extensions(mode: Setup.Mode) -> void:
	for exercise: Setup.TrainingExercise in [Setup.TrainingExercise.PENALTY_6M, Setup.TrainingExercise.ACCUMULATED_FREE_KICK]:
		var setup: Setup = _exercise(mode, exercise)
		setup.actor_positions[3] = Vector3(18.5, 0, 1.15)
		var tuning: Tuning = Tuning.new()
		tuning.training_seconds = 0.1
		if not _start("G24/G29 pending kick extension", setup, tuning):
			return
		await _ready_restart()
		var taker: int = _state().restart.taker_actor_id
		var at: Vector3 = _state().actor(taker).position
		var command: Command = _restart_command()
		_check("restricted kick is physically launched before regulation closes", _submit(command) == OK)
		await _frames(12)
		_check("clock reaches zero but only the pending kick remains active", _state().seconds_remaining == 0.0 and
			_state().period_state == Types.PeriodState.EXTENDED_KICK and _state().extended_restart_id == _state().restart.id and
			_state().extended_kick_event_id >= 0 and _state().phase == Snapshot.Phase.PLAYING)
		command = _command(taker)
		command.action = Command.Action.SWITCH_TEAMMATE
		_reject_command("no control switch to prolong the extended attack", command, ERR_UNAVAILABLE, "Action unavailable in the current rule context")
		_check("extended flight can be paused", _simulation.set_paused(true) == OK)
		var frozen: Array = _fingerprint(_state())
		await _frames(10)
		_check("pause freezes the restricted kick and its identifiers", frozen == _fingerprint(_state()))
		_check("extended flight resumes", _simulation.set_paused(false) == OK and _state().ball_velocity.length() > 1.0)
		await _phase(Snapshot.Phase.FINISHED, 220)
		_check("restricted goal finishes exactly once without another kickoff", _count(Event.Kind.GOAL) == 1 and _count(Event.Kind.END) == 1 and
			_state().score == Vector2i(1, 0) and _state().selected_actor_id == taker and _flat_distance(at, _state().actor(taker).position) < 0.001)
		_check("goal net remains physical during restricted follow-through", _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.BALL_CONTACT and event.reason == &"net"))
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.PENALTY_6M)
	var tuning: Tuning = Tuning.new()
	tuning.training_seconds = 0.1
	if not _start("G29 keeper save is not immediate terminal", setup, tuning):
		return
	await _ready_restart()
	var command: Command = _restart_command()
	_check("save fixture launches a real restricted penalty", _submit(command) == OK)
	var keeper_movement_accepted: bool = true
	for frame: int in range(140):
		var defense: Command = _command(3)
		defense.move = Vector2.LEFT
		defense.aim = Vector2.LEFT
		keeper_movement_accepted = (_submit(defense) == OK) and keeper_movement_accepted
		await _frames(1)
		if _count(Event.Kind.SAVE) > 0 or _state().phase == Snapshot.Phase.FINISHED:
			break
	_check("keeper actively intercepts inside the area rather than assuming a line collection stops a shot",
		keeper_movement_accepted and _state().actor(3).position.x < 19.0)
	_check("keeper touch alone does not end the pending shot", _count(Event.Kind.SAVE) == 1 and _count(Event.Kind.END) == 0 and _state().phase == Snapshot.Phase.PLAYING)
	await _phase(Snapshot.Phase.FINISHED, 240)
	_check("physically stopped saved ball ends without granting another attack", _count(Event.Kind.GOAL) == 0 and _count(Event.Kind.END) == 1 and
		_last(Event.Kind.END).reason == &"extended_kick_ball_stopped")
	if not _start("G29 line collection cannot erase a physical goal", setup, tuning):
		return
	await _ready_restart()
	_check("line-collection fixture retains the same real penalty", _submit(_restart_command()) == OK)
	await _phase(Snapshot.Phase.FINISHED, 240)
	_check("a keeper touch may still be followed by a legitimate complete-ball goal", _count(Event.Kind.SAVE) == 1 and
		_count(Event.Kind.GOAL) == 1 and _count(Event.Kind.END) == 1 and _state().score == Vector2i(1, 0) and
		_index(Event.Kind.SAVE) < _index(Event.Kind.GOAL) and _index(Event.Kind.GOAL) < _index(Event.Kind.END))
	var regulation_tuning: Tuning = Tuning.new()
	regulation_tuning.training_seconds = 6.0
	if not _start("G29 completed regulation penalty cannot grant a later extension", setup, regulation_tuning):
		return
	await _ready_restart()
	command = _restart_command()
	_check("regulation penalty is launched through the same production action", _submit(command) == OK)
	var stopped_ticks: int = 0
	for frame: int in range(240):
		await _frames(1)
		var stopped: bool = _state().ball_velocity.length() <= regulation_tuning.extended_ball_stop_speed and \
			_state().ball_angular_velocity.length() * Tuning.BALL_RADIUS <= regulation_tuning.extended_ball_stop_speed
		stopped_ticks = stopped_ticks + 1 if stopped and _count(Event.Kind.SAVE) > 0 else 0
		if stopped_ticks >= regulation_tuning.extended_ball_stop_ticks + 2:
			break
	_check("saved kick physically settles with regulation time still remaining", _count(Event.Kind.SAVE) == 1 and
		stopped_ticks >= regulation_tuning.extended_ball_stop_ticks + 2 and _state().seconds_remaining > 0.0 and
		_state().period_state == Types.PeriodState.REGULATION)
	await _phase(Snapshot.Phase.FINISHED, 400)
	_check("completed kick does not resurrect as an extended attack at the later deadline", _count(Event.Kind.END) == 1 and
		_last(Event.Kind.END).reason == &"training_time_elapsed" and _state().period_state == Types.PeriodState.REGULATION and
		_state().extended_restart_id == -1 and _state().extended_kick_event_id == -1)
	tuning.keeper_control_acceleration = 30.0
	if not _start("G29 original kicker cannot attack a rebounding extended shot", setup, tuning):
		return
	await _ready_restart()
	command = _restart_command()
	command.shot_charge = 1.0
	_check("fast penalty is actually launched for rebound outcome", _submit(command) == OK)
	await _phase(Snapshot.Phase.FINISHED, 300)
	_check("new non-defending-keeper touch ends extension immediately", _count(Event.Kind.SAVE) == 1 and _count(Event.Kind.END) == 1 and
		_last(Event.Kind.END).reason == &"extended_kick_other_player_touch" and _state().last_touch_actor_id == command.actor_id)
	setup = _quiet(mode)
	setup.actor_positions[0] = Vector3(18, 0, 0)
	setup.actor_positions[1] = Vector3(17.26, 0, 0)
	setup.actor_forwards[1] = Vector2.RIGHT
	setup.ball_position = Vector3(8, 0.8, -5)
	tuning = Tuning.new()
	tuning.training_seconds = 0.101
	if not _start("G29 penalty awarded on the final physical tick", setup, tuning):
		return
	var accepted: bool = true
	for frame: int in range(12):
		if _state().phase != Snapshot.Phase.PLAYING:
			break
		command = _command(1)
		command.move = Vector2.RIGHT
		command.aim = Vector2.RIGHT
		command.close_control = true
		command.action = Command.Action.TACKLE if frame == 0 else Command.Action.NONE
		accepted = (_submit(command) == OK) and accepted
		await _frames(1)
	_check("actual last-tick body foul creates the pending penalty extension", accepted and _count(Event.Kind.FOUL) == 1 and
		_state().restart.kind == Types.RestartKind.PENALTY_6M and _state().seconds_remaining == 0.0 and
		_state().period_state == Types.PeriodState.EXTENDED_KICK and _state().extended_kick_event_id == -1)
	await _ready_restart()
	await _frames(250)
	_check("pending extended penalty keeps its preparation and has no four-second expiry", _state().phase == Snapshot.Phase.RESTART_PAUSE and
		_state().restart.stage == Types.RestartStage.READY and _state().restart.deadline_tick == -1 and _state().seconds_remaining == 0.0)


func _extended_expiry(mode: Setup.Mode, measured_contact_ticks: int) -> void:
	_scope = "G29 extended sixth expiry reference; mode=%d" % mode
	_check("expiry fixture has a measured production collision later than the minimum timer", measured_contact_ticks > 6)
	if measured_contact_ticks <= 6:
		return
	var tuning: Tuning = Tuning.new()
	tuning.training_seconds = (float(measured_contact_ticks) - 0.25) / Tuning.PHYSICS_HZ
	if not _start("G29 pending sixth expiry ends without a replacement restart",
		_seventh_contact_setup(mode), tuning):
		return
	await _ready_restart()
	var taker: int = _state().restart.taker_actor_id
	_check("expiry fixture replays the actual seeded launch", _submit(_restart_command()) == OK)
	await _frames(1)
	var observation: Dictionary = await _provoke_seventh_foul(taker)
	_scenarios[-1]["physical_challenge"] = observation.duplicate()
	_scenarios[-1]["reference_live_ticks"] = measured_contact_ticks
	_check("the repeated body foul lands on the last regulation tick", observation["accepted"] and observation["challenged"] and
		observation["collision"] and int(observation["live_ticks"]) == measured_contact_ticks and _count(Event.Kind.FOUL) == 1 and
		_state().seconds_remaining == 0.0 and _state().period_state == Types.PeriodState.EXTENDED_KICK and
		_state().restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK and _state().extended_kick_event_id == -1)
	await _ready_restart()
	var pending: Snapshot = _state()
	var awards: int = 0
	for event: Event in _events:
		if event.kind == Event.Kind.RESTART_CHANGED and event.reason == &"awarded":
			awards += 1
	_check("extended pending sixth keeps the exact four-second deadline", pending.restart.deadline_tick == pending.restart.ready_tick + 240 and
		pending.extended_restart_id == pending.restart.id)
	await _phase(Snapshot.Phase.FINISHED, 245)
	var final_awards: int = 0
	for event: Event in _events:
		if event.kind == Event.Kind.RESTART_CHANGED and event.reason == &"awarded":
			final_awards += 1
	_check("NONE extended_kick_expired finalizes once without an indirect replacement", _count(Event.Kind.END) == 1 and
		_last(Event.Kind.END).reason == &"extended_kick_expired" and final_awards == awards and
		_state().restart.id == pending.restart.id and _state().selected_actor_id == pending.selected_actor_id and
		_state().accumulated_fouls == Vector2i(0, 7) and _state().extended_kick_event_id == -1)
	var final_state: Array = _fingerprint(_state())
	await _frames(12)
	_check("expiry terminal is idempotent and freezes its real ball", _count(Event.Kind.END) == 1 and final_state == _fingerprint(_state()))


func _world_isolation() -> void:
	var setup: Setup = _exercise(Setup.Mode.PREVIEW_5V5, Setup.TrainingExercise.ACCUMULATED_FREE_KICK)
	if not _start("G23 private rule state and physics spaces", setup):
		return
	var second: Simulation = Simulation.new()
	root.add_child(second)
	_check("second authority has an independent setup", second.start() == OK)
	await _frames(3)
	var ball_a: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	var ball_b: RigidBody3D = second.get_node("Ball") as RigidBody3D
	_check("two World3D physics spaces never share bodies or rule state", PhysicsServer3D.body_get_space(ball_a.get_rid()) !=
		PhysicsServer3D.body_get_space(ball_b.get_rid()) and _state().accumulated_fouls == Vector2i(0, 6) and
		second.get_snapshot().accumulated_fouls == Vector2i.ZERO and second.get_snapshot().restart.kind == Types.RestartKind.NONE)
	second.queue_free()
	await process_frame


func _exercise(mode: Setup.Mode, exercise: Setup.TrainingExercise) -> Setup:
	var setup: Setup = Setup.for_exercise(mode, exercise)
	setup.ai_actor_ids = []
	return setup


func _quiet(mode: Setup.Mode) -> Setup:
	var setup: Setup = _exercise(mode, Setup.TrainingExercise.FREE_PLAY)
	var positions: Dictionary[int, Vector3] = {
		0: Vector3(-12, 0, -8), 1: Vector3(12, 0, -8), 2: Vector3(-18.5, 0, 8), 3: Vector3(18.5, 0, 8),
		4: Vector3(-6, 0, -8), 5: Vector3(6, 0, -8), 6: Vector3(-6, 0, 8), 7: Vector3(6, 0, 8), 8: Vector3(-12, 0, 8), 9: Vector3(12, 0, 8),
	}
	for id: int in setup.actor_positions:
		setup.actor_positions[id] = positions[id]
	setup.ball_position = Vector3(0, 0.12, 0)
	return setup


func _start(label: String, setup: Setup, tuning: Tuning = null) -> bool:
	_scope = "%s; mode=%d; exercise=%d" % [label, setup.mode, setup.training_exercise]
	_check("prior negative expectations drained", _expected.is_empty())
	_events.clear()
	_simulation.tuning = Tuning.new() if tuning == null else tuning
	var result: Error = _simulation.start(setup)
	_scenarios.append({"name": _scope, "mode": setup.mode, "exercise": setup.training_exercise,
		"ball": str(setup.ball_position), "velocity": str(setup.ball_velocity), "start_error": result})
	_check("production start", result == OK)
	return result == OK


func _ready_restart() -> void:
	for frame: int in range(100):
		if _state().restart.stage == Types.RestartStage.READY or _state().phase == Snapshot.Phase.FINISHED:
			break
		await _frames(1)
	_check("bounded wait reaches READY kind=%d id=%d" % [_state().restart.kind, _state().restart.id],
		_state().phase == Snapshot.Phase.RESTART_PAUSE and _state().restart.stage == Types.RestartStage.READY)


func _new_restart(previous_id: int, maximum: int) -> void:
	for frame: int in maximum:
		if _state().phase == Snapshot.Phase.RESTART_PAUSE and _state().restart.id > previous_id:
			return
		await _frames(1)
	_check("bounded wait reaches a new adjudicated restart", false)


func _phase(phase: Snapshot.Phase, maximum: int) -> void:
	for frame: int in maximum:
		if _state().phase == phase:
			return
		await _frames(1)
	_check("bounded phase wait %d" % phase, false)


func _restart_command() -> Command:
	var state: Snapshot = _state()
	var command: Command = _command(state.restart.taker_actor_id)
	command.action = Command.Action.KEEPER_THROW if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE else Command.Action.PASS
	if state.restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		command.action = Command.Action.SHOOT
		command.aim = Vector2(state.actor(command.actor_id).attack_direction.x, 0.0)
	return command


func _command(actor_id: int) -> Command:
	return Command.new(actor_id, _state().actor(actor_id).last_command_sequence + 1)


func _submit(command: Command) -> Error:
	return _simulation.submit_human_command(command) if command.actor_id == _state().selected_actor_id else _simulation.submit_command(command)


func _reject_command(label: String, command: Command, code: Error, message: String) -> void:
	_allow_refusal(label, command.actor_id, code, message)
	var actual: Error = _submit(command)
	_check("expected refusal " + label, actual == code and _expected.is_empty())


func _allow_refusal(label: String, actor_id: int, code: Error, message: String) -> void:
	_expected.append({"name": _scope + "/" + label, "actor_id": actor_id, "code": code, "message": message})


func _on_refusal(actor_id: int, code: Error, message: String) -> void:
	var actual: Dictionary = {"actor_id": actor_id, "code": code, "message": message, "scope": _scope}
	if _expected.is_empty():
		actual["state"] = _diagnostic_state()
		_unexpected.append(actual)
		return
	var expected: Dictionary = _expected.pop_front()
	actual["expected"] = expected
	actual["matched"] = actor_id == int(expected["actor_id"]) and code == int(expected["code"]) and message == String(expected["message"])
	_negatives.append(actual)
	if not bool(actual["matched"]):
		_unexpected.append(actual)


func _frames(count: int) -> void:
	_requested_steps += count
	_pending_steps = count
	for frame: int in count:
		await physics_frame
		await process_frame
		_pending_steps -= 1
		_last_progress_ms = Time.get_ticks_msec()
		_last_progress_frame = Engine.get_physics_frames()


func _state() -> Snapshot:
	return _simulation.get_snapshot()


func _body(id: int) -> CharacterBody3D:
	return _simulation.get_node("Actor%d" % id) as CharacterBody3D


func _actor_contact(a: int, b: int) -> bool:
	for index: int in _body(a).get_slide_collision_count():
		if _body(a).get_slide_collision(index).get_collider() == _body(b):
			return true
	return false


func _ball_overlaps_actor(actor_id: int) -> bool:
	var ball: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	var collider: CollisionShape3D = ball.get_child(0) as CollisionShape3D
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	query.collision_mask = Tuning.ACTOR_LAYER
	query.exclude = [ball.get_rid()]
	var space: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(PhysicsServer3D.body_get_space(ball.get_rid()))
	for hit: Dictionary in space.intersect_shape(query, 16):
		if hit["rid"] == _body(actor_id).get_rid():
			return true
	return false


func _last(kind: Event.Kind, reason: StringName = &"") -> Event:
	for index: int in range(_events.size() - 1, -1, -1):
		if _events[index].kind == kind and (reason == &"" or _events[index].reason == reason):
			return _events[index]
	return null


func _index(kind: Event.Kind, reason: StringName = &"") -> int:
	for index: int in range(_events.size() - 1, -1, -1):
		if _events[index].kind == kind and (reason == &"" or _events[index].reason == reason):
			return index
	return -1


func _count(kind: Event.Kind) -> int:
	var count: int = 0
	for event: Event in _events:
		if event.kind == kind:
			count += 1
	return count


func _check_selected() -> void:
	var state: Snapshot = _state()
	var humans: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.human_controlled:
			humans.append(actor.actor_id)
	var effective: Array[int] = state.ai_intent_actor_ids.duplicate()
	effective.erase(state.selected_actor_id)
	_check("exactly the selected HOME is human and excluded from effective AI", humans == [state.selected_actor_id] and
		state.actor(state.selected_actor_id).team_id == 0 and state.ai_actor_ids == effective)


func _fingerprint(state: Snapshot) -> Array:
	var restart: Types.RestartState = state.restart
	var result: Array = [state.mode, state.training_exercise, state.tick, state.phase, state.resume_phase, state.score,
		state.seconds_remaining, state.phase_seconds_remaining, state.selected_actor_id, state.ai_intent_actor_ids,
		state.ai_actor_ids, state.ball_position, state.ball_velocity, state.ball_rotation, state.ball_angular_velocity,
		state.ball_owner_id, state.last_touch_actor_id, state.last_touch_tick, state.last_pass_actor_id,
		state.last_pass_target_actor_id, state.last_pass_tick, state.accumulated_fouls, state.period_state,
		state.extended_restart_id, state.extended_kick_event_id, state.human_control_context,
		state.human_allowed_actions, state.selected_can_move, restart.id, restart.kind, restart.stage, restart.launch_contact_id,
		restart.awarded_team_id, restart.taker_actor_id, restart.spot, restart.offence_spot, restart.border,
		restart.spot_choice, restart.has_spot_choice, restart.stage_started_tick, restart.placement_end_tick,
		restart.ready_tick, restart.deadline_tick, restart.minimum_opponent_distance,
		restart.direct_opponent_goal_allowed, restart.requires_direct_shot, restart.other_actor_touched]
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.team_id, actor.role, actor.human_controlled, actor.attack_direction,
			actor.position, actor.spawn_position, actor.velocity, actor.forward, actor.facing_yaw, actor.close_control,
			actor.action_cooldown, actor.last_command_sequence, actor.last_command_tick, actor.ball_contact_reachable,
			actor.ball_in_hands, actor.gesture_kind, actor.gesture_started_tick, actor.gesture_duration_ticks,
			actor.gesture_direction, actor.gesture_contact_position])
	return result


func _aim(from: Vector3, to: Vector3) -> Vector2:
	return Vector2(to.x - from.x, to.z - from.z).normalized()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(label: String, passed: bool) -> void:
	var name: String = _scope + "/" + label
	if name in _names:
		_invalid_names = true
		push_error("Duplicate semantic gameplay check: " + name)
		quit(2)
		return
	_names[name] = true
	_checks.append({"name": name, "passed": passed})
	print(("PASS " if passed else "FAIL ") + name)
	if not passed and is_instance_valid(_simulation):
		var diagnostic: Dictionary = {"name": name, "state": _diagnostic_state()}
		_diagnostics.append(diagnostic)
		print("FUTSAL_GAMEPLAY_DIAGNOSTIC ", JSON.stringify(diagnostic))


func _diagnostic_state() -> Dictionary:
	var state: Snapshot = _state()
	var actors: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append({"id": actor.actor_id, "position": [actor.position.x, actor.position.y, actor.position.z],
			"velocity": [actor.velocity.x, actor.velocity.y, actor.velocity.z], "forward": [actor.forward.x, actor.forward.z],
			"reachable": actor.ball_contact_reachable, "hands": actor.ball_in_hands, "sequence": actor.last_command_sequence})
	var recent: Array[Dictionary] = []
	for event: Event in _events.slice(maxi(0, _events.size() - 24)):
		recent.append({"kind": event.kind, "actor": event.actor_id, "target": event.target_actor_id,
			"tick": event.tick, "reason": String(event.reason), "contact_id": event.contact_id})
	return {"tick": state.tick, "phase": state.phase, "period": state.period_state, "seconds": state.seconds_remaining,
		"score": [state.score.x, state.score.y], "owner": state.ball_owner_id, "selected": state.selected_actor_id,
		"ball": [state.ball_position.x, state.ball_position.y, state.ball_position.z],
		"linear": [state.ball_velocity.x, state.ball_velocity.y, state.ball_velocity.z],
		"angular": [state.ball_angular_velocity.x, state.ball_angular_velocity.y, state.ball_angular_velocity.z],
		"restart": {"id": state.restart.id, "kind": state.restart.kind, "stage": state.restart.stage,
			"taker": state.restart.taker_actor_id, "deadline": state.restart.deadline_tick,
			"spot": [state.restart.spot.x, state.restart.spot.y, state.restart.spot.z]},
		"actors": actors, "recent_events": recent}


func _report(forced_exit: int = -1) -> void:
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	var ok: bool = _completed and not _invalid_names and failures.is_empty() and _unexpected.is_empty() and _expected.is_empty()
	print("FUTSAL_GAMEPLAY_RULES_TESTS ", JSON.stringify({"ok": ok, "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "checks": _checks, "failures": failures, "scenarios": _scenarios,
		"expected_refusals": _negatives.size(), "negative_cases": _negatives, "unexpected_refusals": _unexpected,
		"pending_refusals": _expected, "duplicate_names": _invalid_names, "headless": DisplayServer.get_name() == "headless",
		"complete": _completed, "selected_groups": _selected_groups, "diagnostics": _diagnostics,
		"requested_physics_steps": _requested_steps, "physics_steps": Engine.get_physics_frames() - _physics_started_frame,
		"pending_step_budget": _pending_steps, "watchdog_failure": _watchdog_failure,
		"watchdog_probe": _watchdog_probe,
		"engine": Engine.get_version_info()["string"], "physics": "Jolt Physics", "physics_hz": Engine.physics_ticks_per_second,
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0}))
	quit(forced_exit if forced_exit >= 0 else (0 if ok else 1))


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_GAMEPLAY_RULES_TESTS_INCOMPLETE")
		quit(2)
