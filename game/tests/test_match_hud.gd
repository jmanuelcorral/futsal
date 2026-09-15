extends SceneTree

const Rules = preload("res://match/simulation/match_rule_types.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Adapter = preload("res://match/presentation/input/match_input.gd")

const HudScript = preload("res://match/presentation/hud/match_hud.gd")
const HudScene: PackedScene = preload("res://match/presentation/hud/match_hud.tscn")
const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back",
	&"sprint", &"close_control", &"pass", &"shoot", &"pause",
]

var _hud: HudScript
var _checks: Array[Dictionary] = []
var _expected_validation_errors: int = 0
var _selection_errors: int = 0
var _restart_errors: int = 0
var _check_scope: String = "initialization"
var _case_context: String = ""
var _restart_checks_completed: bool = false
var _feedback_checks_completed: bool = false
var _charging_feedback_checks_completed: bool = false
var _selection_checks_completed: bool = false
var _suite_completed: bool = false
var _requests: Dictionary = {"pause": 0, "resume": 0, "restart": 0, "quit": 0, "development": 0}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_bindings: Dictionary = _binding_snapshot()
	_hud = HudScene.instantiate() as HudScript
	_check("native scene instantiates the production script", _hud != null)
	if _hud == null:
		_finish()
		return
	root.add_child(_hud)
	_hud.pause_requested.connect(func() -> void: _requests["pause"] += 1)
	_hud.resume_requested.connect(func() -> void: _requests["resume"] += 1)
	_hud.restart_requested.connect(func() -> void: _requests["restart"] += 1)
	_hud.quit_requested.connect(func() -> void: _requests["quit"] += 1)
	_hud.development_requested.connect(func() -> void: _requests["development"] += 1)
	await _settle()
	await _run_case(_test_initial_scene)
	await _run_case(_test_score_clock_charge)
	await _run_case(_test_teams_and_pre_ready)
	await _run_case(_test_possession_guide)
	await _run_case(_test_dribble_guide)
	await _run_case(_test_events)
	await _run_case(_test_pause_and_native_focus)
	await _run_case(_test_results)
	await _run_case(_test_mode_and_development)
	await _run_case(_test_selected_actor)
	await _run_case(_test_resizing)
	await _run_case(_test_restart_presentation)
	await _run_case(_test_corner_restart_layout)
	await _run_case(_test_restart_feedback_surfaces)
	await _run_case(_test_feedback_during_charge)
	_check("the original invalid-input diagnostics remain exactly sixteen",
		_expected_validation_errors - _selection_errors - _restart_errors == 16)
	_check("HUD never rewrites any match InputMap binding", _binding_snapshot() == original_bindings)
	for action: StringName in ACTIONS:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		_check("binding present: " + String(action), not events.is_empty())
		for event: InputEvent in events:
			_check("all-device binding: " + String(action) + "/" + event.get_class() + "/" + event.as_text(), event.device == -1)
	paused = false
	_hud.queue_free()
	await process_frame
	_suite_completed = true
	_finish()


func _run_case(test: Callable) -> void:
	_check_scope = String(test.get_method()).trim_prefix("_test_")
	_case_context = ""
	await test.call()
	_check_scope = "completion"
	_case_context = ""


