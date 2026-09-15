class_name MatchSimulation
extends Node3D

const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Actor = preload("res://match/simulation/match_actor.gd")
const Ball = preload("res://match/simulation/match_ball.gd")
const AI = preload("res://match/simulation/match_ai.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Rules = preload("res://match/simulation/match_rules.gd")
const Launch = preload("res://match/simulation/match_launch.gd")

const HUMAN_ID: int = 0
const RIVAL_ID: int = 1
const HOME_KEEPER_ID: int = 2
const AWAY_KEEPER_ID: int = 3
const ACTOR_IDS: Array[int] = [HUMAN_ID, RIVAL_ID, HOME_KEEPER_ID, AWAY_KEEPER_ID]
const PREVIEW_ACTOR_IDS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

signal event_raised(event: Event)
signal goal_scored(event: Event)
signal pass_made(event: Event)
signal shot_taken(event: Event)
signal save_made(event: Event)
signal restarted(event: Event)
signal match_ended(event: Event)
signal ball_contact(event: Event)
signal command_rejected(actor_id: int, code: Error, message: String)

@export var tuning: Tuning = Tuning.new()

var last_error: String = ""

var _config: Tuning
var _setup: Setup
var _actor_ids: Array[int] = ACTOR_IDS.duplicate()
var _actors: Array[Actor] = []
var _ball: Ball
var _world: World3D
var _frame_boxes: Array[AABB] = []
var _phase: Snapshot.Phase = Snapshot.Phase.READY
var _resume_phase: Snapshot.Phase = Snapshot.Phase.READY
var _tick: int = 0
var _score: Vector2i = Vector2i.ZERO
var _seconds_remaining: float = 0.0
var _phase_seconds: float = 0.0
var _kickoff_team: int = 0
var _selected_actor_id: int = HUMAN_ID
var _owner_id: int = -1
var _last_touch_id: int = -1
var _previous_ball_position: Vector3 = Vector3.ZERO
var _receive_lock: float = 0.0
var _shot_id: int = -1
var _shot_team: int = -1
var _shot_age: float = 0.0
var _saved_shot_id: int = -1
var _event_sequence: int = 0
var _events: Array[Event] = []
var _collision_exceptions: Array[int] = []
var _collision_release_ticks: Dictionary[int, int] = {}
var _in_step: bool = false
var _notifying_refusal: bool = false
var _restart: Types.RestartState = Types.RestartState.new()
var _restart_sequence: int = 0
var _accumulated_fouls: Vector2i = Vector2i.ZERO
var _last_touch_tick: int = -1
var _last_pass_actor_id: int = -1
var _last_pass_target_actor_id: int = -1
var _last_pass_tick: int = -1
var _period_state: Types.PeriodState = Types.PeriodState.REGULATION
var _extended_restart_id: int = -1
var _extended_kick_event_id: int = -1
var _restart_kick_event_id: int = -1
var _restricted_kick_live: bool = false
var _extended_stop_ticks: int = 0
var _extended_keeper_collected: bool = false
var _contact_sequence: int = 0
var _contact_keys: Dictionary[String, int] = {}
var _adjudicated_contacts: Dictionary[int, bool] = {}
var _registered_touches: Dictionary[int, bool] = {}
var _actor_contact_episodes: Dictionary[String, int] = {}
var _ball_touch_ticks: Dictionary[int, int] = {}
var _tackle_started_ticks: Dictionary[int, int] = {}


func _ready() -> void:
	_create_world()
	reset()


func reset(setup: Setup = null) -> Error:
	if _in_step or _notifying_refusal:
		return _refuse(ERR_BUSY, "Defer reset/start/pause until after simulation event delivery")
	if not is_inside_tree() or _ball == null:
		return _refuse(ERR_UNCONFIGURED, "Add MatchSimulation to a SceneTree before reset/start")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY):
		return _refuse(ERR_INVALID_PARAMETER, "The authority requires an identity world transform")
	if Engine.physics_ticks_per_second != Tuning.PHYSICS_HZ:
		return _refuse(ERR_UNCONFIGURED, "MatchSimulation requires 60 physics ticks per second")
	if String(ProjectSettings.get_setting("physics/3d/physics_engine")) != "Jolt Physics":
		return _refuse(ERR_UNCONFIGURED, "MatchSimulation requires Jolt Physics")
	if tuning == null:
		return _refuse(ERR_INVALID_PARAMETER, "Tuning cannot be null")
	var tuning_error: String = tuning.validation_error()
	if not tuning_error.is_empty():
		return _refuse(ERR_INVALID_PARAMETER, tuning_error)
	var candidate: Setup = Setup.new() if setup == null else setup.copy()
	var setup_error: String = _validate_setup(candidate)
	if not setup_error.is_empty():
		return _refuse(ERR_INVALID_PARAMETER, setup_error)
	_config = tuning.duplicate(true) as Tuning
	_setup = candidate
	_setup.ai_actor_ids.sort()
	_ball.configure(_config)
	_score = Vector2i.ZERO
	_tick = 0
	_event_sequence = 0
	_seconds_remaining = _config.training_seconds
	_phase_seconds = 0.0
	_kickoff_team = 0
	_restart = Types.RestartState.new()
	_restart_sequence = 0
	_accumulated_fouls = Vector2i(0, 6) if _setup.training_exercise == Setup.TrainingExercise.ACCUMULATED_FREE_KICK else Vector2i.ZERO
	_period_state = Types.PeriodState.REGULATION
	_extended_restart_id = -1
	_extended_kick_event_id = -1
	_restart_kick_event_id = -1
	_restricted_kick_live = false
	_extended_stop_ticks = 0
	_extended_keeper_collected = false
	_contact_sequence = 0
	_contact_keys.clear()
	_adjudicated_contacts.clear()
	_registered_touches.clear()
	_phase = Snapshot.Phase.READY
	_resume_phase = Snapshot.Phase.READY
	_reset_motion(_setup)
	last_error = ""
	return OK


func start(setup: Setup = null) -> Error:
	var result: Error = reset(setup)
	if result != OK:
		return result
	_in_step = true
	_phase = Snapshot.Phase.PLAYING
	_record(Event.Kind.RESTART, -1, &"training_start")
	var exercise_restart: Types.RestartState = _exercise_restart()
	if exercise_restart.kind == Types.RestartKind.NONE:
		_ball.resume()
	else:
		_begin_restart(exercise_restart)
	_deliver_events()
	_in_step = false
	return OK


func set_paused(paused: bool) -> Error:
	if _in_step or _notifying_refusal:
		return _refuse(ERR_BUSY, "Defer reset/start/pause until after simulation event delivery")
	if paused == (_phase == Snapshot.Phase.PAUSED):
		last_error = ""
		return OK
	if paused:
		if _phase not in [Snapshot.Phase.PLAYING, Snapshot.Phase.GOAL_PAUSE, Snapshot.Phase.RESTART_PAUSE]:
			return _refuse(ERR_UNAVAILABLE, "Only an active training match can be paused")
		_resume_phase = _phase
		_phase = Snapshot.Phase.PAUSED
		_ball.suspend()
	else:
		_phase = _resume_phase
		if _phase in [Snapshot.Phase.PLAYING, Snapshot.Phase.GOAL_PAUSE]:
			_ball.resume()
	last_error = ""
	return OK


func set_ai_actor_ids(ids: Array[int]) -> Error:
	if _in_step or _notifying_refusal:
		return _refuse(ERR_BUSY, "Defer AI changes until after the simulation tick/event delivery")
	if not is_inside_tree() or _setup == null or _ball == null:
		return _refuse(ERR_UNCONFIGURED, "Initialize MatchSimulation before changing AI")
	var validation_error: String = _validate_ai_ids(ids, _actor_ids)
	if not validation_error.is_empty():
		return _refuse(ERR_INVALID_PARAMETER, validation_error)
	var accepted: Array[int] = ids.duplicate()
	accepted.sort()
	if accepted != _setup.ai_actor_ids:
		for actor: Actor in _actors:
			if actor.actor_id != _selected_actor_id and (actor.actor_id in accepted) != (actor.actor_id in _setup.ai_actor_ids):
				_clear_actor_intent(actor)
		_setup.ai_actor_ids = accepted
	last_error = ""
	return OK


func submit_human_command(command: Command) -> Error:
	if _in_step or _notifying_refusal:
		return _refuse(ERR_BUSY, "Submit human commands between simulation ticks/events", command.actor_id if command != null else -1)
	if command != null and command.actor_id != _selected_actor_id:
		return _refuse(ERR_UNAUTHORIZED, "Human input controls only the currently selected actor", command.actor_id)
	return _accept_command(command)


func submit_command(command: Command) -> Error:
	if _in_step or _notifying_refusal:
		return _refuse(ERR_BUSY, "Submit commands between simulation ticks/events", command.actor_id if command != null else -1)
	return _accept_command(command)


func query_human_launch(request: Command) -> Launch.Solution:
	if _setup == null or _config == null or _ball == null:
		var unconfigured: Launch.Solution = Launch.Solution.new()
		unconfigured.error = ERR_UNCONFIGURED
		unconfigured.reason = &"unconfigured"
		return unconfigured
	if request != null and request.actor_id != _selected_actor_id:
		var unauthorized: Launch.Solution = Launch.Solution.new()
		unauthorized.error = ERR_UNAUTHORIZED
		unauthorized.reason = &"not_selected"
		unauthorized.actor_id = request.actor_id
		unauthorized.tick = _tick
		return unauthorized
	return Launch.resolve(get_snapshot(), request, _config)


