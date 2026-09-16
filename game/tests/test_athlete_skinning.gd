extends SceneTree
## Comprueba el recurso real y su skinning; no sustituye capturas ni prueba de FPS.
## godot --headless --path game --script res://tests/test_athlete_skinning.gd

const Athlete = preload("res://match/presentation/athletes/athlete_view.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const MatchHost = preload("res://match/match.gd")
const MatchScene = preload("res://match/match.tscn")
const VisualTests = preload("res://tests/test_match_visuals.gd")

var _checks: Array[Dictionary] = []
var _native: VisualTests.NativeErrors = VisualTests.NativeErrors.new()
var _views: Array[Athlete] = []
var _started_ms: int = 0
var _reported: bool = false
var _geometry_metrics: Array[Dictionary] = []


func _initialize() -> void:
	OS.add_logger(_native)
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if not _reported and Time.get_ticks_msec() - _started_ms > 30000:
		_check("Skinning termina antes del watchdog", false)
		_report()
	return false


func _run() -> void:
	_check("Mascara rechaza pesos vacios", not _valid_kit_mask(Color(0, 0, 0, 0)))
	_check("Mascara rechaza suma incompatible con cuantizacion",
		not _valid_kit_mask(Color(0.25, 0.25, 0, 0)))
	_check("Mascara rechaza canales no finitos", not _valid_kit_mask(Color(NAN, 0, 0, 1)))
	_check("Mascara normaliza el error de un byte observado en Godot",
		_valid_kit_mask(Color(243.0 / 255.0, 11.0 / 255.0, 0, 0)))
	var skeleton_ids: Dictionary[int, bool] = {}
	var shared_meshes: Array[int] = []
	for id: int in 10:
		var view: Athlete = Athlete.new()
		root.add_child(view)
		_views.append(view)
		var colour: Color = Color("#172f4d") if id % 2 == 0 else Color("#c8c2b6")
		var configured: Error = view.configure(id, colour, id + 1)
		_check("configure devuelve OK id=%d" % id, configured == OK)
		if configured != OK:
			_report()
			return
		var skin: Node3D = view._skin_view
		var skeleton: Skeleton3D = view._skin_view.skeleton
		skeleton_ids[skeleton.get_instance_id()] = true
		_check("Un esqueleto compartible y propio por instancia id=%d" % id,
			skeleton.get_bone_count() >= 20 and skeleton.get_bone_count() <= 80)
		_check("Modelo visible, sin cuerpos de primitivas id=%d" % id,
			view._skin_view._model.visible and not view._skin_view.meshes.is_empty()
			and view._body.find_children("*", "MeshInstance3D", true, false).size()
				== view._skin_view.meshes.size())
		_check("Modelo sin colisiones de presentacion id=%d" % id,
			skin.find_children("*", "CollisionObject3D", true, false).is_empty()
			and skin.find_children("*", "CollisionShape3D", true, false).is_empty())
		var mesh_ids: Array[int] = []
		for mesh: MeshInstance3D in view._skin_view.meshes:
			mesh_ids.append(mesh.mesh.get_instance_id())
		if id == 0:
			shared_meshes = mesh_ids
			_test_mesh_data(view)
		else:
			_check("Geometria importada reutilizada id=%d" % id, mesh_ids == shared_meshes)
		var kit: ShaderMaterial = view._skin_view._materials[&"AthleteKit"] as ShaderMaterial
		_check("Colores textiles corresponden al equipo id=%d" % id,
			kit != null and kit.get_shader_parameter("primary_color") == colour
			and kit.get_shader_parameter("accent_color")
				== (Color("#eee8d8") if id % 2 == 0 else Color("#172f4d")))
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = Snapshot.Team.HOME if id % 2 == 0 else Snapshot.Team.AWAY
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.position = Vector3(float(id) - 5.0, 0, 2.0)
		actor.facing_yaw = float(id) * 0.37
		actor.velocity = Basis(Vector3.UP, actor.facing_yaw) * Vector3(0, 0, -8.0)
		for frame: int in 12:
			view.present(actor, actor, 1.0, 1.0 / 60.0, false, 0.0)
			_check("Pies y palmas reales siguen los targets id=%d frame=%d" % [id, frame],
				_contacts_match(view))
		view.reset_pose()
		_check("Reset conserva contactos reales id=%d" % id, _contacts_match(view))
	_check("Diez esqueletos independientes", skeleton_ids.size() == 10)
	_test_vertex_deformation(_views[0])
	_test_anatomical_ik(_views[0])
	_test_near_parallel_legs(_views[0])
	_test_boot_geometry(_views[0])
	_test_shot_surface(_views[0])
	_test_palm_surface(_views[2])
	_test_reconcile_camera()
	_report()


func _test_mesh_data(view: Athlete) -> void:
	var triangles: int = 0
	var minimum: Vector3 = Vector3(INF, INF, INF)
	var maximum: Vector3 = Vector3(-INF, -INF, -INF)
	for mesh: MeshInstance3D in view._skin_view.meshes:
		var connected: bool = mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) == view._skin_view.skeleton
		_check("Mesh enlazado al esqueleto real " + mesh.name, connected)
		if not connected:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var label: String = "%s superficie=%d" % [mesh.name, surface]
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			for slot: BaseMaterial3D.TextureParam in [
				BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS,
			]:
				var texture: Texture2D = source.get_texture(slot) if source != null else null
				var image: Image = texture.get_image() if texture != null else null
				_check("Mapa PBR RGBA8 opaco sin conversion de hardware %s slot=%d" % [label, slot],
					image != null and image.get_format() == Image.FORMAT_RGBA8
					and image.detect_alpha() == Image.ALPHA_NONE)
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			_check("UV y normales por vertice " + label,
				not vertices.is_empty() and uv.size() == vertices.size() and normals.size() == vertices.size())
			var skin_shape: bool = bones.size() == vertices.size() * 4 and weights.size() == bones.size()
			_check("Cuatro influencias como maximo " + label, skin_shape)
			var finite_geometry: bool = true
			var normalized_weights: bool = skin_shape
			if skin_shape:
				for vertex: int in vertices.size():
					var total: float = 0.0
					for influence: int in 4:
						var offset: int = vertex * 4 + influence
						var weight: float = weights[offset]
						normalized_weights = normalized_weights and is_finite(weight) and weight >= 0.0 \
							and bones[offset] >= 0 and bones[offset] < mesh.skin.get_bind_count()
						total += weight
					normalized_weights = normalized_weights and absf(total - 1.0) < 0.001
			for vertex: Vector3 in vertices:
				finite_geometry = finite_geometry and vertex.is_finite()
				var local: Vector3 = view.to_local(mesh.to_global(vertex))
				minimum = minimum.min(local)
				maximum = maximum.max(local)
			_check("Vertices finitos " + label, finite_geometry)
			_check("Pesos normalizados e indices validos " + label, normalized_weights)
			var material: Material = mesh.get_active_material(surface)
			if material is ShaderMaterial:
				var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				var valid_mask: bool = colours.size() == vertices.size()
				for colour: Color in colours:
					valid_mask = valid_mask and _valid_kit_mask(colour)
				_check("Mascara textil RGBA8 y pesos efectivos normalizados " + label, valid_mask)
	_check("Presupuesto de geometria por atleta", triangles > 1000 and triangles <= 60000)
	_check("Atleta adulto en metros y pies cerca del suelo",
		maximum.y - minimum.y >= 1.65 and maximum.y - minimum.y <= 1.85
		and minimum.y >= -0.02 and minimum.y <= 0.08)


