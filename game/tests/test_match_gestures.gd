extends SceneTree
## Componentes visuales con snapshots controlados; no son evidencia de física,
## cámaras de producción, capturas, calidad artística ni deriva real de apoyos.
## Ejecutar únicamente durante composición estable:
## godot --headless --path game --script res://tests/test_match_gestures.gd

const Athlete = preload("res://match/presentation/athletes/athlete_view.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const VisualTests = preload("res://tests/test_match_visuals.gd")
const AthleteMaterials = preload("res://tests/athlete_test_materials.gd")

var _checks: Array[Dictionary] = []
var _check_names: Dictionary[String, bool] = {}
var _duplicate_checks: Array[String] = []
var _expected_errors: Dictionary[String, int] = {}
var _native_errors: VisualTests.NativeErrors = VisualTests.NativeErrors.new()
var _views: Array[Athlete] = []
var _event_id: int = 0
var _started_ms: int = 0
var _completed: bool = false
var _reported: bool = false


func _initialize() -> void:
	OS.add_logger(_native_errors)
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if not _reported and Time.get_ticks_msec() - _started_ms > 30000:
		_check("Watchdog de gestos: ejecución completa en 30 segundos", false)
		_report()
	return false


func _run() -> void:
	_test_cuts()
	_test_foot_gestures()
	_test_tick_clock()
	_test_restart_defender_stride()
	_test_replacement_cancel_reset()
	_test_keeper_throw()
	_test_identity_and_selection()
	_test_rejections()
	_completed = true
	_report()


func _test_cuts() -> void:
	var yaws: Array[float] = [0.0, PI * 0.5, PI, -PI * 0.5]
	for yaw_index: int in yaws.size():
		for side: int in [-1, 1]:
			var name: String = "CUT orientación=%d lado=%d" % [yaw_index, side]
			var view: Athlete = _view(0)
			var actor: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.CUT, yaws[yaw_index])
			actor.position = Vector3(float(side) * 9.0, 0, float(yaw_index) * 2.0 - 3.0)
			var facing: Basis = Basis(Vector3.UP, actor.facing_yaw)
			actor.gesture_direction = facing * Vector3(float(side), 0, 0)
			actor.gesture_contact_position = actor.position + facing * Vector3(0, Tuning.BALL_RADIUS, -0.42)
			var accepted: Event = _event(actor)
			view.react(accepted, actor)
			_present_tick(view, actor, 99.0)
			var anticipation_start: float = view._gesture_weight
			_present_tick(view, actor, 99.5)
			var anticipation_middle: float = view._gesture_weight
			_present_tick(view, actor, 100.0)
			var body: Node3D = view.get_node("ArticulatedBody") as Node3D
			_check(name + " anticipación interpolada termina en tick de contacto",
				is_zero_approx(anticipation_start) and anticipation_middle > 0.0
				and anticipation_middle < 1.0 and is_equal_approx(view._gesture_weight, 1.0)
				and is_zero_approx(view._gesture_progress))
			_check(name + " cadera y torso inclinan hacia el lado del enganche",
				body.rotation.z * float(side) < -0.10 and body.position.x * float(side) > 0.025
				and body.position.y < -0.05)
			_check(name + " pie de acción y apoyo son opuestos",
				view._contact_leg == (0 if side < 0 else 1)
				and view._support_leg == 1 - view._contact_leg)
			_check(name + " puntera usa contacto mundial pese a traslación y yaw",
				_toe_world(view).distance_to(actor.gesture_contact_position
					- view._foot_forward_world * Tuning.BALL_RADIUS) < 0.025)
			var plant: Vector3 = view._support_world
			_check(name + " tobillo de apoyo llega a su ancla al contacto",
				_ankle_world(view, view._support_leg).distance_to(plant) < 0.025)
			var contact_pose: String = _pose(view)
			actor.position += facing * Vector3(0.005 * float(side), 0, -0.01)
			actor.facing_yaw += 0.01
			_present_tick(view, actor, 100.5)
			_check(name + " apoyo conserva ancla durante el intervalo plantado",
				_ankle_world(view, view._support_leg).distance_to(plant) < 0.025)
			_check(name + " contacto no queda pegado a coordenadas locales al mover y girar",
				_toe_world(view).distance_to(accepted.contact_point
					- view._foot_forward_world * Tuning.BALL_RADIUS) < 0.04)
			_present_tick(view, actor, 107.0)
			_check(name + " recuperación distinta del contacto sin miembros inválidos",
				_pose(view) != contact_pose and view._gesture_progress > 0.3 and _limbs_valid(view))
			_present_tick(view, actor, 118.0)
			_check(name + " duración autoritativa termina el gesto",
				view._gesture_kind == Rules.GestureKind.NONE and is_zero_approx(view._gesture_weight)
				and is_zero_approx(body.rotation.z) and is_zero_approx(body.rotation.y))


