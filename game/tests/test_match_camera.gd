extends "res://tests/test_match_preview_integration.gd"
## Cámara de producción en la escena real y trazas nativas tick a tick.
## Las trayectorias controladas usan snapshots separados: no alteran el simulador.

const Launch = preload("res://match/simulation/match_launch.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const CORNERS: Array[Setup.TrainingExercise] = [
	Setup.TrainingExercise.CORNER_POS_X_NEG_Z, Setup.TrainingExercise.CORNER_POS_X_POS_Z,
	Setup.TrainingExercise.CORNER_NEG_X_NEG_Z, Setup.TrainingExercise.CORNER_NEG_X_POS_Z,
]

var _completed_cases: Array[String] = []
var _suite_complete: bool = false
var _camera_evidence: Array[Dictionary] = []
var _launch_requests: Array[Dictionary] = []
var _athlete_presentations: Array[Dictionary] = []
var _transition_evidence: Array[Dictionary] = []
var _trace_coverage: Dictionary[String, Dictionary] = {}
var _legacy_counterexample_checked: bool = false


func _run() -> void:
	if not await _load_actual_main():
		_report()
		quit(1)
		return
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		await _test_broadcast_projection(mode)
		await _test_four_corners(mode)
		await _test_corner_lifecycle(mode)
		await _test_opponent_corner(mode)
		await _test_corner_expiry_reset(mode)
	_suite_complete = true
	_check("diagnósticos nativos sin rechazo inesperado", _diagnostics_ok())
	if _failed():
		_report()
		quit(1)
		return
	await _test_exit()


func _test_broadcast_projection(mode: Setup.Mode) -> void:
	var case_id: String = "broadcast-framing/%d" % mode
	if not await _catalog(mode, Setup.TrainingExercise.FREE_PLAY, case_id):
		return
	var original: Snapshot = _state()
	var fingerprint: Array = _full_fingerprint(original)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var camera: Camera = Camera.new()
	viewport.add_child(camera)
	var offset: Vector3 = Camera.PREVIEW_OFFSET if mode == Setup.Mode.PREVIEW_5V5 else Camera.OFFSET
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var state: Snapshot = original.copy()
			state.ball_position = Vector3(end * 19.85, Tuning.BALL_RADIUS, side * 8.0)
			state.ball_velocity = Vector3.ZERO
			var far_actor: int = 4 if mode == Setup.Mode.PREVIEW_5V5 else 0
			state.actor(far_actor).position = Vector3(-end * 18.0, 0.0, side * 7.0)
			for selected: int in [0, 2]:
				state.selected_actor_id = selected
				for actor: Snapshot.ActorSnapshot in state.actors:
					actor.human_controlled = actor.actor_id == selected
				camera.reset_context()
				camera.follow(state, state.ball_position, 0.0, true)
				var label: String = "%s extremo=%d banda=%d foco=%d" % [case_id, int(end), int(side), selected]
				_check(label + " conserva la orientación fija usada para calcular el encuadre",
					camera.global_basis.x.dot(Vector3.RIGHT) > 0.999999
					and camera.global_basis.z.dot(offset.normalized()) > 0.999999
					and camera.get_camera_state()["mode"] == "broadcast")
				var points: PackedVector3Array = []
				for actor: Snapshot.ActorSnapshot in state.actors:
					if mode == Setup.Mode.MICRO_1V1 and actor.actor_id != selected:
						continue
					for x: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
						for y: float in [0.0, Tuning.ACTOR_HEIGHT]:
							for z: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
								points.append(actor.position + Vector3(x, y, z))
				for x: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
					for y: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
						for z: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
							points.append(state.ball_position + Vector3(x, y, z))
				var outside: Array[Vector2] = []
				for point: Vector3 in points:
					var screen: Vector2 = camera.unproject_position(point) / Vector2(viewport.size)
					if camera.is_position_behind(point) or not screen.is_finite() \
							or screen.x < 0.0 or screen.x > 1.0 or screen.y < 0.0 or screen.y > 1.0:
						outside.append(screen)
				_check(label + " no recorta extremos de atletas ni esfera del balón", outside.is_empty())
				_camera_evidence.append({"case": case_id, "end": end, "side": side,
					"selected_actor_id": selected, "tested_points": points.size(),
					"outside_count": outside.size(), "camera": camera.get_camera_state()})
	camera.free()
	viewport.free()
	_check(case_id + " no modifica actores ni estado del partido real", _full_fingerprint(original) == fingerprint)
	_case_done(case_id)


