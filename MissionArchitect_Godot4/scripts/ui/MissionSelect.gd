## MissionSelect.gd
## Mission selection screen — 4 mission cards with full details

extends Control

var mission_grid: HBoxContainer
var difficulty_btns: HBoxContainer
var selected_label: Label
var begin_btn: Button
var back_btn: Button

const DIFFICULTIES: Array = ["Cadet", "Engineer", "Director", "Legend"]
const DIFF_BUDGET_MULT: Array = [1.3, 1.0, 0.8, 0.6]
const DIFF_COLORS: Array = [
	Color("#39D6FF"), Color("#4F9DFF"), Color("#FFB347"), Color("#FF6B4A")
]

# ─── Coloured palette (matches the title-screen concept art) ─────────────────
const C_PAGE   := Color(0.008, 0.031, 0.071)
const C_PANEL  := Color(0.02, 0.055, 0.105, 0.94)
const C_CYAN   := Color(0.20, 0.84, 1.0)
const C_ORANGE := Color(1.0, 0.62, 0.14)
const C_TEXT   := Color("#FFFFFF")
const C_DIM    := Color(0.56, 0.68, 0.80)
const C_LINE   := Color(0.12, 0.42, 0.66)
const C_BTN    := Color(0.035, 0.09, 0.16)

var selected_mission_id: String = ""
var selected_difficulty: String = "Cadet"
var _card_data: Array = []
var hangar_viewport: SubViewport
var hangar_time: float = 0.0
# Animated hangar elements collected while the 3D bay is built so _process
# can pulse, flicker and rotate them (idle VFX, no gameplay cost).
var _hangar_rings: Array[MeshInstance3D] = []
var _hangar_bay_lights: Array[OmniLight3D] = []
var _hangar_engine_lights: Array[OmniLight3D] = []
var _hangar_planets: Array[MeshInstance3D] = []
var _hangar_camera: Camera3D = null
var _hangar_cam_base: Vector3 = Vector3.ZERO

func _ready() -> void:
	mission_grid      = _g("ScrollContainer/MissionGrid")
	difficulty_btns   = _g("BottomBar/DifficultyButtons")
	selected_label    = _g("BottomBar/SelectedLabel")
	begin_btn         = _g("BottomBar/BeginButton")
	back_btn          = _g("BottomBar/BackButton")

	if begin_btn:
		begin_btn.disabled = true  # enabled when mission selected
		begin_btn.pressed.connect(_on_begin_pressed)
		begin_btn.tooltip_text = "Select a mission first"
		# Debug: print to confirm node found
		print("[MissionSelect] begin_btn found: ", begin_btn.name)
	else:
		push_error("[MissionSelect] begin_btn NOT FOUND at BottomBar/BeginButton")
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)

	# This page keeps the concept-art colours, including the 3D hangar preview.
	MissionForge.colorize(self)
	_style_navigation()
	_build_3d_hangar()
	_build_difficulty_buttons()
	_build_mission_cards()
	if selected_label:
		selected_label.text = "Selected:  None"
	print("[MissionSelect] Ready — %d missions loaded" % GameManager.missions.size())

func _g(path: String) -> Node:
	return get_node_or_null(path)

func _style_navigation() -> void:
	var page_bg := _g("Background") as ColorRect
	if page_bg:
		page_bg.color = C_PAGE
	var header := _g("Header") as PanelContainer
	if header:
		var header_style := StyleBoxFlat.new()
		header_style.bg_color = Color(0.0, 0.03, 0.07, 0.94)
		header_style.border_color = C_LINE
		header_style.border_width_bottom = 1
		header_style.border_width_left = 0
		header_style.border_width_right = 0
		header_style.set_corner_radius_all(0)
		header_style.content_margin_left = 24
		header_style.content_margin_right = 24
		header_style.content_margin_top = 0
		header_style.content_margin_bottom = 0
		header.add_theme_stylebox_override("panel", header_style)
	var header_content := _g("Header/HeaderContent") as HBoxContainer
	if header_content:
		header_content.add_theme_constant_override("separation", 18)
	var heading := _g("Header/HeaderContent/HeaderLabel") as Label
	if heading:
		heading.text = "MISSION ARCHITECT   —   SELECT YOUR MISSION"
		heading.add_theme_color_override("font_color", C_TEXT)
		heading.add_theme_font_size_override("font_size", 24)
	var nav_items := _g("Header/HeaderContent/NavItems") as HBoxContainer
	if nav_items:
		nav_items.add_theme_constant_override("separation", 18)
		for item in nav_items.get_children():
			if item is Label:
				item.add_theme_color_override("font_color", C_DIM)
				item.add_theme_font_size_override("font_size", 13)
	var backing := _g("BottomBacking") as ColorRect
	if backing:
		backing.color = Color(0.0, 0.03, 0.07, 0.96)
	var bottom := _g("BottomBar") as HBoxContainer
	if bottom:
		bottom.add_theme_constant_override("separation", 10)
	var difficulty_label := _g("BottomBar/DifficultyLabel") as Label
	if difficulty_label:
		difficulty_label.add_theme_color_override("font_color", C_DIM)
		difficulty_label.add_theme_font_size_override("font_size", 14)
	if begin_btn:
		begin_btn.custom_minimum_size = Vector2(188, 46)
		_style_button(begin_btn, true)
	if back_btn:
		_style_button(back_btn, false)
	if selected_label:
		selected_label.add_theme_color_override("font_color", C_TEXT)
		selected_label.add_theme_font_size_override("font_size", 15)