func _accept_command(command: Command) -> Error:
	if command == null:
		return _refuse(ERR_INVALID_PARAMETER, "Command cannot be null")
	if command.actor_id not in _actor_ids:
		return _refuse(ERR_DOES_NOT_EXIST, "Unknown actor ID", command.actor_id)
	if _phase != Snapshot.Phase.PLAYING and not (_phase == Snapshot.Phase.RESTART_PAUSE and _restart.stage == Types.RestartStage.READY):
		return _refuse(ERR_UNAVAILABLE, "Commands require live play or a ready restart", command.actor_id)
	var actor: Actor = _actors[command.actor_id]
	if command.sequence < 0 or command.sequence > Command.MAX_SEQUENCE or command.sequence <= actor.last_sequence:
		return _refuse(ERR_INVALID_PARAMETER, "Sequence must increase per actor within [0, 2147483647]", actor.actor_id)
	if not command.move.is_finite() or command.move.length_squared() > 1.00001:
		return _refuse(ERR_INVALID_PARAMETER, "Move must be a finite vector of length <= 1", actor.actor_id)
	if not command.aim.is_finite() or command.aim.length_squared() > 1.00001:
		return _refuse(ERR_INVALID_PARAMETER, "Aim must be a finite vector of length <= 1", actor.actor_id)
	if command.action < Command.Action.NONE or command.action > Command.Action.CHOOSE_RESTART_SPOT:
		return _refuse(ERR_INVALID_PARAMETER, "Unknown action", actor.actor_id)
	if not is_finite(command.shot_charge) or command.shot_charge < 0.0 or command.shot_charge > 1.0:
		return _refuse(ERR_INVALID_PARAMETER, "Shot charge must be finite and within [0, 1]", actor.actor_id)
	if not is_finite(command.shot_lift) or command.shot_lift < 0.0 or command.shot_lift > 1.0:
		return _refuse(ERR_INVALID_PARAMETER, "Shot lift must be finite and within [0, 1]", actor.actor_id)
	if command.target_actor_id != -1:
		if command.action not in [Command.Action.PASS, Command.Action.KEEPER_THROW] or command.target_actor_id not in _actor_ids:
			return _refuse(ERR_INVALID_PARAMETER, "A target is valid only for a pass/throw to a known teammate", actor.actor_id)
		if command.target_actor_id == actor.actor_id or _actors[command.target_actor_id].team_id != actor.team_id:
			return _refuse(ERR_INVALID_PARAMETER, "Pass target must be a different actor on the same team", actor.actor_id)
	if command.restart_spot_choice < Types.SpotChoice.DEFAULT or command.restart_spot_choice > Types.SpotChoice.OFFENCE_SPOT:
		return _refuse(ERR_INVALID_PARAMETER, "Unknown restart spot choice", actor.actor_id)
	if command.action != Command.Action.CHOOSE_RESTART_SPOT and command.restart_spot_choice != Types.SpotChoice.DEFAULT:
		return _refuse(ERR_INVALID_PARAMETER, "Spot choice requires CHOOSE_RESTART_SPOT", actor.actor_id)
	if command.action not in [Command.Action.NONE, Command.Action.SWITCH_TEAMMATE, Command.Action.CHOOSE_RESTART_SPOT] and actor.action_cooldown > 0.0:
		return _refuse(ERR_BUSY, "Action is cooling down", actor.actor_id)
	if command.action != Command.Action.NONE and actor.pending_action != null:
		return _refuse(ERR_BUSY, "An action is already queued for the next physics tick", actor.actor_id)
	if command.action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		var solution: Launch.Solution = Launch.resolve(get_snapshot(), command, _config)
		if solution.error != OK or not solution.executable:
			return _refuse(solution.error if solution.error != OK else ERR_UNAVAILABLE, "Launch refused: " + String(solution.reason), actor.actor_id)
	if command.action == Command.Action.TACKLE and _owner_id == actor.actor_id:
		return _refuse(ERR_UNAVAILABLE, "Cannot tackle your own possession", actor.actor_id)
	if command.action == Command.Action.SWITCH_TEAMMATE:
		if actor.actor_id != _selected_actor_id:
			return _refuse(ERR_UNAUTHORIZED, "Only the selected actor can switch control", actor.actor_id)
		if _owner_id == actor.actor_id:
			return _refuse(ERR_UNAVAILABLE, "Switching requires the selected actor to be off the ball", actor.actor_id)
		if _teammate_recipient(actor, actor.global_position, _command_direction(command.aim)) == -1:
			return _refuse(ERR_UNAVAILABLE, "No teammate lies in the requested switch direction", actor.actor_id)
	if command.action == Command.Action.DRIBBLE:
		if not _can_kick(actor) or _ball_in_hands(actor):
			return _refuse(ERR_UNAVAILABLE, "Dribbling requires reachable foot contact", actor.actor_id)
		if actor.dribble_cooldown > 0.0:
			return _refuse(ERR_BUSY, "Dribble recovery is cooling down", actor.actor_id)
		var direction: Vector3 = _dribble_direction(actor, command.aim)
		if direction.is_zero_approx():
			return _refuse(ERR_UNAVAILABLE, "Backward input does not define a third dribble", actor.actor_id)
		if _allied_dribble_finishes(actor, _dribble_velocity(actor, direction)):
			return _refuse(ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish", actor.actor_id)
	if command.action == Command.Action.CHOOSE_RESTART_SPOT and not _can_choose_spot(actor, command.restart_spot_choice):
		return _refuse(ERR_UNAVAILABLE, "Only the ready awarded taker can choose a legal sixth-foul spot", actor.actor_id)
	var state: Snapshot = get_snapshot()
	if command.action not in Rules.allowed_actions(actor.actor_id, state):
		return _refuse(ERR_UNAVAILABLE, "Action unavailable in the current rule context", actor.actor_id)
	if _allied_goalward_intent(actor, command.move):
		return _refuse(ERR_UNAUTHORIZED, "Unselected HOME cannot deliberately carry into the goal mouth", actor.actor_id)
	actor.command = command.copy()
	actor.command.action = Command.Action.NONE
	actor.command.target_actor_id = -1
	actor.command.shot_charge = 0.0
	actor.command.shot_lift = 0.0
	actor.command.restart_spot_choice = Types.SpotChoice.DEFAULT
	if command.action != Command.Action.NONE:
		actor.pending_action = command.copy()
	actor.last_sequence = command.sequence
	actor.last_command_tick = _tick
	actor.command_age = 0.0
	last_error = ""
	return OK


func get_snapshot() -> Snapshot:
	var state: Snapshot = Snapshot.new()
	state.selected_actor_id = _selected_actor_id
	if _setup != null:
		state.mode = _setup.mode
		state.training_exercise = _setup.training_exercise
		state.ai_intent_actor_ids = _setup.ai_actor_ids.duplicate()
		state.ai_actor_ids = _effective_ai_ids()
	state.tick = _tick
	state.phase = _phase
	state.resume_phase = _resume_phase
	state.score = _score
	state.seconds_remaining = _seconds_remaining
	state.phase_seconds_remaining = _phase_seconds
	state.ball_owner_id = _owner_id
	state.last_touch_actor_id = _last_touch_id
	state.last_touch_tick = _last_touch_tick
	state.last_pass_actor_id = _last_pass_actor_id
	state.last_pass_target_actor_id = _last_pass_target_actor_id
	state.last_pass_tick = _last_pass_tick
	state.restart = _restart.copy()
	state.accumulated_fouls = _accumulated_fouls
	state.period_state = _period_state
	state.extended_restart_id = _extended_restart_id
	state.extended_kick_event_id = _extended_kick_event_id
	if _ball != null:
		var ball_transform: Transform3D = _ball.snapshot_transform()
		state.ball_position = ball_transform.origin
		state.ball_velocity = _ball.linear_velocity
		state.ball_rotation = ball_transform.basis.get_rotation_quaternion()
		state.ball_angular_velocity = _ball.angular_velocity
	for actor: Actor in _actors:
		var item: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		item.actor_id = actor.actor_id
		item.team_id = actor.team_id
		item.role = actor.role
		item.human_controlled = actor.actor_id == _selected_actor_id
		item.attack_direction = _setup.attack_direction(actor.team_id) if _setup != null else (Vector3.RIGHT if actor.team_id == 0 else Vector3.LEFT)
		item.spawn_position = actor.spawn_position
		item.position = actor.global_position
		item.velocity = actor.velocity
		item.forward = actor.forward
		item.facing_yaw = actor.rotation.y
		item.close_control = actor.command.close_control
		item.action_cooldown = actor.action_cooldown
		item.last_command_sequence = actor.last_sequence
		item.last_command_tick = actor.last_command_tick
		item.ball_contact_reachable = _can_kick(actor) if _config != null else false
		item.ball_in_hands = _ball_in_hands(actor)
		item.gesture_kind = actor.gesture_kind if _tick < actor.gesture_started_tick + actor.gesture_duration_ticks else Types.GestureKind.NONE
		item.gesture_started_tick = actor.gesture_started_tick
		item.gesture_duration_ticks = actor.gesture_duration_ticks
		item.gesture_direction = actor.gesture_direction
		item.gesture_contact_position = actor.gesture_contact_position
		state.actors.append(item)
	if _config != null and state.actor(_selected_actor_id) != null:
		state.human_allowed_actions = Rules.allowed_actions(_selected_actor_id, state).duplicate()
		state.selected_can_move = Rules.can_move(_selected_actor_id, state) and not _extension_keeper_held(_selected_actor_id)
		if _phase == Snapshot.Phase.PLAYING and (state.selected_can_move or _period_state == Types.PeriodState.REGULATION):
			state.human_control_context = Types.ControlContext.LIVE
		elif _phase == Snapshot.Phase.RESTART_PAUSE and _restart.stage == Types.RestartStage.READY:
			state.human_control_context = Types.ControlContext.RESTART_AIM if _restart.awarded_team_id == 0 else Types.ControlContext.RESTART_DEFEND
	return state


func _physics_process(delta: float) -> void:
	if _phase in [Snapshot.Phase.READY, Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED]:
		return
	_in_step = true
	_tick += 1
	if _phase == Snapshot.Phase.GOAL_PAUSE:
		_consume_ball_contacts(_ball._take_contact_samples(), null, false)
		_phase_seconds = maxf(0.0, _phase_seconds - delta)
		if _phase_seconds <= 0.0:
			_restart_play()
		_end_step()
		return
	if _phase == Snapshot.Phase.RESTART_PAUSE:
		_step_restart(delta)
		_check_period()
		_end_step()
		return
	_seconds_remaining = maxf(0.0, _seconds_remaining - delta)
	_ball.control_acceleration = 0.0
	_ball.control_actor_id = -1
	_receive_lock = maxf(0.0, _receive_lock - delta)
	_shot_age += delta
	if _shot_age > 4.0:
		_shot_id = -1
	var crossing: Types.BoundaryCrossing = Rules.first_crossing(_previous_ball_position, _ball.global_position, _config)
	_consume_ball_contacts(_ball._take_contact_samples(), crossing, true)
	if _phase == Snapshot.Phase.PLAYING:
		_check_boundaries(crossing)
	if _phase != Snapshot.Phase.PLAYING:
		_check_period()
		_end_step()
		return
	_refresh_possession()
	_drive_ai(delta)
	var touches_before_motion: Dictionary[int, int] = _ball_touch_ticks.duplicate()
	_step_actors(delta)
	_refresh_possession()
	_resolve_pending_actions()
	_consume_actor_contacts(touches_before_motion)
	if _phase == Snapshot.Phase.PLAYING:
		_control_ball()
		_clean_collision_exceptions()
		_previous_ball_position = _ball.global_position
		_check_extended_outcome()
	_check_period()
	_end_step()


func _resolve_pending_actions() -> void:
	var selected_at_resolution: int = _selected_actor_id
	_resolve_action(_actors[selected_at_resolution])
	for actor: Actor in _actors:
		if _phase not in [Snapshot.Phase.PLAYING, Snapshot.Phase.RESTART_PAUSE]:
			break
		if actor.actor_id != selected_at_resolution:
			_resolve_action(actor)


func _step_actors(delta: float) -> void:
	var observation: Snapshot = get_snapshot()
	var displacements: Dictionary[int, Vector3] = {}
	var pre_contact_velocities: Dictionary[int, Vector3] = {}
	for actor: Actor in _actors:
		if Rules.can_move(actor.actor_id, observation) and not _extension_keeper_held(actor.actor_id):
			var movement: Vector3 = actor._prepare_step(delta, _config)
			movement = _guard_allied_displacement(actor, movement)
			var constrained: Vector3 = Rules.constrain_displacement(actor.actor_id, movement, observation, _config)
			if constrained != movement:
				# Do not spend the rule's tolerance on movement: native float32 integration can cross that boundary.
				constrained = constrained.move_toward(Vector3.ZERO,
					Tuning.NATIVE_JOLT_PROFILE[&"physics/jolt_physics_3d/simulation/penetration_slop"])
			movement = constrained
			displacements[actor.actor_id] = movement
			pre_contact_velocities[actor.actor_id] = Vector3(movement.x / delta, actor.velocity.y, movement.z / delta)
		else:
			actor._aim_only(delta, _config)
			pre_contact_velocities[actor.actor_id] = Vector3.ZERO
	# Moving a lower ID may zero its slide velocity before the other athlete reports the same impact.
	for actor: Actor in _actors:
		if actor.actor_id in displacements:
			actor._move_prepared(displacements[actor.actor_id], delta, pre_contact_velocities)
		actor.possession_seconds = actor.possession_seconds + delta if _owner_id == actor.actor_id else 0.0


func _end_step() -> void:
	_deliver_events()
	_in_step = false


func _drive_ai(delta: float) -> void:
	var state: Snapshot = get_snapshot()
	var preview_field_decision: bool = false
	for id: int in state.ai_actor_ids:
		_actors[id].ai_timer -= delta
		if _setup.mode == Setup.Mode.PREVIEW_5V5 and _actors[id].role == Snapshot.Role.FIELD and _actors[id].ai_timer <= 0.0:
			preview_field_decision = true
	for id: int in state.ai_actor_ids:
		var actor: Actor = _actors[id]
		var preview_field: bool = _setup.mode == Setup.Mode.PREVIEW_5V5 and actor.role == Snapshot.Role.FIELD
		var decide_now: bool = preview_field_decision if preview_field else actor.ai_timer <= 0.0
		# All preview field decisions share one observation, including chaser handoffs.
		if decide_now:
			actor.ai_timer = _config.ai_interval
			var command: Command = AI.decide(state.actor(id), state, _config, actor.possession_seconds)
			# Contact can be lost during a decision interval; use the same refusal path as human input.
			if actor.pending_action != null or (command.action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW] and not _can_kick(actor)):
				command.action = Command.Action.NONE
				command.target_actor_id = -1
				command.shot_charge = 0.0
				command.shot_lift = 0.0
				command.restart_spot_choice = Types.SpotChoice.DEFAULT
			_accept_command(command)


