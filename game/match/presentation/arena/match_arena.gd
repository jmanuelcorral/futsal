extends Node3D
## Pabellón G1 original. Pista 40 × 20; abertura de portería 3 × 2 metros.
## La pared de cámara y cubierta interpuestas no se dibujan durante el partido.

const Geometry = preload("res://match/presentation/geometry.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const CourtShader = preload("res://match/presentation/arena/court.gdshader")


func _ready() -> void:
	_build_court()
	_build_goals()
	_build_hall()
	_build_lighting()


func _build_court() -> void:
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(48.0, 28.0)
	var wood: ShaderMaterial = ShaderMaterial.new()
	wood.shader = CourtShader
	Geometry.mesh_node(self, "Court40x20", floor_mesh, wood)
	var paint: StandardMaterial3D = Geometry.material(Color("#f3eee3"), 0.65)
	var paths: Array[PackedVector3Array] = []
	paths.append(PackedVector3Array([
		Vector3(-20, 0.012, -10), Vector3(20, 0.012, -10),
		Vector3(20, 0.012, 10), Vector3(-20, 0.012, 10), Vector3(-20, 0.012, -10),
	]))
	paths.append(PackedVector3Array([Vector3(0, 0.012, -10), Vector3(0, 0.012, 10)]))
	paths.append(Geometry.circle(3.0, Vector3(0, 0.012, 0), 96))
	for end: float in [-1.0, 1.0]:
		paths.append_array(_penalty_area_paths(end))
		for distance: float in [Tuning.PENALTY_RADIUS, 10.0]:
			paths.append(Geometry.circle(0.055,
				Vector3(end * (Tuning.COURT_LENGTH * 0.5 - distance), 0.013, 0), 16))
	paths.append(Geometry.circle(0.055, Vector3(0, 0.013, 0), 16))
	var markings: MeshInstance3D = Geometry.mesh_node(self, "FutsalMarkings", Geometry.ribbons(paths, 0.08), paint)
	markings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _penalty_area_paths(end: float) -> Array[PackedVector3Array]:
	var goal_x: float = Tuning.COURT_LENGTH * 0.5
	var area_x: float = end * (goal_x - Tuning.PENALTY_RADIUS)
	var half_straight: float = Tuning.PENALTY_STRAIGHT_LENGTH * 0.5
	var paths: Array[PackedVector3Array] = [PackedVector3Array([
		Vector3(area_x, 0.012, -half_straight),
		Vector3(area_x, 0.012, half_straight),
	])]
	for side: float in [-1.0, 1.0]:
		var arc: PackedVector3Array = []
		for index: int in 49:
			var angle: float = PI * 0.5 * float(index) / 48.0
			arc.append(Vector3(end * (goal_x - Tuning.PENALTY_RADIUS * cos(angle)), 0.012,
				side * (Tuning.GOAL_POST_OUTER_Z + Tuning.PENALTY_RADIUS * sin(angle))))
		paths.append(arc)
	return paths


func _build_goals() -> void:
	var white: StandardMaterial3D = Geometry.material(Color("#eceee9"), 0.5)
	var dark: StandardMaterial3D = Geometry.material(Color("#243c48"), 0.7)
	var net: StandardMaterial3D = Geometry.material(Color("#a4aaa4"), 0.95)
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	for end: float in [-1.0, 1.0]:
		var goal: Node3D = Node3D.new()
		goal.name = "HomeGoal" if end < 0.0 else "AwayGoal"
		add_child(goal)
		var x: float = end * Tuning.COURT_LENGTH * 0.5
		var post_height: float = Tuning.GOAL_HEIGHT + Tuning.POST_THICKNESS
		var crossbar_y: float = Tuning.GOAL_HEIGHT + Tuning.POST_THICKNESS * 0.5
		for side: float in [-1.0, 1.0]:
			var z: float = side * Tuning.GOAL_POST_CENTER_Z
			Geometry.box(goal, "Post", Vector3(Tuning.POST_THICKNESS, post_height, Tuning.POST_THICKNESS),
				Vector3(x, post_height * 0.5, z), white)
			for band: int in 5:
				Geometry.box(goal, "PostBand",
					Vector3(Tuning.POST_THICKNESS + 0.001, 0.18, Tuning.POST_THICKNESS + 0.001),
					Vector3(x, 0.16 + float(band) * 0.4, z), dark)
			Geometry.box(goal, "GroundFrame", Vector3(1.5, 0.035, 0.035),
				Vector3(x + end * 0.75, 0.025, z), white)
		Geometry.box(goal, "Crossbar",
			Vector3(Tuning.POST_THICKNESS, Tuning.POST_THICKNESS, Tuning.GOAL_POST_OUTER_Z * 2.0),
			Vector3(x, crossbar_y, 0), white)
		for band: int in 7:
			Geometry.box(goal, "CrossbarBand",
				Vector3(Tuning.POST_THICKNESS + 0.001, Tuning.POST_THICKNESS + 0.001, 0.18),
				Vector3(x, crossbar_y, -1.2 + float(band) * 0.4), dark)
		var threads: SurfaceTool = SurfaceTool.new()
		threads.begin(Mesh.PRIMITIVE_TRIANGLES)
		for column: int in 19:
			var z: float = lerpf(-1.57, 1.57, float(column) / 18.0)
			Geometry.rod(threads, Vector3(x + end * 1.48, 0.02, z),
				Vector3(x + end * 1.48, 2.045, z), 0.006)
			Geometry.rod(threads, Vector3(x + end * 0.045, 2.045, z),
				Vector3(x + end * 1.48, 2.045, z), 0.006)
		for row: int in 13:
			var y: float = 0.03 + float(row) * 0.166
			Geometry.rod(threads, Vector3(x + end * 1.48, y, -1.57),
				Vector3(x + end * 1.48, y, 1.57), 0.006)
			for side: float in [-1.0, 1.0]:
				Geometry.rod(threads, Vector3(x + end * 0.045, y, side * 1.57),
					Vector3(x + end * 1.48, y, side * 1.57), 0.006)
		for depth: int in 9:
			var at_x: float = x + end * (0.06 + float(depth) * 0.175)
			Geometry.rod(threads, Vector3(at_x, 2.045, -1.57),
				Vector3(at_x, 2.045, 1.57), 0.006)
			for side: float in [-1.0, 1.0]:
				Geometry.rod(threads, Vector3(at_x, 0.02, side * 1.57),
					Vector3(at_x, 2.045, side * 1.57), 0.006)
		var net_mesh: MeshInstance3D = Geometry.mesh_node(goal, "Net", threads.commit(), net)
		net_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_hall() -> void:
	var wall: StandardMaterial3D = Geometry.material(Color("#536269"), 0.95)
	var padding: StandardMaterial3D = Geometry.material(Color("#233941"), 0.95)
	var steel: StandardMaterial3D = Geometry.material(Color("#374851"), 0.55)
	var seats: StandardMaterial3D = Geometry.material(Color("#8a8980"), 0.85)
	var bench: StandardMaterial3D = Geometry.material(Color("#a08358"), 0.72)
	Geometry.box(self, "FarWall", Vector3(48, 7.8, 0.3), Vector3(0, 3.9, -14), wall)
	Geometry.box(self, "FarPadding", Vector3(48, 1.2, 0.16), Vector3(0, 0.6, -13.77), padding)
	for end: float in [-1.0, 1.0]:
		Geometry.box(self, "EndWall", Vector3(0.3, 7.8, 28), Vector3(end * 24, 3.9, 0), wall)
		Geometry.box(self, "EndPadding", Vector3(0.16, 1.2, 28), Vector3(end * 23.77, 0.6, 0), padding)
	for column: int in 7:
		var x: float = -21.0 + float(column) * 7.0
		Geometry.box(self, "Pillar", Vector3(0.18, 7.8, 0.24), Vector3(x, 3.9, -13.6), steel)
		Geometry.box(self, "RoofBeam", Vector3(0.15, 0.22, 2.4), Vector3(x, 7.6, -12.5), steel)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 8.0
		Geometry.box(self, "BenchSeat", Vector3(5.0, 0.10, 0.55), Vector3(x, 0.48, -11.75), bench)
		Geometry.box(self, "BenchBack", Vector3(5.0, 0.44, 0.08), Vector3(x, 0.88, -11.97), seats)
		for leg: float in [-2.0, 0.0, 2.0]:
			Geometry.box(self, "BenchLeg", Vector3(0.08, 0.45, 0.4), Vector3(x + leg, 0.225, -11.75), steel)
		var doorway: MeshInstance3D = Geometry.box(self, "Access", Vector3(1.6, 2.5, 0.04),
			Vector3(side * 18, 1.25, -13.8), padding)
		doorway.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sign: Label3D = Label3D.new()
		sign.name = "OriginalHallSign"
		sign.text = "PISTA 01" if side < 0.0 else "FÚTBOL SALA"
		sign.position = Vector3(side * 9, 3.35, -13.8)
		sign.pixel_size = 0.01
		sign.font_size = 64
		sign.modulate = Color("#e2e1d8")
		sign.outline_size = 0
		add_child(sign)
	var lamp_material: StandardMaterial3D = Geometry.material(Color("#eee9da"), 0.65)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(0.5, 0.48, 0.43)
	lamp_material.emission_energy_multiplier = 1.0
	for column: int in 5:
		Geometry.box(self, "FarLuminaire", Vector3(3.5, 0.10, 0.4),
			Vector3(-16 + column * 8, 7.1, -10.8), lamp_material)


func _build_lighting() -> void:
	var surroundings: WorldEnvironment = WorldEnvironment.new()
	surroundings.name = "IndoorEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#192932")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d5dfe5")
	environment.ambient_light_energy = 0.26
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = false
	surroundings.environment = environment
	add_child(surroundings)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "CeilingKey"
	key.rotation_degrees = Vector3(-68, -28, 0)
	key.light_color = Color("#fff0da")
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 75.0
	key.shadow_bias = 0.015
	key.shadow_normal_bias = 0.8
	key.light_angular_distance = 1.4
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "CeilingFill"
	fill.rotation_degrees = Vector3(-48, 150, 0)
	fill.light_color = Color("#dbe5ec")
	fill.light_energy = 0.3
	add_child(fill)
	# Cinco luminarias de techo: OmniLights sobre las cajas decorativas para rebote cálido.
	# Sin sombra propia para no generar sombras cruzadas; aclaran coronillas y parqué.
	for column: int in 5:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "Luminaire%d" % column
		lamp.position = Vector3(-16.0 + float(column) * 8.0, 6.9, -10.8)
		lamp.light_color = Color("#fff2e0")
		lamp.light_energy = 0.85
		lamp.omni_range = 15.0
		lamp.omni_attenuation = 2.0
		lamp.shadow_enabled = false
		add_child(lamp)
