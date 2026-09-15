class_name MatchRuleTypes
extends RefCounted

enum RestartKind { NONE, KICK_IN, CORNER, GOAL_CLEARANCE, DIRECT_FREE_KICK, INDIRECT_FREE_KICK, PENALTY_6M, ACCUMULATED_FREE_KICK }
enum RestartStage { NONE, STOPPED, PLACEMENT, READY, IN_PLAY }
enum SpotChoice { DEFAULT, TEN_METRE, OFFENCE_SPOT }
enum ControlContext { DISABLED, LIVE, RESTART_AIM, RESTART_DEFEND }
enum FoulVerdict { NONE, CLEAN, LATE, RECKLESS }
enum GestureKind { NONE, CUT, PACE_CHANGE, TACKLE, FOOT_KICK, KEEPER_THROW }
enum LaunchKind { FOOT_PASS, FOOT_SHOT, KEEPER_THROW }
enum Border { NONE, NEG_X, POS_X, NEG_Z, POS_Z }
enum ContactKind { BALL_ACTOR, ACTOR_ACTOR }
enum DecisionKind { NONE, GOAL, RESTART, FOUL }
enum PeriodState { REGULATION, EXTENDED_KICK }


class RestartState extends RefCounted:
	var id: int = -1
	var awarded_team_id: int = -1
	var taker_actor_id: int = -1
	var launch_contact_id: int = -1
	var kind: RestartKind = RestartKind.NONE
	var stage: RestartStage = RestartStage.NONE
	var spot: Vector3 = Vector3.ZERO
	var offence_spot: Vector3 = Vector3.ZERO
	var border: Border = Border.NONE
	var spot_choice: SpotChoice = SpotChoice.DEFAULT
	var has_spot_choice: bool = false
	var stage_started_tick: int = -1
	var placement_end_tick: int = -1
	var ready_tick: int = -1
	var deadline_tick: int = -1
	var minimum_opponent_distance: float = 0.0
	var direct_opponent_goal_allowed: bool = false
	var requires_direct_shot: bool = false
	var other_actor_touched: bool = false

	func copy() -> RestartState:
		var result: RestartState = get_script().new()
		result.id = id
		result.awarded_team_id = awarded_team_id
		result.taker_actor_id = taker_actor_id
		result.launch_contact_id = launch_contact_id
		result.kind = kind
		result.stage = stage
		result.spot = spot
		result.offence_spot = offence_spot
		result.border = border
		result.spot_choice = spot_choice
		result.has_spot_choice = has_spot_choice
		result.stage_started_tick = stage_started_tick
		result.placement_end_tick = placement_end_tick
		result.ready_tick = ready_tick
		result.deadline_tick = deadline_tick
		result.minimum_opponent_distance = minimum_opponent_distance
		result.direct_opponent_goal_allowed = direct_opponent_goal_allowed
		result.requires_direct_shot = requires_direct_shot
		result.other_actor_touched = other_actor_touched
		return result


class BoundaryCrossing extends RefCounted:
	var border: Border = Border.NONE
	var fraction: float = INF
	var position: Vector3 = Vector3.ZERO
	var goal_team_id: int = -1

	func copy() -> BoundaryCrossing:
		var result: BoundaryCrossing = get_script().new()
		result.border = border
		result.fraction = fraction
		result.position = position
		result.goal_team_id = goal_team_id
		return result


class ContactEvidence extends RefCounted:
	var contact_id: int = -1
	var tick: int = -1
	var actor_id: int = -1
	var other_actor_id: int = -1
	var kind: ContactKind = ContactKind.BALL_ACTOR
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	var actor_velocity: Vector3 = Vector3.ZERO
	var other_velocity: Vector3 = Vector3.ZERO
	var tackle_started_tick: int = -1
	var ball_touch_tick: int = -1
	var ball_touched_first: bool = false

	func copy() -> ContactEvidence:
		var result: ContactEvidence = get_script().new()
		result.contact_id = contact_id
		result.tick = tick
		result.actor_id = actor_id
		result.other_actor_id = other_actor_id
		result.kind = kind
		result.point = point
		result.normal = normal
		result.actor_velocity = actor_velocity
		result.other_velocity = other_velocity
		result.tackle_started_tick = tackle_started_tick
		result.ball_touch_tick = ball_touch_tick
		result.ball_touched_first = ball_touched_first
		return result


class ActorPlacement extends RefCounted:
	var actor_id: int = -1
	var position: Vector3 = Vector3.ZERO
	var forward: Vector2 = Vector2.RIGHT

	func copy() -> ActorPlacement:
		var result: ActorPlacement = get_script().new()
		result.actor_id = actor_id
		result.position = position
		result.forward = forward
		return result


class RuleDecision extends RefCounted:
	var kind: DecisionKind = DecisionKind.NONE
	var scoring_team_id: int = -1
	var offender_actor_id: int = -1
	var victim_actor_id: int = -1
	var contact_id: int = -1
	var foul_verdict: FoulVerdict = FoulVerdict.NONE
	var position: Vector3 = Vector3.ZERO
	var reason: StringName = &""
	var restart: RestartState = RestartState.new()
	var counts_as_accumulated_foul: bool = false

	func copy() -> RuleDecision:
		var result: RuleDecision = get_script().new()
		result.kind = kind
		result.scoring_team_id = scoring_team_id
		result.offender_actor_id = offender_actor_id
		result.victim_actor_id = victim_actor_id
		result.contact_id = contact_id
		result.foul_verdict = foul_verdict
		result.position = position
		result.reason = reason
		result.restart = restart.copy()
		result.counts_as_accumulated_foul = counts_as_accumulated_foul
		return result
