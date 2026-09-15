extends "res://tests/test_match_camera.gd"
## Integración del catálogo, saques, guía y regates con el main y eventos nativos.

var _command_negative: String = ""
var _command_negative_actor: int = -1
var _command_negative_code: Error = OK
var _command_negative_remaining: int = 0
var _feedback: Array[String] = []
var _exercise_requests: Array[int] = []
var _helper_check_context: String = ""


func _run() -> void:
	if not await _load_actual_main():
		_report()
		quit(1)
		return
	_adapter().feedback_requested.connect(func(message: String) -> void: _feedback.append(message))
	_development.exercise_requested.connect(func(exercise: Setup.TrainingExercise) -> void:
		_exercise_requests.append(exercise))
	_test_abi_and_geometry()
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		await _test_catalog_ui(mode)
		await _test_keeper_throw(mode)
		await _test_precision_and_penalty(mode)
		await _test_accumulated_choice(mode)
		await _test_live_guide(mode)
		for gesture: int in 3:
			await _test_native_dribble(mode, gesture)
	await _test_invalid_exercise()
	await _test_terminal_controls()
	_suite_complete = true
	_check("G25 diagnósticos limitados a negativas declaradas", _diagnostics_ok())
	if _failed():
		_report()
		quit(1)
		return
	await _test_exit()


func _test_abi_and_geometry() -> void:
	_check("G01 ABI de fases y acciones 0.3 preservada y ampliada",
		Command.Action.SWITCH_TEAMMATE == 4 and Command.Action.DRIBBLE == 5
		and Command.Action.KEEPER_THROW == 6 and Command.Action.CHOOSE_RESTART_SPOT == 7
		and Snapshot.Phase.RESTART_PAUSE == 3 and Snapshot.Phase.FINISHED == 5
		and Event.Kind.FOCUS_CHANGED == 9 and Event.Kind.RESTART_CHANGED == 10
		and Event.Kind.DRIBBLE == 11 and Event.Kind.FOUL == 12)
	_check("G01 schema3 añade L físico y X real sin ratones genéricos",
		ProjectSettings.get_setting("futsal/preparation/input_schema_version") == 3
		and InputMap.action_get_events("dribble").size() == 2
		and InputMap.action_get_events("dribble").any(func(event: InputEvent) -> bool:
			return event is InputEventKey and event.physical_keycode == KEY_L and event.device == -1)
		and InputMap.action_get_events("dribble").any(func(event: InputEvent) -> bool:
			return event is InputEventJoypadButton and event.button_index == JOY_BUTTON_X and event.device == -1))
	_check("G32 no se altera escala para encuadrar las nuevas jugadas",
		Tuning.COURT_LENGTH == 40.0 and Tuning.COURT_WIDTH == 20.0 and Tuning.ACTOR_HEIGHT == 1.75
		and Tuning.BALL_RADIUS == 0.105 and Tuning.GOAL_WIDTH == 3.0 and Tuning.GOAL_HEIGHT == 2.0)
	_check("G01 guía empieza desactivada visualmente sin un lanzamiento humano",
		not _arrow().visible and _adapter().get_preview_command() == null)
	_check("G18 descripción coincide con el afinado de teclado/mando elegido",
		_host.get_aim_controls_hint() == Adapter.FINE_AIM_HINT
		and Adapter.FINE_AIM_HINT.contains("Ctrl + (A/D") and Adapter.FINE_AIM_HINT.contains("LT + stick")
		and is_equal_approx(rad_to_deg(Adapter.FINE_AIM_RADIANS_PER_SECOND), 30.0))
	_case_done("abi")


