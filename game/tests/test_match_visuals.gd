extends SceneTree
## Prueba de regresión visual: parqué, iluminación interior y animación de atletas.
## Ejecutar: godot --headless --path game --script res://tests/test_match_visuals.gd
## Verifica parámetros de materiales y propiedades de nodos. No sustituye a la
## inspección GPU del ejecutable ni a las pruebas físicas de producción.

const Arena = preload("res://match/presentation/arena/match_arena.gd")
const AthleteView = preload("res://match/presentation/athletes/athlete_view.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const AthleteMaterials = preload("res://tests/athlete_test_materials.gd")


class NativeErrors extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _entries: Array[Dictionary] = []

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		_entries.append({
			"function": function, "file": file, "line": line, "code": code,
			"rationale": rationale, "type": error_type,
		})
		_mutex.unlock()

	func snapshot() -> Dictionary:
		_mutex.lock()
		var entries: Array[Dictionary] = _entries.duplicate(true)
		_mutex.unlock()
		var result: Dictionary = {
			"error_count": 0, "script_error_count": 0, "shader_error_count": 0,
			"warning_count": 0, "entries": entries,
			"scope": "OS.Logger desde _initialize; errores de carga también deben verificarse en stderr",
		}
		for entry: Dictionary in entries:
			match int(entry["type"]):
				ERROR_TYPE_ERROR:
					result["error_count"] += 1
				ERROR_TYPE_SCRIPT:
					result["script_error_count"] += 1
				ERROR_TYPE_SHADER:
					result["shader_error_count"] += 1
				ERROR_TYPE_WARNING:
					result["warning_count"] += 1
		return result

var _checks: Array[Dictionary] = []
var _check_names: Dictionary[String, bool] = {}
var _duplicate_checks: Array[String] = []
var _native_errors: NativeErrors = NativeErrors.new()
var _started_ms: int = 0
var _selection_checks_completed: bool = false
var _arena_checks_completed: bool = false
var _reported: bool = false


func _initialize() -> void:
	OS.add_logger(_native_errors)
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if not _reported and Time.get_ticks_msec() - _started_ms > 30000:
		_check("Suite visual termina antes del watchdog de 30 segundos", false)
		_report()
	return false


func _run() -> void:
	_check("TAA configurado y solicitado por el viewport",
		ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa") == true and root.use_taa)
	_check("Sombras direccionales suaves con filtrado alto",
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
			== RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	# ---- Arena: ambiente, luces y parqué ----
	var arena: Arena = Arena.new()
	root.add_child(arena)
	await process_frame

	var env_node: WorldEnvironment = arena.get_node_or_null("IndoorEnvironment") as WorldEnvironment
	_check("WorldEnvironment existe", env_node != null)
	if env_node != null and env_node.environment != null:
		var e: Environment = env_node.environment
		_check("Ambient energy reducida (< 0.40)", e.ambient_light_energy < 0.40)
		_check("Tonemap Filmic activo", e.tonemap_mode == Environment.TONE_MAPPER_FILMIC)

	var key_light: DirectionalLight3D = arena.get_node_or_null("CeilingKey") as DirectionalLight3D
	_check("CeilingKey encontrada", key_light != null)
	if key_light != null:
		_check("Key sombras activadas", key_light.shadow_enabled)
		_check("Key shadow_bias ajustado (<= 0.02)", key_light.shadow_bias <= 0.02)
		_check("Key shadow_normal_bias >= 0.5", key_light.shadow_normal_bias >= 0.5)
		_check("Key energy >= 1.0", key_light.light_energy >= 1.0)

	var omnis: Array[Node] = arena.find_children("Luminaire*", "OmniLight3D", true, false)
	_check("Luminarias OmniLight añadidas (>= 5)", omnis.size() >= 5)
	if omnis.size() > 0:
		var first_omni: OmniLight3D = omnis[0] as OmniLight3D
		_check("Luminaria sin sombra propia (rendimiento)", not first_omni.shadow_enabled)
		_check("Luminaria range >= 12.0 m", first_omni.omni_range >= 12.0)

	var court_mesh: MeshInstance3D = arena.get_node_or_null("Court40x20") as MeshInstance3D
	_check("Malla Court40x20 existe", court_mesh != null)
	if court_mesh != null:
		var mat: Material = court_mesh.material_override
		_check("Parqué usa ShaderMaterial personalizado", mat is ShaderMaterial)
	_test_penalty_geometry(arena)

	# ---- Atletas: portero, marcadores y animación de sprint ----
	var kits: Array[Color] = [
		Color("#172f4d"), Color("#c8c2b6"), Color("#172f4d"), Color("#c8c2b6"),
	]
	var numbers: Array[int] = [7, 4, 1, 1]
	var athletes: Array[AthleteView] = []
	for id: int in 4:
		var av: AthleteView = AthleteView.new()
		root.add_child(av)
		av.configure(id, kits[id], numbers[id])
		athletes.append(av)
	await process_frame

	# Verificar distintivo de portero: únicamente IDs 2 y 3 (correcto para modo micro Y 5v5)
	for id: int in 4:
		var av: AthleteView = athletes[id]
		var badge: Node = av.get_node_or_null("ArticulatedBody/KeeperRole")
		var expected_keeper: bool = id in [2, 3]
		_check("Distintivo portero id=%d correcto" % id, (badge != null) == expected_keeper)

	# Verificar marcador de equipo visible en todos los actores
	for id: int in 4:
		var marker: MeshInstance3D = athletes[id].get_node_or_null("TeamShape") as MeshInstance3D
		_check("TeamShape existe id=%d" % id, marker != null)

	# Verificar inclinación de sprint: _body.rotation.x < 0 a v ≈ sprint_speed (7 m/s)
	for id: int in 2:
		var av: AthleteView = athletes[id]
		var snap: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		snap.actor_id = id
		snap.position = Vector3(float(id) * 4.0, 0.0, 0.0)
		snap.velocity = Vector3(7.0, 0.0, 0.0)
		snap.facing_yaw = 0.0
		av.present(snap, snap, 1.0, 0.05, false, 0.0)
		var body: Node3D = av.get_node_or_null("ArticulatedBody") as Node3D
		_check("Inclinación sprint activa id=%d (rotation.x < -0.01)" % id,
			body != null and body.rotation.x < -0.01)

	# Verificar frecuencia de zancada: a velocidad 7 m/s debe superar 3.5 Hz
	# (no medible sin tick; verificar parámetro de forma indirecta via _gait avance)
	# La prueba de sprint anterior garantiza que present() se invocó con v=7.

	# ---- 5v5 completo: configure()+present() para IDs 0..9 ----
	# HOME par (0,2,4,6,8), AWAY impar (1,3,5,7,9); porteros 2,3; campo 4-9
	var kit_home: Color = Color("#172f4d")
	var kit_away: Color = Color("#c8c2b6")
	var all_ids: Array[int] = [0,1,2,3,4,5,6,7,8,9]
	for fid: int in all_ids:
		var kit5: Color = kit_home if fid % 2 == 0 else kit_away
		var av5: AthleteView = AthleteView.new()
		root.add_child(av5)
		av5.configure(fid, kit5, fid + 1)
		var sn5: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		sn5.actor_id = fid
		sn5.velocity  = Vector3(4.5, 0.0, 0.0) if fid > 3 else Vector3.ZERO
		sn5.facing_yaw = 0.0
		av5.present(sn5, sn5, 1.0, 0.016, fid == 0, 0.0)
		var badge5: Node = av5.get_node_or_null("ArticulatedBody/KeeperRole")
		var expect_keeper: bool = fid in [2, 3]
		_check("configure+present id=%d keeper=%s" % [fid, expect_keeper],
			(badge5 != null) == expect_keeper)
		root.remove_child(av5)
		av5.queue_free()
	await process_frame

	# ---- Transiciones de pose: parado → sprint → parado ----
	var trans_av: AthleteView = athletes[0]
	var body_tr: Node3D = trans_av.get_node_or_null("ArticulatedBody") as Node3D
	var still_sn: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	still_sn.actor_id = 0; still_sn.velocity = Vector3.ZERO; still_sn.facing_yaw = 0.0
	trans_av.present(still_sn, still_sn, 1.0, 0.05, false, 0.0)
	_check("Parado: sin inclinación (rotation.x >= -0.005)",
		body_tr != null and body_tr.rotation.x >= -0.005)
	var run_sn: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	run_sn.actor_id = 0; run_sn.velocity = Vector3(7.5, 0.0, 0.0); run_sn.facing_yaw = 0.0
	trans_av.present(run_sn, run_sn, 1.0, 0.05, false, 0.0)
	_check("Sprint: inclinación activa (rotation.x < -0.05)",
		body_tr != null and body_tr.rotation.x < -0.05)
	trans_av.present(still_sn, still_sn, 1.0, 0.05, false, 0.0)
	_check("Vuelta parado: lean se cancela (rotation.x >= -0.005)",
		body_tr != null and body_tr.rotation.x >= -0.005)

	# ---- Shader: verificar correcciones clave en el código fuente ----
	if court_mesh != null:
		var mat_sh: ShaderMaterial = court_mesh.material_override as ShaderMaterial
		if mat_sh != null and mat_sh.shader != null:
			var code: String = mat_sh.shader.code
			_check("Shader sin sin(270) (causa raíz del shimmer eliminada)", not code.contains("270.0"))
			_check("Shader tiene fwidth (seam adaptativo)", code.contains("fwidth"))
			_check("Shader tiene METALLIC=0 explícito", code.contains("METALLIC"))

	_test_dynamic_selection_marks()
	_test_bounded_leg_segments(athletes[0])
	for av: AthleteView in athletes:
		av.free()
	arena.free()
	await process_frame
	_report()


func _test_penalty_geometry(arena: Arena) -> void:
	var markings: MeshInstance3D = arena.get_node("FutsalMarkings") as MeshInstance3D
	var arrays: Array = markings.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var home: Array[PackedVector3Array] = arena._penalty_area_paths(-1.0)
	var away: Array[PackedVector3Array] = arena._penalty_area_paths(1.0)
	_check("Área comparte radio de 6 m y tramo de 3,16 m del reglamento",
		is_equal_approx(Tuning.PENALTY_RADIUS, 6.0)
		and is_equal_approx(Tuning.PENALTY_STRAIGHT_LENGTH, 3.16)
		and is_equal_approx(Tuning.GOAL_POST_OUTER_Z, Tuning.PENALTY_STRAIGHT_LENGTH * 0.5))
	for end: int in [-1, 1]:
		var paths: Array[PackedVector3Array] = home if end == -1 else away
		var straight: PackedVector3Array = paths[0]
		_check("Tramo frontal del área usa longitud compartida extremo=%d" % end,
			is_equal_approx(straight[0].distance_to(straight[1]), Tuning.PENALTY_STRAIGHT_LENGTH))
		_check("Tramo frontal del área está a radio reglamentario extremo=%d" % end,
			is_equal_approx(absf(straight[0].x), Tuning.COURT_LENGTH * 0.5 - Tuning.PENALTY_RADIUS))
		for index: int in 2:
			var side: float = -1.0 if index == 0 else 1.0
			var arc: PackedVector3Array = paths[index + 1]
			var center: Vector3 = Vector3(end * Tuning.COURT_LENGTH * 0.5,
				0.012, side * Tuning.GOAL_POST_OUTER_Z)
			var radius_correct: bool = true
			var rendered: bool = true
			for point: Vector3 in arc:
				radius_correct = radius_correct and is_equal_approx(point.distance_to(center), Tuning.PENALTY_RADIUS)
				rendered = rendered and _rendered_ribbon_point(vertices, point)
			_check("Arco reglamentario nace del exterior del poste extremo=%d lado=%d" % [end, index],
				radius_correct and arc[0].is_equal_approx(straight[index]))
			_check("Arco llega a línea de meta sin ampliar portería extremo=%d lado=%d" % [end, index],
				is_equal_approx(arc[-1].x, center.x)
				and is_equal_approx(absf(arc[-1].z), Tuning.GOAL_POST_OUTER_Z + Tuning.PENALTY_RADIUS))
			_check("Marcaje renderizado contiene el arco compartido extremo=%d lado=%d" % [end, index],
				rendered)
		var goal: Node3D = arena.get_node("HomeGoal" if end == -1 else "AwayGoal") as Node3D
		var post_count: int = 0
		for node: Node in goal.get_children():
			if node is not MeshInstance3D:
				continue
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.mesh is not BoxMesh:
				continue
			var box: BoxMesh = mesh.mesh as BoxMesh
			if is_equal_approx(box.size.y, Tuning.GOAL_HEIGHT + Tuning.POST_THICKNESS):
				post_count += 1
				_check("Poste mantiene abertura interior de 3 m extremo=%d poste=%d" % [end, post_count],
					is_equal_approx(absf(mesh.position.z), Tuning.GOAL_POST_CENTER_Z)
					and is_equal_approx(absf(mesh.position.z) - box.size.z * 0.5, Tuning.GOAL_WIDTH * 0.5)
					and is_equal_approx(box.size.x, Tuning.POST_THICKNESS))
		_check("Dos postes visibles por extremo=%d" % end, post_count == 2)
		var bar: MeshInstance3D = goal.get_node("Crossbar") as MeshInstance3D
		var bar_box: BoxMesh = bar.mesh as BoxMesh
		_check("Larguero mantiene abertura interior de 2 m extremo=%d" % end,
			is_equal_approx(bar.position.y - bar_box.size.y * 0.5, Tuning.GOAL_HEIGHT)
			and is_equal_approx(bar_box.size.z, Tuning.GOAL_POST_OUTER_Z * 2.0))
	var mirrored: bool = true
	for path_index: int in home.size():
		for point_index: int in home[path_index].size():
			var point: Vector3 = home[path_index][point_index]
			point.x = -point.x
			mirrored = mirrored and point.is_equal_approx(away[path_index][point_index])
	_check("Áreas idénticas al reflejar ejercicios entre ambas porterías", mirrored)
	_check("Escala física de cancha, balón y atleta permanece intacta",
		is_equal_approx(Tuning.COURT_LENGTH, 40.0) and is_equal_approx(Tuning.COURT_WIDTH, 20.0)
		and is_equal_approx(Tuning.BALL_RADIUS, 0.105) and is_equal_approx(Tuning.ACTOR_HEIGHT, 1.75))
	_arena_checks_completed = true


func _rendered_ribbon_point(vertices: PackedVector3Array, point: Vector3) -> bool:
	for index: int in range(0, vertices.size(), 6):
		if (vertices[index] + vertices[index + 2]).is_equal_approx(point * 2.0):
			return true
		if (vertices[index + 1] + vertices[index + 4]).is_equal_approx(point * 2.0):
			return true
	return false


func _test_bounded_leg_segments(view: AthleteView) -> void:
	var hip: Vector3 = Vector3(-0.10, 0.89, 0.0)
	var target: Vector3 = Vector3(-2.0, 0.08, -3.0)
	view._pose_leg(0, hip, target)
	var leg: Array = view._legs[0]
	var thigh: Node3D = leg[0] as Node3D
	var shin: Node3D = leg[1] as Node3D
	var shoe: Node3D = leg[3] as Node3D
	var ankle: Vector3 = shoe.position - AthleteView.SHOE_OFFSET
	var lengths: Vector2 = view._skin_view.rig.leg_lengths[0]
	_check("Contacto inalcanzable limita tobillo, no estira pierna",
		hip.distance_to(ankle) <= lengths.x + lengths.y - AthleteView.LIMB_EXTENSION_MARGIN + 0.00001
		and ankle.distance_to(target) > 1.0)
	_check("Muslo y espinilla mantienen longitudes articuladas",
		is_equal_approx(thigh.basis.y.length(), lengths.x)
		and is_equal_approx(shin.basis.y.length(), lengths.y))
	view._pose_leg(0, hip, hip)
	_check("Objetivo coincidente con cadera produce transformaciones finitas",
		thigh.transform.is_finite() and shin.transform.is_finite() and shoe.transform.is_finite())


func _test_dynamic_selection_marks() -> void:
	var views: Array[AthleteView] = []
	var identities: Array[String] = []
	for id: int in 10:
		var view: AthleteView = AthleteView.new()
		root.add_child(view)
		var home: bool = id % 2 == 0
		view.configure(id, Color("#172f4d") if home else Color("#c8c2b6"), id + 1)
		var selection: Label3D = view.get_node_or_null("HumanSelection") as Label3D
		_check("Capacidad de marca HOME, incluido portero: id=%d" % id, (selection != null) == home)
		if selection != null:
			_check("Sin selección inventada antes del snapshot: id=%d" % id, not selection.visible)
		var actor: Snapshot.ActorSnapshot = _selection_actor(id, id == 0)
		view.present(actor, actor, 1.0, 0.0, false, 0.0)
		views.append(view)
		identities.append(_athlete_identity(view))
	var previous_id: int = 0
	var transition: int = 0
	for selected_id: int in [0, 4, 2, 0]:
		var context: String = "paso=%d foco=%d" % [transition, selected_id]
		var visible_count: int = 0
		var visible_id: int = -1
		for id: int in 10:
			var before: Snapshot.ActorSnapshot = _selection_actor(id, id == previous_id)
			var actor: Snapshot.ActorSnapshot = _selection_actor(id, id == selected_id)
			var view: AthleteView = views[id]
			view.present(before, actor, 0.5, 0.0, false, 0.0)
			var selection: Label3D = view.get_node_or_null("HumanSelection") as Label3D
			if selection != null and selection.visible:
				visible_count += 1
				visible_id = id
				_check("Marca conserva forma y paleta al seleccionar %s id=%d" % [context, id],
					selection.text == "▼" and selection.modulate == Color("#e9d096")
					and selection.outline_modulate == Color("#182e40") and is_equal_approx(selection.position.y, 2.12))
			var marker: MeshInstance3D = view.get_node("TeamShape") as MeshInstance3D
			var ink: Color = (marker.material_override as StandardMaterial3D).albedo_color
			_check("Sólo el seleccionado resalta TeamShape: %s id=%d" % [context, id],
				ink == (Color("#eee8d8") if id == selected_id else Color("#314350")))
			_check("Foco no recrea vista, modelo, materiales, dorsal ni kit: %s id=%d" % [context, id],
				_athlete_identity(view) == identities[id])
			_check("Foco no añade colisiones a presentación: %s id=%d" % [context, id],
				view.find_children("*", "CollisionObject3D", true, false).is_empty()
				and view.find_children("*", "CollisionShape3D", true, false).is_empty())
		_check("Una sola marca usa snapshot actual, no el interpolado anterior: %s" % context,
			visible_count == 1 and visible_id == selected_id)
		if previous_id != selected_id:
			_check("Marca anterior oculta: %d -> %d" % [previous_id, selected_id],
				not (views[previous_id].get_node("HumanSelection") as Label3D).visible)
		previous_id = selected_id
		transition += 1
	for id: int in 10:
		var actor: Snapshot.ActorSnapshot = _selection_actor(id, false)
		views[id].present(actor, actor, 1.0, 0.0, false, 0.0)
		var selection: Label3D = views[id].get_node_or_null("HumanSelection") as Label3D
		_check("Desmarcar no conserva un ID cero implícito: id=%d" % id, selection == null or not selection.visible)
	var away: Snapshot.ActorSnapshot = _selection_actor(1, true)
	views[1].present(away, away, 1.0, 0.0, false, 0.0)
	_check("Flag humano indebido en AWAY no crea marca local",
		views[1].get_node_or_null("HumanSelection") == null
		and ((views[1].get_node("TeamShape") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == Color("#314350"))
	for view: AthleteView in views:
		view.free()
	_selection_checks_completed = true


func _selection_actor(id: int, controlled: bool) -> Snapshot.ActorSnapshot:
	var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	actor.actor_id = id
	actor.team_id = Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY
	actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
	actor.human_controlled = controlled
	actor.position = Vector3(float(id) - 5.0, 0.0, 0.0)
	actor.velocity = Vector3.ZERO
	actor.facing_yaw = 0.0
	return actor


func _athlete_identity(view: AthleteView) -> String:
	var body: Node3D = view.get_node("ArticulatedBody") as Node3D
	var meshes: Array[Dictionary] = []
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		meshes.append({
			"node": mesh.get_instance_id(), "mesh": mesh.mesh.get_instance_id(),
			"materials": AthleteMaterials.surface_identity(mesh), "transform": mesh.transform,
		})
	var team_shape: MeshInstance3D = view.get_node("TeamShape") as MeshInstance3D
	var selection: Label3D = view.get_node_or_null("HumanSelection") as Label3D
	return var_to_str({
		"view": view.get_instance_id(), "body": body.get_instance_id(),
		"actor": view.actor_id, "dorsal": view.dorsal, "kit": view.kit_color,
		"back_number": (body.get_node("BackNumber") as Label3D).text,
		"front_number": (body.get_node("FrontNumber") as Label3D).text,
		"meshes": meshes, "team_shape": team_shape.get_instance_id(),
		"team_mesh": team_shape.mesh.get_instance_id(), "team_material": team_shape.material_override.get_instance_id(),
		"selection": selection.get_instance_id() if selection != null else 0,
	})


func _check(name: String, passed: bool) -> void:
	if _check_names.has(name):
		_duplicate_checks.append(name)
	_check_names[name] = true
	_checks.append({"name": name, "passed": passed})
	print("[%s] %s" % ["OK  " if passed else "FALLO", name])


func _report() -> void:
	if _reported:
		return
	_reported = true
	_check("Escenarios de marca dinámica completados", _selection_checks_completed)
	_check("Escenarios de áreas y postes completados", _arena_checks_completed)
	_check("Identificadores de comprobación visual únicos", _duplicate_checks.is_empty())
	var native: Dictionary = _native_errors.snapshot()
	_check("Sin errores nativos inesperados en la prueba visual",
		native["error_count"] == 0 and native["script_error_count"] == 0 and native["shader_error_count"] == 0)
	var passed: int = 0
	var failures: Array = []
	for c: Dictionary in _checks:
		if c["passed"]:
			passed += 1
		else:
			failures.append(c["name"])
	var total: int = _checks.size()
	var ok: bool = failures.is_empty()
	# Prefijo literal descubierto por el allrunner de Ferro; formato normalizado.
	print("FUTSAL_VISUAL_TESTS " + JSON.stringify({
		"ok": ok, "passed": passed, "total": total,
		"failures": failures,
		"checks": _checks, "duplicate_checks": _duplicate_checks,
		"native_errors": native,
		"headless": DisplayServer.get_name() == "headless",
	}))
	OS.remove_logger(_native_errors)
	quit(0 if ok else 1)