func _valid_kit_mask(colour: Color) -> bool:
	for channel: float in [colour.r, colour.g, colour.b, colour.a]:
		if not is_finite(channel) or channel < 0.0 or channel > 1.0:
			return false
	var weights: Vector4 = Vector4(colour.r, colour.g, colour.b, colour.a)
	var total: float = weights.dot(Vector4.ONE)
	# ArrayMesh convierte COLOR_0 a RGBA8; el shader normaliza tras esa cuantizacion.
	if total <= 0.0 or absf(total - 1.0) > 4.0 / 255.0 + 0.000001:
		return false
	weights /= total
	return absf(weights.dot(Vector4.ONE) - 1.0) < 0.000001


func _contacts_match(view: Athlete) -> bool:
	var skeleton: Skeleton3D = view._skin_view.skeleton
	for side: int in 2:
		var suffix: String = "_L" if side == 0 else "_R"
		var foot: int = skeleton.find_bone("Foot" + suffix)
		var palm: int = skeleton.find_bone("Palm" + suffix)
		if foot < 0 or palm < 0:
			return false
		if view._gesture_kind == Rules.GestureKind.NONE:
			var shoulder: Vector3 = view._skin_view.rig.joint_position(side, "UpperArm")
			var elbow: Vector3 = view._body.to_local(skeleton.to_global(
				skeleton.get_bone_global_pose(skeleton.find_bone("Forearm" + suffix)).origin))
			if elbow.y > shoulder.y:
				return false
		var ankle_world: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
		var palm_world: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(palm).origin)
		if ankle_world.distance_to(view._body.to_global(view._posed_ankles[side])) > 0.0001 \
				or palm_world.distance_to((view._arms[side][2] as Node3D).global_position) > 0.0001:
			return false
		for chain: PackedStringArray in [
			PackedStringArray(["Thigh", "Shin", "Foot"]),
			PackedStringArray(["UpperArm", "Forearm", "Hand", "Palm"]),
		]:
			for segment: int in range(chain.size() - 1):
				var from: int = skeleton.find_bone(chain[segment] + suffix)
				var to: int = skeleton.find_bone(chain[segment + 1] + suffix)
				var actual: float = skeleton.get_bone_global_pose(from).origin.distance_to(
					skeleton.get_bone_global_pose(to).origin)
				var rest: float = skeleton.get_bone_global_rest(from).origin.distance_to(
					skeleton.get_bone_global_rest(to).origin)
				if absf(actual - rest) > 0.0001:
					return false
		for segment: int in [0, 1]:
			if absf((view._arms[side][segment] as Node3D).basis.y.length()
					- view._skin_view.rig.arm_lengths[side][segment]) > 0.0001:
				return false
	return true


