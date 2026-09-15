extends "res://tests/test_match_integration.gd"
## Fixture nativo compartido; este recorrido comprueba el default 5v5 ANTES de reset.

const DevelopmentMenu = preload("res://match/presentation/development/match_dev_menu.gd")
const ALL_AI: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
const ALL_INTENT: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

var _development: DevelopmentMenu
var _mode_requests: Array[int] = []
var _error_codes: Array[int] = []
var _expected_errors: int = 0
var _mouse_events: int = 0
var _negative_case: String = ""
var _negative_code: Error = OK
var _remaining_errors: int = 0
var _remaining_refusals: int = 0
var _expected_refusals: Array[Dictionary] = []
var _unexpected_errors: Array[String] = []
var _unexpected_refusals: Array[Dictionary] = []
var _keeper_distribution_evidence: Array[Dictionary] = []
var _restart_menu_evidence: Array[Dictionary] = []


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var bindings: Dictionary = _bindings()
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	_check("default apunta al main de producción", path == "res://match/match.tscn")
	var scene: PackedScene = load(path) as PackedScene
	_host = scene.instantiate() as MatchHost if scene != null else null
	_check("default instancia el host real", _host != null)
	if _host == null:
		_report()
		quit(1)
		return
	_development = _host.get_node("MatchDevMenu") as DevelopmentMenu
	var simulation: Simulation = _host.get_node("Simulation") as Simulation
	simulation.event_raised.connect(func(event: Event) -> void: _events.append(event))
	simulation.command_rejected.connect(_record_refusal)
	_host.command_submitted.connect(func(command: Command, _result: Error) -> void: _commands.append(command))
	_host.integration_error.connect(_record_error)
	_host.exit_requested.connect(_on_exit_requested)
	_development.mode_requested.connect(func(mode: Setup.Mode) -> void: _mode_requests.append(mode))
	root.add_child(_host)
	current_scene = _host
	await _frames(6)
	_assert_composition(Setup.Mode.PREVIEW_5V5, 10, "default antes de cualquier drill")
	_check("default PLAYING avanza reloj/ticks con las nueve IA", _state().phase == Snapshot.Phase.PLAYING
		and _state().tick > 0 and _state().seconds_remaining < 120.0 and _state().ai_actor_ids == ALL_AI
		and _state().selected_actor_id == 0 and _state().ai_intent_actor_ids == ALL_INTENT)
	_check("arranque normal no ejecuta smoke ni bootstrap", not _host.has_node("MatchSmoke")
		and not _development.is_open() and not _control("PauseOverlay").visible)
	_check("HUD preview no promete pase fijo al portero", not _label("PassHint").text.contains("al portero"))
	_assert_frame("default")
	if _failed():
		_report()
		quit(1)
		return
	var origin: Vector3 = _state().actor(0).position
	_key(KEY_D, true)
	await _frames(8)
	_check("default diez recibe D física antes de un reset", _state().actor(0).position.x > origin.x + 0.05
		and _commands[-1].move.x > 0.99 and _state().actor(0).last_command_sequence > 0)
	_key(KEY_D, false)
	await _frames(15)
	_check("liberación nativa frena al humano del default", _planar_speed() < 0.02)
	if _failed():
		_report()
		quit(1)
		return
	await _test_mode_controls()
	await _test_ai_controls()
	await _test_preview_passes()
	await _test_menu_input_barriers()
	await _test_goal_and_out_menus()
	await _test_development_rejections()
	await _test_finished_menu()
	await _test_preview_edges()
	_check("menú/host no reescriben InputMap", bindings == _bindings())
	_check("errores limitados a las negativas previstas", _errors.size() == _expected_errors and _unexpected_errors.is_empty())
	_check("sin rechazos fuera de su negativa explícita", _unexpected_refusals.is_empty()
		and _refusals.size() == _expected_refusals.size())
	_check("recorrido usa teclado, Xbox y ratón nativos", int(_native_events["key"]) > 40
		and int(_native_events["joy_button"]) > 20 and int(_native_events["joy_motion"]) > 10 and _mouse_events >= 4)
	if _failed():
		_report()
		quit(1)
		return
	await _test_exit()


func _test_mode_controls() -> void:
	await _open_from_hud()
	var before: Array = _full_fingerprint(_state())
	var requests: int = _mode_requests.size()
	await _choose_mode(Setup.Mode.MICRO_1V1)
	_check("seleccionar modo no aplica ni cambia física", _full_fingerprint(_state()) == before
		and _mode_requests.size() == requests and _development.is_open())
	await _apply_mode()
	_assert_composition(Setup.Mode.MICRO_1V1, 4, "10 a 4 mediante teclado")
	_check("aplicar micro cierra modal y restaura sus tres IA", not _development.is_open()
		and not _control("PauseOverlay").visible and _state().ai_actor_ids == [1, 2, 3])
	await _open_from_hud(true)
	_check("micro permite configurar intención latente del campo controlado",
		not (_dev_control("TeammatesToggle") as BaseButton).disabled
		and (_dev_control("TeammatesToggle") as BaseButton).button_pressed
		and _state().ai_intent_actor_ids == [0, 1, 2, 3])
	await _choose_mode(Setup.Mode.PREVIEW_5V5, true)
	await _apply_mode(true)
	_assert_composition(Setup.Mode.PREVIEW_5V5, 10, "4 a 10 mediante Xbox")
	_check("modo aplica un solo preset por pulsación", _mode_requests.size() == requests + 2
		and _state().ai_actor_ids == ALL_AI and _state().score == Vector2i.ZERO)
	var human_view: Node = _host.get_node("Athletes/Athlete0")
	var old_view_id: int = human_view.get_instance_id()
	await _open_from_hud()
	await _apply_mode()
	_check("aplicar el mismo modo reinicia vistas y reloj explícitamente",
		_host.get_node("Athletes/Athlete0").get_instance_id() != old_view_id and not is_instance_valid(human_view)
		and _state().tick < 8 and _state().seconds_remaining > 119.8 and _state().ai_actor_ids == ALL_AI)
	_check("ningún A modal genera pase o tiro al aplicar", _count(Event.Kind.PASS, 0) == 0
		and _count(Event.Kind.SHOT, 0) == 0 and _count(Event.Kind.TACKLE, 0) == 0)