func _test_catalog_ui(mode: Setup.Mode) -> void:
	_release_all()
	await _frames(2)
	_check("G30 m%d modo real para catálogo" % mode, _host.start_development_mode(mode) == OK)
	var intent: Array[int] = [0, 2]
	if mode == Setup.Mode.PREVIEW_5V5:
		intent = [0, 4, 8]
	_check("G30 m%d configura intención parcial y latente" % mode, _host.set_ai_actor_ids(intent) == OK)
	_host.set_aim_guide_enabled(false)
	for exercise_id: int in 12:
		var exercise: Setup.TrainingExercise = exercise_id as Setup.TrainingExercise
		var label: String = "G30 m%d ejercicio%d vía UI" % [mode, exercise]
		_tap(KEY_F1)
		await _frames(2)
		_check(label + ": F1 abre un único modal", _development.is_open() and not _control("PauseOverlay").visible)
		var before: Array = _full_fingerprint(_state())
		var confirmed_exercise: Setup.TrainingExercise = _state().training_exercise
		var previous_requests: int = _exercise_requests.size()
		var selector: OptionButton = _dev_control("ExerciseSelector") as OptionButton
		for attempt: int in 15:
			if root.gui_get_focus_owner() == selector:
				break
			_tap(KEY_TAB)
		_check(label + ": selector recibe foco mediante Tab real", root.gui_get_focus_owner() == selector
			and selector.item_count == 12)
		if not await _choose_exercise_popup(selector, exercise, mode == Setup.Mode.PREVIEW_5V5, label):
			return
		_check(label + ": selección sigue siendo borrador", selector.get_selected_id() == exercise
			and _exercise_requests.size() == previous_requests and _full_fingerprint(_state()) == before
			and _state().mode == mode and _state().ai_intent_actor_ids == intent
			and _state().training_exercise == confirmed_exercise
			and not _host.is_aim_guide_enabled() and _development.is_open())
		if mode == Setup.Mode.MICRO_1V1:
			await _with_check_context(label + "; aplicar por teclado", _activate_dev.bind("ApplyExerciseButton"))
		else:
			await _with_check_context(label + "; aplicar por ratón", _click_dev.bind("ApplyExerciseButton"))
		var state: Snapshot = _state()
		_check(label + ": confirmación explícita inicia el preset real",
			_exercise_requests.size() == previous_requests + 1 and _exercise_requests[-1] == exercise
			and state.training_exercise == exercise and state.mode == mode and not _development.is_open()
			and not _control("PauseOverlay").visible and state.score == Vector2i.ZERO)
		_check(label + ": conserva intención exacta y preferencia de guía",
			state.ai_intent_actor_ids == intent and not _host.is_aim_guide_enabled()
			and state.ai_actor_ids == _effective(intent, state.selected_actor_id))
		_check(label + ": STOPPED/PLACEMENT reales o juego libre, según catálogo",
			state.phase == (Snapshot.Phase.PLAYING if exercise in [Setup.TrainingExercise.FREE_PLAY,
				Setup.TrainingExercise.DRIBBLE_CUT, Setup.TrainingExercise.DRIBBLE_PACE_CHANGE]
				else Snapshot.Phase.RESTART_PAUSE))
		_check(label + ": reiniciar conserva catálogo e intención",
			_host.restart_match() == OK and _state().training_exercise == exercise
			and _state().ai_intent_actor_ids == intent and not _host.is_aim_guide_enabled())
		await _frames(3)
		_case_done("catalog/%d/%d" % [mode, exercise])
	_check("G30 m%d modo canónico restaura FREE_PLAY y preferencias IA por defecto" % mode,
		_host.start_development_mode(mode) == OK and _state().training_exercise == Setup.TrainingExercise.FREE_PLAY
		and _state().selected_actor_id == 0 and _state().ai_intent_actor_ids == ([0, 1, 2, 3] if mode == 0 else ALL_INTENT))


func _choose_exercise_popup(selector: OptionButton, exercise: Setup.TrainingExercise, controller: bool, label: String) -> bool:
	if root.gui_get_focus_owner() != selector:
		_check(label + ": no se activa otro control si falta foco del selector", false)
		return false
	var draft_before: int = selector.get_selected_id()
	var requests_before: int = _exercise_requests.size()
	var popup: PopupMenu = selector.get_popup()
	if controller:
		_button(JOY_BUTTON_A, true)
		_button(JOY_BUTTON_A, false)
	else:
		_tap(KEY_ENTER)
	await _frames(1)
	_check(label + ": aceptar abre el popup nativo", popup.visible)
	if not popup.visible:
		return false
	for step: int in selector.item_count:
		var focused: int = popup.get_focused_item()
		if focused >= 0 and popup.get_item_id(focused) == exercise:
			break
		if controller:
			_button(JOY_BUTTON_DPAD_DOWN, true)
			_button(JOY_BUTTON_DPAD_DOWN, false)
		else:
			_tap(KEY_DOWN)
		await _frames(1)
	var focused: int = popup.get_focused_item()
	var reached: bool = focused >= 0 and popup.get_item_id(focused) == exercise
	_check(label + ": navegación vertical real cambia el resaltado, no aplica ni confirma",
		reached and selector.get_selected_id() == draft_before and _exercise_requests.size() == requests_before)
	if not reached:
		return false
	if controller:
		_button(JOY_BUTTON_A, true)
		_button(JOY_BUTTON_A, false)
	else:
		_tap(KEY_ENTER)
	await _frames(1)
	var selected: bool = not popup.visible and selector.get_selected_id() == exercise
	_check(label + ": aceptar opción devuelve foco al selector y espera Iniciar",
		selected and root.gui_get_focus_owner() == selector and _exercise_requests.size() == requests_before)
	return selected and root.gui_get_focus_owner() == selector and _exercise_requests.size() == requests_before


