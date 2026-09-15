extends SceneTree

const Simulation = preload("res://match/simulation/match_simulation.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const CALLBACK_BUSY_MESSAGES: Dictionary[String, String] = {
	"start": "Defer reset/start/pause until after simulation event delivery",
	"reset": "Defer reset/start/pause until after simulation event delivery",
	"set_paused": "Defer reset/start/pause until after simulation event delivery",
	"set_ai_actor_ids": "Defer AI changes until after the simulation tick/event delivery",
	"submit_command": "Submit commands between simulation ticks/events",
	"submit_human_command": "Submit human commands between simulation ticks/events",
}

var _simulation: Simulation
var _checks: Array[Dictionary] = []
var _check_context: String = "initialization"
var _events: Array[Event] = []
var _refusals: Array[Dictionary] = []
var _refusal_notifications: Array[Dictionary] = []
var _refusal_evidence: Array[Dictionary] = []
var _claimed_refusal_notifications: Dictionary[int, String] = {}
var _active_refusal_context: String = ""
var _expected_refusals: int = 0
var _busy_probe: bool = false
var _busy_kind: Event.Kind = Event.Kind.RESTART
var _busy_results: Array[int] = []
var _capture_focus_state: bool = false
var _focus_observations: Array[Dictionary] = []
var _focus_mutation_probe: bool = false
var _focus_mutation_results: Array[int] = []
var _nested_refusal_results: Array[int] = []
var _focus_probe_unchanged: bool = false
var _started_ms: int = 0
var _completed: bool = false
var _keeper_distribution_evidence: Array[Dictionary] = []


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_ms > 120000:
		push_error("Preview test watchdog: exceeded 120 seconds of wall time")
		quit(2)
	return false


func _run() -> void:
	_simulation = Simulation.new()
	_simulation.event_raised.connect(_on_event)
	_simulation.command_rejected.connect(_on_refusal)
	_simulation.command_rejected.connect(_on_focus_probe_refusal)
	var initial_ai_ids: Array[int] = [1]
	_reject("AI before initialization", _observe_api(_simulation.set_ai_actor_ids, [initial_ai_ids]), ERR_UNCONFIGURED)
	root.add_child(_simulation)
	await process_frame
	_check("preview test uses headless Jolt at 60 Hz", DisplayServer.get_name() == "headless" and
		ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics" and Engine.physics_ticks_per_second == 60)
	await _run_test(_test_modes_and_copies)
	await _run_test(_test_new_colliders)
	await _run_test(_test_invalid_setups)
	await _run_test(_test_toggle_groups)
	await _run_test(_test_toggle_actions)
	await _run_test(_test_toggle_phases_and_callbacks)
	await _run_test(_test_pass_selection)
	await _run_test(_test_new_receiver_goal_and_restarts)
	await _run_test(_test_preview_ai)
	await _run_test(_test_focus_selection)
	await _run_test(_test_focus_pass_and_refusals)
	await _run_test(_test_focus_action_order)
	await _run_test(_test_focus_intent)
	await _run_test(_test_focus_phases)
	_simulation.queue_free()
	await process_frame
	_check("refusal ledger links every observed signal and API return exactly once", _refusal_accounting_is_complete())
	_completed = true
	_finish()


func _run_test(test: Callable) -> void:
	var previous_context: String = _check_context
	_check_context = String(test.get_method()).trim_prefix("_test_").replace("_", " ")
	await test.call()
	_check_context = previous_context


func _test_modes_and_copies() -> void:
	_check("enum values and micro constant remain compatible", Setup.Mode.MICRO_1V1 == 0 and Setup.Mode.PREVIEW_5V5 == 1 and
		Simulation.ACTOR_IDS == [0, 1, 2, 3])
	_check("initialized default is micro with its original AI", _state().mode == Setup.Mode.MICRO_1V1 and
		_state().actors.size() == 4 and _state().ai_actor_ids == [1, 2, 3])
	var preset: Setup = Setup.preview_5v5()
	var copied: Setup = preset.copy()
	copied.actor_positions[4] = Vector3(-9.0, 0.0, -6.0)
	copied.actor_forwards[4] = Vector2.LEFT
	copied.ai_actor_ids.clear()
	copied.ball_position = Vector3(0.0, 0.5, 0.0)
	copied.ball_velocity = Vector3(1.0, 2.0, 3.0)
	copied.ball_angular_velocity = Vector3(4.0, 5.0, 6.0)
	var second_copy: Setup = copied.copy()
	_check("copy preserves mode and every setup field", second_copy.mode == Setup.Mode.PREVIEW_5V5 and
		second_copy.actor_positions == copied.actor_positions and second_copy.actor_forwards == copied.actor_forwards and
		second_copy.ai_actor_ids == copied.ai_actor_ids and second_copy.ball_position == copied.ball_position and
		second_copy.ball_velocity == copied.ball_velocity and second_copy.ball_angular_velocity == copied.ball_angular_velocity)
	_check("setup copies are independent of the canonical preset", preset.actor_positions[4] == Vector3(-8.0, 0.0, -6.0) and
		preset.actor_forwards[4] == Vector2.RIGHT and preset.ai_actor_ids == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] and
		preset.ball_position == Vector3(-1.45, 0.12, 0.0) and preset.ball_velocity == Vector3.ZERO)
	if not _start("canonical preview", preset):
		return
	var initial: Snapshot = _state()
	_check_composition(initial, 10, Setup.Mode.PREVIEW_5V5)
	var bodies: Dictionary = {}
	var shapes: Dictionary = {}
	for actor: Snapshot.ActorSnapshot in initial.actors:
		var body: CharacterBody3D = _body(actor.actor_id)
		var collider: CollisionShape3D = body.get_child(0) as CollisionShape3D
		var shape: CapsuleShape3D = collider.shape as CapsuleShape3D
		bodies[body.get_rid().get_id()] = true
		shapes[shape.get_rid().get_id()] = true
		_check("preview actor %d has its own active physical capsule" % actor.actor_id, shape != null and
			PhysicsServer3D.body_get_shape_count(body.get_rid()) == 1 and body.collision_layer == Tuning.ACTOR_LAYER and
			PhysicsServer3D.body_get_space(body.get_rid()) == _space() and is_equal_approx(shape.radius, Tuning.ACTOR_RADIUS) and
			is_equal_approx(shape.height, Tuning.ACTOR_HEIGHT))
		_check("preview actor %d starts at its exact preset pose" % actor.actor_id, actor.position == preset.actor_positions[actor.actor_id] and
			actor.forward.is_equal_approx(Vector3(1.0 if actor.team_id == 0 else -1.0, 0.0, 0.0)))
	_check("ten bodies and ten shapes are genuinely distinct", bodies.size() == 10 and shapes.size() == 10)
	var before: Array = _fingerprint(_state())
	preset.mode = Setup.Mode.MICRO_1V1
	preset.actor_positions.clear()
	preset.actor_forwards.clear()
	preset.ai_actor_ids.clear()
	preset.ball_velocity = Vector3(32.0, 0.0, 0.0)
	_check("mutating submitted setup cannot change authority", before == _fingerprint(_state()))
	var detached: Snapshot = _state()
	detached.mode = Setup.Mode.MICRO_1V1
	detached.selected_actor_id = 9
	detached.ai_intent_actor_ids.clear()
	detached.ai_actor_ids.clear()
	detached.actor(4).position = Vector3(999.0, 999.0, 999.0)
	detached.actor(4).role = Snapshot.Role.KEEPER
	detached.actors.clear()
	_check("mode, AI list and actors are detached snapshots", before == _fingerprint(_state()))
	var removed_instances: Dictionary = {}
	for id: int in [4, 5, 6, 7, 8, 9]:
		removed_instances[id] = _body(id).get_instance_id()
	_check("reset null deliberately selects micro", _simulation.reset() == OK)
	_check_composition(_state(), 4, Setup.Mode.MICRO_1V1)
	await _frames(2)
	var canonical: Setup = Setup.preview_5v5()
	var no_ghosts: bool = true
	for id: int in [4, 5, 6, 7, 8, 9]:
		no_ghosts = no_ghosts and not is_instance_id_valid(int(removed_instances[id])) and _simulation.get_node_or_null("Actor%d" % id) == null
		var at: Vector3 = canonical.actor_positions[id] + Vector3.UP
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(at - Vector3.RIGHT, at + Vector3.RIGHT, Tuning.ACTOR_LAYER)
		no_ghosts = no_ghosts and PhysicsServer3D.space_get_direct_state(_space()).intersect_ray(ray).is_empty()
	_check("switch to micro destroys removed nodes and their physics collisions", no_ghosts)
	_reject("removed actor cannot receive commands", _observe_api(_simulation.submit_command, [Command.new(8, 0)]), ERR_DOES_NOT_EXIST, 8)
	var removed_ai_ids: Array[int] = [8]
	_reject("removed actor cannot generate AI", _observe_api(_simulation.set_ai_actor_ids, [removed_ai_ids]), ERR_INVALID_PARAMETER)
	for cycle: int in range(3):
		if not _start("recurring preview %d" % cycle, Setup.preview_5v5()):
			return
		await _frames(3)
		_check_composition(_state(), 10, Setup.Mode.PREVIEW_5V5)
		_check("recurring start null restores micro defaults %d" % cycle, _simulation.start() == OK and
			_state().mode == Setup.Mode.MICRO_1V1 and _state().ai_actor_ids == [1, 2, 3] and _state().actors.size() == 4)
	_check("explicit ready preview is also supported", _simulation.reset(Setup.preview_5v5()) == OK and
		_state().mode == Setup.Mode.PREVIEW_5V5 and _state().phase == Snapshot.Phase.READY and _state().actors.size() == 10)
	var ready: Array = _fingerprint(_state())
	await _frames(5)
	_check("ready preview stays physically frozen", ready == _fingerprint(_state()))


func _test_new_colliders() -> void:
	for id: int in [4, 5, 6, 7, 8, 9]:
		var setup: Setup = _isolated_preview()
		setup.actor_positions[id] = Vector3.ZERO
		setup.ball_position = Vector3(-2.0, 0.8, 0.0)
		setup.ball_velocity = Vector3(12.0, 0.0, 0.0)
		if not _start("physical contact with new actor %d" % id, setup):
			return
		var physical_start: Transform3D = PhysicsServer3D.body_get_state(_body(id).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		await _frames(14)
		_check("reset actor %d is a teleport, not a sweep or residual motion" % id, physical_start.origin == Vector3.ZERO and
			_flat_distance(_state().actor(id).position, Vector3.ZERO) < 0.005 and _flat_speed(_state().actor(id).velocity) < 0.005)
		var rebounded: bool = _state().ball_velocity.x < -0.5 and _state().ball_position.x < 0.0
		var contacted: bool = _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.BALL_CONTACT and event.actor_id == id and event.reason == &"athlete")
		_check("new actor %d physically rebounds the airborne ball with AI off" % id, rebounded and contacted)
		if not rebounded or not contacted:
			var contacts: Array[Dictionary] = []
			for event: Event in _events:
				if event.kind == Event.Kind.BALL_CONTACT:
					contacts.append({"id": event.actor_id, "position": str(event.position), "velocity": str(event.velocity)})
			print("PREVIEW_COLLIDER_DIAGNOSTIC ", JSON.stringify({"id": id, "contacts": contacts,
				"ball": str(_state().ball_position), "velocity": str(_state().ball_velocity),
				"actor": str(_state().actor(id).position), "owner": _state().ball_owner_id}))
		_check("new actor %d contact does not invent a goal or keeper save" % id,
			_count(Event.Kind.GOAL) == 0 and _count(Event.Kind.SAVE) == 0 and _state().actors.size() == 10)