func _test_ai_controls() -> void:
	var setup: Setup = _safe_preview()
	setup.ai_actor_ids = ALL_INTENT.duplicate()
	await _begin("IA por grupos del menú", setup)
	await _open_from_hud()
	var frozen: Array = _progress_fingerprint(_state())
	await _activate_dev("RivalToggle")
	_check("rival desactiva también portero visitante", _state().ai_actor_ids == [2, 4, 6, 8]
		and not (_dev_control("RivalToggle") as BaseButton).button_pressed)
	await _activate_dev("TeammatesToggle", true)
	_check("compañeros afecta solo campos HOME", _state().ai_actor_ids == [2])
	await _click_dev("KeeperToggle")
	_check("los tres grupos permiten apagar toda IA", _state().ai_actor_ids.is_empty()
		and _host.get_node("Athletes").get_child_count() == 10)
	_check("toggles no alteran balón, marcador, reloj ni cuerpos", _progress_fingerprint(_state()) == frozen)
	await _activate_dev("RivalToggle", true)
	await _activate_dev("TeammatesToggle")
	await _click_dev("KeeperToggle")
	_check("grupos completos restauran las nueve IA", _state().ai_actor_ids == ALL_AI)
	var exact: Array = _full_fingerprint(_state())
	_check("IA idempotente aceptada por host", _host.set_ai_actor_ids(ALL_INTENT.duplicate()) == OK)
	_check("IA idempotente conserva decisiones/poses/tiempos", _full_fingerprint(_state()) == exact)
	var supplied: Array[int] = [4, 2, 1]
	_check("mutador host acepta y ordena subconjunto", _host.set_ai_actor_ids(supplied) == OK)
	supplied.clear()
	_check("mutación posterior del array no toca autoridad", _state().ai_actor_ids == [1, 2, 4])
	_check("UI refleja grupos parciales confirmados", _dev_label("RivalStatus").text.contains("Parcial")
		and _dev_label("TeammatesStatus").text.contains("Parcial"))
	await _activate_dev("RivalToggle")
	var expected: Array[int] = [1, 2, 3, 4, 5, 7, 9]
	_check("activar grupo parcial lo completa sin tocar otro", _state().ai_actor_ids == expected
		and _dev_label("TeammatesStatus").text.contains("Parcial"))
	_tap(KEY_ESCAPE)
	await _frames(2)
	_check("cerrar desarrollo vuelve a pausa, no a PLAYING", not _development.is_open()
		and _state().phase == Snapshot.Phase.PAUSED and _control("PauseOverlay").visible)
	_tap(KEY_ESCAPE)
	await _frames(12)
	_check("continuar reanuda generadores habilitados", _state().phase == Snapshot.Phase.PLAYING
		and _state().actor(4).last_command_sequence > 0)
	frozen = _progress_fingerprint(_state())
	var empty_ids: Array[int] = []
	_check("mutador admite apagar IA durante PLAYING", _host.set_ai_actor_ids(empty_ids) == OK)
	_check("mutación en juego no reinicia progreso", _progress_fingerprint(_state()) == frozen)
	var actions: int = _ai_actions()
	await _frames(20)
	var stopped: bool = true
	for actor: Snapshot.ActorSnapshot in _state().actors:
		if not actor.human_controlled:
			stopped = stopped and Vector2(actor.velocity.x, actor.velocity.z).length() < 0.05
	_check("desactivar IA frena físicamente, no retira atletas", stopped and _state().actors.size() == 10
		and _ai_actions() == actions and _state().phase == Snapshot.Phase.PLAYING)
	_check("restart conserva modo e intención apagada", _host.restart_match() == OK
		and _state().mode == Setup.Mode.PREVIEW_5V5 and _state().ai_actor_ids.is_empty()
		and _state().ai_intent_actor_ids.is_empty())
	await _frames(4)
	await _open_from_hud()
	await _apply_mode()
	_check("aplicar preset restaura IA por defecto, no los toggles", _state().ai_actor_ids == ALL_AI)


func _test_preview_passes() -> void:
	var setup: Setup = _pass_preview()
	await _begin("pase neutro preview", setup)
	_tap(KEY_J)
	await _frames(2)
	var pass_event: Event = _last(Event.Kind.PASS, 0)
	var command: Command = _last_command(Command.Action.PASS)
	_check("preview deja receptor -1 y aim neutro al core", command != null and command.target_actor_id == -1
		and command.aim.is_zero_approx())
	_check("core elige compañero nuevo, no portero fijo", pass_event != null and pass_event.target_actor_id == 4
		and pass_event.velocity.x > 6.0)
	_check("foco pasa al receptor en la patada, no en la recepción", _state().selected_actor_id == 4
		and _state().ball_owner_id == -1)
	for frame: int in 100:
		if _state().ball_owner_id == 4:
			break
		await _frames(1)
	_check("compañero 4 recibe físicamente el pase", _state().ball_owner_id == 4)
	setup.actor_positions[4] = Vector3(0, 0, -7)
	setup.actor_forwards[4] = Vector2(-1, 1).normalized()
	await _begin("pase dirigido Xbox preview", setup)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	_button(JOY_BUTTON_A, true)
	_button(JOY_BUTTON_A, false)
	await _frames(2)
	_release_all()
	pass_event = _last(Event.Kind.PASS, 0)
	command = _last_command(Command.Action.PASS)
	_check("stick dirige pase preview sin fijar receptor", command != null and command.target_actor_id == -1
		and command.aim.x > 0.6 and command.aim.y < -0.6)
	_check("pase Xbox llega al compañero dentro del cono", pass_event != null and pass_event.target_actor_id == 4
		and pass_event.velocity.z < -5.0)
	setup = _pass_preview()
	setup.actor_positions[4] = Vector3(-8, 0, -7)
	await _begin("pase libre sin candidato frontal", setup)
	_key(KEY_D, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_D, false)
	pass_event = _last(Event.Kind.PASS, 0)
	_check("sin candidato no gira mágicamente hacia un compañero", pass_event != null
		and pass_event.target_actor_id == -1 and pass_event.velocity.x > 6.0
		and _state().selected_actor_id == 0)
	setup = Setup.preview_5v5()
	setup.ai_actor_ids = [2]
	setup.actor_forwards[8] = Vector2.LEFT
	setup.ball_position = Vector3(-17.95, 0.12, 0)
	await _keeper_distribution_case("portero con humano tapado por el apoyo cercano", setup, 4)
	setup.actor_positions[0] = Vector3(-12, 0, -8)
	await _keeper_distribution_case("portero prioriza al humano con línea segura", setup, 0)


