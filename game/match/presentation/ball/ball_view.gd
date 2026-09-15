extends Node3D

const Geometry = preload("res://match/presentation/geometry.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const BallShader = preload("res://match/presentation/ball/ball.gdshader")

var _ball: MeshInstance3D
var _ground_cue: MeshInstance3D


func _ready() -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = Tuning.BALL_RADIUS
	sphere.height = Tuning.BALL_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var leather: ShaderMaterial = ShaderMaterial.new()
	leather.shader = BallShader
	_ball = Geometry.mesh_node(self, "BallMesh", sphere, leather)
	var paths: Array[PackedVector3Array] = [Geometry.circle(0.19, Vector3.ZERO, 32)]
	var ink: StandardMaterial3D = Geometry.material(Color("#243442"), 1.0)
	_ground_cue = Geometry.mesh_node(self, "LandingCue", Geometry.ribbons(paths, 0.025), ink)
	_ground_cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func present(at: Vector3, orientation: Quaternion) -> void:
	_ball.position = at
	_ball.quaternion = orientation.normalized()
	_ground_cue.position = Vector3(at.x, 0.018, at.z)
	_ground_cue.visible = at.y > 0.24
