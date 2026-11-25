extends Control

var sim: IntersectionMain

var _is_mobile: bool = false
var _ui_built: bool = false
var _drawer_open: bool = false
var _active_mobile_tab: int = 0
var _camera_preset_idx: int = 0
var _ui_refresh_timer: float = 0.0

var _syncing_layout: bool = false
var _force_mode: int = 0 # 0 = auto, 1 = force mobile, 2 = force desktop
var _startup_resync_done: bool = false
var _startup_timer: float = 0.0

# Cached history so rebuilding UI on rotate/preset/lang preserves graph history
var _hist_wait: PackedFloat32Array = PackedFloat32Array()
var _hist_tp: PackedFloat32Array = PackedFloat32Array()

# Dynamic widget refs
var panel_container: PanelContainer
var toggle_panel_btn: Button
var floating_controls: VBoxContainer
var lane_checkboxes: Array[CheckBox] = []
var ns_lane_btns: Array[Button] = []
var ew_lane_btns: Array[Button] = []
var speed_btns: Array[Button] = []
var time_btns: Array[Button] = []
var pause_btn: Button
var mobile_tab_btns: Array[Button] = []
var mobile_tab_pages: Array[Control] = []
var metrics_graph: MetricsGraph

# Telemetry labels
var lbl_phase: Label
var lbl_counts: Label
var lbl_perf: Label

# Reusable theme styles
var _style_panel: StyleBoxFlat
var _style_sheet: StyleBoxFlat
var _style_btn: StyleBoxFlat
var _style_btn_hover: StyleBoxFlat
var _style_btn_active: StyleBoxFlat
var _style_btn_danger: StyleBoxFlat
var _style_slider_bg: StyleBoxFlat
var _style_slider_fill: StyleBoxFlat

func bind_simulation(main_sim: IntersectionMain) -> void:
	sim = main_sim
	_init_styles()
	sim.metrics_sampled.connect(_on_metrics_sampled)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_sync_scale_and_layout(true)

func _on_metrics_sampled(waiting_cnt: float, throughput_pm: float) -> void:
	_hist_wait.append(waiting_cnt)
	_hist_tp.append(throughput_pm)
	if _hist_wait.size() > MetricsGraph.MAX_POINTS:
		_hist_wait.remove_at(0)
	if _hist_tp.size() > MetricsGraph.MAX_POINTS:
		_hist_tp.remove_at(0)
	if is_instance_valid(metrics_graph):
		metrics_graph.push_sample(waiting_cnt, throughput_pm)

func _init_styles() -> void:
	var dark_bg := Color(0.07, 0.09, 0.13, 0.88)
	var border_col := Color(0.28, 0.36, 0.48, 0.78)

	_style_panel = _make_box(dark_bg, border_col, 10, 12, 10)

	_style_sheet = StyleBoxFlat.new()
	_style_sheet.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	_style_sheet.border_color = Color(0.30, 0.42, 0.58, 0.85)
	_style_sheet.border_width_top = 2
	_style_sheet.corner_radius_top_left = 16
	_style_sheet.corner_radius_top_right = 16
	_style_sheet.content_margin_left = 12
	_style_sheet.content_margin_right = 12
	_style_sheet.content_margin_top = 10
	_style_sheet.content_margin_bottom = 12

	_style_btn = _make_box(Color(0.15, 0.19, 0.26, 0.92), Color(0.32, 0.40, 0.52, 0.7), 8, 8, 6)
	_style_btn_hover = _make_box(Color(0.21, 0.27, 0.36, 0.96), Color(0.45, 0.60, 0.80, 0.9), 8, 8, 6)
	_style_btn_active = _make_box(Color(0.16, 0.48, 0.84, 0.98), Color(0.45, 0.78, 1.0, 1.0), 8, 8, 6)
	_style_btn_danger = _make_box(Color(0.76, 0.18, 0.18, 0.96), Color(1.0, 0.45, 0.45, 0.95), 8, 8, 6)

	_style_slider_bg = StyleBoxFlat.new()
	_style_slider_bg.bg_color = Color(0.20, 0.24, 0.32, 0.95)
	_style_slider_bg.set_corner_radius_all(4)
	_style_slider_bg.content_margin_top = 4
	_style_slider_bg.content_margin_bottom = 4

	_style_slider_fill = StyleBoxFlat.new()
	_style_slider_fill.bg_color = Color(0.24, 0.62, 0.96, 1.0)
	_style_slider_fill.set_corner_radius_all(4)
	_style_slider_fill.content_margin_top = 4
	_style_slider_fill.content_margin_bottom = 4

