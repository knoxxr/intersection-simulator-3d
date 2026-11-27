extends Node3D
class_name IntersectionMain

@onready var road_builder: RoadBuilder = $RoadBuilder
@onready var traffic_ctrl: TrafficController = $TrafficController
@onready var spawner: VehicleSpawner = $VehicleSpawner
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var ui_ctrl: Control = $UILayer/UIController

var intersection_type: RoadBuilder.IntersectionType = RoadBuilder.IntersectionType.SIGNALIZED
var paused: bool = false
var sim_speed: float = 1.0
var elapsed_sim_time: float = 0.0

# Real-time telemetry & analytics
var total_passed: int = 0
var total_wait_accum: float = 0.0
var recent_records: Array[Dictionary] = [] # rolling 60s vehicle pass records
var dir_max_queue: Array[int] = [0, 0, 0, 0]
var snapshots: Array[Dictionary] = []      # saved A/B comparison snapshots (max 4)
var csv_log: Array[Dictionary] = []        # 1Hz time-series log (max 600s)
var _sample_accum: float = 0.0

signal metrics_sampled(waiting_cnt: float, throughput_pm: float)

func _ready() -> void:
	randomize()
	spawner.vehicle_passed.connect(_on_vehicle_passed)
	_rebuild_world()
	ui_ctrl.bind_simulation(self)

func _process(delta: float) -> void:
	if paused:
		return
	var total_dt := minf(delta, 0.05) * sim_speed
	# Sub-step when running at high speed (2x/4x) so steering & IDM physics stay rock-solid
	var steps := maxi(1, int(ceilf(total_dt / 0.025)))
	var dt := total_dt / float(steps)

	for _s in range(steps):
		elapsed_sim_time += dt
		var dir_waits := spawner.get_waiting_counts_by_dir()
		for d in range(4):
			if dir_waits[d] > dir_max_queue[d]:
				dir_max_queue[d] = dir_waits[d]
		var emerg_app := spawner.get_active_emergency_approach()
		traffic_ctrl.set_live_inputs(dir_waits, emerg_app)
		if _s == steps - 1:
			road_builder.update_congestion(dir_waits)

		traffic_ctrl.step_simulation(dt)
		spawner.step_simulation(dt, traffic_ctrl)

	while not recent_records.is_empty() and (elapsed_sim_time - float(recent_records[0]["t"])) > 60.0:
		recent_records.pop_front()

	_sample_accum += total_dt
	if _sample_accum >= 1.0:
		_sample_accum = 0.0
		var m := get_metrics()
		metrics_sampled.emit(float(m["waiting"]), float(m["throughput"]))
		var dw: Array = m["dir_waits"]
		csv_log.append({
			"t": elapsed_sim_time,
			"tp": m["throughput"],
			"wait": m["waiting"],
			"avg60": m["avg_wait_60s"],
			"p95": m["p95_wait"],
			"los": m["los"],
			"nonstop": m["nonstop_pct"],
			"kmh": m["avg_speed_kmh"],
			"wn": dw[0], "ws": dw[1], "we": dw[2], "ww": dw[3]
		})
		if csv_log.size() > 600:
			csv_log.pop_front()

func _on_vehicle_passed(info: Dictionary) -> void:
	total_passed += 1
	var w: float = float(info.get("wait", 0.0))
	total_wait_accum += w
	var rec := info.duplicate()
	rec["t"] = elapsed_sim_time
	recent_records.append(rec)

