class_name MatchRules
extends RefCounted

const Types = preload("res://match/simulation/match_rule_types.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")

const EPSILON: float = 0.0001
const PLACEMENT_MARGIN: float = 0.03
const CORNER_RADIUS: float = Tuning.CORNER_ARC_RADIUS
const PLACEMENT_TICKS: int = Tuning.RESTART_PLACEMENT_TICKS
const FOUR_SECOND_TICKS: int = Tuning.RESTART_DEADLINE_TICKS
const FLOOR_CONTACT_SLOP: float = 0.025


static func first_crossing(previous: Vector3, current: Vector3, tuning: Tuning) -> Types.BoundaryCrossing:
	var result: Types.BoundaryCrossing = Types.BoundaryCrossing.new()
	result.border = Types.Border.NONE
	result.fraction = INF
	result.position = current
	# An end is geometric; the scoring team depends on the exercise in boundary_decision.
	result.goal_team_id = -1
	if tuning == null or not previous.is_finite() or not current.is_finite():
		return result
	for axis: int in [0, 2]:
		var half: float = Tuning.COURT_LENGTH * 0.5 if axis == 0 else Tuning.COURT_WIDTH * 0.5
		var limit: float = half + Tuning.BALL_RADIUS
		for end: float in [-1.0, 1.0]:
			var start: float = previous[axis] * end
			var finish: float = current[axis] * end
			if start > limit or finish <= limit or finish <= start:
				continue
			var fraction: float = (limit - start) / (finish - start)
			if fraction >= result.fraction:
				continue
			result.fraction = fraction
			result.position = previous.lerp(current, fraction)
			if axis == 0:
				result.border = Types.Border.NEG_X if end < 0.0 else Types.Border.POS_X
			else:
				result.border = Types.Border.NEG_Z if end < 0.0 else Types.Border.POS_Z
	return result


static func boundary_decision(crossing: Types.BoundaryCrossing, state: Snapshot, tuning: Tuning) -> Types.RuleDecision:
	var result: Types.RuleDecision = _none(&"no_crossing")
	if crossing == null or state == null or tuning == null:
		result.reason = &"invalid_boundary_input"
		return result
	if state.phase != Snapshot.Phase.PLAYING:
		result.reason = &"ball_not_in_play"
		return result
	if state.period_state == Types.PeriodState.EXTENDED_KICK and (not _extension_valid(state) or state.restart.stage != Types.RestartStage.IN_PLAY or state.extended_kick_event_id < 0):
		result.reason = &"inactive_extended_kick"
		return result
	if crossing.border == Types.Border.NONE:
		return result
	if not _valid_border(crossing.border) or not crossing.position.is_finite() or not is_finite(crossing.fraction) or crossing.fraction < 0.0 or crossing.fraction > 1.0 or not _crossing_on_border(crossing):
		result.reason = &"invalid_crossing"
		return result
	result.position = crossing.position
	var end: float = _border_end(crossing.border)
	if end != 0.0 and _through_goal(crossing.position):
		var scoring_team: int = _attacking_team(end, state)
		if scoring_team < 0:
			result.reason = &"invalid_attack_direction"
			return result
		var restricted: bool = _untouched_restart(state)
		var own_net: bool = restricted and scoring_team != state.restart.awarded_team_id
		var direct_forbidden: bool = restricted and not own_net and not _direct_goal_allowed(state.restart.kind)
		var own_direct_forbidden: bool = own_net
		if not direct_forbidden and not own_direct_forbidden:
			result.kind = Types.DecisionKind.GOAL
			result.scoring_team_id = scoring_team
			var last: Snapshot.ActorSnapshot = state.actor(state.last_touch_actor_id)
			result.reason = &"own_goal" if last != null and last.team_id != scoring_team else &"complete_ball_crossing"
			return result
		if state.period_state == Types.PeriodState.EXTENDED_KICK:
			result.reason = &"extended_kick_no_goal"
			return result
		var kind: Types.RestartKind = Types.RestartKind.CORNER if own_direct_forbidden else Types.RestartKind.GOAL_CLEARANCE
		return _restart_decision(kind, 1 - state.restart.awarded_team_id, crossing.position, crossing.border, state, tuning, &"disallowed_direct_goal")
	if state.period_state == Types.PeriodState.EXTENDED_KICK:
		result.reason = &"extended_kick_ball_out"
		return result
	var last_actor: Snapshot.ActorSnapshot = state.actor(state.last_touch_actor_id)
	# Untouched training kick-ins fall back to HOME; end lines default to a goal clearance.
	var beneficiary: int = 1 - last_actor.team_id if last_actor != null else Snapshot.Team.HOME
	if crossing.border in [Types.Border.NEG_Z, Types.Border.POS_Z]:
		return _restart_decision(Types.RestartKind.KICK_IN, beneficiary, crossing.position, crossing.border, state, tuning, &"touchline_exit")
	var attacking: int = _attacking_team(end, state)
	if attacking < 0:
		result.reason = &"invalid_attack_direction"
		return result
	var defending: int = 1 - attacking
	var restart_kind: Types.RestartKind = Types.RestartKind.CORNER if last_actor != null and last_actor.team_id == defending else Types.RestartKind.GOAL_CLEARANCE
	beneficiary = attacking if restart_kind == Types.RestartKind.CORNER else defending
	return _restart_decision(restart_kind, beneficiary, crossing.position, crossing.border, state, tuning, &"end_line_exit")


