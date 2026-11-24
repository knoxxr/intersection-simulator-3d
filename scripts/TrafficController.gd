extends Node3D
class_name TrafficController

# Signal operation modes
enum SignalMode {
	TWO_PHASE,        # N-S Green / E-W Green (standard)
	FOUR_PHASE,       # Protected Left Turn phases (N-S Straight -> N-S Left -> E-W Straight -> E-W Left)
	FLASHING_YELLOW,  # Uncontrolled flashing yellow caution
	ALL_RED           # Emergency all-red stop (gridlock/queue test)
}

# Turn types matching Vehicle.gd
enum TurnType { STRAIGHT, LEFT, RIGHT }

# Current signal state returned to vehicles
enum Aspect { RED, YELLOW, GREEN, FLASHING_YELLOW }

var mode: SignalMode = SignalMode.TWO_PHASE
var ns_green_duration: float = 8.0
var ew_green_duration: float = 8.0
var left_green_duration: float = 5.0
var yellow_duration: float = 2.5
var all_red_duration: float = 1.0

# Internal phase state
# 2-Phase steps: 0=NS_GREEN, 1=NS_YELLOW, 2=ALL_RED_TO_EW, 3=EW_GREEN, 4=EW_YELLOW, 5=ALL_RED_TO_NS
# 4-Phase steps:
#   0=NS_STRAIGHT_GREEN, 1=NS_STRAIGHT_YELLOW, 2=AR_1,
#   3=NS_LEFT_GREEN,     4=NS_LEFT_YELLOW,     5=AR_2,
#   6=EW_STRAIGHT_GREEN, 7=EW_STRAIGHT_YELLOW, 8=AR_3,
#   9=EW_LEFT_GREEN,     10=EW_LEFT_YELLOW,    11=AR_4
var phase_index: int = 0
var phase_timer: float = 0.0
var flash_timer: float = 0.0
var flash_on: bool = true

# 4 traffic light nodes indexed by approach: 0=North, 1=South, 2=East, 3=West
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
	reposition_lights(7.0)

func reposition_lights(road_half: float) -> void:
	if lights.size() < 4:
		return
	var offset := road_half + 1.4
	# Place each traffic light on the far-right or near-right corner of its approach, facing approaching traffic
	# Approach 0 (from North, heading +Z): cars are at x < 0, z < 0. Place pole at (-offset, 0, +offset) or (-offset, 0, -offset)
	# Pole arm extends +X in local space; bulbs face -Z in local space.
	# For Approach 0 (approaching from -Z heading +Z): want bulbs facing -Z -> rotation_y = 0, pole on right side (-offset, 0, +offset) so arm extends +X toward road!
	lights[0].position = Vector3(-offset, 0, offset)
	lights[0].rotation_degrees = Vector3(0, 0, 0)

	# Approach 1 (from South, heading -Z): approaching from +Z -> want bulbs facing +Z -> rotation_y = 180, pole at (+offset, 0, -offset)
	lights[1].position = Vector3(offset, 0, -offset)
	lights[1].rotation_degrees = Vector3(0, 180, 0)

	# Approach 2 (from East, heading -X): approaching from +X -> want bulbs facing +X -> rotation_y = -90, pole at (-offset, 0, -offset)
	lights[2].position = Vector3(-offset, 0, -offset)
	lights[2].rotation_degrees = Vector3(0, -90, 0)

	# Approach 3 (from West, heading +X): approaching from -X -> want bulbs facing -X -> rotation_y = 90, pole at (+offset, 0, +offset)
	lights[3].position = Vector3(offset, 0, offset)
	lights[3].rotation_degrees = Vector3(0, 90, 0)

func set_mode(new_mode: SignalMode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	_reset_phase()

func _reset_phase() -> void:
	phase_index = 0
	phase_timer = _get_phase_duration(phase_index)
	_update_light_visuals()

func force_next_phase() -> void:
	if mode == SignalMode.FLASHING_YELLOW or mode == SignalMode.ALL_RED:
		return
	var total := 6 if mode == SignalMode.TWO_PHASE else 12
	phase_index = (phase_index + 1) % total
	phase_timer = _get_phase_duration(phase_index)
	_update_light_visuals()

func step_simulation(delta: float) -> void:
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

	phase_timer -= delta
	if phase_timer <= 0.0:
		var total := 6 if mode == SignalMode.TWO_PHASE else 12
		phase_index = (phase_index + 1) % total
		phase_timer = _get_phase_duration(phase_index)
		_update_light_visuals()

func _get_phase_duration(idx: int) -> float:
	if mode == SignalMode.TWO_PHASE:
		match idx:
			0: return ns_green_duration
			1: return yellow_duration
			2: return all_red_duration
			3: return ew_green_duration
			4: return yellow_duration
			5: return all_red_duration
	elif mode == SignalMode.FOUR_PHASE:
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
	return 1.0

# Returns the signal Aspect for a vehicle on approach_idx (0=N, 1=S, 2=E, 3=W) doing turn_type
func get_signal_for(approach_idx: int, turn_type: int) -> Aspect:
	if mode == SignalMode.ALL_RED:
		return Aspect.RED
	if mode == SignalMode.FLASHING_YELLOW:
		return Aspect.FLASHING_YELLOW

	var is_ns := (approach_idx == 0 or approach_idx == 1)

	if mode == SignalMode.TWO_PHASE:
		if is_ns:
			if phase_index == 0:
				return Aspect.GREEN
			elif phase_index == 1:
				return Aspect.YELLOW
			return Aspect.RED
		else:
			if phase_index == 3:
				return Aspect.GREEN
			elif phase_index == 4:
				return Aspect.YELLOW
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
	return mode == SignalMode.TWO_PHASE and turn_type == TurnType.LEFT and get_signal_for(approach_idx, turn_type) == Aspect.GREEN

func get_phase_label() -> String:
	match mode:
		SignalMode.ALL_RED:
			return "전체 적색 (긴급 정지)"
		SignalMode.FLASHING_YELLOW:
			return "황색 점멸 (주의 서행)"
		SignalMode.TWO_PHASE:
			match phase_index:
				0: return "남북 직진/회전 녹색"
				1: return "남북 황색"
				2: return "전방 적색 (정리)"
				3: return "동서 직진/회전 녹색"
				4: return "동서 황색"
				5: return "전방 적색 (정리)"
		SignalMode.FOUR_PHASE:
			match phase_index:
				0: return "남북 직진/우회전 녹색"
				1: return "남북 직진 황색"
				2: return "전방 적색 (정리)"
				3: return "남북 좌회전 보호 신호"
				4: return "남북 좌회전 황색"
				5: return "전방 적색 (정리)"
				6: return "동서 직진/우회전 녹색"
				7: return "동서 직진 황색"
				8: return "전방 적색 (정리)"
				9: return "동서 좌회전 보호 신호"
				10: return "동서 좌회전 황색"
				11: return "전방 적색 (정리)"
	return "-"

func get_time_remaining() -> float:
	if mode == SignalMode.ALL_RED or mode == SignalMode.FLASHING_YELLOW:
		return 0.0
	return max(0.0, phase_timer)

func _update_light_visuals() -> void:
	if lights.size() < 4:
		return

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

		var left_on := (mode == SignalMode.FOUR_PHASE and left_asp == Aspect.GREEN)
		lights[i].set_display(main_col, left_on)