func _load_actual_main() -> bool:
	root.size = Vector2i(1920, 1080)
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	_check("G25 entrada configurada es el partido de producción", path == "res://match/match.tscn")
	var packed: PackedScene = load(path) as PackedScene
	_host = packed.instantiate() as MatchHost if packed != null else null
	_check("G25 instancia el script productivo real", _host != null and _host.get_script() == MatchHost)
	if _host == null:
		return false
	_development = _host.get_node("MatchDevMenu") as DevelopmentMenu
	var simulation: Simulation = _host.get_node("Simulation") as Simulation
	simulation.event_raised.connect(func(event: Event) -> void: _events.append(event))
	simulation.command_rejected.connect(_record_refusal)
	_host.integration_error.connect(_record_error)
	_host.exit_requested.connect(_on_exit_requested)
	_host.command_submitted.connect(func(command: Command, result: Error) -> void:
		_commands.append(command)
		if result == OK and command.action in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
			_launch_requests.append({"command": command.copy(), "solution": simulation.query_human_launch(command)}))
	root.add_child(_host)
	current_scene = _host
	await _frames(6)
	var original: Snapshot = _state()
	_check("G01 default intacto antes de resets: FREE_PLAY, 0/10/9",
		original.training_exercise == Setup.TrainingExercise.FREE_PLAY
		and original.phase == Snapshot.Phase.PLAYING and original.selected_actor_id == 0
		and original.actors.size() == 10 and original.ai_actor_ids == ALL_AI
		and original.ai_intent_actor_ids == ALL_INTENT and not _development.is_open()
		and not _control("PauseOverlay").visible)
	var origin: Vector3 = original.actor(0).position
	_key(KEY_D, true)
	await _frames(8)
	_check("G25 D física mueve el default antes de un drill", _state().actor(0).position.x > origin.x + 0.05
		and _commands[-1].move.x > 0.99 and _state().tick > original.tick)
	_key(KEY_D, false)
	await _frames(15)
	_check("G25 liberación física frena el default", _planar_speed() < 0.02)
	return not _failed()


func _catalog(mode: Setup.Mode, exercise: Setup.TrainingExercise, label: String) -> bool:
	_release_all()
	await _frames(2)
	_check(label + ": modo canónico", _host.start_development_mode(mode) == OK)
	var no_ai: Array[int] = []
	_check(label + ": intención IA vacía explícita", _host.set_ai_actor_ids(no_ai) == OK)
	_host.set_aim_guide_enabled(true)
	_events.clear()
	_commands.clear()
	_launch_requests.clear()
	var result: Error = _host.start_training_exercise(exercise)
	_check(label + ": aplica catálogo mediante API productiva", result == OK)
	if result != OK:
		return false
	var initial: Snapshot = _state()
	_check(label + ": conserva modo y preferencias sin cuerpos ficticios",
		initial.mode == mode and initial.training_exercise == exercise and initial.ai_intent_actor_ids.is_empty()
		and initial.actors.size() == (4 if mode == Setup.Mode.MICRO_1V1 else 10)
		and _host.get_node("Athletes").get_child_count() == initial.actors.size())
	if exercise not in [Setup.TrainingExercise.FREE_PLAY, Setup.TrainingExercise.DRIBBLE_CUT,
			Setup.TrainingExercise.DRIBBLE_PACE_CHANGE]:
		_check(label + ": arranca STOPPED y no salta a READY", initial.phase == Snapshot.Phase.RESTART_PAUSE
			and initial.restart.stage == Rules.RestartStage.STOPPED)
	await _frames(4)
	return true


func _ready_restart(label: String) -> bool:
	for frame: int in 90:
		if _state().restart.stage == Rules.RestartStage.READY:
			break
		await _frames(1)
	var state: Snapshot = _state()
	var ready: bool = state.phase == Snapshot.Phase.RESTART_PAUSE and state.restart.stage == Rules.RestartStage.READY
	_check(label + ": READY real en un recorrido acotado", ready)
	_check(label + ": preparación mínima de 60 ticks", ready and state.restart.ready_tick >= 60
		and state.restart.placement_end_tick <= state.restart.ready_tick)
	if ready:
		await _frames(2)
	return ready


