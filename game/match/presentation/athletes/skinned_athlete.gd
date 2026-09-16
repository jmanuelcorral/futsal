extends Node3D

const Rig = preload("res://match/presentation/athletes/athlete_rig.gd")
const KitShader = preload("res://match/presentation/athletes/athlete_kit.gdshader")
const ERROR_PREFIX: String = "SkinnedAthlete rejected invalid asset: "
const SKIN_TINTS: Array[Color] = [
	Color.WHITE, Color(1.02, 1.0, 0.98), Color(0.80, 0.77, 0.75), Color(0.94, 0.93, 0.92),
]
const TEXTURE_CHANNELS: Dictionary[int, Vector4] = {
	BaseMaterial3D.TEXTURE_CHANNEL_RED: Vector4(1, 0, 0, 0),
	BaseMaterial3D.TEXTURE_CHANNEL_GREEN: Vector4(0, 1, 0, 0),
	BaseMaterial3D.TEXTURE_CHANNEL_BLUE: Vector4(0, 0, 1, 0),
	BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: Vector4(0, 0, 0, 1),
	BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: Vector4(0.33333333, 0.33333333, 0.33333333, 0),
}

var rig: Rig = Rig.new()
var skeleton: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var _model: Node3D
var _materials: Dictionary[StringName, Material] = {}


func configure(scene: PackedScene, actor_id: int, primary: Color) -> Error:
	if scene == null or actor_id < 0 or actor_id > 9 or _model != null:
		return _reject("configuration")
	var instance: Node = scene.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		return _reject("model_root")
	_model = instance as Node3D
	_model.name = "CourtAthlete"
	_model.rotation.y = PI
	_model.visible = false
	add_child(_model)
	var skeletons: Array[Node] = _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		return _reject("skeleton_count")
	skeleton = skeletons[0] as Skeleton3D
	if not _model.find_children("*", "CollisionObject3D", true, false).is_empty() \
			or not _model.find_children("*", "CollisionShape3D", true, false).is_empty():
		return _reject("presentation_collision")
	var binding: Error = rig.bind(skeleton, self)
	if binding != OK:
		return binding
	var home: bool = actor_id % 2 == 0
	var contrast: Color = Color("#eee8d8") if home else Color("#172f4d")
	var shorts: Color = Color("#192e43") if home else Color("#dbd5c8")
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if not mesh.mesh is ArrayMesh or mesh.skin == null \
				or mesh.get_node_or_null(mesh.skeleton) != skeleton:
			return _reject("mesh_skin:" + mesh.name)
		for surface: int in mesh.mesh.get_surface_count():
			var source: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
			if source == null:
				return _reject("surface_material:" + mesh.name)
			var material_name: StringName = source.resource_name
			if material_name == &"AthleteKit" \
					and ((mesh.mesh as ArrayMesh).surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0:
				return _reject("kit_mask:" + mesh.name)
			if not _materials.has(material_name):
				var material: Material = _material(source, actor_id, primary, shorts, contrast)
				if material == null:
					return _reject("material_name:" + source.resource_name)
				_materials[material_name] = material
			mesh.set_surface_override_material(surface, _materials[material_name])
		mesh.custom_aabb = AABB(Vector3(-1.0, -0.3, -1.0), Vector3(2.0, 2.5, 2.0))
		meshes.append(mesh)
	if meshes.is_empty():
		return _reject("missing_mesh")
	_model.visible = true
	return OK


func _material(source: BaseMaterial3D, actor_id: int, primary: Color,
		shorts: Color, contrast: Color) -> Material:
	match source.resource_name:
		"AthleteSkin":
			var skin: BaseMaterial3D = source.duplicate() as BaseMaterial3D
			skin.albedo_color = source.albedo_color * SKIN_TINTS[actor_id % SKIN_TINTS.size()]
			skin.metallic = 0.0
			return skin
		"AthleteGear":
			return source.duplicate() as Material
		"AthleteKit":
			if not source is StandardMaterial3D:
				return null
			var original: StandardMaterial3D = source as StandardMaterial3D
			if not TEXTURE_CHANNELS.has(original.roughness_texture_channel) \
					or not TEXTURE_CHANNELS.has(original.ao_texture_channel):
				return null
			var kit: ShaderMaterial = ShaderMaterial.new()
			kit.shader = KitShader
			kit.set_shader_parameter("primary_color", primary)
			kit.set_shader_parameter("secondary_color", shorts)
			kit.set_shader_parameter("accent_color", contrast)
			kit.set_shader_parameter("trim_color", contrast)
			kit.set_shader_parameter("has_albedo_map", original.albedo_texture != null)
			kit.set_shader_parameter("has_normal_map", original.normal_enabled and original.normal_texture != null)
			kit.set_shader_parameter("has_roughness_map", original.roughness_texture != null)
			kit.set_shader_parameter("has_ao_map", original.ao_enabled and original.ao_texture != null)
			kit.set_shader_parameter("albedo_map", original.albedo_texture)
			kit.set_shader_parameter("normal_map", original.normal_texture)
			kit.set_shader_parameter("roughness_map", original.roughness_texture)
			kit.set_shader_parameter("ao_map", original.ao_texture)
			kit.set_shader_parameter("ao_uses_uv2", original.ao_on_uv2)
			kit.set_shader_parameter("ao_light_affect", original.ao_light_affect)
			kit.set_shader_parameter("fabric_roughness", original.roughness)
			kit.set_shader_parameter("fabric_normal_strength", original.normal_scale)
			kit.set_shader_parameter("roughness_channel", TEXTURE_CHANNELS[original.roughness_texture_channel])
			kit.set_shader_parameter("ao_channel", TEXTURE_CHANNELS[original.ao_texture_channel])
			return kit
	return null


func _reject(reason: String) -> Error:
	push_error(ERROR_PREFIX + reason)
	return ERR_INVALID_DATA