func _test_initial_scene() -> void:
	_check("HUD processes while host tree is paused", _hud.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("score starts neutral", _label("Score").text == "0 – 0")
	_check("clock starts neutral", _label("Clock").text == "00:00")
	_check("pause overlay starts hidden", not _control("PauseOverlay").visible)
	_check("event starts hidden", not _control("EventPanel").visible)
	_check("zero charge does not obstruct play", not _control("ChargePanel").visible)
	_check("prototype is identified", _label("PrototypeBadge").text == "G1 · PROTOTIPO")
	_check("selection is not invented before a confirmed actor", _label("SelectedActor").text == "CONTROL · —\nSin selección")
	_check("normal HUD does not capture court input", (_hud.get_node("Frame") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for panel: String in ["Scoreboard", "EventPanel", "SelectionPanel", "HelpPanel", "ChargePanel"]:
		_check("noninteractive panel ignores mouse: " + panel, _control(panel).mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("pause shortcut is not in gameplay focus traversal", _button("PauseButton").focus_mode == Control.FOCUS_NONE)
	var focus_style: StyleBoxFlat = _button("ResumeButton").get_theme_stylebox("focus") as StyleBoxFlat
	_check("keyboard/controller focus has a non-colour outline cue", focus_style != null and focus_style.border_width_left >= 3)


func _test_score_clock_charge() -> void:
	_check("score update accepted", _hud.update_score(3, 2))
	_check("both supplied scores are rendered", _label("Score").text == "3 – 2")
	_rejected("negative score is rejected", _hud.update_score(-1, 4))
	_rejected("oversized score is rejected", _hud.update_score(3, HudScript.MAX_SCORE + 1))
	_check("invalid scores preserve both values", _label("Score").text == "3 – 2")
	_check("maximum supported scores accepted", _hud.update_score(999, 999))
	_check("maximum scores are not silently truncated", _label("Score").text == "999 – 999")
	_hud.update_score(3, 2)
	var clock_cases: Array[Dictionary] = [
		{"seconds": 0.0, "text": "00:00"},
		{"seconds": 0.01, "text": "00:01"},
		{"seconds": 59.0, "text": "00:59"},
		{"seconds": 59.01, "text": "01:00"},
		{"seconds": 60.0, "text": "01:00"},
		{"seconds": 119.99, "text": "02:00"},
		{"seconds": 180.0, "text": "03:00"},
		{"seconds": -42.0, "text": "00:00"},
		{"seconds": 5999.0, "text": "99:59"},
		{"seconds": 1.0e30, "text": "99:59"},
	]
	for clock_case: Dictionary in clock_cases:
		var seconds: float = float(clock_case["seconds"])
		_check("clock accepts finite seconds: " + str(seconds), _hud.update_clock(seconds))
		_check("clock format: " + str(seconds), _label("Clock").text == String(clock_case["text"]))
	for seconds: float in [NAN, INF, -INF]:
		_rejected("nonfinite clock is rejected: " + str(seconds), _hud.update_clock(seconds))
		_check("nonfinite clock preserves last valid display: " + str(seconds), _label("Clock").text == "99:59")
	_hud.update_clock(120.0)
	_check("charge accepted", _hud.set_shot_charge(0.42))
	_check("charge uses real ProgressBar", is_equal_approx((_control("ShotCharge") as ProgressBar).value, 0.42))
	_check("charge also has numeric feedback", _label("ChargeValue").text == "42 %")
	_check("positive charge is visible", _control("ChargePanel").visible)
	_hud.set_shot_charge(-0.5)
	_check("negative finite charge clamps to zero and hides", not _control("ChargePanel").visible and _label("ChargeValue").text == "0 %")
	_hud.set_shot_charge(10.0)
	_check("large finite charge clamps to full", is_equal_approx((_control("ShotCharge") as ProgressBar).value, 1.0))
	for charge: float in [NAN, INF, -INF]:
		_rejected("nonfinite charge is rejected: " + str(charge), _hud.set_shot_charge(charge))
		_check("invalid charge preserves visible data: " + str(charge), _label("ChargeValue").text == "100 %")


func _test_teams_and_pre_ready() -> void:
	_check("baseline home colour is navy", _hud.home_color.is_equal_approx(Color("#172f4d")))
	_check("baseline away colour is ivory", _hud.away_color.is_equal_approx(Color("#eee8d8")))
	_check("default dorsals are distinct", _label("HomeDorsal").text == "07" and _label("AwayDorsal").text == "11")
	_check("home shape also has a text cue", _label("HomeCue").text.contains("CÍRCULO"))
	_check("away shape also has a text cue", _label("AwayCue").text.contains("ROMBO"))
	var second: HudScript = HudScene.instantiate() as HudScript
	_check("score accepts data before ready", second.update_score(8, 4))
	_check("clock accepts data before ready", second.update_clock(61.0))
	_check("charge accepts data before ready", second.set_shot_charge(0.25))
	_check("event accepts data before ready", second.show_event("SAQUE · Local", 1.0))
	second.home_color = Color("#f5a044")
	second.away_color = Color("#23405f")
	second.home_dorsal = 12
	second.away_dorsal = 4
	second.set_has_possession(true)
	root.add_child(second)
	await _settle()
	_check("pre-ready score survives scene initialization", (second.get_node("%Score") as Label).text == "8 – 4")
	_check("pre-ready clock survives scene initialization", (second.get_node("%Clock") as Label).text == "01:01")
	_check("pre-ready charge survives scene initialization", (second.get_node("%ChargeValue") as Label).text == "25 %")
	_check("pre-ready event starts when ready", (second.get_node("%EventText") as Label).text == "SAQUE · Local")
	_check("pre-ready possession selects the contextual guide", (second.get_node("%PassHint") as Label).text == "Pase y controlar receptor")
	var second_home: StyleBoxFlat = (second.get_node("%HomeChip") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	var first_home: StyleBoxFlat = (_control("HomeChip") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	_check("home property changes native chip fill", second_home.bg_color.is_equal_approx(second.home_color))
	_check("away property changes native diamond fill", (second.get_node("%AwayFill") as Polygon2D).color.is_equal_approx(second.away_color))
	_check("dorsal properties render before ready", (second.get_node("%HomeDorsal") as Label).text == "12" and (second.get_node("%AwayDorsal") as Label).text == "04")
	_check("team style resources are instance-local", first_home != second_home and first_home.bg_color.is_equal_approx(_hud.home_color))
	_check("light kit gets dark dorsal text", (second.get_node("%HomeDorsal") as Label).get_theme_color("font_color") == Color.BLACK)
	_check("dark kit gets light dorsal text", (second.get_node("%AwayDorsal") as Label).get_theme_color("font_color") == Color.WHITE)
	second.home_color = Color("#23405f")
	_check("live colour changes reach the chip", second_home.bg_color.is_equal_approx(second.home_color))
	_check("matching colours still retain distinct shapes/dorsals",
		(second.get_node("%HomeCue") as Label).text.contains("CÍRCULO")
		and (second.get_node("%AwayCue") as Label).text.contains("ROMBO")
		and (second.get_node("%HomeDorsal") as Label).text != (second.get_node("%AwayDorsal") as Label).text)
	_expected_validation_errors += 1
	second.home_color = Color(NAN, 0.0, 0.0, 1.0)
	_check("nonfinite kit colour preserves prior colour", second.home_color.is_equal_approx(Color("#23405f")))
	_expected_validation_errors += 1
	second.away_dorsal = 100
	_check("invalid dorsal preserves prior number", second.away_dorsal == 4)
	second.free()
	var pending_pause: HudScript = HudScene.instantiate() as HudScript
	pending_pause.set_paused(true)
	root.add_child(pending_pause)
	await _settle()
	_check("pre-ready pause is rendered", (pending_pause.get_node("%PauseOverlay") as Control).visible)
	_check("pre-ready pause gets initial focus", root.gui_get_focus_owner() == pending_pause.get_node("%ResumeButton"))
	pending_pause.free()
	await _settle()


func _test_possession_guide() -> void:
	for name: String in ["MoveKeys", "PassKeys", "ShootKeys", "SprintKeys", "CloseControlKeys"]:
		_check("dual-device guide is visible: " + name, _label(name).is_visible_in_tree() and _label(name).text.contains("/"))
	_check("movement includes WASD arrows and left stick", _label("MoveKeys").text == "WASD / Flechas / Stick")
	_check("pass matches J and Xbox A", _label("PassKeys").text == "J / A")
	_check("shoot matches K and Xbox B", _label("ShootKeys").text == "K / B")
	_check("sprint matches Shift and RT", _label("SprintKeys").text == "Shift / RT")
	_check("close control matches Ctrl and LT", _label("CloseControlKeys").text == "Ctrl / LT")
	_hud.set_has_possession(true)
	_check("possession context is explicit", _label("ControlsContext").text.begins_with("CON BALÓN"))
	_check("possession maps pass to receiver control", _label("PassHint").text == "Pase y controlar receptor")
	_check("shot explains hold and release", _label("ShootHint").text == "Tiro: mantener / soltar")
	_hud.set_has_possession(false)
	_check("defensive context is explicit", _label("ControlsContext").text.begins_with("SIN BALÓN"))
	_check("off-ball J/A selects a teammate with direction", _label("PassHint").text == "Cambiar jugador · + dirección")
	_check("defensive B shows a steal attempt", _label("ShootHint").text == "Robo de pie")
	_check("defensive LT shows lateral containment", _label("CloseControlHint").text == "Contención lateral")
	_check("context changes never invent shot charge", _label("ChargeValue").text == "100 %")


func _test_dribble_guide() -> void:
	var guide: HudScript = HudScene.instantiate() as HudScript
	guide.set_mode(Setup.Mode.PREVIEW_5V5)
	guide.set_selected_actor(_selected_actor(0))
	guide.set_has_possession(true)
	guide.set_shot_charge(0.37)
	root.add_child(guide)
	await _settle()
	var keys: Label = guide.get_node("%DribbleKeys") as Label
	var hint: Label = guide.get_node("%DribbleHint") as Label
	_check("preview actor 0 pre-ready possession displays both dribble labels",
		keys.is_visible_in_tree() and hint.is_visible_in_tree())
	_check("live dribble labels identify keyboard L and controller X", keys.text == "L / X")
	_check("live dribble hint names cut and change of pace", hint.text == "Enganche / cambio de ritmo")
	guide.set_has_possession(false)
	_check("preview actor 0 ball loss hides both dribble labels", not keys.visible and not hint.visible)
	guide.set_has_possession(true)
	_check("preview actor 0 confirmed recovery restores both dribble labels", keys.visible and hint.visible)
	guide.set_selected_actor(_selected_actor(4))
	_check("preview focus 0 to 4 does not inherit a dribble permission", not keys.visible and not hint.visible)
	guide.set_has_possession(false)
	_check("preview actor 4 with pass in flight cannot claim a dribble", not keys.visible and not hint.visible)
	guide.set_has_possession(true)
	_check("preview actor 4 confirmed possession restores the live dribble hint", keys.visible and hint.visible)
	_check("dribble presentation never changes the supplied charge",
		(guide.get_node("%ChargeValue") as Label).text == "37 %")
	_check("dribble presentation preserves the original contextual pass and shot hints",
		(guide.get_node("%PassHint") as Label).text == "Pase y controlar receptor"
		and (guide.get_node("%ShootHint") as Label).text == "Tiro: mantener / soltar")
	guide.free()
	await _settle()


func _test_events() -> void:
	for message: String in ["GOL · Local", "FUERA · Saque de banda", "SAQUE · Visita", "FIN · Entrenamiento"]:
		_check("event accepted: " + message, _hud.show_event(message, 2.0))
		_check("real event label is updated: " + message, _label("EventText").text == message and _control("EventPanel").visible)
		_check("events do not award or reset scores: " + message, _label("Score").text == "3 – 2")
		_check("events do not advance or reset the clock: " + message, _label("Clock").text == "02:00")
	_rejected("zero event duration is rejected", _hud.show_event("INVALID", 0.0))
	_rejected("negative event duration is rejected", _hud.show_event("INVALID", -1.0))
	_rejected("NaN event duration is rejected", _hud.show_event("INVALID", NAN))
	_rejected("infinite event duration is rejected", _hud.show_event("INVALID", INF))
	_check("invalid event leaves previous message intact", _label("EventText").text == "FIN · Entrenamiento")
	_hud.show_event("AVISO", 100.0)
	_check("long duration is bounded", is_equal_approx((_hud.get_node("EventTimer") as Timer).wait_time, HudScript.MAX_EVENT_DURATION))
	_hud.show_event("   ")
	_check("empty event clears and stops its timer", not _control("EventPanel").visible and (_hud.get_node("EventTimer") as Timer).is_stopped())
	_hud.show_event("ANTERIOR", 0.05)
	_hud.show_event("ACTUAL", 0.3)
	await create_timer(0.10, true, false, true).timeout
	_check("replacement is not cleared by a stale timeout", _label("EventText").text == "ACTUAL")
	paused = true
	Engine.time_scale = 0.0
	_hud.show_event("AVISO EN PAUSA", 0.05)
	await create_timer(0.12, true, false, true).timeout
	_check("real timer expires while tree and game time are paused", not _control("EventPanel").visible and _label("EventText").text.is_empty())
	_check("UI timing never advances the supplied match clock", _label("Clock").text == "02:00")
	Engine.time_scale = 1.0
	paused = false


func _test_pause_and_native_focus() -> void:
	_key(KEY_ESCAPE)
	_check("keyboard pause emits exactly one intent", _requests["pause"] == 1)
	_check("pause intent does not open a modal or pause the tree", not _control("PauseOverlay").visible and not paused)
	_joy_button(JOY_BUTTON_START, 1)
	_check("controller Start emits pause intent on device 1", _requests["pause"] == 2)
	_button("PauseButton").pressed.emit()
	_check("native pause button emits the same intent", _requests["pause"] == 3)
	var host_focus: Button = Button.new()
	host_focus.text = "Host focus fixture"
	root.add_child(host_focus)
	host_focus.grab_focus()
	_hud.set_paused(true)
	await _settle()
	_check("host pause opens the modal", _control("PauseOverlay").visible)
	_check("set_paused does not mutate SceneTree", not paused)
	_check("initial modal focus is Continue", _focused("ResumeButton"))
	_key(KEY_DOWN)
	_check("native keyboard Down focuses Restart", _focused("RestartButton"))
	_key(KEY_TAB)
	_check("native Tab reaches Development", _focused("DevelopmentButton"))
	_key(KEY_TAB)
	_check("native Tab focuses Exit", _focused("QuitButton"))
	_hud.set_paused(true)
	_check("repeated paused snapshots preserve chosen focus", _focused("QuitButton"))
	_key(KEY_TAB, true)
	_check("native Shift-Tab reaches Development", _focused("DevelopmentButton"))
	_key(KEY_TAB, true)
	_check("native Shift-Tab focuses Restart", _focused("RestartButton"))
	_key(KEY_UP)
	_check("native keyboard Up focuses Continue", _focused("ResumeButton"))
	_key(KEY_UP)
	_check("focus wraps inside modal instead of reaching host UI", _focused("QuitButton"))
	_key(KEY_DOWN)
	_check("focus wraps back to Continue", _focused("ResumeButton"))
	paused = true
	_joy_button(JOY_BUTTON_DPAD_DOWN, 0)
	_check("native controller D-pad navigates during tree pause", _focused("RestartButton"))
	_joy_axis(JOY_AXIS_LEFT_Y, 1.0, 1)
	_check("native left stick reaches Development on device 1", _focused("DevelopmentButton"))
	_joy_button(JOY_BUTTON_A, 1)
	_check("Development emits an intent without hiding pause", _requests["development"] == 1 and _control("PauseOverlay").visible)
	_joy_axis(JOY_AXIS_LEFT_Y, 1.0, 1)
	_check("native left stick navigates on device 1", _focused("QuitButton"))
	_joy_button(JOY_BUTTON_A, 1)
	_check("controller A on Exit emits one quit intent", _requests["quit"] == 1)
	_check("quit intent leaves authoritative state untouched", paused and _control("PauseOverlay").visible)
	_key(KEY_UP)
	_check("Exit navigates back through Development", _focused("DevelopmentButton"))
	_key(KEY_UP)
	_key(KEY_ENTER)
	_check("keyboard Enter on Restart emits one restart intent", _requests["restart"] == 1)
	_joy_button(JOY_BUTTON_B, 0)
	_check("controller B requests resume, not a second match action", _requests["resume"] == 1)
	_key(KEY_ESCAPE)
	_check("Esc resumes once despite also matching ui_cancel", _requests["resume"] == 2)
	_joy_button(JOY_BUTTON_START, 1)
	_check("Start resumes once while paused", _requests["resume"] == 3)
	_key(KEY_ESCAPE, false, true)
	_check("echoed pause key does not emit another intent", _requests["resume"] == 3)
	_button("ResumeButton").grab_focus()
	_joy_button(JOY_BUTTON_A, 0)
	_check("controller A activates Continue during pause", _requests["resume"] == 4)
	_check("resume intents never unpause or close UI themselves", paused and _control("PauseOverlay").visible)
	_joy_axis(JOY_AXIS_LEFT_Y, 0.2, 1)
	_check("stick drift does not move modal focus", _focused("ResumeButton"))
	_joy_axis(JOY_AXIS_LEFT_Y, 0.8, 1, false)
	_check("stick threshold moves one item", _focused("RestartButton"))
	_joy_axis(JOY_AXIS_LEFT_Y, 0.9, 1, false)
	_check("held stick cannot race through the menu", _focused("RestartButton"))
	_joy_axis(JOY_AXIS_LEFT_Y, 0.0, 1)
	_joy_axis(JOY_AXIS_LEFT_Y, 0.8, 1)
	_check("neutral stick rearms the next step to Development", _focused("DevelopmentButton"))
	_joy_axis(JOY_AXIS_LEFT_Y, 0.8, 1)
	_check("neutral stick rearms the next step", _focused("QuitButton"))
	_hud.set_paused(false)
	await _settle()
	_check("host view change closes modal even when tree remains paused", not _control("PauseOverlay").visible and paused)
	_check("focus returns to the prior host control", root.gui_get_focus_owner() == host_focus)
	paused = false
	host_focus.free()


func _test_results() -> void:
	_check("host result is accepted", _hud.show_result(4, 2, "Fin de la sesión"))
	await _settle()
	_check("result displays supplied score", _label("Score").text == "4 – 2")
	_check("result displays supplied message", _label("ModalDetail").text == "Fin de la sesión\nLOCAL 4 – 2 VISITA")
	_check("result cannot offer Continue", not _button("ResumeButton").visible)
	_check("result starts focused on Restart", _focused("RestartButton"))
	_check("show_result does not pause the tree", not paused)
	var resume_before: int = int(_requests["resume"])
	_key(KEY_ESCAPE)
	_joy_button(JOY_BUTTON_B, 1)
	_joy_button(JOY_BUTTON_START, 0)
	_check("result cannot be resumed via cancel or pause shortcuts", _requests["resume"] == resume_before)
	var restart_before: int = int(_requests["restart"])
	_joy_button(JOY_BUTTON_A, 0)
	_check("result restart is a single host intent", _requests["restart"] == restart_before + 1)
	_check("restart intent does not reset the score", _label("Score").text == "4 – 2")
	_key(KEY_UP)
	_check("result focus loop excludes hidden Continue", _focused("QuitButton"))
	_rejected("invalid result score is rejected", _hud.show_result(1000, 0, "Invalid"))
	_rejected("empty result message is rejected", _hud.show_result(0, 0, " "))
	_check("invalid result is atomic", _label("Score").text == "4 – 2" and _label("ModalDetail").text.begins_with("Fin de la sesión"))
	_hud.set_paused(false)
	_check("unpause snapshot cannot dismiss terminal result", _control("PauseOverlay").visible and not _button("ResumeButton").visible)
	_hud.set_paused(true)
	_hud.clear_result()
	_check("clear_result respects the last host pause state", _control("PauseOverlay").visible and _button("ResumeButton").visible)
	_check("clear_result does not reset score", _label("Score").text == "4 – 2")
	_hud.set_paused(false)
	_check("explicit host reset can return to gameplay UI", not _control("PauseOverlay").visible)


func _test_mode_and_development() -> void:
	_hud.set_has_possession(true)
	_check("micro mode is accepted", _hud.set_mode(Setup.Mode.MICRO_1V1) == OK)
	_check("micro has an explicit regression label", _label("TrainingLabel").text == "1v1 de regresión")
	_check("micro explains passing and taking receiver control", _label("PassHint").text == "Pase y controlar receptor")
	_check("preview mode is accepted", _hud.set_mode(Setup.Mode.PREVIEW_5V5) == OK)
	_check("preview disclaims progression", _label("TrainingLabel").text == "5v5 experimental · Sin progresión/XP")
	_check("preview explains passing and taking receiver control", _label("PassHint").text == "Pase y controlar receptor")
	for invalid: int in [-1, 2, 99]:
		_check("unknown mode returns an explicit Error: " + str(invalid),
			_hud.call("set_mode", invalid) == ERR_INVALID_PARAMETER)
		_check("unknown mode preserves confirmed labels: " + str(invalid),
			_label("TrainingLabel").text == "5v5 experimental · Sin progresión/XP"
			and _label("PassHint").text == "Pase y controlar receptor")
	_hud.update_score(5, 4)
	_hud.update_clock(93.0)
	_hud.set_paused(true)
	_button("DevelopmentButton").grab_focus()
	var development_before: int = int(_requests["development"])
	_key(KEY_ENTER)
	_check("keyboard activates Development", _requests["development"] == development_before + 1)
	_check("Development does not itself change modal state", _control("PauseOverlay").visible)
	_hud.set_development_open(true)
	await _settle()
	_check("development suppresses the HUD modal", not _control("PauseOverlay").visible)
	_check("development disables the mouse pause shortcut", _button("PauseButton").disabled)
	_check("development does not pause the tree", not paused)
	var before: Dictionary = _requests.duplicate()
	for key: Key in [KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_UP, KEY_DOWN]:
		_key(key)
	for button: JoyButton in [JOY_BUTTON_START, JOY_BUTTON_B, JOY_BUTTON_A, JOY_BUTTON_DPAD_DOWN]:
		_joy_button(button, 1)
	for name: String in ["PauseButton", "ResumeButton", "RestartButton", "DevelopmentButton", "QuitButton"]:
		_button(name).pressed.emit()
	_check("suppressed HUD emits no keyboard controller or stale-button intent", _requests == before)
	_hud.set_paused(true)
	_hud.set_mode(Setup.Mode.MICRO_1V1)
	_check("new snapshots do not reopen the underlying modal", not _control("PauseOverlay").visible)
	_hud.set_development_open(false)
	await _settle()
	_check("closing development restores the stored pause", _control("PauseOverlay").visible and _button("ResumeButton").visible)
	_check("closing development restores the entry focus", _focused("DevelopmentButton"))
	_check("closing development does not request resume", _requests == before)
	_check("development did not reset score or clock", _label("Score").text == "5 – 4" and _label("Clock").text == "01:33")
	paused = true
	_hud.set_development_open(true)
	_hud.show_result(6, 4, "Resultado confirmado")
	_hud.set_paused(false)
	_check("result stays suppressed until development closes", not _control("PauseOverlay").visible)
	_hud.set_development_open(false)
	await _settle()
	_check("closing development can restore a terminal result", _control("PauseOverlay").visible and not _button("ResumeButton").visible)
	_check("terminal result still offers Development", _button("DevelopmentButton").is_visible_in_tree())
	_check("result data stays supplied by the host", _label("ModalDetail").text == "Resultado confirmado\nLOCAL 6 – 4 VISITA")
	_check("development close never unpauses the tree", paused)
	_key(KEY_ESCAPE)
	_check("restored result cannot accidentally resume", _requests == before)
	paused = false
	_hud.clear_result()
	_hud.set_paused(false)
	var pending: HudScript = HudScene.instantiate() as HudScript
	_check("mode can be supplied before ready", pending.set_mode(Setup.Mode.PREVIEW_5V5) == OK)
	pending.set_paused(true)
	pending.set_development_open(true)
	root.add_child(pending)
	await _settle()
	_check("pre-ready development suppresses initial pause", not (pending.get_node("%PauseOverlay") as Control).visible)
	_check("pre-ready mode reaches the native label", (pending.get_node("%TrainingLabel") as Label).text.begins_with("5v5 experimental"))
	pending.set_development_open(false)
	_check("pre-ready stored pause can be restored", (pending.get_node("%PauseOverlay") as Control).visible)
	pending.free()
	await _settle()


func _test_selected_actor() -> void:
	_hud.set_mode(Setup.Mode.PREVIEW_5V5)
	_hud.set_shot_charge(0.6)
	var identity: String = _team_identity_signature()
	var score: String = _label("Score").text
	var clock: String = _label("Clock").text
	for id: int in [0, 4, 2, 0]:
		_case_context = "from=%s to=%d" % [_label("SelectedActor").text.replace("\n", " "), id]
		var actor: Snapshot.ActorSnapshot = _selected_actor(id)
		_hud.set_has_possession(true)
		_check("confirmed selected actor accepted: " + str(id), _hud.set_selected_actor(actor) == OK)
		var role: String = "PORTERO" if id == 2 else "CAMPO"
		var text: String = "CONTROL · ID %d\n%s LOCAL" % [id, role]
		_check("selected identity and role are rendered: " + str(id), _label("SelectedActor").text == text)
		_check("handoff does not inherit the old actor's possession",
			not _label("ControlsContext").text.begins_with("CON BALÓN"))
		var owner: int = -1 if id == 4 else id
		_hud.set_has_possession(id == owner)
		_check("confirmed possession is rendered for the selected actor",
			_label("PassHint").text == ("Pase y controlar receptor" if owner == id else "Cambiar jugador · + dirección"))
		_check("in-flight handoff does not claim the receiver owns the ball",
			id != 4 or _label("ControlsContext").text.begins_with("SIN BALÓN"))
		_check("handoff preserves team colours crests and dorsals", _team_identity_signature() == identity)
		_check("handoff does not alter score clock or supplied charge",
			_label("Score").text == score and _label("Clock").text == clock and _label("ChargeValue").text == "60 %")
		actor.actor_id = 8
		actor.role = Snapshot.Role.KEEPER
		actor.human_controlled = false
		_check("HUD copies selected metadata rather than retaining the caller object", _label("SelectedActor").text == text)
	_case_context = ""
	_hud.set_has_possession(true)
	_hud.set_selected_actor(_selected_actor(0))
	_check("repeated selection confirmation preserves confirmed possession", _label("ControlsContext").text.begins_with("CON BALÓN"))
	var invalid: Array[Snapshot.ActorSnapshot] = [null]
	var away: Snapshot.ActorSnapshot = _selected_actor(1)
	away.team_id = Snapshot.Team.AWAY
	invalid.append(away)
	var not_human: Snapshot.ActorSnapshot = _selected_actor(4)
	not_human.human_controlled = false
	invalid.append(not_human)
	invalid.append(_selected_actor(-1))
	invalid.append(_selected_actor(10))
	var bad_role: Snapshot.ActorSnapshot = _selected_actor(0)
	bad_role.set("role", 99)
	invalid.append(bad_role)
	var before: String = _selection_signature()
	for actor: Snapshot.ActorSnapshot in invalid:
		_case_context = "null actor" if actor == null else "id=%d team=%d role=%d human=%s" % [
			actor.actor_id, actor.team_id, actor.role, actor.human_controlled]
		_selection_errors += 1
		_expected_validation_errors += 1
		_check("invalid selection returns ERR_INVALID_PARAMETER", _hud.set_selected_actor(actor) == ERR_INVALID_PARAMETER)
		_check("invalid selection leaves the entire presentation unchanged", _selection_signature() == before)
	_case_context = ""
	var requests: Dictionary = _requests.duplicate()
	_key(KEY_J)
	_joy_button(JOY_BUTTON_A, 1)
	_key(KEY_LEFT)
	_key(KEY_RIGHT)
	_check("gameplay J/A and direction remain host-owned", _selection_signature() == before and _requests == requests)
	_hud.set_mode(Setup.Mode.MICRO_1V1)
	_hud.set_selected_actor(_selected_actor(2))
	_hud.set_has_possession(false)
	_check("micro keeper can be selected without possession", _label("SelectedActor").text == "CONTROL · ID 2\nPORTERO LOCAL"
		and _label("PassHint").text == "Cambiar jugador · + dirección")
	_hud.set_has_possession(true)
	_check("controlled keeper can pass and control the receiver", _label("PassHint").text == "Pase y controlar receptor")
	_hud.set_mode(Setup.Mode.PREVIEW_5V5)
	_hud.set_selected_actor(_selected_actor(4))
	_hud.set_has_possession(false)
	_hud.set_paused(true)
	_hud.show_event("GOL · Pausa")
	_hud.show_event("FUERA · Reposición")
	_check("goal and out presentation do not reset confirmed selection",
		_label("SelectedActor").text == "CONTROL · ID 4\nCAMPO LOCAL")
	_hud.show_result(6, 4, "Final confirmado")
	_check("finished presentation retains the last selected actor",
		_label("SelectedActor").text == "CONTROL · ID 4\nCAMPO LOCAL")
	_hud.clear_result()
	_hud.set_paused(false)
	_hud.set_selected_actor(_selected_actor(0))
	_check("only confirmed reset data selects actor zero again",
		_label("SelectedActor").text == "CONTROL · ID 0\nCAMPO LOCAL")
	var pending: HudScript = HudScene.instantiate() as HudScript
	_check("selected actor can be supplied before ready", pending.set_selected_actor(_selected_actor(2)) == OK)
	pending.set_has_possession(false)
	root.add_child(pending)
	await _settle()
	_check("pre-ready keeper identity reaches the real scene", (pending.get_node("%SelectedActor") as Label).text == "CONTROL · ID 2\nPORTERO LOCAL")
	_check("pre-ready possession remains independently confirmed", (pending.get_node("%PassHint") as Label).text == "Cambiar jugador · + dirección")
	pending.free()
	await _settle()
	_selection_checks_completed = true


func _test_corner_restart_layout() -> void:
	var original_size: Vector2i = root.size
	var hud: HudScript = HudScene.instantiate() as HudScript
	var corner: Snapshot = _restart_fixture(Rules.RestartKind.CORNER, Snapshot.Team.HOME)
	_check("own corner layout can be confirmed before ready", hud.present_restart(corner) == OK)
	hud.set_restart_aim_hint(Adapter.FINE_AIM_HINT)
	root.add_child(hud)
	await _settle()
	var panel: Control = hud.get_node("%RestartPanel") as Control
	var help: Control = hud.get_node("%HelpPanel") as Control
	var feedback: Control = hud.get_node("%RestartFeedbackPanel") as Control
	var scoreboard: Control = hud.get_node("Frame/Scoreboard") as Control
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		_case_context = str(resolution)
		_check("own corner remains accepted", hud.present_restart(corner) == OK)
		root.size = resolution
		await _settle()
		var bounds: Rect2 = _screen_rect(panel)
		var view: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution))
		_check("corner instructions remain visible and inside the viewport",
			panel.is_visible_in_tree() and view.encloses(bounds))
		_check("corner instructions stay above the control legend with a gap",
			bounds.end.y <= _screen_rect(help).position.y - 8.0)
		_check("corner instructions do not overlap the scoreboard or fine-aim help",
			not bounds.intersects(_screen_rect(scoreboard)) and not bounds.intersects(_screen_rect(feedback)))
		_check("non-corner restart restores the original upper layout",
			hud.present_restart(_restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.HOME)) == OK
			and is_equal_approx(panel.position.y, 146.0))
		_check("corner text never permanently enlarges the authored panel offsets",
			is_equal_approx(panel.offset_bottom - panel.offset_top, 112.0))
		_check("opponent corner keeps the broadcast HUD layout",
			hud.present_restart(_restart_fixture(Rules.RestartKind.CORNER, Snapshot.Team.AWAY)) == OK
			and is_equal_approx(panel.position.y, 146.0))
		hud.present_restart(corner)
		var live: Snapshot = corner.copy()
		live.restart.stage = Rules.RestartStage.IN_PLAY
		live.phase = Snapshot.Phase.PLAYING
		live.human_control_context = Rules.ControlContext.LIVE
		live.selected_can_move = true
		_check("accepted corner hides the panel and restores its original layout",
			hud.present_restart(live) == OK and not panel.visible and is_equal_approx(panel.position.y, 146.0))
	hud.free()
	root.size = original_size
	await _settle()


func _test_restart_presentation() -> void:
	var hud: HudScript = HudScene.instantiate() as HudScript
	var initial: Snapshot = _restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.HOME)
	_check("confirmed restart can be supplied before ready", hud.present_restart(initial) == OK)
	root.add_child(hud)
	await _settle()
	var title: Label = hud.get_node("%RestartTitle") as Label
	var clock: Label = hud.get_node("%RestartClock") as Label
	var detail: Label = hud.get_node("%RestartDetail") as Label
	var fouls: Label = hud.get_node("%FoulTotals") as Label
	for kind: Rules.RestartKind in [Rules.RestartKind.KICK_IN, Rules.RestartKind.CORNER,
			Rules.RestartKind.GOAL_CLEARANCE, Rules.RestartKind.DIRECT_FREE_KICK, Rules.RestartKind.INDIRECT_FREE_KICK,
			Rules.RestartKind.PENALTY_6M, Rules.RestartKind.ACCUMULATED_FREE_KICK]:
		for team: Snapshot.Team in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
			var state: Snapshot = _restart_fixture(kind, team)
			_case_context = "kind=%d awarded_team=%d" % [kind, team]
			var original: String = _restart_snapshot_signature(state)
			_check("confirmed restart accepted", hud.present_restart(state) == OK)
			_check("awarded side and real taker are displayed", title.text.contains("LOCAL" if team == 0 else "VISITA")
				and title.text.contains("ID %d" % state.restart.taker_actor_id))
			_check("UI does not mutate restart clock roster or counters", original == _restart_snapshot_signature(state))
			_check("clock distinguishes penalty from timed restarts", clock.text.contains("sin cuenta de 4 s")
				if kind == Rules.RestartKind.PENALTY_6M else clock.text == "Listo · 4.0 s")
			_check("both confirmed foul counts are visible", fouls.text.contains("LOCAL 2") and fouls.text.contains("VISITA 5"))
			if team == Snapshot.Team.AWAY:
				_check("rival restart preserves defensive player-change hint",
					(hud.get_node("%PassHint") as Label).text == "Cambiar jugador · + dirección")
				_check("rival restart never advertises stealing a stationary ball",
					(hud.get_node("%ShootHint") as Label).text == "Sin robo en balón parado")
			else:
				_check("own restart direction is aim rather than locomotion",
					(hud.get_node("%MoveHint") as Label).text == "Apuntar (sin caminar)")
				if kind == Rules.RestartKind.GOAL_CLEARANCE:
					_check("goal clearance advertises a quick hand throw not a charged foot pass",
						detail.text.contains("manos") and (hud.get_node("%PassHint") as Label).text == "Saque con manos · pulsar")
				elif state.restart.requires_direct_shot or kind == Rules.RestartKind.PENALTY_6M:
					_check("shot-only restart never advertises quick passing",
						detail.text.contains("Tiro directo obligatorio") and (hud.get_node("%PassHint") as Label).text == "Pase no disponible")
				else:
					_check("legal quick pass has no mandatory charge",
						(hud.get_node("%PassHint") as Label).text == "Pase rápido · pulsar")
			state.restart.stage = Rules.RestartStage.PLACEMENT
			state.restart.ready_tick = -1
			state.restart.deadline_tick = -1
			state.human_control_context = Rules.ControlContext.DISABLED
			state.human_allowed_actions = []
			state.selected_can_move = false
			_check("placement is explicit and has no premature countdown", hud.present_restart(state) == OK
				and clock.text.begins_with("Preparación"))
	_case_context = "authoritative deadlines"
	var state: Snapshot = _restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.HOME)
	hud.present_restart(state)
	var frozen: String = clock.text
	await create_timer(0.05, true, false, true).timeout
	_check("UI wall time cannot advance the four-second rule", clock.text == frozen)
	state.tick += 120
	_check("only a new snapshot advances ready countdown", hud.present_restart(state) == OK and clock.text == "Listo · 2.0 s")
	state.tick = state.restart.deadline_tick - 1
	_check("last legal tick is not rounded down to expired", hud.present_restart(state) == OK and clock.text == "Listo · 0.1 s")
	state.phase = Snapshot.Phase.PAUSED
	state.human_control_context = Rules.ControlContext.DISABLED
	state.human_allowed_actions = []
	state.selected_can_move = false
	_check("confirmed pause preserves the remaining ready deadline", hud.present_restart(state) == OK and clock.text == "Listo · 0.1 s")
	paused = true
	await create_timer(0.03, true, false, true).timeout
	_check("paused UI does not invent extra restart time", clock.text == "Listo · 0.1 s")
	paused = false
	state = _restart_fixture(Rules.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.HOME)
	state.restart.has_spot_choice = true
	state.restart.spot_choice = Rules.SpotChoice.TEN_METRE
	state.human_allowed_actions = [Command.Action.SHOOT, Command.Action.CHOOSE_RESTART_SPOT]
	state.training_exercise = Setup.TrainingExercise.ACCUMULATED_FREE_KICK
	_check("sixth exercise shows legal spot alternative", hud.present_restart(state) == OK
		and detail.text.contains("punto de infracción") and (hud.get_node("%DribbleHint") as Label).text == "Elegir punto legal")
	_check("seeded exercise counters never claim a played foul history", fouls.text.contains("contador inicial predefinido"))
	state.restart.spot_choice = Rules.SpotChoice.OFFENCE_SPOT
	_check("confirmed alternate spot offers the ten-metre mark", hud.present_restart(state) == OK and detail.text.contains("marca de 10 m"))
	state.period_state = Rules.PeriodState.EXTENDED_KICK
	state.seconds_remaining = 0.0
	state.extended_restart_id = state.restart.id
	_check("zero-clock extension is explicitly the last launch", hud.present_restart(state) == OK and clock.text.begins_with("ÚLTIMO LANZAMIENTO"))
	state.restart.stage = Rules.RestartStage.IN_PLAY
	state.phase = Snapshot.Phase.PLAYING
	state.human_control_context = Rules.ControlContext.DISABLED
	state.human_allowed_actions = [Command.Action.NONE]
	_check("last-shot resolution cannot advertise another attack", hud.present_restart(state) == OK
		and (hud.get_node("%PassHint") as Label).text == "Sin nuevo pase ni cambio"
		and (hud.get_node("%ShootHint") as Label).text == "Sin segundo ataque")
	state = _restart_fixture(Rules.RestartKind.PENALTY_6M, Snapshot.Team.HOME)
	state.accumulated_fouls = Vector2i(2, 5)
	_check("penalty display does not invent an extra accumulated foul", hud.present_restart(state) == OK
		and fouls.text == "ACUM. LOCAL 2 · VISITA 5")
	hud.set_restart_aim_hint(Adapter.FINE_AIM_HINT)
	hud.show_restart_feedback("Este saque exige un tiro", state.restart.id, state.selected_actor_id)
	var before: String = _restart_ui_signature(hud)
	for invalid: String in ["null", "null_restart", "bad_kind", "bad_stage", "nan_spot", "negative_fouls", "wrong_taker_team",
			"field_goal_clearance", "penalty_deadline", "illegal_penalty_pass", "renewed_deadline",
			"own_taker_can_move", "live_context_during_ready", "unknown_exercise", "wrong_extension_id"]:
		var bad: Snapshot = _restart_fixture(Rules.RestartKind.PENALTY_6M, Snapshot.Team.HOME)
		match invalid:
			"null": bad = null
			"null_restart": bad.restart = null
			"bad_kind": bad.restart.set("kind", 99)
			"bad_stage": bad.restart.set("stage", 99)
			"nan_spot": bad.restart.spot.x = NAN
			"negative_fouls": bad.accumulated_fouls.x = -1
			"wrong_taker_team": bad.restart.taker_actor_id = 1
			"field_goal_clearance":
				bad = _restart_fixture(Rules.RestartKind.GOAL_CLEARANCE, Snapshot.Team.HOME)
				bad.actor(2).role = Snapshot.Role.FIELD
			"penalty_deadline": bad.restart.deadline_tick = bad.tick + 240
			"illegal_penalty_pass": bad.human_allowed_actions.append(Command.Action.PASS)
			"renewed_deadline":
				bad = _restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.HOME)
				bad.restart.deadline_tick += 1
			"own_taker_can_move": bad.selected_can_move = true
			"live_context_during_ready": bad.human_control_context = Rules.ControlContext.LIVE
			"unknown_exercise": bad.set("training_exercise", 99)
			"wrong_extension_id":
				bad.period_state = Rules.PeriodState.EXTENDED_KICK
				bad.seconds_remaining = 0.0
				bad.extended_restart_id = bad.restart.id + 1
		_case_context = "invalid restart " + invalid
		_restart_errors += 1
		_expected_validation_errors += 1
		_check("returns explicit invalid-parameter error", hud.present_restart(bad) == ERR_INVALID_PARAMETER)
		_check("rejection leaves every visible restart field intact", before == _restart_ui_signature(hud))
	_case_context = "restart layout"
	hud.clear_restart_feedback()
	hud.present_restart(_restart_fixture(Rules.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.HOME))
	await _settle()
	_check("restart panel leaves the court center clear", not _screen_rect(hud.get_node("%RestartPanel") as Control).has_point(Vector2(root.size) * 0.5))
	_check("restart information does not overlap selected identity", not _screen_rect(hud.get_node("%RestartPanel") as Control).intersects(
		_screen_rect(hud.get_node("%SelectionPanel") as Control)))
	state = _restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.HOME)
	state.restart.stage = Rules.RestartStage.IN_PLAY
	state.phase = Snapshot.Phase.PLAYING
	state.human_control_context = Rules.ControlContext.LIVE
	state.human_allowed_actions = [Command.Action.PASS, Command.Action.SHOOT, Command.Action.DRIBBLE]
	state.selected_can_move = true
	hud.set_selected_actor(state.actor(0))
	hud.set_has_possession(true)
	_check("accepted restart snapshot removes the preparation panel", hud.present_restart(state) == OK
		and not (hud.get_node("%RestartPanel") as Control).visible)
	_check("live confirmed possession restores pass charge and dribble instructions",
		(hud.get_node("%PassHint") as Label).text == "Pase y controlar receptor"
		and (hud.get_node("%DribbleKeys") as Label).visible)
	state.restart.kind = Rules.RestartKind.NONE
	state.restart.stage = Rules.RestartStage.NONE
	state.accumulated_fouls = Vector2i.ZERO
	_check("confirmed new session clears restart and both foul counters", hud.present_restart(state) == OK
		and not (hud.get_node("%RestartPanel") as Control).visible and fouls.text == "ACUM. LOCAL 0 · VISITA 0")
	state.selected_actor_id = 2
	for actor: Snapshot.ActorSnapshot in state.actors:
		actor.human_controlled = actor.actor_id == 2
	state.actor(2).ball_in_hands = true
	state.ball_owner_id = 2
	state.human_allowed_actions = [Command.Action.KEEPER_THROW]
	hud.set_selected_actor(state.actor(2))
	hud.set_has_possession(true)
	_check("live keeper hands use the confirmed quick throw action", hud.present_restart(state) == OK
		and (hud.get_node("%PassHint") as Label).text == "Lanzar con manos · pulsar"
		and (hud.get_node("%ShootHint") as Label).text == "Sin patada con balón en manos"
		and not (hud.get_node("%DribbleKeys") as Label).visible)
	hud.free()
	await _settle()
	_restart_checks_completed = true


