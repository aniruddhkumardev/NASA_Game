## SpacecraftBuilder.gd
## Polished NASA-inspired 3-panel spacecraft design interface.
## Layout: TopBar (mission + workflow) | LeftPanel (components) | Center (3D viewport) | RightPanel (resources) | BottomBar (stats + actions)

extends Node3D

# ─── Palette (premium black & white UI) ──────────────────────────────────────
const COL_BG          := Color("#000000")
const COL_PANEL       := Color("#0A0A0A")
const COL_PANEL_ALT   := Color("#151515")
const COL_BORDER      := Color("#333333")
const COL_ACCENT      := Color("#FFFFFF")
const COL_ACCENT_DIM  := Color("#B3B3B3")
const COL_TEXT        := Color("#FFFFFF")
const COL_TEXT_DIM    := Color("#B3B3B3")
const COL_OK          := Color("#FFFFFF")
const COL_WARN        := Color("#D9D9D9")
const COL_ERR         := Color("#FFFFFF")
const COL_BAR_BG      := Color("#202020")

# ─── 3D nodes ─────────────────────────────────────────────────────────────────
var bus_mesh: Node3D
var solar_panels: Node3D
var antenna_mount: Node3D
var instrument_rack: Node3D
var engine_mount: Node3D
var rocket_mesh: Node3D
var orbit_camera: Camera3D
var spacecraft_root: Node3D
var _using_glb_model: bool = false   # true once the detailed craft is built (skips procedural material overrides)
var _rocket_present: bool = false
var _last_rocket_id: String = ""
var _cam_target: Vector3 = Vector3.ZERO   # orbit pivot (lowered when a rocket is shown)

# Cached realistic materials for the procedural spacecraft
var _mat_solar: ShaderMaterial
var _mat_gold: StandardMaterial3D
var _mat_silver: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_dish: StandardMaterial3D
var _mat_lens: StandardMaterial3D
var _mat_radar: StandardMaterial3D
var _mat_orange: StandardMaterial3D

# ─── UI nodes ─────────────────────────────────────────────────────────────────
var component_list: VBoxContainer
var tab_buttons: Array = []
var current_category: int = 0
var resource_bars: Dictionary = {}   # key -> {bar, value_label, prev_val}
var summary_labels: Dictionary = {}  # key -> Label
var mission_title_lbl: Label
var mission_sub_lbl: Label
var error_panel: Control
var error_list: VBoxContainer
var continue_btn: Button
var validate_btn: Button
var back_btn: Button
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport

const CATEGORIES: Array = ["bus", "power", "battery", "comms", "instruments", "propulsion", "rocket"]
const CAT_LABELS: Array = ["Bus", "Power", "Battery", "Comms", "Instruments", "Propulsion", "Rocket"]
const CAT_ICONS:  Array = ["✦", "", "▮", "", "", "⚡", "▲"]

# ─── Camera orbit ─────────────────────────────────────────────────────────────
var _cam_yaw: float   = 30.0
var _cam_pitch: float = 20.0
var _cam_zoom: float  = 8.0
var _mouse_dragging: bool = false
var _idle_rotation: float = 0.0
var _last_interaction_ms: int = 0

# ══════════════════════════════════════════════════════════════════════════════
# READY
# ══════════════════════════════════════════════════════════════════════════════
const VIEWPORT_PATH     := "UI/MainLayout/VBox/MainContent/CenterViewport"
const VIEWPORT_CTR_PATH := "UI/MainLayout/VBox/MainContent/CenterViewport/ViewportContainer"
const SCENE3D_PATH      := "UI/MainLayout/VBox/MainContent/CenterViewport/ViewportContainer/SubViewport"
var _paint_white: ShaderMaterial = null        # rocket airframe paints
var _paint_black: ShaderMaterial = null
var _paint_carbon: ShaderMaterial = null
var _paint_orange: ShaderMaterial = null
var _paint_steel: ShaderMaterial = null
var _mat_bell: StandardMaterial3D = null       # engine nozzle interior (double-sided)
var _mat_flame: ShaderMaterial = null          # animated engine exhaust
var _mat_ion_glow: StandardMaterial3D = null   # ion thruster grid glow
var _mat_plasma: StandardMaterial3D = null     # ion plasma beam (additive blue)
var _last_prop_id: String = ""                 # propulsion id currently modelled


func _ready() -> void:
	# Wire 3D nodes from SubViewport (nested inside SubViewportContainer)
	orbit_camera    = get_node_or_null(SCENE3D_PATH + "/OrbitCamera")
	spacecraft_root = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D")
	bus_mesh        = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/BusMesh")
	solar_panels    = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/SolarPanels")
	antenna_mount   = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/AntennaMesh")
	instrument_rack = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/InstrumentRack")
	engine_mount    = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/EngineMesh")
	rocket_mesh     = get_node_or_null(SCENE3D_PATH + "/Spacecraft3D/RocketMesh")
	sub_viewport    = get_node_or_null(SCENE3D_PATH) as SubViewport

	# Root background
	_apply_root_background()

	# Build UI
	var theme := _build_theme()
	$UI/MainLayout.theme = theme
	$UI/MainLayout/VBox/TopBar.theme = theme
	$UI/MainLayout/VBox/MainContent/LeftPanel.theme = theme
	$UI/MainLayout/VBox/MainContent/RightPanel.theme = theme
	$UI/MainLayout/VBox/BottomBar.theme = theme
	$UI/ErrorPanel.theme = theme

	viewport_container = get_node_or_null(VIEWPORT_CTR_PATH) as SubViewportContainer
	if viewport_container:
		viewport_container.clip_contents = true
		# Route camera input through the container so UI clicks don't accidentally orbit
		viewport_container.gui_input.connect(_on_viewport_gui_input)
		# With stretch=true, SubViewportContainer automatically syncs SubViewport size
		# to the container's pixel size, so no manual resize is needed.

	_build_top_bar(theme)
	_build_left_panel(theme)
	_build_right_panel(theme)
	_build_bottom_bar(theme)
	_build_view_presets(theme)
	_setup_error_panel(theme)

	_setup_mission_info()
	_populate_category(0)
	_refresh_ui()
	_build_realistic_spacecraft()
	_update_3d_spacecraft()
	_update_cam()
	_play_entry_animations()

	GameManager.resource_updated.connect(_on_resource_updated)
	print("[Builder] Ready — mission: " + GameManager.current_mission.get("name", "?"))

func _apply_root_background() -> void:
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(bg)
	$UI.move_child(bg, 0)

# ══════════════════════════════════════════════════════════════════════════════
# VIEW PRESET BUTTONS (overlay on top of 3D viewport)
# ══════════════════════════════════════════════════════════════════════════════
func _build_view_presets(_t: Theme) -> void:
	var bar := get_node_or_null(VIEWPORT_PATH + "/ViewPresetBar") as HBoxContainer
	if not bar:
		return
	var presets := [
		{"label": "3/4",  "yaw": 30.0,  "pitch": 20.0, "zoom": 8.0},
		{"label": "Front", "yaw": 0.0,   "pitch": 0.0,  "zoom": 7.0},
		{"label": "Side",  "yaw": 90.0,  "pitch": 0.0,  "zoom": 7.0},
		{"label": "Top",   "yaw": 0.0,   "pitch": 75.0, "zoom": 9.0},
		{"label": "Reset", "yaw": 30.0,  "pitch": 20.0, "zoom": 8.0},
	]
	for p in presets:
		var btn := Button.new()
		btn.text = p["label"]
		btn.custom_minimum_size = Vector2(64, 28)
		btn.add_theme_font_size_override("font_size", 11)
		# Semi-transparent dark chip so buttons read over any scene
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.039, 0.039, 0.039, 0.82)
		sb.border_color = Color("#333333")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", sb)
		var sb_hover := sb.duplicate() as StyleBoxFlat
		sb_hover.bg_color = Color(0.125, 0.125, 0.125, 0.92)
		sb_hover.border_color = Color("#FFFFFF")
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_color_override("font_color", COL_TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", COL_TEXT)
		btn.pressed.connect(_on_view_preset.bind(p["yaw"], p["pitch"], p["zoom"]))
		bar.add_child(btn)

func _on_view_preset(yaw: float, pitch: float, zoom: float) -> void:
	# Tween the camera to the new preset for a smooth transition
	var z: float = zoom * (1.45 if _rocket_present else 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_set_cam_yaw, _cam_yaw, yaw, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_cam_pitch, _cam_pitch, pitch, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_cam_zoom, _cam_zoom, z, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_last_interaction_ms = Time.get_ticks_msec()

func _set_cam_yaw(v: float) -> void:
	_cam_yaw = v
	_update_cam()

func _set_cam_pitch(v: float) -> void:
	_cam_pitch = v
	_update_cam()

func _set_cam_zoom(v: float) -> void:
	_cam_zoom = v
	_update_cam()

# ══════════════════════════════════════════════════════════════════════════════
# THEME
# ══════════════════════════════════════════════════════════════════════════════
func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	# Colors
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_color", "RichTextLabel", COL_TEXT)

	# PanelContainer
	var panel := StyleBoxFlat.new()
	panel.bg_color = COL_PANEL
	panel.border_color = COL_BORDER
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)

	# Button — normal / hover / pressed / disabled (secondary control skin)
	t.set_stylebox("normal",  "Button", _btn_style(Color("#111111"), COL_BORDER))
	t.set_stylebox("hover",   "Button", _btn_style(Color("#202020"), Color("#FFFFFF")))
	t.set_stylebox("pressed", "Button", _btn_style(Color("#000000"), Color("#FFFFFF")))
	t.set_stylebox("disabled","Button", _btn_style(COL_PANEL, COL_BORDER))
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color("#FFFFFF"))
	t.set_color("font_pressed_color", "Button", Color("#FFFFFF"))
	t.set_color("font_disabled_color", "Button", Color("#777777"))
	t.set_font_size("font_size", "Button", 13)

	# ProgressBar — #202020 track, white fill
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = COL_BAR_BG
	pb_bg.set_corner_radius_all(2)
	pb_bg.content_margin_top = 2
	pb_bg.content_margin_bottom = 2
	t.set_stylebox("background", "ProgressBar", pb_bg)

	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = COL_ACCENT
	pb_fill.set_corner_radius_all(2)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	t.set_color("font_color", "ProgressBar", COL_TEXT)

	# ScrollContainer / VBox spacing
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)

	return t

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