func _make_box(bg: Color, border: Color, radius: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

func _on_viewport_resized() -> void:
	if _syncing_layout:
		return
	call_deferred("_sync_scale_and_layout", false)

func _get_web_viewport_info() -> Dictionary:
	var info := {
		"dpr": clampf(DisplayServer.screen_get_scale(), 1.0, 3.0),
		"css_w": 0.0,
		"css_h": 0.0,
		"is_touch": OS.has_feature("mobile")
	}
	if OS.has_feature("web"):
		var dpr_v: Variant = JavaScriptBridge.eval("window.devicePixelRatio || 1")
		var w_v: Variant = JavaScriptBridge.eval("window.innerWidth || 0")
		var h_v: Variant = JavaScriptBridge.eval("window.innerHeight || 0")
		var touch_v: Variant = JavaScriptBridge.eval("(('ontouchstart' in window) || (navigator.maxTouchPoints > 0) || window.matchMedia('(pointer: coarse)').matches) ? 1 : 0")
		if dpr_v != null:
			info["dpr"] = clampf(float(dpr_v), 1.0, 3.5)
		if w_v != null:
			info["css_w"] = float(w_v)
		if h_v != null:
			info["css_h"] = float(h_v)
		if touch_v != null:
			info["is_touch"] = int(touch_v) == 1
	return info

func _sync_scale_and_layout(force_rebuild: bool) -> void:
	if sim == null or _syncing_layout:
		return
	_syncing_layout = true

	var web_info := _get_web_viewport_info()
	var scale_factor: float = web_info["dpr"]
	var root_win := get_tree().root
	if root_win != null and absf(root_win.content_scale_factor - scale_factor) > 0.05:
		root_win.content_scale_factor = scale_factor

	var phys_size := Vector2(DisplayServer.window_get_size())
	if phys_size.x <= 1.0 or phys_size.y <= 1.0:
		phys_size = Vector2(1280, 720)
	var logical_size := phys_size / scale_factor
	if web_info["css_w"] > 10.0 and web_info["css_h"] > 10.0:
		logical_size = Vector2(web_info["css_w"], web_info["css_h"])

	var portrait := logical_size.y > logical_size.x
	var is_touch: bool = web_info["is_touch"]
	var want_mobile := (logical_size.x < 900.0) or (logical_size.y < 540.0) or portrait or is_touch
	if _force_mode == 1:
		want_mobile = true
	elif _force_mode == 2:
		want_mobile = false

	sim.orbit_camera.set_portrait_mode(portrait)

	if force_rebuild or (not _ui_built) or (_is_mobile != want_mobile):
		var same_mode := _ui_built and (_is_mobile == want_mobile)
		var prev_open := _drawer_open
		_is_mobile = want_mobile
		_ui_built = true
		if _is_mobile:
			_drawer_open = prev_open if same_mode else false
			_build_mobile_ui(portrait)
		else:
			_drawer_open = prev_open if same_mode else true
			_build_desktop_ui()
		_restore_graph_history()
		_refresh_metrics()
	elif _is_mobile and panel_container != null:
		panel_container.anchor_top = 0.48 if portrait else 0.34
	_syncing_layout = false

func _restore_graph_history() -> void:
	if not is_instance_valid(metrics_graph):
		return
	metrics_graph.wait_history = _hist_wait.duplicate()
	metrics_graph.throughput_history = _hist_tp.duplicate()
	metrics_graph.queue_redraw()

func _toggle_ui_layout_mode() -> void:
	_force_mode = 2 if _is_mobile else 1
	_sync_scale_and_layout(true)

func _on_toggle_language() -> void:
	Lang.toggle()
	_sync_scale_and_layout(true)

func _apply_preset_and_sync(preset_id: String) -> void:
	sim.apply_preset(preset_id)
	_sync_scale_and_layout(true)

func _process(delta: float) -> void:
	if sim == null:
		return
	if not _startup_resync_done:
		_startup_timer += delta
		if _startup_timer >= 0.35:
			_startup_resync_done = true
			_sync_scale_and_layout(false)
	_ui_refresh_timer += delta
	if _ui_refresh_timer >= 0.15:
		_ui_refresh_timer = 0.0
		_refresh_metrics()

func _clear_ui() -> void:
	for c in get_children():
		c.queue_free()
	lane_checkboxes.clear()
	ns_lane_btns.clear()
	ew_lane_btns.clear()
	speed_btns.clear()
	time_btns.clear()
	mobile_tab_btns.clear()
	mobile_tab_pages.clear()
	panel_container = null
	floating_controls = null
	toggle_panel_btn = null
	pause_btn = null
	metrics_graph = null
	lbl_phase = null
	lbl_counts = null
	lbl_perf = null

func _style_button(btn: Button, active: bool = false, min_h: int = 34, font_sz: int = 13, danger: bool = false) -> void:
	btn.custom_minimum_size.y = min_h
	btn.add_theme_font_size_override("font_size", font_sz)
	if danger:
		btn.add_theme_stylebox_override("normal", _style_btn_danger)
		btn.add_theme_stylebox_override("hover", _style_btn_danger)
		btn.add_theme_stylebox_override("pressed", _style_btn_danger)
	else:
		btn.add_theme_stylebox_override("normal", _style_btn_active if active else _style_btn)
		btn.add_theme_stylebox_override("hover", _style_btn_active if active else _style_btn_hover)
		btn.add_theme_stylebox_override("pressed", _style_btn_active)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))

