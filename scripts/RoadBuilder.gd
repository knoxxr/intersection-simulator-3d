extends Node3D
class_name RoadBuilder

const LANE_WIDTH: float = 3.5
const ROAD_HALF_LEN: float = 115.0

enum TimeOfDay { DAY, SUNSET, NIGHT }
enum IntersectionType { SIGNALIZED, ROUNDABOUT }

var dynamic_root: Node3D
var env_built: bool = false
var sun_light: DirectionalLight3D
var world_env_node: WorldEnvironment
var time_of_day: TimeOfDay = TimeOfDay.DAY
var intersection_type: IntersectionType = IntersectionType.SIGNALIZED

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
var lamp_pole_mat: StandardMaterial3D
var lamp_bulb_mat: StandardMaterial3D
var monument_mat: StandardMaterial3D
var building_mats: Array[StandardMaterial3D] = []

# Congestion overlay bars (4 dynamic MeshInstance3D nodes sharing 1 BoxMesh)
var congestion_bars: Array[MeshInstance3D] = []
var congestion_mats: Array[StandardMaterial3D] = []
var congestion_overlay_enabled: bool = true

static func get_roundabout_radii(ns_lanes: int, ew_lanes: int) -> Dictionary:
	var ring_lanes := clampi(maxi(ns_lanes, ew_lanes), 1, 10)
	var island_r := maxf(6.5, 5.5 + float(ring_lanes) * 0.85)
	var outer_r := island_r + float(ring_lanes) * LANE_WIDTH
	var yield_dist := outer_r + 2.8
	return {
		"ring_lanes": ring_lanes,
		"island_r": island_r,
		"outer_r": outer_r,
		"yield_dist": yield_dist
	}

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
	lamp_pole_mat = _make_mat(Color(0.25, 0.27, 0.32), 0.6)
	monument_mat = _make_mat(Color(0.82, 0.84, 0.88), 0.4)

	lamp_bulb_mat = StandardMaterial3D.new()
	lamp_bulb_mat.albedo_color = Color(0.85, 0.82, 0.70)
	lamp_bulb_mat.roughness = 0.25
	lamp_bulb_mat.emission_enabled = true
	lamp_bulb_mat.emission = Color(1.0, 0.88, 0.58)
	lamp_bulb_mat.emission_energy_multiplier = 0.0

	var b_colors := [
		Color(0.62, 0.68, 0.75),
		Color(0.75, 0.70, 0.64),
		Color(0.55, 0.60, 0.66),
		Color(0.70, 0.74, 0.78),
		Color(0.66, 0.60, 0.56)
	]
	for c in b_colors:
		building_mats.append(_make_mat(c, 0.75))

	congestion_mats.clear()
	for _i in range(4):
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.15, 0.85, 0.35)
		cm.roughness = 0.35
		cm.emission_enabled = true
		cm.emission = Color(0.15, 0.85, 0.35)
		cm.emission_energy_multiplier = 0.85
		congestion_mats.append(cm)

func _make_mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

func _setup_lighting_and_sky() -> void:
	if env_built:
		return
	env_built = true

	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun_light.shadow_bias = 0.12
	sun_light.shadow_normal_bias = 1.8
	sun_light.directional_shadow_max_distance = 220.0
	add_child(sun_light)

	world_env_node = WorldEnvironment.new()
	world_env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_env_node.environment = env
	add_child(world_env_node)

	set_time_of_day(TimeOfDay.DAY)

func set_time_of_day(mode: TimeOfDay) -> void:
	time_of_day = mode
	if sun_light == null or world_env_node == null:
		return
	var env := world_env_node.environment
	match mode:
		TimeOfDay.DAY:
			sun_light.light_energy = 1.15
			sun_light.light_color = Color(1.0, 0.97, 0.92)
			sun_light.rotation_degrees = Vector3(-52, 34, 0)
			env.background_color = Color(0.56, 0.75, 0.92)
			env.ambient_light_color = Color(0.75, 0.80, 0.88)
			env.ambient_light_energy = 0.60
			lamp_bulb_mat.emission_energy_multiplier = 0.0
		TimeOfDay.SUNSET:
			sun_light.light_energy = 0.95
			sun_light.light_color = Color(1.0, 0.62, 0.34)
			sun_light.rotation_degrees = Vector3(-22, 62, 0)
			env.background_color = Color(0.78, 0.46, 0.34)
			env.ambient_light_color = Color(0.72, 0.50, 0.45)
			env.ambient_light_energy = 0.48
			lamp_bulb_mat.emission_energy_multiplier = 1.4
		TimeOfDay.NIGHT:
			sun_light.light_energy = 0.28
			sun_light.light_color = Color(0.42, 0.56, 0.88)
			sun_light.rotation_degrees = Vector3(-60, -25, 0)
			env.background_color = Color(0.06, 0.09, 0.16)
			env.ambient_light_color = Color(0.24, 0.30, 0.46)
			env.ambient_light_energy = 0.42
			lamp_bulb_mat.emission_energy_multiplier = 2.8

