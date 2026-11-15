## MainMenu.gd — Title screen.
##
## The whole scene (Earth limb, launch pad, astronaut, lunar horizon, moon,
## header, title, HUD panel, mission pipeline, version badges) is carried by a
## single background plate so the screen reads exactly like the approved
## concept art.  Only the five menu buttons are live controls; they are
## positioned with fractional anchors measured off the plate, so they sit on
## top of their painted counterparts at any window size and stay invisible
## until hovered.
##
## If the plate is missing (not imported yet, or stripped from a build) the
## buttons fall back to self-drawn styling so the menu never becomes unusable.

extends Control

# ─── Palette (coloured title screen plate) ────────────────────────────────────
const C_NAVY   := Color(0.015, 0.03, 0.08)
const C_CYAN   := Color(0.15, 0.85, 1.0)
const C_ORANGE := Color(1.0, 0.62, 0.14)
const C_RED    := Color(1.0, 0.38, 0.36)
const C_TEXT   := Color(0.92, 0.96, 1.0)
const C_DIM    := Color(0.55, 0.66, 0.8)

const BG_URL := "res://assets/images/menu_background.png"
const MOON_URL := "res://assets/images/menu_moon.png"
const HOWTO_SCRIPT := "res://scripts/ui/HowToPlayOverlay.gd"

# The plate is authored at 1672x941; animated overlays are anchored as
# fractions of it so they track the art at any window size.
const PLATE_SIZE := Vector2(1672.0, 941.0)
const MOON_CROP := Rect2(1404, 25, 204, 204)
const MOON_GLOW_CROP := Rect2(1336, -43, 340, 340)
# Painted orbit around the title, sampled from the plate's pixel coordinates.
const ORBIT_PTS := [
	Vector2(1238, 108), Vector2(1255, 128), Vector2(1259, 141),
	Vector2(1246, 155), Vector2(1232, 165), Vector2(1216, 175),
	Vector2(1197, 185), Vector2(1177, 195), Vector2(1154, 205),
	Vector2(1130, 215), Vector2(1103, 225), Vector2(1085, 231),
	Vector2(1050, 240), Vector2(1014, 248), Vector2(978, 256),
]
const ORBIT_SPEED := 34.0  # plate px per second

const MOON_SPIN_SHADER := preload("res://shaders/moon_spin.gdshader")
const MOON_GLOW_SHADER := preload("res://shaders/moon_glow.gdshader")

# Hit areas as fractions of the plate (left, top, right, bottom), measured from
# the border lines of the painted buttons in menu_background.png (1672x941).
const BTN_START    := [0.3680, 0.3430, 0.6490, 0.4145]
const BTN_LOAD     := [0.3774, 0.4240, 0.6423, 0.4857]
const BTN_HOWTO    := [0.3774, 0.4995, 0.6423, 0.5611]
const BTN_SETTINGS := [0.3774, 0.5749, 0.6423, 0.6366]
const BTN_QUIT     := [0.3774, 0.6504, 0.6423, 0.7120]

var _bg_ok := false
var _moon_tex: Texture2D
var _start_btn: Button
var _load_btn: Button
var _howto_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _howto: Control
var _settings: Control
var _orbit_fx: Control
var _orbit_curve: Curve2D
var _orbit_len := 0.0
var _orbit_dist := 0.0
var _orbit_trail: Array[Vector2] = []
var _fx_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Whole title screen keeps the concept-art colours, including the animated
	# moon and orbit overlays added below.
	MissionForge.colorize(self)
	_build_background()
	_build_orbit_fx()
	_build_buttons()
	_build_howto_overlay()
	_build_settings_overlay()
	_wire()
	# Fade the whole screen in.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.7)