func _test_four_corners(mode: Setup.Mode) -> void:
	for exercise: Setup.TrainingExercise in CORNERS:
		var label: String = "G06/G08/G14 m%d córner%d" % [mode, exercise]
		if not await _catalog(mode, exercise, label):
			return
		var initial: Snapshot = _state()
		var request: Command = _adapter().get_preview_command()
		_check(label + ": prepara guía sin ejecutar ni consumir flancos", request != null)
		if request != null:
			var solution: Launch.Solution = _host.get_simulation().query_human_launch(request)
			_check(label + ": consulta de preparación válida y no ejecutable", solution.error == OK and not solution.executable)
		if not await _ready_restart(label):
			return
		var state: Snapshot = _state()
		var camera: Camera = _camera()
		var camera_state: Dictionary = camera.get_camera_state()
		var expected_end: float = -1.0 if exercise in [Setup.TrainingExercise.CORNER_NEG_X_NEG_Z,
			Setup.TrainingExercise.CORNER_NEG_X_POS_Z] else 1.0
		var expected_side: float = -1.0 if exercise in [Setup.TrainingExercise.CORNER_POS_X_NEG_Z,
			Setup.TrainingExercise.CORNER_NEG_X_NEG_Z] else 1.0
		_check(label + ": esquina y ataque espejados coherentemente",
			signf(state.restart.spot.x) == expected_end and signf(state.restart.spot.z) == expected_side
			and signf(state.actor(state.selected_actor_id).attack_direction.x) == expected_end)
		var goal_bounds: Rect2 = Rect2(camera.unproject_position(
			Vector3(expected_end * 20.0, 0.0, -Tuning.GOAL_POST_OUTER_Z)), Vector2.ZERO)
		for depth: float in [20.0, 21.5]:
			for height: float in [0.0, 2.08]:
				for lateral: float in [-Tuning.GOAL_POST_OUTER_Z, Tuning.GOAL_POST_OUTER_Z]:
					goal_bounds = goal_bounds.expand(camera.unproject_position(
						Vector3(expected_end * depth, height, lateral)))
		var hint_panel: Control = _control("RestartFeedbackPanel")
		_check(label + ": ayuda visible de apuntado no tapa la portería atacada a 1080p",
			hint_panel.is_visible_in_tree() and not goal_bounds.intersects(hint_panel.get_global_rect()))
		var restart_panel: Control = _control("RestartPanel")
		_check(label + ": instrucciones y plazo del córner no tapan la portería atacada a 1080p",
			restart_panel.is_visible_in_tree() and not goal_bounds.intersects(restart_panel.get_global_rect()))
		_check(label + ": cámara de córner llega antes de READY sin ACK del renderer",
			camera_state["mode"] == "corner" and camera_state["transition_complete"]
			and camera_state["transition_ticks_elapsed"] == 45
			and state.restart.id == initial.restart.id)
		_check(label + ": detrás y ligeramente por encima del balón",
			camera.position.x * expected_end > state.restart.spot.x * expected_end
			and camera.position.z * expected_side > state.restart.spot.z * expected_side
			and camera.position.y >= 2.5 and camera.position.y <= 3.5
			and camera.fov >= 45.0 and camera.fov <= 66.0)
		_assert_corner_frame(label, state)
		_assert_guide(label)
		_test_sampled_transitions(mode, exercise, state)
		var at: Vector3 = state.actor(state.selected_actor_id).position
		_key(KEY_RIGHT, true)
		_key(KEY_SHIFT, true)
		await _frames(5)
		_check(label + ": dirección/sprint no desplazan al sacador propio",
			_state().actor(state.selected_actor_id).position.distance_to(at) < 0.001
			and _commands[-1].move.is_zero_approx() and not _commands[-1].sprint)
		_release_all()
		_camera_evidence.append({"case": label, "mode": mode, "exercise": exercise, "tick": state.tick,
			"restart_id": state.restart.id, "camera": camera_state})
		_case_done("corner/%d/%d" % [mode, exercise])


func _test_corner_lifecycle(mode: Setup.Mode) -> void:
	var label: String = "G12/G15/G16 m%d cámara y ciclo de input" % mode
	if not await _catalog(mode, CORNERS[0], label):
		return
	_key(KEY_RIGHT, true)
	await _frames(2)
	var first: Command = _adapter().get_preview_command()
	var from_basis: Basis = _camera().global_basis
	var projection: Dictionary = _camera().get_input_projection()
	var sample_count: int = _adapter().sample_count
	var tick: int = _state().tick
	await _frames(42)
	var held: Command = _adapter().get_preview_command()
	_check(label + ": la cámara gira, el aim retenido no",
		first != null and held != null and first.aim.distance_to(held.aim) < 0.0001
		and from_basis.x.dot(_camera().global_basis.x) < 0.99
		and _camera().get_input_projection()["serial"] == projection["serial"])
	_check(label + ": un muestreo por tick, no uno por lector de guía",
		_adapter().sample_count - sample_count == _state().tick - tick)
	var snapshot: Array = _full_fingerprint(_state())
	var charge: float = _adapter().shot_charge
	var samples: int = _adapter().sample_count
	var error_text: String = _host.get_simulation().last_error
	for query_index: int in 8:
		var cached: Command = _adapter().get_preview_command()
		_check(label + ": copia cacheada disponible %d" % query_index, cached != null)
		if cached != null:
			var solution: Launch.Solution = _host.get_simulation().query_human_launch(cached)
			cached.aim = Vector2.ZERO
			_check(label + ": consulta pura %d" % query_index, solution.error == OK)
	_check(label + ": lecturas no cambian autoridad, carga, error ni número de samples",
		snapshot == _full_fingerprint(_state()) and _adapter().shot_charge == charge
		and _adapter().sample_count == samples and _host.get_simulation().last_error == error_text
		and _adapter().get_preview_command().aim == held.aim)
	_key(KEY_RIGHT, false)
	await _frames(2)
	_key(KEY_LEFT, true)
	await _frames(2)
	var changed: Command = _adapter().get_preview_command()
	_check(label + ": liberar y cambiar dirección recaptura ejes reales",
		changed != null and _camera().get_input_projection()["serial"] > projection["serial"]
		and changed.aim.dot(_camera().screen_direction_to_court(Vector2.LEFT).normalized()) > 0.999)
	_release_all()
	if not await _ready_restart(label):
		return
	_button(JOY_BUTTON_B, true)
	await _frames(6)
	_check(label + ": cargar no abandona cámara ni ejecuta tiro",
		_camera().get_camera_state()["mode"] == "corner" and _adapter().shot_charge > 0.0
		and _count(Event.Kind.SHOT) == 0)
	_tap(KEY_ESCAPE)
	await _frames(2)
	var frozen: Array = _full_fingerprint(_state())
	var frozen_camera: Transform3D = _camera().global_transform
	await _frames(12)
	_check(label + ": pausa congela deadline, vuelo y transición de cámara",
		_full_fingerprint(_state()) == frozen and _camera().global_transform.is_equal_approx(frozen_camera)
		and not _arrow().visible and _adapter().get_preview_command() == null)
	_button(JOY_BUTTON_B, false)
	_tap(KEY_ESCAPE)
	await _frames(4)
	_check(label + ": reanudar descarta la carga anterior sin cambiar vista",
		_state().phase == Snapshot.Phase.RESTART_PAUSE and _adapter().shot_charge == 0.0
		and _camera().get_camera_state()["mode"] == "corner" and _count(Event.Kind.SHOT) == 0)
	_tap(KEY_J)
	await _frames(2)
	var passed: Event = _last(Event.Kind.PASS, 0)
	_check(label + ": PASS aceptado inicia retorno, no el botón de carga",
		passed != null and passed.success and _camera().get_camera_state()["mode"] == "returning"
		and _camera().get_camera_state()["accepted_return_event_id"] == passed.event_id)
	var accepted_tick: int = _state().tick
	await _frames(45)
	_check(label + ": retorno lateral termina en <=45 ticks",
		_camera().get_camera_state()["mode"] == "broadcast" and _state().tick >= accepted_tick + 45
		and absf(_camera().global_basis.x.y) < 0.001)
	_case_done("lifecycle/%d" % mode)


