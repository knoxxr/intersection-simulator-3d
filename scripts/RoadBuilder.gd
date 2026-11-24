extends Node3D
class_name RoadBuilder

const LANE_WIDTH: float = 3.5
const ROAD_HALF_LEN: float = 68.0

var dynamic_root: Node3D
var env_built: bool = false

# Materials reused across rebuilds
var grass_mat: StandardMaterial3D
var asphalt_mat: StandardMaterial3D
var intersection_mat: StandardMaterial3D
var sidewalk_mat: StandardMaterial3D
var yellow_line_mat: StandardMaterial3D
var white_line_mat: StandardMaterial3D
var cone_mat: StandardMaterial3D
var cone_stripe_mat: StandardMaterial3D
var trunk_mat: StandardMaterial3D
var foliage_mat: StandardMaterial3D
var building_mats: Array[StandardMaterial3D] = []

func _ready() -> void:
	_init_materials()
	_setup_lighting_and_sky()
	dynamic_root = Node3D.new()
	dynamic_root.name = "DynamicRoad"
	add_child(dynamic_root)

func _init_materials() -> void:
	grass_mat = _make_mat(Color(0.28, 0.48, 0.25), 0.92)
	asphalt_mat = _make_mat(Color(0.18, 0.19, 0.21), 0.88)
	intersection_mat = _make_mat(Color(0.16, 0.17, 0.19), 0.88)
	sidewalk_mat = _make_mat(Color(0.66, 0.67, 0.69), 0.85)
	yellow_line_mat = _make_mat(Color(0.95, 0.78, 0.12), 0.5)
	white_line_mat = _make_mat(Color(0.93, 0.94, 0.96), 0.5)
	cone_mat = _make_mat(Color(1.0, 0.36, 0.05), 0.45)
	cone_stripe_mat = _make_mat(Color(0.98, 0.98, 0.98), 0.35)
	trunk_mat = _make_mat(Color(0.36, 0.24, 0.15), 0.9)
	foliage_mat = _make_mat(Color(0.19, 0.45, 0.22), 0.85)

	var b_colors := [
		Color(0.62, 0.68, 0.75),
		Color(0.75, 0.70, 0.64),
		Color(0.55, 0.60, 0.66),
		Color(0.70, 0.74, 0.78),
		Color(0.66, 0.60, 0.56)
	]
	for c in b_colors:
		building_mats.append(_make_mat(c, 0.75))

func _make_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

func _setup_lighting_and_sky() -> void:
	if env_built:
		return
	env_built = true

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.91)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.directional_shadow_max_distance = 130.0
	sun.rotation_degrees = Vector3(-52, 34, 0)
	add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

