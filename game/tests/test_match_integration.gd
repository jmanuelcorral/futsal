extends SceneTree
## Prueba nativa del main de producción. No usa action_press ni autoridad simulada.
## --capture=res://match/validation.png permite inspeccionar un render real opcional.

const MatchHost = preload("res://match/match.gd")
const Simulation = preload("res://match/simulation/match_simulation.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Adapter = preload("res://match/presentation/input/match_input.gd")
const Camera = preload("res://match/presentation/camera/broadcast_camera.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const IntegrationRules = preload("res://match/simulation/match_rule_types.gd")
const GameplaySmoke = preload("res://diagnostics/gameplay_smoke.gd")

var _host: MatchHost
var _checks: Array[Dictionary] = []
var _events: Array[Event] = []
var _commands: Array[Command] = []
var _errors: Array[String] = []
var _refusals: Array[Dictionary] = []
var _started_ms: int = 0
var _report_printed: bool = false
var _expect_exit: bool = false
var _exit_received: bool = false
var _native_events: Dictionary = {"key": 0, "joy_button": 0, "joy_motion": 0}


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_ms > 120000 and not _report_printed:
		_check("watchdog: recorrido termina antes de 120 s reales", false)
		_report()
		quit(2)
	return false


func _finalize() -> void:
	if not _report_printed:
		_check("recorrido termina mediante la salida prevista", _expect_exit and _exit_received)
		_check("diagnósticos siguen siendo válidos hasta la salida", _diagnostics_ok())
		_report()
	if _failed():
		quit(1)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	_test_gameplay_output_paths()
	var original_bindings: Dictionary = _bindings()
	_check("identidad del laboratorio que conserva la regresión G1",
		ProjectSettings.get_setting("application/config/name") == "Futsal — Laboratorio 5v5"
		and ProjectSettings.get_setting("application/config/version") == "0.5.0-preview")
	_check("schema 3 conserva entrada contextual y flechas y añade L/X",
		ProjectSettings.get_setting("futsal/preparation/input_schema_version") == 3
		and InputMap.has_action("dribble"))
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	_check("main por defecto es el partido, no el bootstrap", scene_path == "res://match/match.tscn")
	var main_scene: PackedScene = load(scene_path) as PackedScene
	_host = main_scene.instantiate() as MatchHost if main_scene != null else null
	_check("main instancia el anfitrión real", _host != null)
	if _host == null:
		_report()
		quit(1)
		return
	var simulation: Simulation = _host.get_node("Simulation") as Simulation
	simulation.event_raised.connect(func(event: Event) -> void: _events.append(event))
	simulation.command_rejected.connect(func(id: int, code: Error, message: String) -> void:
		_refusals.append({"id": id, "code": code, "message": message}))
	_host.command_submitted.connect(func(command: Command, _result: Error) -> void: _commands.append(command))
	_host.integration_error.connect(func(_code: Error, message: String) -> void: _errors.append(message))
	_host.exit_requested.connect(_on_exit_requested)
	root.add_child(_host)
	current_scene = _host
	await _frames(6)
	_check("regresión G1 selecciona micro mediante start_match(null)", _host.start_match() == OK)
	await _frames(6)
	_test_main_contract()
	await _capture_if_requested()
	await _test_keyboard_movement()
	await _test_native_joypad()
	await _test_pass_and_return()
	await _test_charged_shot()
	await _test_context_and_cooldown()
	await _test_pause_and_modal()
	await _test_cancelled_charge()
	await _test_controller_disconnect()
	await _test_goal_out_result()
	await _test_camera()
	_check("InputMap conserva todos los eventos originales", _bindings() == original_bindings)
	_check("sin errores de integración de producción", _errors.is_empty())
	_check("ningún rechazo en el recorrido válido", _refusals.is_empty())
	_check("se ejercitaron objetos nativos de las tres familias", int(_native_events["key"]) > 30
		and int(_native_events["joy_button"]) > 15 and int(_native_events["joy_motion"]) > 15)
	if _failed():
		_report()
		quit(1)
		return
	await _test_exit()


func _test_gameplay_output_paths() -> void:
	var roots: Array[Array] = [
		["C:/repo/game", "C:/Godot/Godot.exe", false, "C:/repo/game"],
		["/work/game", "/opt/godot/Godot", false, "/work/game"],
		["", "C:\\bundle\\Futsal.exe", false, "C:/bundle"],
		["", "/opt/futsal/Futsal.x86_64", false, "/opt/futsal"],
		["", "/Applications/Futsal.app/Contents/MacOS/Futsal", true, "/Applications/Futsal.app"],
		["", "/opt/futsal/Futsal", true, "/opt/futsal"],
		["/work/game", "/Applications/Godot.app/Contents/MacOS/Godot", true, "/work/game"],
		["", "/Applications/Futsal.app/Contents/MacOS/../MacOS/Futsal", true, "/Applications/Futsal.app"],
		["", "/Applications/Futsal.app/Contents/./MacOS/Futsal", true, "/Applications/Futsal.app"],
		["", "/Applications/Futsal.APP/CONTENTS/MACOS/Futsal", true, "/Applications/Futsal.APP"],
		["", "\\Applications\\Futsal.app\\Contents\\MacOS\\..\\MacOS\\Futsal", true, "/Applications/Futsal.app"],
		["", "C:\\bundle\\bin\\..\\Futsal.exe", false, "C:/bundle"],
		["/work/shared/../game", "/opt/godot/Godot", false, "/work/game"],
	]
	for index: int in roots.size():
		var values: Array = roots[index]
		_check("G31 raiz fisica de editor o instalacion caso=%d" % index,
			GameplaySmoke.runtime_output_root(values[0], values[1], values[2]) == values[3])
	var paths: Array[Array] = [
		["/tmp/proof", "/opt/futsal", true],
		["/opt/futsal", "/opt/futsal", false],
		["/opt/futsal/captures", "/opt/futsal", false],
		["/opt/futsal-other", "/opt/futsal", true],
		["/tmp/../opt/futsal/captures", "/opt/futsal", false],
		["C:\\BUNDLE\\captures", "c:/bundle", false],
		["C:/bundle-other", "C:/bundle", true],
		["/Applications/Futsal.app/Contents/Resources", "/Applications/Futsal.app", false],
		["res://captures", "/work/game", false],
		["user://captures", "/work/game", false],
		["/tmp/proof", "", false],
		["/tmp/proof", "relative", false],
		["/tmp/proof", "/", false],
		["res:\\\\captures", "/work/game", false],
		["user:\\\\captures", "/work/game", false],
		["RES://captures", "/work/game", false],
		["UsEr:\\\\captures", "/work/game", false],
		["/tmp/proof", "res:\\\\game", false],
		["/tmp/proof", "USER://game", false],
		["/Applications/Futsal.app/Contents/MacOS/../Resources", "/Applications/Futsal.app", false],
		["/Applications/futsal.app/contents/Resources", "/Applications/Futsal.APP", false],
	]
	for index: int in paths.size():
		var values: Array = paths[index]
		_check("G31 contencion de salida portable caso=%d" % index,
			GameplaySmoke.output_is_outside_runtime(values[0], values[1]) == values[2])


func _test_main_contract() -> void:
	var state: Snapshot = _state()
	var restart_before: Array = _restart_fingerprint(state)
	var detached: Snapshot = state.copy()
	detached.restart.launch_contact_id += 1
	_check("huella de reanudación distingue launch_contact_id sin inferirlo del tick",
		detached.tick == state.tick and _restart_fingerprint(detached) != restart_before
		and _fingerprint(detached) != _fingerprint(state))
	_check("cambiar contacto en copia no muta snapshot ni autoridad",
		_restart_fingerprint(state) == restart_before and _restart_fingerprint(_state()) == restart_before)
	_check("setup nulo mantiene modo MICRO_1V1", state.mode == Setup.Mode.MICRO_1V1)
	_check("micro reiniciado selecciona 0 sin perder intención IA", state.selected_actor_id == 0
		and state.ai_intent_actor_ids == [0, 1, 2, 3] and state.ai_actor_ids == [1, 2, 3])
	_check("la autoridad del main es MatchSimulation/Jolt a 60 Hz", _host.get_simulation() is Simulation
		and Engine.physics_ticks_per_second == 60 and ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics")
	_check("micro explícito arranca sin menú diagnóstico", state.phase == Snapshot.Phase.PLAYING and state.tick > 0)
	_check("son cuatro atletas, dos porteros y un humano", state.actors.size() == 4
		and state.actors.filter(func(actor: Snapshot.ActorSnapshot) -> bool: return actor.human_controlled).size() == 1
		and state.actors.filter(func(actor: Snapshot.ActorSnapshot) -> bool: return actor.role == Snapshot.Role.KEEPER).size() == 2)
	_check("cuatro representaciones, no plantillas extra", _host.get_node("Athletes").get_child_count() == 4)
	_check("autoridad mantiene identidad global", _host.get_simulation().global_transform.is_equal_approx(Transform3D.IDENTITY))
	_check("input antes de autoridad y snapshots después del tick",
		_host.get_node("MatchInput").process_physics_priority < _host.get_simulation().process_physics_priority
		and _host.process_physics_priority > _host.get_simulation().process_physics_priority)
	for node_name: String in ["Arena", "Athletes", "BallView"]:
		_check("presentación sin colisiones duplicadas: " + node_name,
			_host.get_node(node_name).find_children("*", "CollisionObject3D", true, false).is_empty())
	var body: RigidBody3D = _host.get_simulation().get_node("Ball") as RigidBody3D
	_check("balón físico del main conserva CCD y mundo privado", body.continuous_cd
		and PhysicsServer3D.body_get_space(body.get_rid()) != _host.get_world_3d().space)
	var mesh: SphereMesh = _host.get_node("BallView/BallMesh").get("mesh") as SphereMesh
	_check("balón visible conserva radio físico de futsal", is_equal_approx(mesh.radius, Tuning.BALL_RADIUS))
	_check("pista y ambas porterías son visibles", _host.has_node("Arena/Court40x20")
		and _host.has_node("Arena/HomeGoal/Crossbar") and _host.has_node("Arena/AwayGoal/Net"))
	_check("HUD muestra reloj y marcador vivos", _label("Score").text == "0 – 0" and _label("Clock").text == "02:00")
	_check("contexto coincide con posesión humana", state.ball_owner_id == 0
		and _label("ControlsContext").text.begins_with("CON BALÓN"))
	_check("cámara de producción activa y perspectiva", _camera().current and _camera().projection == Camera3D.PROJECTION_PERSPECTIVE)
	_check("mapeo lateral mantiene ataque a derecha", _camera().screen_direction_to_court(Vector2.RIGHT).dot(Vector2.RIGHT) > 0.99)
	_check("presentación no pausa SceneTree global", not paused)
	for id: int in Simulation.ACTOR_IDS:
		var view: Node3D = _host.get_node("Athletes/Athlete%d" % id) as Node3D
		_check("atleta recibe tick/fase/posición del balón desde snapshots del host %d" % id,
			view.get("_context_valid") and view.get("_context_tick") >= 0
			and view.get("_context_tick") <= state.tick)
		var legs: Array = view.get("_legs")
		var arms: Array = view.get("_arms")
		var joints_meet: bool = true
		for side: int in 2:
			var thigh: Node3D = legs[side][0] as Node3D
			var shin: Node3D = legs[side][1] as Node3D
			var forearm: Node3D = arms[side][1] as Node3D
			var hand: Node3D = arms[side][2] as Node3D
			joints_meet = joints_meet and (thigh.global_transform * Vector3.UP).distance_to(shin.global_position) < 0.001
			joints_meet = joints_meet and (forearm.global_transform * Vector3.UP).distance_to(hand.global_position) < 0.001
		_check("extremos de huesos coinciden con articulaciones %d" % id, joints_meet)
		var projected: Vector2 = _camera().unproject_position(state.actor(id).position) / root.get_visible_rect().size
		_check("atleta %d visible en saque inicial" % id, projected.x > 0.015 and projected.x < 0.985
			and projected.y > 0.15 and projected.y < 0.8)


func _test_keyboard_movement() -> void:
	await _begin("teclado", _no_ball_setup())
	var origin: Vector3 = _state().actor(0).position
	_key(KEY_D, true)
	_check("tecla física device 0 llega al InputMap real", Input.is_action_pressed("move_right"))
	await _frames(18)
	_check("D desplaza a derecha por autoridad", _state().actor(0).position.x > origin.x + 0.9)
	_check("D produce velocidad sin comando fabricado", _state().actor(0).velocity.x > 5.0
		and _commands[-1].move.x > 0.99)
	var sequence: int = _state().actor(0).last_command_sequence
	_key(KEY_D, false)
	await _frames(14)
	_check("objeto de liberación separado frena movimiento", not Input.is_action_pressed("move_right")
		and _planar_speed() < 0.02)
	_check("secuencias humanas aumentan entre ticks", _state().actor(0).last_command_sequence > sequence)
	_key(KEY_D, true)
	_key(KEY_W, true)
	await _frames(18)
	_check("diagonales WASD normalizadas", is_equal_approx(_commands[-1].move.length(), 1.0)
		and _commands[-1].move.x > 0.6 and _commands[-1].move.y < -0.6)
	_check("diagonal no supera velocidad cardinal", absf(_planar_speed() - _host.get_simulation().tuning.move_speed) < 0.1)
	_key(KEY_SHIFT, true)
	await _frames(18)
	_check("Shift aplica sprint nativo", _commands[-1].sprint and absf(_planar_speed() - 8.0) < 0.1)
	_key(KEY_CTRL, true)
	await _frames(18)
	_check("Ctrl prevalece sobre Shift sin perder dirección", _commands[-1].close_control
		and _state().actor(0).close_control and absf(_planar_speed() - 3.5) < 0.1)
	_release_all()
	await _frames(14)
	_check("liberar teclado completo frena a cero", _planar_speed() < 0.02)


func _test_native_joypad() -> void:
	await _begin("stick Xbox", _no_ball_setup())
	var origin: Vector3 = _state().actor(0).position
	_axis(JOY_AXIS_LEFT_X, 0.12)
	await _frames(12)
	_check("zona muerta real impide drift", _state().actor(0).position.distance_to(origin) < 0.01
		and _commands[-1].move.is_zero_approx())
	_axis(JOY_AXIS_LEFT_X, 0.6)
	await _frames(18)
	_check("stick parcial conserva intensidad analógica", _commands[-1].move.x > 0.3 and _commands[-1].move.x < 0.8)
	_check("stick parcial mueve más lento que WASD", _planar_speed() > 2.0 and _planar_speed() < 4.5)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(18)
	_check("diagonal Xbox normaliza vector sin perder eje vertical", is_equal_approx(_commands[-1].move.length(), 1.0)
		and _commands[-1].move.y < -0.6)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(18)
	_check("RT axis 5 es sprint real", _commands[-1].sprint and absf(_planar_speed() - 8.0) < 0.1)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(18)
	_check("LT axis 4 domina RT como control cercano", _commands[-1].close_control and absf(_planar_speed() - 3.5) < 0.1)
	_release_all()
	await _frames(14)
	_check("ejes y gatillos neutros liberan intención", _planar_speed() < 0.02
		and not _commands[-1].sprint and not _commands[-1].close_control)
	_axis(JOY_AXIS_LEFT_X, -1.0, 3)
	await _frames(15)
	_check("binding device -1 admite otro mando real", _commands[-1].move.x < -0.99 and _state().actor(0).velocity.x < -4.0)
	_axis(JOY_AXIS_LEFT_X, 0.0, 3)
	await _frames(12)


func _test_pass_and_return() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = [2]
	setup.actor_positions[0] = Vector3(-12.0, 0, 0)
	setup.actor_forwards[0] = Vector2.LEFT
	setup.ball_position = Vector3(-12.55, 0.12, 0)
	await _begin("J / pase al portero", setup)
	_check("drill obtiene posesión mediante contacto", _state().ball_owner_id == 0)
	_key(KEY_J, true)
	await _frames(2)
	_key(KEY_J, false)
	_check("J ejecuta pase una sola vez", _count(Event.Kind.PASS, 0) == 1)
	var pass_event: Event = _last(Event.Kind.PASS, 0)
	_check("J dirige pase al compañero 2", pass_event != null and pass_event.target_actor_id == 2 and pass_event.velocity.x < -6.0)
	_check("HUD refleja pase emitido por autoridad", _label("EventText").text.begins_with("PASE"))
	_check("patada selecciona portero antes de recibir, sin regalar posesión",
		_state().selected_actor_id == 2 and _state().ball_owner_id == -1 and _state().ai_actor_ids.is_empty())
	for frame: int in 120:
		if _state().ball_owner_id == 2:
			break
		await _frames(1)
	_check("portero seleccionado recibe físicamente", _state().ball_owner_id == 2)
	await _frames(35)
	_check("portero controlado no devuelve por IA", _count(Event.Kind.PASS, 2) == 0
		and _state().selected_actor_id == 2 and _state().ball_owner_id == 2)
	_tap(KEY_J)
	await _frames(2)
	_check("J desde portero devuelve manualmente y selecciona campo",
		_count(Event.Kind.PASS, 2) == 1 and _state().selected_actor_id == 0
		and _last(Event.Kind.PASS, 2).target_actor_id == 0)
	for frame: int in 120:
		if _state().ball_owner_id == 0:
			break
		await _frames(1)
	_check("campo recibe devolución manual sin teleport", _state().ball_owner_id == 0)
	var keeper_ai: Setup = setup.copy()
	keeper_ai.ball_position = Vector3(-17.95, 0.12, 0)
	await _begin("portero IA fuera de foco", keeper_ai)
	for frame: int in 180:
		if _count(Event.Kind.PASS, 2) > 0 and _state().ball_owner_id == 0:
			break
		await _frames(1)
	_check("portero fuera de foco conserva devolución IA real", _count(Event.Kind.PASS, 2) >= 1
		and _state().selected_actor_id == 0 and _count(Event.Kind.FOCUS_CHANGED) == 0)
	_check("campo recibe devolución IA sin teleport", _state().ball_owner_id == 0)
	await _begin("A / pase Xbox", setup)
	_button(JOY_BUTTON_A, true)
	await _frames(2)
	_button(JOY_BUTTON_A, false)
	_check("Xbox A usa misma acción PASS y receptor", _count(Event.Kind.PASS, 0) == 1
		and _last(Event.Kind.PASS, 0).target_actor_id == 2)
	await _frames(16)
	_check("mantener/liberar A no duplica el pase", _count(Event.Kind.PASS, 0) == 1)
	await _begin("pase dirigido conserva stick", setup)
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	_button(JOY_BUTTON_A, true)
	await _frames(2)
	_button(JOY_BUTTON_A, false)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	pass_event = _last(Event.Kind.PASS, 0)
	_check("fuera del cono, pase no gira mágicamente al portero", pass_event != null
		and pass_event.target_actor_id == -1 and pass_event.velocity.z < -6.0 and absf(pass_event.velocity.x) < 1.0)


func _test_charged_shot() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	await _begin("K / carga al soltar", setup)
	_key(KEY_K, true)
	await _frames(12)
	var early_charge: float = (_control("ShotCharge") as ProgressBar).value
	_check("mantener K carga sin tirar", early_charge > 0.15 and early_charge < 0.6 and _count(Event.Kind.SHOT, 0) == 0)
	_check("barra real de carga es visible", _control("ChargePanel").visible)
	_key(KEY_K, true, true)
	_key(KEY_K, true, true)
	await _frames(8)
	_check("eco nativo no reinicia la carga", (_control("ShotCharge") as ProgressBar).value > early_charge)
	_key(KEY_K, false)
	await _frames(2)
	var shot: Event = _last(Event.Kind.SHOT, 0)
	_check("soltar K ejecuta exactamente un SHOT", _count(Event.Kind.SHOT, 0) == 1)
	_check("potencia procede del tiempo mantenido", shot != null and shot.shot_charge > 0.3 and shot.shot_charge < 0.7)
	_check("balón físico sale hacia portería rival", shot != null and shot.velocity.x > 13.0 and _state().ball_velocity.x > 10.0)
	_check("soltar oculta carga y cambia contexto", not _control("ChargePanel").visible
		and _label("ShootHint").text == "Robo de pie")
	await _begin("B / carga Xbox acotada", setup)
	_button(JOY_BUTTON_B, true)
	await _frames(65)
	_check("B carga a 1 sin disparo automático", is_equal_approx((_host.get_node("MatchInput") as Adapter).shot_charge, 1.0)
		and _count(Event.Kind.SHOT, 0) == 0)
	_button(JOY_BUTTON_B, false)
	await _frames(2)
	shot = _last(Event.Kind.SHOT, 0)
	_check("liberación Xbox B dispara carga máxima una vez", shot != null and is_equal_approx(shot.shot_charge, 1.0)
		and _count(Event.Kind.SHOT, 0) == 1)
	await _begin("pulsación corta entre ticks", setup)
	_key(KEY_K, true)
	_key(KEY_K, false)
	await _frames(2)
	_check("pulsar/soltar antes de un tick no pierde la acción", _count(Event.Kind.SHOT, 0) == 1)


func _test_context_and_cooldown() -> void:
	await _begin("K defensivo", _no_ball_setup())
	_key(KEY_K, true)
	await _frames(2)
	_check("K sin posesión es TACKLE, nunca SHOT", _count(Event.Kind.TACKLE, 0) == 1 and _count(Event.Kind.SHOT, 0) == 0)
	await _frames(18)
	_check("mantener robo no repite acciones ni barra", _count(Event.Kind.TACKLE, 0) == 1 and not _control("ChargePanel").visible)
	_key(KEY_K, false)
	_key(KEY_D, true)
	for attempt: int in 4:
		_key(KEY_K, true)
		_key(KEY_K, false)
		await _frames(1)
	_check("cooldown contextual no borra movimiento", _commands[-1].move.x > 0.99 and _state().actor(0).velocity.x > 1.0)
	_check("cooldown normal no se trata como error del motor", _errors.is_empty())
	_release_all()
	await _begin("B defensivo", _no_ball_setup())
	_button(JOY_BUTTON_B, true)
	await _frames(2)
	_button(JOY_BUTTON_B, false)
	_check("Xbox B defensivo usa el mismo TACKLE", _count(Event.Kind.TACKLE, 0) == 1 and _count(Event.Kind.SHOT, 0) == 0)
	_button(JOY_BUTTON_A, true)
	_axis(JOY_AXIS_LEFT_X, -1.0)
	await _frames(12)
	_check("A sin balón cambia al portero y conserva stick, no contiene",
		_state().selected_actor_id == 2 and not _commands[-1].close_control
		and _commands[-1].move.x < -0.99 and _count(Event.Kind.PASS) == 0
		and _count(Event.Kind.FOCUS_CHANGED) == 1)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(12)
	_check("LT conserva contención manual sin regalar posesión", _commands[-1].close_control
		and _state().ball_owner_id != _state().selected_actor_id and _planar_speed() <= 3.51)
	_release_all()


func _test_pause_and_modal() -> void:
	var setup: Setup = _no_ball_setup()
	setup.ball_position = Vector3(0, 1.4, 4)
	setup.ball_velocity = Vector3(6, 1.0, -1)
	setup.ball_angular_velocity = Vector3(5, 15, 20)
	await _begin("Esc pausa vuelo real", setup)
	_key(KEY_D, true)
	await _frames(3)
	_tap(KEY_ESCAPE)
	await _frames(2)
	var frozen: Snapshot = _state()
	var frozen_commands: int = _commands.size()
	var body: RigidBody3D = _host.get_simulation().get_node("Ball") as RigidBody3D
	var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_check("Esc llega a HUD y pausa autoridad", frozen.phase == Snapshot.Phase.PAUSED and _control("PauseOverlay").visible)
	await _frames(30)
	_check("pausa congela reloj, ticks y estados completos", _fingerprint(frozen) == _fingerprint(_state()))
	_check("pausa congela cuerpo Jolt, no solo snapshot", physical.is_equal_approx(
		PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)))
	_check("host no envía comandos al pausar", _commands.size() == frozen_commands and not paused)
	_tap(KEY_ESCAPE)
	await _frames(14)
	_check("Esc reanuda una sola vez sin doble toggle", _state().phase == Snapshot.Phase.PLAYING and not _control("PauseOverlay").visible)
	_check("reanudar restaura vuelo y reloj", _state().ball_position.distance_to(frozen.ball_position) > 0.15
		and _state().seconds_remaining < frozen.seconds_remaining)
	_check("movimiento retenido no se hereda sin soltar", _planar_speed() < 0.02
		and _label("EventText").text == "Suelta los controles para continuar")
	_key(KEY_D, false)
	await _frames(2)
	_key(KEY_D, true)
	await _frames(6)
	_check("una pulsación nueva recupera movimiento tras pausa", _state().actor(0).velocity.x > 1.0)
	_key(KEY_D, false)
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _frames(2)
	_check("Start Xbox pausa por señal HUD existente", _state().phase == Snapshot.Phase.PAUSED)
	_button(JOY_BUTTON_A, true)
	await _frames(3)
	_check("A modal continúa sin convertirse en pase", _state().phase == Snapshot.Phase.PLAYING and _count(Event.Kind.PASS, 0) == 0)
	_button(JOY_BUTTON_A, false)
	_button(JOY_BUTTON_START, true)
	_button(JOY_BUTTON_START, false)
	await _frames(2)
	_button(JOY_BUTTON_B, true)
	await _frames(3)
	_check("B modal continúa sin convertirse en robo", _state().phase == Snapshot.Phase.PLAYING and _count(Event.Kind.TACKLE, 0) == 0)
	_button(JOY_BUTTON_B, false)
	_tap(KEY_ESCAPE)
	await _frames(2)
	_navigate_hud("RestartButton")
	_tap(KEY_ENTER)
	await _frames(4)
	_check("reinicio desde menú restablece reloj y marcador", _state().phase == Snapshot.Phase.PLAYING
		and _state().score == Vector2i.ZERO and _state().seconds_remaining > 119.7)
	_check("reinicio retira modal y carga", not _control("PauseOverlay").visible and not _control("ChargePanel").visible)
	_check("reinicio conserva el setup del drill", _state().actor(0).spawn_position == setup.actor_positions[0])


func _test_cancelled_charge() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	await _begin("carga cancelada por pausa", setup)
	_key(KEY_K, true)
	await _frames(8)
	_tap(KEY_ESCAPE)
	await _frames(2)
	_check("pausa limpia carga retenida", not _control("ChargePanel").visible)
	_key(KEY_K, false)
	_tap(KEY_ESCAPE)
	await _frames(4)
	_check("soltar durante pausa no dispara al continuar", _count(Event.Kind.SHOT, 0) == 0)
	await _begin("tiro aceptado no queda pendiente al pausar", setup)
	_key(KEY_K, true)
	await _frames(8)
	_key(KEY_K, false)
	await _frames(1)
	_tap(KEY_ESCAPE)
	await _frames(2)
	var shots_before_resume: int = _count(Event.Kind.SHOT, 0)
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check("acción aceptada se resuelve antes de pausa, no al reanudar", _count(Event.Kind.SHOT, 0) == shots_before_resume)
	await _begin("carga cancelada por foco", setup)
	_key(KEY_K, true)
	await _frames(8)
	_host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check("pérdida de foco pausa y limpia carga", _state().phase == Snapshot.Phase.PAUSED and not _control("ChargePanel").visible)
	_key(KEY_K, false)
	_host.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames(2)
	_check("recuperar foco no reanuda por sorpresa", _state().phase == Snapshot.Phase.PAUSED)
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check("carga anterior al cambio de ventana queda cancelada", _count(Event.Kind.SHOT, 0) == 0)
	_key(KEY_K, true)
	await _frames(6)
	root.focus_exited.emit()
	await _frames(2)
	_check("señal de foco de Window también pausa y cancela carga", _state().phase == Snapshot.Phase.PAUSED
		and not _control("ChargePanel").visible)
	_key(KEY_K, false)
	_tap(KEY_ESCAPE)
	await _frames(3)
	_check("Window focus_exited no deja un tiro pendiente", _count(Event.Kind.SHOT, 0) == 0)
	await _begin("carga cancelada por reinicio", setup)
	_button(JOY_BUTTON_B, true)
	await _frames(8)
	_tap(KEY_ESCAPE)
	await _frames(2)
	_navigate_hud("RestartButton")
	_button(JOY_BUTTON_A, true)
	await _frames(3)
	_button(JOY_BUTTON_A, false)
	_button(JOY_BUTTON_B, false)
	await _frames(4)
	_check("reinicio no hereda B cargado ni A del menú", _state().phase == Snapshot.Phase.PLAYING
		and _count(Event.Kind.SHOT, 0) == 0 and _count(Event.Kind.PASS, 0) == 0 and not _control("ChargePanel").visible)
	await _begin("pérdida de posesión cancela carga", setup)
	_key(KEY_K, true)
	await _frames(5)
	_key(KEY_A, true)
	_key(KEY_SHIFT, true)
	var lost: bool = false
	for frame: int in 55:
		await _frames(1)
		if _state().ball_owner_id != 0:
			lost = true
			break
	_check("escenario pierde posesión por física real", lost)
	await _frames(2)
	_check("perder balón limpia carga sin cambiar a robo retenido", not _control("ChargePanel").visible
		and _count(Event.Kind.TACKLE, 0) == 0)
	_release_all()
	await _frames(4)
	_check("soltar tras perder balón no fabrica tiro", _count(Event.Kind.SHOT, 0) == 0)


func _test_goal_out_result() -> void:
	var setup: Setup = _goal_setup(1.0)
	setup.actor_positions[0] = Vector3(17.2, 0, -0.5)
	setup.ball_position = Vector3(17.75, 0.12, -0.5)
	setup.ball_velocity = Vector3.ZERO
	await _begin("gol desde tiro humano real", setup)
	_key(KEY_K, true)
	await _frames(14)
	_key(KEY_K, false)
	for frame: int in 30:
		if _state().phase == Snapshot.Phase.GOAL_PAUSE:
			break
		await _frames(1)
	_check("tiro con teclado cruza portería y puntúa", _state().score == Vector2i(1, 0) and _count(Event.Kind.GOAL) == 1)
	_check("score y aviso consumen gol autoritativo", _label("Score").text == "1 – 0" and _label("EventText").text.begins_with("GOL"))
	_check("gol bloquea acciones y limpia carga", _state().phase == Snapshot.Phase.GOAL_PAUSE and not _control("ChargePanel").visible)
	_tap(KEY_ESCAPE)
	await _frames(2)
	var frozen: Snapshot = _state()
	_check("gol también admite pausa explícita", frozen.phase == Snapshot.Phase.PAUSED and frozen.resume_phase == Snapshot.Phase.GOAL_PAUSE)
	await _frames(12)
	_check("pausa durante red congela fase y vuelo", _fingerprint(frozen) == _fingerprint(_state()))
	_key(KEY_K, true)
	_key(KEY_K, false)
	_tap(KEY_ESCAPE)
	await _frames(95)
	_check("saque conserva un solo gol y reanuda", _state().score == Vector2i(1, 0)
		and _state().phase == Snapshot.Phase.PLAYING and _count(Event.Kind.GOAL) == 1)
	_check("no arrastra disparo pulsado en pausa del gol", _count(Event.Kind.SHOT, 0) == 1)
	_check("teleport de saque no interpola atletas a través de pista",
		(_host.get_node("Athletes/Athlete0") as Node3D).position.distance_to(_state().actor(0).position) < 0.2)
	await _begin("gol de visita y resultado", _goal_setup(-1.0), 0.3)
	for frame: int in 150:
		if _state().phase == Snapshot.Phase.FINISHED:
			break
		await _frames(1)
	_check("portería opuesta cuenta a visita", _state().score == Vector2i(0, 1) and _label("Score").text == "0 – 1")
	_check("tiempo final procede solo de autoridad", _state().phase == Snapshot.Phase.FINISHED and _count(Event.Kind.END) == 1)
	_check("resultado real sin botón continuar", _control("PauseOverlay").visible
		and not _control("ResumeButton").visible and _label("ModalTitle").text == "FIN DEL ENTRENAMIENTO")
	_check("resultado muestra score recibido y cero reloj", _label("ModalDetail").text.contains("LOCAL 0 – 1 VISITA")
		and _label("Clock").text == "00:00")
	frozen = _state()
	var command_count: int = _commands.size()
	_tap(KEY_ESCAPE)
	await _frames(12)
	_check("Esc en resultado no reanuda partido terminado", _fingerprint(frozen) == _fingerprint(_state())
		and _commands.size() == command_count)
	_button(JOY_BUTTON_A, true)
	await _frames(3)
	_button(JOY_BUTTON_A, false)
	await _frames(2)
	_check("A en resultado reinicia partido limpio", _state().phase == Snapshot.Phase.PLAYING
		and _state().score == Vector2i.ZERO and not _control("PauseOverlay").visible)
	var outside: Setup = _no_ball_setup()
	outside.ball_position = Vector3(0, 0.12, 9.8)
	outside.ball_velocity = Vector3(0, 0, 6)
	await _begin("fuera físico y saque de banda reglado", outside)
	for frame: int in 15:
		if _state().phase == Snapshot.Phase.RESTART_PAUSE:
			break
		await _frames(1)
	_check("fuera usa fase física de reposición", _state().phase == Snapshot.Phase.RESTART_PAUSE and _state().score == Vector2i.ZERO)
	_check("HUD de reanudación consume un saque de banda real", _state().restart.kind == IntegrationRules.RestartKind.KICK_IN
		and _control("RestartPanel").visible and _label("RestartTitle").text.to_lower().contains("banda"))
	var stopped_clock: float = _state().seconds_remaining
	_key(KEY_K, true)
	await _frames(8)
	_key(KEY_K, false)
	_check("fuera detiene reloj e input", is_equal_approx(_state().seconds_remaining, stopped_clock)
		and _count(Event.Kind.TACKLE, 0) == 0)
	for frame: int in 90:
		if _state().restart.stage == IntegrationRules.RestartStage.READY:
			break
		await _frames(1)
	var ready: Snapshot = _state()
	_check("banda prepara al menos 60 ticks, sin reset antiguo a centro", ready.phase == Snapshot.Phase.RESTART_PAUSE
		and ready.restart.stage == IntegrationRules.RestartStage.READY and ready.restart.ready_tick >= 60
		and absf(ready.restart.spot.z) > 9.5 and absf(ready.restart.spot.x) < 0.5
		and ready.restart.deadline_tick == ready.restart.ready_tick + 240)
	_check("banda restablece contexto legal sin acción retenida", ready.human_control_context in [
		IntegrationRules.ControlContext.RESTART_AIM, IntegrationRules.ControlContext.RESTART_DEFEND]
		and _count(Event.Kind.SHOT, 0) == 0 and _count(Event.Kind.TACKLE, 0) == 0
		and is_equal_approx(ready.seconds_remaining, stopped_clock))


func _test_camera() -> void:
	var positions: Array[Vector3] = [
		Vector3(0, 0.12, 0), Vector3(-19, 0.12, -9), Vector3(19, 0.12, 9),
		Vector3(-19, 0.12, 9), Vector3(19, 0.12, -9), Vector3(0, 3, 0),
	]
	for index: int in positions.size():
		var setup: Setup = _no_ball_setup()
		setup.ball_position = positions[index]
		await _begin("encuadre %d" % index, setup)
		var state: Snapshot = _state()
		var camera: Camera = _camera()
		var pixel: Vector2 = camera.unproject_position(state.ball_position)
		var viewport_size: Vector2 = root.get_visible_rect().size
		var normalized: Vector2 = pixel / viewport_size
		_check("balón dentro de zona central segura %d" % index,
			not camera.is_position_behind(state.ball_position) and normalized.x > 0.3
			and normalized.x < 0.7 and normalized.y > 0.25 and normalized.y < 0.75)
		var diameter: float = camera.unproject_position(state.ball_position + camera.global_basis.x * Tuning.BALL_RADIUS).distance_to(
			camera.unproject_position(state.ball_position - camera.global_basis.x * Tuning.BALL_RADIUS))
		_check("diámetro proyectado >=8 px a 1080p en fixture %d" % index, diameter >= 8.0)
		var selected: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
		var feet: Vector2 = camera.unproject_position(selected.position) / viewport_size
		var head: Vector2 = camera.unproject_position(selected.position + Vector3.UP * Tuning.ACTOR_HEIGHT) / viewport_size
		_check("seleccionado completo visible junto al balón en fixture %d" % index,
			feet.x > 0.02 and feet.x < 0.98 and feet.y > 0.16 and feet.y < 0.84
			and head.x > 0.02 and head.x < 0.98 and head.y > 0.16 and head.y < 0.84)
		_check("roll nulo y perspectiva lateral estable %d" % index, absf(camera.global_basis.x.y) < 0.001
			and camera.position.y > 12.0 and camera.position.z > state.ball_position.z + 16.0)
	var flight: Setup = _no_ball_setup()
	flight.ball_position = Vector3(-8, 0.12, -3)
	flight.ball_velocity = Vector3(24, 0, 4)
	await _begin("seguimiento rápido", flight)
	var visible: bool = true
	var previous_camera: Vector3 = _camera().position
	var stable: bool = true
	for frame: int in 35:
		await _frames(1)
		var pixel: Vector2 = _camera().unproject_position(_state().ball_position) / root.get_visible_rect().size
		visible = visible and pixel.x > 0.15 and pixel.x < 0.85 and pixel.y > 0.2 and pixel.y < 0.8
		stable = stable and _camera().position.distance_to(previous_camera) < 1.0
		previous_camera = _camera().position
	_check("seguimiento de balón rápido mantiene encuadre seguro", visible)
	_check("cámara no salta durante vuelo continuo", stable)


func _test_controller_disconnect() -> void:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	await _begin("desconexión del mando activo", setup)
	_button(JOY_BUTTON_B, true, 0)
	await _frames(8)
	var adapter: Adapter = _host.get_node("MatchInput") as Adapter
	_check("eventos de mando identifican dispositivo activo y cargan tiro",
		adapter.active_joypad == 0 and adapter.shot_charge > 0.0)
	var charge: float = adapter.shot_charge
	Input.joy_connection_changed.emit(1, false)
	await _frames(2)
	_check("desconectar otro mando conserva partido y carga",
		_state().phase == Snapshot.Phase.PLAYING and adapter.shot_charge > charge)
	Input.joy_connection_changed.emit(0, true)
	await _frames(2)
	_check("conectar el mando activo no pausa el partido", _state().phase == Snapshot.Phase.PLAYING)
	Input.joy_connection_changed.emit(0, false)
	await _frames(2)
	_check("desconexión activa llega al host, pausa y cancela carga",
		_state().phase == Snapshot.Phase.PAUSED and _control("PauseOverlay").visible
		and not _control("ChargePanel").visible and is_zero_approx(adapter.shot_charge))
	var frozen: Snapshot = _state()
	await _frames(12)
	_check("desconexión mantiene física y reloj congelados", _fingerprint(frozen) == _fingerprint(_state()))
	Input.joy_connection_changed.emit(0, true)
	await _frames(2)
	_check("reconectar no reanuda sin intención del jugador", _state().phase == Snapshot.Phase.PAUSED)
	_button(JOY_BUTTON_B, false, 0)
	_button(JOY_BUTTON_START, true, 0)
	_button(JOY_BUTTON_START, false, 0)
	await _frames(5)
	_check("Start reanuda sin disparar la carga cancelada",
		_state().phase == Snapshot.Phase.PLAYING and _count(Event.Kind.SHOT, 0) == 0)
	_key(KEY_D, true)
	await _frames(3)
	Input.joy_connection_changed.emit(0, false)
	await _frames(2)
	_check("desconexión del mando anterior no pausa control por teclado",
		adapter.active_joypad == -1 and _state().phase == Snapshot.Phase.PLAYING)
	_release_all()


func _test_exit() -> void:
	await _begin("salida desde modal real", _no_ball_setup())
	_tap(KEY_ESCAPE)
	await _frames(2)
	_navigate_hud("QuitButton")
	_check("navegación alcanza Salir en HUD real", root.gui_get_focus_owner() == _control("QuitButton"))
	_expect_exit = true
	_button(JOY_BUTTON_A, true)
	for frame: int in 15:
		await _frames(1)
	_check("Salir debe terminar el proceso", false)
	_report()
	quit(1)


func _on_exit_requested() -> void:
	_exit_received = true
	_check("Salir del HUD llega a quit_match de producción", _expect_exit)
	_check("salida desactiva recogida de órdenes", not (_host.get_node("MatchInput") as Adapter).enabled)


func _navigate_hud(node_name: String) -> void:
	for attempt: int in 8:
		if root.gui_get_focus_owner() == _control(node_name):
			return
		_tap(KEY_DOWN)


func _capture_if_requested() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			if DisplayServer.get_name() == "headless":
				_check("captura requiere renderer real", false)
				return
			await RenderingServer.frame_post_draw
			var target: String = argument.trim_prefix("--capture=")
			var error: Error = root.get_texture().get_image().save_png(target)
			_check("captura real guardada sin retoque", error == OK)
			print("FUTSAL_MATCH_CAPTURE ", target, " renderer=", RenderingServer.get_current_rendering_method(),
				" gpu=", RenderingServer.get_video_adapter_name())


func _begin(label: String, setup: Setup, seconds: float = 120.0) -> void:
	_release_all()
	await _frames(2)
	_events.clear()
	_commands.clear()
	_host.get_simulation().tuning.training_seconds = seconds
	_check("start real: " + label, _host.start_match(setup) == OK)
	await _frames(5)


func _no_ball_setup() -> Setup:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	setup.ball_position = Vector3(0, 0.12, 6)
	return setup


func _goal_setup(end: float) -> Setup:
	var setup: Setup = Setup.new()
	setup.ai_actor_ids = []
	setup.actor_positions = {
		0: Vector3(-8, 0, -8), 1: Vector3(8, 0, -8),
		2: Vector3(-18.5, 0, 8), 3: Vector3(18.5, 0, 8),
	}
	setup.ball_position = Vector3(end * 19.2, 0.12, 0)
	setup.ball_velocity = Vector3(end * 12, 0, 0)
	return setup


func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.device = 0
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	_native_events["key"] += 1
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _button(button: JoyButton, pressed: bool, device: int = 0) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	_native_events["joy_button"] += 1
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axis(axis: JoyAxis, value: float, device: int = 0) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	_native_events["joy_motion"] += 1
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_all() -> void:
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
			KEY_SHIFT, KEY_CTRL, KEY_J, KEY_K, KEY_L, KEY_ESCAPE, KEY_F1]:
		_key(key, false)
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_START]:
		_button(button, false)
	for axis: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		_axis(axis, 0.0)
	_axis(JOY_AXIS_LEFT_X, 0.0, 3)
	_axis(JOY_AXIS_LEFT_Y, 0.0, 3)


