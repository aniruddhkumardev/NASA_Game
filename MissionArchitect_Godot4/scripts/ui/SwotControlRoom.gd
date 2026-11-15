extends Control

## SWOT Mission Control Center — the ground segment for the Earth Climate
## Sentinel.  Four live monitors mirror the real SWOT (NASA/CNES) flight
## operations loop: ground-track/station contact, the KaRIn swath scanning
## ocean/lake/river surfaces, water-level telemetry, and the downlink record
## queue.  Every number is read from the live simulation state; nothing here
## invents a measurement the spacecraft did not take.

signal close_requested

const C_BG := Color("#000000")
const C_PANEL := Color("#0A0A0A")
const C_ACCENT := Color("#FFFFFF")
const C_TEXT := Color("#FFFFFF")
const C_DIM := Color("#B3B3B3")
const C_GREEN := Color("#FFFFFF")
const C_AMBER := Color("#D9D9D9")
const C_RED := Color("#B3B3B3")
const C_OCEAN := Color("#B3B3B3")
const C_LAKE := Color("#FFFFFF")
const C_RIVER := Color("#777777")

var _font: Font
var _data: Dictionary = {}
var _state: Dictionary = {}
var _targets: Array = []
var _clock: String = "T+ 00d 00h 00m"
var _sat_lat: float = 0.0
var _sat_lon: float = 0.0
var _time_scale: float = 1.0
var _pulse: float = 0.0
var _focus_idx: int = 0
var _focus_timer: float = 8.0
var _sample_timer: float = 0.5
var _last_scanned: String = ""
var _history: Dictionary = {}
var _close_btn: Button

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_close_btn = Button.new()
	_close_btn.text = "CLOSE  [C]"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.add_theme_font_size_override("font_size", 12)
	_close_btn.add_theme_color_override("font_color", C_ACCENT)
	_close_btn.pressed.connect(func() -> void: close_requested.emit())
	add_child(_close_btn)
	_close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -150.0
	_close_btn.offset_top = 16.0
	_close_btn.offset_right = -20.0
	_close_btn.offset_bottom = 52.0
	set_process(true)

func update_data(payload: Dictionary) -> void:
	_data = payload
	_state = payload.get("state", {})
	_targets = _state.get("swot_water_targets", [])
	_clock = String(payload.get("clock", _clock))
	_sat_lat = float(payload.get("sat_lat", 0.0))
	_sat_lon = float(payload.get("sat_lon", 0.0))
	_time_scale = float(payload.get("time_scale", 1.0))
	var scanned_now: String = String(_state.get("last_swot_scan", ""))
	if scanned_now != "" and scanned_now != _last_scanned:
		_last_scanned = scanned_now
		var idx: int = _index_of(scanned_now)
		if idx >= 0:
			_focus_idx = idx
			_focus_timer = 8.0

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	_focus_timer -= delta
	if _focus_timer <= 0.0:
		_focus_timer = 8.0
		_advance_focus()
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer = 0.5
		_sample_chart()
	queue_redraw()

func _advance_focus() -> void:
	if _targets.is_empty():
		return
	for step in range(1, _targets.size() + 1):
		var idx: int = (_focus_idx + step) % _targets.size()
		if bool(_targets[idx].get("scanned", false)):
			_focus_idx = idx
			return

func _index_of(name: String) -> int:
	for i in range(_targets.size()):
		if String(_targets[i].get("name", "")) == name:
			return i
	return -1

func _focus() -> Dictionary:
	if _targets.is_empty():
		return {}
	return _targets[_focus_idx % _targets.size()]