func _test_foot_gestures() -> void:
	var kinds: Array[Rules.GestureKind] = [
		Rules.GestureKind.PACE_CHANGE, Rules.GestureKind.FOOT_KICK, Rules.GestureKind.TACKLE,
	]
	for kind: Rules.GestureKind in kinds:
		var view: Athlete = _view(0)
		var baseline: Athlete = _view(0)
		var actor: Snapshot.ActorSnapshot = _actor(0, kind, PI * 0.5)
		var runner: Snapshot.ActorSnapshot = _actor(0)
		runner.facing_yaw = actor.facing_yaw
		runner.position = actor.position
		var direction: Vector3 = Basis(Vector3.UP, actor.facing_yaw) * Vector3.FORWARD
		actor.gesture_direction = direction
		actor.gesture_contact_position = actor.position + direction * 0.48 + Vector3.UP * Tuning.BALL_RADIUS
		actor.velocity = direction * 7.5
		runner.velocity = actor.velocity
		view.react(_event(actor), actor)
		var all_limbs_bounded: bool = true
		var maximum_lean: float = 0.0
		for index: int in 39:
			var tick: float = 99.0 + float(index) * 0.5
			if index > 0:
				actor.position += actor.velocity * 0.5 / float(Tuning.PHYSICS_HZ)
				runner.position = actor.position
			_present_tick(view, actor, tick)
			_present_tick(baseline, runner, tick)
			all_limbs_bounded = all_limbs_bounded and _limbs_valid(view)
			maximum_lean = minf(maximum_lean, (view.get_node("ArticulatedBody") as Node3D).rotation.x)
		var name: String = "Gesto de pie=%d" % kind
		_check(name + " conserva longitudes finitas durante sprint y recuperación", all_limbs_bounded)
		_check(name + " torso acompaña la acción", maximum_lean < -0.15)
		_check(name + " vuelve a la misma zancada de sprint, no a un pie de patada retenido",
			view._gesture_kind == Rules.GestureKind.NONE and _same_pose(view, baseline))
		var identity: String = _identity(view)
		var snapshot_before: String = _actor_state(actor)
		_present_tick(view, actor, 119.0)
		_check(name + " presentación no altera autoridad ni identidad",
			_actor_state(actor) == snapshot_before and _identity(view) == identity)
	var shot_view: Athlete = _view(0)
	var shot: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	var shot_event: Event = _event(shot)
	shot_event.kind = Event.Kind.SHOT
	shot_event.launch_kind = Rules.LaunchKind.FOOT_SHOT
	shot_event.position = Vector3(7, 1, 7)
	shot_view.react(shot_event, shot)
	_present_tick(shot_view, shot, 100.0)
	_check("SHOT aceptado usa contact_point, no la posición genérica del evento",
		shot_view._gesture_kind == Rules.GestureKind.FOOT_KICK
		and _toe_world(shot_view).distance_to(shot.gesture_contact_position
			- shot_view._foot_forward_world * Tuning.BALL_RADIUS) < 0.025)
	var miss_view: Athlete = _view(0)
	var miss: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.TACKLE)
	miss.gesture_contact_position = Vector3(0, Tuning.BALL_RADIUS, -1.8)
	var miss_event: Event = _event(miss)
	miss_event.success = false
	miss_view.react(miss_event, miss)
	_present_tick(miss_view, miss, 100.0)
	_check("Entrada fallida gesticula sin aceptar un contacto de evento",
		miss_view._event_started_tick == -1 and miss_view._event_contact_tick == -1
		and _toe_world(miss_view).distance_to(miss.gesture_contact_position) > 0.5
		and _limbs_valid(miss_view))
	var charge_view: Athlete = _view(0)
	var charge: Snapshot.ActorSnapshot = _actor(0)
	charge.ball_contact_reachable = true
	_present_tick(charge_view, charge, 50.0)
	var neutral_ankle: Vector3 = charge_view._posed_ankles[1]
	_present_pair(charge_view, charge, charge, 50, 50, 1.0, Vector3.ZERO, Vector3.ZERO, 0.0, 1.0)
	_check("Carga alcanzable anticipa pie sin fabricar golpeo aceptado",
		charge_view._posed_ankles[1].z > neutral_ankle.z + 0.10
		and charge_view._gesture_kind == Rules.GestureKind.NONE)
	charge.ball_contact_reachable = false
	_present_pair(charge_view, charge, charge, 50, 50, 1.0, Vector3.ZERO, Vector3.ZERO, 0.0, 1.0)
	_check("Carga sin contacto alcanzable no mantiene anticipación de patada",
		charge_view._posed_ankles[1].is_equal_approx(neutral_ankle))