func _style_button(button: Button, primary: bool = false, accent: Color = C_CYAN) -> void:
	button.add_theme_font_size_override("font_size", 14)
	var edge := Color(accent.r, accent.g, accent.b, 0.55)
	if primary:
		button.add_theme_stylebox_override("normal", MissionForge.flat(accent, accent, 0, 3))
		button.add_theme_stylebox_override("hover", MissionForge.flat(accent.lightened(0.22), accent.lightened(0.22), 0, 3))
		button.add_theme_stylebox_override("pressed", MissionForge.flat(accent.darkened(0.18), accent.darkened(0.18), 0, 3))
		button.add_theme_stylebox_override("focus", MissionForge.flat(accent.lightened(0.22), accent.lightened(0.22), 0, 3))
		button.add_theme_stylebox_override("disabled", MissionForge.flat(Color("#081422"), C_LINE, 1, 3))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(key, Color("#000000"))
		button.add_theme_color_override("font_disabled_color", C_DIM)
	else:
		button.add_theme_stylebox_override("normal", MissionForge.flat(C_BTN, edge, 1, 3))
		button.add_theme_stylebox_override("hover", MissionForge.flat(Color(0.05, 0.14, 0.24), accent, 1, 3))
		button.add_theme_stylebox_override("pressed", MissionForge.flat(accent, accent, 0, 3))
		button.add_theme_stylebox_override("focus", MissionForge.flat(Color(0.05, 0.14, 0.24), accent, 1, 3))
		button.add_theme_stylebox_override("disabled", MissionForge.flat(Color("#081422"), C_LINE, 1, 3))
		button.add_theme_color_override("font_color", accent.lightened(0.35))
		button.add_theme_color_override("font_hover_color", C_TEXT)
		button.add_theme_color_override("font_pressed_color", Color("#000000"))
		button.add_theme_color_override("font_focus_color", C_TEXT)
		button.add_theme_color_override("font_disabled_color", C_DIM)

## Toggle control: dark navy idle, accent border and tint when selected.
func _style_toggle(button: Button, accent: Color) -> void:
	var edge := Color(accent.r, accent.g, accent.b, 0.45)
	var pressed := MissionForge.flat(Color(accent.r, accent.g, accent.b, 0.18), accent, 2, 3)
	button.add_theme_stylebox_override("normal", MissionForge.flat(Color("#081422"), C_LINE, 1, 3))
	button.add_theme_stylebox_override("hover", MissionForge.flat(Color(0.05, 0.14, 0.24), edge, 1, 3))
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", MissionForge.flat(Color(0.05, 0.14, 0.24), edge, 1, 3))
	button.add_theme_stylebox_override("disabled", MissionForge.flat(Color("#081422"), C_LINE, 1, 3))
	button.add_theme_color_override("font_hover_color", accent.lightened(0.3))
	button.add_theme_color_override("font_pressed_color", accent)
	button.add_theme_color_override("font_focus_color", accent)
	button.add_theme_font_size_override("font_size", 14)

func _process(delta: float) -> void:
	if hangar_viewport == null:
		return
	hangar_time += delta
	var t := hangar_time
	# Rockets gently sway and hover on their stands like service-positioned
	# vehicles being integrated rather than static props.
	for entry in _card_data:
		var rocket: Node3D = entry.get("rocket")
		if is_instance_valid(rocket):
			rocket.rotation.y = sin(t * 0.25 + float(entry["index"])) * 0.10
			rocket.position.y = 2.25 + sin(t * 0.8 + float(entry["index"]) * 1.7) * 0.035
	# Pad halo rings breathe with the bay light colour.
	for i in _hangar_rings.size():
		var ring := _hangar_rings[i]
		if is_instance_valid(ring) and ring.material_override is StandardMaterial3D:
			(ring.material_override as StandardMaterial3D).emission_energy_multiplier = 2.4 + sin(t * 2.2 + float(i) * 1.3) * 1.2
	# Bay lights idle-flicker like industrial vapour lamps.
	for i in _hangar_bay_lights.size():
		var light := _hangar_bay_lights[i]
		if is_instance_valid(light):
			light.light_energy = 1.25 + sin(t * 3.1 + float(i) * 2.9) * 0.18 + randf_range(-0.04, 0.04)
	# Engine glow lights shimmer under each vehicle.
	for i in _hangar_engine_lights.size():
		var glight := _hangar_engine_lights[i]
		if is_instance_valid(glight):
			glight.light_energy = 1.7 + sin(t * 5.5 + float(i)) * 0.5 + randf_range(-0.1, 0.1)
	# Planets and moons slowly spin; Earth's cloud layer reads movement.
	for planet in _hangar_planets:
		if is_instance_valid(planet):
			planet.rotate_y(delta * 0.07)
	# Cinematic camera drift keeps the shot alive without stealing focus.
	if _hangar_camera:
		_hangar_camera.position = _hangar_cam_base + Vector3(sin(t * 0.06) * 1.6, sin(t * 0.09) * 0.35, 0.0)
		_hangar_camera.look_at(Vector3(0.0, 1.0, -2.0), Vector3.UP)