func _effective_ai_ids() -> Array[int]:
	var effective: Array[int] = _setup.ai_actor_ids.duplicate()
	effective.erase(_selected_actor_id)
	return effective


func _clear_actor_intent(actor: Actor) -> void:
	actor.command = Command.new(actor.actor_id, actor.last_sequence)
	actor.pending_action = null
	actor.command_age = 0.0
	actor.ai_timer = 0.0


func _resolve_action(actor: Actor) -> void:
	if actor.pending_action == null:
		return
	var action: Command = actor.pending_action
	actor.pending_action = null
	_execute_action(actor, action)


func _change_focus(target_id: int, reason: StringName) -> void:
	if target_id == _selected_actor_id:
		return
	var previous_id: int = _selected_actor_id
	_clear_actor_intent(_actors[previous_id])
	_clear_actor_intent(_actors[target_id])
	_selected_actor_id = target_id
	var event: Event = _record(Event.Kind.FOCUS_CHANGED, previous_id, reason)
	event.target_actor_id = target_id


func _refresh_possession() -> void:
	if _owner_id >= 0:
		var owner: Actor = _actors[_owner_id]
		var height_limit: float = 1.15 if owner.role == Snapshot.Role.KEEPER else 0.5
		if _flat_distance(owner.global_position, _ball.global_position) > _config.control_leash or _ball.position.y > height_limit or not _clear_contact(owner):
			_owner_id = -1
			owner.possession_seconds = 0.0
		else:
			return
	if _receive_lock > 0.0:
		return
	var nearest_id: int = -1
	var nearest_distance: float = INF
	for actor: Actor in _actors:
		if actor.receive_cooldown > 0.0:
			continue
		var distance: float = _flat_distance(actor.global_position, _ball.global_position)
		if distance > _config.receive_radius or distance >= nearest_distance:
			continue
		var keeper: bool = actor.role == Snapshot.Role.KEEPER
		if _ball.position.y > (1.1 if keeper else 0.4):
			continue
		var relative_speed: float = (_ball.linear_velocity - Vector3(actor.velocity.x, 0.0, actor.velocity.z)).length()
		if relative_speed > (_config.keeper_receive_speed if keeper else _config.receive_speed):
			continue
		var toward_ball: Vector3 = _flat_direction(actor.global_position, _ball.global_position)
		if not keeper and actor.forward.dot(toward_ball) < -0.3:
			continue
		if not _clear_contact(actor):
			continue
		nearest_id = actor.actor_id
		nearest_distance = distance
	if nearest_id >= 0:
		_owner_id = nearest_id
		var actor: Actor = _actors[nearest_id]
		actor.possession_seconds = 0.0
		_ignore_actor_collision(nearest_id)
		_record(Event.Kind.POSSESSION, nearest_id, &"received")


func _control_ball() -> void:
	if _owner_id < 0:
		return
	var actor: Actor = _actors[_owner_id]
	var offset: float = 0.48 if actor.command.close_control else 0.57
	var acceleration: float = _config.control_acceleration
	if actor.possession_seconds < 0.18:
		acceleration = _config.receive_acceleration
	if actor.command.sprint and not actor.command.close_control:
		offset = 0.74
		acceleration *= 0.65
	if actor.role == Snapshot.Role.KEEPER:
		acceleration = _config.keeper_control_acceleration
	var target: Vector3 = actor.global_position + actor.forward * offset
	if _unselected_home_carrier(actor) and _inside_allied_goal_exclusion(actor.global_position):
		var attack: Vector3 = _setup.attack_direction(actor.team_id)
		if (target - actor.global_position).dot(attack) > 0.0:
			target.x = actor.global_position.x
	var correction: Vector3 = Vector3(target.x - _ball.position.x, 0.0, target.z - _ball.position.z) * 9.0
	correction = correction.limit_length(4.0)
	_ball.control_velocity = Vector3(actor.velocity.x, 0.0, actor.velocity.z) + correction
	if _unselected_home_carrier(actor) and _inside_allied_goal_exclusion(actor.global_position) and _ball.control_velocity.dot(_setup.attack_direction(actor.team_id)) > 0.0:
		_ball.control_velocity.x = 0.0
	_ball.control_acceleration = acceleration
	_ball.control_actor_id = actor.actor_id if _flat_distance(actor.position, _ball.position) <= _config.receive_radius and _ball.position.y <= (1.1 if actor.role == Snapshot.Role.KEEPER else 0.4) else -1


func _execute_action(actor: Actor, command: Command) -> void:
	var action: Command.Action = command.action
	if action == Command.Action.SWITCH_TEAMMATE:
		if actor.actor_id != _selected_actor_id:
			_refuse(ERR_UNAUTHORIZED, "Only the selected actor can switch control", actor.actor_id)
			return
		if _owner_id == actor.actor_id:
			_refuse(ERR_UNAVAILABLE, "Possession was acquired before the switch tick", actor.actor_id)
			return
		var recipient: int = _teammate_recipient(actor, actor.global_position, _command_direction(command.aim))
		if recipient == -1:
			_refuse(ERR_UNAVAILABLE, "No teammate lies in the requested switch direction", actor.actor_id)
			return
		if action not in Rules.allowed_actions(actor.actor_id, get_snapshot()):
			_refuse(ERR_UNAVAILABLE, "Action context changed before its resolution tick", actor.actor_id)
			return
		_change_focus(recipient, &"off_ball_switch")
		return
	if action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		_execute_launch(actor, command)
		return
	if action not in Rules.allowed_actions(actor.actor_id, get_snapshot()):
		_refuse(ERR_UNAVAILABLE, "Action context changed before its resolution tick", actor.actor_id)
		return
	if action == Command.Action.CHOOSE_RESTART_SPOT:
		_choose_restart_spot(actor, command.restart_spot_choice)
		return
	if action == Command.Action.TACKLE:
		_tackle(actor)
		return
	if action == Command.Action.DRIBBLE:
		_dribble(actor, command)
		return