func _rebuild_world() -> void:
	var is_rotary := (intersection_type == RoadBuilder.IntersectionType.ROUNDABOUT)
	var is_under := (intersection_type == RoadBuilder.IntersectionType.UNDERPASS)
	var is_over := (intersection_type == RoadBuilder.IntersectionType.OVERPASS)
	var is_tri := (intersection_type == RoadBuilder.IntersectionType.TRI_LEVEL)
	spawner.is_roundabout = is_rotary
	spawner.is_underpass = is_under
	spawner.is_overpass = is_over
	spawner.is_tri_level = is_tri
	traffic_ctrl.set_roundabout_mode(is_rotary)
	var grade_sep_only := false
	var grade_label_key := "ph_underpass_free"
	var light_ns_half := spawner.ns_lanes * RoadBuilder.LANE_WIDTH
	var light_ew_half := spawner.ew_lanes * RoadBuilder.LANE_WIDTH
	var ns_arm_override := -1.0
	var ew_arm_override := -1.0
	if is_under or is_over:
		var lay := RoadBuilder.get_underpass_layout(spawner.ns_lanes, spawner.ew_lanes)
		grade_sep_only = (int(lay["s_lanes"]) == 0)
		grade_label_key = "ph_overpass_free" if is_over else "ph_underpass_free"
		light_ns_half = float(lay["total_ns_half"])
		if is_over and float(lay["surf_w"]) > 0.1:
			ns_arm_override = float(lay["surf_w"]) * 0.7
	elif is_tri:
		var lay := RoadBuilder.get_tri_level_layout(spawner.ns_lanes, spawner.ew_lanes)
		grade_sep_only = (int(lay["ns_s"]) == 0 or int(lay["ew_s"]) == 0)
		grade_label_key = "ph_tri_level_free"
		light_ns_half = float(lay["total_ns_half"])
		light_ew_half = float(lay["total_ew_half"])
		if float(lay["ns_surf_w"]) > 0.1:
			ns_arm_override = float(lay["ns_surf_w"]) * 0.7
		if float(lay["ew_surf_w"]) > 0.1:
			ew_arm_override = float(lay["ew_surf_w"]) * 0.7
	traffic_ctrl.set_grade_separated_only(grade_sep_only, grade_label_key)
	road_builder.rebuild(
		spawner.ns_lanes,
		spawner.ew_lanes,
		spawner.lane_enabled,
		spawner.approach_enabled,
		intersection_type
	)
	traffic_ctrl.reposition_lights(light_ns_half, light_ew_half, ns_arm_override, ew_arm_override)

func set_intersection_type(new_type: RoadBuilder.IntersectionType) -> void:
	if intersection_type == new_type:
		return
	intersection_type = new_type
	# Clear vehicles currently on incompatible geometry so none clip the roundabout island or grade-separated walls
	spawner.clear_all_vehicles()
	_rebuild_world()

func set_ns_lanes(count: int) -> void:
	var c := clampi(count, 1, 10)
	if spawner.ns_lanes == c:
		return
	spawner.ns_lanes = c
	if intersection_type != RoadBuilder.IntersectionType.SIGNALIZED and intersection_type != RoadBuilder.IntersectionType.ROUNDABOUT:
		spawner.clear_all_vehicles()
	_rebuild_world()

func set_ew_lanes(count: int) -> void:
	var c := clampi(count, 1, 10)
	if spawner.ew_lanes == c:
		return
	spawner.ew_lanes = c
	if intersection_type != RoadBuilder.IntersectionType.SIGNALIZED and intersection_type != RoadBuilder.IntersectionType.ROUNDABOUT:
		spawner.clear_all_vehicles()
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

func _reset_open_lanes() -> void:
	for i in range(spawner.lane_enabled.size()):
		spawner.lane_enabled[i] = true

