extends RigidBody3D

const Tuning = preload("res://match/simulation/match_tuning.gd")

var rolling_resistance: float = 0.45
var maximum_speed: float = 32.0
var control_velocity: Vector3 = Vector3.ZERO
var control_acceleration: float = 0.0
var control_actor_id: int = -1
var _held_transform: Transform3D = Transform3D.IDENTITY
var _held_linear: Vector3 = Vector3.ZERO
var _held_angular: Vector3 = Vector3.ZERO
var _contact_samples: Array[Dictionary] = []
var _active_bodies: Dictionary[int, int] = {}
var _native_episode: int = 0
var _control_actor: int = -1
var _control_episode: int = -1
var _sphere_shape: SphereShape3D
var _release_body: RID
var _release_body_instance_id: int = -1
var _release_native_episode: int = -1
var _release_contact_id: int = -1


func _init() -> void:
	mass = Tuning.BALL_MASS
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 16
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.015
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	collision_layer = Tuning.BALL_LAYER
	collision_mask = Tuning.WORLD_LAYER | Tuning.ACTOR_LAYER
	freeze = true
	_sphere_shape = SphereShape3D.new()
	_sphere_shape.radius = Tuning.BALL_RADIUS
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = _sphere_shape
	add_child(collider)


func configure(tuning: Tuning) -> void:
	rolling_resistance = tuning.rolling_resistance
	maximum_speed = tuning.maximum_ball_speed
	var material: PhysicsMaterial = PhysicsMaterial.new()
	material.friction = tuning.ball_friction
	material.bounce = tuning.ball_bounce
	physics_material_override = material


func place(at: Vector3, linear: Vector3, angular: Vector3) -> void:
	freeze = true
	control_acceleration = 0.0
	control_velocity = Vector3.ZERO
	control_actor_id = -1
	_control_actor = -1
	_control_episode = -1
	_active_bodies.clear()
	_contact_samples.clear()
	_clear_release_episode()
	_held_transform = Transform3D(Basis.IDENTITY, at)
	_held_linear = linear
	_held_angular = angular
	global_transform = _held_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _held_transform)
	reset_physics_interpolation()


func suspend() -> void:
	if freeze:
		return
	# The server may be one completed physics step ahead of the Node3D sync callback.
	_held_transform = PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	_held_linear = PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	_held_angular = PhysicsServer3D.body_get_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	freeze = true
	global_transform = _held_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _held_transform)


func resume() -> void:
	if not freeze:
		return
	freeze = false
	global_transform = _held_transform
	linear_velocity = _held_linear
	angular_velocity = _held_angular
	sleeping = false


func snapshot_transform() -> Transform3D:
	# Keep frozen snapshots stable across the server's quaternion normalization callback.
	return _held_transform if freeze else global_transform


func kick(velocity: Vector3) -> void:
	control_acceleration = 0.0
	control_actor_id = -1
	_control_actor = -1
	_control_episode = -1
	_clear_release_episode()
	linear_velocity = velocity.limit_length(maximum_speed)
	angular_velocity = Vector3.UP.cross(Vector3(velocity.x, 0.0, velocity.z)) / Tuning.BALL_RADIUS
	sleeping = false


func _begin_release_episode(body: RID, body_instance_id: int, contact_id: int, space: PhysicsDirectSpaceState3D) -> void:
	_release_body = body
	_release_body_instance_id = body_instance_id
	_release_contact_id = contact_id
	_refresh_release_episode(space, global_transform)
	if _release_contact_id >= 0:
		_release_native_episode = int(_active_bodies.get(body_instance_id, -1))
		if _release_native_episode < 0:
			_native_episode += 1
			_release_native_episode = _native_episode
		_active_bodies[_release_body_instance_id] = _release_native_episode


func _release_contact_for_body(body_instance_id: int, episode: int) -> int:
	return _release_contact_id if body_instance_id == _release_body_instance_id and episode == _release_native_episode else -1