func update_congestion(dir_wait_counts: Array[int]) -> void:
	for i in range(min(congestion_bars.size(), dir_wait_counts.size())):
		var bar := congestion_bars[i]
		if not is_instance_valid(bar):
			continue
		bar.visible = congestion_overlay_enabled
		if not congestion_overlay_enabled:
			continue
		var w_cnt := dir_wait_counts[i]
		var col := Color(0.14, 0.85, 0.42)
		if w_cnt >= 6:
			col = Color(0.98, 0.22, 0.18)
		elif w_cnt >= 3:
			col = Color(0.98, 0.74, 0.14)
		var m := congestion_mats[i]
		m.albedo_color = col
		m.emission = col

func rebuild(ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool], itype: IntersectionType = IntersectionType.SIGNALIZED) -> void:
	intersection_type = itype
	if dynamic_root == null:
		return
	# Detach immediately so rapid lane-slider drags NEVER render two roads on the same frame!
	var old_children := dynamic_root.get_children()
	for c in old_children:
		dynamic_root.remove_child(c)
		c.queue_free()
	congestion_bars.clear()

	# Two MeshBatches: flat non-shadow-casting road/markings + shadow-casting structures (buildings/trees/poles/cones)
	var flat_batch := MeshBatch.new()
	var solid_batch := MeshBatch.new()

	# Ground base plane cleanly 0.25m below road surface
	flat_batch.add_box(Vector3(0, -0.45, 0), Vector3(480, 0.4, 480), grass_mat)

	if itype == IntersectionType.ROUNDABOUT:
		_build_roundabout_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)
	else:
		_build_signalized_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)

	# Commit entire world into ~14 batched MeshInstance3D draw calls (down from 1,500+!)
	flat_batch.commit_as_nodes(dynamic_root, false)
	solid_batch.commit_as_nodes(dynamic_root, true)

