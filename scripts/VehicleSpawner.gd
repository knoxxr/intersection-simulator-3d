extends Node3D
class_name VehicleSpawner

const LANE_WIDTH: float = 3.5
const SPAWN_DIST: float = 110.0
const MAX_VEHICLES: int = 180
const GRID_CELL: float = 16.0

# Live configurable simulation settings (1..10 lanes per direction, Signalized, Roundabout, or Underpass)
var ns_lanes: int = 2
var ew_lanes: int = 2
var is_roundabout: bool = false
var is_underpass: bool = false
var lane_enabled: Array[bool] = [true, true, true, true, true, true, true, true, true, true]
var approach_enabled: Array[bool] = [true, true, true, true] # N, S, E, W
var global_traffic_rate: float = 1.0
var dir_traffic_mult: Array[float] = [1.0, 1.0, 1.0, 1.0]
var left_turn_ratio: float = 0.22
var right_turn_ratio: float = 0.20

var spawn_timers: Array[float] = [0.4, 0.9, 1.4, 1.9]
var active_vehicles: Array[SimVehicle] = []
var _spatial_grid: Dictionary = {}
var _in_box_vehicles: Array = []

signal vehicle_passed(wait_time: float)

var _palette: Array[Color] = [
	Color(0.18, 0.48, 0.85),
	Color(0.82, 0.20, 0.22),
	Color(0.92, 0.93, 0.95),
	Color(0.22, 0.25, 0.30),
	Color(0.16, 0.62, 0.45),
	Color(0.88, 0.52, 0.14),
	Color(0.48, 0.34, 0.72),
	Color(0.55, 0.60, 0.66)
]

func clear_all_vehicles() -> void:
	for v in active_vehicles:
		if is_instance_valid(v):
			remove_child(v)
			v.queue_free()
	active_vehicles.clear()
	_spatial_grid.clear()
	_in_box_vehicles.clear()

func get_waiting_counts_by_dir() -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for v in active_vehicles:
		if is_instance_valid(v) and v.is_waiting:
			counts[v.approach_idx] += 1
	return counts

func get_active_emergency_approach() -> int:
	var best_app := -1
	var best_dist := 9999.0
	for v in active_vehicles:
		if is_instance_valid(v) and v.is_emergency and not v.is_underpass and not v.has_passed_intersection:
			var d := v.stop_progress - v.progress
			if d < best_dist:
				best_dist = d
				best_app = v.approach_idx
	return best_app

func spawn_ambulance(preferred_approach: int = -1) -> bool:
	var candidates: Array[int] = []
	if preferred_approach >= 0 and preferred_approach < 4 and approach_enabled[preferred_approach]:
		candidates.append(preferred_approach)
	else:
		for a in range(4):
			if approach_enabled[a]:
				candidates.append(a)
		candidates.shuffle()

	for app in candidates:
		var is_ns := (app == 0 or app == 1)
		var l_cnt := ns_lanes if is_ns else ew_lanes
		var open_lanes: Array[int] = []
		for l in range(l_cnt):
			if l < lane_enabled.size() and lane_enabled[l]:
				open_lanes.append(l)
		if open_lanes.is_empty():
			continue
		var chosen_lane: int = open_lanes[0]
		var path_data := _build_path(app, chosen_lane, TrafficController.TurnType.STRAIGHT)
		var pts: PackedVector3Array = path_data["points"]
		var spawn_pos: Vector3 = pts[0]

		var blocked := false
		for other in active_vehicles:
			if is_instance_valid(other) and other.position.distance_squared_to(spawn_pos) < 64.0:
				blocked = true
				break
		if blocked:
			continue

		var veh := SimVehicle.new()
		add_child(veh)
		veh.setup(
			app,
			chosen_lane,
			TrafficController.TurnType.STRAIGHT,
			pts,
			path_data["stop_progress"],
			path_data["exit_progress"],
			SimVehicle.VehicleKind.AMBULANCE,
			Color.WHITE,
			is_roundabout,
			path_data["ring_radius"],
			bool(path_data.get("is_underpass", false))
		)
		active_vehicles.append(veh)
		return true
	return false

