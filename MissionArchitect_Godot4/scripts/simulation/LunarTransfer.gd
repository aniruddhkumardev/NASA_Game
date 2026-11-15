## Dedicated Earth-to-Moon cinematic. This is only used by Lunar South Pole Scout.
extends Node3D

const EARTH_TEXTURE := preload("res://assets/textures/earth-blue-marble-8k.jpg")
const MOON_TEXTURE := preload("res://assets/textures/nasa-lro-lunar-color-2k.jpg")
# Directional rocket-exhaust shader: white-hot at the nozzle (top of the cone,
# local +Y) grading to a cooler blue toward the tip, with faint mach-diamond
# bands near the throat and a subtle time flicker.  Additive + unshaded so it
# glows against space, but the alpha falls off along the length so it stays a
# sharp jet rather than blooming into a lamp.
const PLUME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 hot_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 mid_color : source_color = vec3(0.55, 0.75, 1.0);
uniform vec3 tip_color : source_color = vec3(0.30, 0.45, 1.0);
uniform float axis_h = 3.0;
uniform float brightness = 2.0;
uniform float mach = 0.4;
uniform float flicker_speed = 26.0;
varying float along;
void vertex() {
	along = clamp(VERTEX.y / axis_h + 0.5, 0.0, 1.0);
}
void fragment() {
	float flick = 0.88 + 0.12 * sin(TIME * flicker_speed + along * 6.0);
	float prof = pow(along, 1.3);
	float band = 0.5 + 0.5 * sin(along * 44.0 - TIME * flicker_speed * 0.7);
	float dm = mach * band * smoothstep(0.3, 1.0, along);
	vec3 col = mix(tip_color, mid_color, smoothstep(0.0, 0.5, along));
	col = mix(col, hot_color, smoothstep(0.5, 1.0, along));
	float a = clamp(prof * (1.0 + dm) * flick, 0.0, 1.0);
	ALBEDO = col;
	EMISSION = col * brightness;
	ALPHA = a;
}
"""
var phase_label: Label
var detail_label: Label
var telemetry_label: Label
var begin_button: Button
var camera: Camera3D
var earth: MeshInstance3D
var moon: MeshInstance3D
var vehicle: Node3D
var plume_grp: Node3D
var plume: MeshInstance3D
var plume_core: MeshInstance3D
var plume_light: OmniLight3D
var transfer_arc: MeshInstance3D
# Earth phasing / orbit-raising spiral — drawn as a continuous trail that grows
# as the stack circles Earth and drifts outward, instead of static rings.
var phasing_trail: MeshInstance3D
const _ORBIT_PLANE := Vector3(deg_to_rad(66.0), deg_to_rad(-18.0), deg_to_rad(20.0))
# Lunar capture spiral — mirrors the Earth phasing spiral but winds INWARD:
# the stack arrives far from the Moon and, braking each pass, circles closer
# until it settles into polar orbit.  Drawn as a trail that grows as it goes.
var moon_trail: MeshInstance3D
const _MOON_ORBIT_PLANE := Vector3(deg_to_rad(78.0), deg_to_rad(10.0), 0.0)
# Apogee radii of the three concentric Earth-parking ellipses (orbit-raising
# burns step these up) and of the three lunar-capture ellipses (braking burns
# step these down).  All ellipses share one perigee so the loops nest and touch
# at the burn point, exactly like the reference mission-profile diagram.
const _PARK_APS := [4.7, 5.7, 6.7]
const _CAP_APS := [7.6, 6.0, 5.0]
# The real translunar trajectory: a smooth Catmull-Rom path that leaves the
# parking orbit, coasts out, then sweeps around the Moon (flyby → capture)
# instead of parking beside it.  Drawn as a glowing line so the motion reads as
# following a physical path; the craft and the line sample the same function.
var _fp: Array[Vector3] = []
var flight_line: MeshInstance3D
var lunar_orbit_ring: MeshInstance3D
var timer := 0.0
var active := false
var handoff_requested := false

func _ready() -> void:
	phase_label = get_node("UI/Panel/VBox/Phase")
	detail_label = get_node("UI/Panel/VBox/Detail")
	telemetry_label = get_node("UI/Panel/VBox/Telemetry")
	begin_button = get_node("UI/Panel/VBox/Begin")
	MissionForge.style_button(begin_button, true)
	camera = get_node("Camera")
	_build_space_scene()
	begin_button.pressed.connect(_begin)
	# This scene follows an already completed Earth launch; it must not ask the
	# player to restart the journey with a second button press.
	active = true
	begin_button.hide()
	phase_label.text = "EARTH PARKING ORBIT — GUIDANCE ALIGNMENT"
	detail_label.text = "Same propulsion module + Vikram stack released by the launch vehicle; coasting above Earth before translunar injection."
	_update_cinematic(0.0)

func _build_space_scene() -> void:
	earth = _sphere(3.15, EARTH_TEXTURE, Color.WHITE, true)
	earth.position = Vector3(-6.6, -1.2, -10.0)
	add_child(earth)
	moon = _sphere(2.0, MOON_TEXTURE, Color(0.52, 0.52, 0.52), false)
	moon.position = Vector3(10.0, 1.4, -18.0)
	add_child(moon)
	vehicle = Node3D.new()
	add_child(vehicle)
	# Chandrayaan-style transfer stack: a gold-foil propulsion module carrying
	# the Vikram lander, with two solar wings and a high-gain dish — the real
	# orbiter+lander silhouette rather than a generic satellite drum.  The gold
	# surfaces use the same procedural MLI thermal-blanket foil (quilted albedo +
	# wrinkle normal map) as the launch-stack transfer craft, so the bus reads as
	# a foil-wrapped spacecraft rather than flat-painted gold boxes.
	var mli := _make_mli_textures()
	var gold := _foil_material(Color(0.62, 0.44, 0.12), mli)
	var foil := _foil_material(Color(0.74, 0.57, 0.19), mli)
	# Propulsion module (lower bus): boxy MLI blanket + engine bell on the -Y base.
	var propulsion := MeshInstance3D.new()
	var prop_mesh := BoxMesh.new()
	prop_mesh.size = Vector3(0.62, 0.82, 0.62)
	propulsion.mesh = prop_mesh
	propulsion.position.y = -0.42
	propulsion.material_override = gold
	vehicle.add_child(propulsion)
	for fy in [-0.72, -0.42, -0.12]:
		var rib := MeshInstance3D.new()
		var rib_mesh := BoxMesh.new()
		rib_mesh.size = Vector3(0.64, 0.02, 0.02)
		rib.mesh = rib_mesh
		rib.position = Vector3(0, fy, 0.32)
		rib.material_override = foil
		vehicle.add_child(rib)
	var bell := MeshInstance3D.new()
	var bell_mesh := CylinderMesh.new()
	bell_mesh.top_radius = 0.10
	bell_mesh.bottom_radius = 0.20
	bell_mesh.height = 0.28
	bell.mesh = bell_mesh
	bell.position.y = -0.97
	bell.material_override = _metal(Color(0.30, 0.30, 0.33))
	vehicle.add_child(bell)
	# Vikram lander (upper bus): faceted gold prism with sun-catching panel ribs.
	var lander := MeshInstance3D.new()
	var lander_mesh := BoxMesh.new()
	lander_mesh.size = Vector3(0.60, 0.66, 0.60)
	lander.mesh = lander_mesh
	lander.position.y = 0.36
	lander.material_override = gold
	vehicle.add_child(lander)
	for fy in [0.16, 0.36, 0.56]:
		var lrib := MeshInstance3D.new()
		var lrib_mesh := BoxMesh.new()
		lrib_mesh.size = Vector3(0.62, 0.02, 0.02)
		lrib.mesh = lrib_mesh
		lrib.position = Vector3(0, fy, 0.31)
		lrib.material_override = foil
		vehicle.add_child(lrib)
	# Two solar wings on a spar across the middle.
	var spar := MeshInstance3D.new()
	var spar_mesh := BoxMesh.new()
	spar_mesh.size = Vector3(2.6, 0.03, 0.05)
	spar.mesh = spar_mesh
	spar.position.y = 0.10
	spar.material_override = _metal(Color(0.55, 0.55, 0.58))
	vehicle.add_child(spar)
	for sx in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(1.05, 0.02, 0.62)
		wing.mesh = wing_mesh
		wing.position = Vector3(sx * 1.05, 0.10, 0.0)
		wing.material_override = _metal(Color(0.015, 0.07, 0.22))
		vehicle.add_child(wing)
	# High-gain dish antenna on top.
	var dish := MeshInstance3D.new()
	var dish_mesh := CylinderMesh.new()
	dish_mesh.top_radius = 0.24
	dish_mesh.bottom_radius = 0.04
	dish_mesh.height = 0.14
	dish.mesh = dish_mesh
	dish.position.y = 0.78
	dish.material_override = _metal(Color(0.82, 0.82, 0.80))
	vehicle.add_child(dish)
	# Engine exhaust: a two-layer directional jet (bright white core inside a
	# blue outer plume) streaming from the -Y nozzle, matching the launch-stack
	# look.  A single warm cone lit by an on-board point light read as a glowing
	# lamp, so the jet is cool/white, elongated, and the light is dim and pushed
	# away from the craft body.  It fires only during the TLI and LOI burns.
	plume_grp = Node3D.new()
	plume_grp.name = "EnginePlumeGroup"
	plume_grp.visible = false
	vehicle.add_child(plume_grp)
	plume = MeshInstance3D.new()
	plume.name = "EnginePlume"
	var plume_mesh := CylinderMesh.new()
	# A sharp jet, not a flaring lamp: wide at the nozzle (top) and tapering to a
	# near-point at the tip so the exhaust reads as a defined spike.
	plume_mesh.top_radius = 0.17
	plume_mesh.bottom_radius = 0.02
	plume_mesh.height = 3.6
	plume_mesh.radial_segments = 16
	plume_mesh.rings = 8
	plume.mesh = plume_mesh
	plume.position = Vector3(0, -2.7, 0)
	plume.material_override = _make_plume_mat(Color(0.62, 0.82, 1.0), Color(0.34, 0.56, 1.0), Color(0.16, 0.30, 0.85), 3.6, 1.7, 0.5)
	plume_grp.add_child(plume)
	plume_core = MeshInstance3D.new()
	plume_core.name = "PlumeCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.075
	core_mesh.bottom_radius = 0.012
	core_mesh.height = 2.8
	core_mesh.radial_segments = 12
	plume_core.mesh = core_mesh
	plume_core.position = Vector3(0, -2.3, 0)
	plume_core.material_override = _make_plume_mat(Color(1.0, 1.0, 1.0), Color(0.72, 0.86, 1.0), Color(0.40, 0.60, 1.0), 2.8, 3.2, 0.6)
	plume_grp.add_child(plume_core)
	plume_light = OmniLight3D.new()
	plume_light.position = Vector3(0, -1.5, 0)
	plume_light.light_color = Color(0.55, 0.75, 1.0)
	plume_light.omni_range = 1.6
	plume_light.light_energy = 0.0
	plume_grp.add_child(plume_light)
	transfer_arc = MeshInstance3D.new()
	var arc := TorusMesh.new()
	arc.inner_radius = 5.95
	arc.outer_radius = 6.0
	arc.rings = 96
	arc.ring_segments = 10
	transfer_arc.mesh = arc
	transfer_arc.material_override = _glow(Color(0.08, 0.42, 0.95, 0.3))
	transfer_arc.position = earth.position
	transfer_arc.rotation_degrees = Vector3(66, -18, 20)
	transfer_arc.visible = false
	add_child(transfer_arc)
	# The phasing orbit is drawn as a continuous trail that grows as the stack
	# circles Earth and drifts outward — not a few static rings.
	phasing_trail = MeshInstance3D.new()
	phasing_trail.name = "PhasingTrail"
	phasing_trail.material_override = _glow(Color(0.55, 0.78, 1.0, 0.75))
	phasing_trail.visible = false
	add_child(phasing_trail)
	# Mirror of the Earth trail: grows as the stack spirals inward around the
	# Moon during capture.
	moon_trail = MeshInstance3D.new()
	moon_trail.name = "MoonTrail"
	moon_trail.material_override = _glow(Color(0.55, 0.78, 1.0, 0.75))
	moon_trail.visible = false
	add_child(moon_trail)
	# Translunar trajectory: one graceful arc that leaves the phasing spiral,
	# bows gently outward, and terminates AT the Moon's near side so the stack is
	# captured — not a wavy snake and not a line that runs on past the Moon.
	# The first two waypoints are laid along the spiral's own prograde exit
	# tangent so the departure is tangent-continuous: the craft curves away from
	# Earth smoothly instead of snapping to a sharp corner where it turns for the
	# Moon (a real trajectory has no kink; velocity direction is continuous).
	_fp = []
	var _fp0 := _parking_point(7.0)
	var _exit := (_fp0 - _parking_point(6.85)).normalized()
	var _mo := _moon_point(15.0)
	# The waypoints advance MONOTONICALLY along the Earth→Moon line (fractions
	# 0 → 0.42 → 0.78 → 1) with only a small perpendicular bow that peaks mid-
	# flight and vanishes at both ends.  The old layout put one control point 12
	# units along the prograde orbital tangent and then snapped the next one back
	# to 55% toward the Moon; that zigzag made the curve bulge past the Moon and
	# sweep back THROUGH the lunar sphere on approach — the craft visibly flew
	# inside the Moon.  Monotonic spacing + a near-side endpoint keeps the whole
	# arc in open space and arriving at the near side.
	var _to_moon := _mo - _fp0
	var _d := _to_moon.length()
	var _mdir := _to_moon / maxf(_d, 1e-4)
	var _bow := _mdir.cross(Vector3(0, 1, 0)).normalized()
	# Depart exactly along the parking ellipse's prograde exit tangent (short lead,
	# so no wild overshoot) for a tangent-continuous, kink-free handoff, then bend
	# gently onto the Earth→Moon line.
	_fp.append(_fp0)
	_fp.append(_fp0 + _exit * 4.0)
	_fp.append(_fp0 + _mdir * (_d * 0.42) + _bow * 1.8)
	_fp.append(_fp0 + _mdir * (_d * 0.78) + _bow * 0.9)
	_fp.append(_mo)
	flight_line = MeshInstance3D.new()
	flight_line.name = "TranslunarTrajectory"
	var verts := PackedVector3Array()
	for s in 61:
		verts.append(_flight_point(float(s) / 60.0))
	var line_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	flight_line.mesh = line_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.6, 0.82, 1.0, 0.55)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.emission_enabled = true
	lm.emission = Color(0.5, 0.75, 1.0)
	lm.emission_energy_multiplier = 1.4
	flight_line.material_override = lm
	flight_line.visible = false
	add_child(flight_line)
	# The settled 100 km polar orbit is NOT shown as a thick static ring — the
	# user rejected that as a Saturn-ring look.  Only the thin growing
	# trajectory line (like Earth's) represents the path.  This node is kept
	# solely so any saved scene reference resolves; it stays hidden forever.
	lunar_orbit_ring = MeshInstance3D.new()
	lunar_orbit_ring.name = "LunarOrbitRing"
	lunar_orbit_ring.visible = false
	add_child(lunar_orbit_ring)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -54, 0)
	sun.light_energy = 1.25
	add_child(sun)
	_add_stars()

func _sphere(radius: float, texture: Texture2D, color: Color, unshaded: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 64
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.roughness = 0.92
	# Distant globes taxed the low-res NASA maps; anisotropic sampling keeps
	# surface detail legible at grazing angles instead of smearing it.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission_texture = texture
		mat.emission = Color(0.1, 0.16, 0.32)
		mat.emission_energy_multiplier = 0.28
	node.material_override = mat
	return node

func _metal(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.3
	return mat

## A metallic material painted with the procedural gold MLI foil: the albedo and
## normal textures carry the quilted-blanket colour and wrinkle detail, so the
## base tint only shifts it slightly.  Used for the transfer bus surfaces.
func _foil_material(tint: Color, mli: Array) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = mli[0]
	mat.metallic = 0.55
	mat.roughness = 0.32
	mat.metallic_specular = 0.7
	mat.normal_enabled = true
	mat.normal_texture = mli[1]
	mat.normal_scale = 0.7
	mat.emission_enabled = true
	mat.emission = tint * 0.28
	mat.emission_energy_multiplier = 0.10
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func _mli_noise2(grid: PackedFloat32Array, n: int, u: float, v: float) -> float:
	var fx: float = u * n
	var fy: float = v * n
	var x0 := int(floor(fx)) % n
	var y0 := int(floor(fy)) % n
	var x1 := (x0 + 1) % n
	var y1 := (y0 + 1) % n
	var tx: float = fx - floor(fx)
	var ty: float = fy - floor(fy)
	var a := grid[y0 * n + x0]
	var b := grid[y0 * n + x1]
	var c := grid[y1 * n + x0]
	var d := grid[y1 * n + x1]
	return lerp(lerp(a, b, tx), lerp(c, d, tx), ty)

## Procedurally build a crinkled gold MLI thermal-blanket look: a quilted albedo
## (individual blanket sheets + darker seams + per-sheet tint) and a matching
## wrinkle normal map.  Shared with the launch-stack transfer craft.
func _make_mli_textures() -> Array:
	var size := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	var n1 := 16
	var n2 := 48
	var g1 := PackedFloat32Array()
	for i in range(n1 * n1):
		g1.append(rng.randf())
	var g2 := PackedFloat32Array()
	for i in range(n2 * n2):
		g2.append(rng.randf())
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in range(size):
		for x in range(size):
			var u := float(x) / size
			var v := float(y) / size
			heights[y * size + x] = 0.65 * _mli_noise2(g1, n1, u, v) + 0.35 * _mli_noise2(g2, n2, u, v)
	var nrm := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var l := heights[y * size + ((x - 1 + size) % size)]
			var r := heights[y * size + ((x + 1) % size)]
			var dn := heights[((y - 1 + size) % size) * size + x]
			var up := heights[((y + 1) % size) * size + x]
			var nx := (l - r) * 2.2
			var ny := (dn - up) * 2.2
			var nlen := sqrt(nx * nx + ny * ny + 1.0)
			nrm.set_pixel(x, y, Color((nx / nlen) * 0.5 + 0.5, (ny / nlen) * 0.5 + 0.5, (1.0 / nlen) * 0.5 + 0.5))
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cells := 8
	var base := Color(0.80, 0.56, 0.14)
	for y in range(size):
		for x in range(size):
			var u := float(x) / size
			var v := float(y) / size
			var cx := int(u * cells)
			var cy := int(v * cells)
			var tint := 0.82 + 0.34 * _mli_noise2(g1, n1, (float(cx) + 0.5) / cells, (float(cy) + 0.5) / cells)
			var fu := u * cells - cx
			var fv := v * cells - cy
			var seam := minf(minf(fu, 1.0 - fu), minf(fv, 1.0 - fv))
			var seamf := clampf(seam / 0.07, 0.0, 1.0)
			var shade := lerpf(0.5, 1.0, seamf) * tint
			alb.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade))
	var albedo_tex := ImageTexture.create_from_image(alb)
	var normal_tex := ImageTexture.create_from_image(nrm)
	return [albedo_tex, normal_tex]

## Build a rocket-exhaust ShaderMaterial from PLUME_SHADER with the given colour
## ramp (hot→mid→tip along the jet), cone height (for the length parameter),
## overall brightness and mach-diamond strength.
func _make_plume_mat(hot: Color, mid: Color, tip: Color, axis_h: float, brightness: float, mach: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = PLUME_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("hot_color", hot)
	mat.set_shader_parameter("mid_color", mid)
	mat.set_shader_parameter("tip_color", tip)
	mat.set_shader_parameter("axis_h", axis_h)
	mat.set_shader_parameter("brightness", brightness)
	mat.set_shader_parameter("mach", mach)
	return mat

func _glow(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	return mat

func _add_stars() -> void:
	for i in 90:
		var star := _sphere(0.012 + float(i % 3) * 0.006, null, Color(0.72, 0.84, 1.0), true)
		var a := float(i) * 2.399
		star.position = Vector3(cos(a) * (18.0 + float(i % 11)), -6.5 + float((i * 13) % 130) * 0.1, -19.0 - abs(sin(a)) * 12.0)
		add_child(star)

func _begin() -> void:
	active = true
	begin_button.disabled = true
	begin_button.text = "TRANSLUNAR TRANSFER IN PROGRESS"

func _process(delta: float) -> void:
	if not active:
		return
	timer += delta
	if moon:
		moon.rotation.y += delta * 0.03
	_update_cinematic(timer)
	if timer < 7.0:
		phase_label.text = "1 / 3  •  EARTH PARKING & PHASING ORBITS"
		detail_label.text = "The stack raises its orbit through a series of concentric ellipses, each perigee burn lifting the apogee until the translunar injection window opens."
	elif timer < 15.0:
		phase_label.text = "2 / 3  •  TRANSLUNAR INJECTION"
		detail_label.text = "The propulsion module carries Vikram away from Earth. Earth recedes; the real lunar target fills the navigation view."
	elif timer < 22.0:
		phase_label.text = "3 / 3  •  LUNAR APPROACH & CAPTURE"
		detail_label.text = "The spacecraft brakes at the Moon, then rotates its orbit over permanently shadowed south-pole terrain."
	elif not handoff_requested:
		handoff_requested = true
		CinematicTransition.travel("res://scenes/lunar/lunar_mission.tscn", "LUNAR ORBIT CAPTURE", "Braking burn complete — Vikram lander preparing for south-pole descent")

func _update_cinematic(t: float) -> void:
	# The old decorative circular parking ring is retired: the nested parking
	# ellipses drawn by _rebuild_phasing_trail now show the real orbit profile, so
	# a single perfect circle would only clash with them.
	transfer_arc.visible = false
	if t < 7.0:
		# Circle Earth while drifting outward, drawing the trail as it goes so
		# the trajectory builds up behind the stack instead of a static ring.
		vehicle.position = _parking_point(t)
		_rebuild_phasing_trail(t)
		var fwd := _parking_point(t + 0.12) - _parking_point(t)
		if fwd.length_squared() > 1e-8:
			vehicle.basis = Basis(Quaternion(Vector3(0, 1, 0), fwd.normalized()))
		# Orbit-raising burn thrust: the module fires prograde at perigee so a
		# visible exhaust jet trails behind the craft as it works its way out
		# through the nested parking ellipses.
		_set_plume(true, 0.85)
		flight_line.visible = false
		if moon_trail:
			moon_trail.visible = false
	elif t < 15.0:
		# Translunar coast: the trajectory line draws itself out to the craft as
		# it flies, continuing the trail left by the Earth spiral.  Reaches the
		# Moon's approach point by t=15 so the capture spiral can begin.
		flight_line.visible = true
		if moon_trail:
			moon_trail.visible = false
		if lunar_orbit_ring:
			lunar_orbit_ring.visible = false
		var u: float = clampf((t - 7.0) / 8.0, 0.0, 1.0)
		# Roughly LINEAR coast: a translunar cruise is near-constant velocity, and
		# the old ease-out 1-(1-u)^2 front-loaded progress so the craft was already
		# ~86% of the way by t=12 — it then dwelled over the lunar disc for the last
		# few seconds, reading as "entering/exiting the Moon."  Linear keeps it out
		# in open space mid-leg and only arrives at the near side near t=15.
		var eased: float = u
		vehicle.position = _flight_point(eased)
		_rebuild_flight_line(eased)
		var nxt: Vector3 = _flight_point(minf(eased + 0.01, 1.0))
		var vel: Vector3 = nxt - vehicle.position
		# Continuous thrust across the whole translunar leg: the module keeps
		# firing prograde so the exhaust never blinks out between the TLI burn and
		# the lunar approach — the craft flies engine-on the entire way to the Moon.
		if vel.length_squared() > 1e-8:
			vehicle.basis = Basis(Quaternion(Vector3(0, -1, 0), vel.normalized() * -1.0))
		_set_plume(true, 1.0 if t < 9.5 else 0.7)
	else:
		# Lunar capture: mirror of the Earth spiral but winding INWARD — the
		# stack arrives far out and, braking each pass (LOI burn at the start),
		# circles progressively closer until it settles into polar orbit.
		flight_line.visible = false
		vehicle.position = _moon_point(t)
		_rebuild_moon_trail(t)
		var fwd2 := _moon_point(t + 0.12) - _moon_point(t)
		# Keep the engine lit through the capture spiral too, but orient the stack
		# so the exhaust TRAILS BEHIND it (nose +Y into the flight direction),
		# matching the coast leg.  Pointing the jet along the velocity vector made
		# the flame shoot out in front of the craft, which reads as impractical.
		if fwd2.length_squared() > 1e-8:
			vehicle.basis = Basis(Quaternion(Vector3(0, -1, 0), fwd2.normalized() * -1.0))
		_set_plume(true, 0.7 if t < 17.5 else 0.5)
	# Cinematic scale: as the stack reaches the Moon it pulls back so it reads
	# as a small spacecraft settling into a big Moon's orbit, not a slab the
	# size of the disc.  The hero shots near Earth stay full size.
	var vscale := 1.0
	if t >= 13.0:
		vscale = lerpf(1.0, 0.34, clampf((t - 13.0) / 6.0, 0.0, 1.0))
	vehicle.scale = Vector3(vscale, vscale, vscale)
	if t < 15.0:
		# Approach shot: stand off to the SIDE of the flight path (a fixed offset
		# along the Earth→Moon cross-axis) so the orbiter and the ahead Moon
		# separate by parallax.  The old dead-ahead chase view put the Moon
		# directly behind the craft, so the orbiter slid down the middle of the
		# disc and looked like it was entering or exiting the Moon.  From the side
		# it clearly flies past the lunar limb toward the near side.
		var _axis := (moon.position - earth.position).normalized()
		var _side := _axis.cross(Vector3.UP).normalized()
		camera.position = vehicle.position + _side * 8.5 + Vector3(0.0, 3.6, 0.0)
		camera.look_at(vehicle.position.lerp(moon.position, 0.22), Vector3.UP)
	else:
		# View the capture orbit from a HIGH angle so it reads as a ring circling
		# AROUND the Moon.  The near-horizontal orbit seen from the old low oblique
		# angle (-8.5,5.5,12) made the orbit's near arc and the growing trail cross
		# OVER the lunar face — the ellipse looked like it plunged into the Moon at
		# one limb and out the other, and the craft followed it, reading as "flying
		# inside the Moon."  From above, the ellipse (perigee 3.4 > disc radius 2.0)
		# circles the disc's rim and the craft only ever passes BEHIND the Moon.
		camera.position = moon.position + Vector3(-3.0, 13.0, 5.5)
		camera.look_at(moon.position, Vector3.UP)
	telemetry_label.text = "TRANSFER ELAPSED  %02d:%02d  |  DISTANCE TO MOON  %s  |  POLAR ORBIT INSERTION  100 km" % [int(t) / 60, int(t) % 60, _distance_text(t)]

func _set_plume(on: bool, intensity: float) -> void:
	if plume_grp:
		plume_grp.visible = on
		if on:
			var flick: float = 0.82 + 0.18 * sin(timer * 42.0)
			plume_grp.scale = Vector3(intensity, intensity * flick, intensity)
	if plume_light:
		plume_light.light_energy = 0.8 * intensity if on else 0.0

func _distance_text(t: float) -> String:
	if t < 7.0:
		return "384,400 km"
	if t < 15.0:
		return "%d km" % int(384400.0 * (1.0 - clamp((t - 7.0) / 8.0, 0.0, 1.0)) + 9000.0)
	return "%d km" % max(100, int(9000.0 * (1.0 - clamp((t - 15.0) / 7.0, 0.0, 1.0))))

# A point on the Earth phasing spiral at time tt (0..7): three revolutions whose
# radius climbs from low parking orbit to the translunar departure point, always
# clear of the Earth's surface.  Its end (tt=7) matches _fp[0] so the trail and
# the translunar line join seamlessly.
# A point on the Earth parking orbit at time tt (0..7): three concentric
# Keplerian ellipse passes that share one perigee, the apogee stepping up after
# each burn (reference steps 2-3).  Earth sits at the common focus, so the loops
# nest and touch at perigee — a real orbit-raising profile, not a smooth spiral.
func _parking_point(tt: float) -> Vector3:
	var per := 7.0 / 3.0
	var idx := clampi(int(tt / per), 0, 2)
	var rp := 3.7
	var ra: float = _PARK_APS[idx]
	var p := 2.0 * rp * ra / (rp + ra)
	var e := (ra - rp) / (ra + rp)
	var th := fmod(tt, per) / per * TAU
	var r := p / (1.0 + e * cos(th))
	var local := Vector3(cos(th) * r, 0.0, sin(th) * r * 0.9)
	return earth.position + Basis.from_euler(_ORBIT_PLANE) * local

func _phasing_point(tt: float) -> Vector3:
	var p1 := clampf(tt / 7.0, 0.0, 1.0)
	# Two revolutions instead of three: the stack circles Earth noticeably
	# slower.  A whole number of turns keeps the tt=7 endpoint identical, so the
	# translunar line still joins seamlessly.
	var ang := p1 * 2.0 * TAU
	var rr := lerpf(4.2, 5.4, p1)
	var local := Vector3(cos(ang) * rr, 0.0, sin(ang) * rr * 0.82)
	return earth.position + Basis.from_euler(_ORBIT_PLANE) * local

# Continue the phasing spiral past its nominal end (t=7) with the SAME rotation
# sense and a radius that keeps climbing outward, so a transfer built on these
# points peels off prograde — the craft unwinds the way it was already orbiting
# instead of being forced into a lateral turn that would demand a big plane-change.
func _spiral_extend(tt: float) -> Vector3:
	var p1 := tt / 7.0
	var ang := p1 * 2.0 * TAU
	var rr := lerpf(4.2, 5.4, minf(p1, 1.0)) + maxf(p1 - 1.0, 0.0) * 2.2
	var local := Vector3(cos(ang) * rr, 0.0, sin(ang) * rr * 0.82)
	return earth.position + Basis.from_euler(_ORBIT_PLANE) * local

# Rebuild the phasing trail as a line strip from t=0 up to the current time, so
# the trajectory visibly draws itself as the stack circles and recedes.
func _rebuild_phasing_trail(t: float) -> void:
	if not phasing_trail:
		return
	var steps := 140
	var verts := PackedVector3Array()
	for k in range(steps + 1):
		verts.append(_parking_point(t * float(k) / float(steps)))
	var lm := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	phasing_trail.mesh = lm
	phasing_trail.visible = true

# A point on the lunar capture spiral at time tt (15..22): three revolutions
# whose radius SHRINKS from a far approach down to the settled polar orbit,
# always clear of the Moon's surface.  Its start (tt=15) matches _fp[5] so the
# translunar line and this inward spiral join seamlessly.  Mirror of
# _phasing_point but far→near instead of near→far.
func _moon_point(tt: float) -> Vector3:
	# Concentric capture ellipses around the Moon: each braking burn at the shared
	# perigee lowers the apogee, winding the craft down into the settled low orbit
	# — the mirror of the Earth parking stack (reference steps 6-7).  The perigee
	# FACES EARTH (custom frame, +X along Moon→Earth) so the craft arrives at the
	# Moon's near side and the transfer line touches the visible limb instead of
	# crossing the sphere; perigee 4.6 > disc radius 2.0 keeps a clear margin so
	# the orbiter never looks like it is sitting on the lunar surface.
	var per := 7.0 / 3.0
	var lt := tt - 15.0
	var idx := clampi(int(lt / per), 0, 2)
	var rp := 4.6
	var ra: float = _CAP_APS[idx]
	var p := 2.0 * rp * ra / (rp + ra)
	var e := (ra - rp) / (ra + rp)
	var th := fmod(lt, per) / per * TAU
	var r := p / (1.0 + e * cos(th))
	var to_earth := (earth.position - moon.position).normalized()
	var zax := to_earth.cross(Vector3(0, 1, 0)).normalized()
	var yax := zax.cross(to_earth).normalized()
	var frame := Basis(to_earth, yax, zax)
	var local := Vector3(cos(th) * r, 0.0, sin(th) * r * 0.9)
	return moon.position + frame * local

# Rebuild the capture trail as a line strip that grows from the Moon-arrival
# point (t=15) up to the craft — the same progressive thin trajectory line the
# Earth spiral draws.  No thick static orbit ring is used; the trail itself
# shows the inward winding capture.
func _rebuild_moon_trail(t: float) -> void:
	if not moon_trail:
		return
	var steps := 140
	var verts := PackedVector3Array()
	for k in range(steps + 1):
		var tt: float = 15.0 + (t - 15.0) * float(k) / float(steps)
		verts.append(_moon_point(tt))
	var lm := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	moon_trail.mesh = lm
	moon_trail.visible = true

# Grow the translunar line out to the craft's current parameter so the path
# forms behind it rather than appearing all at once.
func _rebuild_flight_line(eased: float) -> void:
	if not flight_line:
		return
	var steps := 90
	var verts := PackedVector3Array()
	for k in range(steps + 1):
		verts.append(_flight_point(eased * float(k) / float(steps)))
	var lm := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	flight_line.mesh = lm

# Catmull-Rom sampling of the translunar waypoints (_fp), u in [0, 1].
func _flight_point(u: float) -> Vector3:
	if _fp.size() < 2:
		return Vector3.ZERO
	var n := _fp.size()
	var seg: float = clampf(u, 0.0, 1.0) * float(n - 1)
	var i: int = int(floor(seg))
	if i >= n - 1:
		i = n - 2
	var f: float = seg - float(i)
	return _catmull(_fp[maxi(i - 1, 0)], _fp[i], _fp[i + 1], _fp[min(i + 2, n - 1)], f)

func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, f: float) -> Vector3:
	# Centripetal Catmull-Rom (Barry–Goldman).  Knot spacing uses the square root
	# of each segment length, which stops the curve cusping/looping when the
	# waypoints are unevenly spaced — the uniform version made a corkscrew right
	# at the spacecraft, which reads as non-physical for a translunar path.
	var alpha := 0.5
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 1e-4), alpha)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 1e-4), alpha)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 1e-4), alpha)
	var tt := lerpf(t1, t2, f)
	var a1 := (p0 * (t1 - tt) + p1 * (tt - t0)) / (t1 - t0)
	var a2 := (p1 * (t2 - tt) + p2 * (tt - t1)) / (t2 - t1)
	var a3 := (p2 * (t3 - tt) + p3 * (tt - t2)) / (t3 - t2)
	var b1 := (a1 * (t2 - tt) + a2 * (tt - t0)) / (t2 - t0)
	var b2 := (a2 * (t3 - tt) + a3 * (tt - t1)) / (t3 - t1)
	var c := (b1 * (t2 - tt) + b2 * (tt - t1)) / (t2 - t1)
	return c