func _test_tick_clock() -> void:
	var view: Athlete = _view(0)
	var actor: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.CUT)
	actor.velocity = Vector3(0, 0, -4.0)
	view.react(_event(actor), actor)
	_present_tick(view, actor, 103.0)
	var pose: String = _pose(view)
	var progress: float = view._gesture_progress
	for index: int in 5:
		_present_pair(view, actor, actor, 103, 103, 1.0, Vector3.ZERO, Vector3.ZERO, 0.2 + index)
	_check("Tick repetido no avanza gesto ni zancada con delta render variable",
		_pose(view) == pose and is_equal_approx(view._gesture_progress, progress))
	_present_pair(view, actor, actor, 103, 103, 1.0, Vector3.ZERO, Vector3.ZERO, 4.0, 0.0, Snapshot.Phase.PAUSED)
	_check("Pausa conserva pose y fase aun con tiempo de render transcurrido",
		_pose(view) == pose and is_equal_approx(view._gesture_progress, progress))
	_present_pair(view, actor, actor, 103, 107, 1.0, Vector3.ZERO, Vector3.ZERO, 0.0)
	_check("Tick autoritativo sí avanza gesto con delta render cero",
		view._gesture_progress > progress and _pose(view) != pose)
	var duplicate: Event = _event(actor)
	duplicate.tick = 100
	view.react(duplicate, actor)
	_present_tick(view, actor, 107.0)
	var after_event: String = _pose(view)
	var after_progress: float = view._gesture_progress
	view.react(duplicate, actor)
	_present_tick(view, actor, 107.0)
	_check("Duplicar un evento aceptado no reinicia la recuperación",
		_pose(view) == after_event and is_equal_approx(view._gesture_progress, after_progress))


func _test_replacement_cancel_reset() -> void:
	var view: Athlete = _view(0)
	var first: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	var old_event: Event = _event(first)
	view.react(old_event, first)
	_present_tick(view, first, 100.0)
	var next: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.CUT)
	next.gesture_started_tick = 102
	next.gesture_direction = Vector3.LEFT
	next.gesture_contact_position = Vector3(-0.10, Tuning.BALL_RADIUS, -0.40)
	view.react(_event(next), next)
	_present_tick(view, next, 102.0)
	var contact: Vector3 = view._gesture_contact_world
	view.react(old_event, next)
	_present_tick(view, next, 102.0)
	_check("Gesto nuevo sustituye patada anterior sin doble artefacto",
		view._gesture_kind == Rules.GestureKind.CUT and view._gesture_started_tick == 102
		and view._contact_leg == 0 and view._gesture_contact_world == contact)
	var cancelled: Snapshot.ActorSnapshot = _actor(0)
	cancelled.velocity = Vector3(0, 0, -7.5)
	_present_tick(view, cancelled, 103.0)
	var cancel_weight: float = view._gesture_weight
	_present_tick(view, cancelled, 104.5)
	_check("Cancelación mezcla de forma acotada, sin otra acción autoritativa",
		view._gesture_weight > 0.0 and view._gesture_weight < cancel_weight)
	_present_tick(view, cancelled, 106.0)
	_check("Cancelación devuelve brazos, torso y pies a locomoción",
		view._gesture_kind == Rules.GestureKind.NONE and is_zero_approx(view._gesture_weight)
		and is_zero_approx((view.get_node("ArticulatedBody") as Node3D).rotation.z) and _limbs_valid(view))
	next.gesture_started_tick = 110
	view.react(_event(next), next)
	_present_tick(view, next, 110.0)
	var identity: String = _identity(view)
	view.reset_pose()
	_check("Reset elimina gesto, reloj, eventos y selección obsoletos inmediatamente",
		view._gesture_kind == Rules.GestureKind.NONE and view._event_started_tick == -1
		and view._last_event_id == -1 and view._last_render_tick < 0.0 and is_zero_approx(view._gait)
		and not (view.get_node("HumanSelection") as Label3D).visible)
	_check("Reset conserva dorsal, kit y geometría", _identity(view) == identity and _limbs_valid(view))
	cancelled.velocity = Vector3.ZERO
	_present_tick(view, cancelled, 0.0)
	_check("Nuevo inicio en tick cero no revive una patada antigua",
		view._gesture_kind == Rules.GestureKind.NONE
		and (view.get_node("ArticulatedBody") as Node3D).rotation.is_zero_approx())