func _build_signalized_geometry(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var ns_half: float = ns_lanes * LANE_WIDTH
	var ew_half: float = ew_lanes * LANE_WIDTH
	var ns_width: float = ns_half * 2.0
	var ew_width: float = ew_half * 2.0
	var stop_z: float = ew_half + 3.2
	var stop_x: float = ns_half + 3.2

	var ns_arm_len: float = ROAD_HALF_LEN - ew_half
	var ns_arm_center: float = ew_half + ns_arm_len * 0.5
	var ew_arm_len: float = ROAD_HALF_LEN - ns_half
	var ew_arm_center: float = ns_half + ew_arm_len * 0.5

	# Non-overlapping road slabs (all tops cleanly at y = 0.0)
	flat_batch.add_box(Vector3(0, -0.10, 0), Vector3(ns_width, 0.20, ew_width), intersection_mat)
	flat_batch.add_box(Vector3(0, -0.10, -ns_arm_center), Vector3(ns_width, 0.20, ns_arm_len), asphalt_mat)
	flat_batch.add_box(Vector3(0, -0.10, ns_arm_center), Vector3(ns_width, 0.20, ns_arm_len), asphalt_mat)
	flat_batch.add_box(Vector3(ew_arm_center, -0.10, 0), Vector3(ew_arm_len, 0.20, ew_width), asphalt_mat)
	flat_batch.add_box(Vector3(-ew_arm_center, -0.10, 0), Vector3(ew_arm_len, 0.20, ew_width), asphalt_mat)

	_build_corner_blocks(flat_batch, solid_batch, ns_half, ew_half)
	_build_arm_markings(flat_batch, ns_lanes, ew_lanes, ns_half, ew_half, stop_z, stop_x, ew_half + 1.55, ns_half + 1.55, false)
	_build_congestion_bars(ns_half, ew_half, stop_z, stop_x)
	_build_lane_cones(solid_batch, ns_lanes, ew_lanes, stop_z, stop_x, lane_enabled, approach_enabled)

func _build_roundabout_geometry(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var ns_half: float = ns_lanes * LANE_WIDTH
	var ew_half: float = ew_lanes * LANE_WIDTH
	var rinfo := get_roundabout_radii(ns_lanes, ew_lanes)
	var ring_lanes: int = rinfo["ring_lanes"]
	var island_r: float = rinfo["island_r"]
	var outer_r: float = rinfo["outer_r"]
	var yield_dist: float = rinfo["yield_dist"]

	# 1. Circulatory asphalt disk (top at y = 0.0)
	flat_batch.add_cylinder(Vector3(0, -0.10, 0), outer_r, 0.20, intersection_mat, Vector3.ZERO, true)

	# 2. 4 exact-fit non-overlapping road arms meeting circular rim cleanly at y = 0.0
	_add_roundabout_arm_quads(flat_batch, ns_half, outer_r, true, -1.0)
	_add_roundabout_arm_quads(flat_batch, ns_half, outer_r, true, 1.0)
	_add_roundabout_arm_quads(flat_batch, ew_half, outer_r, false, 1.0)
	_add_roundabout_arm_quads(flat_batch, ew_half, outer_r, false, -1.0)

	# 3. Central Landscaped Island
	flat_batch.add_cylinder(Vector3(0, 0.14, 0), island_r, 0.28, sidewalk_mat, Vector3.ZERO, true)
	flat_batch.add_cylinder(Vector3(0, 0.36, 0), maxf(2.0, island_r - 0.65), 0.16, grass_mat, Vector3.ZERO, true)

	# Central monument
	solid_batch.add_tapered_cylinder(Vector3(0, 0.84, 0), 1.6, 2.2, 0.8, monument_mat, 16)
	solid_batch.add_tapered_cylinder(Vector3(0, 3.85, 0), 0.25, 0.85, 5.4, monument_mat, 12)

	# Ring of trees on central island
	var tree_ring_r := island_r - 2.6
	if tree_ring_r >= 3.0:
		var tree_cnt := clampi(int(tree_ring_r * 0.9), 4, 12)
		for i in range(tree_cnt):
			var ang := TAU * float(i) / float(tree_cnt)
			_add_tree(solid_batch, Vector3(cos(ang) * tree_ring_r, 0.44, sin(ang) * tree_ring_r))

	# 4. Dashed Circular Lane Lines (all batched into 1 draw call!)
	for l in range(1, ring_lanes):
		var lr := island_r + float(l) * LANE_WIDTH
		var circ := TAU * lr
		var dash_cnt := maxi(12, int(circ / 5.5))
		for d in range(dash_cnt):
			var a := TAU * float(d) / float(dash_cnt)
			flat_batch.add_plane_xz(Vector3(cos(a) * lr, 0.05, sin(a) * lr), Vector2(0.16, 2.4), white_line_mat, -a)

	# 5. Corner urban blocks outside roundabout circle
	var block_offset := maxf(outer_r + 1.5, maxf(ns_half, ew_half) + 1.5)
	_build_corner_blocks(flat_batch, solid_batch, block_offset, block_offset)

	# 6. Arm lane lines, yield lines, crosswalks, congestion bars, cones
	_build_arm_markings(flat_batch, ns_lanes, ew_lanes, ns_half, ew_half, yield_dist, yield_dist, yield_dist + 2.4, yield_dist + 2.4, true)
	_build_congestion_bars(ns_half, ew_half, yield_dist + 3.8, yield_dist + 3.8)
	_build_lane_cones(solid_batch, ns_lanes, ew_lanes, yield_dist + 1.5, yield_dist + 1.5, lane_enabled, approach_enabled)

func _add_roundabout_arm_quads(flat_batch: MeshBatch, half_w: float, outer_r: float, along_z: bool, dir_sign: float) -> void:
	var slices := 18
	for i in range(slices):
		var u0 := lerpf(-half_w, half_w, float(i) / float(slices))
		var u1 := lerpf(-half_w, half_w, float(i + 1) / float(slices))
		var r0 := sqrt(maxf(0.01, outer_r * outer_r - u0 * u0))
		var r1 := sqrt(maxf(0.01, outer_r * outer_r - u1 * u1))

		var p0: Vector3
		var p1: Vector3
		var p2: Vector3
		var p3: Vector3
		if along_z:
			p0 = Vector3(u0, 0.0, dir_sign * r0)
			p1 = Vector3(u1, 0.0, dir_sign * r1)
			p2 = Vector3(u1, 0.0, dir_sign * ROAD_HALF_LEN)
			p3 = Vector3(u0, 0.0, dir_sign * ROAD_HALF_LEN)
		else:
			p0 = Vector3(dir_sign * r0, 0.0, u0)
			p1 = Vector3(dir_sign * r1, 0.0, u1)
			p2 = Vector3(dir_sign * ROAD_HALF_LEN, 0.0, u1)
			p3 = Vector3(dir_sign * ROAD_HALF_LEN, 0.0, u0)
		flat_batch.add_quad_up(p0, p1, p2, p3, asphalt_mat)

func _build_corner_blocks(flat_batch: MeshBatch, solid_batch: MeshBatch, x_in: float, z_in: float) -> void:
	var sw_x_in := x_in + 0.04
	var sw_z_in := z_in + 0.04
	var sw_w := maxf(6.0, ROAD_HALF_LEN - sw_x_in)
	var sw_d := maxf(6.0, ROAD_HALF_LEN - sw_z_in)
	var sw_cx := sw_x_in + sw_w * 0.5
	var sw_cz := sw_z_in + sw_d * 0.5
	var corners := [
		Vector2(-1, -1),
		Vector2(1, -1),
		Vector2(-1, 1),
		Vector2(1, 1)
	]
	for idx in range(4):
		var s: Vector2 = corners[idx]
		flat_batch.add_box(Vector3(s.x * sw_cx, 0.05, s.y * sw_cz), Vector3(sw_w, 0.30, sw_d), sidewalk_mat)

		var px_in := x_in + 3.8
		var pz_in := z_in + 3.8
		var pw := ROAD_HALF_LEN - px_in - 1.0
		var pd := ROAD_HALF_LEN - pz_in - 1.0
		if pw > 4.0 and pd > 4.0:
			flat_batch.add_box(Vector3(s.x * (px_in + pw * 0.5), 0.26, s.y * (pz_in + pd * 0.5)), Vector3(pw, 0.12, pd), grass_mat)

		_add_street_lamp(solid_batch, flat_batch, Vector3(s.x * (x_in + 2.6), 0.20, s.y * (z_in + 2.6)), s)

		var bx := x_in + 10.5
		var bz := z_in + 10.5
		var heights := [12.0, 17.0, 9.5, 15.0]
		if bx + 8.0 < ROAD_HALF_LEN and bz + 8.0 < ROAD_HALF_LEN:
			_add_building(solid_batch, Vector3(s.x * (bx + 3.5), 0.32, s.y * (bz + 3.5)), Vector3(10.0, heights[idx], 10.0), building_mats[idx % building_mats.size()])
		if bx + 22.0 < ROAD_HALF_LEN and bz + 9.0 < ROAD_HALF_LEN:
			_add_building(solid_batch, Vector3(s.x * (bx + 18.0), 0.32, s.y * (bz + 4.5)), Vector3(11.0, heights[(idx + 2) % 4] * 0.85, 9.0), building_mats[(idx + 1) % building_mats.size()])
		if bx + 9.0 < ROAD_HALF_LEN and bz + 22.0 < ROAD_HALF_LEN:
			_add_building(solid_batch, Vector3(s.x * (bx + 4.5), 0.32, s.y * (bz + 18.0)), Vector3(9.0, heights[(idx + 1) % 4] * 0.9, 11.0), building_mats[(idx + 3) % building_mats.size()])

		if x_in + 6.0 < ROAD_HALF_LEN and z_in + 6.0 < ROAD_HALF_LEN:
			_add_tree(solid_batch, Vector3(s.x * (x_in + 5.6), 0.32, s.y * (z_in + 5.6)))
		if x_in + 16.0 < ROAD_HALF_LEN and z_in + 6.0 < ROAD_HALF_LEN:
			_add_tree(solid_batch, Vector3(s.x * (x_in + 16.0), 0.32, s.y * (z_in + 6.0)))
		if x_in + 6.0 < ROAD_HALF_LEN and z_in + 16.0 < ROAD_HALF_LEN:
			_add_tree(solid_batch, Vector3(s.x * (x_in + 6.0), 0.32, s.y * (z_in + 16.0)))

func _build_arm_markings(flat_batch: MeshBatch, ns_lanes: int, ew_lanes: int, ns_half: float, ew_half: float, stop_z: float, stop_x: float, cw_z_dist: float, cw_x_dist: float, is_yield: bool) -> void:
	var mark_y: float = 0.05

	var ns_mark_start := (cw_z_dist + 1.5) if is_yield else (stop_z + 0.3)
	var ns_mark_len := maxf(2.0, ROAD_HALF_LEN - ns_mark_start)
	var ns_mark_mid := ns_mark_start + ns_mark_len * 0.5
	for sign_z in [-1.0, 1.0]:
		var sz: float = float(sign_z)
		flat_batch.add_plane_xz(Vector3(-0.15, mark_y, sz * ns_mark_mid), Vector2(0.14, ns_mark_len), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(0.15, mark_y, sz * ns_mark_mid), Vector2(0.14, ns_mark_len), yellow_line_mat)

		for l in range(1, ns_lanes):
			var lx := l * LANE_WIDTH
			var z_pos := ns_mark_start + 2.5
			while z_pos < ROAD_HALF_LEN - 2.0:
				flat_batch.add_plane_xz(Vector3(-lx, mark_y, sz * z_pos), Vector2(0.14, 2.8), white_line_mat)
				flat_batch.add_plane_xz(Vector3(lx, mark_y, sz * z_pos), Vector2(0.14, 2.8), white_line_mat)
				z_pos += 6.0

		var incoming_x_sign: float = sz
		if is_yield:
			var sx_pos := 0.7
			while sx_pos < ns_half - 0.5:
				flat_batch.add_plane_xz(Vector3(incoming_x_sign * sx_pos, mark_y, sz * stop_z), Vector2(0.85, 0.50), white_line_mat)
				sx_pos += 1.65
		else:
			flat_batch.add_plane_xz(Vector3(incoming_x_sign * (ns_half * 0.5), mark_y, sz * stop_z), Vector2(ns_half - 0.3, 0.45), white_line_mat)

		var cw_z: float = sz * cw_z_dist
		var stripe_x := -ns_half + 0.9
		while stripe_x <= ns_half - 0.8:
			flat_batch.add_plane_xz(Vector3(stripe_x, mark_y, cw_z), Vector2(0.75, 2.0), white_line_mat)
			stripe_x += 1.75

	var ew_mark_start := (cw_x_dist + 1.5) if is_yield else (stop_x + 0.3)
	var ew_mark_len := maxf(2.0, ROAD_HALF_LEN - ew_mark_start)
	var ew_mark_mid := ew_mark_start + ew_mark_len * 0.5
	for sign_x in [-1.0, 1.0]:
		var sx: float = float(sign_x)
		flat_batch.add_plane_xz(Vector3(sx * ew_mark_mid, mark_y, -0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(sx * ew_mark_mid, mark_y, 0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)

		for l in range(1, ew_lanes):
			var lz := l * LANE_WIDTH
			var x_pos := ew_mark_start + 2.5
			while x_pos < ROAD_HALF_LEN - 2.0:
				flat_batch.add_plane_xz(Vector3(sx * x_pos, mark_y, -lz), Vector2(2.8, 0.14), white_line_mat)
				flat_batch.add_plane_xz(Vector3(sx * x_pos, mark_y, lz), Vector2(2.8, 0.14), white_line_mat)
				x_pos += 6.0

		var incoming_z_sign: float = -sx
		if is_yield:
			var sz_pos := 0.7
			while sz_pos < ew_half - 0.5:
				flat_batch.add_plane_xz(Vector3(sx * stop_x, mark_y, incoming_z_sign * sz_pos), Vector2(0.50, 0.85), white_line_mat)
				sz_pos += 1.65
		else:
			flat_batch.add_plane_xz(Vector3(sx * stop_x, mark_y, incoming_z_sign * (ew_half * 0.5)), Vector2(0.45, ew_half - 0.3), white_line_mat)

		var cw_x: float = sx * cw_x_dist
		var stripe_z := -ew_half + 0.9
		while stripe_z <= ew_half - 0.8:
			flat_batch.add_plane_xz(Vector3(cw_x, mark_y, stripe_z), Vector2(2.0, 0.75), white_line_mat)
			stripe_z += 1.75

func _build_congestion_bars(ns_half: float, ew_half: float, start_z: float, start_x: float) -> void:
	var strip_len := 22.0
	var strip_y := 0.24
	congestion_bars.append(_add_congestion_bar(Vector3(0.65, 0.08, strip_len), Vector3(-(ns_half + 0.85), strip_y, -(start_z + strip_len * 0.5 + 1.0)), congestion_mats[0]))
	congestion_bars.append(_add_congestion_bar(Vector3(0.65, 0.08, strip_len), Vector3(ns_half + 0.85, strip_y, start_z + strip_len * 0.5 + 1.0), congestion_mats[1]))
	congestion_bars.append(_add_congestion_bar(Vector3(strip_len, 0.08, 0.65), Vector3(start_x + strip_len * 0.5 + 1.0, strip_y, -(ew_half + 0.85)), congestion_mats[2]))
	congestion_bars.append(_add_congestion_bar(Vector3(strip_len, 0.08, 0.65), Vector3(-(start_x + strip_len * 0.5 + 1.0), strip_y, ew_half + 0.85), congestion_mats[3]))

func _build_lane_cones(solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, stop_z: float, stop_x: float, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	for a in range(4):
		var f: Vector3 = forwards[a]
		var r: Vector3 = rights[a]
		var is_ns := (a == 0 or a == 1)
		var l_cnt := ns_lanes if is_ns else ew_lanes
		var s_dist := stop_z if is_ns else stop_x
		for l in range(l_cnt):
			var closed: bool = (not approach_enabled[a]) or (l < lane_enabled.size() and not lane_enabled[l])
			if closed:
				var d := (l + 0.5) * LANE_WIDTH
				for dist in [s_dist + 2.5, s_dist + 8.5, s_dist + 14.5]:
					var pos: Vector3 = -f * float(dist) + r * d
					_add_cone(solid_batch, pos)

func _add_congestion_bar(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = congestion_overlay_enabled
	dynamic_root.add_child(mi)
	return mi

func _add_street_lamp(solid_batch: MeshBatch, flat_batch: MeshBatch, base_pos: Vector3, corner_sign: Vector2) -> void:
	solid_batch.add_tapered_cylinder(base_pos + Vector3(0, 3.6, 0), 0.09, 0.13, 7.2, lamp_pole_mat, 8)
	flat_batch.add_sphere(base_pos + Vector3(-corner_sign.x * 0.7, 7.15, -corner_sign.y * 0.7), 0.34, 0.45, lamp_bulb_mat)

func _add_building(solid_batch: MeshBatch, base_pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> void:
	solid_batch.add_box(base_pos + Vector3(0, sz.y * 0.5, 0), sz, mat)
	solid_batch.add_box(base_pos + Vector3(0, sz.y + 0.24, 0), Vector3(sz.x + 0.4, 0.45, sz.z + 0.4), sidewalk_mat)

func _add_tree(solid_batch: MeshBatch, base_pos: Vector3) -> void:
	solid_batch.add_tapered_cylinder(base_pos + Vector3(0, 1.1, 0), 0.22, 0.30, 2.2, trunk_mat, 8)
	solid_batch.add_sphere(base_pos + Vector3(0, 3.2, 0), 1.65, 3.1, foliage_mat)

func _add_cone(solid_batch: MeshBatch, pos: Vector3) -> void:
	solid_batch.add_box(pos + Vector3(0, 0.08, 0), Vector3(0.65, 0.08, 0.65), cone_mat)
	solid_batch.add_tapered_cylinder(pos + Vector3(0, 0.51, 0), 0.06, 0.24, 0.78, cone_mat, 8)
	solid_batch.add_tapered_cylinder(pos + Vector3(0, 0.59, 0), 0.145, 0.185, 0.16, cone_stripe_mat, 8)
