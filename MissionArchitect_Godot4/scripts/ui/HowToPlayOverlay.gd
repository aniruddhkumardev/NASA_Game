## HowToPlayOverlay.gd — full-screen "HOW TO PLAY" modal.
##
## Like the main menu, the modal is carried by a background plate cut from the
## approved concept art (assets/images/howto_background.png, 1637x924 — the
## screenshot with its OS title bar cropped off).  The plate has two regions
## erased, because both of them change with user input and a baked picture would
## end up lying about the current state:
##
##   * the page content area - refilled by howto_page_flow.png for Game Flow and
##     by live, selectable text for the other four tabs
##   * the whole tab rail column - all five tabs are drawn live, so whichever
##     one is active is the one that looks active, and none of them can vanish
##
## Close and the header X stay painted; their live Buttons are transparent hit
## areas pinned with fractional anchors measured off the plate, so they land on
## their counterparts at any window size.  If the plate is missing the chrome is
## drawn from code instead and the flow page renders from data.

extends Control

# ─── Palette (kept in step with MainMenu.gd) ──────────────────────────────────
const C_CYAN   := Color("#FFFFFF")
const C_ORANGE := Color("#B3B3B3")
const C_TEXT   := Color("#FFFFFF")
const C_DIM    := Color("#B3B3B3")
const C_MODAL  := Color("#151515")

const PLATE_URL     := "res://assets/images/howto_background.png"
const FLOW_PAGE_URL := "res://assets/images/howto_page_flow.png"

# Rects as fractions of the plate (left, top, right, bottom), measured off the
# grid overlay drawn on the concept screenshot.
const TAB_RECTS := {
	"flow":  [0.0538, 0.1807, 0.2028, 0.2511],
	"keys":  [0.0538, 0.2673, 0.2028, 0.3377],
	"tips":  [0.0538, 0.3593, 0.2028, 0.4286],
	"goals": [0.0538, 0.4502, 0.2028, 0.5216],
	"faq":   [0.0538, 0.5346, 0.2028, 0.6017],
}
const CONTENT_RECT  := [0.2187, 0.1472, 0.9542, 0.8431]	# erased page area
const CLOSE_RECT    := [0.4246, 0.8658, 0.5693, 0.9178]
const X_RECT        := [0.9114, 0.0823, 0.9456, 0.1429]

# Tab rail order: [key, label, icon]
const TABS := [
	["flow",  "Game Flow",    "play"],
	["keys",  "Controls",     "keyboard"],
	["tips",  "Mission Tips", "rocket"],
	["goals", "Objectives",   "target"],
	["faq",   "FAQ",          "help"],
]

# Fallback GAME FLOW cards (only used when the plate is absent): [n, title, icon, blurb]
const FLOW_CARDS := [
	["1", "Mission Select",     "target", "Pick a target: Earth Observation, Moon, Mars or Asteroid."],
	["2", "Spacecraft Builder", "cube",   "Configure bus, power, instruments, antenna, propulsion and rocket."],
	["3", "Launch",             "rocket", "Launch the rocket and reach orbit - fly the ascent and stage events."],
	["4", "Destination",        "earth",  "Complete mission operations: Earth orbit, lunar landing, or Mars cruise."],
	["5", "Mission Report",     "check",  "See the score breakdown, results and improvement tips."],
]

# Keycaps: [keys shown, description].  Matches the [input] map in project.godot.
const KEY_ROWS := [
	[["W", "A", "S", "D"], "Move astronaut / rover"],
	[["Space"],             "Jump"],
	[["Shift"],             "Sprint"],
	[["E"],                 "Interact / Use"],
	[["T"],                 "Transmit data"],
	[["I"],                 "Science scan"],
	[["M"],                 "Open orbital map"],
	[["Up", "Down"],        "Throttle (increase / decrease)"],
	[[".", ","],            "Change simulation speed (faster / slower)"],
	[["Esc"],               "Pause / game menu"],
	[["Mouse"],             "Look around / rotate craft"],
]