func apply_preset(preset_id: String) -> void:
	var prev_type := intersection_type
	_reset_open_lanes()
	match preset_id:
		"normal":
			intersection_type = RoadBuilder.IntersectionType.SIGNALIZED
			spawner.ns_lanes = 2
			spawner.ew_lanes = 2
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.0
			spawner.dir_traffic_mult = [1.0, 1.0, 1.0, 1.0]
			spawner.left_turn_ratio = 0.22
			spawner.right_turn_ratio = 0.20
			traffic_ctrl.ns_green_duration = 8.0
			traffic_ctrl.ew_green_duration = 8.0
			traffic_ctrl.set_mode(TrafficController.SignalMode.TWO_PHASE)
		"rush_hour":
			intersection_type = RoadBuilder.IntersectionType.SIGNALIZED
			spawner.ns_lanes = 4
			spawner.ew_lanes = 2
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.8
			spawner.dir_traffic_mult = [1.9, 1.8, 0.7, 0.7]
			spawner.left_turn_ratio = 0.20
			spawner.right_turn_ratio = 0.18
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
		"left_jam":
			intersection_type = RoadBuilder.IntersectionType.SIGNALIZED
			spawner.ns_lanes = 3
			spawner.ew_lanes = 3
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.5
			spawner.dir_traffic_mult = [1.2, 1.2, 1.1, 1.1]
			spawner.left_turn_ratio = 0.46
			spawner.right_turn_ratio = 0.14
			traffic_ctrl.left_green_duration = 6.5
			traffic_ctrl.set_mode(TrafficController.SignalMode.FOUR_PHASE)
		"construction":
			intersection_type = RoadBuilder.IntersectionType.SIGNALIZED
			spawner.ns_lanes = 3
			spawner.ew_lanes = 2
			spawner.lane_enabled[0] = false
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.5
			spawner.dir_traffic_mult = [1.4, 1.3, 1.0, 1.0]
			spawner.left_turn_ratio = 0.18
			spawner.right_turn_ratio = 0.22
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
		"roundabout":
			intersection_type = RoadBuilder.IntersectionType.ROUNDABOUT
			spawner.ns_lanes = 2
			spawner.ew_lanes = 2
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.2
			spawner.dir_traffic_mult = [1.0, 1.0, 1.0, 1.0]
			spawner.left_turn_ratio = 0.28
			spawner.right_turn_ratio = 0.24
			orbit_camera.set_preset_iso()
		"underpass":
			intersection_type = RoadBuilder.IntersectionType.UNDERPASS
			spawner.ns_lanes = 4
			spawner.ew_lanes = 2
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.8
			spawner.dir_traffic_mult = [1.7, 1.7, 1.0, 1.0]
			spawner.left_turn_ratio = 0.18
			spawner.right_turn_ratio = 0.18
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
			orbit_camera.set_preset_iso()
		"overpass":
			intersection_type = RoadBuilder.IntersectionType.OVERPASS
			spawner.ns_lanes = 4
			spawner.ew_lanes = 2
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 1.8
			spawner.dir_traffic_mult = [1.7, 1.7, 1.0, 1.0]
			spawner.left_turn_ratio = 0.18
			spawner.right_turn_ratio = 0.18
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
			orbit_camera.set_preset_iso()
		"tri_level":
			intersection_type = RoadBuilder.IntersectionType.TRI_LEVEL
			spawner.ns_lanes = 4
			spawner.ew_lanes = 4
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 2.0
			spawner.dir_traffic_mult = [1.5, 1.5, 1.5, 1.5]
			spawner.left_turn_ratio = 0.18
			spawner.right_turn_ratio = 0.18
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
			orbit_camera.set_preset_iso()
		"mega10":
			intersection_type = RoadBuilder.IntersectionType.SIGNALIZED
			spawner.ns_lanes = 10
			spawner.ew_lanes = 6
			spawner.approach_enabled = [true, true, true, true]
			spawner.global_traffic_rate = 2.0
			spawner.dir_traffic_mult = [1.4, 1.4, 1.0, 1.0]
			spawner.left_turn_ratio = 0.22
			spawner.right_turn_ratio = 0.20
			traffic_ctrl.set_mode(TrafficController.SignalMode.SMART_ADAPTIVE)
			orbit_camera.set_preset_wide()

	if prev_type != intersection_type or (intersection_type != RoadBuilder.IntersectionType.SIGNALIZED and intersection_type != RoadBuilder.IntersectionType.ROUNDABOUT):
		spawner.clear_all_vehicles()
	_rebuild_world()

func reset_simulation() -> void:
	spawner.clear_all_vehicles()
	total_passed = 0
	total_wait_accum = 0.0
	elapsed_sim_time = 0.0
	_sample_accum = 0.0
	recent_records.clear()
	dir_max_queue = [0, 0, 0, 0]
	csv_log.clear()

static func compute_los(avg_delay_sec: float) -> String:
	if avg_delay_sec <= 10.0: return "A"
	if avg_delay_sec <= 20.0: return "B"
	if avg_delay_sec <= 35.0: return "C"
	if avg_delay_sec <= 55.0: return "D"
	if avg_delay_sec <= 80.0: return "E"
	return "F"

static func get_los_color(grade: String) -> Color:
	match grade:
		"A": return Color(0.16, 0.88, 0.48)
		"B": return Color(0.48, 0.90, 0.30)
		"C": return Color(0.96, 0.84, 0.22)
		"D": return Color(0.98, 0.60, 0.16)
		"E": return Color(0.96, 0.36, 0.20)
		_:   return Color(0.94, 0.18, 0.24)

