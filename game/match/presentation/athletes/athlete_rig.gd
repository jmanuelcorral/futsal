extends RefCounted
## Retargetea los contactos de presentacion; nunca mueve actores o balon fisicos.

const ERROR_PREFIX: String = "AthleteRig rejected invalid data: "
const SIDE_SUFFIXES: Array[String] = ["_L", "_R"]
const SEGMENTS: Array[String] = [
	"Thigh", "Shin", "Foot", "Toe", "UpperArm", "Forearm", "Hand", "Palm",
]

var skeleton: Skeleton3D
var leg_lengths: Array[Vector2] = []
var arm_lengths: Array[Vector2] = []
var _indices: Dictionary[StringName, int] = {}
var _rest: Dictionary[StringName, Transform3D] = {}
var _frame_to_skeleton: Transform3D = Transform3D.IDENTITY
var _ready: bool = false
var _foot_neutral: Array[Basis] = []


func bind(source: Skeleton3D, frame: Node3D) -> Error:
	if source == null or frame == null or not source.is_inside_tree() or not frame.is_inside_tree():
		return _reject("skeleton_frame")
	var mapping: Transform3D = source.global_transform.affine_inverse() * frame.global_transform
	if not mapping.is_finite() or not _rigid_basis(mapping.basis):
		return _reject("rig_scale")
	var indices: Dictionary[StringName, int] = {}
	var rest: Dictionary[StringName, Transform3D] = {}
	var skeleton_to_frame: Transform3D = mapping.affine_inverse()
	for suffix: String in SIDE_SUFFIXES:
		for segment: String in SEGMENTS:
			var bone: StringName = StringName(segment + suffix)
			var index: int = source.find_bone(bone)
			if index < 0:
				return _reject("missing_bone:" + bone)
			var pose: Transform3D = skeleton_to_frame * source.get_bone_global_rest(index)
			if not pose.is_finite() or not _rigid_basis(pose.basis):
				return _reject("bone_rest:" + bone)
			indices[bone] = index
			rest[bone] = pose
		for chain: PackedStringArray in [
			PackedStringArray(["Thigh", "Shin", "Foot", "Toe"]),
			PackedStringArray(["UpperArm", "Forearm", "Hand", "Palm"]),
		]:
			for index: int in range(chain.size() - 1):
				var parent: StringName = StringName(chain[index] + suffix)
				var child: StringName = StringName(chain[index + 1] + suffix)
				if source.get_bone_parent(indices[child]) != indices[parent]:
					return _reject("bone_parent:" + child)
				if rest[parent].origin.distance_to(rest[child].origin) < 0.005:
					return _reject("bone_length:" + parent)
	skeleton = source
	_indices = indices
	_rest = rest
	_frame_to_skeleton = mapping
	leg_lengths.clear()
	arm_lengths.clear()
	_foot_neutral.clear()
	for suffix: String in SIDE_SUFFIXES:
		leg_lengths.append(Vector2(
			rest[StringName("Thigh" + suffix)].origin.distance_to(rest[StringName("Shin" + suffix)].origin),
			rest[StringName("Shin" + suffix)].origin.distance_to(rest[StringName("Foot" + suffix)].origin)))
		arm_lengths.append(Vector2(
			rest[StringName("UpperArm" + suffix)].origin.distance_to(rest[StringName("Forearm" + suffix)].origin),
			rest[StringName("Forearm" + suffix)].origin.distance_to(rest[StringName("Hand" + suffix)].origin)
				+ rest[StringName("Hand" + suffix)].origin.distance_to(rest[StringName("Palm" + suffix)].origin)))
		var forward: Vector3 = rest[StringName("Toe" + suffix)].origin - rest[StringName("Foot" + suffix)].origin
		_foot_neutral.append(Basis(Vector3.UP, -atan2(-forward.x, -forward.z)))
	_ready = true
	skeleton.reset_bone_poses()
	return OK