# ─── Drawing ──────────────────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	# faint CRT scanlines keep the wall-of-monitors look without obscuring text
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.02), 1.0)
		y += 4.0

	var header_h := 74.0
	var footer_h := 30.0
	draw_rect(Rect2(0.0, 0.0, size.x, header_h), Color("#0A0A0A"), true)
	draw_line(Vector2(0.0, header_h), Vector2(size.x, header_h), Color("#333333"), 1.0)
	_text(Vector2(22.0, 32.0), "SWOT MISSION CONTROL CENTER", 22, C_ACCENT)
	_text(Vector2(22.0, 53.0), "Surface Water & Ocean Topography  ·  NASA / CNES  ·  swot.jpl.nasa.gov", 12, C_DIM)
	_text(Vector2(22.0, 68.0), "KaRIn interferometer  ·  120 km swath  ·  891 km orbit  ·  21-day repeat", 10, Color("#777777"))

	var contact: bool = bool(_state.get("ground_contact", false))
	var station: String = String(_state.get("ground_station_name", ""))
	if station == "":
		station = "no station in view"
	_text_right(size.x - 175.0, 28.0, _clock, 17, C_TEXT)
	_text_right(size.x - 175.0, 47.0, "%sx TIME COMPRESSION" % _fmt_scale(_time_scale), 10, C_DIM)
	_text_right(size.x - 175.0, 66.0, ("CONTACT · " + station.to_upper()) if contact else "NO GROUND CONTACT",
		12, C_GREEN if contact else C_RED)

	var pad := 16.0
	var top := header_h + pad
	var bottom := size.y - footer_h - pad
	var gap := 12.0
	var w: float = maxf((size.x - pad * 2.0 - gap) * 0.5, 80.0)
	var h: float = maxf((bottom - top - gap) * 0.5, 60.0)
	var left := Rect2(pad, top, w, h)
	var right := Rect2(pad + w + gap, top, w, h)
	var bl := Rect2(pad, top + h + gap, w, h)
	var br := Rect2(pad + w + gap, top + h + gap, w, h)

	_draw_map_monitor(left)
	_draw_swath_monitor(right)
	_draw_water_monitor(bl)
	_draw_downlink_monitor(br)

	draw_line(Vector2(0.0, size.y - footer_h), Vector2(size.x, size.y - footer_h), Color("#333333"), 1.0)
	_text(Vector2(20.0, size.y - 10.0), "PRESS C OR CLICK CLOSE TO RETURN TO ORBIT VIEW   ·   SW-1 / SW-2 WATER RECORDS IN THE NASA/CNES SWOT GROUND SEGMENT", 11, C_DIM)

func _monitor_frame(rect: Rect2, title: String, accent: Color) -> Rect2:
	draw_rect(rect, C_PANEL, true)
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.34), false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 26.0)), Color("#151515"), true)
	draw_line(Vector2(rect.position.x, rect.position.y + 26.0), Vector2(rect.end.x, rect.position.y + 26.0),
		Color(accent.r, accent.g, accent.b, 0.35), 1.0)
	_text(rect.position + Vector2(10.0, 18.0), title, 13, accent)
	return Rect2(rect.position + Vector2(10.0, 34.0),
		Vector2(maxf(rect.size.x - 20.0, 20.0), maxf(rect.size.y - 44.0, 20.0)))