func get_config_short_label() -> String:
	var t_name := Lang.t("type_signal")
	match intersection_type:
		RoadBuilder.IntersectionType.ROUNDABOUT: t_name = Lang.t("type_roundabout")
		RoadBuilder.IntersectionType.UNDERPASS:  t_name = Lang.t("type_underpass")
		RoadBuilder.IntersectionType.OVERPASS:   t_name = Lang.t("type_overpass")
		RoadBuilder.IntersectionType.TRI_LEVEL:  t_name = Lang.t("preset_tri_level")
	var sig_tag := ""
	if intersection_type != RoadBuilder.IntersectionType.ROUNDABOUT and not traffic_ctrl.is_grade_separated_only:
		match traffic_ctrl.mode:
			TrafficController.SignalMode.TWO_PHASE:       sig_tag = "·2P"
			TrafficController.SignalMode.FOUR_PHASE:      sig_tag = "·4P"
			TrafficController.SignalMode.SMART_ADAPTIVE:  sig_tag = "·AI"
			TrafficController.SignalMode.FLASHING_YELLOW: sig_tag = "·FL"
			TrafficController.SignalMode.ALL_RED:         sig_tag = "·AR"
	return "%s %d×%d%s" % [t_name, spawner.ns_lanes, spawner.ew_lanes, sig_tag]

func save_snapshot() -> Dictionary:
	var m := get_metrics()
	var snap := {
		"label": get_config_short_label(),
		"throughput": m["throughput"],
		"avg_wait": m["avg_wait_60s"],
		"p95_wait": m["p95_wait"],
		"los": m["los"],
		"nonstop": m["nonstop_pct"],
		"speed_kmh": m["avg_speed_kmh"]
	}
	snapshots.append(snap)
	if snapshots.size() > 4:
		snapshots.remove_at(0)
	return snap

func clear_snapshots() -> void:
	snapshots.clear()

func export_csv_text() -> String:
	var lines := PackedStringArray()
	lines.append("# 3D Intersection Traffic Simulator Report")
	lines.append("# Current Config: %s" % get_config_short_label())
	if not snapshots.is_empty():
		lines.append("")
		lines.append("# A/B Snapshots")
		lines.append("run,config,throughput_pm,avg_wait_60s,p95_wait_s,los,nonstop_pct,avg_speed_kmh")
		for i in range(snapshots.size()):
			var s: Dictionary = snapshots[i]
			lines.append("%d,\"%s\",%.1f,%.2f,%.2f,%s,%.1f,%.1f" % [
				i + 1, str(s["label"]).replace("\"", "'"),
				float(s["throughput"]), float(s["avg_wait"]), float(s["p95_wait"]),
				str(s["los"]), float(s["nonstop"]), float(s["speed_kmh"])
			])
	lines.append("")
	lines.append("# Time-Series (1Hz)")
	lines.append("time_s,throughput_pm,waiting,avg_wait_60s,p95_wait_s,los,nonstop_pct,avg_speed_kmh,wait_N,wait_S,wait_E,wait_W")
	for row in csv_log:
		lines.append("%.1f,%.1f,%d,%.2f,%.2f,%s,%.1f,%.1f,%d,%d,%d,%d" % [
			float(row["t"]), float(row["tp"]), int(row["wait"]),
			float(row["avg60"]), float(row["p95"]), str(row["los"]),
			float(row["nonstop"]), float(row["kmh"]),
			int(row["wn"]), int(row["ws"]), int(row["we"]), int(row["ww"])
		])
	return "\n".join(lines) + "\n"

func download_csv_report() -> void:
	var csv := export_csv_text()
	if OS.has_feature("web"):
		var b64 := Marshalls.utf8_to_base64(csv)
		var js := """
		(function(){
			const bin = atob('%s');
			const bytes = new Uint8Array(bin.length);
			for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
			const blob = new Blob([bytes], {type: 'text/csv;charset=utf-8;'});
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = url;
			a.download = 'traffic_sim_report.csv';
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
			setTimeout(() => URL.revokeObjectURL(url), 1000);
		})();
		""" % b64
		JavaScriptBridge.eval(js)
	else:
		var f := FileAccess.open("user://traffic_sim_report.csv", FileAccess.WRITE)
		if f != null:
			f.store_string(csv)
			f.close()

