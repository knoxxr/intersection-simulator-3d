extends Node3D
class_name SimVehicle

enum VehicleKind { SEDAN, SUV, TRUCK, TAXI, AMBULANCE }

# Static shared materials (eliminates per-vehicle material allocation & WebGL2 shader recompilation flicker)
static var _mats_ready: bool = false
static var _glass_mat: StandardMaterial3D
static var _wheel_mat: StandardMaterial3D
static var _head_mat: StandardMaterial3D
static var _cargo_mat: StandardMaterial3D
static var _taxi_sign_mat: StandardMaterial3D
static var _amb_stripe_mat: StandardMaterial3D
static var _siren_red_on: StandardMaterial3D
static var _siren_red_off: StandardMaterial3D
static var _siren_blue_on: StandardMaterial3D
static var _siren_blue_off: StandardMaterial3D
static var _brake_off_mat: StandardMaterial3D
static var _brake_on_mat: StandardMaterial3D
static var _turn_off_mat: StandardMaterial3D
static var _turn_on_mat: StandardMaterial3D
static var _body_mat_cache: Dictionary = {}

static func _ensure_shared_mats() -> void:
	if _mats_ready:
		return
	_mats_ready = true

	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.14, 0.22, 0.30, 1.0)
	_glass_mat.roughness = 0.20
	_glass_mat.metallic = 0.35

	_wheel_mat = StandardMaterial3D.new()
	_wheel_mat.albedo_color = Color(0.08, 0.08, 0.09)
	_wheel_mat.roughness = 0.85

	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color(1.0, 0.97, 0.85)
	_head_mat.emission_enabled = true
	_head_mat.emission = Color(1.0, 0.96, 0.82)
	_head_mat.emission_energy_multiplier = 1.6

	_cargo_mat = StandardMaterial3D.new()
	_cargo_mat.albedo_color = Color(0.90, 0.91, 0.93)
	_cargo_mat.roughness = 0.60

	_taxi_sign_mat = StandardMaterial3D.new()
	_taxi_sign_mat.albedo_color = Color(1.0, 0.92, 0.20)
	_taxi_sign_mat.emission_enabled = true
	_taxi_sign_mat.emission = Color(1.0, 0.85, 0.15)
	_taxi_sign_mat.emission_energy_multiplier = 1.3

	_amb_stripe_mat = StandardMaterial3D.new()
	_amb_stripe_mat.albedo_color = Color(0.92, 0.12, 0.12)
	_amb_stripe_mat.roughness = 0.35

	_siren_red_on = _make_emissive_mat(Color(1.0, 0.12, 0.12), Color(1.0, 0.10, 0.10), 3.0)
	_siren_red_off = _make_emissive_mat(Color(0.32, 0.05, 0.05), Color.BLACK, 0.0)
	_siren_blue_on = _make_emissive_mat(Color(0.12, 0.45, 1.0), Color(0.10, 0.48, 1.0), 3.0)
	_siren_blue_off = _make_emissive_mat(Color(0.05, 0.12, 0.32), Color.BLACK, 0.0)

	_brake_off_mat = _make_emissive_mat(Color(0.45, 0.05, 0.05), Color.BLACK, 0.0)
	_brake_on_mat = _make_emissive_mat(Color(1.0, 0.10, 0.08), Color(1.0, 0.12, 0.08), 2.0)

	_turn_off_mat = _make_emissive_mat(Color(0.35, 0.22, 0.02), Color.BLACK, 0.0)
	_turn_on_mat = _make_emissive_mat(Color(1.0, 0.68, 0.05), Color(1.0, 0.65, 0.05), 2.0)

