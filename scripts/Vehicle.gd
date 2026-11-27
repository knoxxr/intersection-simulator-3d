extends Node3D
class_name SimVehicle

enum VehicleKind { SEDAN, SUV, TRUCK, TAXI, AMBULANCE }

# Static shared materials & pre-baked vehicle meshes (eliminates per-car GPU VBO allocation & draw-call overflow!)
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
static var _body_mat_cache: Dictionary = {}
static var _baked_mesh_cache: Dictionary = {} # String key -> ArrayMesh
static var _shared_brake_mesh: BoxMesh
static var _shared_siren_mesh: BoxMesh

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

	_shared_brake_mesh = BoxMesh.new()
	_shared_brake_mesh.size = Vector3(1.50, 0.18, 0.08)

	_shared_siren_mesh = BoxMesh.new()
	_shared_siren_mesh.size = Vector3(0.55, 0.24, 0.32)

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

static func _get_baked_vehicle_mesh(vkind: VehicleKind, body_color: Color, vlen: float) -> ArrayMesh:
	var key := "%d_%d" % [int(vkind), body_color.to_rgba32()]
	if _baked_mesh_cache.has(key):
		return _baked_mesh_cache[key]

	var batch := MeshBatch.new()
	var body_mat := _get_body_mat(body_color)
	var w := 1.85
	var h := 0.72
	var l := vlen

	if vkind == VehicleKind.TRUCK:
		w = 2.15
		batch.add_box(Vector3(0, 1.25, -l * 0.5 + 0.95), Vector3(w * 0.94, 1.85, 1.8), body_mat)
		batch.add_box(Vector3(0, 1.55, -l * 0.5 + 0.02), Vector3(w * 0.84, 0.72, 0.12), _glass_mat)
		batch.add_box(Vector3(0, 1.55, 0.98), Vector3(w, 2.35, l - 2.15), _cargo_mat)
	elif vkind == VehicleKind.AMBULANCE:
		w = 2.08
		var amb_white := _get_body_mat(Color(0.96, 0.97, 0.99))
		batch.add_box(Vector3(0, 1.12, 0), Vector3(w, 1.55, l), amb_white)
		batch.add_box(Vector3(0, 0.95, 0.35), Vector3(w + 0.08, 0.24, l * 0.72), _amb_stripe_mat)
		batch.add_box(Vector3(0, 1.94, 0.45), Vector3(0.95, 0.06, 0.28), _amb_stripe_mat)
		batch.add_box(Vector3(0, 1.94, 0.45), Vector3(0.28, 0.06, 0.95), _amb_stripe_mat)
		batch.add_box(Vector3(0, 1.48, -l * 0.5 - 0.02), Vector3(w * 0.86, 0.58, 0.10), _glass_mat)
	else:
		if vkind == VehicleKind.SUV:
			w = 1.96
			h = 0.82
		batch.add_box(Vector3(0, 0.34 + h * 0.5, 0), Vector3(w, h, l), body_mat)
		var cab_len := l * (0.60 if vkind == VehicleKind.SUV else 0.48)
		var glass_h := 0.48 if vkind == VehicleKind.SUV else 0.42
		var roof_h := 0.16
		var cab_z := 0.22 if vkind == VehicleKind.SEDAN or vkind == VehicleKind.TAXI else 0.10
		var chassis_top := 0.34 + h
		batch.add_box(Vector3(0, chassis_top + glass_h * 0.5, cab_z), Vector3(w * 0.84, glass_h, cab_len * 0.94), _glass_mat)
		batch.add_box(Vector3(0, chassis_top + glass_h + roof_h * 0.5, cab_z), Vector3(w * 0.88, roof_h, cab_len), body_mat)
		if vkind == VehicleKind.TAXI:
			batch.add_box(Vector3(0, chassis_top + glass_h + roof_h + 0.12, 0.10), Vector3(0.65, 0.22, 0.28), _taxi_sign_mat)

	# 4 Wheels baked directly into the same vehicle mesh!
	var wheel_z := l * 0.31
	var wheel_x := w * 0.48
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			batch.add_cylinder(Vector3(float(sx) * wheel_x, 0.34, float(sz) * wheel_z), 0.34, 0.24, _wheel_mat, Vector3(0, 0, 90))

	# Headlights baked directly into the same vehicle mesh!
	for sx in [-1.0, 1.0]:
		batch.add_box(Vector3(float(sx) * (w * 0.34), 0.64, -l * 0.5 - 0.05), Vector3(0.32, 0.18, 0.08), _head_mat)

	var baked := batch.commit_multi_surface()
	_baked_mesh_cache[key] = baked
	return baked

var approach_idx: int = 0       # 0=N, 1=S, 2=E, 3=W
var lane_idx: int = 0
var turn_type: int = 0          # TrafficController.TurnType
var kind: VehicleKind = VehicleKind.SEDAN
var is_emergency: bool = false
var is_roundabout: bool = false
var ring_radius: float = 0.0
var yield_world_pos: Vector3 = Vector3.ZERO

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
var stuck_timer: float = 0.0
var has_passed_intersection: bool = false
var finished: bool = false