func _test_opponent_corner(mode: Setup.Mode) -> void:
	var label: String = "G13/G14 m%d córner rival" % mode
	await _create_opponent_corner(mode, label)
	_check(label + ": adjudicado por salida física tras toque humano",
		_state().restart.kind == Rules.RestartKind.CORNER and _state().restart.awarded_team_id == Snapshot.Team.AWAY
		and _count(Event.Kind.SHOT, 0) == 1)
	if not await _ready_restart(label):
		return
	_check(label + ": mantiene broadcast y defensor controlable",
		_camera().get_camera_state()["mode"] == "broadcast"
		and _state().human_control_context == Rules.ControlContext.RESTART_DEFEND and _state().selected_can_move)
	var clock: float = _state().seconds_remaining
	var origin: Vector3 = _state().actor(_state().selected_actor_id).position
	var defender: Node3D = _host.get_node("Athletes/Athlete%d" % _state().selected_actor_id) as Node3D
	var gait_before: float = defender.get("_gait")
	_key(KEY_RIGHT, true)
	_key(KEY_SHIFT, true)
	_key(KEY_CTRL, true)
	await _frames(8)
	_check(label + ": entrada defensiva nativa conserva movimiento y contención",
		_commands[-1].move.length() > 0.99 and _commands[-1].sprint and _commands[-1].close_control
		and _state().actor(_state().selected_actor_id).position.distance_to(origin) > 0.01
		and _state().seconds_remaining == clock and not _arrow().visible)
	_check(label + ": la presentación también camina durante RESTART_PAUSE",
		defender.get("_context_phase") == Snapshot.Phase.RESTART_PAUSE
		and not is_equal_approx(defender.get("_gait"), gait_before))
	_release_all()
	await _frames(2)
	var selected: int = _state().selected_actor_id
	_tap(KEY_J)
	await _frames(2)
	_check(label + ": J cambia compañero, nunca roba el balón parado",
		_state().selected_actor_id != selected and _count(Event.Kind.TACKLE) == 0
		and _count(Event.Kind.PASS) == 0 and _camera().get_camera_state()["mode"] == "broadcast")
	_case_done("opponent/%d" % mode)


func _create_opponent_corner(mode: Setup.Mode, label: String) -> void:
	var setup: Setup = Setup.for_exercise(mode, Setup.TrainingExercise.FREE_PLAY)
	setup.ai_actor_ids = []
	setup.actor_positions[0] = Vector3(-18.8, 0.0, 8.9)
	setup.actor_forwards[0] = Vector2.LEFT
	setup.ball_position = Vector3(-19.35, 0.12, 8.9)
	await _begin(label, setup)
	_key(KEY_LEFT, true)
	_key(KEY_K, true)
	await _frames(3)
	_key(KEY_K, false)
	_key(KEY_LEFT, false)
	for frame: int in 30:
		if _state().phase == Snapshot.Phase.RESTART_PAUSE:
			break
		await _frames(1)


func _test_corner_expiry_reset(mode: Setup.Mode) -> void:
	var label: String = "G15 m%d vencimiento y reset de cámara" % mode
	if not await _catalog(mode, CORNERS[3], label):
		return
	if not await _ready_restart(label):
		return
	var original: Snapshot = _state()
	for frame: int in 245:
		if _state().restart.id != original.restart.id:
			break
		await _frames(1)
	var expired: Snapshot = _state()
	_check(label + ": vencimiento real concede meta, sin golpeo ficticio",
		expired.restart.id != original.restart.id and expired.restart.kind == Rules.RestartKind.GOAL_CLEARANCE
		and expired.restart.awarded_team_id == Snapshot.Team.AWAY
		and _count(Event.Kind.PASS) == 0 and _count(Event.Kind.SHOT) == 0)
	await _frames(46)
	_check(label + ": abandona la esquina tras vencimiento",
		_camera().get_camera_state()["mode"] == "broadcast")
	_check(label + ": reset público conserva modo", _host.start_training_exercise(Setup.TrainingExercise.FREE_PLAY) == OK)
	await _frames(5)
	var reset_camera: Dictionary = _camera().get_camera_state()
	_check(label + ": nuevo contexto no conserva sacador, transición ni evento",
		_state().mode == mode and _state().training_exercise == Setup.TrainingExercise.FREE_PLAY
		and reset_camera["mode"] == "broadcast" and reset_camera["restart_id"] == -1
		and reset_camera["accepted_return_event_id"] == -1 and reset_camera["transition_started_tick"] == -1)
	_case_done("expiry-reset/%d" % mode)