# ==============================================================================
# MOBILE / PORTRAIT UI
# ==============================================================================
func _build_mobile_ui(portrait: bool = true) -> void:
	_clear_ui()

	# 1. Top Full-Width Compact HUD Bar
	var top_bar := PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 10
	top_bar.offset_right = -10
	top_bar.offset_top = 10
	top_bar.offset_bottom = 94
	top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	top_bar.add_theme_stylebox_override("panel", _style_panel)
	add_child(top_bar)

	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 6)
	top_bar.add_child(top_v)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 5)
	top_v.add_child(row1)

	lbl_phase = Label.new()
	lbl_phase.text = "-"
	lbl_phase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_phase.clip_text = true
	lbl_phase.add_theme_font_size_override("font_size", 13)
	lbl_phase.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	row1.add_child(lbl_phase)

	var lang_btn := Button.new()
	lang_btn.text = Lang.t("lang_btn")
	lang_btn.custom_minimum_size = Vector2(52, 34)
	_style_button(lang_btn, false, 34, 12)
	lang_btn.pressed.connect(_on_toggle_language)
	row1.add_child(lang_btn)

	pause_btn = Button.new()
	pause_btn.text = "▶" if sim.paused else "⏸"
	pause_btn.custom_minimum_size = Vector2(38, 34)
	_style_button(pause_btn, sim.paused, 34, 15)
	pause_btn.pressed.connect(_on_toggle_pause)
	row1.add_child(pause_btn)

	toggle_panel_btn = Button.new()
	toggle_panel_btn.text = Lang.t("close") if _drawer_open else Lang.t("settings")
	toggle_panel_btn.custom_minimum_size = Vector2(74, 34)
	_style_button(toggle_panel_btn, _drawer_open, 34, 13)
	toggle_panel_btn.pressed.connect(_on_toggle_mobile_drawer)
	row1.add_child(toggle_panel_btn)

	lbl_counts = Label.new()
	lbl_counts.text = ""
	lbl_counts.clip_text = true
	lbl_counts.add_theme_font_size_override("font_size", 12)
	lbl_counts.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96))
	top_v.add_child(lbl_counts)

	# 2. Floating Right Quick-Action Buttons
	floating_controls = VBoxContainer.new()
	floating_controls.anchor_left = 1.0
	floating_controls.anchor_right = 1.0
	floating_controls.anchor_top = 1.0
	floating_controls.anchor_bottom = 1.0
	floating_controls.offset_left = -58
	floating_controls.offset_right = -10
	floating_controls.offset_top = -274
	floating_controls.offset_bottom = -16
	floating_controls.add_theme_constant_override("separation", 8)
	floating_controls.visible = not _drawer_open
	add_child(floating_controls)

	var amb_quick := Button.new()
	amb_quick.text = Lang.t("quick_amb")
	amb_quick.custom_minimum_size = Vector2(46, 44)
	_style_button(amb_quick, false, 44, 12, true)
	amb_quick.pressed.connect(func(): sim.dispatch_ambulance())
	floating_controls.add_child(amb_quick)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(46, 44)
	_style_button(zoom_in_btn, false, 44, 20)
	zoom_in_btn.pressed.connect(func(): sim.orbit_camera.zoom_in())
	floating_controls.add_child(zoom_in_btn)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = "−"
	zoom_out_btn.custom_minimum_size = Vector2(46, 44)
	_style_button(zoom_out_btn, false, 44, 20)
	zoom_out_btn.pressed.connect(func(): sim.orbit_camera.zoom_out())
	floating_controls.add_child(zoom_out_btn)

	var cam_cycle_btn := Button.new()
	cam_cycle_btn.text = Lang.t("quick_view")
	cam_cycle_btn.custom_minimum_size = Vector2(46, 44)
	_style_button(cam_cycle_btn, false, 44, 12)
	cam_cycle_btn.pressed.connect(_on_cycle_camera)
	floating_controls.add_child(cam_cycle_btn)

	var next_sig_btn := Button.new()
	next_sig_btn.text = Lang.t("quick_sig")
	next_sig_btn.custom_minimum_size = Vector2(46, 44)
	_style_button(next_sig_btn, false, 44, 12)
	next_sig_btn.pressed.connect(func(): sim.traffic_ctrl.force_next_phase())
	floating_controls.add_child(next_sig_btn)

	# 3. Bottom Sheet Control Drawer
	panel_container = PanelContainer.new()
	panel_container.anchor_left = 0.0
	panel_container.anchor_right = 1.0
	panel_container.anchor_top = 0.48 if portrait else 0.34
	panel_container.anchor_bottom = 1.0
	panel_container.offset_left = 0
	panel_container.offset_right = 0
	panel_container.offset_top = 0
	panel_container.offset_bottom = 0
	panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_container.add_theme_stylebox_override("panel", _style_sheet)
	panel_container.visible = _drawer_open
	add_child(panel_container)

	var sheet_v := VBoxContainer.new()
	sheet_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet_v.add_theme_constant_override("separation", 10)
	panel_container.add_child(sheet_v)

	# Category Tab Strip
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 5)
	sheet_v.add_child(tab_bar)

	var tab_keys := ["tab_presets", "tab_lanes", "tab_traffic", "tab_signals", "tab_control"]
	for t in range(tab_keys.size()):
		var tb := Button.new()
		tb.text = Lang.t(tab_keys[t])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(tb, t == _active_mobile_tab, 40, 12)
		var tab_idx := t
		tb.pressed.connect(func(): _select_mobile_tab(tab_idx))
		tab_bar.add_child(tb)
		mobile_tab_btns.append(tb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_v.add_child(scroll)

	var pages_host := VBoxContainer.new()
	pages_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_host)

	var page_preset := VBoxContainer.new()
	page_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_preset.add_theme_constant_override("separation", 10)
	_populate_scenario_controls(page_preset, true)
	pages_host.add_child(page_preset)

	var page_lanes := VBoxContainer.new()
	page_lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_lanes.add_theme_constant_override("separation", 10)
	_populate_lane_controls(page_lanes, true)
	pages_host.add_child(page_lanes)

	var page_traffic := VBoxContainer.new()
	page_traffic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_traffic.add_theme_constant_override("separation", 10)
	_populate_traffic_controls(page_traffic, true)
	pages_host.add_child(page_traffic)

	var page_signals := VBoxContainer.new()
	page_signals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_signals.add_theme_constant_override("separation", 10)
	_populate_signal_controls(page_signals, true)
	pages_host.add_child(page_signals)

	var page_sim := VBoxContainer.new()
	page_sim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_sim.add_theme_constant_override("separation", 10)
	_populate_sim_camera_controls(page_sim, true)
	_add_graph_block(page_sim)
	pages_host.add_child(page_sim)

	mobile_tab_pages = [page_preset, page_lanes, page_traffic, page_signals, page_sim]
	_select_mobile_tab(clampi(_active_mobile_tab, 0, mobile_tab_pages.size() - 1))