func _test_restart_feedback_surfaces() -> void:
	var hud: HudScript = HudScene.instantiate() as HudScript
	var state: Snapshot = _restart_fixture(Rules.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.HOME)
	state.training_exercise = Setup.TrainingExercise.ACCUMULATED_FREE_KICK
	state.restart.has_spot_choice = true
	state.restart.spot_choice = Rules.SpotChoice.TEN_METRE
	state.human_allowed_actions = [Command.Action.SHOOT, Command.Action.CHOOSE_RESTART_SPOT]
	hud.set_restart_aim_hint(Adapter.FINE_AIM_HINT)
	_check("confirmed feedback fixture is accepted before ready", hud.present_restart(state) == OK
		and hud.set_selected_actor(state.actor(state.selected_actor_id)) == OK)
	root.add_child(hud)
	await _settle()
	var panel: Control = hud.get_node("%RestartFeedbackPanel") as Control
	var hint: Label = hud.get_node("%RestartAimHint") as Label
	var feedback: Label = hud.get_node("%RestartFeedback") as Label
	var timer: Timer = hud.get_node("RestartFeedbackTimer") as Timer
	_check("pre-ready configuration reaches the real own-READY hint surface", panel.is_visible_in_tree()
		and hint.is_visible_in_tree() and hint.text == Adapter.FINE_AIM_HINT and not feedback.visible)
	var source: String = _restart_snapshot_signature(state)
	var title: String = (hud.get_node("%RestartTitle") as Label).text
	var clock: String = (hud.get_node("%RestartClock") as Label).text
	_check("contextual feedback API accepts the confirmed restart and actor",
		hud.show_restart_feedback("Apunta hacia la portería rival", state.restart.id, state.selected_actor_id) == OK)
	await _settle()
	_check("hint and rejection are both visible without replacing the restart facts",
		hint.is_visible_in_tree() and feedback.is_visible_in_tree() and feedback.text == "Apunta hacia la portería rival"
		and (hud.get_node("%RestartTitle") as Label).text == title
		and (hud.get_node("%RestartClock") as Label).text == clock)
	var before: String = _restart_ui_signature(hud)
	var remaining: float = timer.time_left
	for context: Vector2i in [Vector2i(-1, state.selected_actor_id), Vector2i(state.restart.id, -1), Vector2i(state.restart.id, 10)]:
		_check("invalid feedback context preserves data and timer: restart=%d actor=%d" % [context.x, context.y],
			hud.show_restart_feedback("No aplicar", context.x, context.y) == ERR_INVALID_PARAMETER
			and before == _restart_ui_signature(hud) and timer.time_left == remaining)
	_check("refreshing the same authoritative snapshot never renews a transient notice",
		hud.present_restart(state) == OK and before == _restart_ui_signature(hud) and timer.time_left == remaining)
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		var bounds: Rect2 = _screen_rect(panel)
		_check("feedback surface fits without hiding text: " + str(resolution),
			Rect2(Vector2.ZERO, Vector2(resolution)).encloses(bounds)
			and hint.get_line_count() <= hint.max_lines_visible and feedback.get_line_count() <= feedback.max_lines_visible
			and hint.get_visible_line_count() == hint.get_line_count() and feedback.get_visible_line_count() == feedback.get_line_count()
			and bounds.encloses(_screen_rect(hint)) and bounds.encloses(_screen_rect(feedback)))
		for name: String in ["RestartPanel", "SelectionPanel", "HelpPanel", "ChargePanel"]:
			var other: Control = hud.get_node("%" + name) as Control
			_check("feedback avoids " + name + " at " + str(resolution),
				not bounds.intersects(_screen_rect(other)))
			if bounds.intersects(_screen_rect(other)):
				print("LAYOUT feedback=", bounds, " minimum=", panel.get_combined_minimum_size(),
					" other=", name, " bounds=", _screen_rect(other), " minimum=", other.get_combined_minimum_size())
				for path: String in ["%SelectedActor", "%FoulTotals", "%RestartAimHint", "%RestartFeedback", "Frame/ChargePanel/Rows/Hint"]:
					var text: Label = hud.get_node(path) as Label
					print("LAYOUT label=", text.name, " size=", text.size, " minimum=", text.get_combined_minimum_size(),
						" lines=", text.get_line_count(), " visible_lines=", text.get_visible_line_count())
		_check("feedback leaves court center clear: " + str(resolution), not bounds.has_point(Vector2(resolution) * 0.5))
	if not timer.is_stopped():
		await timer.timeout
	await _settle()
	_check("only the transient rejection expires", not feedback.visible and feedback.text.is_empty()
		and hint.is_visible_in_tree() and panel.is_visible_in_tree())
	_check("UI hint and feedback timers cannot change the four-second snapshot", source == _restart_snapshot_signature(state)
		and (hud.get_node("%RestartClock") as Label).text == clock)
	hud.show_restart_feedback("Aviso antes de pausa", state.restart.id, state.selected_actor_id)
	hud.set_paused(true)
	_check("pause hides the surface and discards transient feedback", not panel.is_visible_in_tree()
		and not hint.is_visible_in_tree() and feedback.text.is_empty() and timer.is_stopped())
	_check("presentation pause does not claim authority over SceneTree", not paused)
	paused = true
	await create_timer(0.03, true, false, true).timeout
	hud.set_paused(false)
	_check("presentation resume also leaves global pause with its host", paused)
	paused = false
	_check("resume restores persistent help without replaying the rejection", hint.is_visible_in_tree()
		and not feedback.visible and feedback.text.is_empty())
	hud.show_restart_feedback("Aviso antes de Desarrollo", state.restart.id, state.selected_actor_id)
	hud.set_development_open(true)
	_check("development suppresses the contextual surface", not panel.is_visible_in_tree() and feedback.text.is_empty())
	hud.set_development_open(false)
	_check("closing development can restore the still-confirmed help", hint.is_visible_in_tree() and not feedback.visible)
	hud.show_restart_feedback("Aviso de la reanudación anterior", state.restart.id, state.selected_actor_id)
	state.restart.id += 1
	hud.present_restart(state)
	_check("a different confirmed restart cannot inherit rejection text", hint.is_visible_in_tree() and feedback.text.is_empty())
	hud.show_restart_feedback("Aviso antes de reiniciar sesión", state.restart.id, state.selected_actor_id)
	hud.clear_restart_feedback()
	_check("host reset explicitly clears even if restart IDs could be reused", feedback.text.is_empty() and timer.is_stopped())
	hud.show_restart_feedback("Aviso antes de cambiar modo", state.restart.id, state.selected_actor_id)
	_check("confirmed mode change discards an old-context rejection",
		hud.set_mode(Setup.Mode.PREVIEW_5V5) == OK and feedback.text.is_empty() and timer.is_stopped())
	hud.set_mode(state.mode)
	hud.show_restart_feedback("Aviso antes de resultado", state.restart.id, state.selected_actor_id)
	_check("result overlay clears the notice and hides persistent help",
		hud.show_result(2, 1) and not panel.is_visible_in_tree() and feedback.text.is_empty() and timer.is_stopped())
	hud.clear_result()
	_check("dismissing a result cannot replay discarded text", hint.is_visible_in_tree() and feedback.text.is_empty())
	state.restart.stage = Rules.RestartStage.PLACEMENT
	state.restart.ready_tick = -1
	state.restart.deadline_tick = -1
	state.human_control_context = Rules.ControlContext.DISABLED
	state.human_allowed_actions = []
	_check("placement does not prematurely advertise READY fine aiming",
		hud.present_restart(state) == OK and not hint.is_visible_in_tree() and not panel.visible)
	state = _restart_fixture(Rules.RestartKind.KICK_IN, Snapshot.Team.AWAY)
	hud.present_restart(state)
	_check("rival READY never displays own fine-aim instructions", not hint.is_visible_in_tree() and not panel.visible)
	hud.show_restart_feedback("Defiende sin entrar al balón", state.restart.id, state.selected_actor_id)
	_check("rival feedback can be visible without revealing own-aim help", panel.is_visible_in_tree()
		and feedback.is_visible_in_tree() and not hint.is_visible_in_tree())
	state.selected_actor_id = 2
	for actor: Snapshot.ActorSnapshot in state.actors:
		actor.human_controlled = actor.actor_id == state.selected_actor_id
	_check("confirmed defender focus change clears the old actor's rejection",
		hud.set_selected_actor(state.actor(2)) == OK and feedback.text.is_empty() and timer.is_stopped()
		and hud.present_restart(state) == OK and not panel.visible)
	_check("feedback from a new snapshot can await its matching HUD refresh",
		hud.show_restart_feedback("Aviso del nuevo saque", state.restart.id + 1, state.selected_actor_id) == OK
		and not panel.visible)
	state.restart.id += 1
	_check("only its matching confirmed restart reveals the queued feedback",
		hud.present_restart(state) == OK and feedback.is_visible_in_tree() and feedback.text == "Aviso del nuevo saque"
		and not hint.is_visible_in_tree())
	state.restart.stage = Rules.RestartStage.IN_PLAY
	state.phase = Snapshot.Phase.PLAYING
	state.human_control_context = Rules.ControlContext.LIVE
	state.selected_can_move = true
	hud.present_restart(state)
	_check("accepted restart clears every stopped-play feedback element", not panel.visible and feedback.text.is_empty())
	hud.show_event("GOL · Local", 2.0)
	_check("normal show_event keeps its original independent goal surface",
		(hud.get_node("%EventPanel") as Control).is_visible_in_tree()
		and (hud.get_node("%EventText") as Label).text == "GOL · Local" and not panel.visible)
	hud.free()
	await _settle()
	_feedback_checks_completed = true