var _brake_mesh_node: MeshInstance3D
var _siren_red_mesh: MeshInstance3D
var _siren_blue_mesh: MeshInstance3D
var _brake_lit: bool = false
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
	p_color: Color,
	p_is_roundabout: bool = false,
	p_ring_radius: float = 0.0
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
	is_roundabout = p_is_roundabout
	ring_radius = p_ring_radius

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
	var stop_sample := _sample_pos_and_dir(stop_progress)
	yield_world_pos = stop_sample[0]
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
	# 1. Single shared pre-baked multi-surface MeshInstance3D for the entire vehicle body
	var body_node := MeshInstance3D.new()
	body_node.mesh = _get_baked_vehicle_mesh(kind, body_color, vehicle_length)
	add_child(body_node)

	# 2. Single lightweight shared rear brake bar (no shadow casting)
	_brake_mesh_node = MeshInstance3D.new()
	_brake_mesh_node.mesh = _shared_brake_mesh
	_brake_mesh_node.material_override = _brake_off_mat
	_brake_mesh_node.position = Vector3(0, 0.66, vehicle_length * 0.5 + 0.05)
	_brake_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_brake_mesh_node)

	# 3. Ambulance roof strobe beacons only on emergency vehicles
	if is_emergency:
		_siren_red_mesh = MeshInstance3D.new()
		_siren_red_mesh.mesh = _shared_siren_mesh
		_siren_red_mesh.material_override = _siren_red_on
		_siren_red_mesh.position = Vector3(-0.34, 2.04, -vehicle_length * 0.24)
		_siren_red_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_siren_red_mesh)

		_siren_blue_mesh = MeshInstance3D.new()
		_siren_blue_mesh.mesh = _shared_siren_mesh
		_siren_blue_mesh.material_override = _siren_blue_off
		_siren_blue_mesh.position = Vector3(0.34, 2.04, -vehicle_length * 0.24)
		_siren_blue_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_siren_blue_mesh)

func step_vehicle(delta: float, traffic_ctrl: TrafficController, nearby_vehicles: Array, in_box_vehicles: Array) -> void:
	if finished:
		return

	var target_speed := max_speed
	var inside_intersection := (progress >= stop_progress - 2.0 and progress <= exit_box_progress)
	if is_roundabout and inside_intersection:
		target_speed = min(target_speed, 13.0 if is_emergency else 10.5)
	elif inside_intersection and turn_type != TrafficController.TurnType.STRAIGHT:
		target_speed = min(target_speed, 7.6)

	var must_stop_dist := 9999.0

	# Track deadlock ONLY if stalled while already inside the intersection/roundabout box
	var in_box_now := (progress >= stop_progress - 0.5 and progress <= exit_box_progress + 2.0)
	if in_box_now and speed < 0.45:
		stuck_timer += delta
	elif speed > 1.2 or not in_box_now:
		stuck_timer = 0.0
	var clearing_deadlock := (stuck_timer > 1.8)

	# 1. Traffic signal OR Roundabout yield-on-entry check (only before crossing stop/yield line)
	var dist_to_stop := stop_progress - (progress + vehicle_length * 0.52)
	if dist_to_stop > -0.8 and progress < stop_progress:
		if is_roundabout:
			if dist_to_stop < 13.0:
				target_speed = min(target_speed, 9.5 if is_emergency else 7.6)
			if dist_to_stop < 9.5 and _has_roundabout_conflict(in_box_vehicles):
				must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
		else:
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
				if dist_to_stop < 5.0 and _has_conflicting_in_box(in_box_vehicles):
					must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))
			elif traffic_ctrl.is_unprotected_left(approach_idx, turn_type):
				if dist_to_stop < 6.0 and _has_oncoming_straight(in_box_vehicles):
					must_stop_dist = min(must_stop_dist, max(0.0, dist_to_stop))

	# 2. Spatial-grid car-following & asymmetric crossing priority (prevents mutual deadlocks!)
	var min_gap := 2.1
	var follow_lat := 2.35 if (is_roundabout or inside_intersection) else 1.85
	var follow_dot := 0.45 if (is_roundabout or inside_intersection) else 0.65

	for other in nearby_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		var rel: Vector3 = other_v.position - position
		rel.y = 0.0
		var dist_sq := rel.length_squared()
		if dist_sq > 576.0:
			continue

		var fwd_dist := rel.dot(forward)
		if fwd_dist <= 0.1:
			continue
		var lat_dist := absf(rel.dot(Vector3(-forward.z, 0.0, forward.x)))
		var dir_dot: float = forward.dot(other_v.forward)

		if dir_dot > follow_dot and lat_dist < follow_lat:
			# Same-direction car-following (including curved roundabout arcs)
			# Break rare angled or full-ring lockups inside the intersection box
			if clearing_deadlock and other_v.speed < 0.5:
				if dir_dot < 0.85:
					continue
				if stuck_timer > 2.6 and other_v.stuck_timer > 1.8 and (exit_box_progress - progress) < (other_v.exit_box_progress - other_v.progress):
					continue
			var gap: float = fwd_dist - (vehicle_length * 0.5 + other_v.vehicle_length * 0.5) - min_gap
			if gap < must_stop_dist:
				must_stop_dist = gap
				if gap < 7.0:
					target_speed = min(target_speed, other_v.speed)
		elif dir_dot <= follow_dot and lat_dist < 2.6 and fwd_dist < 10.0:
			# Crossing / merging vehicle conflict — apply ASYMMETRIC priority so BOTH cars never deadlock!
			if clearing_deadlock:
				continue
			if _should_yield_to_crossing(other_v, rel):
				var gap: float = fwd_dist - (vehicle_length * 0.5 + 1.9) - 1.2
				if gap < must_stop_dist:
					must_stop_dist = gap

	# 3. Smooth acceleration / braking
	var desired_speed := target_speed
	if clearing_deadlock:
		desired_speed = min(desired_speed, 5.2)
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

