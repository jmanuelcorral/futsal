extends CanvasLayer
## Presentación G1 sin autoridad de partido. Instanciar match_hud.tscn.
## El anfitrión aplica snapshots y pausa de autoridad; el HUD no modifica SceneTree.
## El reloj no avanza aquí; solo los avisos transitorios usan tiempo de interfaz.
## Pausa usa la acción existente; navegación modal local no modifica InputMap.
## El anfitrión suspende su polling de Input durante pausa/resultado.

signal pause_requested()
signal resume_requested()
signal restart_requested()
signal quit_requested()
signal development_requested()

const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Command = preload("res://match/simulation/player_command.gd")
const SELECTION_ERROR: String = "MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local."
const RESTART_ERROR: String = "MatchHUD.present_restart: estado de reanudación incoherente o no válido."
const MAX_SCORE: int = 999
const MAX_CLOCK_SECONDS: float = 5999.0
const MAX_EVENT_DURATION: float = 10.0
const MIN_UI_SIZE: Vector2 = Vector2(960.0, 540.0)
const RESTART_FEEDBACK_SECONDS: float = 1.5

@export_color_no_alpha var home_color: Color = Color("#172f4d"):
	set(value):
		if not _valid_team_color(value):
			push_error("MatchHUD.home_color: se requiere un color RGB finito, normalizado y opaco.")
			return
		home_color = value
		if is_node_ready():
			_refresh_teams()

@export_color_no_alpha var away_color: Color = Color("#eee8d8"):
	set(value):
		if not _valid_team_color(value):
			push_error("MatchHUD.away_color: se requiere un color RGB finito, normalizado y opaco.")
			return
		away_color = value
		if is_node_ready():
			_refresh_teams()

@export_range(0, 99, 1) var home_dorsal: int = 7:
	set(value):
		if value < 0 or value > 99:
			push_error("MatchHUD.home_dorsal: el dorsal debe estar entre 0 y 99.")
			return
		home_dorsal = value
		if is_node_ready():
			_refresh_teams()

@export_range(0, 99, 1) var away_dorsal: int = 11:
	set(value):
		if value < 0 or value > 99:
			push_error("MatchHUD.away_dorsal: el dorsal debe estar entre 0 y 99.")
			return
		away_dorsal = value
		if is_node_ready():
			_refresh_teams()

var _home_score: int = 0
var _away_score: int = 0
var _clock_seconds: float = 0.0
var _charge: float = 0.0
var _event_message: String = ""
var _event_duration: float = 2.5
var _paused: bool = false
var _development_open: bool = false
var _mode: Setup.Mode = Setup.Mode.MICRO_1V1
var _showing_result: bool = false
var _result_message: String = ""
var _possession_known: bool = false
var _has_possession: bool = false
var _selected_actor_id: int = -1
var _selected_actor_role: Snapshot.Role = Snapshot.Role.FIELD
var _has_restart_state: bool = false
var _control_context: Rules.ControlContext = Rules.ControlContext.LIVE
var _allowed_actions: Array[int] = []
var _restart_visible: bool = false
var _corner_restart: bool = false
var _restart_title: String = ""
var _restart_clock: String = ""
var _restart_detail: String = ""
var _fouls_caption: String = ""
var _restart_has_choice: bool = false
var _extended_period: bool = false
var _selected_can_move: bool = false
var _restart_in_play: bool = false
var _restart_context_id: int = -1
var _restart_context_actor_id: int = -1
var _restart_feedback_active: bool = false
var _own_restart_ready: bool = false
var _restart_aim_hint: String = ""
var _restart_feedback_message: String = ""
var _restart_feedback_id: int = -1
var _restart_feedback_actor_id: int = -1
var _focus_before_modal: WeakRef
var _focus_before_development: WeakRef
var _home_chip_style: StyleBoxFlat
var _stick_directions: Dictionary[int, int] = {}

