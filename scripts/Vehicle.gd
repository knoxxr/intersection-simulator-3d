extends Node3D
class_name SimVehicle

enum VehicleKind { SEDAN, SUV, TRUCK, TAXI }

var approach_idx: int = 0       # 0=N, 1=S, 2=E, 3=W
var lane_idx: int = 0
var turn_type: int = 0          # TrafficController.TurnType
var kind: VehicleKind = VehicleKind.SEDAN

var path_points: PackedVector3Array = PackedVector3Array()
var path_cum_dist: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 1.0
var stop_progress: float = 40.0
var exit_box_progress: float = 65.0

var progress: float = 0.0
var speed: float = 8.0
var max_speed: float = 12.5
var max_accel: float = 4.2
var comfort_decel: float = 5.5
var vehicle_length: float = 4.2

var forward: Vector3 = Vector3(0, 0, 1)
var is_waiting: bool = false
var wait_time: float = 0.0
var has_passed_intersection: bool = false
var finished: bool = false

var brake_mat: StandardMaterial3D
var turn_signal_mat: StandardMaterial3D
var _blink_accum: float = 0.0

func setup(
	p_approach: int,
	p_lane: int,
	p_turn: int,
	p_points: PackedVector3Array,
	p_stop_prog: float,
	p_exit_prog: float,
	p_kind: VehicleKind,
	p_color: Color
) -> void:
	approach_idx = p_approach
	lane_idx = p_lane
	turn_type = p_turn
	path_points = p_points
	stop_progress = p_stop_prog
	exit_box_progress = p_exit_prog
	kind = p_kind

	match kind:
		VehicleKind.SEDAN:
			vehicle_length = 4.2
			max_speed = randf_range(11.5, 14.0)
			max_accel = 4.4
		VehicleKind.SUV:
			vehicle_length = 4.6
			max_speed = randf_range(11.0, 13.2)
			max_accel = 4.0
		VehicleKind.TRUCK:
			vehicle_length = 6.4
			max_speed = randf_range(9.0, 11.0)
			max_accel = 2.8
		VehicleKind.TAXI:
			vehicle_length = 4.3
			max_speed = randf_range(12.2, 14.5)
			max_accel = 4.8

	speed = max_speed * 0.75
	_bake_path()
	_build_mesh(p_color)
	_apply_transform_at(0.0)

func _bake_path() -> void:
	path_cum_dist.clear()
	if path_points.size() < 2:
		total_length = 1.0
		return
	path_cum_dist.append(0.0)
	var acc := 0.0
	for i in range(1, path_points.size()):
		acc += path_points[i - 1].distance_to(path_points[i])
		path_cum_dist.append(acc)
	total_length = max(acc, 0.1)

func _sample_pos_and_dir(dist: float) -> Array:
	if path_points.size() < 2:
		return [position, forward]
	var clamped: float = clamp(dist, 0.0, total_length)
	# Binary search segment
	var lo := 0
	var hi := path_cum_dist.size() - 2
	while lo < hi:
		var mid := (lo + hi) >> 1
		if path_cum_dist[mid + 1] < clamped:
			lo = mid + 1
		else:
			hi = mid
	var d0 := path_cum_dist[lo]
	var d1 := path_cum_dist[lo + 1]
	var t := 0.0 if (d1 - d0) < 0.0001 else (clamped - d0) / (d1 - d0)
	var p := path_points[lo].lerp(path_points[lo + 1], t)
	var dir := (path_points[lo + 1] - path_points[lo])
	dir.y = 0.0
	if dir.length_squared() > 0.00001:
		dir = dir.normalized()
	else:
		dir = forward
	return [p, dir]

func _apply_transform_at(dist: float) -> void:
	var res := _sample_pos_and_dir(dist)
	var p: Vector3 = res[0]
	var f: Vector3 = res[1]
	position = Vector3(p.x, 0.04, p.z)
	forward = f
	var z_axis := -f
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	basis = Basis(x_axis, Vector3.UP, z_axis)