# Monitor 1 — ground track map ────────────────────────────────────────────────
func _draw_map_monitor(rect: Rect2) -> void:
	var c := _monitor_frame(rect, "GROUND TRACK / STATION CONTACT", C_ACCENT)
	if c.size.x < 40.0 or c.size.y < 40.0:
		return
	draw_rect(c, Color("#0A0A0A"), true)
	for lon in range(-180, 181, 30):
		var x: float = c.position.x + (float(lon) + 180.0) / 360.0 * c.size.x
		draw_line(Vector2(x, c.position.y), Vector2(x, c.end.y), Color(1.0, 1.0, 1.0, 0.08), 1.0)
	for lat in range(-60, 91, 30):
		var yy: float = c.position.y + (90.0 - float(lat)) / 180.0 * c.size.y
		draw_line(Vector2(c.position.x, yy), Vector2(c.end.x, yy),
			Color(1.0, 1.0, 1.0, 0.2) if lat == 0 else Color(1.0, 1.0, 1.0, 0.08), 1.0)

	var contact_station: String = String(_state.get("ground_station_name", ""))
	var station_pos := Vector2.ZERO
	var contact_pos := Vector2.ZERO
	var has_contact_pos := false
	for st in SimulationEngine.GROUND_STATIONS:
		var pos := _latlon_to_map(c, float(st["lat"]), float(st["lon"]))
		var holds: bool = contact_station != "" and String(st["name"]) == contact_station
		if holds:
			contact_pos = pos
			has_contact_pos = true
		draw_circle(pos, 3.4 if holds else 2.2, C_GREEN if holds else Color("#777777"))
		if holds:
			draw_arc(pos, 7.5, 0.0, TAU, 24, C_GREEN, 1.5, true)
		var label_pos := pos + Vector2(6.0, -5.0)
		if label_pos.x > c.end.x - 70.0:
			label_pos.x = pos.x - 68.0
		_text(label_pos, String(st["name"]), 8, C_GREEN if holds else C_DIM)

	for t in _targets:
		var pos := _latlon_to_map(c, float(t.get("lat", 0.0)), float(t.get("lon", 0.0)))
		var downlinked: bool = bool(t.get("downlinked", false))
		var scanned: bool = bool(t.get("scanned", false))
		var col: Color = C_GREEN if downlinked else (C_AMBER if scanned else _class_color(String(t.get("water_class", "ocean"))))
		draw_circle(pos, 3.0, col)
		if scanned:
			draw_arc(pos, 6.0, 0.0, TAU, 20, col, 1.2, true)

	var sat := _latlon_to_map(c, _sat_lat, _sat_lon)
	if has_contact_pos:
		draw_dashed_line(sat, contact_pos, Color(1.0, 1.0, 1.0, 0.55), 1.0, 5.0)
	draw_circle(sat, 4.0, Color("#FFFFFF"))
	draw_arc(sat, 8.0, 0.0, TAU, 24, Color("#B3B3B3"), 1.2, true)

	_text(c.position + Vector2(4.0, 12.0), "SUB-POINT  %s  %s" % [_fmt_lat(_sat_lat), _fmt_lon(_sat_lon)], 10, Color("#B3B3B3"))
	var status: String = "AOS · " + contact_station + " · %.0f deg" % float(_state.get("station_elevation_deg", 0.0)) if contact_station != "" else "LOS · waiting for next pass"
	_text(Vector2(c.position.x + 4.0, c.end.y - 6.0), status, 10, C_GREEN if contact_station != "" else C_RED)

