class_name WorldAimGuide
extends Node3D
## Flecha de presentación para query_human_launch(); no consulta input ni simula trayectorias.

const Launch = preload("res://match/simulation/match_launch.gd")
const Rules = preload("res://match/simulation/match_rule_types.gd")
const INVALID_SOLUTION: String = "WorldAimGuide.present: solución o posición de render no válida."
# Escala gráfica de velocidad, no distancia de llegada ni predicción de alcance.
const SPEED_LENGTH_SCALE: float = 0.10
const MAX_LENGTH: float = 4.0
const BALL_GAP: float = 0.18
const HEIGHT_OFFSET: float = 0.035

var _arrow: Node3D
var _shaft: MeshInstance3D
var _head: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_build_arrow()
	clear()


func present(solution: Launch.Solution, render_ball_position: Vector3, enabled: bool) -> void:
	if not enabled:
		clear()
		return
	if solution == null:
		push_error(INVALID_SOLUTION)
		clear()
		return
	if solution.error != OK:
		if solution.reason.is_empty():
			push_error(INVALID_SOLUTION)
		clear()
		return
	if solution.actor_id < 0 or solution.actor_id > 9:
		push_error(INVALID_SOLUTION)
		clear()
		return
	# La consulta autoriza al HOME seleccionado; nunca revelar una guía de los IDs rivales.
	if solution.actor_id % 2 != 0:
		clear()
		return
	if not _valid_solution(solution, render_ball_position):
		push_error(INVALID_SOLUTION)
		clear()
		return
	if not is_node_ready():
		return
	var direction: Vector3 = solution.direction
	var length: float = minf(solution.speed * SPEED_LENGTH_SCALE, MAX_LENGTH)
	var head_length: float = minf(0.38, length * 0.4)
	var shaft_length: float = length - head_length
	_arrow.global_transform = Transform3D(
		Basis(direction, Vector3.UP, direction.cross(Vector3.UP)),
		render_ball_position + Vector3.UP * HEIGHT_OFFSET
	)
	_shaft.position = Vector3(BALL_GAP + shaft_length * 0.5, 0.0, 0.0)
	_shaft.scale = Vector3(shaft_length, 1.0, 0.10 + 0.04 * solution.power)
	_head.position = Vector3(BALL_GAP + shaft_length, 0.01, 0.0)
	_head.scale = Vector3(head_length, 1.0, 0.32 + 0.12 * solution.power)
	_material.albedo_color = Color("#ccb990").lerp(Color("#ead095"), solution.power)
	if not solution.executable:
		_material.albedo_color = _material.albedo_color.lerp(Color("#aebbc8"), 0.35)
	_arrow.set_meta("physical_origin", solution.origin)
	_arrow.set_meta("launch_velocity", solution.velocity)
	_arrow.set_meta("launch_power", solution.power)
	_arrow.set_meta("effective_target_actor_id", solution.effective_target_actor_id)
	_arrow.set_meta("actor_id", solution.actor_id)
	_arrow.set_meta("executable", solution.executable)
	_arrow.show()


func clear() -> void:
	if is_instance_valid(_arrow):
		_arrow.hide()
		for key: StringName in _arrow.get_meta_list():
			_arrow.remove_meta(key)


func _valid_solution(solution: Launch.Solution, render_position: Vector3) -> bool:
	return (render_position.is_finite() and solution.origin.is_finite()
		and solution.direction.is_finite() and solution.velocity.is_finite()
		and absf(solution.direction.y) <= 0.0001
		and absf(solution.direction.length_squared() - 1.0) <= 0.001
		and is_finite(solution.speed) and solution.speed > 0.0
		and is_finite(solution.power) and solution.power >= 0.0 and solution.power <= 1.0
		and solution.velocity.length_squared() > 0.0
		and absf(solution.velocity.length() - solution.speed) <= maxf(0.001, solution.speed * 0.001)
		and Vector3(solution.velocity.x, 0.0, solution.velocity.z).normalized().dot(solution.direction) >= 0.999
		and solution.launch_kind in [Rules.LaunchKind.FOOT_PASS, Rules.LaunchKind.FOOT_SHOT, Rules.LaunchKind.KEEPER_THROW]
		and (solution.launch_kind != Rules.LaunchKind.FOOT_SHOT or solution.effective_target_actor_id == -1)
		and solution.tick >= 0 and solution.effective_target_actor_id >= -1
		and solution.effective_target_actor_id <= 9
		and (solution.effective_target_actor_id == -1 or (solution.effective_target_actor_id % 2 == 0
			and solution.effective_target_actor_id != solution.actor_id)))


func _build_arrow() -> void:
	_arrow = Node3D.new()
	_arrow.name = "Arrow"
	add_child(_arrow)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color("#ead095")
	_material.roughness = 1.0
	var shaft_mesh: BoxMesh = BoxMesh.new()
	shaft_mesh.size = Vector3(1.0, 0.014, 1.0)
	_shaft = _mesh_instance("Shaft", shaft_mesh)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, -0.5), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.5),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var head_mesh: ArrayMesh = ArrayMesh.new()
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_head = _mesh_instance("Head", head_mesh)


func _mesh_instance(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_arrow.add_child(instance)
	return instance