static func _make_emissive_mat(albedo: Color, em: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.28
	m.emission_enabled = true
	m.emission = em
	m.emission_energy_multiplier = energy
	return m

static func _get_body_mat(col: Color) -> StandardMaterial3D:
	var key := col.to_rgba32()
	if _body_mat_cache.has(key):
		return _body_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.35
	m.metallic = 0.22
	_body_mat_cache[key] = m
	return m

var approach_idx: int = 0       # 0=N, 1=S, 2=E, 3=W
var lane_idx: int = 0
var turn_type: int = 0          # TrafficController.TurnType
var kind: VehicleKind = VehicleKind.SEDAN
var is_emergency: bool = false

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

var _brake_meshes: Array[MeshInstance3D] = []
var _turn_meshes: Array[MeshInstance3D] = []
var _siren_red_mesh: MeshInstance3D
var _siren_blue_mesh: MeshInstance3D
var _brake_lit: bool = false
var _turn_lit: bool = false
var _siren_phase: bool = false
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
	_ensure_shared_mats()
	approach_idx = p_approach
	lane_idx = p_lane
	turn_type = p_turn
	path_points = p_points
	stop_progress = p_stop_prog
	exit_box_progress = p_exit_prog
	kind = p_kind
	is_emergency = (kind == VehicleKind.AMBULANCE)

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
		VehicleKind.AMBULANCE:
			vehicle_length = 5.2
			max_speed = 16.8
			max_accel = 5.8
			comfort_decel = 7.0

	speed = max_speed * 0.80
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
	position = Vector3(p.x, 0.06, p.z)
	forward = f
	var z_axis := -f
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	basis = Basis(x_axis, Vector3.UP, z_axis)

func _build_mesh(body_color: Color) -> void:
	var body_mat := _get_body_mat(body_color)

	var w := 1.85
	var h := 0.72
	var l := vehicle_length

	if kind == VehicleKind.TRUCK:
		w = 2.15
		_add_part(Vector3(w * 0.94, 1.85, 1.8), Vector3(0, 1.25, -l * 0.5 + 0.95), body_mat)
		_add_part(Vector3(w * 0.84, 0.72, 0.12), Vector3(0, 1.55, -l * 0.5 + 0.02), _glass_mat)
		_add_part(Vector3(w, 2.35, l - 2.15), Vector3(0, 1.55, 0.98), _cargo_mat)
	elif kind == VehicleKind.AMBULANCE:
		w = 2.08
		var amb_white := _get_body_mat(Color(0.96, 0.97, 0.99))
		# Main van body
		_add_part(Vector3(w, 1.55, l), Vector3(0, 1.12, 0), amb_white)
		# Red emergency side/front trim stripe cleanly protruding outside van body
		_add_part(Vector3(w + 0.08, 0.24, l * 0.72), Vector3(0, 0.95, 0.35), _amb_stripe_mat)
		# Red cross on roof
		_add_part(Vector3(0.95, 0.06, 0.28), Vector3(0, 1.94, 0.45), _amb_stripe_mat)
		_add_part(Vector3(0.28, 0.06, 0.95), Vector3(0, 1.94, 0.45), _amb_stripe_mat)
		# Front windshield
		_add_part(Vector3(w * 0.86, 0.58, 0.10), Vector3(0, 1.48, -l * 0.5 - 0.02), _glass_mat)
		# Flashing roof lightbar (Red left / Blue right)
		_siren_red_mesh = _add_part(Vector3(0.55, 0.24, 0.32), Vector3(-0.34, 2.04, -l * 0.24), _siren_red_on)
		_siren_blue_mesh = _add_part(Vector3(0.55, 0.24, 0.32), Vector3(0.34, 2.04, -l * 0.24), _siren_blue_off)
	else:
		if kind == VehicleKind.SUV:
			w = 1.96
			h = 0.82
		_add_part(Vector3(w, h, l), Vector3(0, 0.34 + h * 0.5, 0), body_mat)
		var cab_len := l * (0.60 if kind == VehicleKind.SUV else 0.48)
		var glass_h := 0.48 if kind == VehicleKind.SUV else 0.42
		var roof_h := 0.16
		var cab_z := 0.22 if kind == VehicleKind.SEDAN or kind == VehicleKind.TAXI else 0.10
		var chassis_top := 0.34 + h
		_add_part(Vector3(w * 0.84, glass_h, cab_len * 0.94), Vector3(0, chassis_top + glass_h * 0.5, cab_z), _glass_mat)
		_add_part(Vector3(w * 0.88, roof_h, cab_len), Vector3(0, chassis_top + glass_h + roof_h * 0.5, cab_z), body_mat)

		if kind == VehicleKind.TAXI:
			_add_part(Vector3(0.65, 0.22, 0.28), Vector3(0, chassis_top + glass_h + roof_h + 0.12, 0.10), _taxi_sign_mat)

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
			wh.material_override = _wheel_mat
			wh.rotation_degrees = Vector3(0, 0, 90)
			wh.position = Vector3(sx * wheel_x, 0.34, sz * wheel_z)
			add_child(wh)

	# Headlights (-Z front) & Brake lights (+Z rear)
	for sx in [-1.0, 1.0]:
		_add_part(Vector3(0.32, 0.18, 0.08), Vector3(sx * (w * 0.34), 0.64, -l * 0.5 - 0.05), _head_mat)
		var bm := _add_part(Vector3(0.36, 0.18, 0.08), Vector3(sx * (w * 0.34), 0.66, l * 0.5 + 0.05), _brake_off_mat)
		_brake_meshes.append(bm)

	# Turn indicator light on turning side
	if turn_type == TrafficController.TurnType.LEFT:
		_turn_meshes.append(_add_part(Vector3(0.22, 0.16, 0.10), Vector3(-w * 0.42, 0.64, -l * 0.5 - 0.06), _turn_off_mat))
		_turn_meshes.append(_add_part(Vector3(0.22, 0.16, 0.10), Vector3(-w * 0.42, 0.66, l * 0.5 + 0.06), _turn_off_mat))
	elif turn_type == TrafficController.TurnType.RIGHT:
		_turn_meshes.append(_add_part(Vector3(0.22, 0.16, 0.10), Vector3(w * 0.42, 0.64, -l * 0.5 - 0.06), _turn_off_mat))
		_turn_meshes.append(_add_part(Vector3(0.22, 0.16, 0.10), Vector3(w * 0.42, 0.66, l * 0.5 + 0.06), _turn_off_mat))

func _add_part(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func step_vehicle(delta: float, traffic_ctrl: TrafficController, all_vehicles: Array) -> void:
	if finished:
		return

	var target_speed := max_speed
	var inside_intersection := (progress >= stop_progress - 2.0 and progress <= exit_box_progress)
	if inside_intersection and turn_type != TrafficController.TurnType.STRAIGHT:
		target_speed = min(target_speed, 7.6)

	var must_stop_dist := 9999.0

	# 1. Traffic signal check (only before crossing stop line)
	var dist_to_stop := stop_progress - (progress + vehicle_length * 0.52)
	if dist_to_stop > -0.8 and progress < stop_progress:
		var aspect := traffic_ctrl.get_signal_for(approach_idx, turn_type)
		if aspect == TrafficController.Aspect.RED:
			must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif aspect == TrafficController.Aspect.YELLOW:
			var min_brake_dist := (speed * speed) / (2.0 * comfort_decel * 1.15)
			if dist_to_stop > max(1.0, min_brake_dist * 0.75):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif aspect == TrafficController.Aspect.FLASHING_YELLOW:
			if dist_to_stop < 12.0:
				target_speed = min(target_speed, 5.5)
			if dist_to_stop < 5.0 and _has_conflicting_in_box(all_vehicles):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		elif traffic_ctrl.is_unprotected_left(approach_idx, turn_type):
			if dist_to_stop < 6.0 and _has_oncoming_straight(all_vehicles):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))

	# 2. Car-following & collision avoidance against other vehicles
	var min_gap := 2.0
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		var rel: Vector3 = other_v.position - position
		var dist_sq := rel.length_squared()
		if dist_sq > 625.0:
			continue

		var fwd_dist := rel.dot(forward)
		if fwd_dist <= 0.1:
			continue
		var lat_dist := absf(rel.dot(Vector3(-forward.z, 0.0, forward.x)))

		var dir_dot: float = forward.dot(other_v.forward)
		if dir_dot > 0.65 and lat_dist < 1.85:
			var gap: float = fwd_dist - (vehicle_length * 0.5 + other_v.vehicle_length * 0.5) - min_gap
			if gap < must_stop_dist:
				must_stop_dist = gap
				if gap < 6.0:
					target_speed = min(target_speed, other_v.speed)
		elif dir_dot <= 0.65 and lat_dist < 2.6 and fwd_dist < 10.5:
			var gap: float = fwd_dist - (vehicle_length * 0.5 + 1.8) - 1.2
			if gap < must_stop_dist:
				must_stop_dist = gap

	# 3. Compute acceleration from target_speed and stopping distance
	var desired_speed := target_speed
	if must_stop_dist < 18.0:
		if must_stop_dist <= 0.15:
			desired_speed = 0.0
		else:
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

	progress += speed * delta
	if not has_passed_intersection and progress >= exit_box_progress:
		has_passed_intersection = true

	is_waiting = (speed < 0.6 and not has_passed_intersection)
	if is_waiting:
		wait_time += delta

	_update_lights(delta, braking)

	if progress >= total_length:
		finished = true
		return

	_apply_transform_at(progress)

