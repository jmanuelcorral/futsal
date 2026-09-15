extends Camera3D
## Retransmisión lateral y transición de córner; solo presentación, sin shake.

const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Event = preload("res://match/simulation/match_event.gd")
const OFFSET: Vector3 = Vector3(0.0, 17.0, 23.0)
const PREVIEW_OFFSET: Vector3 = Vector3(0.0, 18.0, 25.0)
const CORNER_FOV: float = 60.0
const TRANSITION_TICKS: int = 45
const TRANSITION_SIDE_ARC: float = 3.0
const DIRECTION_CHANGE_COSINE: float = 0.9998477
const BALL_FRAME_LIMIT: Vector2 = Vector2(0.90, 0.72)

var _focus: Vector3 = Vector3.ZERO
var _look_target: Vector3 = Vector3.ZERO
var _tracked_ball: Vector3 = Vector3.ZERO
var _initialized: bool = false
var _mode: int = -1
var _distance: float = PREVIEW_OFFSET.length()
var _input_direction: Vector2 = Vector2.ZERO
var _input_right: Vector3 = Vector3.RIGHT
var _input_down: Vector3 = Vector3.BACK
var _input_projection_locked: bool = false
var _input_projection_serial: int = 0
var _corner_active: bool = false
var _corner_restart_id: int = -1
var _corner_taker_id: int = -1
var _corner_spot: Vector3 = Vector3.ZERO
var _corner_transform: Transform3D = Transform3D.IDENTITY
var _broadcast_transform: Transform3D = Transform3D.IDENTITY
var _broadcast_fov: float = 46.0
var _broadcast_available: bool = false
var _transition_from: Transform3D = Transform3D.IDENTITY
var _transition_from_target: Vector3 = Vector3.ZERO
var _transition_from_fov: float = 46.0
var _transition_started_tick: int = -1
var _context_tick: int = 0
var _last_return_event_id: int = -1


func _ready() -> void:
	current = true
	fov = 46.0
	near = 0.1
	far = 110.0
	keep_aspect = Camera3D.KEEP_HEIGHT


func follow(state: Snapshot, ball_at: Vector3, delta: float, snap: bool = false) -> void:
	sync_context(state)
	if state.phase == Snapshot.Phase.PAUSED and _broadcast_available:
		return
	_tracked_ball = ball_at
	var first_pose: bool = not _broadcast_available
	fov = 48.0 if state.mode == Setup.Mode.PREVIEW_5V5 else 46.0
	_follow_broadcast(state, ball_at, delta, snap)
	_broadcast_transform = global_transform
	_broadcast_fov = fov
	_broadcast_available = true
	if first_pose:
		_transition_from = _broadcast_transform
		_transition_from_fov = _broadcast_fov
		_transition_from_target = _focus
	_apply_context_pose()


func sync_context(state: Snapshot) -> void:
	if state.tick < _context_tick:
		reset_context()
	_context_tick = state.tick
	_tracked_ball = state.ball_position
	var restart: Rules.RestartState = state.restart
	var own_corner: bool = restart.kind == Rules.RestartKind.CORNER \
		and restart.awarded_team_id == Snapshot.Team.HOME \
		and restart.stage in [Rules.RestartStage.STOPPED, Rules.RestartStage.PLACEMENT, Rules.RestartStage.READY] \
		and state.phase in [Snapshot.Phase.RESTART_PAUSE, Snapshot.Phase.PAUSED]
	if own_corner:
		var new_corner: bool = not _corner_active or _corner_restart_id != restart.id
		_corner_transform = _corner_pose(restart.spot)
		_corner_spot = restart.spot
		_corner_restart_id = restart.id
		_corner_taker_id = restart.taker_actor_id
		if new_corner:
			_begin_transition()
			_last_return_event_id = -1
		_corner_active = true
	elif _corner_active:
		_begin_transition()
		_corner_active = false
	if _broadcast_available and state.phase != Snapshot.Phase.PAUSED:
		_apply_context_pose()


func react(event: Event) -> void:
	if event.kind in [Event.Kind.PASS, Event.Kind.SHOT] and event.success \
			and event.actor_id == _corner_taker_id and _corner_restart_id >= 0 \
			and (_corner_active or _transition_started_tick == event.tick):
		_last_return_event_id = event.event_id
		if _corner_active:
			_context_tick = event.tick
			_begin_transition()
			_corner_active = false