@onready var _frame: Control = $Frame
@onready var _home_chip: Panel = %HomeChip
@onready var _away_fill: Polygon2D = %AwayFill
@onready var _home_dorsal_label: Label = %HomeDorsal
@onready var _away_dorsal_label: Label = %AwayDorsal
@onready var _score_label: Label = %Score
@onready var _clock_label: Label = %Clock
@onready var _training_label: Label = %TrainingLabel
@onready var _selected_actor_label: Label = %SelectedActor
@onready var _pause_button: Button = %PauseButton
@onready var _charge_panel: PanelContainer = %ChargePanel
@onready var _charge_bar: ProgressBar = %ShotCharge
@onready var _charge_label: Label = %ChargeValue
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _event_label: Label = %EventText
@onready var _event_timer: Timer = $EventTimer
@onready var _controls_context: Label = %ControlsContext
@onready var _move_hint: Label = %MoveHint
@onready var _sprint_keys: Label = %SprintKeys
@onready var _sprint_hint: Label = %SprintHint
@onready var _close_control_keys: Label = %CloseControlKeys
@onready var _pass_hint: Label = %PassHint
@onready var _shoot_hint: Label = %ShootHint
@onready var _dribble_keys: Label = %DribbleKeys
@onready var _dribble_hint: Label = %DribbleHint
@onready var _close_control_hint: Label = %CloseControlHint
@onready var _modal: Control = %PauseOverlay
@onready var _modal_title: Label = %ModalTitle
@onready var _modal_detail: Label = %ModalDetail
@onready var _modal_hint: Label = %ModalHint
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton
@onready var _development_button: Button = %DevelopmentButton
@onready var _quit_button: Button = %QuitButton
@onready var _restart_panel: PanelContainer = %RestartPanel
@onready var _restart_panel_default_offsets: Vector2 = Vector2(_restart_panel.offset_top, _restart_panel.offset_bottom)
@onready var _restart_title_label: Label = %RestartTitle
@onready var _restart_clock_label: Label = %RestartClock
@onready var _restart_detail_label: Label = %RestartDetail
@onready var _fouls_label: Label = %FoulTotals
@onready var _restart_feedback_panel: PanelContainer = %RestartFeedbackPanel
@onready var _restart_aim_hint_label: Label = %RestartAimHint
@onready var _restart_feedback_label: Label = %RestartFeedback
@onready var _restart_feedback_timer: Timer = $RestartFeedbackTimer


func _ready() -> void:
	_home_chip_style = _home_chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_home_chip.add_theme_stylebox_override("panel", _home_chip_style)
	get_viewport().size_changed.connect(_refresh_layout)
	_refresh_layout()
	_refresh_teams()
	_refresh_score()
	_refresh_clock()
	_refresh_mode()
	_refresh_selected_actor()
	_refresh_charge()
	_refresh_controls()
	_refresh_restart()
	_refresh_event()
	_refresh_modal()
	if not _restart_feedback_message.is_empty():
		_restart_feedback_timer.start(RESTART_FEEDBACK_SECONDS)


## Acepta 0..999 por equipo. Un error devuelve false y conserva ambos valores.
func update_score(home: int, away: int) -> bool:
	if not _valid_score(home, away):
		push_error("MatchHUD.update_score: los marcadores deben estar entre 0 y 999.")
		return false
	_home_score = home
	_away_score = away
	if is_node_ready():
		_refresh_score()
	return true


## Segundos restantes; limita a 00:00..99:59 y redondea hacia arriba.
## NaN e infinitos se rechazan sin cambiar la última lectura válida.
func update_clock(seconds: float) -> bool:
	if not is_finite(seconds):
		push_error("MatchHUD.update_clock: los segundos deben ser finitos.")
		return false
	_clock_seconds = clampf(seconds, 0.0, MAX_CLOCK_SECONDS)
	if is_node_ready():
		_refresh_clock()
	return true


## Fracción normalizada; los valores finitos se limitan a 0..1. Cero oculta la barra.
func set_shot_charge(value: float) -> bool:
	if not is_finite(value):
		push_error("MatchHUD.set_shot_charge: la carga debe ser finita.")
		return false
	_charge = clampf(value, 0.0, 1.0)
	if is_node_ready():
		_refresh_charge()
	return true


## Sustituye el aviso anterior, sin conceder goles ni cambiar el reloj.
## Duración positiva y finita, limitada a 10 s reales incluso en pausa.
## Un mensaje vacío borra el aviso. Ejemplos: «GOL · Local», «FUERA · Saque de banda».
func show_event(message: String, duration: float = 2.5) -> bool:
	if not is_finite(duration) or duration <= 0.0:
		push_error("MatchHUD.show_event: la duración debe ser positiva y finita.")
		return false
	_event_message = message.strip_edges()
	_event_duration = minf(duration, MAX_EVENT_DURATION)
	if is_node_ready():
		_refresh_event()
	return true


## Ayuda configurada por el host; visible durante READY propio, sin consumir el canal de avisos.
func set_restart_aim_hint(message: String) -> void:
	_restart_aim_hint = message.strip_edges()
	if is_node_ready():
		_refresh_restart_feedback()


## Aviso ligado al saque y actor que lo originaron; no modifica el plazo autoritativo.
## Un contexto nuevo espera su snapshot; identidades fuera de rango devuelven un error.
func show_restart_feedback(message: String, restart_id: int, actor_id: int) -> Error:
	if restart_id < 0 or actor_id < 0 or actor_id > 9:
		return ERR_INVALID_PARAMETER
	_restart_feedback_message = message.strip_edges()
	_restart_feedback_id = restart_id
	_restart_feedback_actor_id = actor_id
	if is_node_ready():
		_restart_feedback_timer.stop()
		if not _restart_feedback_message.is_empty():
			_restart_feedback_timer.start(RESTART_FEEDBACK_SECONDS)
		_refresh_restart_feedback()
	return OK


func clear_restart_feedback() -> void:
	_restart_feedback_message = ""
	_restart_feedback_id = -1
	_restart_feedback_actor_id = -1
	if is_node_ready():
		_restart_feedback_timer.stop()
		_refresh_restart_feedback()