func _build_mesh(body_color: Color) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.roughness = 0.35
	body_mat.metallic = 0.25

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.14, 0.22, 0.3, 1.0)
	glass_mat.roughness = 0.15
	glass_mat.metallic = 0.4

	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.08, 0.08, 0.09)
	wheel_mat.roughness = 0.85

	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.96, 0.82)
	head_mat.emission_energy_multiplier = 1.4

	brake_mat = StandardMaterial3D.new()
	brake_mat.albedo_color = Color(0.45, 0.05, 0.05)
	brake_mat.roughness = 0.3

	turn_signal_mat = StandardMaterial3D.new()
	turn_signal_mat.albedo_color = Color(0.35, 0.22, 0.02)
	turn_signal_mat.roughness = 0.3

	var w := 1.85
	var h := 0.72
	var l := vehicle_length

	if kind == VehicleKind.TRUCK:
		w = 2.15
		# Front cab (-Z is front)
		_add_part(Vector3(w * 0.94, 1.85, 1.8), Vector3(0, 1.25, -l * 0.5 + 0.95), body_mat)
		_add_part(Vector3(w * 0.88, 0.75, 0.2), Vector3(0, 1.55, -l * 0.5 + 0.02), glass_mat)
		# Cargo trailer box
		var cargo_mat := StandardMaterial3D.new()
		cargo_mat.albedo_color = Color(0.9, 0.91, 0.93)
		cargo_mat.roughness = 0.6
		_add_part(Vector3(w, 2.35, l - 2.1), Vector3(0, 1.55, 0.95), cargo_mat)
	else:
		if kind == VehicleKind.SUV:
			w = 1.96
			h = 0.82
		# Lower chassis
		_add_part(Vector3(w, h, l), Vector3(0, 0.32 + h * 0.5, 0), body_mat)
		# Upper cabin
		var cab_len := l * (0.62 if kind == VehicleKind.SUV else 0.50)
		var cab_h := 0.68 if kind == VehicleKind.SUV else 0.56
		var cab_z := 0.22 if kind == VehicleKind.SEDAN or kind == VehicleKind.TAXI else 0.1
		_add_part(Vector3(w * 0.86, cab_h, cab_len), Vector3(0, 0.32 + h + cab_h * 0.5 - 0.04, cab_z), body_mat)
		# Windows band
		_add_part(Vector3(w * 0.88, cab_h * 0.68, cab_len * 0.92), Vector3(0, 0.32 + h + cab_h * 0.52 - 0.04, cab_z), glass_mat)

		# Taxi roof sign
		if kind == VehicleKind.TAXI:
			var sign_mat := StandardMaterial3D.new()
			sign_mat.albedo_color = Color(1.0, 0.92, 0.2)
			sign_mat.emission_enabled = true
			sign_mat.emission = Color(1.0, 0.85, 0.15)
			sign_mat.emission_energy_multiplier = 1.2
			_add_part(Vector3(0.65, 0.22, 0.28), Vector3(0, 0.32 + h + cab_h + 0.08, 0.1), sign_mat)

	# 4 Wheels
	var wheel_z := l * 0.31
	var wheel_x := w * 0.48
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wh := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 0.24
			wh.mesh = cm
			wh.material_override = wheel_mat
			wh.rotation_degrees = Vector3(0, 0, 90)
			wh.position = Vector3(sx * wheel_x, 0.34, sz * wheel_z)
			add_child(wh)

	# Headlights (-Z front)
	for sx in [-1.0, 1.0]:
		_add_part(Vector3(0.32, 0.18, 0.08), Vector3(sx * (w * 0.34), 0.62, -l * 0.5 - 0.02), head_mat)
		# Brake lights (+Z rear)
		_add_part(Vector3(0.36, 0.18, 0.08), Vector3(sx * (w * 0.34), 0.65, l * 0.5 + 0.02), brake_mat)

	# Turn indicator light on turning side
	if turn_type == TrafficController.TurnType.LEFT:
		_add_part(Vector3(0.22, 0.16, 0.12), Vector3(-w * 0.42, 0.62, -l * 0.5 - 0.03), turn_signal_mat)
		_add_part(Vector3(0.22, 0.16, 0.12), Vector3(-w * 0.42, 0.65, l * 0.5 + 0.03), turn_signal_mat)
	elif turn_type == TrafficController.TurnType.RIGHT:
		_add_part(Vector3(0.22, 0.16, 0.12), Vector3(w * 0.42, 0.62, -l * 0.5 - 0.03), turn_signal_mat)
		_add_part(Vector3(0.22, 0.16, 0.12), Vector3(w * 0.42, 0.65, l * 0.5 + 0.03), turn_signal_mat)