func _select_mobile_tab(idx: int) -> void:
	_active_mobile_tab = idx
	for i in range(mobile_tab_pages.size()):
		mobile_tab_pages[i].visible = (i == idx)
	for i in range(mobile_tab_btns.size()):
		_style_button(mobile_tab_btns[i], i == idx, 40, 12)

func _on_toggle_mobile_drawer() -> void:
	_drawer_open = not _drawer_open
	if panel_container:
		panel_container.visible = _drawer_open
	if toggle_panel_btn:
		toggle_panel_btn.text = Lang.t("close") if _drawer_open else Lang.t("settings")
		_style_button(toggle_panel_btn, _drawer_open, 34, 13)
	if floating_controls:
		floating_controls.visible = not _drawer_open

func _on_cycle_camera() -> void:
	_camera_preset_idx = (_camera_preset_idx + 1) % 4
	match _camera_preset_idx:
		0: sim.orbit_camera.set_preset_iso()
		1: sim.orbit_camera.set_preset_wide()
		2: sim.orbit_camera.set_preset_top()
		3: sim.orbit_camera.set_preset_street()

# ==============================================================================
# DESKTOP / WIDE LANDSCAPE UI
# ==============================================================================
func _build_desktop_ui() -> void:
	_clear_ui()

	# 1. Top-Left Bar: Panel Toggle + Mobile UI Switch + Language Toggle
	toggle_panel_btn = Button.new()
	toggle_panel_btn.text = Lang.t("panel_hide") if _drawer_open else Lang.t("panel_show")
	toggle_panel_btn.position = Vector2(14, 12)
	toggle_panel_btn.size = Vector2(116, 32)
	_style_button(toggle_panel_btn, false, 32, 13)
	toggle_panel_btn.pressed.connect(_on_toggle_desktop_panel)
	add_child(toggle_panel_btn)

	var mode_btn := Button.new()
	mode_btn.text = Lang.t("mobile_ui")
	mode_btn.position = Vector2(138, 12)
	mode_btn.size = Vector2(96, 32)
	_style_button(mode_btn, false, 32, 13)
	mode_btn.pressed.connect(_toggle_ui_layout_mode)
	add_child(mode_btn)

	var lang_btn := Button.new()
	lang_btn.text = Lang.t("lang_btn")
	lang_btn.position = Vector2(242, 12)
	lang_btn.size = Vector2(72, 32)
	_style_button(lang_btn, false, 32, 13)
	lang_btn.pressed.connect(_on_toggle_language)
	add_child(lang_btn)

	# 2. Left Control Panel (Scrollable)
	panel_container = PanelContainer.new()
	panel_container.position = Vector2(14, 50)
	panel_container.custom_minimum_size = Vector2(326, 0)
	panel_container.anchor_bottom = 1.0
	panel_container.offset_bottom = -14
	panel_container.offset_right = 340
	panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_container.add_theme_stylebox_override("panel", _style_panel)
	panel_container.visible = _drawer_open
	add_child(panel_container)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = Lang.t("app_title")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	vbox.add_child(title)

	_add_section_header(vbox, Lang.t("sec_presets"))
	_populate_scenario_controls(vbox, false)

	_add_section_header(vbox, Lang.t("sec_sim_cam"))
	_populate_sim_camera_controls(vbox, false)

	_add_section_header(vbox, Lang.t("sec_lanes"))
	_populate_lane_controls(vbox, false)

	_add_section_header(vbox, Lang.t("sec_traffic"))
	_populate_traffic_controls(vbox, false)

	_add_section_header(vbox, Lang.t("sec_signals"))
	_populate_signal_controls(vbox, false)

	# 3. Top-Right Real-Time Telemetry HUD + Live Trend Graph
	var hud := PanelContainer.new()
	hud.anchor_left = 1.0
	hud.anchor_right = 1.0
	hud.offset_left = -330
	hud.offset_right = -14
	hud.offset_top = 12
	hud.offset_bottom = 228
	hud.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_theme_stylebox_override("panel", _style_panel)
	add_child(hud)

	var hud_v := VBoxContainer.new()
	hud_v.add_theme_constant_override("separation", 5)
	hud.add_child(hud_v)

	var hud_title := Label.new()
	hud_title.text = Lang.t("hud_title")
	hud_title.add_theme_font_size_override("font_size", 14)
	hud_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hud_v.add_child(hud_title)

	lbl_phase = Label.new()
	lbl_phase.text = "-"
	lbl_phase.add_theme_font_size_override("font_size", 13)
	hud_v.add_child(lbl_phase)

	lbl_counts = Label.new()
	lbl_counts.text = ""
	lbl_counts.add_theme_font_size_override("font_size", 13)
	hud_v.add_child(lbl_counts)

	lbl_perf = Label.new()
	lbl_perf.text = ""
	lbl_perf.add_theme_font_size_override("font_size", 12)
	lbl_perf.add_theme_color_override("font_color", Color(0.84, 0.90, 0.96))
	hud_v.add_child(lbl_perf)

	_add_graph_block(hud_v)

	# 4. Bottom-Right Controls Hint
	var hint := PanelContainer.new()
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -280
	hint.offset_right = -14
	hint.offset_top = -42
	hint.offset_bottom = -12
	hint.add_theme_stylebox_override("panel", _make_box(Color(0.06, 0.08, 0.11, 0.72), Color(0.28, 0.36, 0.48, 0.65), 8, 10, 6))
	add_child(hint)

	var hint_lbl := Label.new()
	hint_lbl.text = Lang.t("desktop_hint")
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	hint.add_child(hint_lbl)