func _keeper_distribution_case(label: String, setup: Setup, expected_target: int) -> void:
	await _begin(label, setup)
	var before: Snapshot = _state()
	var human_lane: float = _legacy_lane_clearance(before, 2, 0, before.ball_position)
	var safe_margin: float = Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS + 1.0
	var distribution: Dictionary = {"case": label, "before": _legacy_fixture_state(before),
		"expected_target": expected_target, "human_lane_clearance": human_lane}
	_check(label + ": posesión del portero y foco humano reales", before.ball_owner_id == 2 and before.selected_actor_id == 0)
	if expected_target == 0:
		_check(label + ": humano despejado aunque 8 está más cerca", human_lane > safe_margin
			and before.ball_position.distance_to(before.actor(8).position) < before.ball_position.distance_to(before.actor(0).position))
	else:
		var keeper_lane: float = _legacy_lane_clearance(before, 2, expected_target, before.ball_position)
		var outlet_lane: float = _legacy_lane_clearance(before, expected_target, 0, before.actor(expected_target).position)
		distribution["keeper_to_outlet_clearance"] = keeper_lane
		distribution["outlet_to_human_clearance"] = outlet_lane
		_check(label + ": 8 tapa al humano y 4 abre una salida segura útil", human_lane < Tuning.ACTOR_RADIUS + Tuning.BALL_RADIUS
			and keeper_lane > safe_margin and outlet_lane > safe_margin
			and before.ball_position.distance_to(before.actor(8).position) <
				before.ball_position.distance_to(before.actor(expected_target).position))
	var capture: Callable = func(event: Event) -> void:
		if event.actor_id == 2:
			var actor_command: Command = _host.get_simulation().get_node("Actor2").get("command") as Command
			distribution["at_kick"] = _legacy_fixture_state(_state())
			distribution["command_after_execution"] = {"actor_id": actor_command.actor_id, "sequence": actor_command.sequence,
				"stored_action": actor_command.action, "target_actor_id": actor_command.target_actor_id,
				"aim": [actor_command.aim.x, actor_command.aim.y]}
			distribution["event"] = {"tick": event.tick, "actor_id": event.actor_id,
				"target_actor_id": event.target_actor_id, "velocity": _legacy_vector(event.velocity)}
	_host.get_simulation().pass_made.connect(capture)
	for frame: int in 100:
		if _count(Event.Kind.PASS, 2) > 0:
			break
		await _frames(1)
	_host.get_simulation().pass_made.disconnect(capture)
	_keeper_distribution_evidence.append(distribution)
	var pass_event: Event = _last(Event.Kind.PASS, 2)
	_check(label + ": distribución confirma receptor exacto según política 0.4",
		pass_event != null and pass_event.target_actor_id == expected_target and pass_event.velocity.length() > 6.0
		and _state().actor(expected_target).team_id == Snapshot.Team.HOME
		and _state().actor(expected_target).role == Snapshot.Role.FIELD)
	_check(label + ": pase IA no roba foco ni encadena tiros", _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == [2] and _count(Event.Kind.FOCUS_CHANGED) == 0
		and _count(Event.Kind.PASS, 2) == 1 and _count(Event.Kind.SHOT) == 0)