func _test_sampled_transitions(mode: Setup.Mode, exercise: Setup.TrainingExercise,
		authoritative_ready: Snapshot) -> void:
	var original: Array = _full_fingerprint(authoritative_ready)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	root.add_child(viewport)
	for action: Event.Kind in [Event.Kind.PASS, Event.Kind.SHOT]:
		var case_id: String = "trace/%d/%d/%d" % [mode, exercise, action]
		var camera: Camera = Camera.new()
		viewport.add_child(camera)
		var source: Snapshot = _camera_fixture(authoritative_ready, 0)
		source.phase = Snapshot.Phase.PLAYING
		source.restart = Rules.RestartState.new()
		var counterexample: bool = mode == Setup.Mode.PREVIEW_5V5 \
			and exercise == Setup.TrainingExercise.CORNER_POS_X_NEG_Z and action == Event.Kind.PASS
		if counterexample:
			source.ball_position = Vector3.ZERO
		camera.sync_context(source)
		camera.follow(source, source.ball_position, 0.0, true)
		var source_pose: Transform3D = camera.global_transform
		var source_fov: float = camera.fov
		var previous: Transform3D = source_pose
		var entry_ticks: Array[int] = []
		var return_ticks: Array[int] = []
		var held_projection: Vector2 = Vector2.ZERO
		for tick: int in 61:
			var state: Snapshot = _camera_fixture(authoritative_ready, tick)
			state.restart.stage = Rules.RestartStage.STOPPED if tick == 0 else \
				(Rules.RestartStage.READY if tick >= 60 else Rules.RestartStage.PLACEMENT)
			camera.sync_context(state)
			camera.follow(state, state.ball_position, 1.0 / float(Tuning.PHYSICS_HZ))
			if tick == 0:
				held_projection = camera.screen_direction_to_court(Vector2.RIGHT)
			_check(case_id + " aim retenido entrada tick=%d" % tick,
				camera.screen_direction_to_court(Vector2.RIGHT).is_equal_approx(held_projection))
			_record_transition_sample(case_id, "entry", tick, camera, state.ball_position, previous)
			previous = camera.global_transform
			entry_ticks.append(tick)
			if tick == 20:
				_assert_trace_pause(case_id + " pausa entrada", camera, state)
			if tick == 31 and counterexample:
				_assert_legacy_counterexample(viewport, source_pose, source_fov, camera, state.ball_position)
			if tick == 45:
				_check(case_id + " encuadre completo en 45 sin esperar READY",
					camera.get_camera_state()["transition_complete"]
					and state.restart.stage == Rules.RestartStage.PLACEMENT)
			if tick in [45, 60]:
				_assert_corner_frame_for(case_id + " encuadre tick=%d" % tick, state, camera)
		var options: Array[int] = _visible_home_options_for(authoritative_ready, camera)
		_check(case_id + " receptor visible procede de los actores reales", not options.is_empty())
		if options.is_empty():
			camera.free()
			continue
		var taker: int = authoritative_ready.restart.taker_actor_id
		var receiver: int = options[0]
		var origin: Vector3 = authoritative_ready.ball_position
		var planar_target: Vector3 = authoritative_ready.actor(receiver).position if action == Event.Kind.PASS else Vector3.ZERO
		var direction: Vector3 = planar_target - origin
		direction.y = 0.0
		direction = direction.normalized()
		var speed: float = 14.0 if action == Event.Kind.PASS else 28.0
		var lift: float = 0.0 if action == Event.Kind.PASS else 6.0
		var accepted: Event = Event.new()
		accepted.kind = action
		accepted.actor_id = taker
		accepted.target_actor_id = receiver if action == Event.Kind.PASS else -1
		accepted.tick = 61
		accepted.event_id = 10000 + int(mode) * 1000 + int(exercise) * 10 + int(action)
		accepted.position = origin
		accepted.contact_point = origin
		accepted.velocity = direction * speed + Vector3.UP * lift
		accepted.launch_kind = Rules.LaunchKind.FOOT_PASS if action == Event.Kind.PASS else Rules.LaunchKind.FOOT_SHOT
		accepted.success = false
		var ready_pose: Transform3D = camera.global_transform
		camera.react(accepted)
		var ready: Snapshot = _camera_fixture(authoritative_ready, 60)
		camera.sync_context(ready)
		camera.follow(ready, origin, 1.0)
		_check(case_id + " rechazo permanece en preparación",
			camera.global_transform.is_equal_approx(ready_pose) and camera.get_camera_state()["mode"] == "corner")
		accepted.success = true
		camera.react(accepted)
		previous = camera.global_transform
		var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		for elapsed: int in 47:
			var seconds: float = float(elapsed) / float(Tuning.PHYSICS_HZ)
			var flight: Snapshot = _camera_fixture(authoritative_ready, 61 + elapsed)
			flight.phase = Snapshot.Phase.PLAYING
			flight.restart.stage = Rules.RestartStage.IN_PLAY
			flight.selected_actor_id = receiver if action == Event.Kind.PASS else taker
			flight.ball_position = origin + direction * speed * seconds
			flight.ball_position.y = origin.y + maxf(0.0, lift * seconds - gravity * seconds * seconds * 0.5)
			flight.ball_velocity = direction * speed
			flight.ball_velocity.y = lift - gravity * seconds if flight.ball_position.y > origin.y else 0.0
			camera.sync_context(flight)
			camera.follow(flight, flight.ball_position, 1.0 / float(Tuning.PHYSICS_HZ))
			_record_transition_sample(case_id, "return", elapsed, camera, flight.ball_position, previous)
			previous = camera.global_transform
			return_ticks.append(elapsed)
			var camera_state: Dictionary = camera.get_camera_state()
			_check(case_id + " retorno aceptado tick=%d" % elapsed,
				camera_state["accepted_return_event_id"] == accepted.event_id
				and camera_state["mode"] == ("returning" if elapsed < 45 else "broadcast"))
			_check(case_id + " aim retenido retorno tick=%d" % elapsed,
				camera.screen_direction_to_court(Vector2.RIGHT).is_equal_approx(held_projection))
			if elapsed == 31:
				_assert_trace_pause(case_id + " pausa retorno", camera, flight)
		_trace_coverage[case_id] = {"entry_ticks": entry_ticks, "return_ticks": return_ticks,
			"receiver_id": receiver, "ready_actor_ids": authoritative_ready.actors.map(
				func(actor: Snapshot.ActorSnapshot) -> int: return actor.actor_id)}
		_check(case_id + " todos los ticks están presentes, incluidos 0/31/45/60",
			entry_ticks == range(61) and return_ticks == range(47))
		camera.free()
		_case_done(case_id)
	viewport.free()
	_check("trazas no mutan snapshot autoritativo m%d córner%d" % [mode, exercise],
		_full_fingerprint(authoritative_ready) == original)