func _test_feedback_during_charge() -> void:
	var hud: HudScript = HudScene.instantiate() as HudScript
	var state: Snapshot = _restart_fixture(Rules.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.HOME)
	state.training_exercise = Setup.TrainingExercise.ACCUMULATED_FREE_KICK
	state.restart.has_spot_choice = true
	state.restart.spot_choice = Rules.SpotChoice.TEN_METRE
	state.human_allowed_actions = [Command.Action.SHOOT, Command.Action.CHOOSE_RESTART_SPOT]
	var message: String = "Regate no disponible en este contexto"
	hud.set_restart_aim_hint(Adapter.FINE_AIM_HINT)
	hud.set_selected_actor(state.actor(state.selected_actor_id))
	hud.present_restart(state)
	hud.set_shot_charge(0.65)
	hud.show_restart_feedback(message, state.restart.id, state.selected_actor_id)
	root.add_child(hud)
	var panel: Control = hud.get_node("%RestartFeedbackPanel") as Control
	var charge: Control = hud.get_node("%ChargePanel") as Control
	var charge_hint: Label = hud.get_node("Frame/ChargePanel/Rows/Hint") as Label
	var deadline: Label = hud.get_node("%RestartClock") as Label
	var feedback: Label = hud.get_node("%RestartFeedback") as Label
	for resolution: Vector2i in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await _settle()
		var view: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution))
		var bounds: Rect2 = _screen_rect(panel)
		_check(str(resolution) + " actual charge and rejection panels are visible inside the viewport",
			panel.is_visible_in_tree() and charge.is_visible_in_tree()
			and view.encloses(bounds) and view.encloses(_screen_rect(charge)))
		for name: String in ["RestartPanel", "SelectionPanel", "HelpPanel", "ChargePanel"]:
			_check(str(resolution) + " charging feedback does not obscure " + name,
				not bounds.intersects(_screen_rect(hud.get_node("%" + name) as Control)))
		_check(str(resolution) + " charge instructions are bounded without clipping their real text",
			charge_hint.is_visible_in_tree() and charge_hint.get_line_count() <= charge_hint.max_lines_visible
			and charge_hint.get_visible_line_count() == charge_hint.get_line_count()
			and _screen_rect(charge).encloses(_screen_rect(charge_hint)))
		_check(str(resolution) + " the full real rejection remains legible while charging",
			feedback.is_visible_in_tree() and feedback.text == message
			and feedback.get_visible_line_count() == feedback.get_line_count())
		var before_clock: String = deadline.text
		var before_deadline: int = state.restart.deadline_tick
		state.tick += 6
		_check(str(resolution) + " only presenting the host's newer tick advances the visible deadline",
			deadline.is_visible_in_tree() and deadline.text == before_clock
			and hud.present_restart(state) == OK and deadline.text != before_clock
			and deadline.text == "Listo · %.1f s" % (float(before_deadline - state.tick) / 60.0)
			and state.restart.deadline_tick == before_deadline and feedback.is_visible_in_tree() and not paused)
	hud.free()
	await _settle()
	_charging_feedback_checks_completed = true