func _rebuild_spatial_grid() -> void:
	_spatial_grid.clear()
	_in_box_vehicles.clear()
	for v in active_vehicles:
		if not is_instance_valid(v) or v.finished:
			continue
		var cx := int(floorf(v.position.x / GRID_CELL))
		var cz := int(floorf(v.position.z / GRID_CELL))
		var key := Vector2i(cx, cz)
		if not _spatial_grid.has(key):
			_spatial_grid[key] = []
		_spatial_grid[key].append(v)
		# Track vehicles approaching/inside the intersection or roundabout box
		if v.progress <= v.exit_box_progress and (v.stop_progress - v.progress) < 16.0:
			_in_box_vehicles.append(v)

func _get_nearby_vehicles(pos: Vector3) -> Array:
	var cx := int(floorf(pos.x / GRID_CELL))
	var cz := int(floorf(pos.z / GRID_CELL))
	var result: Array = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if _spatial_grid.has(key):
				result.append_array(_spatial_grid[key])
	return result

func step_simulation(delta: float, traffic_ctrl: TrafficController) -> void:
	for a in range(4):
		if not approach_enabled[a]:
			continue
		var rate: float = global_traffic_rate * dir_traffic_mult[a]
		if rate <= 0.02:
			continue

		spawn_timers[a] -= delta * rate
		if spawn_timers[a] <= 0.0:
			var l_cnt := ns_lanes if (a == 0 or a == 1) else ew_lanes
			var lane_factor := 1.0 / (0.55 + 0.45 * float(l_cnt))
			spawn_timers[a] = randf_range(1.4, 2.7) * lane_factor
			if active_vehicles.size() < MAX_VEHICLES:
				_try_spawn_on_approach(a)

	_rebuild_spatial_grid()

	var i := active_vehicles.size() - 1
	while i >= 0:
		var v := active_vehicles[i]
		if not is_instance_valid(v):
			active_vehicles.remove_at(i)
			i -= 1
			continue
		var nearby := _get_nearby_vehicles(v.position)
		v.step_vehicle(delta, traffic_ctrl, nearby, _in_box_vehicles)
		if v.finished:
			vehicle_passed.emit(v.wait_time)
			remove_child(v)
			v.queue_free()
			active_vehicles.remove_at(i)
		i -= 1

func _try_spawn_on_approach(approach_idx: int) -> void:
	var is_ns := (approach_idx == 0 or approach_idx == 1)
	var l_cnt := ns_lanes if is_ns else ew_lanes
	var open_lanes: Array[int] = []
	for l in range(l_cnt):
		if l < lane_enabled.size() and lane_enabled[l]:
			open_lanes.append(l)
	if open_lanes.is_empty():
		return

	var r := randf()
	var turn_type := TrafficController.TurnType.STRAIGHT
	if r < left_turn_ratio:
		turn_type = TrafficController.TurnType.LEFT
	elif r < left_turn_ratio + right_turn_ratio:
		turn_type = TrafficController.TurnType.RIGHT

	var chosen_lane := _pick_lane_for_turn(open_lanes, l_cnt, turn_type)
	if is_underpass:
		var lay := RoadBuilder.get_underpass_layout(ns_lanes, ew_lanes)
		var u_lanes: int = lay["u_lanes"]
		var s_lanes: int = lay["s_lanes"]
		if is_ns:
			var open_under: Array[int] = []
			var open_surf: Array[int] = []
			for ol in open_lanes:
				if ol < u_lanes:
					open_under.append(ol)
				else:
					open_surf.append(ol)
			if turn_type != TrafficController.TurnType.STRAIGHT:
				if open_surf.is_empty():
					turn_type = TrafficController.TurnType.STRAIGHT
					chosen_lane = open_under[randi() % open_under.size()]
				else:
					chosen_lane = open_surf[0] if turn_type == TrafficController.TurnType.LEFT else open_surf[open_surf.size() - 1]
			else:
				if not open_under.is_empty() and (open_surf.is_empty() or randf() < 0.82):
					chosen_lane = open_under[randi() % open_under.size()]
				elif not open_surf.is_empty():
					chosen_lane = open_surf[randi() % open_surf.size()]
		else:
			if s_lanes == 0:
				turn_type = TrafficController.TurnType.STRAIGHT
				chosen_lane = open_lanes[randi() % open_lanes.size()]

	var path_data := _build_path(approach_idx, chosen_lane, turn_type)
	var pts: PackedVector3Array = path_data["points"]
	var spawn_pos: Vector3 = pts[0]

	for other in active_vehicles:
		if is_instance_valid(other) and other.position.distance_squared_to(spawn_pos) < 86.0:
			return

	var kind_roll := randf()
	var kind := SimVehicle.VehicleKind.SEDAN
	var col: Color = _palette[randi() % _palette.size()]
	if kind_roll < 0.14:
		kind = SimVehicle.VehicleKind.TAXI
		col = Color(0.96, 0.74, 0.08)
	elif kind_roll < 0.28:
		kind = SimVehicle.VehicleKind.TRUCK
		col = _palette[randi() % 4]
	elif kind_roll < 0.55:
		kind = SimVehicle.VehicleKind.SUV

	var veh := SimVehicle.new()
	add_child(veh)
	veh.setup(
		approach_idx,
		chosen_lane,
		turn_type,
		pts,
		path_data["stop_progress"],
		path_data["exit_progress"],
		kind,
		col,
		is_roundabout,
		path_data["ring_radius"],
		bool(path_data.get("is_underpass", false))
	)
	active_vehicles.append(veh)

