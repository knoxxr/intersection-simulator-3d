extends Node3D
class_name RoadBuilder

const LANE_WIDTH: float = 3.5
const ROAD_HALF_LEN: float = 115.0

enum TimeOfDay { DAY, SUNSET, NIGHT }
enum IntersectionType { SIGNALIZED, ROUNDABOUT, UNDERPASS, OVERPASS, TRI_LEVEL }

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
var concrete_wall_mat: StandardMaterial3D
var portal_trim_mat: StandardMaterial3D
var tunnel_light_mat: StandardMaterial3D
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
	var island_r := maxf(6.8, 5.5 + float(ring_lanes) * 1.45)
	var outer_r := island_r + float(ring_lanes) * LANE_WIDTH
	var yield_dist := outer_r + 1.15
	return {
		"ring_lanes": ring_lanes,
		"island_r": island_r,
		"outer_r": outer_r,
		"yield_dist": yield_dist
	}

static func get_underpass_layout(ns_lanes: int, ew_lanes: int) -> Dictionary:
	var u_lanes := 1 if ns_lanes <= 1 else clampi(int((ns_lanes + 1) / 2), 1, ns_lanes - 1)
	var s_lanes := ns_lanes - u_lanes
	var under_half := float(u_lanes) * LANE_WIDTH + 0.40
	var wall_w := 0.95
	var surf_w := float(s_lanes) * LANE_WIDTH
	var total_ns_half := under_half + wall_w + surf_w
	var ew_half := float(ew_lanes) * LANE_WIDTH
	var portal_z := ew_half + 4.8
	var z_bot := portal_z + 2.5
	var z_top := minf(ROAD_HALF_LEN - 14.0, z_bot + 44.0)
	return {
		"u_lanes": u_lanes,
		"s_lanes": s_lanes,
		"under_half": under_half,
		"wall_w": wall_w,
		"surf_w": surf_w,
		"total_ns_half": total_ns_half,
		"ew_half": ew_half,
		"portal_z": portal_z,
		"z_bot": z_bot,
		"z_top": z_top,
		"depth": -5.4
	}

static func get_tri_level_layout(ns_lanes: int, ew_lanes: int) -> Dictionary:
	var wall_w := 0.95
	var ns_u := 1 if ns_lanes <= 1 else clampi(int((ns_lanes + 1) / 2), 1, ns_lanes - 1)
	var ns_s := ns_lanes - ns_u
	var ns_bridge_half := float(ns_u) * LANE_WIDTH + 0.40
	var ns_wall_outer := ns_bridge_half + wall_w
	var ns_surf_w := float(ns_s) * LANE_WIDTH
	var total_ns_half := ns_wall_outer + ns_surf_w

	var ew_u := 1 if ew_lanes <= 1 else clampi(int((ew_lanes + 1) / 2), 1, ew_lanes - 1)
	var ew_s := ew_lanes - ew_u
	var ew_under_half := float(ew_u) * LANE_WIDTH + 0.40
	var ew_wall_outer := ew_under_half + wall_w
	var ew_surf_w := float(ew_s) * LANE_WIDTH
	var total_ew_half := ew_wall_outer + ew_surf_w

	var ew_portal_x := total_ns_half + 4.8
	var ew_x_bot := ew_portal_x + 2.5
	var ew_x_top := minf(ROAD_HALF_LEN - 12.0, ew_x_bot + 42.0)

	var ns_z_bot := total_ew_half + 6.5
	var ns_z_top := minf(ROAD_HALF_LEN - 12.0, ns_z_bot + 42.0)

	return {
		"wall_w": wall_w,
		"ns_u": ns_u,
		"ns_s": ns_s,
		"ns_bridge_half": ns_bridge_half,
		"ns_wall_outer": ns_wall_outer,
		"ns_surf_w": ns_surf_w,
		"total_ns_half": total_ns_half,
		"ns_z_bot": ns_z_bot,
		"ns_z_top": ns_z_top,
		"ew_u": ew_u,
		"ew_s": ew_s,
		"ew_under_half": ew_under_half,
		"ew_wall_outer": ew_wall_outer,
		"ew_surf_w": ew_surf_w,
		"total_ew_half": total_ew_half,
		"ew_portal_x": ew_portal_x,
		"ew_x_bot": ew_x_bot,
		"ew_x_top": ew_x_top,
		"height": 6.0,
		"depth": -5.4
	}

static func get_tri_level_lane_offset(lane_idx: int, is_ns: bool, lay: Dictionary) -> float:
	var u_cnt: int = lay["ns_u"] if is_ns else lay["ew_u"]
	if lane_idx < u_cnt:
		return (float(lane_idx) + 0.5) * LANE_WIDTH
	var s_idx := lane_idx - u_cnt
	var w_out: float = lay["ns_wall_outer"] if is_ns else lay["ew_wall_outer"]
	return w_out + (float(s_idx) + 0.5) * LANE_WIDTH

static func get_underpass_y(abs_z: float, z_bot: float, z_top: float, depth: float = -5.4) -> float:
	if abs_z <= z_bot:
		return depth
	if abs_z >= z_top:
		return 0.0
	var t := (abs_z - z_bot) / maxf(0.1, z_top - z_bot)
	return depth * 0.5 * (1.0 + cos(PI * t))

static func get_underpass_lane_offset(lane_idx: int, layout: Dictionary) -> float:
	var u_lanes: int = layout["u_lanes"]
	if lane_idx < u_lanes:
		return (float(lane_idx) + 0.5) * LANE_WIDTH
	var s_idx := lane_idx - u_lanes
	return float(layout["under_half"]) + float(layout["wall_w"]) + (float(s_idx) + 0.5) * LANE_WIDTH

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
	concrete_wall_mat = _make_mat(Color(0.56, 0.58, 0.62), 0.86)
	portal_trim_mat = _make_mat(Color(0.16, 0.18, 0.22), 0.52)
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

	tunnel_light_mat = StandardMaterial3D.new()
	tunnel_light_mat.albedo_color = Color(0.98, 0.95, 0.86)
	tunnel_light_mat.roughness = 0.2
	tunnel_light_mat.emission_enabled = true
	tunnel_light_mat.emission = Color(1.0, 0.93, 0.76)
	tunnel_light_mat.emission_energy_multiplier = 1.6

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
			tunnel_light_mat.emission_energy_multiplier = 1.6
		TimeOfDay.SUNSET:
			sun_light.light_energy = 0.95
			sun_light.light_color = Color(1.0, 0.62, 0.34)
			sun_light.rotation_degrees = Vector3(-22, 62, 0)
			env.background_color = Color(0.78, 0.46, 0.34)
			env.ambient_light_color = Color(0.72, 0.50, 0.45)
			env.ambient_light_energy = 0.48
			lamp_bulb_mat.emission_energy_multiplier = 1.4
			tunnel_light_mat.emission_energy_multiplier = 2.4
		TimeOfDay.NIGHT:
			sun_light.light_energy = 0.28
			sun_light.light_color = Color(0.42, 0.56, 0.88)
			sun_light.rotation_degrees = Vector3(-60, -25, 0)
			env.background_color = Color(0.06, 0.09, 0.16)
			env.ambient_light_color = Color(0.24, 0.30, 0.46)
			env.ambient_light_energy = 0.42
			lamp_bulb_mat.emission_energy_multiplier = 2.8
			tunnel_light_mat.emission_energy_multiplier = 3.2

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

	if itype == IntersectionType.UNDERPASS:
		_build_underpass_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)
	elif itype == IntersectionType.TRI_LEVEL:
		_build_tri_level_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)
	else:
		# Ground base plane cleanly 0.25m below road surface
		flat_batch.add_box(Vector3(0, -0.45, 0), Vector3(480, 0.4, 480), grass_mat)
		if itype == IntersectionType.ROUNDABOUT:
			_build_roundabout_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)
		elif itype == IntersectionType.OVERPASS:
			_build_overpass_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)
		else:
			_build_signalized_geometry(flat_batch, solid_batch, ns_lanes, ew_lanes, lane_enabled, approach_enabled)

	# Commit entire world into ~16-32 batched MeshInstance3D draw calls (down from 1,500+!)
	flat_batch.commit_as_nodes(dynamic_root, false)
	solid_batch.commit_as_nodes(dynamic_root, true)

