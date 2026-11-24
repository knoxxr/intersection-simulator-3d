extends Node3D
class_name IntersectionMain

@onready var road_builder: RoadBuilder = $RoadBuilder
@onready var traffic_ctrl: TrafficController = $TrafficController
@onready var spawner: VehicleSpawner = $VehicleSpawner
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var ui_ctrl: Control = $UILayer/UIController

var paused: bool = false
var sim_speed: float = 1.0
var elapsed_sim_time: float = 0.0

# Real-time telemetry metrics
var total_passed: int = 0
var total_wait_accum: float = 0.0
var recent_pass_timestamps: Array[float] = []
var _sample_accum: float = 0.0

signal metrics_sampled(waiting_cnt: float, throughput_pm: float)

func _ready() -> void:
	randomize()
	spawner.vehicle_passed.connect(_on_vehicle_passed)
	_rebuild_world()
	ui_ctrl.bind_simulation(self)

func _physics_process(delta: float) -> void:
	if paused:
		return
	var dt := delta * sim_speed
	elapsed_sim_time += dt

	# Feed real-time queue & emergency vehicle telemetry to TrafficController & RoadBuilder
	var dir_waits := spawner.get_waiting_counts_by_dir()
	var emerg_app := spawner.get_active_emergency_approach()
	traffic_ctrl.set_live_inputs(dir_waits, emerg_app)
	road_builder.update_congestion(dir_waits)

	traffic_ctrl.step_simulation(dt)
	spawner.step_simulation(dt, traffic_ctrl)

	while not recent_pass_timestamps.is_empty() and (elapsed_sim_time - recent_pass_timestamps[0]) > 60.0:
		recent_pass_timestamps.pop_front()

	# Push graph sample every 1.0 simulated second
	_sample_accum += dt
	if _sample_accum >= 1.0:
		_sample_accum = 0.0
		var m := get_metrics()
		metrics_sampled.emit(float(m["waiting"]), float(m["throughput"]))

func _on_vehicle_passed(wait_time: float) -> void:
	total_passed += 1
	total_wait_accum += wait_time
	recent_pass_timestamps.append(elapsed_sim_time)

func _rebuild_world() -> void:
	road_builder.rebuild(spawner.ns_lanes, spawner.ew_lanes, spawner.lane_enabled, spawner.approach_enabled)
	traffic_ctrl.reposition_lights(
		spawner.ns_lanes * RoadBuilder.LANE_WIDTH,
		spawner.ew_lanes * RoadBuilder.LANE_WIDTH
	)

# Public API invoked in real-time by UIController
func set_ns_lanes(count: int) -> void:
	var c := clampi(count, 1, 3)
	if spawner.ns_lanes == c:
		return
	spawner.ns_lanes = c
	_rebuild_world()

func set_ew_lanes(count: int) -> void:
	var c := clampi(count, 1, 3)
	if spawner.ew_lanes == c:
		return
	spawner.ew_lanes = c
	_rebuild_world()

func set_lane_enabled(lane_idx: int, enabled: bool) -> void:
	if lane_idx >= 0 and lane_idx < spawner.lane_enabled.size():
		spawner.lane_enabled[lane_idx] = enabled
		_rebuild_world()

func set_approach_enabled(approach_idx: int, enabled: bool) -> void:
	if approach_idx >= 0 and approach_idx < spawner.approach_enabled.size():
		spawner.approach_enabled[approach_idx] = enabled
		_rebuild_world()

func set_time_of_day(mode: RoadBuilder.TimeOfDay) -> void:
	road_builder.set_time_of_day(mode)

func set_congestion_overlay(enabled: bool) -> void:
	road_builder.congestion_overlay_enabled = enabled
	road_builder.update_congestion(spawner.get_waiting_counts_by_dir())

func dispatch_ambulance() -> void:
	spawner.spawn_ambulance(-1)

func apply_preset(preset_id: String) -> void:
	match preset_id:
		"normal":
			spawner.ns_lanes = 2
			spawner.ew_lanes = 2
			spawner.lane_enabled = [true, true, true]
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.0
			spawner.dir_traffic_mult = [1.0, 1.0, 1.0, 1.0]
			spawner.left_turn_ratio = 0.22
			spawner.right_turn_ratio = 0.20
			traffic_ctrl.ns_green_duration = 8.0
			traffic_ctrl.ew_green_duration = 8.0
			traffic_ctrl.set_mode(TrafficController.SignalMode.TWO_PHASE)
		"rush_hour":
			spawner.ns_lanes = 3
			spawner.ew_lanes = 2
			spawner.lane_enabled = [true, true, true]
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.8
			spawner.dir_traffic_mult = [1.9, 1.8, 0.7, 0.7]
			spawner.left_turn_ratio = 0.20
			spawner.right_turn_ratio = 0.18
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
		"left_jam":
			spawner.ns_lanes = 3
			spawner.ew_lanes = 3
			spawner.lane_enabled = [true, true, true]
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.5
			spawner.dir_traffic_mult = [1.2, 1.2, 1.1, 1.1]
			spawner.left_turn_ratio = 0.46
			spawner.right_turn_ratio = 0.14
			traffic_ctrl.left_green_duration = 6.5
			traffic_ctrl.set_mode(TrafficController.SignalMode.FOUR_PHASE)
		"construction":
			spawner.ns_lanes = 3
			spawner.ew_lanes = 2
			spawner.lane_enabled = [false, true, true] # Close inner lane with cones!
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.5
			spawner.dir_traffic_mult = [1.4, 1.3, 1.0, 1.0]
			spawner.left_turn_ratio = 0.18
			spawner.right_turn_ratio = 0.22
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
	_rebuild_world()

func reset_simulation() -> void:
	spawner.clear_all_vehicles()
	total_passed = 0
	total_wait_accum = 0.0
	elapsed_sim_time = 0.0
	_sample_accum = 0.0
	recent_pass_timestamps.clear()

func get_metrics() -> Dictionary:
	var active_cnt := spawner.active_vehicles.size()
	var waiting_cnt := 0
	for v in spawner.active_vehicles:
		if is_instance_valid(v) and v.is_waiting:
			waiting_cnt += 1
	var avg_wait := 0.0 if total_passed == 0 else (total_wait_accum / float(total_passed))
	var window_sec: float = min(60.0, max(5.0, elapsed_sim_time))
	var throughput_per_min := (float(recent_pass_timestamps.size()) / window_sec) * 60.0
	return {
		"active": active_cnt,
		"waiting": waiting_cnt,
		"passed": total_passed,
		"avg_wait": avg_wait,
		"throughput": throughput_per_min,
		"phase": traffic_ctrl.get_phase_label(),
		"phase_time": traffic_ctrl.get_time_remaining(),
		"emergency": traffic_ctrl.is_emergency_active()
	}
