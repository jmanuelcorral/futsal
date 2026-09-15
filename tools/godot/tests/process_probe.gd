extends SceneTree


func _initialize() -> void:
	print("FUTSAL_PROCESS_PROBE " + JSON.stringify({
		"process_id": OS.get_process_id(),
		"executable": OS.get_executable_path(),
		"headless": DisplayServer.get_name() == "headless",
		"scope": "isolated native process identity; NOT main, gameplay or GPU validation",
	}))
	_run.call_deferred()


func _run() -> void:
	var immediate: bool = OS.get_cmdline_user_args().has("--immediate")
	if not immediate:
		await create_timer(1.0).timeout
	quit(0)