func _build_tri_level_geometry(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var lay := get_tri_level_layout(ns_lanes, ew_lanes)
	var wall_w: float = lay["wall_w"]
	var ns_u: int = lay["ns_u"]
	var ns_s: int = lay["ns_s"]
	var ns_bridge_half: float = lay["ns_bridge_half"]
	var ns_wall_outer: float = lay["ns_wall_outer"]
	var ns_surf_w: float = lay["ns_surf_w"]
	var total_ns_half: float = lay["total_ns_half"]
	var ns_z_bot: float = lay["ns_z_bot"]
	var ns_z_top: float = lay["ns_z_top"]

	var ew_u: int = lay["ew_u"]
	var ew_s: int = lay["ew_s"]
	var ew_under_half: float = lay["ew_under_half"]
	var ew_wall_outer: float = lay["ew_wall_outer"]
	var ew_surf_w: float = lay["ew_surf_w"]
	var total_ew_half: float = lay["total_ew_half"]
	var ew_portal_x: float = lay["ew_portal_x"]
	var ew_x_bot: float = lay["ew_x_bot"]
	var ew_x_top: float = lay["ew_x_top"]

	var height: float = lay["height"]
	var depth: float = lay["depth"]
	var girder_thick: float = 0.95
	var mark_y: float = 0.05

	var stop_z: float = total_ew_half + 3.2
	var stop_x: float = total_ns_half + 3.2
	var has_surface_cross: bool = (ns_s > 0 and ew_s > 0)

	# ==========================================================================
	# LEVEL -1: E-W UNDERGROUND UNDERPASS ALONG X AXIS (y = -5.4m)
	# ==========================================================================
	# 1. Split grass base plane around the E-W sunken trough (|z| <= ew_wall_outer, |x| <= ew_x_top + 0.5)
	var cut_z := ew_wall_outer
	var cut_x := ew_x_top + 0.5
	var side_d := 240.0 - cut_z
	var end_w := 240.0 - cut_x
	flat_batch.add_box(Vector3(0.0, -0.45, -(cut_z + side_d * 0.5)), Vector3(480.0, 0.4, side_d), grass_mat)
	flat_batch.add_box(Vector3(0.0, -0.45, cut_z + side_d * 0.5), Vector3(480.0, 0.4, side_d), grass_mat)
	flat_batch.add_box(Vector3(-(cut_x + end_w * 0.5), -0.45, 0.0), Vector3(end_w, 0.4, cut_z * 2.0), grass_mat)
	flat_batch.add_box(Vector3(cut_x + end_w * 0.5, -0.45, 0.0), Vector3(end_w, 0.4, cut_z * 2.0), grass_mat)

	# 2. Deep E-W Tunnel Floor (|x| <= ew_x_bot at y = depth) + Tunnel Markings
	flat_batch.add_box(Vector3(0.0, depth - 0.12, 0.0), Vector3(ew_x_bot * 2.0, 0.24, ew_under_half * 2.0 + 0.4), intersection_mat)
	flat_batch.add_plane_xz(Vector3(0.0, depth + mark_y, -0.15), Vector2(ew_x_bot * 2.0, 0.14), yellow_line_mat)
	flat_batch.add_plane_xz(Vector3(0.0, depth + mark_y, 0.15), Vector2(ew_x_bot * 2.0, 0.14), yellow_line_mat)
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		flat_batch.add_plane_xz(Vector3(0.0, depth + mark_y, fz * (ew_under_half - 0.18)), Vector2(ew_x_bot * 2.0, 0.14), white_line_mat)
		for l in range(1, ew_u):
			var lz := float(l) * LANE_WIDTH
			var xp := -ew_x_bot + 1.8
			while xp < ew_x_bot - 1.5:
				flat_batch.add_plane_xz(Vector3(xp, depth + mark_y, fz * lz), Vector2(2.6, 0.14), white_line_mat)
				xp += 5.6

	# 3. Covered E-W Tunnel Walls, Support Piers, and Ceiling Warm LED Strips (|x| <= ew_portal_x)
	var tunnel_wall_h := (-0.85) - (depth - 0.12)
	var tunnel_wall_cy := (depth - 0.12) + tunnel_wall_h * 0.5
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		flat_batch.add_box(Vector3(0.0, tunnel_wall_cy, fz * (ew_under_half + wall_w * 0.5)), Vector3(ew_portal_x * 2.0, tunnel_wall_h, wall_w), concrete_wall_mat)
		var led_z := fz * (ew_under_half * 0.5)
		var lx := -ew_portal_x + 2.4
		while lx <= ew_portal_x - 2.0:
			flat_batch.add_box(Vector3(lx, -0.89, led_z), Vector3(2.2, 0.08, minf(1.8, ew_under_half * 0.55)), tunnel_light_mat)
			lx += 5.4

	var t_pier_x := -ew_portal_x + 3.5
	while t_pier_x <= ew_portal_x - 3.0:
		solid_batch.add_box(Vector3(t_pier_x, tunnel_wall_cy, 0.0), Vector3(1.25, tunnel_wall_h, 0.46), concrete_wall_mat)
		t_pier_x += 7.0

	# 4. E-W S-Curve Underpass Ramps along ±X (|x| from ew_x_bot to ew_x_top)
	var slices := 22
	var ew_taper := ew_x_top - 5.0
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		for i in range(slices):
			var xa := lerpf(ew_x_bot, ew_x_top, float(i) / float(slices))
			var xb := lerpf(ew_x_bot, ew_x_top, float(i + 1) / float(slices))
			var ya := get_underpass_y(xa, ew_x_bot, ew_x_top, depth)
			var yb := get_underpass_y(xb, ew_x_bot, ew_x_top, depth)
			var x0 := fx * xa
			var x1 := fx * xb
			var n_up := Vector3(-(yb - ya) * fx, xb - xa, 0.0).normalized()

			# Sloped asphalt roadbed
			flat_batch.add_quad_normal(
				Vector3(x0, ya, -ew_under_half),
				Vector3(x0, ya, ew_under_half),
				Vector3(x1, yb, ew_under_half),
				Vector3(x1, yb, -ew_under_half),
				n_up,
				asphalt_mat
			)

			# Ramp markings along X
			for side_s in [-1.0, 1.0]:
				var zc: float = float(side_s) * 0.15
				flat_batch.add_quad_normal(
					Vector3(x0, ya + mark_y, zc - 0.07),
					Vector3(x0, ya + mark_y, zc + 0.07),
					Vector3(x1, yb + mark_y, zc + 0.07),
					Vector3(x1, yb + mark_y, zc - 0.07),
					n_up,
					yellow_line_mat
				)
				var ze: float = float(side_s) * (ew_under_half - 0.18)
				flat_batch.add_quad_normal(
					Vector3(x0, ya + mark_y, ze - 0.07),
					Vector3(x0, ya + mark_y, ze + 0.07),
					Vector3(x1, yb + mark_y, ze + 0.07),
					Vector3(x1, yb + mark_y, ze - 0.07),
					n_up,
					white_line_mat
				)
				if i % 2 == 0:
					for l in range(1, ew_u):
						var zl: float = float(side_s) * float(l) * LANE_WIDTH
						flat_batch.add_quad_normal(
							Vector3(x0, ya + mark_y, zl - 0.07),
							Vector3(x0, ya + mark_y, zl + 0.07),
							Vector3(x1, yb + mark_y, zl + 0.07),
							Vector3(x1, yb + mark_y, zl - 0.07),
							n_up,
							white_line_mat
						)

			# E-W retaining walls along z = ±ew_under_half .. ±ew_wall_outer
			var yt_a := 0.92 if xa <= ew_taper else lerpf(0.92, 0.18, clampf((xa - ew_taper) / 5.0, 0.0, 1.0))
			var yt_b := 0.92 if xb <= ew_taper else lerpf(0.92, 0.18, clampf((xb - ew_taper) / 5.0, 0.0, 1.0))
			for sz in [-1.0, 1.0]:
				var fz: float = float(sz)
				var zi := fz * ew_under_half
				var zo := fz * ew_wall_outer
				flat_batch.add_quad_normal(
					Vector3(x0, ya - 0.08, zi),
					Vector3(x1, yb - 0.08, zi),
					Vector3(x1, yt_b, zi),
					Vector3(x0, yt_a, zi),
					Vector3(0.0, 0.0, -fz),
					concrete_wall_mat
				)
				flat_batch.add_quad_normal(
					Vector3(x0, -0.04, zo),
					Vector3(x1, -0.04, zo),
					Vector3(x1, yt_b, zo),
					Vector3(x0, yt_a, zo),
					Vector3(0.0, 0.0, fz),
					concrete_wall_mat
				)
				flat_batch.add_quad_up(
					Vector3(x0, yt_a, zi),
					Vector3(x0, yt_a, zo),
					Vector3(x1, yt_b, zo),
					Vector3(x1, yt_b, zi),
					sidewalk_mat
				)

		# Deep stub walls between ew_portal_x and ew_x_bot
		var stub_len := ew_x_bot - ew_portal_x
		if stub_len > 0.05:
			var stub_cx := fx * (ew_portal_x + stub_len * 0.5)
			var stub_h := 0.92 - (depth - 0.12)
			var stub_cy := (depth - 0.12) + stub_h * 0.5
			for sz in [-1.0, 1.0]:
				var fz: float = float(sz)
				flat_batch.add_box(Vector3(stub_cx, stub_cy, fz * (ew_under_half + wall_w * 0.5)), Vector3(stub_len, stub_h, wall_w), concrete_wall_mat)

		# Safety guardrail bar along E-W retaining wall top
		var rail_len := maxf(0.0, ew_taper - ew_portal_x)
		if rail_len > 0.5:
			var rail_cx := fx * (ew_portal_x + rail_len * 0.5)
			for sz in [-1.0, 1.0]:
				var fz: float = float(sz)
				solid_batch.add_box(Vector3(rail_cx, 1.08, fz * (ew_under_half + wall_w * 0.5)), Vector3(rail_len, 0.08, 0.12), portal_trim_mat)

		# Flat ground-level E-W express approach beyond ramp top (ew_x_top .. ROAD_HALF_LEN)
		var app_len := maxf(1.0, ROAD_HALF_LEN - ew_x_top)
		var app_cx := fx * (ew_x_top + app_len * 0.5)
		flat_batch.add_box(Vector3(app_cx, -0.10, 0.0), Vector3(app_len, 0.20, ew_under_half * 2.0), asphalt_mat)
		flat_batch.add_plane_xz(Vector3(app_cx, mark_y, -0.15), Vector2(app_len, 0.14), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(app_cx, mark_y, 0.15), Vector2(app_len, 0.14), yellow_line_mat)
		for sz in [-1.0, 1.0]:
			var fz: float = float(sz)
			flat_batch.add_plane_xz(Vector3(app_cx, mark_y, fz * (ew_under_half - 0.18)), Vector2(app_len, 0.14), white_line_mat)
			flat_batch.add_box(Vector3(app_cx, 0.07, fz * (ew_under_half + wall_w * 0.5)), Vector3(app_len, 0.18, wall_w), sidewalk_mat)
			for l in range(1, ew_u):
				var lz := float(l) * LANE_WIDTH
				var xp := ew_x_top + 2.2
				while xp < ROAD_HALF_LEN - 2.0:
					flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, fz * lz), Vector2(2.8, 0.14), white_line_mat)
					xp += 6.0

		# E-W express straight arrows before ramp dive (East fx=+1 -> incoming -Z; West fx=-1 -> incoming +Z)
		var in_z_sign := -fx
		var fwd_in := Vector3(-fx, 0.0, 0.0)
		var rt_in := Vector3(0.0, 0.0, in_z_sign)
		for l in range(ew_u):
			var az := in_z_sign * (float(l) + 0.5) * LANE_WIDTH
			_add_pavement_arrow(flat_batch, Vector3(fx * (ew_x_top + 5.5), mark_y, az), fwd_in, rt_in, white_line_mat)

	# 5. E-W Tunnel Structural Deck Roof & Portals (|x| <= ew_portal_x)
	solid_batch.add_box(Vector3(0.0, -0.475, 0.0), Vector3(ew_portal_x * 2.0, 0.75, ew_wall_outer * 2.0), concrete_wall_mat)
	var plaza_w := ew_portal_x - total_ns_half
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_box(Vector3(fx * (total_ns_half + plaza_w * 0.5), 0.03, 0.0), Vector3(plaza_w, 0.26, ew_wall_outer * 2.0), sidewalk_mat)
		solid_batch.add_box(Vector3(fx * (ew_portal_x - 0.38), 0.58, 0.0), Vector3(0.72, 0.86, ew_wall_outer * 2.0), concrete_wall_mat)
		solid_batch.add_box(Vector3(fx * (ew_portal_x - 0.38), 1.12, 0.0), Vector3(0.14, 0.09, ew_wall_outer * 2.0), portal_trim_mat)

		# Portal steel lintel + alternating yellow/black 4.5m clearance hazard bars facing ±X
		var face_x := fx * (ew_portal_x + 0.06)
		solid_batch.add_box(Vector3(face_x, -0.48, 0.0), Vector3(0.16, 0.76, ew_under_half * 2.0 + 0.6), portal_trim_mat)
		var stripe_w := 1.15
		var sz_pos := -ew_under_half + stripe_w * 0.5
		var s_idx := 0
		while sz_pos < ew_under_half - 0.2:
			var sw := minf(stripe_w, ew_under_half - (sz_pos - stripe_w * 0.5))
			var smat := yellow_line_mat if (s_idx % 2 == 0) else portal_trim_mat
			flat_batch.add_box(Vector3(fx * (ew_portal_x + 0.15), -0.56, sz_pos), Vector3(0.06, 0.42, sw - 0.04), smat)
			sz_pos += stripe_w
			s_idx += 1

	# ==========================================================================
	# LEVEL 0: SURFACE INTERSECTION & FRONTAGE ROADS FOR BOTH AXES (y = 0.0m)
	# ==========================================================================
	flat_batch.add_box(Vector3(0.0, -0.05, 0.0), Vector3(total_ns_half * 2.0, 0.10, total_ew_half * 2.0), intersection_mat)

	# Under-bridge concrete pier islands along N-S (|z| in [total_ew_half, ns_z_top], |x| <= ns_wall_outer)
	var ns_island_len := maxf(1.0, ns_z_top - total_ew_half)
	var ns_island_cz := total_ew_half + ns_island_len * 0.5
	for sz in [-1.0, 1.0]:
		flat_batch.add_box(Vector3(0.0, -0.02, float(sz) * ns_island_cz), Vector3(ns_wall_outer * 2.0, 0.20, ns_island_len), sidewalk_mat)

	# Surface N-S frontage roads (when ns_s > 0)
	if ns_s > 0:
		var ns_f_len := ROAD_HALF_LEN - total_ew_half
		var ns_f_cz := total_ew_half + ns_f_len * 0.5
		var ns_f_cx := ns_wall_outer + ns_surf_w * 0.5
		for sz in [-1.0, 1.0]:
			var fz: float = float(sz)
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				flat_batch.add_box(Vector3(fx * ns_f_cx, -0.10, fz * ns_f_cz), Vector3(ns_surf_w, 0.20, ns_f_len), asphalt_mat)
				for sl in range(1, ns_s):
					var lx := ns_wall_outer + float(sl) * LANE_WIDTH
					var zp := stop_z + 2.6
					while zp < ROAD_HALF_LEN - 2.0:
						flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
						zp += 6.0
				if has_surface_cross:
					var cw_z := fz * (total_ew_half + 1.55)
					var u_s := ns_wall_outer + 0.75
					while u_s <= total_ns_half - 0.65:
						flat_batch.add_plane_xz(Vector3(fx * u_s, mark_y, cw_z), Vector2(0.75, 2.0), white_line_mat)
						u_s += 1.72
			if has_surface_cross:
				var incoming_x_sign: float = fz
				flat_batch.add_plane_xz(Vector3(incoming_x_sign * ns_f_cx, mark_y, fz * stop_z), Vector2(ns_surf_w - 0.3, 0.45), white_line_mat)

	# Surface E-W frontage roads (when ew_s > 0)
	if ew_s > 0:
		var ew_f_len := ROAD_HALF_LEN - total_ns_half
		var ew_f_cx := total_ns_half + ew_f_len * 0.5
		var ew_f_cz := ew_wall_outer + ew_surf_w * 0.5
		for sx in [-1.0, 1.0]:
			var fx: float = float(sx)
			for sz in [-1.0, 1.0]:
				var fz: float = float(sz)
				flat_batch.add_box(Vector3(fx * ew_f_cx, -0.10, fz * ew_f_cz), Vector3(ew_f_len, 0.20, ew_surf_w), asphalt_mat)
				for sl in range(1, ew_s):
					var lz := ew_wall_outer + float(sl) * LANE_WIDTH
					var xp := stop_x + 2.6
					while xp < ROAD_HALF_LEN - 2.0:
						flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, fz * lz), Vector2(2.8, 0.14), white_line_mat)
						xp += 6.0
				if has_surface_cross:
					var cw_x := fx * (total_ns_half + 1.55)
					var u_e := ew_wall_outer + 0.75
					while u_e <= total_ew_half - 0.65:
						flat_batch.add_plane_xz(Vector3(cw_x, mark_y, fz * u_e), Vector2(2.0, 0.75), white_line_mat)
						u_e += 1.72
			if has_surface_cross:
				var incoming_z_sign: float = -fx
				flat_batch.add_plane_xz(Vector3(fx * stop_x, mark_y, incoming_z_sign * ew_f_cz), Vector2(0.45, ew_surf_w - 0.3), white_line_mat)

	# ==========================================================================
	# LEVEL +1: N-S ELEVATED OVERPASS VIADUCT ALONG Z AXIS (y = +6.0m)
	# ==========================================================================
	solid_batch.add_box(Vector3(0.0, height - girder_thick * 0.5 - 0.05, 0.0), Vector3(ns_wall_outer * 2.0, girder_thick - 0.10, ns_z_bot * 2.0), concrete_wall_mat)
	flat_batch.add_box(Vector3(0.0, height - 0.05, 0.0), Vector3(ns_bridge_half * 2.0, 0.10, ns_z_bot * 2.0), asphalt_mat)
	flat_batch.add_plane_xz(Vector3(-0.15, height + mark_y, 0.0), Vector2(0.14, ns_z_bot * 2.0), yellow_line_mat)
	flat_batch.add_plane_xz(Vector3(0.15, height + mark_y, 0.0), Vector2(0.14, ns_z_bot * 2.0), yellow_line_mat)
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_plane_xz(Vector3(fx * (ns_bridge_half - 0.18), height + mark_y, 0.0), Vector2(0.14, ns_z_bot * 2.0), white_line_mat)
		solid_batch.add_box(Vector3(fx * (ns_bridge_half + wall_w * 0.5), height + 0.45, 0.0), Vector3(wall_w, 0.90, ns_z_bot * 2.0), concrete_wall_mat)
		solid_batch.add_box(Vector3(fx * (ns_bridge_half + wall_w * 0.5), height + 1.03, 0.0), Vector3(0.14, 0.09, ns_z_bot * 2.0), portal_trim_mat)
		for l in range(1, ns_u):
			var lx := float(l) * LANE_WIDTH
			var zp := -ns_z_bot + 1.8
			while zp < ns_z_bot - 1.5:
				flat_batch.add_plane_xz(Vector3(fx * lx, height + mark_y, zp), Vector2(0.14, 2.6), white_line_mat)
				zp += 5.6

	# N-S S-Curve Elevated Ramps (|z| from ns_z_bot down to ns_z_top)
	var ns_taper := ns_z_top - 5.0
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		for i in range(slices):
			var za := lerpf(ns_z_bot, ns_z_top, float(i) / float(slices))
			var zb := lerpf(ns_z_bot, ns_z_top, float(i + 1) / float(slices))
			var ya := get_underpass_y(za, ns_z_bot, ns_z_top, height)
			var yb := get_underpass_y(zb, ns_z_bot, ns_z_top, height)
			var z0 := fz * za
			var z1 := fz * zb
			var n_up := Vector3(0.0, zb - za, -(yb - ya) * fz).normalized()
			var n_dn := -n_up

			flat_batch.add_quad_normal(
				Vector3(-ns_bridge_half, ya, z0),
				Vector3(ns_bridge_half, ya, z0),
				Vector3(ns_bridge_half, yb, z1),
				Vector3(-ns_bridge_half, yb, z1),
				n_up,
				asphalt_mat
			)

			var ya_bot := maxf(-0.04, ya - girder_thick) if ya > 2.4 else -0.04
			var yb_bot := maxf(-0.04, yb - girder_thick) if yb > 2.4 else -0.04
			if ya_bot > 0.1 or yb_bot > 0.1:
				flat_batch.add_quad_normal(
					Vector3(-ns_wall_outer, ya_bot, z0),
					Vector3(ns_wall_outer, ya_bot, z0),
					Vector3(ns_wall_outer, yb_bot, z1),
					Vector3(-ns_wall_outer, yb_bot, z1),
					n_dn,
					concrete_wall_mat
				)

			for side_s in [-1.0, 1.0]:
				var xc: float = float(side_s) * 0.15
				flat_batch.add_quad_normal(
					Vector3(xc - 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, yb + mark_y, z1),
					Vector3(xc - 0.07, yb + mark_y, z1),
					n_up,
					yellow_line_mat
				)
				var xe: float = float(side_s) * (ns_bridge_half - 0.18)
				flat_batch.add_quad_normal(
					Vector3(xe - 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, yb + mark_y, z1),
					Vector3(xe - 0.07, yb + mark_y, z1),
					n_up,
					white_line_mat
				)
				if i % 2 == 0:
					for l in range(1, ns_u):
						var xl: float = float(side_s) * float(l) * LANE_WIDTH
						flat_batch.add_quad_normal(
							Vector3(xl - 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, yb + mark_y, z1),
							Vector3(xl - 0.07, yb + mark_y, z1),
							n_up,
							white_line_mat
						)

			var par_a := 0.90 if za <= ns_taper else lerpf(0.90, 0.18, clampf((za - ns_taper) / 5.0, 0.0, 1.0))
			var par_b := 0.90 if zb <= ns_taper else lerpf(0.90, 0.18, clampf((zb - ns_taper) / 5.0, 0.0, 1.0))
			var top_a := ya + par_a
			var top_b := yb + par_b
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				var xi := fx * ns_bridge_half
				var xo := fx * ns_wall_outer
				flat_batch.add_quad_normal(
					Vector3(xi, ya - 0.05, z0),
					Vector3(xi, yb - 0.05, z1),
					Vector3(xi, top_b, z1),
					Vector3(xi, top_a, z0),
					Vector3(-fx, 0.0, 0.0),
					concrete_wall_mat
				)
				flat_batch.add_quad_normal(
					Vector3(xo, ya_bot, z0),
					Vector3(xo, yb_bot, z1),
					Vector3(xo, top_b, z1),
					Vector3(xo, top_a, z0),
					Vector3(fx, 0.0, 0.0),
					concrete_wall_mat
				)
				flat_batch.add_quad_normal(
					Vector3(xi, top_a, z0),
					Vector3(xo, top_a, z0),
					Vector3(xo, top_b, z1),
					Vector3(xi, top_b, z1),
					n_up,
					sidewalk_mat
				)
				if za <= ns_taper:
					var rmid := fx * (ns_bridge_half + wall_w * 0.5)
					flat_batch.add_quad_normal(
						Vector3(rmid - 0.06, top_a + 0.12, z0),
						Vector3(rmid + 0.06, top_a + 0.12, z0),
						Vector3(rmid + 0.06, top_b + 0.12, z1),
						Vector3(rmid - 0.06, top_b + 0.12, z1),
						n_up,
						portal_trim_mat
					)

		# Flat ground-level N-S express approach beyond ramp foot (ns_z_top .. ROAD_HALF_LEN)
		var ns_app_len := maxf(1.0, ROAD_HALF_LEN - ns_z_top)
		var ns_app_cz := fz * (ns_z_top + ns_app_len * 0.5)
		flat_batch.add_box(Vector3(0.0, -0.10, ns_app_cz), Vector3(ns_bridge_half * 2.0, 0.20, ns_app_len), asphalt_mat)
		flat_batch.add_plane_xz(Vector3(-0.15, mark_y, ns_app_cz), Vector2(0.14, ns_app_len), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(0.15, mark_y, ns_app_cz), Vector2(0.14, ns_app_len), yellow_line_mat)
		for sx in [-1.0, 1.0]:
			var fx: float = float(sx)
			flat_batch.add_plane_xz(Vector3(fx * (ns_bridge_half - 0.18), mark_y, ns_app_cz), Vector2(0.14, ns_app_len), white_line_mat)
			flat_batch.add_box(Vector3(fx * (ns_bridge_half + wall_w * 0.5), 0.07, ns_app_cz), Vector3(wall_w, 0.18, ns_app_len), sidewalk_mat)
			for l in range(1, ns_u):
				var lx := float(l) * LANE_WIDTH
				var zp := ns_z_top + 2.2
				while zp < ROAD_HALF_LEN - 2.0:
					flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
					zp += 6.0

		var in_x_sign := fz
		var fwd_in_ns := Vector3(0.0, 0.0, -fz)
		var rt_in_ns := Vector3(in_x_sign, 0.0, 0.0)
		for l in range(ns_u):
			var ax := in_x_sign * (float(l) + 0.5) * LANE_WIDTH
			_add_pavement_arrow(flat_batch, Vector3(ax, mark_y, fz * (ns_z_top + 5.5)), fwd_in_ns, rt_in_ns, white_line_mat)

	# Concrete Bridge T-Piers strictly OUTSIDE the E-W roadway & underpass trough (|z| >= total_ew_half + 2.6)
	var b_pier_z := total_ew_half + 2.6
	while b_pier_z < ns_z_top - 10.0:
		var deck_y := get_underpass_y(b_pier_z, ns_z_bot, ns_z_top, height)
		var under_y := deck_y - girder_thick
		if under_y >= 2.2:
			for sz in [-1.0, 1.0]:
				var pz := float(sz) * b_pier_z
				solid_batch.add_box(Vector3(0.0, under_y - 0.38, pz), Vector3(ns_bridge_half * 1.92, 0.78, 1.45), concrete_wall_mat)
				var col_h := under_y - 0.75
				var col_cy := col_h * 0.5
				if ns_bridge_half <= 5.5:
					solid_batch.add_cylinder(Vector3(0.0, col_cy, pz), 0.65, col_h, concrete_wall_mat, Vector3.ZERO, false)
				else:
					var col_off := ns_bridge_half * 0.54
					solid_batch.add_cylinder(Vector3(-col_off, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
					solid_batch.add_cylinder(Vector3(col_off, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
					if ns_bridge_half >= 14.0:
						solid_batch.add_cylinder(Vector3(0.0, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
		b_pier_z += 11.0

	# Double-Arm Highway Streetlamps along the Elevated Bridge Deck
	var lamp_z := 0.0
	while lamp_z <= ns_z_bot + 16.0:
		var ly := get_underpass_y(lamp_z, ns_z_bot, ns_z_top, height)
		var zs: Array = [0.0] if lamp_z < 0.1 else [-lamp_z, lamp_z]
		for z_item in zs:
			var zz: float = float(z_item)
			solid_batch.add_tapered_cylinder(Vector3(0.0, ly + 2.7, zz), 0.07, 0.11, 5.4, lamp_pole_mat, 8)
			solid_batch.add_box(Vector3(0.0, ly + 5.35, zz), Vector3(2.2, 0.09, 0.09), lamp_pole_mat)
			flat_batch.add_sphere(Vector3(-1.05, ly + 5.25, zz), 0.24, 0.30, lamp_bulb_mat)
			flat_batch.add_sphere(Vector3(1.05, ly + 5.25, zz), 0.24, 0.30, lamp_bulb_mat)
		lamp_z += 15.0

	# Corner Urban Blocks, Congestion Bars, and Construction Cones
	_build_corner_blocks(flat_batch, solid_batch, total_ns_half, total_ew_half)
	_build_congestion_bars(total_ns_half, total_ew_half, stop_z, stop_x)
	_build_tri_level_cones(solid_batch, ns_lanes, ew_lanes, lay, stop_z, stop_x, lane_enabled, approach_enabled)

func _build_tri_level_cones(solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lay: Dictionary, stop_z: float, stop_x: float, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	var ns_u: int = lay["ns_u"]
	var ew_u: int = lay["ew_u"]
	var ns_z_top: float = lay["ns_z_top"]
	var ew_x_top: float = lay["ew_x_top"]
	for a in range(4):
		var f: Vector3 = forwards[a]
		var r: Vector3 = rights[a]
		var is_ns := (a == 0 or a == 1)
		var l_cnt := ns_lanes if is_ns else ew_lanes
		var u_cnt := ns_u if is_ns else ew_u
		for l in range(l_cnt):
			var closed: bool = (not approach_enabled[a]) or (l < lane_enabled.size() and not lane_enabled[l])
			if closed:
				var d := get_tri_level_lane_offset(l, is_ns, lay)
				var s_dist: float
				if l < u_cnt:
					s_dist = (ns_z_top + 1.5) if is_ns else (ew_x_top + 1.5)
				else:
					s_dist = stop_z if is_ns else stop_x
				for dist in [s_dist + 2.5, s_dist + 8.5, s_dist + 14.5]:
					var pos: Vector3 = -f * float(dist) + r * d
					_add_cone(solid_batch, pos)

func _build_overpass_geometry(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var lay := get_underpass_layout(ns_lanes, ew_lanes)
	var u_lanes: int = lay["u_lanes"]
	var s_lanes: int = lay["s_lanes"]
	var bridge_half: float = lay["under_half"]
	var wall_w: float = lay["wall_w"]
	var surf_w: float = lay["surf_w"]
	var total_ns_half: float = lay["total_ns_half"]
	var ew_half: float = lay["ew_half"]
	var z_bot: float = lay["z_bot"]
	var z_top: float = lay["z_top"]
	var height: float = 6.0
	var girder_thick: float = 0.95
	var mark_y: float = 0.05

	var stop_z: float = ew_half + 3.2
	var stop_x: float = total_ns_half + 3.2
	var wall_outer: float = bridge_half + wall_w

	# 1. Surface Intersection Box & Full E-W Street passing cleanly underneath the overpass (y = 0.0)
	flat_batch.add_box(Vector3(0.0, -0.10, 0.0), Vector3(total_ns_half * 2.0, 0.20, ew_half * 2.0), intersection_mat)
	var ew_arm_len := ROAD_HALF_LEN - total_ns_half
	var ew_arm_center := total_ns_half + ew_arm_len * 0.5
	flat_batch.add_box(Vector3(ew_arm_center, -0.10, 0.0), Vector3(ew_arm_len, 0.20, ew_half * 2.0), asphalt_mat)
	flat_batch.add_box(Vector3(-ew_arm_center, -0.10, 0.0), Vector3(ew_arm_len, 0.20, ew_half * 2.0), asphalt_mat)

	# E-W road markings (under the bridge & along arms)
	var ew_mark_start := stop_x + 0.3 if s_lanes > 0 else total_ns_half + 0.3
	var ew_mark_len := maxf(2.0, ROAD_HALF_LEN - ew_mark_start)
	var ew_mark_mid := ew_mark_start + ew_mark_len * 0.5
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_plane_xz(Vector3(fx * ew_mark_mid, mark_y, -0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(fx * ew_mark_mid, mark_y, 0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)
		if s_lanes == 0:
			flat_batch.add_plane_xz(Vector3(0.0, mark_y, -0.15), Vector2(total_ns_half * 2.0, 0.14), yellow_line_mat)
			flat_batch.add_plane_xz(Vector3(0.0, mark_y, 0.15), Vector2(total_ns_half * 2.0, 0.14), yellow_line_mat)
		for l in range(1, ew_lanes):
			var lz := float(l) * LANE_WIDTH
			var xp := ew_mark_start + 2.5
			while xp < ROAD_HALF_LEN - 2.0:
				flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, -lz), Vector2(2.8, 0.14), white_line_mat)
				flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, lz), Vector2(2.8, 0.14), white_line_mat)
				xp += 6.0
		if s_lanes > 0:
			var incoming_z_sign: float = -fx
			flat_batch.add_plane_xz(Vector3(fx * stop_x, mark_y, incoming_z_sign * (ew_half * 0.5)), Vector2(0.45, ew_half - 0.3), white_line_mat)
			var cw_x := fx * (total_ns_half + 1.55)
			var stripe_z := -ew_half + 0.9
			while stripe_z <= ew_half - 0.8:
				flat_batch.add_plane_xz(Vector3(cw_x, mark_y, stripe_z), Vector2(2.0, 0.75), white_line_mat)
				stripe_z += 1.75

	# 2. Under-Bridge Pier Median Islands (|z| in [ew_half, z_top], |x| <= wall_outer) & Surface Frontage Roads
	var under_island_len := maxf(1.0, z_top - ew_half)
	var under_island_cz := ew_half + under_island_len * 0.5
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		flat_batch.add_box(Vector3(0.0, -0.02, fz * under_island_cz), Vector3(wall_outer * 2.0, 0.20, under_island_len), sidewalk_mat)

	if s_lanes > 0:
		var front_len := ROAD_HALF_LEN - ew_half
		var front_cz := ew_half + front_len * 0.5
		var front_cx := wall_outer + surf_w * 0.5
		for sz in [-1.0, 1.0]:
			var fz: float = float(sz)
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				flat_batch.add_box(Vector3(fx * front_cx, -0.10, fz * front_cz), Vector3(surf_w, 0.20, front_len), asphalt_mat)
				for sl in range(1, s_lanes):
					var lx := wall_outer + float(sl) * LANE_WIDTH
					var zp := stop_z + 2.6
					while zp < ROAD_HALF_LEN - 2.0:
						flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
						zp += 6.0
				var cw_z := fz * (ew_half + 1.55)
				var u_s := wall_outer + 0.75
				while u_s <= total_ns_half - 0.65:
					flat_batch.add_plane_xz(Vector3(fx * u_s, mark_y, cw_z), Vector2(0.75, 2.0), white_line_mat)
					u_s += 1.72
			var incoming_x_sign: float = fz
			flat_batch.add_plane_xz(Vector3(incoming_x_sign * front_cx, mark_y, fz * stop_z), Vector2(surf_w - 0.3, 0.45), white_line_mat)

	# 3. Elevated Flat Bridge Deck Span (|z| <= z_bot at y = +6.0m)
	# Concrete box girder structural slab
	solid_batch.add_box(Vector3(0.0, height - girder_thick * 0.5 - 0.05, 0.0), Vector3(wall_outer * 2.0, girder_thick - 0.10, z_bot * 2.0), concrete_wall_mat)
	# Asphalt wearing surface on deck (top cleanly at y = height)
	flat_batch.add_box(Vector3(0.0, height - 0.05, 0.0), Vector3(bridge_half * 2.0, 0.10, z_bot * 2.0), asphalt_mat)
	# Elevated deck markings
	flat_batch.add_plane_xz(Vector3(-0.15, height + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), yellow_line_mat)
	flat_batch.add_plane_xz(Vector3(0.15, height + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), yellow_line_mat)
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_plane_xz(Vector3(fx * (bridge_half - 0.18), height + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), white_line_mat)
		# Bridge concrete parapets + dark steel railing
		solid_batch.add_box(Vector3(fx * (bridge_half + wall_w * 0.5), height + 0.45, 0.0), Vector3(wall_w, 0.90, z_bot * 2.0), concrete_wall_mat)
		solid_batch.add_box(Vector3(fx * (bridge_half + wall_w * 0.5), height + 1.03, 0.0), Vector3(0.14, 0.09, z_bot * 2.0), portal_trim_mat)
		for l in range(1, u_lanes):
			var lx := float(l) * LANE_WIDTH
			var zp := -z_bot + 1.8
			while zp < z_bot - 1.5:
				flat_batch.add_plane_xz(Vector3(fx * lx, height + mark_y, zp), Vector2(0.14, 2.6), white_line_mat)
				zp += 5.6

	# 4. Smooth S-Curve Elevated Viaduct Ramps (|z| from z_bot down to z_top)
	var slices := 22
	var taper_start := z_top - 5.0
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		for i in range(slices):
			var za := lerpf(z_bot, z_top, float(i) / float(slices))
			var zb := lerpf(z_bot, z_top, float(i + 1) / float(slices))
			var ya := get_underpass_y(za, z_bot, z_top, height)
			var yb := get_underpass_y(zb, z_bot, z_top, height)
			var z0 := fz * za
			var z1 := fz * zb
			var n_up := Vector3(0.0, zb - za, -(yb - ya) * fz).normalized()
			var n_dn := -n_up

			# Sloped asphalt deck surface
			flat_batch.add_quad_normal(
				Vector3(-bridge_half, ya, z0),
				Vector3(bridge_half, ya, z0),
				Vector3(bridge_half, yb, z1),
				Vector3(-bridge_half, yb, z1),
				n_up,
				asphalt_mat
			)

			# Ramp girder underside (open viaduct when high, solid abutment when near ground)
			var ya_bot := maxf(-0.04, ya - girder_thick) if ya > 2.4 else -0.04
			var yb_bot := maxf(-0.04, yb - girder_thick) if yb > 2.4 else -0.04
			if ya_bot > 0.1 or yb_bot > 0.1:
				flat_batch.add_quad_normal(
					Vector3(-wall_outer, ya_bot, z0),
					Vector3(wall_outer, ya_bot, z0),
					Vector3(wall_outer, yb_bot, z1),
					Vector3(-wall_outer, yb_bot, z1),
					n_dn,
					concrete_wall_mat
				)

			# Ramp markings: double yellow centerline, white edge lines, dashed white lane lines
			for side_s in [-1.0, 1.0]:
				var xc: float = float(side_s) * 0.15
				flat_batch.add_quad_normal(
					Vector3(xc - 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, yb + mark_y, z1),
					Vector3(xc - 0.07, yb + mark_y, z1),
					n_up,
					yellow_line_mat
				)
				var xe: float = float(side_s) * (bridge_half - 0.18)
				flat_batch.add_quad_normal(
					Vector3(xe - 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, yb + mark_y, z1),
					Vector3(xe - 0.07, yb + mark_y, z1),
					n_up,
					white_line_mat
				)
				if i % 2 == 0:
					for l in range(1, u_lanes):
						var xl: float = float(side_s) * float(l) * LANE_WIDTH
						flat_batch.add_quad_normal(
							Vector3(xl - 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, yb + mark_y, z1),
							Vector3(xl - 0.07, yb + mark_y, z1),
							n_up,
							white_line_mat
						)

			# Side fascia / abutment walls & tapered bridge parapets
			var par_a := 0.90 if za <= taper_start else lerpf(0.90, 0.18, clampf((za - taper_start) / 5.0, 0.0, 1.0))
			var par_b := 0.90 if zb <= taper_start else lerpf(0.90, 0.18, clampf((zb - taper_start) / 5.0, 0.0, 1.0))
			var top_a := ya + par_a
			var top_b := yb + par_b
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				var xi := fx * bridge_half
				var xo := fx * wall_outer
				# Inner parapet wall facing ramp roadbed
				flat_batch.add_quad_normal(
					Vector3(xi, ya - 0.05, z0),
					Vector3(xi, yb - 0.05, z1),
					Vector3(xi, top_b, z1),
					Vector3(xi, top_a, z0),
					Vector3(-fx, 0.0, 0.0),
					concrete_wall_mat
				)
				# Outer viaduct fascia / embankment wall facing surface frontage road
				flat_batch.add_quad_normal(
					Vector3(xo, ya_bot, z0),
					Vector3(xo, yb_bot, z1),
					Vector3(xo, top_b, z1),
					Vector3(xo, top_a, z0),
					Vector3(fx, 0.0, 0.0),
					concrete_wall_mat
				)
				# Top parapet cap
				flat_batch.add_quad_normal(
					Vector3(xi, top_a, z0),
					Vector3(xo, top_a, z0),
					Vector3(xo, top_b, z1),
					Vector3(xi, top_b, z1),
					n_up,
					sidewalk_mat
				)
				# Sloped steel guardrail bar on upper section
				if za <= taper_start:
					var rmid := fx * (bridge_half + wall_w * 0.5)
					flat_batch.add_quad_normal(
						Vector3(rmid - 0.06, top_a + 0.12, z0),
						Vector3(rmid + 0.06, top_a + 0.12, z0),
						Vector3(rmid + 0.06, top_b + 0.12, z1),
						Vector3(rmid - 0.06, top_b + 0.12, z1),
						n_up,
						portal_trim_mat
					)

		# Flat ground-level express approach beyond ramp foot (z_top .. ROAD_HALF_LEN)
		var app_len := maxf(1.0, ROAD_HALF_LEN - z_top)
		var app_cz := fz * (z_top + app_len * 0.5)
		flat_batch.add_box(Vector3(0.0, -0.10, app_cz), Vector3(bridge_half * 2.0, 0.20, app_len), asphalt_mat)
		flat_batch.add_plane_xz(Vector3(-0.15, mark_y, app_cz), Vector2(0.14, app_len), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(0.15, mark_y, app_cz), Vector2(0.14, app_len), yellow_line_mat)
		for sx in [-1.0, 1.0]:
			var fx: float = float(sx)
			flat_batch.add_plane_xz(Vector3(fx * (bridge_half - 0.18), mark_y, app_cz), Vector2(0.14, app_len), white_line_mat)
			flat_batch.add_box(Vector3(fx * (bridge_half + wall_w * 0.5), 0.07, app_cz), Vector3(wall_w, 0.18, app_len), sidewalk_mat)
			for l in range(1, u_lanes):
				var lx := float(l) * LANE_WIDTH
				var zp := z_top + 2.2
				while zp < ROAD_HALF_LEN - 2.0:
					flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
					zp += 6.0

		# Express straight pavement arrows before ramp climb
		var in_x_sign := fz
		var fwd_in := Vector3(0.0, 0.0, -fz)
		var rt_in := Vector3(in_x_sign, 0.0, 0.0)
		for l in range(u_lanes):
			var ax := in_x_sign * (float(l) + 0.5) * LANE_WIDTH
			_add_pavement_arrow(flat_batch, Vector3(ax, mark_y, fz * (z_top + 5.5)), fwd_in, rt_in, white_line_mat)

	# 5. Sculpted Concrete Bridge T-Piers (strictly outside the E-W street!)
	var pier_z := ew_half + 2.6
	while pier_z < z_top - 10.0:
		var deck_y := get_underpass_y(pier_z, z_bot, z_top, height)
		var under_y := deck_y - girder_thick
		if under_y >= 2.2:
			for sz in [-1.0, 1.0]:
				var pz := float(sz) * pier_z
				# Hammerhead pier cap beam supporting girder
				solid_batch.add_box(Vector3(0.0, under_y - 0.38, pz), Vector3(bridge_half * 1.92, 0.78, 1.45), concrete_wall_mat)
				# Concrete columns down to ground
				var col_h := under_y - 0.75
				var col_cy := col_h * 0.5
				if bridge_half <= 5.5:
					solid_batch.add_cylinder(Vector3(0.0, col_cy, pz), 0.65, col_h, concrete_wall_mat, Vector3.ZERO, false)
				else:
					var col_off := bridge_half * 0.54
					solid_batch.add_cylinder(Vector3(-col_off, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
					solid_batch.add_cylinder(Vector3(col_off, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
					if bridge_half >= 14.0:
						solid_batch.add_cylinder(Vector3(0.0, col_cy, pz), 0.62, col_h, concrete_wall_mat, Vector3.ZERO, false)
		pier_z += 11.0

	# 6. Double-Arm Highway Median Streetlamps on the Elevated Bridge Deck
	var lamp_z := 0.0
	while lamp_z <= z_bot + 16.0:
		var ly := get_underpass_y(lamp_z, z_bot, z_top, height)
		var zs: Array = [0.0] if lamp_z < 0.1 else [-lamp_z, lamp_z]
		for z_item in zs:
			var zz: float = float(z_item)
			solid_batch.add_tapered_cylinder(Vector3(0.0, ly + 2.7, zz), 0.07, 0.11, 5.4, lamp_pole_mat, 8)
			solid_batch.add_box(Vector3(0.0, ly + 5.35, zz), Vector3(2.2, 0.09, 0.09), lamp_pole_mat)
			flat_batch.add_sphere(Vector3(-1.05, ly + 5.25, zz), 0.24, 0.30, lamp_bulb_mat)
			flat_batch.add_sphere(Vector3(1.05, ly + 5.25, zz), 0.24, 0.30, lamp_bulb_mat)
		lamp_z += 15.0

	# 7. Corner Urban Blocks, Congestion Bars, and Construction Cones
	_build_corner_blocks(flat_batch, solid_batch, total_ns_half, ew_half)
	_build_congestion_bars(total_ns_half, ew_half, stop_z, stop_x)
	_build_underpass_cones(solid_batch, ns_lanes, ew_lanes, lay, stop_z, stop_x, lane_enabled, approach_enabled)

func _build_underpass_geometry(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var lay := get_underpass_layout(ns_lanes, ew_lanes)
	var u_lanes: int = lay["u_lanes"]
	var s_lanes: int = lay["s_lanes"]
	var under_half: float = lay["under_half"]
	var wall_w: float = lay["wall_w"]
	var surf_w: float = lay["surf_w"]
	var total_ns_half: float = lay["total_ns_half"]
	var ew_half: float = lay["ew_half"]
	var portal_z: float = lay["portal_z"]
	var z_bot: float = lay["z_bot"]
	var z_top: float = lay["z_top"]
	var depth: float = lay["depth"]
	var mark_y: float = 0.05

	var stop_z: float = ew_half + 3.2
	var stop_x: float = total_ns_half + 3.2
	var wall_outer: float = under_half + wall_w

	# 1. Split grass base plane around the sunken underpass trough so ground NEVER clips through the tunnel
	var cut_x := wall_outer
	var cut_z := z_top + 0.5
	var side_w := 240.0 - cut_x
	var end_d := 240.0 - cut_z
	flat_batch.add_box(Vector3(-(cut_x + side_w * 0.5), -0.45, 0.0), Vector3(side_w, 0.4, 480.0), grass_mat)
	flat_batch.add_box(Vector3(cut_x + side_w * 0.5, -0.45, 0.0), Vector3(side_w, 0.4, 480.0), grass_mat)
	flat_batch.add_box(Vector3(0.0, -0.45, -(cut_z + end_d * 0.5)), Vector3(cut_x * 2.0, 0.4, end_d), grass_mat)
	flat_batch.add_box(Vector3(0.0, -0.45, cut_z + end_d * 0.5), Vector3(cut_x * 2.0, 0.4, end_d), grass_mat)

	# 2. Deep Flat Tunnel Floor (|z| <= z_bot at y = depth) + Tunnel Markings
	flat_batch.add_box(Vector3(0.0, depth - 0.12, 0.0), Vector3(under_half * 2.0 + 0.4, 0.24, z_bot * 2.0), intersection_mat)
	flat_batch.add_plane_xz(Vector3(-0.15, depth + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), yellow_line_mat)
	flat_batch.add_plane_xz(Vector3(0.15, depth + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), yellow_line_mat)
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_plane_xz(Vector3(fx * (under_half - 0.18), depth + mark_y, 0.0), Vector2(0.14, z_bot * 2.0), white_line_mat)
		for l in range(1, u_lanes):
			var lx := float(l) * LANE_WIDTH
			var zp := -z_bot + 1.8
			while zp < z_bot - 1.5:
				flat_batch.add_plane_xz(Vector3(fx * lx, depth + mark_y, zp), Vector2(0.14, 2.6), white_line_mat)
				zp += 5.6

	# 3. Covered Tunnel Interior Walls, Support Piers, and Ceiling LED Strips (|z| <= portal_z)
	var tunnel_wall_h := (-0.85) - (depth - 0.12)
	var tunnel_wall_cy := (depth - 0.12) + tunnel_wall_h * 0.5
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_box(Vector3(fx * (under_half + wall_w * 0.5), tunnel_wall_cy, 0.0), Vector3(wall_w, tunnel_wall_h, portal_z * 2.0), concrete_wall_mat)
		# Tunnel ceiling warm LED strips
		var led_x := fx * (under_half * 0.5)
		var lz := -portal_z + 2.4
		while lz <= portal_z - 2.0:
			flat_batch.add_box(Vector3(led_x, -0.89, lz), Vector3(minf(1.8, under_half * 0.55), 0.08, 2.2), tunnel_light_mat)
			lz += 5.4

	# Central concrete structural piers inside tunnel dividing N/S bores
	var pier_z := -portal_z + 3.5
	while pier_z <= portal_z - 3.0:
		solid_batch.add_box(Vector3(0.0, tunnel_wall_cy, pier_z), Vector3(0.46, tunnel_wall_h, 1.25), concrete_wall_mat)
		pier_z += 7.0

	# 4. Smooth S-Curve Ramps (North & South, |z| from z_bot to z_top) + Sloped Retaining Walls & Markings
	var slices := 22
	var taper_start := z_top - 5.0
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		for i in range(slices):
			var za := lerpf(z_bot, z_top, float(i) / float(slices))
			var zb := lerpf(z_bot, z_top, float(i + 1) / float(slices))
			var ya := get_underpass_y(za, z_bot, z_top, depth)
			var yb := get_underpass_y(zb, z_bot, z_top, depth)
			var z0 := fz * za
			var z1 := fz * zb
			var n_up := Vector3(0.0, zb - za, -(yb - ya) * fz).normalized()

			# Sloped asphalt ramp roadbed
			flat_batch.add_quad_normal(
				Vector3(-under_half, ya, z0),
				Vector3(under_half, ya, z0),
				Vector3(under_half, yb, z1),
				Vector3(-under_half, yb, z1),
				n_up,
				asphalt_mat
			)

			# Double yellow centerline along ramp slope
			for side_s in [-1.0, 1.0]:
				var xc: float = float(side_s) * 0.15
				flat_batch.add_quad_normal(
					Vector3(xc - 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, ya + mark_y, z0),
					Vector3(xc + 0.07, yb + mark_y, z1),
					Vector3(xc - 0.07, yb + mark_y, z1),
					n_up,
					yellow_line_mat
				)
				# White ramp edge lines
				var xe: float = float(side_s) * (under_half - 0.18)
				flat_batch.add_quad_normal(
					Vector3(xe - 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, ya + mark_y, z0),
					Vector3(xe + 0.07, yb + mark_y, z1),
					Vector3(xe - 0.07, yb + mark_y, z1),
					n_up,
					white_line_mat
				)
				# Dashed white lane lines along ramp
				if i % 2 == 0:
					for l in range(1, u_lanes):
						var xl: float = float(side_s) * float(l) * LANE_WIDTH
						flat_batch.add_quad_normal(
							Vector3(xl - 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, ya + mark_y, z0),
							Vector3(xl + 0.07, yb + mark_y, z1),
							Vector3(xl - 0.07, yb + mark_y, z1),
							n_up,
							white_line_mat
						)

			# Retaining walls flanking the ramp (rising from sloped floor to tapered safety parapet)
			var yt_a := 0.92 if za <= taper_start else lerpf(0.92, 0.18, clampf((za - taper_start) / 5.0, 0.0, 1.0))
			var yt_b := 0.92 if zb <= taper_start else lerpf(0.92, 0.18, clampf((zb - taper_start) / 5.0, 0.0, 1.0))
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				var xi := fx * under_half
				var xo := fx * wall_outer
				# Inner vertical retaining wall facing into trough
				flat_batch.add_quad_normal(
					Vector3(xi, ya - 0.08, z0),
					Vector3(xi, yb - 0.08, z1),
					Vector3(xi, yt_b, z1),
					Vector3(xi, yt_a, z0),
					Vector3(-fx, 0.0, 0.0),
					concrete_wall_mat
				)
				# Outer vertical parapet face facing surface frontage road
				flat_batch.add_quad_normal(
					Vector3(xo, -0.04, z0),
					Vector3(xo, -0.04, z1),
					Vector3(xo, yt_b, z1),
					Vector3(xo, yt_a, z0),
					Vector3(fx, 0.0, 0.0),
					concrete_wall_mat
				)
				# Top concrete parapet cap
				flat_batch.add_quad_up(
					Vector3(xi, yt_a, z0),
					Vector3(xo, yt_a, z0),
					Vector3(xo, yt_b, z1),
					Vector3(xi, yt_b, z1),
					sidewalk_mat
				)

		# Connect short deep flat retaining walls between portal_z and z_bot
		var stub_len := z_bot - portal_z
		if stub_len > 0.05:
			var stub_cz := fz * (portal_z + stub_len * 0.5)
			var stub_h := 0.92 - (depth - 0.12)
			var stub_cy := (depth - 0.12) + stub_h * 0.5
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				flat_batch.add_box(Vector3(fx * (under_half + wall_w * 0.5), stub_cy, stub_cz), Vector3(wall_w, stub_h, stub_len), concrete_wall_mat)

		# Steel safety guardrail bar along retaining wall top (portal_z .. taper_start)
		var rail_len := maxf(0.0, taper_start - portal_z)
		if rail_len > 0.5:
			var rail_cz := fz * (portal_z + rail_len * 0.5)
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				solid_batch.add_box(Vector3(fx * (under_half + wall_w * 0.5), 1.08, rail_cz), Vector3(0.12, 0.08, rail_len), portal_trim_mat)

		# Flat ground-level express approach beyond ramp top (z_top .. ROAD_HALF_LEN)
		var app_len := maxf(1.0, ROAD_HALF_LEN - z_top)
		var app_cz := fz * (z_top + app_len * 0.5)
		flat_batch.add_box(Vector3(0.0, -0.10, app_cz), Vector3(under_half * 2.0, 0.20, app_len), asphalt_mat)
		flat_batch.add_plane_xz(Vector3(-0.15, mark_y, app_cz), Vector2(0.14, app_len), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(0.15, mark_y, app_cz), Vector2(0.14, app_len), yellow_line_mat)
		for sx in [-1.0, 1.0]:
			var fx: float = float(sx)
			flat_batch.add_plane_xz(Vector3(fx * (under_half - 0.18), mark_y, app_cz), Vector2(0.14, app_len), white_line_mat)
			# Low raised median curb separating express underpass lanes from frontage lanes beyond ramp
			flat_batch.add_box(Vector3(fx * (under_half + wall_w * 0.5), 0.07, app_cz), Vector3(wall_w, 0.18, app_len), sidewalk_mat)
			for l in range(1, u_lanes):
				var lx := float(l) * LANE_WIDTH
				var zp := z_top + 2.2
				while zp < ROAD_HALF_LEN - 2.0:
					flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
					zp += 6.0

		# Express straight pavement arrows before ramp dive (incoming lanes only)
		var in_x_sign := fz # North arm (fz=-1): incoming is -X; South arm (fz=+1): incoming is +X
		var fwd_in := Vector3(0.0, 0.0, -fz)
		var rt_in := Vector3(in_x_sign, 0.0, 0.0)
		for l in range(u_lanes):
			var ax := in_x_sign * (float(l) + 0.5) * LANE_WIDTH
			_add_pavement_arrow(flat_batch, Vector3(ax, mark_y, fz * (z_top + 5.5)), fwd_in, rt_in, white_line_mat)

	# 5. Overpass Bridge Deck & Tunnel Portals (|z| <= portal_z)
	# Structural concrete bridge slab underneath the E-W deck
	solid_batch.add_box(Vector3(0.0, -0.475, 0.0), Vector3(wall_outer * 2.0, 0.75, portal_z * 2.0), concrete_wall_mat)
	# Surface intersection asphalt deck cleanly at y = 0.0
	flat_batch.add_box(Vector3(0.0, -0.05, 0.0), Vector3(total_ns_half * 2.0, 0.10, ew_half * 2.0), intersection_mat)

	# Portal bridge plaza walkways, bridge parapets, and yellow/black clearance warning headers
	var plaza_d := portal_z - ew_half
	for sz in [-1.0, 1.0]:
		var fz: float = float(sz)
		# Raised walkway plaza over the tunnel portal mouth
		flat_batch.add_box(Vector3(0.0, 0.03, fz * (ew_half + plaza_d * 0.5)), Vector3(wall_outer * 2.0, 0.26, plaza_d), sidewalk_mat)
		# Bridge safety parapet wall & railing along portal lip
		solid_batch.add_box(Vector3(0.0, 0.58, fz * (portal_z - 0.38)), Vector3(wall_outer * 2.0, 0.86, 0.72), concrete_wall_mat)
		solid_batch.add_box(Vector3(0.0, 1.12, fz * (portal_z - 0.38)), Vector3(wall_outer * 2.0, 0.09, 0.14), portal_trim_mat)

		# Portal header steel frame + alternating yellow/black 4.5m clearance hazard stripes
		var face_z := fz * (portal_z + 0.06)
		solid_batch.add_box(Vector3(0.0, -0.48, face_z), Vector3(under_half * 2.0 + 0.6, 0.76, 0.16), portal_trim_mat)
		var stripe_w := 1.15
		var sx_pos := -under_half + stripe_w * 0.5
		var s_idx := 0
		while sx_pos < under_half - 0.2:
			var sw := minf(stripe_w, under_half - (sx_pos - stripe_w * 0.5))
			var smat := yellow_line_mat if (s_idx % 2 == 0) else portal_trim_mat
			flat_batch.add_box(Vector3(sx_pos, -0.56, fz * (portal_z + 0.15)), Vector3(sw - 0.04, 0.42, 0.06), smat)
			sx_pos += stripe_w
			s_idx += 1

	# 6. Full E-W Overpass Road Arms (y = 0.0)
	var ew_arm_len := ROAD_HALF_LEN - total_ns_half
	var ew_arm_center := total_ns_half + ew_arm_len * 0.5
	flat_batch.add_box(Vector3(ew_arm_center, -0.10, 0.0), Vector3(ew_arm_len, 0.20, ew_half * 2.0), asphalt_mat)
	flat_batch.add_box(Vector3(-ew_arm_center, -0.10, 0.0), Vector3(ew_arm_len, 0.20, ew_half * 2.0), asphalt_mat)

	# E-W road markings (double yellow, dashed lanes, stop bars & crosswalks if surface frontage exists)
	var ew_mark_start := stop_x + 0.3 if s_lanes > 0 else total_ns_half + 0.3
	var ew_mark_len := maxf(2.0, ROAD_HALF_LEN - ew_mark_start)
	var ew_mark_mid := ew_mark_start + ew_mark_len * 0.5
	for sx in [-1.0, 1.0]:
		var fx: float = float(sx)
		flat_batch.add_plane_xz(Vector3(fx * ew_mark_mid, mark_y, -0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)
		flat_batch.add_plane_xz(Vector3(fx * ew_mark_mid, mark_y, 0.15), Vector2(ew_mark_len, 0.14), yellow_line_mat)
		if s_lanes == 0:
			# Continuous yellow centerline straight across pure grade-separated overpass deck
			flat_batch.add_plane_xz(Vector3(0.0, mark_y, -0.15), Vector2(total_ns_half * 2.0, 0.14), yellow_line_mat)
			flat_batch.add_plane_xz(Vector3(0.0, mark_y, 0.15), Vector2(total_ns_half * 2.0, 0.14), yellow_line_mat)
		for l in range(1, ew_lanes):
			var lz := float(l) * LANE_WIDTH
			var xp := ew_mark_start + 2.5
			while xp < ROAD_HALF_LEN - 2.0:
				flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, -lz), Vector2(2.8, 0.14), white_line_mat)
				flat_batch.add_plane_xz(Vector3(fx * xp, mark_y, lz), Vector2(2.8, 0.14), white_line_mat)
				xp += 6.0
		if s_lanes > 0:
			var incoming_z_sign: float = -fx
			flat_batch.add_plane_xz(Vector3(fx * stop_x, mark_y, incoming_z_sign * (ew_half * 0.5)), Vector2(0.45, ew_half - 0.3), white_line_mat)
			var cw_x := fx * (total_ns_half + 1.55)
			var stripe_z := -ew_half + 0.9
			while stripe_z <= ew_half - 0.8:
				flat_batch.add_plane_xz(Vector3(cw_x, mark_y, stripe_z), Vector2(2.0, 0.75), white_line_mat)
				stripe_z += 1.75

	# 7. Surface N-S Frontage Roads flanking the retaining walls (when s_lanes > 0)
	if s_lanes > 0:
		var front_len := ROAD_HALF_LEN - ew_half
		var front_cz := ew_half + front_len * 0.5
		var front_cx := wall_outer + surf_w * 0.5
		for sz in [-1.0, 1.0]:
			var fz: float = float(sz)
			for sx in [-1.0, 1.0]:
				var fx: float = float(sx)
				flat_batch.add_box(Vector3(fx * front_cx, -0.10, fz * front_cz), Vector3(surf_w, 0.20, front_len), asphalt_mat)
				# Dashed dividers between multiple frontage lanes
				for sl in range(1, s_lanes):
					var lx := wall_outer + float(sl) * LANE_WIDTH
					var zp := stop_z + 2.6
					while zp < ROAD_HALF_LEN - 2.0:
						flat_batch.add_plane_xz(Vector3(fx * lx, mark_y, fz * zp), Vector2(0.14, 2.8), white_line_mat)
						zp += 6.0
				# Crosswalk stripes across frontage roads at ew_half + 1.55
				var cw_z := fz * (ew_half + 1.55)
				var u_s := wall_outer + 0.75
				while u_s <= total_ns_half - 0.65:
					flat_batch.add_plane_xz(Vector3(fx * u_s, mark_y, cw_z), Vector2(0.75, 2.0), white_line_mat)
					u_s += 1.72
			# Stop bar ONLY on the incoming frontage half (fz=-1 -> -X incoming; fz=+1 -> +X incoming)
			var incoming_x_sign: float = fz
			flat_batch.add_plane_xz(Vector3(incoming_x_sign * front_cx, mark_y, fz * stop_z), Vector2(surf_w - 0.3, 0.45), white_line_mat)

	# 8. Corner Urban Blocks, Congestion Bars, and Construction Cones
	_build_corner_blocks(flat_batch, solid_batch, total_ns_half, ew_half)
	_build_congestion_bars(total_ns_half, ew_half, stop_z, stop_x)
	_build_underpass_cones(solid_batch, ns_lanes, ew_lanes, lay, stop_z, stop_x, lane_enabled, approach_enabled)

func _build_underpass_cones(solid_batch: MeshBatch, ns_lanes: int, ew_lanes: int, lay: Dictionary, stop_z: float, stop_x: float, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	var u_lanes: int = lay["u_lanes"]
	var z_top: float = lay["z_top"]
	for a in range(4):
		var f: Vector3 = forwards[a]
		var r: Vector3 = rights[a]
		var is_ns := (a == 0 or a == 1)
		var l_cnt := ns_lanes if is_ns else ew_lanes
		for l in range(l_cnt):
			var closed: bool = (not approach_enabled[a]) or (l < lane_enabled.size() and not lane_enabled[l])
			if closed:
				var d: float = get_underpass_lane_offset(l, lay) if is_ns else ((float(l) + 0.5) * LANE_WIDTH)
				var s_dist: float = (z_top + 1.5) if (is_ns and l < u_lanes) else (stop_z if is_ns else stop_x)
				for dist in [s_dist + 2.5, s_dist + 8.5, s_dist + 14.5]:
					var pos: Vector3 = -f * float(dist) + r * d
					_add_cone(solid_batch, pos)

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
	var cw_dist: float = outer_r + 5.6
	var mark_y: float = 0.05

	# 1. Circulatory asphalt disk (top at y = 0.0)
	flat_batch.add_cylinder(Vector3(0, -0.10, 0), outer_r, 0.20, intersection_mat, Vector3.ZERO, true)

	# 2. 4 exact-fit non-overlapping road arms meeting circular rim cleanly at y = 0.0
	_add_roundabout_arm_quads(flat_batch, ns_half, outer_r, true, -1.0)
	_add_roundabout_arm_quads(flat_batch, ns_half, outer_r, true, 1.0)
	_add_roundabout_arm_quads(flat_batch, ew_half, outer_r, false, 1.0)
	_add_roundabout_arm_quads(flat_batch, ew_half, outer_r, false, -1.0)

	# 3. Central Landscaped Island + Inner Solid Yellow Ring Line
	flat_batch.add_cylinder(Vector3(0, 0.14, 0), island_r, 0.28, sidewalk_mat, Vector3.ZERO, true)
	flat_batch.add_cylinder(Vector3(0, 0.36, 0), maxf(2.0, island_r - 0.85), 0.16, grass_mat, Vector3.ZERO, true)
	flat_batch.add_arc_ribbon(island_r + 0.14, island_r + 0.30, 0.0, TAU, mark_y, 64, yellow_line_mat)

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

	# 4. True Curved Dashed Circulatory Lane Dividers
	for l in range(1, ring_lanes):
		var lr := island_r + float(l) * LANE_WIDTH
		var circ := TAU * lr
		var dash_cnt := maxi(14, int(circ / 5.6))
		var step_a := TAU / float(dash_cnt)
		for d in range(dash_cnt):
			var a0 := float(d) * step_a
			var a1 := a0 + step_a * 0.52
			flat_batch.add_arc_ribbon(lr - 0.08, lr + 0.08, a0, a1, mark_y, 3, white_line_mat)

	# 5. Outer Solid White Edge Lines along the 4 corner arcs between road arms
	var half_ang_ns := asin(clampf(ns_half / outer_r, 0.0, 0.96))
	var half_ang_ew := asin(clampf(ew_half / outer_r, 0.0, 0.96))
	var corner_arcs := [
		Vector2(half_ang_ew, PI * 0.5 - half_ang_ns),             # SE (+X, +Z)
		Vector2(PI * 0.5 + half_ang_ns, PI - half_ang_ew),        # SW (-X, +Z)
		Vector2(PI + half_ang_ew, PI * 1.5 - half_ang_ns),        # NW (-X, -Z)
		Vector2(PI * 1.5 + half_ang_ns, TAU - half_ang_ew)        # NE (+X, -Z)
	]
	for arc_span in corner_arcs:
		var s_span: Vector2 = arc_span
		if s_span.y > s_span.x + 0.02:
			flat_batch.add_arc_ribbon(outer_r - 0.24, outer_r - 0.08, s_span.x, s_span.y, mark_y, 10, white_line_mat)

	# 6. CCW Circulatory Directional Arrows at 4 intercardinal angles
	var arrow_lanes: Array[int] = [int(ring_lanes / 2)]
	if ring_lanes >= 4:
		arrow_lanes = [0, int(ring_lanes / 2), ring_lanes - 1]
	for al in arrow_lanes:
		var ar := island_r + (float(al) + 0.5) * LANE_WIDTH
		for q in range(4):
			var ang := PI * 0.25 + float(q) * (PI * 0.5)
			var pos := Vector3(cos(ang) * ar, mark_y, sin(ang) * ar)
			var ccw_fwd := Vector3(sin(ang), 0.0, -cos(ang))
			var rad_out := Vector3(cos(ang), 0.0, sin(ang))
			_add_pavement_arrow(flat_batch, pos, ccw_fwd, rad_out, white_line_mat)

	# 7. Watertight Curved Corner Sidewalks + Arm Sidewalk Strips + Urban Corner Blocks
	var block_offset := outer_r + 2.0
	_build_corner_blocks(flat_batch, solid_batch, block_offset, block_offset)
	_build_roundabout_sidewalks(flat_batch, solid_batch, ns_half, ew_half, outer_r, block_offset)

	# 8. Continuous Arm Lane Markings, Curved Rim Yield Lines + Shark-Teeth, Splitter Islands, Crosswalks
	_build_roundabout_arm_markings(flat_batch, ns_lanes, ew_lanes, ns_half, ew_half, outer_r, cw_dist)
	_build_congestion_bars(ns_half, ew_half, cw_dist + 2.5, cw_dist + 2.5)
	_build_lane_cones(solid_batch, ns_lanes, ew_lanes, cw_dist + 2.5, cw_dist + 2.5, lane_enabled, approach_enabled)

func _add_pavement_arrow(flat_batch: MeshBatch, center: Vector3, fwd_dir: Vector3, right_dir: Vector3, mat: Material) -> void:
	var f := fwd_dir.normalized()
	var r := right_dir.normalized()
	# Arrow shaft
	var s0 := center - f * 1.15 - r * 0.17
	var s1 := center - f * 1.15 + r * 0.17
	var s2 := center + f * 0.55 + r * 0.17
	var s3 := center + f * 0.55 - r * 0.17
	flat_batch.add_quad_up(s0, s1, s2, s3, mat)
	# Arrowhead
	var h0 := center + f * 0.50 - r * 0.58
	var h1 := center + f * 0.50 + r * 0.58
	var h2 := center + f * 1.65
	flat_batch.add_triangle_up(h0, h1, h2, mat)

func _build_roundabout_sidewalks(flat_batch: MeshBatch, solid_batch: MeshBatch, ns_half: float, ew_half: float, outer_r: float, block_offset: float) -> void:
	var b_lim := block_offset + 0.04
	var r_curb := outer_r + 0.04
	var x_arm := ns_half + 0.04
	var z_arm := ew_half + 0.04
	var top_y := 0.20
	var bot_y := -0.02

	var x_ew := sqrt(maxf(0.1, r_curb * r_curb - z_arm * z_arm))
	var z_ns := sqrt(maxf(0.1, r_curb * r_curb - x_arm * x_arm))
	var a_ew_loc := atan2(z_arm, x_ew)
	var a_ns_loc := atan2(z_ns, x_arm)
	var segs := 14

	# 4 curved corner sidewalk aprons + vertical curb skirts hugging the roundabout rim
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var fx: float = float(sx)
			var fz: float = float(sz)
			var corner := Vector3(fx * b_lim, top_y, fz * b_lim)
			var c_ew := Vector3(fx * b_lim, top_y, fz * z_arm)
			var c_ns := Vector3(fx * x_arm, top_y, fz * b_lim)

			var arc_pts: Array[Vector3] = []
			for i in range(segs + 1):
				var ang := lerpf(a_ew_loc, a_ns_loc, float(i) / float(segs))
				arc_pts.append(Vector3(fx * cos(ang) * r_curb, top_y, fz * sin(ang) * r_curb))

			# Top surface fan (strictly non-overlapping, watertight up to corner blocks)
			flat_batch.add_triangle_up(corner, c_ew, arc_pts[0], sidewalk_mat)
			for i in range(segs):
				flat_batch.add_triangle_up(corner, arc_pts[i], arc_pts[i + 1], sidewalk_mat)
			flat_batch.add_triangle_up(corner, arc_pts[segs], c_ns, sidewalk_mat)

			# Vertical curb walls along straight EW edge, curved corner arc, and straight NS edge
			var p_ew0_b := Vector3(c_ew.x, bot_y, c_ew.z)
			var p_ew1_b := Vector3(arc_pts[0].x, bot_y, arc_pts[0].z)
			flat_batch.add_quad_normal(p_ew0_b, p_ew1_b, arc_pts[0], c_ew, Vector3(0.0, 0.0, -fz), sidewalk_mat)

			for i in range(segs):
				var t0 := arc_pts[i]
				var t1 := arc_pts[i + 1]
				var b0 := Vector3(t0.x, bot_y, t0.z)
				var b1 := Vector3(t1.x, bot_y, t1.z)
				var mid := (t0 + t1) * 0.5
				var inward_n := Vector3(-mid.x, 0.0, -mid.z)
				flat_batch.add_quad_normal(b0, b1, t1, t0, inward_n, sidewalk_mat)

			var p_ns0_b := Vector3(arc_pts[segs].x, bot_y, arc_pts[segs].z)
			var p_ns1_b := Vector3(c_ns.x, bot_y, c_ns.z)
			flat_batch.add_quad_normal(p_ns0_b, p_ns1_b, c_ns, arc_pts[segs], Vector3(-fx, 0.0, 0.0), sidewalk_mat)

	# Straight arm sidewalk strips from b_lim out to ROAD_HALF_LEN (eliminates empty grass strips along arms)
	var arm_len := maxf(0.0, ROAD_HALF_LEN - b_lim)
	var ns_strip_w := maxf(0.0, b_lim - x_arm)
	var ew_strip_d := maxf(0.0, b_lim - z_arm)
	if arm_len > 0.2:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var fx: float = float(sx)
				var fz: float = float(sz)
				if ns_strip_w > 0.15:
					flat_batch.add_box(Vector3(fx * (x_arm + ns_strip_w * 0.5), 0.05, fz * (b_lim + arm_len * 0.5)), Vector3(ns_strip_w, 0.30, arm_len), sidewalk_mat)
					if ns_strip_w > 4.6 and arm_len > 8.0:
						var gw := ns_strip_w - 3.9
						var gd := arm_len - 4.8
						flat_batch.add_box(Vector3(fx * (x_arm + 3.8 + gw * 0.5), 0.26, fz * (b_lim + 3.8 + gd * 0.5)), Vector3(gw, 0.12, gd), grass_mat)
						if b_lim + 12.0 < ROAD_HALF_LEN - 4.0:
							_add_tree(solid_batch, Vector3(fx * (x_arm + 5.6), 0.32, fz * (b_lim + 12.0)))
				if ew_strip_d > 0.15:
					flat_batch.add_box(Vector3(fx * (b_lim + arm_len * 0.5), 0.05, fz * (z_arm + ew_strip_d * 0.5)), Vector3(arm_len, 0.30, ew_strip_d), sidewalk_mat)
					if ew_strip_d > 4.6 and arm_len > 8.0:
						var gw2 := arm_len - 4.8
						var gd2 := ew_strip_d - 3.9
						flat_batch.add_box(Vector3(fx * (b_lim + 3.8 + gw2 * 0.5), 0.26, fz * (z_arm + 3.8 + gd2 * 0.5)), Vector3(gw2, 0.12, gd2), grass_mat)
						if b_lim + 12.0 < ROAD_HALF_LEN - 4.0:
							_add_tree(solid_batch, Vector3(fx * (b_lim + 12.0), 0.32, fz * (z_arm + 5.6)))

func _build_roundabout_arm_markings(flat_batch: MeshBatch, ns_lanes: int, ew_lanes: int, ns_half: float, ew_half: float, outer_r: float, cw_dist: float) -> void:
	var mark_y: float = 0.05
	var arm_dirs := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	var in_sides := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	var splitter_end := outer_r + 12.0

	for a in range(4):
		var is_ns := (a == 0 or a == 1)
		var arm_lanes := ns_lanes if is_ns else ew_lanes
		var arm_half := ns_half if is_ns else ew_half
		var arm_dir: Vector3 = arm_dirs[a]
		var in_side: Vector3 = in_sides[a]

		# 1. Triangular Concrete Splitter Island (split at crosswalk for pedestrian refuge)
		_add_splitter_island_segment(flat_batch, arm_dir, in_side, outer_r + 0.72, 0.56, cw_dist - 1.32, 0.48)
		_add_splitter_island_segment(flat_batch, arm_dir, in_side, cw_dist + 1.32, 0.44, splitter_end, 0.20)

		# 2. Double Yellow Centerline starting cleanly at splitter island tip
		var cl_len := maxf(2.0, ROAD_HALF_LEN - splitter_end)
		for side_s in [-1.0, 1.0]:
			var u_c: float = float(side_s) * 0.15
			var p0 := arm_dir * splitter_end + in_side * (u_c - 0.07) + Vector3(0, mark_y, 0)
			var p1 := arm_dir * splitter_end + in_side * (u_c + 0.07) + Vector3(0, mark_y, 0)
			var p2 := arm_dir * (splitter_end + cl_len) + in_side * (u_c + 0.07) + Vector3(0, mark_y, 0)
			var p3 := arm_dir * (splitter_end + cl_len) + in_side * (u_c - 0.07) + Vector3(0, mark_y, 0)
			flat_batch.add_quad_up(p0, p1, p2, p3, yellow_line_mat)

		# 3. Outer Solid White Road Edge Lines joining the 4 corner circular arcs seamlessly
		var u_edge := arm_half - 0.16
		var edge_rim_d := sqrt(maxf(1.0, outer_r * outer_r - u_edge * u_edge))
		for side_s in [-1.0, 1.0]:
			var ue: float = float(side_s) * u_edge
			var e0 := arm_dir * edge_rim_d + in_side * (ue - 0.08) + Vector3(0, mark_y, 0)
			var e1 := arm_dir * edge_rim_d + in_side * (ue + 0.08) + Vector3(0, mark_y, 0)
			var e2 := arm_dir * ROAD_HALF_LEN + in_side * (ue + 0.08) + Vector3(0, mark_y, 0)
			var e3 := arm_dir * ROAD_HALF_LEN + in_side * (ue - 0.08) + Vector3(0, mark_y, 0)
			flat_batch.add_quad_up(e0, e1, e2, e3, white_line_mat)

		# 4. Curved Dashed Yield Line hugging the circular rim on incoming lanes (+in_side)
		var r_y_in := outer_r + 0.14
		var r_y_out := outer_r + 0.62
		var u_y := 0.82
		while u_y < arm_half - 0.55:
			var u_end := minf(u_y + 0.88, arm_half - 0.30)
			var u_mid := (u_y + u_end) * 0.5
			var rim0 := (arm_dir * sqrt(maxf(1.0, outer_r * outer_r - u_y * u_y)) + in_side * u_y).normalized()
			var rim_m := (arm_dir * sqrt(maxf(1.0, outer_r * outer_r - u_mid * u_mid)) + in_side * u_mid).normalized()
			var rim1 := (arm_dir * sqrt(maxf(1.0, outer_r * outer_r - u_end * u_end)) + in_side * u_end).normalized()
			flat_batch.add_quad_up(
				rim0 * r_y_in + Vector3(0, mark_y, 0),
				rim0 * r_y_out + Vector3(0, mark_y, 0),
				rim_m * r_y_out + Vector3(0, mark_y, 0),
				rim_m * r_y_in + Vector3(0, mark_y, 0),
				white_line_mat
			)
			flat_batch.add_quad_up(
				rim_m * r_y_in + Vector3(0, mark_y, 0),
				rim_m * r_y_out + Vector3(0, mark_y, 0),
				rim1 * r_y_out + Vector3(0, mark_y, 0),
				rim1 * r_y_in + Vector3(0, mark_y, 0),
				white_line_mat
			)
			u_y += 1.52

		# 5. Yield Shark-Teeth (▽) on every incoming lane following the curved rim
		var r_tri_base := outer_r + 1.05
		var r_tri_tip := outer_r + 2.10
		for l in range(arm_lanes):
			var uc := (float(l) + 0.5) * LANE_WIDTH
			var d_base := sqrt(maxf(1.0, r_tri_base * r_tri_base - uc * uc))
			var d_tip := sqrt(maxf(1.0, r_tri_tip * r_tri_tip - uc * uc))
			var tb0 := arm_dir * d_base + in_side * (uc - 0.50) + Vector3(0, mark_y, 0)
			var tb1 := arm_dir * d_base + in_side * (uc + 0.50) + Vector3(0, mark_y, 0)
			var ttip := arm_dir * d_tip + in_side * uc + Vector3(0, mark_y, 0)
			flat_batch.add_triangle_up(tb0, tb1, ttip, white_line_mat)

		# 6. Continuous Arm Lane Dividers (solid approaching yield line, dashed out to road end)
		var cw_near := cw_dist - 1.35
		var cw_far := cw_dist + 1.35
		for l in range(1, arm_lanes):
			var u_div := float(l) * LANE_WIDTH
			var d_rim_in := sqrt(maxf(1.0, (outer_r + 0.78) * (outer_r + 0.78) - u_div * u_div)) + 0.25
			var d_rim_out := sqrt(maxf(1.0, outer_r * outer_r - u_div * u_div)) + 0.35

			# Incoming lane divider: solid white line from curved yield zone to crosswalk
			if cw_near > d_rim_in + 0.6:
				var si0 := arm_dir * d_rim_in + in_side * (u_div - 0.07) + Vector3(0, mark_y, 0)
				var si1 := arm_dir * d_rim_in + in_side * (u_div + 0.07) + Vector3(0, mark_y, 0)
				var si2 := arm_dir * cw_near + in_side * (u_div + 0.07) + Vector3(0, mark_y, 0)
				var si3 := arm_dir * cw_near + in_side * (u_div - 0.07) + Vector3(0, mark_y, 0)
				flat_batch.add_quad_up(si0, si1, si2, si3, white_line_mat)

			# Outgoing lane divider: dashed guiding line from rim to crosswalk
			var d_o := d_rim_out
			while d_o < cw_near - 0.8:
				var d_o1 := minf(d_o + 2.2, cw_near)
				var so0 := arm_dir * d_o - in_side * (u_div - 0.07) + Vector3(0, mark_y, 0)
				var so1 := arm_dir * d_o - in_side * (u_div + 0.07) + Vector3(0, mark_y, 0)
				var so2 := arm_dir * d_o1 - in_side * (u_div + 0.07) + Vector3(0, mark_y, 0)
				var so3 := arm_dir * d_o1 - in_side * (u_div - 0.07) + Vector3(0, mark_y, 0)
				flat_batch.add_quad_up(so0, so1, so2, so3, white_line_mat)
				d_o += 4.2

			# Both sides beyond crosswalk: standard dashed lane lines out to ROAD_HALF_LEN
			var d_pos := cw_far + 1.2
			while d_pos < ROAD_HALF_LEN - 2.0:
				var d_end := minf(d_pos + 2.8, ROAD_HALF_LEN - 1.0)
				for side_s in [-1.0, 1.0]:
					var uu: float = float(side_s) * u_div
					var q0 := arm_dir * d_pos + in_side * (uu - 0.07) + Vector3(0, mark_y, 0)
					var q1 := arm_dir * d_pos + in_side * (uu + 0.07) + Vector3(0, mark_y, 0)
					var q2 := arm_dir * d_end + in_side * (uu + 0.07) + Vector3(0, mark_y, 0)
					var q3 := arm_dir * d_end + in_side * (uu - 0.07) + Vector3(0, mark_y, 0)
					flat_batch.add_quad_up(q0, q1, q2, q3, white_line_mat)
				d_pos += 6.0

		# 7. Zebra Crosswalk (1 car length behind yield line, cleanly passing splitter island refuge)
		var u_cw := -arm_half + 0.9
		while u_cw <= arm_half - 0.8:
			if absf(u_cw) >= 0.95:
				var c0 := arm_dir * (cw_dist - 1.0) + in_side * (u_cw - 0.37) + Vector3(0, mark_y, 0)
				var c1 := arm_dir * (cw_dist - 1.0) + in_side * (u_cw + 0.37) + Vector3(0, mark_y, 0)
				var c2 := arm_dir * (cw_dist + 1.0) + in_side * (u_cw + 0.37) + Vector3(0, mark_y, 0)
				var c3 := arm_dir * (cw_dist + 1.0) + in_side * (u_cw - 0.37) + Vector3(0, mark_y, 0)
				flat_batch.add_quad_up(c0, c1, c2, c3, white_line_mat)
			u_cw += 1.72

func _add_splitter_island_segment(flat_batch: MeshBatch, arm_dir: Vector3, in_side: Vector3, d0: float, hw0: float, d1: float, hw1: float) -> void:
	if d1 <= d0 + 0.3:
		return
	var top_y := 0.16
	var bot_y := -0.02
	var mark_y := 0.05

	var t_l0 := arm_dir * d0 - in_side * hw0 + Vector3(0, top_y, 0)
	var t_r0 := arm_dir * d0 + in_side * hw0 + Vector3(0, top_y, 0)
	var t_r1 := arm_dir * d1 + in_side * hw1 + Vector3(0, top_y, 0)
	var t_l1 := arm_dir * d1 - in_side * hw1 + Vector3(0, top_y, 0)

	var b_l0 := Vector3(t_l0.x, bot_y, t_l0.z)
	var b_r0 := Vector3(t_r0.x, bot_y, t_r0.z)
	var b_r1 := Vector3(t_r1.x, bot_y, t_r1.z)
	var b_l1 := Vector3(t_l1.x, bot_y, t_l1.z)

	# Raised concrete curb top & 4 vertical walls
	flat_batch.add_quad_up(t_l0, t_r0, t_r1, t_l1, sidewalk_mat)
	flat_batch.add_quad_normal(b_l0, b_r0, t_r0, t_l0, -arm_dir, sidewalk_mat)
	flat_batch.add_quad_normal(b_r1, b_l1, t_l1, t_r1, arm_dir, sidewalk_mat)
	flat_batch.add_quad_normal(b_r0, b_r1, t_r1, t_r0, in_side, sidewalk_mat)
	flat_batch.add_quad_normal(b_l1, b_l0, t_l0, t_l1, -in_side, sidewalk_mat)

	# Crisp painted yellow curb edge lines along both sides of the splitter island
	for side_s in [-1.0, 1.0]:
		var ss: float = float(side_s)
		var y0 := arm_dir * d0 + in_side * (ss * (hw0 + 0.04)) + Vector3(0, mark_y, 0)
		var y1 := arm_dir * d0 + in_side * (ss * (hw0 + 0.16)) + Vector3(0, mark_y, 0)
		var y2 := arm_dir * d1 + in_side * (ss * (hw1 + 0.16)) + Vector3(0, mark_y, 0)
		var y3 := arm_dir * d1 + in_side * (ss * (hw1 + 0.04)) + Vector3(0, mark_y, 0)
		flat_batch.add_quad_up(y0, y1, y2, y3, yellow_line_mat)

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