func _test_keeper_throw(mode: Setup.Mode) -> void:
	var label: String = "G07/G11/G17 m%d saque de meta" % mode
	if not await _catalog(mode, Setup.TrainingExercise.GOAL_CLEARANCE, label) or not await _ready_restart(label):
		return
	var before: Snapshot = _state()
	_assert_ready_feedback_surface(label)
	var keeper: int = before.selected_actor_id
	_check(label + ": portero humano, balón en manos y sin locomoción",
		keeper == 2 and before.actor(keeper).ball_in_hands and before.ball_owner_id == keeper
		and before.ball_position.y > 0.5 and not before.selected_can_move
		and before.human_allowed_actions.has(Command.Action.KEEPER_THROW)
		and not before.human_allowed_actions.has(Command.Action.PASS)
		and not before.human_allowed_actions.has(Command.Action.SHOOT))
	_assert_keeper_render_anchor(label, keeper)
	_assert_guide(label)
	_key(KEY_K, true)
	await _frames(4)
	_key(KEY_K, false)
	await _frames(2)
	_check(label + ": K incorrecto no dispara, cambia foco ni consume timer",
		_count(Event.Kind.SHOT) == 0 and _count(Event.Kind.TACKLE) == 0 and _state().selected_actor_id == keeper
		and _adapter().shot_charge == 0.0 and _state().restart.deadline_tick == before.restart.deadline_tick
		and _state().tick > before.tick)
	_assert_restart_feedback_visible(label + ": K rechazado", "J / A: lanzamiento del portero")
	_assert_ready_feedback_surface(label + ": tras rechazo")
	_button(JOY_BUTTON_A, true)
	await _frames(2)
	var event: Event = _last(Event.Kind.PASS, keeper)
	_check(label + ": A produce PASS/KEEPER_THROW físico con foco al receptor",
		event != null and event.launch_kind == Rules.LaunchKind.KEEPER_THROW
		and event.target_actor_id >= 0 and _state().selected_actor_id == event.target_actor_id
		and _state().ball_owner_id == -1 and _state().ball_position.distance_to(before.ball_position) > 0.02
		and _state().phase == Snapshot.Phase.PLAYING and not _arrow().visible)
	await _assert_accepted_launch(label, event)
	await _frames(30)
	_check(label + ": A retenido no repite tras cambiar foco",
		_count(Event.Kind.PASS) == 1 and _count(Event.Kind.FOCUS_CHANGED) == 2)
	_button(JOY_BUTTON_A, false)
	_check(label + ": una sola bandera humana y HUD confirmado",
		_state().actors.filter(func(actor: Snapshot.ActorSnapshot) -> bool: return actor.human_controlled).size() == 1
		and _label("SelectedActor").text.contains("ID %d" % _state().selected_actor_id))
	_case_done("keeper/%d" % mode)