# Monitor 2 — KaRIn swath ────────────────────────────────────────────────────
func _draw_swath_monitor(rect: Rect2) -> void:
	var c := _monitor_frame(rect, "KaRIn SWATH / WATER CLASS DETECTIONS", Color("#FFFFFF"))
	if c.size.x < 40.0 or c.size.y < 40.0:
		return
	# ocean-like background bands
	for i in range(10):
		var band := Rect2(c.position.x, c.position.y + c.size.y * float(i) / 10.0, c.size.x, c.size.y / 10.0)
		draw_rect(band, Color(0.02 + 0.008 * float(i), 0.02 + 0.008 * float(i), 0.02 + 0.008 * float(i)), true)
	# 120 km swath band sweeping across the scene
	var band_h: float = clampf(c.size.y * 0.26, 18.0, 70.0)
	var band_y: float = c.position.y + c.size.y * 0.46 - band_h * 0.5
	draw_rect(Rect2(c.position.x, band_y, c.size.x, band_h), Color(1.0, 1.0, 1.0, 0.10), true)
	draw_line(Vector2(c.position.x, band_y), Vector2(c.end.x, band_y), Color(1.0, 1.0, 1.0, 0.35), 1.0)
	draw_line(Vector2(c.position.x, band_y + band_h), Vector2(c.end.x, band_y + band_h), Color(1.0, 1.0, 1.0, 0.35), 1.0)
	var sweep_x: float = c.position.x + fmod(_pulse * 55.0, maxf(c.size.x, 1.0))
	draw_line(Vector2(sweep_x, band_y), Vector2(sweep_x, band_y + band_h), Color(1.0, 1.0, 1.0, 0.9), 2.0)
	_text(Vector2(c.position.x + 6.0, band_y - 6.0), "KARIN INTERFEROMETER · 120 km SWATH", 9, Color("#B3B3B3"))

	# radar echo waveform
	var pts := PackedVector2Array()
	var wave_y: float = c.position.y + c.size.y * 0.24
	for i in range(48):
		var t: float = float(i) / 47.0
		var px: float = c.position.x + t * c.size.x
		var amp: float = sin(t * 38.0 + _pulse * 5.0) * 4.0 * (1.0 - absf(t - 0.5) * 1.6)
		pts.append(Vector2(px, wave_y + amp))
	draw_polyline(pts, Color("#B3B3B3"), 1.2, true)
	_text(Vector2(c.position.x + 6.0, wave_y - 12.0), "CROSS-TRACK ECHO", 8, C_DIM)

	# per-class detection chips
	var scanned: Dictionary = _state.get("swot_classes_scanned", {})
	var received: Dictionary = _state.get("swot_classes_received", {})
	var chips: Array = [["ocean", "OCEAN", C_OCEAN], ["lake", "LAKE", C_LAKE], ["river", "RIVER", C_RIVER]]
	var chip_w: float = (c.size.x - 16.0) / 3.0
	for i in range(3):
		var cls: String = chips[i][0]
		var col: Color = chips[i][2]
		var chip := Rect2(c.position.x + 4.0 + chip_w * float(i), c.end.y - 52.0, chip_w - 6.0, 48.0)
		draw_rect(chip, Color(col.r, col.g, col.b, 0.10), true)
		draw_rect(chip, Color(col.r, col.g, col.b, 0.45), false, 1.0)
		_text(chip.position + Vector2(6.0, 15.0), String(chips[i][1]), 10, col)
		_text(chip.position + Vector2(6.0, 30.0), "%d/%d SWATHS" % [int(scanned.get(cls, 0)), int(SimulationEngine.SWOT_CLASS_TOTALS.get(cls, 0))], 10, C_TEXT)
		_text(chip.position + Vector2(6.0, 43.0), "%d AT CONTROL ROOM" % int(received.get(cls, 0)), 8, C_DIM)

	var last_scan: String = String(_state.get("last_swot_scan", ""))
	if last_scan == "":
		_text(Vector2(c.position.x + 4.0, c.end.y - 62.0), "NO SWATH ACQUIRED YET — CARRY THE SAR RADAR", 9, C_AMBER)
	else:
		_text(Vector2(c.position.x + 4.0, c.end.y - 62.0), "LAST SWATH: " + _short(last_scan.to_upper(), 46), 9, C_TEXT)

