## MissionForgeTheme.gd — MISSIONFORGE premium black & white UI design system.
##
## The rule this enforces:
##   • every 2D interface element  → the nine B&W palette tokens below
##   • every 3D simulation element → untouched, fully natural colour
##
## It works by attaching a tiny luminance shader (shaders/missionforge_mono.gdshader)
## to CanvasItems only, and by snapping every theme colour override onto the
## palette ramp.  A Node3D, MeshInstance3D, StandardMaterial3D, particle, light or
## WorldEnvironment is never a CanvasItem, so it can never be reached by this
## script.  The two colour systems stay completely independent — no viewport
## filter, no camera effect, no global canvas modulate.
extends Node

const MONO_SHADER := preload("res://shaders/missionforge_mono.gdshader")

# ─── Premium black & white palette (UI only) ─────────────────────────────────
const BLACK        := Color("#000000")
const BG           := Color("#0A0A0A")   # secondary UI background
const CARD         := Color("#151515")   # cards
const RAISED       := Color("#202020")   # elevated panels
const BORDER       := Color("#333333")   # UI borders
const TEXT_MUTED   := Color("#777777")   # muted text
const TEXT_SECONDARY := Color("#B3B3B3") # secondary text
const TEXT_PRIMARY := Color("#FFFFFF")   # primary text
const HOVER        := Color("#D9D9D9")   # primary hover background
const SECONDARY_BG := Color("#111111")   # secondary button background

# Legacy aliases used across older screens — all resolve to the tokens above.
const INK        := BG
const PANEL      := CARD
const PANEL_SOFT := RAISED
const LINE_SOFT  := BORDER
const LINE       := BORDER
const MUTED      := TEXT_MUTED
const DIM        := TEXT_SECONDARY
const TEXT       := TEXT_PRIMARY
const WHITE      := TEXT_PRIMARY
const SUCCESS    := TEXT_PRIMARY
const ALERT      := HOVER

## Live telemetry values stay bright white — the palette has no accent hue.
const LIVE       := TEXT_PRIMARY
const LIVE_SOFT  := HOVER

## Palette ramp, ordered by luminance.  Source colours are snapped to the
## nearest step so every surface ends up on an exact design token.
const RAMP: Array[Color] = [
	BLACK, BG, CARD, RAISED, BORDER, TEXT_MUTED, TEXT_SECONDARY, HOVER, TEXT_PRIMARY,
]

## Rec.709 luminance weights.
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

var _mono_material: ShaderMaterial
var _queued: Dictionary = {}
var _themed: Dictionary = {}
var _tree_scanned := false
var bypassed := false

func _ready() -> void:
	process_priority = 200
	# Development switch: MA_MONO=0 renders the interface in its source colours
	# for side-by-side comparisons.  Never used by gameplay.
	if OS.get_environment("MA_MONO") == "0":
		bypassed = true
		print("[MissionForge] Monochrome layer bypassed (MA_MONO=0)")
		set_process(false)
		return
	_mono_material = ShaderMaterial.new()
	_mono_material.shader = MONO_SHADER
	_mono_material.set_shader_parameter("strength", 1.0)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_tree")
	print("[MissionForge] Black & white UI layer online — 3D colour pipeline untouched")

func _process(_delta: float) -> void:
	if _queued.is_empty():
		return
	# Style a bounded number of new nodes per frame: UI trees built in one
	# _ready() (mission select, builder, launch HUD) can add hundreds of nodes,
	# and a single huge pass would show up as a frame hitch.
	var budget := 96
	var finished: Array = []
	for id in _queued.keys():
		if budget <= 0:
			break
		var node = _queued[id]
		finished.append(id)
		budget -= 1
		if is_instance_valid(node):
			_style_control(node)
	for id in finished:
		_queued.erase(id)

# ─── Colour helpers ──────────────────────────────────────────────────────────
static func _luma(c: Color) -> float:
	return c.r * LUMA.x + c.g * LUMA.y + c.b * LUMA.z

## Converts any colour to a pure grey of the same perceived brightness.
static func mono(c: Color) -> Color:
	var l := _luma(c)
	return Color(l, l, l, c.a)