func _test_restart_defender_stride() -> void:
	var view: Athlete = _view(0)
	var before_actor: Snapshot.ActorSnapshot = _actor(0)
	before_actor.velocity = Vector3(4, 0, 0)
	var actor: Snapshot.ActorSnapshot = _actor(0)
	actor.velocity = before_actor.velocity
	actor.position = before_actor.position + actor.velocity / float(Tuning.PHYSICS_HZ)
	var before: Snapshot = _defender_frame(before_actor, 200)
	var state: Snapshot = _defender_frame(actor, 201)
	view.sync_context(before, before)
	view.present(before_actor, before_actor, 1.0, 0.0, false, 0.0)
	var initial_gait: float = view._gait
	var initial_ankle: Vector3 = view._posed_ankles[0]
	view.sync_context(before, state)
	view.present(before_actor, actor, 1.0, 1.0 / float(Tuning.PHYSICS_HZ), false, 0.0)
	_check("Defensor READY avanza marcha durante RESTART_PAUSE",
		view._gait > initial_gait and not view._posed_ankles[0].is_equal_approx(initial_ankle)
		and _limbs_valid(view))
	var walking_pose: String = _pose(view)
	var walking_gait: float = view._gait
	var paused: Snapshot = _defender_frame(actor, 201)
	paused.phase = Snapshot.Phase.PAUSED
	paused.resume_phase = Snapshot.Phase.RESTART_PAUSE
	paused.human_control_context = Rules.ControlContext.DISABLED
	paused.selected_can_move = false
	view.sync_context(paused, paused)
	view.present(actor, actor, 1.0, 4.0, false, 0.0)
	_check("Pausa detiene también marcha del defensor de saque",
		_pose(view) == walking_pose and is_equal_approx(view._gait, walking_gait))
	var next_actor: Snapshot.ActorSnapshot = _actor(0)
	next_actor.velocity = actor.velocity
	next_actor.position = actor.position + actor.velocity / float(Tuning.PHYSICS_HZ)
	var resumed: Snapshot = _defender_frame(next_actor, 202)
	view.sync_context(state, resumed)
	view.present(actor, next_actor, 1.0, 0.0, false, 0.0)
	var expected_step: float = (1.6 + actor.velocity.length() * 0.30) / float(Tuning.PHYSICS_HZ)
	_check("Defensor reanuda marcha desde tick sin recuperar tiempo pausado",
		is_equal_approx(view._gait, fposmod(walking_gait + expected_step, 1.0)) and _limbs_valid(view))


func _defender_frame(actor: Snapshot.ActorSnapshot, tick: int) -> Snapshot:
	var state: Snapshot = _frame(actor, tick, Vector3.ZERO)
	state.phase = Snapshot.Phase.RESTART_PAUSE
	state.restart.kind = Rules.RestartKind.CORNER
	state.restart.stage = Rules.RestartStage.READY
	state.restart.awarded_team_id = Snapshot.Team.AWAY
	state.restart.taker_actor_id = 1
	state.human_control_context = Rules.ControlContext.RESTART_DEFEND
	state.selected_can_move = true
	return state