func _execute_launch(actor: Actor, command: Command) -> void:
	if not _can_kick(actor):
		_refuse(ERR_UNAVAILABLE, "Possession/contact was lost before the kick tick", actor.actor_id)
		return
	var solution: Launch.Solution = Launch.resolve(get_snapshot(), command, _config)
	if solution.error != OK or not solution.executable:
		_refuse(solution.error if solution.error != OK else ERR_UNAVAILABLE, "Launch changed before contact: " + String(solution.reason), actor.actor_id)
		return
	var taking: bool = _phase == Snapshot.Phase.RESTART_PAUSE
	if not taking:
		_restricted_kick_live = false
	if taking:
		_ball.resume()
		_restart.stage = Types.RestartStage.IN_PLAY
		_restart.stage_started_tick = _tick
		_phase = Snapshot.Phase.PLAYING
		_phase_seconds = 0.0
	_owner_id = -1
	_receive_lock = 0.10
	actor.receive_cooldown = 0.40
	actor.possession_seconds = 0.0
	actor.action_cooldown = _config.action_cooldown
	_ignore_actor_collision(actor.actor_id)
	_collision_release_ticks[actor.actor_id] = _tick + 1
	_ball.kick(solution.velocity)
	var touch: int = _contact_number()
	if taking:
		_restart.launch_contact_id = touch
	_accepted_touch(actor, solution.origin, touch)
	var throwing: bool = command.action == Command.Action.KEEPER_THROW
	var passing: bool = command.action in [Command.Action.PASS, Command.Action.KEEPER_THROW]
	var gesture: Types.GestureKind = Types.GestureKind.KEEPER_THROW if throwing else Types.GestureKind.FOOT_KICK
	_set_gesture(actor, gesture, solution.direction, solution.origin, 18 if throwing else 12)
	var event: Event = _record(Event.Kind.PASS if passing else Event.Kind.SHOT, actor.actor_id, &"throw" if throwing else &"kick")
	event.target_actor_id = solution.effective_target_actor_id
	event.shot_charge = command.shot_charge if not passing else 0.0
	event.launch_kind = solution.launch_kind
	event.gesture_kind = gesture
	event.contact_id = touch
	event.contact_point = solution.origin
	_shot_id = event.event_id if not passing else -1
	_shot_team = actor.team_id
	_shot_age = 0.0
	_saved_shot_id = -1
	if passing:
		_last_pass_actor_id = actor.actor_id
		_last_pass_target_actor_id = solution.effective_target_actor_id
		_last_pass_tick = _tick
	if taking:
		_restart_kick_event_id = event.event_id
		_restricted_kick_live = _restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
		_extended_stop_ticks = 0
		_extended_keeper_collected = false
		if _period_state == Types.PeriodState.EXTENDED_KICK:
			_extended_kick_event_id = event.event_id
	if passing and actor.actor_id == _selected_actor_id and solution.effective_target_actor_id >= 0:
		_change_focus(solution.effective_target_actor_id, &"pass")
	if taking:
		_record_restart_changed(&"taken")
	_previous_ball_position = solution.origin


func _dribble_direction(actor: Actor, aim: Vector2) -> Vector3:
	var forward: Vector3 = Vector3(actor.forward.x, 0.0, actor.forward.z).normalized()
	if aim.is_zero_approx():
		return forward
	var direction: Vector3 = _command_direction(aim)
	var lateral: float = forward.x * direction.z - forward.z * direction.x
	var ahead: float = forward.dot(direction)
	if ahead < -0.5 and absf(lateral) < 0.7:
		return Vector3.ZERO
	if absf(lateral) > absf(ahead):
		return (forward * 0.3 + Vector3(-forward.z, 0.0, forward.x) * signf(lateral)).normalized()
	return forward


func _dribble_velocity(actor: Actor, direction: Vector3) -> Vector3:
	var cut: bool = direction.dot(actor.forward) < 0.8
	var motion: Vector3 = direction * (_config.dribble_cut_speed if cut else _config.dribble_pace_speed)
	if cut:
		motion += Vector3(actor.velocity.x, 0.0, actor.velocity.z) * 0.25
	return motion


func _allied_dribble_finishes(actor: Actor, motion: Vector3) -> bool:
	# A released ball can score from outside the carrier exclusion. Apply the launch
	# mouth geometry to its actual impulse (including cut inertia), not the action label.
	return _unselected_home_carrier(actor) and Launch._toward_goal_mouth(
		_ball.global_position, motion, _setup.attack_direction(actor.team_id))


func _dribble(actor: Actor, command: Command) -> void:
	var direction: Vector3 = _dribble_direction(actor, command.aim)
	if not _can_kick(actor) or _ball_in_hands(actor) or direction.is_zero_approx():
		_refuse(ERR_UNAVAILABLE, "Dribble contact or direction is unavailable", actor.actor_id)
		return
	if actor.dribble_cooldown > 0.0:
		_refuse(ERR_BUSY, "Dribble is still recovering", actor.actor_id)
		return
	var motion: Vector3 = _dribble_velocity(actor, direction)
	if _allied_dribble_finishes(actor, motion):
		_refuse(ERR_UNAUTHORIZED, "Allied dribble cannot intentionally finish", actor.actor_id)
		return
	var cut: bool = direction.dot(actor.forward) < 0.8
	var at: Vector3 = _ball.global_position
	_owner_id = -1
	_receive_lock = 0.0
	actor.receive_cooldown = float(_config.dribble_recovery_ticks) / Tuning.PHYSICS_HZ
	actor.action_cooldown = actor.receive_cooldown
	actor.dribble_cooldown = _config.dribble_cooldown
	actor.possession_seconds = 0.0
	_ignore_actor_collision(actor.actor_id)
	_collision_release_ticks[actor.actor_id] = _tick + 1
	_ball.kick(motion)
	var touch: int = _accepted_touch(actor, at)
	var kind: Types.GestureKind = Types.GestureKind.CUT if cut else Types.GestureKind.PACE_CHANGE
	_set_gesture(actor, kind, direction, at, _config.dribble_duration_ticks)
	var event: Event = _record(Event.Kind.DRIBBLE, actor.actor_id, &"cut" if cut else &"pace_change")
	event.gesture_kind = kind
	event.contact_id = touch
	event.contact_point = at
	_shot_id = -1


func _set_gesture(actor: Actor, kind: Types.GestureKind, direction: Vector3, at: Vector3, ticks: int) -> void:
	actor.gesture_kind = kind
	actor.gesture_started_tick = _tick
	actor.gesture_duration_ticks = ticks
	actor.gesture_direction = direction
	actor.gesture_contact_position = at


func _command_direction(aim: Vector2) -> Vector3:
	return Vector3.ZERO if aim.is_zero_approx() else Vector3(aim.x, 0.0, aim.y).normalized()


func _teammate_recipient(actor: Actor, origin: Vector3, direction: Vector3) -> int:
	var best_id: int = -1
	var best_alignment: float = -INF
	var best_distance: float = INF
	var minimum_alignment: float = cos(deg_to_rad(_config.pass_assist_degrees))
	for candidate: Actor in _actors:
		if candidate.actor_id == actor.actor_id or candidate.team_id != actor.team_id:
			continue
		var alignment: float = 1.0 if direction.is_zero_approx() else direction.dot(_flat_direction(origin, candidate.global_position))
		if not direction.is_zero_approx() and alignment < minimum_alignment:
			continue
		var distance: float = _flat_distance(origin, candidate.global_position)
		var same_angle: bool = is_equal_approx(alignment, best_alignment)
		var same_distance: bool = is_equal_approx(distance, best_distance)
		if best_id == -1 or (alignment > best_alignment and not same_angle) or (same_angle and (
			(distance < best_distance and not same_distance) or (same_distance and candidate.actor_id < best_id))):
			best_id = candidate.actor_id
			best_alignment = alignment
			best_distance = distance
	return best_id


func _tackle(actor: Actor) -> void:
	actor.action_cooldown = _config.tackle_cooldown
	_tackle_started_ticks[actor.actor_id] = _tick
	var direction: Vector3 = _flat_direction(actor.global_position, _ball.global_position)
	var distance: float = _flat_distance(actor.global_position, _ball.global_position)
	var reach: float = _config.tackle_reach
	if _owner_id >= 0 and _actors[_owner_id].command.close_control:
		reach *= 0.8
	var legal_contact: bool = _owner_id != actor.actor_id and distance <= reach and _ball.position.y <= 0.45 and actor.forward.dot(direction) >= 0.35 and _clear_contact(actor)
	var event: Event = _record(Event.Kind.TACKLE, actor.actor_id, &"contact" if legal_contact else &"miss")
	_set_gesture(actor, Types.GestureKind.TACKLE, direction, _ball.global_position, _config.tackle_contact_window_ticks)
	event.gesture_kind = Types.GestureKind.TACKLE
	event.success = legal_contact
	if not legal_contact:
		return
	if _owner_id >= 0:
		_actors[_owner_id].receive_cooldown = 0.45
		_actors[_owner_id].possession_seconds = 0.0
	_owner_id = -1
	_receive_lock = 0.12
	actor.receive_cooldown = 0.15
	_ignore_actor_collision(actor.actor_id)
	_collision_release_ticks[actor.actor_id] = _tick + 1
	_ball.kick(_ball.linear_velocity * 0.45 + direction * 3.0 + Vector3.UP * 0.35)
	event.contact_id = _accepted_touch(actor, _ball.global_position)
	event.contact_point = _ball.global_position
	event.velocity = _ball.linear_velocity


