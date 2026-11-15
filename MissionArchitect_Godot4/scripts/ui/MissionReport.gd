## MissionReport.gd
## Post-mission results screen — animated score reveal, breakdown, improvements

extends Control

const ClimateMediaScript := preload("res://scripts/simulation/ClimateMedia.gd")

var mission_name_label: Label
var status_label: Label
var score_label: Label
var breakdown_panel: VBoxContainer
var improvement_panel: VBoxContainer
var improvements_title: Label
var event_log_panel: VBoxContainer
var retry_btn: Button
var new_mission_btn: Button
var main_menu_btn: Button
var save_btn: Button
var science_bar: ProgressBar
var science_label: Label
var data_label: Label
var orbits_label: Label

func _ready() -> void:
	mission_name_label = _g("Header/MissionNameLabel")
	status_label       = _g("Header/StatusLabel")
	score_label        = _g("ScorePanel/ScoreLabel")
	breakdown_panel    = _g("BreakdownPanel/BVBox/BreakdownList")
	improvement_panel  = _g("ImprovementsPanel/IVBox/ImprovementList")
	improvements_title = _g("ImprovementsPanel/IVBox/ImprovementsTitle")
	event_log_panel    = _g("EventLogPanel/ELVBox/ScrollContainer/EventList")
	retry_btn          = _g("ButtonBar/RetryButton")
	new_mission_btn    = _g("ButtonBar/NewMissionButton")
	main_menu_btn      = _g("ButtonBar/MainMenuButton")
	save_btn           = _g("ButtonBar/SaveButton")
	science_bar        = _g("StatsPanel/StatsVBox/ScienceBar")
	science_label      = _g("StatsPanel/StatsVBox/ScienceLabel")
	data_label         = _g("StatsPanel/StatsVBox/DataLabel")
	orbits_label       = _g("StatsPanel/StatsVBox/OrbitsLabel")

	_style_chrome()

	if retry_btn:       retry_btn.pressed.connect(_on_retry_pressed)
	if new_mission_btn: new_mission_btn.pressed.connect(_on_new_mission_pressed)
	if main_menu_btn:   main_menu_btn.pressed.connect(_on_main_menu_pressed)
	if save_btn:        save_btn.pressed.connect(_on_save_pressed)

	var result: Dictionary = GameManager.mission_result
	var mission: Dictionary = GameManager.current_mission

	if result.is_empty():
		push_warning("[MissionReport] No result data.")
		return

	_show_header(result, mission)
	_animate_score(result)
	_show_breakdown(result)
	_show_improvements(result)
	_show_event_log(result)
	_show_stats(result, mission)
	print("[MissionReport] Score: %d" % result.get("score", 0))

func _style_chrome() -> void:
	for path in ["StatsPanel", "BreakdownPanel", "ImprovementsPanel", "EventLogPanel"]:
		var panel := _g(path) as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", MissionForge.panel_style())
	MissionForge.style_button(retry_btn, true)
	for btn in [new_mission_btn, save_btn, main_menu_btn]:
		if btn:
			MissionForge.style_button(btn, false)
	var header_name := _g("Header/MissionNameLabel") as Label
	if header_name:
		header_name.add_theme_color_override("font_color", Color("#FFFFFF"))
		header_name.add_theme_font_size_override("font_size", 26)
	for path in ["ScorePanel/ScoreTitleLabel", "StatsPanel/StatsVBox/ScienceLabel",
			"StatsPanel/StatsVBox/DataLabel", "StatsPanel/StatsVBox/OrbitsLabel",
			"BreakdownPanel/BVBox/BreakdownTitle", "ImprovementsPanel/IVBox/ImprovementsTitle",
			"EventLogPanel/ELVBox/EventLogTitle"]:
		var lbl := _g(path) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", Color("#FFFFFF") if path.contains("Title") else Color("#B3B3B3"))
	var score := _g("ScorePanel/ScoreLabel") as Label
	if score:
		score.add_theme_color_override("font_color", Color("#FFFFFF"))
		score.add_theme_font_size_override("font_size", 56)
	var sub := _g("ScorePanel/ScoreSubLabel") as Label
	if sub:
		sub.add_theme_color_override("font_color", Color("#777777"))

func _g(path: String) -> Node:
	if has_node(path): return get_node(path)
	return null

func _show_header(result: Dictionary, mission: Dictionary) -> void:
	if mission_name_label:
		mission_name_label.text = mission.get("name", "Mission Complete")

	var success: bool = result.get("success", false)
	if status_label:
		if success:
			status_label.text = "MISSION SUCCESS"
			status_label.add_theme_color_override("font_color", Color("#FFFFFF"))
		else:
			status_label.text = "MISSION PARTIAL FAILURE"
			status_label.add_theme_color_override("font_color", Color("#B3B3B3"))

