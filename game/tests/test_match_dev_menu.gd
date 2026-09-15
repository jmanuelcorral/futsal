extends SceneTree

const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const MenuScript = preload("res://match/presentation/development/match_dev_menu.gd")
const MenuScene: PackedScene = preload("res://match/presentation/development/match_dev_menu.tscn")
const HudScript = preload("res://match/presentation/hud/match_hud.gd")
const HudScene: PackedScene = preload("res://match/presentation/hud/match_hud.tscn")

var _menu: MenuScript
var _checks: Array[Dictionary] = []
var _mode_requests: Array[int] = []
var _ai_requests: Array[PackedInt32Array] = []
var _close_requests: int = 0
var _guide_requests: Array[bool] = []
var _exercise_requests: Array[int] = []
var _check_scope: String = "initialization"
var _case_context: String = ""
var _exercise_checks_completed: bool = false
var _intent_checks_completed: bool = false
var _suite_completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bindings_before: Dictionary = _binding_snapshot()
	_menu = MenuScene.instantiate() as MenuScript
	_check("real development scene instantiates its production script", _menu != null)
	if _menu == null:
		_finish()
		return
	_menu.mode_requested.connect(func(mode: Setup.Mode) -> void: _mode_requests.append(mode))
	_menu.ai_actor_ids_requested.connect(func(ids: Array[int]) -> void:
		_ai_requests.append(PackedInt32Array(ids)))
	_menu.close_requested.connect(func() -> void: _close_requests += 1)
	_menu.aim_guide_requested.connect(func(enabled: bool) -> void: _guide_requests.append(enabled))
	_menu.exercise_requested.connect(func(exercise: Setup.TrainingExercise) -> void: _exercise_requests.append(exercise))
	root.add_child(_menu)
	await _settle()
	await _run_case(_test_initial_state)
	_menu.set_aim_guide_enabled(true)
	await _run_case(_test_confirmed_groups)
	await _run_case(_test_partial_and_derived_groups)
	await _run_case(_test_mode_selection_and_micro)
	await _run_case(_test_selection_intents)
	await _run_case(_test_invalid_snapshots)
	await _run_case(_test_focus_and_input)
	await _run_case(_test_pre_ready)
	await _run_case(_test_hud_modal_exclusion)
	await _run_case(_test_guide_and_exercises)
	await _run_case(_test_resizing)
	_check("development menu never modifies any InputMap action", _binding_snapshot() == bindings_before)
	_check("development menu never changes game time", is_equal_approx(Engine.time_scale, 1.0))
	paused = false
	_menu.free()
	await process_frame
	_suite_completed = true
	_finish()


func _run_case(test: Callable) -> void:
	_check_scope = String(test.get_method()).trim_prefix("_test_")
	_case_context = ""
	await test.call()
	_check_scope = "completion"
	_case_context = ""