static func contact_decision(contact: Types.ContactEvidence, state: Snapshot, tuning: Tuning) -> Types.RuleDecision:
	var result: Types.RuleDecision = _none(&"no_foul")
	if contact == null or state == null or tuning == null or contact.contact_id < 0 or contact.tick < 0:
		result.reason = &"invalid_contact"
		return result
	result.contact_id = contact.contact_id
	result.position = contact.point
	if not contact.point.is_finite() or not contact.normal.is_finite() or not contact.actor_velocity.is_finite() or not contact.other_velocity.is_finite():
		result.reason = &"invalid_contact_vectors"
		return result
	if state.phase != Snapshot.Phase.PLAYING:
		result.reason = &"ball_not_in_play"
		return result
	var actor: Snapshot.ActorSnapshot = state.actor(contact.actor_id)
	if actor == null:
		result.reason = &"non_actor_contact"
		return result
	if actor.team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
		result.reason = &"invalid_contact_team"
		return result
	if not _extension_valid(state):
		result.reason = &"inactive_extended_kick"
		return result
	if state.restart != null and state.restart.stage == Types.RestartStage.IN_PLAY and contact.tick < state.restart.stage_started_tick:
		result.reason = &"contact_precedes_current_restart"
		return result
	if contact.kind == Types.ContactKind.BALL_ACTOR:
		if not _untouched_restart(state) or actor.actor_id != state.restart.taker_actor_id:
			result.reason = &"other_actor_contact"
			return result
		var touch_tick: int = contact.ball_touch_tick if contact.ball_touch_tick >= 0 else contact.tick
		if touch_tick > contact.tick:
			result.reason = &"invalid_touch_order"
			return result
		if contact.contact_id == state.restart.launch_contact_id:
			result.reason = &"original_launch_contact"
			return result
		if state.period_state == Types.PeriodState.EXTENDED_KICK:
			result.reason = &"extended_kick_second_touch"
			return result
		result = _restart_decision(Types.RestartKind.INDIRECT_FREE_KICK, 1 - actor.team_id, contact.point, Types.Border.NONE, state, tuning, &"restart_double_touch")
		result.offender_actor_id = actor.actor_id
		result.contact_id = contact.contact_id
		return result
	if contact.kind != Types.ContactKind.ACTOR_ACTOR:
		result.reason = &"unsupported_contact_kind"
		return result
	var opponent: Snapshot.ActorSnapshot = state.actor(contact.other_actor_id)
	if opponent == null or opponent.team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY] or opponent.team_id == actor.team_id:
		result.reason = &"not_rival_contact"
		return result
	if contact.normal.is_zero_approx():
		result.reason = &"missing_contact_normal"
		return result
	# Collision normals point from the other body towards the challenger.
	var closing: float = maxf(0.0, -(contact.actor_velocity - contact.other_velocity).dot(contact.normal.normalized()))
	var started: int = contact.tackle_started_tick
	var challenge: bool = started >= 0 and contact.tick >= started and contact.tick - started <= tuning.foul_challenge_window_ticks
	if not challenge or closing <= tuning.foul_min_closing_speed + EPSILON:
		result.reason = &"ordinary_body_contact"
		return result
	if closing > tuning.foul_reckless_closing_speed + EPSILON:
		result.foul_verdict = Types.FoulVerdict.RECKLESS
	elif contact.ball_touched_first and contact.ball_touch_tick >= started and contact.ball_touch_tick <= contact.tick:
		result.foul_verdict = Types.FoulVerdict.CLEAN
		result.reason = &"clean_ball_first_challenge"
		return result
	else:
		result.foul_verdict = Types.FoulVerdict.LATE
	if state.period_state == Types.PeriodState.EXTENDED_KICK:
		result.reason = &"extended_kick_contact_ends_play"
		return result
	var spot: Vector3 = _floor_spot(contact.point)
	var penalty: bool = _inside_penalty_area(spot, actor.team_id, state, tuning)
	var kind: Types.RestartKind = Types.RestartKind.PENALTY_6M if penalty else Types.RestartKind.DIRECT_FREE_KICK
	if not penalty and state.accumulated_fouls[actor.team_id] + 1 >= 6:
		kind = Types.RestartKind.ACCUMULATED_FREE_KICK
	result.kind = Types.DecisionKind.FOUL
	result.offender_actor_id = actor.actor_id
	result.victim_actor_id = opponent.actor_id
	result.counts_as_accumulated_foul = not penalty
	result.reason = &"reckless_challenge" if result.foul_verdict == Types.FoulVerdict.RECKLESS else &"late_challenge"
	result.restart = _new_restart(kind, 1 - actor.team_id, spot, Types.Border.NONE, state, tuning)
	return result


static func expiry_decision(state: Snapshot, tuning: Tuning) -> Types.RuleDecision:
	var result: Types.RuleDecision = _none(&"not_expired")
	if state == null or tuning == null or state.restart == null:
		result.reason = &"invalid_restart_state"
		return result
	if not _expired(state):
		return result
	if state.period_state == Types.PeriodState.EXTENDED_KICK:
		result.reason = &"extended_kick_expired"
		return result
	var kind: Types.RestartKind
	match state.restart.kind:
		Types.RestartKind.KICK_IN:
			kind = Types.RestartKind.KICK_IN
		Types.RestartKind.CORNER:
			kind = Types.RestartKind.GOAL_CLEARANCE
		Types.RestartKind.GOAL_CLEARANCE, Types.RestartKind.DIRECT_FREE_KICK, Types.RestartKind.INDIRECT_FREE_KICK, Types.RestartKind.ACCUMULATED_FREE_KICK:
			kind = Types.RestartKind.INDIRECT_FREE_KICK
		_:
			result.reason = &"unsupported_restart_expiry"
			return result
	return _restart_decision(kind, 1 - state.restart.awarded_team_id, state.restart.spot, state.restart.border, state, tuning, &"expired")


