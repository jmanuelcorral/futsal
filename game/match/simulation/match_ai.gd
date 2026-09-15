extends RefCounted

const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Rules = preload("res://match/simulation/match_rules.gd")

const RESTART_SPOT_DECISION_TICKS: int = 18
const FRIENDLY_DISTRIBUTION_WAIT_SECONDS: float = 2.0


static func decide(actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning, held_seconds: float) -> Command:
	var command: Command = Command.new(actor.actor_id, actor.last_command_sequence + 1)
	if state.phase == Snapshot.Phase.RESTART_PAUSE:
		_restart(command, actor, state, tuning)
		return command
	if state.phase != Snapshot.Phase.PLAYING or not Rules.can_move(actor.actor_id, state):
		return command
	if actor.team_id == Snapshot.Team.HOME:
		_friendly(command, actor, state, tuning, held_seconds)
	elif actor.role == Snapshot.Role.KEEPER:
		_keeper(command, actor, state, tuning, held_seconds)
	elif state.mode == Setup.Mode.PREVIEW_5V5:
		_preview_field(command, actor, state, tuning)
	else:
		_field(command, actor, state, tuning)
	if command.action not in Rules.allowed_actions(actor.actor_id, state):
		command.action = Command.Action.NONE
		command.target_actor_id = -1
		command.shot_charge = 0.0
		command.shot_lift = 0.0
	return command