func reset_context() -> void:
	_corner_active = false
	_corner_restart_id = -1
	_corner_taker_id = -1
	_corner_spot = Vector3.ZERO
	_corner_transform = Transform3D.IDENTITY
	_broadcast_available = false
	_transition_from = Transform3D.IDENTITY
	_transition_from_target = Vector3.ZERO
	_look_target = Vector3.ZERO
	_tracked_ball = Vector3.ZERO
	_transition_started_tick = -1
	_context_tick = 0
	_last_return_event_id = -1
	_initialized = false
	release_input_projection()


func get_camera_state() -> Dictionary:
	var elapsed: int = maxi(0, _context_tick - _transition_started_tick)
	var transitioning: bool = _transition_started_tick >= 0 and elapsed < TRANSITION_TICKS
	return {
		"mode": "corner" if _corner_active else ("returning" if transitioning else "broadcast"),
		"restart_id": _corner_restart_id, "taker_actor_id": _corner_taker_id, "tick": _context_tick,
		"restart_spot": [_corner_spot.x, _corner_spot.y, _corner_spot.z],
		"transition_started_tick": _transition_started_tick,
		"transition_ticks_elapsed": mini(elapsed, TRANSITION_TICKS),
		"transition_complete": not transitioning, "accepted_return_event_id": _last_return_event_id,
		"position": [global_position.x, global_position.y, global_position.z],
		"look_target": [_look_target.x, _look_target.y, _look_target.z],
		"tracked_ball": [_tracked_ball.x, _tracked_ball.y, _tracked_ball.z],
		"rotation": [global_rotation.x, global_rotation.y, global_rotation.z], "fov": fov,
		"fov_axis": "vertical" if keep_aspect == Camera3D.KEEP_HEIGHT else "horizontal",
		"keep_aspect": keep_aspect, "near": near, "far": far,
		"input_projection_serial": _input_projection_serial, "input_locked": _input_projection_locked,
		"input_right": [_input_right.x, _input_right.y, _input_right.z],
		"input_down": [_input_down.x, _input_down.y, _input_down.z],
	}


func _begin_transition() -> void:
	_transition_from = global_transform
	_transition_from_target = _look_target
	_transition_from_fov = fov
	_transition_started_tick = _context_tick


func _apply_context_pose() -> void:
	var destination: Transform3D = _corner_transform if _corner_active else _broadcast_transform
	var destination_fov: float = CORNER_FOV if _corner_active else _broadcast_fov
	var weight: float = 1.0
	if _transition_started_tick >= 0:
		weight = smoothstep(0.0, float(TRANSITION_TICKS), float(_context_tick - _transition_started_tick))
	if not _corner_active and weight >= 1.0:
		# El encuadre broadcast ya incluye a los atletas; no reorientarlo sólo al balón.
		fov = _broadcast_fov
		global_transform = _broadcast_transform
		_look_target = _focus
		return
	fov = lerpf(_transition_from_fov, destination_fov, weight)
	global_transform = _blend_pose(_transition_from, destination, weight)


func _follow_broadcast(state: Snapshot, ball_at: Vector3, delta: float, snap: bool) -> void:
	if _mode != state.mode:
		_mode = state.mode
		_initialized = false
		fov = 48.0 if state.mode == Setup.Mode.PREVIEW_5V5 else 46.0
	if state.mode == Setup.Mode.PREVIEW_5V5:
		_follow_preview(state, ball_at, delta, snap)
		return
	var human: Snapshot.ActorSnapshot = state.actor(state.selected_actor_id)
	var lead: Vector3 = Vector3(state.ball_velocity.x, 0.0, state.ball_velocity.z) * 0.13
	lead = lead.limit_length(1.4)
	var support: Vector3 = (human.position - ball_at).limit_length(18.0) * 0.3
	var desired: Vector3 = ball_at + lead + support
	desired.x = clampf(desired.x, -17.0, 17.0)
	desired.z = clampf(desired.z, -8.0, 8.0)
	desired.y = 0.55
	var initialize: bool = snap or not _initialized
	if initialize:
		_focus = desired
	else:
		var step: Vector3 = (desired - _focus) * (1.0 - exp(-5.8 * delta))
		_focus += step.limit_length(20.0 * delta)
	# El balón puede alejarse 32 m/s; limita el retraso sin cambiar yaw ni FOV.
	var error: Vector3 = Vector3(ball_at.x - _focus.x, 0.0, ball_at.z - _focus.z)
	if error.length() > 4.0:
		_focus += error - error.limit_length(4.0)
	var required: float = _micro_distance(human, ball_at)
	if initialize:
		_distance = required
	else:
		_distance = move_toward(_distance, required, (45.0 if required > _distance else 7.0) * delta)
	_initialized = true
	position = _focus + OFFSET.normalized() * _distance
	look_at(_focus, Vector3.UP)