func _test_precision_and_penalty(mode: Setup.Mode) -> void:
	var label: String = "G12/G21/G23/G29 m%d penalti y precisión" % mode
	if not await _catalog(mode, Setup.TrainingExercise.PENALTY_6M, label) or not await _ready_restart(label):
		return
	var before: Snapshot = _state()
	_assert_ready_feedback_surface(label)
	_check(label + ": penalti solo admite tiro y no usa cuatro segundos",
		before.restart.kind == Rules.RestartKind.PENALTY_6M and before.restart.deadline_tick == -1
		and before.human_allowed_actions.has(Command.Action.SHOOT)
		and not before.human_allowed_actions.has(Command.Action.PASS))
	_key(KEY_K, true)
	_key(KEY_L, true)
	_key(KEY_J, true)
	await _frames(4)
	_release_all()
	await _frames(2)
	_check(label + ": prioridad J > L > K no convierte el pase prohibido en tiro",
		_count(Event.Kind.PASS) == 0 and _count(Event.Kind.SHOT) == 0 and _count(Event.Kind.DRIBBLE) == 0
		and _adapter().shot_charge == 0.0 and not _feedback.is_empty())
	_assert_restart_feedback_visible(label + ": pase rechazado por entrada real", _feedback.back() if not _feedback.is_empty() else "")
	_key(KEY_CTRL, true)
	_key(KEY_RIGHT, true)
	await _frames(7)
	var aim: Command = _adapter().get_preview_command()
	var closest_ray: float = 0.0
	if aim != null:
		for ray: int in 8:
			closest_ray = maxf(closest_ray, aim.aim.dot(Vector2.RIGHT.rotated(float(ray) * PI / 4.0)))
	_check(label + ": Ctrl+flecha da ángulo fino, no ocho únicos rayos",
		aim != null and aim.aim.length() > 0.99 and closest_ray < 0.9995
		and _state().actor(before.selected_actor_id).position.distance_to(before.actor(before.selected_actor_id).position) < 0.001
		and _commands[-1].move.is_zero_approx() and not _commands[-1].close_control)
	_key(KEY_CTRL, false)
	await _frames(2)
	_check(label + ": soltar modificador conserva el ángulo retenido",
		aim != null and _adapter().get_preview_command() != null
		and _adapter().get_preview_command().aim.distance_to(aim.aim) < 0.0001)
	_key(KEY_UP, true)
	_key(KEY_RIGHT, false)
	await _frames(2)
	var changed: Command = _adapter().get_preview_command()
	_check(label + ": cambiar dirección recupera apuntado directo sin neutral de stick",
		changed != null and changed.aim.dot(_camera().screen_direction_to_court(Vector2.UP)) > 0.999)
	_key(KEY_K, true)
	await _frames(3)
	_key(KEY_K, false)
	await _frames(2)
	_check(label + ": tiro lateral prohibido no se ejecuta ni cambia foco",
		_count(Event.Kind.SHOT) == 0 and _state().selected_actor_id == before.selected_actor_id
		and _state().restart.stage == Rules.RestartStage.READY)
	_assert_restart_feedback_visible(label + ": rechazo real de preflight", "Apunta hacia la portería rival")
	_release_all()
	await _frames(2)
	_key(KEY_RIGHT, true)
	await _frames(2)
	_key(KEY_RIGHT, false)
	_button(JOY_BUTTON_B, true)
	await _frames(6)
	_assert_guide(label + " antes de perder foco")
	root.focus_exited.emit()
	await _frames(2)
	var frozen: Array = _full_fingerprint(_state())
	await _frames(8)
	_check(label + ": perder foco pausa de verdad y borra la intención cacheada",
		_state().phase == Snapshot.Phase.PAUSED and _full_fingerprint(_state()) == frozen
		and _adapter().get_preview_command() == null and _adapter().shot_charge == 0.0 and not _arrow().visible)
	_check(label + ": pausa oculta ayuda y descarta el rechazo anterior",
		not _control("RestartFeedbackPanel").is_visible_in_tree()
		and not _label("RestartAimHint").is_visible_in_tree() and _label("RestartFeedback").text.is_empty())
	var view: Node3D = _host.get_node("Athletes/Athlete%d" % before.selected_actor_id) as Node3D
	_check(label + ": gesto de render congela su edad en el tick autoritativo",
		view.get("_context_valid") and view.get("_context_tick") == _state().tick
		and view.get("_context_phase") == Snapshot.Phase.PAUSED
		and view.get("_last_render_tick") == float(_state().tick))
	Input.joy_connection_changed.emit(0, false)
	await _frames(2)
	_check(label + ": desconexión durante pausa no ejecuta ni cambia el penalti",
		_full_fingerprint(_state()) == frozen and _count(Event.Kind.SHOT) == 0)
	_button(JOY_BUTTON_B, false)
	Input.joy_connection_changed.emit(0, true)
	_tap(KEY_ESCAPE)
	await _frames(270)
	_check(label + ": esperar más de cuatro segundos no cambia penalti ni reloj efectivo",
		_state().restart.stage == Rules.RestartStage.READY and _state().restart.deadline_tick == -1
		and _state().seconds_remaining == before.seconds_remaining and _count(Event.Kind.SHOT) == 0)
	_assert_ready_feedback_surface(label + ": ayuda persistente tras reanudar y esperar")
	_check(label + ": reanudar no reproduce el aviso ya descartado", _label("RestartFeedback").text.is_empty())
	_button(JOY_BUTTON_B, true)
	await _frames(8)
	_button(JOY_BUTTON_B, false)
	await _frames(2)
	var shot: Event = _last(Event.Kind.SHOT, before.selected_actor_id)
	_check(label + ": nueva carga y liberación sí ejecutan el tiro", shot != null
		and _state().selected_actor_id == before.selected_actor_id)
	await _assert_accepted_launch(label, shot)
	_case_done("precision/%d" % mode)


