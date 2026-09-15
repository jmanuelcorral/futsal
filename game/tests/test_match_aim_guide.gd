extends SceneTree

const Launch = preload("res://match/simulation/match_launch.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const GuideScript = preload("res://match/presentation/aim/world_aim_guide.gd")
const GuideScene: PackedScene = preload("res://match/presentation/aim/world_aim_guide.tscn")

var _checks: Array[Dictionary] = []
var _expected_errors: int = 0
var _completed: bool = false
var _started_ms: int = 0


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_ms > 120000:
		push_error("Aim guide test watchdog: exceeded 120 seconds")
		quit(2)
	return false


func _run() -> void:
	var private_view: SubViewport = SubViewport.new()
	private_view.size = Vector2i(960, 540)
	private_view.own_world_3d = true
	root.add_child(private_view)
	var parent: Node3D = Node3D.new()
	parent.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.4, 0.8, 1.2)), Vector3(5, 2, -4))
	private_view.add_child(parent)
	var guide: GuideScript = GuideScene.instantiate() as GuideScript
	parent.add_child(guide)
	await process_frame
	var arrow: Node3D = guide.get_node("Arrow") as Node3D
	var shaft: MeshInstance3D = guide.get_node("Arrow/Shaft") as MeshInstance3D
	var head: MeshInstance3D = guide.get_node("Arrow/Head") as MeshInstance3D
	var material: StandardMaterial3D = shaft.material_override as StandardMaterial3D
	var host_world: World3D = parent.get_world_3d()
	_check("real guide scene starts with no visible arrow", not arrow.visible)
	_check("guide inherits the existing private world", guide.get_world_3d() == host_world
		and private_view.find_world_3d() == host_world)
	_check("guide never creates another viewport or world", guide.find_children("*", "Viewport", true, false).is_empty())
	_check("guide adds no collision objects", guide.find_children("*", "CollisionObject3D", true, false).is_empty())
	_check("direction head is a real original triangle", head.mesh is ArrayMesh and head.mesh.get_surface_count() == 1
		and head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 3)
	_check("both visible parts share one unlit nonemissive material", head.material_override == material
		and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not material.emission_enabled)
	_check("guide casts no shadows into the parquet", shaft.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and head.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var resources: Array[int] = [shaft.get_instance_id(), head.get_instance_id(), shaft.mesh.get_instance_id(),
		head.mesh.get_instance_id(), material.get_instance_id()]
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized()]:
		for speed: float in [8.0, 28.0]:
			var solution: Launch.Solution = _solution(direction, speed, 0.25 if speed == 8.0 else 1.0)
			solution.effective_target_actor_id = 4
			solution.launch_kind = Rules.LaunchKind.FOOT_PASS
			var original: String = _signature(solution)
			var render_ball: Vector3 = solution.origin + Vector3(0.07, 0.02, -0.03)
			var context: String = "direction=%s speed=%.1f" % [direction, speed]
			guide.present(solution, render_ball, true)
			_check(context + " displays a real mesh guide", arrow.visible and head.is_visible_in_tree())
			_check(context + " world origin follows interpolation only", arrow.global_position.is_equal_approx(
				render_ball + Vector3.UP * GuideScript.HEIGHT_OFFSET))
			_check(context + " assisted direction survives transformed parent", arrow.global_basis.x.is_equal_approx(direction))
			var tip: Vector3 = head.global_transform * Vector3.RIGHT
			var length: float = minf(speed * GuideScript.SPEED_LENGTH_SCALE, GuideScript.MAX_LENGTH)
			_check(context + " speed determines actual arrow geometry", tip.is_equal_approx(
				render_ball + Vector3.UP * (GuideScript.HEIGHT_OFFSET + 0.01) + direction * (GuideScript.BALL_GAP + length)))
			_check(context + " actual power determines head width", is_equal_approx(head.scale.z, 0.32 + 0.12 * solution.power))
			_check(context + " physical origin and launch velocity remain observable", arrow.get_meta("physical_origin") == solution.origin
				and arrow.get_meta("launch_velocity") == solution.velocity and arrow.get_meta("effective_target_actor_id") == 4)
			_check(context + " presentation never mutates the solution", original == _signature(solution))
			_check(context + " repeated presentation reuses nodes meshes and material",
				resources == [shaft.get_instance_id(), head.get_instance_id(), shaft.mesh.get_instance_id(),
					head.mesh.get_instance_id(), material.get_instance_id()])
	_test_shared_launch_resolver(guide, arrow)
	var solution: Launch.Solution = _solution(Vector3.RIGHT, 14.0, 0.6)
	solution.executable = false
	solution.reason = &"placement"
	guide.present(solution, solution.origin, true)
	_check("valid preparation may render before execution is legal", arrow.visible and not bool(arrow.get_meta("executable")))
	guide.present(solution, solution.origin, false)
	_check("host disabling the guide clears its visual context", not arrow.visible and arrow.get_meta_list().is_empty())
	guide.present(solution, solution.origin, true)
	_check("host confirmation can restore the guide", arrow.visible)
	guide.clear()
	guide.clear()
	_check("accepted kick or cancellation can clear idempotently", not arrow.visible and arrow.get_meta_list().is_empty())
	guide.present(null, Vector3(NAN, 0, 0), false)
	_check("lost-ball focus pause and reset can disable without a stale solution", not arrow.visible)
	for actor_id: int in [1, 3, 5, 7, 9]:
		solution = _solution(Vector3.RIGHT, 14.0, 0.6)
		solution.actor_id = actor_id
		guide.present(solution, solution.origin, true)
		_check("no rival arrow for actor=%d" % actor_id, not arrow.visible)
	solution = _solution(Vector3.LEFT, 12.0, 0.4)
	solution.actor_id = 2
	solution.launch_kind = Rules.LaunchKind.KEEPER_THROW
	solution.origin = Vector3(-15, 1.1, 2)
	solution.velocity = solution.direction * sqrt(solution.speed * solution.speed - 9.0) + Vector3.UP * 3.0
	guide.present(solution, solution.origin, true)
	_check("selected goalkeeper uses the authoritative hand origin", arrow.visible
		and arrow.get_meta("physical_origin") == Vector3(-15, 1.1, 2))
	for invalid: String in ["origin_nan", "direction_nan", "direction_nonplanar", "velocity_inf", "speed_nan",
			"power_inf", "power_negative", "opposite_velocity", "render_nan", "missing_reason", "null_solution",
			"invalid_actor", "rival_receiver", "speed_mismatch", "shot_receiver"]:
		solution = _solution(Vector3.RIGHT, 14.0, 0.6)
		var render_ball: Vector3 = solution.origin
		match invalid:
			"origin_nan": solution.origin.x = NAN
			"direction_nan": solution.direction.z = NAN
			"direction_nonplanar": solution.direction = Vector3.UP
			"velocity_inf": solution.velocity.y = INF
			"speed_nan": solution.speed = NAN
			"power_inf": solution.power = INF
			"power_negative": solution.power = -0.1
			"opposite_velocity": solution.velocity = Vector3.LEFT * 14.0
			"render_nan": render_ball.z = NAN
			"missing_reason":
				solution.error = ERR_INVALID_PARAMETER
				solution.reason = &""
			"null_solution": solution = null
			"invalid_actor": solution.actor_id = 99
			"rival_receiver": solution.effective_target_actor_id = 1
			"speed_mismatch": solution.speed += 1.0
			"shot_receiver": solution.effective_target_actor_id = 4
		_expected_errors += 1
		guide.present(solution, render_ball, true)
		_check("invalid " + invalid + " hides every stale arrow", not arrow.visible and arrow.get_meta_list().is_empty())
	solution = _solution(Vector3.RIGHT, 14.0, 0.6)
	solution.error = ERR_UNAVAILABLE
	solution.reason = &"ball_contact_lost"
	solution.origin.x = NAN
	guide.present(solution, Vector3.ZERO, true)
	_check("a diagnosed unavailable core query clears rather than inventing a trajectory", not arrow.visible)
	guide.present(_solution(Vector3.RIGHT, 14.0, 0.6), Vector3(2, 0.12, 3), true)
	_check("a new valid confirmed context recovers after refusals", arrow.visible)
	var guide_id: int = guide.get_instance_id()
	guide.free()
	_check("freeing guide removes all its native render nodes", not is_instance_id_valid(guide_id) and parent.get_child_count() == 0)
	_check("guide cleanup never replaces the host world", parent.get_world_3d() == host_world)
	private_view.free()
	await process_frame
	_completed = true
	_finish()