func _test_menu_input_barriers() -> void:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	await _begin("F1 durante carga y sprint", setup)
	_key(KEY_D, true)
	_key(KEY_SHIFT, true)
	_key(KEY_K, true)
	await _frames(5)
	_check("fixture mantiene carga y sprint reales antes de menú", _adapter().shot_charge > 0.0
		and _commands[-1].sprint and _planar_speed() > 0.2)
	_tap(KEY_F1)
	await _frames(3)
	_check("F1 abre un único modal y pausa autoridad", _development.is_open() and not _control("PauseOverlay").visible
		and _state().phase == Snapshot.Phase.PAUSED and _state().resume_phase == Snapshot.Phase.PLAYING and not paused)
	_check("abrir menú cancela carga y sampling", is_zero_approx(_adapter().shot_charge) and not _adapter().enabled)
	var frozen: Array = _full_fingerprint(_state())
	var sampled: int = _commands.size()
	await _frames(20)
	_check("menú congela estado completo y no envía órdenes", frozen == _full_fingerprint(_state()) and sampled == _commands.size())
	_button(JOY_BUTTON_B, true)
	_button(JOY_BUTTON_B, false)
	await _frames(2)
	_check("B vuelve a pausa sin reanudación o robo", _state().phase == Snapshot.Phase.PAUSED
		and not _development.is_open() and _control("PauseOverlay").visible and _count(Event.Kind.TACKLE, 0) == 0)
	_tap(KEY_ESCAPE)
	await _frames(16)
	_check("reanudar exige neutral y descarta sprint/carga retenidos", _state().phase == Snapshot.Phase.PLAYING
		and not _commands[-1].sprint and _commands[-1].move.is_zero_approx()
		and _planar_speed() < 0.02 and _count(Event.Kind.SHOT, 0) == 0)
	_release_all()
	await _frames(3)
	_key(KEY_D, true)
	_key(KEY_SHIFT, true)
	await _frames(20)
	_check("nueva pulsación recupera sprint después de menú", _commands[-1].sprint and _planar_speed() > 7.0)
	_release_all()
	await _begin("foco y desconexión con desarrollo abierto", setup)
	_button(JOY_BUTTON_B, true)
	await _frames(8)
	_tap(KEY_F1)
	await _frames(3)
	root.focus_exited.emit()
	Input.joy_connection_changed.emit(0, false)
	await _frames(3)
	_check("foco/desconexión no reanudan ni duplican modal", _development.is_open()
		and _state().phase == Snapshot.Phase.PAUSED and not _control("PauseOverlay").visible and _adapter().shot_charge == 0.0)
	_tap(KEY_ESCAPE)
	await _frames(2)
	Input.joy_connection_changed.emit(0, true)
	await _frames(2)
	_check("reconectar mantiene pausa", _state().phase == Snapshot.Phase.PAUSED)
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _frames(4)
	_button(JOY_BUTTON_B, false)
	await _frames(4)
	_check("Start y liberación posterior no disparan carga anterior", _state().phase == Snapshot.Phase.PLAYING
		and _count(Event.Kind.SHOT, 0) == 0 and _count(Event.Kind.TACKLE, 0) == 0)