## Solo cambia la presentación. No pausa ni reanuda SceneTree.
func set_paused(value: bool) -> void:
	_paused = value
	if value:
		clear_restart_feedback()
	if is_node_ready():
		_refresh_modal()


## Modo confirmado por el anfitrión. Un modo desconocido no cambia la vista.
func set_mode(mode: Setup.Mode) -> Error:
	if mode != Setup.Mode.MICRO_1V1 and mode != Setup.Mode.PREVIEW_5V5:
		return ERR_INVALID_PARAMETER
	if _mode != mode:
		clear_restart_feedback()
	_mode = mode
	if is_node_ready():
		_refresh_mode()
		_refresh_controls()
		_refresh_modal()
	return OK


## Identidad confirmada, independiente de escudos, colores y dorsales del marcador.
## Tras cambiar de actor, el anfitrión confirma posesión con set_has_possession().
## El pase puede seguir en vuelo: transferir foco no transfiere aquí la posesión.
func set_selected_actor(actor: Snapshot.ActorSnapshot) -> Error:
	if actor == null or actor.team_id != Snapshot.Team.HOME or not actor.human_controlled \
			or actor.actor_id < 0 or actor.actor_id > 9 \
			or (actor.role != Snapshot.Role.FIELD and actor.role != Snapshot.Role.KEEPER):
		push_error(SELECTION_ERROR)
		return ERR_INVALID_PARAMETER
	if _selected_actor_id != actor.actor_id:
		_possession_known = false
		if _restart_feedback_actor_id != actor.actor_id:
			clear_restart_feedback()
	_selected_actor_id = actor.actor_id
	_selected_actor_role = actor.role
	if is_node_ready():
		_refresh_selected_actor()
		_refresh_controls()
	return OK


## Suspende el modal del HUD y sus entradas, no la pausa ni el resultado recibidos.
## Al cerrar desarrollo recupera ese modal y su foco; no emite una reanudación.
func set_development_open(value: bool) -> void:
	if _development_open == value:
		return
	_development_open = value
	if value:
		clear_restart_feedback()
	_stick_directions.clear()
	if not is_node_ready():
		return
	_pause_button.disabled = value
	if value:
		var owner: Control = get_viewport().gui_get_focus_owner()
		if _modal.visible:
			_focus_before_development = weakref(
				owner if owner != null and _modal.is_ancestor_of(owner) else _development_button
			)
		if owner != null and _modal.is_ancestor_of(owner):
			owner.release_focus()
		_modal.hide()
	else:
		_refresh_modal(true)


## Contexto recibido del anfitrión; hasta recibirlo se muestran ambas acciones.
func set_has_possession(value: bool) -> void:
	_possession_known = true
	_has_possession = value
	if is_node_ready():
		_refresh_controls()


## Consume solo el snapshot confirmado; sin cuenta atrás local ni mutación del partido.
func present_restart(state: Snapshot) -> Error:
	if not _valid_restart_state(state):
		push_error(RESTART_ERROR)
		return ERR_INVALID_PARAMETER
	var restart: Rules.RestartState = state.restart
	var active: bool = restart.kind != Rules.RestartKind.NONE and restart.stage != Rules.RestartStage.IN_PLAY
	var title: String = ""
	var clock: String = ""
	var detail: String = ""
	if active:
		title = "%s · %s · ID %d" % [_restart_name(restart.kind),
			"LOCAL" if restart.awarded_team_id == Snapshot.Team.HOME else "VISITA", restart.taker_actor_id]
		if restart.stage != Rules.RestartStage.READY:
			clock = "Preparación · el plazo aún no ha comenzado"
		elif restart.kind == Rules.RestartKind.PENALTY_6M:
			clock = "Listo · penalti sin cuenta de 4 s"
		else:
			clock = "Listo · %.1f s" % (ceilf(maxi(0, restart.deadline_tick - state.tick) / 6.0) / 10.0)
		if restart.awarded_team_id == Snapshot.Team.AWAY:
			detail = "Rival al saque · puedes defender y cambiar de jugador"
		elif restart.kind == Rules.RestartKind.GOAL_CLEARANCE:
			detail = "Dirección: apuntar · J / A: saque con las manos"
		elif restart.requires_direct_shot or restart.kind == Rules.RestartKind.PENALTY_6M:
			detail = "Tiro directo obligatorio · K / B: mantener y soltar"
			if restart.has_spot_choice:
				detail += "\nL / X: elegir %s" % ("punto de infracción" if restart.spot_choice == Rules.SpotChoice.TEN_METRE else "marca de 10 m")
		else:
			detail = "Dirección: apuntar · J / A: pase rápido\nK / B: tiro solo si está permitido"
	if state.period_state == Rules.PeriodState.EXTENDED_KICK:
		clock = "ÚLTIMO LANZAMIENTO · " + clock if active else "ÚLTIMO LANZAMIENTO · resolución en curso"
		if not active:
			title = "PERIODO CERRADO · SIN NUEVO ATAQUE"
		active = true
	var fouls: String = "ACUM. LOCAL %d · VISITA %d" % [state.accumulated_fouls.x, state.accumulated_fouls.y]
	if state.training_exercise == Setup.TrainingExercise.ACCUMULATED_FREE_KICK:
		fouls += "\ncontador inicial predefinido"
	_has_restart_state = true
	_control_context = state.human_control_context
	_allowed_actions.assign(state.human_allowed_actions)
	_restart_visible = active and state.phase != Snapshot.Phase.FINISHED
	_corner_restart = _restart_visible and state.phase == Snapshot.Phase.RESTART_PAUSE \
		and restart.kind == Rules.RestartKind.CORNER and restart.awarded_team_id == Snapshot.Team.HOME
	_restart_title = title
	_restart_clock = clock
	_restart_detail = detail
	_fouls_caption = fouls
	_restart_has_choice = restart.has_spot_choice
	_extended_period = state.period_state == Rules.PeriodState.EXTENDED_KICK
	_selected_can_move = state.selected_can_move
	_restart_in_play = restart.stage == Rules.RestartStage.IN_PLAY
	_restart_context_id = restart.id
	_restart_context_actor_id = state.selected_actor_id
	_restart_feedback_active = state.phase == Snapshot.Phase.RESTART_PAUSE and restart.kind != Rules.RestartKind.NONE \
		and restart.stage in [Rules.RestartStage.STOPPED, Rules.RestartStage.PLACEMENT, Rules.RestartStage.READY]
	_own_restart_ready = _restart_feedback_active and restart.stage == Rules.RestartStage.READY \
		and restart.awarded_team_id == Snapshot.Team.HOME
	if not _restart_feedback_active or _restart_feedback_id != restart.id or _restart_feedback_actor_id != state.selected_actor_id:
		clear_restart_feedback()
	if is_node_ready():
		_refresh_restart()
		_refresh_controls()
	return OK


