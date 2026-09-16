extends Control

const INPUT_SCHEMA_VERSION: int = 3
const EXPECTED_PROJECT_VERSION: String = "0.5.0-preview"
const DIAGNOSTIC_SCENE: String = "res://bootstrap/bootstrap.tscn"
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back",
	&"sprint", &"close_control", &"pass", &"shoot", &"pause", &"dribble",
]

@onready var details: Label = %Details


func _ready() -> void:
	var status: Dictionary = build_diagnostics()
	details.text = (
		"Proyecto %s  |  Godot %s\nRenderer: %s  |  GPU: %s\n"
		+ "Física configurada: %s / %d Hz\nInput schema v%d: %d acciones declaradas"
	) % [
		status["project_version"], status["engine_version"],
		status["rendering_method"], status["gpu_name"],
		status["physics_engine"], status["physics_ticks_per_second"],
		status["input_schema_version"], REQUIRED_ACTIONS.size(),
	]
	if OS.get_cmdline_user_args().has("--smoke-test"):
		_run_smoke.call_deferred()


func build_diagnostics() -> Dictionary:
	var headless: bool = DisplayServer.get_name() == "headless"
	var actions: Dictionary = {}
	for action: StringName in REQUIRED_ACTIONS:
		actions[String(action)] = InputMap.has_action(action)
	return {
		"scope": "technical-diagnostic-only",
		"diagnostic_scene": scene_file_path,
		"diagnostic_mode_requested": OS.get_cmdline_user_args().has("--diagnostic-bootstrap"),
		"configured_main_scene": String(ProjectSettings.get_setting("application/run/main_scene")),
		"project_version": String(ProjectSettings.get_setting("application/config/version")),
		"engine_version": String(Engine.get_version_info()["string"]),
		"executable": OS.get_executable_path(),
		"process_id": OS.get_process_id(),
		"editor_binary": OS.has_feature("editor"),
		"display_server": DisplayServer.get_name(),
		"headless": headless,
		"gpu_validated": false,
		"rendering_method_configured": String(
			ProjectSettings.get_setting("rendering/renderer/rendering_method")
		),
		"rendering_method": "headless" if headless else RenderingServer.get_current_rendering_method(),
		"rendering_driver": "dummy" if headless else RenderingServer.get_current_rendering_driver_name(),
		"gpu_name": "not measured (headless)" if headless else RenderingServer.get_video_adapter_name(),
		"gpu_vendor": "" if headless else RenderingServer.get_video_adapter_vendor(),
		"gpu_api": "" if headless else RenderingServer.get_video_adapter_api_version(),
		"physics_engine": String(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"input_schema_version": int(ProjectSettings.get_setting("futsal/preparation/input_schema_version")),
		"actions": actions,
		"viewport_width": int(get_viewport_rect().size.x),
		"viewport_height": int(get_viewport_rect().size.y),
		"timestamp_utc": Time.get_datetime_string_from_system(true),
	}


func _run_smoke() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var report: Dictionary = build_diagnostics()
	var checks: Array[Dictionary] = []
	_record(checks, "preview project metadata (not gameplay validation)", report["project_version"] == EXPECTED_PROJECT_VERSION)
	_record(checks, "explicit independent diagnostic scene", report["diagnostic_scene"] == DIAGNOSTIC_SCENE)
	_record(checks, "pinned engine runtime", report["engine_version"] == "4.7.2-stable (official)")
	_record(checks, "Forward+ configured", report["rendering_method_configured"] == "forward_plus")
	_record(checks, "Jolt configured", report["physics_engine"] == "Jolt Physics")
	_record(checks, "physics clock 60 Hz", report["physics_ticks_per_second"] == 60)
	_record(checks, "input schema version", report["input_schema_version"] == INPUT_SCHEMA_VERSION)
	for action: StringName in REQUIRED_ACTIONS:
		_record(checks, "input action: " + String(action), InputMap.has_action(action))
	checks.append_array(run_input_smoke())
	_record(checks, "viewport is 1080p", report["viewport_width"] == 1920 and report["viewport_height"] == 1080)
	if not OS.has_feature("editor"):
		_record(checks, "exported diagnostic explicitly requested", bool(report["diagnostic_mode_requested"]))
		_record(checks, "test runner excluded from export", not ResourceLoader.exists("res://tests/test_bootstrap.gd"))
	var capture_path: String = _argument("--capture-path=")
	if not bool(report["headless"]):
		_record(checks, "Forward+ active on GPU", report["rendering_method"] == "forward_plus")
		_record(checks, "rendering device present", RenderingServer.get_rendering_device() != null)
		_record(checks, "GPU name reported", not String(report["gpu_name"]).is_empty())
		if not capture_path.is_empty():
			await RenderingServer.frame_post_draw
			var image: Image = get_viewport().get_texture().get_image()
			_record(checks, "rendered image is 1080p", image.get_size() == Vector2i(1920, 1080))
			_record(checks, "rendered image contains UI", _has_pixel_variation(image))
			var saved: Error = image.save_png(capture_path)
			_record(checks, "rendered PNG saved", saved == OK)
			report["capture_path"] = capture_path
			report["gpu_validated"] = saved == OK and report["rendering_method"] == "forward_plus"
			report["frames_drawn"] = Engine.get_frames_drawn()
	else:
		_record(checks, "no GPU claim in headless mode", not bool(report["gpu_validated"]))
		_record(checks, "headless must not request capture", capture_path.is_empty())
	report["checks"] = checks
	var failed: int = 0
	for check: Dictionary in checks:
		if not bool(check["passed"]):
			failed += 1
	report["passed"] = checks.size() - failed
	report["total"] = checks.size()
	report["ok"] = failed == 0
	var report_path: String = _argument("--report-path=")
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write smoke report: %s (error %d)" % [report_path, FileAccess.get_open_error()])
			get_tree().quit(2)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("FUTSAL_BOOTSTRAP_SMOKE " + JSON.stringify(report))
	get_tree().quit(0 if failed == 0 else 1)


func run_input_smoke(device_index: int = 0) -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	var keys: Array[Key] = [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_CTRL, KEY_J, KEY_K, KEY_ESCAPE, KEY_L]
	var axes: Array[JoyAxis] = [
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_LEFT_Y,
		JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_TRIGGER_LEFT,
	]
	var axis_values: Array[float] = [-1.0, 1.0, -1.0, 1.0, 1.0, 1.0]
	var buttons: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_X]
	for index: int in REQUIRED_ACTIONS.size():
		var action: StringName = REQUIRED_ACTIONS[index]
		var key_press: InputEventKey = InputEventKey.new()
		key_press.device = device_index
		key_press.physical_keycode = keys[index]
		key_press.keycode = keys[index]
		key_press.pressed = true
		var key_release: InputEventKey = InputEventKey.new()
		key_release.device = device_index
		key_release.physical_keycode = keys[index]
		key_release.keycode = keys[index]
		key_release.pressed = false
		_check_input_pair(checks, action, key_press, key_release, "keyboard device %d" % device_index)
		if index < axes.size():
			var axis_press: InputEventJoypadMotion = InputEventJoypadMotion.new()
			axis_press.device = device_index
			axis_press.axis = axes[index]
			axis_press.axis_value = axis_values[index]
			var axis_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
			axis_release.device = device_index
			axis_release.axis = axes[index]
			axis_release.axis_value = 0.0
			_check_input_pair(checks, action, axis_press, axis_release, "controller device %d" % device_index)
		else:
			var button_press: InputEventJoypadButton = InputEventJoypadButton.new()
			button_press.device = device_index
			button_press.button_index = buttons[index - axes.size()]
			button_press.pressed = true
			button_press.pressure = 1.0
			var button_release: InputEventJoypadButton = InputEventJoypadButton.new()
			button_release.device = device_index
			button_release.button_index = buttons[index - axes.size()]
			button_release.pressed = false
			button_release.pressure = 0.0
			_check_input_pair(checks, action, button_press, button_release, "controller device %d" % device_index)
	var arrows: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	for index: int in arrows.size():
		var arrow_press: InputEventKey = InputEventKey.new()
		arrow_press.device = device_index
		arrow_press.physical_keycode = arrows[index]
		arrow_press.keycode = arrows[index]
		arrow_press.pressed = true
		var arrow_release: InputEventKey = arrow_press.duplicate() as InputEventKey
		arrow_release.pressed = false
		_check_input_pair(checks, REQUIRED_ACTIONS[index], arrow_press, arrow_release, "arrow keyboard device %d" % device_index)
	return checks


func _check_input_pair(
	checks: Array[Dictionary], action: StringName, press: InputEvent, release: InputEvent, source: String
) -> void:
	var label: String = source + " / " + String(action)
	_record(checks, label + " press matches InputMap", InputMap.event_is_action(press, action))
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	_record(checks, label + " native dispatch presses action", Input.is_action_pressed(action))
	_record(checks, label + " release matches InputMap", InputMap.event_is_action(release, action))
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	_record(checks, label + " native dispatch releases action", not Input.is_action_pressed(action))


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _record(checks: Array[Dictionary], label: String, passed: bool) -> void:
	checks.append({"name": label, "passed": passed})


func _has_pixel_variation(image: Image) -> bool:
	if image.is_empty():
		return false
	var background: Color = image.get_pixel(0, 0)
	for y: int in range(100, mini(image.get_height(), 480), 4):
		for x: int in range(96, mini(image.get_width(), 1700), 4):
			var pixel: Color = image.get_pixel(x, y)
			if absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) > 0.2:
				return true
	return false