static func placement_plan(state: Snapshot, tuning: Tuning) -> Array[Types.ActorPlacement]:
	var result: Array[Types.ActorPlacement] = []
	if state == null or tuning == null or state.restart == null or state.phase != Snapshot.Phase.RESTART_PAUSE or not _valid_restart_kind(state.restart.kind):
		return result
	var taker: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
	if taker == null or taker.team_id != state.restart.awarded_team_id or _spot_error(state, tuning) != OK:
		return result
	var at: Vector3 = _taker_position(taker, state, tuning)
	if not at.is_finite():
		return result
	result.append(_placement(taker.actor_id, at, state.restart.spot - at))
	var occupied: Dictionary[int, Vector3] = {taker.actor_id: at}
	var pending: Array[int] = []
	var ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if not actor.position.is_finite() or actor.team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
			result.clear()
			return result
		if actor.actor_id != taker.actor_id:
			if actor.actor_id in ids:
				result.clear()
				return result
			ids.append(actor.actor_id)
	ids.sort()
	for id: int in ids:
		var actor: Snapshot.ActorSnapshot = state.actor(id)
		if _position_legal(actor, actor.position, state, tuning) and _separated(actor.position, occupied):
			occupied[id] = actor.position
		else:
			pending.append(id)
	for id: int in pending:
		var actor: Snapshot.ActorSnapshot = state.actor(id)
		var candidate: Vector3 = _project_position(actor, actor.position, state, tuning)
		if not _position_legal(actor, candidate, state, tuning) or not _separated(candidate, occupied):
			candidate = _find_placement(actor, state, tuning, occupied)
		# An empty plan is an explicit failure: the authority must not enter READY.
		if not candidate.is_finite():
			result.clear()
			return result
		occupied[id] = candidate
	for iteration: int in 5:
		var projected: Snapshot = _placement_view(state, occupied)
		var invalid: Array[int] = []
		for id: int in ids:
			if not _position_legal(projected.actor(id), occupied[id], projected, tuning):
				invalid.append(id)
		if invalid.is_empty():
			for id: int in ids:
				if _flat_distance(state.actor(id).position, occupied[id]) > EPSILON:
					result.append(_placement(id, occupied[id], state.restart.spot - occupied[id]))
			return result
		for id: int in invalid:
			occupied.erase(id)
			var replacement: Vector3 = _find_placement(projected.actor(id), projected, tuning, occupied)
			if not replacement.is_finite():
				result.clear()
				return result
			occupied[id] = replacement
	result.clear()
	return result


static func allowed_actions(actor_id: int, state: Snapshot) -> Array[Command.Action]:
	var result: Array[Command.Action] = []
	if state == null:
		return result
	var actor: Snapshot.ActorSnapshot = state.actor(actor_id)
	if actor == null:
		return result
	result.append(Command.Action.NONE)
	if state.phase == Snapshot.Phase.PLAYING:
		if state.period_state == Types.PeriodState.EXTENDED_KICK:
			return result
		if state.ball_owner_id == actor_id:
			if actor.action_cooldown > 0.0 or not actor.ball_contact_reachable or (_untouched_restart(state) and state.restart.taker_actor_id == actor_id):
				return result
			if actor.role == Snapshot.Role.KEEPER and actor.ball_in_hands:
				result.append(Command.Action.KEEPER_THROW)
			else:
				result.append(Command.Action.PASS)
				result.append(Command.Action.DRIBBLE)
				if _may_shoot(actor, state):
					result.append(Command.Action.SHOOT)
		else:
			if actor.action_cooldown <= 0.0:
				result.append(Command.Action.TACKLE)
			if actor_id == state.selected_actor_id and actor.team_id == Snapshot.Team.HOME:
				result.append(Command.Action.SWITCH_TEAMMATE)
		return result
	if state.phase != Snapshot.Phase.RESTART_PAUSE or state.restart == null or not _valid_restart_kind(state.restart.kind) or state.restart.stage != Types.RestartStage.READY or _expired(state) or not _extension_valid(state):
		return result
	if actor_id == state.restart.taker_actor_id and actor.team_id == state.restart.awarded_team_id:
		return _restart_actions(actor, state)
	if actor_id == state.selected_actor_id and actor.team_id == Snapshot.Team.HOME and state.restart.awarded_team_id != actor.team_id:
		result.append(Command.Action.SWITCH_TEAMMATE)
	return result


static func can_move(actor_id: int, state: Snapshot) -> bool:
	if state == null or state.actor(actor_id) == null or not _extension_valid(state):
		return false
	if state.phase == Snapshot.Phase.PLAYING:
		if state.period_state != Types.PeriodState.EXTENDED_KICK:
			return true
		return state.restart != null and state.restart.stage == Types.RestartStage.IN_PLAY \
			and state.restart.id == state.extended_restart_id and state.actor(actor_id).role == Snapshot.Role.KEEPER \
			and state.actor(actor_id).team_id != state.restart.awarded_team_id
	return state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart != null \
		and _valid_restart_kind(state.restart.kind) and state.restart.stage == Types.RestartStage.READY \
		and not _expired(state) and actor_id != state.restart.taker_actor_id


static func constrain_displacement(actor_id: int, displacement: Vector3, state: Snapshot, tuning: Tuning) -> Vector3:
	if tuning == null or not displacement.is_finite() or not can_move(actor_id, state):
		return Vector3.ZERO
	if state.phase == Snapshot.Phase.PLAYING:
		return displacement
	var actor: Snapshot.ActorSnapshot = state.actor(actor_id)
	if not _position_legal(actor, actor.position, state, tuning):
		return Vector3.ZERO
	if _motion_legal(actor, actor.position, actor.position + displacement, state, tuning):
		return displacement
	var low: float = 0.0
	var high: float = 1.0
	for iteration: int in 22:
		var fraction: float = (low + high) * 0.5
		if _motion_legal(actor, actor.position, actor.position + displacement * fraction, state, tuning):
			low = fraction
		else:
			high = fraction
	return displacement * low