func _valid_restart_state(state: Snapshot) -> bool:
	if state == null or state.restart == null or state.tick < 0 \
			or not is_finite(state.seconds_remaining) or state.seconds_remaining < 0.0 \
			or state.accumulated_fouls.x < 0 or state.accumulated_fouls.y < 0 \
			or state.mode not in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5] \
			or state.phase < Snapshot.Phase.READY or state.phase > Snapshot.Phase.FINISHED \
			or state.human_control_context < Rules.ControlContext.DISABLED or state.human_control_context > Rules.ControlContext.RESTART_DEFEND \
			or state.training_exercise < Setup.TrainingExercise.FREE_PLAY or state.training_exercise > Setup.TrainingExercise.ACCUMULATED_FREE_KICK \
			or state.period_state not in [Rules.PeriodState.REGULATION, Rules.PeriodState.EXTENDED_KICK]:
		return false
	var actors: Dictionary[int, Snapshot.ActorSnapshot] = {}
	var human: Snapshot.ActorSnapshot = null
	var expected_count: int = 4 if state.mode == Setup.Mode.MICRO_1V1 else 10
	if state.actors.size() != expected_count:
		return false
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor == null or actors.has(actor.actor_id) or actor.actor_id < 0 or actor.actor_id >= expected_count \
				or actor.team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY] \
				or actor.role not in [Snapshot.Role.FIELD, Snapshot.Role.KEEPER]:
			return false
		actors[actor.actor_id] = actor
		if actor.human_controlled:
			if human != null or actor.team_id != Snapshot.Team.HOME or actor.actor_id != state.selected_actor_id:
				return false
			human = actor
	if human == null:
		return false
	if state.human_control_context == Rules.ControlContext.DISABLED and state.selected_can_move:
		return false
	var actions: Array[int] = []
	for action: int in state.human_allowed_actions:
		if action < Command.Action.NONE or action > Command.Action.CHOOSE_RESTART_SPOT or actions.has(action):
			return false
		actions.append(action)
	var restart: Rules.RestartState = state.restart
	if restart.kind < Rules.RestartKind.NONE or restart.kind > Rules.RestartKind.ACCUMULATED_FREE_KICK \
			or restart.stage < Rules.RestartStage.NONE or restart.stage > Rules.RestartStage.IN_PLAY \
			or restart.spot_choice < Rules.SpotChoice.DEFAULT or restart.spot_choice > Rules.SpotChoice.OFFENCE_SPOT \
			or restart.border < Rules.Border.NONE or restart.border > Rules.Border.POS_Z \
			or not restart.spot.is_finite() or not restart.offence_spot.is_finite() \
			or not is_finite(restart.minimum_opponent_distance) or restart.minimum_opponent_distance < 0.0:
		return false
	if restart.kind == Rules.RestartKind.NONE:
		return (restart.stage == Rules.RestartStage.NONE and state.period_state == Rules.PeriodState.REGULATION
			and state.human_control_context not in [Rules.ControlContext.RESTART_AIM, Rules.ControlContext.RESTART_DEFEND])
	if restart.id < 0 or restart.stage == Rules.RestartStage.NONE \
			or not actors.has(restart.taker_actor_id) or restart.awarded_team_id not in [Snapshot.Team.HOME, Snapshot.Team.AWAY] \
			or actors[restart.taker_actor_id].team_id != restart.awarded_team_id:
		return false
	if restart.kind == Rules.RestartKind.GOAL_CLEARANCE and actors[restart.taker_actor_id].role != Snapshot.Role.KEEPER:
		return false
	var shot_only: bool = restart.kind in [Rules.RestartKind.PENALTY_6M, Rules.RestartKind.ACCUMULATED_FREE_KICK]
	if (restart.kind == Rules.RestartKind.ACCUMULATED_FREE_KICK and not restart.requires_direct_shot) \
			or (not shot_only and restart.requires_direct_shot) \
			or (restart.has_spot_choice and restart.kind != Rules.RestartKind.ACCUMULATED_FREE_KICK):
		return false
	if restart.kind == Rules.RestartKind.PENALTY_6M and restart.deadline_tick != -1:
		return false
	if restart.stage == Rules.RestartStage.READY:
		if restart.ready_tick < 0 or restart.ready_tick > state.tick:
			return false
		if restart.kind != Rules.RestartKind.PENALTY_6M and restart.deadline_tick != restart.ready_tick + 240:
			return false
	if restart.stage != Rules.RestartStage.IN_PLAY:
		if state.phase != Snapshot.Phase.RESTART_PAUSE and not (state.phase == Snapshot.Phase.PAUSED and state.resume_phase == Snapshot.Phase.RESTART_PAUSE):
			return false
		if restart.awarded_team_id == Snapshot.Team.HOME and restart.taker_actor_id != state.selected_actor_id:
			return false
		if state.phase == Snapshot.Phase.PAUSED and state.human_control_context != Rules.ControlContext.DISABLED:
			return false
		if restart.stage == Rules.RestartStage.READY and state.phase != Snapshot.Phase.PAUSED:
			var expected_context: Rules.ControlContext = Rules.ControlContext.RESTART_AIM \
				if restart.awarded_team_id == Snapshot.Team.HOME else Rules.ControlContext.RESTART_DEFEND
			if state.human_control_context != expected_context:
				return false
	elif state.human_control_context in [Rules.ControlContext.RESTART_AIM, Rules.ControlContext.RESTART_DEFEND]:
		return false
	if state.human_control_context == Rules.ControlContext.RESTART_AIM:
		if restart.awarded_team_id != Snapshot.Team.HOME or state.selected_can_move:
			return false
		if shot_only and (Command.Action.PASS in actions or Command.Action.KEEPER_THROW in actions):
			return false
		if restart.kind == Rules.RestartKind.GOAL_CLEARANCE and (Command.Action.PASS in actions or Command.Action.SHOOT in actions):
			return false
	if state.human_control_context == Rules.ControlContext.RESTART_DEFEND:
		if restart.awarded_team_id != Snapshot.Team.AWAY or Command.Action.TACKLE in actions or Command.Action.SHOOT in actions \
				or Command.Action.PASS in actions or Command.Action.KEEPER_THROW in actions or Command.Action.DRIBBLE in actions:
			return false
	if state.period_state == Rules.PeriodState.EXTENDED_KICK:
		if not shot_only or state.seconds_remaining != 0.0 or state.extended_restart_id != restart.id:
			return false
	return true