# ══════════════════════════════════════════════════════════════════════════════
# TOP BAR
# ══════════════════════════════════════════════════════════════════════════════
func _build_top_bar(_t: Theme) -> void:
	var top := $UI/MainLayout/VBox/TopBar as HBoxContainer

	# Mission info card
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	top.add_child(card)

	var card_hb := HBoxContainer.new()
	card_hb.add_theme_constant_override("separation", 12)
	card.add_child(card_hb)

	var icon := Label.new()
	icon.text = "◈"
	icon.add_theme_font_size_override("font_size", 24)
	icon.custom_minimum_size = Vector2(38, 38)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_hb.add_child(icon)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	card_hb.add_child(vb)

	mission_title_lbl = Label.new()
	mission_title_lbl.add_theme_font_size_override("font_size", 16)
	mission_title_lbl.add_theme_color_override("font_color", COL_ACCENT)
	vb.add_child(mission_title_lbl)

	mission_sub_lbl = Label.new()
	mission_sub_lbl.add_theme_font_size_override("font_size", 11)
	mission_sub_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	vb.add_child(mission_sub_lbl)

	# Workflow steps
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 8)
	steps.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(steps)
	var step_names := ["1  DESIGN", "2  RESOURCES", "3  VALIDATE", "4  LAUNCH"]
	for i in step_names.size():
		var s := Label.new()
		s.text = step_names[i]
		s.add_theme_font_size_override("font_size", 12)
		if i == 0:
			s.add_theme_color_override("font_color", COL_ACCENT)
		else:
			s.add_theme_color_override("font_color", COL_TEXT_DIM)
		steps.add_child(s)
		if i < step_names.size() - 1:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_color_override("font_color", COL_TEXT_DIM)
			steps.add_child(arrow)

func _setup_mission_info() -> void:
	var m: Dictionary = GameManager.current_mission
	if mission_title_lbl:
		mission_title_lbl.text = m.get("name", "Mission")
	if mission_sub_lbl:
		mission_sub_lbl.text = "Target: %s   |   Budget: $%dM   |   Mass Limit: ≤%d kg   |   Goal: %d sci pts" % [
			m.get("target", "?"), m.get("budget", 0), m.get("mass_limit", 0), m.get("science_goal", 0)
		]

# ══════════════════════════════════════════════════════════════════════════════
# LEFT PANEL — Component Browser
# ══════════════════════════════════════════════════════════════════════════════
func _build_left_panel(_t: Theme) -> void:
	var panel := $UI/MainLayout/VBox/MainContent/LeftPanel as PanelContainer
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "SPACECRAFT COMPONENTS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	# Category tabs — 2 rows in a GridContainer for compact layout
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)

	for i in CAT_LABELS.size():
		var btn := Button.new()
		btn.text = "%s %s" % [CAT_ICONS[i], CAT_LABELS[i]]
		btn.toggle_mode = true
		btn.button_pressed = (i == 0)
		btn.custom_minimum_size = Vector2(70, 34)
		btn.add_theme_font_size_override("font_size", 11)
		_style_toggle(btn)
		btn.pressed.connect(_on_tab_pressed.bind(i, btn))
		grid.add_child(btn)
		tab_buttons.append(btn)

	# Scrollable component list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	component_list = VBoxContainer.new()
	component_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_list.add_theme_constant_override("separation", 6)
	scroll.add_child(component_list)

func _on_tab_pressed(idx: int, pressed_btn: Button) -> void:
	current_category = idx
	for b in tab_buttons:
		b.button_pressed = (b == pressed_btn)
	_populate_category(idx)

## Toggle chip: #111111 idle, white fill with black label when active.
func _style_toggle(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _btn_style(Color("#111111"), COL_BORDER))
	btn.add_theme_stylebox_override("hover", _btn_style(COL_PANEL_ALT, COL_TEXT_DIM))
	btn.add_theme_stylebox_override("pressed", _btn_style(COL_ACCENT, COL_ACCENT))
	btn.add_theme_stylebox_override("focus", _btn_style(COL_PANEL_ALT, COL_ACCENT))
	btn.add_theme_stylebox_override("disabled", _btn_style(COL_PANEL, COL_BORDER))
	btn.add_theme_color_override("font_color", COL_TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", COL_TEXT)
	btn.add_theme_color_override("font_pressed_color", Color("#000000"))
	btn.add_theme_color_override("font_focus_color", COL_TEXT)
	btn.add_theme_color_override("font_disabled_color", Color("#777777"))

func _populate_category(cat_idx: int) -> void:
	current_category = cat_idx
	if not component_list:
		return
	for child in component_list.get_children():
		child.queue_free()

	var cat_name: String = CATEGORIES[cat_idx]
	var items: Array = GameManager.components.get(cat_name, [])
	for item in items:
		var card := _make_component_card(item, cat_name)
		component_list.add_child(card)

func _make_component_card(item: Dictionary, category: String) -> Control:
	var is_sel: bool = _is_selected(item, category)
	var accent: Color = COL_ACCENT

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 78)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("mf_selected", is_sel)

	var sb := StyleBoxFlat.new()
	if is_sel:
		sb.bg_color = Color("#202020")
		sb.border_color = Color("#FFFFFF")
		sb.set_border_width_all(1)
		sb.border_width_left = 3
	else:
		sb.bg_color = Color("#151515")
		sb.border_color = Color("#333333")
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)

	# Icon block
	var icon := Label.new()
	icon.text = item.get("icon", "◆")
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", accent)
	icon.custom_minimum_size = Vector2(34, 34)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(icon)

	# Text column
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	hb.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(name_lbl)

	var stats := Label.new()
	stats.text = _stats_line(item)
	stats.add_theme_font_size_override("font_size", 10)
	stats.add_theme_color_override("font_color", COL_TEXT_DIM)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(stats)

	# In the climate mission every instrument box stands in for a real NASA
	# Earth-observation sensor, so the card names that sensor.  The mapping lives
	# in the mission definition, which keeps every other mission's builder
	# exactly as it was — here the payload choice becomes a choice about real
	# science, not just stats.
	if category == "instruments":
		var analogs: Dictionary = GameManager.current_mission.get("sensor_analogs", {})
		var inst_id: String = String(item.get("id", ""))
		if analogs.has(inst_id):
			var analog := Label.new()
			analog.text = "Models: " + String(analogs[inst_id])
			analog.add_theme_font_size_override("font_size", 10)
			analog.add_theme_color_override("font_color", COL_TEXT_DIM)
			analog.autowrap_mode = TextServer.AUTOWRAP_WORD
			vb.add_child(analog)

	# Selection check
	if is_sel:
		var check := Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 18)
		check.add_theme_color_override("font_color", accent)
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(check)

	# Invisible click button overlay
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 78)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(_on_component_pressed.bind(item, category))
	btn.mouse_entered.connect(_on_card_hover.bind(card, true))
	btn.mouse_exited.connect(_on_card_hover.bind(card, false))
	card.add_child(btn)

	return card

