class_name MatchDevMenu
extends CanvasLayer
## Menú técnico efímero: present() recibe confirmaciones; las señales solicitan cambios.
## El selector es un borrador para «Aplicar modo y reiniciar», no el modo confirmado.
## El anfitrión pausa la autoridad, coordina el HUD y atiende close_requested().
## show_error("") borra un rechazo; present() no lo borra durante actualizaciones continuas.

const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const MIN_UI_SIZE: Vector2 = Vector2(960.0, 540.0)
const EXERCISE_LABELS: Dictionary[int, String] = {
	Setup.TrainingExercise.FREE_PLAY: "Juego libre",
	Setup.TrainingExercise.KICK_IN: "Saque de banda",
	Setup.TrainingExercise.CORNER_POS_X_NEG_Z: "Córner +X / −Z",
	Setup.TrainingExercise.CORNER_POS_X_POS_Z: "Córner +X / +Z",
	Setup.TrainingExercise.CORNER_NEG_X_NEG_Z: "Córner −X / −Z (espejo)",
	Setup.TrainingExercise.CORNER_NEG_X_POS_Z: "Córner −X / +Z (espejo)",
	Setup.TrainingExercise.GOAL_CLEARANCE: "Saque de meta",
	Setup.TrainingExercise.DRIBBLE_CUT: "Regate · enganche",
	Setup.TrainingExercise.DRIBBLE_PACE_CHANGE: "Regate · cambio de ritmo",
	Setup.TrainingExercise.DIRECT_FREE_KICK: "Libre directo",
	Setup.TrainingExercise.PENALTY_6M: "Penalti de 6 m",
	Setup.TrainingExercise.ACCUMULATED_FREE_KICK: "Sexta acumulada",
}

signal mode_requested(mode: Setup.Mode)
## Intención completa de IA, incluido el seleccionado; no es la lista efectiva.
signal ai_actor_ids_requested(ids: Array[int])
signal close_requested()
signal aim_guide_requested(enabled: bool)
signal exercise_requested(exercise: Setup.TrainingExercise)

var _open: bool = false
var _has_state: bool = false
var _mode: Setup.Mode = Setup.Mode.MICRO_1V1
var _pending_mode: Setup.Mode = Setup.Mode.MICRO_1V1
var _exercise: Setup.TrainingExercise = Setup.TrainingExercise.FREE_PLAY
var _pending_exercise: Setup.TrainingExercise = Setup.TrainingExercise.FREE_PLAY
var _aim_guide_confirmed: bool = false
var _aim_guide_enabled: bool = false
var _actor_count: int = 0
var _selected_actor_id: int = -1
var _selected_role: Snapshot.Role = Snapshot.Role.FIELD
var _ai_intent_actor_ids: Array[int] = []
var _ai_actor_ids: Array[int] = []
var _rival_ids: Array[int] = []
var _local_field_ids: Array[int] = []
var _keeper_ids: Array[int] = []
var _error_message: String = ""
var _focus_before_open: WeakRef
var _stick_directions: Dictionary[int, int] = {}

@onready var _frame: Control = $Frame
@onready var _summary: Label = %StateSummary
@onready var _mode_selector: Button = %ModeSelector
@onready var _mode_dropdown: PanelContainer = %ModeDropdown
@onready var _micro_choice: Button = %MicroChoice
@onready var _preview_choice: Button = %PreviewChoice
@onready var _apply_button: Button = %ApplyModeButton
@onready var _rival_toggle: CheckBox = %RivalToggle
@onready var _teammates_toggle: CheckBox = %TeammatesToggle
@onready var _keeper_toggle: CheckBox = %KeeperToggle
@onready var _rival_status: Label = %RivalStatus
@onready var _teammates_status: Label = %TeammatesStatus
@onready var _keeper_status: Label = %KeeperStatus
@onready var _error_label: Label = %ErrorText
@onready var _close_button: Button = %CloseButton
@onready var _aim_toggle: CheckBox = %AimGuideToggle
@onready var _exercise_selector: OptionButton = %ExerciseSelector
@onready var _exercise_button: Button = %ApplyExerciseButton


