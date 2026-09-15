extends SceneTree

const Bootstrap = preload("res://bootstrap/bootstrap.gd")
const ARROWS: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]

var _checks: Array[Dictionary] = []
var _completed: bool = false
var _dispatch_checks: int = 0


func _initialize() -> void:
	create_timer(10.0).timeout.connect(func() -> void:
		if not _completed:
			quit(1))
	_run.call_deferred()


func _run() -> void:
	var bootstrap: Bootstrap = Bootstrap.new()
	var original: Dictionary = {}
	_check("diagnostic requires input schema 3", Bootstrap.INPUT_SCHEMA_VERSION == 3)
	_check("diagnostic requires exact gameplay version", Bootstrap.EXPECTED_PROJECT_VERSION == "0.4.0-preview")
	for index: int in ARROWS.size():
		var action: StringName = Bootstrap.REQUIRED_ACTIONS[index]
		original[action] = InputMap.action_get_events(action)
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == ARROWS[index]:
				InputMap.action_erase_event(action, event)
	var missing: Array[Dictionary] = bootstrap.run_input_smoke()
	var missing_arrows: Array[Dictionary] = missing.filter(func(check: Dictionary) -> bool:
		return String(check["name"]).begins_with("arrow keyboard"))
	_check("missing arrow fixture is rejected by the real diagnostic helper",
		not missing_arrows.is_empty() and missing_arrows.any(func(check: Dictionary) -> bool: return not bool(check["passed"])))
	_check("missing arrows do not disguise a legacy binding failure",
		missing.all(func(check: Dictionary) -> bool:
			return String(check["name"]).begins_with("arrow keyboard") or bool(check["passed"])))
	for index: int in ARROWS.size():
		var event: InputEventKey = InputEventKey.new()
		event.device = -1
		event.physical_keycode = ARROWS[index]
		event.keycode = ARROWS[index]
		InputMap.action_add_event(Bootstrap.REQUIRED_ACTIONS[index], event)
	for device: int in [0, 1]:
		var checks: Array[Dictionary] = bootstrap.run_input_smoke(device)
		_dispatch_checks += checks.size()
		_check("isolated keyboard/arrows/joypad press-release device %d" % device,
			checks.all(func(check: Dictionary) -> bool: return bool(check["passed"])))
		_check("dispatch count follows action and arrow arrays device %d" % device,
			checks.size() == (Bootstrap.REQUIRED_ACTIONS.size() * 2 + ARROWS.size()) * 4)
	for action: StringName in original:
		InputMap.action_erase_events(action)
		for event: InputEvent in original[action]:
			InputMap.action_add_event(action, event)
	bootstrap.free()
	_completed = true
	_report()


func _finalize() -> void:
	if not _completed:
		_check("input helper reached completion before shutdown", false)
		_report()


func _check(name: String, passed: bool) -> void:
	_checks.append({"name": name, "passed": passed})


func _report() -> void:
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	print("FUTSAL_INPUT_SCHEMA_TESTS " + JSON.stringify({
		"ok": failures.is_empty(), "passed": _checks.size() - failures.size(), "total": _checks.size(),
		"checks": _checks, "failures": failures, "native_dispatch_checks": _dispatch_checks,
		"scope": "isolated in-process arrow bindings; NOT shipped InputMap, default main, focus or GPU acceptance",
	}))
	quit(0 if failures.is_empty() else 1)
