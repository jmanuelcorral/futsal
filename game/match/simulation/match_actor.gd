extends CharacterBody3D

const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")

var actor_id: int = -1
var team_id: int = -1
var role: Snapshot.Role = Snapshot.Role.FIELD
var spawn_position: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.RIGHT
var command: Command = Command.new()
var pending_action: Command
var last_sequence: int = -1
var last_command_tick: int = -1
var command_age: float = 0.0
var action_cooldown: float = 0.0
var receive_cooldown: float = 0.0
var ai_timer: float = 0.0
var possession_seconds: float = 0.0
var dribble_cooldown: float = 0.0
var gesture_kind: Types.GestureKind = Types.GestureKind.NONE
var gesture_started_tick: int = -1
var gesture_duration_ticks: int = 0
var gesture_direction: Vector3 = Vector3.ZERO
var gesture_contact_position: Vector3 = Vector3.ZERO
var _slide_contacts: Array[Dictionary] = []


func _init() -> void:
	collision_layer = Tuning.ACTOR_LAYER
	collision_mask = Tuning.WORLD_LAYER | Tuning.ACTOR_LAYER
	floor_snap_length = 0.15
	safe_margin = 0.002
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = Tuning.ACTOR_RADIUS
	shape.height = Tuning.ACTOR_HEIGHT
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = Tuning.ACTOR_HEIGHT * 0.5
	add_child(collider)


func reset_state(at: Vector3, direction: Vector2) -> void:
	spawn_position = at
	_place_for_restart(at, direction)
	command = Command.new(actor_id)
	pending_action = null
	last_sequence = -1
	last_command_tick = -1
	command_age = 0.0
	action_cooldown = 0.0
	receive_cooldown = 0.0
	ai_timer = 0.0
	possession_seconds = 0.0
	dribble_cooldown = 0.0
	gesture_kind = Types.GestureKind.NONE
	gesture_started_tick = -1
	gesture_duration_ticks = 0
	gesture_direction = Vector3.ZERO
	gesture_contact_position = Vector3.ZERO
	_slide_contacts.clear()


func _place_for_restart(at: Vector3, direction: Vector2) -> void:
	# A restart teleports; a queued kinematic target would sweep the old body through the new drill.
	PhysicsServer3D.body_set_mode(get_rid(), PhysicsServer3D.BODY_MODE_STATIC)
	position = at
	velocity = Vector3.ZERO
	forward = Vector3(direction.x, 0.0, direction.y).normalized()
	rotation.y = atan2(-forward.x, -forward.z)
	force_update_transform()
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	PhysicsServer3D.body_set_mode(get_rid(), PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	reset_physics_interpolation()


func step(delta: float, tuning: Tuning) -> void:
	_move_prepared(_prepare_step(delta, tuning), delta)


func _tick_command(delta: float, tuning: Tuning) -> void:
	action_cooldown = maxf(0.0, action_cooldown - delta)
	receive_cooldown = maxf(0.0, receive_cooldown - delta)
	dribble_cooldown = maxf(0.0, dribble_cooldown - delta)
	command_age += delta
	if command_age > tuning.command_timeout:
		command.move = Vector2.ZERO
		command.aim = Vector2.ZERO
		command.sprint = false
		command.close_control = false
		command.action = Command.Action.NONE
		command.target_actor_id = -1
		command.shot_charge = 0.0
		command.shot_lift = 0.0
		command.restart_spot_choice = Types.SpotChoice.DEFAULT


func _turn(tuning: Tuning, delta: float) -> void:
	var facing: Vector2 = command.aim if not command.aim.is_zero_approx() else command.move
	if not facing.is_zero_approx():
		var desired_yaw: float = atan2(-facing.x, -facing.y)
		rotation.y = rotate_toward(rotation.y, desired_yaw, tuning.turn_speed * delta)
		forward = -global_basis.z


func _aim_only(delta: float, tuning: Tuning) -> void:
	_tick_command(delta, tuning)
	_turn(tuning, delta)
	velocity = Vector3.ZERO
	_slide_contacts.clear()


func _prepare_step(delta: float, tuning: Tuning) -> Vector3:
	_tick_command(delta, tuning)
	var speed: float = tuning.keeper_speed if role == Snapshot.Role.KEEPER else tuning.move_speed
	if command.close_control:
		speed = minf(speed, tuning.close_control_speed)
	elif command.sprint and role == Snapshot.Role.FIELD:
		speed = tuning.sprint_speed
	var desired: Vector3 = Vector3(command.move.x, 0.0, command.move.y) * speed
	var planar: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = tuning.braking if desired.is_zero_approx() or planar.dot(desired) < 0.0 else tuning.acceleration
	planar = planar.move_toward(desired, rate * delta)
	velocity = Vector3(planar.x, -0.5 if is_on_floor() else velocity.y - 9.81 * delta, planar.z)
	_turn(tuning, delta)
	return planar * delta


func _move_prepared(displacement: Vector3, delta: float, pre_contact_velocities: Dictionary[int, Vector3] = {}) -> void:
	var start: Vector3 = position
	velocity.x = displacement.x / delta
	velocity.z = displacement.z / delta
	var incoming: Vector3 = velocity
	_slide_contacts.clear()
	move_and_slide()
	for index: int in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(index)
		var other: Object = collision.get_collider()
		if other is CharacterBody3D:
			var other_id: int = int(other.get("actor_id"))
			_slide_contacts.append({"actor_id": other_id, "point": collision.get_position(),
				"normal": collision.get_normal(), "actor_velocity": incoming,
				"other_velocity": pre_contact_velocities.get(other_id, collision.get_collider_velocity())})
	# Training athletes stay on the playing surface; the ball has no touchline walls.
	var limited: Vector3 = Vector3(clampf(position.x, -19.65, 19.65), position.y, clampf(position.z, -9.65, 9.65))
	# A legal touchline taker/penalty keeper may begin outside the ordinary walking limit.
	if absf(start.x) > 19.65:
		limited.x = signf(start.x) * minf(absf(start.x), position.x * signf(start.x))
	if absf(start.z) > 9.65:
		limited.z = signf(start.z) * minf(absf(start.z), position.z * signf(start.z))
	if not is_equal_approx(position.x, limited.x):
		velocity.x = 0.0
	if not is_equal_approx(position.z, limited.z):
		velocity.z = 0.0
	position = limited


func _take_slide_contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = _slide_contacts
	_slide_contacts = []
	return result