func _pick_lane_for_turn(open_lanes: Array[int], total_lanes: int, turn_type: int) -> int:
	if open_lanes.size() == 1:
		return open_lanes[0]
	if turn_type == TrafficController.TurnType.LEFT:
		# Innermost 1~2 open lanes on wide roads
		var left_band := mini(open_lanes.size(), 2 if total_lanes >= 5 else 1)
		return open_lanes[randi() % left_band]
	elif turn_type == TrafficController.TurnType.RIGHT:
		# Outermost 1~2 open lanes on wide roads
		var right_band := mini(open_lanes.size(), 2 if total_lanes >= 5 else 1)
		return open_lanes[open_lanes.size() - 1 - (randi() % right_band)]
	else:
		# Straight: distribute across middle/all open lanes cleanly
		if open_lanes.size() >= 3:
			var mid_idx := 1 + (randi() % (open_lanes.size() - 1))
			return open_lanes[mid_idx]
		return open_lanes[randi() % open_lanes.size()]

func _build_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
	if is_underpass:
		return _build_underpass_path(approach_idx, lane_idx, turn_type)
	if is_roundabout:
		return _build_roundabout_path(approach_idx, lane_idx, turn_type)
	return _build_signalized_path(approach_idx, lane_idx, turn_type)

func _build_underpass_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]

	var f: Vector3 = forwards[approach_idx]
	var r: Vector3 = rights[approach_idx]
	var is_ns := (approach_idx == 0 or approach_idx == 1)

	var lay := RoadBuilder.get_underpass_layout(ns_lanes, ew_lanes)
	var u_lanes: int = lay["u_lanes"]
	var s_lanes: int = lay["s_lanes"]
	var total_ns_half: float = lay["total_ns_half"]
	var ew_half: float = lay["ew_half"]
	var portal_z: float = lay["portal_z"]
	var z_bot: float = lay["z_bot"]
	var z_top: float = lay["z_top"]
	var depth: float = lay["depth"]

	# Subcase A: N-S Underground Express Lane (smooth 3D S-curve ramp down, flat tunnel under deck, ramp up)
	if is_ns and lane_idx < u_lanes:
		var d_u := RoadBuilder.get_underpass_lane_offset(lane_idx, lay)
		var pts := PackedVector3Array()
		var p_spawn := -f * SPAWN_DIST + r * d_u
		pts.append(p_spawn)

		# Entry ramp (-z_top .. -z_bot)
		var ramp_steps := 18
		for i in range(ramp_steps + 1):
			var dist_z := lerpf(z_top, z_bot, float(i) / float(ramp_steps))
			var y := RoadBuilder.get_underpass_y(dist_z, z_bot, z_top, depth)
			var p := -f * dist_z + r * d_u
			p.y = y
			pts.append(p)

		# Exit ramp (+z_bot .. +z_top)
		for i in range(ramp_steps + 1):
			var dist_z := lerpf(z_bot, z_top, float(i) / float(ramp_steps))
			var y := RoadBuilder.get_underpass_y(dist_z, z_bot, z_top, depth)
			var p := f * dist_z + r * d_u
			p.y = y
			pts.append(p)

		pts.append(f * SPAWN_DIST + r * d_u)
		var half_len := SPAWN_DIST
		return {
			"points": pts,
			"stop_progress": half_len - portal_z,
			"exit_progress": half_len + portal_z,
			"ring_radius": 0.0,
			"is_underpass": true
		}

	# Subcase B: Surface Frontage N-S OR E-W Overpass Deck (y = 0.0)
	var entry_stop: float = (ew_half + 3.2) if is_ns else (total_ns_half + 3.2)
	var cross_stop: float = (total_ns_half + 3.2) if is_ns else (ew_half + 3.2)
	var d_entry: float = RoadBuilder.get_underpass_lane_offset(lane_idx, lay) if is_ns else ((float(lane_idx) + 0.5) * LANE_WIDTH)

	var d_exit: float = d_entry
	if turn_type != TrafficController.TurnType.STRAIGHT:
		if is_ns:
			var ex_ew := clampi(lane_idx - u_lanes, 0, ew_lanes - 1)
			if turn_type == TrafficController.TurnType.LEFT:
				ex_ew = clampi(ex_ew, 0, mini(1, ew_lanes - 1))
			elif turn_type == TrafficController.TurnType.RIGHT:
				ex_ew = ew_lanes - 1
			d_exit = (float(ex_ew) + 0.5) * LANE_WIDTH
		else:
			# E-W turning onto N-S MUST exit onto surface frontage lanes (outside retaining wall!)
			var ex_s := 0 if turn_type == TrafficController.TurnType.LEFT else maxi(0, s_lanes - 1)
			d_exit = RoadBuilder.get_underpass_lane_offset(u_lanes + ex_s, lay)

	var pts_s := PackedVector3Array()
	var spawn_pt := -f * SPAWN_DIST + r * d_entry
	var stop_pt := -f * entry_stop + r * d_entry
	var stop_prog := spawn_pt.distance_to(stop_pt)
	var exit_prog := stop_prog + entry_stop * 2.0

	if turn_type == TrafficController.TurnType.STRAIGHT or (not is_ns and s_lanes == 0):
		var exit_box_pt := f * entry_stop + r * d_entry
		var end_pt := f * SPAWN_DIST + r * d_entry
		pts_s.append(spawn_pt)
		pts_s.append(stop_pt)
		pts_s.append(exit_box_pt)
		pts_s.append(end_pt)
		exit_prog = stop_prog + stop_pt.distance_to(exit_box_pt)
	else:
		var ctrl: Vector3
		var exit_corner: Vector3
		var end_pt: Vector3
		if turn_type == TrafficController.TurnType.RIGHT:
			ctrl = -f * d_exit + r * d_entry
			exit_corner = -f * d_exit + r * cross_stop
			end_pt = -f * d_exit + r * SPAWN_DIST
		else: # LEFT
			ctrl = f * d_exit + r * d_entry
			exit_corner = f * d_exit - r * cross_stop
			end_pt = f * d_exit - r * SPAWN_DIST

		pts_s.append(spawn_pt)
		pts_s.append(stop_pt)

		var arc_len := 0.0
		var prev := stop_pt
		var steps := 24
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var omt := 1.0 - t
			var p := (omt * omt) * stop_pt + (2.0 * omt * t) * ctrl + (t * t) * exit_corner
			arc_len += prev.distance_to(p)
			pts_s.append(p)
			prev = p

		pts_s.append(end_pt)
		exit_prog = stop_prog + arc_len

	# If s_lanes == 0 (1-lane pure grade-separated overpass), E-W also flows non-stop without signals
	return {
		"points": pts_s,
		"stop_progress": stop_prog,
		"exit_progress": exit_prog,
		"ring_radius": 0.0,
		"is_underpass": (s_lanes == 0)
	}