func _camera_fixture(source: Snapshot, tick: int) -> Snapshot:
	var result: Snapshot = Snapshot.new()
	result.mode = source.mode
	result.tick = tick
	result.phase = Snapshot.Phase.RESTART_PAUSE
	result.resume_phase = Snapshot.Phase.RESTART_PAUSE
	result.selected_actor_id = source.selected_actor_id
	result.actors = source.actors.duplicate()
	result.ball_position = source.ball_position
	result.ball_velocity = Vector3.ZERO
	result.restart = source.restart.copy()
	result.restart.stage = Rules.RestartStage.READY
	result.restart.stage_started_tick = 0
	result.restart.placement_end_tick = 60
	result.restart.ready_tick = 60
	result.restart.deadline_tick = 300
	return result


func _assert_trace_pause(label: String, camera: Camera, state: Snapshot) -> void:
	var before: Transform3D = camera.global_transform
	var before_fov: float = camera.fov
	var paused: Snapshot = _camera_fixture(state, state.tick)
	paused.restart = state.restart.copy()
	paused.phase = Snapshot.Phase.PAUSED
	paused.resume_phase = state.phase
	paused.ball_velocity = state.ball_velocity
	for sample: int in 3:
		camera.sync_context(paused)
		camera.follow(paused, paused.ball_position, 0.5 + float(sample))
		_check(label + " sin reloj render alternativo muestra=%d" % sample,
			camera.global_transform.is_equal_approx(before) and is_equal_approx(camera.fov, before_fov))


func _record_transition_sample(case_id: String, direction: String, tick: int, camera: Camera,
		ball: Vector3, previous: Transform3D) -> void:
	var label: String = "%s %s tick=%d" % [case_id, direction, tick]
	var pixel: Vector2 = camera.unproject_position(ball) / camera.get_viewport().get_visible_rect().size
	var behind: bool = camera.is_position_behind(ball)
	var fits: bool = _native_ball_in_frame(camera, ball)
	var turn: float = previous.basis.get_rotation_quaternion().angle_to(camera.global_basis.get_rotation_quaternion())
	var travel: float = previous.origin.distance_to(camera.global_position)
	_check(label + " balón delante y esfera completa dentro del encuadre", not behind and fits)
	_check(label + " sin corte, roll, inversión de ejes ni FOV extremo",
		travel < 3.5 and turn < 0.35 and absf(camera.global_basis.x.y) < 0.0001
		and camera.global_basis.y.y > 0.05 and camera.global_transform.is_finite()
		and camera.fov >= 46.0 and camera.fov <= 60.0)
	var blockers: Array[String] = _ball_blockers(camera, ball)
	_check(label + " trayectoria no esconde balón tras recinto o red", blockers.is_empty())
	_transition_evidence.append({
		"case": case_id, "direction": direction, "elapsed": tick,
		"camera": camera.get_camera_state(), "ball": [ball.x, ball.y, ball.z],
		"screen": [pixel.x, pixel.y], "behind": behind, "sphere_in_frame": fits,
		"travel": travel, "turn_radians": turn, "blockers": blockers,
	})