func _state() -> Snapshot:
	return _host.get_snapshot()


func _camera() -> Camera:
	return _host.get_node("BroadcastCamera") as Camera


func _label(node_name: String) -> Label:
	return _host.get_node("MatchHUD").get_node("%" + node_name) as Label


func _control(node_name: String) -> Control:
	return _host.get_node("MatchHUD").get_node("%" + node_name) as Control


func _planar_speed() -> float:
	var velocity: Vector3 = _state().actor(_state().selected_actor_id).velocity
	return Vector2(velocity.x, velocity.z).length()


func _count(kind: Event.Kind, actor_id: int = -1) -> int:
	return _events.filter(func(event: Event) -> bool:
		return event.kind == kind and (actor_id == -1 or event.actor_id == actor_id)).size()


func _last(kind: Event.Kind, actor_id: int) -> Event:
	for index: int in range(_events.size() - 1, -1, -1):
		if _events[index].kind == kind and _events[index].actor_id == actor_id:
			return _events[index]
	return null


func _bindings() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(var_to_str(event))
		result[action] = events
	return result


func _fingerprint(state: Snapshot) -> Array:
	var result: Array = [state.tick, state.phase, state.resume_phase, state.score, state.seconds_remaining,
		state.phase_seconds_remaining, state.ball_position, state.ball_velocity, state.ball_rotation,
		state.ball_angular_velocity, state.ball_owner_id, state.last_touch_actor_id, state.selected_actor_id,
		state.human_control_context, state.human_allowed_actions.duplicate(), state.selected_can_move,
		state.accumulated_fouls, state.last_touch_tick, state.last_pass_actor_id, state.last_pass_target_actor_id,
		state.last_pass_tick, state.period_state, state.extended_restart_id, state.extended_kick_event_id,
		state.training_exercise, _restart_fingerprint(state)]
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.position, actor.velocity, actor.forward, actor.action_cooldown,
			actor.last_command_sequence, actor.last_command_tick, actor.close_control, actor.human_controlled,
			actor.ball_contact_reachable, actor.ball_in_hands, actor.gesture_kind, actor.gesture_started_tick,
			actor.gesture_duration_ticks, actor.gesture_direction, actor.gesture_contact_position])
	return result