func _can_kick(actor: Actor) -> bool:
	var taking: bool = _phase == Snapshot.Phase.RESTART_PAUSE and _restart.taker_actor_id == actor.actor_id and _restart.stage in [Types.RestartStage.PLACEMENT, Types.RestartStage.READY]
	return (_owner_id == actor.actor_id or taking) and _flat_distance(actor.global_position, _ball.global_position) <= _config.control_leash and _ball.position.y <= (1.4 if _ball_in_hands(actor) else (1.15 if actor.role == Snapshot.Role.KEEPER else 0.5)) and _clear_contact(actor)


func _ball_in_hands(actor: Actor) -> bool:
	return _phase in [Snapshot.Phase.RESTART_PAUSE, Snapshot.Phase.PAUSED] and _restart.kind == Types.RestartKind.GOAL_CLEARANCE and _restart.taker_actor_id == actor.actor_id and _restart.stage in [Types.RestartStage.PLACEMENT, Types.RestartStage.READY]


func _clear_contact(actor: Actor) -> bool:
	var from: Vector3 = Vector3(actor.position.x, _ball.position.y, actor.position.z)
	if from.distance_squared_to(_ball.global_position) < 0.000001:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, _ball.global_position, Tuning.WORLD_LAYER | Tuning.ACTOR_LAYER)
	query.exclude = [actor.get_rid(), _ball.get_rid()]
	return _world.direct_space_state.intersect_ray(query).is_empty()


func _check_boundaries(crossing: Types.BoundaryCrossing) -> void:
	if crossing.border != Types.Border.NONE:
		_apply_rule_decision(Rules.boundary_decision(crossing, get_snapshot(), _config))
	elif _ball.global_position.y < -0.5:
		_refuse(ERR_INVALID_DATA, "Ball left the physical floor without a legal boundary crossing")
		_finish(&"invalid_ball_state")


func _apply_rule_decision(decision: Types.RuleDecision) -> void:
	if decision == null:
		_refuse(ERR_INVALID_DATA, "Rules returned no decision object")
		return
	if decision.kind == Types.DecisionKind.NONE:
		if String(decision.reason).begins_with("extended_kick_"):
			_finish(decision.reason)
		return
	if decision.contact_id >= 0:
		if decision.contact_id in _adjudicated_contacts:
			return
		_adjudicated_contacts[decision.contact_id] = true
	if decision.kind == Types.DecisionKind.GOAL:
		if _phase != Snapshot.Phase.PLAYING or decision.scoring_team_id not in [0, 1]:
			return
		_score[decision.scoring_team_id] += 1
		_kickoff_team = 1 - decision.scoring_team_id
		_phase = Snapshot.Phase.GOAL_PAUSE
		_phase_seconds = _config.goal_pause_seconds
		_restricted_kick_live = false
		_ball.control_acceleration = 0.0
		_ball.control_actor_id = -1
		var goal: Event = _record(Event.Kind.GOAL, _last_touch_id, decision.reason)
		goal.team_id = decision.scoring_team_id
		return
	if decision.kind == Types.DecisionKind.FOUL:
		if decision.offender_actor_id not in _actor_ids or decision.victim_actor_id not in _actor_ids:
			_refuse(ERR_INVALID_DATA, "Foul decision names an unknown athlete")
			return
		if decision.counts_as_accumulated_foul:
			_accumulated_fouls[_actors[decision.offender_actor_id].team_id] += 1
		var foul: Event = _record(Event.Kind.FOUL, decision.offender_actor_id, decision.reason)
		foul.target_actor_id = decision.victim_actor_id
		foul.foul_verdict = decision.foul_verdict
		foul.contact_id = decision.contact_id
		foul.contact_point = decision.position
	if decision.restart == null or decision.restart.kind == Types.RestartKind.NONE:
		_refuse(ERR_INVALID_DATA, "An awarded decision requires a typed restart")
		return
	if _period_state == Types.PeriodState.EXTENDED_KICK and _extended_kick_event_id >= 0:
		_finish(&"extended_kick_stopped")
		return
	if _seconds_remaining <= 0.0 and decision.restart.kind not in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		_finish()
		return
	_begin_restart(decision.restart)


func _restart_play() -> void:
	if _seconds_remaining <= 0.0:
		_phase_seconds = 0.0
		_finish()
		return
	var kickoff: Setup = Setup.preview_5v5() if _setup.mode == Setup.Mode.PREVIEW_5V5 else Setup.new()
	kickoff.ai_actor_ids = _setup.ai_actor_ids.duplicate()
	kickoff.training_exercise = _setup.training_exercise
	kickoff.actor_positions[RIVAL_ID] = Vector3(2.0, 0.0, 0.0)
	if _setup.attack_direction(0).x < 0.0:
		for id: int in kickoff.actor_positions:
			var at: Vector3 = kickoff.actor_positions[id]
			at.x = -at.x
			kickoff.actor_positions[id] = at
			var forward: Vector2 = kickoff.actor_forwards[id]
			forward.x = -forward.x
			kickoff.actor_forwards[id] = forward
	var direction: Vector2 = kickoff.actor_forwards[_kickoff_team]
	kickoff.ball_position = kickoff.actor_positions[_kickoff_team] + Vector3(direction.x * 0.55, 0.12, direction.y * 0.55)
	_reset_motion(kickoff)
	_restart = Types.RestartState.new()
	_restricted_kick_live = false
	_restart_kick_event_id = -1
	_phase_seconds = 0.0
	_phase = Snapshot.Phase.PLAYING
	_ball.resume()
	var event: Event = _record(Event.Kind.RESTART, _kickoff_team, &"training_kickoff")
	event.team_id = _kickoff_team


func _exercise_restart() -> Types.RestartState:
	var result: Types.RestartState = Types.RestartState.new()
	result.awarded_team_id = Snapshot.Team.HOME
	result.spot = Vector3(_setup.ball_position.x, Tuning.BALL_RADIUS, _setup.ball_position.z)
	result.offence_spot = result.spot
	result.minimum_opponent_distance = 5.0
	match _setup.training_exercise:
		Setup.TrainingExercise.KICK_IN:
			result.kind = Types.RestartKind.KICK_IN
			result.border = Types.Border.NEG_Z
			result.spot.z = -Tuning.COURT_WIDTH * 0.5
		Setup.TrainingExercise.CORNER_POS_X_NEG_Z, Setup.TrainingExercise.CORNER_POS_X_POS_Z, Setup.TrainingExercise.CORNER_NEG_X_NEG_Z, Setup.TrainingExercise.CORNER_NEG_X_POS_Z:
			result.kind = Types.RestartKind.CORNER
			result.border = Types.Border.POS_X if _setup.attack_direction(0).x > 0.0 else Types.Border.NEG_X
			result.direct_opponent_goal_allowed = true
		Setup.TrainingExercise.GOAL_CLEARANCE:
			result.kind = Types.RestartKind.GOAL_CLEARANCE
			result.minimum_opponent_distance = 0.0
		Setup.TrainingExercise.DIRECT_FREE_KICK:
			result.kind = Types.RestartKind.DIRECT_FREE_KICK
			result.direct_opponent_goal_allowed = true
		Setup.TrainingExercise.PENALTY_6M:
			result.kind = Types.RestartKind.PENALTY_6M
			result.direct_opponent_goal_allowed = true
			result.requires_direct_shot = true
		Setup.TrainingExercise.ACCUMULATED_FREE_KICK:
			result.kind = Types.RestartKind.ACCUMULATED_FREE_KICK
			result.direct_opponent_goal_allowed = true
			result.requires_direct_shot = true
			result.has_spot_choice = true
			result.spot_choice = Types.SpotChoice.TEN_METRE
			result.offence_spot = Vector3(12.0, Tuning.BALL_RADIUS, 8.5)
	if result.kind == Types.RestartKind.NONE:
		if absf(_setup.ball_position.x) > Tuning.COURT_LENGTH * 0.5 + Tuning.BALL_RADIUS:
			result.kind = Types.RestartKind.GOAL_CLEARANCE
			result.awarded_team_id = 1 if _setup.ball_position.x * _setup.attack_direction(0).x > 0.0 else 0
			result.minimum_opponent_distance = 0.0
			result.border = Types.Border.POS_X if _setup.ball_position.x > 0.0 else Types.Border.NEG_X
			result.spot = Vector3(-_setup.attack_direction(result.awarded_team_id).x * 18.0, _config.keeper_hand_height, clampf(_setup.ball_position.z, -3.0, 3.0))
		elif absf(_setup.ball_position.z) > Tuning.COURT_WIDTH * 0.5 + Tuning.BALL_RADIUS:
			result.kind = Types.RestartKind.KICK_IN
			result.border = Types.Border.POS_Z if _setup.ball_position.z > 0.0 else Types.Border.NEG_Z
			result.spot.z = signf(_setup.ball_position.z) * Tuning.COURT_WIDTH * 0.5
	if result.kind != Types.RestartKind.NONE:
		result.taker_actor_id = _nearest_taker(result.awarded_team_id, result.kind, result.spot)
	return result


func _nearest_taker(team: int, kind: Types.RestartKind, spot: Vector3) -> int:
	var best: int = -1
	var distance: float = INF
	for actor: Actor in _actors:
		if actor.team_id != team:
			continue
		if kind == Types.RestartKind.GOAL_CLEARANCE:
			if actor.role == Snapshot.Role.KEEPER:
				return actor.actor_id
			continue
		if actor.role != Snapshot.Role.FIELD:
			continue
		var candidate: float = _flat_distance(actor.position, spot)
		if best == -1 or (candidate < distance and not is_equal_approx(candidate, distance)) or (is_equal_approx(candidate, distance) and actor.actor_id < best):
			best = actor.actor_id
			distance = candidate
	return best