func _on_card_hover(card: Control, entering: bool) -> void:
	var sb := card.get_theme_stylebox("panel") as StyleBoxFlat
	if not sb:
		return
	var is_sel: bool = card.get_meta("mf_selected", false)
	var new_sb := sb.duplicate() as StyleBoxFlat
	if entering:
		new_sb.bg_color = Color("#202020")
		new_sb.border_color = Color("#B3B3B3") if not is_sel else Color("#FFFFFF")
	else:
		new_sb.bg_color = Color("#202020") if is_sel else Color("#151515")
		new_sb.border_color = Color("#FFFFFF") if is_sel else Color("#333333")
	card.add_theme_stylebox_override("panel", new_sb)

func _stats_line(item: Dictionary) -> String:
	var p: Array = []
	if item.has("mass"):              p.append("%d kg" % item["mass"])
	if item.has("cost"):              p.append("$%dM" % item["cost"])
	if item.has("power_gen"):         p.append("+%dW" % item["power_gen"])
	if item.has("power_draw") and item["power_draw"] > 0:
		p.append("-%dW" % item["power_draw"])
	if item.has("science_per_orbit"): p.append("+%d sci/orb" % item["science_per_orbit"])
	if item.has("capacity_wh"):       p.append("%d Wh" % item["capacity_wh"])
	if item.has("bandwidth_mbps"):    p.append("%d Mbps" % item["bandwidth_mbps"])
	if item.has("payload_kg"):        p.append("cap %d kg" % item["payload_kg"])
	if item.has("delta_v"):           p.append("Δv %d" % item["delta_v"])
	if item.has("reliability"):       p.append("%d%% rel" % int(item["reliability"] * 100))
	return "  •  ".join(p)

func _is_selected(item: Dictionary, category: String) -> bool:
	if category == "instruments":
		return GameManager.has_instrument(item["id"])
	var stored: Dictionary = GameManager.spacecraft_config.get(category, {})
	return stored.get("id", "") == item["id"]

func _on_component_pressed(item: Dictionary, category: String) -> void:
	if category == "instruments":
		GameManager.toggle_instrument(item)
	else:
		GameManager.set_component(category, item)
	_populate_category(current_category)
	_refresh_ui()
	_update_3d_spacecraft()

# ══════════════════════════════════════════════════════════════════════════════
# RIGHT PANEL — Resource Dashboard
# ══════════════════════════════════════════════════════════════════════════════
func _build_right_panel(_t: Theme) -> void:
	var panel := $UI/MainLayout/VBox/MainContent/RightPanel as PanelContainer
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "MISSION RESOURCES"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", COL_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var defs := [
		{"key": "mass",    "icon": "◆",  "label": "Mass",    "color": Color("#B3B3B3")},
		{"key": "power",   "icon": "◇",  "label": "Power",   "color": Color("#B3B3B3")},
		{"key": "budget",  "icon": "▤",  "label": "Budget",  "color": Color("#B3B3B3")},
		{"key": "data",    "icon": "▦",  "label": "Data",    "color": Color("#B3B3B3")},
		{"key": "science", "icon": "✧",  "label": "Science", "color": Color("#B3B3B3")},
		{"key": "battery", "icon": "▮",  "label": "Battery", "color": Color("#B3B3B3")},
	]
	for d in defs:
		vb.add_child(_make_resource_card(d))

func _make_resource_card(def: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 68)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#151515")
	sb.border_color = Color("#333333")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)

	var icon := Label.new()
	icon.text = def["icon"]
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", def["color"])
	icon.custom_minimum_size = Vector2(28, 28)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(icon)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	hb.add_child(vb)

	var header := HBoxContainer.new()
	vb.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = def["label"]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "0 / 0"
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(val_lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = def["color"]
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(bar)

	resource_bars[def["key"]] = {"bar": bar, "value": val_lbl, "color": def["color"], "prev": 0.0}
	return card

func _refresh_ui() -> void:
	var cfg: Dictionary = GameManager.spacecraft_config
	var msn: Dictionary = GameManager.current_mission

	var mass: float  = cfg.get("total_mass", 0)
	var cost: float  = cfg.get("total_cost", 0)
	var gen: float   = cfg.get("total_power_gen", 0)
	var draw: float  = cfg.get("total_power_draw", 0)
	var data: float  = cfg.get("total_data_rate", 0)
	var sci: float   = cfg.get("total_science_per_orbit", 0)
	var batt: float  = cfg.get("battery_capacity", 0)
	var mlim: float  = msn.get("mass_limit", 500)
	var blim: float  = msn.get("budget", 120)
	var plim: float  = msn.get("power_limit", 300)
	var slim: float  = max(msn.get("science_goal", 80), 1)

	_update_resource("mass",    mass, mlim, "%d / %d kg" % [int(mass), int(mlim)])
	_update_resource("power",   gen,  plim, "%dW gen / %dW draw" % [int(gen), int(draw)])
	_update_resource("budget",  cost, blim, "$%dM / $%dM" % [int(cost), int(blim)])
	_update_resource("data",    data, max(data, 100), "%d Mbps" % int(data))
	_update_resource("science", sci,  slim, "+%.1f pts/orb" % sci)
	_update_resource("battery", batt, max(batt, 600), "%d Wh" % int(batt))

	if continue_btn:
		continue_btn.disabled = not GameManager.is_design_valid()

	# Bottom summary
	if summary_labels.has("mass"):
		summary_labels["mass"].text = "%d kg" % int(mass)
	if summary_labels.has("power"):
		summary_labels["power"].text = "%d W" % int(gen - draw)
	if summary_labels.has("cost"):
		summary_labels["cost"].text = "$%dM" % int(cost)
	if summary_labels.has("science"):
		summary_labels["science"].text = "+%.1f pts" % sci

func _update_resource(key: String, val: float, max_val: float, text: String) -> void:
	if not resource_bars.has(key):
		return
	var d: Dictionary = resource_bars[key]
	var bar: ProgressBar = d["bar"]
	var lbl: Label = d["value"]
	bar.max_value = max(max_val, 1)
	var frac: float = clamp(val / max(max_val, 1), 0.0, 1.0)
	_animate_bar(bar, d["prev"], val, max_val)
	d["prev"] = val
	lbl.text = text
	# Color shift when over 80%
	var col: Color = d["color"]
	if frac > 0.95:
		col = COL_ERR
	elif frac > 0.85:
		col = COL_WARN
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)

func _animate_bar(bar: ProgressBar, _old_val: float, new_val: float, max_val: float) -> void:
	bar.max_value = max(max_val, 1)
	var tw := create_tween()
	tw.tween_property(bar, "value", new_val, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_resource_updated(_n: String, _v: float) -> void:
	_refresh_ui()

# ══════════════════════════════════════════════════════════════════════════════
# BOTTOM BAR
# ══════════════════════════════════════════════════════════════════════════════
func _build_bottom_bar(_t: Theme) -> void:
	var bot := $UI/MainLayout/VBox/BottomBar as HBoxContainer

	back_btn = Button.new()
	back_btn.text = "←  Back"
	back_btn.custom_minimum_size = Vector2(120, 46)
	back_btn.pressed.connect(_on_back_pressed)
	bot.add_child(back_btn)

	validate_btn = Button.new()
	validate_btn.text = "✓  Validate Design"
	validate_btn.custom_minimum_size = Vector2(180, 46)
	validate_btn.pressed.connect(_on_validate_pressed)
	bot.add_child(validate_btn)

	# Summary stats
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 22)
	bot.add_child(stats)
	var stat_defs := [
		{"key": "mass",    "icon": "◆",  "label": "Est. Mass"},
		{"key": "power",   "icon": "◇",  "label": "Est. Power"},
		{"key": "budget",  "icon": "▤",  "label": "Est. Cost"},
		{"key": "science", "icon": "✧",  "label": "Est. Science"},
	]
	for sd in stat_defs:
		stats.add_child(_make_stat_block(sd["icon"], sd["label"], sd["key"]))

	# Spacer pushes continue button to right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(spacer)

	continue_btn = Button.new()
	continue_btn.text = "PROCEED TO LAUNCH  »"
	continue_btn.custom_minimum_size = Vector2(240, 50)
	continue_btn.disabled = true
	MissionForge.style_button(continue_btn, true)
	continue_btn.pressed.connect(_on_continue_pressed)
	bot.add_child(continue_btn)