# ─── Difficulty buttons ───────────────────────────────────────────────────────
func _build_difficulty_buttons() -> void:
	if not difficulty_btns:
		return
	for i in range(DIFFICULTIES.size()):
		var btn := Button.new()
		btn.text = DIFFICULTIES[i]
		btn.toggle_mode = true
		btn.button_pressed = (DIFFICULTIES[i] == selected_difficulty)
		btn.custom_minimum_size = Vector2(88, 38)
		btn.size_flags_stretch_ratio = 1.0
		_style_toggle(btn, DIFF_COLORS[i])
		btn.add_theme_color_override("font_color", DIFF_COLORS[i])
		btn.pressed.connect(_on_difficulty_selected.bind(DIFFICULTIES[i], btn))
		difficulty_btns.add_child(btn)

# ─── Mission cards ────────────────────────────────────────────────────────────
func _build_mission_cards() -> void:
	if not mission_grid:
		push_error("[MissionSelect] mission_grid node not found!")
		return

	for child in mission_grid.get_children():
		child.queue_free()
	_card_data.clear()

	for mission in GameManager.missions:
		var card := _make_card(mission)
		mission_grid.add_child(card)

func _make_card(mission: Dictionary) -> PanelContainer:
	var mission_index: int = GameManager.missions.find(mission)
	var card_colors: Array[Color] = [
		Color(0.0, 0.68, 1.0),
		Color(1.0, 0.64, 0.04),
		Color(1.0, 0.25, 0.12),
		Color(0.68, 0.2, 1.0)
	]
	var col: Color = card_colors[mission_index % card_colors.size()] if mission_index >= 0 else mission.get("color", Color.CYAN)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 280)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = Color(col.r, col.g, col.b, 0.45)
	sb.set_border_width_all(1)
	sb.border_width_top = 3
	sb.set_corner_radius_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	sb.content_margin_left   = 20
	sb.content_margin_right  = 20
	sb.content_margin_top    = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)

	var icon_bg := PanelContainer.new()
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(col.r, col.g, col.b, 0.16)
	icon_style.border_color = Color(col.r, col.g, col.b, 0.6)
	icon_style.set_border_width_all(1)
	icon_style.set_corner_radius_all(2)
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	icon_bg.custom_minimum_size = Vector2(32, 32)
	icon_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(icon_bg)

	var badge := Label.new()
	badge.text = "MISSION %02d" % (GameManager.missions.find(mission) + 1)
	badge.add_theme_color_override("font_color", col.lightened(0.25))
	badge.add_theme_font_size_override("font_size", 12)
	header_row.add_child(badge)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	# Header must live inside the same VBox as the content — two direct
	# PanelContainer children stack on top of each other and overlap.
	vbox.add_child(header_row)

	var title := Label.new()
	title.text = mission.get("name", "?")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = mission.get("subtitle", mission.get("description", ""))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_color_override("font_color", C_DIM)
	sub.add_theme_font_size_override("font_size", 12)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.y = 48
	vbox.add_child(sub)

	var divider := HSeparator.new()
	divider.modulate = C_LINE
	vbox.add_child(divider)
	var stats: Array = [
		["◎", "Target", mission.get("target", "?")],
		["▦", "Duration", "%d days" % mission.get("duration_days", 365)],
		["◉", "Budget", "$%dM" % mission.get("budget", 0)],
		["⬡", "Mass limit", "%d kg" % mission.get("mass_limit", 0)],
		["✦", "Science goal", "%d pts" % mission.get("science_goal", 0)],
		["✦", "Difficulty", mission.get("difficulty", "?")],
	]
	for stat_data in stats:
		var stat := Label.new()
		stat.text = "%s  %s:  %s" % stat_data
		stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat.add_theme_color_override("font_color", C_DIM)
		stat.add_theme_font_size_override("font_size", 12)
		vbox.add_child(stat)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = "SELECT MISSION   »"
	btn.custom_minimum_size = Vector2(0, 42)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn, false, col)
	btn.pressed.connect(_on_card_selected.bind(mission.get("id",""), panel, sb, mission))
	vbox.add_child(btn)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_card_selected(mission.get("id",""), panel, sb, mission)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_entered.connect(func() -> void:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "scale", Vector2(1.02, 1.02), 0.12)
	)
	panel.mouse_exited.connect(func() -> void:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.12)
	)

	var rocket: Node3D = _make_mission_rocket(mission_index, col)
	if hangar_viewport and hangar_viewport.get_child_count() > 0:
		hangar_viewport.get_child(0).add_child(rocket)
		rocket.position.x = [-9.0, -3.0, 3.0, 9.0][mission_index % 4]
	_card_data.append({"id": mission.get("id",""), "panel": panel, "sb": sb, "col": col, "rocket": rocket, "index": mission_index})
	return panel