func _restart_fixture(kind: Rules.RestartKind, team: Snapshot.Team) -> Snapshot:
	var state: Snapshot = Snapshot.new()
	state.mode = Setup.Mode.MICRO_1V1
	state.phase = Snapshot.Phase.RESTART_PAUSE
	state.resume_phase = Snapshot.Phase.RESTART_PAUSE
	state.tick = 100
	state.seconds_remaining = 70.0
	state.accumulated_fouls = Vector2i(2, 5)
	state.restart = Rules.RestartState.new()
	state.restart.id = 7
	state.restart.kind = kind
	state.restart.stage = Rules.RestartStage.READY
	state.restart.awarded_team_id = team
	state.restart.taker_actor_id = (2 if team == Snapshot.Team.HOME else 3) if kind == Rules.RestartKind.GOAL_CLEARANCE else team
	state.restart.ready_tick = state.tick
	state.restart.deadline_tick = -1 if kind == Rules.RestartKind.PENALTY_6M else state.tick + 240
	state.restart.requires_direct_shot = kind == Rules.RestartKind.ACCUMULATED_FREE_KICK
	state.selected_actor_id = state.restart.taker_actor_id if team == Snapshot.Team.HOME else 0
	state.human_control_context = Rules.ControlContext.RESTART_AIM if team == Snapshot.Team.HOME else Rules.ControlContext.RESTART_DEFEND
	state.selected_can_move = team == Snapshot.Team.AWAY
	for id: int in range(4):
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = id % 2
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.human_controlled = id == state.selected_actor_id
		state.actors.append(actor)
	if team == Snapshot.Team.AWAY:
		state.human_allowed_actions = [Command.Action.SWITCH_TEAMMATE]
	elif kind == Rules.RestartKind.GOAL_CLEARANCE:
		state.human_allowed_actions = [Command.Action.KEEPER_THROW]
	elif state.restart.requires_direct_shot or kind == Rules.RestartKind.PENALTY_6M:
		state.human_allowed_actions = [Command.Action.SHOOT]
	else:
		state.human_allowed_actions = [Command.Action.PASS, Command.Action.SHOOT]
	return state


