extends SceneTree
## Negative guard fixtures only; never a source/export gameplay validation.

const MainScene: PackedScene = preload("res://match/match.tscn")
const Simulation = preload("res://match/simulation/match_simulation.gd")
const Event = preload("res://match/simulation/match_event.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const MatchInput = preload("res://match/presentation/input/match_input.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scenario: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--entrypoint-negative="):
			scenario = argument.substr("--entrypoint-negative=".length())
	if not OS.get_cmdline_user_args().has("--smoke-test") or scenario.is_empty():
		push_error("The negative entrypoint fixture requires --smoke-test and --entrypoint-negative.")
		quit(2)
		return
	var main: Node = MainScene.instantiate()
	root.add_child(main)
	current_scene = main
	var simulation: Simulation = main.get_node("Simulation") as Simulation
	if main.get_node_or_null("MatchSmoke") == null:
		push_error("The real main has no opt-in smoke hook; the fixture cannot run.")
		quit(2)
		return
	match scenario:
		"micro-default":
			if int(main.call(&"start_match", Setup.new())) != OK:
				push_error("Could not establish the four-actor negative fixture through the public host API.")
				quit(2)
		"not-started":
			if simulation.reset() != OK:
				push_error("Could not establish the READY negative fixture through the public API.")
				quit(2)
		"no-ticks":
			var input_adapter: MatchInput = main.get_node("MatchInput") as MatchInput
			# The pre-tick sampler must stall with its authority, not resubmit a cached command.
			input_adapter.set_physics_process(false)
			simulation.set_physics_process(false)
		"input-repaired-on-restart":
			var bindings: Array[InputEvent] = InputMap.action_get_events(&"move_right")
			InputMap.action_erase_events(&"move_right")
			simulation.restarted.connect(func(_event: Event) -> void:
				for binding: InputEvent in bindings:
					InputMap.action_add_event(&"move_right", binding))
		_:
			push_error("Unknown negative entrypoint fixture: " + scenario)
			quit(2)
	print("FUTSAL_ENTRYPOINT_NEGATIVE " + JSON.stringify({
		"case": scenario, "scope": "in-process negative fixture; production files unchanged",
		"main_scene": main.scene_file_path,
	}))