func rebuild(lane_count: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	if dynamic_root == null:
		return
	for c in dynamic_root.get_children():
		c.queue_free()

	var road_half: float = lane_count * LANE_WIDTH
	var road_width: float = road_half * 2.0
	var stop_dist: float = road_half + 3.2

	# 1. Ground base plane
	_add_box(Vector3(160, 0.4, 160), Vector3(0, -0.22, 0), grass_mat)

	# 2. Roads (N-S and E-W asphalt strips)
	_add_box(Vector3(road_width, 0.06, ROAD_HALF_LEN * 2.0), Vector3(0, -0.01, 0), asphalt_mat)
	_add_box(Vector3(ROAD_HALF_LEN * 2.0, 0.06, road_width), Vector3(0, -0.008, 0), asphalt_mat)
	# Intersection center pad
	_add_box(Vector3(road_width + 0.1, 0.07, road_width + 0.1), Vector3(0, -0.005, 0), intersection_mat)

	# 3. Four corner urban blocks (sidewalks + stylized buildings + trees)
	var sw_inner := road_half + 0.05
	var sw_outer := ROAD_HALF_LEN
	var sw_size := sw_outer - sw_inner
	var sw_center := sw_inner + sw_size * 0.5
	var corners := [
		Vector2(-1, -1),
		Vector2(1, -1),
		Vector2(-1, 1),
		Vector2(1, 1)
	]
	for idx in range(4):
		var s: Vector2 = corners[idx]
		# Sidewalk slab
		_add_box(
			Vector3(sw_size, 0.22, sw_size),
			Vector3(s.x * sw_center, 0.09, s.y * sw_center),
			sidewalk_mat
		)
		# Inner grass park patch inside block
		var park_inner := road_half + 3.8
		var park_size := sw_outer - park_inner - 1.0
		if park_size > 4.0:
			var park_c := park_inner + park_size * 0.5
			_add_box(
				Vector3(park_size, 0.24, park_size),
				Vector3(s.x * park_c, 0.10, s.y * park_c),
				grass_mat
			)

		# Stylized low-poly buildings set back nicely from intersection
		var b_off := road_half + 11.0
		var heights := [11.0, 16.0, 8.5, 14.0]
		_add_building(
			Vector3(s.x * (b_off + 3.5), 0.2, s.y * (b_off + 3.5)),
			Vector3(10.0, heights[idx], 10.0),
			building_mats[idx % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (b_off + 18.0), 0.2, s.y * (b_off + 4.5)),
			Vector3(11.0, heights[(idx + 2) % 4] * 0.85, 9.0),
			building_mats[(idx + 1) % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (b_off + 4.5), 0.2, s.y * (b_off + 18.0)),
			Vector3(9.0, heights[(idx + 1) % 4] * 0.9, 11.0),
			building_mats[(idx + 3) % building_mats.size()]
		)

		# Corner trees
		_add_tree(Vector3(s.x * (road_half + 5.5), 0.2, s.y * (road_half + 5.5)))
		_add_tree(Vector3(s.x * (road_half + 6.0), 0.2, s.y * (road_half + 16.0)))
		_add_tree(Vector3(s.x * (road_half + 16.0), 0.2, s.y * (road_half + 6.0)))

	# 4. Road Markings: double yellow centerlines, dashed lane lines, stop lines, crosswalks
	var arm_start := stop_dist + 0.3
	var arm_len := ROAD_HALF_LEN - arm_start
	var arm_mid := arm_start + arm_len * 0.5

	# N-S arms (North = -Z, South = +Z)
	for sign_z in [-1.0, 1.0]:
		# Double yellow centerline
		_add_box(Vector3(0.14, 0.02, arm_len), Vector3(-0.14, 0.03, sign_z * arm_mid), yellow_line_mat)
		_add_box(Vector3(0.14, 0.02, arm_len), Vector3(0.14, 0.03, sign_z * arm_mid), yellow_line_mat)

		# Dashed lane dividers on both sides of centerline
		for l in range(1, lane_count):
			var lx := l * LANE_WIDTH
			var z_pos := arm_start + 2.5
			while z_pos < ROAD_HALF_LEN - 2.0:
				_add_box(Vector3(0.12, 0.02, 2.8), Vector3(-lx, 0.03, sign_z * z_pos), white_line_mat)
				_add_box(Vector3(0.12, 0.02, 2.8), Vector3(lx, 0.03, sign_z * z_pos), white_line_mat)
				z_pos += 6.0

		# Stop line on incoming half only:
		# North arm (sign_z = -1) incoming is -X; South arm (sign_z = +1) incoming is +X
		var incoming_x_sign: float = sign_z
		_add_box(
			Vector3(road_half - 0.3, 0.02, 0.45),
			Vector3(incoming_x_sign * (road_half * 0.5), 0.03, sign_z * stop_dist),
			white_line_mat
		)

		# Crosswalk stripes across full width
		var cw_z: float = float(sign_z) * (road_half + 1.55)
		var stripe_x := -road_half + 0.9
		while stripe_x <= road_half - 0.8:
			_add_box(Vector3(0.75, 0.02, 2.1), Vector3(stripe_x, 0.03, cw_z), white_line_mat)
			stripe_x += 1.75

	# E-W arms (East = +X, West = -X)
	for sign_x in [-1.0, 1.0]:
		# Double yellow centerline
		_add_box(Vector3(arm_len, 0.02, 0.14), Vector3(sign_x * arm_mid, 0.03, -0.14), yellow_line_mat)
		_add_box(Vector3(arm_len, 0.02, 0.14), Vector3(sign_x * arm_mid, 0.03, 0.14), yellow_line_mat)

		# Dashed lane dividers
		for l in range(1, lane_count):
			var lz := l * LANE_WIDTH
			var x_pos := arm_start + 2.5
			while x_pos < ROAD_HALF_LEN - 2.0:
				_add_box(Vector3(2.8, 0.02, 0.12), Vector3(sign_x * x_pos, 0.03, -lz), white_line_mat)
				_add_box(Vector3(2.8, 0.02, 0.12), Vector3(sign_x * x_pos, 0.03, lz), white_line_mat)
				x_pos += 6.0

		# Stop line on incoming half:
		# East arm (sign_x = +1) incoming is -Z; West arm (sign_x = -1) incoming is +Z
		var incoming_z_sign: float = -sign_x
		_add_box(
			Vector3(0.45, 0.02, road_half - 0.3),
			Vector3(sign_x * stop_dist, 0.03, incoming_z_sign * (road_half * 0.5)),
			white_line_mat
		)

		# Crosswalk stripes
		var cw_x: float = float(sign_x) * (road_half + 1.55)
		var stripe_z := -road_half + 0.9
		while stripe_z <= road_half - 0.8:
			_add_box(Vector3(2.1, 0.02, 0.75), Vector3(cw_x, 0.03, stripe_z), white_line_mat)
			stripe_z += 1.75

	# 5. Traffic Cones for closed lanes or disabled approaches
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	for a in range(4):
		var f: Vector3 = forwards[a]
		var r: Vector3 = rights[a]
		for l in range(lane_count):
			var closed: bool = (not approach_enabled[a]) or (l < lane_enabled.size() and not lane_enabled[l])
			if closed:
				var d := (l + 0.5) * LANE_WIDTH
				for dist in [stop_dist + 2.5, stop_dist + 8.5, stop_dist + 14.5]:
					var pos: Vector3 = -f * float(dist) + r * d
					_add_cone(pos)

func _add_box(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	dynamic_root.add_child(mi)

func _add_building(base_pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = base_pos + Vector3(0, sz.y * 0.5, 0)
	dynamic_root.add_child(mi)

	# Roof cap trim
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(sz.x + 0.35, 0.45, sz.z + 0.35)
	roof.mesh = rm
	roof.material_override = sidewalk_mat
	roof.position = base_pos + Vector3(0, sz.y + 0.22, 0)
	dynamic_root.add_child(roof)

func _add_tree(base_pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.22
	tm.bottom_radius = 0.30
	tm.height = 2.2
	trunk.mesh = tm
	trunk.material_override = trunk_mat
	trunk.position = base_pos + Vector3(0, 1.1, 0)
	dynamic_root.add_child(trunk)

	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 1.65
	cm.height = 3.1
	crown.mesh = cm
	crown.material_override = foliage_mat
	crown.position = base_pos + Vector3(0, 3.2, 0)
	dynamic_root.add_child(crown)

func _add_cone(pos: Vector3) -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.65, 0.08, 0.65)
	base.mesh = bm
	base.material_override = cone_mat
	base.position = pos + Vector3(0, 0.07, 0)
	dynamic_root.add_child(base)

	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.24
	cm.height = 0.78
	cone.mesh = cm
	cone.material_override = cone_mat
	cone.position = pos + Vector3(0, 0.48, 0)
	dynamic_root.add_child(cone)

	var stripe := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.13
	sm.bottom_radius = 0.17
	sm.height = 0.16
	stripe.mesh = sm
	stripe.material_override = cone_stripe_mat
	stripe.position = pos + Vector3(0, 0.56, 0)
	dynamic_root.add_child(stripe)