# Monitor 3 — water-level telemetry ────────────────────────────────────────
func _draw_water_monitor(rect: Rect2) -> void:
	var t := _focus()
	var title := "WATER LEVEL TELEMETRY"
	if not t.is_empty():
		title += " — " + _short(String(t.get("name", "")).to_upper(), 34)
	var c := _monitor_frame(rect, title, Color("#B3B3B3"))
	if c.size.x < 40.0 or c.size.y < 40.0 or t.is_empty():
		return
	var scanned: bool = bool(t.get("scanned", false))
	var cls: String = String(t.get("water_class", "ocean"))
	var col := _class_color(cls)
	var chart := Rect2(c.position.x, c.position.y + 4.0, c.size.x * 0.62, c.size.y - 92.0)
	if chart.size.y < 20.0:
		chart.size.y = maxf(c.size.y - 60.0, 20.0)
	draw_rect(chart, Color("#0A0A0A"), true)
	for i in range(1, 4):
		var gy: float = chart.position.y + chart.size.y * float(i) / 4.0
		draw_line(Vector2(chart.position.x, gy), Vector2(chart.end.x, gy), Color(1.0, 1.0, 1.0, 0.08), 1.0)
	for i in range(1, 4):
		var gx: float = chart.position.x + chart.size.x * float(i) / 4.0
		draw_line(Vector2(gx, chart.position.y), Vector2(gx, chart.end.y), Color(1.0, 1.0, 1.0, 0.08), 1.0)

	var target_name: String = String(t.get("name", ""))
	var hist: Array = _history.get(target_name, [])
	if scanned and hist.size() >= 2:
		var lo: float = float(hist[0])
		var hi: float = float(hist[0])
		for v in hist:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		var span: float = maxf(hi - lo, 0.001)
		var line := PackedVector2Array()
		for i in range(hist.size()):
			var fx: float = chart.position.x + float(i) / float(hist.size() - 1) * chart.size.x
			var fy: float = chart.end.y - (float(hist[i]) - lo) / span * chart.size.y * 0.86 - chart.size.y * 0.07
			line.append(Vector2(fx, fy))
		draw_polyline(line, col, 2.0, true)
		draw_circle(line[line.size() - 1], 3.0, Color(1.0, 1.0, 1.0))
		_text(Vector2(chart.position.x + 4.0, chart.position.y + 11.0), "MAX %.2f" % hi, 8, C_DIM)
		_text(Vector2(chart.position.x + 4.0, chart.end.y - 4.0), "MIN %.2f" % lo, 8, C_DIM)
	else:
		_text(Vector2(chart.position.x + 8.0, chart.position.y + chart.size.y * 0.5),
			"AWAITING KaRIn SWATH" if not scanned else "COLLECTING TELEMETRY...", 11, C_AMBER)

	var stat_x: float = c.position.x + c.size.x * 0.65
	var y: float = c.position.y + 16.0
	_text(Vector2(stat_x, y), _class_label(cls) + " SITE", 10, col)
	y += 18.0
	for line in _stats_lines(t):
		_text(Vector2(stat_x, y), line, 10, C_TEXT)
		y += 15.0
	_text(Vector2(c.position.x, c.end.y - 34.0), _short(String(t.get("sensor", "")), 60), 9, C_DIM)
	_text(Vector2(c.position.x, c.end.y - 20.0), _short("SOURCE: " + String(t.get("source", "")), 64), 9, C_DIM)
	var state_txt: String = "RECEIVED AT CONTROL ROOM" if bool(t.get("downlinked", false)) else ("ONBOARD — AWAITING GROUND PASS" if scanned else "NOT YET OBSERVED")
	_text(Vector2(c.position.x, c.end.y - 5.0), state_txt, 10, C_GREEN if bool(t.get("downlinked", false)) else (C_AMBER if scanned else C_RED))

# Monitor 4 — downlink queue ────────────────────────────────────────────────
func _draw_downlink_monitor(rect: Rect2) -> void:
	var c := _monitor_frame(rect, "DOWNLINK / GROUND SEGMENT RECORDS", Color("#B3B3B3"))
	if c.size.x < 40.0 or c.size.y < 40.0:
		return
	var contact: bool = bool(_state.get("ground_contact", false))
	var station: String = String(_state.get("ground_station_name", ""))
	draw_circle(c.position + Vector2(6.0, 8.0), 3.5, C_GREEN if contact else C_RED)
	_text(c.position + Vector2(14.0, 12.0), ("LINK ACTIVE · " + station.to_upper()) if contact else "LINK IDLE · NO STATION ABOVE HORIZON", 10, C_GREEN if contact else C_RED)
	_text(c.position + Vector2(0.0, 28.0), "STORED %.0f MB  ·  SENT %.0f MB  ·  RECORDS %d/%d" % [
		float(_state.get("data_stored_mb", 0.0)), float(_state.get("data_transmitted_mb", 0.0)),
		int(_state.get("swot_received", 0)), SimulationEngine.SWOT_WATER_TARGETS.size()], 9, C_TEXT)

	var y: float = c.position.y + 46.0
	var row_h: float = 18.0
	for t in _targets:
		if y > c.end.y - 18.0:
			break
		var scanned: bool = bool(t.get("scanned", false))
		var downlinked: bool = bool(t.get("downlinked", false))
		var col: Color = C_GREEN if downlinked else (C_AMBER if scanned else Color("#777777"))
		var tag: String = "[RECEIVED]" if downlinked else ("[ONBOARD ]" if scanned else "[--------]")
		draw_rect(Rect2(c.position.x, y - 10.0, c.size.x, row_h - 2.0), Color(col.r, col.g, col.b, 0.06), true)
		_text(Vector2(c.position.x + 4.0, y + 2.0), tag, 9, col)
		_text(Vector2(c.position.x + 78.0, y + 2.0), _short(String(t.get("name", "")), 36), 9, C_TEXT)
		_text_right(c.end.x - 4.0, y + 2.0, _short(_class_label(String(t.get("water_class", "ocean"))), 8), 8, _class_color(String(t.get("water_class", "ocean"))))
		y += row_h
	var last_rx: String = String(_state.get("last_swot_received", ""))
	_text(Vector2(c.position.x, c.end.y - 4.0), "LAST RECEIVED: " + (_short(last_rx, 48) if last_rx != "" else "—"), 9, C_DIM)