func _restart_fingerprint(state: Snapshot) -> Array:
	var restart: IntegrationRules.RestartState = state.restart
	return [restart.id, restart.kind, restart.stage, restart.awarded_team_id, restart.taker_actor_id,
		restart.spot, restart.offence_spot, restart.border, restart.spot_choice, restart.has_spot_choice,
		restart.stage_started_tick, restart.placement_end_tick, restart.ready_tick, restart.deadline_tick,
		restart.minimum_opponent_distance, restart.direct_opponent_goal_allowed,
		restart.requires_direct_shot, restart.other_actor_touched, restart.launch_contact_id]


func _check(label: String, passed: bool) -> void:
	_checks.append({"name": label, "passed": passed})
	if not passed:
		print("FAIL ", label)


func _failed() -> bool:
	return _checks.any(func(item: Dictionary) -> bool: return not bool(item["passed"]))


func _diagnostics_ok() -> bool:
	return _errors.is_empty() and _refusals.is_empty()


func _report() -> void:
	if _report_printed:
		return
	_report_printed = true
	var failures: Array[String] = []
	for item: Dictionary in _checks:
		if not bool(item["passed"]):
			failures.append(String(item["name"]))
	print("FUTSAL_MATCH_INTEGRATION_TESTS ", JSON.stringify({
		"ok": failures.is_empty(), "passed": _checks.size() - failures.size(), "total": _checks.size(),
		"failures": failures, "integration_errors": _errors, "command_refusals": _refusals,
		"native_events": _native_events, "engine": Engine.get_version_info()["string"],
		"headless": DisplayServer.get_name() == "headless", "physics_hz": Engine.physics_ticks_per_second,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
	}))
