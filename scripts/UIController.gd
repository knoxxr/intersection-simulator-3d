extends Control

var sim: IntersectionMain

var panel_container: PanelContainer
var toggle_panel_btn: Button
var lane_checkboxes: Array[CheckBox] = []
var pause_btn: Button

# Telemetry labels
var lbl_phase: Label
var lbl_counts: Label
var lbl_perf: Label

var _ui_refresh_timer: float = 0.0

func bind_simulation(main_sim: IntersectionMain) -> void:
	sim = main_sim
	_build_ui()

func _process(delta: float) -> void:
	if sim == null:
		return
	_ui_refresh_timer += delta
	if _ui_refresh_timer >= 0.15:
		_ui_refresh_timer = 0.0
		_refresh_metrics()

func _make_panel_style(bg: Color, border: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _build_ui() -> void:
	# Clean previous children if any
	for c in get_children():
		c.queue_free()

	var dark_bg := Color(0.08, 0.10, 0.14, 0.86)
	var border_col := Color(0.28, 0.35, 0.46, 0.75)

	# 1. Left Toggle Button (for collapsing panel)
	toggle_panel_btn = Button.new()
	toggle_panel_btn.text = "◀ 패널 접기"
	toggle_panel_btn.position = Vector2(14, 12)
	toggle_panel_btn.size = Vector2(110, 30)
	toggle_panel_btn.pressed.connect(_on_toggle_panel)
	add_child(toggle_panel_btn)

	# 2. Left Control Panel (Scrollable)
	panel_container = PanelContainer.new()
	panel_container.position = Vector2(14, 48)
	panel_container.custom_minimum_size = Vector2(310, 0)
	panel_container.anchor_bottom = 1.0
	panel_container.offset_bottom = -14
	panel_container.offset_right = 324
	panel_container.add_theme_stylebox_override("panel", _make_panel_style(dark_bg, border_col, 10))
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

	# Title
	var title := Label.new()
	title.text = "3D 교차로 교통 시뮬레이터"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	vbox.add_child(title)

	# --- Section 1: Simulation & Camera Controls ---
	_add_section_header(vbox, "시뮬레이션 & 카메라")

	var sim_row := HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 6)
	vbox.add_child(sim_row)

	pause_btn = Button.new()
	pause_btn.text = "일시정지"
	pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_btn.pressed.connect(_on_toggle_pause)
	sim_row.add_child(pause_btn)

	var reset_btn := Button.new()
	reset_btn.text = "차량 초기화"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(func(): sim.reset_simulation())
	sim_row.add_child(reset_btn)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	vbox.add_child(speed_row)
	var sp_lbl := Label.new()
	sp_lbl.text = "배속:"
	sp_lbl.add_theme_font_size_override("font_size", 13)
	speed_row.add_child(sp_lbl)
	for sp in [0.5, 1.0, 2.0, 4.0]:
		var b := Button.new()
		b.text = "%sx" % str(sp)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): sim.sim_speed = sp)
		speed_row.add_child(b)

	var cam_row := HBoxContainer.new()
	cam_row.add_theme_constant_override("separation", 4)
	vbox.add_child(cam_row)
	var cam_iso := Button.new()
	cam_iso.text = "3D 시점"
	cam_iso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam_iso.pressed.connect(func(): sim.orbit_camera.set_preset_iso())
	cam_row.add_child(cam_iso)

	var cam_top := Button.new()
	cam_top.text = "탑뷰"
	cam_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam_top.pressed.connect(func(): sim.orbit_camera.set_preset_top())
	cam_row.add_child(cam_top)

	var cam_low := Button.new()
	cam_low.text = "근접 시점"
	cam_low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam_low.pressed.connect(func(): sim.orbit_camera.set_preset_street())
	cam_row.add_child(cam_low)

	# --- Section 2: Lane Controls ---
	_add_section_header(vbox, "차선 설정 (실시간 반영)")

	var lane_cnt_row := HBoxContainer.new()
	lane_cnt_row.add_theme_constant_override("separation", 4)
	vbox.add_child(lane_cnt_row)
	var lc_lbl := Label.new()
	lc_lbl.text = "편도 차선:"
	lc_lbl.add_theme_font_size_override("font_size", 13)
	lane_cnt_row.add_child(lc_lbl)
	for cnt in [1, 2, 3]:
		var lb := Button.new()
		lb.text = "%d차선" % cnt
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.pressed.connect(func():
			sim.set_lane_count(cnt)
			_update_lane_checkbox_visibility(cnt)
		)
		lane_cnt_row.add_child(lb)

	var lane_open_row := HBoxContainer.new()
	lane_open_row.add_theme_constant_override("separation", 6)
	vbox.add_child(lane_open_row)
	lane_checkboxes.clear()
	var lane_names := ["1차선(내)", "2차선", "3차선(외)"]
	for idx in range(3):
		var cb := CheckBox.new()
		cb.text = lane_names[idx]
		cb.button_pressed = true
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(pressed: bool): sim.set_lane_enabled(idx, pressed))
		lane_open_row.add_child(cb)
		lane_checkboxes.append(cb)
	_update_lane_checkbox_visibility(sim.spawner.lane_count)

	var dir_open_row := HBoxContainer.new()
	dir_open_row.add_theme_constant_override("separation", 4)
	vbox.add_child(dir_open_row)
	var dir_lbl := Label.new()
	dir_lbl.text = "진입:"
	dir_lbl.add_theme_font_size_override("font_size", 12)
	dir_open_row.add_child(dir_lbl)
	var dir_names := ["북", "남", "동", "서"]
	for a in range(4):
		var dcb := CheckBox.new()
		dcb.text = dir_names[a]
		dcb.button_pressed = true
		dcb.add_theme_font_size_override("font_size", 12)
		dcb.toggled.connect(func(pressed: bool): sim.set_approach_enabled(a, pressed))
		dir_open_row.add_child(dcb)

	# --- Section 3: Traffic Volume & Turn Ratios ---
	_add_section_header(vbox, "트래픽 양 & 회전 비율")

	_add_slider(vbox, "전체 교통량", 0.0, 3.0, 0.1, sim.spawner.global_traffic_rate, "x", func(val: float):
		sim.spawner.global_traffic_rate = val
	)
	_add_slider(vbox, "북→남 통행량", 0.0, 2.0, 0.1, 1.0, "x", func(val: float): sim.spawner.dir_traffic_mult[0] = val)
	_add_slider(vbox, "남→북 통행량", 0.0, 2.0, 0.1, 1.0, "x", func(val: float): sim.spawner.dir_traffic_mult[1] = val)
	_add_slider(vbox, "동→서 통행량", 0.0, 2.0, 0.1, 1.0, "x", func(val: float): sim.spawner.dir_traffic_mult[2] = val)
	_add_slider(vbox, "서→동 통행량", 0.0, 2.0, 0.1, 1.0, "x", func(val: float): sim.spawner.dir_traffic_mult[3] = val)

	_add_slider(vbox, "좌회전 비율", 0.0, 60.0, 2.0, sim.spawner.left_turn_ratio * 100.0, "%", func(val: float):
		sim.spawner.left_turn_ratio = val / 100.0
	)
	_add_slider(vbox, "우회전 비율", 0.0, 50.0, 2.0, sim.spawner.right_turn_ratio * 100.0, "%", func(val: float):
		sim.spawner.right_turn_ratio = val / 100.0
	)

	# --- Section 4: Traffic Signal Controls ---
	_add_section_header(vbox, "신호등 제어 & 시나리오")

	var mode_opt := OptionButton.new()
	mode_opt.add_item("2현시 (남북/동서 교대)", TrafficController.SignalMode.TWO_PHASE)
	mode_opt.add_item("4현시 (좌회전 보호 신호)", TrafficController.SignalMode.FOUR_PHASE)
	mode_opt.add_item("황색 점멸 (주의 서행)", TrafficController.SignalMode.FLASHING_YELLOW)
	mode_opt.add_item("전체 적색 (정체 테스트)", TrafficController.SignalMode.ALL_RED)
	mode_opt.item_selected.connect(func(idx: int):
		var id := mode_opt.get_item_id(idx)
		sim.traffic_ctrl.set_mode(id as TrafficController.SignalMode)
	)
	vbox.add_child(mode_opt)

	_add_slider(vbox, "남북 녹색 시간", 2.0, 20.0, 0.5, sim.traffic_ctrl.ns_green_duration, "초", func(val: float):
		sim.traffic_ctrl.ns_green_duration = val
	)
	_add_slider(vbox, "동서 녹색 시간", 2.0, 20.0, 0.5, sim.traffic_ctrl.ew_green_duration, "초", func(val: float):
		sim.traffic_ctrl.ew_green_duration = val
	)
	_add_slider(vbox, "좌회전 보호 시간", 2.0, 12.0, 0.5, sim.traffic_ctrl.left_green_duration, "초", func(val: float):
		sim.traffic_ctrl.left_green_duration = val
	)
	_add_slider(vbox, "황색 신호 시간", 1.0, 5.0, 0.5, sim.traffic_ctrl.yellow_duration, "초", func(val: float):
		sim.traffic_ctrl.yellow_duration = val
	)

	var next_phase_btn := Button.new()
	next_phase_btn.text = "다음 신호 즉시 전환"
	next_phase_btn.pressed.connect(func(): sim.traffic_ctrl.force_next_phase())
	vbox.add_child(next_phase_btn)

	# 3. Top-Right Real-Time Telemetry HUD
	var hud := PanelContainer.new()
	hud.anchor_left = 1.0
	hud.anchor_right = 1.0
	hud.offset_left = -305
	hud.offset_right = -14
	hud.offset_top = 12
	hud.offset_bottom = 128
	hud.add_theme_stylebox_override("panel", _make_panel_style(dark_bg, border_col, 10))
	add_child(hud)

	var hud_v := VBoxContainer.new()
	hud_v.add_theme_constant_override("separation", 5)
	hud.add_child(hud_v)

	var hud_title := Label.new()
	hud_title.text = "실시간 교차로 현황"
	hud_title.add_theme_font_size_override("font_size", 14)
	hud_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hud_v.add_child(hud_title)

	lbl_phase = Label.new()
	lbl_phase.text = "신호: -"
	lbl_phase.add_theme_font_size_override("font_size", 13)
	hud_v.add_child(lbl_phase)

	lbl_counts = Label.new()
	lbl_counts.text = "차량: 0대 (대기 0대)"
	lbl_counts.add_theme_font_size_override("font_size", 13)
	hud_v.add_child(lbl_counts)

	lbl_perf = Label.new()
	lbl_perf.text = "통과: 0대 | 처리량: 0/분 | 대기: 0.0초"
	lbl_perf.add_theme_font_size_override("font_size", 12)
	lbl_perf.add_theme_color_override("font_color", Color(0.84, 0.90, 0.96))
	hud_v.add_child(lbl_perf)

	# 4. Bottom-Right Controls Hint
	var hint := PanelContainer.new()
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -270
	hint.offset_right = -14
	hint.offset_top = -42
	hint.offset_bottom = -12
	hint.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.08, 0.11, 0.72), border_col, 8))
	add_child(hint)

	var hint_lbl := Label.new()
	hint_lbl.text = "마우스 드래그: 회전 | 휠: 확대/축소"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	hint.add_child(hint_lbl)