func _build_signalized_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]

	var f: Vector3 = forwards[approach_idx]
	var r: Vector3 = rights[approach_idx]
	var is_ns := (approach_idx == 0 or approach_idx == 1)

	var ns_half: float = ns_lanes * LANE_WIDTH
	var ew_half: float = ew_lanes * LANE_WIDTH
	var entry_stop: float = (ew_half + 3.2) if is_ns else (ns_half + 3.2)
	var cross_stop: float = (ns_half + 3.2) if is_ns else (ew_half + 3.2)
	var cross_lanes: int = ew_lanes if is_ns else ns_lanes

	var d_entry: float = (lane_idx + 0.5) * LANE_WIDTH
	var exit_lane := clampi(lane_idx, 0, cross_lanes - 1)
	if turn_type == TrafficController.TurnType.LEFT:
		exit_lane = clampi(lane_idx, 0, mini(1, cross_lanes - 1))
	elif turn_type == TrafficController.TurnType.RIGHT:
		exit_lane = cross_lanes - 1
	var d_exit: float = (exit_lane + 0.5) * LANE_WIDTH

	var pts := PackedVector3Array()
	var spawn_pt := -f * SPAWN_DIST + r * d_entry
	var stop_pt := -f * entry_stop + r * d_entry
	var stop_prog := spawn_pt.distance_to(stop_pt)
	var exit_prog := stop_prog + entry_stop * 2.0

	if turn_type == TrafficController.TurnType.STRAIGHT:
		var exit_box_pt := f * entry_stop + r * d_entry
		var end_pt := f * SPAWN_DIST + r * d_entry
		pts.append(spawn_pt)
		pts.append(stop_pt)
		pts.append(exit_box_pt)
		pts.append(end_pt)
		exit_prog = stop_prog + stop_pt.distance_to(exit_box_pt)
	else:
		var ctrl: Vector3
		var exit_corner: Vector3
		var end_pt: Vector3
		if turn_type == TrafficController.TurnType.RIGHT:
			ctrl = -f * d_exit + r * d_entry
			exit_corner = -f * d_exit + r * cross_stop
			end_pt = -f * d_exit + r * SPAWN_DIST
		else: # LEFT
			ctrl = f * d_exit + r * d_entry
			exit_corner = f * d_exit - r * cross_stop
			end_pt = f * d_exit - r * SPAWN_DIST

		pts.append(spawn_pt)
		pts.append(stop_pt)

		var arc_len := 0.0
		var prev := stop_pt
		var steps := 24
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var omt := 1.0 - t
			var p := (omt * omt) * stop_pt + (2.0 * omt * t) * ctrl + (t * t) * exit_corner
			arc_len += prev.distance_to(p)
			pts.append(p)
			prev = p

		pts.append(end_pt)
		exit_prog = stop_prog + arc_len

	return {
		"points": pts,
		"stop_progress": stop_prog,
		"exit_progress": exit_prog,
		"ring_radius": 0.0
	}