func _add_graph_block(parent: VBoxContainer) -> void:
	var leg := Label.new()
	leg.text = Lang.t("graph_legend")
	leg.add_theme_font_size_override("font_size", 11)
	leg.add_theme_color_override("font_color", Color(0.74, 0.82, 0.90))
	parent.add_child(leg)

	metrics_graph = MetricsGraph.new()
	metrics_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics_graph.custom_minimum_size = Vector2(240, 68)
	parent.add_child(metrics_graph)

func _on_toggle_desktop_panel() -> void:
	_drawer_open = not _drawer_open
	if panel_container:
		panel_container.visible = _drawer_open
	if toggle_panel_btn:
		toggle_panel_btn.text = Lang.t("panel_hide") if _drawer_open else Lang.t("panel_show")

# ==============================================================================
# SHARED CONTROL BUILDERS
# ==============================================================================
func _populate_scenario_controls(parent: VBoxContainer, touch: bool) -> void:
	var btn_h := 42 if touch else 30
	var fsz := 14 if touch else 12

	var amb_btn := Button.new()
	amb_btn.text = Lang.t("btn_ambulance")
	_style_button(amb_btn, false, btn_h + 2, fsz + 1, true)
	amb_btn.pressed.connect(func(): sim.dispatch_ambulance())
	parent.add_child(amb_btn)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 5)
	parent.add_child(row1)

	var p_norm := Button.new()
	p_norm.text = Lang.t("preset_normal")
	p_norm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_norm, false, btn_h, fsz)
	p_norm.pressed.connect(func(): _apply_preset_and_sync("normal"))
	row1.add_child(p_norm)

	var p_rush := Button.new()
	p_rush.text = Lang.t("preset_rush")
	p_rush.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_rush, false, btn_h, fsz)
	p_rush.pressed.connect(func(): _apply_preset_and_sync("rush_hour"))
	row1.add_child(p_rush)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 5)
	parent.add_child(row2)

	var p_left := Button.new()
	p_left.text = Lang.t("preset_left")
	p_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_left, false, btn_h, fsz)
	p_left.pressed.connect(func(): _apply_preset_and_sync("left_jam"))
	row2.add_child(p_left)

	var p_const := Button.new()
	p_const.text = Lang.t("preset_const")
	p_const.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_const, false, btn_h, fsz)
	p_const.pressed.connect(func(): _apply_preset_and_sync("construction"))
	row2.add_child(p_const)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 5)
	parent.add_child(row3)

	var p_rotary := Button.new()
	p_rotary.text = Lang.t("preset_roundabout")
	p_rotary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_rotary, sim.intersection_type == RoadBuilder.IntersectionType.ROUNDABOUT, btn_h, fsz)
	p_rotary.pressed.connect(func(): _apply_preset_and_sync("roundabout"))
	row3.add_child(p_rotary)

	var p_mega := Button.new()
	p_mega.text = Lang.t("preset_mega10")
	p_mega.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_mega, false, btn_h, fsz)
	p_mega.pressed.connect(func(): _apply_preset_and_sync("mega10"))
	row3.add_child(p_mega)

