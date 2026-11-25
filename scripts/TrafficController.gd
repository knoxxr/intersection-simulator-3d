extends Node3D
class_name TrafficController

# Signal operation modes
enum SignalMode {
	TWO_PHASE,        # N-S Green / E-W Green (standard)
	FOUR_PHASE,       # Protected Left Turn phases
	SMART_ADAPTIVE,   # AI/Queue-aware adaptive green extension & early switching
	FLASHING_YELLOW,  # Uncontrolled flashing yellow caution
	ALL_RED           # Emergency all-red stop (gridlock/queue test)
}

enum TurnType { STRAIGHT, LEFT, RIGHT }
enum Aspect { RED, YELLOW, GREEN, FLASHING_YELLOW }

var mode: SignalMode = SignalMode.TWO_PHASE
var ns_green_duration: float = 8.0
var ew_green_duration: float = 8.0
var left_green_duration: float = 5.0
var yellow_duration: float = 2.5
var all_red_duration: float = 1.0

var phase_index: int = 0
var phase_timer: float = 0.0
var phase_elapsed: float = 0.0
var flash_timer: float = 0.0
var flash_on: bool = true

# Smart adaptive, emergency preemption, and roundabout state
var _smart_ns_wait: int = 0
var _smart_ew_wait: int = 0
var _emergency_approach: int = -1 # -1 = none, 0..3 = approaching ambulance
var is_roundabout: bool = false

var lights: Array[TrafficLight] = []

func _ready() -> void:
	_create_lights()
	_reset_phase()

func _create_lights() -> void:
	for child in get_children():
		child.queue_free()
	lights.clear()
	var names := ["TL_North", "TL_South", "TL_East", "TL_West"]
	for n in names:
		var tl := TrafficLight.new()
		tl.name = n
		add_child(tl)
		lights.append(tl)
	reposition_lights(7.0, 7.0)

func set_roundabout_mode(enabled: bool) -> void:
	is_roundabout = enabled
	visible = not enabled

func reposition_lights(ns_half: float, ew_half: float) -> void:
	if lights.size() < 4:
		return
	var off_x := ns_half + 1.5
	var off_z := ew_half + 1.5
	lights[0].position = Vector3(-off_x, 0, off_z)
	lights[0].rotation_degrees = Vector3(0, 0, 0)
	lights[0].set_arm_reach(ns_half)

	lights[1].position = Vector3(off_x, 0, -off_z)
	lights[1].rotation_degrees = Vector3(0, 180, 0)
	lights[1].set_arm_reach(ns_half)

	lights[2].position = Vector3(-off_x, 0, -off_z)
	lights[2].rotation_degrees = Vector3(0, -90, 0)
	lights[2].set_arm_reach(ew_half)

	lights[3].position = Vector3(off_x, 0, off_z)
	lights[3].rotation_degrees = Vector3(0, 90, 0)
	lights[3].set_arm_reach(ew_half)