func _test_vertex_deformation(view: Athlete) -> void:
	view.reset_pose()
	var selected_mesh: MeshInstance3D
	var selected_arrays: Array = []
	var selected_vertex: int = -1
	for mesh: MeshInstance3D in view._skin_view.meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for offset: int in weights.size():
				if weights[offset] < 0.75:
					continue
				var bone: int = _bone_index(mesh, view._skin_view.skeleton, bones[offset])
				if bone >= 0 and view._skin_view.skeleton.get_bone_name(bone) == "Foot_L":
					selected_mesh = mesh
					selected_arrays = arrays
					selected_vertex = offset / 4
					break
			if selected_vertex >= 0:
				break
		if selected_vertex >= 0:
			break
	_check("Malla contiene vertices realmente pesados al pie izquierdo", selected_vertex >= 0)
	if selected_vertex < 0:
		return
	var before: Vector3 = _skinned_vertex(view, selected_mesh, selected_arrays, selected_vertex)
	view._pose_leg(0, Vector3(-0.10, 0.89, 0), Vector3(-0.18, 0.30, -0.25))
	var changed: Vector3 = _skinned_vertex(view, selected_mesh, selected_arrays, selected_vertex)
	_check("La piel real se deforma, no solo los nodos de contacto",
		before.is_finite() and changed.is_finite() and before.distance_to(changed) > 0.10)
	view.reset_pose()
	var restored: Vector3 = _skinned_vertex(view, selected_mesh, selected_arrays, selected_vertex)
	_check("Reset restaura el vertice de la malla real", restored.distance_to(before) < 0.0001)