func _micro_distance(actor: Snapshot.ActorSnapshot, ball_at: Vector3) -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(1.0, viewport_size.y)
	var tangent: float = tan(deg_to_rad(fov) * 0.5)
	var backward: Vector3 = OFFSET.normalized()
	var up: Vector3 = Vector3(0.0, backward.z, -backward.y)
	var required: float = OFFSET.length()
	var points: PackedVector3Array = [ball_at - Vector3.ONE * Tuning.BALL_RADIUS,
		ball_at + Vector3.ONE * Tuning.BALL_RADIUS]
	for x: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
		for z: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
			points.append(actor.position + Vector3(x, 0.0, z))
			points.append(actor.position + Vector3(x, Tuning.ACTOR_HEIGHT, z))
	for point: Vector3 in points:
		var relative: Vector3 = point - _focus
		var horizontal: float = absf(relative.x) / (tangent * aspect * 0.94)
		var vertical: float = absf(relative.dot(up)) / (tangent * 0.6)
		required = maxf(required, relative.dot(backward) + maxf(horizontal, vertical))
	return required


func _follow_preview(state: Snapshot, ball_at: Vector3, delta: float, snap: bool) -> void:
	var desired: Vector3 = Vector3(clampf(ball_at.x * 0.05, -0.7, 0.7),
		0.55, clampf(ball_at.z * 0.15, -1.2, 1.2))
	if snap or not _initialized:
		_focus = desired
	else:
		_focus = _focus.lerp(desired, 1.0 - exp(-3.5 * delta))
	var required: float = _preview_distance(state, ball_at)
	if snap or not _initialized:
		_distance = required
	else:
		_distance = maxf(required, lerpf(_distance, required, 1.0 - exp(-2.0 * delta)))
	_initialized = true
	position = _focus + PREVIEW_OFFSET.normalized() * _distance
	far = maxf(110.0, _distance + 50.0)
	look_at(_focus, Vector3.UP)


func _preview_distance(state: Snapshot, ball_at: Vector3) -> float:
	var points: PackedVector3Array = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		for x: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
			for z: float in [-Tuning.ACTOR_RADIUS, Tuning.ACTOR_RADIUS]:
				points.append(actor.position + Vector3(x, 0.0, z))
				points.append(actor.position + Vector3(x, Tuning.ACTOR_HEIGHT, z))
	for x: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
		for y: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
			for z: float in [-Tuning.BALL_RADIUS, Tuning.BALL_RADIUS]:
				points.append(ball_at + Vector3(x, y, z))
	for end: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			points.append(Vector3(end * 21.65, 0.0, side * 1.65))
			points.append(Vector3(end * 21.65, 2.15, side * 1.65))
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(1.0, viewport_size.y)
	var tangent: float = tan(deg_to_rad(fov) * 0.5)
	var backward: Vector3 = PREVIEW_OFFSET.normalized()
	var up: Vector3 = Vector3(0.0, backward.z, -backward.y)
	var required: float = PREVIEW_OFFSET.length()
	# Ajustar distancia, no geometría ni visibilidad de jugadores. FOV es vertical
	# con KEEP_HEIGHT; el margen vertical separa la pista de los paneles del HUD.
	for point: Vector3 in points:
		var relative: Vector3 = point - _focus
		var horizontal: float = absf(relative.x) / (tangent * aspect * 0.96)
		var vertical: float = absf(relative.dot(up)) / (tangent * 0.54)
		required = maxf(required, relative.dot(backward) + maxf(horizontal, vertical))
	return required