func _should_yield_to_crossing(other_v: SimVehicle, rel: Vector3) -> bool:
	# Emergency vehicles take priority
	if is_emergency and not other_v.is_emergency:
		return false
	if other_v.is_emergency and not is_emergency:
		return true

	# If the other car is moving swiftly across our nose while we are slower, yield to it
	if other_v.speed > 2.5 and speed < 1.5:
		return true

	# Check if we are ALSO in front of the other car (potential mutual deadlock!)
	var other_sees_us_ahead := (-rel).dot(other_v.forward) > 0.1
	if not other_sees_us_ahead:
		# Other car's rear/side is right in front of us -> we must yield cleanly
		return true

	# Both cars see each other ahead -> strict deterministic priority so ONLY ONE yields!
	var my_in := progress >= stop_progress
	var other_in := other_v.progress >= other_v.stop_progress
	if my_in and not other_in:
		return false # Already circulating/inside has priority over entering
	if other_in and not my_in:
		return true

	# Whoever is closer to exiting clears the intersection first
	var my_rem := exit_box_progress - progress
	var other_rem := other_v.exit_box_progress - other_v.progress
	if absf(my_rem - other_rem) > 1.5:
		return my_rem > other_rem

	# Final deterministic tie-breaker by instance ID (impossible for both to return true!)
	return get_instance_id() < other_v.get_instance_id()

func _has_roundabout_conflict(in_box_vehicles: Array) -> bool:
	for other in in_box_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		# Only yield to vehicles already circulating inside the roundabout ring
		if other_v.progress < other_v.stop_progress - 0.5 or other_v.progress > other_v.exit_box_progress:
			continue
		if other_v.approach_idx == approach_idx and other_v.lane_idx == lane_idx:
			continue
		var to_entry := yield_world_pos - other_v.position
		to_entry.y = 0.0
		var dist := to_entry.length()
		if dist > 17.5:
			continue
		# Must yield to circulating cars in our target ring lane AND any outer ring lane we have to cross!
		if other_v.ring_radius < ring_radius - 3.6 and dist > 6.5:
			continue
		if dist < 6.0:
			return true
		if other_v.forward.dot(to_entry / dist) > 0.28:
			return true
	return false

func _has_conflicting_in_box(in_box_vehicles: Array) -> bool:
	for other in in_box_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		if other_v.approach_idx == approach_idx:
			continue
		if other_v.progress >= other_v.stop_progress - 0.5:
			return true
	return false

func _has_oncoming_straight(in_box_vehicles: Array) -> bool:
	var opp := 1 if approach_idx == 0 else (0 if approach_idx == 1 else (3 if approach_idx == 2 else 2))
	for other in in_box_vehicles:
		if other == self or other.finished:
			continue
		var other_v: SimVehicle = other
		if other_v.approach_idx == opp and other_v.turn_type != TrafficController.TurnType.LEFT:
			if other_v.speed > 1.5:
				return true
	return false

func _update_lights(delta: float, braking: bool) -> void:
	if braking != _brake_lit and _brake_mesh_node != null:
		_brake_lit = braking
		_brake_mesh_node.material_override = _brake_on_mat if braking else _brake_off_mat

	if is_emergency and _siren_red_mesh != null and _siren_blue_mesh != null:
		_blink_accum += delta
		var sp := fmod(_blink_accum, 0.36) < 0.18
		if sp != _siren_phase:
			_siren_phase = sp
			_siren_red_mesh.material_override = _siren_red_on if sp else _siren_red_off
			_siren_blue_mesh.material_override = _siren_blue_off if sp else _siren_blue_on