func _build_3d_hangar() -> void:
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "MissionHangar3D"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.stretch = true
	hangar_viewport = SubViewport.new()
	hangar_viewport.size = Vector2i(1280, 720)
	hangar_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(hangar_viewport)
	add_child(viewport_container)
	move_child(viewport_container, 1)

	var world := Node3D.new()
	world.name = "MissionHangarWorld"
	world.position.y = 2.2  # raise the stage so vehicles sit nose-to-pad
	                          # fully in the strip above the mission cards
	hangar_viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assets/textures/starfield-v1.png") as Texture2D
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_energy_multiplier = 0.8
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.38, 0.46, 0.64)
	environment.ambient_light_energy = 0.72
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.12
	# Close-the-gap rendering quality: filmic tone mapping + SSAO + SSR give
	# the scene PBR-grade depth (grounded corners, glossy floor reflections)
	# without any per-object material rewrites.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 1.6
	environment.ssr_enabled = true
	environment_node.environment = environment
	world.add_child(environment_node)

	var camera := Camera3D.new()
	# Slightly tighter distance and a higher look-target so each vehicle is
	# framed nose-to-nozzle with headroom for the fairing tip.
	camera.position = Vector3(0.0, 8.2, 27.5)
	camera.fov = 40.0
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 2.4, -2.0), Vector3.UP)
	camera.current = true
	_hangar_camera = camera
	_hangar_cam_base = camera.position
	_hangar_rings.clear()
	_hangar_bay_lights.clear()
	_hangar_engine_lights.clear()
	_hangar_planets.clear()

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, -24.0, 0.0)
	key_light.light_color = Color(0.76, 0.84, 1.0)
	key_light.light_energy = 1.9
	world.add_child(key_light)

	var wing_backdrop := MeshInstance3D.new()
	var backdrop_mesh := PlaneMesh.new()
	backdrop_mesh.size = Vector2(35.0, 17.5)
	wing_backdrop.mesh = backdrop_mesh
	wing_backdrop.position = Vector3(0.0, 7.0, -18.0)
	var wall_material := StandardMaterial3D.new()
	# VAB interior photo is optional; fall back to a hangar-blue tint when the
	# asset hasn't been added yet so the backdrop still renders.
	var backdrop_tex := ResourceLoader.exists("res://assets/textures/nasa-artemis-vab-interior.jpg")
	if backdrop_tex:
		wall_material.albedo_texture = load("res://assets/textures/nasa-artemis-vab-interior.jpg") as Texture2D
	else:
		wall_material.albedo_color = Color(0.05, 0.09, 0.16)
	wall_material.emission_enabled = true
	wall_material.emission = Color(0.14, 0.22, 0.4)
	wall_material.emission_energy_multiplier = 0.35
	wall_material.roughness = 0.9
	wing_backdrop.material_override = wall_material
	world.add_child(wing_backdrop)

	_add_hangar_floor(world)
	_add_hangar_frame(world)
	_add_wall_dressing(world)

	for i in range(GameManager.missions.size()):
		var x: float = [-9.0, -3.0, 3.0, 9.0][i % 4]
		var tint: Color = GameManager.missions[i].get("color", Color.CYAN)
		_add_hangar_box(world, Vector3(x, -0.05, -0.2), Vector3(4.8, 0.3, 5.0), Color(0.018, 0.032, 0.06), 0.46, 0.12)
		_add_hangar_box(world, Vector3(x, 0.12, -0.2), Vector3(3.9, 0.08, 4.1), Color(0.035, 0.055, 0.085), 0.38, 0.18)
		var pad := MeshInstance3D.new()
		var pad_mesh := CylinderMesh.new()
		pad_mesh.top_radius = 1.78
		pad_mesh.bottom_radius = 1.92
		pad_mesh.height = 0.3
		pad_mesh.radial_segments = 64
		pad.mesh = pad_mesh
		# Lifted to bay-local y2.3 so the pad + halo ring peek above the card
		# line like the concept art, under the hovering vehicle.
		pad.position = Vector3(x, 2.3, -0.2)
		pad.material_override = _make_material(Color(0.1, 0.13, 0.18), 0.34, 0.12)
		world.add_child(pad)
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 1.68
		ring_mesh.outer_radius = 1.8
		ring_mesh.rings = 64
		ring_mesh.ring_segments = 12
		ring.mesh = ring_mesh
		ring.position = Vector3(x, 2.47, -0.2)
		ring.material_override = _make_material(tint.lightened(0.2), 0.24, 3.0)
		world.add_child(ring)
		_hangar_rings.append(ring)
		# Mirror-polish apron under the pad: catches the halo ring and the
		# engine light like the wet hangar floor of the concept art.
		var pool := MeshInstance3D.new()
		var pool_mesh := BoxMesh.new()
		pool_mesh.size = Vector3(5.0, 0.04, 2.0)
		pool.mesh = pool_mesh
		pool.position = Vector3(x, 2.3, -0.2)
		var pool_mat := StandardMaterial3D.new()
		pool_mat.albedo_color = Color(0.03, 0.05, 0.08, 1.0)
		pool_mat.metallic = 0.95
		pool_mat.roughness = 0.08
		pool_mat.emission_enabled = true
		pool_mat.emission = Color(tint.r * 0.25, tint.g * 0.25, tint.b * 0.3)
		pool_mat.emission_energy_multiplier = 1.4
		pool.material_override = pool_mat
		world.add_child(pool)
		# Overhead work light: a warm spot straight down every bay, plus a soft
		# additive cone so the air between trusses reads as a light shaft.
		var shaft := SpotLight3D.new()
		shaft.position = Vector3(x, 12.0, 0.2)
		shaft.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
		shaft.spot_range = 18.0
		shaft.spot_angle = 23.0
		shaft.light_color = Color(1.0, 0.86, 0.66)
		shaft.light_energy = 2.4
		shaft.shadow_enabled = true
		world.add_child(shaft)
		var shaft_cone := MeshInstance3D.new()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.55
		cone_mesh.bottom_radius = 3.2
		cone_mesh.height = 11.6
		cone_mesh.radial_segments = 24
		cone_mesh.cap_top = false
		cone_mesh.cap_bottom = false
		shaft_cone.mesh = cone_mesh
		shaft_cone.position = Vector3(x, 6.2, 0.4)
		var cone_mat := StandardMaterial3D.new()
		cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Brighter than the usual 0.05 so the shafts read as warm hangar
		# beams between the trusses rather than faint tinted cones.
		cone_mat.albedo_color = Color(1.0, 0.9, 0.76, 0.1)
		cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		shaft_cone.material_override = cone_mat
		shaft_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(shaft_cone)
		_add_dust_sparks(world, x, tint)
		_make_bay_planet(world, i, x, tint)
		var bay_light := OmniLight3D.new()
		bay_light.position = Vector3(x, 9.5, 1.0)
		bay_light.light_color = tint
		bay_light.light_energy = 1.4
		bay_light.omni_range = 12.0
		world.add_child(bay_light)
		_hangar_bay_lights.append(bay_light)
		var bay_title := Label3D.new()
		bay_title.text = "BAY %02d" % (i + 1)
		bay_title.font_size = 36
		bay_title.pixel_size = 0.008
		bay_title.modulate = tint.lightened(0.28)
		bay_title.outline_size = 4
		bay_title.outline_modulate = Color(0.008, 0.015, 0.04, 1.0)
		bay_title.position = Vector3(x - 0.7, 11.5, -10.8)
		world.add_child(bay_title)