func _solution(direction: Vector3, speed: float, power: float) -> Launch.Solution:
	var solution: Launch.Solution = Launch.Solution.new()
	solution.error = OK
	solution.executable = true
	solution.reason = &"ready"
	solution.tick = 100
	solution.actor_id = 0
	solution.restart_id = -1
	solution.effective_target_actor_id = -1
	solution.launch_kind = Rules.LaunchKind.FOOT_SHOT
	solution.origin = Vector3(2, 0.12, -3)
	solution.direction = direction
	solution.velocity = direction * speed
	solution.speed = speed
	solution.power = power
	return solution


func _test_shared_launch_resolver(guide: GuideScript, arrow: Node3D) -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for action: Command.Action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
			var state: Snapshot = _launch_fixture(mode)
			var actor_id: int = 2 if action == Command.Action.KEEPER_THROW else 0
			state.selected_actor_id = actor_id
			state.ball_owner_id = actor_id
			for actor: Snapshot.ActorSnapshot in state.actors:
				actor.human_controlled = actor.actor_id == actor_id
				actor.ball_contact_reachable = actor.actor_id == actor_id
			var command: Command = Command.new(actor_id, 0)
			command.action = action
			command.aim = Vector2.RIGHT
			command.shot_charge = 0.65
			if action == Command.Action.KEEPER_THROW:
				state.actor(2).ball_in_hands = true
				state.ball_position = state.actor(2).position + Vector3(0.3, 1.1, 0)
				var toward: Vector3 = state.actor(0).position - state.ball_position
				command.aim = Vector2(toward.x, toward.z).normalized()
				command.target_actor_id = 0
			var before: String = _launch_state_signature(state)
			var solution: Launch.Solution = Launch.resolve(state, command, Tuning.new())
			var context: String = "shared resolver mode=%d action=%d actor=%d" % [mode, action, actor_id]
			_check(context + " provides an executable authoritative solution", solution.error == OK and solution.executable)
			var render_ball: Vector3 = state.ball_position + Vector3(0.04, 0.01, -0.02)
			guide.present(solution, render_ball, true)
			_check(context + " feeds the real mesh scene", arrow.visible)
			if not arrow.visible:
				continue
			_check(context + " draws the shared effective direction", arrow.global_basis.x.is_equal_approx(solution.direction))
			_check(context + " retains the actual kick velocity and power", arrow.get_meta("launch_velocity") == solution.velocity
				and arrow.get_meta("launch_power") == solution.power)
			_check(context + " separates physical and interpolated origin", arrow.get_meta("physical_origin") == state.ball_position
				and arrow.global_position.is_equal_approx(render_ball + Vector3.UP * GuideScript.HEIGHT_OFFSET))
			_check(context + " query and presentation leave the source state intact", before == _launch_state_signature(state))
			if action == Command.Action.PASS:
				_check(context + " renders real receiver assistance rather than raw aim",
					solution.effective_target_actor_id == (2 if mode == Setup.Mode.MICRO_1V1 else 4)
					and not solution.direction.is_equal_approx(Vector3.RIGHT))
			elif action == Command.Action.KEEPER_THROW:
				_check(context + " represents actual vertical throw speed without an invented arc", solution.velocity.y > 0.0
					and is_equal_approx(solution.velocity.length(), solution.speed))