func _test_keeper_throw() -> void:
	for id: int in [2, 3]:
		var view: Athlete = _view(id)
		var keeper: Snapshot.ActorSnapshot = _actor(id, Rules.GestureKind.NONE, PI * 0.5 if id == 2 else -PI * 0.5)
		keeper.position = Vector3(-7.0 if id == 2 else 7.0, 0, 2.0)
		keeper.ball_in_hands = true
		var facing: Basis = Basis(Vector3.UP, keeper.facing_yaw)
		var anchor: Vector3 = keeper.position + facing * Vector3(0, 1.12, -0.34)
		var before_anchor: Vector3 = anchor + facing * Vector3(0.01, 0.02, 0.01)
		var mesh_count: int = view.find_children("*", "MeshInstance3D", true, false).size()
		_present_pair(view, keeper, keeper, 60, 61, 0.5, before_anchor, anchor)
		var real_render_ball: Vector3 = before_anchor.lerp(anchor, 0.5)
		_check("Portero %d manos rodean el mismo balón interpolado que BallView" % id,
			((_hand_world(view, 0) + _hand_world(view, 1)) * 0.5).distance_to(real_render_ball) < 0.025)
		var right: Vector3 = facing * Vector3.RIGHT
		_check("Portero %d agarre a ambos lados del ancla real" % id,
			absf((_hand_world(view, 0) - real_render_ball).dot(right) + Tuning.BALL_RADIUS) < 0.0001
			and absf((_hand_world(view, 1) - real_render_ball).dot(right) - Tuning.BALL_RADIUS) < 0.0001)
		var rejected: Event = Event.new()
		rejected.kind = Event.Kind.PASS
		rejected.launch_kind = Rules.LaunchKind.KEEPER_THROW
		rejected.gesture_kind = Rules.GestureKind.KEEPER_THROW
		rejected.actor_id = id
		rejected.tick = 62
		rejected.position = anchor
		rejected.success = false
		view.react(rejected, keeper)
		_present_tick(view, keeper, 62.0, anchor)
		_check("Portero %d rechazo no inicia liberación ni patada" % id,
			view._gesture_kind == Rules.GestureKind.NONE
			and ((_hand_world(view, 0) + _hand_world(view, 1)) * 0.5).distance_to(anchor) < 0.025)
		var throw_actor: Snapshot.ActorSnapshot = _actor(id, Rules.GestureKind.KEEPER_THROW, keeper.facing_yaw)
		throw_actor.position = keeper.position
		throw_actor.gesture_started_tick = 70
		throw_actor.gesture_direction = facing * Vector3.FORWARD
		throw_actor.gesture_contact_position = anchor
		var accepted: Event = _event(throw_actor)
		view.react(accepted, throw_actor)
		_present_pair(view, keeper, throw_actor, 69, 70, 0.5, anchor, anchor)
		_check("Portero %d conserva agarre antes del tick aceptado" % id,
			((_hand_world(view, 0) + _hand_world(view, 1)) * 0.5).distance_to(anchor) < 0.025)
		_present_tick(view, throw_actor, 70.0, anchor)
		var release_hand: Vector3 = _hand_world(view, 1)
		_check("Portero %d suelta con mano en el ancla del evento" % id,
			release_hand.distance_to(anchor + right * Tuning.BALL_RADIUS) < 0.025
			and view._gesture_kind == Rules.GestureKind.KEEPER_THROW)
		var flying_ball: Vector3 = anchor + throw_actor.gesture_direction * 1.5
		_present_tick(view, throw_actor, 75.0, flying_ball)
		_check("Portero %d brazo sigue lanzamiento, no persigue balón libre" % id,
			_hand_world(view, 1).distance_to(release_hand) > 0.03
			and _hand_world(view, 1).distance_to(flying_ball) > 0.8)
		_check("Portero %d saque de manos no usa pie en posición elevada de balón" % id,
			_ankle_world(view, 0).y < 0.18 and _ankle_world(view, 1).y < 0.18)
		_present_tick(view, throw_actor, 88.0, flying_ball)
		_check("Portero %d recuperación final no conserva lanzamiento" % id,
			view._gesture_kind == Rules.GestureKind.NONE and _limbs_valid(view))
		_check("Portero %d no añade balón falso ni cuerpos físicos" % id,
			view.find_children("*", "MeshInstance3D", true, false).size() == mesh_count
			and view.find_children("*Ball*", "MeshInstance3D", true, false).is_empty()
			and view.find_children("*", "CollisionObject3D", true, false).is_empty())


func _test_identity_and_selection() -> void:
	var views: Array[Athlete] = []
	var identities: Array[String] = []
	for id: int in 10:
		var view: Athlete = _view(id)
		views.append(view)
		identities.append(_identity(view))
	for focus: int in [0, 4, 2]:
		var selected_count: int = 0
		for id: int in 10:
			var actor: Snapshot.ActorSnapshot = _actor(id, Rules.GestureKind.PACE_CHANGE)
			actor.human_controlled = id == focus
			actor.velocity = Vector3(0, 0, -7.5)
			_present_tick(views[id], actor, 100.0)
			var selection: Label3D = views[id].get_node_or_null("HumanSelection") as Label3D
			if selection != null and selection.visible:
				selected_count += 1
			_check("Gesto preserva identidad y marca foco=%d actor=%d" % [focus, id],
				_identity(views[id]) == identities[id]
				and (selection == null or selection.visible == (id == focus)))
		_check("Durante gestos existe una única selección HOME foco=%d" % focus, selected_count == 1)
	for id: int in 10:
		var actor: Snapshot.ActorSnapshot = _actor(id)
		actor.human_controlled = false
		_present_tick(views[id], actor, 120.0)
		_present_tick(views[id], actor, 123.0)
		var selection: Label3D = views[id].get_node_or_null("HumanSelection") as Label3D
		_check("Limpieza de control y gesto no deja marca huérfana actor=%d" % id,
			(selection == null or not selection.visible) and views[id]._gesture_kind == Rules.GestureKind.NONE)