func _has_conflicting_in_box(all_vehicles: Array) -> bool:
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		if other_v.approach_idx == approach_idx:
			continue
		if other_v.progress >= other_v.stop_progress - 0.5 and other_v.progress <= other_v.exit_box_progress:
			return true
	return false

func _has_oncoming_straight(all_vehicles: Array) -> bool:
	var opp := 1 if approach_idx == 0 else (0 if approach_idx == 1 else (3 if approach_idx == 2 else 2))
	for other in all_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		if other_v.approach_idx == opp and other_v.turn_type != TrafficController.TurnType.LEFT:
			var d_stop: float = other_v.stop_progress - other_v.progress
			if other_v.progress <= other_v.exit_box_progress and d_stop < 15.0 and other_v.speed > 1.5:
				return true
	return false

func _update_lights(delta: float, braking: bool) -> void:
	if braking != _brake_lit:
		_brake_lit = braking
		var m := _brake_on_mat if braking else _brake_off_mat
		for mesh_node in _brake_meshes:
			mesh_node.material_override = m

	_blink_accum += delta
	if is_emergency and _siren_red_mesh != null and _siren_blue_mesh != null:
		var sp := fmod(_blink_accum, 0.36) < 0.18
		if sp != _siren_phase:
			_siren_phase = sp
			_siren_red_mesh.material_override = _siren_red_on if sp else _siren_red_off
			_siren_blue_mesh.material_override = _siren_blue_off if sp else _siren_blue_on

	if turn_type != TrafficController.TurnType.STRAIGHT and not _turn_meshes.is_empty():
		var near_turn := (progress > stop_progress - 18.0 and progress < exit_box_progress + 2.0)
		var lit := near_turn and fmod(_blink_accum, 0.7) < 0.35
		if lit != _turn_lit:
			_turn_lit = lit
			var tm := _turn_on_mat if lit else _turn_off_mat
			for mesh_node in _turn_meshes:
				mesh_node.material_override = tm
