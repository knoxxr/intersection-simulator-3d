extends Node3D
class_name TrafficLight

enum SignalColor { RED, YELLOW, GREEN, OFF }

static var _shared_arrow_front: ArrayMesh
static var _shared_disc_mesh: CylinderMesh
static var _shared_backing_mesh: CylinderMesh
static var _shared_visor_mesh: BoxMesh

var red_mat: StandardMaterial3D
var yellow_mat: StandardMaterial3D
var green_mat: StandardMaterial3D
var left_mat: StandardMaterial3D

var _pole_built: bool = false
var _arm_node: MeshInstance3D
var _housing_root: Node3D

static func _ensure_shared_meshes() -> void:
	if _shared_disc_mesh != null:
		return
	_shared_disc_mesh = CylinderMesh.new()
	_shared_disc_mesh.top_radius = 0.25
	_shared_disc_mesh.bottom_radius = 0.25
	_shared_disc_mesh.height = 0.08
	_shared_disc_mesh.radial_segments = 16
	_shared_disc_mesh.rings = 1

	_shared_backing_mesh = CylinderMesh.new()
	_shared_backing_mesh.top_radius = 0.29
	_shared_backing_mesh.bottom_radius = 0.29
	_shared_backing_mesh.height = 0.06
	_shared_backing_mesh.radial_segments = 16
	_shared_backing_mesh.rings = 1

	_shared_visor_mesh = BoxMesh.new()
	_shared_visor_mesh.size = Vector3(0.62, 0.06, 0.26)

	_shared_arrow_front = _bake_arrow_mesh(1.0)

static func _bake_arrow_mesh(dir_x: float) -> ArrayMesh:
	# Builds a razor-sharp 3D left-turn arrow (←) on the -Z front face pointing toward dir_x (+X = driver's left)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zf := -0.025 # front face toward approaching driver (-Z)
	var zb := 0.025  # back face into housing (+Z)

	# Helper to add front-facing (-Z) triangle with exact Godot CW winding: (v1-v0).cross(v2-v0).z >= 0 for -Z normal
	var add_tri := func(p0: Vector3, p1: Vector3, p2: Vector3, n_dir: Vector3) -> void:
		var n := n_dir.normalized()
		st.set_normal(n)
		st.set_uv(Vector2.ZERO)
		if (p1 - p0).cross(p2 - p0).dot(n) <= 0.0:
			st.add_vertex(p0)
			st.add_vertex(p1)
			st.add_vertex(p2)
		else:
			st.add_vertex(p0)
			st.add_vertex(p2)
			st.add_vertex(p1)

	var add_quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n_dir: Vector3) -> void:
		add_tri.call(p0, p1, p2, n_dir)
		add_tri.call(p0, p2, p3, n_dir)

	# 1. Arrowhead triangle: tip at (dir_x * 0.21, 0), base at (dir_x * 0.01, ±0.165)
	var tip_f := Vector3(dir_x * 0.21, 0.0, zf)
	var top_f := Vector3(dir_x * 0.01, 0.165, zf)
	var bot_f := Vector3(dir_x * 0.01, -0.165, zf)
	var tip_b := Vector3(dir_x * 0.21, 0.0, zb)
	var top_b := Vector3(dir_x * 0.01, 0.165, zb)
	var bot_b := Vector3(dir_x * 0.01, -0.165, zb)

	add_tri.call(tip_f, top_f, bot_f, Vector3(0, 0, -1))
	add_quad.call(tip_f, top_f, top_b, tip_b, Vector3(dir_x * 0.165, 0.20, 0.0))
	add_quad.call(bot_f, tip_f, tip_b, bot_b, Vector3(dir_x * 0.165, -0.20, 0.0))
	add_quad.call(top_f, bot_f, bot_b, top_b, Vector3(-dir_x, 0.0, 0.0))

	# 2. Horizontal shaft rectangle: x from (dir_x * 0.02) back to (-dir_x * 0.19), y in [-0.048, +0.048]
	var sx0 := dir_x * 0.02
	var sx1 := -dir_x * 0.19
	var sy := 0.048
	var s0f := Vector3(sx0, sy, zf)
	var s1f := Vector3(sx1, sy, zf)
	var s2f := Vector3(sx1, -sy, zf)
	var s3f := Vector3(sx0, -sy, zf)
	var s0b := Vector3(sx0, sy, zb)
	var s1b := Vector3(sx1, sy, zb)
	var s2b := Vector3(sx1, -sy, zb)
	var s3b := Vector3(sx0, -sy, zb)

	add_quad.call(s0f, s1f, s2f, s3f, Vector3(0, 0, -1))
	add_quad.call(s0f, s1f, s1b, s0b, Vector3(0, 1, 0))
	add_quad.call(s2f, s3f, s3b, s2b, Vector3(0, -1, 0))
	add_quad.call(s1f, s2f, s2b, s1b, Vector3(-dir_x, 0, 0))

	return st.commit()

