extends Node3D
class_name RoadBuilder

const LANE_WIDTH: float = 3.5
const ROAD_HALF_LEN: float = 68.0

enum TimeOfDay { DAY, SUNSET, NIGHT }

var dynamic_root: Node3D
var env_built: bool = false
var sun_light: DirectionalLight3D
var world_env_node: WorldEnvironment
var time_of_day: TimeOfDay = TimeOfDay.DAY

# Materials reused across rebuilds (never toggle emission_enabled at runtime!)
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
var building_mats: Array[StandardMaterial3D] = []

# Congestion overlay bars (4 approaches: N, S, E, W)
var congestion_bars: Array[MeshInstance3D] = []
var congestion_mats: Array[StandardMaterial3D] = []
var congestion_overlay_enabled: bool = true

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
	sun_light.directional_shadow_max_distance = 90.0
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
		var col := Color(0.14, 0.85, 0.42) # Smooth green
		if w_cnt >= 6:
			col = Color(0.98, 0.22, 0.18)  # Heavy red
		elif w_cnt >= 3:
			col = Color(0.98, 0.74, 0.14)  # Moderate amber
		var m := congestion_mats[i]
		m.albedo_color = col
		m.emission = col

func rebuild(ns_lanes: int, ew_lanes: int, lane_enabled: Array[bool], approach_enabled: Array[bool]) -> void:
	if dynamic_root == null:
		return
	for c in dynamic_root.get_children():
		c.queue_free()
	congestion_bars.clear()

	var ns_half: float = ns_lanes * LANE_WIDTH   # Half-width of N-S road along X
	var ew_half: float = ew_lanes * LANE_WIDTH   # Half-width of E-W road along Z
	var ns_width: float = ns_half * 2.0
	var ew_width: float = ew_half * 2.0
	var stop_z: float = ew_half + 3.2            # Stop line Z for N/S approaches
	var stop_x: float = ns_half + 3.2            # Stop line X for E/W approaches

	var ns_arm_len: float = ROAD_HALF_LEN - ew_half
	var ns_arm_center: float = ew_half + ns_arm_len * 0.5
	var ew_arm_len: float = ROAD_HALF_LEN - ns_half
	var ew_arm_center: float = ns_half + ew_arm_len * 0.5

	# 1. Ground base plane cleanly 0.25m below road surface (zero Z-fighting)
	_add_box(Vector3(170, 0.4, 170), Vector3(0, -0.45, 0), grass_mat, false)

	# 2. Non-overlapping Road Geometry (all tops cleanly at y = 0.0)
	_add_box(Vector3(ns_width, 0.20, ew_width), Vector3(0, -0.10, 0), intersection_mat, false)
	# North & South arms
	_add_box(Vector3(ns_width, 0.20, ns_arm_len), Vector3(0, -0.10, -ns_arm_center), asphalt_mat, false)
	_add_box(Vector3(ns_width, 0.20, ns_arm_len), Vector3(0, -0.10, ns_arm_center), asphalt_mat, false)
	# East & West arms
	_add_box(Vector3(ew_arm_len, 0.20, ew_width), Vector3(ew_arm_center, -0.10, 0), asphalt_mat, false)
	_add_box(Vector3(ew_arm_len, 0.20, ew_width), Vector3(-ew_arm_center, -0.10, 0), asphalt_mat, false)

	# 3. Four corner urban blocks (adapted to asymmetric ns_half / ew_half)
	var sw_x_in := ns_half + 0.02
	var sw_z_in := ew_half + 0.02
	var sw_w := ROAD_HALF_LEN - sw_x_in
	var sw_d := ROAD_HALF_LEN - sw_z_in
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
		# Sidewalk slab (bottom = -0.10, top = +0.20)
		_add_box(
			Vector3(sw_w, 0.30, sw_d),
			Vector3(s.x * sw_cx, 0.05, s.y * sw_cz),
			sidewalk_mat,
			false
		)
		# Inner grass park sits cleanly ON TOP of sidewalk (top = +0.32)
		var px_in := ns_half + 3.8
		var pz_in := ew_half + 3.8
		var pw := ROAD_HALF_LEN - px_in - 1.0
		var pd := ROAD_HALF_LEN - pz_in - 1.0
		if pw > 4.0 and pd > 4.0:
			_add_box(
				Vector3(pw, 0.12, pd),
				Vector3(s.x * (px_in + pw * 0.5), 0.26, s.y * (pz_in + pd * 0.5)),
				grass_mat,
				false
			)

		# Corner street lamp (lights up during sunset/night)
		_add_street_lamp(Vector3(s.x * (ns_half + 2.6), 0.20, s.y * (ew_half + 2.6)), s)

		# Stylized low-poly buildings
		var bx := ns_half + 11.0
		var bz := ew_half + 11.0
		var heights := [11.0, 16.0, 8.5, 14.0]
		_add_building(
			Vector3(s.x * (bx + 3.5), 0.32, s.y * (bz + 3.5)),
			Vector3(10.0, heights[idx], 10.0),
			building_mats[idx % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (bx + 18.0), 0.32, s.y * (bz + 4.5)),
			Vector3(11.0, heights[(idx + 2) % 4] * 0.85, 9.0),
			building_mats[(idx + 1) % building_mats.size()]
		)
		_add_building(
			Vector3(s.x * (bx + 4.5), 0.32, s.y * (bz + 18.0)),
			Vector3(9.0, heights[(idx + 1) % 4] * 0.9, 11.0),
			building_mats[(idx + 3) % building_mats.size()]
		)

		# Corner trees
		_add_tree(Vector3(s.x * (ns_half + 5.6), 0.32, s.y * (ew_half + 5.6)))
		_add_tree(Vector3(s.x * (ns_half + 6.0), 0.32, s.y * (ew_half + 16.0)))
		_add_tree(Vector3(s.x * (ns_half + 16.0), 0.32, s.y * (ew_half + 6.0)))

	# 4. Road Markings at y = +0.05 (zero Z-fighting)
	var mark_y: float = 0.05

	# N-S arms (North = -Z, South = +Z)
	var ns_mark_start := stop_z + 0.3
	var ns_mark_len := ROAD_HALF_LEN - ns_mark_start
	var ns_mark_mid := ns_mark_start + ns_mark_len * 0.5
	for sign_z in [-1.0, 1.0]:
		var sz: float = float(sign_z)
		_add_marking(Vector2(0.14, ns_mark_len), Vector3(-0.15, mark_y, sz * ns_mark_mid), yellow_line_mat)
		_add_marking(Vector2(0.14, ns_mark_len), Vector3(0.15, mark_y, sz * ns_mark_mid), yellow_line_mat)

		for l in range(1, ns_lanes):
			var lx := l * LANE_WIDTH
			var z_pos := ns_mark_start + 2.5
			while z_pos < ROAD_HALF_LEN - 2.0:
				_add_marking(Vector2(0.14, 2.8), Vector3(-lx, mark_y, sz * z_pos), white_line_mat)
				_add_marking(Vector2(0.14, 2.8), Vector3(lx, mark_y, sz * z_pos), white_line_mat)
				z_pos += 6.0

		var incoming_x_sign: float = sz
		_add_marking(
			Vector2(ns_half - 0.3, 0.45),
			Vector3(incoming_x_sign * (ns_half * 0.5), mark_y, sz * stop_z),
			white_line_mat
		)

		var cw_z: float = sz * (ew_half + 1.55)
		var stripe_x := -ns_half + 0.9
		while stripe_x <= ns_half - 0.8:
			_add_marking(Vector2(0.75, 2.1), Vector3(stripe_x, mark_y, cw_z), white_line_mat)
			stripe_x += 1.75

	# E-W arms (East = +X, West = -X)
	var ew_mark_start := stop_x + 0.3
	var ew_mark_len := ROAD_HALF_LEN - ew_mark_start
	var ew_mark_mid := ew_mark_start + ew_mark_len * 0.5
	for sign_x in [-1.0, 1.0]:
		var sx: float = float(sign_x)
		_add_marking(Vector2(ew_mark_len, 0.14), Vector3(sx * ew_mark_mid, mark_y, -0.15), yellow_line_mat)
		_add_marking(Vector2(ew_mark_len, 0.14), Vector3(sx * ew_mark_mid, mark_y, 0.15), yellow_line_mat)

		for l in range(1, ew_lanes):
			var lz := l * LANE_WIDTH
			var x_pos := ew_mark_start + 2.5
			while x_pos < ROAD_HALF_LEN - 2.0:
				_add_marking(Vector2(2.8, 0.14), Vector3(sx * x_pos, mark_y, -lz), white_line_mat)
				_add_marking(Vector2(2.8, 0.14), Vector3(sx * x_pos, mark_y, lz), white_line_mat)
				x_pos += 6.0

		var incoming_z_sign: float = -sx
		_add_marking(
			Vector2(0.45, ew_half - 0.3),
			Vector3(sx * stop_x, mark_y, incoming_z_sign * (ew_half * 0.5)),
			white_line_mat
		)

		var cw_x: float = sx * (ns_half + 1.55)
		var stripe_z := -ew_half + 0.9
		while stripe_z <= ew_half - 0.8:
			_add_marking(Vector2(2.1, 0.75), Vector3(cw_x, mark_y, stripe_z), white_line_mat)
			stripe_z += 1.75

	# 5. Congestion Status Strips (on sidewalk curb next to each incoming approach, index 0=N, 1=S, 2=E, 3=W)
	var strip_len := 18.0
	var strip_y := 0.24
	# North incoming is -X, -Z
	congestion_bars.append(_add_congestion_bar(Vector3(0.55, 0.08, strip_len), Vector3(-(ns_half + 0.75), strip_y, -(stop_z + strip_len * 0.5 + 1.0)), congestion_mats[0]))
	# South incoming is +X, +Z
	congestion_bars.append(_add_congestion_bar(Vector3(0.55, 0.08, strip_len), Vector3(ns_half + 0.75, strip_y, stop_z + strip_len * 0.5 + 1.0), congestion_mats[1]))
	# East incoming is +X, -Z
	congestion_bars.append(_add_congestion_bar(Vector3(strip_len, 0.08, 0.55), Vector3(stop_x + strip_len * 0.5 + 1.0, strip_y, -(ew_half + 0.75)), congestion_mats[2]))
	# West incoming is -X, +Z
	congestion_bars.append(_add_congestion_bar(Vector3(strip_len, 0.08, 0.55), Vector3(-(stop_x + strip_len * 0.5 + 1.0), strip_y, ew_half + 0.75), congestion_mats[3]))

	# 6. Traffic Cones for closed lanes or disabled approaches
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
					_add_cone(pos)

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

func _add_street_lamp(base_pos: Vector3, corner_sign: Vector2) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09
	pm.bottom_radius = 0.13
	pm.height = 7.2
	pole.mesh = pm
	pole.material_override = lamp_pole_mat
	pole.position = base_pos + Vector3(0, 3.6, 0)
	dynamic_root.add_child(pole)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.34
	hm.height = 0.45
	head.mesh = hm
	head.material_override = lamp_bulb_mat
	head.position = base_pos + Vector3(-corner_sign.x * 0.7, 7.15, -corner_sign.y * 0.7)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dynamic_root.add_child(head)

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
