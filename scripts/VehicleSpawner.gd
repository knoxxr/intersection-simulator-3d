extends Node3D
class_name VehicleSpawner

const LANE_WIDTH: float = 3.5
const SPAWN_DIST: float = 64.0
const MAX_VEHICLES: int = 90

# Live configurable simulation settings
var lane_count: int = 2
var lane_enabled: Array[bool] = [true, true, true]
var approach_enabled: Array[bool] = [true, true, true, true] # N, S, E, W
var global_traffic_rate: float = 1.0  # Multiplier 0.0 ~ 3.0 (1.0 = ~1 vehicle every 2.2s per approach)
var dir_traffic_mult: Array[float] = [1.0, 1.0, 1.0, 1.0] # N, S, E, W individual volume 0.0 ~ 2.0
var left_turn_ratio: float = 0.22
var right_turn_ratio: float = 0.20

var spawn_timers: Array[float] = [0.4, 0.9, 1.4, 1.9]
var active_vehicles: Array[SimVehicle] = []

# Metrics signals
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

func step_simulation(delta: float, traffic_ctrl: TrafficController) -> void:
	# 1. Spawn logic for each of the 4 approaches
	for a in range(4):
		if not approach_enabled[a]:
			continue
		var rate: float = global_traffic_rate * dir_traffic_mult[a]
		if rate <= 0.02:
			continue

		spawn_timers[a] -= delta * rate
		if spawn_timers[a] <= 0.0:
			# Base interval ~2.3s scaled inversely by lane_count slightly so wider roads fill nicely
			var lane_factor := 1.0 / (0.65 + 0.35 * lane_count)
			spawn_timers[a] = randf_range(1.6, 3.0) * lane_factor
			if active_vehicles.size() < MAX_VEHICLES:
				_try_spawn_on_approach(a)

	# 2. Step all vehicles
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
	# Collect currently open lanes
	var open_lanes: Array[int] = []
	for l in range(lane_count):
		if l < lane_enabled.size() and lane_enabled[l]:
			open_lanes.append(l)
	if open_lanes.is_empty():
		return

	# Choose turn type
	var r := randf()
	var turn_type := TrafficController.TurnType.STRAIGHT
	if r < left_turn_ratio:
		turn_type = TrafficController.TurnType.LEFT
	elif r < left_turn_ratio + right_turn_ratio:
		turn_type = TrafficController.TurnType.RIGHT

	# Choose appropriate lane for the turn type among open lanes
	var chosen_lane := _pick_lane_for_turn(open_lanes, turn_type)
	# If chosen lane doesn't support turn (e.g. only outer lane open), adjust turn type cleanly
	var path_data := _build_vehicle_path(approach_idx, chosen_lane, turn_type)
	var pts: PackedVector3Array = path_data["points"]
	var spawn_pos: Vector3 = pts[0]

	# Ensure spawn zone is clear of queued cars (minimum 9.5m clearance)
	for other in active_vehicles:
		if is_instance_valid(other) and other.position.distance_squared_to(spawn_pos) < 90.0:
			return

	# Pick vehicle kind & color
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

func _pick_lane_for_turn(open_lanes: Array[int], turn_type: int) -> int:
	if open_lanes.size() == 1:
		return open_lanes[0]
	if turn_type == TrafficController.TurnType.LEFT:
		# Innermost open lane (smallest index)
		return open_lanes[0]
	elif turn_type == TrafficController.TurnType.RIGHT:
		# Outermost open lane (largest index)
		return open_lanes[open_lanes.size() - 1]
	else:
		# Straight: prefer middle/outer if 3 lanes, else any open lane
		if lane_count == 3 and open_lanes.has(1):
			if open_lanes.has(2) and randf() < 0.45:
				return 2
			return 1
		return open_lanes[randi() % open_lanes.size()]

func _build_vehicle_path(approach_idx: int, lane_idx: int, turn_type: int) -> Dictionary:
	# Unit forward (F) and right (R) vectors for right-hand traffic
	var forwards := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var rights := [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]

	var f: Vector3 = forwards[approach_idx]
	var r: Vector3 = rights[approach_idx]

	var road_half: float = lane_count * LANE_WIDTH
	var stop_dist: float = road_half + 3.2
	var d_entry: float = (lane_idx + 0.5) * LANE_WIDTH

	var exit_lane := clampi(lane_idx, 0, lane_count - 1)
	if turn_type == TrafficController.TurnType.LEFT:
		exit_lane = 0
	elif turn_type == TrafficController.TurnType.RIGHT:
		exit_lane = lane_count - 1
	var d_exit: float = (exit_lane + 0.5) * LANE_WIDTH

	var pts := PackedVector3Array()
	var spawn_pt := -f * SPAWN_DIST + r * d_entry
	var stop_pt := -f * stop_dist + r * d_entry
	var stop_prog := spawn_pt.distance_to(stop_pt)
	var exit_prog := stop_prog + stop_dist * 2.0

	if turn_type == TrafficController.TurnType.STRAIGHT:
		var exit_box_pt := f * stop_dist + r * d_entry
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
			exit_corner = -f * d_exit + r * stop_dist
			end_pt = -f * d_exit + r * SPAWN_DIST
		else: # LEFT
			ctrl = f * d_exit + r * d_entry
			exit_corner = f * d_exit - r * stop_dist
			end_pt = f * d_exit - r * SPAWN_DIST

		pts.append(spawn_pt)
		pts.append(stop_pt)

		# Sample quadratic Bezier smoothly (14 segments)
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