func _restart_snapshot_signature(state: Snapshot) -> String:
	return var_to_str([state.tick, state.phase, state.seconds_remaining, state.accumulated_fouls,
		state.selected_actor_id, state.human_allowed_actions, state.restart.id, state.restart.kind,
		state.restart.stage, state.restart.spot, state.restart.ready_tick, state.restart.deadline_tick])


func _restart_ui_signature(hud: HudScript) -> String:
	var values: Array = []
	for name: String in ["RestartTitle", "RestartClock", "RestartDetail", "FoulTotals", "ControlsContext", "MoveHint", "PassHint", "ShootHint", "DribbleHint", "RestartAimHint", "RestartFeedback"]:
		var label: Label = hud.get_node("%" + name) as Label
		values.append([label.text, label.visible])
	values.append((hud.get_node("%RestartPanel") as Control).visible)
	values.append((hud.get_node("%RestartFeedbackPanel") as Control).visible)
	return var_to_str(values)


func _selected_actor(id: int) -> Snapshot.ActorSnapshot:
	var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	actor.actor_id = id
	actor.team_id = Snapshot.Team.HOME
	actor.role = Snapshot.Role.KEEPER if id == 2 else Snapshot.Role.FIELD
	actor.human_controlled = true
	return actor


func _team_identity_signature() -> String:
	return var_to_str([
		_hud.home_color, _hud.away_color, _hud.home_dorsal, _hud.away_dorsal,
		_label("HomeDorsal").text, _label("AwayDorsal").text, _label("HomeCue").text, _label("AwayCue").text,
		(_control("HomeChip") as Panel).get_theme_stylebox("panel").get_instance_id(),
		(_hud.get_node("%AwayFill") as Polygon2D).color,
	])