# ─── Background plate ─────────────────────────────────────────────────────────
func _build_background() -> void:
	# Letterbox safety: the plate is 16:9, so any other aspect shows navy bars
	# rather than a stretched photograph.
	var base := ColorRect.new()
	base.color = C_NAVY
	_full(base)
	add_child(base)
	MissionForge.colorize(base)

	var tex: Texture2D = load(BG_URL) if ResourceLoader.exists(BG_URL) else null
	_bg_ok = tex != null
	if not _bg_ok:
		return

	var plate := TextureRect.new()
	plate.texture = tex
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# This page is a colour exception: the approved concept art is shown as
	# painted, while every other screen stays on the black & white system.
	_full(plate)
	add_child(plate)
	MissionForge.colorize(plate)
	_build_moon_fx()

# ─── Animated moon ────────────────────────────────────────────────────────────
func _build_moon_fx() -> void:
	# Halo first: the spinning disc covers its centre, so only the rim glow shows.
	var halo := ColorRect.new()
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_rect(halo, MOON_GLOW_CROP)
	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = MOON_GLOW_SHADER
	halo.material = halo_mat
	add_child(halo)

	# The disc is the plate's moon cropped to its own soft-edged texture, spun in
	# the shader so rotation reads as lunar spin without redrawing the artwork.
	if not ResourceLoader.exists(MOON_URL):
		return
	_moon_tex = load(MOON_URL)
	var moon := TextureRect.new()
	moon.texture = _moon_tex
	moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	moon.stretch_mode = TextureRect.STRETCH_SCALE
	moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_rect(moon, MOON_CROP)
	var moon_mat := ShaderMaterial.new()
	moon_mat.shader = MOON_SPIN_SHADER
	moon.material = moon_mat
	add_child(moon)

# Gives the orbit layer a real _draw() hook (drawing from a signal callback is
# not guaranteed to land inside the CanvasItem draw pass).
class OrbitLayer extends Control:
	var paint: Callable

	func _draw() -> void:
		if paint.is_valid():
			paint.call()

# ─── Animated orbit ───────────────────────────────────────────────────────────
func _build_orbit_fx() -> void:
	var layer := OrbitLayer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.paint = _draw_orbit_fx
	_orbit_fx = layer
	_orbit_curve = Curve2D.new()
	for p in ORBIT_PTS:
		_orbit_curve.add_point(p)
	_orbit_len = _orbit_curve.get_baked_length()
	add_child(layer)

func _process(delta: float) -> void:
	if _orbit_fx == null:
		return
	_fx_time += delta
	_orbit_dist += ORBIT_SPEED * delta
	if _orbit_dist > _orbit_len + 24.0:
		_orbit_dist = 0.0
		_orbit_trail.clear()
	if _orbit_dist <= _orbit_len:
		_orbit_trail.append(_orbit_curve.sample_baked(_orbit_dist))
		if _orbit_trail.size() > 22:
			_orbit_trail.pop_front()
	elif not _orbit_trail.is_empty():
		_orbit_trail.pop_front()
	_orbit_fx.queue_redraw()