func _make_stat_block(icon: String, label: String, key: String) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	var hb_top := HBoxContainer.new()
	hb_top.add_theme_constant_override("separation", 6)
	vb.add_child(hb_top)

	var ic := Label.new()
	ic.text = icon
	ic.add_theme_font_size_override("font_size", 14)
	ic.add_theme_color_override("font_color", COL_TEXT_DIM)
	hb_top.add_child(ic)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
	hb_top.add_child(lbl)

	var val := Label.new()
	val.text = "0"
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(val)

	summary_labels[key] = val
	return vb

# ══════════════════════════════════════════════════════════════════════════════
# ERROR PANEL
# ══════════════════════════════════════════════════════════════════════════════
func _setup_error_panel(_t: Theme) -> void:
	error_panel = $UI/ErrorPanel
	error_list = $UI/ErrorPanel/ErrorVBox/ScrollContainer/ErrorList
	var title := $UI/ErrorPanel/ErrorVBox/ErrorTitle as Label
	if title:
		title.add_theme_color_override("font_color", COL_TEXT)
		title.add_theme_font_size_override("font_size", 18)
	var dismiss := $UI/ErrorPanel/ErrorVBox/DismissError as Button
	if dismiss:
		MissionForge.style_button(dismiss, false)
		dismiss.pressed.connect(func(): _hide_error_panel())
	if error_panel:
		error_panel.hide()

func _on_validate_pressed() -> void:
	if not error_panel or not error_list:
		return
	for c in error_list.get_children():
		c.queue_free()

	var errors: Array = GameManager.validate_design()
	if errors.is_empty():
		var ok := Label.new()
		ok.text = "✓  Design is valid — ready to launch!"
		ok.add_theme_color_override("font_color", COL_OK)
		ok.add_theme_font_size_override("font_size", 14)
		error_list.add_child(ok)
	else:
		for err in errors:
			var lbl := Label.new()
			lbl.text = ("✕  " if err["type"] == "error" else "!  ") + err["msg"] + "\n    → " + err.get("fix", "")
			lbl.add_theme_color_override("font_color", COL_ERR if err["type"] == "error" else COL_WARN)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			error_list.add_child(lbl)

	_show_error_panel()

func _show_error_panel() -> void:
	if not error_panel:
		return
	error_panel.show()
	error_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(error_panel, "modulate:a", 1.0, 0.2)

func _hide_error_panel() -> void:
	if not error_panel:
		return
	var tw := create_tween()
	tw.tween_property(error_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(error_panel.hide)

# ══════════════════════════════════════════════════════════════════════════════
# 3D SPACECRAFT
# ══════════════════════════════════════════════════════════════════════════════
## Builds a detailed, realistic spacecraft directly in Godot and drops the parts
## into the existing per-component containers (BusMesh / SolarPanels / AntennaMesh
## / EngineMesh) so the show/hide + scaling logic in _update_3d_spacecraft keeps
## working. Uses a procedural solar-cell shader, gold MLI foil, a parabolic dish
## and thruster bells for a believable hardware look.

const SOLAR_SHADER := """
shader_type spatial;

uniform vec3 cell_dark   : source_color = vec3(0.010, 0.035, 0.130);
uniform vec3 cell_bright : source_color = vec3(0.030, 0.100, 0.300);
uniform vec3 grid_color  : source_color = vec3(0.550, 0.620, 0.780);
uniform vec2 cells = vec2(4.0, 10.0);
uniform float grid_width = 0.035;
uniform float busbar_width = 0.010;

float hash21(vec2 p) {
	p = fract(p * vec2(123.4, 345.6));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV * cells;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	vec2 d = min(f, 1.0 - f);
	// pixel footprint in cell space -> drives anti-aliasing so lines never pop
	vec2 w = fwidth(uv) + vec2(1e-5);
	float line_x = 1.0 - smoothstep(grid_width - w.x, grid_width + w.x, d.x);
	float line_y = 1.0 - smoothstep(grid_width - w.y, grid_width + w.y, d.y);
	float border = max(line_x, line_y);
	float bus = max(1.0 - smoothstep(busbar_width - w.x, busbar_width + w.x, abs(f.x - 0.30)),
	               1.0 - smoothstep(busbar_width - w.x, busbar_width + w.x, abs(f.x - 0.70)));
	// fade grid detail out when a cell is smaller than ~half a pixel (kills shimmer)
	float fade = clamp(0.5 / max(w.x, w.y), 0.0, 1.0);
	float v = hash21(id);
	vec3 col = mix(cell_dark, cell_bright, v);
	col *= 0.9 + 0.2 * smoothstep(0.0, 1.0, f.x * 0.5 + f.y * 0.5);
	float line = clamp(max(border, bus * 0.85), 0.0, 1.0) * fade;
	col = mix(col, grid_color, line);
	ALBEDO = col;
	METALLIC = 0.2;
	ROUGHNESS = mix(0.16, 0.55, line);
}
"""

## Painted rocket airframe: horizontal panel rings + vertical stringer seams,
## anti-aliased with fwidth so they stay crisp (no shimmer) while orbiting.
const ROCKET_PAINT_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.90);
uniform vec3 line_color : source_color = vec3(0.05, 0.05, 0.07);
uniform float rings = 9.0;
uniform float seams = 16.0;
uniform float metallic_v = 0.35;
uniform float rough_v = 0.45;

void fragment() {
	float ring = fract(UV.y * rings);
	float rd = min(ring, 1.0 - ring);
	float wy = fwidth(UV.y * rings) + 1e-5;
	float line_h = 1.0 - smoothstep(0.02 - wy, 0.02 + wy, rd);

	float seam = fract(UV.x * seams);
	float sd = min(seam, 1.0 - seam);
	float wx = fwidth(UV.x * seams) + 1e-5;
	float line_v = 1.0 - smoothstep(0.012 - wx, 0.012 + wx, sd);

	float line = clamp(max(line_h, line_v * 0.65), 0.0, 1.0);
	ALBEDO = mix(base_color, line_color, line * 0.75);
	METALLIC = metallic_v;
	ROUGHNESS = mix(rough_v, rough_v + 0.2, line);
}
"""

## Engine exhaust plume: additive, unshaded, animated flicker. UV.y = 1 at the
## nozzle (hottest, white-hot) fading to a tapering orange tip at UV.y = 0.
const FLAME_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec3 c_hot  : source_color = vec3(1.00, 0.97, 0.82);
uniform vec3 c_mid  : source_color = vec3(1.00, 0.52, 0.14);
uniform vec3 c_cool : source_color = vec3(0.55, 0.07, 0.02);
uniform float flicker = 11.0;
uniform float intensity = 1.25;

void fragment() {
	float v = UV.y;                                   // 1 nozzle, 0 tip
	vec3 col = mix(c_cool, c_mid, smoothstep(0.0, 0.5, v));
	col = mix(col, c_hot, smoothstep(0.5, 0.92, v));
	float a = smoothstep(0.0, 0.22, v);              // taper out at the tip
	float f = 0.82 + 0.18 * sin(TIME * flicker + UV.x * 26.0 + v * 9.0);
	ALBEDO = col * (0.9 + 1.5 * v) * f * intensity;
	ALPHA = a * f * 0.95;
}
"""

func _build_realistic_spacecraft() -> void:
	if not spacecraft_root:
		return
	_make_materials()
	_clear(bus_mesh); _clear(solar_panels); _clear(antenna_mount); _clear(engine_mount)
	_build_bus(bus_mesh)
	_build_solar_wings(solar_panels)
	_build_antenna(antenna_mount)
	_clear(instrument_rack)
	_using_glb_model = true
	spacecraft_root.scale = Vector3.ONE * 0.78

