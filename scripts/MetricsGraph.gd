extends Control
class_name MetricsGraph

var wait_history: PackedFloat32Array = PackedFloat32Array()
var throughput_history: PackedFloat32Array = PackedFloat32Array()
const MAX_POINTS: int = 48

const COL_TP := Color(0.28, 0.86, 1.0, 0.96)
const COL_WAIT := Color(1.0, 0.62, 0.16, 0.96)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 82)

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

	# Chart panel background & border
	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.06, 0.10, 0.78), true)
	draw_rect(Rect2(0, 0, w, h), Color(0.24, 0.34, 0.46, 0.60), false, 1.0)

	var pad_x := 6.0
	var pad_top := 15.0
	var pad_bot := 14.0
	var plot_w := w - pad_x * 2.0
	var plot_h := maxf(10.0, h - pad_top - pad_bot)

	# Horizontal grid lines
	for g in range(0, 4):
		var gy := pad_top + plot_h * (float(g) / 3.0)
		draw_line(Vector2(pad_x, gy), Vector2(w - pad_x, gy), Color(0.26, 0.34, 0.44, 0.28), 1.0)

	var font := ThemeDB.fallback_font
	var fsz := 10

	# Compute dynamic Y scales
	var max_wait := 10.0
	for v in wait_history:
		if v > max_wait:
			max_wait = v
	var max_tp := 30.0
	for v in throughput_history:
		if v > max_tp:
			max_tp = v
	max_wait = ceilf(max_wait / 5.0) * 5.0
	max_tp = ceilf(max_tp / 10.0) * 10.0

	# Top Y-axis scale labels (Left: Throughput max in Cyan, Right: Waiting max in Amber)
	if font != null:
		draw_string(font, Vector2(pad_x, 11.0), "▲ %.0f/m" % max_tp, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_TP)
		draw_string(font, Vector2(pad_x, 11.0), "▲ %.0f" % max_wait, HORIZONTAL_ALIGNMENT_RIGHT, plot_w, fsz, COL_WAIT)
		# Bottom X-axis time labels
		var axis_col := Color(0.62, 0.70, 0.80, 0.78)
		draw_string(font, Vector2(pad_x, h - 3.0), "-48s", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, axis_col)
		draw_string(font, Vector2(pad_x, h - 3.0), Lang.t("graph_now"), HORIZONTAL_ALIGNMENT_RIGHT, plot_w, fsz, axis_col)

	if wait_history.size() < 2:
		return

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

	# Draw lines and latest-point dot indicators
	draw_polyline(pts_tp, COL_TP, 2.2, true)
	draw_polyline(pts_wait, COL_WAIT, 2.2, true)
	draw_circle(pts_tp[pts_tp.size() - 1], 3.2, COL_TP)
	draw_circle(pts_wait[pts_wait.size() - 1], 3.2, COL_WAIT)