func _test_goal_and_out_menus() -> void:
	var goal: Setup = Setup.preview_5v5()
	goal.ai_actor_ids = []
	goal.ball_position = Vector3(19.2, 0.12, 0)
	goal.ball_velocity = Vector3(8, 0, 0)
	await _begin("desarrollo durante vuelo de gol", goal)
	for frame: int in 20:
		if _state().phase == Snapshot.Phase.GOAL_PAUSE:
			break
		await _frames(1)
	_check("gol preview se adjudica por autoridad", _state().phase == Snapshot.Phase.GOAL_PAUSE
		and _state().score == Vector2i(1, 0) and _label("Score").text == "1 – 0")
	_tap(KEY_F1)
	await _frames(2)
	_check("desarrollo conserva fase de retorno GOAL_PAUSE", _development.is_open()
		and _state().phase == Snapshot.Phase.PAUSED and _state().resume_phase == Snapshot.Phase.GOAL_PAUSE)
	var frozen: Array = _progress_fingerprint(_state())
	await _activate_dev("KeeperToggle")
	await _frames(12)
	_check("IA en gol no cambia vuelo congelado, reloj o score", _progress_fingerprint(_state()) == frozen
		and _state().ai_actor_ids == [2])
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _frames(2)
	_check("Start de desarrollo vuelve a pausa de gol", not _development.is_open()
		and _state().phase == Snapshot.Phase.PAUSED and _state().resume_phase == Snapshot.Phase.GOAL_PAUSE)
	var ball: Vector3 = _state().ball_position
	var clock: float = _state().seconds_remaining
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check("continuar restaura vuelo GOAL_PAUSE, no solo UI", _state().phase == Snapshot.Phase.GOAL_PAUSE
		and _state().ball_position.distance_to(ball) > 0.03 and is_equal_approx(_state().seconds_remaining, clock))
	await _frames(90)
	_check("saque posterior conserva diez, IA y gol único", _state().mode == Setup.Mode.PREVIEW_5V5
		and _state().actors.size() == 10 and _state().ai_actor_ids == [2]
		and _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	_check("reinicio después del gol conserva modo/IA sin score antiguo", _host.restart_match() == OK
		and _state().mode == Setup.Mode.PREVIEW_5V5 and _state().ai_actor_ids == [2] and _state().score == Vector2i.ZERO)
	var outside: Setup = _safe_preview()
	outside.ball_position = Vector3(0, 0.12, 9.8)
	outside.ball_velocity = Vector3(0, 0, 6)
	var awards: Array[Snapshot] = []
	var pause_on_award: Callable = func(event: Event) -> void:
		if event.kind == Event.Kind.RESTART_CHANGED and event.restart.stage == IntegrationRules.RestartStage.STOPPED:
			awards.append(_host.get_simulation().get_snapshot())
			# Defer the native key, never pause from inside authority event delivery.
			_tap.call_deferred(KEY_F1)
	_host.get_simulation().event_raised.connect(pause_on_award)
	await _begin("desarrollo durante reposición", outside)
	for frame: int in 15:
		if _state().phase == Snapshot.Phase.PAUSED and _development.is_open():
			break
		await _frames(1)
	_host.get_simulation().event_raised.disconnect(pause_on_award)
	_check("preview entra en reposición por fuera real", awards.size() == 1)
	if awards.size() != 1:
		return
	var awarded: Snapshot = awards[0]
	_check("fixture pausa STOPPED antes de su colocación localizada",
		awarded.phase == Snapshot.Phase.RESTART_PAUSE and awarded.restart.stage == IntegrationRules.RestartStage.STOPPED
		and awarded.ball_position.distance_to(awarded.restart.spot) > 0.1)
	_record_restart_menu("awarded before F1", awarded)
	await _frames(2)
	_check("menú conserva retorno a RESTART_PAUSE", _development.is_open()
		and _state().resume_phase == Snapshot.Phase.RESTART_PAUSE
		and _state().restart.stage == IntegrationRules.RestartStage.STOPPED and _state().tick == awarded.tick)
	_record_restart_menu("F1 paused")
	var stopped: Array = _full_fingerprint(_state())
	var stopped_progress: Array = _progress_fingerprint(_state())
	var stopped_commands: int = _commands.size()
	await _frames(12)
	_check("pausa STOPPED congela íntegramente física, reloj y preparación",
		_full_fingerprint(_state()) == stopped and _commands.size() == stopped_commands)
	_record_restart_menu("STOPPED remains frozen")
	await _activate_dev("RivalToggle", true)
	_check("cambiar IA no adelanta colocación ni consume reloj pausado",
		_progress_fingerprint(_state()) == stopped_progress and _state().ai_intent_actor_ids == [1, 3, 5, 7, 9])
	_record_restart_menu("AI toggled while paused")
	_tap(KEY_ESCAPE)
	await _frames(2)
	ball = _state().ball_position
	_check("cerrar Desarrollo deja STOPPED aún en pausa y conserva su balón",
		_state().phase == Snapshot.Phase.PAUSED and _state().tick == awarded.tick
		and _state().restart.stage == IntegrationRules.RestartStage.STOPPED and ball.is_equal_approx(awarded.ball_position))
	_record_restart_menu("menu closed, still paused")
	_tap(KEY_ESCAPE)
	await _frames(3)
	_record_restart_menu("resumed for three frames")
	var placed: Snapshot = _state()
	_check("continuar STOPPED permite solo la colocación autoritativa pendiente",
		placed.phase == Snapshot.Phase.RESTART_PAUSE and placed.restart.stage == IntegrationRules.RestartStage.PLACEMENT
		and placed.restart.id == awarded.restart.id and placed.tick > awarded.tick
		and placed.ball_position.is_equal_approx(placed.restart.spot) and placed.ball_velocity.is_zero_approx()
		and placed.seconds_remaining == awarded.seconds_remaining and placed.score == awarded.score
		and placed.restart.placement_end_tick == awarded.restart.placement_end_tick)
	_tap(KEY_F1)
	await _frames(2)
	var paused_placement: Snapshot = _state()
	var frozen_placement: Array = _full_fingerprint(paused_placement)
	var placement_commands: int = _commands.size()
	_check("segundo F1 pausa PLACEMENT, no inventa otro saque",
		paused_placement.phase == Snapshot.Phase.PAUSED and paused_placement.restart.stage == IntegrationRules.RestartStage.PLACEMENT
		and paused_placement.restart.id == placed.restart.id)
	await _frames(12)
	_check("pausa durante PLACEMENT conserva física y todos los contadores",
		_full_fingerprint(_state()) == frozen_placement and _commands.size() == placement_commands)
	_record_restart_menu("PLACEMENT remains frozen")
	_tap(KEY_ESCAPE)
	await _frames(2)
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check("reanudar PLACEMENT conserva ahora el balón ya colocado y su plazo",
		_state().phase == Snapshot.Phase.RESTART_PAUSE and _state().restart.stage == IntegrationRules.RestartStage.PLACEMENT
		and _state().tick > paused_placement.tick and _state().ball_position.is_equal_approx(paused_placement.ball_position)
		and _state().ball_velocity.is_zero_approx() and _state().seconds_remaining == paused_placement.seconds_remaining
		and _state().restart.placement_end_tick == paused_placement.restart.placement_end_tick)
	_record_restart_menu("PLACEMENT resumed without reposition")
	var stopped_restart_id: int = _state().restart.id
	for frame: int in 90:
		if _state().restart.stage == IntegrationRules.RestartStage.READY or _state().phase == Snapshot.Phase.PLAYING:
			break
		await _frames(1)
	_check("banda reglada conserva preview e intención IA tras menú",
		_state().actors.size() == 10 and _state().ai_intent_actor_ids == [1, 3, 5, 7, 9]
		and _state().restart.id == stopped_restart_id and _state().restart.kind == IntegrationRules.RestartKind.KICK_IN
		and _state().restart.stage in [IntegrationRules.RestartStage.READY, IntegrationRules.RestartStage.IN_PLAY]
		and _state().restart.ready_tick == placed.restart.placement_end_tick
		and _state().restart.ready_tick - placed.restart.stage_started_tick >= 60)
	_check("reanudación procede del saque, nunca del antiguo reset central",
		absf(_state().restart.spot.z) > 9.5 and _state().score == Vector2i.ZERO
		and _state().ai_actor_ids == [1, 3, 5, 7, 9])


func _test_development_rejections() -> void:
	await _begin("rechazos atómicos de desarrollo", _safe_preview())
	await _open_from_hud()
	var exact: Array = _full_fingerprint(_state())
	var views: Array[int] = _view_ids()
	var errors_before: int = _errors.size()
	_begin_negative("modo inválido de UI", ERR_INVALID_PARAMETER, false)
	_development.mode_requested.emit(99 as Setup.Mode)
	await _frames(2)
	_end_negative()
	_check("modo inválido de UI devuelve error visible", _errors.size() == errors_before + 1
		and _error_codes[-1] == ERR_INVALID_PARAMETER and _dev_label("ErrorText").visible
		and not _dev_label("ErrorText").text.is_empty())
	_check("rechazo de modo conserva partido, vistas y panel", _full_fingerprint(_state()) == exact
		and _view_ids() == views and _development.is_open())
	var invalid_ids: Array[int] = [-1]
	errors_before = _errors.size()
	_begin_negative("ID negativo en IA desde UI", ERR_INVALID_PARAMETER, true)
	_development.ai_actor_ids_requested.emit(invalid_ids)
	await _frames(2)
	_end_negative()
	_check("UI no puede introducir ID negativo en IA", _errors.size() == errors_before + 1
		and _error_codes[-1] == ERR_INVALID_PARAMETER and _full_fingerprint(_state()) == exact)
	for candidate: Array in [[2, 2], [20]]:
		var ids: Array[int] = []
		ids.assign(candidate)
		_begin_negative("IDs inválidos " + str(ids), ERR_INVALID_PARAMETER, true)
		_expect_error("IDs inválidos", _host.set_ai_actor_ids(ids), ERR_INVALID_PARAMETER)
		_check("lista rechazada no muta el snapshot", _full_fingerprint(_state()) == exact)
	var invalid: Setup = Setup.preview_5v5()
	invalid.actor_positions.erase(9)
	_begin_negative("setup incompleto", ERR_INVALID_PARAMETER, true)
	_expect_error("setup incompleto", _host.start_match(invalid), ERR_INVALID_PARAMETER)
	_check("start fallido no retira vistas ni cierra menú", _full_fingerprint(_state()) == exact
		and _view_ids() == views and _development.is_open())
	_begin_negative("reanudar con desarrollo abierto", ERR_BUSY, false)
	_expect_error("reanudar con desarrollo abierto", _host.set_match_paused(false), ERR_BUSY)
	_check("resume rechazado mantiene un único modal", _development.is_open() and not _control("PauseOverlay").visible
		and _state().phase == Snapshot.Phase.PAUSED)
	var selected: Array[int] = [2, 4]
	_check("operación válida posterior confirma y limpia rechazo", _host.set_ai_actor_ids(selected) == OK
		and _dev_label("ErrorText").text.is_empty())
	_tap(KEY_ESCAPE)
	await _frames(2)
	_check("restart no hereda ninguna lista inválida", _host.restart_match() == OK
		and _state().ai_actor_ids == selected and _state().mode == Setup.Mode.PREVIEW_5V5)
	await _begin("reentrada real desde evento de pase", _pass_preview())
	var codes: Array[int] = []
	var unchanged: Array[bool] = []
	_host.get_simulation().pass_made.connect(func(_event: Event) -> void:
		var before: Array = _full_fingerprint(_state())
		var before_views: Array[int] = _view_ids()
		_begin_negative("reentrada IA durante pase", ERR_BUSY, true)
		codes.append(_host.set_ai_actor_ids(selected))
		_end_negative()
		_begin_negative("reentrada de modo durante pase", ERR_BUSY, true)
		codes.append(_host.start_development_mode(Setup.Mode.MICRO_1V1))
		_end_negative()
		unchanged.append(before == _full_fingerprint(_state()) and before_views == _view_ids()),
		CONNECT_ONE_SHOT)
	_tap(KEY_J)
	await _frames(3)
	_check("mutaciones dentro de eventos propagan ERR_BUSY", codes == [ERR_BUSY, ERR_BUSY])
	_check("reentrada no cambia modo ni consume evento legítimo", unchanged == [true]
		and _state().mode == Setup.Mode.PREVIEW_5V5 and _count(Event.Kind.PASS, 0) == 1
		and _label("EventText").text.begins_with("PASE"))


func _test_finished_menu() -> void:
	await _begin("desarrollo desde resultado", _safe_preview(), 0.25)
	await _frames(25)
	_check("resultado preview llega desde el reloj real", _state().phase == Snapshot.Phase.FINISHED
		and _count(Event.Kind.END) == 1 and _control("PauseOverlay").visible)
	await _open_from_hud(true)
	var exact: Array = _full_fingerprint(_state())
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _frames(3)
	_check("cerrar desarrollo retorna a resultado sin continuar", _full_fingerprint(_state()) == exact
		and not _development.is_open() and _control("PauseOverlay").visible and not _control("ResumeButton").visible)
	await _open_from_hud()
	_host.get_simulation().tuning.training_seconds = 120.0
	await _click_dev("ApplyModeButton")
	_check("aplicar modo desde resultado crea sesión nueva", _state().phase == Snapshot.Phase.PLAYING
		and _state().mode == Setup.Mode.PREVIEW_5V5 and _state().seconds_remaining > 119.8
		and _state().score == Vector2i.ZERO and _state().ai_actor_ids == ALL_AI
		and not _development.is_open() and not _control("PauseOverlay").visible)


func _test_preview_edges() -> void:
	for corner: Vector3 in [Vector3(-19.3, 0, 9.3), Vector3(19.3, 0, 9.3), Vector3(19.3, 0, -9.3)]:
		var setup: Setup = _safe_preview()
		setup.actor_positions[4] = corner
		setup.ball_position = Vector3(corner.x - signf(corner.x) * 0.9, 0.12, corner.z)
		await _begin("encuadre preview de esquina " + str(corner), setup)
		_assert_frame("esquina " + str(corner))
		_check("encuadre no deforma pista ni balón", is_equal_approx(Tuning.COURT_LENGTH, 40.0)
			and is_equal_approx(Tuning.COURT_WIDTH, 20.0) and is_equal_approx(Tuning.BALL_RADIUS, 0.105)
			and _host.get_node("Athletes/Athlete4").get("scale").is_equal_approx(Vector3.ONE))


func _test_exit() -> void:
	await _begin("salida preview con modal nativo", _safe_preview())
	_tap(KEY_ESCAPE)
	await _frames(2)
	_navigate_hud("QuitButton")
	_check("foco de mando llega a Salir real", root.gui_get_focus_owner() == _control("QuitButton"))
	_expect_exit = true
	_button(JOY_BUTTON_A, true)
	for frame: int in 15:
		await _frames(1)
	_check("Salir finaliza realmente el proceso", false)
	_report()
	quit(1)


func _assert_composition(mode: Setup.Mode, count: int, label: String) -> void:
	var state: Snapshot = _state()
	_check(label + ": modo/recuento autoritativos", state.mode == mode and state.actors.size() == count)
	var bodies: Array[Node] = _host.get_simulation().find_children("*", "CharacterBody3D", true, false)
	_check(label + ": igual número de cuerpos y vistas", bodies.size() == count and _host.get_node("Athletes").get_child_count() == count)
	var rids: Array[RID] = []
	var ids: Array[int] = []
	var valid: bool = true
	var geometry_present: bool = true
	var fields: Array[int] = [0, 0]
	var keepers: Array[int] = [0, 0]
	var humans: Array[int] = []
	var ball: RigidBody3D = _host.get_simulation().get_node("Ball") as RigidBody3D
	var space: RID = PhysicsServer3D.body_get_space(ball.get_rid())
	for actor: Snapshot.ActorSnapshot in state.actors:
		ids.append(actor.actor_id)
		if actor.human_controlled:
			humans.append(actor.actor_id)
		if actor.role == Snapshot.Role.KEEPER:
			keepers[actor.team_id] += 1
		else:
			fields[actor.team_id] += 1
		var body: CharacterBody3D = null
		for candidate: Node in bodies:
			if candidate.get("actor_id") == actor.actor_id:
				body = candidate as CharacterBody3D
				break
		valid = valid and body != null and actor.team_id == actor.actor_id % 2
		if body != null:
			valid = valid and not rids.has(body.get_rid()) and PhysicsServer3D.body_get_space(body.get_rid()) == space
			rids.append(body.get_rid())
		var view: Node3D = _host.get_node_or_null("Athletes/Athlete%d" % actor.actor_id) as Node3D
		valid = valid and view != null and view.get("actor_id") == actor.actor_id
		geometry_present = geometry_present and view != null and not view.find_children("*", "MeshInstance3D", true, false).is_empty()
	ids.sort()
	_check(label + ": identidades físicas independientes en mundo privado", valid and rids.size() == count
		and space != _host.get_world_3d().space and ids == range(count))
	_check(label + ": un seleccionado HOME y roles correctos por equipo",
		humans == [state.selected_actor_id] and state.actor(state.selected_actor_id).team_id == Snapshot.Team.HOME
		and keepers == [1, 1]
		and fields == ([1, 1] if count == 4 else [4, 4]))
	_check(label + ": cada atleta tiene geometría real sin colliders duplicados", geometry_present
		and _host.get_node("Athletes").find_children("*", "CollisionObject3D", true, false).is_empty())


func _assert_frame(label: String) -> void:
	var points: PackedVector3Array = [_state().ball_position]
	for actor: Snapshot.ActorSnapshot in _state().actors:
		points.append(actor.position)
		points.append(actor.position + Vector3.UP * Tuning.ACTOR_HEIGHT)
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			points.append(Vector3(end * 21.5, 2.08, side * 1.61))
	var visible: bool = true
	for point: Vector3 in points:
		var normalized: Vector2 = _camera().unproject_position(point) / root.get_visible_rect().size
		visible = visible and not _camera().is_position_behind(point) and normalized.x > 0.01 \
			and normalized.x < 0.99 and normalized.y > 0.19 and normalized.y < 0.81
	_check(label + ": diez siluetas, balón y ambas porterías dentro del encuadre", visible)


func _open_from_hud(xbox: bool = false) -> void:
	if _state().phase not in [Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED]:
		_tap(KEY_ESCAPE)
		await _frames(2)
	_navigate_hud("DevelopmentButton")
	if xbox:
		_button(JOY_BUTTON_A, true)
		_button(JOY_BUTTON_A, false)
	else:
		_tap(KEY_ENTER)
	await _frames(3)
	_check("Desarrollo del HUD abre panel real exclusivo", _development.is_open() and not _control("PauseOverlay").visible
		and _state().phase in [Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED])


func _choose_mode(mode: Setup.Mode, xbox: bool = false) -> void:
	await _activate_dev("ModeSelector", xbox)
	_check("selector abre desplegable nativo", _dev_control("ModeDropdown").visible)
	await _activate_dev("MicroChoice" if mode == Setup.Mode.MICRO_1V1 else "PreviewChoice", xbox)
	_check("selección queda como borrador visible", not _dev_control("ModeDropdown").visible
		and (_dev_control("ModeSelector") as Button).text.contains("1v1" if mode == Setup.Mode.MICRO_1V1 else "5v5"))


func _apply_mode(xbox: bool = false) -> void:
	await _activate_dev("ApplyModeButton", xbox)


func _activate_dev(node_name: String, xbox: bool = false) -> void:
	var target: Control = _dev_control(node_name)
	for attempt: int in 12:
		if root.gui_get_focus_owner() == target:
			break
		if xbox:
			_button(JOY_BUTTON_DPAD_DOWN, true)
			_button(JOY_BUTTON_DPAD_DOWN, false)
		else:
			_tap(KEY_TAB)
	_check("foco nativo Desarrollo: " + node_name, root.gui_get_focus_owner() == target)
	if xbox:
		_button(JOY_BUTTON_A, true)
		_button(JOY_BUTTON_A, false)
	else:
		_tap(KEY_ENTER)
	await _frames(3)


func _click_dev(node_name: String) -> void:
	var at: Vector2 = _dev_control(node_name).get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.device = 0
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		_mouse_events += 1
	await _frames(3)


func _safe_preview() -> Setup:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	setup.ball_position = Vector3(0, 1.4, 4)
	setup.ball_velocity = Vector3(2, 0, 1)
	return setup


func _pass_preview() -> Setup:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	setup.actor_positions[0] = Vector3(-4, 0, -3)
	setup.actor_positions[1] = Vector3(6, 0, 5)
	setup.actor_positions[4] = Vector3(2, 0, -3)
	setup.actor_forwards[4] = Vector2.LEFT
	setup.ball_position = Vector3(-3.45, 0.12, -3)
	return setup


func _adapter() -> Adapter:
	return _host.get_node("MatchInput") as Adapter


func _dev_control(node_name: String) -> Control:
	return _development.get_node("%" + node_name) as Control


func _dev_label(node_name: String) -> Label:
	return _development.get_node("%" + node_name) as Label


func _last_command(action: Command.Action) -> Command:
	for index: int in range(_commands.size() - 1, -1, -1):
		if _commands[index].action == action:
			return _commands[index]
	return null


func _ai_actions() -> int:
	return _events.filter(func(event: Event) -> bool:
		return event.actor_id > 0 and event.kind in [Event.Kind.SHOT, Event.Kind.PASS, Event.Kind.TACKLE]).size()


func _full_fingerprint(state: Snapshot) -> Array:
	return _fingerprint(state) + [state.mode, state.ai_actor_ids.duplicate(), state.ai_intent_actor_ids.duplicate()]


func _record_restart_menu(label: String, captured: Snapshot = null) -> void:
	_restart_menu_evidence.append({"case": label, "state": _legacy_fixture_state(captured if captured != null else _state())})


func _legacy_fixture_state(state: Snapshot) -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append({"id": actor.actor_id, "team": actor.team_id, "role": actor.role,
			"position": _legacy_vector(actor.position), "velocity": _legacy_vector(actor.velocity),
			"spawn": _legacy_vector(actor.spawn_position), "sequence": actor.last_command_sequence})
	return {"tick": state.tick, "phase": state.phase, "resume_phase": state.resume_phase,
		"score": [state.score.x, state.score.y], "seconds_remaining": state.seconds_remaining,
		"selected_actor_id": state.selected_actor_id, "ball_owner_id": state.ball_owner_id,
		"ball_position": _legacy_vector(state.ball_position), "ball_velocity": _legacy_vector(state.ball_velocity),
		"ai_intent_actor_ids": state.ai_intent_actor_ids, "ai_actor_ids": state.ai_actor_ids, "actors": actors,
		"restart": {"id": state.restart.id, "kind": state.restart.kind, "stage": state.restart.stage,
			"spot": _legacy_vector(state.restart.spot), "launch_contact_id": state.restart.launch_contact_id,
			"stage_started_tick": state.restart.stage_started_tick, "placement_end_tick": state.restart.placement_end_tick,
			"ready_tick": state.restart.ready_tick, "deadline_tick": state.restart.deadline_tick}}


func _legacy_vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _legacy_lane_clearance(state: Snapshot, passer: int, receiver: int, origin: Vector3) -> float:
	var start: Vector2 = Vector2(origin.x, origin.z)
	var target: Vector2 = Vector2(state.actor(receiver).position.x, state.actor(receiver).position.z)
	var clearance: float = INF
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.actor_id in [passer, receiver]:
			continue
		var point: Vector2 = Vector2(actor.position.x, actor.position.z)
		clearance = minf(clearance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, target)))
	return clearance


