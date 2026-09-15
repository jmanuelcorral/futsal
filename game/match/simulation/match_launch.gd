class_name MatchLaunch
extends RefCounted

const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Rules = preload("res://match/simulation/match_rules.gd")


class Solution extends RefCounted:
	var error: Error = ERR_UNAVAILABLE
	var executable: bool = false
	var reason: StringName = &"unavailable"
	var tick: int = -1
	var actor_id: int = -1
	var restart_id: int = -1
	var effective_target_actor_id: int = -1
	var launch_kind: Types.LaunchKind = Types.LaunchKind.FOOT_PASS
	var origin: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var speed: float = 0.0
	var power: float = 0.0

	func copy() -> Solution:
		var result: Solution = get_script().new()
		result.error = error
		result.executable = executable
		result.reason = reason
		result.tick = tick
		result.actor_id = actor_id
		result.restart_id = restart_id
		result.effective_target_actor_id = effective_target_actor_id
		result.launch_kind = launch_kind
		result.origin = origin
		result.direction = direction
		result.velocity = velocity
		result.speed = speed
		result.power = power
		return result


static func resolve(state: Snapshot, command: Command, tuning: Tuning) -> Solution:
	var result: Solution = Solution.new()
	if state == null or command == null or tuning == null or state.restart == null:
		return _error(result, ERR_INVALID_PARAMETER, &"missing_launch_argument")
	if not tuning.validation_error().is_empty():
		return _error(result, ERR_INVALID_PARAMETER, &"invalid_tuning")
	result.tick = state.tick
	result.actor_id = command.actor_id
	result.restart_id = state.restart.id
	result.origin = state.ball_position
	var actor: Snapshot.ActorSnapshot = state.actor(command.actor_id)
	if actor == null:
		return _error(result, ERR_DOES_NOT_EXIST, &"unknown_actor")
	if command.action not in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		return _error(result, ERR_INVALID_PARAMETER, &"not_a_launch")
	if not command.aim.is_finite() or command.aim.length_squared() > 1.00001 or not command.move.is_finite() or command.move.length_squared() > 1.00001:
		return _error(result, ERR_INVALID_PARAMETER, &"invalid_direction")
	if not is_finite(command.shot_charge) or command.shot_charge < 0.0 or command.shot_charge > 1.0 or not is_finite(command.shot_lift) or command.shot_lift < 0.0 or command.shot_lift > 1.0:
		return _error(result, ERR_INVALID_PARAMETER, &"invalid_power")
	if command.restart_spot_choice != Types.SpotChoice.DEFAULT:
		return _error(result, ERR_INVALID_PARAMETER, &"choice_requires_choice_action")
	if not result.origin.is_finite() or not actor.forward.is_finite() or not actor.position.is_finite():
		return _error(result, ERR_INVALID_PARAMETER, &"invalid_launch_pose")
	var target: Snapshot.ActorSnapshot = state.actor(command.target_actor_id)
	if command.target_actor_id != -1 and (command.action == Command.Action.SHOOT or target == null or target.actor_id == actor.actor_id or target.team_id != actor.team_id):
		return _error(result, ERR_INVALID_PARAMETER, &"invalid_teammate")
	var preparing: bool = state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.stage in [
		Types.RestartStage.STOPPED, Types.RestartStage.PLACEMENT]
	var restart_taker: bool = state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.taker_actor_id == actor.actor_id
	if state.phase != Snapshot.Phase.PLAYING and not restart_taker:
		return _error(result, ERR_UNAVAILABLE, &"launch_context_unavailable")
	if command.action == Command.Action.KEEPER_THROW:
		if not actor.ball_in_hands and not (preparing and state.restart.kind == Types.RestartKind.GOAL_CLEARANCE):
			return _error(result, ERR_UNAVAILABLE, &"ball_not_in_hands")
	elif actor.ball_in_hands:
		return _error(result, ERR_UNAVAILABLE, &"hands_require_throw")
	if not preparing and not actor.ball_contact_reachable:
		return _error(result, ERR_UNAVAILABLE, &"unreachable_ball")
	if not preparing and actor.action_cooldown > 0.0:
		return _error(result, ERR_BUSY, &"launch_cooldown")
	result.direction = actor.forward if command.aim.is_zero_approx() else Vector3(command.aim.x, 0.0, command.aim.y).normalized()
	var distance: float = 8.0
	var lift: float = 0.0
	if command.action in [Command.Action.PASS, Command.Action.KEEPER_THROW]:
		if target == null:
			var origin: Vector3 = actor.position if command.aim.is_zero_approx() else result.origin
			target = _recipient(actor, state, origin, Vector3.ZERO if command.aim.is_zero_approx() else result.direction, tuning.pass_assist_degrees)
		if target != null:
			var to_target: Vector3 = _flat_direction(result.origin, target.position)
			if command.aim.is_zero_approx() or result.direction.dot(to_target) >= cos(deg_to_rad(tuning.pass_assist_degrees)):
				result.direction = to_target
				result.effective_target_actor_id = target.actor_id
				distance = _flat_distance(result.origin, target.position)
		var minimum: float = tuning.pass_min_speed
		var maximum: float = tuning.pass_max_speed
		if command.action == Command.Action.KEEPER_THROW:
			result.launch_kind = Types.LaunchKind.KEEPER_THROW
			minimum = tuning.keeper_throw_min_speed
			maximum = tuning.keeper_throw_max_speed
			lift = tuning.keeper_throw_lift
		result.speed = clampf(distance * 0.60 + 5.0, minimum, maximum)
		result.power = inverse_lerp(minimum, maximum, result.speed) if maximum > minimum else 1.0
	else:
		result.launch_kind = Types.LaunchKind.FOOT_SHOT
		result.speed = lerpf(tuning.shot_min_speed, tuning.shot_max_speed, command.shot_charge)
		result.power = command.shot_charge
		lift = tuning.maximum_shot_lift * command.shot_lift
	if not result.direction.is_finite() or result.direction.is_zero_approx():
		return _error(result, ERR_INVALID_PARAMETER, &"zero_launch_direction")
	result.direction = Vector3(result.direction.x, 0.0, result.direction.z).normalized()
	result.velocity = result.direction * sqrt(maxf(0.0, result.speed * result.speed - lift * lift)) + Vector3.UP * lift
	if actor.team_id == Snapshot.Team.HOME and actor.actor_id != state.selected_actor_id:
		if command.action == Command.Action.SHOOT:
			return _error(result, ERR_UNAUTHORIZED, &"allied_shot_forbidden")
		if result.effective_target_actor_id == -1 and _toward_goal_mouth(result.origin, result.velocity, actor.attack_direction):
			return _error(result, ERR_UNAUTHORIZED, &"allied_disguised_shot_forbidden")
	var rule_error: Error = Rules.launch_error(command, state, result.velocity, result.effective_target_actor_id, tuning)
	if rule_error != OK:
		return _error(result, rule_error, &"launch_rule")
	result.error = OK
	result.executable = not preparing
	result.reason = &"ready" if result.executable else &"preparing"
	return result


