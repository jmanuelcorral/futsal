extends RefCounted


static func surface_identity(mesh: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface: int in mesh.mesh.get_surface_count():
		var material: Material = mesh.get_active_material(surface)
		if material == null:
			push_error("Athlete test found an unbound material surface.")
			return []
		var identity: Dictionary = {"id": material.get_instance_id()}
		if material is BaseMaterial3D:
			var pbr: BaseMaterial3D = material as BaseMaterial3D
			identity["colour"] = pbr.albedo_color
			identity["roughness"] = pbr.roughness
			identity["metallic"] = pbr.metallic
		elif material is ShaderMaterial:
			var shader: ShaderMaterial = material as ShaderMaterial
			identity["shader"] = shader.shader.get_instance_id()
			for parameter: String in [
				"primary_color", "secondary_color", "accent_color", "trim_color",
			]:
				identity[parameter] = shader.get_shader_parameter(parameter)
		result.append(identity)
	return result