func _test_rejections() -> void:
	var view: Athlete = _view(0)
	var valid: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	_present_tick(view, valid, 100.0)
	var invalid_kind: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	invalid_kind.set("gesture_kind", 99)
	_expect_error("gesture_kind", view, func() -> void: _present_tick(view, invalid_kind, 100.0))
	var invalid_vector: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	invalid_vector.gesture_direction = Vector3(NAN, 0, 0)
	_expect_error("gesture_vectors", view, func() -> void: _present_tick(view, invalid_vector, 100.0))
	var invalid_contact: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	invalid_contact.gesture_contact_position = Vector3(0, INF, 0)
	_expect_error("gesture_vectors", view, func() -> void: _present_tick(view, invalid_contact, 100.0))
	var invalid_direction: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.CUT)
	invalid_direction.gesture_direction = Vector3.ZERO
	_expect_error("gesture_direction", view, func() -> void: _present_tick(view, invalid_direction, 100.0))
	var invalid_duration: Snapshot.ActorSnapshot = _actor(0, Rules.GestureKind.FOOT_KICK)
	invalid_duration.gesture_duration_ticks = 0
	_expect_error("gesture_window", view, func() -> void: _present_tick(view, invalid_duration, 100.0))
	_expect_error("interpolation_weight", view,
		func() -> void: view.present(valid, valid, NAN, 0.0, false, 0.0))
	_expect_error("frame_parameters", view,
		func() -> void: view.present(valid, valid, 1.0, NAN, false, 0.0))
	var invalid_event: Event = _event(valid)
	invalid_event.set("launch_kind", 99)
	_expect_error("launch_kind", view, func() -> void: view.react(invalid_event, valid))
	var invalid_gesture_event: Event = _event(valid)
	invalid_gesture_event.set("gesture_kind", 99)
	_expect_error("event_kind", view, func() -> void: view.react(invalid_gesture_event, valid))
	var invalid_event_contact: Event = _event(valid)
	invalid_event_contact.contact_point = Vector3(NAN, 0, 0)
	_expect_error("event_contact", view, func() -> void: view.react(invalid_event_contact, valid))
	var missing_context: Athlete = _view(0)
	_expect_error("snapshot_context_required", missing_context,
		func() -> void: missing_context.present(valid, valid, 1.0, 0.0, false, 0.0))
	var invalid_before: Snapshot = _frame(valid, -1, Vector3.ZERO)
	var invalid_after: Snapshot = _frame(valid, 100, Vector3.ZERO)
	_expect_error("context_ticks", view,
		func() -> void: view.sync_context(invalid_before, invalid_after))


func _view(id: int) -> Athlete:
	var view: Athlete = Athlete.new()
	root.add_child(view)
	view.configure(id, Color("#172f4d") if id % 2 == 0 else Color("#c8c2b6"), id + 1)
	_views.append(view)
	return view


func _actor(id: int, kind: Rules.GestureKind = Rules.GestureKind.NONE,
		yaw: float = 0.0) -> Snapshot.ActorSnapshot:
	var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	actor.actor_id = id
	actor.team_id = Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY
	actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
	actor.human_controlled = id == 0
	actor.position = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	actor.facing_yaw = yaw
	actor.forward = Basis(Vector3.UP, yaw) * Vector3.FORWARD
	actor.ball_contact_reachable = true
	actor.ball_in_hands = false
	actor.gesture_kind = kind
	actor.gesture_started_tick = -1 if kind == Rules.GestureKind.NONE else 100
	actor.gesture_duration_ticks = 0 if kind == Rules.GestureKind.NONE else 18
	actor.gesture_direction = Basis(Vector3.UP, yaw) * (Vector3.RIGHT if kind == Rules.GestureKind.CUT else Vector3.FORWARD)
	actor.gesture_contact_position = actor.position + actor.forward * 0.42 + Vector3.UP * Tuning.BALL_RADIUS
	return actor


