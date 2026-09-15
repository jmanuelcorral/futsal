class_name MatchSnapshot
extends RefCounted

const Setup = preload("res://match/simulation/match_setup.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")

enum Phase { READY, PLAYING, GOAL_PAUSE, RESTART_PAUSE, PAUSED, FINISHED }
enum Role { FIELD, KEEPER }
enum Team { HOME, AWAY }


class ActorSnapshot extends RefCounted:
	var actor_id: int
	var team_id: int
	var role: Role
	var human_controlled: bool
	var attack_direction: Vector3
	var spawn_position: Vector3
	var position: Vector3
	var velocity: Vector3
	var forward: Vector3
	var facing_yaw: float
	var close_control: bool
	var action_cooldown: float
	var last_command_sequence: int
	var last_command_tick: int
	var ball_contact_reachable: bool = false
	var ball_in_hands: bool = false
	var gesture_kind: Rules.GestureKind = Rules.GestureKind.NONE
	var gesture_started_tick: int = -1
	var gesture_duration_ticks: int = 0
	var gesture_direction: Vector3 = Vector3.ZERO
	var gesture_contact_position: Vector3 = Vector3.ZERO

	func copy() -> ActorSnapshot:
		var result: ActorSnapshot = get_script().new()
		result.actor_id = actor_id
		result.team_id = team_id
		result.role = role
		result.human_controlled = human_controlled
		result.attack_direction = attack_direction
		result.spawn_position = spawn_position
		result.position = position
		result.velocity = velocity
		result.forward = forward
		result.facing_yaw = facing_yaw
		result.close_control = close_control
		result.action_cooldown = action_cooldown
		result.last_command_sequence = last_command_sequence
		result.last_command_tick = last_command_tick
		result.ball_contact_reachable = ball_contact_reachable
		result.ball_in_hands = ball_in_hands
		result.gesture_kind = gesture_kind
		result.gesture_started_tick = gesture_started_tick
		result.gesture_duration_ticks = gesture_duration_ticks
		result.gesture_direction = gesture_direction
		result.gesture_contact_position = gesture_contact_position
		return result


var mode: Setup.Mode = Setup.Mode.MICRO_1V1
var selected_actor_id: int = 0
var ai_intent_actor_ids: Array[int] = []
var ai_actor_ids: Array[int] = []
var tick: int = 0
var phase: Phase = Phase.READY
var resume_phase: Phase = Phase.READY
var score: Vector2i = Vector2i.ZERO
var seconds_remaining: float = 0.0
var phase_seconds_remaining: float = 0.0
var actors: Array[ActorSnapshot] = []
var ball_position: Vector3 = Vector3.ZERO
var ball_velocity: Vector3 = Vector3.ZERO
var ball_rotation: Quaternion = Quaternion.IDENTITY
var ball_angular_velocity: Vector3 = Vector3.ZERO
var ball_owner_id: int = -1
var last_touch_actor_id: int = -1
var restart: Rules.RestartState = Rules.RestartState.new()
var accumulated_fouls: Vector2i = Vector2i.ZERO
var human_control_context: Rules.ControlContext = Rules.ControlContext.DISABLED
var human_allowed_actions: Array[Command.Action] = []
var selected_can_move: bool = false
var last_touch_tick: int = -1
var last_pass_actor_id: int = -1
var last_pass_target_actor_id: int = -1
var last_pass_tick: int = -1
var period_state: Rules.PeriodState = Rules.PeriodState.REGULATION
var extended_restart_id: int = -1
var extended_kick_event_id: int = -1
var training_exercise: Setup.TrainingExercise = Setup.TrainingExercise.FREE_PLAY


func actor(id: int) -> ActorSnapshot:
	for state: ActorSnapshot in actors:
		if state.actor_id == id:
			return state
	return null


func copy() -> MatchSnapshot:
	var result: MatchSnapshot = get_script().new()
	result.mode = mode
	result.selected_actor_id = selected_actor_id
	result.ai_intent_actor_ids = ai_intent_actor_ids.duplicate()
	result.ai_actor_ids = ai_actor_ids.duplicate()
	result.tick = tick
	result.phase = phase
	result.resume_phase = resume_phase
	result.score = score
	result.seconds_remaining = seconds_remaining
	result.phase_seconds_remaining = phase_seconds_remaining
	for item: ActorSnapshot in actors:
		result.actors.append(item.copy())
	result.ball_position = ball_position
	result.ball_velocity = ball_velocity
	result.ball_rotation = ball_rotation
	result.ball_angular_velocity = ball_angular_velocity
	result.ball_owner_id = ball_owner_id
	result.last_touch_actor_id = last_touch_actor_id
	result.restart = restart.copy()
	result.accumulated_fouls = accumulated_fouls
	result.human_control_context = human_control_context
	result.human_allowed_actions = human_allowed_actions.duplicate()
	result.selected_can_move = selected_can_move
	result.last_touch_tick = last_touch_tick
	result.last_pass_actor_id = last_pass_actor_id
	result.last_pass_target_actor_id = last_pass_target_actor_id
	result.last_pass_tick = last_pass_tick
	result.period_state = period_state
	result.extended_restart_id = extended_restart_id
	result.extended_kick_event_id = extended_kick_event_id
	result.training_exercise = training_exercise
	return result