static func launch_error(command: Command, state: Snapshot, velocity: Vector3, effective_target_actor_id: int, tuning: Tuning) -> Error:
	if command == null or state == null or tuning == null or not velocity.is_finite():
		return ERR_INVALID_PARAMETER
	if not _extension_valid(state):
		return ERR_UNAVAILABLE
	var actor: Snapshot.ActorSnapshot = state.actor(command.actor_id)
	if actor == null or command.action not in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		return ERR_INVALID_PARAMETER
	if not command.aim.is_finite() or command.aim.length_squared() > 1.00001 or not is_finite(command.shot_charge) or command.shot_charge < 0.0 or command.shot_charge > 1.0 or not is_finite(command.shot_lift) or command.shot_lift < 0.0 or command.shot_lift > 1.0:
		return ERR_INVALID_PARAMETER
	if velocity.length_squared() <= EPSILON * EPSILON or velocity.length() > tuning.maximum_ball_speed + EPSILON:
		return ERR_INVALID_PARAMETER
	if command.action == Command.Action.SHOOT and (command.target_actor_id != -1 or effective_target_actor_id != -1):
		return ERR_INVALID_PARAMETER
	if command.target_actor_id < -1 or effective_target_actor_id < -1:
		return ERR_INVALID_PARAMETER
	for target_id: int in [command.target_actor_id, effective_target_actor_id]:
		if target_id >= 0:
			var target: Snapshot.ActorSnapshot = state.actor(target_id)
			if target == null or target.actor_id == actor.actor_id or target.team_id != actor.team_id:
				return ERR_INVALID_PARAMETER
	if command.target_actor_id >= 0 and effective_target_actor_id >= 0 and command.target_actor_id != effective_target_actor_id:
		return ERR_INVALID_PARAMETER
	if command.action == Command.Action.SHOOT and not _may_shoot(actor, state):
		return ERR_UNAUTHORIZED
	if actor.team_id == Snapshot.Team.HOME and actor.actor_id != state.selected_actor_id and effective_target_actor_id < 0:
		return ERR_UNAUTHORIZED
	if command.action == Command.Action.KEEPER_THROW and actor.role != Snapshot.Role.KEEPER:
		return ERR_UNAUTHORIZED
	if state.phase == Snapshot.Phase.PLAYING:
		return OK if command.action in allowed_actions(actor.actor_id, state) else ERR_UNAVAILABLE
	if state.phase != Snapshot.Phase.RESTART_PAUSE or state.restart == null or actor.actor_id != state.restart.taker_actor_id or actor.team_id != state.restart.awarded_team_id:
		return ERR_UNAVAILABLE
	if state.restart.stage not in [Types.RestartStage.STOPPED, Types.RestartStage.PLACEMENT, Types.RestartStage.READY] or _expired(state):
		return ERR_UNAVAILABLE
	if command.action not in _restart_actions(actor, state):
		return ERR_UNAUTHORIZED
	var spot_error: Error = _spot_error(state, tuning)
	if spot_error != OK:
		return spot_error
	if state.restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		if velocity.dot(_attack_direction(state.restart.awarded_team_id, state)) <= EPSILON:
			return ERR_INVALID_PARAMETER
	if state.restart.stage == Types.RestartStage.READY:
		if not actor.ball_contact_reachable or _flat_distance(state.ball_position, state.restart.spot) > 0.04 or state.ball_velocity.length() > 0.05:
			return ERR_UNAVAILABLE
		if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE and not actor.ball_in_hands:
			return ERR_UNAVAILABLE
		if _flat_distance(actor.position, state.restart.spot) > tuning.control_leash or not _clear_of_posts(actor.position):
			return ERR_UNAVAILABLE
		var occupied: Dictionary[int, Vector3] = {}
		for participant: Snapshot.ActorSnapshot in state.actors:
			if participant.actor_id != actor.actor_id and not _position_legal(participant, participant.position, state, tuning):
				return ERR_UNAVAILABLE
			if not _separated(participant.position, occupied):
				return ERR_UNAVAILABLE
			occupied[participant.actor_id] = participant.position
	# Preparatory vectors may be previewed, but allowed_actions still prohibits their execution.
	return OK


static func project_to_penalty_area_line(point: Vector3, defending_team_id: int, state: Snapshot, tuning: Tuning) -> Vector3:
	if state == null or tuning == null or not point.is_finite() or defending_team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
		return Vector3.INF
	var lateral: float = maxf(0.0, absf(point.z) - Tuning.GOAL_POST_OUTER_Z)
	if lateral > Tuning.PENALTY_RADIUS + EPSILON:
		return Vector3(INF, point.y, point.z)
	var depth: float = sqrt(maxf(0.0, Tuning.PENALTY_RADIUS * Tuning.PENALTY_RADIUS - lateral * lateral))
	var own_end: float = -_attack_direction(defending_team_id, state).x
	return Vector3(own_end * (Tuning.COURT_LENGTH * 0.5 - depth), point.y, point.z)


static func _none(reason: StringName) -> Types.RuleDecision:
	var result: Types.RuleDecision = Types.RuleDecision.new()
	result.kind = Types.DecisionKind.NONE
	result.scoring_team_id = -1
	result.offender_actor_id = -1
	result.victim_actor_id = -1
	result.contact_id = -1
	result.foul_verdict = Types.FoulVerdict.NONE
	result.counts_as_accumulated_foul = false
	result.restart = Types.RestartState.new()
	result.reason = reason
	return result


static func _restart_decision(kind: Types.RestartKind, team: int, point: Vector3, border: Types.Border, state: Snapshot, tuning: Tuning, reason: StringName) -> Types.RuleDecision:
	var result: Types.RuleDecision = _none(reason)
	if team not in [Snapshot.Team.HOME, Snapshot.Team.AWAY] or not point.is_finite():
		result.reason = &"invalid_restart_award"
		return result
	result.kind = Types.DecisionKind.RESTART
	result.position = point
	result.restart = _new_restart(kind, team, point, border, state, tuning)
	return result