func _event(actor: Snapshot.ActorSnapshot) -> Event:
	var event: Event = Event.new()
	_event_id += 1
	event.event_id = _event_id
	event.actor_id = actor.actor_id
	event.team_id = actor.team_id
	event.tick = actor.gesture_started_tick
	event.position = actor.gesture_contact_position
	event.contact_point = actor.gesture_contact_position
	event.velocity = actor.gesture_direction * 8.0
	event.gesture_kind = actor.gesture_kind
	match actor.gesture_kind:
		Rules.GestureKind.CUT, Rules.GestureKind.PACE_CHANGE:
			event.kind = Event.Kind.DRIBBLE
		Rules.GestureKind.TACKLE:
			event.kind = Event.Kind.TACKLE
		Rules.GestureKind.KEEPER_THROW:
			event.kind = Event.Kind.PASS
			event.launch_kind = Rules.LaunchKind.KEEPER_THROW
		_:
			event.kind = Event.Kind.PASS
			event.launch_kind = Rules.LaunchKind.FOOT_PASS
	return event


func _frame(actor: Snapshot.ActorSnapshot, tick: int, ball: Vector3) -> Snapshot:
	var state: Snapshot = Snapshot.new()
	state.tick = tick
	state.phase = Snapshot.Phase.PLAYING
	state.ball_position = ball
	state.ball_owner_id = actor.actor_id if actor.ball_in_hands else -1
	state.actors.append(actor)
	return state


func _present_tick(view: Athlete, actor: Snapshot.ActorSnapshot, tick: float,
		ball: Vector3 = Vector3.ZERO) -> void:
	var current_tick: int = maxi(0, int(ceil(tick)))
	if actor.gesture_kind != Rules.GestureKind.NONE:
		current_tick = maxi(current_tick, actor.gesture_started_tick)
	var before_tick: int = maxi(0, current_tick - 1)
	var weight: float = tick - float(before_tick) if current_tick != before_tick else 1.0
	_present_pair(view, actor, actor, before_tick, current_tick, weight, ball, ball)


func _present_pair(view: Athlete, before_actor: Snapshot.ActorSnapshot, actor: Snapshot.ActorSnapshot,
		before_tick: int, tick: int, weight: float, before_ball: Vector3, ball: Vector3,
		delta: float = 0.016, charge: float = 0.0, phase: Snapshot.Phase = Snapshot.Phase.PLAYING) -> void:
	var before: Snapshot = _frame(before_actor, before_tick, before_ball)
	var state: Snapshot = _frame(actor, tick, ball)
	state.phase = phase
	var ball_state: String = var_to_str([before.ball_position, state.ball_position, state.ball_owner_id])
	view.sync_context(before, state)
	view.present(before_actor, actor, weight, delta, actor.ball_in_hands, charge)
	if var_to_str([before.ball_position, state.ball_position, state.ball_owner_id]) != ball_state:
		_check("Presentación mutó balón de fixture tick=%d actor=%d" % [tick, actor.actor_id], false)


func _toe_world(view: Athlete) -> Vector3:
	var shoe: Node3D = view._legs[view._contact_leg][3] as Node3D
	return shoe.to_global(Vector3(0, 0, -0.5))


func _ankle_world(view: Athlete, index: int) -> Vector3:
	return (view.get_node("ArticulatedBody") as Node3D).to_global(view._posed_ankles[index])


func _hand_world(view: Athlete, index: int) -> Vector3:
	return (view._arms[index][2] as Node3D).global_position


func _limbs_valid(view: Athlete) -> bool:
	for node: Node in view.find_children("*", "Node3D", true, false):
		if not (node as Node3D).transform.is_finite():
			return false
	for side: int in view._legs.size():
		var leg: Array = view._legs[side]
		var lengths: Vector2 = view._skin_view.rig.leg_lengths[side]
		for index: int in [0, 1]:
			if absf((leg[index] as Node3D).basis.y.length() - lengths[index]) > 0.0001:
				return false
	return true


func _pose(view: Athlete) -> String:
	var transforms: Array[Transform3D] = [view.transform]
	for node: Node in view.find_children("*", "Node3D", true, false):
		transforms.append((node as Node3D).transform)
	for bone: int in view._skin_view.skeleton.get_bone_count():
		transforms.append(view._skin_view.skeleton.get_bone_global_pose(bone))
	return var_to_str([view._gait, transforms])