func _add_hangar_floor(parent: Node3D) -> void:
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(34.0, 30.0)
	floor.mesh = floor_mesh
	# Raised to bay-local y2.15 so the polished deck peeks above the mission
	# card line — the cards then overlap a glossy, reflective hangar floor
	# exactly like the concept art.
	floor.position = Vector3(0.0, 2.15, -1.5)
	var floor_material := _make_material(Color(0.045, 0.065, 0.1), 0.14, 0.08)
	floor_material.metallic = 0.78
	floor.material_override = floor_material
	parent.add_child(floor)
	for z in [-10.0, -7.0, -4.0, -1.0, 2.0, 5.0]:
		_add_hangar_box(parent, Vector3(0.0, 2.165, z), Vector3(28.0, 0.025, 0.035), Color(0.12, 0.18, 0.24), 0.35, 0.22)
	for x in [-15.0, -12.0, -6.0, 0.0, 6.0, 12.0, 15.0]:
		_add_hangar_box(parent, Vector3(x, 2.165, -1.5), Vector3(0.035, 0.025, 25.0), Color(0.08, 0.13, 0.19), 0.4, 0.16)
	for x in [-13.0, 13.0]:
		_add_hangar_box(parent, Vector3(x, 2.18, -1.5), Vector3(0.14, 0.035, 25.0), Color(0.08, 0.3, 0.52), 0.3, 1.4)

func _add_wall_dressing(parent: Node3D) -> void:
	# Warm glowing window strips down both side walls — reads as office /
	# control-room light bleeding into the hangar like the concept art.
	for side in [-1.0, 1.0]:
		for k in range(4):
			# Left wall strips sit further in; the NASA sign owns that corner.
			var strip_x: float = side * 14.2 if side > 0.0 else -12.4
			_add_hangar_box(parent, Vector3(strip_x, 2.6 + float(k) * 2.2, -17.85),
				Vector3(0.55, 1.15, 0.06), Color(1.0, 0.72, 0.38), 0.3, 2.2)
	# Vertical mission-status ticker strip along the remaining wall: subtle
	# cyan pulses that make the wall feel alive rather than a flat sheet.
	for x_pos in [-11.6, 0.0, 5.8]:
		_add_hangar_box(parent, Vector3(x_pos, 4.4, -17.88),
			Vector3(3.4, 0.16, 0.05), Color(0.25, 0.55, 0.9), 0.3, 1.3)

func _add_hangar_frame(parent: Node3D) -> void:
	var steel := Color(0.19, 0.25, 0.34)
	var edge := Color(0.12, 0.18, 0.27)
	for x in [-13.0, -6.0, 0.0, 6.0, 13.0]:
		_add_hangar_box(parent, Vector3(x, 6.0, -10.8), Vector3(0.22, 12.0, 0.34), steel, 0.44, 0.12)
		_add_hangar_box(parent, Vector3(x, 12.0, -6.8), Vector3(0.34, 0.32, 8.0), steel, 0.4, 0.16)
		_add_hangar_box(parent, Vector3(x, 12.4, -6.8), Vector3(0.1, 0.08, 8.0), Color(0.12, 0.3, 0.48), 0.3, 0.75)
	for bay in range(4):
		var center_x: float = -9.5 + float(bay) * 6.33
		for angle in [-31.0, 31.0]:
			var brace := MeshInstance3D.new()
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(6.6, 0.13, 0.16)
			brace.mesh = brace_mesh
			brace.position = Vector3(center_x, 10.45, -10.62)
			brace.rotation_degrees.z = angle
			brace.material_override = _make_material(steel.lightened(0.12), 0.42, 0.16)
			parent.add_child(brace)
			for end_x in [-3.1, 3.1]:
				_add_hangar_box(parent, Vector3(center_x + end_x, 10.45 + end_x * tan(deg_to_rad(angle)), -10.48), Vector3(0.22, 0.22, 0.16), edge, 0.4, 0.12)
	for y in [9.0, 12.1]:
		_add_hangar_box(parent, Vector3(0.0, y, -11.0), Vector3(26.0, 0.22, 0.3), steel, 0.46, 0.14)
	for x in [-9.5, -3.2, 3.2, 9.5]:
		_add_hangar_box(parent, Vector3(x, 12.65, -7.0), Vector3(5.8, 0.12, 0.16), edge, 0.45, 0.1)
		var lamp := MeshInstance3D.new()
		var lamp_mesh := BoxMesh.new()
		lamp_mesh.size = Vector3(1.2, 0.08, 0.4)
		lamp.mesh = lamp_mesh
		lamp.position = Vector3(x, 12.4, -4.0)
		lamp.material_override = _make_material(Color(1.0, 0.58, 0.25), 0.3, 2.4)
		parent.add_child(lamp)
		var light := OmniLight3D.new()
		light.position = Vector3(x, 11.8, -3.5)
		light.light_color = Color(1.0, 0.56, 0.28)
		light.light_energy = 1.1
		light.omni_range = 7.0
		parent.add_child(light)