func _test_accumulated_choice(mode: Setup.Mode) -> void:
	var label: String = "G09/G22 m%d sexta acumulada" % mode
	if not await _catalog(mode, Setup.TrainingExercise.ACCUMULATED_FREE_KICK, label) or not await _ready_restart(label):
		return
	var before: Snapshot = _state()
	_assert_ready_feedback_surface(label)
	_check(label + ": contador inicial visible y elección realmente permitida",
		before.accumulated_fouls.y == 6 and before.restart.has_spot_choice
		and before.human_allowed_actions.has(Command.Action.CHOOSE_RESTART_SPOT)
		and _label("FoulTotals").text.contains("predefinido")
		and _label("FoulTotals").text.contains("VISITA 6"))
	_key(KEY_L, true)
	await _frames(2)
	var chosen: Snapshot = _state()
	_check(label + ": L elige punto de falta sin renovar el plazo",
		chosen.restart.spot_choice == Rules.SpotChoice.OFFENCE_SPOT
		and chosen.restart.spot.distance_to(chosen.restart.offence_spot) < 0.001
		and chosen.restart.deadline_tick == before.restart.deadline_tick and chosen.score == before.score)
	_key(KEY_L, true, true)
	await _frames(8)
	_check(label + ": retención y echo no alternan otra vez",
		_state().restart.spot_choice == chosen.restart.spot_choice and _spot_change_count() == 1)
	_key(KEY_L, false)
	await _frames(2)
	_button(JOY_BUTTON_X, true)
	_button(JOY_BUTTON_X, false)
	await _frames(2)
	_check(label + ": X vuelve a diez metros, sin regate ni extensión del timer",
		_state().restart.spot_choice == Rules.SpotChoice.TEN_METRE and _spot_change_count() == 2
		and _count(Event.Kind.DRIBBLE) == 0 and _state().restart.deadline_tick == before.restart.deadline_tick)
	var exact: Array = _full_fingerprint(_state())
	var camera: Transform3D = _camera().global_transform
	var bad: Command = Command.new(_state().selected_actor_id,
		_state().actor(_state().selected_actor_id).last_command_sequence)
	_command_negative = label + ": secuencia repetida"
	_command_negative_actor = bad.actor_id
	_command_negative_code = ERR_INVALID_PARAMETER
	_command_negative_remaining = 1
	var result: Error = _host.get_simulation().submit_human_command(bad)
	_check(_command_negative, result == ERR_INVALID_PARAMETER and _command_negative_remaining == 0
		and _full_fingerprint(_state()) == exact and _camera().global_transform.is_equal_approx(camera))
	_command_negative = ""
	var blocked: Snapshot = _state()
	var denied: Command = Command.new(blocked.selected_actor_id, blocked.actor(blocked.selected_actor_id).last_command_sequence + 1)
	denied.action = Command.Action.PASS
	denied.aim = Vector2.RIGHT
	_command_negative = label + ": pase prohibido en READY"
	_command_negative_actor = denied.actor_id
	_command_negative_code = ERR_UNAUTHORIZED
	_command_negative_remaining = 1
	result = _host.get_simulation().submit_human_command(denied)
	_check(_command_negative,
		result == ERR_UNAUTHORIZED and _command_negative_remaining == 0
		and _refusals[-1]["message"] == "Launch refused: launch_rule"
		and _full_fingerprint(_state()) == _full_fingerprint(blocked))
	_command_negative = ""
	await _frames(1)
	_assert_restart_feedback_visible(label + ": rechazo real de autoridad", "Acción no disponible en este saque")
	_check(label + ": mostrar el rechazo no pausa ni renueva cuatro segundos",
		_state().tick > blocked.tick and _state().restart.deadline_tick == blocked.restart.deadline_tick
		and _state().phase == Snapshot.Phase.RESTART_PAUSE)
	_case_done("choice/%d" % mode)


func _test_live_guide(mode: Setup.Mode) -> void:
	var label: String = "G16/G17/G18 m%d guía de tiro vivo" % mode
	if not await _catalog(mode, Setup.TrainingExercise.FREE_PLAY, label):
		return
	_check(label + ": nuevo entrenamiento borra ayuda de saque y rechazo anterior",
		not _control("RestartFeedbackPanel").is_visible_in_tree()
		and not _label("RestartAimHint").is_visible_in_tree() and _label("RestartFeedback").text.is_empty())
	_button(JOY_BUTTON_B, true)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	await _frames(10)
	_assert_guide(label)
	_check(label + ": carga nativa real habilita la flecha del jugador seleccionado",
		_adapter().shot_charge > 0.1 and _adapter().get_preview_command().action == Command.Action.SHOOT)
	_tap(KEY_F1)
	await _frames(2)
	var frozen: Array = _full_fingerprint(_state())
	await _with_check_context(label + "; desactivar guía por ratón", _click_dev.bind("AimGuideToggle"))
	_check(label + ": checkbox real confirma OFF sin tocar mundo, reloj ni IA",
		not _host.is_aim_guide_enabled() and not (_dev_control("AimGuideToggle") as BaseButton).button_pressed
		and _full_fingerprint(_state()) == frozen and not _arrow().visible)
	_check(label + ": Desarrollo no deja una segunda superficie contextual activa",
		not _control("RestartFeedbackPanel").is_visible_in_tree())
	await _with_check_context(label + "; activar guía por ratón", _click_dev.bind("AimGuideToggle"))
	_check(label + ": checkbox real confirma ON, aún sin revelar guía en pausa",
		_host.is_aim_guide_enabled() and _full_fingerprint(_state()) == frozen and not _arrow().visible)
	_tap(KEY_ESCAPE)
	await _frames(2)
	_tap(KEY_ESCAPE)
	await _frames(5)
	_check(label + ": reanudar exige neutral de sprint/carga, no replay",
		not _commands[-1].sprint and _commands[-1].move.is_zero_approx()
		and _adapter().shot_charge == 0.0 and _count(Event.Kind.SHOT) == 0)
	_release_all()
	await _frames(3)
	_key(KEY_K, true)
	await _frames(8)
	_assert_guide(label + " nueva pulsación")
	_key(KEY_K, false)
	await _frames(2)
	var shot: Event = _last(Event.Kind.SHOT, 0)
	await _assert_accepted_launch(label, shot)
	_check(label + ": ejecutar borra flecha y caché sin cambiar foco",
		shot != null and not _arrow().visible and _adapter().get_preview_command() == null
		and _state().selected_actor_id == 0)
	_case_done("guide/%d" % mode)