func set_mode(new_mode: SignalMode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	_reset_phase()

func _reset_phase() -> void:
	phase_index = 0
	phase_elapsed = 0.0
	phase_timer = _get_phase_duration(phase_index)
	_update_light_visuals()

func force_next_phase() -> void:
	if mode == SignalMode.FLASHING_YELLOW or mode == SignalMode.ALL_RED:
		return
	var total := 12 if mode == SignalMode.FOUR_PHASE else 6
	phase_index = (phase_index + 1) % total
	phase_elapsed = 0.0
	phase_timer = _get_phase_duration(phase_index)
	_update_light_visuals()

func set_live_inputs(dir_wait_counts: Array[int], emergency_approach: int) -> void:
	if dir_wait_counts.size() >= 4:
		_smart_ns_wait = dir_wait_counts[0] + dir_wait_counts[1]
		_smart_ew_wait = dir_wait_counts[2] + dir_wait_counts[3]
	_emergency_approach = emergency_approach

func is_emergency_active() -> bool:
	return _emergency_approach >= 0

func step_simulation(delta: float) -> void:
	# Emergency preemption overrides normal cycle to clear ambulance axis cleanly
	if _emergency_approach >= 0:
		_step_emergency_preemption(delta)
		return

	if mode == SignalMode.ALL_RED:
		_update_light_visuals()
		return

	if mode == SignalMode.FLASHING_YELLOW:
		flash_timer += delta
		if flash_timer >= 0.6:
			flash_timer = 0.0
			flash_on = not flash_on
			_update_light_visuals()
		return

	phase_elapsed += delta

	# SMART_ADAPTIVE uses the 6-step NS/EW cycle with dynamic green duration
	if mode == SignalMode.SMART_ADAPTIVE:
		var is_green := (phase_index == 0 or phase_index == 3)
		if is_green:
			var min_g := 4.0
			var max_g := 18.0
			var cur_wait := _smart_ns_wait if phase_index == 0 else _smart_ew_wait
			var opp_wait := _smart_ew_wait if phase_index == 0 else _smart_ns_wait

			var should_switch := false
			if phase_elapsed >= max_g:
				should_switch = true
			elif phase_elapsed >= min_g:
				# Switch early if opposite direction has waiting cars and active direction is clear or heavily outnumbered
				if opp_wait > 0 and cur_wait == 0:
					should_switch = true
				elif opp_wait >= cur_wait + 4 and phase_elapsed >= 6.0:
					should_switch = true

			phase_timer = max(0.0, max_g - phase_elapsed)
			if should_switch:
				phase_index = (phase_index + 1) % 6
				phase_elapsed = 0.0
				phase_timer = _get_phase_duration(phase_index)
				_update_light_visuals()
			return

	phase_timer -= delta
	if phase_timer <= 0.0:
		var total := 12 if mode == SignalMode.FOUR_PHASE else 6
		phase_index = (phase_index + 1) % total
		phase_elapsed = 0.0
		phase_timer = _get_phase_duration(phase_index)
		_update_light_visuals()

func _step_emergency_preemption(delta: float) -> void:
	# Ensure signal transitions smoothly to give GREEN to _emergency_approach's axis
	var want_ns := (_emergency_approach == 0 or _emergency_approach == 1)
	var target_green := 0 if want_ns else 3
	if mode == SignalMode.FOUR_PHASE:
		target_green = 0 if want_ns else 6

	if phase_index == target_green:
		# Hold green until emergency clears!
		phase_timer = 1.0
		_update_light_visuals()
		return

	# If currently on yellow or all-red clearance, count down rapidly and jump to target_green
	if mode == SignalMode.FLASHING_YELLOW or mode == SignalMode.ALL_RED:
		phase_index = target_green
		phase_timer = 1.0
		_update_light_visuals()
		return

	var is_clearance := false
	if mode == SignalMode.FOUR_PHASE:
		is_clearance = (phase_index in [1, 2, 4, 5, 7, 8, 10, 11])
	else:
		is_clearance = (phase_index in [1, 2, 4, 5])

	if not is_clearance:
		# Start immediate yellow clearance from conflicting green
		phase_index = (phase_index + 1) % (12 if mode == SignalMode.FOUR_PHASE else 6)
		phase_timer = min(1.4, yellow_duration)
		_update_light_visuals()
	else:
		phase_timer -= delta
		if phase_timer <= 0.0:
			# After brief clearance, switch directly to emergency green
			phase_index = target_green
			phase_timer = 1.0
			_update_light_visuals()

func _get_phase_duration(idx: int) -> float:
	if mode == SignalMode.FOUR_PHASE:
		match idx:
			0: return ns_green_duration
			1: return yellow_duration
			2: return all_red_duration
			3: return left_green_duration
			4: return yellow_duration
			5: return all_red_duration
			6: return ew_green_duration
			7: return yellow_duration
			8: return all_red_duration
			9: return left_green_duration
			10: return yellow_duration
			11: return all_red_duration
	else:
		match idx:
			0: return ns_green_duration
			1: return yellow_duration
			2: return all_red_duration
			3: return ew_green_duration
			4: return yellow_duration
			5: return all_red_duration
	return 1.0

func get_signal_for(approach_idx: int, turn_type: int) -> Aspect:
	var is_ns := (approach_idx == 0 or approach_idx == 1)

	# Emergency preemption active
	if _emergency_approach >= 0:
		var want_ns := (_emergency_approach == 0 or _emergency_approach == 1)
		var target_green := (0 if want_ns else 6) if mode == SignalMode.FOUR_PHASE else (0 if want_ns else 3)
		if phase_index == target_green:
			return Aspect.GREEN if (is_ns == want_ns) else Aspect.RED
		# Clearance state before switching
		return Aspect.RED

	if mode == SignalMode.ALL_RED:
		return Aspect.RED
	if mode == SignalMode.FLASHING_YELLOW:
		return Aspect.FLASHING_YELLOW

	if mode == SignalMode.TWO_PHASE or mode == SignalMode.SMART_ADAPTIVE:
		if is_ns:
			if phase_index == 0: return Aspect.GREEN
			if phase_index == 1: return Aspect.YELLOW
			return Aspect.RED
		else:
			if phase_index == 3: return Aspect.GREEN
			if phase_index == 4: return Aspect.YELLOW
			return Aspect.RED

	# FOUR_PHASE
	var is_left := (turn_type == TurnType.LEFT)
	if is_ns:
		if not is_left:
			if phase_index == 0: return Aspect.GREEN
			if phase_index == 1: return Aspect.YELLOW
			return Aspect.RED
		else:
			if phase_index == 3: return Aspect.GREEN
			if phase_index == 4: return Aspect.YELLOW
			return Aspect.RED
	else:
		if not is_left:
			if phase_index == 6: return Aspect.GREEN
			if phase_index == 7: return Aspect.YELLOW
			return Aspect.RED
		else:
			if phase_index == 9: return Aspect.GREEN
			if phase_index == 10: return Aspect.YELLOW
			return Aspect.RED

func is_unprotected_left(approach_idx: int, turn_type: int) -> bool:
	return (mode == SignalMode.TWO_PHASE or mode == SignalMode.SMART_ADAPTIVE) and turn_type == TurnType.LEFT and get_signal_for(approach_idx, turn_type) == Aspect.GREEN

func get_phase_label() -> String:
	if is_roundabout:
		if _emergency_approach >= 0:
			return Lang.t("ph_roundabout_ems")
		return Lang.t("ph_roundabout")

	if _emergency_approach >= 0:
		var dir_str := Lang.t("axis_ns") if (_emergency_approach == 0 or _emergency_approach == 1) else Lang.t("axis_ew")
		return Lang.t("ph_emerg") % dir_str

	match mode:
		SignalMode.ALL_RED:
			return Lang.t("ph_all_red")
		SignalMode.FLASHING_YELLOW:
			return Lang.t("ph_flash")
		SignalMode.SMART_ADAPTIVE:
			match phase_index:
				0: return Lang.t("ph_ai_ns_g") % [_smart_ns_wait, _smart_ew_wait]
				1: return Lang.t("ph_ai_ns_y")
				2: return Lang.t("ph_clear")
				3: return Lang.t("ph_ai_ew_g") % [_smart_ns_wait, _smart_ew_wait]
				4: return Lang.t("ph_ai_ew_y")
				5: return Lang.t("ph_clear")
		SignalMode.TWO_PHASE:
			match phase_index:
				0: return Lang.t("ph_ns_g")
				1: return Lang.t("ph_ns_y")
				2: return Lang.t("ph_clear")
				3: return Lang.t("ph_ew_g")
				4: return Lang.t("ph_ew_y")
				5: return Lang.t("ph_clear")
		SignalMode.FOUR_PHASE:
			match phase_index:
				0: return Lang.t("ph_ns_st_g")
				1: return Lang.t("ph_ns_st_y")
				2: return Lang.t("ph_clear")
				3: return Lang.t("ph_ns_lt_g")
				4: return Lang.t("ph_ns_lt_y")
				5: return Lang.t("ph_clear")
				6: return Lang.t("ph_ew_st_g")
				7: return Lang.t("ph_ew_st_y")
				8: return Lang.t("ph_clear")
				9: return Lang.t("ph_ew_lt_g")
				10: return Lang.t("ph_ew_lt_y")
				11: return Lang.t("ph_clear")
	return "-"

func get_time_remaining() -> float:
	if is_roundabout or _emergency_approach >= 0 or mode == SignalMode.ALL_RED or mode == SignalMode.FLASHING_YELLOW:
		return 0.0
	return max(0.0, phase_timer)

func _update_light_visuals() -> void:
	if lights.size() < 4:
		return

	if _emergency_approach < 0:
		if mode == SignalMode.ALL_RED:
			for tl in lights:
				tl.set_display(TrafficLight.SignalColor.RED, false)
			return
		if mode == SignalMode.FLASHING_YELLOW:
			var col := TrafficLight.SignalColor.YELLOW if flash_on else TrafficLight.SignalColor.OFF
			for tl in lights:
				tl.set_display(col, false)
			return

	for i in range(4):
		var main_asp := get_signal_for(i, TurnType.STRAIGHT)
		var left_asp := get_signal_for(i, TurnType.LEFT)
		var main_col := TrafficLight.SignalColor.RED
		if main_asp == Aspect.GREEN:
			main_col = TrafficLight.SignalColor.GREEN
		elif main_asp == Aspect.YELLOW:
			main_col = TrafficLight.SignalColor.YELLOW
		elif left_asp == Aspect.YELLOW:
			main_col = TrafficLight.SignalColor.YELLOW

		var left_on := (_emergency_approach < 0 and mode == SignalMode.FOUR_PHASE and left_asp == Aspect.GREEN)
		lights[i].set_display(main_col, left_on)