func _native_ball_in_frame(camera: Camera3D, ball: Vector3) -> bool:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	for x: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
		for y: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
			for z: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
				var point: Vector3 = ball + Vector3(x, y, z)
				var pixel: Vector2 = camera.unproject_position(point) / size
				if camera.is_position_behind(point) or not pixel.is_finite() \
						or pixel.x < 0.035 or pixel.x > 0.965 or pixel.y < 0.12 or pixel.y > 0.88:
					return false
	return true


func _assert_legacy_counterexample(viewport: SubViewport, from: Transform3D, from_fov: float,
		production: Camera, ball: Vector3) -> void:
	var legacy: Camera3D = Camera3D.new()
	viewport.add_child(legacy)
	legacy.keep_aspect = Camera3D.KEEP_HEIGHT
	var weight: float = smoothstep(0.0, 45.0, 31.0)
	var destination: Transform3D = production._corner_pose(ball)
	var from_yaw: float = atan2(from.basis.z.x, from.basis.z.z)
	var to_yaw: float = atan2(destination.basis.z.x, destination.basis.z.z)
	var from_pitch: float = atan2(-from.basis.z.y, Vector2(from.basis.z.x, from.basis.z.z).length())
	var to_pitch: float = atan2(-destination.basis.z.y, Vector2(destination.basis.z.x, destination.basis.z.z).length())
	legacy.global_transform = Transform3D(
		Basis(Vector3.UP, lerp_angle(from_yaw, to_yaw, weight))
		* Basis(Vector3.RIGHT, lerpf(from_pitch, to_pitch, weight)),
		from.origin.lerp(destination.origin, weight))
	legacy.fov = lerpf(from_fov, Camera.CORNER_FOV, weight)
	_check("Vasquez: mezcla independiente antigua deja balón detrás en tick 31/45",
		legacy.is_position_behind(ball))
	_check("Vasquez: follow/sync_context productivos mantienen visible ese mismo tick",
		not production.is_position_behind(ball) and _native_ball_in_frame(production, ball))
	var legacy_pixel: Vector2 = legacy.unproject_position(ball)
	var production_pixel: Vector2 = production.unproject_position(ball)
	_camera_evidence.append({"case": "legacy-counterexample", "tick": 31,
		"legacy_behind": legacy.is_position_behind(ball),
		"legacy_screen": [legacy_pixel.x, legacy_pixel.y],
		"production_behind": production.is_position_behind(ball),
		"production_screen": [production_pixel.x, production_pixel.y]})
	legacy.free()
	_legacy_counterexample_checked = true
	_case_done("legacy-counterexample")


func _assert_corner_frame(label: String, state: Snapshot) -> void:
	_assert_corner_frame_for(label, state, _camera())


func _assert_corner_frame_for(label: String, state: Snapshot, camera: Camera) -> void:
	var athlete: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	var visible: bool = true
	for point: Vector3 in [state.ball_position, athlete.position, athlete.position + Vector3.UP * Tuning.ACTOR_HEIGHT]:
		var pixel: Vector2 = camera.unproject_position(point) / camera.get_viewport().get_visible_rect().size
		visible = visible and not camera.is_position_behind(point) and pixel.x > 0.03 and pixel.x < 0.97 \
			and pixel.y > 0.12 and pixel.y < 0.86
	_check(label + ": balón y sacador completo fuera de los bordes/HUD", visible)
	_check(label + ": al menos un compañero ofrece una opción visible", not _visible_home_options_for(state, camera).is_empty())
	_check(label + ": ojo dentro de recinto, debajo de vigas y sin roll",
		absf(camera.position.x) < 23.5 and absf(camera.position.z) < 13.5 and camera.position.y < 7.0
		and absf(camera.global_basis.x.y) < 0.001)
	_check(label + ": segmento a balón no atraviesa mallas de muro/techo/red", _ball_blockers(camera, state.ball_position).is_empty())


func _ball_blockers(camera: Camera3D, ball: Vector3) -> Array[String]:
	var blockers: Array[String] = []
	for node: Node in _host.get_node("Arena").find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var path: String = String(mesh.get_path())
		if ["Wall", "Padding", "Roof", "Pillar", "Net"].any(func(part: String) -> bool: return path.contains(part)):
			var local_eye: Vector3 = mesh.to_local(camera.global_position)
			var local_ball: Vector3 = mesh.to_local(ball)
			if _segment_hits_box(mesh.get_aabb(), local_eye, local_ball):
				blockers.append(path)
	return blockers


func _visible_home_options(state: Snapshot) -> Array[int]:
	return _visible_home_options_for(state, _camera())


func _visible_home_options_for(state: Snapshot, camera: Camera3D) -> Array[int]:
	var ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id != Snapshot.Team.HOME or actor.actor_id == state.selected_actor_id:
			continue
		var visible: bool = true
		for point: Vector3 in [actor.position, actor.position + Vector3.UP * Tuning.ACTOR_HEIGHT]:
			var at: Vector2 = camera.unproject_position(point) / camera.get_viewport().get_visible_rect().size
			visible = visible and not camera.is_position_behind(point) and at.x > 0.03 and at.x < 0.97 \
				and at.y > 0.12 and at.y < 0.86
		if visible:
			ids.append(actor.actor_id)
	return ids