func _progress_fingerprint(state: Snapshot) -> Array:
	var result: Array = [state.mode, state.phase, state.resume_phase, state.tick, state.score,
		state.seconds_remaining, state.phase_seconds_remaining, state.ball_position, state.ball_velocity,
		state.ball_rotation, state.ball_angular_velocity, state.ball_owner_id, state.last_touch_actor_id,
		state.selected_actor_id, state.accumulated_fouls, state.period_state, state.extended_restart_id,
		state.extended_kick_event_id, state.training_exercise, _restart_fingerprint(state)]
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.position, actor.velocity, actor.action_cooldown, actor.last_command_sequence])
	return result


func _view_ids() -> Array[int]:
	var ids: Array[int] = []
	for node: Node in _host.get_node("Athletes").get_children():
		ids.append(node.get_instance_id())
	return ids


func _expect_error(label: String, result: Error, expected: Error) -> void:
	_check("negativa esperada " + label, result == expected and not _error_codes.is_empty()
		and _error_codes[-1] == expected and not _dev_label("ErrorText").text.is_empty())
	_end_negative()


func _begin_negative(label: String, code: Error, core_refusal: bool) -> void:
	_negative_case = label
	_negative_code = code
	_remaining_errors = 1
	_remaining_refusals = 1 if core_refusal else 0