func _add_part(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func step_vehicle(delta: float, traffic_ctrl: TrafficController, all_vehicles: Array) -> void:
	if finished:
		return

	var target_speed := max_speed
	# Slow down smoothly while curving inside intersection
	var inside_intersection := (progress >= stop_progress - 2.0 and progress <= exit_box_progress)
	if inside_intersection and turn_type != TrafficController.TurnType.STRAIGHT:
		target_speed = min(target_speed, 7.2)

	var must_stop_dist := 9999.0

	# 1. Traffic signal check (only before crossing stop line)
	var dist_to_stop := stop_progress - (progress + vehicle_length * 0.52)
	if dist_to_stop > -0.8 and progress < stop_progress:
		var aspect := traffic_ctrl.get_signal_for(approach_idx, turn_type)
		if aspect == TrafficController.Aspect.RED:
			must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif aspect == TrafficController.Aspect.YELLOW:
			# Stop if enough room to stop comfortably, otherwise clear the intersection
			var min_brake_dist := (speed * speed) / (2.0 * comfort_decel * 1.15)
			if dist_to_stop > max(1.0, min_brake_dist * 0.75):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif aspect == TrafficController.Aspect.FLASHING_YELLOW:
			# Caution mode: slow down when approaching stop line & yield if another approach is in the box
			if dist_to_stop < 12.0:
				target_speed = min(target_speed, 5.5)
			if dist_to_stop < 5.0 and _has_conflicting_in_box(all_vehicles, false):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif traffic_ctrl.is_unprotected_left(approach_idx, turn_type):
			# Yield to oncoming straight/right traffic when turning left on 2-phase green
			if dist_to_stop < 6.0 and _has_oncoming_straight(all_vehicles):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))

	# 2. Car-following & collision avoidance against other vehicles
	var min_gap := 2.0
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		var rel: Vector3 = other.position - position
		var dist_sq := rel.length_squared()
		if dist_sq > 625.0: # > 25m ignore
			continue

		var fwd_dist := rel.dot(forward)
		if fwd_dist <= 0.1:
			continue
		var lat_dist := absf(rel.dot(Vector3(-forward.z, 0.0, forward.x)))

		# Same direction / queued vehicle check
		var other_v: SimVehicle = other
		var dir_dot: float = forward.dot(other_v.forward)
		if dir_dot > 0.65 and lat_dist < 1.85:
			var gap: float = fwd_dist - (vehicle_length * 0.5 + other_v.vehicle_length * 0.5) - min_gap
			if gap < must_stop_dist:
				must_stop_dist = gap
				# Also match slower leader speed smoothly
				if gap < 6.0:
					target_speed = min(target_speed, other_v.speed)
		elif dir_dot <= 0.65 and lat_dist < 2.6 and fwd_dist < 10.5:
			# Crossing vehicle right in front of us inside intersection
			var gap: float = fwd_dist - (vehicle_length * 0.5 + 1.8) - 1.2
			if gap < must_stop_dist:
				must_stop_dist = gap

	# 3. Compute acceleration from target_speed and stopping distance
	var desired_speed := target_speed
	if must_stop_dist < 18.0:
		if must_stop_dist <= 0.15:
			desired_speed = 0.0
		else:
			# Safe speed to stop within must_stop_dist: v = sqrt(2 * a * d)
			var safe_v := sqrt(max(0.0, 2.0 * (comfort_decel * 0.85) * must_stop_dist))
			desired_speed = min(desired_speed, safe_v)

	var braking := false
	if desired_speed < speed:
		var decel := comfort_decel * (1.8 if must_stop_dist < 2.5 else 1.0)
		speed = max(desired_speed, speed - decel * delta)
		braking = (speed - desired_speed > 0.35) or (speed < 0.8)
	else:
		speed = min(desired_speed, speed + max_accel * delta)
		braking = speed < 0.4

	# Advance along path
	progress += speed * delta
	if not has_passed_intersection and progress >= exit_box_progress:
		has_passed_intersection = true

	# Wait metric tracking (counted when stalled before leaving intersection)
	is_waiting = (speed < 0.6 and not has_passed_intersection)
	if is_waiting:
		wait_time += delta

	# Update visuals: brake lights & blinking turn signal
	_update_lights(delta, braking)

	if progress >= total_length:
		finished = true
		return

	_apply_transform_at(progress)

func _has_conflicting_in_box(all_vehicles: Array, _unused: bool) -> bool:
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		if other.approach_idx == approach_idx:
			continue
		if other.progress >= other.stop_progress - 0.5 and other.progress <= other.exit_box_progress:
			return true
	return false

func _has_oncoming_straight(all_vehicles: Array) -> bool:
	# Opposite approach: 0<->1, 2<->3
	var opp := 1 if approach_idx == 0 else (0 if approach_idx == 1 else (3 if approach_idx == 2 else 2))
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		if other.approach_idx == opp and other.turn_type != TrafficController.TurnType.LEFT:
			# Oncoming car is inside intersection or within 14m of stop line and moving
			var d_stop: float = other.stop_progress - other.progress
			if other.progress <= other.exit_box_progress and d_stop < 15.0 and other.speed > 1.5:
				return true
	return false

func _update_lights(delta: float, braking: bool) -> void:
	if brake_mat:
		if braking:
			brake_mat.albedo_color = Color(1.0, 0.1, 0.08)
			brake_mat.emission_enabled = true
			brake_mat.emission = Color(1.0, 0.12, 0.08)
			brake_mat.emission_energy_multiplier = 2.0
		else:
			brake_mat.albedo_color = Color(0.45, 0.05, 0.05)
			brake_mat.emission_enabled = false

	if turn_type != TrafficController.TurnType.STRAIGHT and turn_signal_mat:
		var near_turn := (progress > stop_progress - 18.0 and progress < exit_box_progress + 2.0)
		_blink_accum += delta
		var on := near_turn and fmod(_blink_accum, 0.7) < 0.35
		if on:
			turn_signal_mat.albedo_color = Color(1.0, 0.68, 0.05)
			turn_signal_mat.emission_enabled = true
			turn_signal_mat.emission = Color(1.0, 0.65, 0.05)
			turn_signal_mat.emission_energy_multiplier = 2.2
		else:
			turn_signal_mat.albedo_color = Color(0.35, 0.22, 0.02)
			turn_signal_mat.emission_enabled = false