func _populate_sim_camera_controls(parent: VBoxContainer, touch: bool) -> void:
	var btn_h := 42 if touch else 30
	var fsz := 14 if touch else 12

	var sim_row := HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 6)
	parent.add_child(sim_row)

	var p_btn := Button.new()
	p_btn.text = Lang.t("resume") if sim.paused else Lang.t("pause")
	p_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(p_btn, sim.paused, btn_h, fsz)
	p_btn.pressed.connect(func():
		_on_toggle_pause()
		p_btn.text = Lang.t("resume") if sim.paused else Lang.t("pause")
		_style_button(p_btn, sim.paused, btn_h, fsz)
	)
	sim_row.add_child(p_btn)
	if not touch:
		pause_btn = p_btn

	var reset_btn := Button.new()
	reset_btn.text = Lang.t("reset_cars")
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(reset_btn, false, btn_h, fsz)
	reset_btn.pressed.connect(func():
		sim.reset_simulation()
		_hist_wait.clear()
		_hist_tp.clear()
		if is_instance_valid(metrics_graph):
			metrics_graph.clear_history()
	)
	sim_row.add_child(reset_btn)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 5)
	parent.add_child(speed_row)
	var sp_lbl := Label.new()
	sp_lbl.text = Lang.t("speed_lbl")
	sp_lbl.add_theme_font_size_override("font_size", fsz)
	speed_row.add_child(sp_lbl)

	speed_btns.clear()
	var speeds := [0.5, 1.0, 2.0, 4.0]
	for sp in speeds:
		var sp_val: float = float(sp)
		var b := Button.new()
		b.text = "%sx" % str(sp_val)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, absf(sim.sim_speed - sp_val) < 0.05, btn_h, fsz)
		b.pressed.connect(func():
			sim.sim_speed = sp_val
			_refresh_speed_button_styles(btn_h, fsz)
		)
		speed_row.add_child(b)
		speed_btns.append(b)

	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 5)
	parent.add_child(cam_row)

	var cam_iso := Button.new()
	cam_iso.text = Lang.t("cam_3d")
	cam_iso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(cam_iso, false, btn_h, fsz)
	cam_iso.pressed.connect(func(): sim.orbit_camera.set_preset_iso())
	cam_row.add_child(cam_iso)

	var cam_wide := Button.new()
	cam_wide.text = Lang.t("cam_wide")
	cam_wide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(cam_wide, false, btn_h, fsz)
	cam_wide.pressed.connect(func(): sim.orbit_camera.set_preset_wide())
	cam_row.add_child(cam_wide)

	var cam_top := Button.new()
	cam_top.text = Lang.t("cam_top")
	cam_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(cam_top, false, btn_h, fsz)
	cam_top.pressed.connect(func(): sim.orbit_camera.set_preset_top())
	cam_row.add_child(cam_top)

	var cam_low := Button.new()
	cam_low.text = Lang.t("cam_low")
	cam_low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(cam_low, false, btn_h, fsz)
	cam_low.pressed.connect(func(): sim.orbit_camera.set_preset_street())
	cam_row.add_child(cam_low)

	var tod_row := HBoxContainer.new()
	tod_row.add_theme_constant_override("separation", 5)
	parent.add_child(tod_row)
	var tod_lbl := Label.new()
	tod_lbl.text = Lang.t("time_lbl")
	tod_lbl.add_theme_font_size_override("font_size", fsz)
	tod_row.add_child(tod_lbl)

	time_btns.clear()
	var tod_keys := ["time_day", "time_sunset", "time_night"]
	var tod_modes := [RoadBuilder.TimeOfDay.DAY, RoadBuilder.TimeOfDay.SUNSET, RoadBuilder.TimeOfDay.NIGHT]
	for i in range(3):
		var tb := Button.new()
		tb.text = Lang.t(tod_keys[i])
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m_val: RoadBuilder.TimeOfDay = tod_modes[i]
		_style_button(tb, sim.road_builder.time_of_day == m_val, btn_h, fsz)
		tb.pressed.connect(func():
			sim.set_time_of_day(m_val)
			_refresh_time_button_styles(btn_h, fsz)
		)
		tod_row.add_child(tb)
		time_btns.append(tb)

	var cong_cb := CheckBox.new()
	cong_cb.text = Lang.t("cong_overlay")
	cong_cb.button_pressed = sim.road_builder.congestion_overlay_enabled
	cong_cb.custom_minimum_size.y = 36 if touch else 24
	cong_cb.add_theme_font_size_override("font_size", fsz)
	cong_cb.toggled.connect(func(pressed: bool): sim.set_congestion_overlay(pressed))
	parent.add_child(cong_cb)

	if touch:
		var pc_btn := Button.new()
		pc_btn.text = Lang.t("pc_ui")
		_style_button(pc_btn, false, btn_h, fsz)
		pc_btn.pressed.connect(_toggle_ui_layout_mode)
		parent.add_child(pc_btn)

		var tip := Label.new()
		tip.text = Lang.t("touch_tip")
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.add_theme_font_size_override("font_size", 12)
		tip.add_theme_color_override("font_color", Color(0.75, 0.82, 0.90))
		parent.add_child(tip)

func _refresh_speed_button_styles(btn_h: int, fsz: int) -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0]
	for i in range(min(speed_btns.size(), speeds.size())):
		_style_button(speed_btns[i], absf(sim.sim_speed - float(speeds[i])) < 0.05, btn_h, fsz)

func _refresh_time_button_styles(btn_h: int, fsz: int) -> void:
	var tod_modes := [RoadBuilder.TimeOfDay.DAY, RoadBuilder.TimeOfDay.SUNSET, RoadBuilder.TimeOfDay.NIGHT]
	for i in range(min(time_btns.size(), tod_modes.size())):
		_style_button(time_btns[i], sim.road_builder.time_of_day == tod_modes[i], btn_h, fsz)