func _selection_signature() -> String:
	return var_to_str([
		_label("SelectedActor").text, _label("ControlsContext").text,
		_label("PassHint").text, _label("ShootHint").text, _label("CloseControlHint").text,
		_label("DribbleKeys").visible, _label("DribbleHint").visible, _label("DribbleHint").text,
		_label("Score").text, _label("Clock").text, _label("ChargeValue").text,
		_team_identity_signature(), _requests,
	])


func _test_resizing() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for resolution: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = resolution
		_hud.set_has_possession(true)
		_hud.update_score(999, 999)
		_hud.set_shot_charge(1.0)
		_hud.show_event("FUERA · Saque de banda para el equipo local", 10.0)
		await _settle()
		var view_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution))
		var center: Vector2 = Vector2(resolution) * 0.5
		for name: String in ["Scoreboard", "EventPanel", "SelectionPanel", "HelpPanel", "ChargePanel", "PauseButton"]:
			var bounds: Rect2 = _screen_rect(_control(name))
			_check(str(resolution) + " contains " + name, view_rect.encloses(bounds))
			_check(str(resolution) + " court center clear of " + name, not bounds.has_point(center))
		_check(str(resolution) + " scoreboard and pause do not overlap",
			not _screen_rect(_control("Scoreboard")).intersects(_screen_rect(_control("PauseButton"))))
		_check(str(resolution) + " lower corner panels do not overlap",
			not _screen_rect(_control("HelpPanel")).intersects(_screen_rect(_control("ChargePanel"))))
		_check(str(resolution) + " selected identity does not cover scoreboard",
			not _screen_rect(_control("SelectionPanel")).intersects(_screen_rect(_control("Scoreboard"))))
		_check(str(resolution) + " selected identity does not cover pause shortcut",
			not _screen_rect(_control("SelectionPanel")).intersects(_screen_rect(_control("PauseButton"))))
		var stretch: Vector2 = root.get_stretch_transform().get_scale()
		var frame_scale: Vector2 = (_hud.get_node("Frame") as Control).scale
		_check(str(resolution) + " physical control text stays at least 20 px",
			float(_label("ShootHint").get_theme_font_size("font_size")) * stretch.y * frame_scale.y >= 19.99)
		for name: String in ["Score", "HomeCue", "AwayCue", "MoveKeys", "PassHint", "ShootHint", "DribbleKeys", "DribbleHint", "CloseControlHint", "SelectedActor"]:
			var label: Label = _label(name)
			_check(str(resolution) + " label fits: " + name,
				label.size.x + 0.01 >= label.get_combined_minimum_size().x)
		_hud.set_has_possession(false)
		await _settle()
		_check(str(resolution) + " directional switch hint fits without blocking court center",
			_label("PassHint").size.x >= _label("PassHint").get_combined_minimum_size().x
			and not _screen_rect(_control("HelpPanel")).has_point(center))
		_hud.show_event("AVISO ".repeat(120), 10.0)
		await _settle()
		_check(str(resolution) + " long event remains in its top band", _screen_rect(_control("EventPanel")).end.y <= 240.0)
		_hud.set_paused(true)
		await _settle()
		_check(str(resolution) + " pause panel fits the window", view_rect.encloses(_screen_rect(_control("ModalPanel"))))
		_check(str(resolution) + " pause dim covers entire viewport",
			_screen_rect(_control("PauseOverlay")).is_equal_approx(view_rect))
		_hud.show_result(999, 999, "Fin de entrenamiento ".repeat(60))
		await _settle()
		_check(str(resolution) + " long result stays within viewport", view_rect.encloses(_screen_rect(_control("ModalPanel"))))
		_hud.clear_result()
		_hud.set_paused(false)
		_hud.set_mode(Setup.Mode.PREVIEW_5V5)
		await _settle()
		_check(str(resolution) + " preview header fits the window", view_rect.encloses(_screen_rect(_control("Scoreboard"))))
		_check(str(resolution) + " preview header does not overlap pause",
			not _screen_rect(_control("Scoreboard")).intersects(_screen_rect(_control("PauseButton"))))
		_check(str(resolution) + " preview label is not truncated",
			_label("TrainingLabel").size.x + 0.01 >= _label("TrainingLabel").get_combined_minimum_size().x)
		_hud.set_mode(Setup.Mode.MICRO_1V1)