func _restart_name(kind: Rules.RestartKind) -> String:
	match kind:
		Rules.RestartKind.KICK_IN: return "SAQUE DE BANDA"
		Rules.RestartKind.CORNER: return "CÓRNER"
		Rules.RestartKind.GOAL_CLEARANCE: return "SAQUE DE META"
		Rules.RestartKind.DIRECT_FREE_KICK: return "LIBRE DIRECTO"
		Rules.RestartKind.INDIRECT_FREE_KICK: return "LIBRE INDIRECTO"
		Rules.RestartKind.PENALTY_6M: return "PENALTI · 6 m"
		Rules.RestartKind.ACCUMULATED_FREE_KICK: return "SEXTA Y SIGUIENTES · SIN BARRERA"
	return ""


func _refresh_restart() -> void:
	_restart_panel.visible = _restart_visible
	_restart_title_label.text = _restart_title
	_restart_clock_label.text = _restart_clock
	_restart_detail_label.text = _restart_detail
	_fouls_label.text = _fouls_caption
	_fouls_label.visible = _has_restart_state
	_event_panel.visible = not _event_message.is_empty() and not _restart_visible
	_refresh_restart_layout()
	_refresh_restart_feedback()


func _refresh_restart_layout() -> void:
	var top: float = maxf(_restart_panel_default_offsets.x, _frame.size.y - 392.0) \
		if _corner_restart else _restart_panel_default_offsets.x
	# Cambiar position copiaría la altura mínima expandida y después impediría encoger.
	_restart_panel.offset_top = top
	_restart_panel.offset_bottom = top + _restart_panel_default_offsets.y - _restart_panel_default_offsets.x


