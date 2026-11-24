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
	traffic_ctrl.step_simulation(dt)
	spawner.step_simulation(dt, traffic_ctrl)

	# Trim rolling 60s throughput window
	while not recent_pass_timestamps.is_empty() and (elapsed_sim_time - recent_pass_timestamps[0]) > 60.0:
		recent_pass_timestamps.pop_front()

func _on_vehicle_passed(wait_time: float) -> void:
	total_passed += 1
	total_wait_accum += wait_time
	recent_pass_timestamps.append(elapsed_sim_time)

func _rebuild_world() -> void:
	road_builder.rebuild(spawner.lane_count, spawner.lane_enabled, spawner.approach_enabled)
	traffic_ctrl.reposition_lights(spawner.lane_count * RoadBuilder.LANE_WIDTH)

# Public API invoked in real-time by UIController
func set_lane_count(count: int) -> void:
	var c := clampi(count, 1, 3)
	if spawner.lane_count == c:
		return
	spawner.lane_count = c
	_rebuild_world()

func set_lane_enabled(lane_idx: int, enabled: bool) -> void:
	if lane_idx >= 0 and lane_idx < spawner.lane_enabled.size():
		spawner.lane_enabled[lane_idx] = enabled
		_rebuild_world()

func set_approach_enabled(approach_idx: int, enabled: bool) -> void:
	if approach_idx >= 0 and approach_idx < spawner.approach_enabled.size():
		spawner.approach_enabled[approach_idx] = enabled
		_rebuild_world()

func reset_simulation() -> void:
	spawner.clear_all_vehicles()
	total_passed = 0
	total_wait_accum = 0.0
	elapsed_sim_time = 0.0
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
		"phase_time": traffic_ctrl.get_time_remaining()
	}