func _test_invalid_setups() -> void:
	if not _start("atomic preview validation", _isolated_preview()):
		return
	await _frames(3)
	var before: Array = _fingerprint(_state())
	var cases: Array[Dictionary] = []
	var bad: Setup = Setup.preview_5v5()
	bad.set("mode", 99)
	cases.append({"name": "unknown mode", "setup": bad})
	bad = Setup.preview_5v5()
	bad.mode = Setup.Mode.MICRO_1V1
	cases.append({"name": "ten actors do not infer preview", "setup": bad})
	bad = Setup.new()
	bad.mode = Setup.Mode.PREVIEW_5V5
	cases.append({"name": "preview cannot omit six bodies", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_positions.erase(8)
	bad.actor_positions[40] = Vector3(-13.0, 0.0, 0.0)
	cases.append({"name": "wrong position key with correct count", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_forwards.erase(9)
	bad.actor_forwards[40] = Vector2.LEFT
	cases.append({"name": "wrong facing key with correct count", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_positions[4] = Vector3(NAN, 0.0, 0.0)
	cases.append({"name": "nonfinite added actor", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_positions[6] = Vector3(20.0, 0.0, 0.0)
	cases.append({"name": "added actor beyond court", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_positions[8] = bad.actor_positions[0]
	cases.append({"name": "added actor overlaps human", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_forwards[7] = Vector2.ZERO
	cases.append({"name": "added actor has zero facing", "setup": bad})
	bad = Setup.preview_5v5()
	bad.actor_forwards[9] = Vector2(INF, 0.0)
	cases.append({"name": "added actor has nonfinite facing", "setup": bad})
	bad = Setup.preview_5v5()
	bad.ai_actor_ids = [0, 40]
	cases.append({"name": "setup rejects absent AI intent", "setup": bad})
	bad = Setup.preview_5v5()
	bad.ai_actor_ids = [4, 4]
	cases.append({"name": "setup duplicate new AI", "setup": bad})
	bad = Setup.preview_5v5()
	bad.ai_actor_ids = [10]
	cases.append({"name": "setup unknown new AI", "setup": bad})
	bad = Setup.preview_5v5()
	bad.ball_velocity = Vector3(33.0, 0.0, 0.0)
	cases.append({"name": "preview keeps ball speed bounds", "setup": bad})
	for item: Dictionary in cases:
		_reject(String(item["name"]), _observe_api(_simulation.start, [item["setup"]]), ERR_INVALID_PARAMETER)
		_check(String(item["name"]) + " is atomic", before == _fingerprint(_state()) and _physical_actor_count() == 10)
	for values: Array in [[40], [1, 1], [-1], [10], [2, 0, 60], [2, 11]]:
		var ids: Array[int] = []
		ids.assign(values)
		_reject("invalid live AI " + str(ids), _observe_api(_simulation.set_ai_actor_ids, [ids]), ERR_INVALID_PARAMETER)
		_check("invalid live AI does not mutate any state: " + str(ids), before == _fingerprint(_state()))
	var command: Command = _command(4)
	command.action = Command.Action.PASS
	command.target_actor_id = 5
	_reject("new actor cannot target opposing team", _observe_api(_simulation.submit_command, [command]), ERR_INVALID_PARAMETER, 4)
	command.target_actor_id = 10
	_reject("pass cannot target absent preview actor", _observe_api(_simulation.submit_command, [command]), ERR_INVALID_PARAMETER, 4)
	command.target_actor_id = 4
	_reject("new actor cannot pass to itself", _observe_api(_simulation.submit_command, [command]), ERR_INVALID_PARAMETER, 4)
	_reject("human API still refuses new AI actors", _observe_api(_simulation.submit_human_command, [_command(4)]), ERR_UNAUTHORIZED, 4)
	_check("invalid command validation also leaves preview intact", before == _fingerprint(_state()))


func _test_toggle_groups() -> void:
	var groups: Dictionary[String, Array] = {"enemy including keeper": [1, 3, 5, 7, 9], "home field intent including selected": [0, 4, 6, 8], "home keeper": [2]}
	for label: String in groups:
		if not _start("toggle " + label, Setup.preview_5v5()):
			return
		await _frames(4)
		var ids: Array[int] = _state().ai_intent_actor_ids.duplicate()
		var sequences: Dictionary[int, int] = {}
		var rids: Dictionary[int, RID] = {}
		for id: int in groups[label]:
			ids.erase(id)
			sequences[id] = _state().actor(id).last_command_sequence
			rids[id] = _body(id).get_rid()
		var before: Array = _invariants(_state())
		_check("disable group " + label, _simulation.set_ai_actor_ids(ids) == OK)
		_check("toggle preserves score, clock, ball, poses, velocities and cooldowns", before == _invariants(_state()))
		await _frames(30)
		var stopped: bool = true
		for id: int in groups[label]:
			var actor: Snapshot.ActorSnapshot = _state().actor(id)
			stopped = (stopped and actor.last_command_sequence == sequences[id] and _flat_speed(actor.velocity) < 0.02 and
				_body(id).get_rid() == rids[id] and _body(id).collision_layer == Tuning.ACTOR_LAYER)
		_check("disabled group brakes without deleting bodies: " + label, stopped and _physical_actor_count() == 10)
		_check("re-enable group " + label, _simulation.set_ai_actor_ids([9, 8, 7, 6, 5, 4, 3, 2, 1, 0]) == OK)
		await _frames(2)
		var renewed: bool = true
		for id: int in groups[label]:
			var expected_sequence: bool = _state().actor(id).last_command_sequence == sequences[id] if id == _state().selected_actor_id else _state().actor(id).last_command_sequence > sequences[id]
			renewed = renewed and expected_sequence and _body(id).get_rid() == rids[id]
		_check("re-enabled group uses fresh sequences: " + label, renewed and _refusals.is_empty() and
			_state().ai_actor_ids == [1, 2, 3, 4, 5, 6, 7, 8, 9])
	var setup: Setup = Setup.preview_5v5()
	setup.ball_position = Vector3(0.0, 1.5, 4.0)
	setup.ball_velocity = Vector3(7.0, 2.0, 0.0)
	if not _start("all AI off during flight", setup):
		return
	await _frames(4)
	var before: Array = _invariants(_state())
	var ball_before: Vector3 = _state().ball_position
	_check("all AI can be disabled", _simulation.set_ai_actor_ids([]) == OK and _state().ai_actor_ids.is_empty())
	_check("all-off is not a reset or a freeze", before == _invariants(_state()) and not _ball().freeze)
	await _frames(24)
	_check("ball keeps moving while all AI is off", _state().ball_position.distance_to(ball_before) > 1.0 and _state().ball_velocity.x > 1.0)
	_check("all disabled athletes remain physically present", _physical_actor_count() == 10 and
		_state().actors.all(func(actor: Snapshot.ActorSnapshot) -> bool: return _flat_speed(actor.velocity) < 0.02))
	var ids: Array[int] = [9, 1, 3]
	_check("AI API copies and sorts a partial group", _simulation.set_ai_actor_ids(ids) == OK and _state().ai_actor_ids == [1, 3, 9])
	ids.append(0)
	ids.clear()
	_check("caller cannot mutate effective AI through its array", _state().ai_actor_ids == [1, 3, 9])


func _test_toggle_actions() -> void:
	var setup: Setup = _isolated_preview()
	setup.actor_positions[5] = Vector3(-3.0, 0.0, 0.0)
	setup.actor_forwards[5] = Vector2.RIGHT
	setup.ball_position = Vector3(-2.45, 0.12, 0.0)
	setup.ai_actor_ids = [5]
	if not _start("disable pending AI action", setup):
		return
	await _frames(4)
	_check("new field actor can receive and control the ball", _state().ball_owner_id == 5)
	var command: Command = _command(5)
	command.action = Command.Action.SHOOT
	command.shot_charge = 0.8
	command.aim = Vector2.RIGHT
	_check("real pending shot is accepted for added actor", _simulation.submit_command(command) == OK)
	var accepted_sequence: int = command.sequence
	var before: Array = _invariants(_state())
	_check("disabling generator cancels its held action", _simulation.set_ai_actor_ids([]) == OK and before == _invariants(_state()))
	await _frames(12)
	_check("disabled actor never executes stale shot and brakes normally", _count(Event.Kind.SHOT) == 0 and
		_state().actor(5).last_command_sequence == accepted_sequence and _flat_speed(_state().actor(5).velocity) < 0.02)
	_check("re-enable after a pending action", _simulation.set_ai_actor_ids([5]) == OK)
	await _frames(4)
	_check("resume cannot resurrect the old shot or reset its sequence", _count(Event.Kind.SHOT) == 0 and
		_state().actor(5).last_command_sequence > accepted_sequence)
	if not _start("intact enabled actor keeps its pending action", setup):
		return
	await _frames(4)
	command = _command(5)
	command.action = Command.Action.SHOOT
	command.aim = Vector2.RIGHT
	_check("enabled actor has a real accepted pending shot", _simulation.submit_command(command) == OK)
	before = _fingerprint(_state())
	_check("same nonempty AI set leaves accepted state untouched", _simulation.set_ai_actor_ids([5]) == OK and before == _fingerprint(_state()))
	_check("changing another generator leaves the actor enabled", _simulation.set_ai_actor_ids([6, 5]) == OK and _state().ai_actor_ids == [5, 6])
	await _frames(2)
	_check("unchanged enabled actor executes its accepted shot once", _count(Event.Kind.SHOT, 5) == 1 and _refusals.is_empty())
	setup.ai_actor_ids = []
	if not _start("disabled generators still allow manual drill commands", setup):
		return
	await _frames(4)
	command = _command(5)
	command.action = Command.Action.SHOOT
	command.aim = Vector2.RIGHT
	_check("manual drill action with AI off is valid", _simulation.submit_command(command) == OK)
	before = _fingerprint(_state())
	_check("same AI set is strictly idempotent", _simulation.set_ai_actor_ids([]) == OK and before == _fingerprint(_state()))
	await _frames(2)
	_check("idempotent toggle cannot erase an intact pending action", _count(Event.Kind.SHOT, 5) == 1)
	var cooldown: float = _state().actor(5).action_cooldown
	var sequence: int = _state().actor(5).last_command_sequence
	_check("enabling AI preserves accepted sequence and cooldown", _simulation.set_ai_actor_ids([5]) == OK and
		_state().actor(5).last_command_sequence == sequence and _state().actor(5).action_cooldown == cooldown and cooldown > 0.0)
	await _frames(2)
	_check("fresh AI commands respect the existing action cooldown", _count(Event.Kind.SHOT, 5) == 1 and
		_state().actor(5).last_command_sequence > sequence and _refusals.is_empty())
	if not _start("enable drops old manual intent", setup):
		return
	await _frames(4)
	command = _command(5)
	command.action = Command.Action.SHOOT
	command.aim = Vector2.RIGHT
	_check("manual pending action before enabling AI", _simulation.submit_command(command) == OK)
	_check("changed generator starts without old manual action", _simulation.set_ai_actor_ids([5]) == OK)
	await _frames(3)
	_check("enabled AI does not inherit a retained manual shot", _count(Event.Kind.SHOT, 5) == 0 and
		_state().actor(5).last_command_sequence > command.sequence)
	var human: Command = _command(0)
	human.move = Vector2.RIGHT
	human.close_control = true
	_check("human intention can coexist with developer toggles", _simulation.submit_human_command(human) == OK)
	_check("AI change never clears the human intention", _simulation.set_ai_actor_ids([]) == OK and _state().actor(0).close_control)
	await _frames(1)
	_check("human still moves after all generators are disabled", _state().actor(0).velocity.x > 0.0 and
		_state().actor(0).last_command_sequence == human.sequence)


func _test_toggle_phases_and_callbacks() -> void:
	_check("ready preview accepts developer settings", _simulation.reset(Setup.preview_5v5()) == OK and
		_simulation.set_ai_actor_ids([2, 8]) == OK and _state().phase == Snapshot.Phase.READY)
	var ready: Array = _fingerprint(_state())
	await _frames(6)
	_check("ready AI settings do not start the simulation", ready == _fingerprint(_state()))
	var setup: Setup = _isolated_preview()
	setup.ai_actor_ids = [1, 2, 3, 4, 5, 6, 7, 8, 9]
	setup.ball_position = Vector3(0.0, 1.0, 0.0)
	setup.ball_velocity = Vector3(8.0, 0.0, 0.0)
	if not _start("pause and live developer settings", setup):
		return
	await _frames(3)
	_check("pause preview with moving ball", _simulation.set_paused(true) == OK)
	var paused: Array = _invariants(_state())
	_check("AI toggle is valid while paused and preserves all physical state", _simulation.set_ai_actor_ids([2, 4]) == OK and
		paused == _invariants(_state()))
	var changed: Array = _fingerprint(_state())
	await _frames(10)
	_check("paused developer settings never advance clock or physics", changed == _fingerprint(_state()))
	var at: Vector3 = _state().ball_position
	_check("resume after developer change", _simulation.set_paused(false) == OK)
	await _frames(3)
	_check("flight resumes with only the confirmed generators", _state().ball_position.distance_to(at) > 0.1 and _state().ai_actor_ids == [2, 4])
	var tune: Tuning = Tuning.new()
	tune.training_seconds = 0.15
	if not _start("terminal developer settings", _isolated_preview(), tune):
		return
	await _frames(15)
	var finished: Array = _invariants(_state())
	_check("initialized finished matches admit AI settings without reopening play", _state().phase == Snapshot.Phase.FINISHED and
		_simulation.set_ai_actor_ids([9, 2]) == OK and _state().ai_actor_ids == [2, 9] and finished == _invariants(_state()))
	await _frames(10)
	_check("terminal match remains frozen after settings change", finished == _invariants(_state()) and _count(Event.Kind.END) == 1)
	_busy_probe = true
	_busy_kind = Event.Kind.RESTART
	_busy_results.clear()
	if not _start("callback mutation guard", Setup.preview_5v5()):
		_busy_probe = false
		return
	_busy_probe = false
	_check("AI changes during event delivery return exact ERR_BUSY", _busy_results == [ERR_BUSY] and
		_state().ai_actor_ids == [1, 2, 3, 4, 5, 6, 7, 8, 9] and int(_refusals[-1]["actor_id"]) == -1)
	_check("event refusal does not leave mutation guard stuck", _simulation.set_ai_actor_ids([2]) == OK)


func _test_pass_selection() -> void:
	var cases: Array[Dictionary] = [
		{"name": "angle precedes distance", "four": Vector3(8, 0, 0), "six": Vector3(4, 0, 1), "aim": Vector2.RIGHT, "target": -1, "expected": 4},
		{"name": "ball origin changes angular ranking", "four": Vector3(2, 0, 1), "six": Vector3(6, 0, 3.2), "aim": Vector2.RIGHT, "target": -1, "expected": 6},
		{"name": "distance breaks equal angle", "four": Vector3(5, 0, 0), "six": Vector3(10, 0, 0), "aim": Vector2.RIGHT, "target": -1, "expected": 4},
		{"name": "ID breaks equal angle and distance", "four": Vector3(6, 0, -1), "six": Vector3(6, 0, 1), "aim": Vector2.RIGHT, "target": -1, "expected": 4},
		{"name": "neutral pass chooses nearest teammate", "four": Vector3(6, 0, 0), "six": Vector3(-6, 0, 8), "aim": Vector2.ZERO, "target": -1, "expected": 4},
		{"name": "no teammate in cone remains free", "four": Vector3(-6, 0, -8), "six": Vector3(-6, 0, 8), "aim": Vector2(0, 1), "target": -1, "expected": -1},
		{"name": "explicit outside-cone target never forces retarget", "four": Vector3(6, 0, 6), "six": Vector3(6, 0, 0), "aim": Vector2.RIGHT, "target": 4, "expected": -1},
		{"name": "explicit valid target overrides automatic ranking", "four": Vector3(4, 0, 0), "six": Vector3(8, 0, 0), "aim": Vector2.RIGHT, "target": 6, "expected": 6},
	]
	for item: Dictionary in cases:
		var setup: Setup = _isolated_preview()
		setup.actor_positions[0] = Vector3.ZERO
		setup.actor_positions[4] = item["four"]
		setup.actor_positions[6] = item["six"]
		setup.ball_position = Vector3(0.55, 0.12, 0.0)
		if not _start("preview pass " + String(item["name"]), setup):
			return
		await _frames(4)
		var command: Command = _command(0)
		command.action = Command.Action.PASS
		command.aim = item["aim"]
		command.target_actor_id = int(item["target"])
		_check("pass input accepted: " + String(item["name"]), _simulation.submit_human_command(command) == OK)
		await _frames(2)
		var pass_event: Event = _first_event(Event.Kind.PASS)
		var facing: Vector3 = Vector3.RIGHT if command.aim.is_zero_approx() else Vector3(command.aim.x, 0.0, command.aim.y)
		_check("production pass selection: " + String(item["name"]), pass_event != null and
			pass_event.target_actor_id == int(item["expected"]) and pass_event.velocity.normalized().dot(facing) >= cos(deg_to_rad(35.0)) - 0.00001)
		_check("pass selection does not teleport ball to receiver", _state().ball_owner_id == -1 and _state().ball_position.distance_to(setup.ball_position) < 1.0)
		_check("only the effective recipient gets pass focus: " + String(item["name"]),
			_state().selected_actor_id == (int(item["expected"]) if int(item["expected"]) >= 0 else 0) and
			_count(Event.Kind.FOCUS_CHANGED) == (1 if int(item["expected"]) >= 0 else 0))
	var keeper_target: Setup = _isolated_preview()
	keeper_target.actor_positions[0] = Vector3.ZERO
	keeper_target.actor_positions[2] = Vector3(6.0, 0.0, 0.0)
	keeper_target.ball_position = Vector3(0.55, 0.12, 0.0)
	if not _start("untargeted preview pass may select keeper", keeper_target):
		return
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.RIGHT
	_check("untargeted pass can include keeper", _simulation.submit_human_command(command) == OK)
	await _frames(2)
	_check("same-team keepers remain valid preview recipients", _first_event(Event.Kind.PASS) != null and _first_event(Event.Kind.PASS).target_actor_id == 2)
	for tied: bool in [false, true]:
		var setup: Setup = _isolated_preview()
		setup.actor_positions[2] = Vector3(-18.5, 0.0, 0.0)
		setup.actor_positions[4] = Vector3(-13.0 if tied else -11.0, 0.0, -2.0 if tied else 0.0)
		setup.actor_positions[6] = Vector3(-13.0 if tied else -14.0, 0.0, 2.0 if tied else 0.0)
		setup.actor_forwards[4] = Vector2.LEFT
		setup.actor_forwards[6] = Vector2.LEFT
		setup.ball_position = Vector3(-17.95, 0.12, 0.0)
		setup.ai_actor_ids = [2]
		await _keeper_distribution_case("keeper prioritizes safe human; nearer fields tied=%s" % tied, setup, 0)
	for tied: bool in [false, true]:
		var setup: Setup = Setup.preview_5v5()
		setup.ai_actor_ids = [2]
		setup.actor_positions[4] = Vector3(-8.0 if tied else -10.0, 0.0, -6.0)
		setup.actor_forwards[4] = Vector2.LEFT
		setup.actor_forwards[6] = Vector2.LEFT
		setup.ball_position = Vector3(-17.95, 0.12, 0.0)
		await _keeper_distribution_case("keeper finds useful safe field outlet; tied=%s" % tied,
			setup, 4 if tied else 6)


func _keeper_distribution_case(label: String, setup: Setup, expected_target: int) -> void:
	if not _start(label, setup):
		return
	var initial: Snapshot = _state()
	await _frames(4)
	var before: Snapshot = _state()
	var origin: Vector3 = before.ball_position
	var human_lane: float = _distribution_lane_clearance(before, 2, 0, origin)
	var safe_margin: float = Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 1.0
	var observation: Dictionary = {"case": _check_context, "initial": _distribution_state(initial), "before": _distribution_state(before),
		"expected_target": expected_target, "human_lane_clearance": human_lane}
	_check("keeper policy fixture has actual possession and unchanged human selection",
		before.ball_owner_id == 2 and before.selected_actor_id == 0 and before.ai_actor_ids == [2])
	if expected_target == 0:
		_check("human outlet is genuinely clear despite closer field teammates",
			human_lane > safe_margin and _flat_distance(origin, before.actor(0).position) >
				minf(_flat_distance(origin, before.actor(4).position), _flat_distance(origin, before.actor(6).position)))
	else:
		var keeper_lane: float = _distribution_lane_clearance(before, 2, expected_target, origin)
		var outlet_lane: float = _distribution_lane_clearance(before, expected_target, 0, before.actor(expected_target).position)
		observation["keeper_to_outlet_clearance"] = keeper_lane
		observation["outlet_to_human_clearance"] = outlet_lane
		_check("human is screened by nearer 8 but the field outlet opens two safe lanes",
			human_lane < Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS and keeper_lane > safe_margin
			and outlet_lane > safe_margin and _flat_distance(origin, before.actor(8).position) <
				_flat_distance(origin, before.actor(expected_target).position))
		_check("useful field candidates distinguish forward progress from a symmetric ID tie",
			(before.actor(6).position.x > before.actor(4).position.x if expected_target == 6 else
				is_equal_approx(_flat_distance(initial.ball_position, initial.actor(4).position),
					_flat_distance(initial.ball_position, initial.actor(6).position))))
	var capture: Callable = func(event: Event) -> void:
		if event.actor_id == 2:
			observation["at_kick"] = _distribution_state(_state())
			observation["command_after_execution"] = _distribution_command(_body(2).get("command") as Command)
			observation["event"] = {"tick": event.tick, "actor_id": event.actor_id,
				"target_actor_id": event.target_actor_id, "velocity": _distribution_vector(event.velocity)}
	_simulation.pass_made.connect(capture)
	await _frames(61)
	_simulation.pass_made.disconnect(capture)
	_keeper_distribution_evidence.append(observation)
	var pass_event: Event = _first_event(Event.Kind.PASS)
	_check("keeper follows safe-human/useful-outlet policy with an exact field receiver",
		pass_event != null and pass_event.actor_id == 2 and pass_event.target_actor_id == expected_target
		and before.actor(expected_target).team_id == Snapshot.Team.HOME
		and before.actor(expected_target).role == Snapshot.Role.FIELD and _refusals.is_empty())
	_check("autonomous distribution neither steals focus nor chains a finishing action",
		_state().selected_actor_id == 0 and _state().ai_intent_actor_ids == [2]
		and _count(Event.Kind.FOCUS_CHANGED) == 0 and _count(Event.Kind.PASS, 2) == 1 and _count(Event.Kind.SHOT) == 0)


func _test_new_receiver_goal_and_restarts() -> void:
	var setup: Setup = _isolated_preview()
	setup.actor_positions[0] = Vector3.ZERO
	setup.actor_positions[4] = Vector3(5.0, 0.0, 0.0)
	setup.actor_forwards[4] = Vector2.LEFT
	setup.ball_position = Vector3(0.55, 0.12, 0.0)
	if not _start("new physical receiver then goal", setup):
		return
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.RIGHT
	_check("human passes through production API to added actor", _simulation.submit_human_command(command) == OK)
	var received: bool = false
	for frame: int in range(100):
		await _frames(1)
		if _state().ball_owner_id == 4:
			received = true
			break
	_check("new field teammate physically receives the pass", received and _first_event(Event.Kind.PASS) != null and
		_first_event(Event.Kind.PASS).target_actor_id == 4 and _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.POSSESSION and event.actor_id == 4))
	if not received:
		return
	command = _command(4)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.aim = Vector2.RIGHT
	_busy_probe = true
	_busy_kind = Event.Kind.SHOT
	_busy_results.clear()
	_check("added field player can shoot", _simulation.submit_command(command) == OK)
	await _frames(2)
	_busy_probe = false
	_check("AI mutator also refuses inside a physics action event", _busy_results == [ERR_BUSY] and _state().ai_actor_ids.is_empty())
	await _wait_phase(Snapshot.Phase.GOAL_PAUSE, 100)
	var goal: Event = _first_event(Event.Kind.GOAL)
	_check("goal from added field player has correct team and one event", goal != null and goal.actor_id == 4 and
		goal.team_id == 0 and _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	var rids: Array[int] = _body_ids()
	var before: Array = _invariants(_state())
	_check("goal-phase toggle preserves live goal flight", _simulation.set_ai_actor_ids([6, 3]) == OK and before == _invariants(_state()))
	await _wait_phase(Snapshot.Phase.PLAYING, 100)
	_check("goal kickoff keeps preview composition, score and toggles", _state().mode == Setup.Mode.PREVIEW_5V5 and
		_state().actors.size() == 10 and _state().ai_actor_ids == [3, 6] and _state().score == Vector2i(1, 0) and _body_ids() == rids)
	_check("goal kickoff uses all canonical preview spawns", _state().actor(8).spawn_position == Vector3(-13, 0, 0) and
		_state().actor(9).spawn_position == Vector3(13, 0, 0) and _state().ball_position.x > 0.0 and _count(Event.Kind.GOAL) == 1)
	setup = _isolated_preview()
	setup.ai_actor_ids = [4, 9]
	setup.ball_position = Vector3(0.0, 0.5, 9.8)
	setup.ball_velocity = Vector3(0.0, 0.0, 20.0)
	if not _start("preview training out", setup):
		return
	await _wait_phase(Snapshot.Phase.RESTART_PAUSE, 30)
	_check("preview still uses explicit physical training out", _state().phase == Snapshot.Phase.RESTART_PAUSE and
		_state().ball_position.z > 10.105 and _count(Event.Kind.GOAL) == 0 and _ball().freeze)
	before = _invariants(_state())
	_check("out-phase AI change does not thaw or reset ball", _simulation.set_ai_actor_ids([2]) == OK and before == _invariants(_state()) and _ball().freeze)
	await _take_local_restart("preview out")
	_check("out restart keeps ten bodies and effective AI", _state().mode == Setup.Mode.PREVIEW_5V5 and
		_state().actors.size() == 10 and _state().ai_actor_ids == [2] and _state().score == Vector2i.ZERO and
		_state().restart.kind == Types.RestartKind.KICK_IN and absf(_state().ball_position.z) > 9.0)
	var persisted: Setup = Setup.preview_5v5()
	persisted.ai_actor_ids = _state().ai_intent_actor_ids.duplicate()
	_check("host-owned setup copy preserves settings through reset", _simulation.reset(persisted) == OK and
		_state().mode == Setup.Mode.PREVIEW_5V5 and _state().ai_actor_ids == [2] and _state().phase == Snapshot.Phase.READY)
	_check("host-owned setup copy preserves settings through restart", _simulation.start(persisted) == OK and
		_state().mode == Setup.Mode.PREVIEW_5V5 and _state().ai_actor_ids == [2] and _state().score == Vector2i.ZERO)
	_check("applying canonical mode deliberately restores defaults", _simulation.start(Setup.preview_5v5()) == OK and
		_state().ai_actor_ids == [1, 2, 3, 4, 5, 6, 7, 8, 9])


func _test_preview_ai() -> void:
	var setup: Setup = _isolated_preview()
	setup.actor_positions[0] = Vector3(-15, 0, -8)
	setup.actor_positions[1] = Vector3(4, 0, -3)
	setup.actor_positions[4] = Vector3(-4, 0, -3)
	setup.actor_positions[5] = Vector3(4, 0, 3)
	setup.actor_positions[6] = Vector3(-4, 0, 3)
	setup.actor_positions[7] = Vector3(10, 0, -6)
	setup.actor_positions[8] = Vector3(-14, 0, 0)
	setup.actor_positions[9] = Vector3(14, 0, 0)
	setup.ai_actor_ids = [1, 4, 5, 6, 7, 8, 9]
	if not _start("preview chaser tie and support lanes", setup):
		return
	var initial: Snapshot = _state()
	await _frames(12)
	var home_chasers: int = 0
	var away_chasers: int = 0
	for id: int in setup.ai_actor_ids:
		var improvement: float = _flat_distance(initial.actor(id).position, initial.ball_position) - _flat_distance(_state().actor(id).position, initial.ball_position)
		if improvement > 0.3:
			if _state().actor(id).team_id == 0:
				home_chasers += 1
			else:
				away_chasers += 1
	_check("only one field chaser per team physically closes the loose ball", home_chasers == 1 and away_chasers == 1)
	_check("distance tie assigns chasing to lowest active IDs", _state().actor(1).position.z > initial.actor(1).position.z + 0.1 and
		_state().actor(4).position.z > initial.actor(4).position.z + 0.1)
	_check("other field players support or cover their separate spawn lanes", absf(_state().actor(5).position.z - 3.0) < 0.01 and
		absf(_state().actor(6).position.z - 3.0) < 0.01 and absf(_state().actor(7).position.z + 6.0) < 0.01 and
		_state().actor(8).position.z < -0.1 and _state().actor(9).position.x > 14.0)
	var old_home_sequence: int = _state().actor(4).last_command_sequence
	var old_away_sequence: int = _state().actor(1).last_command_sequence
	var new_home_at: Vector3 = _state().actor(6).position
	var new_away_at: Vector3 = _state().actor(5).position
	_check("disable both selected chasers", _simulation.set_ai_actor_ids([5, 6, 7, 8, 9]) == OK)
	await _frames(15)
	_check("chaser handoff ignores disabled actors even when they are closer", _state().actor(6).position.z < new_home_at.z - 0.1 and
		_state().actor(5).position.z < new_away_at.z - 0.1 and _state().actor(4).last_command_sequence == old_home_sequence and
		_state().actor(1).last_command_sequence == old_away_sequence and _flat_speed(_state().actor(4).velocity) < 0.02)
	for opponent_near: bool in [false, true]:
		setup = _isolated_preview()
		setup.actor_positions[5] = Vector3(5.0, 0.0, 0.0)
		setup.actor_positions[1] = Vector3(6.5, 0.0, 0.0)
		setup.actor_positions[4] = Vector3(5.0, 0.0, 1.4) if opponent_near else Vector3(-6.0, 0.0, -8.0)
		setup.ball_position = Vector3(4.45, 0.12, 0.0)
		setup.ai_actor_ids = [5]
		if not _start("preview threat uses opponents nearby=%s" % opponent_near, setup):
			return
		await _frames(4)
		_check("preview threat is based on rival team, not hardcoded human", _state().ball_owner_id == 5 and
			_state().actor(5).close_control == opponent_near)
	setup = _isolated_preview()
	setup.actor_positions[4] = Vector3(-2.0, 0.0, 2.0)
	setup.ball_position = Vector3(0.0, 0.12, 2.0)
	setup.ai_actor_ids = [4]
	if not _start("added teammate autonomously recovers and distributes", setup):
		return
	var received: bool = false
	var legal_speeds: bool = true
	for frame: int in range(600):
		await _frames(1)
		received = received or _state().ball_owner_id == 4
		legal_speeds = legal_speeds and _flat_speed(_state().actor(4).velocity) <= _simulation.tuning.sprint_speed + 0.01
		if _count(Event.Kind.PASS, 4) > 0:
			break
	_check("added field AI recovers, moves and executes a real pass without finishing", received and _count(Event.Kind.PASS, 4) == 1 and
		_count(Event.Kind.SHOT, 4) == 0 and _state().actor(4).position.distance_to(setup.actor_positions[4]) > 0.5)
	_check("preview AI respects normal movement and command validation", legal_speeds and _refusals.is_empty())
	if _count(Event.Kind.PASS, 4) == 0:
		print("PREVIEW_AI_DIAGNOSTIC ", _diagnostic())


func _test_focus_selection() -> void:
	_check("focus action and event append without renumbering", Command.Action.NONE == 0 and Command.Action.PASS == 1 and
		Command.Action.SHOOT == 2 and Command.Action.TACKLE == 3 and Command.Action.SWITCH_TEAMMATE == 4 and
		Event.Kind.BALL_CONTACT == 8 and Event.Kind.FOCUS_CHANGED == 9)
	var cases: Array[Dictionary] = [
		{"name": "neutral actor origin not ball", "four": Vector3(2, 0, 0), "six": Vector3(9, 0, 6), "aim": Vector2.ZERO, "expected": 4},
		{"name": "neutral distance tie uses ID behind facing", "four": Vector3(-2, 0, 0), "six": Vector3(2, 0, 0), "aim": Vector2.ZERO, "expected": 4},
		{"name": "negative lateral direction", "four": Vector3(0, 0, -6), "six": Vector3(0, 0, 6), "aim": Vector2(0, -1), "expected": 4},
		{"name": "positive lateral direction", "four": Vector3(0, 0, -6), "six": Vector3(0, 0, 6), "aim": Vector2(0, 1), "expected": 6},
		{"name": "angle before nearer distance", "four": Vector3(6, 0, 1), "six": Vector3(3, 0, 1), "aim": Vector2.RIGHT, "expected": 4},
		{"name": "equal angle prefers distance", "four": Vector3(3, 0, 0), "six": Vector3(6, 0, 0), "aim": Vector2.RIGHT, "expected": 4},
		{"name": "equal angle and distance prefers ID", "four": Vector3(6, 0, -1), "six": Vector3(6, 0, 1), "aim": Vector2.RIGHT, "expected": 4},
		{"name": "inside 35 degrees negative side", "four": Vector3(6, 0, -4.19), "six": Vector3(6, 0, 4.22), "aim": Vector2.RIGHT, "expected": 4},
		{"name": "inside 35 degrees positive side", "four": Vector3(6, 0, -4.22), "six": Vector3(6, 0, 4.19), "aim": Vector2.RIGHT, "expected": 6},
		{"name": "both candidates outside 35 degrees", "four": Vector3(6, 0, -4.22), "six": Vector3(6, 0, 4.22), "aim": Vector2.RIGHT, "expected": -1},
	]
	for item: Dictionary in cases:
		var setup: Setup = _isolated_preview()
		setup.actor_positions[0] = Vector3.ZERO
		setup.actor_positions[4] = item["four"]
		setup.actor_positions[6] = item["six"]
		setup.ball_position = Vector3(9, 1, 6)
		if not _start("switch " + String(item["name"]), setup):
			return
		var before: Snapshot = _state()
		var command: Command = _command(0)
		command.action = Command.Action.SWITCH_TEAMMATE
		command.aim = item["aim"]
		var submission: Dictionary = _observe_api(_simulation.submit_human_command, [command])
		var code: Error = submission["return_code"]
		if int(item["expected"]) == -1:
			_reject("no directed switch candidate", submission, ERR_UNAVAILABLE, 0)
			_check("no-candidate switch is fully atomic", _fingerprint(before) == _fingerprint(_state()) and _count(Event.Kind.FOCUS_CHANGED) == 0)
			continue
		_check("switch queues without changing selection: " + String(item["name"]), code == OK and
			_state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
		await _frames(1)
		var target: int = int(item["expected"])
		var focus: Event = _first_event(Event.Kind.FOCUS_CHANGED)
		_check_focus("switch chooses " + String(item["name"]), target)
		_check("switch preserves physical positions and ball ownership: " + String(item["name"]),
			_flat_distance(before.actor(0).position, _state().actor(0).position) < 0.001 and
			_flat_distance(before.actor(target).position, _state().actor(target).position) < 0.001 and
			_state().ball_owner_id == before.ball_owner_id and _state().score == before.score and _count(Event.Kind.PASS) == 0)
		_check("switch emits typed focus reason: " + String(item["name"]), focus != null and focus.actor_id == 0 and
			focus.target_actor_id == target and focus.reason == &"off_ball_switch" and _count(Event.Kind.FOCUS_CHANGED) == 1)
	var micro: Setup = Setup.new()
	micro.ai_actor_ids = []
	micro.ball_position = Vector3(0, 1, 5)
	micro.actor_positions[0] = Vector3(19, 0, 0)
	micro.actor_positions[3] = Vector3(18.5, 0, 6)
	if not _start("micro switch without artificial range", micro):
		return
	for target: int in [2, 0, 2, 0]:
		var selected: int = _state().selected_actor_id
		var command: Command = _command(selected)
		command.action = Command.Action.SWITCH_TEAMMATE
		command.aim = Vector2.LEFT if target == 2 else Vector2.RIGHT
		var transition: String = "from=%d to=%d command_sequence=%d" % [selected, target, command.sequence]
		_check("micro accepts adjacent switch ticks: " + transition, _simulation.submit_human_command(command) == OK)
		await _frames(1)
		_check_focus("micro switches across 37.5 metres: " + transition, target)
		_check("micro switching retains all physical athletes: " + transition,
			_physical_actor_count() == 4 and _state().ai_intent_actor_ids.is_empty())
	var setup: Setup = _focus_setup()
	setup.ball_position = Vector3(2.55, 0.12, 0)
	if not _start("teammate possessing is still an off-ball switch", setup):
		return
	var command: Command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("switch accepted before teammate receives", _simulation.submit_human_command(command) == OK)
	await _frames(2)
	_check_focus("teammate owner receives focus without a pass", 8)
	_check("switch keeps teammate possession and never fabricates a kick", _state().ball_owner_id == 8 and
		_count(Event.Kind.PASS) == 0 and _first_event(Event.Kind.FOCUS_CHANGED).reason == &"off_ball_switch")
	var before: Array = _fingerprint(_state())
	_reject("old human identity no longer authorized", _observe_api(_simulation.submit_human_command, [_command(0)]), ERR_UNAUTHORIZED, 0)
	command = _command(8)
	command.action = Command.Action.SWITCH_TEAMMATE
	_reject("selected owner cannot switch instead of passing", _observe_api(_simulation.submit_human_command, [command]), ERR_UNAVAILABLE, 8)
	command = _command(1)
	command.action = Command.Action.SWITCH_TEAMMATE
	_reject("AI authority command cannot change human focus", _observe_api(_simulation.submit_command, [command]), ERR_UNAUTHORIZED, 1)
	command = _command(8)
	command.action = Command.Action.SWITCH_TEAMMATE
	command.target_actor_id = 0
	_reject("switch cannot carry an explicit target", _observe_api(_simulation.submit_human_command, [command]), ERR_INVALID_PARAMETER, 8)
	_check("rejected focus commands leave live state unchanged", before == _fingerprint(_state()))
	var detached: Snapshot = _state()
	detached.selected_actor_id = 9
	detached.actor(8).human_controlled = false
	detached.ai_intent_actor_ids.append(99)
	detached.ai_actor_ids.append(8)
	_check("dynamic focus and both AI lists are detached", before == _fingerprint(_state()))


func _test_focus_pass_and_refusals() -> void:
	var setup: Setup = _isolated_preview()
	setup.actor_positions[0] = Vector3.ZERO
	setup.actor_positions[4] = Vector3(-2, 0, 0)
	setup.actor_positions[6] = Vector3(2.3, 0, 0)
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("neutral pass uses controlled actor not ball or facing", setup):
		return
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.PASS
	_capture_focus_state = true
	_focus_observations.clear()
	_check("neutral pass queues before focus transfer", _simulation.submit_human_command(command) == OK and
		_state().selected_actor_id == 0 and _state().ball_owner_id == 0 and _count(Event.Kind.PASS) == 0)
	await _frames(1)
	_capture_focus_state = false
	var pass_event: Event = _first_event(Event.Kind.PASS)
	var focus: Event = _first_event(Event.Kind.FOCUS_CHANGED)
	_check_focus("accepted neutral kick transfers to nearest actor", 4)
	_check("pass points behind original facing at the actor-nearest teammate", pass_event != null and pass_event.target_actor_id == 4 and pass_event.velocity.x < -6.9)
	_check("pass precedes focus in the same tick", pass_event != null and focus != null and pass_event.event_id < focus.event_id and
		pass_event.tick == focus.tick and focus.actor_id == 0 and focus.target_actor_id == 4 and focus.reason == &"pass")
	_check("pass observers already see atomic new focus and free physical ball", _focus_observations.size() == 2 and
		_focus_observations[0] == {"kind": Event.Kind.PASS, "selected": 4, "intent": [], "effective": [], "owner": -1, "humans": [4]} and
		_focus_observations[1] == {"kind": Event.Kind.FOCUS_CHANGED, "selected": 4, "intent": [], "effective": [], "owner": -1, "humans": [4]} and
		_state().ball_position.distance_to(setup.ball_position) < 0.5)
	var received: bool = false
	for frame: int in range(90):
		await _frames(1)
		if _state().ball_owner_id == 4:
			received = true
			break
	_check("focused real receiver subsequently controls the physical pass", received and _count(Event.Kind.FOCUS_CHANGED) == 1)
	setup = _focus_setup()
	setup.actor_positions[8] = Vector3(8, 0, 0)
	setup.actor_positions[1] = Vector3(3.5, 0, 0)
	setup.actor_forwards[8] = Vector2.LEFT
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("interception does not steal player focus", setup):
		return
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.RIGHT
	command.target_actor_id = 8
	_check("interceptable pass is accepted, not possession-guaranteed", _simulation.submit_human_command(command) == OK)
	for frame: int in range(90):
		await _frames(1)
		if _state().ball_owner_id == 1:
			break
	_check_focus("interception retains chosen home focus", 8)
	_check("opponent physically intercepts without another focus event", _state().ball_owner_id == 1 and
		_count(Event.Kind.FOCUS_CHANGED) == 1 and _first_event(Event.Kind.PASS).target_actor_id == 8)
	setup = _focus_setup()
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("switch context changes before action resolution", setup):
		return
	command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	var switch_submission: Dictionary = _observe_api(_simulation.submit_human_command, [command])
	_check("off-ball switch may queue before first physical reception", switch_submission["return_code"] == OK and _state().ball_owner_id == -1)
	await _frames(1)
	_check("new possession rejects switch at resolution without converting it", _state().ball_owner_id == 0 and
		_state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0 and _count(Event.Kind.PASS) == 0 and
		_refusals.size() == 1 and int(_refusals[0]["code"]) == ERR_UNAVAILABLE and int(_refusals[0]["actor_id"]) == 0)
	_reject_later("queued switch loses its off-ball context", switch_submission, ERR_UNAVAILABLE, 0)
	setup = _focus_setup()
	setup.ball_position = Vector3(0.55, 0.12, 0)
	setup.ball_velocity = Vector3(0, 6, 0)
	if not _start("queued kick loses rising physical ball contact", setup):
		return
	for frame: int in range(12):
		await _frames(1)
		if _state().ball_position.y > 0.43:
			break
	_check("rising ball is owned and reachable when pass is submitted", _state().ball_owner_id == 0 and
		_state().ball_position.y > 0.43 and _state().ball_position.y <= 0.5)
	command = _command(0)
	command.action = Command.Action.PASS
	var pass_submission: Dictionary = _observe_api(_simulation.submit_human_command, [command])
	_check("contact-loss pass is initially valid", pass_submission["return_code"] == OK)
	await _frames(2)
	_check("physical loss between submission and tick refuses the kick", _count(Event.Kind.PASS) == 0 and
		_count(Event.Kind.FOCUS_CHANGED) == 0 and _state().selected_actor_id == 0 and _refusals.size() == 1 and
		int(_refusals[0]["code"]) == ERR_UNAVAILABLE)
	_reject_later("queued pass loses physical ball contact", pass_submission, ERR_UNAVAILABLE, 0)
	await _frames(85)
	_check("rejected pass does not fire later when ball falls back", _count(Event.Kind.PASS) == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	setup = _focus_setup()
	setup.ball_position = Vector3(0.55, 0.12, 0)
	if not _start("physical cooldown does not impose switch cooldown", setup):
		return
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	_check("neutral shot remains a physical shot", _simulation.submit_human_command(command) == OK)
	await _frames(1)
	_check("neutral shooting retains facing and focus", _first_event(Event.Kind.SHOT) != null and
		_first_event(Event.Kind.SHOT).velocity.x > 27.9 and _state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	command = _command(0)
	command.action = Command.Action.PASS
	var before: Array = _fingerprint(_state())
	_reject("cooling pass cannot transfer focus", _observe_api(_simulation.submit_human_command, [command]), ERR_BUSY, 0)
	_check("cooldown rejection is atomic", before == _fingerprint(_state()))
	command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("off-ball switch is legal during shot cooldown", _simulation.submit_human_command(command) == OK)
	await _frames(1)
	_check_focus("switch during cooldown selects teammate", 8)
	_check("focus does not erase old physical cooldown", _state().actor(0).action_cooldown > 0.25)


func _test_focus_action_order() -> void:
	for reverse: bool in [false, true]:
		var setup: Setup = _focus_setup()
		setup.ai_actor_ids = [0, 8]
		setup.ball_position = Vector3(2.55 if reverse else 0.55, 0.12, 0)
		setup.actor_forwards[8] = Vector2.RIGHT if reverse else Vector2.LEFT
		var sender: int = 8 if reverse else 0
		var recipient: int = 0 if reverse else 8
		if not _start("selected-first handoff %d->%d" % [sender, recipient], setup):
			return
		if reverse:
			var switch: Command = _command(0)
			switch.action = Command.Action.SWITCH_TEAMMATE
			_check("obtain high-ID selection using real off-ball action", _simulation.submit_human_command(switch) == OK)
		await _frames(3)
		_check("handoff caster has physical possession", _state().selected_actor_id == sender and _state().ball_owner_id == sender)
		var pending: Command = _command(recipient)
		pending.action = Command.Action.TACKLE
		pending.move = Vector2.RIGHT
		pending.sprint = true
		_check("recipient has an accepted pending authority action", _simulation.submit_command(pending) == OK)
		var command: Command = _command(sender)
		command.action = Command.Action.PASS
		command.aim = Vector2.LEFT if reverse else Vector2.RIGHT
		command.move = Vector2(0, 1)
		command.sprint = true
		command.close_control = true
		command.target_actor_id = recipient
		_focus_observations.clear()
		_capture_focus_state = true
		_check("selected pending pass accepted ahead of recipient", _simulation.submit_human_command(command) == OK)
		await _frames(1)
		_capture_focus_state = false
		_check_focus("pending handoff resolves independent of ID order", recipient)
		_check("recipient pending tackle is cancelled, not executed or cooled down", _count(Event.Kind.TACKLE, recipient) == 0 and
			_state().actor(recipient).action_cooldown == 0.0 and _count(Event.Kind.PASS, sender) == 1)
		_check("handoff clears both held flags but preserves momentum and cooldown", not _state().actor(sender).close_control and
			not _state().actor(recipient).close_control and _flat_speed(_state().actor(sender).velocity) > 0.1 and
			_flat_speed(_state().actor(recipient).velocity) > 0.1 and _state().actor(sender).action_cooldown > 0.3)
		_check("handoff retains accepted actor sequences", _state().actor(sender).last_command_sequence == command.sequence and
			_state().actor(recipient).last_command_sequence >= pending.sequence)
		_check("pass event exposes effective AI after atomic handoff", _focus_observations.size() == 2 and
			_focus_observations[0]["selected"] == recipient and _focus_observations[0]["effective"] == [sender] and
			_focus_observations[0]["intent"] == [0, 8] and _focus_observations[0]["humans"] == [recipient] and
			_focus_observations[0]["owner"] == -1)
		var sender_sequence: int = command.sequence
		_check("disable old actor generation without resetting handoff", _simulation.set_ai_actor_ids([]) == OK)
		command = _command(recipient)
		command.aim = Vector2.RIGHT
		_check("new human command continues previous AI sequence", command.sequence > pending.sequence and _simulation.submit_human_command(command) == OK)
		var before: Array = _fingerprint(_state())
		_reject("stale pre-focus sequence cannot be replayed", _observe_api(_simulation.submit_human_command, [pending]), ERR_INVALID_PARAMETER, recipient)
		_check("stale recipient action cannot change focus or movement", before == _fingerprint(_state()))
		await _frames(5)
		_check("old body brakes normally with no retained human movement", _flat_speed(_state().actor(sender).velocity) < 0.02 and
			_state().actor(sender).last_command_sequence == sender_sequence and
			_count(Event.Kind.TACKLE, recipient) == 0)
	var setup: Setup = _focus_setup()
	setup.ai_actor_ids = [0, 8]
	if not _start("focus callbacks refuse all public mutations", setup):
		return
	_focus_mutation_results.clear()
	_nested_refusal_results.clear()
	_focus_probe_unchanged = false
	_focus_mutation_probe = true
	var command: Command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("callback probe switch accepted", _simulation.submit_human_command(command) == OK)
	await _frames(1)
	_focus_mutation_probe = false
	_check("all six public mutations return busy during focus delivery", _focus_mutation_results.size() == 6 and
		_focus_mutation_results.all(func(code: int) -> bool: return code == ERR_BUSY) and _focus_probe_unchanged)
	_check("rejection callbacks return busy without recursively emitting", _nested_refusal_results.size() == 36 and _refusals.size() == 6 and
		_nested_refusal_results.all(func(code: int) -> bool: return code == ERR_BUSY))
	_check_focus("reentrant commands cannot undo new selection", 8)
	_check("reentrant start cannot replace preview mode or intention", _state().mode == Setup.Mode.PREVIEW_5V5 and
		_state().ai_intent_actor_ids == [0, 8] and _physical_actor_count() == 10)
	var before: Array = _fingerprint(_state())
	_nested_refusal_results.clear()
	_refusals.clear()
	_focus_mutation_probe = true
	var absent_ai_ids: Array[int] = [99]
	_reject("between-tick rejection also guards nested mutations", _observe_api(_simulation.set_ai_actor_ids, [absent_ai_ids]), ERR_INVALID_PARAMETER)
	_focus_mutation_probe = false
	_check("all six public mutations are busy inside a between-tick refusal", _nested_refusal_results.size() == 6 and
		_nested_refusal_results.all(func(code: int) -> bool: return code == ERR_BUSY) and
		_refusals.size() == 1 and before == _fingerprint(_state()))


func _test_focus_intent() -> void:
	var cases: Array[Array] = [[], [0], [4], [0, 4], [8, 2, 0], [8]]
	for values: Array in cases:
		var setup: Setup = _focus_setup()
		setup.ai_actor_ids.assign(values)
		var expected: Array[int] = setup.ai_actor_ids.duplicate()
		expected.sort()
		if not _start("exact focus intention " + str(values), setup):
			return
		var initial_effective: Array[int] = expected.duplicate()
		initial_effective.erase(0)
		_check("initial effective AI excludes only selected actor", _state().ai_intent_actor_ids == expected and _state().ai_actor_ids == initial_effective)
		var command: Command = _command(0)
		command.action = Command.Action.SWITCH_TEAMMATE
		_check("first exact-subset switch accepted", _simulation.submit_human_command(command) == OK)
		await _frames(1)
		var selected_sequence: int = _state().actor(8).last_command_sequence
		await _frames(5)
		var effective: Array[int] = expected.duplicate()
		effective.erase(8)
		_check("handoff preserves exact submitted intention without inference", _state().selected_actor_id == 8 and
			_state().ai_intent_actor_ids == expected and _state().ai_actor_ids == effective)
		_check("old human generates AI only if explicitly intended", (_state().actor(0).last_command_sequence > command.sequence) == (0 in expected) and
			_state().actor(8).last_command_sequence == selected_sequence)
		command = _command(8)
		command.action = Command.Action.SWITCH_TEAMMATE
		_check("return exact-subset switch accepted", _simulation.submit_human_command(command) == OK)
		await _frames(6)
		_check("return handoff preserves exact list and resumes only intended recipient AI", _state().selected_actor_id == 0 and
			_state().ai_intent_actor_ids == expected and _state().ai_actor_ids == initial_effective and
			(_state().actor(8).last_command_sequence > command.sequence) == (8 in expected))
	var setup: Setup = _focus_setup()
	if not _start("latent selected preference preserves human command", setup):
		return
	var command: Command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("select added athlete for latent toggle", _simulation.submit_human_command(command) == OK)
	await _frames(1)
	command = _command(8)
	command.move = Vector2.RIGHT
	command.sprint = true
	command.close_control = true
	_check("human movement submitted before latent toggle", _simulation.submit_human_command(command) == OK)
	var selected_preference: Array[int] = [8]
	_check("selected ID is a valid latent AI preference", _simulation.set_ai_actor_ids(selected_preference) == OK)
	selected_preference.clear()
	await _frames(4)
	_check("latent change preserves real movement and does not generate selected AI", _state().actor(8).velocity.x > 1.0 and
		_state().actor(8).close_control and _state().actor(8).last_command_sequence == command.sequence and
		_state().ai_intent_actor_ids == [8] and _state().ai_actor_ids.is_empty())
	var before: Array = _fingerprint(_state())
	_check("identical selected preference is idempotent", _simulation.set_ai_actor_ids([8]) == OK and before == _fingerprint(_state()))
	command = _command(8)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("queue switch before disabling only latent preference", _simulation.submit_human_command(command) == OK)
	_check("latent removal does not clear pending human action", _simulation.set_ai_actor_ids([]) == OK)
	await _frames(1)
	_check_focus("pending human switch survives latent preference removal", 0)
	_check("empty intention stays empty after latent handoff", _state().ai_intent_actor_ids.is_empty() and _state().ai_actor_ids.is_empty())


func _test_focus_phases() -> void:
	var setup: Setup = _focus_setup()
	setup.ai_actor_ids = [0, 8]
	setup.ball_position = Vector3(0, 1.5, 4)
	setup.ball_velocity = Vector3(5, 2, 0)
	if not _start("pause and restart with nondefault focus", setup):
		return
	var command: Command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("select before user pause", _simulation.submit_human_command(command) == OK)
	await _frames(1)
	_check("pause focused match", _simulation.set_paused(true) == OK)
	var paused: Array = _fingerprint(_state())
	await _frames(12)
	_check("user pause freezes physical state while preserving selection and intent", paused == _fingerprint(_state()) and
		_state().selected_actor_id == 8 and _state().ai_intent_actor_ids == [0, 8])
	_reject("paused selected cannot submit actions", _observe_api(_simulation.submit_human_command, [_command(8)]), ERR_UNAVAILABLE, 8)
	_check("resume preserves selection and live ball flight", _simulation.set_paused(false) == OK and
		_state().selected_actor_id == 8 and _state().ball_velocity.length() > 1.0)
	var persisted: Setup = Setup.preview_5v5()
	persisted.ai_actor_ids = _state().ai_intent_actor_ids.duplicate()
	_check("host-style explicit reset selects zero and keeps intent/mode", _simulation.reset(persisted) == OK and
		_state().phase == Snapshot.Phase.READY and _state().selected_actor_id == 0 and
		_state().ai_intent_actor_ids == [0, 8] and _state().ai_actor_ids == [8] and _state().mode == Setup.Mode.PREVIEW_5V5)
	_check("host-style restart keeps intent while starting at zero", _simulation.start(persisted) == OK and
		_state().selected_actor_id == 0 and _state().ai_intent_actor_ids == [0, 8])
	_check("canonical preview apply restores complete default intention", _simulation.start(Setup.preview_5v5()) == OK and
		_state().selected_actor_id == 0 and _state().ai_intent_actor_ids == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] and
		_state().ai_actor_ids == [1, 2, 3, 4, 5, 6, 7, 8, 9])
	_check("null start still deliberately restores four-actor micro defaults", _simulation.start() == OK and
		_state().selected_actor_id == 0 and _state().ai_intent_actor_ids == [0, 1, 2, 3] and _state().ai_actor_ids == [1, 2, 3] and
		_state().mode == Setup.Mode.MICRO_1V1 and _physical_actor_count() == 4)
	for goal: bool in [true, false]:
		setup = _focus_setup()
		setup.ai_actor_ids = [0, 8]
		setup.ball_position = Vector3(19.3, 0.6, 0) if goal else Vector3(0, 0.5, 9.8)
		setup.ball_velocity = Vector3(20, 0, 0) if goal else Vector3(0, 0, 20)
		if not _start("canonical kickoff preserves focus during pause goal=%s" % goal, setup):
			return
		command = _command(0)
		command.action = Command.Action.SWITCH_TEAMMATE
		_check("switch before physical goal or out", _simulation.submit_human_command(command) == OK)
		var pause_phase: Snapshot.Phase = Snapshot.Phase.GOAL_PAUSE if goal else Snapshot.Phase.RESTART_PAUSE
		await _wait_phase(pause_phase, 20)
		var paused_selection: int = 8 if goal else _state().restart.taker_actor_id
		_check("goal keeps focus and out selects the awarded home taker", _state().phase == pause_phase and
			_state().selected_actor_id == paused_selection and _state().ai_intent_actor_ids == [0, 8] and
			_state().score == (Vector2i(1, 0) if goal else Vector2i.ZERO))
		_reject("goal/out selected cannot submit actions", _observe_api(_simulation.submit_human_command, [_command(paused_selection)]), ERR_UNAVAILABLE, paused_selection)
		_check("explicit pause over goal/out retains focus", _simulation.set_paused(true) == OK and _state().selected_actor_id == paused_selection)
		paused = _fingerprint(_state())
		await _frames(5)
		_check("nested goal/out pause is physically frozen", paused == _fingerprint(_state()))
		_check("resume goal/out keeps focus until canonical kickoff", _simulation.set_paused(false) == OK and
			_state().phase == pause_phase and _state().selected_actor_id == paused_selection)
		if goal:
			await _wait_phase(Snapshot.Phase.PLAYING, 110)
			_check_focus("canonical goal kickoff restores default focus", 0)
		else:
			await _take_local_restart("focused touchline")
			_check("localized out resumes only after a physical kick", _state().restart.stage == Types.RestartStage.IN_PLAY and
				_count(Event.Kind.PASS) == 1)
		var effective: Array[int] = [0, 8]
		effective.erase(_state().selected_actor_id)
		_check("goal/out preserves intent, roster, score and effective selection", _state().mode == Setup.Mode.PREVIEW_5V5 and
			_state().ai_intent_actor_ids == [0, 8] and _state().ai_actor_ids == effective and _physical_actor_count() == 10 and
			_state().score == (Vector2i(1, 0) if goal else Vector2i.ZERO) and (not goal or _count(Event.Kind.FOCUS_CHANGED) == 1))
	for goal_at_buzzer: bool in [false, true]:
		setup = _focus_setup()
		setup.ball_position = Vector3(19.61, 0.4, 0) if goal_at_buzzer else Vector3(0, 1.5, 4)
		setup.ball_velocity = Vector3(5, 0, 0) if goal_at_buzzer else Vector3.ZERO
		var tuning: Tuning = Tuning.new()
		tuning.training_seconds = 0.105 if goal_at_buzzer else 0.15
		if not _start("terminal retains focus goal_at_buzzer=%s" % goal_at_buzzer, setup, tuning):
			return
		command = _command(0)
		command.action = Command.Action.SWITCH_TEAMMATE
		_check("select before terminal training tick", _simulation.submit_human_command(command) == OK)
		await _wait_phase(Snapshot.Phase.FINISHED, 110)
		_check_focus("finished match retains current selection", 8)
		_check("terminal ends exactly once without canonical selection reset", _count(Event.Kind.END) == 1 and
			_count(Event.Kind.GOAL) == (1 if goal_at_buzzer else 0) and _state().seconds_remaining == 0.0 and
			_count(Event.Kind.FOCUS_CHANGED) == 1)
		paused = _fingerprint(_state())
		_reject("terminal selected cannot act", _observe_api(_simulation.submit_human_command, [_command(8)]), ERR_UNAVAILABLE, 8)
		await _frames(5)
		_check("finished selection and physics remain frozen", paused == _fingerprint(_state()))
		_check("terminal may retain latent intention without generating actions", _simulation.set_ai_actor_ids([0, 8]) == OK and
			_state().selected_actor_id == 8 and _state().ai_intent_actor_ids == [0, 8] and _state().ai_actor_ids == [0])


func _focus_setup() -> Setup:
	var setup: Setup = _isolated_preview()
	setup.actor_positions[0] = Vector3.ZERO
	setup.actor_positions[8] = Vector3(2, 0, 0)
	setup.ball_position = Vector3(9, 1, 4)
	return setup


func _check_focus(label: String, expected: int) -> void:
	var state: Snapshot = _state()
	var humans: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.human_controlled:
			humans.append(actor.actor_id)
	_check(label, state.selected_actor_id == expected and humans == [expected] and state.actor(expected).team_id == 0 and
		expected not in state.ai_actor_ids)


func _start(label: String, setup: Setup, tuning: Tuning = null) -> bool:
	_check_context = "%s; initial mode=%d; AI intent=%s" % [label, setup.mode, str(setup.ai_actor_ids)]
	_events.clear()
	_refusals.clear()
	_simulation.tuning = Tuning.new() if tuning == null else tuning
	var code: Error = _simulation.start(setup)
	_check("start " + label, code == OK)
	if code != OK:
		print("PREVIEW_START_ERROR ", label, ": ", _simulation.last_error)
	return code == OK


func _isolated_preview() -> Setup:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	setup.actor_positions = {
		0: Vector3(-12, 0, -8), 1: Vector3(12, 0, -8),
		2: Vector3(-18.5, 0, 8), 3: Vector3(18.5, 0, 8),
		4: Vector3(-6, 0, -8), 5: Vector3(6, 0, -8),
		6: Vector3(-6, 0, 8), 7: Vector3(6, 0, 8),
		8: Vector3(-12, 0, 8), 9: Vector3(12, 0, 8),
	}
	setup.ball_position = Vector3(0.0, 0.12, 0.0)
	return setup


func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame


func _wait_phase(phase: Snapshot.Phase, maximum_frames: int) -> void:
	for frame: int in maximum_frames:
		if _state().phase == phase:
			return
		await _frames(1)
	_check("bounded wait reached phase %d" % phase, false)


func _take_local_restart(label: String) -> void:
	for frame: int in range(140):
		if _state().phase != Snapshot.Phase.RESTART_PAUSE or _state().restart.stage == Types.RestartStage.READY:
			break
		await _frames(1)
	_check(label + " reaches localized READY", _state().phase == Snapshot.Phase.RESTART_PAUSE and _state().restart.stage == Types.RestartStage.READY)
	if _state().phase != Snapshot.Phase.RESTART_PAUSE or _state().restart.stage != Types.RestartStage.READY:
		return
	var command: Command = _command(_state().restart.taker_actor_id)
	command.action = Command.Action.KEEPER_THROW if _state().restart.kind == Types.RestartKind.GOAL_CLEARANCE else Command.Action.PASS
	if _state().restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		command.action = Command.Action.SHOOT
		command.aim = Vector2(_state().actor(command.actor_id).attack_direction.x, 0.0)
	_check(label + " uses a production restart command", _simulation.submit_command(command) == OK)
	await _frames(2)


func _state() -> Snapshot:
	return _simulation.get_snapshot()


func _command(id: int) -> Command:
	return Command.new(id, _state().actor(id).last_command_sequence + 1)


func _body(id: int) -> CharacterBody3D:
	return _simulation.get_node("Actor%d" % id) as CharacterBody3D


func _ball() -> RigidBody3D:
	return _simulation.get_node("Ball") as RigidBody3D


func _space() -> RID:
	return PhysicsServer3D.body_get_space(_ball().get_rid())


func _body_ids() -> Array[int]:
	var ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in _state().actors:
		ids.append(_body(actor.actor_id).get_instance_id())
	return ids


func _physical_actor_count() -> int:
	var count: int = 0
	for child: Node in _simulation.get_children():
		if child is CharacterBody3D:
			count += 1
	return count


func _count(kind: Event.Kind, actor_id: int = -1) -> int:
	var count: int = 0
	for event: Event in _events:
		if event.kind == kind and (actor_id == -1 or event.actor_id == actor_id):
			count += 1
	return count


func _first_event(kind: Event.Kind) -> Event:
	for event: Event in _events:
		if event.kind == kind:
			return event
	return null


func _on_event(event: Event) -> void:
	_events.append(event)
	if _busy_probe and event.kind == _busy_kind:
		var empty_ids: Array[int] = []
		var context: String = "event %s actor=%d target=%d" % [Event.Kind.keys()[event.kind], event.actor_id, event.target_actor_id]
		_busy_results.append(_callback_refusal(context, _simulation.set_ai_actor_ids, [empty_ids]))
	if _capture_focus_state and event.kind in [Event.Kind.PASS, Event.Kind.FOCUS_CHANGED]:
		var state: Snapshot = _state()
		var humans: Array[int] = []
		for actor: Snapshot.ActorSnapshot in state.actors:
			if actor.human_controlled:
				humans.append(actor.actor_id)
		_focus_observations.append({"kind": event.kind, "selected": state.selected_actor_id, "intent": state.ai_intent_actor_ids,
			"effective": state.ai_actor_ids, "owner": state.ball_owner_id, "humans": humans})
	if _focus_mutation_probe and event.kind == Event.Kind.FOCUS_CHANGED:
		var before: Array = _fingerprint(_state())
		var empty_ids: Array[int] = []
		var context: String = "event FOCUS_CHANGED %d->%d" % [event.actor_id, event.target_actor_id]
		_focus_mutation_results.append(_callback_refusal(context, _simulation.start, []))
		_focus_mutation_results.append(_callback_refusal(context, _simulation.reset, []))
		_focus_mutation_results.append(_callback_refusal(context, _simulation.set_paused, [false]))
		_focus_mutation_results.append(_callback_refusal(context, _simulation.set_ai_actor_ids, [empty_ids]))
		_focus_mutation_results.append(_callback_refusal(context, _simulation.submit_command, [Command.new(99, 0)]))
		_focus_mutation_results.append(_callback_refusal(context, _simulation.submit_human_command, [Command.new(event.actor_id, 0)]))
		_focus_probe_unchanged = before == _fingerprint(_state())


func _on_refusal(actor_id: int, code: Error, message: String) -> void:
	var notification: Dictionary = {"index": _refusal_notifications.size(), "actor_id": actor_id, "code": code,
		"message": message, "context": _check_context, "call": _active_refusal_context}
	_refusal_notifications.append(notification)
	_refusals.append(notification)


func _on_focus_probe_refusal(actor_id: int, code: Error, message: String) -> void:
	if not _focus_mutation_probe:
		return
	var parent: Dictionary = {"actor_id": actor_id, "code": code, "message": message, "call": _active_refusal_context}
	var context: String = "command_rejected from %s (actor=%d code=%d)" % [_active_refusal_context, actor_id, code]
	var empty_ids: Array[int] = []
	_nested_refusal_results.append(_callback_refusal(context, _simulation.set_ai_actor_ids, [empty_ids], false, parent))
	_nested_refusal_results.append(_callback_refusal(context, _simulation.submit_command, [null], false, parent))
	_nested_refusal_results.append(_callback_refusal(context, _simulation.start, [], false, parent))
	_nested_refusal_results.append(_callback_refusal(context, _simulation.reset, [], false, parent))
	_nested_refusal_results.append(_callback_refusal(context, _simulation.set_paused, [true], false, parent))
	_nested_refusal_results.append(_callback_refusal(context, _simulation.submit_human_command,
		[_command(_state().selected_actor_id)], false, parent))


func _observe_api(api: Callable, arguments: Array, context: String = "") -> Dictionary:
	var request: Dictionary = {"method": String(api.get_method()), "arguments": _refusal_arguments(arguments)}
	var call_label: String = "%s %s" % [request["method"], JSON.stringify(request["arguments"])]
	if not context.is_empty():
		call_label = context + " / " + call_label
	var previous_context: String = _active_refusal_context
	var notification_start: int = _refusal_notifications.size()
	var last_error_before: String = _simulation.last_error
	_active_refusal_context = call_label
	var actual: Error = api.callv(arguments)
	var last_error_after: String = _simulation.last_error
	var notification_end: int = _refusal_notifications.size()
	_active_refusal_context = previous_context
	return {"source": "api_return", "call": call_label, "request": request, "return_code": actual,
		"last_error_before": last_error_before, "last_error_after": last_error_after,
		"notification_start": notification_start, "notification_end": notification_end,
		"notifications": _refusal_notifications.slice(notification_start, notification_end).duplicate(true)}


func _refusal_arguments(arguments: Array) -> Array:
	var captured: Array = []
	for argument: Variant in arguments:
		if argument is Command:
			captured.append({"type": "PlayerCommand", "actor_id": argument.actor_id,
				"sequence": argument.sequence, "action": argument.action})
		elif argument is Setup:
			captured.append({"type": "MatchSetup", "mode": argument.mode, "ai_actor_ids": argument.ai_actor_ids.duplicate()})
		elif argument is Array:
			captured.append(argument.duplicate(true))
		else:
			captured.append(argument)
	return captured


func _callback_refusal(context: String, api: Callable, arguments: Array,
		notification_expected: bool = true, parent_notification: Dictionary = {}) -> Error:
	var requested_actor_id: int = -1
	if not arguments.is_empty() and arguments[0] is Command:
		requested_actor_id = arguments[0].actor_id
	var observation: Dictionary = _observe_api(api, arguments, context)
	var actual: Error = observation["return_code"]
	var notifications: Array = observation["notifications"]
	var valid: bool = actual == ERR_BUSY
	if notification_expected:
		valid = (valid and notifications.size() == 1 and int(notifications[0]["code"]) == actual and
			int(notifications[0]["actor_id"]) == requested_actor_id and
			String(notifications[0]["message"]) == CALLBACK_BUSY_MESSAGES[String(api.get_method())] and
			String(observation["last_error_after"]) == String(notifications[0]["message"]))
	else:
		# Recursive refusals return a code while preserving the outer diagnostic and suppressing another signal.
		valid = (valid and notifications.is_empty() and not parent_notification.is_empty() and
			not String(observation["last_error_before"]).is_empty() and
			observation["last_error_before"] == observation["last_error_after"] and
			observation["last_error_before"] == parent_notification["message"])
	observation["notification_expected"] = notification_expected
	if not parent_notification.is_empty():
		observation["parent_notification"] = parent_notification.duplicate(true)
	_record_refusal(String(observation["call"]), observation, valid)
	return actual


func _reject(label: String, observation: Dictionary, expected: Error, actor_id: int = -1) -> void:
	var notifications: Array = observation["notifications"]
	var actual: Error = observation["return_code"]
	var valid: bool = (actual == expected and not String(observation["last_error_after"]).is_empty() and
		notifications.size() == 1 and int(notifications[0]["code"]) == expected and
		int(notifications[0]["actor_id"]) == actor_id and
		String(notifications[0]["message"]) == String(observation["last_error_after"]))
	observation["notification_expected"] = true
	_record_refusal(label, observation, valid)


func _reject_later(label: String, submission: Dictionary, expected: Error, actor_id: int) -> void:
	var notifications: Array[Dictionary] = _refusal_notifications.slice(int(submission["notification_end"])).duplicate(true)
	var observation: Dictionary = {"source": "command_rejected", "submission": submission.duplicate(true),
		"notifications": notifications, "last_error_after": _simulation.last_error}
	var valid: bool = (submission["return_code"] == OK and submission["notifications"].is_empty() and
		notifications.size() == 1 and int(notifications[0]["code"]) == expected and
		int(notifications[0]["actor_id"]) == actor_id and not String(notifications[0]["message"]).is_empty() and
		String(notifications[0]["message"]) == String(observation["last_error_after"]))
	_record_refusal(label, observation, valid)


func _record_refusal(label: String, observation: Dictionary, passed: bool) -> void:
	_expected_refusals += 1
	var check_label: String = "expected refusal: " + label
	var identity: String = _check_identity(check_label)
	for notification: Dictionary in observation["notifications"]:
		var index: int = int(notification["index"])
		if _claimed_refusal_notifications.has(index):
			passed = false
		else:
			_claimed_refusal_notifications[index] = identity
	observation["name"] = identity
	observation["passed"] = passed
	_refusal_evidence.append(observation)
	_check(check_label, passed)


func _refusal_accounting_is_complete() -> bool:
	if _expected_refusals != _refusal_evidence.size() or _claimed_refusal_notifications.size() != _refusal_notifications.size():
		return false
	var names: Dictionary[String, bool] = {}
	for check: Dictionary in _checks:
		var name: String = check["name"]
		if name.begins_with("expected refusal: "):
			if names.has(name) or not bool(check["passed"]):
				return false
			names[name] = true
	if names.size() != _refusal_evidence.size():
		return false
	for observation: Dictionary in _refusal_evidence:
		var name: String = observation["name"]
		if not names.has(name) or not bool(observation["passed"]):
			return false
		names.erase(name)
		if observation["source"] == "api_return":
			if int(observation["return_code"]) == OK:
				return false
		elif observation["source"] == "command_rejected":
			if int(observation["submission"]["return_code"]) != OK or observation["notifications"].size() != 1:
				return false
		else:
			return false
	for index: int in _refusal_notifications.size():
		if not _claimed_refusal_notifications.has(index):
			return false
	return names.is_empty()


func _check_composition(state: Snapshot, count: int, mode: Setup.Mode) -> void:
	var fields: Vector2i = Vector2i.ZERO
	var keepers: Vector2i = Vector2i.ZERO
	var humans: Array[int] = []
	var ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		ids.append(actor.actor_id)
		if actor.role == Snapshot.Role.KEEPER:
			keepers[actor.team_id] += 1
		else:
			fields[actor.team_id] += 1
		if actor.human_controlled:
			humans.append(actor.actor_id)
	var expected_ids: Array[int] = []
	for id: int in count:
		expected_ids.append(id)
	_check("composition %d has exact sorted identities and default selection" % count, state.mode == mode and ids == expected_ids and
		state.selected_actor_id == 0 and humans == [state.selected_actor_id] and _physical_actor_count() == count)
	_check("composition %d has correct fields and keepers by team" % count, keepers == Vector2i.ONE and
		fields == (Vector2i(4, 4) if mode == Setup.Mode.PREVIEW_5V5 else Vector2i.ONE) and
		state.actor(2).role == Snapshot.Role.KEEPER and state.actor(3).role == Snapshot.Role.KEEPER)


func _invariants(state: Snapshot) -> Array:
	var result: Array = [state.mode, state.selected_actor_id, state.tick, state.phase, state.resume_phase, state.score, state.seconds_remaining, state.phase_seconds_remaining,
		state.ball_position, state.ball_velocity, state.ball_rotation, state.ball_angular_velocity, state.ball_owner_id, state.last_touch_actor_id,
		state.last_touch_tick, state.last_pass_actor_id, state.last_pass_target_actor_id, state.last_pass_tick,
		state.training_exercise, state.accumulated_fouls, state.period_state, state.extended_restart_id, state.extended_kick_event_id,
		state.human_control_context, state.human_allowed_actions, state.selected_can_move]
	var restart: Types.RestartState = state.restart
	result.append([restart.id, restart.kind, restart.stage, restart.launch_contact_id, restart.awarded_team_id, restart.taker_actor_id, restart.spot,
		restart.offence_spot, restart.border, restart.spot_choice, restart.has_spot_choice, restart.stage_started_tick,
		restart.placement_end_tick, restart.ready_tick, restart.deadline_tick, restart.minimum_opponent_distance,
		restart.direct_opponent_goal_allowed, restart.requires_direct_shot, restart.other_actor_touched])
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.team_id, actor.role, actor.human_controlled, actor.spawn_position, actor.position, actor.velocity,
			actor.forward, actor.facing_yaw, actor.action_cooldown, actor.last_command_sequence, actor.last_command_tick,
			actor.ball_contact_reachable, actor.ball_in_hands, actor.gesture_kind, actor.gesture_started_tick,
			actor.gesture_duration_ticks, actor.gesture_direction, actor.gesture_contact_position])
	return result


func _fingerprint(state: Snapshot) -> Array:
	var result: Array = _invariants(state)
	result.append(state.ai_intent_actor_ids)
	result.append(state.ai_actor_ids)
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append(actor.close_control)
	return result


func _flat_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _distribution_state(state: Snapshot) -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append({"id": actor.actor_id, "team": actor.team_id, "role": actor.role,
			"position": _distribution_vector(actor.position), "sequence": actor.last_command_sequence})
	return {"tick": state.tick, "phase": state.phase, "selected_actor_id": state.selected_actor_id,
		"ball_owner_id": state.ball_owner_id, "ball_position": _distribution_vector(state.ball_position),
		"ai_intent_actor_ids": state.ai_intent_actor_ids, "actors": actors}


func _distribution_command(command: Command) -> Dictionary:
	return {"actor_id": command.actor_id, "sequence": command.sequence, "stored_action": command.action,
		"target_actor_id": command.target_actor_id, "aim": [command.aim.x, command.aim.y],
		"move": [command.move.x, command.move.y], "close_control": command.close_control}


func _distribution_vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _distribution_lane_clearance(state: Snapshot, passer: int, receiver: int, origin: Vector3) -> float:
	var start: Vector2 = Vector2(origin.x, origin.z)
	var target: Vector2 = Vector2(state.actor(receiver).position.x, state.actor(receiver).position.z)
	var clearance: float = INF
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.actor_id in [passer, receiver]:
			continue
		var point: Vector2 = Vector2(actor.position.x, actor.position.z)
		clearance = minf(clearance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, target)))
	return clearance


func _diagnostic() -> String:
	var actions: Array[Dictionary] = []
	for event: Event in _events:
		if event.kind != Event.Kind.BALL_CONTACT:
			actions.append({"kind": event.kind, "actor_id": event.actor_id, "target": event.target_actor_id, "reason": event.reason})
	return JSON.stringify({"phase": _state().phase, "owner": _state().ball_owner_id, "ball": str(_state().ball_position),
		"actor4": str(_state().actor(4).position), "actions": actions, "refusals": _refusals})


func _check_identity(label: String) -> String:
	return "%s [case: %s]" % [label, _check_context]


func _check(label: String, passed: bool) -> void:
	var identity: String = _check_identity(label)
	_checks.append({"name": identity, "passed": passed})
	print(("PASS " if passed else "FAIL ") + identity)


func _finish() -> void:
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	print("FUTSAL_PREVIEW_TESTS ", JSON.stringify({"ok": failures.is_empty() and _completed, "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "expected_refusals": _expected_refusals, "failures": failures, "checks": _checks,
		"refusal_evidence": _refusal_evidence, "refusal_notifications": _refusal_notifications,
		"keeper_distribution": _keeper_distribution_evidence,
		"engine": Engine.get_version_info()["string"], "physics": "Jolt Physics", "physics_hz": Engine.physics_ticks_per_second,
		"headless": true, "wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0}))
	quit(0 if failures.is_empty() and _completed else 1)


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_PREVIEW_TESTS_INCOMPLETE")
		quit(2)
