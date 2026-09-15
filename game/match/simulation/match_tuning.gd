class_name MatchTuning
extends Resource

const COURT_LENGTH: float = 40.0
const COURT_WIDTH: float = 20.0
const GOAL_WIDTH: float = 3.0
const GOAL_HEIGHT: float = 2.0
const GOAL_DEPTH: float = 1.5
const POST_THICKNESS: float = 0.08
const PENALTY_RADIUS: float = 6.0
const GOAL_POST_CENTER_Z: float = GOAL_WIDTH * 0.5 + POST_THICKNESS * 0.5
const GOAL_POST_OUTER_Z: float = GOAL_WIDTH * 0.5 + POST_THICKNESS
const PENALTY_STRAIGHT_LENGTH: float = GOAL_POST_OUTER_Z * 2.0
const CORNER_ARC_RADIUS: float = 0.25
const RESTART_PLACEMENT_TICKS: int = 60
const RESTART_DEADLINE_TICKS: int = 240
const CORNER_CAMERA_TRANSITION_TICKS: int = 45
const NET_THICKNESS: float = 0.06
const BALL_RADIUS: float = 0.105
const BALL_MASS: float = 0.43
const ACTOR_RADIUS: float = 0.28
const ACTOR_HEIGHT: float = 1.75
const WORLD_LAYER: int = 1
const ACTOR_LAYER: int = 2
const BALL_LAYER: int = 4
const PHYSICS_HZ: int = 60
const NATIVE_JOLT_PROFILE: Dictionary[StringName, float] = {
	&"physics/jolt_physics_3d/simulation/penetration_slop": 0.002,
	&"physics/jolt_physics_3d/simulation/continuous_cd_max_penetration": 0.02,
	&"physics/jolt_physics_3d/simulation/continuous_cd_movement_threshold": 0.25,
	&"physics/jolt_physics_3d/limits/max_angular_velocity": 400.0,
}

@export var training_seconds: float = 120.0
@export var move_speed: float = 5.8
@export var sprint_speed: float = 8.0
@export var close_control_speed: float = 3.5
@export var keeper_speed: float = 5.2
@export var acceleration: float = 28.0
@export var braking: float = 36.0
@export var turn_speed: float = 14.0
@export var command_timeout: float = 0.25
@export var ai_interval: float = 0.12
@export var control_acceleration: float = 30.0
@export var receive_acceleration: float = 85.0
@export var keeper_control_acceleration: float = 65.0
@export var control_leash: float = 1.05
@export var receive_radius: float = 0.68
@export var receive_speed: float = 12.0
@export var keeper_receive_speed: float = 14.0
@export var rolling_resistance: float = 0.45
@export var ball_friction: float = 0.35
@export var ball_bounce: float = 0.48
@export var maximum_ball_speed: float = 32.0
@export var pass_min_speed: float = 7.0
@export var pass_max_speed: float = 14.0
@export var pass_assist_degrees: float = 35.0
@export var shot_min_speed: float = 9.0
@export var shot_max_speed: float = 28.0
@export var maximum_shot_lift: float = 6.0
@export var action_cooldown: float = 0.32
@export var tackle_reach: float = 0.95
@export var tackle_cooldown: float = 0.65
@export var keeper_return_delay: float = 0.60
@export var goal_pause_seconds: float = 1.25
@export var restart_pause_seconds: float = 0.65
@export var ai_restart_delay_ticks: int = 24
@export var tackle_contact_window_ticks: int = 12
@export var foul_challenge_window_ticks: int = 18
@export var foul_min_closing_speed: float = 0.8
@export var foul_reckless_closing_speed: float = 9.5
@export var allied_goal_exclusion_depth: float = 3.0
@export var allied_goal_exclusion_half_width: float = 1.7
@export var dribble_cooldown: float = 0.70
@export var dribble_duration_ticks: int = 24
@export var dribble_recovery_ticks: int = 10
@export var dribble_cut_speed: float = 4.8
@export var dribble_pace_speed: float = 7.8
@export var keeper_hand_height: float = 1.05
@export var keeper_hand_forward: float = 0.32
@export var keeper_throw_min_speed: float = 6.0
@export var keeper_throw_max_speed: float = 14.0
@export var keeper_throw_lift: float = 2.4
@export var extended_ball_stop_speed: float = 0.18
@export var extended_ball_stop_ticks: int = 18