static func _new_restart(kind: Types.RestartKind, team: int, point: Vector3, border: Types.Border, state: Snapshot, tuning: Tuning) -> Types.RestartState:
	var restart: Types.RestartState = Types.RestartState.new()
	restart.id = 0
	restart.kind = kind
	restart.stage = Types.RestartStage.STOPPED
	restart.awarded_team_id = team
	restart.border = border
	restart.spot = _floor_spot(point)
	restart.offence_spot = restart.spot
	restart.spot_choice = Types.SpotChoice.DEFAULT
	restart.has_spot_choice = false
	restart.stage_started_tick = state.tick
	restart.placement_end_tick = state.tick + PLACEMENT_TICKS
	restart.ready_tick = -1
	restart.deadline_tick = -1
	restart.minimum_opponent_distance = 0.0 if kind == Types.RestartKind.GOAL_CLEARANCE else 5.0
	restart.direct_opponent_goal_allowed = _direct_goal_allowed(kind)
	restart.requires_direct_shot = kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
	restart.other_actor_touched = false
	match kind:
		Types.RestartKind.KICK_IN:
			var side: float = -1.0 if border == Types.Border.NEG_Z or (border == Types.Border.NONE and point.z < 0.0) else 1.0
			restart.spot = Vector3(clampf(point.x, -20.0, 20.0), Tuning.BALL_RADIUS, side * Tuning.COURT_WIDTH * 0.5)
			restart.border = Types.Border.NEG_Z if side < 0.0 else Types.Border.POS_Z
		Types.RestartKind.CORNER:
			var end: float = _attack_direction(team, state).x
			var side: float = -1.0 if point.z < 0.0 else 1.0
			restart.spot = Vector3(end * (Tuning.COURT_LENGTH * 0.5 - 0.12), Tuning.BALL_RADIUS, side * (Tuning.COURT_WIDTH * 0.5 - 0.12))
			restart.border = Types.Border.NEG_X if end < 0.0 else Types.Border.POS_X
		Types.RestartKind.GOAL_CLEARANCE:
			var keeper: Snapshot.ActorSnapshot = _keeper_for(team, state)
			var side: float = clampf(keeper.position.z, -3.0, 3.0) if keeper != null else 0.0
			restart.spot = Vector3(-_attack_direction(team, state).x * 18.0, tuning.keeper_hand_height, side)
		Types.RestartKind.INDIRECT_FREE_KICK:
			if _inside_penalty_area(restart.spot, 1 - team, state, tuning):
				restart.spot = project_to_penalty_area_line(restart.spot, 1 - team, state, tuning)
		Types.RestartKind.PENALTY_6M:
			restart.spot = _penalty_mark(team, 6.0, state)
		Types.RestartKind.ACCUMULATED_FREE_KICK:
			restart.spot = _penalty_mark(team, 10.0, state)
			restart.has_spot_choice = _offence_spot_eligible(restart.offence_spot, team, state, tuning)
			restart.spot_choice = Types.SpotChoice.TEN_METRE
	restart.taker_actor_id = _pick_taker(team, kind, restart.spot, state)
	return restart


static func _attack_direction(team: int, state: Snapshot) -> Vector3:
	var setup: Setup = Setup.new()
	setup.mode = state.mode
	setup.training_exercise = state.training_exercise
	return setup.attack_direction(team)


static func _attacking_team(end: float, state: Snapshot) -> int:
	for team: int in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
		if is_equal_approx(_attack_direction(team, state).x, end):
			return team
	return -1


static func _keeper_for(team: int, state: Snapshot) -> Snapshot.ActorSnapshot:
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id == team and actor.role == Snapshot.Role.KEEPER:
			return actor
	return null


static func _pick_taker(team: int, kind: Types.RestartKind, spot: Vector3, state: Snapshot) -> int:
	if kind == Types.RestartKind.GOAL_CLEARANCE:
		var keeper: Snapshot.ActorSnapshot = _keeper_for(team, state)
		return keeper.actor_id if keeper != null else -1
	var best: int = -1
	var best_distance: float = INF
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id != team:
			continue
		var distance: float = _flat_distance(actor.position, spot) + (50.0 if actor.role == Snapshot.Role.KEEPER else 0.0)
		if best < 0 or distance < best_distance - EPSILON or (is_equal_approx(distance, best_distance) and actor.actor_id < best):
			best = actor.actor_id
			best_distance = distance
	return best


static func _restart_actions(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Array[Command.Action]:
	var result: Array[Command.Action] = [Command.Action.NONE]
	if not _valid_restart_kind(state.restart.kind):
		return result
	match state.restart.kind:
		Types.RestartKind.GOAL_CLEARANCE:
			if actor.role == Snapshot.Role.KEEPER:
				result.append(Command.Action.KEEPER_THROW)
		Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK:
			# The 0.4 control contract exposes shots only for both penalty variants.
			if _may_shoot(actor, state):
				result.append(Command.Action.SHOOT)
			if state.restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK and state.restart.has_spot_choice:
				result.append(Command.Action.CHOOSE_RESTART_SPOT)
		_:
			result.append(Command.Action.PASS)
			if _may_shoot(actor, state):
				result.append(Command.Action.SHOOT)
	return result


static func _may_shoot(actor: Snapshot.ActorSnapshot, state: Snapshot) -> bool:
	return actor.team_id != Snapshot.Team.HOME or actor.actor_id == state.selected_actor_id


static func _expired(state: Snapshot) -> bool:
	return state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart != null \
		and state.restart.stage == Types.RestartStage.READY and state.restart.kind != Types.RestartKind.PENALTY_6M \
		and state.restart.deadline_tick >= 0 and state.tick >= state.restart.deadline_tick


static func _extension_valid(state: Snapshot) -> bool:
	return state.period_state != Types.PeriodState.EXTENDED_KICK or (state.restart != null \
		and state.restart.id == state.extended_restart_id \
		and state.restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK])


static func _untouched_restart(state: Snapshot) -> bool:
	return state.restart != null and _valid_restart_kind(state.restart.kind) \
		and state.restart.stage == Types.RestartStage.IN_PLAY and not state.restart.other_actor_touched


static func _valid_restart_kind(kind: Types.RestartKind) -> bool:
	return kind >= Types.RestartKind.KICK_IN and kind <= Types.RestartKind.ACCUMULATED_FREE_KICK


static func _valid_border(border: Types.Border) -> bool:
	return border >= Types.Border.NEG_X and border <= Types.Border.POS_Z


static func _border_end(border: Types.Border) -> float:
	return -1.0 if border == Types.Border.NEG_X else (1.0 if border == Types.Border.POS_X else 0.0)


static func _crossing_on_border(crossing: Types.BoundaryCrossing) -> bool:
	var end: float = _border_end(crossing.border)
	if end != 0.0:
		return absf(crossing.position.x - end * (Tuning.COURT_LENGTH * 0.5 + Tuning.BALL_RADIUS)) <= EPSILON
	var side: float = -1.0 if crossing.border == Types.Border.NEG_Z else 1.0
	return absf(crossing.position.z - side * (Tuning.COURT_WIDTH * 0.5 + Tuning.BALL_RADIUS)) <= EPSILON


static func _direct_goal_allowed(kind: Types.RestartKind) -> bool:
	return kind in [Types.RestartKind.CORNER, Types.RestartKind.DIRECT_FREE_KICK, Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]


static func _through_goal(point: Vector3) -> bool:
	return absf(point.z) + Tuning.BALL_RADIUS <= Tuning.GOAL_WIDTH * 0.5 + EPSILON \
		and point.y + Tuning.BALL_RADIUS <= Tuning.GOAL_HEIGHT + EPSILON \
		and point.y >= Tuning.BALL_RADIUS - FLOOR_CONTACT_SLOP