func _begin_restart(awarded: Types.RestartState) -> void:
	if awarded == null or awarded.kind <= Types.RestartKind.NONE or awarded.kind > Types.RestartKind.ACCUMULATED_FREE_KICK or awarded.awarded_team_id not in [0, 1] or awarded.taker_actor_id not in _actor_ids or not awarded.spot.is_finite() or not awarded.offence_spot.is_finite():
		_refuse(ERR_INVALID_DATA, "Invalid restart decision from rules/catalog")
		_finish(&"invalid_restart_decision")
		return
	if _actors[awarded.taker_actor_id].team_id != awarded.awarded_team_id:
		_refuse(ERR_INVALID_DATA, "Restart taker belongs to the wrong team")
		_finish(&"invalid_restart_taker")
		return
	_restart = awarded.copy()
	_restart_sequence += 1
	_restart.id = _restart_sequence
	_restart.launch_contact_id = -1
	_restart.stage = Types.RestartStage.STOPPED
	_restart.stage_started_tick = _tick
	_restart.placement_end_tick = _tick + 1 + Tuning.RESTART_PLACEMENT_TICKS
	_restart.ready_tick = -1
	_restart.deadline_tick = -1
	_restart.other_actor_touched = false
	_restart_kick_event_id = -1
	_restricted_kick_live = false
	_extended_stop_ticks = 0
	_extended_keeper_collected = false
	_phase = Snapshot.Phase.RESTART_PAUSE
	_phase_seconds = 0.0
	_owner_id = -1
	_ball.control_acceleration = 0.0
	_ball.control_actor_id = -1
	_ball.suspend()
	for actor: Actor in _actors:
		_clear_actor_intent(actor)
		actor.velocity = Vector3.ZERO
		actor.gesture_kind = Types.GestureKind.NONE
		actor.gesture_duration_ticks = 0
	if _restart.awarded_team_id == Snapshot.Team.HOME:
		_change_focus(_restart.taker_actor_id, &"restart_taker")
	if _seconds_remaining <= 0.0 and _restart.kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
		_period_state = Types.PeriodState.EXTENDED_KICK
		_extended_restart_id = _restart.id
		_extended_kick_event_id = -1
	_record_restart_changed(&"awarded")


func _step_restart(delta: float) -> void:
	_ball.control_acceleration = 0.0
	_ball.control_actor_id = -1
	match _restart.stage:
		Types.RestartStage.STOPPED:
			if not _apply_restart_placement():
				return
			_restart.stage = Types.RestartStage.PLACEMENT
			_restart.stage_started_tick = _tick
			_restart.placement_end_tick = _tick + Tuning.RESTART_PLACEMENT_TICKS
			_anchor_restart_ball()
			_record_restart_changed(&"placement")
		Types.RestartStage.PLACEMENT:
			for actor: Actor in _actors:
				actor._aim_only(delta, _config)
			_anchor_restart_ball()
			_phase_seconds = maxf(0.0, float(_restart.placement_end_tick - _tick) / Tuning.PHYSICS_HZ)
			if _tick >= _restart.placement_end_tick:
				_restart.stage = Types.RestartStage.READY
				_restart.stage_started_tick = _tick
				_restart.ready_tick = _tick
				_restart.deadline_tick = -1 if _restart.kind == Types.RestartKind.PENALTY_6M else _tick + Tuning.RESTART_DEADLINE_TICKS
				_owner_id = _restart.taker_actor_id
				_record_restart_changed(&"ready")
		Types.RestartStage.READY:
			if _restart.deadline_tick >= 0 and _tick >= _restart.deadline_tick:
				for actor: Actor in _actors:
					if actor.pending_action != null:
						_refuse(ERR_UNAVAILABLE, "Restart deadline elapsed before the pending action", actor.actor_id)
				_record_restart_changed(&"expired")
				_apply_rule_decision(Rules.expiry_decision(get_snapshot(), _config))
				return
			_phase_seconds = maxf(0.0, float(_restart.deadline_tick - _tick) / Tuning.PHYSICS_HZ) if _restart.deadline_tick >= 0 else 0.0
			_drive_ai(delta)
			_step_actors(delta)
			_anchor_restart_ball()
			_resolve_pending_actions()
			if _phase == Snapshot.Phase.PLAYING:
				_clean_collision_exceptions()
				_previous_ball_position = _ball.global_position


func _apply_restart_placement() -> bool:
	var plan: Array[Types.ActorPlacement] = Rules.placement_plan(get_snapshot(), _config)
	if plan.is_empty():
		_refuse(ERR_INVALID_DATA, "Rules could not construct a legal localized placement")
		_finish(&"invalid_restart_placement")
		return false
	var positions: Dictionary[int, Vector3] = {}
	var changed: Array[int] = []
	for actor: Actor in _actors:
		positions[actor.actor_id] = actor.position
	for placement: Types.ActorPlacement in plan:
		if placement == null or placement.actor_id not in _actor_ids or placement.actor_id in changed or not placement.position.is_finite() or not placement.forward.is_finite() or not placement.forward.is_normalized():
			_refuse(ERR_INVALID_DATA, "Rules returned an invalid actor placement")
			_finish(&"invalid_restart_placement")
			return false
		positions[placement.actor_id] = placement.position
		changed.append(placement.actor_id)
	for id: int in positions:
		for other: int in positions:
			if other < id and _flat_distance(positions[id], positions[other]) < Tuning.ACTOR_RADIUS * 2.0:
				_refuse(ERR_INVALID_DATA, "Restart placement overlaps physical athletes")
				_finish(&"overlapping_restart_placement")
				return false
	for id: int in _collision_exceptions:
		_ball.remove_collision_exception_with(_actors[id])
	_collision_exceptions.clear()
	_collision_release_ticks.clear()
	_actor_contact_episodes.clear()
	for placement: Types.ActorPlacement in plan:
		var actor: Actor = _actors[placement.actor_id]
		_clear_actor_intent(actor)
		actor._place_for_restart(placement.position, placement.forward)
	_ball.place(_restart.spot, Vector3.ZERO, Vector3.ZERO)
	_previous_ball_position = _restart.spot
	return true


func _anchor_restart_ball() -> void:
	if _restart.kind == Types.RestartKind.GOAL_CLEARANCE:
		var keeper: Actor = _actors[_restart.taker_actor_id]
		var anchor: Vector3 = keeper.position + keeper.forward * _config.keeper_hand_forward
		anchor.y = _config.keeper_hand_height
		_restart.spot = anchor
		_ball.place(anchor, Vector3.ZERO, Vector3.ZERO)
		_owner_id = keeper.actor_id
	_previous_ball_position = _ball.global_position


func _can_choose_spot(actor: Actor, choice: Types.SpotChoice) -> bool:
	return _phase == Snapshot.Phase.RESTART_PAUSE and _restart.stage == Types.RestartStage.READY and \
		_restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK and _restart.has_spot_choice and \
		actor.actor_id == _restart.taker_actor_id and actor.team_id == _restart.awarded_team_id and \
		choice in [Types.SpotChoice.DEFAULT, Types.SpotChoice.TEN_METRE, Types.SpotChoice.OFFENCE_SPOT] and \
		(_restart.deadline_tick < 0 or _tick < _restart.deadline_tick)


func _choose_restart_spot(actor: Actor, choice: Types.SpotChoice) -> void:
	if not _can_choose_spot(actor, choice):
		_refuse(ERR_UNAVAILABLE, "Restart spot choice is no longer available", actor.actor_id)
		return
	var selected_choice: Types.SpotChoice = Types.SpotChoice.TEN_METRE if choice == Types.SpotChoice.DEFAULT else choice
	if selected_choice == _restart.spot_choice:
		return
	var before: Types.RestartState = _restart.copy()
	_restart.spot_choice = selected_choice
	_restart.spot = _restart.offence_spot if selected_choice == Types.SpotChoice.OFFENCE_SPOT else Vector3(_setup.attack_direction(actor.team_id).x * 10.0, Tuning.BALL_RADIUS, 0.0)
	if not _apply_restart_placement():
		_restart = before
		return
	_owner_id = _restart.taker_actor_id
	_record_restart_changed(&"spot_changed")


func _record_restart_changed(reason: StringName) -> void:
	var event: Event = _record(Event.Kind.RESTART_CHANGED, _restart.taker_actor_id, reason)
	event.team_id = _restart.awarded_team_id
	event.position = _restart.spot
	event.restart = _restart.copy()


