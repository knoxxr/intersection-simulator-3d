extends Node3D
class_name OrbitCamera

var camera: Camera3D

var yaw: float = 0.72          # Radians around Y
var pitch: float = -0.68       # Radians down from horizon
var distance: float = 52.0
var target: Vector3 = Vector3.ZERO

var target_yaw: float = 0.72
var target_pitch: float = -0.68
var target_distance: float = 52.0

var dragging: bool = false

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 48.0
	camera.near = 0.5
	camera.far = 350.0
	add_child(camera)
	camera.current = true
	_update_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_distance = clamp(target_distance - 4.0, 18.0, 110.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_distance = clamp(target_distance + 4.0, 18.0, 110.0)
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		target_yaw -= mm.relative.x * 0.007
		target_pitch = clamp(target_pitch - mm.relative.y * 0.007, -1.48, -0.18)

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

func set_preset_iso() -> void:
	target_yaw = 0.72
	target_pitch = -0.68
	target_distance = 52.0

func set_preset_top() -> void:
	target_yaw = 0.0
	target_pitch = -1.46
	target_distance = 62.0

func set_preset_street() -> void:
	target_yaw = 0.55
	target_pitch = -0.26
	target_distance = 28.0