static func _floor_spot(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -Tuning.COURT_LENGTH * 0.5, Tuning.COURT_LENGTH * 0.5), Tuning.BALL_RADIUS, clampf(point.z, -Tuning.COURT_WIDTH * 0.5, Tuning.COURT_WIDTH * 0.5))


static func _penalty_mark(attacking_team: int, distance: float, state: Snapshot) -> Vector3:
	return Vector3(_attack_direction(attacking_team, state).x * (Tuning.COURT_LENGTH * 0.5 - distance), Tuning.BALL_RADIUS, 0.0)


static func _inside_penalty_area(point: Vector3, team: int, state: Snapshot, tuning: Tuning, margin: float = 0.0) -> bool:
	if tuning == null or not point.is_finite() or team not in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
		return false
	var own_end: float = -_attack_direction(team, state).x
	var depth: float = Tuning.COURT_LENGTH * 0.5 - own_end * point.x
	var lateral: float = maxf(0.0, absf(point.z) - Tuning.GOAL_POST_OUTER_Z)
	var radius: float = Tuning.PENALTY_RADIUS + margin
	return depth >= -EPSILON and depth * depth + lateral * lateral <= radius * radius + EPSILON


static func _offence_spot_eligible(point: Vector3, attacking_team: int, state: Snapshot, tuning: Tuning) -> bool:
	var depth: float = Tuning.COURT_LENGTH * 0.5 - point.x * _attack_direction(attacking_team, state).x
	return point.is_finite() and depth > EPSILON and depth < 10.0 - EPSILON \
		and absf(point.z) <= Tuning.COURT_WIDTH * 0.5 \
		and not _inside_penalty_area(point, 1 - attacking_team, state, tuning)


static func _spot_error(state: Snapshot, tuning: Tuning) -> Error:
	var restart: Types.RestartState = state.restart
	if restart == null or restart.awarded_team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY] or not restart.spot.is_finite():
		return ERR_INVALID_DATA
	var point: Vector3 = restart.spot
	match restart.kind:
		Types.RestartKind.KICK_IN:
			return OK if absf(absf(point.z) - Tuning.COURT_WIDTH * 0.5) <= EPSILON and absf(point.x) <= Tuning.COURT_LENGTH * 0.5 + EPSILON else ERR_INVALID_DATA
		Types.RestartKind.CORNER:
			return OK if _flat_distance(point, _corner(state)) <= CORNER_RADIUS + EPSILON and absf(point.x) <= 20.0 and absf(point.z) <= 10.0 else ERR_INVALID_DATA
		Types.RestartKind.GOAL_CLEARANCE:
			return OK if _inside_penalty_area(point, restart.awarded_team_id, state, tuning) else ERR_INVALID_DATA
		Types.RestartKind.DIRECT_FREE_KICK:
			return OK if absf(point.x) <= 20.0 and absf(point.z) <= 10.0 and not _inside_penalty_area(point, 1 - restart.awarded_team_id, state, tuning) else ERR_INVALID_DATA
		Types.RestartKind.INDIRECT_FREE_KICK:
			return OK if absf(point.x) <= 20.0 and absf(point.z) <= 10.0 and not _inside_penalty_area(point, 1 - restart.awarded_team_id, state, tuning, -0.001) else ERR_INVALID_DATA
		Types.RestartKind.PENALTY_6M:
			return OK if _flat_distance(point, _penalty_mark(restart.awarded_team_id, 6.0, state)) <= EPSILON else ERR_INVALID_DATA
		Types.RestartKind.ACCUMULATED_FREE_KICK:
			if restart.spot_choice in [Types.SpotChoice.DEFAULT, Types.SpotChoice.TEN_METRE]:
				return OK if _flat_distance(point, _penalty_mark(restart.awarded_team_id, 10.0, state)) <= EPSILON else ERR_INVALID_DATA
			if restart.spot_choice == Types.SpotChoice.OFFENCE_SPOT:
				return OK if restart.has_spot_choice and _offence_spot_eligible(restart.offence_spot, restart.awarded_team_id, state, tuning) and _flat_distance(point, restart.offence_spot) <= EPSILON else ERR_INVALID_DATA
	return ERR_INVALID_DATA


static func _corner(state: Snapshot) -> Vector3:
	var end: float = _attack_direction(state.restart.awarded_team_id, state).x
	var side: float = -1.0 if state.restart.spot.z < 0.0 else 1.0
	return Vector3(end * Tuning.COURT_LENGTH * 0.5, Tuning.BALL_RADIUS, side * Tuning.COURT_WIDTH * 0.5)


static func _placement(id: int, at: Vector3, facing: Vector3) -> Types.ActorPlacement:
	var result: Types.ActorPlacement = Types.ActorPlacement.new()
	result.actor_id = id
	result.position = Vector3(at.x, 0.0, at.z)
	result.forward = Vector2(facing.x, facing.z).normalized()
	if result.forward.is_zero_approx():
		result.forward = Vector2.RIGHT
	return result