func _test_native_dribble(mode: Setup.Mode, gesture: int) -> void:
	var label: String = "G12/G19 m%d regate%d" % [mode, gesture]
	var exercise: Setup.TrainingExercise = Setup.TrainingExercise.DRIBBLE_PACE_CHANGE if gesture == 2 \
		else Setup.TrainingExercise.DRIBBLE_CUT
	if not await _catalog(mode, exercise, label):
		return
	var before: Snapshot = _state()
	var axis: JoyAxis = JOY_AXIS_LEFT_X if gesture == 2 else JOY_AXIS_LEFT_Y
	var amount: float = -1.0 if gesture == 0 else 1.0
	var key: Key = KEY_RIGHT if gesture == 2 else (KEY_UP if gesture == 0 else KEY_DOWN)
	var controller: bool = (mode + gesture) % 2 != 0
	_key(KEY_K, true)
	if controller:
		_axis(axis, amount)
		_button(JOY_BUTTON_X, true)
	else:
		_key(key, true)
		_key(KEY_L, true)
	await _frames(2)
	var event: Event = _last(Event.Kind.DRIBBLE, 0)
	var expected: Rules.GestureKind = Rules.GestureKind.PACE_CHANGE if gesture == 2 else Rules.GestureKind.CUT
	_check(label + ": L/X produce contacto y gesto autoritativos, no solo animación",
		event != null and event.success and event.gesture_kind == expected and event.contact_point.is_finite()
		and not _state().actor(0).gesture_contact_position.is_zero_approx()
		and _state().actor(0).gesture_kind == expected and _state().actor(0).gesture_duration_ticks > 0
		and _state().ball_position.distance_to(before.ball_position) > 0.01 and _state().ball_velocity.length() > 0.5
		and _state().actor(0).action_cooldown > 0.0)
	if event != null and gesture != 2:
		_check(label + ": enganches izquierdo y derecho tienen contacto lateral distinto",
			signf(_state().actor(0).gesture_direction.z) == amount)
	_check(label + ": regate gana a K simultánea sin arrastrar carga",
		_count(Event.Kind.SHOT) == 0 and _adapter().shot_charge == 0.0 and _state().selected_actor_id == 0)
	await _assert_host_contact_pose(label, event)
	if not controller:
		_key(KEY_L, true, true)
	await _frames(14)
	_check(label + ": mantener el botón no repite durante recuperación", _count(Event.Kind.DRIBBLE, 0) == 1
		and _count(Event.Kind.SHOT) == 0)
	_release_all()
	await _frames(3)
	_check(label + ": liberar no ejecuta tiro aplazado", _count(Event.Kind.SHOT) == 0)
	_case_done("dribble/%d/%d" % [mode, gesture])


func _test_invalid_exercise() -> void:
	_tap(KEY_F1)
	await _frames(2)
	var exact: Array = _full_fingerprint(_state())
	var views: Array[int] = _view_ids()
	_begin_negative("G30 ejercicio fuera de catálogo", ERR_INVALID_PARAMETER, false)
	_development.exercise_requested.emit(99 as Setup.TrainingExercise)
	await _frames(2)
	_end_negative()
	_check("G30 rechazo de ejercicio es visible, atómico y no una caída a FREE_PLAY",
		_full_fingerprint(_state()) == exact and _view_ids() == views and _development.is_open()
		and _dev_label("ErrorText").visible and not _dev_label("ErrorText").text.is_empty())
	_tap(KEY_ESCAPE)
	await _frames(2)
	_case_done("invalid-exercise")


func _test_terminal_controls() -> void:
	await _begin("G24 terminal de autoridad", _no_ball_setup(), 0.12)
	await _frames(20)
	var frozen: Array = _full_fingerprint(_state())
	var count: int = _commands.size()
	_key(KEY_L, true)
	_key(KEY_L, false)
	_button(JOY_BUTTON_X, true)
	_button(JOY_BUTTON_X, false)
	await _frames(10)
	_check("G24 fin mantiene foco/score y bloquea nuevos controles sin reset implícito",
		_state().phase == Snapshot.Phase.FINISHED and _full_fingerprint(_state()) == frozen
		and _commands.size() == count and not _arrow().visible and _adapter().get_preview_command() == null
		and _control("PauseOverlay").visible)
	_check("G24 resultado no conserva ayuda ni rechazo de una reanudación",
		not _control("RestartFeedbackPanel").is_visible_in_tree()
		and not _label("RestartAimHint").is_visible_in_tree() and _label("RestartFeedback").text.is_empty())
	_case_done("terminal")


