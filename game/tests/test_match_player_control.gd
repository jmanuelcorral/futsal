extends "res://tests/test_match_preview_integration.gd"
## F01–F12 sobre el main real; las únicas órdenes construidas son negativas explícitas.

const GameplayTypes = preload("res://match/simulation/match_rule_types.gd")

const CASES: Array[String] = [
	"F01", "F02", "F03", "F04", "F05", "F06",
	"F07", "F08", "F09", "F10", "F11", "F12",
]

var _authority: Simulation
var _completed_cases: Array[String] = []
var _observed_events: Array[Dictionary] = []
var _submitted_samples: Array[Dictionary] = []
var _focus_evidence: Array[Dictionary] = []
var _camera_motion: Dictionary = {}
var _negative_actor: int = -1
var _source_script: String = ""


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var bindings: Dictionary = _bindings()
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	_check("F01 main configurado de producción", path == "res://match/match.tscn")
	var packed: PackedScene = load(path) as PackedScene
	_host = packed.instantiate() as MatchHost if packed != null else null
	_check("F01 instancia anfitrión real", _host != null)
	if _host == null:
		_report()
		quit(1)
		return
	_source_script = _host.get_script().resource_path
	_authority = _host.get_node("Simulation") as Simulation
	_development = _host.get_node("MatchDevMenu") as DevelopmentMenu
	_authority.event_raised.connect(_record_live_event)
	_authority.command_rejected.connect(_record_refusal)
	_host.command_submitted.connect(_record_live_command)
	_host.integration_error.connect(_record_error)
	_host.exit_requested.connect(_on_exit_requested)
	_development.mode_requested.connect(func(mode: Setup.Mode) -> void: _mode_requests.append(mode))
	root.add_child(_host)
	current_scene = _host
	await _frames(6)
	_check("F01 scripts reales de host, autoridad, entrada y cámara",
		_source_script == "res://match/match.gd" and _authority.get_script() == Simulation
		and _adapter().get_script() == Adapter and _camera().get_script() == Camera)
	_assert_composition(Setup.Mode.PREVIEW_5V5, 10, "F01 default antes de drills")
	_check("F01 default 0/10/9 con intención completa", _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == ALL_INTENT and _state().ai_actor_ids == ALL_AI
		and _state().phase == Snapshot.Phase.PLAYING and _state().tick > 0
		and _state().seconds_remaining < 120.0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	_assert_frame("F01 default")
	var before: Snapshot = _state()
	_key(KEY_RIGHT, true)
	await _frames(10)
	_check("F01 flecha física mueve al default antes de cualquier reset",
		_state().actor(0).position.x > before.actor(0).position.x + 0.15
		and _commands[-1].move.x > 0.99 and _state().selected_actor_id == 0)
	_key(KEY_RIGHT, false)
	await _frames(14)
	_check("F01 liberación nativa frena al default", _planar_speed() < 0.02)
	if _failed():
		_report()
		quit(1)
		return
	await _test_mode_controls()
	_completed_cases.append("F01")
	await _case_nearest()
	_completed_cases.append("F02")
	await _case_directions()
	_completed_cases.append("F03")
	await _case_edges()
	_completed_cases.append("F04")
	await _case_teammate_owner()
	_completed_cases.append("F05")
	await _case_pass_focus()
	_completed_cases.append("F06")
	await _case_pass_negatives()
	_completed_cases.append("F07")
	await _case_sequences()
	_completed_cases.append("F08")
	await _case_ai_intent()
	_completed_cases.append("F09")
	await _case_input_lifecycle()
	_completed_cases.append("F10")
	await _case_phases()
	_completed_cases.append("F11")
	await _case_presentation()
	_completed_cases.append("F12")
	_check("F01–F12 no modifican bindings durante ejecución", bindings == _bindings())
	_check("negativas exactas y ninguna advertencia de integración imprevista", _diagnostics_ok())
	_check("entrada nativa teclado, mando y UI con ratón", int(_native_events["key"]) > 100
		and int(_native_events["joy_button"]) > 30 and int(_native_events["joy_motion"]) > 30
		and _mouse_events >= 2)
	if _failed():
		_report()
		quit(1)
		return
	await _test_exit()


func _case_nearest() -> void:
	var setup: Setup = _pass_preview()
	setup.actor_positions[4] = Vector3(-7, 0, -5)
	setup.actor_positions[6] = Vector3(10, 0, 6)
	setup.ball_position = Vector3(10.55, 0.12, 6)
	await _begin("F02 cercano al controlado, no al balón", setup)
	_check("F02 balón está en otro compañero lejano", _state().ball_owner_id == 6)
	_tap(KEY_J)
	await _frames(2)
	_check("F02 neutro elige cercano a 0 y no cercano al balón", _state().selected_actor_id == 4
		and _state().ball_owner_id == 6 and _count(Event.Kind.PASS) == 0)
	setup.actor_positions[6] = Vector3(-7, 0, -1)
	setup.ball_position = Vector3(10, 0.12, 6)
	await _begin("F02 empate por identidad", setup)
	_tap(KEY_J)
	await _frames(2)
	_check("F02 distancia igual usa ID menor", _state().selected_actor_id == 4)
	await _begin("F02 micro incluye portero", _no_ball_setup())
	_tap(KEY_J)
	await _frames(2)
	_check("F02 micro cambia 0 a 2", _state().selected_actor_id == 2)
	_tap(KEY_J)
	await _frames(2)
	_check("F02 micro vuelve 2 a 0", _state().selected_actor_id == 0
		and _count(Event.Kind.FOCUS_CHANGED) == 2 and _count(Event.Kind.PASS) == 0)


func _case_directions() -> void:
	var keys: Array[Dictionary] = [
		{"key": KEY_LEFT, "id": 8}, {"key": KEY_RIGHT, "id": 6},
		{"key": KEY_UP, "id": 4}, {"key": KEY_DOWN, "id": 2},
		{"key": KEY_A, "id": 8}, {"key": KEY_D, "id": 6},
		{"key": KEY_W, "id": 4}, {"key": KEY_S, "id": 2},
	]
	for item: Dictionary in keys:
		for order: int in 3:
			var label: String = "F03 tecla %s orden %d" % [OS.get_keycode_string(item["key"]), order]
			await _begin(label, _fan_setup())
			if order == 2:
				_tap(KEY_J)
			_key(item["key"] as Key, true)
			if order == 0:
				await _frames(1)
			if order != 2:
				_tap(KEY_J)
			_check(label + " no cambia optimistamente", _state().selected_actor_id == 0)
			await _frames(2)
			_check(label + " usa dirección al muestrear", _state().selected_actor_id == int(item["id"])
				and _count(Event.Kind.FOCUS_CHANGED) == 1 and _count(Event.Kind.PASS) == 0)
			_key(item["key"] as Key, false)
	var sticks: Array[Dictionary] = [
		{"axis": JOY_AXIS_LEFT_X, "value": -1.0, "id": 8},
		{"axis": JOY_AXIS_LEFT_X, "value": 1.0, "id": 6},
		{"axis": JOY_AXIS_LEFT_Y, "value": -1.0, "id": 4},
		{"axis": JOY_AXIS_LEFT_Y, "value": 1.0, "id": 2},
	]
	for item: Dictionary in sticks:
		for order: int in 3:
			var label: String = "F03 stick %d/%s orden %d" % [item["axis"], item["value"], order]
			await _begin(label, _fan_setup())
			if order == 2:
				_button(JOY_BUTTON_A, true)
			_axis(item["axis"] as JoyAxis, float(item["value"]))
			if order == 0:
				await _frames(1)
			if order != 2:
				_button(JOY_BUTTON_A, true)
			await _frames(2)
			_button(JOY_BUTTON_A, false)
			_axis(item["axis"] as JoyAxis, 0.0)
			_check(label + " selecciona por cámara y no por orden de eventos",
				_state().selected_actor_id == int(item["id"]) and _count(Event.Kind.FOCUS_CHANGED) == 1)
	var setup: Setup = _pass_preview()
	setup.ball_position = Vector3(0, 0.12, 8)
	setup.actor_positions[4] = Vector3(-8, 0, -6)
	await _begin("F03 sin candidato dentro del cono", setup)
	_begin_control_negative("F03 switch sin candidato", ERR_UNAVAILABLE, 0)
	_key(KEY_RIGHT, true)
	_tap(KEY_J)
	await _frames(2)
	_end_control_negative()
	_check("F03 rechazo conserva seleccionado y movimiento", _state().selected_actor_id == 0
		and _commands[-1].move.x > 0.99 and _state().actor(0).velocity.x > 0.0
		and _count(Event.Kind.FOCUS_CHANGED) == 0)
	_check("F03 rechazo tiene feedback contextual, no error de contacto",
		_label("EventText").text == "No hay compañero en esa dirección")
	_release_all()


func _case_edges() -> void:
	await _begin("F04 switch retenido y echo", _fan_setup())
	_key(KEY_LEFT, true)
	_key(KEY_J, true)
	await _frames(2)
	for attempt: int in 5:
		_key(KEY_J, true, true)
		_key(KEY_J, true)
		await _frames(2)
	_check("F04 flanco único bloquea hold y echo, incluso eventos press repetidos",
		_state().selected_actor_id == 8 and _count(Event.Kind.FOCUS_CHANGED) == 1
		and _commands.filter(func(command: Command) -> bool:
			return command.action == Command.Action.SWITCH_TEAMMATE).size() == 1)
	await _begin("F04 pase retenido atraviesa recepción", _pass_preview())
	_key(KEY_J, true)
	await _frames(2)
	_key(KEY_J, true, true)
	await _wait_owner(4)
	await _frames(30)
	_check("F04 nueva posesión no repite el pase ni cambia foco",
		_state().selected_actor_id == 4 and _state().ball_owner_id == 4
		and _count(Event.Kind.PASS) == 1 and _count(Event.Kind.FOCUS_CHANGED) == 1)
	_key(KEY_J, false)
	await _frames(1)
	_tap(KEY_J)
	await _frames(2)
	_check("F04 soltar habilita exactamente un nuevo pase", _count(Event.Kind.PASS) == 2
		and _state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 2)


func _case_teammate_owner() -> void:
	var setup: Setup = _fan_setup()
	setup.ball_position = Vector3(6.55, 0.12, 0)
	await _begin("F05 compañero poseedor", setup)
	_check("F05 compañero 6 posee por contacto físico", _state().ball_owner_id == 6)
	var possessions: int = _count(Event.Kind.POSSESSION)
	_key(KEY_RIGHT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_RIGHT, false)
	_check("F05 J elige poseedor, no le ordena un pase",
		_state().selected_actor_id == 6 and _state().ball_owner_id == 6
		and _count(Event.Kind.PASS) == 0 and _count(Event.Kind.POSSESSION) == possessions
		and _last_command(Command.Action.SWITCH_TEAMMATE) != null)
	_check("F05 HUD usa posesión del seleccionado", _label("ControlsContext").text.begins_with("CON BALÓN"))


func _case_pass_focus() -> void:
	for directed: bool in [false, true]:
		var setup: Setup = _pass_preview()
		if directed:
			setup.actor_positions[4] = Vector3(0, 0, -7)
			setup.actor_forwards[4] = Vector2(-1, 1).normalized()
		await _begin("F06 pase a campo dirigido=%s" % directed, setup)
		var before: Snapshot = _state()
		var views: Array[int] = _view_ids()
		if directed:
			_axis(JOY_AXIS_LEFT_X, 1.0)
			_axis(JOY_AXIS_LEFT_Y, -1.0)
		_button(JOY_BUTTON_A, true)
		_check("F06 pulsación no transfiere antes del tick", _state().selected_actor_id == 0)
		await _frames(2)
		_button(JOY_BUTTON_A, false)
		_release_all()
		var pass_event: Event = _last(Event.Kind.PASS, 0)
		var focus_event: Event = _last(Event.Kind.FOCUS_CHANGED, 0)
		_check("F06 transferencia solo tras patada autoritativa", pass_event != null and focus_event != null
			and pass_event.event_id < focus_event.event_id and pass_event.tick == focus_event.tick
			and pass_event.target_actor_id == 4 and focus_event.target_actor_id == 4
			and focus_event.reason == &"pass" and _state().selected_actor_id == 4
			and _state().ball_owner_id == -1)
		var event_state: Snapshot = _focus_snapshot()
		_check("F06 ambos eventos publican snapshot coherente y receptor físico intacto",
			event_state != null and event_state.selected_actor_id == 4 and event_state.ball_owner_id == -1
			and event_state.actor(4).position.distance_to(before.actor(4).position) < 0.07
			and _view_ids() == views and _state().ai_intent_actor_ids.is_empty())
		await _wait_owner(4)
		_check("F06 posesión llega después de la patada", _state().ball_owner_id == 4
			and _state().selected_actor_id == 4 and _count(Event.Kind.FOCUS_CHANGED) == 1)
	await _test_pass_and_return()


func _case_pass_negatives() -> void:
	var setup: Setup = _pass_preview()
	setup.actor_positions[4] = Vector3(-2, 0, -3)
	_authority.tuning.action_cooldown = 1.0
	await _begin("F07 cooldown después de pase y devolución físicos", setup)
	_tap(KEY_J)
	await _frames(2)
	await _wait_owner(4)
	await _frames(18)
	_tap(KEY_J)
	await _frames(2)
	await _wait_owner(0)
	_check("F07 fixture recupera balón con apoyo todavía enfriando", _state().selected_actor_id == 0
		and _state().ball_owner_id == 0 and _state().actor(0).action_cooldown > 0.03)
	var focus_count: int = _count(Event.Kind.FOCUS_CHANGED)
	var passes: int = _count(Event.Kind.PASS)
	_tap(KEY_J)
	await _frames(1)
	_check("F07 adaptador comunica cooldown sin encolar pase ni foco",
		_count(Event.Kind.PASS) == passes and _count(Event.Kind.FOCUS_CHANGED) == focus_count
		and _label("EventText").text == "Espera al siguiente apoyo")
	_begin_control_negative("F07 rechazo de cooldown", ERR_BUSY, 0)
	_check("F07 autoridad rechaza patada durante cooldown", _submit_negative_pass() == ERR_BUSY)
	_end_control_negative()
	_check("F07 rechazo de cooldown no cambia foco", _state().selected_actor_id == 0)
	_authority.tuning.action_cooldown = 0.32
	await _begin("F07 sin contacto alcanzable", _no_ball_setup())
	_begin_control_negative("F07 pase sin contacto", ERR_UNAVAILABLE, 0)
	_check("F07 autoridad rechaza pase sin contacto", _submit_negative_pass() == ERR_UNAVAILABLE)
	_end_control_negative()
	await _frames(2)
	_check("F07 contacto ausente no concede foco ni pase", _state().selected_actor_id == 0
		and _count(Event.Kind.PASS) == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	await _begin("F07 receptor explícito rival", _pass_preview())
	_begin_control_negative("F07 receptor rival", ERR_INVALID_PARAMETER, 0)
	_check("F07 receptor inválido se rechaza", _submit_negative_pass(1) == ERR_INVALID_PARAMETER)
	_end_control_negative()
	await _frames(2)
	_check("F07 objetivo inválido no transfiere", _state().selected_actor_id == 0
		and _state().ball_owner_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	setup = _pass_preview()
	setup.actor_positions[4] = Vector3(-8, 0, -7)
	await _begin("F07 pase libre", setup)
	_key(KEY_RIGHT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_RIGHT, false)
	var pass_event: Event = _last(Event.Kind.PASS, 0)
	_check("F07 pase libre mantiene foco aunque salga balón", pass_event != null
		and pass_event.target_actor_id == -1 and _state().selected_actor_id == 0
		and _count(Event.Kind.FOCUS_CHANGED) == 0 and _state().ball_owner_id == -1)
	setup = _pass_preview()
	setup.actor_positions[1] = Vector3(-1, 0, -3)
	setup.actor_forwards[1] = Vector2.LEFT
	await _begin("F07 intercepción real", setup)
	_tap(KEY_J)
	await _frames(2)
	await _wait_owner(1)
	_check("F07 rival intercepta sin recibir foco", _state().ball_owner_id == 1
		and _state().selected_actor_id == 4 and _count(Event.Kind.FOCUS_CHANGED) == 1
		and _last(Event.Kind.FOCUS_CHANGED, 0).target_actor_id == 4)


func _case_sequences() -> void:
	var setup: Setup = _fan_setup()
	setup.ai_actor_ids = ALL_INTENT.duplicate()
	setup.ball_position = Vector3(15, 0.12, 8)
	await _begin("F08 secuencias 0 a 8 a 0 con IA", setup)
	var initial_sequence: int = _state().actor(8).last_command_sequence
	_key(KEY_LEFT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_LEFT, false)
	var first: Snapshot = _focus_snapshot()
	_check("F08 8 conserva secuencia de su IA anterior", _state().selected_actor_id == 8
		and initial_sequence >= 0 and first.actor(8).last_command_sequence >= initial_sequence
		and _first_sample_after(first, 8) == first.actor(8).last_command_sequence + 1)
	_begin_control_negative("F08 antiguo seleccionado no autorizado", ERR_UNAUTHORIZED, 0)
	var stale: Command = Command.new(0, _state().actor(0).last_command_sequence + 1)
	_check("F08 humano antiguo no conserva autorización", _authority.submit_human_command(stale) == ERR_UNAUTHORIZED)
	_end_control_negative()
	await _frames(5)
	_key(KEY_RIGHT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_RIGHT, false)
	var second: Snapshot = _focus_snapshot()
	_check("F08 volver a 0 toma secuencia posterior a su IA", _state().selected_actor_id == 0
		and second.actor(0).last_command_sequence > first.actor(0).last_command_sequence
		and _first_sample_after(second, 0) == second.actor(0).last_command_sequence + 1
		and _state().ai_actor_ids == ALL_AI and _state().ai_intent_actor_ids == ALL_INTENT)
	_check("F08 no hay acciones heredadas de receptores", _count(Event.Kind.FOCUS_CHANGED) == 2
		and _count(Event.Kind.PASS) == 0 and _count(Event.Kind.SHOT) == 0)
	await _begin("F08 reentrada desde FOCUS_CHANGED", _fan_setup())
	var reentrant: Array[int] = []
	var callback: Callable = func(event: Event) -> void:
		if event.kind != Event.Kind.FOCUS_CHANGED:
			return
		var state: Snapshot = _state()
		_begin_control_negative("F08 comando dentro de evento", ERR_BUSY, state.selected_actor_id)
		var command: Command = Command.new(state.selected_actor_id,
			state.actor(state.selected_actor_id).last_command_sequence + 1)
		reentrant.append(_authority.submit_human_command(command))
		_end_control_negative()
	_authority.event_raised.connect(callback)
	_key(KEY_LEFT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_LEFT, false)
	_authority.event_raised.disconnect(callback)
	_check("F08 callback no muta autoridad ni pierde cambio válido", reentrant == [ERR_BUSY]
		and _state().selected_actor_id == 8 and _count(Event.Kind.FOCUS_CHANGED) == 1)
	for recipient: int in [8, 0]:
		setup = _pass_preview()
		setup.actor_positions[0] = Vector3(10 if recipient == 8 else 14, 0, -3)
		setup.actor_positions[8] = Vector3(14 if recipient == 8 else 10, 0, -3)
		setup.actor_positions[4] = Vector3(-8, 0, -6)
		setup.actor_positions[6] = Vector3(-8, 0, 6)
		setup.actor_positions[3] = Vector3(18.5, 0, 8)
		setup.ball_position = Vector3(14.55 if recipient == 8 else 17, 0.12, -3)
		setup.ball_velocity = Vector3.ZERO if recipient == 8 else Vector3(-4, 0, 0)
		await _begin("F08 cancelar patada IA pendiente hacia %d" % recipient, setup)
		if recipient == 0:
			_key(KEY_LEFT, true)
			_tap(KEY_J)
			await _frames(2)
			_release_all()
			await _frames(2)
		await _wait_owner(recipient)
		var sequence: int = _state().actor(recipient).last_command_sequence
		var ai: Array[int] = [0, 8]
		_check("F08 activar IA real del próximo receptor", _host.set_ai_actor_ids(ai) == OK)
		_key(KEY_RIGHT, true)
		_tap(KEY_J)
		await _frames(2)
		_key(KEY_RIGHT, false)
		var handed: Snapshot = _focus_snapshot()
		_check("F08 IA del receptor aceptó secuencia antes del traspaso %d" % recipient,
			handed != null and handed.selected_actor_id == recipient
			and handed.actor(recipient).last_command_sequence == sequence + 1)
		_check("F08 acción del seleccionado cancela patada IA, también hacia ID inferior %d" % recipient,
			_state().selected_actor_id == recipient and _state().ball_owner_id == recipient
			and _count(Event.Kind.SHOT) == 0 and _count(Event.Kind.PASS) == 0
			and handed.actor(recipient).action_cooldown == 0.0)


func _case_ai_intent() -> void:
	for values: Array in [[], [0], [2, 8], [0, 2, 4, 6, 8]]:
		var intent: Array[int] = []
		intent.assign(values)
		var setup: Setup = _fan_setup()
		setup.ai_actor_ids = intent.duplicate()
		await _begin("F09 intención exacta " + str(intent), setup)
		_key(KEY_LEFT, true)
		_tap(KEY_J)
		await _frames(2)
		_key(KEY_LEFT, false)
		var effective: Array[int] = intent.duplicate()
		effective.erase(8)
		_check("F09 transferencia respeta intención " + str(intent),
			_state().selected_actor_id == 8 and _state().ai_intent_actor_ids == intent
			and _state().ai_actor_ids == effective)
		var old_sequence: int = _state().actor(0).last_command_sequence
		await _frames(12)
		_check("F09 antiguo humano vuelve a IA solo si estaba previsto " + str(intent),
			(_state().actor(0).last_command_sequence > old_sequence) == intent.has(0))
		_check("F09 reinicio preserva intención y vuelve a 0 " + str(intent), _host.restart_match() == OK
			and _state().selected_actor_id == 0 and _state().ai_intent_actor_ids == intent
			and _state().mode == Setup.Mode.PREVIEW_5V5)
	await _begin("F09 intención latente del controlado", _fan_setup())
	_key(KEY_LEFT, true)
	_tap(KEY_J)
	await _frames(2)
	_key(KEY_LEFT, false)
	_key(KEY_D, true)
	_key(KEY_SHIFT, true)
	await _frames(8)
	var before: Snapshot = _state()
	var latent: Array[int] = [8]
	_check("F09 permite intención del seleccionado sin interrumpirlo", _host.set_ai_actor_ids(latent) == OK
		and _state().actor(8).velocity == before.actor(8).velocity
		and _state().ai_intent_actor_ids == [8] and _state().ai_actor_ids.is_empty())
	await _frames(4)
	_check("F09 movimiento humano continúa al cambiar preferencia latente",
		_state().selected_actor_id == 8 and _commands[-1].move.x > 0.99 and _commands[-1].sprint)
	_release_all()
	await _frames(3)
	await _open_from_hud()
	_check("F09 grupo local parcial incluye al seleccionado",
		_dev_label("TeammatesStatus").text.contains("Parcial")
		and not (_dev_control("TeammatesToggle") as BaseButton).disabled)
	await _click_dev("TeammatesToggle")
	_check("F09 ratón configura intención completa del campo, incluido el humano",
		_state().ai_intent_actor_ids == [0, 4, 6, 8] and _state().ai_actor_ids == [0, 4, 6])
	var configured: Array[int] = _state().ai_intent_actor_ids.duplicate()
	_tap(KEY_ESCAPE)
	await _frames(2)
	_tap(KEY_ESCAPE)
	await _frames(3)
	_tap(KEY_J)
	await _frames(2)
	var handoff: Snapshot = _focus_snapshot()
	_check("F09 preferencia latente se restaura al deseleccionar", _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == configured and _state().ai_actor_ids == [4, 6, 8])
	await _frames(12)
	_check("F09 antiguo seleccionado vuelve a generar IA prevista",
		_state().actor(8).last_command_sequence > handoff.actor(8).last_command_sequence)
	_check("F09 reinicio conserva preferencia latente, no lista efectiva",
		_host.restart_match() == OK and _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == configured and _state().ai_actor_ids == [4, 6, 8])
	_check("F09 modo canónico restaura defaults completos",
		_host.start_development_mode(Setup.Mode.PREVIEW_5V5) == OK
		and _state().selected_actor_id == 0 and _state().ai_intent_actor_ids == ALL_INTENT
		and _state().ai_actor_ids == ALL_AI)


func _case_input_lifecycle() -> void:
	await _begin("F10 sprint continúa al cambiar jugador", _fan_setup())
	_key(KEY_A, true)
	_key(KEY_SHIFT, true)
	await _frames(14)
	_key(KEY_J, true)
	await _frames(2)
	var before: Vector3 = _state().actor(8).position
	_check("F10 cambio no exige neutral del stick o sprint", _state().selected_actor_id == 8
		and _commands[-1].actor_id == 8 and _commands[-1].move.x < -0.99 and _commands[-1].sprint
		and not bool(_adapter().get("_waiting_for_neutral")) and _adapter().enabled)
	await _frames(10)
	_check("F10 nuevo atleta se mueve con controles retenidos",
		_state().actor(8).position.x < before.x - 0.2 and _planar_speed() > 3.0
		and _count(Event.Kind.FOCUS_CHANGED) == 1)
	await _begin("F10 pase conserva stick y RT", _pass_preview())
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_button(JOY_BUTTON_A, true)
	await _frames(2)
	before = _state().actor(4).position
	_check("F10 pase no crea barrera nueva para stick y RT", _state().selected_actor_id == 4
		and _commands[-1].actor_id == 4 and _commands[-1].move.x > 0.99 and _commands[-1].sprint
		and not bool(_adapter().get("_waiting_for_neutral")) and _adapter().shot_charge == 0.0)
	await _frames(8)
	_check("F10 receptor corre sin soltar controles tras pasar",
		_state().actor(4).position.x > before.x + 0.15 and _count(Event.Kind.PASS) == 1
		and _count(Event.Kind.FOCUS_CHANGED) == 1)
	for pass_first: bool in [true, false]:
		await _begin("F10 pase prevalece sobre tiro simultáneo " + str(pass_first), _pass_preview())
		if pass_first:
			_key(KEY_J, true)
		_key(KEY_K, true)
		if not pass_first:
			_key(KEY_J, true)
		await _frames(3)
		_check("F10 orden de botones no convierte pase en tiro", _state().selected_actor_id == 4
			and _count(Event.Kind.PASS) == 1 and _count(Event.Kind.SHOT) == 0
			and _adapter().shot_charge == 0.0)
		_release_all()
		await _frames(2)
	await _begin("F10 carga no migra al receptor", _pass_preview())
	_key(KEY_K, true)
	await _frames(8)
	_check("F10 carga procede de entrada real", _adapter().shot_charge > 0.1)
	_key(KEY_J, true)
	await _frames(2)
	_key(KEY_J, false)
	await _wait_owner(4)
	_check("F10 B/K retenido no carga al nuevo dueño", _state().selected_actor_id == 4
		and _state().ball_owner_id == 4 and _adapter().shot_charge == 0.0
		and _count(Event.Kind.SHOT) == 0 and _count(Event.Kind.TACKLE) == 0)
	_key(KEY_K, false)
	await _frames(2)
	_check("F10 soltar carga cancelada no dispara", _count(Event.Kind.SHOT) == 0)
	for route: String in ["pausa", "desarrollo", "foco", "desconexión"]:
		await _begin("F10 barrera estricta tras " + route, _fan_setup())
		_key(KEY_LEFT, true)
		_tap(KEY_J)
		await _frames(2)
		_release_all()
		await _frames(2)
		if route == "desconexión":
			_axis(JOY_AXIS_LEFT_X, 1.0)
			_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		else:
			_key(KEY_D, true)
			_key(KEY_SHIFT, true)
		await _frames(6)
		match route:
			"pausa": _tap(KEY_ESCAPE)
			"desarrollo": _tap(KEY_F1)
			"foco": root.focus_exited.emit()
			"desconexión": Input.joy_connection_changed.emit(0, false)
		await _frames(3)
		_check("F10 " + route + " pausa al seleccionado vigente", _state().phase == Snapshot.Phase.PAUSED
			and _state().selected_actor_id == 8 and not _adapter().enabled)
		if route == "desarrollo":
			_tap(KEY_ESCAPE)
			await _frames(2)
		if route == "desconexión":
			Input.joy_connection_changed.emit(0, true)
		_tap(KEY_ESCAPE)
		await _frames(16)
		_check("F10 " + route + " no hereda movimiento hasta neutral", _state().selected_actor_id == 8
			and _state().phase == Snapshot.Phase.PLAYING and _commands[-1].move.is_zero_approx()
			and not _commands[-1].sprint and _planar_speed() < 0.02)
		_release_all()
		await _frames(3)
		_key(KEY_D, true)
		await _frames(5)
		_check("F10 " + route + " recupera el mismo atleta tras soltar", _commands[-1].actor_id == 8
			and _state().actor(8).velocity.x > 1.0)
		_release_all()


func _case_phases() -> void:
	var setup: Setup = _pass_preview()
	setup.ai_actor_ids = [0, 2]
	setup.actor_positions[3] = Vector3(18.5, 0, 8)
	setup.ball_position = Vector3(17, 0.12, 0)
	setup.ball_velocity = Vector3(7, 0, 0)
	await _begin("F11 gol conserva foco hasta saque", setup)
	_tap(KEY_J)
	await _frames(2)
	_check("F11 selecciona compañero antes del gol", _state().selected_actor_id == 4)
	await _wait_phase(Snapshot.Phase.GOAL_PAUSE, 90)
	_check("F11 gol no devuelve foco prematuramente a 0", _state().selected_actor_id == 4
		and _state().score == Vector2i(1, 0))
	_tap(KEY_F1)
	await _frames(2)
	var intent: Array[int] = [4]
	_check("F11 cambiar IA latente durante gol conserva foco y fase",
		_host.set_ai_actor_ids(intent) == OK and _state().selected_actor_id == 4
		and _state().resume_phase == Snapshot.Phase.GOAL_PAUSE and _state().ai_actor_ids.is_empty())
	var frozen: Array = _full_fingerprint(_state())
	await _frames(12)
	_check("F11 pausa de gol congela también selección", _full_fingerprint(_state()) == frozen)
	_tap(KEY_ESCAPE)
	await _frames(2)
	_tap(KEY_ESCAPE)
	await _wait_phase(Snapshot.Phase.PLAYING, 120)
	_check("F11 saque canónico restaura 0 e intención, no defaults", _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == [4] and _state().ai_actor_ids == [4]
		and _state().score == Vector2i(1, 0))
	setup = _pass_preview()
	setup.ball_position = Vector3(0, 0.12, 8)
	setup.ball_velocity = Vector3(0, 0, 3)
	await _begin("F11 fuera cede foco al sacador local", setup)
	_tap(KEY_J)
	await _frames(2)
	await _wait_phase(Snapshot.Phase.RESTART_PAUSE, 90)
	var restart_taker: int = _state().restart.taker_actor_id
	_check("F11 fuera selecciona al sacador HOME sin reset colectivo", _state().selected_actor_id == restart_taker
		and _state().restart.kind == GameplayTypes.RestartKind.KICK_IN and _state().restart.awarded_team_id == 0)
	_tap(KEY_ESCAPE)
	await _frames(2)
	frozen = _full_fingerprint(_state())
	await _frames(10)
	_check("F11 pausa de fuera conserva estado completo", _full_fingerprint(_state()) == frozen
		and _state().resume_phase == Snapshot.Phase.RESTART_PAUSE)
	_tap(KEY_ESCAPE)
	for frame: int in range(140):
		if _state().restart.stage == GameplayTypes.RestartStage.READY:
			break
		await _frames(1)
	_check("F11 fuera requiere colocación y READY antes del pase", _state().phase == Snapshot.Phase.RESTART_PAUSE
		and _state().restart.stage == GameplayTypes.RestartStage.READY and _state().selected_actor_id == restart_taker)
	_tap(KEY_J)
	await _frames(3)
	var restart_pass: Event = _last(Event.Kind.PASS, restart_taker)
	_check("F11 J libera físicamente la banda sin reactivar IA", _state().phase == Snapshot.Phase.PLAYING
		and _state().restart.stage == GameplayTypes.RestartStage.IN_PLAY and restart_pass != null
		and _state().selected_actor_id == (restart_pass.target_actor_id if restart_pass.target_actor_id >= 0 else restart_taker)
		and _state().ball_position.distance_to(_state().restart.spot) < 1.0
		and _state().ai_intent_actor_ids.is_empty() and _state().ai_actor_ids.is_empty())
	await _begin("F11 fin conserva seleccionado", _fan_setup(), 0.3)
	_key(KEY_LEFT, true)
	_tap(KEY_J)
	await _frames(2)
	_release_all()
	await _wait_phase(Snapshot.Phase.FINISHED, 45)
	_check("F11 fin no cambia identidad controlada", _state().selected_actor_id == 8
		and _control("PauseOverlay").visible and not _control("ResumeButton").visible)
	frozen = _full_fingerprint(_state())
	var commands: int = _commands.size()
	_tap(KEY_J)
	_tap(KEY_K)
	await _frames(4)
	_check("F11 resultado no acepta acciones del juego", _full_fingerprint(_state()) == frozen
		and _commands.size() == commands)
	_begin_control_negative("F11 comando tras FINISHED", ERR_UNAVAILABLE, 8)
	var command: Command = Command.new(8, _state().actor(8).last_command_sequence + 1)
	command.action = Command.Action.SWITCH_TEAMMATE
	_check("F11 autoridad tampoco acepta switch terminal", _authority.submit_human_command(command) == ERR_UNAVAILABLE)
	_end_control_negative()
	_authority.tuning.training_seconds = 120.0
	_check("F11 reiniciar conserva preview y el apagado", _host.restart_match() == OK
		and _state().selected_actor_id == 0 and _state().ai_intent_actor_ids.is_empty()
		and _state().mode == Setup.Mode.PREVIEW_5V5)
	var copy: Snapshot = _state()
	copy.selected_actor_id = 8
	copy.ai_intent_actor_ids.append(8)
	copy.ai_actor_ids.append(8)
	copy.actor(0).human_controlled = false
	_check("F11 snapshot no da autoridad a quien lo modifica", _state().selected_actor_id == 0
		and _state().actor(0).human_controlled and _state().ai_intent_actor_ids.is_empty())
	_check("F11 start null conserva micro con selección e intención canónicas", _host.start_match() == OK
		and _state().actors.size() == 4 and _state().selected_actor_id == 0
		and _state().ai_intent_actor_ids == [0, 1, 2, 3])


func _case_presentation() -> void:
	await _begin("F12 identidad visual estable", _fan_setup())
	var views: Array[int] = _view_ids()
	var identities: Array = _view_identities()
	_key(KEY_LEFT, true)
	_tap(KEY_J)
	await _frames(3)
	_key(KEY_LEFT, false)
	_check("F12 cambio no recrea vistas ni cambia dorsal/kit", _view_ids() == views
		and _view_identities() == identities)
	_assert_selected_presentation("F12 preview")
	_assert_frame("F12 después de cambiar a 8")
	var setup: Setup = _no_ball_setup()
	setup.actor_positions[0] = Vector3(15, 0, -7)
	setup.actor_positions[2] = Vector3(-18.5, 0, 8)
	setup.ball_position = Vector3(18, 0.12, -7)
	await _begin("F12 cámara micro entre extremos", setup)
	var previous: Vector3 = _camera().position
	var initial_focus: Vector3 = _camera().get("_focus")
	var start_tick: int = _state().tick
	var previous_frame: int = Engine.get_process_frames()
	var sampled_frames: int = 0
	var consecutive: bool = true
	var maximum_step: float = 0.0
	var minimum_right_dot: float = INF
	_tap(KEY_J)
	var stable: bool = true
	var ball_visible: bool = true
	# Una espera física puede incluir varios renders; el límite de salto es por imagen.
	for frame: int in 6000:
		await process_frame
		var current_frame: int = Engine.get_process_frames()
		consecutive = consecutive and current_frame == previous_frame + 1
		var step: float = _camera().position.distance_to(previous)
		var right_dot: float = _camera().global_basis.x.dot(Vector3.RIGHT)
		maximum_step = maxf(maximum_step, step)
		minimum_right_dot = minf(minimum_right_dot, right_dot)
		stable = stable and step < 1.0 and right_dot > 0.999
		ball_visible = ball_visible and _on_screen(_state().ball_position)
		previous = _camera().position
		previous_frame = current_frame
		sampled_frames += 1
		if _state().tick - start_tick >= 50:
			break
	var keeper_visible: bool = _on_screen(_state().actor(2).position) \
		and _on_screen(_state().actor(2).position + Vector3.UP * Tuning.ACTOR_HEIGHT)
	var focus_progress_x: float = initial_focus.x - (_camera().get("_focus") as Vector3).x
	_camera_motion = {"start_tick": start_tick, "end_tick": _state().tick,
		"sampled_frames": sampled_frames, "consecutive": consecutive, "maximum_step": maximum_step,
		"minimum_right_dot": minimum_right_dot, "ball_visible": ball_visible,
		"end_phase": _state().phase, "camera_mode": _camera().get_camera_state()["mode"],
		"selected_actor_id": _state().selected_actor_id, "keeper_visible": keeper_visible,
		"focus_progress_x": focus_progress_x}
	_check("F12 muestrea imágenes consecutivas durante los 50 ticks completos",
		consecutive and sampled_frames > 0 and _state().tick - start_tick >= 50)
	_check("F12 la transferencia sigue en juego y cámara broadcast",
		_state().phase == Snapshot.Phase.PLAYING and _camera().get_camera_state()["mode"] == "broadcast")
	_check("F12 cámara no gira ni salta al cambiar de extremo", stable and ball_visible)
	_check("F12 micro sigue al seleccionado y encuadra balón y silueta",
		_state().selected_actor_id == 2 and keeper_visible and focus_progress_x > 1.0)
	_assert_selected_presentation("F12 portero")
	await _test_preview_edges()


func _fan_setup() -> Setup:
	var setup: Setup = Setup.preview_5v5()
	setup.ai_actor_ids = []
	setup.actor_positions = {
		0: Vector3(0, 0, 0), 1: Vector3(12, 0, -7),
		2: Vector3(0, 0, 6), 3: Vector3(18.5, 0, 0),
		4: Vector3(0, 0, -6), 5: Vector3(14, 0, -4),
		6: Vector3(6, 0, 0), 7: Vector3(12, 0, 7),
		8: Vector3(-6, 0, 0), 9: Vector3(15, 0, 5),
	}
	setup.ball_position = Vector3(9, 0.12, 0)
	return setup


func _begin(label: String, setup: Setup, seconds: float = 120.0) -> void:
	_observed_events.clear()
	_submitted_samples.clear()
	await super._begin(label, setup, seconds)


func _wait_owner(id: int, limit: int = 150) -> void:
	for frame: int in limit:
		if _state().ball_owner_id == id:
			break
		await _frames(1)
	_check("recepción física esperada de %d" % id, _state().ball_owner_id == id)


func _wait_phase(phase: Snapshot.Phase, limit: int) -> void:
	for frame: int in limit:
		if _state().phase == phase:
			break
		await _frames(1)
	_check("fase autoritativa esperada " + Snapshot.Phase.keys()[phase], _state().phase == phase)


func _submit_negative_pass(target: int = -1) -> Error:
	var state: Snapshot = _state()
	var command: Command = Command.new(state.selected_actor_id,
		state.actor(state.selected_actor_id).last_command_sequence + 1)
	command.action = Command.Action.PASS
	command.target_actor_id = target
	return _authority.submit_human_command(command)


func _record_live_event(event: Event) -> void:
	_events.append(event)
	if event.kind in [Event.Kind.PASS, Event.Kind.FOCUS_CHANGED]:
		var state: Snapshot = _authority.get_snapshot()
		_observed_events.append({"event": event, "state": state})
		if event.kind == Event.Kind.FOCUS_CHANGED:
			_focus_evidence.append({"old_id": event.actor_id, "selected_actor_id": state.selected_actor_id,
				"target_id": event.target_actor_id, "reason": String(event.reason), "mode": state.mode,
				"tick": state.tick, "owner_id": state.ball_owner_id,
				"ai_intent_actor_ids": state.ai_intent_actor_ids, "ai_actor_ids": state.ai_actor_ids})


func _record_live_command(command: Command, result: Error) -> void:
	_commands.append(command)
	_submitted_samples.append({"actor_id": command.actor_id, "sequence": command.sequence,
		"tick": _authority.get_snapshot().tick, "result": result})


func _focus_snapshot() -> Snapshot:
	for index: int in range(_observed_events.size() - 1, -1, -1):
		var event: Event = _observed_events[index]["event"]
		if event.kind == Event.Kind.FOCUS_CHANGED:
			return _observed_events[index]["state"]
	return null


func _first_sample_after(state: Snapshot, actor_id: int) -> int:
	for sample: Dictionary in _submitted_samples:
		if sample["actor_id"] == actor_id and sample["tick"] >= state.tick and sample["result"] == OK:
			return int(sample["sequence"])
	return -1


func _begin_control_negative(label: String, code: Error, actor_id: int) -> void:
	_negative_case = label
	_negative_code = code
	_negative_actor = actor_id
	_remaining_errors = 0
	_remaining_refusals = 1


func _end_control_negative() -> void:
	_check("negativa exacta: " + _negative_case, _remaining_refusals == 0 and _remaining_errors == 0)
	_negative_case = ""
	_negative_code = OK
	_negative_actor = -1


func _record_refusal(id: int, code: Error, message: String) -> void:
	var item: Dictionary = {"id": id, "code": code, "message": message}
	_refusals.append(item)
	if not _negative_case.is_empty() and id == _negative_actor and code == _negative_code and _remaining_refusals > 0:
		_remaining_refusals -= 1
		var expected: Dictionary = item.duplicate()
		expected["case"] = _negative_case
		_expected_refusals.append(expected)
	else:
		_unexpected_refusals.append(item)


func _view_identities() -> Array:
	var result: Array = []
	for view: Node in _host.get_node("Athletes").get_children():
		result.append([view.get("actor_id"), view.get("dorsal"), view.get("kit_color")])
	return result


func _assert_selected_presentation(label: String) -> void:
	var state: Snapshot = _state()
	var humans: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.human_controlled:
			humans.append(actor.actor_id)
	_check(label + ": una marca humana autoritativa HOME", humans == [state.selected_actor_id]
		and state.actor(state.selected_actor_id).team_id == Snapshot.Team.HOME)
	_check(label + ": contexto HUD del seleccionado real", _label("ControlsContext").text.begins_with(
		"CON BALÓN" if state.ball_owner_id == state.selected_actor_id else "SIN BALÓN"))
	var caption: String = "CONTROL · ID %d\n%s LOCAL" % [state.selected_actor_id,
		"PORTERO" if state.actor(state.selected_actor_id).role == Snapshot.Role.KEEPER else "CAMPO"]
	_check(label + ": HUD identifica jugador y rol confirmados", _label("SelectedActor").is_visible_in_tree()
		and _label("SelectedActor").text == caption)
	var visible_markers: Array[int] = []
	for view: Node in _host.get_node("Athletes").get_children():
		var marker: Label3D = view.get("_selection_marker") as Label3D
		if marker != null and marker.is_visible_in_tree():
			visible_markers.append(int(view.get("actor_id")))
	_check(label + ": una sola marca de control visible en geometría real", visible_markers == [state.selected_actor_id])


func _on_screen(point: Vector3) -> bool:
	var normalized: Vector2 = _camera().unproject_position(point) / root.get_visible_rect().size
	return not _camera().is_position_behind(point) and normalized.x > 0.02 and normalized.x < 0.98 \
		and normalized.y > 0.16 and normalized.y < 0.84


func _report() -> void:
	if _report_printed:
		return
	var complete: bool = _completed_cases == CASES and _expect_exit and _exit_received
	_check("F01–F12 completos y salida real recibida", complete)
	_report_printed = true
	var failures: Array[String] = []
	for item: Dictionary in _checks:
		if not item["passed"]:
			failures.append(String(item["name"]))
	print("FUTSAL_PLAYER_CONTROL_TESTS ", JSON.stringify({
		"ok": failures.is_empty() and complete, "complete": complete,
		"passed": _checks.size() - failures.size(), "total": _checks.size(), "failures": failures,
		"cases_completed": _completed_cases, "source_script": _source_script,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"project_version": ProjectSettings.get_setting("application/config/version"),
		"input_schema_version": ProjectSettings.get_setting("futsal/preparation/input_schema_version"),
		"native_events": _native_events, "mouse_events": _mouse_events,
		"command_refusals": _refusals, "expected_command_refusals": _expected_refusals,
		"unexpected_command_refusals": _unexpected_refusals, "integration_errors": _errors,
		"unexpected_integration_errors": _unexpected_errors, "focus_changes": _focus_evidence,
		"camera_handoff_motion": _camera_motion,
		"headless": DisplayServer.get_name() == "headless", "engine": Engine.get_version_info()["string"],
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
	}))