func _key(code: Key, shift: bool = false, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.device = 0
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.echo = echo
	event.pressed = true
	root.push_input(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	event.echo = false
	root.push_input(event)


func _joy_button(button: JoyButton, device: int) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	root.push_input(event)


func _joy_axis(axis: JoyAxis, value: float, device: int, release: bool = true) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	root.push_input(event)
	if release:
		event = event.duplicate() as InputEventJoypadMotion
		event.axis_value = 0.0
		root.push_input(event)


func _binding_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var serialized: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			serialized.append(var_to_str(event))
		snapshot[action] = serialized
	return snapshot


func _screen_rect(control: Control) -> Rect2:
	var transform: Transform2D = root.get_final_transform() * control.get_global_transform_with_canvas()
	return transform * Rect2(Vector2.ZERO, control.size)


func _control(name: String) -> Control:
	return _hud.get_node("%" + name) as Control


func _label(name: String) -> Label:
	return _control(name) as Label


func _button(name: String) -> Button:
	return _control(name) as Button


func _focused(name: String) -> bool:
	return root.gui_get_focus_owner() == _button(name)


func _settle() -> void:
	await process_frame
	await process_frame


func _rejected(label: String, accepted: bool) -> void:
	_expected_validation_errors += 1
	_check(label, not accepted)


func _check(label: String, passed: bool) -> void:
	var identity: String = "%s [case: %s%s]" % [label, _check_scope, "; " + _case_context if not _case_context.is_empty() else ""]
	_checks.append({"name": identity, "passed": passed})
	print(("PASS " if passed else "FAIL ") + identity)


func _finish() -> void:
	_check("HUD suite reached completion", _suite_completed)
	_check("selected actor scenarios reached completion", _selection_checks_completed)
	_check("restart presentation scenarios reached completion", _restart_checks_completed)
	_check("restart feedback surface scenarios reached completion", _feedback_checks_completed)
	_check("charging feedback scenarios reached completion", _charging_feedback_checks_completed)
	var failures: Array[String] = []
	for check: Dictionary in _checks:
		if not bool(check["passed"]):
			failures.append(String(check["name"]))
	print("FUTSAL_HUD_TESTS " + JSON.stringify({
		"ok": failures.is_empty(),
		"passed": _checks.size() - failures.size(),
		"total": _checks.size(),
		"expected_validation_errors": _expected_validation_errors,
		"new_expected_error_counts": {HudScript.SELECTION_ERROR: _selection_errors, HudScript.RESTART_ERROR: _restart_errors},
		"failures": failures, "checks": _checks,
	}))
	quit(0 if failures.is_empty() else 1)