static func _restart(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> void:
	if actor.actor_id not in state.ai_actor_ids or actor.actor_id == state.selected_actor_id or state.restart == null or state.restart.stage != Types.RestartStage.READY:
		return
	var legal: Array[Command.Action] = Rules.allowed_actions(actor.actor_id, state)
	if actor.actor_id != state.restart.taker_actor_id:
		if Rules.can_move(actor.actor_id, state):
			_restart_support(command, actor, state, tuning)
		return
	if actor.team_id == Snapshot.Team.HOME or state.restart.ready_tick < 0:
		return
	var elapsed: int = state.tick - state.restart.ready_tick
	var attack: Vector3 = _attack_direction(actor.team_id, state)
	if Command.Action.CHOOSE_RESTART_SPOT in legal and elapsed >= mini(RESTART_SPOT_DECISION_TICKS, tuning.ai_restart_delay_ticks) and state.restart.spot_choice != Types.SpotChoice.OFFENCE_SPOT:
		var depth: float = Tuning.COURT_LENGTH * 0.5 - state.restart.offence_spot.x * attack.x
		if depth > Tuning.PENALTY_RADIUS + 0.1 and depth < 9.5 and absf(state.restart.offence_spot.z) < 2.0:
			command.action = Command.Action.CHOOSE_RESTART_SPOT
			command.restart_spot_choice = Types.SpotChoice.OFFENCE_SPOT
			return
	if elapsed < tuning.ai_restart_delay_ticks:
		return
	if state.restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		if Command.Action.SHOOT in legal:
			_restart_shot(command, actor, state)
		return
	var receiver: Snapshot.ActorSnapshot = _restart_receiver(actor, state)
	if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
		if Command.Action.KEEPER_THROW not in legal:
			return
		command.action = Command.Action.KEEPER_THROW
	elif receiver == null and state.restart.kind in [Types.RestartKind.CORNER, Types.RestartKind.DIRECT_FREE_KICK] and Command.Action.SHOOT in legal:
		_restart_shot(command, actor, state)
		return
	elif Command.Action.PASS in legal:
		command.action = Command.Action.PASS
	else:
		return
	if receiver != null:
		command.target_actor_id = receiver.actor_id
		command.aim = _direction(state.restart.spot, receiver.position)
	else:
		var outlet: Vector3 = Vector3(clampf(state.restart.spot.x + attack.x * 5.0, -13.0, 13.0), 0.0, state.restart.spot.z * 0.4)
		command.aim = _direction(state.restart.spot, outlet)
		if command.aim.is_zero_approx():
			command.aim = Vector2(attack.x, 0.25).normalized()


static func _restart_shot(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot) -> void:
	var goal: Vector3 = _attack_direction(actor.team_id, state) * Tuning.COURT_LENGTH * 0.5
	for opponent: Snapshot.ActorSnapshot in state.actors:
		if opponent.team_id != actor.team_id and opponent.role == Snapshot.Role.KEEPER:
			goal.z = -0.55 if opponent.position.z >= 0.0 else 0.55
			break
	command.action = Command.Action.SHOOT
	command.aim = _direction(state.restart.spot, goal)
	command.shot_charge = 0.8
	command.shot_lift = 0.05


static func _restart_receiver(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Snapshot.ActorSnapshot:
	var best: Snapshot.ActorSnapshot
	var best_score: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id != actor.team_id or candidate.actor_id == actor.actor_id:
			continue
		var distance: float = _flat_distance(state.restart.spot, candidate.position)
		var score: float = distance + (0.0 if _safe_friendly_pass(actor, candidate, state.restart.spot, state) else 100.0)
		if best == null or score < best_score - 0.0001 or (is_equal_approx(score, best_score) and candidate.actor_id < best.actor_id):
			best = candidate
			best_score = score
	return best


static func _restart_support(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> void:
	var attack: Vector3 = _attack_direction(actor.team_id, state)
	var destination: Vector3 = actor.spawn_position
	if actor.role == Snapshot.Role.KEEPER:
		destination = Vector3(-attack.x * 18.5, 0.0, clampf(state.restart.spot.z * 0.2, -1.15, 1.15))
		if state.restart.kind == Types.RestartKind.PENALTY_6M and actor.team_id != state.restart.awarded_team_id:
			destination.x = -attack.x * Tuning.COURT_LENGTH * 0.5
	else:
		destination.x += clampf(state.restart.spot.x * 0.25, -4.0, 4.0)
		destination.x += attack.x * (2.0 if actor.team_id == state.restart.awarded_team_id else -1.0)
		destination.x = clampf(destination.x, -13.0, 13.0)
		if absf(destination.z) < 2.0:
			destination.z = -4.0 if actor.actor_id % 4 == 0 else 4.0
		destination.z = clampf(destination.z, -8.5, 8.5)
	var gap: float = _flat_distance(actor.position, destination)
	var move: Vector2 = _direction(actor.position, destination) * clampf(gap / 0.7, 0.0, 1.0)
	var speed: float = tuning.keeper_speed if actor.role == Snapshot.Role.KEEPER else tuning.move_speed
	var displacement: Vector3 = Vector3(move.x, 0.0, move.y) * speed / Tuning.PHYSICS_HZ
	displacement = Rules.constrain_displacement(actor.actor_id, displacement, state, tuning)
	command.move = Vector2(displacement.x, displacement.z) * Tuning.PHYSICS_HZ / speed
	command.aim = _direction(actor.position, state.restart.spot)


static func _friendly(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning, held_seconds: float) -> void:
	if state.phase != Snapshot.Phase.PLAYING:
		return
	if state.ball_owner_id == actor.actor_id:
		_friendly_on_ball(command, actor, state, tuning, held_seconds)
		return
	if actor.role == Snapshot.Role.KEEPER:
		_keeper(command, actor, state, tuning, held_seconds)
		return
	var owner: Snapshot.ActorSnapshot = state.actor(state.ball_owner_id)
	var friendly_possession: bool = owner != null and owner.team_id == actor.team_id
	if not friendly_possession and (state.mode == Setup.Mode.MICRO_1V1 or actor.actor_id == _chaser_id(actor.team_id, state)):
		_field(command, actor, state, tuning)
		return
	var destination: Vector3 = actor.spawn_position
	destination.x += clampf(state.ball_position.x * 0.25, -4.0, 4.0)
	destination.x += _attack_direction(actor.team_id, state).x * (2.0 if friendly_possession else -1.0)
	destination.x = clampf(destination.x, -13.0, 13.0)
	if absf(destination.z) < 2.0:
		destination.z = -4.0 if actor.actor_id % 4 == 0 else 4.0
	destination.z = clampf(destination.z, -8.5, 8.5)
	var gap: float = _flat_distance(actor.position, destination)
	command.move = _direction(actor.position, destination) * clampf(gap / 0.7, 0.0, 1.0)
	command.aim = _direction(actor.position, state.ball_position)


static func _friendly_on_ball(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning, held_seconds: float) -> void:
	var delay: float = maxf(0.6, tuning.action_cooldown + 2.0 * tuning.ai_interval)
	var distribution_delay: float = maxf(FRIENDLY_DISTRIBUTION_WAIT_SECONDS, maxf(2.0 * delay, tuning.keeper_return_delay))
	var recipient: Snapshot.ActorSnapshot = _friendly_recipient(actor, state)
	if recipient == null and held_seconds >= distribution_delay:
		recipient = _friendly_distribution_recipient(actor, state)
	var destination: Vector3 = _friendly_carry_destination(actor, state)
	var gap: float = _flat_distance(actor.position, destination)
	command.move = _direction(actor.position, destination) * clampf(gap / 0.6, 0.0, 1.0)
	command.aim = _direction(actor.position, destination)
	command.close_control = true
	if recipient == null:
		return
	if actor.role == Snapshot.Role.KEEPER:
		delay = tuning.keeper_return_delay
		command.move = Vector2.ZERO
		command.aim = _direction(state.ball_position, recipient.position)
	elif recipient.actor_id != state.selected_actor_id:
		delay *= 2.0
	var settled_ticks: int = floori(held_seconds * Tuning.PHYSICS_HZ + 0.0001)
	if actor.action_cooldown > 0.0 or settled_ticks < ceili(delay * Tuning.PHYSICS_HZ):
		return
	command.action = Command.Action.KEEPER_THROW if actor.role == Snapshot.Role.KEEPER and actor.ball_in_hands else Command.Action.PASS
	command.target_actor_id = recipient.actor_id
	command.aim = _direction(state.ball_position, recipient.position)


static func _friendly_recipient(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Snapshot.ActorSnapshot:
	var human: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	if human != null and _safe_friendly_pass(actor, human, state.ball_position, state):
		return human
	var best: Snapshot.ActorSnapshot
	var best_score: float = -INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if not _safe_friendly_pass(actor, candidate, state.ball_position, state):
			continue
		if state.last_pass_target_actor_id == actor.actor_id and state.last_pass_actor_id == candidate.actor_id and state.last_pass_tick >= 0 and state.tick - state.last_pass_tick < 2 * Tuning.PHYSICS_HZ:
			continue
		var opens_human_lane: bool = human != null and _safe_friendly_pass(candidate, human, candidate.position, state)
		var progress: float = _friendly_outlet_value(candidate, state) - _friendly_outlet_value(actor, state)
		# A useful outlet opens the human's lane or advances a stable ordering, not an immediate return loop.
		if not opens_human_lane and progress < 0.75:
			continue
		var score: float = (100.0 if opens_human_lane else 0.0) + progress - _flat_distance(state.ball_position, candidate.position) * 0.25
		var tied: bool = is_equal_approx(score, best_score)
		if best == null or (score > best_score and not tied) or (tied and candidate.actor_id < best.actor_id):
			best = candidate
			best_score = score
	return best


static func _friendly_distribution_recipient(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Snapshot.ActorSnapshot:
	var best: Snapshot.ActorSnapshot
	var best_score: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id != actor.team_id or candidate.actor_id == actor.actor_id or not candidate.position.is_finite():
			continue
		if absf(candidate.position.x) > Tuning.COURT_LENGTH * 0.5 - Tuning.ACTOR_RADIUS or absf(candidate.position.z) > Tuning.COURT_WIDTH * 0.5 - Tuning.ACTOR_RADIUS:
			continue
		var distance: float = _flat_distance(state.ball_position, candidate.position)
		if distance < Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 0.1:
			continue
		# After useful safe outlets have failed, involve the human rather than circulating indefinitely.
		if candidate.actor_id == state.selected_actor_id:
			return candidate
		if state.last_pass_target_actor_id == actor.actor_id and state.last_pass_actor_id == candidate.actor_id:
			continue
		var pressure: Snapshot.ActorSnapshot = _nearest_opponent(candidate, state)
		var space: float = minf(5.0, _flat_distance(candidate.position, pressure.position)) if pressure != null else 5.0
		var score: float = distance * 0.25 - space * 2.0
		if not _safe_friendly_pass(actor, candidate, state.ball_position, state):
			score += 100.0
		if best == null or score < best_score - 0.0001 or (is_equal_approx(score, best_score) and candidate.actor_id < best.actor_id):
			best = candidate
			best_score = score
	return best


static func _friendly_outlet_value(actor: Snapshot.ActorSnapshot, state: Snapshot) -> float:
	return actor.position.dot(_attack_direction(actor.team_id, state)) + absf(actor.position.z) * 0.35


static func _safe_friendly_pass(actor: Snapshot.ActorSnapshot, recipient: Snapshot.ActorSnapshot, origin: Vector3, state: Snapshot) -> bool:
	if recipient.actor_id == actor.actor_id or recipient.team_id != actor.team_id:
		return false
	if absf(recipient.position.x) > 19.0 or absf(recipient.position.z) > 9.0:
		return false
	var start: Vector2 = Vector2(origin.x, origin.z)
	var target: Vector2 = Vector2(recipient.position.x, recipient.position.z)
	var distance: float = start.distance_to(target)
	if distance < 2.0 or distance > 24.0:
		return false
	var direction: Vector2 = (target - start) / distance
	for obstacle: Snapshot.ActorSnapshot in state.actors:
		if obstacle.actor_id == actor.actor_id or obstacle.actor_id == recipient.actor_id:
			continue
		var point: Vector2 = Vector2(obstacle.position.x, obstacle.position.z)
		var opponent: bool = obstacle.team_id != actor.team_id
		if opponent and point.distance_to(target) < Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 1.0:
			return false
		var along: float = (point - start).dot(direction)
		if along < 0.0 or along > distance:
			continue
		var clearance: float = Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + (0.65 if opponent else 0.2)
		if point.distance_to(start + direction * along) < clearance:
			return false
	return true


static func _friendly_carry_destination(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Vector3:
	var side: float = -1.0 if actor.actor_id % 4 == 0 else 1.0
	var threat: Snapshot.ActorSnapshot = _nearest_opponent(actor, state)
	if threat != null and _flat_distance(actor.position, threat.position) < 4.0 and absf(threat.position.z - actor.position.z) > 0.2:
		side = -1.0 if threat.position.z > actor.position.z else 1.0
	var lateral_limit: float = 2.5 if actor.role == Snapshot.Role.KEEPER else 7.0
	if absf(actor.position.z) >= lateral_limit:
		side = -signf(actor.position.z)
	var attack: Vector3 = _attack_direction(actor.team_id, state)
	var destination: Vector3 = actor.position + Vector3(-attack.x * 1.2, 0.0, side * 2.4)
	if actor.role == Snapshot.Role.KEEPER:
		var own_end: float = -attack.x
		destination.x = own_end * clampf(actor.position.x * own_end, 15.0, 18.5)
		destination.z = clampf(destination.z, -3.0, 3.0)
	else:
		destination.x = clampf(destination.x, -13.0, 13.0)
		destination.z = clampf(destination.z, -8.5, 8.5)
	return destination


static func _field(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> void:
	var ball: Vector3 = state.ball_position
	var attack: Vector3 = _attack_direction(actor.team_id, state)
	var goal: Vector3 = attack * Tuning.COURT_LENGTH * 0.5
	var destination: Vector3 = ball
	if state.ball_owner_id == actor.actor_id:
		var defender: Snapshot.ActorSnapshot = state.actor(2 if actor.team_id == 1 else 3)
		goal.z = -0.75 if defender.position.z >= 0.0 else 0.75
		destination = goal
		command.aim = _direction(actor.position, goal)
		var threat: Snapshot.ActorSnapshot = _nearest_opponent(actor, state)
		command.close_control = threat != null and _flat_distance(actor.position, threat.position) < 2.0
		if absf(goal.x - actor.position.x) < 12.0 and actor.action_cooldown <= 0.0:
			command.action = Command.Action.SHOOT
			command.shot_charge = 0.72
			command.shot_lift = 0.12
	elif state.ball_owner_id >= 0:
		var owner: Snapshot.ActorSnapshot = state.actor(state.ball_owner_id)
		if owner.team_id == actor.team_id:
			destination = ball + attack * 6.0 + Vector3(0.0, 0.0, 3.0)
		else:
			var distance: float = _flat_distance(actor.position, ball)
			destination = ball - attack * (0.35 if distance < 1.6 else 0.9)
			command.aim = _direction(actor.position, ball)
			command.close_control = distance < 2.0
			if distance < tuning.tackle_reach and actor.action_cooldown <= 0.0:
				command.action = Command.Action.TACKLE
	else:
		destination = ball + Vector3(state.ball_velocity.x, 0.0, state.ball_velocity.z) * 0.15
		command.close_control = _flat_distance(actor.position, ball) < 1.6
	destination.x = clampf(destination.x, -19.0, 19.0)
	destination.z = clampf(destination.z, -9.0, 9.0)
	var gap: float = _flat_distance(actor.position, destination)
	command.move = _direction(actor.position, destination) * clampf(gap / 0.6, 0.0, 1.0)
	command.sprint = gap > 3.0 and state.ball_owner_id != actor.actor_id


static func _keeper(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning, held_seconds: float) -> void:
	var teammate: Snapshot.ActorSnapshot = _nearest_field_teammate(actor, state) if state.mode == Setup.Mode.PREVIEW_5V5 else state.actor(actor.team_id)
	var sign_to_goal: float = -_attack_direction(actor.team_id, state).x
	var goal_x: float = sign_to_goal * 20.0
	var ball: Vector3 = state.ball_position
	var destination: Vector3 = Vector3(sign_to_goal * 18.5, 0.0, clampf(ball.z * 0.25, -1.15, 1.15))
	command.aim = _direction(actor.position, ball)
	if state.ball_owner_id == actor.actor_id:
		command.aim = _direction(actor.position, teammate.position)
		command.close_control = true
		destination = actor.position
		if held_seconds >= tuning.keeper_return_delay and actor.action_cooldown <= 0.0:
			command.action = Command.Action.KEEPER_THROW if actor.ball_in_hands else Command.Action.PASS
			command.target_actor_id = teammate.actor_id
	elif state.ball_owner_id == -1:
		var incoming: bool = state.ball_velocity.x * sign_to_goal > 0.5
		if incoming:
			var intercept_seconds: float = (destination.x - ball.x) / state.ball_velocity.x
			if intercept_seconds >= 0.0 and intercept_seconds <= 0.65:
				destination.z = clampf(ball.z + state.ball_velocity.z * intercept_seconds, -1.25, 1.25)
		if absf(goal_x - ball.x) < 5.5 and absf(ball.z) < 3.5 and state.ball_velocity.length() < 5.0:
			destination = ball
	destination.x = clampf(destination.x * sign_to_goal, 14.5, 19.3) * sign_to_goal
	destination.z = clampf(destination.z, -3.5, 3.5)
	var gap: float = _flat_distance(actor.position, destination)
	command.move = _direction(actor.position, destination) * clampf(gap / 0.5, 0.0, 1.0)


static func _preview_field(command: Command, actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> void:
	var owner: Snapshot.ActorSnapshot = state.actor(state.ball_owner_id)
	var friendly_possession: bool = owner != null and owner.team_id == actor.team_id
	if state.ball_owner_id == actor.actor_id or (not friendly_possession and actor.actor_id == _chaser_id(actor.team_id, state)):
		_field(command, actor, state, tuning)
		return
	var destination: Vector3 = actor.spawn_position
	destination.x += clampf(state.ball_position.x * 0.25, -4.0, 4.0)
	destination.x += _attack_direction(actor.team_id, state).x * (2.0 if friendly_possession else -1.0)
	destination.x = clampf(destination.x, -16.5, 16.5)
	destination.z = clampf(destination.z, -8.5, 8.5)
	command.aim = _direction(actor.position, state.ball_position)
	var gap: float = _flat_distance(actor.position, destination)
	command.move = _direction(actor.position, destination) * clampf(gap / 0.7, 0.0, 1.0)


static func _chaser_id(team_id: int, state: Snapshot) -> int:
	var best_id: int = -1
	var best_distance: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id != team_id or candidate.role != Snapshot.Role.FIELD or candidate.actor_id not in state.ai_actor_ids:
			continue
		var distance: float = _flat_distance(candidate.position, state.ball_position)
		var tied: bool = is_equal_approx(distance, best_distance)
		if best_id == -1 or (distance < best_distance and not tied) or (tied and candidate.actor_id < best_id):
			best_id = candidate.actor_id
			best_distance = distance
	return best_id


static func _nearest_field_teammate(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Snapshot.ActorSnapshot:
	var nearest: Snapshot.ActorSnapshot
	var best_distance: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id != actor.team_id or candidate.role != Snapshot.Role.FIELD:
			continue
		var distance: float = _flat_distance(actor.position, candidate.position)
		var tied: bool = is_equal_approx(distance, best_distance)
		if nearest == null or (distance < best_distance and not tied) or (tied and candidate.actor_id < nearest.actor_id):
			nearest = candidate
			best_distance = distance
	return nearest


static func _nearest_opponent(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Snapshot.ActorSnapshot:
	var nearest: Snapshot.ActorSnapshot
	var best_distance: float = INF
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id == actor.team_id:
			continue
		var distance: float = _flat_distance(actor.position, candidate.position)
		var tied: bool = is_equal_approx(distance, best_distance)
		if nearest == null or (distance < best_distance and not tied) or (tied and candidate.actor_id < nearest.actor_id):
			nearest = candidate
			best_distance = distance
	return nearest


static func _direction(from: Vector3, to: Vector3) -> Vector2:
	return Vector2(to.x - from.x, to.z - from.z).normalized()


static func _attack_direction(team: int, state: Snapshot) -> Vector3:
	var setup: Setup = Setup.new()
	setup.mode = state.mode
	setup.training_exercise = state.training_exercise
	return setup.attack_direction(team)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