func _build_roundabout_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]

	var f: Vector3 = forwards[approach_idx]
	var r: Vector3 = rights[approach_idx]
	var is_ns := (approach_idx == 0 or approach_idx == 1)

	var rinfo := RoadBuilder.get_roundabout_radii(ns_lanes, ew_lanes)
	var ring_lanes: int = rinfo["ring_lanes"]
	var island_r: float = rinfo["island_r"]
	var outer_r: float = rinfo["outer_r"]
	var yield_r: float = outer_r + 0.95

	var d_entry: float = (lane_idx + 0.5) * LANE_WIDTH
	var spawn_pt := -f * SPAWN_DIST + r * d_entry
	var entry_rim_d := sqrt(maxf(1.0, outer_r * outer_r - d_entry * d_entry))
	var entry_yield_d := sqrt(maxf(1.0, yield_r * yield_r - d_entry * d_entry))
	var yield_pt := -f * entry_yield_d + r * d_entry
	var entry_rim := -f * entry_rim_d + r * d_entry

	var exit_f: Vector3 = f
	var exit_r: Vector3 = r
	var exit_lanes: int = ns_lanes if is_ns else ew_lanes
	if turn_type == TrafficController.TurnType.RIGHT:
		exit_f = r
		exit_r = -f
		exit_lanes = ew_lanes if is_ns else ns_lanes
	elif turn_type == TrafficController.TurnType.LEFT:
		exit_f = -r
		exit_r = f
		exit_lanes = ew_lanes if is_ns else ns_lanes

	var circ_lane := clampi(lane_idx, 0, ring_lanes - 1)
	var exit_lane := clampi(lane_idx, 0, exit_lanes - 1)
	if turn_type == TrafficController.TurnType.RIGHT:
		circ_lane = ring_lanes - 1
		exit_lane = exit_lanes - 1
	elif turn_type == TrafficController.TurnType.LEFT:
		circ_lane = clampi(lane_idx, 0, mini(1, ring_lanes - 1))
		exit_lane = clampi(lane_idx, 0, mini(1, exit_lanes - 1))

	var r_circ := island_r + (float(circ_lane) + 0.5) * LANE_WIDTH
	var d_exit := (float(exit_lane) + 0.5) * LANE_WIDTH
	var exit_rim_d := sqrt(maxf(1.0, outer_r * outer_r - d_exit * d_exit))
	var exit_yield_d := sqrt(maxf(1.0, yield_r * yield_r - d_exit * d_exit))
	var exit_rim := exit_f * exit_rim_d + exit_r * d_exit
	var exit_yield := exit_f * exit_yield_d + exit_r * d_exit
	var end_pt := exit_f * SPAWN_DIST + exit_r * d_exit

	var pts := PackedVector3Array()
	pts.append(spawn_pt)
	pts.append(yield_pt)
	var stop_prog := spawn_pt.distance_to(yield_pt)

	var a_entry := atan2(entry_rim.z, entry_rim.x)
	var a_exit := atan2(exit_rim.z, exit_rim.x)
	var raw_ccw := wrapf(a_exit - a_entry, -TAU, 0.0)
	if raw_ccw > -0.02:
		raw_ccw -= TAU

	var arc_len := 0.0
	var prev := yield_pt

	if turn_type == TrafficController.TurnType.RIGHT and absf(raw_ccw) < 0.30:
		var mid_a := a_entry + raw_ccw * 0.5
		var ctrl := Vector3(cos(mid_a) * outer_r, 0.0, sin(mid_a) * outer_r)
		var steps := 14
		for s in range(1, steps + 1):
			var t := float(s) / float(steps)
			var omt := 1.0 - t
			var p := (omt * omt) * yield_pt + (2.0 * omt * t) * ctrl + (t * t) * exit_yield
			arc_len += prev.distance_to(p)
			pts.append(p)
			prev = p
	else:
		var shift := minf(0.14, absf(raw_ccw) * 0.22)
		var a_start := a_entry - shift
		var a_end := a_entry + raw_ccw + shift
		var p_ring_start := Vector3(cos(a_start) * r_circ, 0.0, sin(a_start) * r_circ)
		var p_ring_end := Vector3(cos(a_end) * r_circ, 0.0, sin(a_end) * r_circ)

		# 1. Smooth entry curve: yield_pt -> entry_rim -> p_ring_start
		for s in range(1, 7):
			var t := float(s) / 6.0
			var omt := 1.0 - t
			var p := (omt * omt) * yield_pt + (2.0 * omt * t) * entry_rim + (t * t) * p_ring_start
			arc_len += prev.distance_to(p)
			pts.append(p)
			prev = p

		# 2. High-res CCW circular arc along r_circ
		var sweep := a_end - a_start
		var arc_steps := clampi(int(absf(sweep) * 18.0), 8, 48)
		for s in range(1, arc_steps + 1):
			var t := float(s) / float(arc_steps)
			var ang := a_start + sweep * t
			var p := Vector3(cos(ang) * r_circ, 0.0, sin(ang) * r_circ)
			arc_len += prev.distance_to(p)
			pts.append(p)
			prev = p

		# 3. Smooth exit curve: p_ring_end -> exit_rim -> exit_yield
		for s in range(1, 7):
			var t := float(s) / 6.0
			var omt := 1.0 - t
			var p := (omt * omt) * p_ring_end + (2.0 * omt * t) * exit_rim + (t * t) * exit_yield
			arc_len += prev.distance_to(p)
			pts.append(p)
			prev = p

	pts.append(end_pt)
	var exit_prog := stop_prog + arc_len

	return {
		"points": pts,
		"stop_progress": stop_prog,
		"exit_progress": exit_prog,
		"ring_radius": r_circ
	}