func _refresh_restart_feedback() -> void:
	var unobstructed: bool = not _paused and not _development_open and not _showing_result
	_restart_aim_hint_label.text = _restart_aim_hint
	_restart_aim_hint_label.visible = unobstructed and _own_restart_ready and not _restart_aim_hint.is_empty()
	_restart_feedback_label.text = _restart_feedback_message
	_restart_feedback_label.tooltip_text = _restart_feedback_message
	_restart_feedback_label.visible = unobstructed and _restart_feedback_active and not _restart_feedback_message.is_empty() \
		and _restart_feedback_id == _restart_context_id and _restart_feedback_actor_id == _restart_context_actor_id
	_restart_feedback_panel.visible = _restart_aim_hint_label.visible or _restart_feedback_label.visible


## Resultado suministrado, sin inferir ganador ni conceder recompensas.
## El resultado no ofrece «Continuar»; se retira explícitamente con clear_result().
func show_result(home: int, away: int, message: String = "Entrenamiento completado") -> bool:
	if not _valid_score(home, away) or message.strip_edges().is_empty():
		push_error("MatchHUD.show_result: se requieren marcadores válidos y un mensaje no vacío.")
		return false
	_home_score = home
	_away_score = away
	_result_message = message.strip_edges()
	_showing_result = true
	clear_restart_feedback()
	if is_node_ready():
		_refresh_score()
		_refresh_modal()
	return true


## Retira el resultado, conserva los datos y respeta el último set_paused().
func clear_result() -> void:
	_showing_result = false
	_result_message = ""
	if is_node_ready():
		_refresh_modal()


func _input(event: InputEvent) -> void:
	if _development_open:
		return
	if event.is_action_pressed("pause"):
		if not _showing_result:
			if _paused:
				resume_requested.emit()
			else:
				pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not _modal.visible:
		return
	# No depender de los ui_* predeterminados: este motor los limita por dispositivo
	# y no incluye A/B. Se conservan intactos los bindings compartidos del proyecto.
	if event is InputEventKey:
		_handle_modal_key(event as InputEventKey)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		_handle_modal_button(event as InputEventJoypadButton)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		_handle_modal_axis(event as InputEventJoypadMotion)
		get_viewport().set_input_as_handled()


func _handle_modal_key(event: InputEventKey) -> void:
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
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not event.echo:
				_activate_focused()
		KEY_ESCAPE:
			if not event.echo:
				_on_resume_pressed()