func _end_negative() -> void:
	_expected_errors += 1
	_check("diagnóstico exacto de negativa: " + _negative_case, _remaining_errors == 0 and _remaining_refusals == 0)
	_negative_case = ""
	_negative_code = OK


func _record_error(code: Error, message: String) -> void:
	_error_codes.append(code)
	_errors.append(message)
	if not _negative_case.is_empty() and code == _negative_code and _remaining_errors > 0:
		_remaining_errors -= 1
	else:
		_unexpected_errors.append(message)


func _record_refusal(id: int, code: Error, message: String) -> void:
	var item: Dictionary = {"id": id, "code": code, "message": message}
	_refusals.append(item)
	if not _negative_case.is_empty() and id == -1 and code == _negative_code and _remaining_refusals > 0:
		_remaining_refusals -= 1
		var expected: Dictionary = item.duplicate()
		expected["case"] = _negative_case
		_expected_refusals.append(expected)
	else:
		_unexpected_refusals.append(item)


func _diagnostics_ok() -> bool:
	return _negative_case.is_empty() and _errors.size() == _expected_errors and _unexpected_errors.is_empty() \
		and _unexpected_refusals.is_empty() and _refusals.size() == _expected_refusals.size()


func _report() -> void:
	if _report_printed:
		return
	_report_printed = true
	var failures: Array[String] = []
	for item: Dictionary in _checks:
		if not bool(item["passed"]):
			failures.append(String(item["name"]))
	print("FUTSAL_MATCH_PREVIEW_INTEGRATION_TESTS ", JSON.stringify({
		"ok": failures.is_empty(), "passed": _checks.size() - failures.size(), "total": _checks.size(),
		"failures": failures, "expected_development_errors": _expected_errors,
		"error_codes": _error_codes, "command_refusals": _refusals,
		"expected_command_refusals": _expected_refusals, "unexpected_integration_errors": _unexpected_errors,
		"unexpected_command_refusals": _unexpected_refusals,
		"keeper_distribution": _keeper_distribution_evidence, "restart_menu": _restart_menu_evidence,
		"native_events": _native_events, "mouse_events": _mouse_events,
		"engine": Engine.get_version_info()["string"], "headless": DisplayServer.get_name() == "headless",
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
	}))
