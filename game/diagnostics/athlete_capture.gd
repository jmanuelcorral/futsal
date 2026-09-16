extends Node
## Capturas opt-in del partido real; no altera el arranque normal del producto.

const MatchHost = preload("res://match/match.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Simulation = preload("res://match/simulation/match_simulation.gd")
const Hud = preload("res://match/presentation/hud/match_hud.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const DETAIL_CAMERA_OFFSET: Vector3 = Vector3(3.24, 1.30, -4.32)
const CAMERA_SETTLE_RENDER_FRAMES: int = 24

var _host: MatchHost
var _camera: Camera3D
var _output: String = ""
var _captures: Array[Dictionary] = []
var _started_ms: int = 0
var _failed: bool = false
var _shadow_probe: bool = false
var _key_light: DirectionalLight3D
var _detail_offset: Vector3 = DETAIL_CAMERA_OFFSET
var _detail_cut_frame: int = -1


func run(simulation: Simulation, _hud: Hud) -> void:
	_host = simulation.get_parent() as MatchHost
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> void:
	if not _failed and Time.get_ticks_msec() - _started_ms > 60000:
		_fail("Capture watchdog expired.")
	if not _failed and _camera != null and _camera.current:
		_update_detail_camera()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Player capture requires a real rendered viewport.")
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--athlete-capture-dir="):
			_output = argument.trim_prefix("--athlete-capture-dir=").replace("\\", "/").simplify_path()
		elif argument == "--athlete-shadow-probe":
			_shadow_probe = true
	if not _output.is_absolute_path() or _output.to_lower().begins_with("res:") or _output.to_lower().begins_with("user:") \
			or DirAccess.dir_exists_absolute(_output):
		_fail("Provide a new absolute athlete-capture-dir.")
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		_fail("Could not create the requested capture directory.")
		return
	if _host == null:
		_fail("Player capture requires the actual match host.")
		return
	await _frames(3)
	var lights: Array[Node] = _host.find_children("CeilingKey", "DirectionalLight3D", true, false)
	if lights.size() != 1:
		_fail("Player capture requires the scene's named CeilingKey light.")
		return
	_key_light = lights[0] as DirectionalLight3D
	var micro: Setup = Setup.new()
	micro.ai_actor_ids = []
	if _host.start_match(micro) != OK:
		_fail("Micro match did not start.")
		return
	await _frames(8)
	await _capture("micro-broadcast", false, false)
	if _host.set_match_paused(true) != OK:
		_fail("Could not pause for close-up inspection.")
		return
	(_host.get_node("MatchHUD") as CanvasLayer).visible = false
	(_host.get_node("MatchDevMenu") as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.name = "AssetInspectionCamera"
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 40.0
	_host.add_child(_camera)
	_point_camera(DETAIL_CAMERA_OFFSET)
	await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
	await _capture("micro-front-detail", true, false)
	if _shadow_probe:
		var original_bias: float = _key_light.shadow_bias
		var original_normal_bias: float = _key_light.shadow_normal_bias
		var original_angle: float = _key_light.light_angular_distance
		var original_shadows: bool = _key_light.shadow_enabled
		var original_taa: bool = get_tree().root.use_taa
		get_tree().root.use_taa = false
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-no-temporal-aa", true, false)
		_key_light.shadow_bias = 0.10
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-shadow-bias", true, false)
		_key_light.shadow_normal_bias = 2.0
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-normal-bias", true, false)
		_key_light.shadow_normal_bias = original_normal_bias
		_key_light.light_angular_distance = 0.0
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-hard-shadows", true, false)
		_key_light.light_angular_distance = original_angle
		_key_light.shadow_bias = original_bias
		get_tree().root.use_taa = true
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-temporal-aa", true, false)
		get_tree().root.use_taa = original_taa
		_key_light.shadow_enabled = false
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
		await _capture("micro-front-no-shadows", true, false)
		_key_light.shadow_bias = original_bias
		_key_light.shadow_enabled = original_shadows
		await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
	_point_camera(DETAIL_CAMERA_OFFSET * Vector3(-1, 1, -1))
	await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
	await _capture("micro-back-detail", true, false)
	_point_camera(DETAIL_CAMERA_OFFSET)
	await _render_frames(CAMERA_SETTLE_RENDER_FRAMES)
	if _host.set_match_paused(false) != OK:
		_fail("Could not resume the motion sample.")
		return
	await _frames(2)
	_key(KEY_SHIFT, true)
	_key(KEY_D, true)
	for index: int in 4:
		await _frames(6)
		await _capture("micro-sprint-%02d" % index, true, true)
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	_camera.current = false
	(_host.get_node("BroadcastCamera") as Camera3D).make_current()
	(_host.get_node("MatchHUD") as CanvasLayer).visible = true
	var preview: Setup = Setup.preview_5v5()
	preview.ai_actor_ids = []
	if _host.start_match(preview) != OK:
		_fail("Preview match did not start.")
		return
	await _frames(8)
	await _capture("preview-broadcast", false, false)
	var corner: Setup = Setup.for_exercise(Setup.Mode.PREVIEW_5V5, Setup.TrainingExercise.CORNER_POS_X_NEG_Z)
	corner.ai_actor_ids = []
	if _host.start_match(corner) != OK:
		_fail("Corner exercise did not start.")
		return
	var corner_ready: bool = false
	for frame: int in 600:
		await _frames(1)
		var state: Snapshot = _host.get_snapshot()
		var camera_state: Dictionary = _host.get_node("BroadcastCamera").get_camera_state()
		if state.restart.stage == Rules.RestartStage.READY and camera_state["mode"] == "corner" \
				and camera_state["transition_complete"]:
			corner_ready = true
			break
	if not corner_ready:
		_fail("Own corner did not reach READY with its behind-taker camera settled.")
		return
	await _capture("preview-corner", false, false)
	if _failed:
		return
	var manifest: Dictionary = {
		"scope": "real match scene in exported binary; extra camera only for asset inspection",
		"editor_binary": OS.has_feature("editor"),
		"engine": Engine.get_version_info(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": [int(get_tree().root.size.x), int(get_tree().root.size.y)],
		"fixed_fps_is_diagnostic": true,
		"camera_settle_render_frames": CAMERA_SETTLE_RENDER_FRAMES,
		"ai_disabled_for_repeatable_asset_inspection": true,
		"fps_measurement": false,
		"shadow_probe": _shadow_probe,
		"formal_art_gate_approved": false,
		"directional_shadow_filter_quality": ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
		"captures": _captures,
	}
	var file: FileAccess = FileAccess.open(_output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write the capture manifest.")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("FUTSAL_PLAYER_CAPTURES " + JSON.stringify(manifest))
	get_tree().quit(0)


func _point_camera(offset: Vector3) -> void:
	if _detail_cut_frame < 0 or not _camera.current or not _detail_offset.is_equal_approx(offset):
		_detail_cut_frame = Engine.get_frames_drawn()
	_detail_offset = offset
	_update_detail_camera()
	_camera.make_current()


func _update_detail_camera() -> void:
	var player: Node3D = _host.get_node("Athletes/Athlete0") as Node3D
	_camera.global_position = player.global_position + player.global_basis * _detail_offset
	_camera.look_at(player.global_position + Vector3(0, 0.88, 0), Vector3.UP)


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().physics_frame
	await get_tree().process_frame


func _render_frames(count: int) -> void:
	var start: int = Engine.get_frames_drawn()
	while not _failed and Engine.get_frames_drawn() - start < count:
		await RenderingServer.frame_post_draw


func _capture(name: String, close_up: bool, moving: bool) -> void:
	if _failed:
		return
	await RenderingServer.frame_post_draw
	var render_frame: int = Engine.get_frames_drawn()
	var frames_since_cut: int = render_frame - _detail_cut_frame if close_up else -1
	if close_up and (_detail_cut_frame < 0 or frames_since_cut < CAMERA_SETTLE_RENDER_FRAMES):
		_fail("Close-up capture preceded the required rendered frames after its camera cut.")
		return
	var image: Image = get_viewport().get_texture().get_image()
	var destination: String = _output.path_join(name + ".png")
	if image.get_width() != 1920 or image.get_height() != 1080 or FileAccess.file_exists(destination):
		_fail("Unexpected resolution or reused capture path.")
		return
	if image.save_png(destination) != OK:
		_fail("Could not save capture " + name)
		return
	var state: Snapshot = _host.get_snapshot()
	var actor: Snapshot.ActorSnapshot = state.actor(0)
	if moving and Vector2(actor.velocity.x, actor.velocity.z).length() < 0.1:
		_fail("A requested sprint sample did not move the actual actor.")
		return
	var camera: Camera3D = _camera if close_up else _host.get_node("BroadcastCamera") as Camera3D
	_captures.append({
		"file": name + ".png", "sha256": FileAccess.get_sha256(destination),
		"mode": state.mode, "actor_count": state.actors.size(), "tick": state.tick,
		"close_up_diagnostic_camera": close_up, "motion_sample": moving,
		"render_frame": render_frame, "detail_camera_cut_frame": _detail_cut_frame if close_up else -1,
		"render_frames_since_camera_cut": frames_since_cut,
		"actor_velocity": [actor.velocity.x, actor.velocity.y, actor.velocity.z],
		"camera_position": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
		"camera_basis": var_to_str(camera.global_basis), "camera_fov": camera.fov,
		"restart_kind": state.restart.kind, "restart_stage": state.restart.stage,
		"camera_context": {} if close_up else _host.get_node("BroadcastCamera").get_camera_state(),
		"key_shadow_bias": _key_light.shadow_bias, "key_shadows_enabled": _key_light.shadow_enabled,
		"key_shadow_normal_bias": _key_light.shadow_normal_bias,
		"key_angular_distance": _key_light.light_angular_distance, "temporal_aa": get_tree().root.use_taa,
	})


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.device = 0
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	get_tree().quit(2)