func _ready() -> void:
	if not _pole_built:
		_build_mesh()

func _build_mesh() -> void:
	_ensure_shared_meshes()
	_pole_built = true

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.22, 0.24, 0.28)
	pole_mat.roughness = 0.6

	var housing_mat := StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.09, 0.10, 0.12)
	housing_mat.roughness = 0.5

	var backing_mat := StandardMaterial3D.new()
	backing_mat.albedo_color = Color(0.025, 0.03, 0.035)
	backing_mat.roughness = 0.4

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
	box_mesh.size = Vector3(3.36, 0.96, 0.46)
	housing.mesh = box_mesh
	housing.material_override = housing_mat
	_housing_root.add_child(housing)

	red_mat = _create_bulb_mat(Color(0.22, 0.04, 0.04))
	yellow_mat = _create_bulb_mat(Color(0.24, 0.19, 0.03))
	left_mat = _create_bulb_mat(Color(0.04, 0.16, 0.07))
	green_mat = _create_bulb_mat(Color(0.03, 0.18, 0.06))

	# Single-sided front face (-Z) facing approaching traffic only; solid dark backplate on rear (+Z).
	# Standard Korean 4-lens horizontal order (driver's Left -> Right): [RED] [YELLOW] [← LEFT] [GREEN]
	var offsets := [1.14, 0.38, -0.38, -1.14]
	var mats := [red_mat, yellow_mat, left_mat, green_mat]

	for i in range(4):
		var ox: float = offsets[i]

		# Top sun visor on front (-Z) face only
		var visor := MeshInstance3D.new()
		visor.mesh = _shared_visor_mesh
		visor.material_override = housing_mat
		visor.position = Vector3(ox, 0.34, -0.31)
		visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_housing_root.add_child(visor)

		# Dark circular recessed lens backing on front (-Z) face only
		var bg := MeshInstance3D.new()
		bg.mesh = _shared_backing_mesh
		bg.material_override = backing_mat
		bg.rotation_degrees = Vector3(90, 0, 0)
		bg.position = Vector3(ox, 0.0, -0.23)
		bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_housing_root.add_child(bg)

		if i == 2:
			# Dedicated 3D Left-Turn Arrow (←) on front (-Z) face only
			var arr_f := MeshInstance3D.new()
			arr_f.mesh = _shared_arrow_front
			arr_f.material_override = left_mat
			arr_f.position = Vector3(ox, 0.0, -0.27)
			arr_f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_housing_root.add_child(arr_f)
		else:
			var bulb := MeshInstance3D.new()
			bulb.mesh = _shared_disc_mesh
			bulb.material_override = mats[i]
			bulb.rotation_degrees = Vector3(90, 0, 0)
			bulb.position = Vector3(ox, 0.0, -0.25)
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_housing_root.add_child(bulb)

func set_arm_reach(road_half: float) -> void:
	if not _pole_built:
		_build_mesh()
	var reach := clampf(road_half * 0.55 + 1.2, 2.2, 16.0)
	var arm_mesh := _arm_node.mesh as CylinderMesh
	if arm_mesh:
		arm_mesh.height = reach + 1.4
	_arm_node.position = Vector3((reach + 1.4) * 0.5, 6.2, 0)
	_housing_root.position = Vector3(reach, 5.8, 0)

func _create_bulb_mat(base_color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base_color
	m.roughness = 0.22
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.emission_energy_multiplier = 0.0
	return m

func set_display(main_color: SignalColor, left_green: bool) -> void:
	if not _pole_built:
		_build_mesh()

	_set_bulb(red_mat, main_color == SignalColor.RED, Color(1.0, 0.14, 0.12), Color(0.22, 0.04, 0.04), 2.8)
	_set_bulb(yellow_mat, main_color == SignalColor.YELLOW, Color(1.0, 0.78, 0.08), Color(0.24, 0.19, 0.03), 2.8)
	_set_bulb(green_mat, main_color == SignalColor.GREEN, Color(0.10, 0.96, 0.36), Color(0.03, 0.18, 0.06), 2.8)
	_set_bulb(left_mat, left_green, Color(0.08, 1.0, 0.42), Color(0.04, 0.16, 0.07), 3.2)

func _set_bulb(mat: StandardMaterial3D, lit: bool, on_col: Color, off_col: Color, energy: float) -> void:
	if lit:
		mat.albedo_color = on_col
		mat.emission = on_col
		mat.emission_energy_multiplier = energy
	else:
		mat.albedo_color = off_col
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = 0.0