func _test_anatomical_ik(view: Athlete) -> void:
	var origin: Vector3 = Vector3(0, 1, 0)
	var chains: Array[Vector2] = [view._skin_view.rig.leg_lengths[0], view._skin_view.rig.arm_lengths[0]]
	for chain: int in chains.size():
		var lengths: Vector2 = chains[chain]
		var offsets: Array[Vector3] = [
			Vector3.ZERO, Vector3(3, 2, -4), Vector3(0, -0.40, -0.08),
			Vector3(0.02, 0, -1).normalized() * 0.5, Vector3(-0.02, 0, -1).normalized() * 0.5,
			Vector3(0.02, 0, 1).normalized() * 0.5, Vector3(-0.02, 0, 1).normalized() * 0.5,
		]
		for index: int in offsets.size():
			var pole: Vector3 = Vector3.DOWN if index < 3 else Vector3.FORWARD
			var pose: Array[Vector3] = view._solve_limb(origin, origin + offsets[index], lengths, pole)
			_check("IK desigual finita y sin estirar cadena=%d caso=%d" % [chain, index],
				pose[0].is_finite() and pose[1].is_finite()
				and absf(origin.distance_to(pose[0]) - lengths.x) < 0.0001
				and absf(pose[0].distance_to(pose[1]) - lengths.y) < 0.0001)


func _test_near_parallel_legs(view: Athlete) -> void:
	view.reset_pose()
	for side: int in 2:
		var hip: Vector3 = view._skin_view.rig.joint_position(side, "Thigh")
		for lateral: float in [-0.02, 0.0, 0.02]:
			for forward: float in [-1.0, 1.0]:
				view._pose_leg(side, hip, hip + Vector3(lateral, 0, forward).normalized() * 0.5)
				_check("Huesos reales conservan longitud con polo casi paralelo lado=%d x=%s z=%s" % [
					side, str(lateral), str(forward)], _contacts_match(view))
	view.reset_pose()


func _test_reconcile_camera() -> void:
	var host: MatchHost = MatchScene.instantiate() as MatchHost
	root.add_child(host)
	host.set_process(false)
	host.set_physics_process(false)
	host.get_simulation().set_physics_process(false)
	host._input_adapter.set_physics_process(false)
	_check("Reconciliacion parte del micro real", host.start_match(Setup.new()) == OK)
	_check("Autoridad pasa a preview sin llamar start_match del host",
		host.get_simulation().reset(Setup.preview_5v5()) == OK)
	host._snap_camera = false
	host._physics_process(0.0)
	_check("Ruta fisica reconstruye diez atletas y solicita snap de camara",
		host._athletes.size() == 10 and host._snap_camera)
	host._snap_camera = false
	host._physics_process(0.0)
	_check("Ruta fisica estable no reinicia camara cada tick", not host._snap_camera)
	host.free()


func _test_boot_geometry(view: Athlete) -> void:
	view.reset_pose()
	for side: int in 2:
		var points: PackedVector3Array = _boot_vertices(view, side)
		_check("Geometria real suficiente de bota lado=%d" % side, points.size() > 100)
		if points.is_empty():
			continue
		var minimum: Vector3 = Vector3(INF, INF, INF)
		for point: Vector3 in points:
			minimum = minimum.min(view.to_local(point))
		var toe_x: float = 0.0
		var toe_count: int = 0
		for point: Vector3 in points:
			var local: Vector3 = view.to_local(point)
			if local.z <= minimum.z + 0.003:
				toe_x += local.x
				toe_count += 1
		var ankle: Vector3 = view._posed_ankles[side]
		var lateral_error: float = absf(toe_x / float(toe_count) - ankle.x)
		var reach_error: float = absf(ankle.z - minimum.z - Athlete.SHOE_TOE_REACH)
		_geometry_metrics.append({
			"side": side, "sole_min_y": minimum.y,
			"toe_lateral_error": lateral_error, "toe_reach_error": reach_error,
		})
		_check("Suela real sobre el suelo, no enterrada lado=%d" % side,
			minimum.y >= -0.003 and minimum.y <= 0.006)
		_check("Puntera real alineada, sin apertura de pose A lado=%d" % side, lateral_error < 0.012)
		_check("Alcance real de puntera calibrado lado=%d" % side, reach_error < 0.003)
		var sign_x: float = -1.0 if side == 0 else 1.0
		view._pose_leg(side, Vector3(sign_x * 0.10, 0.89, 0), Vector3(sign_x * 0.115, 0.08, 0))
		var old_minimum: float = INF
		for point: Vector3 in _boot_vertices(view, side):
			old_minimum = minf(old_minimum, view.to_local(point).y)
		_check("Oraculo detecta el hundimiento con geometria anterior lado=%d" % side, old_minimum < -0.02)
		view.reset_pose()


