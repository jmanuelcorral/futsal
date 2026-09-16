extends SceneTree
## godot --headless --path game --script res://tests/test_athlete_rig.gd

const Rig = preload("res://match/presentation/athletes/athlete_rig.gd")
var _checks: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var frame: Node3D = Node3D.new()
	root.add_child(frame)
	frame.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(12, 0, -4))
	var source: Skeleton3D = Skeleton3D.new()
	frame.add_child(source)
	source.rotation.y = PI
	_bone(source, "Root", -1, Vector3.ZERO)
	var hips: int = _bone(source, "Hips", 0, Vector3(0, 0.89, 0))
	var chest: int = _bone(source, "Chest", hips, Vector3(0, 1.40, 0))
	for side: int in 2:
		var sign_x: float = 1.0 if side == 0 else -1.0
		var suffix: String = "_L" if side == 0 else "_R"
		var thigh: int = _bone(source, "Thigh" + suffix, hips, Vector3(sign_x * 0.10, 0.89, 0))
		var shin: int = _bone(source, "Shin" + suffix, thigh, Vector3(sign_x * 0.10, 0.48, 0))
		var foot: int = _bone(source, "Foot" + suffix, shin, Vector3(sign_x * 0.10, 0.08, 0))
		_bone(source, "Toe" + suffix, foot, Vector3(sign_x * 0.10, 0.04, 0.14))
		var upper: int = _bone(source, "UpperArm" + suffix, chest, Vector3(sign_x * 0.215, 1.4, 0))
		var forearm: int = _bone(source, "Forearm" + suffix, upper, Vector3(sign_x * 0.35, 1.15, 0))
		var hand: int = _bone(source, "Hand" + suffix, forearm, Vector3(sign_x * 0.45, 0.92, 0))
		_bone(source, "Palm" + suffix, hand, Vector3(sign_x * 0.48, 0.865, 0))
	source.reset_bone_poses()
	var rig: Rig = Rig.new()
	_check("bind rotated asset", rig.bind(source, frame) == OK)
	_check("leg lengths come from unequal rest segments", rig.leg_lengths[0].is_equal_approx(Vector2(0.41, 0.40)))
	_check("rest shoulder is expressed in the athlete frame",
		rig.joint_position(0, "UpperArm").distance_to(Vector3(-0.215, 1.40, 0)) < 0.00001)
	_check("arm target length includes the real palm offset",
		is_equal_approx(rig.arm_lengths[0].y, Vector2(0.10, 0.23).length() + Vector2(0.03, 0.055).length()))
	_check("reject nonuniform scale with determinant one",
		not rig._rigid_basis(Basis.from_scale(Vector3(2, 1, 0.5))))
	_check("reject mirrored basis", not rig._rigid_basis(Basis.from_scale(Vector3(-1, 1, 1))))
	_check("reject coincident segment", not rig._valid_segment(Vector3.ZERO, Vector3.ZERO))
	_check("reject nonfinite segment", not rig._valid_segment(Vector3(INF, 0, 0), Vector3.ZERO))
	_check("reject overflowing segment distance",
		not rig._valid_segment(Vector3(1e30, 0, 0), Vector3(-1e30, 0, 0)))
	frame.transform = Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.4), Vector3(-7, 0.3, 10))
	for side: int in 2:
		var sign_x: float = -1.0 if side == 0 else 1.0
		var suffix: String = "_L" if side == 0 else "_R"
		var hip: Vector3 = Vector3(sign_x * 0.10, 0.89, 0)
		var knee: Vector3 = Vector3(sign_x * 0.13, 0.56, -0.20)
		var ankle: Vector3 = Vector3(sign_x * 0.18, 0.12, -0.35)
		var foot_basis: Basis = Basis(Vector3.UP, sign_x * 0.4)
		_check("leg accepted " + suffix, rig.pose_leg(side, hip, knee, ankle, foot_basis) == OK)
		_check("hip reaches target " + suffix, _point(source, frame, "Thigh" + suffix).distance_to(hip) < 0.00001)
		_check("knee reaches target " + suffix, _point(source, frame, "Shin" + suffix).distance_to(knee) < 0.00001)
		_check("ankle reaches target " + suffix, _point(source, frame, "Foot" + suffix).distance_to(ankle) < 0.00001)
		var toe: Vector3 = ankle + foot_basis * Vector3(0, -0.04, -0.14)
		_check("toe follows foot orientation " + suffix, _point(source, frame, "Toe" + suffix).distance_to(toe) < 0.00001)
		var shoulder: Vector3 = Vector3(sign_x * 0.215, 1.4, 0)
		var elbow: Vector3 = Vector3(sign_x * 0.32, 1.2, -0.10)
		var palm: Vector3 = Vector3(sign_x * 0.20, 1.02, -0.32)
		_check("arm accepted " + suffix, rig.pose_arm(side, shoulder, elbow, palm) == OK)
		_check("shoulder reaches target " + suffix,
			_point(source, frame, "UpperArm" + suffix).distance_to(shoulder) < 0.00001)
		_check("elbow reaches target " + suffix,
			_point(source, frame, "Forearm" + suffix).distance_to(elbow) < 0.00001)
		_check("actual palm, not wrist, reaches grip " + suffix,
			_point(source, frame, "Palm" + suffix).distance_to(palm) < 0.00001)
		_check("wrist stays behind palm " + suffix,
			_point(source, frame, "Hand" + suffix).distance_to(palm) > 0.05)
	for index: int in source.get_bone_count():
		var pose: Transform3D = source.get_bone_global_pose(index)
		_check("bone finite and no scale " + source.get_bone_name(index),
			pose.is_finite() and is_equal_approx(pose.basis.determinant(), 1.0))
	rig.reset_pose()
	for index: int in source.get_bone_count():
		_check("rest reset " + source.get_bone_name(index),
			source.get_bone_global_pose(index).is_equal_approx(source.get_bone_global_rest(index)))
	frame.free()
	var failed: Array[String] = []
	for check: Dictionary in _checks:
		if not check["passed"]:
			failed.append(check["name"])
	print("FUTSAL_RIG_CONTRACT_TESTS " + JSON.stringify({
		"ok": failed.is_empty(), "passed": _checks.size() - failed.size(),
		"total": _checks.size(), "checks": _checks, "failures": failed,
		"scope": "native synthetic skeleton; not the production mesh or artistic approval",
	}))
	quit(0 if failed.is_empty() else 1)


func _bone(source: Skeleton3D, name: String, parent: int, position: Vector3) -> int:
	var index: int = source.add_bone(name)
	source.set_bone_parent(index, parent)
	var pose: Transform3D = Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.8), position)
	var local: Transform3D = source.get_bone_global_rest(parent).affine_inverse() * pose \
		if parent >= 0 else pose
	source.set_bone_rest(index, local)
	return index


func _point(source: Skeleton3D, frame: Node3D, name: String) -> Vector3:
	return frame.to_local(source.to_global(source.get_bone_global_pose(source.find_bone(name)).origin))


func _check(name: String, passed: bool) -> void:
	_checks.append({"name": name, "passed": passed})