func _check_period() -> void:
	if _seconds_remaining > 0.0 or _phase in [Snapshot.Phase.FINISHED, Snapshot.Phase.GOAL_PAUSE]:
		return
	var awaiting: bool = _phase == Snapshot.Phase.RESTART_PAUSE and _restart.kind in [
		Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
	if awaiting or (_phase == Snapshot.Phase.PLAYING and _restricted_kick_live):
		_period_state = Types.PeriodState.EXTENDED_KICK
		_extended_restart_id = _restart.id
		_extended_kick_event_id = _restart_kick_event_id
	else:
		_finish()


func _defending_keeper_id() -> int:
	for actor: Actor in _actors:
		if actor.role == Snapshot.Role.KEEPER and actor.team_id != _restart.awarded_team_id:
			return actor.actor_id
	return -1


func _extension_keeper_held(actor_id: int) -> bool:
	return _period_state == Types.PeriodState.EXTENDED_KICK and _extended_keeper_collected and actor_id == _defending_keeper_id()


func _check_extended_outcome() -> void:
	if not _restricted_kick_live or _restart_kick_event_id < 0 or _phase != Snapshot.Phase.PLAYING:
		return
	var stopped: bool = _ball.linear_velocity.length() <= _config.extended_ball_stop_speed and \
		_ball.angular_velocity.length() * Tuning.BALL_RADIUS <= _config.extended_ball_stop_speed
	_extended_stop_ticks = _extended_stop_ticks + 1 if stopped else 0
	if _extended_stop_ticks >= _config.extended_ball_stop_ticks:
		_restricted_kick_live = false
		if _period_state == Types.PeriodState.EXTENDED_KICK:
			_finish(&"extended_kick_ball_stopped")


func _unselected_home_carrier(actor: Actor) -> bool:
	return actor.team_id == Snapshot.Team.HOME and actor.actor_id != _selected_actor_id and _owner_id == actor.actor_id


func _inside_allied_goal_exclusion(at: Vector3) -> bool:
	return at.x * _setup.attack_direction(0).x >= Tuning.COURT_LENGTH * 0.5 - _config.allied_goal_exclusion_depth and \
		absf(at.z) <= _config.allied_goal_exclusion_half_width


func _allied_goalward_intent(actor: Actor, move: Vector2) -> bool:
	if not _unselected_home_carrier(actor):
		return false
	var motion: Vector3 = Vector3(move.x, 0.0, move.y)
	return motion.dot(_setup.attack_direction(0)) > 0.0 and _inside_allied_goal_exclusion(actor.position + motion * _config.sprint_speed * _config.command_timeout)


func _guard_allied_displacement(actor: Actor, movement: Vector3) -> Vector3:
	if _unselected_home_carrier(actor) and movement.dot(_setup.attack_direction(0)) > 0.0 and _inside_allied_goal_exclusion(actor.position + movement):
		movement.x = 0.0
	return movement


func _finish(reason: StringName = &"training_time_elapsed") -> void:
	if _phase == Snapshot.Phase.FINISHED:
		return
	_phase = Snapshot.Phase.FINISHED
	_phase_seconds = 0.0
	_ball.suspend()
	_record(Event.Kind.END, -1, reason)


func _reset_motion(setup: Setup) -> void:
	for id: int in _collision_exceptions:
		_ball.remove_collision_exception_with(_actors[id])
	_collision_exceptions.clear()
	_collision_release_ticks.clear()
	_actor_contact_episodes.clear()
	_ball_touch_ticks.clear()
	_tackle_started_ticks.clear()
	_reconcile_actors(_ids_for_mode(setup.mode))
	for actor: Actor in _actors:
		actor.reset_state(setup.actor_positions[actor.actor_id], setup.actor_forwards[actor.actor_id])
	_ball.place(setup.ball_position, setup.ball_velocity, setup.ball_angular_velocity)
	_selected_actor_id = HUMAN_ID
	_previous_ball_position = setup.ball_position
	_owner_id = -1
	_last_touch_id = -1
	_last_touch_tick = -1
	_last_pass_actor_id = -1
	_last_pass_target_actor_id = -1
	_last_pass_tick = -1
	_receive_lock = 0.0
	_shot_id = -1
	_shot_team = -1
	_shot_age = 0.0
	_saved_shot_id = -1
	_events.clear()


func _ignore_actor_collision(id: int) -> void:
	if id not in _collision_exceptions:
		_ball.add_collision_exception_with(_actors[id])
		_collision_exceptions.append(id)


func _clean_collision_exceptions() -> void:
	_ball._refresh_release_episode(_world.direct_space_state, _ball.snapshot_transform())
	for index: int in range(_collision_exceptions.size() - 1, -1, -1):
		var id: int = _collision_exceptions[index]
		if id != _owner_id and _tick > int(_collision_release_ticks.get(id, -1)) and _flat_distance(_actors[id].global_position, _ball.global_position) > Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 0.03:
			_ball.remove_collision_exception_with(_actors[id])
			_collision_exceptions.remove_at(index)
			_collision_release_ticks.erase(id)


func _contact_number(key: String = "") -> int:
	if not key.is_empty() and key in _contact_keys:
		return _contact_keys[key]
	_contact_sequence += 1
	if not key.is_empty():
		_contact_keys[key] = _contact_sequence
	return _contact_sequence


func _accepted_touch(actor: Actor, at: Vector3, contact_id: int = -1) -> int:
	var contact: Types.ContactEvidence = Types.ContactEvidence.new()
	contact.contact_id = _contact_number() if contact_id < 0 else contact_id
	contact.tick = _tick
	contact.actor_id = actor.actor_id
	contact.kind = Types.ContactKind.BALL_ACTOR
	contact.point = at
	contact.normal = _flat_direction(at, actor.position)
	contact.actor_velocity = actor.velocity
	contact.other_velocity = _ball.linear_velocity
	contact.tackle_started_tick = int(_tackle_started_ticks.get(actor.actor_id, -1))
	contact.ball_touch_tick = _tick
	_ball._begin_release_episode(actor.get_rid(), actor.get_instance_id(), contact.contact_id, _world.direct_space_state)
	_register_ball_touch(contact, true)
	return contact.contact_id


func _consume_ball_contacts(samples: Array[Dictionary], crossing: Types.BoundaryCrossing, apply_rules: bool) -> void:
	var displacement: Vector3 = _ball.global_position - _previous_ball_position
	var squared: float = displacement.length_squared()
	for sample: Dictionary in samples:
		var center: Vector3 = sample["ball_position"]
		sample["fraction"] = (center - _previous_ball_position).dot(displacement) / squared if squared > 0.000001 else 0.0
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["fraction"]) < float(b["fraction"]))
	for sample: Dictionary in samples:
		var id: int = int(sample["actor_id"])
		var key: String = "%s:%d" % [sample["source"], int(sample["episode"])]
		var contact_id: int = int(sample.get("contact_id", -1))
		if contact_id < 0:
			contact_id = _contact_number(key)
		else:
			_contact_keys[key] = contact_id
		var event: Event = _record(Event.Kind.BALL_CONTACT, id, sample["surface"])
		event.contact_id = contact_id
		event.contact_point = sample["point"]
		event.position = sample["ball_position"]
		event.velocity = sample["ball_velocity"]
		if not apply_rules or id not in _actor_ids or _phase != Snapshot.Phase.PLAYING:
			continue
		if crossing != null and crossing.border != Types.Border.NONE and float(sample["fraction"]) > crossing.fraction + 0.00001:
			continue
		var contact: Types.ContactEvidence = Types.ContactEvidence.new()
		contact.contact_id = contact_id
		contact.tick = _tick
		contact.actor_id = id
		contact.kind = Types.ContactKind.BALL_ACTOR
		contact.point = sample["point"]
		contact.normal = sample["normal"]
		contact.actor_velocity = sample["actor_velocity"]
		contact.other_velocity = sample["ball_velocity"]
		contact.tackle_started_tick = int(_tackle_started_ticks.get(id, -1))
		contact.ball_touch_tick = _tick
		_register_ball_touch(contact, sample["source"] == &"control")


func _register_ball_touch(contact: Types.ContactEvidence, controlled: bool) -> void:
	if contact.contact_id in _registered_touches:
		return
	_registered_touches[contact.contact_id] = true
	var actor: Actor = _actors[contact.actor_id]
	var decision: Types.RuleDecision = Rules.contact_decision(contact, get_snapshot(), _config)
	_last_touch_id = actor.actor_id
	_last_touch_tick = contact.tick
	_ball_touch_ticks[actor.actor_id] = contact.tick
	if actor.role == Snapshot.Role.KEEPER:
		_record_save(actor, &"collected" if controlled else &"body_contact")
	_shot_id = -1
	if _restart.stage == Types.RestartStage.IN_PLAY:
		if actor.actor_id != _restart.taker_actor_id:
			_restart.other_actor_touched = true
		var original_release: bool = actor.actor_id == _restart.taker_actor_id and contact.contact_id == _restart.launch_contact_id
		if _restricted_kick_live and not original_release:
			if actor.actor_id == _defending_keeper_id():
				_extended_keeper_collected = _extended_keeper_collected or controlled
			else:
				_restricted_kick_live = false
				if _period_state == Types.PeriodState.EXTENDED_KICK and _extended_kick_event_id >= 0:
					_finish(&"extended_kick_other_player_touch")
					return
	_apply_rule_decision(decision)


func _consume_actor_contacts(touches_before_motion: Dictionary[int, int]) -> void:
	var candidates: Dictionary[String, Dictionary] = {}
	for actor: Actor in _actors:
		for sample: Dictionary in actor._take_slide_contacts():
			var other: int = int(sample["actor_id"])
			if other not in _actor_ids or _actors[other].team_id == actor.team_id:
				continue
			var key: String = "%d:%d" % [mini(actor.actor_id, other), maxi(actor.actor_id, other)]
			sample["offender"] = actor.actor_id
			var start: int = int(_tackle_started_ticks.get(actor.actor_id, -1))
			var active: bool = start >= 0 and _tick >= start and _tick - start <= _config.foul_challenge_window_ticks
			var relative: Vector3 = Vector3(sample["actor_velocity"]) - Vector3(sample["other_velocity"])
			var closing: float = maxf(0.0, -relative.dot(Vector3(sample["normal"])))
			sample["priority"] = closing + (100.0 if active else 0.0)
			if key not in candidates or float(sample["priority"]) > float(candidates[key]["priority"]):
				candidates[key] = sample
	var active_episodes: Dictionary[String, int] = {}
	var keys: Array[String] = []
	keys.assign(candidates.keys())
	keys.sort()
	for key: String in keys:
		var sample: Dictionary = candidates[key]
		var is_new: bool = key not in _actor_contact_episodes
		var episode: int = _contact_number() if is_new else _actor_contact_episodes[key]
		active_episodes[key] = episode
		if not is_new or _phase != Snapshot.Phase.PLAYING:
			continue
		var id: int = int(sample["offender"])
		var contact: Types.ContactEvidence = Types.ContactEvidence.new()
		contact.contact_id = episode
		contact.tick = _tick
		contact.kind = Types.ContactKind.ACTOR_ACTOR
		contact.actor_id = id
		contact.other_actor_id = int(sample["actor_id"])
		contact.point = sample["point"]
		contact.normal = sample["normal"]
		contact.actor_velocity = sample["actor_velocity"]
		contact.other_velocity = sample["other_velocity"]
		contact.tackle_started_tick = int(_tackle_started_ticks.get(id, -1))
		contact.ball_touch_tick = int(touches_before_motion.get(id, -1))
		var active_challenge: bool = contact.tackle_started_tick >= 0 and _tick >= contact.tackle_started_tick and \
			_tick - contact.tackle_started_tick <= _config.foul_challenge_window_ticks
		contact.ball_touched_first = active_challenge and contact.ball_touch_tick >= contact.tackle_started_tick and contact.ball_touch_tick <= _tick
		_apply_rule_decision(Rules.contact_decision(contact, get_snapshot(), _config))
	_actor_contact_episodes = active_episodes