static func _taker_position(actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> Vector3:
	var direction: Vector3 = _attack_direction(actor.team_id, state)
	if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
		var keeper_at: Vector3 = state.restart.spot - direction * tuning.keeper_hand_forward
		keeper_at.y = 0.0
		return keeper_at if _inside_penalty_area(keeper_at, actor.team_id, state, tuning) and _clear_of_posts(keeper_at) else Vector3.INF
	if state.restart.kind == Types.RestartKind.KICK_IN:
		direction = Vector3(direction.x * 0.25, 0.0, -signf(state.restart.spot.z)).normalized()
	elif state.restart.kind == Types.RestartKind.CORNER:
		direction = Vector3(-signf(state.restart.spot.x), 0.0, -signf(state.restart.spot.z)).normalized()
	var distance: float = Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 0.08
	var desired: Vector3 = state.restart.spot - direction * distance
	desired.y = 0.0
	var outside_allowed: bool = state.restart.kind in [Types.RestartKind.KICK_IN, Types.RestartKind.CORNER]
	if not outside_allowed:
		desired = _clamp_pitch(desired)
	for index: int in 17:
		var candidate: Vector3 = desired
		if index > 0:
			var angle: float = TAU * float(index - 1) / 16.0
			candidate = state.restart.spot + Vector3(cos(angle), 0.0, sin(angle)) * distance
			candidate.y = 0.0
			if not outside_allowed and candidate != _clamp_pitch(candidate):
				continue
		if _flat_distance(candidate, state.restart.spot) < Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + PLACEMENT_MARGIN or not _clear_of_posts(candidate):
			continue
		if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE and not _inside_penalty_area(candidate, actor.team_id, state, tuning):
			continue
		return candidate
	return Vector3.INF


static func _ball_distance(actor: Snapshot.ActorSnapshot, state: Snapshot) -> float:
	var distance: float = Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 0.18
	var restart: Types.RestartState = state.restart
	var defending_keeper: bool = actor.team_id != restart.awarded_team_id and actor.role == Snapshot.Role.KEEPER
	if restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		if not defending_keeper or restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK:
			distance = 5.0
	elif actor.team_id != restart.awarded_team_id and restart.kind != Types.RestartKind.GOAL_CLEARANCE:
		distance = 5.0
	return distance


static func _excluded_area(actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning) -> int:
	var restart: Types.RestartState = state.restart
	if restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		return -1 if actor.team_id != restart.awarded_team_id and actor.role == Snapshot.Role.KEEPER else 1 - restart.awarded_team_id
	if actor.team_id != restart.awarded_team_id and (restart.kind == Types.RestartKind.GOAL_CLEARANCE or (restart.kind in [Types.RestartKind.DIRECT_FREE_KICK, Types.RestartKind.INDIRECT_FREE_KICK] and _inside_penalty_area(restart.spot, restart.awarded_team_id, state, tuning))):
		return restart.awarded_team_id
	return -1


static func _behind_ball(actor: Snapshot.ActorSnapshot, state: Snapshot) -> bool:
	return state.restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK] \
		and not (actor.team_id != state.restart.awarded_team_id and actor.role == Snapshot.Role.KEEPER)


static func _penalty_keeper(actor: Snapshot.ActorSnapshot, state: Snapshot) -> bool:
	return state.restart.kind == Types.RestartKind.PENALTY_6M and actor.team_id != state.restart.awarded_team_id and actor.role == Snapshot.Role.KEEPER


static func _position_legal(actor: Snapshot.ActorSnapshot, point: Vector3, state: Snapshot, tuning: Tuning) -> bool:
	if not point.is_finite() or not _clear_of_posts(point):
		return false
	if _penalty_keeper(actor, state):
		return absf(point.x - _penalty_mark(state.restart.awarded_team_id, 0.0, state).x) <= EPSILON \
			and absf(point.z) <= Tuning.GOAL_WIDTH * 0.5 - Tuning.ACTOR_RADIUS - PLACEMENT_MARGIN
	if point != _clamp_pitch(point):
		return false
	var reference: Vector3 = state.restart.spot
	var distance: float = _ball_distance(actor, state)
	if state.restart.kind == Types.RestartKind.CORNER and actor.team_id != state.restart.awarded_team_id:
		reference = _corner(state)
		distance = 5.0 + CORNER_RADIUS
	if _flat_distance(point, reference) < distance - EPSILON:
		return false
	if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
		var keeper: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
		if keeper == null or _flat_distance(point, keeper.position) < _hand_clearance(tuning) - EPSILON:
			return false
	if _behind_ball(actor, state) and (point - state.restart.spot).dot(_attack_direction(state.restart.awarded_team_id, state)) > EPSILON:
		return false
	var area: int = _excluded_area(actor, state, tuning)
	if area >= 0 and _inside_penalty_area(point, area, state, tuning):
		return false
	for member: Snapshot.ActorSnapshot in _wall_members(actor, state):
		if _flat_distance(point, member.position) < 1.0 - EPSILON:
			return false
	return true


static func _project_position(actor: Snapshot.ActorSnapshot, point: Vector3, state: Snapshot, tuning: Tuning) -> Vector3:
	var result: Vector3 = _clamp_pitch(point)
	var attack: Vector3 = _attack_direction(state.restart.awarded_team_id, state)
	if _penalty_keeper(actor, state):
		return Vector3(attack.x * Tuning.COURT_LENGTH * 0.5, 0.0, clampf(point.z, -1.15, 1.15))
	for iteration: int in 8:
		if _behind_ball(actor, state) and (result - state.restart.spot).dot(attack) > -PLACEMENT_MARGIN:
			result.x = state.restart.spot.x - attack.x * PLACEMENT_MARGIN
		var reference: Vector3 = state.restart.spot
		var distance: float = _ball_distance(actor, state) + PLACEMENT_MARGIN
		if state.restart.kind == Types.RestartKind.CORNER and actor.team_id != state.restart.awarded_team_id:
			reference = _corner(state)
			distance = 5.0 + CORNER_RADIUS + PLACEMENT_MARGIN
		result = _push_from(result, reference, distance, -attack)
		if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
			var keeper: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
			if keeper != null:
				result = _push_from(result, keeper.position, _hand_clearance(tuning) + PLACEMENT_MARGIN, attack)
		var area: int = _excluded_area(actor, state, tuning)
		if area >= 0 and _inside_penalty_area(result, area, state, tuning):
			result = project_to_penalty_area_line(result, area, state, tuning) + _attack_direction(area, state) * PLACEMENT_MARGIN
		for member: Snapshot.ActorSnapshot in _wall_members(actor, state):
			result = _push_from(result, member.position, 1.0 + PLACEMENT_MARGIN, -attack)
		result = _clamp_pitch(result)
		if _position_legal(actor, result, state, tuning):
			return result
	return result


static func _find_placement(actor: Snapshot.ActorSnapshot, state: Snapshot, tuning: Tuning, occupied: Dictionary[int, Vector3]) -> Vector3:
	for ring: int in range(1, 9):
		for index: int in 16:
			var angle: float = TAU * float((index + actor.actor_id * 3) % 16) / 16.0
			var proposed: Vector3 = actor.position + Vector3(cos(angle), 0.0, sin(angle)) * float(ring) * 0.8
			var candidate: Vector3 = _project_position(actor, proposed, state, tuning)
			if _position_legal(actor, candidate, state, tuning) and _separated(candidate, occupied):
				return candidate
	for x: int in range(-19, 20):
		for z: int in range(-9, 10):
			var candidate: Vector3 = _project_position(actor, Vector3(x, 0.0, z), state, tuning)
			if _position_legal(actor, candidate, state, tuning) and _separated(candidate, occupied):
				return candidate
	return Vector3.INF