const MISSION_TIPS := [
	["Budget before brilliance", "Every part has a cost and the mission budget is hard. Buy the instruments the objectives actually need, then spend the rest on margin."],
	["Power is a story, not a number", "Averages hide eclipses. Check that generation plus battery covers the worst-case load, especially through the lunar night."],
	["Mass decides the rocket", "The heavier the bus, the bigger the launcher. Trim mass early and the launch window becomes far more forgiving."],
	["Downlink on every contact", "Science you cannot transmit is science you did not collect. Plan antenna coverage around your ground-station windows."],
	["Keep a delta-v reserve", "Reserve margin for course corrections and the deorbit or landing burn. Nominal profiles are not the only ones you will fly."],
]

const FAQ_ROWS := [
	["Can I change my design after launch?", "No. Once the rocket clears the tower the stack is fixed - use the Mission Report to iterate on the next attempt."],
	["Why did my mission score drop?", "Score is reduced by over-budget hardware, power failures and missed objectives. The report breaks each one down."],
	["Is there an autopilot for launch?", "Yes. Let autopilot fly the ascent, or take the throttle yourself with Up/Down and stage the events manually."],
	["Where is my progress saved?", "Save games live in the user data folder. LOAD SAVED MISSION on the main menu only lights up once a save exists."],
	["How do I speed up a long cruise?", "Use . to accelerate simulation time and , to slow it back down. M opens the orbital map at any point."],
]

var _baked := false
var _tab_buttons := {}
var _pages := {}
var _flow_art: TextureRect
var _flow_fallback: Control
var _other_host: Control

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# set_anchors_and_offsets_preset, not set_anchors_preset: the latter rewrites
	# the offsets so the *current* rect is preserved, which at build time means it
	# locks this control to 0x0 and nothing inside it ever lays out.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_baked = ResourceLoader.exists(PLATE_URL)
	_build_plate()
	_build_content()
	_build_tabs()
	_build_close_buttons()
	_select("flow")

func open() -> void:
	show()
	_select("flow")

func close() -> void:
	hide()

func _select(key: String) -> void:
	for k in _pages:
		_pages[k].visible = (k == key)
	for k in _tab_buttons:
		_tab_buttons[k].set_pressed_no_signal(k == key)
	if _baked:
		_flow_art.visible = (key == "flow")
	else:
		_flow_fallback.visible = (key == "flow")
	_other_host.visible = (key != "flow")

# ─── Background plate ─────────────────────────────────────────────────────────
func _build_plate() -> void:
	# Letterbox safety: the plate is 16:9, so any other aspect shows navy rather
	# than a stretched photograph.
	var base := ColorRect.new()
	base.color = Color("#000000")
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill(base)
	add_child(base)
	if not _baked:
		return
	var plate := TextureRect.new()
	plate.texture = load(PLATE_URL)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill(plate)
	add_child(plate)

# ─── Content area ─────────────────────────────────────────────────────────────
func _build_content() -> void:
	if _baked:
		# The Game Flow page is the concept art itself, dropped back into the
		# rectangle the plate generator erased.
		_flow_art = TextureRect.new()
		_flow_art.texture = load(FLOW_PAGE_URL)
		_flow_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_flow_art.stretch_mode = TextureRect.STRETCH_SCALE
		_flow_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anchor(_flow_art, CONTENT_RECT)
		add_child(_flow_art)
	else:
		# _panel_host() already parents the panel.
		_flow_fallback = _panel_host()
		_pages["flow"] = _page_flow()
		_flow_fallback.add_child(_pages["flow"])

	_other_host = _panel_host()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_other_host.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	_pages["keys"]  = _page_keys()
	_pages["tips"]  = _page_tips()
	_pages["goals"] = _page_goals()
	_pages["faq"]   = _page_faq()
	for k in ["keys", "tips", "goals", "faq"]:
		stack.add_child(_pages[k])