func _record_save(actor: Actor, reason: StringName) -> void:
	if _shot_id >= 0 and _shot_team != actor.team_id and _saved_shot_id != _shot_id:
		_saved_shot_id = _shot_id
		_record(Event.Kind.SAVE, actor.actor_id, reason)


func _record(kind: Event.Kind, actor_id: int, reason: StringName) -> Event:
	var event: Event = Event.new()
	event.event_id = _event_sequence
	_event_sequence += 1
	event.tick = _tick
	event.kind = kind
	event.actor_id = actor_id
	event.team_id = _actors[actor_id].team_id if actor_id >= 0 else -1
	event.position = _ball.global_position
	event.velocity = _ball.linear_velocity
	event.score = _score
	event.reason = reason
	event.restart = _restart.copy()
	_events.append(event)
	return event


func _deliver_events() -> void:
	var pending: Array[Event] = _events.duplicate()
	_events.clear()
	for event: Event in pending:
		match event.kind:
			Event.Kind.GOAL:
				goal_scored.emit(event)
			Event.Kind.PASS:
				pass_made.emit(event)
			Event.Kind.SHOT:
				shot_taken.emit(event)
			Event.Kind.SAVE:
				save_made.emit(event)
			Event.Kind.RESTART:
				restarted.emit(event)
			Event.Kind.END:
				match_ended.emit(event)
			Event.Kind.BALL_CONTACT:
				ball_contact.emit(event)
		event_raised.emit(event)


func _refuse(code: Error, message: String, actor_id: int = -1) -> Error:
	if _notifying_refusal:
		return code
	last_error = message
	_notifying_refusal = true
	command_rejected.emit(actor_id, code, message)
	_notifying_refusal = false
	return code


func _validate_setup(setup: Setup) -> String:
	if setup.mode not in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		return "Unknown training mode"
	if setup.training_exercise < Setup.TrainingExercise.FREE_PLAY or setup.training_exercise > Setup.TrainingExercise.ACCUMULATED_FREE_KICK:
		return "Unknown catalogued training exercise"
	var ids: Array[int] = _ids_for_mode(setup.mode)
	if setup.actor_positions.size() != ids.size() or setup.actor_forwards.size() != ids.size():
		return "A training setup must describe exactly the actors of its explicit mode"
	for id: int in ids:
		if not setup.actor_positions.has(id) or not setup.actor_forwards.has(id):
			return "A training setup is missing a stable actor ID"
		var at: Vector3 = setup.actor_positions[id]
		if not at.is_finite() or absf(at.y) > 0.00001 or absf(at.x) > 19.6 or absf(at.z) > 9.6:
			return "Actor %d needs finite court coordinates with feet at y=0" % id
		var direction: Vector2 = setup.actor_forwards[id]
		if not direction.is_finite() or not direction.is_normalized():
			return "Actor %d needs a finite unit facing vector" % id
		for other: int in ids:
			if other < id and at.distance_to(setup.actor_positions[other]) < Tuning.ACTOR_RADIUS * 2.0 + 0.02:
				return "Actor starting capsules must not overlap"
	var ai_error: String = _validate_ai_ids(setup.ai_actor_ids, ids)
	if not ai_error.is_empty():
		return ai_error
	var ball: Vector3 = setup.ball_position
	if not ball.is_finite() or absf(ball.x) > 22.0 or absf(ball.z) > 12.0 or ball.y < Tuning.BALL_RADIUS or ball.y > 6.0:
		return "Ball needs finite training-floor coordinates, radius <= y <= 6"
	if not setup.ball_velocity.is_finite() or setup.ball_velocity.length() > tuning.maximum_ball_speed:
		return "Ball velocity exceeds the finite permitted speed"
	if not setup.ball_angular_velocity.is_finite() or setup.ball_angular_velocity.length() > 400.0:
		return "Ball angular velocity must be finite and <= 400 rad/s"
	for box: AABB in _frame_boxes:
		var nearest: Vector3 = ball.clamp(box.position, box.end)
		if nearest.distance_squared_to(ball) < Tuning.BALL_RADIUS * Tuning.BALL_RADIUS - 0.000001:
			return "Ball starts overlapping a goal frame or net collider"
	return ""


func _validate_ai_ids(ids: Array[int], active_ids: Array[int]) -> String:
	var unique: Array[int] = []
	for id: int in ids:
		if id not in active_ids or id in unique:
			return "AI intent IDs must be unique active actors"
		unique.append(id)
	return ""


func _ids_for_mode(mode: Setup.Mode) -> Array[int]:
	return PREVIEW_ACTOR_IDS if mode == Setup.Mode.PREVIEW_5V5 else ACTOR_IDS


func _reconcile_actors(ids: Array[int]) -> void:
	for index: int in range(_actors.size() - 1, -1, -1):
		if _actors[index].actor_id not in ids:
			_actors[index].free()
			_actors.remove_at(index)
	for id: int in ids:
		if id >= _actors.size():
			_create_actor(id)
	_actor_ids = ids.duplicate()


func _create_actor(id: int) -> void:
	var actor: Actor = Actor.new()
	actor.name = "Actor%d" % id
	actor.actor_id = id
	actor.team_id = id % 2
	actor.role = Snapshot.Role.KEEPER if id in [HOME_KEEPER_ID, AWAY_KEEPER_ID] else Snapshot.Role.FIELD
	add_child(actor)
	PhysicsServer3D.body_set_space(actor.get_rid(), _world.space)
	_actors.append(actor)


func _create_world() -> void:
	# Jolt snapshots these settings when a space/body is created; per-space setters are unsupported.
	var previous_settings: Dictionary[StringName, Variant] = {}
	for key: StringName in Tuning.NATIVE_JOLT_PROFILE:
		previous_settings[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, Tuning.NATIVE_JOLT_PROFILE[key])
	ProjectSettings.settings_changed.emit()
	_world = World3D.new()
	PhysicsServer3D.space_set_active(_world.space, true)
	_static_box("TrainingFloor", Vector3(48.0, 0.4, 28.0), Vector3(0.0, -0.2, 0.0), &"floor")
	for sign_value: float in [-1.0, 1.0]:
		var goal_x: float = sign_value * Tuning.COURT_LENGTH * 0.5
		var prefix: String = "HomeGoal" if sign_value < 0.0 else "AwayGoal"
		var post: float = Tuning.POST_THICKNESS
		for side: float in [-1.0, 1.0]:
			var side_name: String = "Left" if side < 0.0 else "Right"
			_static_box(prefix + side_name + "Post",
				Vector3(post, Tuning.GOAL_HEIGHT + post, post),
				Vector3(goal_x, (Tuning.GOAL_HEIGHT + post) * 0.5, side * Tuning.GOAL_POST_CENTER_Z), &"post")
			_static_box(prefix + side_name + "Net",
				Vector3(Tuning.GOAL_DEPTH, Tuning.GOAL_HEIGHT, Tuning.NET_THICKNESS),
				Vector3(goal_x + sign_value * (Tuning.GOAL_DEPTH * 0.5 + post * 0.5), Tuning.GOAL_HEIGHT * 0.5, side * (Tuning.GOAL_WIDTH * 0.5 + post + Tuning.NET_THICKNESS * 0.5)), &"net")
		_static_box(prefix + "Crossbar",
			Vector3(post, post, Tuning.GOAL_WIDTH + post * 2.0),
			Vector3(goal_x, Tuning.GOAL_HEIGHT + post * 0.5, 0.0), &"crossbar")
		_static_box(prefix + "BackNet",
			Vector3(Tuning.NET_THICKNESS, Tuning.GOAL_HEIGHT, Tuning.GOAL_WIDTH + post * 2.0),
			Vector3(goal_x + sign_value * Tuning.GOAL_DEPTH, Tuning.GOAL_HEIGHT * 0.5, 0.0), &"net")
		_static_box(prefix + "RoofNet",
			Vector3(Tuning.GOAL_DEPTH, Tuning.NET_THICKNESS, Tuning.GOAL_WIDTH + post * 2.0),
			Vector3(goal_x + sign_value * (Tuning.GOAL_DEPTH * 0.5 + post * 0.5), Tuning.GOAL_HEIGHT + post, 0.0), &"net")
	for id: int in _ids_for_mode(Setup.Mode.MICRO_1V1):
		_create_actor(id)
	_ball = Ball.new()
	_ball.name = "Ball"
	add_child(_ball)
	PhysicsServer3D.body_set_space(_ball.get_rid(), _world.space)
	for key: StringName in previous_settings:
		ProjectSettings.set_setting(key, previous_settings[key])
	ProjectSettings.settings_changed.emit()


func _static_box(node_name: String, size: Vector3, at: Vector3, surface: StringName) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.collision_layer = Tuning.WORLD_LAYER
	body.collision_mask = Tuning.BALL_LAYER | Tuning.ACTOR_LAYER
	body.set_meta(&"surface", surface)
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = 0.55 if surface == &"floor" else 0.3
	material.bounce = 0.0 if surface != &"net" else 0.05
	body.physics_material_override = material
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	PhysicsServer3D.body_set_space(body.get_rid(), _world.space)
	if surface != &"floor":
		_frame_boxes.append(AABB(at - size * 0.5, size))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
