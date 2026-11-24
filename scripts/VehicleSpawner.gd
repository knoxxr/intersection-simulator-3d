extends Node3D
class_name VehicleSpawner

const LANE_WIDTH: float = 3.5
const SPAWN_DIST: float = 64.0
const MAX_VEHICLES: int = 95

# Live configurable simulation settings (now supporting asymmetric N-S and E-W lanes!)
var ns_lanes: int = 2
var ew_lanes: int = 2
var lane_enabled: Array[bool] = [true, true, true]
var approach_enabled: Array[bool] = [true, true, true, true] # N, S, E, W
var global_traffic_rate: float = 1.0
var dir_traffic_mult: Array[float] = [1.0, 1.0, 1.0, 1.0]
var left_turn_ratio: float = 0.22
var right_turn_ratio: float = 0.20

var spawn_timers: Array[float] = [0.4, 0.9, 1.4, 1.9]
var active_vehicles: Array[SimVehicle] = []

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
			v.queue_free()
	active_vehicles.clear()

func get_waiting_counts_by_dir() -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	for v in active_vehicles:
		if is_instance_valid(v) and v.is_waiting:
			counts[v.approach_idx] += 1
	return counts

func get_active_emergency_approach() -> int:
	# Returns approach_idx of closest approaching emergency vehicle not yet past intersection, else -1
	var best_app := -1
	var best_dist := 9999.0
	for v in active_vehicles:
		if is_instance_valid(v) and v.is_emergency and not v.has_passed_intersection:
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
		# Pick approaches sorted randomly among enabled ones
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
		var path_data := _build_vehicle_path(app, chosen_lane, TrafficController.TurnType.STRAIGHT)
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
			Color.WHITE
		)
		active_vehicles.append(veh)
		return true
	return false

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
			var lane_factor := 1.0 / (0.65 + 0.35 * l_cnt)
			spawn_timers[a] = randf_range(1.6, 3.0) * lane_factor
			if active_vehicles.size() < MAX_VEHICLES:
				_try_spawn_on_approach(a)

	var i := active_vehicles.size() - 1
	while i >= 0:
		var v := active_vehicles[i]
		if not is_instance_valid(v):
			active_vehicles.remove_at(i)
			i -= 1
			continue
		v.step_vehicle(delta, traffic_ctrl, active_vehicles)
		if v.finished:
			vehicle_passed.emit(v.wait_time)
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
	var path_data := _build_vehicle_path(approach_idx, chosen_lane, turn_type)
	var pts: PackedVector3Array = path_data["points"]
	var spawn_pos: Vector3 = pts[0]

	for other in active_vehicles:
		if is_instance_valid(other) and other.position.distance_squared_to(spawn_pos) < 90.0:
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
		col
	)
	active_vehicles.append(veh)

func _pick_lane_for_turn(open_lanes: Array[int], total_lanes: int, turn_type: int) -> int:
	if open_lanes.size() == 1:
		return open_lanes[0]
	if turn_type == TrafficController.TurnType.LEFT:
		return open_lanes[0]
	elif turn_type == TrafficController.TurnType.RIGHT:
		return open_lanes[open_lanes.size() - 1]
	else:
		if total_lanes == 3 and open_lanes.has(1):
			if open_lanes.has(2) and randf() < 0.45:
				return 2
			return 1
		return open_lanes[randi() % open_lanes.size()]

func _build_vehicle_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
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
		exit_lane = 0
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
		var steps := 14
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
		"exit_progress": exit_prog
	}