## Snaps any colour onto the palette ramp (alpha preserved).
static func token(c: Color) -> Color:
	var l := _luma(c)
	var best: Color = RAMP[0]
	var best_dist := 999.0
	for step in RAMP:
		var d := absf(step.r - l)
		if d < best_dist:
			best_dist = d
			best = step
	return Color(best.r, best.g, best.b, c.a)

# ─── Style factories (premium B&W) ───────────────────────────────────────────
static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box

## Panel chrome: #151515 card (or #0A0A0A surface) with a 1px #333 border.
static func panel_style(card: bool = true) -> StyleBoxFlat:
	return flat(CARD if card else BG, BORDER, 1, 3)

## Secondary control: #111111 fill, #333 border, white label.
static func secondary_button_style() -> StyleBoxFlat:
	return flat(SECONDARY_BG, BORDER, 1, 3)

## Applies the premium B&W button skin.  primary = white fill / black label.
func style_button(button: Button, primary: bool = false) -> void:
	if button == null:
		return
	if primary:
		var normal := flat(TEXT_PRIMARY, TEXT_PRIMARY, 0, 3)
		var hover := flat(HOVER, HOVER, 0, 3)
		var pressed := flat(Color("#C9C9C9"), Color("#C9C9C9"), 0, 3)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("focus", hover)
		button.add_theme_stylebox_override("disabled", flat(RAISED, BORDER, 1, 3))
		button.add_theme_color_override("font_color", BLACK)
		button.add_theme_color_override("font_hover_color", BLACK)
		button.add_theme_color_override("font_pressed_color", BLACK)
		button.add_theme_color_override("font_focus_color", BLACK)
		button.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	else:
		button.add_theme_stylebox_override("normal", secondary_button_style())
		button.add_theme_stylebox_override("hover", flat(RAISED, HOVER, 1, 3))
		button.add_theme_stylebox_override("pressed", flat(BLACK, TEXT_PRIMARY, 1, 3))
		button.add_theme_stylebox_override("focus", flat(RAISED, TEXT_PRIMARY, 1, 3))
		button.add_theme_stylebox_override("disabled", flat(BG, BORDER, 1, 3))
		button.add_theme_color_override("font_color", TEXT_PRIMARY)
		button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
		button.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		button.add_theme_color_override("font_focus_color", TEXT_PRIMARY)
		button.add_theme_color_override("font_disabled_color", TEXT_MUTED)