func _add_hangar_box(parent: Node3D, pos: Vector3, dimensions: Vector3, tint: Color, roughness: float, emission: float) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	box.mesh = mesh
	box.position = pos
	box.material_override = _make_material(tint, roughness, emission)
	parent.add_child(box)

func _make_material(tint: Color, roughness: float, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.52 if emission_energy < 1.0 else 0.15
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = emission_energy
	return material

## Per-bay launch vehicle. Each mission gets a distinct real-world archetype
## (Falcon 9 / SLS / Orion / Atlas V) with its own paint scheme, interstage,
## grid fins/finlets, boosters, engine nozzles and body lettering so the four
## bays never look like clones of the same pale cylinder.
func _make_mission_rocket(mission_index: int, tint: Color) -> Node3D:
	var rocket := Node3D.new()
	rocket.name = "MissionRocket%d" % (mission_index + 1)
	rocket.position.y = 0.8

	var body_col := Color(0.93, 0.94, 0.97)      # first/second-stage paint
	var accent_col := Color(0.16, 0.2, 0.28)     # interstage + hardware
	var nose_col := tint.lightened(0.2)          # fairing / tip
	var booster_col := Color(0.88, 0.9, 0.94)    # side-boosters
	var decal_col := Color(0.05, 0.05, 0.06)     # body lettering
	var booster_set := true
	match mission_index:
		0:  # Low Earth Orbit — Falcon-9 archetype: white + graphite black
			accent_col = Color(0.07, 0.075, 0.09)
			nose_col = Color(0.07, 0.075, 0.09)
		1:  # Lunar south-pole — SLS archetype: burnt-orange core, white boosters
			body_col = Color(0.94, 0.48, 0.12)
			accent_col = Color(0.62, 0.27, 0.07)
			nose_col = Color(0.94, 0.48, 0.12)
		2:  # Mars — Orion/Atlas archetype: white + signal-red hardpoints
			accent_col = Color(0.8, 0.11, 0.09)
			nose_col = Color(0.8, 0.11, 0.09)
		3:  # Asteroid — Atlas-V archetype: graphite body, silver hardware
			body_col = Color(0.33, 0.36, 0.43)
			accent_col = Color(0.85, 0.87, 0.92)
			nose_col = tint.lightened(0.15)
			booster_col = Color(0.8, 0.82, 0.88)
			decal_col = Color(0.94, 0.95, 0.98)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_col
	body_mat.metallic = 0.12
	body_mat.roughness = 0.34
	var hard_mat := _make_material(accent_col, 0.3, 0.0)
	hard_mat.metallic = 0.85
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.09, 0.1, 0.12)
	metal_mat.metallic = 0.9
	metal_mat.roughness = 0.38

	# ── Engine section: dark skirt + three nozzles peeking underneath ──
	_add_cyl(rocket, 0.5, 0.42, 0.42, Vector3(0.0, 0.32, 0.0), metal_mat)
	for k in range(3):
		var ang: float = TAU * float(k) / 3.0 + 0.5
		_add_cyl(rocket, 0.05, 0.15, 0.38,
			Vector3(cos(ang) * 0.26, 0.16, sin(ang) * 0.26), metal_mat)

	# ── First stage ──
	_add_cyl(rocket, 0.5, 0.58, 3.9, Vector3(0.0, 2.45, 0.0), body_mat)
	# Panel-joint rings keep the skin from looking like one flat tube.
	_add_cyl(rocket, 0.585, 0.585, 0.055, Vector3(0.0, 1.45, 0.0), hard_mat)
	_add_cyl(rocket, 0.545, 0.545, 0.055, Vector3(0.0, 3.05, 0.0), hard_mat)

	# ── Interstage / stage separator ──
	_add_cyl(rocket, 0.52, 0.53, 0.5, Vector3(0.0, 4.65, 0.0), hard_mat)

	# ── Second stage ──
	_add_cyl(rocket, 0.5, 0.52, 1.15, Vector3(0.0, 5.48, 0.0), body_mat)

	# ── Payload fairing: long taper + tip sphere ──
	_add_cyl(rocket, 0.05, 0.5, 1.5, Vector3(0.0, 6.8, 0.0), hard_mat if mission_index != 1 else body_mat)
	var tip := SphereMesh.new()
	tip.radius = 0.075
	tip.height = 0.15
	var tip_mesh := MeshInstance3D.new()
	tip_mesh.mesh = tip
	var tip_mat := _make_material(tint.lightened(0.4), 0.25, 2.2)
	tip_mesh.material_override = tip_mat
	tip_mesh.position = Vector3(0.0, 7.58, 0.0)
	rocket.add_child(tip_mesh)

	# ── Aero hardware per archetype ──
	if mission_index == 0:
		# Falcon-style grid fins near the top of the first stage.
		for k in range(4):
			var ang: float = TAU * float(k) / 4.0
			var fin := MeshInstance3D.new()
			var fin_mesh := BoxMesh.new()
			fin_mesh.size = Vector3(0.1, 0.46, 0.24)
			fin.mesh = fin_mesh
			fin.position = Vector3(cos(ang) * 0.58, 4.2, sin(ang) * 0.58)
			fin.rotation.y = -ang
			fin.material_override = metal_mat
			rocket.add_child(fin)
	elif mission_index in [1, 2]:
		# Redescent finlets at the base — tapered race fins like SLS/Orion.
		for side in [-1.0, 1.0]:
			_add_cyl(rocket, 0.06, 0.24, 1.05,
				Vector3(side * 0.68, 0.62, 0.62), hard_mat)
		_add_cyl(rocket, 0.06, 0.24, 1.05, Vector3(0.0, 0.62, -0.78), hard_mat)

	# ── Side boosters: every bay carries solids for that Heavy silhouette ──
	var booster_h: float = 4.2 if mission_index == 3 else 3.6
	for side in [-1.0, 1.0]:
		_add_cyl(rocket, 0.26, 0.34, booster_h,
			Vector3(side * 0.92, 0.45 + booster_h * 0.5, 0.0), body_mat if mission_index == 1 else _make_material(booster_col, 0.34, 0.0))
		# Booster nose cone in the accent paint.
		_add_cyl(rocket, 0.02, 0.27, 0.75,
			Vector3(side * 0.92, 0.45 + booster_h + 0.36, 0.0), hard_mat)
		# Hardpoint ring where the booster meets the core.
		_add_cyl(rocket, 0.3, 0.3, 0.09,
			Vector3(side * 0.92, 0.45 + booster_h * 0.55, 0.0),
			_make_material(tint, 0.28, 0.4))

	# ── Body lettering, like the real vehicles ──
	var decal := Label3D.new()
	decal.text = ["FALCON 9", "SLS BLOCK 1", "ORION SLS", "ATLAS V 551"][mission_index % 4]
	decal.font_size = 26
	decal.pixel_size = 0.006
	decal.modulate = decal_col
	decal.outline_size = 2
	decal.position = Vector3(0.0, 3.6, 0.575)
	rocket.add_child(decal)

	# Floating display stand: hoisted above pad level so the whole vehicle
	# reads nose-to-engine in the strip between the header and the cards.
	# Horizontal bias keeps the cores heroic/fat rather than pencil-thin.
	rocket.scale = Vector3(1.05, 0.8, 1.05)

	# ── Engine idle glow + exhaust plume + ground-haze light ──
	# Additive flame cones under the skirt sell a hot-running engine the way
	# the concept art shows, even while the vehicle is idling on the stand.
	for flame_k in range(2):
		var flame := MeshInstance3D.new()
		var flame_mesh := CylinderMesh.new()
		flame_mesh.top_radius = 0.26
		flame_mesh.bottom_radius = 0.05
		flame_mesh.height = 1.25
		flame_mesh.radial_segments = 20
		flame_mesh.cap_top = false
		flame.mesh = flame_mesh
		var flame_side: float = -1.0 + float(flame_k) * 2.0
		flame.position = Vector3(flame_side * 0.16, -0.14 - float(flame_k) * 0.12, 0.0)
		var flame_mat := StandardMaterial3D.new()
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.albedo_color = Color(tint.r, 0.62 * tint.r + 0.35, 0.22 * tint.r + 0.08, 0.55 - float(flame_k) * 0.18)
		flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		flame.material_override = flame_mat
		rocket.add_child(flame)
	_add_cyl(rocket, 0.08, 0.25, 0.5, Vector3(0.0, 0.28, 0.0),
		_make_material(tint.lightened(0.25), 0.25, 2.0))
	var engine_light := OmniLight3D.new()
	engine_light.position.y = 0.35
	engine_light.light_color = tint
	engine_light.light_energy = 1.7
	engine_light.omni_range = 5.0
	rocket.add_child(engine_light)
	_hangar_engine_lights.append(engine_light)
	return rocket