func _refresh_release_episode(space: PhysicsDirectSpaceState3D, at: Transform3D) -> void:
	if _release_contact_id < 0:
		return
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere_shape
	query.transform = at
	query.collision_mask = Tuning.ACTOR_LAYER
	query.exclude = [get_rid()]
	query.margin = Tuning.NATIVE_JOLT_PROFILE[&"physics/jolt_physics_3d/simulation/penetration_slop"]
	for hit: Dictionary in space.intersect_shape(query, 16):
		if hit["rid"] == _release_body:
			return
	_active_bodies.erase(_release_body_instance_id)
	_clear_release_episode()


func _clear_release_episode() -> void:
	_release_body = RID()
	_release_body_instance_id = -1
	_release_native_episode = -1
	_release_contact_id = -1


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var motion: Vector3 = state.linear_velocity
	if control_acceleration > 0.0:
		var planar: Vector3 = Vector3(motion.x, 0.0, motion.z)
		var before_control: Vector3 = planar
		planar = planar.move_toward(control_velocity, control_acceleration * state.step)
		motion.x = planar.x
		motion.z = planar.z
		if control_actor_id >= 0:
			if _control_actor != control_actor_id:
				_control_actor = control_actor_id
				_control_episode = -1
			if _control_episode == -1 and not planar.is_equal_approx(before_control):
				_native_episode += 1
				_control_episode = _native_episode
				_contact_samples.append({"source": &"control", "episode": _control_episode, "actor_id": control_actor_id,
					"surface": &"controlled_touch", "point": state.transform.origin, "ball_position": state.transform.origin,
					"normal": (planar - before_control).normalized(), "actor_velocity": control_velocity,
					"ball_velocity": state.linear_velocity})
		else:
			_control_actor = -1
			_control_episode = -1
	else:
		_control_actor = -1
		_control_episode = -1
	var grounded: bool = false
	var contacts: Dictionary[int, int] = {}
	for index: int in state.get_contact_count():
		var collider: Object = state.get_contact_collider_object(index)
		if collider == null:
			continue
		var body_id: int = collider.get_instance_id()
		var surface: StringName = &"athlete" if collider is CharacterBody3D else StringName(collider.get_meta(&"surface", &"world"))
		grounded = grounded or surface == &"floor"
		if body_id in contacts:
			continue
		if body_id not in _active_bodies:
			_native_episode += 1
			_active_bodies[body_id] = _native_episode
			var point: Vector3 = state.get_contact_local_position(index)
			var normal: Vector3 = state.get_contact_local_normal(index).normalized()
			# Use the CCD contact location, not a later end-of-step pose, for boundary ordering.
			var contact_center: Vector3 = point + normal * Tuning.BALL_RADIUS
			_contact_samples.append({"source": &"body", "episode": _active_bodies[body_id],
				"actor_id": int(collider.get("actor_id")) if collider is CharacterBody3D else -1,
				"contact_id": _release_contact_for_body(body_id, _active_bodies[body_id]),
				"surface": surface, "point": point, "ball_position": contact_center, "normal": normal,
				"actor_velocity": state.get_contact_collider_velocity_at_position(index), "ball_velocity": state.linear_velocity})
		contacts[body_id] = _active_bodies[body_id]
	if _release_contact_id >= 0:
		contacts[_release_body_instance_id] = _release_native_episode
	_active_bodies = contacts
	# Only actual shape separation retires the original release; elapsed ticks do not.
	_refresh_release_episode(state.get_space_state(), state.transform)
	if grounded:
		var planar: Vector3 = Vector3(motion.x, 0.0, motion.z)
		planar = planar.move_toward(Vector3.ZERO, rolling_resistance * state.step)
		motion.x = planar.x
		motion.z = planar.z
	state.linear_velocity = motion.limit_length(maximum_speed)


func _take_contact_samples() -> Array[Dictionary]:
	var result: Array[Dictionary] = _contact_samples
	_contact_samples = []
	return result