func _test_initial_state() -> void:
	_check("development starts closed", not _menu.is_open() and not (_menu.get_node("Frame") as Control).visible)
	_check("development can process during host SceneTree pause", _menu.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("no initial authority is invented", _label("StateSummary").text.begins_with("Sin estado confirmado"))
	for name: String in ["ModeSelector", "ApplyModeButton", "RivalToggle", "TeammatesToggle", "KeeperToggle", "AimGuideToggle", "ExerciseSelector", "ApplyExerciseButton"]:
		_check("unconfigured control is disabled: " + name, _button(name).disabled)
	_check("initial error is hidden", not _label("ErrorText").visible)
	_menu.set_open(true)
	_check("unconfigured menu can still be closed", _focused("CloseButton"))
	var before: int = _close_requests
	_key(KEY_ENTER)
	_check("close emits exactly one intention", _close_requests == before + 1)
	_check("close intention waits for the host", _menu.is_open())
	_check("opening and close intention do not pause authority", not paused)
	_menu.set_open(false)
	_check("host closes the presentation explicitly", not _menu.is_open())
	_menu.show_error("Error previo")
	_check("error API is usable while closed", _label("ErrorText").text == "Error previo")
	_menu.show_error("")
	_check("empty error clears the rejection", not _label("ErrorText").visible)


func _test_confirmed_groups() -> void:
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	var original: String = _snapshot_signature(state)
	_check("preview snapshot accepted", _menu.present(state) == OK)
	_menu.set_open(true)
	await _settle()
	_check("confirmed summary separates ten actors and nine effective AI", _label("StateSummary").text.contains("10 atletas · IA efectiva 9/9"))
	_check("confirmed selected actor is identified without being fixed", _label("StateSummary").text.contains("Control: ID 0 · CAMPO"))
	_check("default intent includes the currently controlled actor", _label("StateSummary").text.contains("Intención 10/10"))
	for name: String in ["RivalToggle", "TeammatesToggle", "KeeperToggle"]:
		_check("preview group uses an enabled native CheckBox: " + name,
			_control(name) is CheckBox and not _button(name).disabled and _button(name).button_pressed)
	_check("rival includes all five opponents", _label("RivalStatus").text == "Intención 5/5 · IA 5")
	_check("local fields include the selected actor's latent preference",
		_label("TeammatesStatus").text == "Intención 4/4 · IA 3 · Susp. ID 0")
	_check("local keeper is a separate group", _label("KeeperStatus").text == "Intención 1/1 · IA 1")
	var before: int = _ai_requests.size()
	_click(_control("RivalToggle"))
	_check("native mouse click requests the full remaining intent including selected",
		_ai_requests.size() == before + 1 and _last_ai_is([0, 2, 4, 6, 8]))
	_check("checkbox does not optimistically commit off", _button("RivalToggle").button_pressed)
	_check("status does not optimistically commit off", _label("RivalStatus").text == "Intención 5/5 · IA 5")
	_check("click leaves caller snapshot unchanged", _snapshot_signature(state) == original)
	_menu.show_error("No se pudo aplicar la IA")
	_menu.present(state)
	_check("continuous snapshots preserve a visible rejection", _label("ErrorText").visible and _label("ErrorText").text == "No se pudo aplicar la IA")
	_click(_control("RivalToggle"))
	_check("retry is based on the last confirmed intent", _last_ai_is([0, 2, 4, 6, 8]))
	_check("new request clears the old rejection", not _label("ErrorText").visible)
	_set_intent(state, [0, 2, 4, 6, 8])
	_menu.present(state)
	_check("host confirmation finally turns the rival group off", not _button("RivalToggle").button_pressed)
	_check("host confirmation updates the rival status", _label("RivalStatus").text == "Intención 0/5 · IA 0")
	_button("TeammatesToggle").grab_focus()
	_key(KEY_SPACE)
	_check("keyboard toggles teammates without removing local keeper", _last_ai_is([2]))
	_check("keyboard request still waits for confirmation", _button("TeammatesToggle").button_pressed)
	_set_intent(state, [2])
	_menu.present(state)
	_button("KeeperToggle").grab_focus()
	_joy_button(JOY_BUTTON_A, 1)
	_check("controller can request all AI off", _last_ai_is([]))
	_check("controller request still waits for confirmation", _button("KeeperToggle").button_pressed)
	_set_intent(state, [])
	_menu.present(state)
	_check("all AI off still reports ten actors", _label("StateSummary").text.contains("10 atletas · IA efectiva 0/9"))
	_check("all AI off does not remove snapshot actors", state.actors.size() == 10)
	_check("UI never resets supplied score clock phase or ball", state.score == Vector2i(2, 1)
		and is_equal_approx(state.seconds_remaining, 93.0) and state.phase == Snapshot.Phase.PAUSED
		and state.ball_position == Vector3(1.0, 0.12, 2.0))
	for name: String in ["RivalToggle", "TeammatesToggle", "KeeperToggle"]:
		_check("confirmed empty AI set is shown: " + name, not _button(name).button_pressed)
	_click(_control("RivalToggle"))
	_check("enabling rival includes the rival keeper", _last_ai_is([1, 3, 5, 7, 9]))


func _test_partial_and_derived_groups() -> void:
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_set_intent(state, [1, 2, 5])
	_menu.present(state)
	await _settle()
	_check("partial rival intent and activity are explicit", _label("RivalStatus").text == "Parcial 2/5 · IA 2")
	_check("partial checkbox is not falsely shown as fully enabled", not _button("RivalToggle").button_pressed)
	_click(_control("RivalToggle"))
	_check("activating partial rival enables every rival", _last_ai_is([1, 2, 3, 5, 7, 9]))
	_check("partial display waits for the host", _label("RivalStatus").text == "Parcial 2/5 · IA 2")
	_set_intent(state, [2, 4])
	_menu.present(state)
	_check("partial local fields are explicit", _label("TeammatesStatus").text == "Parcial 1/4 · IA 1")
	_click(_control("TeammatesToggle"))
	_check("activating partial fields includes the selected actor", _last_ai_is([0, 2, 4, 6, 8]))
	state = _snapshot(Setup.Mode.PREVIEW_5V5)
	state.actor(1).team_id = Snapshot.Team.HOME
	state.actor(4).team_id = Snapshot.Team.AWAY
	state.actors.reverse()
	var original: String = _snapshot_signature(state)
	_check("valid metadata can be presented in arbitrary actor order", _menu.present(state) == OK)
	_click(_control("RivalToggle"))
	_check("rival group derives from team metadata rather than a second ID catalog", _last_ai_is([0, 1, 2, 6, 8]))
	_check("deriving groups does not sort or mutate snapshot actors", _snapshot_signature(state) == original)
	state = _snapshot(Setup.Mode.PREVIEW_5V5)
	state.actor(2).role = Snapshot.Role.FIELD
	state.actor(6).role = Snapshot.Role.KEEPER
	_set_intent(state, [])
	_check("valid role metadata is accepted", _menu.present(state) == OK)
	_click(_control("KeeperToggle"))
	_check("keeper group derives from role rather than a hardcoded ID", _last_ai_is([6]))
	state.ai_intent_actor_ids.append(9)
	state.ai_actor_ids.append(9)
	state.actor(6).team_id = Snapshot.Team.AWAY
	_click(_control("KeeperToggle"))
	_check("later caller mutation cannot alter detached groups or intent", _last_ai_is([6]))
	state = _snapshot(Setup.Mode.PREVIEW_5V5)
	_set_intent(state, [9, 2, 5, 0])
	original = _snapshot_signature(state)
	_check("unordered intent and effective IDs can be safely copied", _menu.present(state) == OK)
	_check("normalizing presentation does not sort the caller array", _snapshot_signature(state) == original)
	_click(_control("RivalToggle"))
	_check("request IDs are sorted and preserve latent selected intent", _last_ai_is([0, 1, 2, 3, 5, 7, 9]))
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	var mutate_request: Callable = func(ids: Array[int]) -> void: ids.clear()
	_menu.ai_actor_ids_requested.connect(mutate_request)
	_click(_control("RivalToggle"))
	_menu.ai_actor_ids_requested.disconnect(mutate_request)
	_click(_control("RivalToggle"))
	_check("signal payload mutation cannot alter confirmed intent", _last_ai_is([0, 2, 4, 6, 8]))


func _test_mode_selection_and_micro() -> void:
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_menu.present(state)
	var before: int = _mode_requests.size()
	_click(_control("ModeSelector"))
	await _settle()
	_check("native mouse opens the mode dropdown", _control("ModeDropdown").visible)
	_check("dropdown starts on the selected preview option", _focused("PreviewChoice"))
	_key(KEY_UP)
	_check("keyboard navigates to micro option", _focused("MicroChoice"))
	_key(KEY_ENTER)
	_check("keyboard selection closes the dropdown", not _control("ModeDropdown").visible)
	_check("selection changes only the pending selector", (_button("ModeSelector") as Button).text.begins_with("1v1 de regresión"))
	_check("selection alone emits no reset", _mode_requests.size() == before)
	_check("selection alone keeps confirmed preview and ten actors", _label("StateSummary").text.begins_with("5v5 experimental · 10 atletas"))
	_menu.present(state)
	_check("repeated confirmed snapshots do not erase the user's pending selection", (_button("ModeSelector") as Button).text.begins_with("1v1 de regresión"))
	_click(_control("ApplyModeButton"))
	_check("only explicit Apply requests micro mode", _mode_requests.size() == before + 1 and _mode_requests.back() == Setup.Mode.MICRO_1V1)
	_check("Apply does not optimistically replace confirmed composition", not _button("TeammatesToggle").disabled
		and _label("StateSummary").text.contains("10 atletas") and _menu.is_open())
	_menu.show_error("Cambio de modo rechazado")
	_menu.present(state)
	_check("rejected mode remains visibly rejected", _label("ErrorText").text == "Cambio de modo rechazado")
	state = _snapshot(Setup.Mode.MICRO_1V1)
	_check("confirmed micro snapshot accepted", _menu.present(state) == OK)
	await _settle()
	_check("confirmed micro reports four actors", _label("StateSummary").text.begins_with("1v1 de regresión · 4 atletas"))
	_check("micro local field group is enabled with latent selected intent", not _button("TeammatesToggle").disabled
		and _button("TeammatesToggle").button_pressed and _label("TeammatesStatus").text == "Intención 1/1 · IA 0 · Susp. ID 0")
	var ai_before: int = _ai_requests.size()
	_click(_control("TeammatesToggle"))
	_check("mouse can change the selected micro actor's latent preference",
		_ai_requests.size() == ai_before + 1 and _last_ai_is([1, 2, 3]))
	_key(KEY_SPACE)
	_check("keyboard retries use confirmed intent without optimistic checkbox state",
		_ai_requests.size() == ai_before + 2 and _last_ai_is([1, 2, 3]) and _button("TeammatesToggle").button_pressed)
	_button("RivalToggle").grab_focus()
	_key(KEY_DOWN)
	_check("keyboard navigation includes the micro field preference", _focused("TeammatesToggle"))
	_key(KEY_DOWN)
	_check("keyboard still reaches the micro keeper", _focused("KeeperToggle"))
	_click(_control("RivalToggle"))
	_check("micro rival toggle preserves selected field and local keeper intent", _last_ai_is([0, 2]))
	_click(_control("KeeperToggle"))
	_check("micro keeper toggle preserves selected field and rival intent", _last_ai_is([0, 1, 3]))
	before = _mode_requests.size()
	_click(_control("ApplyModeButton"))
	_check("explicitly applying the same mode still requests a reset", _mode_requests.size() == before + 1
		and _mode_requests.back() == Setup.Mode.MICRO_1V1)
	_click(_control("ModeSelector"))
	await _settle()
	_joy_button(JOY_BUTTON_DPAD_DOWN, 1)
	_check("controller navigates dropdown choices", _focused("PreviewChoice"))
	_joy_button(JOY_BUTTON_A, 1)
	_check("controller selection does not apply the mode", _mode_requests.size() == before + 1
		and _label("StateSummary").text.contains("4 atletas"))
	_click(_control("ApplyModeButton"))
	_check("preview uses the exact typed mode value", _mode_requests.back() == Setup.Mode.PREVIEW_5V5)
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	_check("host preview confirmation retains the enabled local field group", not _button("TeammatesToggle").disabled)
	_click(_control("ModeSelector"))
	await _settle()
	_click(_control("MicroChoice"))
	_check("mouse chooses a dropdown option without applying", (_button("ModeSelector") as Button).text.begins_with("1v1 de regresión"))
	_menu.set_open(false)
	_menu.set_open(true)
	_check("closing discards an unapplied mode draft", (_button("ModeSelector") as Button).text.begins_with("5v5 experimental"))
	_click(_control("ModeSelector"))
	await _settle()
	ai_before = _ai_requests.size()
	_click(_control("KeeperToggle"))
	_check("outside dropdown click dismisses choices without toggling underlying AI",
		not _control("ModeDropdown").visible and _ai_requests.size() == ai_before)


func _test_selection_intents() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		_case_context = "default mode=%d" % mode
		var state: Snapshot = _snapshot(mode)
		var setup: Setup = Setup.new() if mode == Setup.Mode.MICRO_1V1 else Setup.preview_5v5()
		_check("public setup default is complete AI intent: " + str(mode), setup.ai_actor_ids == state.ai_intent_actor_ids)
		_check("public setup copy preserves selected-inclusive intent: mode=%d" % mode, setup.copy().ai_actor_ids == setup.ai_actor_ids)
		var full_intent: Array[int] = state.ai_intent_actor_ids.duplicate()
		var selections: Array[int] = [0, 2, 0]
		if mode == Setup.Mode.PREVIEW_5V5:
			selections = [0, 4, 2, 0]
		var fields: int = 1 if mode == Setup.Mode.MICRO_1V1 else 4
		for selected: int in selections:
			_case_context = "mode=%d intent=%s from=%d to=%d" % [mode, state.ai_intent_actor_ids, state.selected_actor_id, selected]
			_select_actor(state, selected)
			var original: String = _snapshot_signature(state)
			var ai_before: int = _ai_requests.size()
			_check("confirmed HOME selection is accepted: mode=%d actor=%d" % [mode, selected], _menu.present(state) == OK)
			_check("selected ID and role are displayed from the snapshot",
				_label("StateSummary").text.contains("Control: ID %d · %s" % [selected, "PORTERO" if selected == 2 else "CAMPO"]))
			_check("selection changes do not rewrite intent", state.ai_intent_actor_ids == full_intent)
			_check("presenting selection does not emit a preference request", _ai_requests.size() == ai_before)
			_check("presenting selection leaves caller state intact", _snapshot_signature(state) == original)
			_check("all intended groups stay checked across handoff",
				_button("RivalToggle").button_pressed and _button("TeammatesToggle").button_pressed
				and _button("KeeperToggle").button_pressed)
			var field_status: String = "Intención %d/%d · IA %d" % [fields, fields, fields if selected == 2 else fields - 1]
			var keeper_status: String = "Intención 1/1 · IA %d" % (0 if selected == 2 else 1)
			if selected == 2:
				keeper_status += " · Susp. ID 2"
			else:
				field_status += " · Susp. ID %d" % selected
			_check("field preference and effective activity remain distinct", _label("TeammatesStatus").text == field_status)
			_check("keeper preference can be suspended by human control", _label("KeeperStatus").text == keeper_status)
		_set_intent(state, [])
		for selected: int in selections:
			_case_context = "mode=%d intent=[] from=%d to=%d" % [mode, state.selected_actor_id, selected]
			_select_actor(state, selected)
			_check("empty intent survives each confirmed focus change", _menu.present(state) == OK)
			_check("focus never implicitly re-enables any preference", not _button("RivalToggle").button_pressed
				and not _button("TeammatesToggle").button_pressed and not _button("KeeperToggle").button_pressed)
			_check("effective activity remains empty with all actors retained", state.ai_actor_ids.is_empty()
				and _label("StateSummary").text.contains("%d atletas · IA efectiva 0/%d" % [state.actors.size(), state.actors.size() - 1]))
	_case_context = ""
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_set_intent(state, [0, 4, 6])
	var expected_effective: Array[PackedInt32Array] = [
		PackedInt32Array([4, 6]), PackedInt32Array([0, 6]),
		PackedInt32Array([0, 4, 6]), PackedInt32Array([4, 6]),
	]
	var step: int = 0
	for selected: int in [0, 4, 2, 0]:
		_case_context = "subset=%s from=%d to=%d" % [state.ai_intent_actor_ids, state.selected_actor_id, selected]
		_select_actor(state, selected)
		_check("subset intent accepts field and keeper selection", _menu.present(state) == OK)
		_check("effective subset follows supplied selected ID", PackedInt32Array(state.ai_actor_ids) == expected_effective[step])
		_check("partial local intent remains exactly three of four", _label("TeammatesStatus").text.begins_with("Parcial 3/4"))
		_check("unconfigured keeper is never silently re-enabled", not _button("KeeperToggle").button_pressed
			and _label("KeeperStatus").text == "Intención 0/1 · IA 0")
		step += 1
	_case_context = ""
	_set_intent(state, [4])
	_menu.present(state)
	_click(_control("TeammatesToggle"))
	_check("enabling partial intent returns all HOME fields including the selected actor", _last_ai_is([0, 4, 6, 8]))
	_check("partial request remains uncommitted before host response", not _button("TeammatesToggle").button_pressed
		and _label("TeammatesStatus").text == "Parcial 1/4 · IA 1")
	_menu.show_error("Cambio rechazado; revisa la selección")
	_select_actor(state, 4)
	_menu.present(state)
	_check("rejection remains visible after confirmed focus change", _label("ErrorText").visible)
	_check("selected-only latent preference has no effective activity",
		_label("TeammatesStatus").text == "Parcial 1/4 · IA 0 · Susp. ID 4")
	_click(_control("TeammatesToggle"))
	_check("retry after handoff keeps the selected latent preference", _last_ai_is([0, 4, 6, 8]))
	_check("retry cannot optimistically enable missing preferences", _label("TeammatesStatus").text == "Parcial 1/4 · IA 0 · Susp. ID 4")
	state = _snapshot(Setup.Mode.MICRO_1V1)
	_set_intent(state, [0])
	_menu.present(state)
	_click(_control("TeammatesToggle"))
	_check("micro selected-only preference can be switched fully off", _last_ai_is([]))
	_check("latent micro checkbox still waits for host confirmation", _button("TeammatesToggle").button_pressed)
	_set_intent(state, [])
	_menu.present(state)
	_select_actor(state, 2)
	_menu.present(state)
	_click(_control("KeeperToggle"))
	_check("controlled keeper preference can be enabled without effective keeper AI", _last_ai_is([2]))
	_check("keeper checkbox does not commit the requested latent preference", not _button("KeeperToggle").button_pressed)
	_set_intent(state, [2])
	_menu.present(state)
	_check("host confirms keeper preference while suspending execution", _button("KeeperToggle").button_pressed
		and _label("KeeperStatus").text == "Intención 1/1 · IA 0 · Susp. ID 2")
	state = _snapshot(Setup.Mode.PREVIEW_5V5)
	_select_actor(state, 4)
	_menu.present(state)
	for phase: Snapshot.Phase in [
		Snapshot.Phase.GOAL_PAUSE, Snapshot.Phase.RESTART_PAUSE, Snapshot.Phase.PAUSED, Snapshot.Phase.FINISHED,
	]:
		state.phase = phase
		_case_context = "phase=%d selected=%d" % [phase, state.selected_actor_id]
		var original: String = _snapshot_signature(state)
		_check("phase presentation accepts the confirmed last focus: " + str(phase), _menu.present(state) == OK)
		_check("phase cannot implicitly reset focus or intent",
			_label("StateSummary").text.contains("Control: ID 4 · CAMPO") and _snapshot_signature(state) == original)
	_case_context = ""
	_click(_control("ModeSelector"))
	await _settle()
	_click(_control("MicroChoice"))
	_select_actor(state, 2)
	_menu.present(state)
	_check("focus change does not erase a pending mode choice", (_button("ModeSelector") as Button).text.begins_with("1v1 de regresión"))
	_check("pending mode selection cannot reset confirmed player focus", _label("StateSummary").text.contains("Control: ID 2 · PORTERO"))
	var before: String = _view_signature()
	state.mode = Setup.Mode.MICRO_1V1
	_check("mode and composition mismatch is rejected", _menu.present(state) == ERR_INVALID_PARAMETER)
	_check("mode mismatch cannot change focus or pending selections", _view_signature() == before)
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	var confirmed: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	var response: Dictionary = {"result": ERR_UNCONFIGURED}
	var accept_snapshot: Callable = func(ids: Array[int]) -> void:
		_set_intent(confirmed, ids)
		response["result"] = _menu.present(confirmed)
	_menu.ai_actor_ids_requested.connect(accept_snapshot)
	_click(_control("RivalToggle"))
	_menu.ai_actor_ids_requested.disconnect(accept_snapshot)
	_check("native click can receive a synchronous confirmed snapshot", response["result"] == OK
		and not _button("RivalToggle").button_pressed and _last_ai_is([0, 2, 4, 6, 8]))
	var reject_snapshot: Callable = func(_ids: Array[int]) -> void:
		_menu.show_error("Solicitud rechazada")
	_menu.ai_actor_ids_requested.connect(reject_snapshot)
	_click(_control("RivalToggle"))
	_menu.ai_actor_ids_requested.disconnect(reject_snapshot)
	_check("native click rejection preserves confirmed preference", not _button("RivalToggle").button_pressed
		and _label("RivalStatus").text == "Intención 0/5 · IA 0" and _label("ErrorText").text == "Solicitud rechazada")
	_intent_checks_completed = true


func _test_invalid_snapshots() -> void:
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	_menu.show_error("Rechazo previo")
	_button("KeeperToggle").grab_focus()
	var before: String = _view_signature()
	_check("null snapshot returns ERR_INVALID_PARAMETER", _menu.present(null) == ERR_INVALID_PARAMETER)
	_check("null snapshot is atomic", _view_signature() == before)
	var cases: Array[Dictionary] = []
	var bad: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.set("mode", 99)
	cases.append({"name": "unknown mode", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.set("training_exercise", 99)
	cases.append({"name": "unknown training exercise", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actors.pop_back()
	cases.append({"name": "incorrect actor count", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actors[4] = bad.actors[1]
	cases.append({"name": "duplicate actor ID", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actors[4] = null
	cases.append({"name": "null actor", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(9).actor_id = 10
	cases.append({"name": "out of mode actor ID", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(0).human_controlled = false
	cases.append({"name": "missing human", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(4).human_controlled = true
	cases.append({"name": "second human", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(0).team_id = Snapshot.Team.AWAY
	cases.append({"name": "human on wrong team", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(4).team_id = 99
	cases.append({"name": "unknown team", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(4).set("role", 99)
	cases.append({"name": "unknown role", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.actor(4).role = Snapshot.Role.KEEPER
	cases.append({"name": "incoherent role counts", "state": bad})
	for id: int in [-1, 10]:
		bad = _snapshot(Setup.Mode.PREVIEW_5V5)
		bad.selected_actor_id = id
		cases.append({"name": "invalid selected ID " + str(id), "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.selected_actor_id = 4
	cases.append({"name": "selected ID does not match the sole human", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	_select_actor(bad, 1)
	cases.append({"name": "selected actor belongs to AWAY", "state": bad})
	for invalid_ids: Array in [[0], [1, 1], [10]]:
		bad = _snapshot(Setup.Mode.PREVIEW_5V5)
		bad.ai_actor_ids.assign(invalid_ids)
		cases.append({"name": "invalid effective AI IDs " + str(invalid_ids), "state": bad})
	for invalid_ids: Array in [[-1], [10], [0, 0], [1, 1]]:
		bad = _snapshot(Setup.Mode.PREVIEW_5V5)
		bad.ai_intent_actor_ids.assign(invalid_ids)
		cases.append({"name": "invalid intent IDs " + str(invalid_ids), "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	bad.ai_actor_ids.pop_back()
	cases.append({"name": "effective activity omits intended nonselected actor", "state": bad})
	bad = _snapshot(Setup.Mode.PREVIEW_5V5)
	_set_intent(bad, [1])
	bad.ai_actor_ids.append(2)
	cases.append({"name": "effective activity silently re-enables an unconfigured actor", "state": bad})
	bad = _snapshot(Setup.Mode.MICRO_1V1)
	_select_actor(bad, 2)
	bad.ai_actor_ids.append(2)
	cases.append({"name": "controlled keeper cannot also run effective AI", "state": bad})
	for invalid: Dictionary in cases:
		_check(String(invalid["name"]) + " returns ERR_INVALID_PARAMETER",
			_menu.present(invalid["state"] as Snapshot) == ERR_INVALID_PARAMETER)
		_check(String(invalid["name"]) + " leaves all presentation and signals untouched", _view_signature() == before)
	_menu.show_error("")


func _test_focus_and_input() -> void:
	_menu.set_open(false)
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	var external: Button = Button.new()
	external.text = "Host focus fixture"
	root.add_child(external)
	external.grab_focus()
	_menu.set_open(true)
	await _settle()
	_check("menu starts focused on the mode selector", _focused("ModeSelector"))
	_key(KEY_TAB)
	_check("Tab reaches explicit Apply", _focused("ApplyModeButton"))
	_menu.set_open(true)
	_check("repeated open calls preserve focus", _focused("ApplyModeButton"))
	_key(KEY_DOWN)
	_check("keyboard reaches rival group", _focused("RivalToggle"))
	_key(KEY_DOWN)
	_check("keyboard reaches teammate group", _focused("TeammatesToggle"))
	_key(KEY_DOWN)
	_check("keyboard reaches local keeper group", _focused("KeeperToggle"))
	_key(KEY_DOWN)
	_check("keyboard reaches confirmed aim preference", _focused("AimGuideToggle"))
	_key(KEY_DOWN)
	_check("keyboard reaches the exercise draft", _focused("ExerciseSelector"))
	_key(KEY_DOWN)
	_check("keyboard reaches explicit exercise restart", _focused("ApplyExerciseButton"))
	_key(KEY_DOWN)
	_check("keyboard reaches close", _focused("CloseButton"))
	_key(KEY_DOWN)
	_check("focus wraps without reaching host controls", _focused("ModeSelector"))
	_key(KEY_TAB, true)
	_check("reverse Tab wraps to close", _focused("CloseButton"))
	_joy_button(JOY_BUTTON_DPAD_UP, 0)
	_joy_button(JOY_BUTTON_DPAD_UP, 0)
	_joy_button(JOY_BUTTON_DPAD_UP, 0)
	_joy_button(JOY_BUTTON_DPAD_UP, 0)
	_check("controller device 0 navigates groups", _focused("KeeperToggle"))
	_joy_axis(0.2, 1)
	_check("left stick drift does not move focus", _focused("KeeperToggle"))
	_joy_axis(0.8, 1, false)
	_check("controller device 1 left stick moves focus", _focused("AimGuideToggle"))
	_joy_axis(0.9, 1, false)
	_check("held stick cannot race through options", _focused("AimGuideToggle"))
	_joy_axis(0.0, 1)
	_joy_axis(-0.8, 1)
	_check("stick neutral rearms navigation", _focused("KeeperToggle"))
	var style: StyleBoxFlat = _button("RivalToggle").get_theme_stylebox("focus") as StyleBoxFlat
	_check("native checkbox has a visible focus outline", style != null and style.border_width_left >= 3)
	_button("ModeSelector").grab_focus()
	_key(KEY_ENTER)
	_check("keyboard opens dropdown without depending on default ui_accept", _control("ModeDropdown").visible)
	var close_before: int = _close_requests
	_key(KEY_ESCAPE, false, true)
	_check("echoed cancel does not close or request close", _close_requests == close_before)
	_key(KEY_ESCAPE)
	_check("cancel from dropdown requests returning to host once", _close_requests == close_before + 1)
	_check("cancel closes dropdown but waits for host to close the menu", not _control("ModeDropdown").visible and _menu.is_open())
	_menu.set_open(false)
	_check("closing restores previous external focus", root.gui_get_focus_owner() == external)
	close_before = _close_requests
	_key(KEY_ESCAPE)
	_joy_button(JOY_BUTTON_START, 1)
	_check("closed development does not handle pause input", _close_requests == close_before)
	_menu.set_open(true)
	paused = true
	_joy_button(JOY_BUTTON_B, 1)
	_check("controller can request close while SceneTree is paused", _close_requests == close_before + 1)
	_check("controller close does not unpause SceneTree", paused)
	_menu.set_open(false)
	_check("set_open never changes global pause", paused)
	paused = false
	external.free()


func _test_pre_ready() -> void:
	var pending: MenuScript = MenuScene.instantiate() as MenuScript
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_check("snapshot can be presented before ready", pending.present(state) == OK)
	pending.show_error("Mensaje del anfitrión")
	pending.set_aim_guide_enabled(false)
	pending.set_open(true)
	state.ai_intent_actor_ids.clear()
	state.ai_actor_ids.clear()
	root.add_child(pending)
	await _settle()
	_check("pre-ready open is rendered", pending.is_open() and (pending.get_node("Frame") as Control).visible)
	_check("pre-ready snapshot copies intent and effective lists", (pending.get_node("%StateSummary") as Label).text.contains("IA efectiva 9/9")
		and (pending.get_node("%StateSummary") as Label).text.contains("Intención 10/10"))
	_check("pre-ready error is rendered", (pending.get_node("%ErrorText") as Label).text == "Mensaje del anfitrión")
	_check("pre-ready guide preference is confirmed without enabling it", not (pending.get_node("%AimGuideToggle") as CheckBox).button_pressed
		and not (pending.get_node("%AimGuideToggle") as CheckBox).disabled)
	_check("pre-ready open gets usable native focus", root.gui_get_focus_owner() == pending.get_node("%ModeSelector"))
	pending.free()
	await _settle()


func _test_hud_modal_exclusion() -> void:
	_menu.set_open(false)
	_menu.present(_snapshot(Setup.Mode.PREVIEW_5V5))
	var hud: HudScript = HudScene.instantiate() as HudScript
	root.add_child(hud)
	hud.set_mode(Setup.Mode.PREVIEW_5V5)
	hud.update_score(7, 6)
	hud.update_clock(88.0)
	hud.set_paused(true)
	var requests: Dictionary = {"resume": 0, "pause": 0}
	hud.resume_requested.connect(func() -> void: requests["resume"] += 1)
	hud.pause_requested.connect(func() -> void: requests["pause"] += 1)
	var open_development: Callable = func() -> void:
		hud.set_development_open(true)
		_menu.set_open(true)
	var close_development: Callable = func() -> void:
		_menu.set_open(false)
		hud.set_development_open(false)
	hud.development_requested.connect(open_development)
	_menu.close_requested.connect(close_development)
	await _settle()
	for cancel: String in ["keyboard", "controller_b", "controller_start", "exercise_popup"]:
		_click(hud.get_node("%DevelopmentButton") as Control)
		await _settle()
		_check(cancel + ": native pause button opens development", _menu.is_open())
		_check(cancel + ": exactly one modal is visible", not (hud.get_node("%PauseOverlay") as Control).visible
			and (_menu.get_node("Frame") as Control).visible)
		root.move_child(_menu, root.get_child_count() - 1)
		if cancel == "controller_start":
			_click(_control("ModeSelector"))
			await _settle()
		elif cancel == "exercise_popup":
			_click(_control("ExerciseSelector"))
			await _settle()
		match cancel:
			"keyboard":
				_key(KEY_ESCAPE)
			"controller_b":
				_joy_button(JOY_BUTTON_B, 0)
			"controller_start":
				_joy_button(JOY_BUTTON_START, 1)
			"exercise_popup":
				_key(KEY_ESCAPE)
		await _settle()
		_check(cancel + ": host restores pause rather than gameplay", not _menu.is_open()
			and (hud.get_node("%PauseOverlay") as Control).visible)
		_check(cancel + ": cancel cannot leak through as resume", requests["resume"] == 0 and requests["pause"] == 0)
		_check(cancel + ": entry focus is restored", root.gui_get_focus_owner() == hud.get_node("%DevelopmentButton"))
		_check(cancel + ": score and clock are unchanged", (hud.get_node("%Score") as Label).text == "7 – 6"
			and (hud.get_node("%Clock") as Label).text == "01:28")
	_check("UI modal handoff never changes SceneTree pause", not paused)
	hud.show_result(7, 6, "Resultado confirmado")
	hud.set_paused(false)
	await _settle()
	_click(hud.get_node("%DevelopmentButton") as Control)
	await _settle()
	_check("development can also open from a real result overlay", _menu.is_open()
		and not (hud.get_node("%PauseOverlay") as Control).visible)
	_joy_button(JOY_BUTTON_B, 1)
	await _settle()
	_check("return from development restores result without Continue", not _menu.is_open()
		and (hud.get_node("%PauseOverlay") as Control).visible and not (hud.get_node("%ResumeButton") as Button).visible)
	_check("result return cannot request a resume", requests["resume"] == 0)
	_menu.close_requested.disconnect(close_development)
	hud.development_requested.disconnect(open_development)
	hud.free()
	await _settle()


func _test_guide_and_exercises() -> void:
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_menu.present(state)
	_menu.set_aim_guide_enabled(true)
	_menu.set_open(true)
	await _settle()
	var selector: OptionButton = _control("ExerciseSelector") as OptionButton
	_check("exercise selector is a real bounded OptionButton", selector.item_count == 12)
	var before: int = _guide_requests.size()
	_click(_control("AimGuideToggle"))
	_check("native guide checkbox requests disabling once", _guide_requests.size() == before + 1 and not _guide_requests.back())
	_check("guide checkbox remains at the confirmed value", _button("AimGuideToggle").button_pressed)
	_menu.show_error("Guía rechazada")
	_menu.present(state)
	_check("rejected guide request remains visible and uncommitted", _button("AimGuideToggle").button_pressed
		and _label("ErrorText").text == "Guía rechazada")
	_menu.set_aim_guide_enabled(false)
	_check("only host confirmation disables the shown guide preference", not _button("AimGuideToggle").button_pressed)
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		_case_context = "guide preference mode=%d" % mode
		state = _snapshot(mode)
		_menu.present(state)
		_check("confirmed guide preference survives mode=%d" % mode, not _button("AimGuideToggle").button_pressed)
		for exercise: int in range(12):
			_case_context = "mode=%d exercise=%d" % [mode, exercise]
			var original: String = _snapshot_signature(state)
			var original_intent: Array[int] = state.ai_intent_actor_ids.duplicate()
			var requests_before: int = _exercise_requests.size()
			selector.grab_focus()
			_key(KEY_ENTER)
			await _settle()
			_check("keyboard opens the actual exercise popup", selector.get_popup().visible)
			var steps: int = posmod(exercise - selector.selected, selector.item_count)
			for step: int in steps:
				_joy_button(JOY_BUTTON_DPAD_DOWN, 1)
			_joy_button(JOY_BUTTON_A, 1)
			await _settle()
			_check("controller confirms the selected draft only", selector.get_selected_id() == exercise
				and _exercise_requests.size() == requests_before and _snapshot_signature(state) == original)
			_check("selection closes its native popup", not selector.get_popup().visible)
			_button("ApplyExerciseButton").grab_focus()
			_key(KEY_ENTER)
			_check("explicit exercise button emits exactly one typed request", _exercise_requests.size() == requests_before + 1
				and _exercise_requests.back() == exercise)
			_check("exercise request does not fabricate authority confirmation", _snapshot_signature(state) == original
				and selector.tooltip_text.contains(MenuScript.EXERCISE_LABELS[state.training_exercise]))
			state.training_exercise = exercise as Setup.TrainingExercise
			_check("confirmed exercise snapshot is accepted", _menu.present(state) == OK)
			_check("host confirmation is now represented", selector.tooltip_text.contains(MenuScript.EXERCISE_LABELS[exercise]))
			_check("exercise presentation retains exact AI intent and guide preference",
				state.ai_intent_actor_ids == original_intent and not _button("AimGuideToggle").button_pressed)
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		state = _snapshot(mode)
		_menu.present(state)
		for controller: bool in [false, true]:
			for exercise: int in [0, 6, 11]:
				_case_context = "native route=%s mode=%d exercise=%d" % ["controller" if controller else "keyboard", mode, exercise]
				var requests_before: int = _exercise_requests.size()
				var original: String = _snapshot_signature(state)
				for attempt: int in 12:
					if _focused("ExerciseSelector"):
						break
					if controller:
						_joy_button(JOY_BUTTON_DPAD_DOWN, 1)
					else:
						_key(KEY_TAB)
				_check("native focus navigation reaches the exercise selector", _focused("ExerciseSelector"))
				if not _focused("ExerciseSelector"):
					return
				if controller:
					_joy_button(JOY_BUTTON_A, 1)
				else:
					_key(KEY_ENTER)
				await _settle()
				var popup: PopupMenu = selector.get_popup()
				_check("native accept opens the real popup without applying", popup.visible
					and _exercise_requests.size() == requests_before)
				if not popup.visible:
					return
				var draft_before: int = selector.get_selected_id()
				for step: int in selector.item_count:
					var focused: int = popup.get_focused_item()
					if focused >= 0 and popup.get_item_id(focused) == exercise:
						break
					if controller:
						_joy_button(JOY_BUTTON_DPAD_DOWN, 1)
					else:
						_key(KEY_DOWN)
					var next: int = posmod(focused + 1, selector.item_count)
					_check("one native navigation step from %d to %d" % [focused, next], popup.get_focused_item() == next)
				var focused: int = popup.get_focused_item()
				_check("highlighting reaches the requested option without confirming its draft",
					focused >= 0 and popup.get_item_id(focused) == exercise
					and selector.get_selected_id() == draft_before and _exercise_requests.size() == requests_before)
				if controller:
					_joy_button(JOY_BUTTON_A, 1)
				else:
					_key(KEY_ENTER)
				await _settle()
				_check("native confirmation closes the popup and returns focus once",
					not popup.visible and selector.get_selected_id() == exercise and _focused("ExerciseSelector"))
				_check("native draft confirmation preserves authoritative exercise mode AI and guide",
					_snapshot_signature(state) == original and _exercise_requests.size() == requests_before
					and selector.tooltip_text.contains(MenuScript.EXERCISE_LABELS[state.training_exercise])
					and not _button("AimGuideToggle").button_pressed)
				if controller:
					_joy_button(JOY_BUTTON_DPAD_DOWN, 1)
				else:
					_key(KEY_TAB)
				_check("native navigation reaches the explicit exercise action", _focused("ApplyExerciseButton"))
				if not _focused("ApplyExerciseButton"):
					return
				if controller:
					_joy_button(JOY_BUTTON_A, 1)
				else:
					_key(KEY_ENTER)
				await _settle()
				_check("native explicit apply emits exactly the requested exercise once",
					_exercise_requests.size() == requests_before + 1 and _exercise_requests.back() == exercise
					and _snapshot_signature(state) == original)
				state.training_exercise = exercise as Setup.TrainingExercise
				_check("only the host snapshot commits the natively requested exercise", _menu.present(state) == OK
					and selector.tooltip_text.contains(MenuScript.EXERCISE_LABELS[exercise]))
	_case_context = "exercise error and cancellation"
	var snapshot_before: String = _snapshot_signature(state)
	var reject_exercise: Callable = func(_exercise: Setup.TrainingExercise) -> void:
		_menu.show_error("No se pudo iniciar el ejercicio")
	_menu.exercise_requested.connect(reject_exercise)
	_click(_control("ApplyExerciseButton"))
	_menu.exercise_requested.disconnect(reject_exercise)
	_check("exercise error remains explicit after a native rejected click", _label("ErrorText").visible
		and _label("ErrorText").text == "No se pudo iniciar el ejercicio" and _snapshot_signature(state) == snapshot_before)
	selector.grab_focus()
	_key(KEY_LEFT)
	_check("left arrow selects a draft without mutating the snapshot", _snapshot_signature(state) == snapshot_before)
	_menu.set_open(false)
	_menu.set_open(true)
	_check("closing discards only the uncommitted exercise choice", selector.get_selected_id() == state.training_exercise)
	var confirm_guide: Callable = func(enabled: bool) -> void: _menu.set_aim_guide_enabled(enabled)
	_menu.aim_guide_requested.connect(confirm_guide)
	_click(_control("AimGuideToggle"))
	_menu.aim_guide_requested.disconnect(confirm_guide)
	_check("native guide click supports synchronous host confirmation", _button("AimGuideToggle").button_pressed)
	_exercise_checks_completed = true


func _test_resizing() -> void:
	var state: Snapshot = _snapshot(Setup.Mode.PREVIEW_5V5)
	_menu.present(state)
	_menu.set_open(true)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		_menu.show_error("No se pudo aplicar este cambio. ".repeat(80))
		await _settle()
		var view: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution))
		var panel_bounds: Rect2 = _screen_rect(_control("DevPanel"))
		_check(str(resolution) + " development panel fits even with a long error", view.encloses(panel_bounds))
		if not view.encloses(panel_bounds):
			print("LAYOUT panel=", panel_bounds, " viewport=", view)
			for child: Node in _control("DevPanel").get_node("Rows").get_children():
				var control: Control = child as Control
				print("LAYOUT ", control.name, " size=", control.size, " minimum=", control.get_combined_minimum_size())
		var navigation: Label = _menu.get_node("Frame/Center/DevPanel/Rows/Footer/NavigationHint") as Label
		_check(str(resolution) + " navigation guide has exactly two native text lines", navigation.get_line_count() == 2)
		var error_bounds: Rect2 = _screen_rect(_label("ErrorText"))
		var error_slot: Rect2 = _screen_rect(_label("ErrorText").get_parent() as Control)
		_check(str(resolution) + " long error stays within its reserved slot", error_slot.encloses(error_bounds))
		if not error_slot.encloses(error_bounds):
			print("LAYOUT error=", error_bounds, " slot=", error_slot)
		_check(str(resolution) + " modal input cover fills the viewport",
			_screen_rect(_menu.get_node("Frame") as Control).is_equal_approx(view))
		for name: String in ["ModeSelector", "ApplyModeButton", "RivalToggle", "TeammatesToggle", "KeeperToggle", "AimGuideToggle", "ExerciseSelector", "ApplyExerciseButton", "CloseButton"]:
			_check(str(resolution) + " real control is visible and inside viewport: " + name,
				_control(name).is_visible_in_tree() and view.encloses(_screen_rect(_control(name))))
		var stretch: Vector2 = root.get_stretch_transform().get_scale()
		var frame_scale: Vector2 = (_menu.get_node("Frame") as Control).scale
		_check(str(resolution) + " group text stays at least 20 physical pixels",
			float(_button("RivalToggle").get_theme_font_size("font_size")) * stretch.y * frame_scale.y >= 19.99)
		_click(_control("ModeSelector"))
		await _settle()
		_check(str(resolution) + " real dropdown opens and fits", _control("ModeDropdown").visible
			and view.encloses(_screen_rect(_control("ModeDropdown"))))
		_click(_control("PreviewChoice"))
		_check(str(resolution) + " mouse can select from scaled dropdown", not _control("ModeDropdown").visible)
		for selected: int in [4, 2, 0]:
			_select_actor(state, selected)
			_menu.present(state)
			await _settle()
			_check(str(resolution) + " selection and latent activity fit: " + str(selected),
				view.encloses(_screen_rect(_control("DevPanel"))))
			_check(str(resolution) + " confirmed summary keeps two readable lines: " + str(selected),
				_label("StateSummary").get_line_count() == 2)
	_menu.set_open(false)


func _snapshot(mode: Setup.Mode) -> Snapshot:
	var state: Snapshot = Snapshot.new()
	state.mode = mode
	state.selected_actor_id = 0
	state.phase = Snapshot.Phase.PAUSED
	state.score = Vector2i(2, 1)
	state.seconds_remaining = 93.0
	state.tick = 120
	state.ball_position = Vector3(1.0, 0.12, 2.0)
	state.actors = []
	state.ai_intent_actor_ids = []
	state.ai_actor_ids = []
	var home_ids: Array[int] = [0, 2, 4, 6, 8]
	var count: int = 4 if mode == Setup.Mode.MICRO_1V1 else 10
	for id: int in count:
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = Snapshot.Team.HOME if home_ids.has(id) else Snapshot.Team.AWAY
		actor.role = Snapshot.Role.KEEPER if id == 2 or id == 3 else Snapshot.Role.FIELD
		actor.human_controlled = id == 0
		state.actors.append(actor)
		state.ai_intent_actor_ids.append(id)
		if not actor.human_controlled:
			state.ai_actor_ids.append(id)
	return state


func _set_intent(state: Snapshot, ids: Array[int]) -> void:
	state.ai_intent_actor_ids = ids.duplicate()
	state.ai_actor_ids = ids.duplicate()
	state.ai_actor_ids.erase(state.selected_actor_id)


func _select_actor(state: Snapshot, id: int) -> void:
	state.selected_actor_id = id
	for actor: Snapshot.ActorSnapshot in state.actors:
		actor.human_controlled = actor.actor_id == id
	state.ai_actor_ids = state.ai_intent_actor_ids.duplicate()
	state.ai_actor_ids.erase(id)


func _snapshot_signature(state: Snapshot) -> String:
	var actors: Array[Dictionary] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		actors.append({"id": actor.actor_id, "team": actor.team_id, "role": actor.role, "human": actor.human_controlled})
	return var_to_str({
		"mode": state.mode, "actors": actors, "selected": state.selected_actor_id,
		"intent": state.ai_intent_actor_ids, "ai": state.ai_actor_ids,
		"score": state.score, "clock": state.seconds_remaining, "phase": state.phase,
		"tick": state.tick, "ball": state.ball_position,
		"exercise": state.training_exercise,
	})


func _view_signature() -> String:
	var focused: Control = root.gui_get_focus_owner()
	var result: Dictionary = {
		"open": _menu.is_open(), "summary": _label("StateSummary").text,
		"selector": (_button("ModeSelector") as Button).text, "dropdown": _control("ModeDropdown").visible,
		"error": _label("ErrorText").text, "error_visible": _label("ErrorText").visible,
		"focus": focused.get_instance_id() if focused != null else 0, "modes": _mode_requests.size(),
		"ai_requests": _ai_requests.size(), "closes": _close_requests,
		"guide_requests": _guide_requests.size(), "guide": _button("AimGuideToggle").button_pressed,
		"exercise": (_control("ExerciseSelector") as OptionButton).get_selected_id(), "exercise_requests": _exercise_requests.size(),
	}
	for name: String in ["Rival", "Teammates", "Keeper"]:
		result[name] = [_button(name + "Toggle").button_pressed, _button(name + "Toggle").disabled, _label(name + "Status").text]
	return var_to_str(result)


func _last_ai_is(ids: Array[int]) -> bool:
	return not _ai_requests.is_empty() and _ai_requests.back() == PackedInt32Array(ids)


func _key(code: Key, shift: bool = false, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.device = 0
	event.physical_keycode = code
	event.keycode = code
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = true
	_send_native_input(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	event.echo = false
	_send_native_input(event)


func _joy_button(button: JoyButton, device: int) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	_send_native_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	_send_native_input(event)


func _send_native_input(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _joy_axis(value: float, device: int, release: bool = true) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device
	event.axis = JOY_AXIS_LEFT_Y
	event.axis_value = value
	root.push_input(event)
	if release:
		event = event.duplicate() as InputEventJoypadMotion
		event.axis_value = 0.0
		root.push_input(event)


func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.device = 0
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.device = 0
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)


func _binding_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(var_to_str(event))
		result[action] = events
	return result


func _screen_rect(control: Control) -> Rect2:
	return root.get_final_transform() * control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _control(name: String) -> Control:
	return _menu.get_node("%" + name) as Control


func _button(name: String) -> BaseButton:
	return _control(name) as BaseButton


func _label(name: String) -> Label:
	return _control(name) as Label


func _focused(name: String) -> bool:
	return root.gui_get_focus_owner() == _control(name)


func _settle() -> void:
	await process_frame
	await process_frame


func _check(label: String, passed: bool) -> void:
	var identity: String = "%s [case: %s%s]" % [label, _check_scope, "; " + _case_context if not _case_context.is_empty() else ""]
	_checks.append({"name": identity, "passed": passed})
	print(("PASS " if passed else "FAIL ") + identity)


func _finish() -> void:
	_check("development suite reached completion", _suite_completed)
	_check("selection and latent intent cases reached completion", _intent_checks_completed)
	_check("guide and exercise control cases reached completion", _exercise_checks_completed)
	var failures: Array[String] = []
	for check: Dictionary in _checks:
		if not bool(check["passed"]):
			failures.append(String(check["name"]))
	print("FUTSAL_DEV_MENU_TESTS " + JSON.stringify({
		"ok": failures.is_empty(), "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "expected_validation_errors": 0, "failures": failures, "checks": _checks,
	}))
	quit(0 if failures.is_empty() else 1)
