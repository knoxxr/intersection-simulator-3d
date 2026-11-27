extends Control
class_name DirectionBars

var dir_waits: Array[int] = [0, 0, 0, 0]
var dir_max_q: Array[int] = [0, 0, 0, 0]
var dir_avg_wait: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 82)

func set_data(waits: Array, max_q: Array, avg_w: Array) -> void:
	for i in range(4):
		if i < waits.size(): dir_waits[i] = int(waits[i])
		if i < max_q.size(): dir_max_q[i] = int(max_q[i])
		if i < avg_w.size(): dir_avg_wait[i] = float(avg_w[i])
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 40.0 or h < 40.0:
		return

	draw_rect(Rect2(0, 0, w, h), Color(0.04, 0.06, 0.10, 0.78), true)
	draw_rect(Rect2(0, 0, w, h), Color(0.24, 0.34, 0.46, 0.55), false, 1.0)

	var font := ThemeDB.fallback_font
	var fsz := 11
	var dir_keys := ["dir_n", "dir_s", "dir_e", "dir_w"]

	var max_scale := 8.0
	for i in range(4):
		max_scale = maxf(max_scale, float(maxi(dir_waits[i], dir_max_q[i])))

	var pad_x := 8.0
	var pad_y := 6.0
	var row_h := (h - pad_y * 2.0) / 4.0
	var lbl_w := 24.0
	var stat_w := 102.0
	var bar_x := pad_x + lbl_w
	var bar_w := maxf(24.0, w - bar_x - stat_w - pad_x)

	for i in range(4):
		var ry := pad_y + float(i) * row_h
		var by := ry + 3.0
		var bh := maxf(6.0, row_h - 6.0)

		if font != null:
			draw_string(font, Vector2(pad_x, ry + row_h * 0.74), Lang.t(dir_keys[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.84, 0.90, 0.96))

		# Bar background track
		draw_rect(Rect2(bar_x, by, bar_w, bh), Color(0.12, 0.16, 0.22, 0.95), true)

		# Peak queue ghost marker
		if dir_max_q[i] > 0:
			var peak_frac := clampf(float(dir_max_q[i]) / max_scale, 0.0, 1.0)
			var px := bar_x + peak_frac * bar_w
			draw_line(Vector2(px, by), Vector2(px, by + bh), Color(0.75, 0.82, 0.92, 0.55), 1.5)

		# Live queue fill bar (green / amber / red)
		var q := dir_waits[i]
		if q > 0:
			var frac := clampf(float(q) / max_scale, 0.0, 1.0)
			var col := Color(0.18, 0.85, 0.46, 0.95)
			if q >= 6:
				col = Color(0.96, 0.28, 0.24, 0.95)
			elif q >= 3:
				col = Color(0.98, 0.72, 0.18, 0.95)
			draw_rect(Rect2(bar_x, by, maxf(3.0, frac * bar_w), bh), col, true)

		# Right-aligned numeric readout: "Q:3 (M8) 12.1s"
		if font != null:
			var txt := "%d (M%d) %.1fs" % [q, dir_max_q[i], dir_avg_wait[i]]
			draw_string(font, Vector2(bar_x + bar_w + 4.0, ry + row_h * 0.74), txt, HORIZONTAL_ALIGNMENT_RIGHT, stat_w - 2.0, 10, Color(0.86, 0.91, 0.97))