## Small helper: add a tapered cylinder part to the rocket assembly.
func _add_cyl(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 32
	part.mesh = mesh
	part.position = pos
	part.material_override = mat
	parent.add_child(part)

func _make_bay_planet(parent: Node3D, mission_index: int, x: float, tint: Color) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	# Oversized, half-hidden bodies like the concept art: a huge blue Earth
	# arc, a rusty Mars, a pitted moon and an asteroid cluster sentinel.
	sphere.radius = [4.2, 2.5, 3.4, 2.2][mission_index % 4]
	sphere.height = sphere.radius * 2.0
	orb.mesh = sphere
	orb.position = Vector3(x + [3.4, 2.6, 2.8, 2.2][mission_index % 4],
		[7.0, 8.4, 7.8, 8.8][mission_index % 4], -10.35)
	orb.material_override = _make_mission_planet_material(mission_index, tint)
	parent.add_child(orb)
	_hangar_planets.append(orb)

## Slow-rising dust motes drifting through the light shafts — cheap but sells
## the hangar atmosphere.
func _add_dust_sparks(parent: Node3D, x: float, tint: Color) -> void:
	var sparks := GPUParticles3D.new()
	sparks.amount = 36
	sparks.lifetime = 5.0
	sparks.preprocess = 4.0
	sparks.position = Vector3(x, 0.5, 0.4)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.4, 5.0, 1.6)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 30.0
	pm.gravity = Vector3(0.0, 0.02, 0.0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.28
	pm.scale_min = 0.3
	pm.scale_max = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.85, 0.35))
	g.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	sparks.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = spark_mat
	sparks.draw_pass_1 = quad
	parent.add_child(sparks)