static func _placement_view(state: Snapshot, positions: Dictionary[int, Vector3]) -> Snapshot:
	var result: Snapshot = Snapshot.new()
	result.mode = state.mode
	result.phase = state.phase
	result.training_exercise = state.training_exercise
	result.selected_actor_id = state.selected_actor_id
	result.restart = state.restart.copy()
	for actor: Snapshot.ActorSnapshot in state.actors:
		var item: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		item.actor_id = actor.actor_id
		item.team_id = actor.team_id
		item.role = actor.role
		item.position = positions[actor.actor_id]
		result.actors.append(item)
	return result


static func _motion_legal(actor: Snapshot.ActorSnapshot, from: Vector3, to: Vector3, state: Snapshot, tuning: Tuning) -> bool:
	if not _position_legal(actor, to, state, tuning):
		return false
	var reference: Vector3 = state.restart.spot
	var distance: float = _ball_distance(actor, state)
	if state.restart.kind == Types.RestartKind.CORNER and actor.team_id != state.restart.awarded_team_id:
		reference = _corner(state)
		distance = 5.0 + CORNER_RADIUS
	if _segment_distance(reference, from, to) < distance - EPSILON:
		return false
	if state.restart.kind == Types.RestartKind.GOAL_CLEARANCE:
		var keeper: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
		if keeper == null or _segment_distance(keeper.position, from, to) < _hand_clearance(tuning) - EPSILON:
			return false
	var area: int = _excluded_area(actor, state, tuning)
	if area >= 0:
		var own_x: float = -_attack_direction(area, state).x * Tuning.COURT_LENGTH * 0.5
		var low: Vector3 = Vector3(own_x, 0.0, -Tuning.GOAL_POST_OUTER_Z)
		var high: Vector3 = Vector3(own_x, 0.0, Tuning.GOAL_POST_OUTER_Z)
		if _segments_distance(from, to, low, high) <= Tuning.PENALTY_RADIUS + EPSILON:
			return false
	for member: Snapshot.ActorSnapshot in _wall_members(actor, state):
		if _segment_distance(member.position, from, to) < 1.0 - EPSILON:
			return false
	return true


static func _wall_members(actor: Snapshot.ActorSnapshot, state: Snapshot) -> Array[Snapshot.ActorSnapshot]:
	var result: Array[Snapshot.ActorSnapshot] = []
	if actor.team_id != state.restart.awarded_team_id or state.restart.kind not in [Types.RestartKind.DIRECT_FREE_KICK, Types.RestartKind.INDIRECT_FREE_KICK]:
		return result
	for candidate: Snapshot.ActorSnapshot in state.actors:
		if candidate.team_id == actor.team_id or _flat_distance(candidate.position, state.restart.spot) > 7.0:
			continue
		for neighbour: Snapshot.ActorSnapshot in state.actors:
			if neighbour.actor_id != candidate.actor_id and neighbour.team_id == candidate.team_id and _flat_distance(candidate.position, neighbour.position) <= 1.5:
				result.append(candidate)
				break
	return result


static func _clamp_pitch(point: Vector3) -> Vector3:
	var margin: float = Tuning.ACTOR_RADIUS + PLACEMENT_MARGIN
	return Vector3(clampf(point.x, -Tuning.COURT_LENGTH * 0.5 + margin, Tuning.COURT_LENGTH * 0.5 - margin), point.y, clampf(point.z, -Tuning.COURT_WIDTH * 0.5 + margin, Tuning.COURT_WIDTH * 0.5 - margin))


static func _hand_clearance(tuning: Tuning) -> float:
	return Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + tuning.keeper_hand_forward + PLACEMENT_MARGIN


static func _clear_of_posts(point: Vector3) -> bool:
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var delta: Vector2 = Vector2(absf(point.x - end * Tuning.COURT_LENGTH * 0.5), absf(point.z - side * Tuning.GOAL_POST_CENTER_Z))
			delta = (delta - Vector2.ONE * Tuning.POST_THICKNESS * 0.5).max(Vector2.ZERO)
			if delta.length() < Tuning.ACTOR_RADIUS + PLACEMENT_MARGIN:
				return false
	return true


static func _separated(point: Vector3, occupied: Dictionary[int, Vector3]) -> bool:
	for other: Vector3 in occupied.values():
		if _flat_distance(point, other) < Tuning.ACTOR_RADIUS * 2.0 + PLACEMENT_MARGIN:
			return false
	return true


static func _push_from(point: Vector3, origin: Vector3, distance: float, fallback: Vector3) -> Vector3:
	var delta: Vector3 = point - origin
	delta.y = 0.0
	if delta.length() >= distance:
		return point
	if delta.is_zero_approx():
		delta = fallback
	var result: Vector3 = origin + delta.normalized() * distance
	result.y = point.y
	return result


static func _segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var start: Vector2 = Vector2(from.x, from.z)
	var delta: Vector2 = Vector2(to.x - from.x, to.z - from.z)
	var at: Vector2 = Vector2(point.x, point.z)
	var fraction: float = clampf((at - start).dot(delta) / delta.length_squared(), 0.0, 1.0) if not delta.is_zero_approx() else 0.0
	return at.distance_to(start + delta * fraction)


static func _segments_distance(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	var first: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var second: Vector2 = Vector2(d.x - c.x, d.z - c.z)
	var offset: Vector2 = Vector2(c.x - a.x, c.z - a.z)
	var cross: float = first.cross(second)
	if absf(cross) > EPSILON:
		var along_first: float = offset.cross(second) / cross
		var along_second: float = offset.cross(first) / cross
		if along_first >= 0.0 and along_first <= 1.0 and along_second >= 0.0 and along_second <= 1.0:
			return 0.0
	return minf(minf(_segment_distance(a, c, d), _segment_distance(b, c, d)), minf(_segment_distance(c, a, b), _segment_distance(d, a, b)))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