func _draw_orbit_fx() -> void:
	var s := _orbit_fx.size
	var sx := s.x / PLATE_SIZE.x
	var sy := s.y / PLATE_SIZE.y
	var unit := minf(sx, sy)

	# Beacon blinking on the painted satellite at the head of the orbit.
	var beacon := Vector2(1250.0 * sx, 94.0 * sy)
	var blink := 0.6 + 0.4 * sin(_fx_time * 2.4)
	_orbit_fx.draw_circle(beacon, 8.0 * unit, Color(0.45, 0.85, 1.0, 0.10 * blink))
	_orbit_fx.draw_circle(beacon, 2.6 * unit, Color(0.80, 0.96, 1.0, 0.85 * blink))

	if _orbit_trail.is_empty():
		return
	var fade_in := clampf(_orbit_dist / 28.0, 0.0, 1.0)
	var fade_out := clampf((_orbit_len - _orbit_dist) / 42.0, 0.0, 1.0)
	var alpha := minf(fade_in, fade_out)
	if alpha <= 0.01:
		return
	var trail_n := _orbit_trail.size()
	for i in range(trail_n):
		var p := _orbit_trail[i]
		var f := float(i + 1) / float(trail_n)
		_orbit_fx.draw_circle(
			Vector2(p.x * sx, p.y * sy),
			(1.2 + 3.6 * f) * unit,
			Color(0.30, 0.75, 1.0, 0.22 * f * f * alpha))
	var head := _orbit_trail[trail_n - 1]
	var hp := Vector2(head.x * sx, head.y * sy)
	var pulse := 1.0 + 0.15 * sin(_fx_time * 6.0)
	_orbit_fx.draw_circle(hp, 16.0 * unit * pulse, Color(0.35, 0.80, 1.0, 0.16 * alpha))
	_orbit_fx.draw_circle(hp, 8.0 * unit * pulse, Color(0.45, 0.85, 1.0, 0.30 * alpha))
	_orbit_fx.draw_circle(hp, 4.6 * unit * pulse, Color(0.92, 0.99, 1.0, 0.98 * alpha))

# ─── Buttons ─────────────────────────────────────────────────────────────────
func _build_buttons() -> void:
	_start_btn    = _menu_button("START NEW MISSION",    BTN_START,    C_ORANGE)
	_load_btn     = _menu_button("LOAD SAVED MISSION",   BTN_LOAD,     C_CYAN)
	_howto_btn    = _menu_button("HOW TO PLAY",          BTN_HOWTO,    C_CYAN)
	_settings_btn = _menu_button("SETTINGS",             BTN_SETTINGS, C_CYAN)
	_quit_btn     = _menu_button("QUIT",                 BTN_QUIT,     C_RED)
	add_child(_start_btn)
	add_child(_load_btn)
	add_child(_howto_btn)
	add_child(_settings_btn)
	add_child(_quit_btn)

func _menu_button(label: String, rect: Array, accent: Color) -> Button:
	var b := Button.new()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# NOTE: no clip_contents here - it would cut off the hover glow shadow that
	# is drawn outside the button rect.
	# Fractional anchors keep the hit area glued to the painted button.
	b.anchor_left = rect[0]
	b.anchor_top = rect[1]
	b.anchor_right = rect[2]
	b.anchor_bottom = rect[3]
	b.offset_left = 0.0
	b.offset_top = 0.0
	b.offset_right = 0.0
	b.offset_bottom = 0.0
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH

	if _bg_ok:
		# The plate already draws icon + label + frame, so the live button is a
		# transparent hit area that only lights up on interaction.
		b.text = ""
		b.add_theme_stylebox_override("normal", _ghost_style(accent, false))
		b.add_theme_stylebox_override("hover", _ghost_style(accent, true))
		b.add_theme_stylebox_override("pressed", _ghost_style(accent, true, 0.22))
		b.add_theme_stylebox_override("focus", _ghost_style(accent, true))
		b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	else:
		# Fallback: no plate, so the buttons must carry their own look.
		b.text = label
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _solid_style(accent))
		b.add_theme_stylebox_override("hover", _solid_style(accent.lightened(0.25)))
		b.add_theme_stylebox_override("pressed", _solid_style(accent.lightened(0.35)))
		b.add_theme_stylebox_override("focus", _solid_style(accent))
		b.add_theme_stylebox_override("disabled", _solid_style(Color("#202020")))
	MissionForge.colorize(b)
	return b

func _ghost_style(accent: Color, hot: bool, strength: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var a := strength if strength >= 0.0 else (0.10 if hot else 0.0)
	s.bg_color = Color(accent.r, accent.g, accent.b, a)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.85 if hot else 0.0)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 2; s.corner_radius_bottom_left = 2
	s.corner_radius_top_right = 2; s.corner_radius_bottom_right = 2
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.28 if hot else 0.0)
	s.shadow_size = 12 if hot else 0
	s.shadow_offset = Vector2(0, 0)
	return s