func validation_error() -> String:
	# Scalar bounds retain float64 precision; a Vector2 would round the inclusive 0.1 minimum.
	var bounds: Dictionary[StringName, Array] = {
		&"training_seconds": [0.1, 600.0],
		&"move_speed": [1.0, 9.0],
		&"sprint_speed": [1.0, 10.0],
		&"close_control_speed": [1.0, 6.0],
		&"keeper_speed": [1.0, 8.0],
		&"acceleration": [5.0, 60.0],
		&"braking": [5.0, 70.0],
		&"turn_speed": [2.0, 25.0],
		&"command_timeout": [0.10, 1.0],
		&"ai_interval": [0.05, 0.20],
		&"control_acceleration": [10.0, 50.0],
		&"receive_acceleration": [45.0, 100.0],
		&"keeper_control_acceleration": [30.0, 90.0],
		&"control_leash": [0.8, 1.2],
		&"receive_radius": [0.45, 0.75],
		&"receive_speed": [3.0, 14.0],
		&"keeper_receive_speed": [8.0, 16.0],
		&"rolling_resistance": [0.0, 2.0],
		&"ball_friction": [0.05, 0.8],
		&"ball_bounce": [0.05, 0.75],
		&"maximum_ball_speed": [16.0, 32.0],
		&"pass_min_speed": [3.0, 12.0],
		&"pass_max_speed": [5.0, 16.0],
		&"pass_assist_degrees": [0.0, 40.0],
		&"shot_min_speed": [5.0, 15.0],
		&"shot_max_speed": [16.0, 30.0],
		&"maximum_shot_lift": [0.0, 8.0],
		&"action_cooldown": [0.15, 1.0],
		&"tackle_reach": [0.6, 1.1],
		&"tackle_cooldown": [0.3, 1.5],
		&"keeper_return_delay": [0.3, 2.0],
		&"goal_pause_seconds": [0.2, 3.0],
		&"restart_pause_seconds": [0.2, 2.0],
		&"ai_restart_delay_ticks": [1.0, 120.0],
		&"tackle_contact_window_ticks": [1.0, 30.0],
		&"foul_challenge_window_ticks": [1.0, 60.0],
		&"foul_min_closing_speed": [0.1, 4.0],
		&"foul_reckless_closing_speed": [2.0, 20.0],
		&"allied_goal_exclusion_depth": [1.5, 6.0],
		&"allied_goal_exclusion_half_width": [1.5, 3.0],
		&"dribble_cooldown": [0.35, 2.0],
		&"dribble_duration_ticks": [12.0, 45.0],
		&"dribble_recovery_ticks": [4.0, 24.0],
		&"dribble_cut_speed": [2.0, 7.0],
		&"dribble_pace_speed": [4.0, 10.0],
		&"keeper_hand_height": [0.7, 1.4],
		&"keeper_hand_forward": [0.2, 0.55],
		&"keeper_throw_min_speed": [3.0, 10.0],
		&"keeper_throw_max_speed": [8.0, 18.0],
		&"keeper_throw_lift": [0.5, 4.0],
		&"extended_ball_stop_speed": [0.05, 0.5],
		&"extended_ball_stop_ticks": [6.0, 60.0],
	}
	for field: StringName in bounds:
		var value: float = get(field)
		if not is_finite(value) or value < bounds[field][0] or value > bounds[field][1]:
			return "%s must be finite and within [%s, %s]" % [
				field, bounds[field][0], bounds[field][1]]
	if close_control_speed > move_speed or move_speed > sprint_speed:
		return "Speeds must satisfy close_control_speed <= move_speed <= sprint_speed"
	if pass_min_speed > pass_max_speed or pass_max_speed > maximum_ball_speed:
		return "Pass speeds exceed their ordered bounds"
	if shot_min_speed > shot_max_speed or shot_max_speed > maximum_ball_speed:
		return "Shot speeds exceed their ordered bounds"
	if maximum_shot_lift > shot_min_speed:
		return "Maximum shot lift cannot exceed the minimum total shot speed"
	if ai_interval >= command_timeout:
		return "AI interval must be shorter than command timeout"
	if foul_min_closing_speed >= foul_reckless_closing_speed:
		return "Ordinary and reckless closing-speed thresholds must be ordered"
	if dribble_recovery_ticks >= dribble_duration_ticks or dribble_duration_ticks > dribble_cooldown * PHYSICS_HZ:
		return "Dribble recovery/duration/cooldown must be ordered"
	if keeper_throw_min_speed > keeper_throw_max_speed or keeper_throw_max_speed > maximum_ball_speed:
		return "Keeper throw speeds must fit the ball speed limit"
	if keeper_throw_lift >= keeper_throw_min_speed:
		return "Keeper throw lift must leave a positive planar release speed"
	return ""
