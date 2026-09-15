extends SceneTree

const Bootstrap = preload("res://bootstrap/bootstrap.gd")

var checks: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://bootstrap/bootstrap.tscn") as PackedScene
	_check("boot scene loads", scene != null)
	if scene == null:
		_finish()
		return
	var boot: Bootstrap = scene.instantiate() as Bootstrap
	_check("independent diagnostic script is scene entrypoint", boot != null)
	if boot == null:
		_finish()
		return
	root.add_child(boot)
	await process_frame
	var status: Dictionary = boot.build_diagnostics()
	_check("preview project version", status["project_version"] == Bootstrap.EXPECTED_PROJECT_VERSION)
	_check("explicit diagnostic path", status["diagnostic_scene"] == Bootstrap.DIAGNOSTIC_SCENE)
	_check("pinned native engine", status["engine_version"] == "4.7.2-stable (official)")
	_check("headless is not GPU evidence", bool(status["headless"]) and not bool(status["gpu_validated"]))
	_check("Forward+ configured", status["rendering_method_configured"] == "forward_plus")
	_check("Compatibility fallback disabled", not bool(
		ProjectSettings.get_setting("rendering/rendering_device/fallback_to_opengl3")
	))
	_check("Jolt configured", status["physics_engine"] == "Jolt Physics")
	_check("physics ticks are 60 Hz", Engine.physics_ticks_per_second == 60)
	_check("native .blend import disabled", not bool(ProjectSettings.get_setting("filesystem/import/blender/enabled")))
	_check("schema v3", status["input_schema_version"] == 3 and Bootstrap.INPUT_SCHEMA_VERSION == 3)
	_check("project viewport configured for 1080p",
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and
		ProjectSettings.get_setting("display/window/size/viewport_height") == 1080)
	var actions: Array[StringName] = [
		&"move_left", &"move_right", &"move_forward", &"move_back",
		&"sprint", &"close_control", &"pass", &"shoot", &"pause", &"dribble",
	]
	var keys: Array[int] = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_CTRL, KEY_J, KEY_K, KEY_ESCAPE, KEY_L]
	var arrows: Array[int] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	var axes: Array[int] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_LEFT_Y, JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_TRIGGER_LEFT]
	var axis_values: Array[float] = [-1.0, 1.0, -1.0, 1.0, 1.0, 1.0]
	var buttons: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_X]
	var bindings_complete: bool = Bootstrap.REQUIRED_ACTIONS == actions and keys.size() == actions.size() \
		and axes.size() == axis_values.size() and axes.size() + buttons.size() == actions.size()
	_check("schema-3 action order and complete independent binding matrix", bindings_complete)
	if not bindings_complete:
		boot.queue_free()
		_finish()
		return
	for index: int in Bootstrap.REQUIRED_ACTIONS.size():
		var action: StringName = Bootstrap.REQUIRED_ACTIONS[index]
		_check("action exists: " + String(action), InputMap.has_action(action))
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var keyboard_matches: bool = false
		var arrow_matches: bool = index >= arrows.size()
		var controller_bound: bool = false
		for event: InputEvent in events:
			if event is InputEventKey:
				var key: InputEventKey = event as InputEventKey
				keyboard_matches = keyboard_matches or (key.device == -1 and key.physical_keycode == keys[index])
				if index < arrows.size():
					arrow_matches = arrow_matches or (key.device == -1 and key.physical_keycode == arrows[index])
			if event is InputEventJoypadMotion and index < axes.size():
				var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
				controller_bound = motion.device == -1 and motion.axis == axes[index] and is_equal_approx(motion.axis_value, axis_values[index])
			if event is InputEventJoypadButton and index >= axes.size():
				var button: InputEventJoypadButton = event as InputEventJoypadButton
				controller_bound = button.device == -1 and button.button_index == buttons[index - axes.size()]
		_check("keyboard binding: " + String(action), keyboard_matches)
		if index < arrows.size():
			_check("physical arrow binding: " + String(action), arrow_matches)
		_check("controller binding: " + String(action), controller_bound)
	for device_index: int in [0, 1]:
		for check: Dictionary in boot.run_input_smoke(device_index):
			_check(String(check["name"]), bool(check["passed"]))
	_check("initial UI distinguishes diagnosis from gameplay", boot.get_node("Margin/Status/Scope").get("text") ==
		"Diagnóstico técnico independiente de la microdemo")
	_check("UI status reports actual native engine", boot.details.text.contains("4.7.2"))
	var autoload_count: int = 0
	for property: Dictionary in ProjectSettings.get_property_list():
		if String(property["name"]).begins_with("autoload/"):
			autoload_count += 1
	_check("no autoload gameplay services", autoload_count == 0)
	await _check_physics()
	var pipeline_scene: String = _argument("--pipeline-scene=")
	_check("pipeline test resource supplied", not pipeline_scene.is_empty())
	if not pipeline_scene.is_empty():
		_check_pipeline(pipeline_scene)
	boot.queue_free()
	await process_frame
	_finish()


func _check_physics() -> void:
	var body: RigidBody3D = RigidBody3D.new()
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = SphereShape3D.new()
	body.add_child(collider)
	body.position = Vector3(0, 5, 0)
	root.add_child(body)
	for tick: int in range(8):
		await physics_frame
	_check("native 3D physics advances gravity", body.position.y < 4.99)
	body.queue_free()
	await process_frame


func _check_pipeline(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	_check("Blender GLB imported as PackedScene", packed != null)
	if packed == null:
		return
	var instance: Node3D = packed.instantiate() as Node3D
	_check("GLB instantiates as 3D", instance != null)
	if instance == null:
		return
	root.add_child(instance)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(instance, meshes)
	_check("GLB has exactly one probe mesh", meshes.size() == 1)
	if meshes.size() == 1:
		var probe: MeshInstance3D = meshes[0]
		_check("mesh data exists", probe.mesh != null)
		if probe.mesh != null:
			var bounds: AABB = probe.global_transform * probe.mesh.get_aabb()
			_check("Blender metres and Y-up: 2 x 6 x 4", bounds.size.is_equal_approx(Vector3(2, 6, 4)))
			_check("unit mesh scale", probe.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE))
			_check("one material surface", probe.mesh.get_surface_count() == 1)
			var material: StandardMaterial3D = probe.get_active_material(0) as StandardMaterial3D
			_check("glTF PBR material imported", material != null)
			if material != null:
				_check("material red base colour", material.albedo_color.is_equal_approx(Color(1, 0, 0, 1)))
				_check("material metallic preserved", is_equal_approx(material.metallic, 0.2))
				_check("material roughness preserved", is_equal_approx(material.roughness, 0.65))
	instance.free()


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, meshes)


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _check(label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})
	print(("PASS " if passed else "FAIL ") + label)


func _finish() -> void:
	var failed: int = 0
	for check: Dictionary in checks:
		if not bool(check["passed"]):
			failed += 1
	var result: Dictionary = {"ok": failed == 0, "passed": checks.size() - failed, "total": checks.size(), "checks": checks}
	var report_path: String = _argument("--report-path=")
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write native test report.")
			quit(2)
			return
		file.store_string(JSON.stringify(result, "\t") + "\n")
		file.close()
	print("FUTSAL_NATIVE_TESTS " + JSON.stringify(result))
	quit(0 if failed == 0 else 1)