func _solid_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#111111")
	s.border_color = accent
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.corner_radius_top_left = 2; s.corner_radius_bottom_left = 2
	s.corner_radius_top_right = 2; s.corner_radius_bottom_right = 2
	s.content_margin_left = 20; s.content_margin_right = 20
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s

# ─── How-to overlay ───────────────────────────────────────────────────────────
func _build_howto_overlay() -> void:
	# Full modal with its own tab rail and pages; see HowToPlayOverlay.gd.
	_howto = load(HOWTO_SCRIPT).new()
	_howto.name = "HowToPlayOverlay"
	add_child(_howto)

# ─── Settings overlay ─────────────────────────────────────────────────────────
func _build_settings_overlay() -> void:
	_settings = _overlay()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	card.add_theme_stylebox_override("panel", MissionForge.panel_style(true))
	center.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)

	var title := _label("SETTINGS", 28, C_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = (get_window().mode == Window.MODE_FULLSCREEN)
	fs.add_theme_color_override("font_color", C_TEXT)
	fs.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	fs.add_theme_color_override("font_pressed_color", Color("#FFFFFF"))
	fs.toggled.connect(func(on):
		get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED)
	v.add_child(fs)

	v.add_child(_label("Master Volume", 15, C_DIM))
	var vol := HSlider.new()
	vol.min_value = 0; vol.max_value = 1.0; vol.step = 0.01
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lin := pow(10.0, AudioServer.get_bus_volume_db(0) / 20.0)
	vol.value = clampf(lin, 0.0, 1.0)
	vol.value_changed.connect(func(val):
		AudioServer.set_bus_volume_db(0, linear_to_db(val))
		AudioServer.set_bus_mute(0, val <= 0.001))
	v.add_child(vol)

	v.add_child(_overlay_close(_settings))

func _overlay() -> Control:
	var dim := Control.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	_full(bg)
	dim.add_child(bg)
	dim.hide()
	add_child(dim)
	return dim

func _overlay_close(target: Control) -> Button:
	var b := Button.new()
	b.text = "Close"
	b.custom_minimum_size = Vector2(150, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	MissionForge.style_button(b, false)
	b.pressed.connect(func(): target.hide())
	return b

# Esc dismisses whichever modal is currently up, matching the X and Close
# buttons without stealing the key from the Settings overlay.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _howto.visible:
		_howto.close()
		get_viewport().set_input_as_handled()
	elif _settings.visible:
		_settings.hide()
		get_viewport().set_input_as_handled()

# ─── Wiring ───────────────────────────────────────────────────────────────────
func _wire() -> void:
	_load_btn.disabled = not FileAccess.file_exists("user://savegame.json")
	_start_btn.pressed.connect(func(): GameManager.go_to_scene("res://scenes/ui/mission_select.tscn"))
	_load_btn.pressed.connect(func():
		if GameManager.load_game(): GameManager.go_to_builder())
	_howto_btn.pressed.connect(func(): _howto.open())
	_settings_btn.pressed.connect(func(): _settings.show())
	_quit_btn.pressed.connect(func(): get_tree().quit())

# ─── Small helpers ────────────────────────────────────────────────────────────
func _full(c: Control) -> void:
	# Use the anchors *and* offsets preset - set_anchors_preset alone preserves
	# the current (still zero) rect as offsets, which pins the child to 0x0.
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Anchors a control onto a rectangle measured in plate pixels.
func _plate_rect(c: Control, rect: Rect2) -> void:
	c.anchor_left = rect.position.x / PLATE_SIZE.x
	c.anchor_top = rect.position.y / PLATE_SIZE.y
	c.anchor_right = rect.end.x / PLATE_SIZE.x
	c.anchor_bottom = rect.end.y / PLATE_SIZE.y
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