func _ready() -> void:
	get_viewport().size_changed.connect(_refresh_layout)
	_mode_selector.item_rect_changed.connect(_position_dropdown)
	_exercise_selector.clear()
	_exercise_selector.get_popup().window_input.connect(_on_exercise_window_input)
	for id: int in EXERCISE_LABELS:
		_exercise_selector.add_item(EXERCISE_LABELS[id], id)
		_exercise_selector.set_item_tooltip(_exercise_selector.item_count - 1,
			"Ejercicio local de producción. Los córners −X espejan la orientación del equipo, no la portería asignada.")
	_refresh_layout()
	_refresh_state()
	_refresh_error()
	_refresh_open()


## Valida toda la información que presenta antes de modificar la vista.
## Copia intención y actividad efectiva; exige efectiva = intención menos seleccionado.
## No conserva referencias al snapshot ni a sus actores.
func present(state: Snapshot) -> Error:
	if state == null or not _known_mode(state.mode) or not EXERCISE_LABELS.has(state.training_exercise):
		return ERR_INVALID_PARAMETER
	var expected_count: int = 4 if state.mode == Setup.Mode.MICRO_1V1 else 10
	if state.actors.size() != expected_count or state.selected_actor_id < 0 \
			or state.selected_actor_id >= expected_count:
		return ERR_INVALID_PARAMETER
	var seen: Dictionary[int, bool] = {}
	var human: Snapshot.ActorSnapshot = null
	var fields: Dictionary[int, int] = {Snapshot.Team.HOME: 0, Snapshot.Team.AWAY: 0}
	var keepers: Dictionary[int, int] = {Snapshot.Team.HOME: 0, Snapshot.Team.AWAY: 0}
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor == null or actor.actor_id < 0 or actor.actor_id >= expected_count \
				or seen.has(actor.actor_id):
			return ERR_INVALID_PARAMETER
		if actor.team_id != Snapshot.Team.HOME and actor.team_id != Snapshot.Team.AWAY:
			return ERR_INVALID_PARAMETER
		if actor.role != Snapshot.Role.FIELD and actor.role != Snapshot.Role.KEEPER:
			return ERR_INVALID_PARAMETER
		seen[actor.actor_id] = true
		if actor.role == Snapshot.Role.FIELD:
			fields[actor.team_id] += 1
		else:
			keepers[actor.team_id] += 1
		if actor.human_controlled:
			if human != null or actor.actor_id != state.selected_actor_id \
					or actor.team_id != Snapshot.Team.HOME:
				return ERR_INVALID_PARAMETER
			human = actor
	var expected_fields: int = 1 if state.mode == Setup.Mode.MICRO_1V1 else 4
	if human == null or fields[Snapshot.Team.HOME] != expected_fields \
			or fields[Snapshot.Team.AWAY] != expected_fields \
			or keepers[Snapshot.Team.HOME] != 1 or keepers[Snapshot.Team.AWAY] != 1:
		return ERR_INVALID_PARAMETER
	var rival_ids: Array[int] = []
	var local_field_ids: Array[int] = []
	var keeper_ids: Array[int] = []
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id != human.team_id:
			rival_ids.append(actor.actor_id)
		elif actor.role == Snapshot.Role.KEEPER:
			keeper_ids.append(actor.actor_id)
		else:
			local_field_ids.append(actor.actor_id)
	var intent_ids: Array[int] = []
	for id: int in state.ai_intent_actor_ids:
		if not seen.has(id) or intent_ids.has(id):
			return ERR_INVALID_PARAMETER
		intent_ids.append(id)
	var ai_ids: Array[int] = []
	for id: int in state.ai_actor_ids:
		if id == human.actor_id or not seen.has(id) or ai_ids.has(id):
			return ERR_INVALID_PARAMETER
		ai_ids.append(id)
	rival_ids.sort()
	local_field_ids.sort()
	keeper_ids.sort()
	intent_ids.sort()
	ai_ids.sort()
	var expected_ai: Array[int] = intent_ids.duplicate()
	expected_ai.erase(state.selected_actor_id)
	if ai_ids != expected_ai:
		return ERR_INVALID_PARAMETER
	var mode_changed: bool = not _has_state or _mode != state.mode
	var exercise_changed: bool = not _has_state or _exercise != state.training_exercise
	_mode = state.mode
	_exercise = state.training_exercise
	_actor_count = state.actors.size()
	_selected_actor_id = human.actor_id
	_selected_role = human.role
	_ai_intent_actor_ids = intent_ids
	_ai_actor_ids = ai_ids
	_rival_ids = rival_ids
	_local_field_ids = local_field_ids
	_keeper_ids = keeper_ids
	_has_state = true
	if mode_changed:
		_pending_mode = _mode
	if mode_changed or exercise_changed:
		_pending_exercise = _exercise
	if is_node_ready():
		if mode_changed:
			_close_dropdown(false)
		if mode_changed or exercise_changed:
			_exercise_selector.get_popup().hide()
		_refresh_state()
	return OK


