extends RefCounted
## Geometría original y provisional de G1; nunca crea cuerpos físicos.


static func material(color: Color, roughness: float = 0.8) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	return result


static func mesh_node(parent: Node3D, node_name: String, mesh: Mesh, surface: Material,
		at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	result.name = node_name
	result.mesh = mesh
	result.material_override = surface
	result.position = at
	parent.add_child(result)
	return result


static func box(parent: Node3D, node_name: String, size: Vector3, at: Vector3,
		surface: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return mesh_node(parent, node_name, mesh, surface, at)


static func ellipsoid(parent: Node3D, node_name: String, size: Vector3, at: Vector3,
		surface: Material) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 20
	mesh.rings = 12
	var result: MeshInstance3D = mesh_node(parent, node_name, mesh, surface, at)
	result.scale = size
	return result


## Cada anillo es (altura, radio X, radio Z), desde abajo hacia arriba.
static func profile(rings: Array[Vector3], segments: int = 20) -> ArrayMesh:
	var vertices: PackedVector3Array = []
	var normals: PackedVector3Array = []
	var indices: PackedInt32Array = []
	for row: int in rings.size():
		var section: Vector3 = rings[row]
		var before: Vector3 = rings[maxi(0, row - 1)]
		var after: Vector3 = rings[mini(rings.size() - 1, row + 1)]
		var height: float = maxf(0.001, after.x - before.x)
		for column: int in segments:
			var angle: float = TAU * float(column) / float(segments)
			var x: float = cos(angle)
			var z: float = sin(angle)
			vertices.append(Vector3(x * section.y, section.x, z * section.z))
			var slope: float = ((after.y - before.y) * x * x +
				(after.z - before.z) * z * z) / height
			normals.append(Vector3(x / maxf(section.y, 0.01), -slope * 8.0,
				z / maxf(section.z, 0.01)).normalized())
			if row < rings.size() - 1:
				var a: int = row * segments + column
				var b: int = row * segments + (column + 1) % segments
				var c: int = a + segments
				var d: int = b + segments
				indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func circle(radius: float, center: Vector3 = Vector3.ZERO,
		segments: int = 64) -> PackedVector3Array:
	var points: PackedVector3Array = []
	for index: int in segments + 1:
		var angle: float = TAU * float(index) / float(segments)
		points.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	return points


static func ribbons(paths: Array[PackedVector3Array], width: float) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for points: PackedVector3Array in paths:
		for index: int in points.size() - 1:
			var from: Vector3 = points[index]
			var to: Vector3 = points[index + 1]
			var side: Vector3 = (to - from).cross(Vector3.UP).normalized() * width * 0.5
			_triangle(surface, from - side, to - side, from + side, Vector3.UP)
			_triangle(surface, to - side, to + side, from + side, Vector3.UP)
	return surface.commit()


static func rod(surface: SurfaceTool, from: Vector3, to: Vector3, radius: float,
		sides: int = 5) -> void:
	var direction: Vector3 = (to - from).normalized()
	var right: Vector3 = direction.cross(Vector3.FORWARD)
	if right.length_squared() < 0.01:
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var tangent: Vector3 = direction.cross(right).normalized()
	for index: int in sides:
		var angle: float = TAU * float(index) / float(sides)
		var next: float = TAU * float(index + 1) / float(sides)
		var a: Vector3 = (right * cos(angle) + tangent * sin(angle)) * radius
		var b: Vector3 = (right * cos(next) + tangent * sin(next)) * radius
		var normal: Vector3 = (a + b).normalized()
		_triangle(surface, from + a, from + b, to + a, normal)
		_triangle(surface, from + b, to + b, to + a, normal)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		normal: Vector3) -> void:
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.add_vertex(c)