func _handle_modal_button(event: InputEventJoypadButton) -> void:
	if not event.pressed:
		return
	match event.button_index:
		JOY_BUTTON_DPAD_UP:
			_move_focus(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move_focus(1)
		JOY_BUTTON_A:
			_activate_focused()
		JOY_BUTTON_B:
			_on_resume_pressed()


func _handle_modal_axis(event: InputEventJoypadMotion) -> void:
	if event.axis != JOY_AXIS_LEFT_Y or not is_finite(event.axis_value):
		return
	if absf(event.axis_value) <= 0.3:
		_stick_directions.erase(event.device)
	elif absf(event.axis_value) >= 0.55:
		var direction: int = 1 if event.axis_value > 0.0 else -1
		if _stick_directions.get(event.device, 0) != direction:
			_stick_directions[event.device] = direction
			_move_focus(direction)


func _move_focus(direction: int) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not _modal.is_ancestor_of(focused):
		(_restart_button if _showing_result else _resume_button).grab_focus()
		return
	var neighbor: NodePath = focused.focus_next if direction > 0 else focused.focus_previous
	var next: Button = focused.get_node_or_null(neighbor) as Button
	if next != null and next.is_visible_in_tree() and not next.disabled:
		next.grab_focus()


func _activate_focused() -> void:
	var focused: Button = get_viewport().gui_get_focus_owner() as Button
	if focused != null and _modal.is_ancestor_of(focused) \
			and focused.is_visible_in_tree() and not focused.disabled:
		focused.pressed.emit()


func _refresh_layout() -> void:
	var stretch: Vector2 = get_viewport().get_stretch_transform().get_scale().abs()
	stretch.x = maxf(stretch.x, 0.001)
	stretch.y = maxf(stretch.y, 0.001)
	var pixels: Vector2 = get_viewport().get_visible_rect().size * stretch
	var fit: float = minf(1.0, minf(pixels.x / MIN_UI_SIZE.x, pixels.y / MIN_UI_SIZE.y))
	fit = maxf(fit, 0.001)
	# Compensa canvas_items sin tocar el viewport: texto de tamaño físico estable
	# desde 960×540 hasta 1920×1080; por debajo se reduce el conjunto para que quepa.
	_frame.scale = Vector2(fit, fit) / stretch
	_frame.size = pixels / fit
	_refresh_restart_layout()


func _refresh_teams() -> void:
	_home_chip_style.bg_color = home_color
	_away_fill.color = away_color
	_home_dorsal_label.text = "%02d" % home_dorsal
	_away_dorsal_label.text = "%02d" % away_dorsal
	_home_dorsal_label.add_theme_color_override("font_color", _dorsal_ink(home_color))
	_away_dorsal_label.add_theme_color_override("font_color", _dorsal_ink(away_color))


func _refresh_score() -> void:
	_score_label.text = "%d – %d" % [_home_score, _away_score]
	if _showing_result:
		_modal_detail.text = "%s\nLOCAL %d – %d VISITA" % [
			_result_message, _home_score, _away_score,
		]


func _refresh_clock() -> void:
	var total: int = ceili(_clock_seconds)
	var minutes: int = floori(float(total) / 60.0)
	_clock_label.text = "%02d:%02d" % [minutes, total % 60]


func _refresh_charge() -> void:
	_charge_bar.value = _charge
	_charge_label.text = "%d %%" % roundi(_charge * 100.0)
	_charge_panel.visible = _charge > 0.0


func _refresh_mode() -> void:
	_training_label.text = _mode_caption()


func _refresh_selected_actor() -> void:
	if _selected_actor_id < 0:
		_selected_actor_label.text = "CONTROL · —\nSin selección"
	else:
		_selected_actor_label.text = "CONTROL · ID %d\n%s LOCAL" % [
			_selected_actor_id, "PORTERO" if _selected_actor_role == Snapshot.Role.KEEPER else "CAMPO",
		]


func _mode_caption() -> String:
	return "5v5 experimental · Sin progresión/XP" \
		if _mode == Setup.Mode.PREVIEW_5V5 else "1v1 de regresión"


func _refresh_controls() -> void:
	_dribble_keys.visible = _possession_known and _has_possession
	_dribble_hint.visible = _dribble_keys.visible
	_move_hint.text = "Mover / Orientar"
	_sprint_keys.show()
	_sprint_hint.show()
	_close_control_keys.show()
	_close_control_hint.show()
	if _has_restart_state and _extended_period and _restart_in_play:
		_controls_context.text = "ÚLTIMO LANZAMIENTO · RESOLUCIÓN"
		_move_hint.text = "Mover portero defensor" if _selected_can_move else "Esperar resolución"
		_pass_hint.text = "Sin nuevo pase ni cambio"
		_shoot_hint.text = "Sin segundo ataque"
		_dribble_keys.hide()
		_dribble_hint.hide()
		_sprint_keys.visible = _selected_can_move
		_sprint_hint.visible = _selected_can_move
		_close_control_keys.visible = _selected_can_move
		_close_control_hint.visible = _selected_can_move
		_close_control_hint.text = "Contención lateral"
		return
	if _has_restart_state and _control_context != Rules.ControlContext.LIVE:
		var own_aim: bool = _control_context == Rules.ControlContext.RESTART_AIM
		var defending: bool = _control_context == Rules.ControlContext.RESTART_DEFEND
		_controls_context.text = "SAQUE PROPIO · APUNTAR" if own_aim else "SAQUE RIVAL · DEFENDER" if defending else "CONTROLES EN ESPERA"
		_move_hint.text = "Apuntar (sin caminar)" if own_aim else "Mover / Orientar" if defending else "Esperar preparación"
		_pass_hint.text = "Cambiar jugador · + dirección" if defending else "Pase no disponible"
		if own_aim and Command.Action.KEEPER_THROW in _allowed_actions:
			_pass_hint.text = "Saque con manos · pulsar"
		elif own_aim and Command.Action.PASS in _allowed_actions:
			_pass_hint.text = "Pase rápido · pulsar"
		_shoot_hint.text = "Tiro: mantener / soltar" if Command.Action.SHOOT in _allowed_actions else "Sin robo en balón parado"
		_dribble_keys.visible = own_aim and _restart_has_choice and Command.Action.CHOOSE_RESTART_SPOT in _allowed_actions
		_dribble_hint.visible = _dribble_keys.visible
		_dribble_hint.text = "Elegir punto legal" if _dribble_keys.visible else "Enganche / cambio de ritmo"
		_sprint_keys.visible = defending
		_sprint_hint.visible = defending
		_close_control_keys.visible = defending
		_close_control_hint.visible = defending
		_close_control_hint.text = "Contención lateral"
		return
	_dribble_hint.text = "Enganche / cambio de ritmo"
	if _has_restart_state:
		_dribble_keys.visible = _dribble_keys.visible and Command.Action.DRIBBLE in _allowed_actions
		_dribble_hint.visible = _dribble_keys.visible
	if not _possession_known:
		_controls_context.text = "CONTROLES · TECLADO / XBOX"
		_pass_hint.text = "Pase / Cambiar jugador"
		_shoot_hint.text = "Tiro / Robo de pie"
		_close_control_hint.text = "Control / Contención"
	elif _has_possession:
		_controls_context.text = "CON BALÓN · TECLADO / XBOX"
		_pass_hint.text = "Pase y controlar receptor"
		_shoot_hint.text = "Tiro: mantener / soltar"
		_close_control_hint.text = "Control cercano"
	else:
		_controls_context.text = "SIN BALÓN · TECLADO / XBOX"
		_pass_hint.text = "Cambiar jugador · + dirección"
		_shoot_hint.text = "Robo de pie"
		_close_control_hint.text = "Contención lateral"
	if _has_restart_state and Command.Action.KEEPER_THROW in _allowed_actions:
		_pass_hint.text = "Lanzar con manos · pulsar"
		_shoot_hint.text = "Sin patada con balón en manos"
		_dribble_keys.hide()
		_dribble_hint.hide()


func _refresh_event() -> void:
	_event_label.text = _event_message
	_event_panel.visible = not _event_message.is_empty() and not _restart_visible
	_event_timer.stop()
	if not _event_message.is_empty():
		_event_timer.start(_event_duration)


func _refresh_modal(restoring_development: bool = false) -> void:
	_refresh_restart_feedback()
	_pause_button.disabled = _development_open
	if _development_open:
		_modal.hide()
		return
	var was_visible: bool = _modal.visible
	var should_show: bool = _paused or _showing_result
	if was_visible != should_show:
		_stick_directions.clear()
	if should_show and not was_visible and not restoring_development:
		var owner: Control = get_viewport().gui_get_focus_owner()
		_focus_before_modal = weakref(owner) if owner != null else null
	_modal.visible = should_show
	_resume_button.visible = not _showing_result
	if _showing_result:
		_modal_title.text = "FIN DEL ENTRENAMIENTO"
		_modal_detail.text = "%s\nLOCAL %d – %d VISITA" % [
			_result_message, _home_score, _away_score,
		]
		_modal_hint.text = "Flechas / Stick · Elegir     Intro / A · Aceptar"
	else:
		_modal_title.text = "PAUSA"
		_modal_detail.text = "Entrenamiento · " + _mode_caption()
		_modal_hint.text = "Flechas / Stick · Elegir     Intro / A · Aceptar\nEsc / B / Menú · Continuar"
	if should_show:
		var buttons: Array[Button] = [_restart_button, _development_button, _quit_button]
		if not _showing_result:
			buttons.push_front(_resume_button)
		_set_focus_loop(buttons)
		var restored: Button = _focus_before_development.get_ref() as Button \
			if restoring_development and _focus_before_development != null else null
		if restored != null and buttons.has(restored):
			restored.grab_focus()
		elif not buttons.has(get_viewport().gui_get_focus_owner()):
			buttons[0].grab_focus()
	elif was_visible or restoring_development:
		var owner: Control = get_viewport().gui_get_focus_owner()
		if owner != null and _modal.is_ancestor_of(owner):
			owner.release_focus()
		if _focus_before_modal != null:
			var previous: Control = _focus_before_modal.get_ref() as Control
			if is_instance_valid(previous) and previous.is_inside_tree() \
					and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE:
				previous.grab_focus()
		_focus_before_modal = null
	if restoring_development:
		_focus_before_development = null


func _set_focus_loop(buttons: Array[Button]) -> void:
	for index: int in buttons.size():
		var button: Button = buttons[index]
		var before: Button = buttons[posmod(index - 1, buttons.size())]
		var after: Button = buttons[(index + 1) % buttons.size()]
		button.focus_previous = button.get_path_to(before)
		button.focus_next = button.get_path_to(after)
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")


func _on_event_timeout() -> void:
	_event_message = ""
	_event_label.text = ""
	_event_panel.hide()


func _on_restart_feedback_timeout() -> void:
	clear_restart_feedback()


func _on_pause_pressed() -> void:
	if not _development_open and not _paused and not _showing_result:
		pause_requested.emit()


func _on_resume_pressed() -> void:
	if not _development_open and _paused and not _showing_result:
		resume_requested.emit()


func _on_restart_pressed() -> void:
	if _modal.visible:
		restart_requested.emit()


func _on_development_pressed() -> void:
	if _modal.visible and not _development_open:
		development_requested.emit()


func _on_quit_pressed() -> void:
	if _modal.visible:
		quit_requested.emit()


func _valid_score(home: int, away: int) -> bool:
	return home >= 0 and home <= MAX_SCORE and away >= 0 and away <= MAX_SCORE


func _valid_team_color(value: Color) -> bool:
	return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) \
		and is_finite(value.a) and value.r >= 0.0 and value.r <= 1.0 \
		and value.g >= 0.0 and value.g <= 1.0 and value.b >= 0.0 and value.b <= 1.0 \
		and is_equal_approx(value.a, 1.0)


func _dorsal_ink(fill: Color) -> Color:
	return Color.BLACK if fill.srgb_to_linear().get_luminance() > 0.179 else Color.WHITE