## Solo visibilidad/foco. Cerrar descarta el borrador de modo, no cambia el partido.
func set_open(value: bool) -> void:
	if _open == value:
		return
	_open = value
	if _has_state:
		_pending_mode = _mode
		_pending_exercise = _exercise
	_stick_directions.clear()
	if is_node_ready():
		_refresh_selector()
		_refresh_exercise()
		_refresh_open()


func is_open() -> bool:
	return _open


## Confirmación efímera del anfitrión; no se restablece al recibir otro modo o ejercicio.
func set_aim_guide_enabled(enabled: bool) -> void:
	_aim_guide_enabled = enabled
	_aim_guide_confirmed = true
	if is_node_ready():
		_refresh_aim_guide()
		if _open:
			_refresh_focus_loop()


## Texto plano, acotado visualmente a dos líneas. No cambia ninguna selección confirmada.
func show_error(message: String) -> void:
	_error_message = message.strip_edges()
	if is_node_ready():
		_refresh_error()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()
		_handle_key(event as InputEventKey)
	elif event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		_handle_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		_handle_axis(event as InputEventJoypadMotion)
	elif event is InputEventMouseButton and _mode_dropdown.visible:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and not _mode_dropdown.get_global_rect().has_point(mouse.position):
			get_viewport().set_input_as_handled()
			_close_dropdown()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	match key:
		KEY_UP:
			_move_focus(-1)
		KEY_DOWN:
			_move_focus(1)
		KEY_TAB:
			_move_focus(-1 if event.shift_pressed else 1)
		KEY_LEFT, KEY_RIGHT:
			if get_viewport().gui_get_focus_owner() == _exercise_selector and not event.echo:
				_cycle_exercise(-1 if key == KEY_LEFT else 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_activate_focused()
		KEY_ESCAPE:
			if not event.echo:
				_on_close_pressed()


func _handle_button(event: InputEventJoypadButton) -> void:
	if not event.pressed:
		return
	match event.button_index:
		JOY_BUTTON_DPAD_UP:
			_move_focus(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move_focus(1)
		JOY_BUTTON_A:
			_activate_focused()
		JOY_BUTTON_B, JOY_BUTTON_START:
			_on_close_pressed()


func _on_exercise_window_input(event: InputEvent) -> void:
	if not _open:
		return
	var popup: PopupMenu = _exercise_selector.get_popup()
	if event.is_action_pressed("pause") or (event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_B, JOY_BUTTON_START]):
		popup.set_input_as_handled()
		get_viewport().set_input_as_handled()
		_on_close_pressed()
		return
	# PopupMenu procesa sus ui_* antes de emitir window_input.
	for action: StringName in [&"ui_accept", &"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		if event.is_action(action):
			return
	if event is InputEventKey:
		_exercise_selector.get_popup().set_input_as_handled()
		_handle_key(event as InputEventKey)
	elif event is InputEventJoypadButton:
		_exercise_selector.get_popup().set_input_as_handled()
		_handle_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_exercise_selector.get_popup().set_input_as_handled()
		_handle_axis(event as InputEventJoypadMotion)


func _handle_axis(event: InputEventJoypadMotion) -> void:
	if event.axis != JOY_AXIS_LEFT_Y or not is_finite(event.axis_value):
		return
	if absf(event.axis_value) <= 0.3:
		_stick_directions.erase(event.device)
	elif absf(event.axis_value) >= 0.55:
		var direction: int = 1 if event.axis_value > 0.0 else -1
		if _stick_directions.get(event.device, 0) != direction:
			_stick_directions[event.device] = direction
			_move_focus(direction)


func _refresh_layout() -> void:
	var stretch: Vector2 = get_viewport().get_stretch_transform().get_scale().abs()
	stretch.x = maxf(stretch.x, 0.001)
	stretch.y = maxf(stretch.y, 0.001)
	var pixels: Vector2 = get_viewport().get_visible_rect().size * stretch
	var fit: float = maxf(0.001, minf(1.0,
		minf(pixels.x / MIN_UI_SIZE.x, pixels.y / MIN_UI_SIZE.y)))
	_frame.scale = Vector2(fit, fit) / stretch
	_frame.size = pixels / fit
	if _mode_dropdown.visible:
		_position_dropdown.call_deferred()


func _refresh_open() -> void:
	var was_visible: bool = _frame.visible
	if _open and not was_visible:
		var owner: Control = get_viewport().gui_get_focus_owner()
		_focus_before_open = weakref(owner) if owner != null else null
	_frame.visible = _open
	if _open:
		_refresh_focus_loop()
	else:
		_close_dropdown(false)
		_exercise_selector.get_popup().hide()
		var owner: Control = get_viewport().gui_get_focus_owner()
		if owner != null and _frame.is_ancestor_of(owner):
			owner.release_focus()
		if was_visible and _focus_before_open != null:
			var previous: Control = _focus_before_open.get_ref() as Control
			if is_instance_valid(previous) and previous.is_inside_tree() \
					and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE:
				previous.grab_focus()
		_focus_before_open = null


func _refresh_state() -> void:
	if _has_state:
		_summary.text = "%s · %d atletas · IA efectiva %d/%d\nControl: ID %d · %s · Intención %d/%d · Sin progresión/XP" % [
			_mode_title(_mode), _actor_count, _ai_actor_ids.size(), _actor_count - 1,
			_selected_actor_id, "PORTERO" if _selected_role == Snapshot.Role.KEEPER else "CAMPO",
			_ai_intent_actor_ids.size(), _actor_count,
		]
	else:
		_summary.text = "Sin estado confirmado\nLos controles estarán disponibles al recibir un snapshot válido."
	_refresh_selector()
	_apply_button.disabled = not _has_state
	_refresh_exercise()
	_refresh_aim_guide()
	_refresh_groups()
	if _open and _frame.visible:
		_refresh_focus_loop()


func _refresh_selector() -> void:
	_mode_selector.disabled = not _has_state
	_mode_selector.text = _mode_title(_pending_mode) + "  ▾" if _has_state else "Sin estado recibido"


func _refresh_exercise() -> void:
	_exercise_selector.disabled = not _has_state
	_exercise_button.disabled = not _has_state
	_exercise_selector.select(_exercise_selector.get_item_index(_pending_exercise) if _has_state else -1)
	_exercise_selector.tooltip_text = "Selección sin aplicar. Confirmado: %s. Conserva modo, intención IA y guía." % EXERCISE_LABELS[_exercise] \
		if _has_state else "Sin estado confirmado del anfitrión."


func _refresh_aim_guide() -> void:
	_aim_toggle.disabled = not _has_state or not _aim_guide_confirmed
	_aim_toggle.set_pressed_no_signal(_aim_guide_enabled)
	_aim_toggle.tooltip_text = "Guía propia confirmada por el anfitrión; no predice una llegada garantizada." \
		if _aim_guide_confirmed else "Pendiente de la preferencia confirmada del anfitrión."


func _refresh_groups() -> void:
	_refresh_toggle(_rival_toggle, _rival_status, _rival_ids)
	_refresh_toggle(_teammates_toggle, _teammates_status, _local_field_ids)
	_refresh_toggle(_keeper_toggle, _keeper_status, _keeper_ids)


func _refresh_toggle(toggle: CheckBox, status: Label, ids: Array[int]) -> void:
	var intended: int = _enabled_count(ids, _ai_intent_actor_ids)
	var active: int = _enabled_count(ids, _ai_actor_ids)
	toggle.disabled = not _has_state or ids.is_empty()
	toggle.set_pressed_no_signal(not ids.is_empty() and intended == ids.size())
	if not _has_state:
		status.text = "Sin estado"
	elif ids.is_empty():
		status.text = "Sin actores"
	else:
		var state_text: String = "Parcial" if intended > 0 and intended < ids.size() else "Intención"
		status.text = "%s %d/%d · IA %d" % [state_text, intended, ids.size(), active]
		if ids.has(_selected_actor_id) and _ai_intent_actor_ids.has(_selected_actor_id):
			status.text += " · Susp. ID %d" % _selected_actor_id


func _refresh_error() -> void:
	_error_label.text = _error_message
	_error_label.visible = not _error_message.is_empty()


func _focusable_controls() -> Array[Control]:
	if _mode_dropdown.visible:
		return [_micro_choice, _preview_choice]
	var controls: Array[Control] = []
	for button: BaseButton in [
		_mode_selector, _apply_button, _rival_toggle, _teammates_toggle, _keeper_toggle, _close_button,
	]:
		if not button.disabled:
			controls.append(button)
	var close_index: int = controls.find(_close_button)
	for button: BaseButton in [_aim_toggle, _exercise_selector, _exercise_button]:
		if not button.disabled:
			controls.insert(close_index, button)
			close_index += 1
	return controls


func _refresh_focus_loop() -> void:
	if _exercise_selector.get_popup().visible:
		return
	var controls: Array[Control] = _focusable_controls()
	for index: int in controls.size():
		var control: Control = controls[index]
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_bottom = control.focus_next
		control.focus_neighbor_left = NodePath(".")
		control.focus_neighbor_right = NodePath(".")
	if not controls.has(get_viewport().gui_get_focus_owner()):
		controls[0].grab_focus()


func _move_focus(direction: int) -> void:
	if _exercise_selector.get_popup().visible:
		var popup: PopupMenu = _exercise_selector.get_popup()
		var index: int = popup.get_focused_item()
		if index < 0:
			index = _exercise_selector.selected
		popup.set_focused_item(posmod(index + direction, _exercise_selector.item_count))
		return
	var controls: Array[Control] = _focusable_controls()
	var owner: Control = get_viewport().gui_get_focus_owner()
	if not controls.has(owner):
		controls[0].grab_focus()
		return
	var index: int = controls.find(owner)
	controls[posmod(index + direction, controls.size())].grab_focus()


func _activate_focused() -> void:
	if _exercise_selector.get_popup().visible:
		var index: int = _exercise_selector.get_popup().get_focused_item()
		if index >= 0:
			_on_exercise_selected(index)
		_exercise_selector.get_popup().hide()
		_exercise_selector.grab_focus()
		return
	var button: BaseButton = get_viewport().gui_get_focus_owner() as BaseButton
	if button != null and not button.disabled and _focusable_controls().has(button):
		if button == _exercise_selector:
			_exercise_selector.show_popup()
			_exercise_selector.get_popup().set_focused_item(_exercise_selector.selected)
			return
		button.pressed.emit()


func _on_mode_selector_pressed() -> void:
	if not _open or not _has_state:
		return
	_exercise_selector.get_popup().hide()
	if _mode_dropdown.visible:
		_close_dropdown()
		return
	_mode_dropdown.show()
	_position_dropdown()
	_stick_directions.clear()
	_refresh_focus_loop()
	(_micro_choice if _pending_mode == Setup.Mode.MICRO_1V1 else _preview_choice).grab_focus()


func _position_dropdown() -> void:
	if not _mode_dropdown.visible:
		return
	var relative: Transform2D = _frame.get_global_transform_with_canvas().affine_inverse() \
		* _mode_selector.get_global_transform_with_canvas()
	_mode_dropdown.position = relative * Vector2(0.0, _mode_selector.size.y) + Vector2(0.0, 4.0)
	_mode_dropdown.size = Vector2(_mode_selector.size.x, _mode_dropdown.get_combined_minimum_size().y)


func _close_dropdown(restore_focus: bool = true) -> void:
	var was_visible: bool = _mode_dropdown.visible
	_mode_dropdown.hide()
	_stick_directions.clear()
	if was_visible and restore_focus and _open:
		_refresh_focus_loop()
		_mode_selector.grab_focus()


func _on_micro_chosen() -> void:
	_select_mode(Setup.Mode.MICRO_1V1)


func _on_preview_chosen() -> void:
	_select_mode(Setup.Mode.PREVIEW_5V5)


func _select_mode(mode: Setup.Mode) -> void:
	if not _open or not _has_state or not _mode_dropdown.visible or not _known_mode(mode):
		return
	_pending_mode = mode
	_refresh_selector()
	_close_dropdown()


func _on_apply_pressed() -> void:
	if _open and _has_state and not _mode_dropdown.visible and not _exercise_selector.get_popup().visible:
		show_error("")
		mode_requested.emit(_pending_mode)


func _on_rival_pressed() -> void:
	_request_group(_rival_ids)


func _on_teammates_pressed() -> void:
	_request_group(_local_field_ids)


func _on_keeper_pressed() -> void:
	_request_group(_keeper_ids)


func _request_group(ids: Array[int]) -> void:
	# El clic nativo puede alternar el CheckBox; restaurar la confirmación antes de emitir.
	_refresh_groups()
	if not _open or not _has_state or ids.is_empty() or _mode_dropdown.visible or _exercise_selector.get_popup().visible:
		return
	var requested: Array[int] = _ai_intent_actor_ids.duplicate()
	var disable_group: bool = _enabled_count(ids, _ai_intent_actor_ids) == ids.size()
	for id: int in ids:
		if disable_group:
			requested.erase(id)
		elif not requested.has(id):
			requested.append(id)
	requested.sort()
	show_error("")
	ai_actor_ids_requested.emit(requested)


func _on_close_pressed() -> void:
	if _open:
		_close_dropdown()
		_exercise_selector.get_popup().hide()
		close_requested.emit()


func _on_aim_guide_pressed() -> void:
	_refresh_aim_guide()
	if not _open or not _has_state or not _aim_guide_confirmed or _mode_dropdown.visible \
			or _exercise_selector.get_popup().visible:
		return
	show_error("")
	aim_guide_requested.emit(not _aim_guide_enabled)


func _on_exercise_selected(index: int) -> void:
	if not _open or not _has_state or index < 0 or index >= _exercise_selector.item_count:
		_refresh_exercise()
		return
	var id: int = _exercise_selector.get_item_id(index)
	if not EXERCISE_LABELS.has(id):
		return
	_pending_exercise = id as Setup.TrainingExercise
	_refresh_exercise()


func _cycle_exercise(direction: int) -> void:
	if _open and _has_state and not _mode_dropdown.visible:
		_on_exercise_selected(posmod(_exercise_selector.selected + direction, _exercise_selector.item_count))


func _on_exercise_apply_pressed() -> void:
	if _open and _has_state and not _mode_dropdown.visible and not _exercise_selector.get_popup().visible:
		show_error("")
		exercise_requested.emit(_pending_exercise)


func _enabled_count(ids: Array[int], enabled: Array[int]) -> int:
	var active: int = 0
	for id: int in ids:
		if enabled.has(id):
			active += 1
	return active


func _known_mode(mode: Setup.Mode) -> bool:
	return mode == Setup.Mode.MICRO_1V1 or mode == Setup.Mode.PREVIEW_5V5


func _mode_title(mode: Setup.Mode) -> String:
	match mode:
		Setup.Mode.MICRO_1V1:
			return "1v1 de regresión"
		Setup.Mode.PREVIEW_5V5:
			return "5v5 experimental"
	return "Modo no válido"