func pose_leg(side: int, hip: Vector3, knee: Vector3, ankle: Vector3,
		foot_basis: Basis) -> Error:
	if not _ready or side < 0 or side >= SIDE_SUFFIXES.size():
		return _reject("leg_identity")
	if not _valid_segment(hip, knee) or not _valid_segment(knee, ankle) \
			or not _rigid_basis(foot_basis):
		return _reject("leg_transform")
	var suffix: String = SIDE_SUFFIXES[side]
	var thigh: StringName = StringName("Thigh" + suffix)
	var shin: StringName = StringName("Shin" + suffix)
	var foot: StringName = StringName("Foot" + suffix)
	_set_pose(thigh, _segment_pose(thigh, shin, hip, knee))
	_set_pose(shin, _segment_pose(shin, foot, knee, ankle))
	_set_pose(foot, Transform3D(foot_basis * _foot_neutral[side] * _rest[foot].basis, ankle))
	return OK


func pose_arm(side: int, shoulder: Vector3, elbow: Vector3, palm: Vector3) -> Error:
	if not _ready or side < 0 or side >= SIDE_SUFFIXES.size():
		return _reject("arm_identity")
	if not _valid_segment(shoulder, elbow) or not _valid_segment(elbow, palm):
		return _reject("arm_transform")
	var suffix: String = SIDE_SUFFIXES[side]
	var upper: StringName = StringName("UpperArm" + suffix)
	var forearm: StringName = StringName("Forearm" + suffix)
	var hand: StringName = StringName("Hand" + suffix)
	var palm_bone: StringName = StringName("Palm" + suffix)
	var rest_offset: Vector3 = _rest[palm_bone].origin - _rest[hand].origin
	if palm.distance_to(elbow) <= rest_offset.length() + 0.001:
		return _reject("palm_reach")
	var direction: Vector3 = (palm - elbow).normalized()
	var rotation: Basis = Basis(Quaternion(rest_offset.normalized(), direction))
	var wrist: Vector3 = palm - rotation * rest_offset
	if not _valid_segment(elbow, wrist):
		return _reject("palm_reach")
	_set_pose(upper, _segment_pose(upper, forearm, shoulder, elbow))
	_set_pose(forearm, _segment_pose(forearm, hand, elbow, wrist))
	_set_pose(hand, Transform3D(rotation * _rest[hand].basis, wrist))
	return OK


func reset_pose() -> void:
	if _ready:
		skeleton.reset_bone_poses()


func joint_position(side: int, segment: String) -> Vector3:
	if not _ready or side < 0 or side >= SIDE_SUFFIXES.size() or segment not in SEGMENTS:
		_reject("rest_joint")
		return Vector3(INF, INF, INF)
	return _rest[StringName(segment + SIDE_SUFFIXES[side])].origin


func _segment_pose(bone: StringName, child: StringName,
		from: Vector3, to: Vector3) -> Transform3D:
	var rest_axis: Vector3 = (_rest[child].origin - _rest[bone].origin).normalized()
	var target_axis: Vector3 = (to - from).normalized()
	var rotation: Basis = Basis(Quaternion(rest_axis, target_axis))
	return Transform3D(rotation * _rest[bone].basis, from)


func _set_pose(bone: StringName, pose_in_frame: Transform3D) -> void:
	skeleton.set_bone_global_pose(_indices[bone], _frame_to_skeleton * pose_in_frame)


func _valid_segment(from: Vector3, to: Vector3) -> bool:
	var distance: float = from.distance_squared_to(to)
	return from.is_finite() and to.is_finite() and is_finite(distance) and distance > 0.000001


func _rigid_basis(basis: Basis) -> bool:
	return basis.is_finite() and is_equal_approx(basis.determinant(), 1.0) \
		and basis.is_equal_approx(basis.orthonormalized())


func _reject(reason: String) -> Error:
	push_error(ERROR_PREFIX + reason)
	return ERR_INVALID_DATA
