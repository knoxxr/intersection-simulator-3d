extends Node3D
class_name OrbitCamera

const MIN_DIST: float = 18.0
const MAX_DIST: float = 260.0

var camera: Camera3D

var yaw: float = 0.72          # Radians around Y
var pitch: float = -0.68       # Radians down from horizon
var distance: float = 64.0
var target: Vector3 = Vector3.ZERO

var target_yaw: float = 0.72
var target_pitch: float = -0.68
var target_distance: float = 64.0

var dragging: bool = false
var is_portrait: bool = false
var _touches: Dictionary = {}  # finger_index -> Vector2 position

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 48.0
	camera.near = 2.0
	camera.far = 520.0
	add_child(camera)
	camera.current = true
	_update_camera_transform()

func set_portrait_mode(portrait: bool) -> void:
	if is_portrait == portrait:
		return
	is_portrait = portrait
	if camera:
		camera.fov = 56.0 if portrait else 48.0
	if portrait and target_distance < 78.0:
		target_distance = 86.0
	elif not portrait and target_distance > 80.0 and target_distance < 95.0:
		target_distance = 64.0

func _unhandled_input(event: InputEvent) -> void:
	# Multi-touch support for mobile (1-finger orbit, 2-finger pinch zoom)
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		var prev_pos: Vector2 = _touches.get(sd.index, sd.position - sd.relative)
		_touches[sd.index] = sd.position

		if _touches.size() == 1:
			target_yaw -= sd.relative.x * 0.008
			target_pitch = clamp(target_pitch - sd.relative.y * 0.008, -1.50, -0.15)
		elif _touches.size() == 2:
			var keys := _touches.keys()
			var other_idx: int = keys[0] if keys[1] == sd.index else keys[1]
			var other_pos: Vector2 = _touches[other_idx]
			var prev_dist := prev_pos.distance_to(other_pos)
			var curr_dist := sd.position.distance_to(other_pos)
			var delta_dist := curr_dist - prev_dist
			var sens := 0.14 + target_distance * 0.0025
			target_distance = clamp(target_distance - delta_dist * sens, MIN_DIST, MAX_DIST)
		return

	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.01:
			target_distance = clamp(target_distance / mg.factor, MIN_DIST, MAX_DIST)
		return

	# Desktop mouse controls (ignore touch-emulated mouse events to avoid double-orbiting)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_in()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_out()
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION:
			return
		target_yaw -= mm.relative.x * 0.007
		target_pitch = clamp(target_pitch - mm.relative.y * 0.007, -1.50, -0.15)

func _process(delta: float) -> void:
	var k: float = min(1.0, delta * 9.0)
	yaw = lerpf(yaw, target_yaw, k)
	pitch = lerpf(pitch, target_pitch, k)
	distance = lerpf(distance, target_distance, k)
	_update_camera_transform()

func _update_camera_transform() -> void:
	if camera == null:
		return
	var horiz := cos(pitch) * distance
	var y := -sin(pitch) * distance
	var x := sin(yaw) * horiz
	var z := cos(yaw) * horiz
	camera.position = target + Vector3(x, y, z)
	camera.look_at(target, Vector3.UP)

func zoom_in() -> void:
	var step := maxf(6.0, target_distance * 0.14)
	target_distance = clamp(target_distance - step, MIN_DIST, MAX_DIST)

func zoom_out() -> void:
	var step := maxf(6.0, target_distance * 0.16)
	target_distance = clamp(target_distance + step, MIN_DIST, MAX_DIST)

func set_preset_iso() -> void:
	target_yaw = 0.72
	target_pitch = -0.68
	target_distance = 86.0 if is_portrait else 64.0

func set_preset_wide() -> void:
	target_yaw = 0.72
	target_pitch = -0.82
	target_distance = 175.0 if is_portrait else 140.0

func set_preset_top() -> void:
	target_yaw = 0.0
	target_pitch = -1.48
	target_distance = 140.0 if is_portrait else 105.0

func set_preset_street() -> void:
	target_yaw = 0.55
	target_pitch = -0.26
	target_distance = 36.0 if is_portrait else 28.0