static func _recipient(actor: Snapshot.ActorSnapshot, state: Snapshot, origin: Vector3, direction: Vector3, degrees: float) -> Snapshot.ActorSnapshot:
	var best: Snapshot.ActorSnapshot
	var best_alignment: float = -INF
	var best_distance: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.actor_id == actor.actor_id or candidate.team_id != actor.team_id:
			continue
		var alignment: float = 1.0 if direction.is_zero_approx() else direction.dot(_flat_direction(origin, candidate.position))
		if not direction.is_zero_approx() and alignment < cos(deg_to_rad(degrees)):
			continue
		var distance: float = _flat_distance(origin, candidate.position)
		var same_angle: bool = is_equal_approx(alignment, best_alignment)
		var same_distance: bool = is_equal_approx(distance, best_distance)
		if best == null or (alignment > best_alignment and not same_angle) or (same_angle and (
			(distance < best_distance and not same_distance) or (same_distance and candidate.actor_id < best.actor_id))):
			best = candidate
			best_alignment = alignment
			best_distance = distance
	return best


static func _toward_goal_mouth(origin: Vector3, velocity: Vector3, attack: Vector3) -> bool:
	if velocity.x * attack.x <= 0.0001:
		return false
	var time: float = (attack.x * Tuning.COURT_LENGTH * 0.5 - origin.x) / velocity.x
	return time >= 0.0 and absf(origin.z + velocity.z * time) <= Tuning.GOAL_WIDTH * 0.5 + Tuning.BALL_RADIUS


static func _error(result: Solution, code: Error, reason: StringName) -> Solution:
	result.error = code
	result.executable = false
	result.reason = reason
	return result


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _flat_direction(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
