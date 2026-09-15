extends SceneTree

const Simulation = preload("res://match/simulation/match_simulation.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")

var _simulation: Simulation
var _checks: Array[Dictionary] = []
var _events: Array[Event] = []
var _refusals: Array[Dictionary] = []
var _contact_cases: Array[Dictionary] = []
var _shot_cases: Array[Dictionary] = []
var _expected_refusals: int = 0
var _started_ms: int = 0
var _completed: bool = false


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_ms > 120000:
		push_error("Match test watchdog: exceeded 120 seconds of wall time")
		quit(2)
	return false


func _run() -> void:
	var original_jolt_settings: Dictionary[StringName, Variant] = {}
	for key: StringName in Tuning.NATIVE_JOLT_PROFILE:
		original_jolt_settings[key] = ProjectSettings.get_setting(key)
	_simulation = Simulation.new()
	root.add_child(_simulation)
	_simulation.event_raised.connect(func(event: Event) -> void: _events.append(event))
	_simulation.command_rejected.connect(func(id: int, code: Error, message: String) -> void:
		_refusals.append({"actor_id": id, "code": code, "message": message}))
	await process_frame
	_check("world is headless, Jolt, 60 Hz", DisplayServer.get_name() == "headless" and
		ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics" and Engine.physics_ticks_per_second == 60)
	for key: StringName in original_jolt_settings:
		_check("private-world creation restores " + String(key), ProjectSettings.get_setting(key) == original_jolt_settings[key])
	_check("ready has four stable actors", _simulation.get_snapshot().phase == Snapshot.Phase.READY and
		_simulation.get_snapshot().actors.size() == 4)
	var ball: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	_check("production ball uses real rigid body and CCD", ball != null and ball.continuous_cd and
		is_equal_approx(ball.mass, Tuning.BALL_MASS))
	var sphere: SphereShape3D = ball.get_child(0).get("shape") as SphereShape3D
	_check("physical sphere matches exposed radius", sphere != null and is_equal_approx(sphere.radius, Tuning.BALL_RADIUS))
	for id: int in Simulation.ACTOR_IDS:
		var actor: Snapshot.ActorSnapshot = _simulation.get_snapshot().actor(id)
		_check("stable actor %d identity/team/role" % id, actor != null and actor.actor_id == id and
			actor.team_id == id % 2 and actor.role == (Snapshot.Role.FIELD if id < 2 else Snapshot.Role.KEEPER) and
			actor.attack_direction.x == (1.0 if id % 2 == 0 else -1.0) and actor.human_controlled == (id == 0))
	await _test_world_isolation()
	await _test_movement()
	await _test_validation()
	await _test_pause_reset_end()
	await _test_pass_return()
	await _test_kick_direction()
	await _test_tackle()
	await _test_boundaries()
	await _test_ai()
	await _test_contacts()
	await _test_shots()
	_simulation.queue_free()
	await process_frame
	_completed = true
	_finish()


func _test_world_isolation() -> void:
	var baseline: Snapshot = _state()
	var second: Simulation = Simulation.new()
	root.add_child(second)
	var first_ball: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	var second_ball: RigidBody3D = second.get_node("Ball") as RigidBody3D
	_check("authorities own separate real physics spaces", PhysicsServer3D.body_get_space(first_ball.get_rid()) !=
		PhysicsServer3D.body_get_space(second_ball.get_rid()))
	var setup: Setup = _empty_court()
	setup.ball_position = baseline.ball_position
	setup.ball_velocity = Vector3(-6.0, 0.0, 0.0)
	_check("second overlapping world starts through same API", second.start(setup) == OK)
	await _frames(22)
	_check("separate worlds do not collide or advance each other", second.get_snapshot().ball_position.x < -3.0 and
		_fingerprint(baseline) == _fingerprint(_state()))
	second.queue_free()
	await process_frame


func _test_movement() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	_begin("movement", setup)
	await _frames(4)
	_check("stationary human receives nearby ball", _state().ball_owner_id == 0)
	var start_position: Vector3 = _state().actor(0).position
	var command: Command = _command(0)
	command.move = Vector2.RIGHT
	_check("human movement accepted", _simulation.submit_human_command(command) == OK)
	command.move = Vector2.LEFT
	await _frames(1)
	_check("accepted command is copied and applies on next tick", _state().actor(0).velocity.x > 0.0 and
		_state().actor(0).last_command_tick < _state().tick)
	await _drive(0, Vector2.RIGHT, 15)
	_check("responsive bounded acceleration", _state().actor(0).position.x > start_position.x + 0.6 and
		_state().actor(0).velocity.x <= _simulation.tuning.move_speed + 0.02)
	_check("dribbling is physical and remains within leash", _state().ball_owner_id == 0 and
		_flat_distance(_state().actor(0).position, _state().ball_position) <= _simulation.tuning.control_leash)
	await _drive(0, Vector2.LEFT, 6)
	_check("opposite direction brakes before reversing", _state().actor(0).velocity.x <= 2.3)
	await _drive(0, Vector2.LEFT, 12)
	_check("direction reverses without teleport", _state().actor(0).velocity.x < -3.0)
	await _drive(0, Vector2.ZERO, 12)
	_check("neutral command brakes to rest", absf(_state().actor(0).velocity.x) < 0.02)
	await _drive(0, Vector2(0.0, 1.0), 30, true)
	_check("sprint reaches its bounded speed", absf(_state().actor(0).velocity.z - _simulation.tuning.sprint_speed) < 0.1)
	await _drive(0, Vector2(0.0, 1.0), 25, true, true)
	_check("close control overrides sprint", absf(_state().actor(0).velocity.z - _simulation.tuning.close_control_speed) < 0.1)
	await _frames(40)
	_check("stale input expires and brakes", Vector2(_state().actor(0).velocity.x, _state().actor(0).velocity.z).length() < 0.02)
	var snapshot: Snapshot = _state()
	snapshot.actors[0].position = Vector3(999.0, 999.0, 999.0)
	snapshot.ball_position = Vector3(999.0, 999.0, 999.0)
	_check("snapshots are detached from authority", _state().actor(0).position.length() < 30.0 and _state().ball_position.length() < 30.0)


func _test_validation() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	_begin("validation", setup)
	await _frames(4)
	var baseline: Snapshot = _state()
	_expect_refusal("null command", _simulation.submit_command(null), ERR_INVALID_PARAMETER)
	_expect_refusal("unknown actor", _simulation.submit_command(Command.new(99, 0)), ERR_DOES_NOT_EXIST)
	_expect_refusal("human cannot control AI", _simulation.submit_human_command(Command.new(1, 0)), ERR_UNAUTHORIZED)
	var command: Command = Command.new(0, -1)
	_expect_refusal("negative sequence", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.sequence = Command.MAX_SEQUENCE + 1
	_expect_refusal("out of range sequence", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command = _command(0)
	command.move = Vector2(NAN, 0.0)
	_expect_refusal("NaN movement", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.move = Vector2(2.0, 0.0)
	_expect_refusal("oversized movement", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.move = Vector2.ZERO
	command.aim = Vector2(INF, 0.0)
	_expect_refusal("infinite aim", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.aim = Vector2.ZERO
	command.shot_charge = 1.01
	_expect_refusal("oversized charge", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.shot_charge = NAN
	_expect_refusal("NaN charge", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.shot_charge = 0.0
	command.shot_lift = -0.1
	_expect_refusal("negative lift", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.shot_lift = 0.0
	command.set("action", 99)
	_expect_refusal("unknown action", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.action = Command.Action.PASS
	command.target_actor_id = 1
	_expect_refusal("opponent pass target", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.target_actor_id = 0
	_expect_refusal("self pass target", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	command.target_actor_id = 40
	_expect_refusal("unknown pass target", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	_check("invalid commands leave state unchanged", _fingerprint(baseline) == _fingerprint(_state()))
	command = _command(0)
	_check("valid neutral command", _simulation.submit_command(command) == OK)
	_expect_refusal("duplicate sequence", _simulation.submit_command(command), ERR_INVALID_PARAMETER)
	var invalid_setup: Setup = setup.copy()
	invalid_setup.ball_velocity = Vector3(33.0, 0.0, 0.0)
	baseline = _state()
	_expect_refusal("out of range drill velocity", _simulation.start(invalid_setup), ERR_INVALID_PARAMETER)
	invalid_setup = setup.copy()
	invalid_setup.actor_positions[0] = Vector3(NAN, 0.0, 0.0)
	_expect_refusal("NaN actor placement", _simulation.reset(invalid_setup), ERR_INVALID_PARAMETER)
	invalid_setup = setup.copy()
	invalid_setup.actor_positions[1] = invalid_setup.actor_positions[0]
	_expect_refusal("overlapping actor placement", _simulation.reset(invalid_setup), ERR_INVALID_PARAMETER)
	invalid_setup = setup.copy()
	invalid_setup.ai_actor_ids = [2, 2]
	_expect_refusal("duplicate AI IDs", _simulation.reset(invalid_setup), ERR_INVALID_PARAMETER)
	invalid_setup = setup.copy()
	invalid_setup.ball_position = Vector3(20.0, 0.7, 1.54)
	_expect_refusal("ball inside post", _simulation.reset(invalid_setup), ERR_INVALID_PARAMETER)
	_simulation.tuning.acceleration = INF
	_expect_refusal("invalid tuning", _simulation.start(setup), ERR_INVALID_PARAMETER)
	_simulation.tuning.acceleration = 28.0
	_check("invalid reset is atomic", _fingerprint(baseline) == _fingerprint(_state()))
	var shot: Command = _command(0)
	shot.action = Command.Action.SHOOT
	shot.aim = Vector2.RIGHT
	_check("one shot can queue", _simulation.submit_command(shot) == OK)
	shot.sequence += 1
	_expect_refusal("second queued action is explicit busy", _simulation.submit_command(shot), ERR_BUSY)
	var movement: Command = _command(0)
	movement.move = Vector2.RIGHT
	_check("movement can update behind queued action", _simulation.submit_command(movement) == OK)
	await _frames(2)
	_check("movement update cannot erase shot edge", _count(Event.Kind.SHOT) == 1 and _state().ball_owner_id == -1)
	shot = _command(0)
	shot.action = Command.Action.SHOOT
	_expect_refusal("action cooldown", _simulation.submit_command(shot), ERR_BUSY)
	await _frames(30)
	shot = _command(0)
	shot.action = Command.Action.SHOOT
	_expect_refusal("kick cannot manufacture possession", _simulation.submit_command(shot), ERR_UNAVAILABLE)
	_check("refusals carry actionable messages", not _refusals.is_empty() and
		_refusals.all(func(item: Dictionary) -> bool: return not String(item["message"]).is_empty()))


func _test_pause_reset_end() -> void:
	var setup: Setup = _empty_court()
	setup.ai_actor_ids = [1, 2, 3]
	setup.ball_position = Vector3(0.0, 1.5, 4.0)
	setup.ball_velocity = Vector3(7.0, 2.0, -2.0)
	setup.ball_angular_velocity = Vector3(5.0, 30.0, 80.0)
	_begin("pause", setup)
	await _drive(0, Vector2.RIGHT, 5)
	_check("pause succeeds", _simulation.set_paused(true) == OK)
	var paused: Snapshot = _state()
	var ball: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	var physical_pose: Transform3D = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_check("pause is idempotent", _simulation.set_paused(true) == OK)
	_expect_refusal("paused command", _simulation.submit_human_command(_command(0)), ERR_UNAVAILABLE)
	await _frames(60)
	var physical_after: Transform3D = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_check("pause freezes native physics, not just cached snapshots", physical_pose.is_equal_approx(physical_after) and
		PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) == Vector3.ZERO and
		PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) == Vector3.ZERO)
	_check("pause freezes ball, athletes, AI, clock, cooldowns and ticks", _fingerprint(paused) == _fingerprint(_state()))
	if _fingerprint(paused) != _fingerprint(_state()):
		print("PAUSE_DIAGNOSTIC before=", _fingerprint(paused), " after=", _fingerprint(_state()))
	_check("resume succeeds", _simulation.set_paused(false) == OK)
	await _frames(3)
	_check("resume restores physical flight", _state().ball_position.distance_to(paused.ball_position) > 0.1 and
		_state().ball_velocity.x > 5.0 and _state().ball_angular_velocity.length() > 80.0 and
		_state().seconds_remaining < paused.seconds_remaining)
	_check("reset enters ready", _simulation.reset() == OK and _state().phase == Snapshot.Phase.READY)
	var reset_state: Snapshot = _state()
	await _frames(30)
	_check("ready is physically frozen", _fingerprint(reset_state) == _fingerprint(_state()))
	_check("reset clears all command/possession/score state", reset_state.score == Vector2i.ZERO and
		reset_state.tick == 0 and reset_state.ball_owner_id == -1 and reset_state.last_touch_actor_id == -1 and
		reset_state.actor(0).last_command_sequence == -1 and reset_state.actor(0).action_cooldown == 0.0)
	_check("reset is repeatable on this platform", _simulation.reset() == OK and _fingerprint(reset_state) == _fingerprint(_state()))
	var kickoff: Setup = Setup.new()
	kickoff.ai_actor_ids = []
	_begin("reset clears queued actions", kickoff)
	await _frames(4)
	var pending: Command = _command(0)
	pending.action = Command.Action.SHOOT
	pending.shot_charge = 1.0
	_check("shot queued before reset", _simulation.submit_command(pending) == OK)
	_check("reset cancels queued shot", _simulation.reset(kickoff) == OK)
	_begin("new start after cancelled shot", kickoff)
	await _frames(8)
	_check("no stale shot or velocity survives restart", _count(Event.Kind.SHOT) == 0 and _state().ball_owner_id == 0 and
		_state().ball_velocity.length() < 0.2 and _state().actor(0).last_command_sequence == -1)
	var tune: Tuning = Tuning.new()
	tune.training_seconds = 0.25
	_begin("terminal timer", _empty_court(), tune)
	await _frames(24)
	var finished: Snapshot = _state()
	_check("training timer ends exactly once", finished.phase == Snapshot.Phase.FINISHED and
		finished.seconds_remaining == 0.0 and _count(Event.Kind.END) == 1)
	await _frames(30)
	_check("terminal state stays frozen", _fingerprint(finished) == _fingerprint(_state()) and _count(Event.Kind.END) == 1)
	_expect_refusal("terminal command", _simulation.submit_command(_command(0)), ERR_UNAVAILABLE)


func _test_pass_return() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = [2]
	setup.actor_positions[0] = Vector3(-8.0, 0.0, 2.0)
	setup.actor_positions[1] = Vector3(8.0, 0.0, 6.0)
	var to_keeper: Vector2 = Vector2(-10.5, -2.0).normalized()
	setup.actor_forwards[0] = to_keeper
	setup.ball_position = setup.actor_positions[0] + Vector3(to_keeper.x * 0.55, 0.12, to_keeper.y * 0.55)
	_begin("pass and return", setup)
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.PASS
	command.aim = to_keeper
	command.target_actor_id = 2
	_check("human pass accepted", _simulation.submit_human_command(command) == OK)
	var keeper_received: bool = false
	var returned: bool = false
	var human_received: bool = false
	for frame: int in range(420):
		await _frames(1)
		keeper_received = keeper_received or _state().ball_owner_id == 2
		if keeper_received:
			break
	_check("keeper physically receives teammate pass", keeper_received)
	await _frames(45)
	_check("controlled keeper waits for human distribution", _state().selected_actor_id == 2 and _count(Event.Kind.PASS, 2) == 0 and
		_state().ai_intent_actor_ids == [2] and _state().ai_actor_ids.is_empty())
	command = _command(2)
	command.action = Command.Action.PASS
	_check("human keeper can return a neutral pass", _simulation.submit_human_command(command) == OK)
	for frame: int in range(420):
		await _frames(1)
		returned = _count(Event.Kind.PASS, 2) > 0
		if returned and _state().ball_owner_id == 0:
			human_received = true
			break
	_check("manual distribution restores field focus through a legal pass", returned and _count(Event.Kind.PASS, 0) == 1 and
		_state().selected_actor_id == 0)
	_check("human can receive goalkeeper return", human_received)
	_check("keeper return generates no invalid AI commands", _refusals.is_empty())
	_check("return pass has the human target", _events.any(func(event: Event) -> bool:
		return event.kind == Event.Kind.PASS and event.actor_id == 2 and event.target_actor_id == 0))
	if not human_received:
		print("PASS_RETURN_DIAGNOSTIC ", _diagnostic())
	var default_setup: Setup = Setup.new()
	default_setup.ai_actor_ids = [2]
	_begin("kickoff-distance goalkeeper return", default_setup)
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.LEFT
	command.target_actor_id = 2
	_check("back pass from default kickoff is accepted", _simulation.submit_human_command(command) == OK)
	human_received = false
	var keeper_return_sent: bool = false
	for frame: int in range(420):
		await _frames(1)
		if _state().ball_owner_id == 2 and not keeper_return_sent:
			command = _command(2)
			command.action = Command.Action.PASS
			keeper_return_sent = _simulation.submit_human_command(command) == OK
		if keeper_return_sent and _state().selected_actor_id == 0 and _state().ball_owner_id != 0:
			var receive_command: Command = _command(0)
			receive_command.aim = Vector2.LEFT
			_simulation.submit_human_command(receive_command)
		if _count(Event.Kind.PASS, 2) == 1 and _state().ball_owner_id == 0:
			human_received = true
			break
	_check("default kickoff permits pass and goalkeeper return", human_received and _count(Event.Kind.PASS, 0) == 1)
	if not human_received:
		print("KICKOFF_RETURN_DIAGNOSTIC ", _diagnostic())
	for from_default: bool in [false, true]:
		var ai_setup: Setup = default_setup.copy() if from_default else setup.copy()
		ai_setup.ball_position = ai_setup.actor_positions[2] + Vector3(0.55, 0.12, 0.0)
		ai_setup.actor_forwards[0] = Vector2.LEFT
		_begin("nonselected keeper AI return default=%s" % from_default, ai_setup)
		var received: bool = false
		for frame: int in range(420):
			await _frames(1)
			if _count(Event.Kind.PASS, 2) > 0 and _state().ball_owner_id == 0:
				received = true
				break
		_check("nonselected keeper still distributes through AI (default_kickoff=%s)" % from_default,
			_count(Event.Kind.PASS, 2) == 1 and received and _refusals.is_empty())
		_check("AI return never changes human focus (default_kickoff=%s)" % from_default,
			_state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)


func _test_kick_direction() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	_begin("bounded pass assistance", setup)
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.RIGHT
	command.target_actor_id = 2
	_check("pass can be aimed away from teammate", _simulation.submit_human_command(command) == OK)
	await _frames(5)
	_check("assistance cannot turn a pass through 180 degrees", _state().ball_velocity.x > 3.0 and
		_events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.PASS and event.target_actor_id == -1))
	_begin("backward pass without self collision", setup)
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.PASS
	command.aim = Vector2.LEFT
	command.target_actor_id = 2
	_check("backward pass is accepted", _simulation.submit_human_command(command) == OK)
	await _frames(18)
	_check("striking foot clearance permits a real backward pass", _state().ball_position.x < -4.0 and _state().ball_velocity.x < -3.0)
	var drill: Setup = _empty_court()
	drill.actor_positions[0] = Vector3.ZERO
	drill.ball_position = Vector3(0.55, 0.12, 0.0)
	_begin("charged loft and real spin", drill)
	await _frames(4)
	command = _command(0)
	command.action = Command.Action.SHOOT
	command.shot_charge = 1.0
	command.shot_lift = 1.0
	_check("charged loft shot uses facing without aim", _simulation.submit_human_command(command) == OK)
	await _frames(3)
	_check("loft and angular motion are physical and bounded", _state().ball_position.y > 0.2 and
		_state().ball_velocity.y > 4.5 and _state().ball_velocity.x > 20.0 and
		_state().ball_angular_velocity.length() > 150.0 and _state().ball_angular_velocity.length() <= 400.0)


func _test_tackle() -> void:
	var setup: Setup = _empty_court()
	setup.actor_positions[0] = Vector3.ZERO
	setup.actor_positions[1] = Vector3(1.3, 0.0, 0.0)
	setup.actor_forwards[1] = Vector2.LEFT
	setup.ball_position = Vector3(0.55, 0.12, 0.0)
	_begin("standing tackle", setup)
	await _frames(4)
	_check("tackle fixture starts with human possession", _state().ball_owner_id == 0)
	var before: Vector3 = _state().actor(1).position
	var command: Command = _command(1)
	command.action = Command.Action.TACKLE
	command.aim = Vector2.LEFT
	_check("opponent standing tackle accepted", _simulation.submit_command(command) == OK)
	await _frames(2)
	_check("legal tackle knocks ball loose, never teleports athlete", _state().ball_owner_id == -1 and
		_state().actor(1).position.distance_to(before) < 0.03 and _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.TACKLE and event.success))
	setup.actor_positions[1] = Vector3(6.0, 0.0, 0.0)
	_begin("distant tackle", setup)
	await _frames(4)
	command = _command(1)
	command.action = Command.Action.TACKLE
	_check("a distant tackle attempt is legal input", _simulation.submit_command(command) == OK)
	await _frames(2)
	_check("distant tackle misses without remote steal", _state().ball_owner_id == 0 and
		_events.any(func(event: Event) -> bool: return event.kind == Event.Kind.TACKLE and not event.success) and
		_count(Event.Kind.FOUL) == 0 and _state().accumulated_fouls == Vector2i.ZERO)


func _test_boundaries() -> void:
	var setup: Setup = _empty_court()
	setup.ball_position = Vector3(20.0 + Tuning.BALL_RADIUS - 0.02, 0.4, 0.0)
	_begin("partial goal crossing", setup)
	await _frames(8)
	_check("partial ball crossing is not a goal", _state().score == Vector2i.ZERO and _state().phase == Snapshot.Phase.PLAYING)
	setup.ball_position = Vector3(19.7, 0.4, 0.0)
	setup.ball_velocity = Vector3(12.0, 0.0, 0.0)
	setup.ball_angular_velocity = Vector3(0.0, 0.0, -12.0 / Tuning.BALL_RADIUS)
	_begin("complete goal crossing", setup)
	await _frames(8)
	_check("complete positive-end crossing awards home only", _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	_check("goal has a distinct pause phase", _state().phase == Snapshot.Phase.GOAL_PAUSE)
	var goal_clock: float = _state().seconds_remaining
	var ball: RigidBody3D = _simulation.get_node("Ball") as RigidBody3D
	var goal_velocity: Vector3 = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var goal_spin: Vector3 = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	_check("goal pause starts with real moving and spinning ball", goal_velocity.length() > 5.0 and goal_spin.length() > 80.0)
	_check("goal pause itself can be paused", _simulation.set_paused(true) == OK)
	var paused: Snapshot = _state()
	await _frames(30)
	_check("pausing goal follow-through really freezes physics", _fingerprint(paused) == _fingerprint(_state()))
	if _fingerprint(paused) != _fingerprint(_state()):
		print("GOAL_PAUSE_DIAGNOSTIC before=", _fingerprint(paused), " after=", _fingerprint(_state()))
	_check("goal pause resumes correctly", _simulation.set_paused(false) == OK and _state().phase == Snapshot.Phase.GOAL_PAUSE)
	var resumed_velocity: Vector3 = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var resumed_spin: Vector3 = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	_check("goal resume restores native linear and angular motion", not ball.freeze and
		resumed_velocity.is_equal_approx(goal_velocity) and resumed_spin.is_equal_approx(goal_spin))
	await _frames(25)
	_check("resumed goal flight moves and rebounds off the net", _state().ball_position.distance_to(paused.ball_position) > 0.1 and
		_state().ball_velocity.x < -0.5 and _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.BALL_CONTACT and event.reason == &"net"))
	_check("goal cannot duplicate on net rebound and clock is stopped", _count(Event.Kind.GOAL) == 1 and _state().seconds_remaining == goal_clock)
	await _frames(60)
	_check("goal restart preserves score and gives conceding field player kickoff", _state().score == Vector2i(1, 0) and
		_state().phase == Snapshot.Phase.PLAYING and _state().ball_owner_id == 1 and _count(Event.Kind.GOAL) == 1)
	var fresh: Setup = _empty_court()
	fresh.ball_position = Vector3(-19.5, 0.4, 0.0)
	fresh.ball_velocity = Vector3(-32.0, 0.0, 0.0)
	_begin("maximum speed negative goal", fresh)
	await _frames(8)
	_check("maximum speed opposite goal awards away only", _state().score == Vector2i(0, 1) and _count(Event.Kind.GOAL) == 1)
	var misses: Array[Dictionary] = [
		{"name": "above crossbar", "position": Vector3(19.5, 2.4, 0.0), "velocity": Vector3(32.0, 0.0, 0.0)},
		{"name": "outside posts", "position": Vector3(19.5, 0.5, 2.2), "velocity": Vector3(32.0, 0.0, 0.0)},
		{"name": "from behind goal", "position": Vector3(20.7, 0.5, 0.0), "velocity": Vector3(-4.0, 0.0, 0.0)},
		{"name": "touchline crossing", "position": Vector3(0.0, 0.5, 9.8), "velocity": Vector3(0.0, 0.0, 20.0)},
		{"name": "whole ball not inside post aperture", "position": Vector3(20.085, 0.5, 1.40), "velocity": Vector3(4.0, 0.0, 0.0)},
	]
	for item: Dictionary in misses:
		var drill: Setup = _empty_court()
		drill.ball_position = item["position"]
		drill.ball_velocity = item["velocity"]
		_begin(String(item["name"]), drill)
		await _frames(15)
		_check(String(item["name"]) + " gives no false goal", _state().score == Vector2i.ZERO and _count(Event.Kind.GOAL) == 0)
		_check(String(item["name"]) + " explicitly awards a localized restart", _state().phase == Snapshot.Phase.RESTART_PAUSE and
			_events.any(func(event: Event) -> bool: return event.kind == Event.Kind.RESTART_CHANGED and event.reason == &"awarded"))
		if item["name"] == "touchline crossing":
			_check("training out can be user-paused", _simulation.set_paused(true) == OK)
			var paused_out: Snapshot = _state()
			await _frames(10)
			_check("user pause also freezes the out countdown", _fingerprint(paused_out) == _fingerprint(_state()))
			_check("out resume restores its restart phase", _simulation.set_paused(false) == OK and
				_state().phase == Snapshot.Phase.RESTART_PAUSE)
			var out_transform: Transform3D = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			await _frames(4)
			var out_after: Transform3D = PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			_check("out resume keeps native ball frozen until a legal restart launch", ball.freeze and out_transform.is_equal_approx(out_after) and
				PhysicsServer3D.body_get_state(ball.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) == Vector3.ZERO)
		await _take_local_restart(String(item["name"]))
		_check(String(item["name"]) + " resumes through a physical launch without a centre reset", _state().phase == Snapshot.Phase.PLAYING and
			_state().restart.stage == Types.RestartStage.IN_PLAY and _state().ball_position.distance_to(_state().restart.spot) < 1.0)
	fresh = _empty_court()
	fresh.actor_positions[0] = Vector3(-13.0, 0.0, 0.0)
	fresh.actor_forwards[0] = Vector2.LEFT
	fresh.ball_position = Vector3(-13.55, 0.12, 0.0)
	_begin("own goal", fresh)
	await _frames(4)
	var own_goal: Command = _command(0)
	own_goal.action = Command.Action.SHOOT
	own_goal.aim = Vector2.LEFT
	own_goal.shot_charge = 0.8
	_check("own-goal shot uses production command", _simulation.submit_human_command(own_goal) == OK)
	await _frames(30)
	_check("last touch does not decide scoring team", _state().score == Vector2i(0, 1) and
		_events.any(func(event: Event) -> bool: return (event.kind == Event.Kind.GOAL and event.actor_id == 0 and
			event.team_id == 1 and event.reason == &"own_goal")))


func _test_ai() -> void:
	var setup: Setup = Setup.new()
	setup.actor_positions[0] = Vector3(-10.0, 0.0, 7.0)
	setup.actor_positions[1] = Vector3(4.0, 0.0, 0.0)
	setup.ball_position = Vector3(1.0, 0.12, 2.0)
	_begin("autonomous rival", setup)
	var initial_rival: Vector3 = _state().actor(1).position
	var recovered: bool = false
	var moved: bool = false
	var legal_speeds: bool = true
	var keeper_moved: bool = false
	for frame: int in range(900):
		await _frames(1)
		var state: Snapshot = _state()
		moved = moved or state.actor(1).position.distance_to(initial_rival) > 2.0
		recovered = recovered or state.ball_owner_id == 1
		keeper_moved = keeper_moved or absf(state.actor(2).position.z) > 0.05 or absf(state.actor(2).position.x + 18.5) > 0.2
		legal_speeds = legal_speeds and Vector2(state.actor(1).velocity.x, state.actor(1).velocity.z).length() <= 8.01
		if _count(Event.Kind.SHOT, 1) > 0:
			break
	_check("rival autonomously approaches loose ball", moved)
	_check("rival controls recovered ball", recovered)
	_check("rival takes legal production shot", _count(Event.Kind.SHOT, 1) > 0)
	_check("AI uses same bounded locomotion", legal_speeds)
	_check("keeper reacts with real movement", keeper_moved)
	_check("rival AI generates no invalid commands", _refusals.is_empty())
	if _count(Event.Kind.SHOT, 1) == 0:
		print("AI_DIAGNOSTIC ", _diagnostic())
	setup = _empty_court()
	setup.actor_positions[0] = Vector3(12.0, 0.0, 0.0)
	setup.actor_positions[3] = Vector3(18.5, 0.0, 0.0)
	setup.ai_actor_ids = [3]
	setup.ball_position = Vector3(12.55, 0.12, 0.0)
	_begin("keeper saves real shot", setup)
	await _frames(4)
	var command: Command = _command(0)
	command.action = Command.Action.SHOOT
	command.aim = Vector2.RIGHT
	command.shot_charge = 0.65
	command.shot_lift = 0.30
	_check("save fixture launches actual shot", _simulation.submit_human_command(command) == OK)
	await _frames(120)
	_check("keeper saves actual opponent shot once", _count(Event.Kind.SAVE, 3) == 1 and _count(Event.Kind.GOAL) == 0)
	_check("save is grounded in collect/body contact", _events.any(func(event: Event) -> bool:
		return event.kind == Event.Kind.SAVE and event.reason in [&"collected", &"body_contact"]))
	if _count(Event.Kind.SAVE, 3) != 1:
		print("SAVE_DIAGNOSTIC ", _diagnostic())
	setup = Setup.new()
	setup.ai_actor_ids = [1]
	setup.actor_positions[0] = Vector3(12.0, 0.0, 0.0)
	setup.actor_positions[1] = Vector3(8.0, 0.0, 2.0)
	setup.ball_position = Vector3(12.55, 0.12, 0.0)
	_begin("rival goal-side defence", setup)
	await _frames(30)
	_check("rival recovers toward its goal side against possession", _state().actor(1).position.x > 10.0 and
		_count(Event.Kind.SHOT, 1) == 0)
	setup = _empty_court()
	setup.ai_actor_ids = [3]
	setup.actor_positions[3] = Vector3(18.5, 0.0, 3.0)
	setup.ball_position = Vector3(19.3, 0.7, 0.0)
	setup.ball_velocity = Vector3(32.0, 0.0, 0.0)
	_begin("keeper cannot warp to distant shot", setup)
	await _frames(10)
	_check("keeper cannot make a remote save", _count(Event.Kind.GOAL) == 1 and _count(Event.Kind.SAVE) == 0 and
		_state().actor(3).position.z > 2.0)
	setup = _empty_court()
	setup.actor_positions[0] = Vector3.ZERO
	setup.ball_position = Vector3(2.0, 0.12, 0.0)
	setup.ai_actor_ids = [0]
	_begin("original field player becomes real micro AI after focus leaves", setup)
	command = _command(0)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("micro input switches from original field to keeper", _simulation.submit_human_command(command) == OK)
	recovered = false
	for frame: int in range(180):
		await _frames(1)
		if _state().ball_owner_id == 0:
			recovered = true
			break
	_check("former human physically recovers under intended AI", recovered and _state().selected_actor_id == 2 and
		_state().ai_actor_ids == [0] and _state().actor(0).last_command_sequence > command.sequence)
	await _frames(12)
	_check("micro home AI protects possession without tackling itself", _state().ball_owner_id == 0 and _count(Event.Kind.TACKLE, 0) == 0)
	for frame: int in range(360):
		if _count(Event.Kind.PASS, 0) > 0:
			break
		await _frames(1)
	_check("former human distributes through a real kick without autonomous finishing", _count(Event.Kind.PASS, 0) == 1 and
		_count(Event.Kind.SHOT, 0) == 0 and _state().actor(0).position.distance_to(setup.actor_positions[0]) > 0.5 and
		_state().selected_actor_id == 2 and _refusals.is_empty())


func _test_contacts() -> void:
	var cases: Array[Dictionary] = []
	for height: float in [0.35, 0.6, 1.0, 1.5, 2.2, 3.1]:
		cases.append({"id": "floor_%.2f" % height, "surface": &"floor",
			"position": Vector3(-3.0 + height, height, 4.0), "velocity": Vector3(height, 0.0, 0.2),
			"frames": 100, "goal": false, "sign": 0.0})
	var fast_floor_cases: Array[Dictionary] = [
		{"position": Vector3(-4.0, 1.0, 4.0), "velocity": Vector3(31.5, -5.0, 0.0)},
		{"position": Vector3(0.0, 3.0, 4.0), "velocity": Vector3(0.0, -32.0, 0.0)},
		{"position": Vector3(0.0, 6.0, 4.0), "velocity": Vector3(0.0, -32.0, 0.0)},
		{"position": Vector3(3.0, 1.0, -4.0), "velocity": Vector3(0.0, -5.0, -31.5)},
	]
	for index: int in fast_floor_cases.size():
		var item: Dictionary = fast_floor_cases[index].duplicate()
		item.merge({"id": "fast_floor_%d" % index, "surface": &"floor", "frames": 100, "goal": false, "sign": 0.0})
		cases.append(item)
	for sign_value: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			for speed: float in [12.0, 32.0]:
				cases.append({"id": "post_%d_%d_%d" % [sign_value, side, speed], "surface": &"post",
					"position": Vector3(sign_value * 18.8, 0.8, side * 1.54), "velocity": Vector3(sign_value * speed, 0.0, 0.0),
					"frames": 24, "goal": false, "sign": sign_value})
		for speed: float in [12.0, 32.0]:
			cases.append({"id": "bar_%d_%d" % [sign_value, speed], "surface": &"crossbar",
				"position": Vector3(sign_value * 19.0, 2.04, 0.0), "velocity": Vector3(sign_value * speed, 0.0, 0.0),
				"frames": 24, "goal": false, "sign": sign_value})
		cases.append({"id": "net_%d" % sign_value, "surface": &"net",
			"position": Vector3(sign_value * 19.25, 0.7, 0.0), "velocity": Vector3(sign_value * 32.0, 0.0, 0.0),
			"frames": 35, "goal": true, "sign": sign_value})
	for item: Dictionary in cases:
		var setup: Setup = _empty_court()
		setup.ball_position = item["position"]
		setup.ball_velocity = item["velocity"]
		_begin(String(item["id"]), setup)
		var min_height: float = setup.ball_position.y
		var max_signed_x: float = 0.0
		var bounced: bool = false
		var finite: bool = true
		for frame: int in int(item["frames"]):
			await _frames(1)
			var state: Snapshot = _state()
			min_height = minf(min_height, state.ball_position.y)
			max_signed_x = maxf(max_signed_x, state.ball_position.x * float(item["sign"]))
			if item["surface"] == &"floor":
				bounced = bounced or state.ball_velocity.y > 0.1
			else:
				bounced = bounced or state.ball_velocity.x * float(item["sign"]) < -0.5
			finite = finite and state.ball_position.is_finite() and state.ball_velocity.is_finite() and state.ball_velocity.length() <= 32.01
		var contact: bool = _events.any(func(event: Event) -> bool:
			return event.kind == Event.Kind.BALL_CONTACT and event.reason == item["surface"])
		var goals: int = _count(Event.Kind.GOAL)
		var correct_goal: bool = goals == (1 if bool(item["goal"]) else 0)
		var no_tunnel: bool = min_height >= Tuning.BALL_RADIUS - 0.025
		if item["surface"] == &"net":
			no_tunnel = no_tunnel and max_signed_x <= 21.5
		elif item["surface"] in [&"post", &"crossbar"]:
			no_tunnel = no_tunnel and max_signed_x < 20.0
		var passed: bool = contact and bounced and finite and correct_goal and no_tunnel
		var result: Dictionary = {"id": item["id"], "surface": item["surface"], "passed": passed,
			"contact": contact, "bounced": bounced, "goals": goals, "min_y": min_height, "max_signed_x": max_signed_x,
			"setup": [str(setup.ball_position), str(setup.ball_velocity)]}
		_contact_cases.append(result)
		_check("distinct contact trajectory " + String(item["id"]), passed)
		if not passed:
			print("CONTACT_DIAGNOSTIC ", JSON.stringify(result), " ", _diagnostic())
	_check("contact matrix has at least 20 genuinely distinct setups", _contact_cases.size() >= 20 and
		_unique_ids(_contact_cases) == cases.size() and _unique_setups(_contact_cases) == cases.size())


func _test_shots() -> void:
	var targets: Array[float] = [-1.54, -0.85, 0.0, 0.85, 1.54]
	for charge_index: int in range(10):
		for lane: int in targets.size():
			var charge: float = float(charge_index) / 9.0
			var post_shot: bool = lane == 0 or lane == 4
			var setup: Setup = _empty_court()
			var from_z: float = targets[lane] if post_shot else float(lane - 2) * 2.5
			setup.actor_positions[0] = Vector3(12.0 + float(charge_index % 3) * 0.25, 0.0, from_z)
			var goal: Vector3 = Vector3(20.0, 0.0, targets[lane])
			var aim: Vector2 = Vector2(goal.x - setup.actor_positions[0].x, goal.z - from_z).normalized()
			setup.actor_forwards[0] = aim
			setup.ball_position = setup.actor_positions[0] + Vector3(aim.x * 0.55, 0.12, aim.y * 0.55)
			var id: String = "shot_charge_%d_lane_%d" % [charge_index, lane]
			_begin(id, setup)
			await _frames(4)
			var command: Command = _command(0)
			command.action = Command.Action.SHOOT
			command.aim = aim
			command.shot_charge = charge
			var accepted: bool = _simulation.submit_human_command(command) == OK
			var min_y: float = setup.ball_position.y
			var max_signed_x: float = setup.ball_position.x
			var post_contact: bool = false
			var bounded: bool = true
			for frame: int in range(140):
				await _frames(1)
				var state: Snapshot = _state()
				min_y = minf(min_y, state.ball_position.y)
				max_signed_x = maxf(max_signed_x, state.ball_position.x)
				bounded = bounded and state.ball_velocity.is_finite() and state.ball_velocity.length() <= 32.01
				post_contact = post_contact or _events.any(func(event: Event) -> bool:
					return event.kind == Event.Kind.BALL_CONTACT and event.reason == &"post")
				if state.phase == Snapshot.Phase.GOAL_PAUSE or (post_contact and state.ball_velocity.x < -0.5):
					break
			await _frames(24)
			var goals: int = _count(Event.Kind.GOAL)
			var shots: int = _count(Event.Kind.SHOT, 0)
			var launch_speed: float = 0.0
			for event: Event in _events:
				if event.kind == Event.Kind.SHOT:
					launch_speed = event.velocity.length()
			var expected_speed: float = lerpf(9.0, 28.0, charge)
			var scoring_ok: bool = (post_contact and goals == 0 and max_signed_x < 20.0) if post_shot else (goals == 1 and _state().score == Vector2i(1, 0))
			var passed: bool = accepted and shots == 1 and scoring_ok and bounded and min_y >= Tuning.BALL_RADIUS - 0.025 and absf(launch_speed - expected_speed) < 0.02
			var result: Dictionary = {"id": id, "passed": passed, "charge": charge, "aim": [aim.x, aim.y],
				"launch_speed": launch_speed, "post_contact": post_contact, "goals": goals, "min_y": min_y,
				"setup": [str(setup.actor_positions[0]), str(aim), charge]}
			_shot_cases.append(result)
			_check("distinct production " + id, passed)
			if not passed:
				print("SHOT_DIAGNOSTIC ", JSON.stringify(result), " ", _diagnostic())
	_check("shot matrix has 50 genuinely distinct setups", _shot_cases.size() == 50 and
		_unique_ids(_shot_cases) == 50 and _unique_setups(_shot_cases) == 50)


func _begin(label: String, setup: Setup, custom_tuning: Tuning = null) -> void:
	_events.clear()
	_refusals.clear()
	_simulation.tuning = Tuning.new() if custom_tuning == null else custom_tuning
	var result: Error = _simulation.start(setup)
	_check("start " + label, result == OK)
	if result != OK:
		print("START_ERROR ", _simulation.last_error)


func _empty_court() -> Setup:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	setup.actor_positions = {
		0: Vector3(-8.0, 0.0, -8.0), 1: Vector3(8.0, 0.0, -8.0),
		2: Vector3(-18.5, 0.0, 8.0), 3: Vector3(18.5, 0.0, 8.0),
	}
	setup.ball_position = Vector3(0.0, 0.12, 0.0)
	return setup


func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame


func _take_local_restart(label: String) -> void:
	for frame: int in range(140):
		if _state().phase != Snapshot.Phase.RESTART_PAUSE or _state().restart.stage == Types.RestartStage.READY:
			break
		await _frames(1)
	_check(label + " reaches localized READY without renderer acknowledgement", _state().phase == Snapshot.Phase.RESTART_PAUSE and _state().restart.stage == Types.RestartStage.READY)
	if _state().phase != Snapshot.Phase.RESTART_PAUSE or _state().restart.stage != Types.RestartStage.READY:
		return
	var command: Command = _command(_state().restart.taker_actor_id)
	command.action = Command.Action.KEEPER_THROW if _state().restart.kind == Types.RestartKind.GOAL_CLEARANCE else Command.Action.PASS
	if _state().restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		command.action = Command.Action.SHOOT
		command.aim = Vector2(_state().actor(command.actor_id).attack_direction.x, 0.0)
	_check(label + " executes the legal restart through production authority", _simulation.submit_command(command) == OK)
	await _frames(2)


func _drive(id: int, move: Vector2, frames: int, sprint: bool = false, close: bool = false) -> void:
	var accepted: bool = true
	for frame: int in frames:
		var command: Command = _command(id)
		command.move = move
		command.sprint = sprint
		command.close_control = close
		accepted = (_simulation.submit_command(command) == OK) and accepted
		await _frames(1)
	_check("continuous drive accepts %d commands (actor=%d move=%s sprint=%s close_control=%s)" %
		[frames, id, str(move), sprint, close], accepted)


func _command(id: int) -> Command:
	return Command.new(id, _state().actor(id).last_command_sequence + 1)


func _state() -> Snapshot:
	return _simulation.get_snapshot()


func _count(kind: Event.Kind, actor_id: int = -1) -> int:
	var result: int = 0
	for event: Event in _events:
		if event.kind == kind and (actor_id == -1 or event.actor_id == actor_id):
			result += 1
	return result


func _unique_ids(cases: Array[Dictionary]) -> int:
	var ids: Dictionary = {}
	for item: Dictionary in cases:
		ids[item["id"]] = true
	return ids.size()


func _unique_setups(cases: Array[Dictionary]) -> int:
	var setups: Dictionary = {}
	for item: Dictionary in cases:
		setups[JSON.stringify(item["setup"])] = true
	return setups.size()


func _expect_refusal(label: String, actual: Error, expected: Error) -> void:
	_expected_refusals += 1
	_check("expected refusal: " + label, actual == expected and not _simulation.last_error.is_empty() and
		not _refusals.is_empty() and int(_refusals[-1]["code"]) == expected)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _fingerprint(state: Snapshot) -> Array:
	var result: Array = [state.mode, state.selected_actor_id, state.ai_intent_actor_ids, state.ai_actor_ids, state.tick, state.phase, state.resume_phase, state.score, state.seconds_remaining,
		state.phase_seconds_remaining, state.ball_position, state.ball_velocity, state.ball_rotation,
		state.ball_angular_velocity, state.ball_owner_id, state.last_touch_actor_id, state.last_touch_tick,
		state.training_exercise, state.accumulated_fouls, state.period_state, state.extended_restart_id, state.extended_kick_event_id,
		state.last_pass_actor_id, state.last_pass_target_actor_id, state.last_pass_tick, state.human_control_context,
		state.human_allowed_actions, state.selected_can_move]
	var restart: Types.RestartState = state.restart
	result.append([restart.id, restart.kind, restart.stage, restart.launch_contact_id, restart.awarded_team_id, restart.taker_actor_id, restart.spot,
		restart.offence_spot, restart.border, restart.spot_choice, restart.has_spot_choice, restart.stage_started_tick,
		restart.placement_end_tick, restart.ready_tick, restart.deadline_tick, restart.minimum_opponent_distance,
		restart.direct_opponent_goal_allowed, restart.requires_direct_shot, restart.other_actor_touched])
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.position, actor.velocity, actor.forward, actor.action_cooldown,
			actor.last_command_sequence, actor.last_command_tick, actor.close_control, actor.spawn_position,
			actor.ball_contact_reachable, actor.ball_in_hands, actor.gesture_kind, actor.gesture_started_tick,
			actor.gesture_duration_ticks, actor.gesture_direction, actor.gesture_contact_position])
	return result


func _diagnostic() -> String:
	var state: Snapshot = _state()
	var events: Array[Dictionary] = []
	for event: Event in _events:
		if event.kind != Event.Kind.BALL_CONTACT or event.reason != &"floor":
			events.append({"kind": event.kind, "actor": event.actor_id, "reason": event.reason,
				"position": str(event.position), "velocity": str(event.velocity)})
	return JSON.stringify({"phase": state.phase, "owner": state.ball_owner_id, "ball": str(state.ball_position),
		"velocity": str(state.ball_velocity), "rival": str(state.actor(1).position), "events": events, "refusals": _refusals})


func _check(label: String, passed: bool) -> void:
	_checks.append({"name": label, "passed": passed})
	print(("PASS " if passed else "FAIL ") + label)


func _finish() -> void:
	var failures: Array[Dictionary] = _checks.filter(func(item: Dictionary) -> bool: return not bool(item["passed"]))
	var contact_passed: int = _contact_cases.filter(func(item: Dictionary) -> bool: return bool(item["passed"])).size()
	var shot_passed: int = _shot_cases.filter(func(item: Dictionary) -> bool: return bool(item["passed"])).size()
	var result: Dictionary = {"ok": failures.is_empty() and _completed, "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "expected_refusals": _expected_refusals, "contact_cases": _contact_cases.size(),
		"contact_passed": contact_passed, "shot_cases": _shot_cases.size(), "shot_passed": shot_passed,
		"engine": Engine.get_version_info()["string"], "physics": "Jolt Physics", "physics_hz": Engine.physics_ticks_per_second,
		"headless": true, "wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
		"failures": failures, "checks": _checks, "contacts": _contact_cases, "shots": _shot_cases}
	print("FUTSAL_MATCH_TESTS ", JSON.stringify(result))
	quit(0 if failures.is_empty() and _completed else 1)


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_MATCH_TESTS_INCOMPLETE")
		quit(2)