func _populate_lane_controls(parent: VBoxContainer, touch: bool) -> void:
	var btn_h := 42 if touch else 30
	var fsz := 14 if touch else 12
	var cb_fsz := 14 if touch else 12

	# Intersection Type Toggle (4-Way Signal vs Roundabout)
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 5)
	parent.add_child(type_row)
	var type_lbl := Label.new()
	type_lbl.text = Lang.t("type_lbl")
	type_lbl.add_theme_font_size_override("font_size", fsz)
	type_row.add_child(type_lbl)

	var is_rotary := (sim.intersection_type == RoadBuilder.IntersectionType.ROUNDABOUT)
	var btn_sig := Button.new()
	btn_sig.text = Lang.t("type_signal")
	btn_sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_sig, not is_rotary, btn_h, fsz)
	btn_sig.pressed.connect(func():
		sim.set_intersection_type(RoadBuilder.IntersectionType.SIGNALIZED)
		_sync_scale_and_layout(true)
	)
	type_row.add_child(btn_sig)

	var btn_rot := Button.new()
	btn_rot.text = Lang.t("type_roundabout")
	btn_rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_rot, is_rotary, btn_h, fsz)
	btn_rot.pressed.connect(func():
		sim.set_intersection_type(RoadBuilder.IntersectionType.ROUNDABOUT)
		_sync_scale_and_layout(true)
	)
	type_row.add_child(btn_rot)

	# 1..10 Lanes per Direction Sliders (N-S & E-W independently)
	ns_lane_btns.clear()
	ew_lane_btns.clear()
	_add_int_slider(parent, Lang.t("ns_lanes"), 1, 10, sim.spawner.ns_lanes, Lang.t("lane_unit"), touch, func(val: int):
		sim.set_ns_lanes(val)
		_update_lane_checkbox_visibility()
	)
	_add_int_slider(parent, Lang.t("ew_lanes"), 1, 10, sim.spawner.ew_lanes, Lang.t("lane_unit"), touch, func(val: int):
		sim.set_ew_lanes(val)
		_update_lane_checkbox_visibility()
	)

	var lane_open_lbl := Label.new()
	lane_open_lbl.text = Lang.t("lane_open_lbl")
	lane_open_lbl.add_theme_font_size_override("font_size", cb_fsz)
	lane_open_lbl.add_theme_color_override("font_color", Color(0.80, 0.86, 0.94))
	parent.add_child(lane_open_lbl)

	var lane_open_row := HBoxContainer.new()
	lane_open_row.add_theme_constant_override("separation", 8)
	parent.add_child(lane_open_row)
	lane_checkboxes.clear()
	var lane_keys := ["lane_1", "lane_2", "lane_3"]
	for idx in range(3):
		var cb := CheckBox.new()
		cb.text = Lang.t(lane_keys[idx])
		cb.button_pressed = sim.spawner.lane_enabled[idx]
		cb.custom_minimum_size.y = 38 if touch else 26
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", cb_fsz)
		var lane_i := idx
		cb.toggled.connect(func(pressed: bool): sim.set_lane_enabled(lane_i, pressed))
		lane_open_row.add_child(cb)
		lane_checkboxes.append(cb)
	_update_lane_checkbox_visibility()

	var dir_open_row := HBoxContainer.new()
	dir_open_row.add_theme_constant_override("separation", 6)
	parent.add_child(dir_open_row)
	var dir_lbl := Label.new()
	dir_lbl.text = Lang.t("approach_lbl")
	dir_lbl.add_theme_font_size_override("font_size", cb_fsz)
	dir_open_row.add_child(dir_lbl)
	var dir_keys := ["dir_n", "dir_s", "dir_e", "dir_w"]
	for a in range(4):
		var dcb := CheckBox.new()
		dcb.text = Lang.t(dir_keys[a])
		dcb.button_pressed = sim.spawner.approach_enabled[a]
		dcb.custom_minimum_size.y = 38 if touch else 26
		dcb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dcb.add_theme_font_size_override("font_size", cb_fsz)
		var app_i := a
		dcb.toggled.connect(func(pressed: bool): sim.set_approach_enabled(app_i, pressed))
		dir_open_row.add_child(dcb)