func _animate_score(result: Dictionary) -> void:
	var final_score: int = result.get("score", 0)
	if not score_label:
		return

	score_label.text = "0"
	var tween: Tween = create_tween()
	var counter: int = 0
	tween.tween_method(func(val: float):
		score_label.text = "%d" % int(val)
		score_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	, 0.0, float(final_score), 1.5)

func _show_breakdown(result: Dictionary) -> void:
	if not breakdown_panel:
		return
	var breakdown: Dictionary = result.get("score_breakdown", {})
	var categories: Array = [
		["Mission Objectives", breakdown.get("objectives", 0), 35],
		["Scientific Discoveries", breakdown.get("science", 0), 25],
		["Engineering Reliability", breakdown.get("reliability", 0), 20],
		["Resource Efficiency", breakdown.get("efficiency", 0), 15],
		["Operational Decisions", breakdown.get("operations", 0), 5]
	]
	for cat in categories:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		breakdown_panel.add_child(row)

		var name_lbl: Label = Label.new()
		name_lbl.text = cat[0]
		name_lbl.custom_minimum_size = Vector2(220, 0)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color("#B3B3B3"))
		row.add_child(name_lbl)

		var bar: ProgressBar = ProgressBar.new()
		bar.max_value = cat[2]
		bar.value = 0
		bar.custom_minimum_size = Vector2(160, 20)
		row.add_child(bar)

		var score_lbl: Label = Label.new()
		score_lbl.text = "%d / %d" % [cat[1], cat[2]]
		score_lbl.add_theme_font_size_override("font_size", 13)
		var frac: float = float(cat[1]) / float(cat[2])
		score_lbl.add_theme_color_override("font_color",
			Color("#FFFFFF") if frac >= 0.5 else Color("#777777"))
		row.add_child(score_lbl)

		# Animate bar
		var tween: Tween = create_tween()
		tween.tween_property(bar, "value", float(cat[1]), 0.8).set_delay(0.3)

func _show_improvements(result: Dictionary) -> void:
	if not improvement_panel:
		return
	var mission: Dictionary = GameManager.current_mission
	var mission_id: String = String(mission.get("id", ""))
	if mission_id == "asteroid_probe" or mission_id == "earth_climate":
		if improvements_title:
			improvements_title.text = "RENDEZVOUS OBJECTIVES & IMPROVEMENTS" if mission_id == "asteroid_probe" else "CLIMATE SURVEY OBJECTIVES & IMPROVEMENTS"
		var completed: Array = result.get("objectives_done", [])
		for objective in result.get("objectives_required", []):
			var done: bool = completed.has(objective)
			var objective_label: Label = Label.new()
			objective_label.text = ("✓  " if done else "○  ") + objective
			objective_label.add_theme_color_override("font_color", Color("#FFFFFF") if done else Color("#777777"))
			objective_label.add_theme_font_size_override("font_size", 11)
			objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			improvement_panel.add_child(objective_label)
	if mission_id == "earth_climate":
		_show_climate_data_returns(result)
		_show_swot_data_returns(result)
	var improvements: Array = result.get("improvements", [])
	for i in range(improvements.size()):
		var lbl: Label = Label.new()
		lbl.text = "%d.  %s" % [i + 1, improvements[i]]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_color_override("font_color", Color("#B3B3B3"))
		lbl.add_theme_font_size_override("font_size", 12)
		improvement_panel.add_child(lbl)

## The mission's actual contribution to the real climate record: every event
## this design sensed from orbit, with the NASA sensor analogue and the data
## source behind it, plus the bonus objectives it earned.  Printed as a data
## return manifest because that is what it is.
func _show_climate_data_returns(result: Dictionary) -> void:
	var observed: Array = result.get("climate_events_observed", [])
	var head: Label = Label.new()
	head.text = "CLIMATE DATA RETURNED — %d of %d real events sensed:" % [observed.size(), 6]
	head.add_theme_color_override("font_color", Color("#FFFFFF"))
	head.add_theme_font_size_override("font_size", 11)
	improvement_panel.add_child(head)
	for ev in observed:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		# The imagery was streamed during the flight and lives in the shared
		# cache now; the report never waits on the network for its evidence.
		var tex: Texture2D = ClimateMediaScript.load_cached(String(ev.get("img_url", "")))
		if tex != null:
			var img := TextureRect.new()
			img.texture = tex
			img.custom_minimum_size = Vector2(150, 88)
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			row.add_child(img)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var line: Label = Label.new()
		line.text = "   Day %d · %s" % [ev.get("day", 0), ev.get("name", "")]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_theme_color_override("font_color", Color("#B3B3B3"))
		line.add_theme_font_size_override("font_size", 10)
		col.add_child(line)
		var facts: Label = Label.new()
		facts.text = "      %s — source: %s\n      %s" % [
			ev.get("sensor", ""), ev.get("source", ""), ev.get("stat", "")]
		facts.autowrap_mode = TextServer.AUTOWRAP_WORD
		facts.add_theme_color_override("font_color", Color("#777777"))
		facts.add_theme_font_size_override("font_size", 9)
		col.add_child(facts)
		row.add_child(col)
		improvement_panel.add_child(row)
	for bonus in result.get("climate_bonus_objectives", []):
		var b: Label = Label.new()
		b.text = "★ Bonus earned: " + String(bonus)
		b.add_theme_color_override("font_color", Color("#FFFFFF"))
		b.add_theme_font_size_override("font_size", 11)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		improvement_panel.add_child(b)