func _panel_host() -> Control:
	var p := PanelContainer.new()
	_anchor(p, CONTENT_RECT)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(C_MODAL.r, C_MODAL.g, C_MODAL.b, 0.88)
	s.border_color = Color("#333333")
	s.set_border_width_all(1)
	s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left = 30; s.content_margin_right = 30
	s.content_margin_top = 22; s.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p

# ─── Tab rail ─────────────────────────────────────────────────────────────────
## All five tabs are drawn live.  Their captions were part of the plate, but a
## baked pill can only ever show one tab as active and erasing just that pill
## made the Game Flow entry disappear, so the rail column is erased wholesale
## and rebuilt here - state, hover and labels now always agree.
func _build_tabs() -> void:
	for t in TABS:
		var key: String = t[0]
		var b := Button.new()
		b.name = "Tab_" + key
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.toggle_mode = true
		b.text = t[1]
		# Every caption in the art starts at the same x, just right of the icon.
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 23)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _rail_style(false, false))
		b.add_theme_stylebox_override("hover", _rail_style(true, false))
		b.add_theme_stylebox_override("toggled", _rail_style(false, true))
		b.add_theme_stylebox_override("pressed", _rail_style(false, true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_anchor(b, TAB_RECTS[key])
		b.pressed.connect(_select.bind(key))
		add_child(b)
		_tab_buttons[key] = b

		# Icon sits in the left third of the pill, exactly where the art has it.
		var ic := IconDrawer.new()
		ic.kind = t[2]
		ic.col = C_TEXT
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.anchor_left = 0.06
		ic.anchor_right = 0.21
		ic.anchor_top = 0.22
		ic.anchor_bottom = 0.78
		b.add_child(ic)

func _rail_style(hot: bool, active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if active:
		s.bg_color = Color("#202020")
		s.border_color = Color("#FFFFFF")
		s.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
		s.shadow_size = 12
	else:
		s.bg_color = Color("#111111") if not hot else Color("#202020")
		s.border_color = Color("#333333")
		s.shadow_size = 0
	s.set_border_width_all(1)
	s.corner_radius_top_left = 4; s.corner_radius_bottom_left = 4
	s.corner_radius_top_right = 4; s.corner_radius_bottom_right = 4
	# Left margin clears the icon band (0.06..0.21 of the pill) and lands the
	# caption where the artwork puts it.
	s.content_margin_left = 52
	s.content_margin_right = 10
	s.shadow_offset = Vector2.ZERO
	return s

# ─── Close / X ────────────────────────────────────────────────────────────────
func _build_close_buttons() -> void:
	# _hit_button() parents the control itself.
	_hit_button("Close", CLOSE_RECT).pressed.connect(close)
	var x := _hit_button("✕", X_RECT)
	x.tooltip_text = "Close"
	x.pressed.connect(close)

## A control that occupies a painted rect on the plate.  With the plate present
## it is invisible until hovered; without one it has to look like a button.
func _hit_button(label: String, rect: Array) -> Button:
	var b := Button.new()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_anchor(b, rect)
	if _baked:
		b.text = ""
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", _ghost(C_CYAN, 0.14))
		b.add_theme_stylebox_override("pressed", _ghost(C_CYAN, 0.26))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	else:
		b.text = label
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		var s := _rail_style(false, true)
		s.content_margin_left = 18; s.content_margin_right = 18
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Added last so the button paints over the tab art it sits on.
	add_child(b)
	return b

func _ghost(accent: Color, strength: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(accent.r, accent.g, accent.b, strength)
	s.border_color = Color("#333333")
	s.set_border_width_all(1)
	s.corner_radius_top_left = 4; s.corner_radius_bottom_left = 4
	s.corner_radius_top_right = 4; s.corner_radius_bottom_right = 4
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.5)
	s.shadow_size = 16
	s.shadow_offset = Vector2.ZERO
	return s

# ─── Pages (live text; also the no-plate fallback for Game Flow) ──────────────
func _page_flow() -> Control:
	var v := _page()
	v.add_child(_section("clock", "GAME FLOW — FROM DESIGN TO DISCOVERY"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for card in FLOW_CARDS:
		row.add_child(_hex_card(card))
	v.add_child(row)
	v.add_child(_section("keyboard", "KEY CONTROLS"))
	v.add_child(_keycap_block(4))
	return v

func _page_keys() -> Control:
	var v := _page()
	v.add_child(_section("keyboard", "ALL KEY BINDINGS"))
	v.add_child(_paragraph(
		"[color=#ffffff]Every action below is defined in the project input map, " +
		"so it works on any keyboard layout.[/color]"))
	v.add_child(_keycap_block(0))
	return v

func _page_tips() -> Control:
	var v := _page()
	v.add_child(_section("rocket", "MISSION TIPS"))
	for t in MISSION_TIPS:
		v.add_child(_paragraph("[b][color=#ffffff]%s[/color][/b]\n%s" % [t[0], t[1]]))
	return v

func _page_goals() -> Control:
	var v := _page()
	v.add_child(_section("target", "MISSION OBJECTIVES"))
	# Read straight from the live catalog so this page can never drift from the
	# missions that are actually shipped.
	for m in GameManager.missions:
		var head := "[b][color=#ffffff]%s[/color][/b]  [color=#777777][i]%s[/i]  ·  %s[/color]\n" % [
			m.get("name", ""), m.get("difficulty", ""), m.get("target", "")]
		var body := ""
		for o in m.get("objectives", []):
			body += "[color=#ffffff]•[/color] %s\n" % o
		var bonus := ""
		for o in m.get("bonus_objectives", []):
			bonus += "[color=#b3b3b3]★[/color] %s\n" % o
		if bonus != "":
			bonus = "[b]Bonus[/b]\n" + bonus
		v.add_child(_paragraph(head + body + bonus))
	return v

func _page_faq() -> Control:
	var v := _page()
	v.add_child(_section("help", "FREQUENTLY ASKED QUESTIONS"))
	for q in FAQ_ROWS:
		v.add_child(_paragraph("[b][color=#ffffff]Q:[/color] %s[/b]\n%s" % [q[0], q[1]]))
	return v

# ─── Building blocks ──────────────────────────────────────────────────────────
func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.visible = false
	return v

func _section(icon: String, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var ic := IconDrawer.new()
	ic.kind = icon
	ic.col = C_CYAN
	ic.custom_minimum_size = Vector2(26, 26)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	h.add_child(_label(text, 21, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT))
	return h

func _hex_card(card: Array) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(196, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hex := HexCard.new()
	hex.kind = card[2]
	hex.number = card[0]
	hex.custom_minimum_size = Vector2(190, 132)
	hex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(hex)

	v.add_child(_label(card[1], 17, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var d := _label(card[3], 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(190, 0)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	return v

## Keycap rows as a two-column grid of [caps] [meaning].  `limit` caps how many
## rows are shown (0 = all), which is how the fallback page gets a short recap.
func _keycap_block(limit: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	var rows := KEY_ROWS if limit == 0 else KEY_ROWS.slice(0, limit)
	for r in rows:
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 6)
		for key in r[0]:
			caps.add_child(_keycap(key))
		grid.add_child(caps)
		var l := _label(r[1], 16, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
	return grid

func _keycap(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(38, 38)
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#202020")
	s.border_color = Color("#333333")
	s.set_border_width_all(1)
	s.corner_radius_top_left = 4; s.corner_radius_top_right = 4
	s.corner_radius_bottom_left = 4; s.corner_radius_bottom_right = 4
	p.add_theme_stylebox_override("panel", s)
	var l := _label(key, 15, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

func _paragraph(bbcode: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", C_TEXT)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.text = bbcode
	return rt

# ─── Small helpers ────────────────────────────────────────────────────────────
func _fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _anchor(c: Control, rect: Array) -> void:
	# Fractional anchors keep the control glued to its painted counterpart; the
	# offsets must be zeroed *after* the anchors are set or the rect collapses.
	c.anchor_left = rect[0]
	c.anchor_top = rect[1]
	c.anchor_right = rect[2]
	c.anchor_bottom = rect[3]
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH

func _label(text: String, size: int, col: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	# No autowrap here on purpose: a wrapping Label reports a tiny minimum width,
	# which collapses the HBox it lives in and stacks the text one character per
	# line.  Callers that genuinely need wrapping opt in explicitly.
	return l

# ─── Vector icon drawer ───────────────────────────────────────────────────────
class IconDrawer extends Control:
	var kind := ""
	var col := Color.WHITE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var lw := maxf(1.8, s * 0.07)
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.22, -s * 0.3), c + Vector2(s * 0.34, 0),
					c + Vector2(-s * 0.22, s * 0.3)]), col)
			"keyboard":
				draw_rect(Rect2(c + Vector2(-s * 0.44, -s * 0.28), Vector2(s * 0.88, s * 0.56)), col, false, lw)
				for r in 2:
					for k in 4:
						draw_circle(c + Vector2(-s * 0.28 + k * s * 0.19, -s * 0.1 + r * s * 0.2), s * 0.045, col)
			"rocket":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -s * 0.46), c + Vector2(s * 0.16, -s * 0.1),
					c + Vector2(s * 0.16, s * 0.24), c + Vector2(-s * 0.16, s * 0.24),
					c + Vector2(-s * 0.16, -s * 0.1)]), col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.16, s * 0.06), c + Vector2(-s * 0.34, s * 0.3),
					c + Vector2(-s * 0.16, s * 0.24)]), col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(s * 0.16, s * 0.06), c + Vector2(s * 0.34, s * 0.3),
					c + Vector2(s * 0.16, s * 0.24)]), col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.09, s * 0.26), c + Vector2(0, s * 0.46),
					c + Vector2(s * 0.09, s * 0.26)]), Color("#B3B3B3"))
			"target":
				draw_arc(c, s * 0.38, 0, TAU, 40, col, lw)
				draw_arc(c, s * 0.2, 0, TAU, 28, col, lw)
				draw_circle(c, s * 0.07, col)
			"help":
				draw_arc(c + Vector2(0, -s * 0.1), s * 0.18, PI, TAU + PI * 0.4, 24, col, lw)
				draw_line(c + Vector2(s * 0.04, s * 0.06), c + Vector2(0, s * 0.2), col, lw)
				draw_circle(c + Vector2(0, s * 0.32), s * 0.05, col)
				draw_rect(Rect2(c + Vector2(-s * 0.42, -s * 0.42), Vector2(s * 0.84, s * 0.84)), col, false, lw * 0.7)
			"cube":
				var pts := [c + Vector2(0, -s * 0.4), c + Vector2(s * 0.36, -s * 0.18),
					c + Vector2(s * 0.36, s * 0.2), c + Vector2(0, s * 0.42),
					c + Vector2(-s * 0.36, s * 0.2), c + Vector2(-s * 0.36, -s * 0.18)]
				draw_colored_polygon(PackedVector2Array(pts), Color(col.r, col.g, col.b, 0.18))
				for i in pts.size():
					draw_line(pts[i], pts[(i + 1) % pts.size()], col, lw)
				draw_line(pts[0], c, col, lw)
				draw_line(pts[3], c, col, lw)
			"earth":
				draw_circle(c, s * 0.4, Color("#333333"))
				draw_arc(c, s * 0.4, 0, TAU, 32, col, lw * 0.7)
				draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.14, col)
				draw_circle(c + Vector2(s * 0.14, s * 0.12), s * 0.1, col)
			"check":
				draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.42), Vector2(s * 0.64, s * 0.84)), col, false, lw)
				for r in 3:
					var y := -s * 0.22 + r * s * 0.22
					draw_line(c + Vector2(-s * 0.2, y), c + Vector2(-s * 0.06, y + s * 0.08), col, lw * 0.8)
					draw_line(c + Vector2(-s * 0.06, y + s * 0.08), c + Vector2(s * 0.08, y - s * 0.06), col, lw * 0.8)
					draw_line(c + Vector2(s * 0.14, y - s * 0.02), c + Vector2(s * 0.26, y - s * 0.02), col, lw * 0.6)
			"clock":
				draw_arc(c, s * 0.4, 0, TAU, 40, col, lw)
				draw_line(c, c + Vector2(0, -s * 0.24), col, lw)
				draw_line(c, c + Vector2(s * 0.2, s * 0.06), col, lw)
			_:
				draw_circle(c, s * 0.3, col)