# ─── Materials ────────────────────────────────────────────────────────────────
func _make_materials() -> void:
	var sh := Shader.new()
	sh.code = SOLAR_SHADER
	_mat_solar = ShaderMaterial.new()
	_mat_solar.shader = sh

	_mat_gold = StandardMaterial3D.new()
	_mat_gold.albedo_color = Color(0.86, 0.66, 0.24)
	_mat_gold.metallic = 0.9
	_mat_gold.roughness = 0.34
	_mat_gold.metallic_specular = 0.7
	# faint self-illumination so rear-facing surfaces never fall into pure black
	_mat_gold.emission_enabled = true
	_mat_gold.emission = Color(0.86, 0.66, 0.24) * 0.12

	_mat_silver = StandardMaterial3D.new()
	_mat_silver.albedo_color = Color(0.80, 0.82, 0.86)
	_mat_silver.metallic = 0.9
	_mat_silver.roughness = 0.30

	_mat_dark = StandardMaterial3D.new()
	_mat_dark.albedo_color = Color(0.14, 0.15, 0.19)
	_mat_dark.metallic = 0.7
	_mat_dark.roughness = 0.5

	_mat_dish = StandardMaterial3D.new()
	_mat_dish.albedo_color = Color(0.92, 0.92, 0.95)
	_mat_dish.metallic = 0.3
	_mat_dish.roughness = 0.42

	_mat_lens = StandardMaterial3D.new()
	_mat_lens.albedo_color = Color(0.02, 0.03, 0.06)
	_mat_lens.metallic = 0.2
	_mat_lens.roughness = 0.08

	_mat_radar = StandardMaterial3D.new()
	_mat_radar.albedo_color = Color(0.72, 0.74, 0.78)
	_mat_radar.metallic = 0.9
	_mat_radar.roughness = 0.28

	_mat_orange = StandardMaterial3D.new()
	_mat_orange.albedo_color = Color(0.85, 0.42, 0.10)
	_mat_orange.metallic = 0.3
	_mat_orange.roughness = 0.55
	_mat_bell = StandardMaterial3D.new()
	_mat_bell.albedo_color = Color(0.06, 0.06, 0.08)
	_mat_bell.metallic = 0.85
	_mat_bell.roughness = 0.4
	_mat_bell.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Painted airframes (panel rings + stringer seams via shader).
	_paint_white = _mat_paint(Color(0.90, 0.91, 0.93), 0.35, 0.42, 10.0, 18.0)
	_paint_black = _mat_paint(Color(0.05, 0.055, 0.07), 0.4, 0.4, 8.0, 16.0)
	_paint_carbon = _mat_paint(Color(0.15, 0.16, 0.19), 0.55, 0.34, 11.0, 20.0)
	_paint_orange = _mat_paint(Color(0.85, 0.40, 0.09), 0.3, 0.5, 9.0, 16.0)
	_paint_steel = _mat_paint(Color(0.72, 0.74, 0.78), 0.85, 0.32, 8.0, 20.0)
	var fsh := Shader.new(); fsh.code = FLAME_SHADER
	_mat_flame = ShaderMaterial.new(); _mat_flame.shader = fsh
	_mat_plasma = StandardMaterial3D.new()
	_mat_plasma.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_plasma.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_plasma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_plasma.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_plasma.albedo_color = Color(0.35, 0.6, 1.0, 0.5)
	_mat_ion_glow = StandardMaterial3D.new()
	_mat_ion_glow.albedo_color = Color(0.2, 0.4, 0.9)
	_mat_ion_glow.metallic = 0.6
	_mat_ion_glow.roughness = 0.3
	_mat_ion_glow.emission_enabled = true
	_mat_ion_glow.emission = Color(0.3, 0.55, 1.0)
	_mat_ion_glow.emission_energy_multiplier = 2.0

# ─── Primitive helpers ────────────────────────────────────────────────────────
func _clear(node: Node) -> void:
	if not node:
		return
	for c in node.get_children():
		c.queue_free()

