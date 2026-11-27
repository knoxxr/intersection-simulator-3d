extends RefCounted
class_name Lang

# Default language: English ("en"), switchable to Korean ("ko") in real time
static var current: String = "en"

const STRINGS: Dictionary = {
	"en": {
		"app_title": "3D Intersection Traffic Simulator",
		"panel_hide": "◀ Hide Panel",
		"panel_show": "▶ Controls",
		"mobile_ui": "Mobile UI",
		"pc_ui": "Switch to Desktop (PC) UI",
		"settings": "⚙ Menu",
		"close": "✕ Close",
		"lang_btn": "한국어",

		# Mobile Tabs
		"tab_presets": "Presets",
		"tab_lanes": "Lanes",
		"tab_traffic": "Traffic",
		"tab_signals": "Signals",
		"tab_control": "Control",

		# Floating mobile quick buttons
		"quick_amb": "EMS",
		"quick_view": "View",
		"quick_sig": "Next",

		# Section headers
		"sec_presets": "Presets & Emergency",
		"sec_sim_cam": "Simulation · Camera · Lighting",
		"sec_lanes": "Intersection Type & Lanes (1–10)",
		"sec_traffic": "Traffic Volume & Turn Mix",
		"sec_signals": "Traffic Signals & AI Adaptive",

		# Intersection Types
		"type_lbl": "Type:",
		"type_signal": "Signal",
		"type_roundabout": "Rotary",
		"type_underpass": "Underpass",
		"type_overpass": "Overpass",
		"type_tri_level": "Overpass + Underpass (3-Level)",

		# Scenarios & Ambulance
		"btn_ambulance": "🚑 Dispatch Ambulance (Preempt)",
		"preset_normal": "Balanced",
		"preset_rush": "Rush Hour (AI)",
		"preset_left": "Heavy Left",
		"preset_const": "Lane Closure",
		"preset_roundabout": "Roundabout",
		"preset_underpass": "Underpass",
		"preset_overpass": "Overpass",
		"preset_tri_level": "3-Level Stack",
		"preset_mega10": "10-Lane Mega",

		# Simulation & Camera & Lighting
		"pause": "Pause",
		"resume": "Resume",
		"reset_cars": "Clear Cars",
		"speed_lbl": "Speed:",
		"cam_3d": "3D",
		"cam_wide": "Wide",
		"cam_top": "Top",
		"cam_low": "Close",
		"time_lbl": "Light:",
		"time_day": "Day",
		"time_sunset": "Sunset",
		"time_night": "Night",
		"cong_overlay": "Road Congestion Colors (G/Y/R)",
		"touch_tip": "Tip: 1-finger drag (orbit) · 2-finger pinch (zoom)",
		"desktop_hint": "Drag: Orbit | Scroll: Zoom",

		# Lanes (1 to 10)
		"ns_lanes": "N-S Lanes (each way)",
		"ew_lanes": "E-W Lanes (each way)",
		"lane_unit": " lanes",
		"lane_open_lbl": "Inner Lanes Open (uncheck to place cones):",
		"lane_1": "Lane 1",
		"lane_2": "Lane 2",
		"lane_3": "Lane 3",
		"approach_lbl": "Entry:",
		"dir_n": "N",
		"dir_s": "S",
		"dir_e": "E",
		"dir_w": "W",

		# Traffic Sliders
		"vol_global": "Global Traffic",
		"vol_ns": "N → S Volume",
		"vol_sn": "S → N Volume",
		"vol_ew": "E → W Volume",
		"vol_we": "W → E Volume",
		"ratio_left": "Left Turn Ratio",
		"ratio_right": "Right Turn Ratio",

		# Signals
		"sig_disabled_rotary": "Roundabout active (unsignalized yield-on-entry)",
		"sig_disabled_underpass": "Grade-separated underpass (1-lane free-flow, no signals)",
		"sig_disabled_overpass": "Grade-separated overpass (1-lane free-flow, no signals)",
		"sig_disabled_tri_level": "3-Level Overpass + Underpass (free-flow, no signals)",
		"mode_2p": "2-Phase (N-S / E-W)",
		"mode_4p": "4-Phase (Protected Left)",
		"mode_ai": "Smart Adaptive (AI Queue)",
		"mode_flash": "Flashing Yellow (Caution)",
		"mode_red": "All Red (Gridlock Test)",
		"dur_ns": "N-S Green",
		"dur_ew": "E-W Green",
		"dur_left": "Left Green",
		"dur_yellow": "Yellow",
		"unit_sec": "s",
		"btn_next_phase": "Force Next Signal Phase",

		# HUD & Metrics
		"hud_title": "Live Intersection Metrics",
		"hud_signal_t": "Signal: %s (%.1fs)",
		"hud_signal": "Signal: %s",
		"hud_counts_pc": "Active: %d | Waiting: %d",
		"hud_perf_pc": "Passed: %d | %.0f/min | Avg Wait %.1fs",
		"hud_mobile_stats": "Active %d | Wait %d | Pass %d (%.0f/m) | Avg %.1fs",
		"graph_tp": "Throughput/m",
		"graph_wait": "Waiting Cars",
		"graph_now": "Now",

		# Signal Phase Labels
		"axis_ns": "N-S",
		"axis_ew": "E-W",
		"ph_roundabout": "Roundabout (Yield on Entry)",
		"ph_roundabout_ems": "🚑 Roundabout — EMS Priority",
		"ph_underpass_free": "Underpass (Free-Flow Grade Separated)",
		"ph_overpass_free": "Overpass (Free-Flow Grade Separated)",
		"ph_tri_level_free": "3-Level Overpass + Underpass (Free-Flow)",
		"ph_emerg": "🚑 Emergency Preempt (%s)",
		"ph_all_red": "All Red (Emergency Stop)",
		"ph_flash": "Flashing Yellow (Yield)",
		"ph_ai_ns_g": "AI N-S Green (%d:%d)",
		"ph_ai_ns_y": "AI N-S Yellow",
		"ph_ai_ew_g": "AI E-W Green (%d:%d)",
		"ph_ai_ew_y": "AI E-W Yellow",
		"ph_clear": "All Red (Clearance)",
		"ph_ns_g": "N-S Green",
		"ph_ns_y": "N-S Yellow",
		"ph_ew_g": "E-W Green",
		"ph_ew_y": "E-W Yellow",
		"ph_ns_st_g": "N-S Straight/Right Green",
		"ph_ns_st_y": "N-S Straight Yellow",
		"ph_ns_lt_g": "N-S Protected Left",
		"ph_ns_lt_y": "N-S Left Yellow",
		"ph_ew_st_g": "E-W Straight/Right Green",
		"ph_ew_st_y": "E-W Straight Yellow",
		"ph_ew_lt_g": "E-W Protected Left",
		"ph_ew_lt_y": "E-W Left Yellow"
	},
	"ko": {
		"app_title": "3D 교차로 교통 시뮬레이터",
		"panel_hide": "◀ 패널 접기",
		"panel_show": "▶ 제어 패널",
		"mobile_ui": "모바일 UI",
		"pc_ui": "데스크톱(PC) UI로 전환",
		"settings": "⚙ 설정",
		"close": "✕ 닫기",
		"lang_btn": "EN",

		# Mobile Tabs
		"tab_presets": "시나리오",
		"tab_lanes": "차선",
		"tab_traffic": "트래픽",
		"tab_signals": "신호등",
		"tab_control": "제어",

		# Floating mobile quick buttons
		"quick_amb": "구급",
		"quick_view": "시점",
		"quick_sig": "신호",

		# Section headers
		"sec_presets": "시나리오 프리셋 & 긴급출동",
		"sec_sim_cam": "시뮬레이션 · 카메라 · 시간대",
		"sec_lanes": "교차로 형태 & 차선 (1~10차선)",
		"sec_traffic": "트래픽 양 & 회전 비율",
		"sec_signals": "신호등 제어 & AI 감응",

		# Intersection Types
		"type_lbl": "형태:",
		"type_signal": "신호등",
		"type_roundabout": "로터리",
		"type_underpass": "지하차도",
		"type_overpass": "고가교",
		"type_tri_level": "고가교 + 지하차도 (3층 입체)",

		# Scenarios & Ambulance
		"btn_ambulance": "🚑 구급차 긴급 출동 (우선신호)",
		"preset_normal": "평시 균형",
		"preset_rush": "출근 러시(AI)",
		"preset_left": "좌회전 정체",
		"preset_const": "1차선 공사",
		"preset_roundabout": "로터리 회전",
		"preset_underpass": "지하차도",
		"preset_overpass": "고가교",
		"preset_tri_level": "고가+지하 3층",
		"preset_mega10": "10차선 대로",

		# Simulation & Camera & Lighting
		"pause": "일시정지",
		"resume": "재개",
		"reset_cars": "차량 초기화",
		"speed_lbl": "배속:",
		"cam_3d": "3D",
		"cam_wide": "멀리",
		"cam_top": "탑뷰",
		"cam_low": "근접",
		"time_lbl": "시간대:",
		"time_day": "낮",
		"time_sunset": "노을",
		"time_night": "야간",
		"cong_overlay": "도로 혼잡도 색상 표시 (초록/노랑/빨강)",
		"touch_tip": "팁: 한 손가락 드래그(회전) · 두 손가락 핀치(확대/축소)",
		"desktop_hint": "마우스 드래그: 회전 | 휠: 확대/축소",

		# Lanes (1 to 10)
		"ns_lanes": "남북 차선 (편도)",
		"ew_lanes": "동서 차선 (편도)",
		"lane_unit": "차선",
		"lane_open_lbl": "내측 차선 개방 (해제 시 공사 라바콘):",
		"lane_1": "1차선",
		"lane_2": "2차선",
		"lane_3": "3차선",
		"approach_lbl": "진입:",
		"dir_n": "북",
		"dir_s": "남",
		"dir_e": "동",
		"dir_w": "서",

		# Traffic Sliders
		"vol_global": "전체 교통량",
		"vol_ns": "북→남 통행량",
		"vol_sn": "남→북 통행량",
		"vol_ew": "동→서 통행량",
		"vol_we": "서→동 통행량",
		"ratio_left": "좌회전 비율",
		"ratio_right": "우회전 비율",

		# Signals
		"sig_disabled_rotary": "로터리 모드 활성화 중 (무신호 회전 우선 양보)",
		"sig_disabled_underpass": "1차선 입체교차 지하차도 (무신호 연속 주행)",
		"sig_disabled_overpass": "1차선 입체교차 고가교 (무신호 연속 주행)",
		"sig_disabled_tri_level": "고가교+지하차도 3층 입체 (무신호 연속 주행)",
		"mode_2p": "2현시 (남북/동서 교대)",
		"mode_4p": "4현시 (좌회전 보호 신호)",
		"mode_ai": "스마트 감응 (AI 대기열 자동 제어)",
		"mode_flash": "황색 점멸 (주의 서행)",
		"mode_red": "전체 적색 (정체 테스트)",
		"dur_ns": "남북 녹색 시간",
		"dur_ew": "동서 녹색 시간",
		"dur_left": "좌회전 보호 시간",
		"dur_yellow": "황색 신호 시간",
		"unit_sec": "초",
		"btn_next_phase": "다음 신호 즉시 전환",

		# HUD & Metrics
		"hud_title": "실시간 교차로 현황",
		"hud_signal_t": "신호: %s (%.1f초)",
		"hud_signal": "신호: %s",
		"hud_counts_pc": "주행 중: %d대 | 정차 대기: %d대",
		"hud_perf_pc": "통과: %d대 | %.0f대/분 | 평균대기 %.1f초",
		"hud_mobile_stats": "주행 %d | 대기 %d | 통과 %d (%.0f/분) | 평균 %.1f초",
		"graph_tp": "분당 처리량",
		"graph_wait": "대기 차량",
		"graph_now": "현재",

		# Signal Phase Labels
		"axis_ns": "남북",
		"axis_ew": "동서",
		"ph_roundabout": "로터리 회전교차로 (회전차량 우선)",
		"ph_roundabout_ems": "🚑 로터리 — 구급차 통과 중",
		"ph_underpass_free": "지하차도 입체교차 (무신호 통과)",
		"ph_overpass_free": "고가교 입체교차 (무신호 통과)",
		"ph_tri_level_free": "고가+지하 3층 입체교차 (무신호 통과)",
		"ph_emerg": "🚑 긴급 우선신호 (%s 통과)",
		"ph_all_red": "전체 적색 (긴급 정지)",
		"ph_flash": "황색 점멸 (주의 서행)",
		"ph_ai_ns_g": "AI감응 남북 녹색 (%d:%d)",
		"ph_ai_ns_y": "AI감응 남북 황색",
		"ph_ai_ew_g": "AI감응 동서 녹색 (%d:%d)",
		"ph_ai_ew_y": "AI감응 동서 황색",
		"ph_clear": "전방 적색 (정리)",
		"ph_ns_g": "남북 직진/회전 녹색",
		"ph_ns_y": "남북 황색",
		"ph_ew_g": "동서 직진/회전 녹색",
		"ph_ew_y": "동서 황색",
		"ph_ns_st_g": "남북 직진/우회전 녹색",
		"ph_ns_st_y": "남북 직진 황색",
		"ph_ns_lt_g": "남북 좌회전 보호 신호",
		"ph_ns_lt_y": "남북 좌회전 황색",
		"ph_ew_st_g": "동서 직진/우회전 녹색",
		"ph_ew_st_y": "동서 직진 황색",
		"ph_ew_lt_g": "동서 좌회전 보호 신호",
		"ph_ew_lt_y": "동서 좌회전 황색"
	}
}

static func t(key: String) -> String:
	var table: Dictionary = STRINGS.get(current, STRINGS["en"])
	if table.has(key):
		return str(table[key])
	return str(STRINGS["en"].get(key, key))

static func toggle() -> void:
	current = "ko" if current == "en" else "en"
	if OS.has_feature("web"):
		var title := t("app_title").replace("'", "\\'")
		JavaScriptBridge.eval("document.title = '%s';" % title)