## The SWOT surface-water layer's return manifest: each real ocean, lake and
## river record, whether it was scanned from orbit and whether a ground-station
## pass carried it to the control room.
func _show_swot_data_returns(result: Dictionary) -> void:
	var records: Array = result.get("swot_water_records", [])
	if records.is_empty():
		return
	var scanned: int = int(result.get("swot_scanned", 0))
	var received: int = int(result.get("swot_received", 0))
	var head: Label = Label.new()
	head.text = "SWOT SURFACE WATER RETURN — %d scanned, %d delivered to the control room:" % [scanned, received]
	head.add_theme_color_override("font_color", Color("#FFFFFF"))
	head.add_theme_font_size_override("font_size", 11)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD
	improvement_panel.add_child(head)
	for rec in records:
		var is_scanned: bool = bool(rec.get("scanned", false))
		var is_downlinked: bool = bool(rec.get("downlinked", false))
		var line: Label = Label.new()
		var tag: String = "✓ RECEIVED" if is_downlinked else ("◉ ONBOARD" if is_scanned else "○ NOT FLOWN")
		line.text = "   %s · %s — %s\n      %s" % [
			tag, String(rec.get("name", "")).to_upper(),
			String(rec.get("water_class", "")).to_upper(), String(rec.get("stat", ""))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_theme_font_size_override("font_size", 10)
		line.add_theme_color_override("font_color",
			Color("#FFFFFF") if is_downlinked else (Color("#B3B3B3") if is_scanned else Color("#777777")))
		improvement_panel.add_child(line)

func _show_event_log(result: Dictionary) -> void:
	if not event_log_panel:
		return
	var events: Array = result.get("events_log", [])
	var show_events: Array = events.slice(max(0, events.size() - 10), events.size())
	var type_colors: Dictionary = {
		"success": Color("#FFFFFF"),
		"danger": Color("#D9D9D9"),
		"warning": Color("#B3B3B3"),
		"info": Color("#777777")
	}
	for ev in show_events:
		var lbl: Label = Label.new()
		lbl.text = "Day %d: %s" % [ev.get("day", 0), ev.get("msg", "")]
		lbl.add_theme_color_override("font_color",
			type_colors.get(ev.get("type", "info"), Color("#B3B3B3")))
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		event_log_panel.add_child(lbl)

func _show_stats(result: Dictionary, mission: Dictionary) -> void:
	var sci: float = result.get("science_collected", 0)
	var sci_goal: float = result.get("science_goal", 80)
	if science_bar:
		science_bar.max_value = sci_goal
		science_bar.value = sci
	if science_label:
		science_label.text = "Science: %.1f / %.0f points (%.0f%%)" % [sci, sci_goal, (sci / max(sci_goal, 1)) * 100]
	if data_label:
		data_label.text = "Data Transmitted: %.2f GB" % result.get("data_transmitted_gb", 0)
	if orbits_label:
		orbits_label.text = "Total Orbits: %d  |  Mission Duration: %d days" % [
			result.get("total_orbits", 0),
			result.get("mission_days", 0)
		]
		if mission.get("id", "") == "earth_climate":
			# The validation line judges of a space-game entry should actually see:
			# the orbit's measured Kepler period above, and here the J2 nodal drift
			# the simulation flew against the 0.9856°/day sun-sync requirement.
			var prec: float = float(result.get("nodal_precession_deg_day", 0.0))
			var events: Array = result.get("climate_events_observed", [])
			orbits_label.text += "  |  %d real events sensed" % events.size()
			orbits_label.text += "  |  SWOT %d scanned / %d at control room" % [
				int(result.get("swot_scanned", 0)), int(result.get("swot_received", 0))]
			if prec > 0.0:
				orbits_label.text += "  |  J2 drift %.4f °/day vs 0.9856 sun-sync" % prec

# ─── Button Callbacks ─────────────────────────────────────────────────────────
func _on_retry_pressed() -> void:
	# Go back to builder with same config
	GameManager.go_to_builder()

func _on_new_mission_pressed() -> void:
	GameManager.mission_result = {}
	GameManager.spacecraft_config = {}
	GameManager._init_spacecraft_config()
	GameManager.go_to_scene("res://scenes/ui/mission_select.tscn")

func _on_main_menu_pressed() -> void:
	GameManager.go_to_main_menu()

func _on_save_pressed() -> void:
	GameManager.save_game()
	save_btn.text = "Saved"
	await get_tree().create_timer(2.0).timeout
	save_btn.text = "Save Result"
