extends Node3D
class_name TrafficLight

enum SignalColor { RED, YELLOW, GREEN, OFF }

var red_mat: StandardMaterial3D
var yellow_mat: StandardMaterial3D
var green_mat: StandardMaterial3D
var left_mat: StandardMaterial3D

var _pole_built: bool = false

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
	pole_mesh.top_radius = 0.14
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 6.2
	pole.mesh = pole_mesh
	pole.material_override = pole_mat
	pole.position = Vector3(0, 3.1, 0)
	add_child(pole)

	# Horizontal cantilever arm reaching over the road (+X in local space)
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.10
	arm_mesh.bottom_radius = 0.12
	arm_mesh.height = 4.2
	arm.mesh = arm_mesh
	arm.material_override = pole_mat
	arm.rotation_degrees = Vector3(0, 0, 90)
	arm.position = Vector3(2.0, 5.9, 0)
	add_child(arm)

	# Signal housing box hanging on the arm (faces -Z in local space toward approaching cars)
	var housing := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(2.7, 0.85, 0.45)
	housing.mesh = box_mesh
	housing.material_override = housing_mat
	housing.position = Vector3(2.8, 5.55, 0)
	add_child(housing)

	# 4 Signal bulbs: Red, Yellow, Left-Arrow, Green (arranged left-to-right facing approaching cars)
	red_mat = _create_bulb_mat(Color(0.2, 0.04, 0.04))
	yellow_mat = _create_bulb_mat(Color(0.22, 0.18, 0.03))
	left_mat = _create_bulb_mat(Color(0.03, 0.18, 0.12))
	green_mat = _create_bulb_mat(Color(0.03, 0.2, 0.06))

	var offsets := [-0.95, -0.32, 0.32, 0.95]
	var mats := [red_mat, yellow_mat, left_mat, green_mat]

	for i in range(4):
		var bulb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.48
		bulb.mesh = sphere
		bulb.material_override = mats[i]
		# Place on BOTH front and back slightly protruding so visible from all camera angles
		bulb.position = Vector3(2.8 + offsets[i], 5.55, -0.18)
		bulb.scale = Vector3(1.0, 1.0, 0.55)
		add_child(bulb)

		var bulb_back := MeshInstance3D.new()
		bulb_back.mesh = sphere
		bulb_back.material_override = mats[i]
		bulb_back.position = Vector3(2.8 + offsets[i], 5.55, 0.18)
		bulb_back.scale = Vector3(1.0, 1.0, 0.55)
		add_child(bulb_back)

	# Secondary vertical beacon at top of pole for easy top-down visibility
	var top_housing := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(0.55, 0.55, 0.55)
	top_housing.mesh = top_box
	top_housing.material_override = housing_mat
	top_housing.position = Vector3(0, 6.45, 0)
	add_child(top_housing)

func _create_bulb_mat(base_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.roughness = 0.25
	m.emission_enabled = false
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
		mat.emission_enabled = true
		mat.emission = on_col
		mat.emission_energy_multiplier = 2.6
	else:
		mat.albedo_color = off_col
		mat.emission_enabled = false