func _mi_box(size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi

func _mi_cyl(r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	return mi

func _mi_sphere(r: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	return mi

## Nose cone: tip points +Y, base at -Y.
func _mi_cone(r: float, h: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = r; cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi

## Painted-airframe material factory.
func _mat_paint(base: Color, metallic: float, rough: float, rings: float, seams: float) -> ShaderMaterial:
	var sh := Shader.new(); sh.code = ROCKET_PAINT_SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("metallic_v", metallic)
	m.set_shader_parameter("rough_v", rough)
	m.set_shader_parameter("rings", rings)
	m.set_shader_parameter("seams", seams)
	return m

## Revolve a 2D profile ((x = radius, y = height), top->bottom) about the Y axis.
## Produces smooth curved surfaces: ogive nose cones and de-Laval bell nozzles.
func _make_revolve(profile: PackedVector2Array, mat: Material, seg: int = 28) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last := profile.size() - 1
	var nrm := PackedVector2Array()
	for j in range(profile.size()):
		var tan: Vector2 = profile[mini(j + 1, last)] - profile[maxi(j - 1, 0)]
		if tan.length() < 1e-6:
			tan = Vector2(1.0, 0.0)
		# profile runs top->bottom (y decreasing, radius increasing); outward normal
		# is the tangent rotated +90 deg.
		nrm.append(Vector2(-tan.y, tan.x).normalized())
	for i in range(seg):
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var c0 := cos(a0); var s0 := sin(a0)
		var c1 := cos(a1); var s1 := sin(a1)
		for j in range(last):
			var p0 := profile[j]; var p1 := profile[j + 1]
			var q0 := nrm[j]; var q1 := nrm[j + 1]
			var v00 := Vector3(p0.x * c0, p0.y, p0.x * s0)
			var v01 := Vector3(p0.x * c1, p0.y, p0.x * s1)
			var v10 := Vector3(p1.x * c0, p1.y, p1.x * s0)
			var v11 := Vector3(p1.x * c1, p1.y, p1.x * s1)
			var n00 := Vector3(q0.x * c0, q0.y, q0.x * s0)
			var n01 := Vector3(q0.x * c1, q0.y, q0.x * s1)
			var n10 := Vector3(q1.x * c0, q1.y, q1.x * s0)
			var n11 := Vector3(q1.x * c1, q1.y, q1.x * s1)
			var u0 := float(i) / seg; var u1 := float(i + 1) / seg
			var t0 := float(j) / last; var t1 := float(j + 1) / last
			_tri(st, v00, n00, Vector2(u0, t0), v10, n10, Vector2(u0, t1), v11, n11, Vector2(u1, t1))
			_tri(st, v00, n00, Vector2(u0, t0), v11, n11, Vector2(u1, t1), v01, n01, Vector2(u1, t0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi

func _tri(st: SurfaceTool, a: Vector3, na: Vector3, ta: Vector2, b: Vector3, nb: Vector3, tb: Vector2, c: Vector3, nc: Vector3, tc: Vector2) -> void:
	st.set_normal(na); st.set_uv(ta); st.add_vertex(a)
	st.set_normal(nb); st.set_uv(tb); st.add_vertex(b)
	st.set_normal(nc); st.set_uv(tc); st.add_vertex(c)

## Ogive nose cone sitting on top of a body. Tip at base.y + height, base at base.y.
func _add_ogive(parent: Node, radius: float, height: float, base: Vector3, mat: Material) -> void:
	var prof := PackedVector2Array([
		Vector2(0.001, height),
		Vector2(radius * 0.5, height * 0.72),
		Vector2(radius * 0.8, height * 0.42),
		Vector2(radius * 0.96, height * 0.14),
		Vector2(radius, 0.0),
	])
	var mi := _make_revolve(prof, mat)
	mi.position = base
	parent.add_child(mi)

## De-Laval bell nozzle; throat at center.y, exit lip lower by `length`.
func _add_bell(parent: Node, throat_r: float, exit_r: float, length: float, center: Vector3, mat: Material) -> void:
	var prof := PackedVector2Array([
		Vector2(throat_r, 0.0),
		Vector2(throat_r * 1.05, -length * 0.12),
		Vector2(exit_r * 0.62, -length * 0.5),
		Vector2(exit_r * 0.86, -length * 0.82),
		Vector2(exit_r, -length),
	])
	var mi := _make_revolve(prof, mat, 20)
	mi.position = center
	parent.add_child(mi)

## Engine cluster: one centre bell + (count-1) bells around a ring, centred at `center`.
func _add_engine_cluster(parent: Node, throat_r: float, exit_r: float, length: float, center: Vector3, ring_r: float, count: int, mat: Material) -> void:
	_add_bell(parent, throat_r, exit_r, length, center, mat)
	if count > 1:
		var n := count - 1
		for i in range(n):
			var a := TAU * float(i) / n
			_add_bell(parent, throat_r, exit_r, length, center + Vector3(cos(a) * ring_r, 0.0, sin(a) * ring_r), mat)

## Grid fin: a small lattice of bars (not a solid plate).
func _add_grid_fin(parent: Node, pos: Vector3, size: float, mat: Material) -> void:
	for k in range(4):
		var bar := _mi_box(Vector3(size, size, 0.02), mat, pos + Vector3(0, 0, -size * 0.5 + size * k / 3.0))
		parent.add_child(bar)
	var spine := _mi_box(Vector3(0.03, size, size), mat, pos + Vector3(0, 0, 0))
	parent.add_child(spine)

## Flame cone: wide at the nozzle (+Y top), tapering to a tip at the bottom.
func _mi_flame_cone(top_r: float, bot_r: float, h: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = top_r; cm.bottom_radius = bot_r; cm.height = h
	cm.radial_segments = 16; cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Engine exhaust: outer plume + hot inner core + flickering glow light.
## `nozzle` is the exit-plane point; the plume fires downward (-Y).
func _add_engine_flame(parent: Node, nozzle: Vector3, radius: float, length: float) -> void:
	if _mat_flame == null:
		return
	parent.add_child(_mi_flame_cone(radius, radius * 0.10, length, _mat_flame, nozzle + Vector3(0, -length * 0.5, 0)))
	parent.add_child(_mi_flame_cone(radius * 0.55, radius * 0.04, length * 0.72, _mat_flame, nozzle + Vector3(0, -length * 0.36, 0)))
	var light := OmniLight3D.new()
	light.position = nozzle + Vector3(0, -length * 0.25, 0)
	light.light_color = Color(1.0, 0.5, 0.16)
	light.light_energy = 3.6
	light.omni_range = 4.0
	light.shadow_enabled = false
	parent.add_child(light)

# ─── Bus: gold MLI-wrapped body with decks and seam bands ─────────────────────
func _build_bus(cont: Node) -> void:
	cont.add_child(_mi_box(Vector3(1.3, 1.5, 1.2), _mat_gold, Vector3.ZERO))
	cont.add_child(_mi_box(Vector3(1.36, 0.09, 1.26), _mat_silver, Vector3(0, 0.79, 0)))
	cont.add_child(_mi_box(Vector3(1.36, 0.09, 1.26), _mat_silver, Vector3(0, -0.79, 0)))
	# MLI blanket seam bands
	for k in range(4):
		cont.add_child(_mi_box(Vector3(1.32, 0.025, 1.22), _mat_dark, Vector3(0, -0.45 + 0.3 * k, 0)))
	# equipment deck panel on the sun-facing side
	cont.add_child(_mi_box(Vector3(0.95, 1.0, 0.03), _mat_dark, Vector3(0, 0.0, 0.615)))

# ─── Solar wings: segmented, framed arrays with a cell shader ─────────────────
func _build_solar_wings(cont: Node) -> void:
	for sign_v in [-1.0, 1.0]:
		var sign: float = sign_v
		# deployable yoke boom along X
		cont.add_child(_mi_cyl(0.05, 0.05, 0.7, _mat_silver,
			Vector3(0.75 * sign, 0.0, 0.0), Vector3(0.0, 0.0, PI / 2.0)))
		var seg_w := 0.62
		var seg_h := 1.5
		var gap := 0.07
		var x: float = 1.15 * sign
		for i in range(3):
			# gold structural frame (thicker; also forms the visible rear back-sheet)
			cont.add_child(_mi_box(Vector3(seg_w + 0.09, seg_h + 0.09, 0.05), _mat_gold, Vector3(x, 0.0, 0.0)))
			# solar cell face mounted on the front half so the rear shows gold, not black
			cont.add_child(_mi_box(Vector3(seg_w, seg_h, 0.02), _mat_solar, Vector3(x, 0.0, 0.028)))
			# hinge between segments
			if i > 0:
				cont.add_child(_mi_cyl(0.035, 0.035, seg_h * 0.9, _mat_silver,
					Vector3(x - (seg_w + gap) * 0.5 * sign, 0.0, 0.0)))
			x += (seg_w + gap) * sign

# ─── Antenna: parabolic dish on a boom with feed horn ─────────────────────────
func _build_antenna(cont: Node) -> void:
	cont.add_child(_mi_cyl(0.04, 0.05, 0.55, _mat_silver, Vector3(0, 1.05, 0)))
	var dish_pos := Vector3(0, 1.35, 0.12)
	# dish: cone frustum opened toward the camera (+Z after 90° X rotation)
	cont.add_child(_mi_cyl(0.42, 0.06, 0.24, _mat_dish, dish_pos, Vector3(PI / 2.0, 0, 0)))
	# rim
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new(); tor.inner_radius = 0.40; tor.outer_radius = 0.45
	rim.mesh = tor; rim.material_override = _mat_silver
	rim.position = dish_pos; rim.rotation = Vector3(PI / 2.0, 0, 0)
	cont.add_child(rim)
	# feed horn on struts in front of the dish
	cont.add_child(_mi_cyl(0.03, 0.03, 0.28, _mat_silver, dish_pos + Vector3(0, 0, 0.2), Vector3(PI / 2.0, 0, 0)))
	cont.add_child(_mi_sphere(0.05, _mat_dark, dish_pos + Vector3(0, 0, 0.34)))

# ─── Engine: main nozzle bell + RCS thruster cluster ──────────────────────────
## Spacecraft propulsion: 3 visually distinct thrusters keyed by catalog id.
func _rebuild_engine(id: String) -> void:
	if not engine_mount:
		return
	_clear(engine_mount)
	engine_mount.add_child(_mi_box(Vector3(0.5, 0.16, 0.5), _mat_dark, Vector3(0, -0.86, 0)))
	match id:
		"prop_cold":
			# Cold gas: a tight cluster of small silver attitude ports + 4 corner RCS.
			for k in range(6):
				var a := TAU * float(k) / 6.0
				engine_mount.add_child(_mi_cyl(0.045, 0.065, 0.14, _mat_silver,
					Vector3(cos(a) * 0.2, -0.96, sin(a) * 0.2)))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					engine_mount.add_child(_mi_cyl(0.04, 0.055, 0.1, _mat_silver,
						Vector3(0.5 * sx, -0.93, 0.5 * sz)))
		"prop_ion":
			# Ion: wide Hall-effect channel, silver grid, blue glowing plasma beam.
			engine_mount.add_child(_mi_cyl(0.30, 0.34, 0.26, _mat_dark, Vector3(0, -1.0, 0)))
			engine_mount.add_child(_mi_cyl(0.30, 0.30, 0.05, _mat_silver, Vector3(0, -1.15, 0)))
			engine_mount.add_child(_mi_cyl(0.22, 0.22, 0.06, _mat_ion_glow, Vector3(0, -1.18, 0)))
			engine_mount.add_child(_mi_flame_cone(0.2, 0.04, 0.8, _mat_plasma, Vector3(0, -1.58, 0)))
			var light := OmniLight3D.new()
			light.position = Vector3(0, -1.45, 0)
			light.light_color = Color(0.3, 0.55, 1.0)
			light.light_energy = 1.8
			light.omni_range = 2.6
			light.shadow_enabled = false
			engine_mount.add_child(light)
		"prop_chemical":
			# Chemical: a large de-Laval bell with a bright orange exhaust plume.
			engine_mount.add_child(_mi_cyl(0.14, 0.14, 0.16, _mat_dark, Vector3(0, -0.94, 0)))
			_add_bell(engine_mount, 0.12, 0.30, 0.52, Vector3(0, -1.02, 0), _mat_bell)
			_add_engine_flame(engine_mount, Vector3(0, -1.54, 0), 0.22, 1.1)
		_:
			engine_mount.add_child(_mi_cyl(0.12, 0.24, 0.36, _mat_dark, Vector3(0, -1.08, 0)))

# ─── Launch vehicle: 5 visually distinct, detailed rockets under the craft ─────
## Rockets are built with their nose tip near local y=0 extending downward, then
## the container is lifted so the top sits just under the spacecraft engine bell.
func _build_rocket(id: String) -> void:
	if not rocket_mesh:
		return
	_clear(rocket_mesh)
	rocket_mesh.position = Vector3(0, -1.4, 0)
	rocket_mesh.scale = Vector3.ONE * 0.85
	match id:
		"electron":
			# Rocket Lab Electron: slim carbon body, white interstage, 9 Rutherfords
			_add_ogive(rocket_mesh, 0.28, 0.85, Vector3(0, -0.9, 0), _paint_black)
			rocket_mesh.add_child(_mi_cyl(0.29, 0.29, 0.45, _paint_white, Vector3(0, -1.12, 0)))
			rocket_mesh.add_child(_mi_cyl(0.275, 0.275, 2.5, _paint_carbon, Vector3(0, -2.6, 0)))
			rocket_mesh.add_child(_mi_cyl(0.29, 0.27, 0.35, _paint_carbon, Vector3(0, -4.0, 0)))
			_add_engine_cluster(rocket_mesh, 0.05, 0.1, 0.32, Vector3(0, -4.16, 0), 0.15, 9, _mat_bell)
			_add_engine_flame(rocket_mesh, Vector3(0, -4.48, 0), 0.17, 1.5)
		"falcon9":
			_build_falcon_core(Vector3.ZERO, true, true)
		"falcon_heavy":
			# three cores sharing a common first-stage length; centre carries the fairing
			_build_falcon_core(Vector3.ZERO, true, true)
			_build_falcon_core(Vector3(-0.98, -1.3, 0), true, false)
			_build_falcon_core(Vector3(0.98, -1.3, 0), true, false)
		"sls":
			# orange core + white Orion fairing + two segmented white SRBs w/ black noses
			rocket_mesh.add_child(_mi_cyl(0.5, 0.5, 3.1, _paint_orange, Vector3(0, -2.75, 0)))
			_add_ogive(rocket_mesh, 0.34, 1.15, Vector3(0, -1.2, 0), _paint_white)
			rocket_mesh.add_child(_mi_cyl(0.52, 0.42, 0.4, _paint_black, Vector3(0, -4.5, 0)))
			_add_engine_cluster(rocket_mesh, 0.1, 0.17, 0.5, Vector3(0, -4.68, 0), 0.22, 4, _mat_bell)
			_add_engine_flame(rocket_mesh, Vector3(0, -5.18, 0), 0.26, 1.9)
			for sx in [-0.92, 0.92]:
				_add_ogive(rocket_mesh, 0.3, 0.8, Vector3(sx, -0.85, 0), _paint_black)
				rocket_mesh.add_child(_mi_cyl(0.3, 0.3, 3.7, _paint_white, Vector3(sx, -3.1, 0)))
				for ry in [-1.6, -2.6, -3.6, -4.6]:
					rocket_mesh.add_child(_mi_cyl(0.315, 0.315, 0.06, _mat_dark, Vector3(sx, ry, 0)))
				_add_bell(rocket_mesh, 0.12, 0.28, 0.5, Vector3(sx, -4.95, 0), _mat_bell)
				_add_engine_flame(rocket_mesh, Vector3(sx, -5.45, 0), 0.22, 1.7)
		"starship":
			# stainless two-stage: ogive nose, window band, forward + aft flaps, hot-stage
			_add_ogive(rocket_mesh, 0.62, 1.6, Vector3(0, -1.65, 0), _paint_steel)
			rocket_mesh.add_child(_mi_cyl(0.62, 0.62, 1.7, _paint_steel, Vector3(0, -2.5, 0)))
			rocket_mesh.add_child(_mi_cyl(0.628, 0.628, 0.12, _mat_dark, Vector3(0, -2.1, 0)))
			for sx in [-0.62, 0.62]:
				var ff := _mi_box(Vector3(0.06, 0.7, 0.42), _paint_steel, Vector3(sx, -2.2, 0))
				ff.rotation_degrees = Vector3(0, 0, -22.0 * sign(sx))
				rocket_mesh.add_child(ff)
			rocket_mesh.add_child(_mi_cyl(0.64, 0.64, 0.16, _paint_black, Vector3(0, -3.44, 0)))
			rocket_mesh.add_child(_mi_cyl(0.62, 0.62, 1.9, _paint_steel, Vector3(0, -4.47, 0)))
			for sx in [-0.62, 0.62]:
				var af := _mi_box(Vector3(0.06, 0.9, 0.5), _paint_steel, Vector3(sx, -4.3, 0))
				af.rotation_degrees = Vector3(0, 0, -15.0 * sign(sx))
				rocket_mesh.add_child(af)
			rocket_mesh.add_child(_mi_cyl(0.62, 0.66, 0.4, _paint_black, Vector3(0, -5.5, 0)))
			_add_engine_cluster(rocket_mesh, 0.08, 0.15, 0.45, Vector3(0, -5.68, 0), 0.4, 13, _mat_bell)
			_add_engine_flame(rocket_mesh, Vector3(0, -6.13, 0), 0.46, 2.2)
		_:
			# generic fallback booster
			_add_ogive(rocket_mesh, 0.42, 1.1, Vector3(0, -1.15, 0), _paint_white)
			rocket_mesh.add_child(_mi_cyl(0.42, 0.42, 2.8, _paint_white, Vector3(0, -3.15, 0)))
			rocket_mesh.add_child(_mi_cyl(0.44, 0.36, 0.4, _paint_black, Vector3(0, -4.75, 0)))
			_add_engine_cluster(rocket_mesh, 0.07, 0.13, 0.4, Vector3(0, -4.93, 0), 0.18, 5, _mat_bell)
			_add_engine_flame(rocket_mesh, Vector3(0, -5.33, 0), 0.22, 1.5)

## A single Falcon-9-style core built at `origin` (nose tip at origin.y):
## white painted body, black interstage, grid-fin lattices, landing legs, 9 Merlins.
func _build_falcon_core(origin: Vector3, with_legs: bool, with_fairing: bool) -> void:
	var r := 0.4
	var nose_h := 1.6 if with_fairing else 0.6
	var nb := origin.y - nose_h   # nose base (body top)
	_add_ogive(rocket_mesh, r, nose_h, Vector3(origin.x, nb, origin.z), _paint_white)
	rocket_mesh.add_child(_mi_cyl(r, r, 2.0, _paint_white, Vector3(origin.x, nb - 1.0, origin.z)))
	rocket_mesh.add_child(_mi_cyl(r + 0.015, r + 0.015, 0.5, _paint_black, Vector3(origin.x, nb - 2.25, origin.z)))
	rocket_mesh.add_child(_mi_cyl(r, r, 1.6, _paint_white, Vector3(origin.x, nb - 3.3, origin.z)))
	var es := nb - 4.35
	rocket_mesh.add_child(_mi_cyl(r, r * 0.85, 0.7, _paint_black, Vector3(origin.x, es, origin.z)))
	for sx in [-1.0, 1.0]:
		_add_grid_fin(rocket_mesh, Vector3(origin.x + sx * (r + 0.04), nb - 0.7, origin.z), 0.42, _mat_dark)
	if with_legs:
		for k in range(4):
			var a := TAU * float(k) / 4.0 + PI / 4.0
			rocket_mesh.add_child(_mi_box(Vector3(0.07, 2.3, 0.07), _paint_black,
				Vector3(origin.x + cos(a) * r * 0.92, nb - 3.2, origin.z + sin(a) * r * 0.92)))
	_add_engine_cluster(rocket_mesh, 0.055, 0.11, 0.42, Vector3(origin.x, es - 0.33, origin.z), 0.2, 9, _mat_bell)
	_add_engine_flame(rocket_mesh, Vector3(origin.x, es - 0.75, origin.z), 0.24, 1.7)

## Reframes the orbit camera so both the spacecraft and the tall launch stack fit.
func _apply_framing(active: bool) -> void:
	if active:
		_cam_target = Vector3(0, -3.0, 0)
	else:
		_cam_target = Vector3.ZERO
	var tz: float = 15.5 if active else 8.0
	var tw := create_tween()
	tw.tween_method(_set_cam_zoom, _cam_zoom, tz, 0.5)
	_update_cam()

func _rebuild_instruments() -> void:
	if not instrument_rack:
		return
	_clear(instrument_rack)
	var instruments: Array = GameManager.spacecraft_config.get("instruments", [])
	# deck slots on the bus top surface (2 rows x 3 cols)
	var slots := [
		Vector3(-0.42, 0.86, -0.30), Vector3(0.0, 0.86, -0.30), Vector3(0.42, 0.86, -0.30),
		Vector3(-0.42, 0.86,  0.30), Vector3(0.0, 0.86,  0.30), Vector3(0.42, 0.86,  0.30),
	]
	for i in range(instruments.size()):
		if i >= slots.size():
			break
		var node := _make_instrument_node(instruments[i])
		node.position = slots[i]
		instrument_rack.add_child(node)

func _mat_instrument(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.45
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col * 0.3
	return m

## Builds type-specific instrument hardware so each payload reads as real
## scientific gear instead of a plain colored box.
func _make_instrument_node(inst: Dictionary) -> Node3D:
	var g := Node3D.new()
	var col: Color = inst.get("color", Color.CYAN)
	var id: String = inst.get("id", "")
	var accent := _mat_instrument(col)
	# mounting base plate (shared)
	g.add_child(_mi_box(Vector3(0.34, 0.05, 0.34), _mat_dark, Vector3(0, 0.025, 0)))

	if id == "camera_hires":
		# long telescope tube with a dark lens at the aperture
		g.add_child(_mi_cyl(0.11, 0.12, 0.36, accent, Vector3(0, 0.24, 0)))
		g.add_child(_mi_cyl(0.125, 0.125, 0.03, _mat_lens, Vector3(0, 0.43, 0)))
		g.add_child(_mi_cyl(0.13, 0.11, 0.06, _mat_dark, Vector3(0, 0.46, 0)))
	elif id == "camera_wide":
		# compact body with a domed wide-angle lens
		g.add_child(_mi_box(Vector3(0.28, 0.22, 0.26), accent, Vector3(0, 0.16, 0)))
		var dome := _mi_sphere(0.11, _mat_lens, Vector3(0, 0.16, 0.15))
		dome.scale = Vector3(1, 1, 0.6)
		g.add_child(dome)
	elif id == "thermal":
		# radiator-shrouded IR telescope
		g.add_child(_mi_cyl(0.10, 0.10, 0.26, accent, Vector3(0, 0.20, 0)))
		g.add_child(_mi_cyl(0.14, 0.10, 0.10, _mat_silver, Vector3(0, 0.36, 0)))
		g.add_child(_mi_cyl(0.105, 0.105, 0.02, _mat_lens, Vector3(0, 0.41, 0)))
	elif id == "spectrometer":
		# instrument box with a slit aperture and detector dome
		g.add_child(_mi_box(Vector3(0.30, 0.24, 0.26), accent, Vector3(0, 0.17, 0)))
		g.add_child(_mi_box(Vector3(0.20, 0.03, 0.28), _mat_lens, Vector3(0, 0.30, 0)))
		g.add_child(_mi_sphere(0.06, _mat_silver, Vector3(0.1, 0.30, -0.12)))
	elif id == "radar":
		# flat SAR panel antenna tilted on a support boom
		g.add_child(_mi_cyl(0.03, 0.03, 0.28, _mat_silver, Vector3(0, 0.18, 0)))
		var panel := _mi_box(Vector3(0.52, 0.03, 0.34), _mat_radar, Vector3(0, 0.34, 0))
		panel.rotation_degrees = Vector3(-22, 0, 0)
		g.add_child(panel)
		var trim := _mi_box(Vector3(0.52, 0.04, 0.03), accent, Vector3(0, 0.34, 0.17))
		trim.rotation_degrees = Vector3(-22, 0, 0)
		g.add_child(trim)
	elif id == "magnetometer":
		# angled boom with sensor spheres at the tip
		g.add_child(_mi_cyl(0.022, 0.022, 0.5, _mat_silver,
			Vector3(0.16, 0.30, 0), Vector3(0, 0, -PI / 3.0)))
		g.add_child(_mi_sphere(0.05, accent, Vector3(0.34, 0.50, 0)))
		g.add_child(_mi_sphere(0.038, accent, Vector3(0.44, 0.56, 0)))
	else:
		g.add_child(_mi_box(Vector3(0.28, 0.24, 0.28), accent, Vector3(0, 0.17, 0)))
	return g

func _update_3d_spacecraft() -> void:
	var cfg: Dictionary = GameManager.spacecraft_config

	var bus: Dictionary = cfg.get("bus", {})
	if bus_mesh:
		if bus.is_empty():
			bus_mesh.hide()
		else:
			bus_mesh.show()
			var s_map := {"bus_small": 0.7, "bus_medium": 1.0, "bus_large": 1.35}
			var s: float = s_map.get(bus.get("id", ""), 1.0)
			bus_mesh.scale = Vector3(s, s, s)
			if not _using_glb_model:
				_apply_material(bus_mesh, bus.get("color", Color.GRAY), 0.7, 0.3, false)

	if solar_panels:
		var pw: Dictionary = cfg.get("power", {})
		if pw.is_empty():
			solar_panels.hide()
		else:
			solar_panels.show()
			var ps_map := {"solar_small": 0.7, "solar_medium": 1.0, "solar_large": 1.3, "rtg": 0.5}
			var ps: float = ps_map.get(pw.get("id", ""), 1.0)
			solar_panels.scale = Vector3(ps, ps, ps)
			if not _using_glb_model:
				_apply_material(solar_panels, pw.get("color", Color.YELLOW), 0.4, 0.4, true)

	if antenna_mount:
		var comms: Dictionary = cfg.get("comms", {})
		if comms.is_empty():
			antenna_mount.hide()
		else:
			antenna_mount.show()
			if not _using_glb_model:
				_apply_material(antenna_mount, comms.get("color", Color(0.8, 0.8, 0.9)), 0.8, 0.2, false)

	if instrument_rack:
		_rebuild_instruments()

	if engine_mount:
		var prop: Dictionary = cfg.get("propulsion", {})
		var pid: String = prop.get("id", "")
		if pid == "" or pid == "prop_none":
			engine_mount.hide()
			_last_prop_id = ""
		else:
			if pid != _last_prop_id:
				_rebuild_engine(pid)
				_last_prop_id = pid
			engine_mount.show()

	if rocket_mesh:
		var rocket: Dictionary = cfg.get("rocket", {})
		if rocket.is_empty():
			rocket_mesh.hide()
			if _rocket_present:
				_rocket_present = false
				_apply_framing(false)
		else:
			var rid: String = rocket.get("id", "")
			if rid != _last_rocket_id:
				_build_rocket(rid)
				_last_rocket_id = rid
			rocket_mesh.show()
			if not _rocket_present:
				_rocket_present = true
				_apply_framing(true)

func _apply_material(node: Node, color: Color, metallic: float, roughness: float, emissive: bool) -> void:
	for child in _collect_meshes(node):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		if emissive:
			m.emission_enabled = true
			m.emission = color * 0.25
		child.material_override = m

func _collect_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_meshes(c))
	return out

# ══════════════════════════════════════════════════════════════════════════════
# CAMERA ORBIT + IDLE ROTATION
# ══════════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	# Gentle idle rotation when user hasn't touched the viewport recently
	if Time.get_ticks_msec() - _last_interaction_ms > 3000 and not _mouse_dragging:
		_cam_yaw += delta * 3.0
		_update_cam()

func _on_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_dragging = event.pressed
			_last_interaction_ms = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = max(3.0, _cam_zoom - 0.6)
			_update_cam()
			_last_interaction_ms = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = min(18.0, _cam_zoom + 0.6)
			_update_cam()
			_last_interaction_ms = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_dragging:
		_cam_yaw   -= event.relative.x * 0.5
		_cam_pitch  = clamp(_cam_pitch - event.relative.y * 0.3, -75.0, 75.0)
		_update_cam()
		_last_interaction_ms = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()

func _update_cam() -> void:
	if not orbit_camera:
		return
	var off := Vector3(
		sin(deg_to_rad(_cam_yaw)) * cos(deg_to_rad(_cam_pitch)),
		sin(deg_to_rad(_cam_pitch)),
		cos(deg_to_rad(_cam_yaw)) * cos(deg_to_rad(_cam_pitch))
	) * _cam_zoom
	var pos := _cam_target + off
	orbit_camera.position = pos
	orbit_camera.look_at_from_position(pos, _cam_target, Vector3.UP)

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY ANIMATIONS
# ══════════════════════════════════════════════════════════════════════════════
func _play_entry_animations() -> void:
	var left := get_node_or_null("UI/MainLayout/VBox/MainContent/LeftPanel")
	var right := get_node_or_null("UI/MainLayout/VBox/MainContent/RightPanel")
	var top := get_node_or_null("UI/MainLayout/VBox/TopBar")
	var bot := get_node_or_null("UI/MainLayout/VBox/BottomBar")
	if left:
		left.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(left, "modulate:a", 1.0, 0.4)
	if right:
		right.modulate.a = 0.0
		var tw2 := create_tween()
		tw2.tween_property(right, "modulate:a", 1.0, 0.4).set_delay(0.05)
	if top:
		top.modulate.a = 0.0
		var tw3 := create_tween()
		tw3.tween_property(top, "modulate:a", 1.0, 0.3)
	if bot:
		bot.modulate.a = 0.0
		var tw4 := create_tween()
		tw4.tween_property(bot, "modulate:a", 1.0, 0.3).set_delay(0.1)

# ══════════════════════════════════════════════════════════════════════════════
# BUTTON CALLBACKS
# ══════════════════════════════════════════════════════════════════════════════
func _on_continue_pressed() -> void:
	GameManager.go_to_launch()

func _on_back_pressed() -> void:
	GameManager.go_to_scene("res://scenes/ui/mission_select.tscn")
