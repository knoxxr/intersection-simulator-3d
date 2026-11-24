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
	intersection_mat = _make_mat(Color(0.15, 0.16, 0.18), 0.88)
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
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	# Orthogonal shadow prevents PSSM split-boundary flickering on WebGL2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 1.8
	sun.directional_shadow_max_distance = 90.0
	sun.rotation_degrees = Vector3(-52, 34, 0)
	add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.ambient_light_energy = 0.60
	# LINEAR tonemapper skips offscreen WebGL2 post-process blit pass (no screen flicker)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
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
	var arm_total_len: float = ROAD_HALF_LEN - road_half
	var arm_center: float = road_half + arm_total_len * 0.5

	# 1. Ground base plane placed cleanly 0.25m below road surface (zero Z-fighting)
	_add_box(Vector3(170, 0.4, 170), Vector3(0, -0.45, 0), grass_mat, false)

	# 2. Non-overlapping Road Geometry (all tops cleanly at y = 0.0)
	# Center intersection pad
	_add_box(Vector3(road_width, 0.20, road_width), Vector3(0, -0.10, 0), intersection_mat, false)
	# 4 non-overlapping road arms (North, South, East, West)
	_add_box(Vector3(road_width, 0.20, arm_total_len), Vector3(0, -0.10, -arm_center), asphalt_mat, false)
	_add_box(Vector3(road_width, 0.20, arm_total_len), Vector3(0, -0.10, arm_center), asphalt_mat, false)
	_add_box(Vector3(arm_total_len, 0.20, road_width), Vector3(arm_center, -0.10, 0), asphalt_mat, false)
	_add_box(Vector3(arm_total_len, 0.20, road_width), Vector3(-arm_center, -0.10, 0), asphalt_mat, false)

	# 3. Four corner urban blocks (non-overlapping sidewalks + raised grass parks + buildings + trees)
	var sw_inner := road_half + 0.02
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
		# Sidewalk slab (bottom = -0.10, top = +0.20)
		_add_box(
			Vector3(sw_size, 0.30, sw_size),
			Vector3(s.x * sw_center, 0.05, s.y * sw_center),
			sidewalk_mat,
			false
		)
		# Inner grass park sits cleanly ON TOP of sidewalk (bottom = +0.20, top = +0.32 -> 12cm separation)
		var park_inner := road_half + 3.8
		var park_size := sw_outer - park_inner - 1.0
		if park_size > 4.0:
			var park_c := park_inner + park_size * 0.5
			_add_box(
				Vector3(park_size, 0.12, park_size),
				Vector3(s.x * park_c, 0.26, s.y * park_c),
				grass_mat,
				false
			)

		# Stylized low-poly buildings set back nicely from intersection
		var b_off := road_half + 11.0
		var heights := [11.0, 16.0, 8.5, 14.0]
		_add_building(
			Vector3(s.x * (b_off + 3.5), 0.32, s.y * (b_off + 3.5)),
			Vector3(10.0, heights[idx], 10.0),
			building_mats[idx % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (b_off + 18.0), 0.32, s.y * (b_off + 4.5)),
			Vector3(11.0, heights[(idx + 2) % 4] * 0.85, 9.0),
			building_mats[(idx + 1) % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (b_off + 4.5), 0.32, s.y * (b_off + 18.0)),
			Vector3(9.0, heights[(idx + 1) % 4] * 0.9, 11.0),
			building_mats[(idx + 3) % building_mats.size()]
		)

		# Corner trees
		_add_tree(Vector3(s.x * (road_half + 5.5), 0.32, s.y * (road_half + 5.5)))
		_add_tree(Vector3(s.x * (road_half + 6.0), 0.32, s.y * (road_half + 16.0)))
		_add_tree(Vector3(s.x * (road_half + 16.0), 0.32, s.y * (road_half + 6.0)))

	# 4. Road Markings: flat planes clearly elevated at y = +0.05 (5cm above road top y = 0.0 -> zero Z-fighting)
	var mark_y: float = 0.05
	var arm_start := stop_dist + 0.3
	var arm_len := ROAD_HALF_LEN - arm_start
	var arm_mid := arm_start + arm_len * 0.5

	# N-S arms (North = -Z, South = +Z)
	for sign_z in [-1.0, 1.0]:
		var sz: float = float(sign_z)
		# Double yellow centerline
		_add_marking(Vector2(0.14, arm_len), Vector3(-0.15, mark_y, sz * arm_mid), yellow_line_mat)
		_add_marking(Vector2(0.14, arm_len), Vector3(0.15, mark_y, sz * arm_mid), yellow_line_mat)

		# Dashed lane dividers on both sides of centerline
		for l in range(1, lane_count):
			var lx := l * LANE_WIDTH
			var z_pos := arm_start + 2.5
			while z_pos < ROAD_HALF_LEN - 2.0:
				_add_marking(Vector2(0.14, 2.8), Vector3(-lx, mark_y, sz * z_pos), white_line_mat)
				_add_marking(Vector2(0.14, 2.8), Vector3(lx, mark_y, sz * z_pos), white_line_mat)
				z_pos += 6.0

		# Stop line on incoming half only
		var incoming_x_sign: float = sz
		_add_marking(
			Vector2(road_half - 0.3, 0.45),
			Vector3(incoming_x_sign * (road_half * 0.5), mark_y, sz * stop_dist),
			white_line_mat
		)

		# Crosswalk stripes across full width
		var cw_z: float = sz * (road_half + 1.55)
		var stripe_x := -road_half + 0.9
		while stripe_x <= road_half - 0.8:
			_add_marking(Vector2(0.75, 2.1), Vector3(stripe_x, mark_y, cw_z), white_line_mat)
			stripe_x += 1.75

	# E-W arms (East = +X, West = -X)
	for sign_x in [-1.0, 1.0]:
		var sx: float = float(sign_x)
		# Double yellow centerline
		_add_marking(Vector2(arm_len, 0.14), Vector3(sx * arm_mid, mark_y, -0.15), yellow_line_mat)
		_add_marking(Vector2(arm_len, 0.14), Vector3(sx * arm_mid, mark_y, 0.15), yellow_line_mat)

		# Dashed lane dividers
		for l in range(1, lane_count):
			var lz := l * LANE_WIDTH
			var x_pos := arm_start + 2.5
			while x_pos < ROAD_HALF_LEN - 2.0:
				_add_marking(Vector2(2.8, 0.14), Vector3(sx * x_pos, mark_y, -lz), white_line_mat)
				_add_marking(Vector2(2.8, 0.14), Vector3(sx * x_pos, mark_y, lz), white_line_mat)
				x_pos += 6.0

		# Stop line on incoming half
		var incoming_z_sign: float = -sx
		_add_marking(
			Vector2(0.45, road_half - 0.3),
			Vector3(sx * stop_dist, mark_y, incoming_z_sign * (road_half * 0.5)),
			white_line_mat
		)

		# Crosswalk stripes
		var cw_x: float = sx * (road_half + 1.55)
		var stripe_z := -road_half + 0.9
		while stripe_z <= road_half - 0.8:
			_add_marking(Vector2(2.1, 0.75), Vector3(cw_x, mark_y, stripe_z), white_line_mat)
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

func _add_box(sz: Vector3, pos: Vector3, mat: StandardMaterial3D, cast_shadows: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if not cast_shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dynamic_root.add_child(mi)

func _add_marking(sz_xz: Vector2, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = sz_xz
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dynamic_root.add_child(mi)

func _add_building(base_pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = base_pos + Vector3(0, sz.y * 0.5, 0)
	dynamic_root.add_child(mi)

	# Roof cap trim sitting cleanly above building top
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(sz.x + 0.4, 0.45, sz.z + 0.4)
	roof.mesh = rm
	roof.material_override = sidewalk_mat
	roof.position = base_pos + Vector3(0, sz.y + 0.24, 0)
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
	base.position = pos + Vector3(0, 0.08, 0)
	dynamic_root.add_child(base)

	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.24
	cm.height = 0.78
	cone.mesh = cm
	cone.material_override = cone_mat
	cone.position = pos + Vector3(0, 0.51, 0)
	dynamic_root.add_child(cone)

	var stripe := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.145
	sm.bottom_radius = 0.185
	sm.height = 0.16
	stripe.mesh = sm
	stripe.material_override = cone_stripe_mat
	stripe.position = pos + Vector3(0, 0.59, 0)
	dynamic_root.add_child(stripe)