func _add_int_slider(parent: VBoxContainer, label_text: String, min_v: int, max_v: int, init_v: int, suffix: String, touch: bool, cb: Callable) -> void:
	var fsz := 14 if touch else 12
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3 if touch else 2)
	parent.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", fsz)
	head.add_child(l)

	var val_lbl := Label.new()
	val_lbl.text = "%d%s" % [init_v, suffix]
	val_lbl.add_theme_font_size_override("font_size", fsz)
	val_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.44))
	head.add_child(val_lbl)

	var sl := HSlider.new()
	sl.min_value = float(min_v)
	sl.max_value = float(max_v)
	sl.step = 1.0
	sl.value = float(init_v)
	sl.custom_minimum_size.y = 32 if touch else 20
	sl.add_theme_stylebox_override("slider", _style_slider_bg)
	sl.add_theme_stylebox_override("grabber_area", _style_slider_fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", _style_slider_fill)
	sl.value_changed.connect(func(v: float):
		var iv := int(roundf(v))
		val_lbl.text = "%d%s" % [iv, suffix]
		cb.call(iv)
	)
	row.add_child(sl)

func _populate_traffic_controls(parent: VBoxContainer, touch: bool) -> void:
	_add_slider(parent, Lang.t("vol_global"), 0.0, 3.0, 0.1, sim.spawner.global_traffic_rate, "x", touch, func(val: float):
		sim.spawner.global_traffic_rate = val
	)
	_add_slider(parent, Lang.t("vol_ns"), 0.0, 2.0, 0.1, sim.spawner.dir_traffic_mult[0], "x", touch, func(val: float):
		sim.spawner.dir_traffic_mult[0] = val
	)
	_add_slider(parent, Lang.t("vol_sn"), 0.0, 2.0, 0.1, sim.spawner.dir_traffic_mult[1], "x", touch, func(val: float):
		sim.spawner.dir_traffic_mult[1] = val
	)
	_add_slider(parent, Lang.t("vol_ew"), 0.0, 2.0, 0.1, sim.spawner.dir_traffic_mult[2], "x", touch, func(val: float):
		sim.spawner.dir_traffic_mult[2] = val
	)
	_add_slider(parent, Lang.t("vol_we"), 0.0, 2.0, 0.1, sim.spawner.dir_traffic_mult[3], "x", touch, func(val: float):
		sim.spawner.dir_traffic_mult[3] = val
	)
	_add_slider(parent, Lang.t("ratio_left"), 0.0, 60.0, 2.0, sim.spawner.left_turn_ratio * 100.0, "%", touch, func(val: float):
		sim.spawner.left_turn_ratio = val / 100.0
	)
	_add_slider(parent, Lang.t("ratio_right"), 0.0, 50.0, 2.0, sim.spawner.right_turn_ratio * 100.0, "%", touch, func(val: float):
		sim.spawner.right_turn_ratio = val / 100.0
	)

func _populate_signal_controls(parent: VBoxContainer, touch: bool) -> void:
	var btn_h := 42 if touch else 32
	var fsz := 14 if touch else 13
	var sec := Lang.t("unit_sec")

	if sim.intersection_type == RoadBuilder.IntersectionType.ROUNDABOUT:
		var note := Label.new()
		note.text = Lang.t("sig_disabled_rotary")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", fsz)
		note.add_theme_color_override("font_color", Color(0.98, 0.82, 0.36))
		parent.add_child(note)
		return

	var mode_opt := OptionButton.new()
	mode_opt.custom_minimum_size.y = btn_h
	mode_opt.add_theme_font_size_override("font_size", fsz)
	mode_opt.add_item(Lang.t("mode_2p"), TrafficController.SignalMode.TWO_PHASE)
	mode_opt.add_item(Lang.t("mode_4p"), TrafficController.SignalMode.FOUR_PHASE)
	mode_opt.add_item(Lang.t("mode_ai"), TrafficController.SignalMode.SMART_ADAPTIVE)
	mode_opt.add_item(Lang.t("mode_flash"), TrafficController.SignalMode.FLASHING_YELLOW)
	mode_opt.add_item(Lang.t("mode_red"), TrafficController.SignalMode.ALL_RED)
	var cur_idx := mode_opt.get_item_index(int(sim.traffic_ctrl.mode))
	if cur_idx >= 0:
		mode_opt.select(cur_idx)
	mode_opt.item_selected.connect(func(idx: int):
		var id := mode_opt.get_item_id(idx)
		sim.traffic_ctrl.set_mode(id as TrafficController.SignalMode)
	)
	parent.add_child(mode_opt)

	_add_slider(parent, Lang.t("dur_ns"), 2.0, 20.0, 0.5, sim.traffic_ctrl.ns_green_duration, sec, touch, func(val: float):
		sim.traffic_ctrl.ns_green_duration = val
	)
	_add_slider(parent, Lang.t("dur_ew"), 2.0, 20.0, 0.5, sim.traffic_ctrl.ew_green_duration, sec, touch, func(val: float):
		sim.traffic_ctrl.ew_green_duration = val
	)
	_add_slider(parent, Lang.t("dur_left"), 2.0, 12.0, 0.5, sim.traffic_ctrl.left_green_duration, sec, touch, func(val: float):
		sim.traffic_ctrl.left_green_duration = val
	)
	_add_slider(parent, Lang.t("dur_yellow"), 1.0, 5.0, 0.5, sim.traffic_ctrl.yellow_duration, sec, touch, func(val: float):
		sim.traffic_ctrl.yellow_duration = val
	)

	var next_phase_btn := Button.new()
	next_phase_btn.text = Lang.t("btn_next_phase")
	_style_button(next_phase_btn, false, btn_h, fsz)
	next_phase_btn.pressed.connect(func(): sim.traffic_ctrl.force_next_phase())
	parent.add_child(next_phase_btn)

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	parent.add_child(lbl)

func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, init_v: float, suffix: String, touch: bool, cb: Callable) -> void:
	var fsz := 14 if touch else 12
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3 if touch else 2)
	parent.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", fsz)
	head.add_child(l)

	var val_lbl := Label.new()
	val_lbl.text = "%.1f%s" % [init_v, suffix]
	val_lbl.add_theme_font_size_override("font_size", fsz)
	val_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.44))
	head.add_child(val_lbl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.custom_minimum_size.y = 32 if touch else 20
	sl.add_theme_stylebox_override("slider", _style_slider_bg)
	sl.add_theme_stylebox_override("grabber_area", _style_slider_fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", _style_slider_fill)
	sl.value_changed.connect(func(v: float):
		val_lbl.text = "%.1f%s" % [v, suffix]
		cb.call(v)
	)
	row.add_child(sl)

func _update_lane_checkbox_visibility() -> void:
	var max_l := maxi(sim.spawner.ns_lanes, sim.spawner.ew_lanes)
	for i in range(lane_checkboxes.size()):
		lane_checkboxes[i].visible = (i < max_l)

func _on_toggle_pause() -> void:
	sim.paused = not sim.paused
	if pause_btn:
		if _is_mobile:
			pause_btn.text = "▶" if sim.paused else "⏸"
			_style_button(pause_btn, sim.paused, 34, 15)
		else:
			pause_btn.text = Lang.t("resume") if sim.paused else Lang.t("pause")
			_style_button(pause_btn, sim.paused, 30, 12)

func _refresh_metrics() -> void:
	if sim == null or lbl_phase == null:
		return
	var m := sim.get_metrics()
	var t_rem: float = m["phase_time"]
	if t_rem > 0.0:
		lbl_phase.text = Lang.t("hud_signal_t") % [m["phase"], t_rem]
	else:
		lbl_phase.text = Lang.t("hud_signal") % m["phase"]

	var is_em: bool = m["emergency"]
	lbl_phase.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36) if is_em else Color(0.55, 0.88, 1.0))

	if _is_mobile:
		if lbl_counts:
			lbl_counts.text = Lang.t("hud_mobile_stats") % [
				m["active"], m["waiting"], m["passed"], m["throughput"], m["avg_wait"]
			]
	else:
		if lbl_counts:
			lbl_counts.text = Lang.t("hud_counts_pc") % [m["active"], m["waiting"]]
		if lbl_perf:
			lbl_perf.text = Lang.t("hud_perf_pc") % [
				m["passed"], m["throughput"], m["avg_wait"]
			]