func screen_direction_to_court(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		release_input_projection()
		return Vector2.ZERO
	var normalized: Vector2 = direction.normalized()
	if not _input_projection_locked or normalized.dot(_input_direction) < DIRECTION_CHANGE_COSINE:
		_input_direction = normalized
		_input_right = global_basis.x
		_input_down = global_basis.z
		_input_right.y = 0.0
		_input_down.y = 0.0
		_input_right = _input_right.normalized()
		_input_down = _input_down.normalized()
		_input_projection_locked = true
		_input_projection_serial += 1
	var planar: Vector3 = _input_right * direction.x + _input_down * direction.y
	return Vector2(planar.x, planar.z).limit_length(1.0)


func release_input_projection() -> void:
	_input_projection_locked = false
	_input_direction = Vector2.ZERO


func get_input_projection() -> Dictionary:
	return {
		"serial": _input_projection_serial, "locked": _input_projection_locked,
		"direction": _input_direction, "right": _input_right, "down": _input_down,
	}


func _corner_pose(ball_at: Vector3) -> Transform3D:
	var end: float = signf(ball_at.x)
	var side: float = signf(ball_at.z)
	var eye: Vector3 = Vector3(ball_at.x + end * 2.2, 2.9, ball_at.z + side * 3.1)
	eye.x = clampf(eye.x, -23.2, 23.2)
	eye.z = clampf(eye.z, -13.2, 13.2)
	var target: Vector3 = _corner_look_target(ball_at)
	return Transform3D(Basis.looking_at((target - eye).normalized(), Vector3.UP), eye)


func _corner_look_target(ball_at: Vector3) -> Vector3:
	return Vector3(ball_at.x - signf(ball_at.x) * 2.0, 0.4,
		ball_at.z - signf(ball_at.z) * 1.1)


func _blend_pose(from: Transform3D, to: Transform3D, weight: float) -> Transform3D:
	var eye: Vector3 = from.origin.lerp(to.origin, weight)
	# Evitar el paso casi cenital que concentra el giro al final del córner lejano.
	if weight > 0.0 and weight < 1.0 and _corner_restart_id >= 0:
		eye.x += signf(_corner_spot.x) * TRANSITION_SIDE_ARC * sin(weight * PI)
		eye.x = clampf(eye.x, -23.2, 23.2)
	var destination_target: Vector3 = _corner_look_target(_corner_spot) if _corner_active else _focus
	var intended_target: Vector3 = _transition_from_target.lerp(destination_target, weight)
	# La orientación nace del ojo ya interpolado. Mezclar yaw/pitch por separado
	# permitía mirar en sentido contrario al balón a mitad del recorrido.
	_look_target = _framed_look_target(eye, intended_target)
	return Transform3D(Basis.looking_at(_look_target - eye, Vector3.UP), eye)


func _framed_look_target(eye: Vector3, intended: Vector3) -> Vector3:
	var target: Vector3 = _safe_look_target(eye, intended)
	if _ball_fits(eye, target):
		return target
	var lower: float = 0.0
	var upper: float = 1.0
	for step: int in 18:
		var middle: float = (lower + upper) * 0.5
		var candidate: Vector3 = _safe_look_target(eye, target.lerp(_tracked_ball, middle))
		if _ball_fits(eye, candidate):
			upper = middle
		else:
			lower = middle
	return _safe_look_target(eye, target.lerp(_tracked_ball, upper))


func _safe_look_target(eye: Vector3, target: Vector3) -> Vector3:
	var offset: Vector3 = target - eye
	if Vector2(offset.x, offset.z).length_squared() < 0.000001:
		var forward: Vector3 = -_transition_from.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.000001:
			forward = Vector3.FORWARD
		target += forward.normalized() * maxf(0.1, absf(offset.y) * 0.15)
	return target


func _ball_fits(eye: Vector3, target: Vector3) -> bool:
	var orientation: Basis = Basis.looking_at(target - eye, Vector3.UP)
	var relative: Vector3 = orientation.transposed() * (_tracked_ball - eye)
	var radius: float = Tuning.BALL_RADIUS * sqrt(3.0)
	var depth: float = -relative.z - radius
	if depth <= near:
		return false
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / maxf(1.0, size.y)
	var half_height: float = depth * tan(deg_to_rad(fov) * 0.5)
	return absf(relative.x) + radius <= half_height * aspect * BALL_FRAME_LIMIT.x \
		and absf(relative.y) + radius <= half_height * BALL_FRAME_LIMIT.y