func _make_mission_planet_material(mission_index: int, tint: Color) -> Material:
	if mission_index == 0:
		var earth := StandardMaterial3D.new()
		earth.albedo_texture = load("res://assets/textures/earth-blue-marble-8k.jpg") as Texture2D
		earth.roughness = 0.82
		earth.emission_enabled = true
		earth.emission = tint * 0.3
		return earth
	if mission_index == 1:
		var moon := StandardMaterial3D.new()
		moon.albedo_texture = load("res://assets/textures/nasa-lro-lunar-color-2k.jpg") as Texture2D
		moon.roughness = 0.9
		return moon
	if mission_index == 3:
		var asteroid := Shader.new()
		asteroid.code = "shader_type spatial;\nvoid vertex(){ float n=sin(VERTEX.x*7.0+VERTEX.y*4.0)*sin(VERTEX.z*8.0+VERTEX.x*3.0); VERTEX += NORMAL*n*0.12; }\nvoid fragment(){ float n=sin(UV.x*65.0)*sin(UV.y*53.0); ALBEDO=mix(vec3(0.12,0.10,0.09),vec3(0.42,0.33,0.25),UV.y*0.55+0.25+n*0.07); ROUGHNESS=0.96; }"
		var asteroid_mat := ShaderMaterial.new()
		asteroid_mat.shader = asteroid
		return asteroid_mat
	var mars_noise := FastNoiseLite.new()
	mars_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mars_noise.frequency = 0.055
	mars_noise.fractal_octaves = 5
	mars_noise.fractal_gain = 0.52
	var mars_texture := NoiseTexture2D.new()
	mars_texture.width = 512
	mars_texture.height = 256
	mars_texture.seamless = true
	mars_texture.noise = mars_noise
	var mars := StandardMaterial3D.new()
	mars.albedo_color = Color(0.88, 0.46, 0.29)
	mars.albedo_texture = mars_texture
	mars.roughness = 0.95
	return mars

# ─── Selection ────────────────────────────────────────────────────────────────
func _apply_card_state(entry: Dictionary, selected: bool) -> void:
	var panel: PanelContainer = entry["panel"]
	var s: StyleBoxFlat = entry["sb"]
	var col: Color = entry.get("col", C_CYAN)
	var target_bg := Color(col.r, col.g, col.b, 0.10) if selected else C_PANEL
	var target_border := col if selected else Color(col.r, col.g, col.b, 0.45)
	var target_shadow_size := 12 if selected else 6
	var target_shadow_alpha := 0.7 if selected else 0.4
	var target_scale := Vector2(1.02, 1.02) if selected else Vector2(1.0, 1.0)

	s.bg_color = target_bg
	s.border_color = target_border
	s.shadow_color = Color(col.r, col.g, col.b, 0.18) if selected else Color(0, 0, 0, target_shadow_alpha)
	s.shadow_size = target_shadow_size
	s.set_border_width_all(2 if selected else 1)
	s.border_width_top = 3 if selected else 2

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", target_scale, 0.14)

func _on_card_selected(mission_id: String, _panel: PanelContainer, _sb: StyleBoxFlat, mission: Dictionary) -> void:
	selected_mission_id = mission_id
	print("[MissionSelect] Mission selected: ", mission_id, " begin_btn=", begin_btn)
	if begin_btn:
		begin_btn.disabled = false
		begin_btn.modulate = Color.WHITE  # ensure not greyed out
		begin_btn.tooltip_text = ""  # clear the hint tooltip
	if selected_label:
		selected_label.text = "Selected:  " + mission.get("name","?")

	# Update borders
	for entry in _card_data:
		_apply_card_state(entry, entry["id"] == mission_id)


# ─── Difficulty ───────────────────────────────────────────────────────────────
func _on_difficulty_selected(diff: String, pressed_btn: Button) -> void:
	selected_difficulty = diff
	if difficulty_btns:
		for child in difficulty_btns.get_children():
			if child is Button:
				child.button_pressed = (child == pressed_btn)

# ─── Navigation ──────────────────────────────────────────────────────────────
func _on_begin_pressed() -> void:
	print("[MissionSelect] BEGIN pressed! mission_id=", selected_mission_id)
	if selected_mission_id.is_empty():
		print("[MissionSelect] ERROR: No mission selected!")
		return
	# Apply difficulty multiplier first
	var idx := DIFFICULTIES.find(selected_difficulty)
	var mult: float = DIFF_BUDGET_MULT[idx] if idx >= 0 else 1.0
	print("[MissionSelect] Starting mission with difficulty=", selected_difficulty, " mult=", mult)
	GameManager.start_mission(selected_mission_id)
	if not GameManager.current_mission.is_empty():
		GameManager.current_mission["budget"] = int(
			GameManager.current_mission.get("budget", 120) * mult
		)

func _on_back_pressed() -> void:
	GameManager.go_to_main_menu()