func _segment_hits_box(box: AABB, from: Vector3, to: Vector3) -> bool:
	var start: float = 0.001
	var end: float = 0.999
	var direction: Vector3 = to - from
	for axis: int in 3:
		if absf(direction[axis]) < 0.000001:
			if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
				return false
			continue
		var near_at: float = (box.position[axis] - from[axis]) / direction[axis]
		var far_at: float = (box.end[axis] - from[axis]) / direction[axis]
		start = maxf(start, minf(near_at, far_at))
		end = minf(end, maxf(near_at, far_at))
		if start > end:
			return false
	return true


func _assert_guide(label: String) -> void:
	var arrow: Node3D = _arrow()
	var request: Command = _adapter().get_preview_command()
	_check(label + ": guía utiliza copia de input cacheada", request != null)
	if request == null:
		return
	var solution: Launch.Solution = _host.get_simulation().query_human_launch(request)
	var ball_mesh: MeshInstance3D = _host.get_node("BallView/BallMesh") as MeshInstance3D
	var shaft: MeshInstance3D = arrow.get_node("Shaft") as MeshInstance3D
	var head: MeshInstance3D = arrow.get_node("Head") as MeshInstance3D
	_check(label + ": flecha de mallas reales en el mismo mundo de render que el balón",
		shaft.mesh != null and head.mesh != null and shaft.is_visible_in_tree() and head.is_visible_in_tree()
		and arrow.get_world_3d() == ball_mesh.get_world_3d()
		and _host.get_node("BallView").is_ancestor_of(arrow))
	_check(label + ": origen de render real, no el root inmóvil de BallView",
		arrow.global_position.distance_to(ball_mesh.global_position + Vector3.UP * 0.035) < 0.0001
		and _host.get_render_ball_position() == ball_mesh.global_position)
	_check(label + ": dirección y velocidad son las del resolver de ejecución",
		solution.error == OK and arrow.global_basis.x.dot(solution.direction) > 0.999
		and arrow.get_meta("launch_velocity", Vector3.ZERO).distance_to(solution.velocity) < 0.001
		and arrow.get_meta("effective_target_actor_id", -2) == solution.effective_target_actor_id)


func _arrow() -> Node3D:
	return _host.get_node("BallView/WorldAimGuide/Arrow") as Node3D


func _case_done(id: String) -> void:
	_check("recorrido finito, caso único: " + id, not _completed_cases.has(id))
	_completed_cases.append(id)


func _expected_cases() -> Array[String]:
	var result: Array[String] = []
	for mode: int in [0, 1]:
		result.append("broadcast-framing/%d" % mode)
		for exercise: int in CORNERS:
			result.append("corner/%d/%d" % [mode, exercise])
			for action: int in [Event.Kind.PASS, Event.Kind.SHOT]:
				result.append("trace/%d/%d/%d" % [mode, exercise, action])
		result.append("lifecycle/%d" % mode)
		result.append("opponent/%d" % mode)
		result.append("expiry-reset/%d" % mode)
	result.append("legacy-counterexample")
	return result


func _test_marker() -> String:
	return "FUTSAL_MATCH_CAMERA_TESTS"


func _frames(count: int) -> void:
	for frame: int in count:
		await physics_frame
		await process_frame
		# Las mallas de presentación se actualizan después de process_frame.
		await create_timer(0.0, true, false, true).timeout


func _report() -> void:
	if _report_printed:
		return
	var expected: Array[String] = _expected_cases()
	var completed: Array[String] = _completed_cases.duplicate()
	expected.sort()
	completed.sort()
	_check("suite completa, ningún caso perdido por aborto asíncrono", _suite_complete and expected == completed)
	_check("diagnósticos exactos hasta la finalización", _diagnostics_ok())
	if "legacy-counterexample" in expected:
		_check("contraejemplo rechazado fue ejercitado por cámaras nativas", _legacy_counterexample_checked)
	var check_names: Dictionary[String, bool] = {}
	for item: Dictionary in _checks:
		check_names[String(item["name"])] = true
	_check("identificadores de comprobación únicos hasta la finalización", check_names.size() == _checks.size())
	_report_printed = true
	var failures: Array[Dictionary] = _checks.filter(func(item: Dictionary) -> bool: return not item["passed"])
	print(_test_marker() + " " + JSON.stringify({
		"ok": failures.is_empty(), "complete": _suite_complete and expected == completed,
		"passed": _checks.size() - failures.size(), "total": _checks.size(), "failures": failures,
		"checks": _checks, "transition_samples": _transition_evidence, "trace_coverage": _trace_coverage,
		"expected_cases": expected, "completed_cases": completed, "camera_samples": _camera_evidence,
		"athlete_presentations": _athlete_presentations,
		"expected_development_errors": _expected_errors, "command_refusals": _refusals,
		"expected_command_refusals": _expected_refusals, "unexpected_integration_errors": _unexpected_errors,
		"unexpected_command_refusals": _unexpected_refusals, "native_events": _native_events,
		"mouse_events": _mouse_events, "engine": Engine.get_version_info()["string"],
		"headless": DisplayServer.get_name() == "headless",
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
		"limitations": ["Encuadre matemático y mallas reales; no sustituye inspección de PNG del ejecutable ni prueba humana."],
	}))
