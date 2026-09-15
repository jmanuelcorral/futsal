extends Node
## Adaptador de InputMap. Solo intención; la autoridad valida el contacto final.

const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Camera = preload("res://match/presentation/camera/broadcast_camera.gd")
const FULL_CHARGE_SECONDS: float = 0.8
const FINE_AIM_RADIANS_PER_SECOND: float = PI / 6.0
const FINE_AIM_HINT: String = "Saque propio · Ctrl + (A/D o ←/→) / LT + stick izq. lateral: ajuste fino"

signal feedback_requested(message: String)
signal physics_sample_requested(delta: float)

var enabled: bool = false
var shot_charge: float = 0.0
var active_joypad: int = -1
var sample_count: int = 0

var _waiting_for_neutral: bool = true
var _neutral_hint_shown: bool = false
var _pass_pressed: bool = false
var _pass_blocked: bool = false
var _shoot_pressed: bool = false
var _shoot_released: bool = false
var _charging: bool = false
var _shoot_blocked: bool = false
var _dribble_pressed: bool = false
var _dribble_blocked: bool = false
var _context: int = -1
var _selected_id: int = -1
var _owner_id: int = -1
var _restart_id: int = -1
var _restart_spot: Vector3 = Vector3.ZERO
var _restart_aim: Vector2 = Vector2.ZERO
var _fine_hold: bool = false
var _fine_turn_sign: float = 1.0
var _fine_input_direction: Vector2 = Vector2.ZERO
var _sample_tick: int = -1
var _sample_command: Command
var _preview_command: Command


func _physics_process(delta: float) -> void:
	if enabled:
		physics_sample_requested.emit(delta)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	clear()


func clear() -> void:
	clear_for_focus_change()
	_waiting_for_neutral = true
	_neutral_hint_shown = false
	_restart_aim = Vector2.ZERO
	_fine_hold = false


func clear_for_focus_change() -> void:
	_pass_pressed = false
	_pass_blocked = Input.is_action_pressed("pass")
	_shoot_pressed = false
	_shoot_released = false
	_charging = false
	shot_charge = 0.0
	_shoot_blocked = Input.is_action_pressed("shoot")
	_dribble_pressed = false
	_dribble_blocked = Input.is_action_pressed("dribble")
	clear_preview()
	_sample_tick = -1
	_sample_command = null


func clear_preview() -> void:
	_preview_command = null


## Copia de la última intención muestreada. Nunca consume flancos ni avanza carga.
func get_preview_command() -> Command:
	return _preview_command.copy() if _preview_command != null else null


func sync_context(state: Snapshot) -> void:
	var context_changed: bool = _context != state.human_control_context
	var restart_changed: bool = _restart_id != state.restart.id or _restart_spot != state.restart.spot
	var keep_prepared_aim: bool = _own_restart(state) and not restart_changed \
		and _selected_id == state.selected_actor_id and _context in [
			Rules.ControlContext.DISABLED, Rules.ControlContext.RESTART_AIM]
	if context_changed or _selected_id != state.selected_actor_id or restart_changed:
		clear_for_focus_change()
		if not keep_prepared_aim:
			_restart_aim = Vector2.ZERO
			_fine_hold = false
	elif _owner_id == state.selected_actor_id and state.ball_owner_id != _owner_id \
			and state.human_control_context == Rules.ControlContext.LIVE:
		_cancel_charge()
		clear_preview()
	_context = state.human_control_context
	_selected_id = state.selected_actor_id
	_owner_id = state.ball_owner_id
	_restart_id = state.restart.id
	_restart_spot = state.restart.spot


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _waiting_for_neutral or event.is_echo():
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		active_joypad = event.device
	elif event is InputEventKey:
		active_joypad = -1
	if event.is_action_released("shoot"):
		if not Input.is_action_pressed("shoot"):
			_shoot_released = not _shoot_blocked
			_shoot_blocked = false
	elif event.is_action_pressed("shoot") and not _shoot_blocked:
		_shoot_pressed = true
	if event.is_action_released("pass"):
		_pass_blocked = Input.is_action_pressed("pass")
	elif event.is_action_pressed("pass") and not _pass_blocked:
		_pass_pressed = true
		_pass_blocked = true
	if event.is_action_released("dribble"):
		_dribble_blocked = Input.is_action_pressed("dribble")
	elif event.is_action_pressed("dribble") and not _dribble_blocked:
		_dribble_pressed = true
		_dribble_blocked = true