## Progress bar: #151515 track, white fill.
func style_progress(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", flat(CARD, BORDER, 1, 2))
	bar.add_theme_stylebox_override("fill", flat(TEXT_PRIMARY, TEXT_PRIMARY, 0, 2))
	bar.add_theme_color_override("font_color", TEXT_PRIMARY)

# ─── Public API ───────────────────────────────────────────────────────────────
## Opts one text control out of the monochrome pass.  Live values are white on
## the palette, so this only pins the colour and drops the shader.
func live(item: CanvasItem, color: Color = LIVE) -> void:
	if item == null:
		return
	item.set_meta("missionforge_live", true)
	if item.material == _mono_material:
		item.material = null
	if not (item is Control):
		return
	var c := item as Control
	c.add_theme_color_override("font_color", color)
	c.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	if c is Button:
		c.add_theme_color_override("font_hover_color", color)
		c.add_theme_color_override("font_pressed_color", color)
		c.add_theme_color_override("font_focus_color", color)
		c.add_theme_color_override("font_disabled_color", TEXT_MUTED)

## Forces the whole 2D tree under `root` through the mono pass right now.
func apply_to(root: Node) -> void:
	_scan_node(root)
	if root is CanvasItem:
		_install(root as CanvasItem)
	for child in root.get_children():
		apply_to(child)

## Exempts one subtree from the monochrome pass (used by the coloured title
## screen).  Any mono/plate shader already attached is removed; children added
## later inherit the exemption through their ancestors.
func colorize(root: Node) -> void:
	if root == null:
		return
	root.set_meta("missionforge_color_page", true)
	for item in root.find_children("*", "CanvasItem", true, false):
		_strip_theme_material(item)
		_queued.erase(item.get_instance_id())
	if root is CanvasItem:
		_strip_theme_material(root as CanvasItem)
		_queued.erase(root.get_instance_id())

func _strip_theme_material(item: CanvasItem) -> void:
	var mat := item.material
	if mat is ShaderMaterial:
		var sh: Shader = (mat as ShaderMaterial).shader
		if sh != null and String(sh.resource_path).begins_with("res://shaders/missionforge_"):
			item.material = null

## 0 = normal mono pass, 1 = colour page, 2 = forced mono (overrides an
## enclosing colour page).
func _bypass_state(node: Node) -> int:
	var walk: Node = node
	while walk != null:
		if walk.has_meta("missionforge_force_mono"):
			return 2
		if walk.has_meta("missionforge_color_page"):
			return 1
		walk = walk.get_parent()
	return 0

# ─── Tree scanning ────────────────────────────────────────────────────────────
func _scan_tree() -> void:
	if _tree_scanned:
		return
	_tree_scanned = true
	_scan_node(get_tree().root)

func _scan_node(root: Node) -> void:
	for item in root.find_children("*", "CanvasItem", true, false):
		_install(item)
	for win in root.find_children("*", "Window", true, false):
		_style_window(win)

func _on_node_added(node: Node) -> void:
	if node is CanvasItem:
		_install(node)
	elif node is Window:
		_style_window(node)

## Sits a UI item in the mono pass.  The shader is attached immediately (before
## its first draw) while the theme overrides are queued for a later frame, when
## the owning script has finished assigning its palette.
func _install(item: CanvasItem) -> void:
	if not is_instance_valid(item):
		return
	if _inside_rendered_viewport(item):
		return
	if _bypass_state(item) == 1:
		_strip_theme_material(item)
		_queued.erase(item.get_instance_id())
		return
	# Live telemetry keeps its bright value: no mono material, no queued restyle.
	if item.has_meta("missionforge_live"):
		if item.material == _mono_material:
			item.material = null
		return
	if item.material == null:
		item.material = _mono_material
	_queued[item.get_instance_id()] = item

## A SubViewportContainer / SubViewport hosts a rendered 3D preview (spacecraft
## builder, hangar, mission select).  Those pixels are simulation, not UI, so
## they must keep their real colours and are deliberately skipped.
func _inside_rendered_viewport(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk is SubViewportContainer or walk is SubViewport:
			return true
		walk = walk.get_parent()
	return false

func _style_window(win: Window) -> void:
	if win == null:
		return
	if win.theme != null:
		_mono_theme(win.theme)

# ─── Control theming ──────────────────────────────────────────────────────────
func _style_control(node: Node) -> void:
	if not (node is Control):
		return
	var c := node as Control
	if c.has_meta("missionforge_live"):
		return
	if _bypass_state(c) == 1:
		return
	if c.theme != null:
		_mono_theme(c.theme)
	# Theme overrides surface as ordinary node properties, which is the only
	# generic way to enumerate them: theme_override_colors/font_color,
	# theme_override_styles/panel, ...
	for prop in c.get_property_list():
		var pname: String = String(prop.get("name", ""))
		if pname.begins_with("theme_override_colors/"):
			var value = c.get(pname)
			if not (value is Color):
				continue
			var current: Color = value
			var snapped := token(current)
			if not current.is_equal_approx(snapped):
				c.set(pname, snapped)
		elif pname.begins_with("theme_override_styles/"):
			_mono_stylebox(c.get(pname))

func _mono_theme(theme: Theme) -> void:
	var id := theme.get_instance_id()
	if _themed.has(id):
		return
	_themed[id] = true
	for type_name in theme.get_color_type_list():
		for color_name in theme.get_color_list(type_name):
			theme.set_color(color_name, type_name, token(theme.get_color(color_name, type_name)))
	for type_name in theme.get_stylebox_type_list():
		for style_name in theme.get_stylebox_list(type_name):
			_mono_stylebox(theme.get_stylebox(style_name, type_name))

func _mono_stylebox(box: StyleBox) -> void:
	if box == null:
		return
	if box is StyleBoxFlat:
		var flat_box := box as StyleBoxFlat
		flat_box.bg_color = token(flat_box.bg_color)
		flat_box.border_color = token(flat_box.border_color)
		flat_box.shadow_color = token(flat_box.shadow_color)
	elif box is StyleBoxLine:
		var line := box as StyleBoxLine
		line.color = token(line.color)
	elif box is StyleBoxTexture:
		var tex := box as StyleBoxTexture
		tex.modulate_color = token(tex.modulate_color)