func _test_shot_surface(view: Athlete) -> void:
	view.reset_pose()
	var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	actor.actor_id = view.actor_id
	actor.team_id = Snapshot.Team.HOME
	actor.role = Snapshot.Role.FIELD
	actor.position = Vector3.ZERO
	actor.forward = Vector3.FORWARD
	actor.attack_direction = Vector3.FORWARD
	actor.gesture_kind = Rules.GestureKind.FOOT_KICK
	actor.gesture_started_tick = 10
	actor.gesture_duration_ticks = 24
	actor.gesture_direction = Vector3.FORWARD
	actor.gesture_contact_position = Vector3(0, Tuning.BALL_RADIUS, -0.48)
	var state: Snapshot = Snapshot.new()
	state.tick = 10
	state.phase = Snapshot.Phase.PLAYING
	state.ball_position = actor.gesture_contact_position
	state.actors.append(actor)
	view.sync_context(state, state)
	view.present(actor, actor, 1.0, 0.0, false, 0.0)
	var tangent: Vector3 = actor.gesture_contact_position - actor.gesture_direction * Tuning.BALL_RADIUS
	var contact_error: float = INF
	var nearest_ball: float = INF
	for vertex: Vector3 in _boot_vertices(view, view._contact_leg):
		contact_error = minf(contact_error, vertex.distance_to(tangent))
		nearest_ball = minf(nearest_ball, vertex.distance_to(actor.gesture_contact_position))
	_geometry_metrics.append({"shot_contact_error": contact_error, "shot_nearest_ball_surface": nearest_ball})
	_check("Puntera deformada real a menos de tres centimetros del contacto", contact_error <= 0.03)
	_check("Bota real toca sin atravesar profundamente el balon",
		absf(nearest_ball - Tuning.BALL_RADIUS) <= 0.03)
	_check("Tiro mantiene longitudes y targets del esqueleto real", _contacts_match(view))
	view.reset_pose()


func _boot_vertices(view: Athlete, side: int) -> PackedVector3Array:
	var suffix: String = "_L" if side == 0 else "_R"
	return _weighted_vertices(view, &"AthleteGearMesh", PackedStringArray(["Foot" + suffix, "Toe" + suffix]))


func _test_palm_surface(view: Athlete) -> void:
	view.reset_pose()
	var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
	actor.actor_id = view.actor_id
	actor.team_id = Snapshot.Team.HOME
	actor.role = Snapshot.Role.KEEPER
	actor.forward = Vector3.FORWARD
	actor.attack_direction = Vector3.FORWARD
	actor.ball_in_hands = true
	var state: Snapshot = Snapshot.new()
	state.tick = 20
	state.phase = Snapshot.Phase.PLAYING
	state.ball_position = Vector3(0, 1.03, -0.24)
	state.ball_owner_id = actor.actor_id
	state.actors.append(actor)
	view.sync_context(state, state)
	view.present(actor, actor, 1.0, 0.0, true, 0.0)
	var skeleton: Skeleton3D = view._skin_view.skeleton
	for side: int in 2:
		var suffix: String = "_L" if side == 0 else "_R"
		var points: PackedVector3Array = _weighted_vertices(
			view, &"AthleteSkinMesh", PackedStringArray(["Hand" + suffix]), 0.5)
		var bone: int = skeleton.find_bone("Palm" + suffix)
		var palm: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		var surface_error: float = _nearest_vertex_distance(points, palm)
		var ball_distance: float = _nearest_vertex_distance(points, state.ball_position)
		_geometry_metrics.append({"palm_side": side, "palm_surface_error": surface_error, "palm_ball_distance": ball_distance})
		_check("Mano contiene piel real pesada lado=%d" % side, points.size() > 30)
		_check("Locator palmar sobre piel real a menos de un centimetro lado=%d" % side, surface_error <= 0.01)
		_check("Piel de palma real a menos de un centimetro del balon lado=%d" % side,
			absf(ball_distance - Tuning.BALL_RADIUS) <= 0.01)
		var original: Vector3 = skeleton.get_bone_pose_position(bone)
		skeleton.set_bone_pose_position(bone, original + Vector3(0.30, 0, 0))
		var displaced: Vector3 = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		_check("Oraculo detecta locator palmar separado de la piel lado=%d" % side,
			_nearest_vertex_distance(points, displaced) > 0.10)
		skeleton.set_bone_pose_position(bone, original)
	_check("Agarre mantiene longitudes y targets del esqueleto real", _contacts_match(view))
	view.reset_pose()