func _launch_fixture(mode: Setup.Mode) -> Snapshot:
	var setup: Setup = Setup.new() if mode == Setup.Mode.MICRO_1V1 else Setup.preview_5v5()
	var state: Snapshot = Snapshot.new()
	state.mode = mode
	state.phase = Snapshot.Phase.PLAYING
	state.tick = 120
	state.seconds_remaining = 90.0
	state.ball_position = setup.ball_position
	for id: int in setup.actor_positions:
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = id % 2
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.position = setup.actor_positions[id]
		actor.forward = Vector3(setup.actor_forwards[id].x, 0.0, setup.actor_forwards[id].y)
		actor.attack_direction = setup.attack_direction(actor.team_id)
		state.actors.append(actor)
	state.actor(2 if mode == Setup.Mode.MICRO_1V1 else 4).position = Vector3(3, 0, 2)
	return state


func _launch_state_signature(state: Snapshot) -> String:
	var actors: Array = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append([actor.actor_id, actor.position, actor.human_controlled, actor.ball_contact_reachable,
			actor.ball_in_hands, actor.action_cooldown, actor.last_command_sequence])
	return var_to_str([state.tick, state.phase, state.ball_position, state.ball_velocity, state.ball_owner_id,
		state.selected_actor_id, state.restart.kind, state.restart.stage, actors])


func _signature(solution: Launch.Solution) -> String:
	return var_to_str([solution.error, solution.executable, solution.reason, solution.tick, solution.actor_id,
		solution.restart_id, solution.effective_target_actor_id, solution.launch_kind,
		solution.origin, solution.direction, solution.velocity, solution.speed, solution.power])


func _check(name: String, passed: bool) -> void:
	_checks.append({"name": name, "passed": passed})
	print(("PASS " if passed else "FAIL ") + name)


func _finish() -> void:
	_check("aim guide suite reached completion", _completed)
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	print("FUTSAL_AIM_GUIDE_TESTS ", JSON.stringify({"ok": failures.is_empty(), "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "checks": _checks, "failures": failures, "expected_validation_errors": _expected_errors,
		"new_expected_error_counts": {GuideScript.INVALID_SOLUTION: _expected_errors}}))
	quit(0 if failures.is_empty() else 1)


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_AIM_GUIDE_TESTS_INCOMPLETE")
		quit(2)