func get_metrics() -> Dictionary:
	var active_cnt := spawner.active_vehicles.size()
	var dir_waits := spawner.get_waiting_counts_by_dir()
	var waiting_cnt := dir_waits[0] + dir_waits[1] + dir_waits[2] + dir_waits[3]
	var avg_wait := 0.0 if total_passed == 0 else (total_wait_accum / float(total_passed))
	var window_sec: float = min(60.0, max(5.0, elapsed_sim_time))
	var rec_cnt := recent_records.size()
	var throughput_per_min := (float(rec_cnt) / window_sec) * 60.0

	var waits_arr: Array[float] = []
	var sum_w60 := 0.0
	var max_w60 := 0.0
	var sum_kmh := 0.0
	var nonstop_cnt := 0

	var dir_sum_w: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var dir_cnt: Array[int] = [0, 0, 0, 0]
	var turn_sum_w: Array[float] = [0.0, 0.0, 0.0]
	var turn_cnt: Array[int] = [0, 0, 0]
	var lvl_over := 0
	var lvl_surf := 0
	var lvl_under := 0

	for rec in recent_records:
		var w: float = float(rec["wait"])
		waits_arr.append(w)
		sum_w60 += w
		if w > max_w60:
			max_w60 = w
		sum_kmh += float(rec["speed_kmh"])
		if not bool(rec["stopped"]):
			nonstop_cnt += 1

		var app: int = clampi(int(rec["approach"]), 0, 3)
		dir_sum_w[app] += w
		dir_cnt[app] += 1

		var trn: int = clampi(int(rec["turn"]), 0, 2)
		turn_sum_w[trn] += w
		turn_cnt[trn] += 1

		var lv: int = int(rec["level"])
		if lv > 0: lvl_over += 1
		elif lv < 0: lvl_under += 1
		else: lvl_surf += 1

	var avg_wait_60s := avg_wait
	var p95_wait := 0.0
	var avg_speed_kmh := 0.0
	var nonstop_pct := 0.0
	if rec_cnt > 0:
		avg_wait_60s = sum_w60 / float(rec_cnt)
		waits_arr.sort()
		var p95_idx := clampi(int(floor(float(rec_cnt - 1) * 0.95)), 0, rec_cnt - 1)
		p95_wait = waits_arr[p95_idx]
		avg_speed_kmh = sum_kmh / float(rec_cnt)
		nonstop_pct = (float(nonstop_cnt) / float(rec_cnt)) * 100.0

	var dir_avg_wait: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for d in range(4):
		if dir_cnt[d] > 0:
			dir_avg_wait[d] = dir_sum_w[d] / float(dir_cnt[d])

	var turn_avg_wait: Array[float] = [0.0, 0.0, 0.0]
	for t in range(3):
		if turn_cnt[t] > 0:
			turn_avg_wait[t] = turn_sum_w[t] / float(turn_cnt[t])

	var los_grade := compute_los(avg_wait_60s)
	# Estimated idling CO2 (~1.95 kg/h per idling passenger vehicle)
	var idle_co2_kgh := float(waiting_cnt) * 1.95

	return {
		"active": active_cnt,
		"waiting": waiting_cnt,
		"passed": total_passed,
		"avg_wait": avg_wait,
		"avg_wait_60s": avg_wait_60s,
		"p95_wait": p95_wait,
		"max_wait": max_w60,
		"los": los_grade,
		"avg_speed_kmh": avg_speed_kmh,
		"nonstop_pct": nonstop_pct,
		"throughput": throughput_per_min,
		"dir_waits": dir_waits,
		"dir_max_queue": dir_max_queue.duplicate(),
		"dir_avg_wait": dir_avg_wait,
		"turn_avg_wait": turn_avg_wait,
		"turn_counts": turn_cnt,
		"level_counts": {"over": lvl_over, "surf": lvl_surf, "under": lvl_under},
		"idle_co2_kgh": idle_co2_kgh,
		"phase": traffic_ctrl.get_phase_label(),
		"phase_time": traffic_ctrl.get_time_remaining(),
		"emergency": traffic_ctrl.is_emergency_active()
	}
