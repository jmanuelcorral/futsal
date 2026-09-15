class_name MatchSetup
extends RefCounted

enum Mode { MICRO_1V1 = 0, PREVIEW_5V5 = 1 }
enum TrainingExercise {
	FREE_PLAY, KICK_IN, CORNER_POS_X_NEG_Z, CORNER_POS_X_POS_Z,
	CORNER_NEG_X_NEG_Z, CORNER_NEG_X_POS_Z, GOAL_CLEARANCE,
	DRIBBLE_CUT, DRIBBLE_PACE_CHANGE, DIRECT_FREE_KICK, PENALTY_6M, ACCUMULATED_FREE_KICK,
}

var mode: Mode = Mode.MICRO_1V1
var training_exercise: TrainingExercise = TrainingExercise.FREE_PLAY
var actor_positions: Dictionary[int, Vector3] = {
	0: Vector3(-2.0, 0.0, 0.0),
	1: Vector3(4.0, 0.0, 1.5),
	2: Vector3(-18.5, 0.0, 0.0),
	3: Vector3(18.5, 0.0, 0.0),
}
var actor_forwards: Dictionary[int, Vector2] = {
	0: Vector2.RIGHT, 1: Vector2.LEFT, 2: Vector2.RIGHT, 3: Vector2.LEFT,
}
var ai_actor_ids: Array[int] = [0, 1, 2, 3]
var ball_position: Vector3 = Vector3(-1.45, 0.12, 0.0)
var ball_velocity: Vector3 = Vector3.ZERO
var ball_angular_velocity: Vector3 = Vector3.ZERO


static func preview_5v5() -> MatchSetup:
	var result: MatchSetup = load("res://match/simulation/match_setup.gd").new()
	result.mode = Mode.PREVIEW_5V5
	result.actor_positions = {
		0: Vector3(-2.0, 0.0, 0.0), 1: Vector3(2.0, 0.0, 0.0),
		2: Vector3(-18.5, 0.0, 0.0), 3: Vector3(18.5, 0.0, 0.0),
		4: Vector3(-8.0, 0.0, -6.0), 5: Vector3(8.0, 0.0, -6.0),
		6: Vector3(-8.0, 0.0, 6.0), 7: Vector3(8.0, 0.0, 6.0),
		8: Vector3(-13.0, 0.0, 0.0), 9: Vector3(13.0, 0.0, 0.0),
	}
	result.actor_forwards = {
		0: Vector2.RIGHT, 1: Vector2.LEFT, 2: Vector2.RIGHT, 3: Vector2.LEFT,
		4: Vector2.RIGHT, 5: Vector2.LEFT, 6: Vector2.RIGHT, 7: Vector2.LEFT,
		8: Vector2.RIGHT, 9: Vector2.LEFT,
	}
	result.ai_actor_ids = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	return result


static func for_exercise(requested_mode: Mode, exercise: TrainingExercise) -> MatchSetup:
	var result: MatchSetup = preview_5v5() if requested_mode == Mode.PREVIEW_5V5 else load("res://match/simulation/match_setup.gd").new()
	result.mode = requested_mode
	result.training_exercise = exercise
	match exercise:
		TrainingExercise.KICK_IN:
			result.ball_position = Vector3(3.0, 0.12, -9.8)
		TrainingExercise.CORNER_POS_X_NEG_Z, TrainingExercise.CORNER_NEG_X_NEG_Z:
			result.ball_position = Vector3(19.85, 0.12, -9.85)
		TrainingExercise.CORNER_POS_X_POS_Z, TrainingExercise.CORNER_NEG_X_POS_Z:
			result.ball_position = Vector3(19.85, 0.12, 9.85)
		TrainingExercise.GOAL_CLEARANCE:
			result.ball_position = Vector3(-17.0, 0.12, 0.0)
		TrainingExercise.DRIBBLE_CUT, TrainingExercise.DRIBBLE_PACE_CHANGE:
			result.actor_positions[0] = Vector3(-3.0, 0.0, -2.0)
			result.actor_positions[1] = Vector3(0.5, 0.0, -2.0)
			result.ball_position = Vector3(-2.45, 0.12, -2.0)
		TrainingExercise.DIRECT_FREE_KICK:
			result.ball_position = Vector3(11.0, 0.12, -2.0)
		TrainingExercise.PENALTY_6M:
			result.ball_position = Vector3(14.0, 0.12, 0.0)
		TrainingExercise.ACCUMULATED_FREE_KICK:
			result.ball_position = Vector3(10.0, 0.12, 0.0)
	if result.attack_direction(0).x < 0.0:
		for id: int in result.actor_positions:
			var at: Vector3 = result.actor_positions[id]
			at.x = -at.x
			result.actor_positions[id] = at
			var forward: Vector2 = result.actor_forwards[id]
			forward.x = -forward.x
			result.actor_forwards[id] = forward
		result.ball_position.x = -result.ball_position.x
	return result


func attack_direction(team_id: int) -> Vector3:
	if team_id not in [0, 1]:
		push_error("MatchSetup.attack_direction requires HOME=0 or AWAY=1")
		return Vector3.ZERO
	var home_sign: float = -1.0 if training_exercise in [
		TrainingExercise.CORNER_NEG_X_NEG_Z, TrainingExercise.CORNER_NEG_X_POS_Z] else 1.0
	return Vector3(home_sign if team_id == 0 else -home_sign, 0.0, 0.0)


func copy() -> MatchSetup:
	var result: MatchSetup = get_script().new()
	result.mode = mode
	result.training_exercise = training_exercise
	result.actor_positions = actor_positions.duplicate()
	result.actor_forwards = actor_forwards.duplicate()
	result.ai_actor_ids = ai_actor_ids.duplicate()
	result.ball_position = ball_position
	result.ball_velocity = ball_velocity
	result.ball_angular_velocity = ball_angular_velocity
	return result
