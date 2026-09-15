extends Node3D
## Anfitrión de entrenamiento: preview 5v5 explícita y micro 1v1 de regresión.
## APIs start/restart/pause se invocan fuera de la entrega de eventos del core.

const Simulation = preload("res://match/simulation/match_simulation.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Launch = preload("res://match/simulation/match_launch.gd")
const Hud = preload("res://match/presentation/hud/match_hud.gd")
const MatchInput = preload("res://match/presentation/input/match_input.gd")
const BroadcastCamera = preload("res://match/presentation/camera/broadcast_camera.gd")
const Athlete = preload("res://match/presentation/athletes/athlete_view.gd")
const BallView = preload("res://match/presentation/ball/ball_view.gd")
const DevMenu = preload("res://match/presentation/development/match_dev_menu.gd")
const AimGuide = preload("res://match/presentation/aim/world_aim_guide.gd")

signal command_submitted(command: Command, result: Error)
signal exit_requested()
signal integration_error(code: Error, message: String)

@onready var _simulation: Simulation = $Simulation
@onready var _input_adapter: MatchInput = $MatchInput
@onready var _camera: BroadcastCamera = $BroadcastCamera
@onready var _hud: Hud = $MatchHUD
@onready var _ball_view: BallView = $BallView
@onready var _development_menu: DevMenu = $MatchDevMenu
@onready var _aim_guide: AimGuide = $BallView/WorldAimGuide

var _athletes: Dictionary[int, Athlete] = {}
var _before: Snapshot
var _state: Snapshot
var _setup: Setup
var _events: Array[Event] = []
var _finished_presented: bool = false
var _feedback_cooldown: float = 0.0
var _last_restart_feedback: String = ""
var _last_feedback_restart_id: int = -1
var _last_feedback_actor_id: int = -1
var _snap_camera: bool = true
var _exiting: bool = false
var _sampled_action: Command.Action = Command.Action.NONE
var _aim_guide_enabled: bool = true
var _launch_preview: Launch.Solution


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--diagnostic-bootstrap"):
		_open_diagnostic.call_deferred()
		return
	_simulation.event_raised.connect(_queue_event)
	_simulation.command_rejected.connect(_on_command_rejected)
	_input_adapter.feedback_requested.connect(_show_feedback)
	_hud.set_restart_aim_hint(MatchInput.FINE_AIM_HINT)
	_input_adapter.physics_sample_requested.connect(_sample_human_input)
	_hud.pause_requested.connect(_request_pause.bind(true))
	_hud.resume_requested.connect(_request_pause.bind(false))
	_hud.restart_requested.connect(_request_restart)
	_hud.quit_requested.connect(_request_exit)
	_hud.development_requested.connect(_request_development)
	_development_menu.mode_requested.connect(_request_development_mode)
	_development_menu.ai_actor_ids_requested.connect(_request_ai_actor_ids)
	_development_menu.close_requested.connect(_request_close_development)
	_development_menu.aim_guide_requested.connect(_request_aim_guide)
	_development_menu.exercise_requested.connect(_request_training_exercise)
	_development_menu.set_aim_guide_enabled(_aim_guide_enabled)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_window().focus_exited.connect(_on_focus_lost)
	var result: Error = start_match(Setup.preview_5v5())
	if result != OK:
		_report_error(result, "No se pudo iniciar el entrenamiento: " + _simulation.last_error)
		return
	if OS.get_cmdline_user_args().has("--smoke-test") or OS.get_cmdline_user_args().has("--gameplay-smoke"):
		_run_smoke()


func _run_smoke() -> void:
	var smoke_path: String = "res://diagnostics/gameplay_smoke.gd" if OS.get_cmdline_user_args().has(
		"--gameplay-smoke") else "res://diagnostics/match_smoke.gd"
	var smoke_script: Script = load(smoke_path) as Script
	if smoke_script == null or not smoke_script.can_instantiate():
		_report_error(ERR_CANT_OPEN, "No se pudo cargar el diagnóstico de partido solicitado")
		get_tree().quit(2)
		return
	var smoke: Node = smoke_script.new() as Node
	if smoke == null or not smoke.has_method("run"):
		if smoke != null:
			smoke.free()
		_report_error(ERR_INVALID_DATA, "El diagnóstico solicitado no expone run(simulation, hud)")
		get_tree().quit(2)
		return
	smoke.name = "MatchSmoke"
	add_child(smoke)
	smoke.call("run", _simulation, _hud)


func _open_diagnostic() -> void:
	var result: Error = get_tree().change_scene_to_file("res://bootstrap/bootstrap.tscn")
	if result != OK:
		push_error("No se pudo abrir el diagnóstico: " + error_string(result))
		get_tree().quit(2)


## Un setup opcional permite drills reproducibles usando la autoridad de producción.
func start_match(setup: Setup = null) -> Error:
	if not is_instance_valid(_simulation):
		return _development_error(ERR_UNCONFIGURED, "Añade el partido al árbol antes de iniciarlo")
	var pending_events: int = _events.size()
	var result: Error = _simulation.start(setup)
	if result != OK:
		return _development_error(result, "No se pudo aplicar el entrenamiento: " + _simulation.last_error)
	_events = _events.slice(pending_events)
	_setup = setup.copy() if setup != null else Setup.new()
	_state = _simulation.get_snapshot()
	_setup.ai_actor_ids = _state.ai_intent_actor_ids.duplicate()
	_reconcile_athletes(true)
	_finished_presented = false
	_feedback_cooldown = 0.0
	_last_restart_feedback = ""
	_last_feedback_restart_id = -1
	_last_feedback_actor_id = -1
	_hud.clear_restart_feedback()
	_development_menu.set_open(false)
	_hud.set_development_open(false)
	_hud.clear_result()
	_hud.set_paused(false)
	_development_menu.show_error("")
	_input_adapter.clear()
	_camera.reset_context()
	_clear_launch_preview()
	_sync_input(_state)
	_before = _state
	_snap_camera = true
	_drain_events()
	_update_hud()
	_present(0.0, 1.0)
	return OK


func restart_match() -> Error:
	if not is_instance_valid(_simulation):
		return _development_error(ERR_UNCONFIGURED, "No hay una autoridad inicializada")
	var live: Snapshot = _simulation.get_snapshot()
	var setup: Setup = _setup.copy() if _setup != null and _setup.mode == live.mode \
		and _setup.training_exercise == live.training_exercise else Setup.for_exercise(live.mode, live.training_exercise)
	if setup == null:
		return _development_error(ERR_INVALID_PARAMETER, "Modo de entrenamiento desconocido")
	setup.ai_actor_ids = live.ai_intent_actor_ids.duplicate()
	return start_match(setup)


func start_development_mode(mode: Setup.Mode) -> Error:
	var setup: Setup = _mode_setup(mode)
	if setup == null:
		return _development_error(ERR_INVALID_PARAMETER, "Modo de desarrollo no válido")
	return start_match(setup)


func start_training_exercise(exercise: Setup.TrainingExercise) -> Error:
	if not is_instance_valid(_simulation):
		return _development_error(ERR_UNCONFIGURED, "No hay una autoridad inicializada")
	if exercise < Setup.TrainingExercise.FREE_PLAY or exercise > Setup.TrainingExercise.ACCUMULATED_FREE_KICK:
		return _development_error(ERR_INVALID_PARAMETER, "Ejercicio de entrenamiento no válido")
	var live: Snapshot = _simulation.get_snapshot()
	var setup: Setup = Setup.for_exercise(live.mode, exercise)
	if setup == null:
		return _development_error(ERR_INVALID_PARAMETER, "No se pudo construir el ejercicio solicitado")
	setup.ai_actor_ids = live.ai_intent_actor_ids.duplicate()
	return start_match(setup)


func set_aim_guide_enabled(enabled: bool) -> void:
	_aim_guide_enabled = enabled
	if is_instance_valid(_development_menu):
		_development_menu.set_aim_guide_enabled(enabled)
	if not enabled:
		_clear_launch_preview()


func is_aim_guide_enabled() -> bool:
	return _aim_guide_enabled


func get_aim_controls_hint() -> String:
	return MatchInput.FINE_AIM_HINT


func get_render_ball_position() -> Vector3:
	return ($BallView/BallMesh as Node3D).global_position


func set_ai_actor_ids(ids: Array[int]) -> Error:
	if not is_instance_valid(_simulation):
		return _development_error(ERR_UNCONFIGURED, "No hay una autoridad inicializada")
	var result: Error = _simulation.set_ai_actor_ids(ids)
	if result != OK:
		return _development_error(result, "No se pudo cambiar la IA: " + _simulation.last_error)
	_state = _simulation.get_snapshot()
	if _setup == null or _setup.mode != _state.mode or _setup.training_exercise != _state.training_exercise:
		_setup = Setup.for_exercise(_state.mode, _state.training_exercise)
	_setup.ai_actor_ids = _state.ai_intent_actor_ids.duplicate()
	_development_menu.show_error("")
	_update_hud()
	if _development_menu.is_open():
		_present_development()
	return OK


## Cerrar desarrollo vuelve a pausa/resultado; nunca reanuda por sí solo.
func open_development_menu() -> Error:
	if _state == null or _exiting:
		return _development_error(ERR_UNAVAILABLE, "No hay un entrenamiento disponible")
	if _development_menu.is_open():
		return OK
	var live: Snapshot = _simulation.get_snapshot()
	if live.phase in [Snapshot.Phase.PLAYING, Snapshot.Phase.GOAL_PAUSE, Snapshot.Phase.RESTART_PAUSE]:
		var result: Error = _simulation.set_paused(true)
		if result != OK:
			return _development_error(result, "No se pudo pausar para abrir desarrollo: " + _simulation.last_error)
	_state = _simulation.get_snapshot()
	_before = _state
	_input_adapter.set_enabled(false)
	_input_adapter.clear()
	_camera.release_input_projection()
	_clear_launch_preview()
	_update_hud()
	var result: Error = _present_development()
	if result != OK:
		return result
	_hud.set_development_open(true)
	_development_menu.show_error("")
	_development_menu.set_open(true)
	return OK


func close_development_menu() -> void:
	if not _development_menu.is_open():
		return
	_development_menu.set_open(false)
	_hud.set_development_open(false)
	_input_adapter.clear()
	_state = _simulation.get_snapshot()
	_before = _state
	_sync_input(_state)
	_update_hud()


func set_match_paused(value: bool) -> Error:
	if not is_instance_valid(_simulation):
		return _development_error(ERR_UNCONFIGURED, "No hay una autoridad inicializada")
	if not value and _development_menu.is_open():
		return _development_error(ERR_BUSY, "Cierra Desarrollo antes de continuar")
	var result: Error = _simulation.set_paused(value)
	if result != OK:
		return _development_error(result, "No se pudo cambiar la pausa: " + _simulation.last_error)
	_input_adapter.clear()
	_camera.release_input_projection()
	_clear_launch_preview()
	_feedback_cooldown = 0.0
	_state = _simulation.get_snapshot()
	_before = _state
	_sync_input(_state)
	_update_hud()
	return OK


func get_snapshot() -> Snapshot:
	return _simulation.get_snapshot()


func get_simulation() -> Simulation:
	return _simulation


func _mode_setup(mode: Setup.Mode) -> Setup:
	match mode:
		Setup.Mode.MICRO_1V1:
			return Setup.new()
		Setup.Mode.PREVIEW_5V5:
			return Setup.preview_5v5()
	return null


func _reconcile_athletes(force: bool = false) -> void:
	var changed: bool = force or _athletes.size() != _state.actors.size()
	for actor: Snapshot.ActorSnapshot in _state.actors:
		changed = changed or not _athletes.has(actor.actor_id)
	if not changed:
		return
	for athlete: Athlete in _athletes.values():
		athlete.free()
	_athletes.clear()
	for actor: Snapshot.ActorSnapshot in _state.actors:
		var home: bool = actor.team_id == Snapshot.Team.HOME
		var keeper: bool = actor.role == Snapshot.Role.KEEPER
		var color: Color = _hud.home_color if home else _hud.away_color
		var number: int = 20 + actor.actor_id
		if keeper:
			color = Color("#a65839") if home else Color("#607b69")
			number = 1 if home else 13
		elif actor.actor_id == Simulation.HUMAN_ID:
			number = _hud.home_dorsal
		elif actor.actor_id == Simulation.RIVAL_ID:
			number = _hud.away_dorsal
		var athlete: Athlete = Athlete.new()
		athlete.name = "Athlete%d" % actor.actor_id
		$Athletes.add_child(athlete)
		athlete.configure(actor.actor_id, color, number)
		athlete.reset_pose()
		_athletes[actor.actor_id] = athlete
	_before = _state
	_snap_camera = true


func quit_match() -> void:
	if _exiting:
		return
	_exiting = true
	_input_adapter.set_enabled(false)
	_clear_launch_preview()
	exit_requested.emit()
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if _state != null and not _exiting and event.is_action_pressed("development"):
		_request_development()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _state == null or _exiting:
		return
	_before = _state
	_state = _simulation.get_snapshot()
	_reconcile_athletes()
	_camera.sync_context(_state)
	_sync_input(_state)
	_drain_events()
	_update_hud()


func _sample_human_input(delta: float) -> void:
	# Muestrear antes del core resuelve la acción en este mismo tick: no queda
	# una patada humana pendiente entre fotogramas que sobreviva a una pausa.
	var live: Snapshot = _simulation.get_snapshot()
	_camera.sync_context(live)
	if not _can_collect_input(live):
		_input_adapter.set_enabled(false)
		_clear_launch_preview()
		return
	var command: Command = _input_adapter.sample(live, _camera, delta)
	_refresh_launch_preview()
	if live.human_control_context == Rules.ControlContext.DISABLED:
		return
	if not _preflight_launch(command, live):
		return
	_sampled_action = command.action
	var result: Error = _simulation.submit_human_command(command)
	command_submitted.emit(command.copy(), result)
	if result in [ERR_BUSY, ERR_UNAVAILABLE] and command.action != Command.Action.NONE:
		# Un contacto puede desaparecer entre muestreo y aceptación. No perder movimiento.
		command.sequence = _simulation.get_snapshot().actor(command.actor_id).last_command_sequence + 1
		_clear_command_action(command)
		result = _simulation.submit_human_command(command)
		command_submitted.emit(command.copy(), result)
	if result != OK:
		_report_error(result, "Entrada no aceptada: " + _simulation.last_error)


func _process(delta: float) -> void:
	if _state == null:
		return
	_feedback_cooldown = maxf(0.0, _feedback_cooldown - delta)
	var weight: float = Engine.get_physics_interpolation_fraction()
	if _state.phase in [Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED, Snapshot.Phase.READY]:
		weight = 1.0
	_present(delta, weight)


func _present(delta: float, weight: float) -> void:
	var animate: bool = _state.phase in [Snapshot.Phase.PLAYING, Snapshot.Phase.RESTART_PAUSE]
	var ball_at: Vector3 = _before.ball_position.lerp(_state.ball_position, weight)
	_ball_view.present(ball_at, _before.ball_rotation.slerp(_state.ball_rotation, weight))
	_camera.follow(_state, ball_at, delta, _snap_camera)
	if _launch_preview != null and _input_adapter.get_preview_command() != null \
			and _aim_guide_enabled and _can_collect_input(_state):
		_aim_guide.present(_launch_preview, get_render_ball_position(), true)
	else:
		_aim_guide.clear()
	_snap_camera = false
	for actor: Snapshot.ActorSnapshot in _state.actors:
		var id: int = actor.actor_id
		_athletes[id].sync_context(_before, _state)
		_athletes[id].present(_before.actor(id), actor, weight,
			delta if animate else 0.0, _state.ball_owner_id == id,
			_input_adapter.shot_charge if id == _state.selected_actor_id else 0.0)


func _update_hud() -> void:
	var mode_result: Error = _hud.set_mode(_state.mode)
	if mode_result != OK:
		_report_error(mode_result, "El HUD no pudo presentar el modo confirmado")
	var selected_result: Error = _hud.set_selected_actor(_state.actor(_state.selected_actor_id))
	if selected_result != OK:
		_report_error(selected_result, "El HUD no pudo presentar al jugador controlado")
	_hud.update_score(_state.score.x, _state.score.y)
	_hud.update_clock(_state.seconds_remaining)
	_hud.set_has_possession(_state.ball_owner_id == _state.selected_actor_id)
	_hud.set_shot_charge(_input_adapter.shot_charge)
	_hud.set_paused(_state.phase == Snapshot.Phase.PAUSED)
	var restart_result: Error = _hud.present_restart(_state)
	if restart_result != OK:
		_report_error(restart_result, "El HUD no pudo presentar la reanudación confirmada")
	if _state.phase == Snapshot.Phase.FINISHED and not _finished_presented:
		_finished_presented = true
		_hud.show_result(_state.score.x, _state.score.y, "Sesión completada · Sin progresión ni XP")


func _queue_event(event: Event) -> void:
	_events.append(event)


func _drain_events() -> void:
	for event: Event in _events:
		_camera.react(event)
		if _athletes.has(event.actor_id):
			_athletes[event.actor_id].react(event, _state.actor(event.actor_id))
		match event.kind:
			Event.Kind.GOAL:
				_input_adapter.clear()
				_clear_launch_preview()
				_hud.show_event("GOL · " + ("Local" if event.team_id == 0 else "Visita"), 2.0)
			Event.Kind.PASS:
				if _before != null and event.actor_id == _before.selected_actor_id:
					_input_adapter.clear_for_focus_change()
					_clear_launch_preview()
				if event.team_id == Snapshot.Team.HOME:
					var receiver: Snapshot.ActorSnapshot = _state.actor(event.target_actor_id)
					if receiver != null and receiver.role == Snapshot.Role.KEEPER:
						_hud.show_event("PASE · Al portero", 1.1)
					elif _state.actor(event.actor_id).role == Snapshot.Role.KEEPER:
						_hud.show_event("PASE · Portero local", 1.1)
					else:
						_hud.show_event("PASE · Compañero" if event.target_actor_id >= 0 else "PASE · Dirigido", 1.1)
			Event.Kind.FOCUS_CHANGED:
				_input_adapter.clear_for_focus_change()
				_clear_launch_preview()
				if event.reason == &"off_ball_switch":
					_hud.show_event("CONTROL · " + ("Portero" if _state.actor(event.target_actor_id).role
						== Snapshot.Role.KEEPER else "Jugador") + " %d" % event.target_actor_id, 1.1)
			Event.Kind.SHOT:
				if event.actor_id == _state.selected_actor_id:
					_input_adapter.clear_for_focus_change()
					_clear_launch_preview()
				_hud.show_event("TIRO · " + ("Local" if event.team_id == 0 else "Visita"), 1.0)
			Event.Kind.SAVE:
				_hud.show_event("PARADA · " + ("Local" if event.team_id == 0 else "Visita"), 1.4)
			Event.Kind.TACKLE:
				if event.actor_id == _state.selected_actor_id:
					_show_feedback("ROBO · Contacto" if event.success else "ROBO · Sin contacto")
			Event.Kind.RESTART:
				_input_adapter.clear()
				_clear_launch_preview()
				_before = _state
				_snap_camera = true
				_camera.reset_context()
				for athlete: Athlete in _athletes.values():
					athlete.reset_pose()
				if event.reason == &"training_start":
					if _state.mode == Setup.Mode.MICRO_1V1:
						_hud.show_event("J / A: pase o cambio · L / X: regate · F1: ejercicios", 4.0)
					else:
						_hud.show_event("5v5 experimental · J / A: pase o cambio · F1: Desarrollo", 4.0)
				else:
					_hud.show_event("REPOSICIÓN · " + ("Local" if event.team_id == 0 else "Visita"), 1.2)
			Event.Kind.RESTART_CHANGED:
				_input_adapter.clear_for_focus_change()
				_clear_launch_preview()
				if event.reason in [&"awarded", &"placement", &"spot_changed"]:
					_before = _state
			Event.Kind.DRIBBLE:
				if event.actor_id == _state.selected_actor_id:
					_input_adapter.clear_for_focus_change()
					_clear_launch_preview()
					_hud.show_event("REGATE · " + ("Enganche" if event.gesture_kind == Rules.GestureKind.CUT
						else "Cambio de ritmo"), 1.1)
			Event.Kind.FOUL:
				_input_adapter.clear_for_focus_change()
				_clear_launch_preview()
				_hud.show_event("FALTA · " + ("Local" if event.team_id == Snapshot.Team.HOME else "Visita"), 1.5)
			Event.Kind.END:
				_input_adapter.clear()
				_clear_launch_preview()
	_events.clear()


func _present_development() -> Error:
	_development_menu.set_aim_guide_enabled(_aim_guide_enabled)
	var result: Error = _development_menu.present(_state)
	if result != OK:
		return _development_error(result, "El menú no pudo presentar el estado confirmado")
	return OK


func _request_development() -> void:
	_input_adapter.set_enabled(false)
	open_development_menu.call_deferred()


func _request_close_development() -> void:
	close_development_menu.call_deferred()


func _request_development_mode(mode: Setup.Mode) -> void:
	_input_adapter.set_enabled(false)
	start_development_mode.call_deferred(mode)


func _request_ai_actor_ids(ids: Array[int]) -> void:
	set_ai_actor_ids.call_deferred(ids.duplicate())


func _request_aim_guide(enabled: bool) -> void:
	set_aim_guide_enabled.call_deferred(enabled)


func _request_training_exercise(exercise: Setup.TrainingExercise) -> void:
	_input_adapter.set_enabled(false)
	start_training_exercise.call_deferred(exercise)


func _can_collect_input(state: Snapshot) -> bool:
	return not _exiting and not _development_menu.is_open() \
		and state.phase in [Snapshot.Phase.PLAYING, Snapshot.Phase.RESTART_PAUSE]


func _sync_input(state: Snapshot) -> void:
	_input_adapter.set_enabled(_can_collect_input(state))
	_input_adapter.sync_context(state)
	if not _input_adapter.enabled:
		_camera.release_input_projection()
		_clear_launch_preview()


func _refresh_launch_preview() -> void:
	var request: Command = _input_adapter.get_preview_command()
	if not _aim_guide_enabled or request == null:
		_clear_launch_preview()
		return
	_launch_preview = _simulation.query_human_launch(request)


func _preflight_launch(command: Command, live: Snapshot) -> bool:
	if command.action not in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		return true
	var solution: Launch.Solution = _simulation.query_human_launch(command)
	if solution.error == OK and solution.executable:
		return true
	var backwards_direct_shot: bool = solution.error == ERR_INVALID_PARAMETER and solution.reason == &"launch_rule" \
		and live.human_control_context == Rules.ControlContext.RESTART_AIM \
		and live.restart.kind in [Rules.RestartKind.PENALTY_6M, Rules.RestartKind.ACCUMULATED_FREE_KICK] \
		and command.action == Command.Action.SHOOT \
		and solution.direction.dot(live.actor(command.actor_id).attack_direction) <= 0.0001
	if solution.error in [OK, ERR_BUSY, ERR_UNAVAILABLE] or backwards_direct_shot:
		_show_feedback("Apunta hacia la portería rival" if backwards_direct_shot
			else ("Espera al siguiente apoyo" if solution.error == ERR_BUSY else "Espera a un contacto válido"))
		_input_adapter.clear_for_focus_change()
		_clear_launch_preview()
		_clear_command_action(command)
		return true
	_report_error(solution.error, "Consulta de lanzamiento no válida: " + String(solution.reason))
	return false


func _clear_command_action(command: Command) -> void:
	command.action = Command.Action.NONE
	command.target_actor_id = -1
	command.shot_charge = 0.0
	command.shot_lift = 0.0
	command.restart_spot_choice = Rules.SpotChoice.DEFAULT


func _clear_launch_preview() -> void:
	_launch_preview = null
	if is_instance_valid(_aim_guide):
		_aim_guide.clear()


func _request_pause(paused: bool) -> void:
	_input_adapter.set_enabled(false)
	_clear_launch_preview()
	set_match_paused.call_deferred(paused)


func _request_restart() -> void:
	_input_adapter.set_enabled(false)
	restart_match.call_deferred()


func _request_exit() -> void:
	_input_adapter.set_enabled(false)
	quit_match.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and _state != null:
		_on_focus_lost()


func _on_focus_lost() -> void:
	if _state != null and _state.phase in [
			Snapshot.Phase.PLAYING, Snapshot.Phase.GOAL_PAUSE, Snapshot.Phase.RESTART_PAUSE]:
		_request_pause(true)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == _input_adapter.active_joypad and _state != null:
		if _state.phase in [Snapshot.Phase.PLAYING, Snapshot.Phase.GOAL_PAUSE, Snapshot.Phase.RESTART_PAUSE]:
			_request_pause(true)


func _on_command_rejected(actor_id: int, code: Error, _message: String) -> void:
	var live: Snapshot = _simulation.get_snapshot()
	if actor_id != live.selected_actor_id:
		return
	if live.phase == Snapshot.Phase.RESTART_PAUSE and live.restart.kind != Rules.RestartKind.NONE \
			and code in [ERR_BUSY, ERR_UNAVAILABLE, ERR_UNAUTHORIZED]:
		_show_feedback("Espera al siguiente apoyo" if code == ERR_BUSY else "Acción no disponible en este saque")
		return
	if code in [ERR_BUSY, ERR_UNAVAILABLE]:
		if _sampled_action == Command.Action.SWITCH_TEAMMATE and code == ERR_UNAVAILABLE:
			_show_feedback("No hay compañero en esa dirección")
		else:
			_show_feedback("Recupera el apoyo" if code == ERR_BUSY else "Acércate al balón para golpear")


func _show_feedback(message: String) -> void:
	var live: Snapshot = _simulation.get_snapshot()
	if live.phase in [Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED] or _development_menu.is_open():
		return
	if live.phase == Snapshot.Phase.RESTART_PAUSE and live.restart.kind != Rules.RestartKind.NONE:
		if _feedback_cooldown <= 0.0 or _last_restart_feedback != message \
				or _last_feedback_restart_id != live.restart.id or _last_feedback_actor_id != live.selected_actor_id:
			var result: Error = _hud.show_restart_feedback(message, live.restart.id, live.selected_actor_id)
			if result != OK:
				_report_error(result, "El HUD no pudo presentar el aviso del saque")
				return
			_last_restart_feedback = message
			_last_feedback_restart_id = live.restart.id
			_last_feedback_actor_id = live.selected_actor_id
			_feedback_cooldown = 0.65
		return
	if _feedback_cooldown <= 0.0:
		_hud.show_event(message, 1.0)
		_feedback_cooldown = 0.65


func _development_error(code: Error, message: String) -> Error:
	if is_instance_valid(_development_menu):
		_development_menu.show_error(message)
	if is_instance_valid(_hud) and (not is_instance_valid(_development_menu) or not _development_menu.is_open()):
		_hud.show_event("ERROR · " + message, 4.0)
	integration_error.emit(code, message)
	push_warning(message)
	return code


func _report_error(code: Error, message: String) -> void:
	integration_error.emit(code, message)
	push_error(message)