func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	parent.add_child(lbl)

func _add_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, init_v: float, suffix: String, cb: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)

	var l := Label.new()
	l.text = label_text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 12)
	head.add_child(l)

	var val_lbl := Label.new()
	val_lbl.text = "%.1f%s" % [init_v, suffix]
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	head.add_child(val_lbl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.value_changed.connect(func(v: float):
		val_lbl.text = "%.1f%s" % [v, suffix]
		cb.call(v)
	)
	row.add_child(sl)

func _update_lane_checkbox_visibility(cnt: int) -> void:
	for i in range(lane_checkboxes.size()):
		lane_checkboxes[i].visible = (i < cnt)

func _on_toggle_panel() -> void:
	panel_container.visible = not panel_container.visible
	toggle_panel_btn.text = "◀ 패널 접기" if panel_container.visible else "▶ 제어 패널"

func _on_toggle_pause() -> void:
	sim.paused = not sim.paused
	pause_btn.text = "재개" if sim.paused else "일시정지"

func _refresh_metrics() -> void:
	var m := sim.get_metrics()
	var t_rem: float = m["phase_time"]
	if t_rem > 0.0:
		lbl_phase.text = "신호: %s (%.1f초)" % [m["phase"], t_rem]
	else:
		lbl_phase.text = "신호: %s" % m["phase"]
	lbl_counts.text = "주행 중: %d대 | 정차 대기: %d대" % [m["active"], m["waiting"]]
	lbl_perf.text = "통과: %d대 | %.0f대/분 | 평균대기 %.1f초" % [m["passed"], m["throughput"], m["avg_wait"]]