func sample(state: Snapshot, camera: Camera, delta: float) -> Command:
	sync_context(state)
	if _sample_tick == state.tick and _sample_command != null:
		return _sample_command.copy()
	sample_count += 1
	var actor: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	var command: Command = Command.new(actor.actor_id, actor.last_command_sequence + 1)
	if not enabled:
		clear_preview()
		return _cache_sample(state, command)
	var stick: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _waiting_for_neutral:
		if stick.is_zero_approx() and not Input.is_action_pressed("shoot") \
				and not Input.is_action_pressed("pass") and not Input.is_action_pressed("sprint") \
				and not Input.is_action_pressed("close_control") and not Input.is_action_pressed("dribble"):
			_waiting_for_neutral = false
			_pass_blocked = false
			_shoot_blocked = false
			_dribble_blocked = false
			camera.release_input_projection()
		elif not _neutral_hint_shown:
			_neutral_hint_shown = true
			feedback_requested.emit("Suelta los controles para continuar")
		return _cache_sample(state, command)
	var direction: Vector2 = camera.screen_direction_to_court(stick)
	if state.selected_can_move:
		command.move = direction
		command.sprint = Input.is_action_pressed("sprint")
		command.close_control = Input.is_action_pressed("close_control")
	command.aim = direction.normalized()
	var aiming_restart: bool = _own_restart(state)
	if aiming_restart:
		command.aim = _stopped_aim(actor, stick, direction, camera, delta)
	var has_ball: bool = state.ball_owner_id == actor.actor_id
	if state.human_control_context == Rules.ControlContext.DISABLED:
		clear_for_focus_change()
		_update_preview(state, command)
		return _cache_sample(state, command)
	if _charging and not _allowed(state, Command.Action.SHOOT):
		_cancel_charge()
	if not Input.is_action_pressed("shoot") and not _shoot_pressed:
		_shoot_blocked = false
	if _pass_pressed:
		_cancel_charge()
		if not aiming_restart and not has_ball:
			if _allowed(state, Command.Action.SWITCH_TEAMMATE):
				command.action = Command.Action.SWITCH_TEAMMATE
			else:
				feedback_requested.emit("Cambio no disponible en este contexto")
		elif _allowed(state, Command.Action.KEEPER_THROW):
			command.action = Command.Action.KEEPER_THROW
		elif _allowed(state, Command.Action.PASS) and actor.action_cooldown <= 0.0:
			command.action = Command.Action.PASS
		else:
			feedback_requested.emit("Este saque exige un tiro" if aiming_restart and _allowed(state, Command.Action.SHOOT)
				else "Espera al siguiente apoyo")
	elif _dribble_pressed:
		_cancel_charge()
		if _allowed(state, Command.Action.CHOOSE_RESTART_SPOT):
			command.action = Command.Action.CHOOSE_RESTART_SPOT
			command.restart_spot_choice = Rules.SpotChoice.OFFENCE_SPOT if state.restart.spot_choice \
				== Rules.SpotChoice.TEN_METRE else Rules.SpotChoice.TEN_METRE
		elif has_ball and _allowed(state, Command.Action.DRIBBLE) and actor.action_cooldown <= 0.0:
			command.action = Command.Action.DRIBBLE
		else:
			feedback_requested.emit("Regate no disponible en este contexto")
	elif _shoot_pressed and not _shoot_blocked:
		if actor.action_cooldown > 0.0:
			feedback_requested.emit("Espera al siguiente apoyo")
			_shoot_blocked = true
		elif (has_ball or aiming_restart) and _allowed(state, Command.Action.SHOOT):
			_charging = true
			shot_charge = 0.0
		elif not has_ball and _allowed(state, Command.Action.TACKLE):
			command.action = Command.Action.TACKLE
			_shoot_blocked = true
		else:
			_shoot_blocked = true
			feedback_requested.emit("J / A: lanzamiento del portero" if _allowed(state,
				Command.Action.KEEPER_THROW) else ("Saque rival: defiende sin entrar al balón" if
				state.human_control_context == Rules.ControlContext.RESTART_DEFEND else "Espera a que el saque esté listo"))
	if _charging:
		shot_charge = minf(1.0, shot_charge + delta / FULL_CHARGE_SECONDS)
		if _shoot_released:
			command.action = Command.Action.SHOOT
			command.shot_charge = shot_charge
			_cancel_charge()
	_update_preview(state, command)
	if command.action == Command.Action.SHOOT:
		clear_preview()
	_pass_pressed = false
	_dribble_pressed = false
	_shoot_pressed = false
	_shoot_released = false
	return _cache_sample(state, command)


