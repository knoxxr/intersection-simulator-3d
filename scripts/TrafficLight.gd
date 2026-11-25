extends Node3D
class_name TrafficLight

enum SignalColor { RED, YELLOW, GREEN, OFF }

var red_mat: StandardMaterial3D
var yellow_mat: StandardMaterial3D
var green_mat: StandardMaterial3D
var left_mat: StandardMaterial3D

var _pole_built: bool = false
var _arm_node: MeshInstance3D
var _housing_root: Node3D

func _ready() -> void:
	if not _pole_built:
		_build_mesh()

func _build_mesh() -> void:
	_pole_built = true

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.24, 0.28)
	pole_mat.roughness = 0.6

	var housing_mat := StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.1, 0.11, 0.13)
	housing_mat.roughness = 0.5

	# Vertical pole
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.16
	pole_mesh.bottom_radius = 0.22
	pole_mesh.height = 6.6
	pole.mesh = pole_mesh
	pole.material_override = pole_mat
	pole.position = Vector3(0, 3.3, 0)
	add_child(pole)

	# Horizontal cantilever arm reaching over the lanes (+X in local space)
	_arm_node = MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.11
	arm_mesh.bottom_radius = 0.13
	arm_mesh.height = 4.6
	_arm_node.mesh = arm_mesh
	_arm_node.material_override = pole_mat
	_arm_node.rotation_degrees = Vector3(0, 0, 90)
	_arm_node.position = Vector3(2.3, 6.2, 0)
	add_child(_arm_node)

	# Signal housing assembly (moved outward when road has many lanes)
	_housing_root = Node3D.new()
	_housing_root.position = Vector3(3.0, 5.8, 0)
	add_child(_housing_root)

	var housing := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(2.9, 0.90, 0.48)
	housing.mesh = box_mesh
	housing.material_override = housing_mat
	_housing_root.add_child(housing)

	red_mat = _create_bulb_mat(Color(0.2, 0.04, 0.04))
	yellow_mat = _create_bulb_mat(Color(0.22, 0.18, 0.03))
	left_mat = _create_bulb_mat(Color(0.03, 0.18, 0.12))
	green_mat = _create_bulb_mat(Color(0.03, 0.2, 0.06))

	var offsets := [-1.02, -0.34, 0.34, 1.02]
	var mats := [red_mat, yellow_mat, left_mat, green_mat]

	for i in range(4):
		var sphere := SphereMesh.new()
		sphere.radius = 0.26
		sphere.height = 0.52

		var bulb := MeshInstance3D.new()
		bulb.mesh = sphere
		bulb.material_override = mats[i]
		bulb.position = Vector3(offsets[i], 0.0, -0.20)
		bulb.scale = Vector3(1.0, 1.0, 0.55)
		_housing_root.add_child(bulb)

		var bulb_back := MeshInstance3D.new()
		bulb_back.mesh = sphere
		bulb_back.material_override = mats[i]
		bulb_back.position = Vector3(offsets[i], 0.0, 0.20)
		bulb_back.scale = Vector3(1.0, 1.0, 0.55)
		_housing_root.add_child(bulb_back)

func set_arm_reach(road_half: float) -> void:
	if not _pole_built:
		_build_mesh()
	var reach := clampf(road_half * 0.55 + 1.6, 3.8, 16.0)
	var arm_mesh := _arm_node.mesh as CylinderMesh
	if arm_mesh:
		arm_mesh.height = reach + 1.4
	_arm_node.position = Vector3((reach + 1.4) * 0.5, 6.2, 0)
	_housing_root.position = Vector3(reach, 5.8, 0)

func _create_bulb_mat(base_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.emission_energy_multiplier = 0.0
	return m

func set_display(main_color: SignalColor, left_green: bool) -> void:
	if not _pole_built:
		_build_mesh()

	_set_bulb(red_mat, main_color == SignalColor.RED, Color(1.0, 0.14, 0.12), Color(0.2, 0.04, 0.04))
	_set_bulb(yellow_mat, main_color == SignalColor.YELLOW, Color(1.0, 0.78, 0.08), Color(0.22, 0.18, 0.03))
	_set_bulb(green_mat, main_color == SignalColor.GREEN, Color(0.1, 0.95, 0.35), Color(0.03, 0.2, 0.06))
	_set_bulb(left_mat, left_green, Color(0.08, 0.95, 0.85), Color(0.03, 0.15, 0.14))

func _set_bulb(mat: StandardMaterial3D, lit: bool, on_col: Color, off_col: Color) -> void:
	if lit:
		mat.albedo_color = on_col
		mat.emission = on_col
		mat.emission_energy_multiplier = 2.4
	else:
		mat.albedo_color = off_col
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = 0.0
