extends Control
class_name MetricsGraph

var wait_history: PackedFloat32Array = PackedFloat32Array()
var throughput_history: PackedFloat32Array = PackedFloat32Array()
const MAX_POINTS: int = 48

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 68)

func push_sample(waiting_cnt: float, throughput_pm: float) -> void:
	wait_history.append(waiting_cnt)
	throughput_history.append(throughput_pm)
	if wait_history.size() > MAX_POINTS:
		wait_history.remove_at(0)
	if throughput_history.size() > MAX_POINTS:
		throughput_history.remove_at(0)
	queue_redraw()

func clear_history() -> void:
	wait_history.clear()
	throughput_history.clear()
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20.0 or h < 20.0:
		return

	# Subtle chart background
	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.06, 0.09, 0.72), true)
	draw_rect(Rect2(0, 0, w, h), Color(0.24, 0.32, 0.44, 0.55), false, 1.0)

	# Horizontal grid lines
	for g in range(1, 4):
		var gy := h * (float(g) / 4.0)
		draw_line(Vector2(2, gy), Vector2(w - 2, gy), Color(0.25, 0.32, 0.42, 0.25), 1.0)

	if wait_history.size() < 2:
		return

	var pad_x := 4.0
	var pad_top := 8.0
	var pad_bot := 6.0
	var plot_w := w - pad_x * 2.0
	var plot_h := h - pad_top - pad_bot

	# Determine scales with sensible floors
	var max_wait := 10.0
	for v in wait_history:
		if v > max_wait:
			max_wait = v
	var max_tp := 30.0
	for v in throughput_history:
		if v > max_tp:
			max_tp = v

	var n := wait_history.size()
	var pts_tp := PackedVector2Array()
	var pts_wait := PackedVector2Array()

	for i in range(n):
		var t := float(i) / float(max(1, MAX_POINTS - 1))
		var x := pad_x + t * plot_w
		var y_tp := pad_top + plot_h * (1.0 - clampf(throughput_history[i] / max_tp, 0.0, 1.0))
		var y_w := pad_top + plot_h * (1.0 - clampf(wait_history[i] / max_wait, 0.0, 1.0))
		pts_tp.append(Vector2(x, y_tp))
		pts_wait.append(Vector2(x, y_w))

	# Draw throughput line (cyan) and waiting queue line (amber/orange)
	draw_polyline(pts_tp, Color(0.28, 0.82, 0.98, 0.92), 2.0, true)
	draw_polyline(pts_wait, Color(1.0, 0.62, 0.18, 0.95), 2.0, true)