func _allowed(state: Snapshot, action: Command.Action) -> bool:
	return state.human_allowed_actions.has(action)


func _own_restart(state: Snapshot) -> bool:
	return state.restart.kind != Rules.RestartKind.NONE and state.restart.stage in [
		Rules.RestartStage.STOPPED, Rules.RestartStage.PLACEMENT, Rules.RestartStage.READY] \
		and state.restart.awarded_team_id == Snapshot.Team.HOME \
		and state.restart.taker_actor_id == state.selected_actor_id


func _stopped_aim(actor: Snapshot.ActorSnapshot, stick: Vector2, direction: Vector2,
		camera: Camera, delta: float) -> Vector2:
	var fine: bool = Input.is_action_pressed("close_control")
	if stick.is_zero_approx():
		_fine_hold = false
	elif fine and absf(stick.x) > 0.01:
		if _restart_aim.is_zero_approx():
			_restart_aim = Vector2(actor.forward.x, actor.forward.z).normalized()
		if not _fine_hold:
			var right: Vector3 = camera.get_input_projection()["right"]
			var tangent: Vector2 = Vector2(-_restart_aim.y, _restart_aim.x)
			_fine_turn_sign = -1.0 if tangent.dot(Vector2(right.x, right.z)) < -0.001 else 1.0
		_fine_hold = true
		_fine_input_direction = stick.normalized()
		_restart_aim = _restart_aim.rotated(
			stick.x * _fine_turn_sign * FINE_AIM_RADIANS_PER_SECOND * delta).normalized()
	else:
		if _fine_hold and _fine_input_direction.dot(stick.normalized()) < Camera.DIRECTION_CHANGE_COSINE:
			_fine_hold = false
		if not _fine_hold:
			_restart_aim = direction.normalized()
	return _restart_aim


func _update_preview(state: Snapshot, command: Command) -> void:
	clear_preview()
	if command.action in [Command.Action.SHOOT, Command.Action.KEEPER_THROW] \
			or (_own_restart(state) and command.action == Command.Action.PASS):
		_preview_command = command.copy()
	elif _charging:
		_preview_command = command.copy()
		_preview_command.action = Command.Action.SHOOT
		_preview_command.shot_charge = shot_charge
	elif _own_restart(state):
		_preview_command = command.copy()
		if state.restart.kind == Rules.RestartKind.GOAL_CLEARANCE:
			_preview_command.action = Command.Action.KEEPER_THROW
		elif state.restart.requires_direct_shot:
			_preview_command.action = Command.Action.SHOOT
		else:
			_preview_command.action = Command.Action.PASS
	if _preview_command != null:
		_preview_command.restart_spot_choice = Rules.SpotChoice.DEFAULT


func _cache_sample(state: Snapshot, command: Command) -> Command:
	_sample_tick = state.tick
	_sample_command = command.copy()
	return command


func _cancel_charge() -> void:
	_charging = false
	shot_charge = 0.0
	_shoot_pressed = false
	_shoot_released = false
	_shoot_blocked = Input.is_action_pressed("shoot")