func _assert_accepted_launch(label: String, event: Event) -> void:
	_check(label + ": ejecución tiene evento físico y petición nativa aceptada",
		event != null and not _launch_requests.is_empty())
	if event == null or _launch_requests.is_empty():
		return
	var request: Dictionary = _launch_requests[-1]
	var solution: Launch.Solution = request["solution"]
	var command: Command = request["command"]
	_check(label + ": ejecución reutiliza origen/dirección/potencia del resolver",
		solution.error == OK and solution.executable and event.velocity.distance_to(solution.velocity) < 0.001
		and event.position.distance_to(solution.origin) < 0.04 and event.launch_kind == solution.launch_kind
		and event.actor_id == command.actor_id and is_equal_approx(event.shot_charge, command.shot_charge))
	_check(label + ": aceptar el golpeo limpia ayuda y rechazo del saque",
		not _control("RestartFeedbackPanel").is_visible_in_tree()
		and not _label("RestartAimHint").is_visible_in_tree() and _label("RestartFeedback").text.is_empty())
	await _assert_host_contact_pose(label, event)


func _assert_ready_feedback_surface(label: String) -> void:
	var state: Snapshot = _state()
	var panel: Control = _control("RestartFeedbackPanel")
	var hint: Label = _label("RestartAimHint")
	_check(label + ": READY propio muestra ayuda real visible, no solo una constante",
		state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.stage == Rules.RestartStage.READY
		and state.restart.awarded_team_id == Snapshot.Team.HOME and panel.is_visible_in_tree()
		and hint.is_visible_in_tree() and hint.text == Adapter.FINE_AIM_HINT
		and hint.get_line_count() <= hint.max_lines_visible and hint.get_visible_line_count() == hint.get_line_count())
	var bounds: Rect2 = _feedback_screen_rect(panel)
	_check(label + ": avisos quedan en la ventana y fuera del centro", root.get_visible_rect().encloses(bounds)
		and not bounds.has_point(root.get_visible_rect().get_center()))
	for name: String in ["RestartPanel", "SelectionPanel", "HelpPanel", "ChargePanel"]:
		_check(label + ": avisos no cubren " + name, not bounds.intersects(_feedback_screen_rect(_control(name))))
	for name: String in ["RestartTitle", "RestartClock", "RestartDetail", "ControlsContext"]:
		_check(label + ": " + name + " sigue visible y legible", _label(name).is_visible_in_tree() and not _label(name).text.is_empty())


func _assert_restart_feedback_visible(label: String, message: String) -> void:
	_check(label + ": aviso producido por la ruta real es visible",
		not message.is_empty() and _control("RestartFeedbackPanel").is_visible_in_tree()
		and _label("RestartFeedback").is_visible_in_tree() and _label("RestartFeedback").text == message
		and _label("RestartFeedback").get_line_count() <= _label("RestartFeedback").max_lines_visible
		and _label("RestartFeedback").get_visible_line_count() == _label("RestartFeedback").get_line_count()
		and _label("RestartAimHint").is_visible_in_tree())


func _feedback_screen_rect(control: Control) -> Rect2:
	return Rect2(control.get_global_transform_with_canvas() * Vector2.ZERO,
		control.size * control.get_global_transform_with_canvas().get_scale().abs())


func _assert_host_contact_pose(label: String, event: Event) -> void:
	_check(label + ": contacto aceptado disponible para observar la presentación real", event != null and event.success)
	if event == null:
		return
	var first: Dictionary = _athlete_pose(event.actor_id)
	_check(label + ": G19/G31 HOST entrega contexto vigente al atleta en contacto",
		first["context_valid"] and first["context_tick"] == _state().tick
		and first["validation_error"] == "" and first["contact_tick"] == event.tick
		and first["gesture_kind"] == event.gesture_kind and first["gesture_weight"] > 0.0
		and first["render_tick"] >= float(event.tick) - 1.0
		and _pose_point(first["contact_world"]).distance_to(event.contact_point) < 0.0001)
	await _frames(2)
	var second: Dictionary = _athlete_pose(event.actor_id)
	_check(label + ": contexto y edad del gesto avanzan desde el HOST, no desde un reloj ficticio",
		second["context_valid"] and second["context_tick"] == _state().tick
		and second["context_tick"] > first["context_tick"] and second["render_tick"] > first["render_tick"]
		and second["gesture_progress"] > first["gesture_progress"] and second["contact_tick"] == event.tick
		and second["validation_error"] == "")
	_check(label + ": cambian transformaciones de pies/manos de los nodos renderizados",
		first["feet"] != second["feet"] or first["hands"] != second["hands"])
	_athlete_presentations.append({"case": label, "event_id": event.event_id, "accepted_tick": event.tick,
		"at_contact": first, "advanced": second})