func _same_pose(a: Athlete, b: Athlete) -> bool:
	if not (a.get_node("ArticulatedBody") as Node3D).transform.is_equal_approx(
			(b.get_node("ArticulatedBody") as Node3D).transform) or not is_equal_approx(a._gait, b._gait):
		return false
	for side: int in 2:
		for index: int in a._legs[side].size():
			if not (a._legs[side][index] as Node3D).transform.is_equal_approx((b._legs[side][index] as Node3D).transform):
				return false
		for index: int in a._arms[side].size():
			if not (a._arms[side][index] as Node3D).transform.is_equal_approx((b._arms[side][index] as Node3D).transform):
				return false
	for bone: int in a._skin_view.skeleton.get_bone_count():
		if not a._skin_view.skeleton.get_bone_global_pose(bone).is_equal_approx(
				b._skin_view.skeleton.get_bone_global_pose(bone)):
			return false
	return true


func _identity(view: Athlete) -> String:
	var identity: Array = [view.actor_id, view.dorsal, view.kit_color]
	var body: Node3D = view.get_node("ArticulatedBody") as Node3D
	identity.append((body.get_node("BackNumber") as Label3D).text)
	identity.append((body.get_node("FrontNumber") as Label3D).text)
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		identity.append([mesh.get_instance_id(), mesh.mesh.get_instance_id(),
			AthleteMaterials.surface_identity(mesh)])
	return var_to_str(identity)


func _actor_state(actor: Snapshot.ActorSnapshot) -> String:
	return var_to_str([actor.actor_id, actor.position, actor.velocity, actor.facing_yaw, actor.human_controlled,
		actor.ball_contact_reachable, actor.ball_in_hands, actor.gesture_kind, actor.gesture_started_tick,
		actor.gesture_duration_ticks, actor.gesture_direction, actor.gesture_contact_position])


func _expect_error(reason: String, view: Athlete, action: Callable) -> void:
	var name: String = Athlete.PRESENTATION_ERROR + reason
	_expected_errors[name] = int(_expected_errors.get(name, 0)) + 1
	var occurrence: int = _expected_errors[name]
	var before: Dictionary = _native_errors.snapshot()
	var pose: String = _pose(view)
	action.call()
	var after: Dictionary = _native_errors.snapshot()
	_check("Rechazo explícito %s caso=%d" % [reason, occurrence],
		int(after["error_count"]) == int(before["error_count"]) + 1
		and view._last_validation_error == reason)
	_check("Sin pose alternativa silenciosa tras %s caso=%d" % [reason, occurrence], _pose(view) == pose)


func _check(name: String, passed: bool) -> void:
	if _check_names.has(name):
		_duplicate_checks.append(name)
	_check_names[name] = true
	_checks.append({"name": name, "passed": passed})
	print("[%s] %s" % ["OK" if passed else "FALLO", name])


func _report() -> void:
	if _reported:
		return
	_reported = true
	for view: Athlete in _views:
		if is_instance_valid(view):
			view.free()
	_views.clear()
	var native: Dictionary = _native_errors.snapshot()
	var actual_expected: Dictionary[String, int] = {}
	var unexpected: Array[Dictionary] = []
	for entry: Dictionary in native["entries"]:
		if int(entry["type"]) == Logger.ERROR_TYPE_WARNING:
			continue
		var message: String = str(entry["rationale"]) if not str(entry["rationale"]).is_empty() else str(entry["code"])
		if int(entry["type"]) == Logger.ERROR_TYPE_ERROR and _expected_errors.has(message):
			actual_expected[message] = int(actual_expected.get(message, 0)) + 1
		else:
			unexpected.append(entry)
	_check("Escenarios de gestos completados", _completed)
	_check("Identificadores de comprobación de gestos únicos", _duplicate_checks.is_empty())
	_check("Errores intencionales medidos coinciden exactamente con casos negativos",
		actual_expected == _expected_errors)
	_check("Sin errores nativos inesperados ni errores de script o shader",
		unexpected.is_empty() and native["script_error_count"] == 0 and native["shader_error_count"] == 0)
	var passed: int = 0
	var failures: Array[String] = []
	for check: Dictionary in _checks:
		if check["passed"]:
			passed += 1
		else:
			failures.append(check["name"])
	var ok: bool = failures.is_empty()
	print("FUTSAL_GESTURE_TESTS " + JSON.stringify({
		"ok": ok, "passed": passed, "total": _checks.size(), "failures": failures,
		"checks": _checks, "duplicate_checks": _duplicate_checks,
		"native_errors": native, "expected_error_counts": _expected_errors,
		"observed_expected_error_counts": actual_expected, "unexpected_errors": unexpected,
		"headless": DisplayServer.get_name() == "headless",
		"scope": "componentes visuales; física, cámaras, 20 PNG y revisión nativa integrada se verifican aparte",
	}))
	OS.remove_logger(_native_errors)
	quit(0 if ok else 1)
