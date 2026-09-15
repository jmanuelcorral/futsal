extends Node3D
## Silueta adulta y gestos provisionales; no rig/animación artística aprobados.
## Pies en el origen y frente local -Z, según el contrato de MatchSnapshot.

const Geometry = preload("res://match/presentation/geometry.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Event = preload("res://match/simulation/match_event.gd")
const RuleTypes = preload("res://match/simulation/match_rule_types.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const LEG_SEGMENT_LENGTH: float = 0.415
const MAX_LEG_REACH: float = 0.824
const ARM_SEGMENT_LENGTH: float = 0.285
const MAX_ARM_REACH: float = 0.566
const ANKLE_HEIGHT: float = 0.08
const SHOE_SIZE: Vector3 = Vector3(0.13, 0.10, 0.28)
const SOLE_SIZE: Vector3 = Vector3(0.134, 0.035, 0.282)
const SHOE_OFFSET: Vector3 = Vector3(0, -0.024, -0.055)
const SOLE_OFFSET: Vector3 = Vector3(0, -0.063, -0.055)
const SHOE_TOE_REACH: float = SHOE_SIZE.z * 0.5 - SHOE_OFFSET.z
const CANCEL_BLEND_TICKS: float = 3.0
const PRESENTATION_ERROR: String = "AthleteView rejected invalid presentation data: "

var actor_id: int = 0
var kit_color: Color = Color("#172f4d")
var dorsal: int = 7

var _body: Node3D
var _marker: MeshInstance3D
var _selection_marker: Label3D
var _legs: Array[Array] = []
var _arms: Array[Array] = []
var _gait: float = 0.0
var _save_remaining: float = 0.0
var _keeper: bool = false
var _context_valid: bool = false
var _context_before_tick: int = 0
var _context_tick: int = 0
var _context_owner_id: int = -1
var _context_previous_in_hands: bool = false
var _context_phase: Snapshot.Phase = Snapshot.Phase.READY
var _ball_before: Vector3 = Vector3.ZERO
var _ball_current: Vector3 = Vector3.ZERO
var _last_render_tick: float = -1.0
var _gesture_kind: RuleTypes.GestureKind = RuleTypes.GestureKind.NONE
var _gesture_started_tick: int = -1
var _gesture_duration_ticks: int = 0
var _gesture_contact_tick: int = -1
var _gesture_progress: float = 0.0
var _gesture_weight: float = 0.0
var _gesture_cancel_tick: float = -1.0
var _gesture_direction_world: Vector3 = Vector3.FORWARD
var _gesture_contact_world: Vector3 = Vector3.ZERO
var _foot_forward_world: Vector3 = Vector3.FORWARD
var _support_forward_world: Vector3 = Vector3.FORWARD
var _support_world: Vector3 = Vector3.ZERO
var _contact_leg: int = 1
var _support_leg: int = 0
var _event_started_tick: int = -1
var _event_contact_tick: int = -1
var _event_gesture_kind: RuleTypes.GestureKind = RuleTypes.GestureKind.NONE
var _event_contact_world: Vector3 = Vector3.ZERO
var _last_event_id: int = -1
var _last_event_tick: int = -1
var _last_validation_error: String = ""
var _posed_ankles: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func configure(id: int, color: Color, number: int) -> void:
	actor_id = id
	kit_color = color
	dorsal = number
	_keeper = id in [2, 3]
	_build()
	reset_pose()


## El ActorSnapshot no contiene su tick ni el balón. El host copia este contexto
## antes de present(); no hay reloj libre ni ancla inventada para los gestos.
func sync_context(before: Snapshot, state: Snapshot) -> void:
	if before == null or state == null:
		_context_valid = false
		_reject_pose("context_null")
		return
	if before.tick < 0 or state.tick < before.tick:
		_context_valid = false
		_reject_pose("context_ticks")
		return
	if not Snapshot.Phase.values().has(state.phase):
		_context_valid = false
		_reject_pose("context_phase")
		return
	if not before.ball_position.is_finite() or not state.ball_position.is_finite():
		_context_valid = false
		_reject_pose("context_ball")
		return
	_context_before_tick = before.tick
	_context_tick = state.tick
	_context_owner_id = state.ball_owner_id
	_context_phase = state.phase
	_ball_before = before.ball_position
	_ball_current = state.ball_position
	var previous_actor: Snapshot.ActorSnapshot = before.actor(actor_id)
	_context_previous_in_hands = previous_actor != null and previous_actor.ball_in_hands
	_context_valid = true


func present(before: Snapshot.ActorSnapshot, actor: Snapshot.ActorSnapshot,
		weight: float, delta: float, has_ball: bool, charge: float) -> void:
	var error: String = _pose_input_error(before, actor, weight, delta, charge)
	if not error.is_empty():
		_reject_pose(error)
		return
	_last_validation_error = ""
	position = before.position.lerp(actor.position, weight)
	position.y = maxf(0.0, position.y)
	rotation.y = lerp_angle(before.facing_yaw, actor.facing_yaw, weight)
	_marker.rotation.y = -rotation.y
	_marker.scale = Vector3.ONE * (1.06 if has_ball else 1.0)
	var controlled: bool = actor.human_controlled and actor.team_id == Snapshot.Team.HOME
	if _selection_marker != null:
		_selection_marker.visible = controlled
	(_marker.material_override as StandardMaterial3D).albedo_color = \
		Color("#eee8d8") if controlled else Color("#314350")
	var render_tick: float = lerpf(float(_context_before_tick), float(_context_tick), weight)
	var pose_delta: float = delta
	if _context_valid:
		if _context_phase == Snapshot.Phase.PAUSED:
			render_tick = float(_context_tick)
		if _last_render_tick >= 0.0 and render_tick < _last_render_tick:
			_clear_gesture()
			_gait = 0.0
			_save_remaining = 0.0
			_event_started_tick = -1
			_event_contact_tick = -1
			_event_gesture_kind = RuleTypes.GestureKind.NONE
			_event_contact_world = Vector3.ZERO
			_last_event_id = -1
			_last_event_tick = -1
		pose_delta = maxf(0.0, render_tick - _last_render_tick) / float(Tuning.PHYSICS_HZ) \
			if _last_render_tick >= 0.0 else 0.0
		_last_render_tick = render_tick
		if _context_phase not in [Snapshot.Phase.PLAYING, Snapshot.Phase.RESTART_PAUSE]:
			pose_delta = 0.0
	_save_remaining = maxf(0.0, _save_remaining - pose_delta)
	var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	var movement: Vector3 = Basis(Vector3.UP, -rotation.y) * Vector3(actor.velocity.x, 0, actor.velocity.z)
	movement = movement.normalized() if speed > 0.1 else Vector3.FORWARD
	var frequency: float = 1.6 + speed * 0.30
	if speed > 0.12:
		_gait = fposmod(_gait + pose_delta * frequency, 1.0)
	var motion: float = clampf(speed / 1.2, 0.0, 1.0)
	var crouch: float = minf(speed * 0.012, 0.095) + (0.04 if _keeper else 0.0)
	_body.position = Vector3(0, -crouch + sin(_gait * TAU * 2.0) * 0.012 * motion, 0)
	var sprint_blend: float = clampf((speed - 1.5) / 5.5, 0.0, 1.0)
	_body.rotation = Vector3(-sprint_blend * 0.095, 0, 0)
	_update_gesture(actor, render_tick)
	_apply_gesture_body()
	var holding: bool = actor.ball_in_hands or (_keeper
		and _gesture_kind == RuleTypes.GestureKind.KEEPER_THROW
		and render_tick < float(_gesture_contact_tick) and _context_previous_in_hands)
	if holding:
		_body.rotation.x = -0.09
	var held_anchor: Vector3 = _ball_before.lerp(_ball_current, weight)
	var body_inverse: Basis = _body.global_basis.inverse()
	var base_foot_basis: Basis = body_inverse * global_basis
	for side_index: int in 2:
		var side: float = -1.0 if side_index == 0 else 1.0
		var phase: float = fposmod(_gait + float(side_index) * 0.5, 1.0)
		var stride: float = minf(0.95, speed * 0.42 / frequency)
		var travel: float
		var lift: float = 0.0
		if phase < 0.42:
			travel = lerpf(0.5, -0.5, phase / 0.42)
		else:
			var swing: float = (phase - 0.42) / 0.58
			travel = lerpf(-0.5, 0.5, smoothstep(0.0, 1.0, swing))
			lift = sin(swing * PI) * (0.08 + speed * 0.025) * motion
		var ankle: Vector3 = Vector3(side * 0.115, ANKLE_HEIGHT - _body.position.y + lift, 0.0)
		ankle += movement * stride * travel
		if side_index == 1 and charge > 0.0 and speed < 2.0 \
				and actor.ball_contact_reachable and _gesture_weight == 0.0:
			ankle.z += charge * 0.16
		var foot_basis: Basis = base_foot_basis
		if _gesture_weight > 0.0:
			var leg_weight: float = _gesture_weight
			var target: Vector3
			var foot_forward: Vector3 = _foot_forward_world
			if side_index == _support_leg:
				leg_weight *= 1.0 - smoothstep(0.08, 0.45, maxf(0.0, _gesture_progress))
				target = _support_world
				foot_forward = _support_forward_world
			elif _gesture_kind == RuleTypes.GestureKind.KEEPER_THROW:
				leg_weight *= 1.0 - smoothstep(0.1, 0.65, maxf(0.0, _gesture_progress))
				target = _support_world + global_basis * Vector3(side * 0.30, 0, -0.10)
				foot_forward = _support_forward_world
			else:
				target = _gesture_ankle_world()
			ankle = ankle.lerp(_body.to_local(target), leg_weight)
			var target_basis: Basis = body_inverse * Basis.looking_at(foot_forward, Vector3.UP)
			foot_basis = Basis(base_foot_basis.get_rotation_quaternion().slerp(
				target_basis.get_rotation_quaternion(), leg_weight))
		_pose_leg(side_index, Vector3(side * 0.10, 0.89, 0.0), ankle, foot_basis)
		var arm_swing: float = sin((_gait + float(side_index) * 0.5) * TAU) * motion
		var shoulder: Vector3 = Vector3(side * 0.215, 1.40, 0.0)
		var arm_range: float = lerpf(0.16, 0.28, sprint_blend)
		var hand_depth: float = lerpf(0.19, 0.34, sprint_blend)
		var elbow: Vector3 = Vector3(side * (0.28 + charge * 0.07), 1.16, arm_swing * arm_range)
		var hand: Vector3 = Vector3(side * (0.30 + charge * 0.11), lerpf(0.98, 0.90, sprint_blend), -0.06 - arm_swing * hand_depth)
		if _keeper:
			elbow = Vector3(side * 0.32, 1.17, -0.06)
			hand = Vector3(side * 0.30, 1.04, -0.27)
			if _save_remaining > 0.0:
				hand += Vector3(side * 0.11, 0.13, -0.10) * (_save_remaining / 0.25)
		if holding:
			hand = _body.to_local(_grip_world(held_anchor, side))
			var grip: Array[Vector3] = _arm_ik(shoulder, hand, side)
			elbow = grip[0]
			hand = grip[1]
		elif _gesture_weight > 0.0:
			var target_hand: Vector3
			if _gesture_kind == RuleTypes.GestureKind.KEEPER_THROW:
				var progress: float = maxf(0.0, _gesture_progress)
				var release: float = smoothstep(0.0, 0.55, progress)
				var hand_world: Vector3 = _grip_world(_gesture_contact_world, side)
				if side_index == 1:
					hand_world += _gesture_direction_world * 0.28 * release
					hand_world += Vector3.UP * 0.16 * sin(progress * PI)
				else:
					hand_world = hand_world.lerp(_body.to_global(hand), release)
				target_hand = _body.to_local(hand_world)
			else:
				var local_direction: Vector3 = global_basis.inverse() * _gesture_direction_world
				var reach: float = 0.14 if _gesture_kind == RuleTypes.GestureKind.PACE_CHANGE else 0.20
				target_hand = Vector3(side * (0.34 + reach), 1.06,
					-side * local_direction.x * 0.22 + (0.14 if side_index == _contact_leg else -0.18))
				if _gesture_kind == RuleTypes.GestureKind.TACKLE:
					target_hand.y += 0.12
				elif _gesture_kind == RuleTypes.GestureKind.PACE_CHANGE:
					target_hand.z = 0.22 if side_index == _contact_leg else -0.32
			var gesture_arm: Array[Vector3] = _arm_ik(shoulder, target_hand, side)
			elbow = elbow.lerp(gesture_arm[0], _gesture_weight)
			hand = hand.lerp(gesture_arm[1], _gesture_weight)
		_pose_arm(side_index, shoulder, elbow, hand)


func react(event: Event, actor: Snapshot.ActorSnapshot) -> void:
	if event == null or actor == null:
		_reject_pose("event_null")
		return
	if not Event.Kind.values().has(event.kind) or not RuleTypes.GestureKind.values().has(event.gesture_kind):
		_reject_pose("event_kind")
		return
	if not RuleTypes.LaunchKind.values().has(event.launch_kind):
		_reject_pose("launch_kind")
		return
	if not event.position.is_finite() or not event.contact_point.is_finite() \
			or not event.velocity.is_finite() or event.tick < 0:
		_reject_pose("event_contact")
		return
	if event.actor_id != actor_id or actor.actor_id != actor_id or not event.success:
		return
	if event.tick < _last_event_tick or (event.tick == _last_event_tick and event.event_id <= _last_event_id):
		return
	if event.kind == Event.Kind.SAVE:
		_save_remaining = 0.25
		_last_event_tick = event.tick
		_last_event_id = event.event_id
		return
	if event.kind not in [Event.Kind.PASS, Event.Kind.SHOT, Event.Kind.TACKLE, Event.Kind.DRIBBLE]:
		return
	if event.tick < actor.gesture_started_tick:
		return
	var expected: RuleTypes.GestureKind = actor.gesture_kind
	if event.kind == Event.Kind.PASS:
		expected = RuleTypes.GestureKind.KEEPER_THROW \
			if event.launch_kind == RuleTypes.LaunchKind.KEEPER_THROW else RuleTypes.GestureKind.FOOT_KICK
		if event.launch_kind == RuleTypes.LaunchKind.FOOT_SHOT:
			_reject_pose("launch_event")
			return
	elif event.kind == Event.Kind.SHOT:
		expected = RuleTypes.GestureKind.FOOT_KICK
		if event.launch_kind != RuleTypes.LaunchKind.FOOT_SHOT:
			_reject_pose("launch_event")
			return
	elif event.kind == Event.Kind.TACKLE:
		expected = RuleTypes.GestureKind.TACKLE
	elif expected not in [RuleTypes.GestureKind.CUT, RuleTypes.GestureKind.PACE_CHANGE]:
		_reject_pose("gesture_event")
		return
	if expected == RuleTypes.GestureKind.NONE or actor.gesture_kind != expected or event.gesture_kind != expected:
		_reject_pose("gesture_event")
		return
	if actor.gesture_started_tick < 0 or actor.gesture_duration_ticks <= 0 \
			or event.tick >= actor.gesture_started_tick + actor.gesture_duration_ticks:
		_reject_pose("event_window")
		return
	_event_started_tick = actor.gesture_started_tick
	_event_contact_tick = event.tick
	_event_gesture_kind = expected
	_event_contact_world = event.contact_point
	_last_event_tick = event.tick
	_last_event_id = event.event_id


func reset_pose() -> void:
	_gait = 0.0
	_save_remaining = 0.0
	_context_valid = false
	_last_render_tick = -1.0
	_event_started_tick = -1
	_event_contact_tick = -1
	_event_gesture_kind = RuleTypes.GestureKind.NONE
	_event_contact_world = Vector3.ZERO
	_last_event_id = -1
	_last_event_tick = -1
	_last_validation_error = ""
	_clear_gesture()
	if _body == null:
		return
	_body.position = Vector3.ZERO
	_body.rotation = Vector3.ZERO
	for index: int in 2:
		var side: float = -1.0 if index == 0 else 1.0
		_pose_leg(index, Vector3(side * 0.10, 0.89, 0), Vector3(side * 0.115, ANKLE_HEIGHT, 0))
		_pose_arm(index, Vector3(side * 0.215, 1.40, 0),
			Vector3(side * 0.28, 1.16, 0), Vector3(side * 0.30, 0.98, -0.06))
	_marker.scale = Vector3.ONE
	(_marker.material_override as StandardMaterial3D).albedo_color = Color("#314350")
	if _selection_marker != null:
		_selection_marker.visible = false


func _pose_input_error(before: Snapshot.ActorSnapshot, actor: Snapshot.ActorSnapshot,
		weight: float, delta: float, charge: float) -> String:
	if before == null or actor == null or _body == null:
		return "actor_null"
	if before.actor_id != actor_id or actor.actor_id != actor_id:
		return "actor_identity"
	if not Snapshot.Team.values().has(actor.team_id) or not Snapshot.Role.values().has(actor.role):
		return "actor_kind"
	if not is_finite(weight) or weight < 0.0 or weight > 1.0:
		return "interpolation_weight"
	if not is_finite(delta) or delta < 0.0 or not is_finite(charge) or charge < 0.0 or charge > 1.0:
		return "frame_parameters"
	if not before.position.is_finite() or not actor.position.is_finite() \
			or not before.velocity.is_finite() or not actor.velocity.is_finite() \
			or not is_finite(before.facing_yaw) or not is_finite(actor.facing_yaw) \
			or not is_finite(Vector2(actor.velocity.x, actor.velocity.z).length()):
		return "actor_transform"
	if not RuleTypes.GestureKind.values().has(actor.gesture_kind):
		return "gesture_kind"
	if not actor.gesture_direction.is_finite() or not actor.gesture_contact_position.is_finite():
		return "gesture_vectors"
	if actor.ball_in_hands and not _keeper:
		return "hands_role"
	if actor.ball_in_hands or actor.gesture_kind != RuleTypes.GestureKind.NONE:
		if not _context_valid:
			return "snapshot_context_required"
	if actor.ball_in_hands and _context_owner_id != actor_id:
		return "hands_owner"
	if actor.gesture_kind != RuleTypes.GestureKind.NONE:
		if actor.gesture_started_tick < 0 or actor.gesture_duration_ticks <= 0 \
				or actor.gesture_started_tick > _context_tick:
			return "gesture_window"
		var direction_length: float = Vector2(actor.gesture_direction.x, actor.gesture_direction.z).length_squared()
		if not is_finite(direction_length) or direction_length < 0.0001:
			return "gesture_direction"
		if actor.gesture_kind == RuleTypes.GestureKind.KEEPER_THROW and not _keeper:
			return "throw_role"
	return ""


func _reject_pose(reason: String) -> void:
	_last_validation_error = reason
	push_error(PRESENTATION_ERROR + reason)


func _clear_gesture() -> void:
	_gesture_kind = RuleTypes.GestureKind.NONE
	_gesture_started_tick = -1
	_gesture_duration_ticks = 0
	_gesture_contact_tick = -1
	_gesture_progress = 0.0
	_gesture_weight = 0.0
	_gesture_cancel_tick = -1.0
	_gesture_contact_world = Vector3.ZERO
	_gesture_direction_world = Vector3.FORWARD
	_foot_forward_world = Vector3.FORWARD
	_support_forward_world = Vector3.FORWARD
	_support_world = Vector3.ZERO
	_contact_leg = 1
	_support_leg = 0


func _update_gesture(actor: Snapshot.ActorSnapshot, render_tick: float) -> void:
	if actor.gesture_kind == RuleTypes.GestureKind.NONE:
		if _gesture_kind != RuleTypes.GestureKind.NONE:
			if _gesture_cancel_tick < 0.0:
				_gesture_cancel_tick = float(_context_tick)
			_gesture_envelope(minf(render_tick, _gesture_cancel_tick))
			_gesture_weight *= 1.0 - smoothstep(0.0, CANCEL_BLEND_TICKS,
				maxf(0.0, render_tick - _gesture_cancel_tick))
			if _gesture_weight <= 0.0:
				_clear_gesture()
		return
	if render_tick >= float(actor.gesture_started_tick + actor.gesture_duration_ticks):
		_clear_gesture()
		return
	if _gesture_kind != actor.gesture_kind or _gesture_started_tick != actor.gesture_started_tick:
		_clear_gesture()
		_gesture_kind = actor.gesture_kind
		_gesture_started_tick = actor.gesture_started_tick
		_gesture_duration_ticks = actor.gesture_duration_ticks
		_gesture_direction_world = Vector3(actor.gesture_direction.x, 0, actor.gesture_direction.z).normalized()
		var facing: Basis = Basis(Vector3.UP, actor.facing_yaw)
		var local_direction: Vector3 = facing.inverse() * _gesture_direction_world
		var local_contact: Vector3 = facing.inverse() * (actor.gesture_contact_position - actor.position)
		_contact_leg = 0 if local_contact.x < -0.025 else 1
		if _gesture_kind == RuleTypes.GestureKind.CUT:
			_contact_leg = 0 if local_direction.x < 0.0 else 1
		elif _gesture_kind == RuleTypes.GestureKind.KEEPER_THROW:
			_contact_leg = 1
		_support_leg = 1 - _contact_leg
		var support_side: float = -1.0 if _support_leg == 0 else 1.0
		_support_forward_world = facing * Vector3.FORWARD
		_foot_forward_world = _gesture_direction_world
		if _gesture_kind == RuleTypes.GestureKind.CUT:
			_foot_forward_world = _support_forward_world.lerp(_gesture_direction_world, 0.32).normalized()
		_support_world = actor.position + facing * Vector3(support_side * 0.15, ANKLE_HEIGHT, 0.02)
	_gesture_cancel_tick = -1.0
	var accepted_contact: bool = _event_started_tick == _gesture_started_tick and _event_gesture_kind == _gesture_kind
	_gesture_contact_tick = _event_contact_tick if accepted_contact else _gesture_started_tick
	_gesture_contact_world = _event_contact_world if accepted_contact else actor.gesture_contact_position
	_gesture_envelope(render_tick)


func _gesture_envelope(render_tick: float) -> void:
	var age: float = render_tick - float(_gesture_contact_tick)
	if age < 0.0:
		# Con contacto inmediato, la anticipación ocupa el intervalo interpolado
		# anterior, nunca retrasa el impulso físico para completar una pose.
		var anticipation: float = maxf(1.0, float(_gesture_contact_tick - _gesture_started_tick))
		_gesture_progress = clampf(age / anticipation, -1.0, 0.0)
		_gesture_weight = smoothstep(-anticipation, 0.0, age)
	else:
		var recovery: float = float(maxi(1,
			_gesture_started_tick + _gesture_duration_ticks - _gesture_contact_tick))
		_gesture_progress = clampf(age / recovery, 0.0, 1.0)
		_gesture_weight = 1.0 - smoothstep(0.22, 1.0, _gesture_progress)


func _apply_gesture_body() -> void:
	if _gesture_weight <= 0.0:
		return
	var local_direction: Vector3 = global_basis.inverse() * _gesture_direction_world
	var turn: float = clampf(atan2(-local_direction.x, -local_direction.z), -0.35, 0.35)
	var progress: float = maxf(0.0, _gesture_progress)
	_body.rotation.y += turn * _gesture_weight
	match _gesture_kind:
		RuleTypes.GestureKind.CUT:
			_body.position.y -= 0.075 * _gesture_weight
			_body.position.x += local_direction.x * 0.045 * _gesture_weight
			_body.rotation.z -= local_direction.x * 0.20 * _gesture_weight
			_body.rotation.x -= 0.08 * _gesture_weight
		RuleTypes.GestureKind.PACE_CHANGE:
			_body.position.y -= 0.05 * _gesture_weight
			_body.rotation.x -= 0.18 * _gesture_weight
		RuleTypes.GestureKind.FOOT_KICK:
			_body.position.y -= 0.035 * _gesture_weight
			_body.rotation.x -= lerpf(0.12, 0.02, progress) * _gesture_weight
		RuleTypes.GestureKind.TACKLE:
			_body.position.y -= 0.10 * _gesture_weight
			_body.rotation.x -= 0.24 * _gesture_weight
		RuleTypes.GestureKind.KEEPER_THROW:
			_body.position.y -= 0.025 * _gesture_weight
			_body.rotation.x += lerpf(0.06, -0.14, smoothstep(0.0, 0.5, progress)) * _gesture_weight


func _gesture_ankle_world() -> Vector3:
	var target: Vector3 = _gesture_contact_world - _foot_forward_world * (Tuning.BALL_RADIUS + SHOE_TOE_REACH)
	target.y = maxf(global_position.y + ANKLE_HEIGHT, _gesture_contact_world.y - SHOE_OFFSET.y)
	if _gesture_progress < 0.0:
		var anticipation: float = -_gesture_progress
		target -= _foot_forward_world * 0.18 * anticipation
		target.y += 0.06 * sin(anticipation * PI)
	else:
		var follow: float = smoothstep(0.0, 0.55, _gesture_progress)
		var distance: float = 0.20 if _gesture_kind == RuleTypes.GestureKind.PACE_CHANGE else 0.16
		target += _gesture_direction_world * distance * follow
		target.y += (0.025 if _gesture_kind == RuleTypes.GestureKind.TACKLE else 0.07) * sin(_gesture_progress * PI)
	return target


func _grip_world(anchor: Vector3, side: float) -> Vector3:
	return anchor + global_basis.x.normalized() * side * (Tuning.BALL_RADIUS + 0.025)


func _arm_ik(shoulder: Vector3, target: Vector3, side: float) -> Array[Vector3]:
	var axis: Vector3 = (target - shoulder).limit_length(MAX_ARM_REACH)
	var hand: Vector3 = shoulder + axis
	var direction: Vector3 = axis.normalized()
	var pole: Vector3 = Vector3(side, 0.05, 0.25)
	pole -= direction * pole.dot(direction)
	if pole.length_squared() < 0.001:
		pole = Vector3.FORWARD - direction * direction.dot(Vector3.FORWARD)
	if pole.length_squared() < 0.001:
		pole = Vector3.RIGHT
	var bend: float = sqrt(maxf(0.0001,
		ARM_SEGMENT_LENGTH * ARM_SEGMENT_LENGTH - axis.length_squared() * 0.25))
	return [shoulder + axis * 0.5 + pole.normalized() * bend, hand]


func _pose_arm(index: int, shoulder: Vector3, elbow: Vector3, hand: Vector3) -> void:
	_set_bone(_arms[index][0] as Node3D, shoulder, elbow)
	_set_bone(_arms[index][1] as Node3D, elbow, hand)
	_set_bone(_arms[index][3] as Node3D, shoulder, shoulder.lerp(elbow, 0.55))
	(_arms[index][2] as Node3D).position = hand


func _build() -> void:
	_body = Node3D.new()
	_body.name = "ArticulatedBody"
	add_child(_body)
	var shirt: StandardMaterial3D = Geometry.material(kit_color, 0.88)
	var ink_color: Color = Color("#eee8d8") if actor_id % 2 == 0 else Color("#172f4d")
	var contrast: StandardMaterial3D = Geometry.material(ink_color, 0.84)
	var shorts: StandardMaterial3D = Geometry.material(Color("#192e43") if actor_id % 2 == 0 else Color("#dbd5c8"), 0.9)
	var skin_colors: Array[Color] = [Color("#ad7957"), Color("#c69a79"), Color("#80573e"), Color("#ba8b66")]
	var skin: StandardMaterial3D = Geometry.material(skin_colors[actor_id % skin_colors.size()], 0.67)
	var hair: StandardMaterial3D = Geometry.material(Color("#292722"), 0.95)
	var shoe: StandardMaterial3D = Geometry.material(Color("#30363a"), 0.77)
	var rubber: StandardMaterial3D = Geometry.material(Color("#b5a387"), 0.92)
	var torso: Array[Vector3] = [
		Vector3(0.965, 0.15, 0.09), Vector3(1.00, 0.18, 0.108),
		Vector3(1.14, 0.172, 0.105), Vector3(1.30, 0.215, 0.12),
		Vector3(1.41, 0.225, 0.108), Vector3(1.46, 0.17, 0.092),
		Vector3(1.47, 0.060, 0.054),
	]
	Geometry.mesh_node(_body, "Jersey", Geometry.profile(torso), shirt)
	var collar: Array[Vector3] = [Vector3(1.466, 0.075, 0.061), Vector3(1.482, 0.073, 0.060)]
	Geometry.mesh_node(_body, "Collar", Geometry.profile(collar), contrast)
	if actor_id == 1:
		var stripe: Array[Vector3] = [Vector3(1.205, 0.193, 0.115), Vector3(1.265, 0.210, 0.122)]
		Geometry.mesh_node(_body, "AwayChestBand", Geometry.profile(stripe), contrast)
	# Definición de hombros: deltoides para silueta atlética más amplia y legible
	Geometry.ellipsoid(_body, "LeftDeltoid",  Vector3(0.098, 0.090, 0.088), Vector3(-0.297, 1.375, 0.0), shirt)
	Geometry.ellipsoid(_body, "RightDeltoid", Vector3(0.098, 0.090, 0.088), Vector3( 0.297, 1.375, 0.0), shirt)
	Geometry.ellipsoid(_body, "Neck", Vector3(0.105, 0.13, 0.10), Vector3(0, 1.505, 0), skin)
	Geometry.ellipsoid(_body, "Head", Vector3(0.188, 0.25, 0.197), Vector3(0, 1.635, -0.005), skin)
	Geometry.ellipsoid(_body, "Hair", Vector3(0.191, 0.088, 0.194), Vector3(0, 1.735, 0.002), hair)
	Geometry.ellipsoid(_body, "Nose", Vector3(0.033, 0.044, 0.042), Vector3(0, 1.633, -0.105), skin)
	# Definición facial: mandíbula y orejas para mayor lectura de silueta de cabeza
	Geometry.ellipsoid(_body, "Jaw",      Vector3(0.142, 0.105, 0.138), Vector3(0,      1.558, -0.010), skin)
	Geometry.ellipsoid(_body, "LeftEar",  Vector3(0.038, 0.052, 0.022), Vector3(-0.182, 1.638,  0.018), skin)
	Geometry.ellipsoid(_body, "RightEar", Vector3(0.038, 0.052, 0.022), Vector3( 0.182, 1.638,  0.018), skin)
	_add_number("BackNumber", str(dorsal), Vector3(0, 1.27, 0.123), 0.0, ink_color, 0.0038)
	_add_number("FrontNumber", str(dorsal), Vector3(0.095, 1.34, -0.115), PI, ink_color, 0.0016)
	if _keeper:
		_add_number("KeeperRole", "P", Vector3(0, 1.075, 0.119), 0.0, ink_color, 0.0018)
	for side: int in 2:
		var leg: Array = [
			_limb("Thigh", 0.085, 0.067, skin),
			_limb("Shin", 0.065, 0.038, skin),
			_limb("Sock", 0.059, 0.043, contrast),
			Geometry.ellipsoid(_body, "CourtShoe", SHOE_SIZE, Vector3.ZERO, shoe),
			_limb("Shorts", 0.112, 0.103, shorts),
			Geometry.ellipsoid(_body, "Sole", SOLE_SIZE, Vector3.ZERO, rubber),
			Geometry.ellipsoid(_body, "KneeGuard", Vector3(0.062, 0.068, 0.052), Vector3.ZERO, shorts),
		]
		_legs.append(leg)
		var arm: Array = [
			_limb("UpperArm", 0.055, 0.043, skin),
			_limb("Forearm", 0.047, 0.030, skin),
			Geometry.ellipsoid(_body, "Glove" if _keeper else "Hand",
				Vector3(0.085, 0.12, 0.068), Vector3.ZERO, contrast if _keeper else skin),
			_limb("Sleeve", 0.076, 0.070, shirt),
		]
		_arms.append(arm)
	var shape: PackedVector3Array
	if actor_id % 2 == 0:
		shape = Geometry.circle(0.44, Vector3(0, 0.02, 0), 48)
	else:
		shape = PackedVector3Array([
			Vector3(0, 0.02, -0.52), Vector3(0.52, 0.02, 0),
			Vector3(0, 0.02, 0.52), Vector3(-0.52, 0.02, 0), Vector3(0, 0.02, -0.52),
		])
	var marker_material: StandardMaterial3D = Geometry.material(
		Color("#314350"), 0.95)
	_marker = Geometry.mesh_node(self, "TeamShape", Geometry.ribbons([shape], 0.045), marker_material)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if actor_id % 2 == 0:
		var selected: Label3D = Label3D.new()
		selected.name = "HumanSelection"
		selected.visible = false
		selected.text = "▼"
		selected.position.y = 2.12
		selected.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		selected.pixel_size = 0.007
		selected.font_size = 36
		selected.modulate = Color("#e9d096")
		selected.outline_modulate = Color("#182e40")
		selected.outline_size = 4
		add_child(selected)
		_selection_marker = selected


func _limb(node_name: String, start_radius: float, end_radius: float,
		surface: Material) -> MeshInstance3D:
	var rings: Array[Vector3] = [
		Vector3(0, start_radius * 0.8, start_radius * 0.8),
		Vector3(0.1, start_radius, start_radius),
		Vector3(0.55, lerpf(start_radius, end_radius, 0.35), lerpf(start_radius, end_radius, 0.35)),
		Vector3(0.95, end_radius, end_radius), Vector3(1.0, end_radius * 0.8, end_radius * 0.8),
	]
	return Geometry.mesh_node(_body, node_name, Geometry.profile(rings, 12), surface)


func _pose_leg(index: int, hip: Vector3, ankle: Vector3, foot_basis: Basis = Basis.IDENTITY) -> void:
	# Limitar sólo la rodilla dejaba la espinilla estirada hasta un tobillo inalcanzable.
	var axis: Vector3 = (ankle - hip).limit_length(MAX_LEG_REACH)
	ankle = hip + axis
	var distance: float = axis.length()
	var direction: Vector3 = axis.normalized()
	var pole: Vector3 = Vector3.FORWARD - direction * direction.dot(Vector3.FORWARD)
	if pole.length_squared() < 0.01:
		pole = Vector3.RIGHT
	var bend: float = sqrt(maxf(0.001,
		LEG_SEGMENT_LENGTH * LEG_SEGMENT_LENGTH - distance * distance * 0.25))
	var knee: Vector3 = hip + direction * distance * 0.5 + pole.normalized() * bend
	var leg: Array = _legs[index]
	_set_bone(leg[0] as Node3D, hip, knee)
	_set_bone(leg[1] as Node3D, knee, ankle)
	_set_bone(leg[2] as Node3D, knee.lerp(ankle, 0.40), ankle)
	_set_bone(leg[4] as Node3D, hip, hip.lerp(knee, 0.64))
	(leg[3] as Node3D).transform = Transform3D(foot_basis * Basis.from_scale(SHOE_SIZE),
		ankle + foot_basis * SHOE_OFFSET)
	(leg[5] as Node3D).transform = Transform3D(foot_basis * Basis.from_scale(SOLE_SIZE),
		ankle + foot_basis * SOLE_OFFSET)
	_posed_ankles[index] = ankle
	if leg.size() > 6:
		(leg[6] as Node3D).position = knee + Vector3(0, 0.028, -0.025)


func _set_bone(node: Node3D, from: Vector3, to: Vector3) -> void:
	var direction: Vector3 = (to - from).normalized()
	var right: Vector3 = direction.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	node.transform = Transform3D(Basis(right, direction * from.distance_to(to), right.cross(direction)), from)


func _add_number(node_name: String, text: String, at: Vector3, yaw: float,
		color: Color, pixel_size: float) -> void:
	var label: Label3D = Label3D.new()
	label.name = node_name
	label.text = text
	label.position = at
	label.rotation.y = yaw
	label.font_size = 52
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	add_child(label)
	label.reparent(_body, false)