func _assert_keeper_render_anchor(label: String, keeper: int) -> void:
	var pose: Dictionary = _athlete_pose(keeper)
	var ball: Vector3 = _host.get_render_ball_position()
	var anchored: bool = true
	for hand: Dictionary in pose["hands"]:
		var distance: float = _pose_point(hand["origin"]).distance_to(ball)
		anchored = anchored and distance >= Tuning.BALL_RADIUS * 0.6 and distance <= Tuning.BALL_RADIUS + 0.06
	_check(label + ": G31 manos reales rodean el mismo balón interpolado de BallView",
		pose["context_valid"] and pose["context_tick"] == _state().tick and pose["validation_error"] == ""
		and _pose_point(pose["snapshot_ball"]) == _state().ball_position and anchored)
	_athlete_presentations.append({"case": label + "/ready_hands", "pose": pose,
		"render_ball_position": [ball.x, ball.y, ball.z]})


func _athlete_pose(id: int) -> Dictionary:
	var view: Node3D = _host.get_node("Athletes/Athlete%d" % id) as Node3D
	var legs: Array = view.get("_legs")
	var arms: Array = view.get("_arms")
	var feet: Array[Dictionary] = []
	var hands: Array[Dictionary] = []
	for side: int in 2:
		feet.append(_mesh_transform(legs[side][3] as Node3D))
		hands.append(_mesh_transform(arms[side][2] as Node3D))
	var contact: Vector3 = view.get("_gesture_contact_world")
	var snapshot_ball: Vector3 = view.get("_ball_current")
	return {"actor_id": id, "path": String(view.get_path()), "source_script": String(view.get_script().resource_path),
		"context_valid": view.get("_context_valid"), "context_before_tick": view.get("_context_before_tick"),
		"context_tick": view.get("_context_tick"), "context_phase": view.get("_context_phase"),
		"render_tick": view.get("_last_render_tick"), "validation_error": view.get("_last_validation_error"),
		"gesture_kind": view.get("_gesture_kind"), "gesture_weight": view.get("_gesture_weight"),
		"gesture_progress": view.get("_gesture_progress"), "contact_tick": view.get("_gesture_contact_tick"),
		"gesture_age_ticks": float(view.get("_last_render_tick")) - float(view.get("_gesture_contact_tick")),
		"contact_world": [contact.x, contact.y, contact.z],
		"snapshot_ball": [snapshot_ball.x, snapshot_ball.y, snapshot_ball.z], "feet": feet, "hands": hands}


func _mesh_transform(node: Node3D) -> Dictionary:
	var transform: Transform3D = node.global_transform
	return {"path": String(node.get_path()), "visible": node.is_visible_in_tree(),
		"origin": [transform.origin.x, transform.origin.y, transform.origin.z],
		"basis_x": [transform.basis.x.x, transform.basis.x.y, transform.basis.x.z],
		"basis_y": [transform.basis.y.x, transform.basis.y.y, transform.basis.y.z],
		"basis_z": [transform.basis.z.x, transform.basis.z.y, transform.basis.z.z]}


func _pose_point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _effective(intent: Array[int], selected: int) -> Array[int]:
	var result: Array[int] = intent.duplicate()
	result.erase(selected)
	return result


func _spot_change_count() -> int:
	return _events.filter(func(event: Event) -> bool:
		return event.kind == Event.Kind.RESTART_CHANGED and event.reason == &"spot_changed").size()


func _with_check_context(context: String, operation: Callable) -> void:
	var previous: String = _helper_check_context
	_helper_check_context = context
	await operation.call()
	_helper_check_context = previous


func _check(label: String, passed: bool) -> void:
	var identity: String = label if _helper_check_context.is_empty() \
		else "%s [case: %s]" % [label, _helper_check_context]
	super(identity, passed)


func _record_refusal(id: int, code: Error, message: String) -> void:
	if _command_negative.is_empty():
		super(id, code, message)
		return
	var item: Dictionary = {"id": id, "code": code, "message": message}
	_refusals.append(item)
	if id == _command_negative_actor and code == _command_negative_code and _command_negative_remaining == 1:
		_command_negative_remaining -= 1
		var expected: Dictionary = item.duplicate()
		expected["case"] = _command_negative
		_expected_refusals.append(expected)
	else:
		_unexpected_refusals.append(item)


func _diagnostics_ok() -> bool:
	return super() and _command_negative.is_empty() and _command_negative_remaining == 0 \
		and _helper_check_context.is_empty()


func _expected_cases() -> Array[String]:
	var result: Array[String] = ["abi", "invalid-exercise", "terminal"]
	for mode: int in [0, 1]:
		for exercise: int in 12:
			result.append("catalog/%d/%d" % [mode, exercise])
		for prefix: String in ["keeper", "precision", "choice", "guide"]:
			result.append("%s/%d" % [prefix, mode])
		for gesture: int in 3:
			result.append("dribble/%d/%d" % [mode, gesture])
	return result


func _test_marker() -> String:
	return "FUTSAL_MATCH_GAMEPLAY_RUNTIME_TESTS"