# ─── Hexagon frame for the fallback GAME FLOW cards ───────────────────────────
class HexCard extends Control:
	var kind := ""
	var number := ""
	var col := Color("#FFFFFF")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var inset := w * 0.06
		var cx := w * 0.5
		var pts := PackedVector2Array([
			Vector2(cx, inset * 0.4),
			Vector2(w - inset, h * 0.3),
			Vector2(w - inset, h * 0.72),
			Vector2(cx, h - inset * 0.4),
			Vector2(inset, h * 0.72),
			Vector2(inset, h * 0.3),
		])
		draw_colored_polygon(pts, Color(0.0823529, 0.0823529, 0.0823529, 0.92))
		var rim := PackedVector2Array(pts)
		rim.append(pts[0])
		draw_polyline(rim, Color(col.r, col.g, col.b, 0.9), 2.5, true)

		var ic := w * 0.34
		var centre := Vector2(cx, h * 0.4)
		_draw_icon(kind, centre, ic, col)

		var bc := Vector2(cx - w * 0.02, h * 0.74)
		draw_circle(bc, w * 0.085, Color("#FFFFFF"))
		var f := ThemeDB.fallback_font
		draw_string(f, bc + Vector2(-w * 0.035, w * 0.032), number,
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(w * 0.11), Color("#000000"))

	func _draw_icon(k: String, c: Vector2, s: float, color: Color) -> void:
		var lw := maxf(2.0, s * 0.07)
		match k:
			"target":
				draw_arc(c, s * 0.42, 0, TAU, 36, color, lw)
				draw_circle(c, s * 0.1, color)
			"cube":
				var p := [c + Vector2(0, -s * 0.44), c + Vector2(s * 0.4, -s * 0.2),
					c + Vector2(s * 0.4, s * 0.22), c + Vector2(0, s * 0.46),
					c + Vector2(-s * 0.4, s * 0.22), c + Vector2(-s * 0.4, -s * 0.2)]
				draw_colored_polygon(PackedVector2Array(p), Color(color.r, color.g, color.b, 0.2))
				for i in p.size():
					draw_line(p[i], p[(i + 1) % p.size()], color, lw)
			"rocket":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -s * 0.5), c + Vector2(s * 0.18, -s * 0.1),
					c + Vector2(s * 0.18, s * 0.26), c + Vector2(-s * 0.18, s * 0.26),
					c + Vector2(-s * 0.18, -s * 0.1)]), color)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.1, s * 0.28), c + Vector2(0, s * 0.5),
					c + Vector2(s * 0.1, s * 0.28)]), Color("#B3B3B3"))
			"earth":
				draw_circle(c, s * 0.42, Color("#333333"))
				draw_arc(c, s * 0.42, 0, TAU, 32, color, lw * 0.8)
				draw_circle(c + Vector2(-s * 0.12, -s * 0.08), s * 0.14, color)
				draw_circle(c + Vector2(s * 0.16, s * 0.14), s * 0.1, color)
			"check":
				draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.44), Vector2(s * 0.68, s * 0.88)),
					color, false, lw)
				draw_line(c + Vector2(-s * 0.18, 0), c + Vector2(-s * 0.02, s * 0.16), color, lw)
				draw_line(c + Vector2(-s * 0.02, s * 0.16), c + Vector2(s * 0.22, -s * 0.18), color, lw)
			_:
				draw_circle(c, s * 0.3, color)