func _nearest_vertex_distance(points: PackedVector3Array, target: Vector3) -> float:
	var distance: float = INF
	for point: Vector3 in points:
		distance = minf(distance, point.distance_to(target))
	return distance


func _weighted_vertices(view: Athlete, mesh_name: StringName, bone_names: PackedStringArray,
		minimum_weight: float = 0.99) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for mesh: MeshInstance3D in view._skin_view.meshes:
		if mesh.name != mesh_name:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for index: int in vertices.size():
				var matching_weight: float = 0.0
				for influence: int in 4:
					var offset: int = index * 4 + influence
					if weights[offset] <= 0.0:
						continue
					var bone: int = _bone_index(mesh, view._skin_view.skeleton, bones[offset])
					if bone < 0:
						push_error("Weighted surface references a missing skeleton bone.")
						return PackedVector3Array()
					var name: String = view._skin_view.skeleton.get_bone_name(bone)
					if name in bone_names:
						matching_weight += weights[offset]
				if matching_weight >= minimum_weight:
					points.append(_skinned_vertex(view, mesh, arrays, index))
	return points


func _skinned_vertex(view: Athlete, mesh: MeshInstance3D, arrays: Array, index: int) -> Vector3:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var position: Vector3 = Vector3.ZERO
	for influence: int in 4:
		var offset: int = index * 4 + influence
		if weights[offset] <= 0.0:
			continue
		var bind: int = bones[offset]
		var bone: int = _bone_index(mesh, view._skin_view.skeleton, bind)
		if bone < 0:
			push_error("Skin bind references a missing skeleton bone.")
			return Vector3(INF, INF, INF)
		position += weights[offset] * (
			view._skin_view.skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index])
	return mesh.to_global(position)


func _bone_index(mesh: MeshInstance3D, skeleton: Skeleton3D, bind: int) -> int:
	var name: StringName = mesh.skin.get_bind_name(bind)
	return skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)


func _check(name: String, passed: bool) -> void:
	_checks.append({"name": name, "passed": passed})


func _report() -> void:
	if _reported:
		return
	_reported = true
	for view: Athlete in _views:
		view.free()
	_views.clear()
	var errors: Dictionary = _native.snapshot()
	_check("Sin errores nativos de skinning", errors["error_count"] == 0
		and errors["script_error_count"] == 0 and errors["shader_error_count"] == 0)
	var failures: Array[String] = []
	for check: Dictionary in _checks:
		if not check["passed"]:
			failures.append(check["name"])
	print("FUTSAL_ATHLETE_SKINNING_TESTS " + JSON.stringify({
		"ok": failures.is_empty(), "passed": _checks.size() - failures.size(),
		"total": _checks.size(), "checks": _checks, "failures": failures,
		"native_errors": errors, "headless": DisplayServer.get_name() == "headless",
		"geometry_metrics": _geometry_metrics,
		"scope": "resource and skeletal deformation; no artistic approval or FPS measurement",
	}))
	OS.remove_logger(_native)
	quit(0 if failures.is_empty() else 1)