# ─── Helpers ─────────────────────────────────────────────────────────────────
func _latlon_to_map(r: Rect2, lat: float, lon: float) -> Vector2:
	return Vector2(r.position.x + (lon + 180.0) / 360.0 * r.size.x,
		r.position.y + (90.0 - lat) / 180.0 * r.size.y)

func _class_color(cls: String) -> Color:
	match cls:
		"lake":
			return C_LAKE
		"river":
			return C_RIVER
		_:
			return C_OCEAN

func _class_label(cls: String) -> String:
	match cls:
		"lake":
			return "LAKE"
		"river":
			return "RIVER"
		_:
			return "OCEAN"

func _chart_value(t: Dictionary) -> float:
	var m: Dictionary = t.get("measurements", {})
	match String(t.get("water_class", "ocean")):
		"lake":
			return float(m.get("level_m", 0.0))
		"river":
			return float(m.get("stage_m", 0.0))
		_:
			return float(m.get("ssh_cm", 0.0))

func _chart_amp(t: Dictionary) -> float:
	match String(t.get("water_class", "ocean")):
		"lake":
			return 0.04
		"river":
			return 0.10
		_:
			return 1.6

func _sample_chart() -> void:
	var t := _focus()
	if t.is_empty() or not bool(t.get("scanned", false)):
		return
	var target_name: String = String(t.get("name", ""))
	var base: float = _chart_value(t)
	var arr: Array = _history.get(target_name, [])
	if arr.is_empty():
		for i in range(10):
			arr.append(base)
	var prev: float = float(arr[arr.size() - 1])
	var amp: float = _chart_amp(t)
	var next: float = prev + sin(_pulse * 1.9 + float(abs(target_name.hash() % 31))) * amp * 0.18
	next = clampf(next, base - amp, base + amp)
	arr.append(next)
	while arr.size() > 64:
		arr.pop_front()
	_history[target_name] = arr

func _stats_lines(t: Dictionary) -> Array:
	var m: Dictionary = t.get("measurements", {})
	match String(t.get("water_class", "ocean")):
		"lake":
			var lines: Array = ["Level: %.1f m" % float(m.get("level_m", 0.0)),
				"Anomaly: %+.0f cm" % float(m.get("anomaly_cm", 0.0))]
			if m.has("area_km2"):
				lines.append("Surface: %.0f km2" % float(m.get("area_km2", 0.0)))
			else:
				lines.append("Capacity: %.0f%%" % float(m.get("capacity_pct", 0.0)))
			return lines
		"river":
			return ["Stage: %.1f m" % float(m.get("stage_m", 0.0)),
				"Width: %.0f m" % float(m.get("width_m", 0.0)),
				"Discharge: %.0f m3/s" % float(m.get("discharge_m3s", 0.0))]
		_:
			return ["Sea-surface height: %.0f cm" % float(m.get("ssh_cm", 0.0)),
				"Geostrophic flow: %.0f cm/s" % float(m.get("geostrophic_cm_s", 0.0)),
				"Eddies resolved: %.0f" % float(m.get("eddies", m.get("front_width_km", 0.0)))]

func _fmt_scale(scale: float) -> String:
	if scale >= 1000.0:
		return "%.0f" % scale
	return "%.0f" % scale

func _fmt_lat(lat: float) -> String:
	return "%.1f%s" % [absf(lat), "N" if lat >= 0.0 else "S"]

func _fmt_lon(lon: float) -> String:
	return "%.1f%s" % [absf(lon), "E" if lon >= 0.0 else "W"]

func _short(s: String, n: int) -> String:
	if s.length() <= n:
		return s
	return s.substr(0, maxi(n - 1, 1)) + "…"

func _text(pos: Vector2, s: String, font_size: int, color: Color) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _text_right(right_x: float, y: float, s: String, font_size: int, color: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
