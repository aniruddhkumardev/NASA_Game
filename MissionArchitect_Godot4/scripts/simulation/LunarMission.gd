## A Chandrayaan-inspired lunar-south-pole landing, not a satellite-orbit substitute.
extends Node3D

const LUNAR_TEXTURE := preload("res://assets/textures/nasa-lro-lunar-color-2k.jpg")
const LUNAR_MOSAIC  := preload("res://assets/textures/nasa-lro-moon-mosaic-1024.jpg")

var moon: MeshInstance3D
var moon_globe: MeshInstance3D
var _globe_center := Vector3(0.0, -11.0, 0.0)
var _globe_radius := 11.0
var scout: Node3D
var camera: Camera3D
var scan_label: Label
var phase_label: Label
var orbit_label: Label
var day_label: Label
var ice_bar: ProgressBar
var rover: Node3D
var ramp: MeshInstance3D
var ramp_group: Node3D
var ramp_pivot: Node3D
var wheel_spins: Array[Node3D] = []
var rover_travel := 0.0
# Distance from the rover's origin down to the lowest point of a grouser tooth
# (hub 0.13 below the origin, tooth standing proud of the 0.13 rim to ~0.153).
# The ride height is measured to the TOOTH tip, not the tyre, or the wheel
# looks like it is skimming the surface instead of pressing into it.
const _ROVER_CLEARANCE := 0.283
# Deployed ramp geometry, SOLVED against the real terrain in _build_vikram().
var ramp_slope_deg := 15.9
var ramp_foot_z := 2.35
var ramp_foot_y := 0.0
# Vikram's payload bay door — the panel that unfolds down and becomes the top
# of Pragyan's egress ramp.  Real Chandrayaan-3 sequence: door swings open,
# then the rover rolls out under its own power down the ramp, not a pop-in.
var door_pivot: Node3D
var deploy_timer := 0.0
var rover_egress_done := false
var mission_time := 0.0
var scan_progress := 0.0
var landed := false
var rover_deployed := false
# Chandrayaan-3 landing beats: the descent engine plume, the regolith dust that
# blows out radially under the lander, the touchdown callout and the wheel
# tracks Pragyan leaves on the surface.  These are the shots that define the
# real footage, so they are driven from the descent rather than being decoration.
var descent_plume: Node3D
var plume_flames: GPUParticles3D
var plume_nozzle: MeshInstance3D
var plume_throat: MeshInstance3D
var plume_ground_glow: MeshInstance3D
var plume_diamonds: Array[MeshInstance3D] = []
var rcs_jets: Array[MeshInstance3D] = []
var sep_rcs_jets: Array[MeshInstance3D] = []
var dust: MeshInstance3D
var callout: Label
var track_root: Node3D
var rover_dust: MeshInstance3D
var touchdown_dust := 0.0
var last_track_z := -99.0
var touchdown_announced := false
# Chandrayaan-3 orbit-phase beats the video opens with: the Orbiter carrying
# Vikram around the Moon, the labelled separation, then Vikram peeling off for
# its powered descent while the Orbiter holds a polar orbit.
var orbiter: Node3D
var vikram_lander: Node3D
var vikram_panel_pivots: Array[Node3D] = []
var vikram_panel_sides: Array[float] = []
var lbl_vikram: Label3D
var lbl_orbiter: Label3D
var lbl_sensor: Label3D
var lbl_camera: Label3D
var separated := false
# The closing shot of the video: permanently-shadowed south-pole craters ringed
# in green as the water-ice survey confirms ice traps.  Revealed progressively.
var psr_root: Node3D
var psr_rings: Array[MeshInstance3D] = []
var lbl_ice: Label3D
# The plume-scoured oval, raised soil collar, and footpad compression scars are
# the AFTERMATH of touchdown — the descent engine digs them out only as Vikram
# settles.  They must not sit at the landing site beforehand, so they live under
# this container, hidden until the lander is on the surface.
var landing_scar: Node3D
# Vikram's pre-landing hazard-detection pass: the descent-camera funnel sweeping
# the terrain, candidate site reticles (hazards rejected, one safe site locked),
# and the status readout that floats with the lander.
var survey_root: Node3D
var survey_cone: MeshInstance3D
var survey_ring: MeshInstance3D
var survey_status: Label3D
var site_nodes: Array[Node3D] = []
var site_mats: Array[StandardMaterial3D] = []
var site_labels: Array[Label3D] = []
var site_safe: Array[bool] = []
var site_reveal: Array[float] = []
# Mission-end controls.  This scene is a one-shot cinematic, so without an
# explicit "End Mission" action the player is stranded on the surface once the
# ice survey finishes.  The button aborts before touchdown and files the report
# after landing.
var end_btn: Button
var end_confirm: ConfirmationDialog
var finishing := false
var surface_complete_announced := false

func _ready() -> void:
	moon = get_node("Moon/MoonSurface")
	scout = get_node("LunarScout")
	camera = get_node("LunarCamera")
	scan_label = get_node("UI/Telemetry/ScanLabel")
	phase_label = get_node("UI/HUD/PhaseLabel")
	orbit_label = get_node("UI/Telemetry/OrbitLabel")
	day_label = get_node("UI/HUD/DayLabel")
	# Live-changing readouts carry the sanctioned red accent; the phase
	# headline stays neutral so the hierarchy survives the accent.
	MissionForge.live(scan_label)
	MissionForge.live(orbit_label)
	MissionForge.live(day_label)
	ice_bar = get_node("UI/Telemetry/IceBar")
	_setup_regolith()
	_add_surface_features()
	_add_landing_site_detail()
	_add_stars()
	_add_earth_in_sky()
	_build_moon_globe()
	_build_vikram()
	_build_orbiter()
	_build_callouts()
	_build_psr_markers()
	_build_site_survey()
	_build_dust()
	_build_tracks()
	_build_callout()
	_build_end_mission_controls()
	phase_label.text = "LUNAR ORBIT INSERTION — SOUTH POLE TARGET LOCKED"
	orbit_label.text = "100 km polar orbit  |  Vikram lander separation pending"
	print("[LunarMission] South-pole descent scene ready")

func _setup_regolith() -> void:
	var material := StandardMaterial3D.new()
	# NASA LRO lunar south pole colour — slightly warm grey
	material.albedo_color   = Color(0.55, 0.53, 0.50, 1.0)
	material.albedo_texture = LUNAR_TEXTURE
	material.uv1_scale      = Vector3(5.0, 5.0, 1.0)
	material.roughness      = 1.0
	material.metallic       = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Layer the low-res mosaic as a detail albedo for multi-scale grain (the
	# full LRO map carries broad geology; the mosaic adds fine regolith noise).
	material.detail_enabled  = true
	material.detail_mask     = LUNAR_MOSAIC
	material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	material.uv2_scale       = Vector3(12.0, 12.0, 1.0)
	_build_displaced_terrain(material)

## Add a starfield — 800 tiny white quads scattered on a large sphere
func _add_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var star_root := Node3D.new()
	star_root.name = "Starfield"
	add_child(star_root)

	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 1.0, 0.95, 1.0)
	star_mat.emission_energy_multiplier = 2.5
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	for i in range(800):
		# Random point on sphere (radius 180)
		var theta := rng.randf_range(0.0, TAU)
		var phi   := acos(rng.randf_range(-1.0, 1.0))
		var r     := 180.0
		var pos   := Vector3(
			r * sin(phi) * cos(theta),
			r * sin(phi) * sin(theta),
			r * cos(phi))
		# Don't put stars below horizon (negative Y from camera view)
		if pos.y < -10.0:
			continue
		var star := MeshInstance3D.new()
		var qm   := QuadMesh.new()
		var size := rng.randf_range(0.08, 0.28)
		qm.size  = Vector2(size, size)
		star.mesh = qm
		star.material_override = star_mat
		star.position = pos
		star_root.add_child(star)

## Add Earth visible in the black sky — a glowing blue sphere
func _add_earth_in_sky() -> void:
	var earth_node := Node3D.new()
	earth_node.name = "EarthInSky"
	add_child(earth_node)

	# Earth sphere — 55 units away, high in sky
	var earth_mesh_inst := MeshInstance3D.new()
	earth_mesh_inst.name = "EarthSphere"
	var sm := SphereMesh.new()
	sm.radius = 6.5
	sm.height = 13.0
	sm.radial_segments = 48
	sm.rings = 24
	earth_mesh_inst.mesh = sm

	var earth_mat := StandardMaterial3D.new()
	earth_mat.albedo_color = Color(0.08, 0.28, 0.72, 1.0)
	earth_mat.roughness    = 0.75
	earth_mat.metallic     = 0.0
	earth_mat.emission_enabled = true
	earth_mat.emission = Color(0.05, 0.18, 0.55, 1.0)
	earth_mat.emission_energy_multiplier = 0.4
	earth_mesh_inst.material_override = earth_mat
	earth_mesh_inst.position = Vector3(-28.0, 38.0, -55.0)
	earth_node.add_child(earth_mesh_inst)

	# Atmosphere halo
	var atmo := MeshInstance3D.new()
	atmo.name = "EarthAtmo"
	var atmo_sm := SphereMesh.new()
	atmo_sm.radius = 6.9
	atmo_sm.height = 13.8
	atmo_sm.radial_segments = 32
	atmo_sm.rings = 16
	atmo.mesh = atmo_sm
	var atmo_mat := StandardMaterial3D.new()
	atmo_mat.albedo_color  = Color(0.3, 0.6, 1.0, 0.12)
	atmo_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmo_mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	atmo_mat.emission_enabled = true
	atmo_mat.emission = Color(0.2, 0.5, 1.0, 1.0)
	atmo_mat.emission_energy_multiplier = 0.6
	atmo.material_override = atmo_mat
	atmo.position = earth_mesh_inst.position
	earth_node.add_child(atmo)

## A cratered lunar GLOBE used only for the opening orbit phase.  The video's
## orbit shots circle a spherical Moon, so the flat landing terrain (which is
## right for the descent) is swapped for this globe while the stack is still in
## orbit; the two never appear at once.
func _build_moon_globe() -> void:
	moon_globe = MeshInstance3D.new()
	moon_globe.name = "MoonGlobe"
	var sm := SphereMesh.new()
	sm.radius = _globe_radius
	sm.height = _globe_radius * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	moon_globe.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.71, 0.68)
	gm.albedo_texture = LUNAR_TEXTURE
	gm.roughness = 1.0
	gm.metallic = 0.0
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	moon_globe.material_override = gm
	moon_globe.position = _globe_center
	add_child(moon_globe)

func _rock_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.20, 0.22)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

## Real cratered terrain: a displaced grid where each crater is a concave bowl
## with a raised rim. The landing apron is kept flat so the lander and rover
## sit correctly; craters and relief live further out.
var _terrain_noise := FastNoiseLite.new()
const _TERRAIN_CRATERS := [
	[Vector2(-12.0, -6.0),  4.5, 1.30],   # large south-polar crater
	[Vector2( 9.0, -11.0),  6.0, 1.60],   # biggest — partially in frame
	[Vector2(-6.5,  11.5),  3.4, 0.90],
	[Vector2(13.0,   5.0),  3.0, 0.80],
	[Vector2( 2.0, -14.0),  5.0, 1.20],
	[Vector2(-15.0,  8.0),  5.5, 1.40],
	[Vector2( 6.0,  13.0),  2.6, 0.65],
	[Vector2(-3.0,  -9.0),  2.2, 0.55],
	[Vector2( 0.5,  -5.5),  1.6, 0.38],   # small fresh crater near lander
	[Vector2(-5.0,   3.8),  1.2, 0.28],   # tiny crater cluster
	[Vector2( 4.5,  -2.0),  0.9, 0.22],
]

func _moon_height(x: float, z: float) -> float:
	var h := _terrain_noise.get_noise_2d(x, z) * 0.45
	for c in _TERRAIN_CRATERS:
		var delta: Vector2 = Vector2(x, z) - Vector2(c[0])
		var d: float = delta.length()
		var r: float = c[1]
		if d < r * 1.5:
			var depth: float = c[2]
			if d < r:
				var t := d / r
				h += -depth * (1.0 - t * t)
			var rim := smoothstep(r * 0.85, r * 1.15, d) * (1.0 - smoothstep(r * 1.15, r * 1.5, d))
			h += depth * 0.55 * rim
	# Landing apron: damp every relief toward zero near the pad.
	h *= smoothstep(1.6, 7.5, Vector2(x, z).length())
	return h

func _build_displaced_terrain(material: StandardMaterial3D) -> void:
	_terrain_noise.seed = 11
	_terrain_noise.frequency = 0.045
	_terrain_noise.fractal_octaves = 5   # more octaves = more fine detail
	var size := 40.0   # slightly larger terrain
	var n    := 100    # higher resolution grid (100x100 quads)
	var step := size / n
	var half := size * 0.5
	var eps  := 0.20
	var st   := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for i in range(n):
		for j in range(n):
			var x0 := -half + float(i) * step
			var z0 := -half + float(j) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var corners := [Vector2(x0,z0), Vector2(x1,z0), Vector2(x1,z1), Vector2(x0,z1)]
			for v in corners:
				st.set_normal(_moon_gradient_normal(v.x, v.y, eps))
				st.set_uv(Vector2((v.x + half) / size, (v.y + half) / size))
				st.add_vertex(Vector3(v.x, _moon_height(v.x, v.y), v.y))
			st.add_index(base + 0)
			st.add_index(base + 1)
			st.add_index(base + 2)
			st.add_index(base + 0)
			st.add_index(base + 2)
			st.add_index(base + 3)
			base += 4
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	moon.mesh = mesh
	material.uv1_scale = Vector3(1.0, 1.0, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	moon.material_override = material

func _moon_gradient_normal(x: float, z: float, eps: float) -> Vector3:
	var dx := (_moon_height(x + eps, z) - _moon_height(x - eps, z)) / (2.0 * eps)
	var dz := (_moon_height(x, z + eps) - _moon_height(x, z - eps)) / (2.0 * eps)
	return Vector3(-dx, 1.0, -dz).normalized()

func _add_surface_features() -> void:
	# Crumpled boulders — displaced spheres with ragged silhouettes, not toys.
	var rock_material := _rock_material()
	var rock_meshes: Array[Mesh] = []
	for seed_value in [3, 17, 41]:
		rock_meshes.append(_crumpled_rock(seed_value))
	for spec in [[-2.2, -.4, .28], [-1.5, 1.25, .18], [1.6, .8, .18], [2.0, -1.0, .34], [3.7, .3, .22], [-3.3, 1.5, .24], [4.6, -1.9, .30], [-4.1, -2.6, .26]]:
		var rock := MeshInstance3D.new()
		rock.mesh = rock_meshes[(int(abs(spec[0]) * 7.0) + int(abs(spec[1]) * 5.0)) % rock_meshes.size()]
		rock.position = Vector3(spec[0], _moon_height(spec[0], spec[1]) + spec[2] * .55, spec[1])
		rock.scale = Vector3.ONE * spec[2]
		rock.rotation_degrees = Vector3(fposmod(spec[0] * 37.0, 360.0), fposmod(spec[1] * 53.0, 360.0), 12.0)
		rock.material_override = rock_material
		get_node("Moon").add_child(rock)

## Ground truth at an actual landing point.  A soft-landing engine scours a
## darker oval out of the mature regolith and throws a raised collar of
## displaced soil around it, and the vicinity is littered with pebbles the
## hazard camera would have screened out.  Parented to the terrain container so
## it disappears with the flat-ground phase during the orbit leg.
func _add_landing_site_detail() -> void:
	var site := get_node("Moon")
	# The scour/collar/scars only appear once the engine has actually dug them.
	landing_scar = Node3D.new()
	landing_scar.name = "LandingScar"
	landing_scar.visible = false
	site.add_child(landing_scar)
	# Plume scour and its raised soil collar.  These MUST conform to the
	# displaced ground: a primitive CylinderMesh or TorusMesh sits at one
	# constant height while the regolith around the lander rises and falls by
	# tens of centimetres, so they clipped through the soil and the collar read
	# as a floating donut pool around Vikram.
	var scour_mat := StandardMaterial3D.new()
	scour_mat.albedo_color = Color(0.36, 0.35, 0.33, 1.0)
	scour_mat.roughness = 1.0
	scour_mat.metallic = 0.0
	scour_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var scour := MeshInstance3D.new()
	scour.mesh = _conformal_patch(0.05, 0.45, 1.05, 4, 34, 0.02, 0.012)
	scour.material_override = scour_mat
	landing_scar.add_child(scour)
	var collar_mat := StandardMaterial3D.new()
	collar_mat.albedo_color = Color(0.58, 0.56, 0.53, 1.0)
	collar_mat.roughness = 1.0
	collar_mat.metallic = 0.0
	collar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var collar := MeshInstance3D.new()
	collar.mesh = _conformal_patch(0.05, 0.45, 1.52, 4, 40, 0.69, 0.030)
	collar.material_override = collar_mat
	landing_scar.add_child(collar)
	# Footpad compression scars — landers do not settle onto a pristine surface,
	# and the dark depressions under each pad are what sell the contact.
	var scar_mat := StandardMaterial3D.new()
	scar_mat.albedo_color = Color(0.33, 0.32, 0.30, 1.0)
	scar_mat.roughness = 1.0
	scar_mat.metallic = 0.0
	scar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var fa := float(i) * PI * 0.5 + PI * 0.25
		var fx := cos(fa) * 0.82
		var fz := sin(fa) * 0.82
		var scar := MeshInstance3D.new()
		scar.mesh = _conformal_patch(fx, fz, 0.30, 3, 20, 0.05, -0.012)
		scar.material_override = scar_mat
		landing_scar.add_child(scar)
	# Rock field — small at first, thinning outward, kept clear of the egress
	# corridor so nothing sits under the ramp or in Pragyan's path.
	var rock_mat := _rock_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = 770421
	for i in 44:
		var a := rng.randf_range(0.0, TAU)
		var r := 1.85 + pow(rng.randf(), 1.7) * 8.5
		var px := cos(a) * r
		var pz := sin(a) * r
		if absf(px) < 0.75 and pz > 0.8 and pz < 5.6:
			continue
		var s := lerpf(0.05, 0.28, pow(rng.randf(), 2.0))
		var rock := MeshInstance3D.new()
		rock.mesh = _crumpled_rock(900 + i)
		rock.material_override = rock_mat
		rock.position = Vector3(px, _moon_height(px, pz) + s * 0.40, pz)
		rock.scale = Vector3(s, s * rng.randf_range(0.52, 0.88), s)
		rock.rotation = Vector3(rng.randf_range(-0.35, 0.35),
			rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35))
		site.add_child(rock)
	# Fine pebble scatter immediately around the footprints — the scale that a
	# lander shot actually shows in the foreground.
	for i in 60:
		var pa := rng.randf_range(0.0, TAU)
		var pr := rng.randf_range(1.1, 4.2)
		var qx := cos(pa) * pr
		var qz := sin(pa) * pr
		if absf(qx) < 0.75 and qz > 0.8 and qz < 5.6:
			continue
		var qs := rng.randf_range(0.018, 0.052)
		var pebble := MeshInstance3D.new()
		pebble.mesh = _crumpled_rock(4000 + i)
		pebble.material_override = rock_mat
		pebble.position = Vector3(qx, _moon_height(qx, qz) + qs * 0.35, qz)
		pebble.scale = Vector3(qs, qs * 0.7, qs)
		site.add_child(pebble)
	# Wheel-thrown regolith.  The Moon has no atmosphere, so there is no plume
	# — only a low skirt of fines that leaves the contact patch and falls right
	# back down, which is exactly what the Apollo and Pragyan drives show.
	rover_dust = MeshInstance3D.new()
	rover_dust.name = "RoverDust"
	var rd := SphereMesh.new()
	rd.radius = 0.30
	rd.height = 0.16
	rd.radial_segments = 16
	rd.rings = 6
	rover_dust.mesh = rd
	var rdm := StandardMaterial3D.new()
	rdm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rdm.albedo_color = Color(0.68, 0.66, 0.62, 0.26)
	rdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rdm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rover_dust.material_override = rdm
	rover_dust.visible = false
	add_child(rover_dust)

## Radial annulus (or disc when r_in is near zero) whose every vertex is placed
## on the displaced regolith surface, with matching terrain normals.  Used for
## ground marks that have to hug the terrain instead of intersecting it.
func _conformal_patch(cx: float, cz: float, r_out: float, rings: int, segs: int,
		r_in: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in range(rings + 1):
		var rr := r_out * lerpf(r_in, 1.0, float(ri) / float(rings))
		for si in range(segs + 1):
			var a := float(si) / float(segs) * TAU
			var px := cx + cos(a) * rr
			var pz := cz + sin(a) * rr
			st.set_normal(_moon_gradient_normal(px, pz, 0.25))
			st.set_uv(Vector2(float(si) / float(segs), float(ri) / float(rings)))
			st.add_vertex(Vector3(px, _moon_height(px, pz) + lift, pz))
	for ri in range(rings):
		for si in range(segs):
			var p00 := ri * (segs + 1) + si
			var p01 := p00 + 1
			var p10 := p00 + (segs + 1)
			var p11 := p10 + 1
			st.add_index(p00)
			st.add_index(p10)
			st.add_index(p01)
			st.add_index(p01)
			st.add_index(p10)
			st.add_index(p11)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh

func _crumpled_rock(seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in range(verts.size()):
		var v := verts[k]
		var crunch := 1.0 + rng.randf_range(-0.28, 0.22)
		verts[k] = Vector3(v.x * crunch, v.y * (1.0 + rng.randf_range(-0.18, 0.12)), v.z * crunch)
	arrays[0] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(verts.size()):
		normals[k] = verts[k].normalized()
	arrays[1] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _make_box(size: Vector3, position: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = material
	parent.add_child(node)
	return node

func _build_vikram() -> void:
	var lander := Node3D.new()
	lander.name = "VikramLander"
	scout.add_child(lander)
	vikram_lander = lander

	# Gold MLI foil (Multi-Layer Insulation) — ISRO gold colour.  Reuses the
	# orbiter's procedural Kapton quilt: a crinkled normal map plus per-panel
	# albedo variation with dark stitch seams.  Flat metallic gold reads as
	# painted plastic; the real lander and rover are wrapped in WRINKLED foil
	# that catches the low sun in dozens of tiny facets.
	var gold := StandardMaterial3D.new()
	var mli := _make_mli_textures()
	gold.albedo_texture = mli[0]
	gold.normal_enabled = true
	gold.normal_texture = mli[1]
	gold.normal_scale   = 0.85
	gold.uv1_scale      = Vector3(2.6, 2.6, 2.6)
	gold.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	gold.metallic  = 0.74
	gold.roughness = 0.38
	gold.emission_enabled = true
	gold.emission = Color(0.5, 0.32, 0.02, 1.0)
	gold.emission_energy_multiplier = 0.06

	# Dark structural panels
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.06, 0.12, 1.0)
	dark.metallic  = 0.55
	dark.roughness = 0.45

	# Silver thruster/structure
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.72, 0.72, 0.76, 1.0)
	silver.metallic  = 0.92
	silver.roughness = 0.22

	# Main body — hexagonal truncated cone (lander bus)
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius    = 0.52
	body_mesh.bottom_radius = 0.70
	body_mesh.height        = 0.52
	body_mesh.radial_segments = 6   # hexagonal for ISRO style
	body.mesh              = body_mesh
	body.position.y        = 0.74
	body.material_override = gold
	lander.add_child(body)

	# Propulsion module on top
	var prop := MeshInstance3D.new()
	var prop_mesh := CylinderMesh.new()
	prop_mesh.top_radius    = 0.34
	prop_mesh.bottom_radius = 0.52
	prop_mesh.height        = 0.30
	prop_mesh.radial_segments = 6
	prop.mesh              = prop_mesh
	prop.position.y        = 1.15
	prop.material_override = silver
	lander.add_child(prop)

	# Structural longerons at the six bus corners.  A plain foil drum looks like
	# an inflatable; the visible frame carries the read that this is built
	# hardware with panels bolted onto it.
	for i in 6:
		var ca := float(i) * PI / 3.0
		_make_box(Vector3(0.05, 0.56, 0.05),
			Vector3(cos(ca) * 0.63, 0.74, sin(ca) * 0.63), silver, lander)
	# Equipment shelf ring at the base of the bus — the dark beam the deck sits on.
	var shelf := MeshInstance3D.new()
	var shelf_mesh := TorusMesh.new()
	shelf_mesh.inner_radius = 0.66
	shelf_mesh.outer_radius = 0.72
	shelf_mesh.rings = 30
	shelf_mesh.ring_segments = 5
	shelf.mesh = shelf_mesh
	shelf.position.y = 0.50
	shelf.material_override = dark
	lander.add_child(shelf)
	# Payload-deck instrument boxes bolted to the flank beside the bay.
	_make_box(Vector3(0.20, 0.15, 0.16), Vector3(-0.50, 0.66, 0.30), dark, lander)
	_make_box(Vector3(0.16, 0.12, 0.20), Vector3( 0.52, 0.68, 0.26), dark, lander)
	# Chaastya-like IIT-DUS instrument package on the front deck, above the bay.
	_make_box(Vector3(0.24, 0.11, 0.17), Vector3(0.0, 1.03, 0.40), gold, lander)
	# Four RCS thruster quads on the propulsion deck.
	for i in 4:
		var ta := float(i) * PI * 0.5 + PI * 0.25
		for dz in [0.0, 0.05]:
			var nozzle := MeshInstance3D.new()
			var nm := CylinderMesh.new()
			nm.top_radius = 0.026
			nm.bottom_radius = 0.014
			nm.height = 0.05
			nm.radial_segments = 10
			nozzle.mesh = nm
			nozzle.position = Vector3(cos(ta) * 0.30, 1.30 + dz, sin(ta) * 0.30)
			nozzle.material_override = dark
			lander.add_child(nozzle)
	# Radar altimetry horns under the deck — the sensors that called the landing.
	for i in 2:
		var hx := -0.26 + float(i) * 0.52
		var horn := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.055
		hm.bottom_radius = 0.030
		hm.height = 0.09
		hm.radial_segments = 12
		horn.mesh = hm
		horn.position = Vector3(hx, 0.44, 0.52)
		horn.rotation_degrees.x = 18.0
		horn.material_override = silver
		lander.add_child(horn)
	# Harness runs across the foil — thin dark tubes that make the gold wrap look
	# like an installed thermal blanket rather than a painted surface.
	for hy in [0.62, 0.86]:
		var harness := MeshInstance3D.new()
		var hmesh := TorusMesh.new()
		hmesh.inner_radius = 0.685
		hmesh.outer_radius = 0.700
		hmesh.rings = 28
		hmesh.ring_segments = 4
		harness.mesh = hmesh
		harness.position.y = hy
		harness.material_override = dark
		lander.add_child(harness)

	# 4 landing legs — matte aluminium, not mirror silver.  A high-metallic /
	# low-roughness leg reflects the sun straight into the camera and reads as
	# a glowing engine plume that never shuts off after touchdown.
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.52, 0.53, 0.56, 1.0)
	leg_mat.metallic = 0.35
	leg_mat.roughness = 0.62
	# Crushed regolith under each footpad is added by _add_landing_site_detail(),
	# which can build it conformal to the displaced terrain.  A flat disc here
	# would sit at one constant height while the ground slopes under it.
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var leg := _make_box(Vector3(0.07, 0.82, 0.07),
			Vector3(cos(a) * 0.58, 0.38, sin(a) * 0.58), leg_mat, lander)
		leg.rotation_degrees.z = -sin(a) * 28.0
		leg.rotation_degrees.x =  cos(a) * 28.0
		# Secondary dorsal brace — real Vikram legs are triangulated, not a
		# single stick, and the brace is what makes the silhouette read as a leg.
		var brace := _make_box(Vector3(0.045, 0.56, 0.045),
			Vector3(cos(a) * 0.46, 0.34, sin(a) * 0.46), leg_mat, lander)
		brace.rotation_degrees.z = -sin(a) * 12.0
		brace.rotation_degrees.x =  cos(a) * 12.0
		# Foot pad — a shallow drum with a raised rim so it is not a flat coin.
		var foot := MeshInstance3D.new()
		var foot_mesh := CylinderMesh.new()
		foot_mesh.top_radius    = 0.18
		foot_mesh.bottom_radius = 0.20
		foot_mesh.height        = 0.07
		foot_mesh.radial_segments = 18
		foot.mesh              = foot_mesh
		foot.position          = Vector3(cos(a) * 0.82, 0.05, sin(a) * 0.82)
		foot.material_override = leg_mat
		lander.add_child(foot)
		var rim := MeshInstance3D.new()
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.19
		rim_mesh.outer_radius = 0.225
		rim_mesh.rings = 18
		rim_mesh.ring_segments = 4
		rim.mesh = rim_mesh
		rim.position = Vector3(cos(a) * 0.82, 0.022, sin(a) * 0.82)
		rim.material_override = leg_mat
		lander.add_child(rim)

	# Solar panels (2x) on fold hinges so Vikram can stow them and fit INSIDE
	# the orbiter's payload bay during cruise, then deploy them on separation.
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "PanelPivot"
		pivot.position = Vector3(side * 0.34, 0.72, 0.0)
		lander.add_child(pivot)
		_make_box(Vector3(1.35, 0.032, 0.40), Vector3(side * 0.71, 0.0, 0.0), dark, pivot)
		var cell_mat := StandardMaterial3D.new()
		cell_mat.albedo_color = Color(0.04, 0.10, 0.45, 1.0)
		cell_mat.metallic  = 0.15
		cell_mat.roughness = 0.55
		cell_mat.emission_enabled = true
		cell_mat.emission = Color(0.02, 0.06, 0.30, 1.0)
		cell_mat.emission_energy_multiplier = 0.12
		_make_box(Vector3(1.30, 0.034, 0.36), Vector3(side * 0.71, 0.0, 0.0), cell_mat, pivot)
		vikram_panel_pivots.append(pivot)
		vikram_panel_sides.append(side)

	# High-gain antenna
	var antenna := MeshInstance3D.new()
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius    = 0.022
	antenna_mesh.bottom_radius = 0.038
	antenna_mesh.height        = 0.68
	antenna.mesh              = antenna_mesh
	antenna.position.y        = 1.30
	antenna.material_override = silver
	lander.add_child(antenna)

	# Antenna dish
	var dish := MeshInstance3D.new()
	var dish_mesh := SphereMesh.new()
	dish_mesh.radius = 0.18
	dish_mesh.height = 0.09
	dish.mesh = dish_mesh
	dish.position = Vector3(0, 1.70, 0)
	dish.material_override = silver
	lander.add_child(dish)

	# Descent engines (4x visible nozzles)
	for i in 4:
		var a := float(i) * PI * 0.5
		var eng := MeshInstance3D.new()
		var eng_mesh := CylinderMesh.new()
		eng_mesh.top_radius    = 0.08
		eng_mesh.bottom_radius = 0.14
		eng_mesh.height        = 0.22
		eng.mesh              = eng_mesh
		eng.position          = Vector3(cos(a) * 0.42, 0.04, sin(a) * 0.42)
		eng.material_override = dark
		lander.add_child(eng)

	# Pragyan's egress ramp — a fixed ground-to-sill bridge that unfolds flat
	# against the door.  Kept hidden until the door has finished swinging so
	# the sequence reads as door-then-roll, not a slab appearing out of nowhere.
	# The panel, its side rails, and the rungs are grouped so they appear as
	# one piece of hardware.
	var ramp_grp := Node3D.new()
	ramp_grp.name = "RampGroup"
	ramp_grp.visible = false
	lander.add_child(ramp_grp)
	ramp_group = ramp_grp
	# The ramp hangs from its OWN hinge at the bay sill so it can swing down
	# into place.  It used to be switched from hidden to fully deployed in a
	# single frame, which is exactly the "stairs appear out of nowhere" the user
	# flagged.  It now starts raised on the hinge and is visible from the moment
	# the door begins to unlatch, so it is never conjured mid-shot.
	ramp_pivot = Node3D.new()
	ramp_pivot.name = "RampPivot"
	ramp_pivot.position = Vector3(0, 0.353, 1.12)
	# Stowed angle.  The panel carries its own deployment slope, so the STOWED
	# angle has to clear that: -45° only lifted it ~29° above horizontal and the
	# thing read as a plank lying flat on the ground, while -112° stood it fully
	# vertical and turned it into a bright monolith taller than the lander.
	# -62° gives a ~46° raised gangway — unmistakably "not lowered yet", and it
	# still swings through 62° when it comes down.
	ramp_pivot.rotation_degrees.x = -62.0
	ramp_grp.add_child(ramp_pivot)
	# Ramp panel: from the door tip (0, 0.35, 1.12) down to the regolith
	# (0, 0.0, 2.35).  Length 1.30 at ~16°, so the rover rolls down under its
	# own drive without visibly floating or clipping.
	# A near-black navy panel disappears against shadowed regolith, so the ramp
	# gets its own bright anodised aluminium with a faint emission lift — the
	# rover must have something visibly to roll down.
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.58, 0.60, 0.64, 1.0)
	ramp_mat.metallic = 0.45
	ramp_mat.roughness = 0.48
	ramp_mat.emission_enabled = true
	ramp_mat.emission = Color(0.16, 0.17, 0.19)
	ramp_mat.emission_energy_multiplier = 0.18
	ramp = _make_box(Vector3(0.70, 0.05, 1.30),
		Vector3(0, -0.178, 0.615), ramp_mat, ramp_pivot)
	# The deployed slope is SOLVED so the panel's foot actually lands on the
	# displaced regolith.  A hard-coded 15.9° assumed the soil out at z=2.35 sat
	# at y=0 — it does not — so the ramp hung in the air with a visible gap under
	# its lower end and read as a loose plank instead of a gangway.
	ramp_slope_deg = _solve_ramp_slope()
	ramp.rotation_degrees.x = ramp_slope_deg
	# Centre the panel on its own axis, half its length from the hinge, so it
	# spans hinge→foot exactly whatever slope the solver returned.
	var rs := deg_to_rad(ramp_slope_deg)
	ramp.position = Vector3(0, -0.65 * sin(rs), 0.65 * cos(rs))
	# Rails and rungs are children of the panel so they inherit its slope.
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.55, 0.57, 0.60, 1.0)
	rail_mat.metallic = 0.55
	rail_mat.roughness = 0.52
	for sx in [-1.0, 1.0]:
		_make_box(Vector3(0.05, 0.08, 1.30), Vector3(sx * 0.35, 0.04, 0), rail_mat, ramp)
	# Anti-slip rungs, kept FLUSH with the panel top (half-thickness 0.025).
	# Standing them proud turned the ramp into a staircase and Pragyan's wheels
	# visibly sank down between the steps.
	for rung_i in 6:
		var rz := -0.55 + float(rung_i) * 0.22
		_make_box(Vector3(0.66, 0.014, 0.040), Vector3(0, 0.024, rz), rail_mat, ramp)
	# Ground foot plate at the lower end (local +Z is the downhill end of the
	# slope).  Without it the ramp looks like a plank leaning on nothing, and the
	# rover appears to fall off the edge instead of rolling onto soil.
	_make_box(Vector3(0.70, 0.035, 0.26), Vector3(0, -0.045, 0.74), rail_mat, ramp)
	for sx in [-1.0, 1.0]:
		_make_box(Vector3(0.05, 0.06, 0.26), Vector3(sx * 0.35, -0.01, 0.74), rail_mat, ramp)
	# Undside stiffener ribs, laid FLAT against the panel bottom.  The earlier
	# "bracing struts" were free-floating boxes rotated -34°, and they stuck out
	# through the underside like broken legs.
	for rib_i in 3:
		_make_box(Vector3(0.66, 0.030, 0.030),
			Vector3(0, -0.040, -0.45 + float(rib_i) * 0.45), rail_mat, ramp)
	# Payload bay interior — a dark inset on the lander's front face so when the
	# door swings open there is a real shadowed cavity Pragyan can roll out of.
	var bay_mat := StandardMaterial3D.new()
	bay_mat.albedo_color = Color(0.02, 0.02, 0.03)
	bay_mat.roughness = 0.95
	bay_mat.metallic = 0.0
	_make_box(Vector3(0.56, 0.34, 0.06), Vector3(0, 0.55, 0.65), bay_mat, lander)
	# Bay door — hinged at its bottom edge so it swings outward and lays flat,
	# becoming the upper section of the ramp.  Real Vikram design.  Given real
	# thickness so an open door reads as a deployed panel, not an edge-on line.
	door_pivot = Node3D.new()
	door_pivot.name = "BayDoorPivot"
	door_pivot.position = Vector3(0, 0.35, 0.70)
	lander.add_child(door_pivot)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.78, 0.56, 0.14, 1.0)
	door_mat.metallic = 0.75
	door_mat.roughness = 0.30
	door_mat.emission_enabled = true
	door_mat.emission = Color(0.20, 0.13, 0.02)
	door_mat.emission_energy_multiplier = 0.45
	_make_box(Vector3(0.60, 0.42, 0.05), Vector3(0, 0.21, 0), door_mat, door_pivot)
	# Structural ribs on the door's outer face.
	for dy in [0.08, 0.21, 0.34]:
		_make_box(Vector3(0.58, 0.025, 0.065), Vector3(0, dy, 0.008), rail_mat, door_pivot)
	door_pivot.rotation.x = 0.0

	# Vikram's throttled descent engine, built the way a real over-expanded
	# vacuum jet actually looks: a white-hot throat at the nozzle exit, a chain of
	# bright shock diamonds running down a narrow incandescent core, and a wide
	# faint cyan-blue envelope fanning out around it.  The diamonds are the part
	# the eye reads as "engine" — without them any glowing cone just looks like a
	# torch, and the previous version was a plain cone tapering to a point with a
	# flat cap at the engine, which rendered as a grey traffic cone.
	descent_plume = Node3D.new()
	descent_plume.name = "DescentPlume"
	descent_plume.position = Vector3(0.0, -0.21, 0.0)
	lander.add_child(descent_plume)
	# Engine bell.  This is hardware, not flame, so it lives on the lander and
	# keeps its own size instead of stretching with the plume.
	plume_nozzle = MeshInstance3D.new()
	var noz_mesh := CylinderMesh.new()
	noz_mesh.top_radius    = 0.10
	noz_mesh.bottom_radius = 0.17
	noz_mesh.height        = 0.16
	noz_mesh.radial_segments = 18
	noz_mesh.rings         = 1
	noz_mesh.cap_top    = false
	noz_mesh.cap_bottom = false
	plume_nozzle.mesh = noz_mesh
	plume_nozzle.position = Vector3(0.0, 0.08, 0.0)
	plume_nozzle.material_override = dark
	lander.add_child(plume_nozzle)
	# White-hot throat — the only place the exhaust is still dense enough to burn
	# flat-out white.  Sitting it right at the nozzle exit gives the jet its hot
	# anchor point, which is what makes the blue below it read as flame.
	plume_throat = MeshInstance3D.new()
	var thr_mesh := SphereMesh.new()
	thr_mesh.radius = 0.10
	thr_mesh.height = 0.20
	thr_mesh.radial_segments = 18
	thr_mesh.rings = 8
	plume_throat.mesh = thr_mesh
	plume_throat.scale = Vector3(1.0, 0.7, 1.0)
	var throat_mat := StandardMaterial3D.new()
	throat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	throat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	throat_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
	throat_mat.albedo_color = Color(1.0, 0.98, 0.92, 0.85)
	throat_mat.emission_enabled = true
	throat_mat.emission = Color(1.0, 0.97, 0.88)
	throat_mat.emission_energy_multiplier = 2.2
	plume_throat.material_override = throat_mat
	descent_plume.add_child(plume_throat)
	# The flame BODY as a GPU particle stream.  A mesh cone always shows a hard
	# silhouette and a stack of billboard puffs reads as a string of pearls; a real
	# rocket flame is a turbulent, translucent column that is white-hot at the
	# nozzle and cools to cyan-blue as it expands and thins — which is exactly what
	# a colour-over-lifetime particle stream gives you for free.
	plume_flames = GPUParticles3D.new()
	plume_flames.name = "FlameStream"
	plume_flames.amount = 170
	plume_flames.lifetime = 0.5
	plume_flames.one_shot = false
	plume_flames.preprocess = 0.5
	plume_flames.local_coords = true
	# A particle system is culled to its visibility AABB, and the default tiny box
	# hides the whole flame the moment a particle leaves the emitter.  Give it room
	# to cover the full column or nothing renders.
	plume_flames.visibility_aabb = AABB(Vector3(-1.2, -2.6, -1.2), Vector3(2.4, 3.2, 2.4))
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 9.0
	pmat.initial_velocity_min = 3.0
	pmat.initial_velocity_max = 4.6
	pmat.gravity = Vector3.ZERO
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.05
	pmat.scale_min = 0.5
	pmat.scale_max = 0.9
	# Puffs grow as they travel so the column widens downstream like an expanding
	# exhaust plume instead of staying a uniform tube.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(0.4, 1.0))
	grow.add_point(Vector2(1.0, 1.7))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pmat.scale_curve = grow_tex
	# White-hot at birth -> cyan-blue -> gone.  The alpha channel fades each puff
	# out at the tip so the column ends softly, and because only the very start is
	# white the body reads as BLUE, not the washed-out white beam the mesh version
	# produced.
	var cramp := Gradient.new()
	cramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.8), Color(0.55, 0.8, 1.0, 0.6),
		Color(0.18, 0.48, 1.0, 0.34), Color(0.08, 0.28, 1.0, 0.0)])
	cramp.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	var cramp_tex := GradientTexture1D.new()
	cramp_tex.gradient = cramp
	pmat.color_ramp = cramp_tex
	plume_flames.process_material = pmat
	var fquad := QuadMesh.new()
	fquad.size = Vector2(0.30, 0.30)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_texture = _radial_glow_texture()
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fquad.material = fmat
	plume_flames.draw_pass_1 = fquad
	descent_plume.add_child(plume_flames)
	# Shock diamonds (Mach disks) — the stacked bright rings marching down the jet.
	var dia_mat := StandardMaterial3D.new()
	dia_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dia_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dia_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
	dia_mat.albedo_color = Color(1.0, 0.97, 0.88, 0.55)
	dia_mat.emission_enabled = true
	dia_mat.emission = Color(1.0, 0.95, 0.82)
	dia_mat.emission_energy_multiplier = 3.0
	for di in 5:
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		# Each disk sits on the core's expansion line and gets wider going down.
		var dr: float = 0.075 + di * 0.036
		dm.top_radius    = dr
		dm.bottom_radius = dr
		dm.height        = 0.030
		dm.radial_segments = 20
		dm.rings         = 1
		dm.cap_top    = true
		dm.cap_bottom = false
		disc.mesh = dm
		disc.position = Vector3(0.0, -0.10 - di * 0.17, 0.0)
		disc.material_override = dia_mat
		descent_plume.add_child(disc)
		plume_diamonds.append(disc)
	# Attitude thrusters.  Vikram trims its descent on the roll axis, so a few
	# short side jets firing in and out of the gold foil sell the fact that the
	# vehicle is actively flying rather than just falling on one big flame.
	for ri in 4:
		var ang_r := TAU * float(ri) / 4.0 + PI / 4.0
		var jet := MeshInstance3D.new()
		var jm := CylinderMesh.new()
		jm.top_radius    = 0.022
		jm.bottom_radius = 0.075
		jm.height        = 0.30
		jm.radial_segments = 12
		jm.rings         = 3
		jm.cap_top    = false
		jm.cap_bottom = false
		jet.mesh = jm
		jet.position = Vector3(sin(ang_r) * 0.46, 0.30, cos(ang_r) * 0.46)
		# Outward and down, which is how a vernier pointing off the thrust axis
		# has to be aimed to produce a torque.
		jet.rotation_degrees = Vector3(-32.0 * cos(ang_r), 0.0, 32.0 * sin(ang_r))
		var jet_mat := StandardMaterial3D.new()
		jet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		jet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jet_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
		jet_mat.albedo_color = Color(0.55, 0.80, 1.0, 0.30)
		jet_mat.emission_enabled = true
		jet_mat.emission = Color(0.55, 0.82, 1.0)
		jet_mat.emission_energy_multiplier = 2.0
		jet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		jet.material_override = jet_mat
		jet.visible = false
		descent_plume.add_child(jet)
		rcs_jets.append(jet)
	# Ground glow.  The single most recognisable part of a powered-descent shot:
	# the jet hits the regolith, flattens, and the whole underside of the dust
	# cloud lights up blue from within.  Lives in world space, not on the lander,
	# because it has to stay pinned to the soil as the vehicle comes down.
	plume_ground_glow = MeshInstance3D.new()
	plume_ground_glow.name = "PlumeGroundGlow"
	# A flat horizontal quad carrying a RADIAL-GRADIENT alpha texture.  Neither a
	# hard-rimmed cylinder disc nor a uniform-alpha sphere works here: the disc
	# shows a crisp circular edge and the sphere shows a bright bubble ring (its
	# silhouette has the longest path through the volume).  A radial gradient that
	# fades opaque-at-centre to transparent-at-edge is the only cheap way to get a
	# genuinely soft glow without a custom shader.
	var glow_mesh := PlaneMesh.new()
	glow_mesh.size = Vector2(2.0, 2.0)
	plume_ground_glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode   = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_texture = _radial_glow_texture()
	glow_mat.albedo_color = Color(0.30, 0.60, 1.0, 0.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.32, 0.62, 1.0)
	glow_mat.emission_texture = _radial_glow_texture()
	glow_mat.emission_energy_multiplier = 1.6
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume_ground_glow.material_override = glow_mat
	plume_ground_glow.visible = false
	add_child(plume_ground_glow)

	# ISRO tricolour on the lander flank — the flag the country saw planted at
	# the south pole, so the vehicle should carry it in the close shots.
	var band_colors := [Color(0.98, 0.53, 0.12), Color(0.96, 0.96, 0.96), Color(0.06, 0.55, 0.22)]
	for bi in band_colors.size():
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.30, 0.05, 0.03)
		band.mesh = bm
		band.position = Vector3(0.0, 0.86 - bi * 0.06, 0.63)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = band_colors[bi]
		bmat.emission_enabled = true
		bmat.emission = band_colors[bi]
		bmat.emission_energy_multiplier = 0.25
		band.material_override = bmat
		lander.add_child(band)
	_build_pragyan(gold, dark, silver)

func _build_pragyan(gold: Material, dark: Material, silver: Material) -> void:
	rover = Node3D.new()
	rover.name = "PragyanRover"
	rover.visible = false
	add_child(rover)

	# REAL Pragyan geometry at 1 unit = 1 m: 0.80 long × 0.50 wide × 0.58 tall,
	# six 0.26 m wheels on three axles.  Pragyan drives toward world +Z while
	# carrying a PI yaw, so its local −Z is the nose and the LONG axis must be
	# local Z.  The previous build was 0.88 wide × 0.60 long with three wheels
	# spread across the WIDTH — that is what made the rover look like a box
	# sliding down the ramp sideways instead of rolling nose-first.
	# Chassis deck and the lower equipment bay.
	_make_box(Vector3(0.50, 0.20, 0.80), Vector3(0, 0.02, 0.0), gold, rover)
	_make_box(Vector3(0.44, 0.10, 0.70), Vector3(0, -0.13, 0.0), gold, rover)
	# Quilted MLI stitch lines along the flanks and the ends.
	for fy in [-0.06, 0.06]:
		for sx in [-1.0, 1.0]:
			_make_box(Vector3(0.010, 0.010, 0.78), Vector3(sx * 0.253, fy, 0), silver, rover)
		for sz in [-1.0, 1.0]:
			_make_box(Vector3(0.46, 0.010, 0.010), Vector3(0, fy, sz * 0.403), silver, rover)
	# Deck frame corner posts — the visible structure under the foil wrap.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_make_box(Vector3(0.035, 0.21, 0.035),
				Vector3(sx * 0.245, 0.02, sz * 0.390), silver, rover)
	# Front and rear bumper rails.
	for sz in [-1.0, 1.0]:
		_make_box(Vector3(0.48, 0.028, 0.020), Vector3(0, -0.075, sz * 0.408), silver, rover)
	# Rocker shaft plus the three axle cross-beams it pivots on.
	_make_box(Vector3(0.54, 0.036, 0.036), Vector3(0, -0.19, 0.0), silver, rover)
	for az in [-0.30, 0.0, 0.30]:
		_make_box(Vector3(0.54, 0.028, 0.028), Vector3(0, -0.19, az), silver, rover)
	# Top solar array — Pragyan's most recognisable feature, a flat blue deck
	# nearly covering the whole top face.
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.04, 0.10, 0.44, 1.0)
	panel_mat.metallic  = 0.12
	panel_mat.roughness = 0.52
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.02, 0.05, 0.28, 1.0)
	panel_mat.emission_energy_multiplier = 0.15
	_make_box(Vector3(0.46, 0.020, 0.74), Vector3(0, 0.13, 0.0), panel_mat, rover)
	# Cell busbars — 5 columns × 7 rows, so the array reads as separate cells
	# instead of one flat blue slab.
	for gx in range(-2, 3):
		_make_box(Vector3(0.005, 0.022, 0.72), Vector3(gx * 0.10, 0.13, 0.0), silver, rover)
	for gz in range(-3, 4):
		_make_box(Vector3(0.44, 0.022, 0.005), Vector3(0, 0.13, gz * 0.10), silver, rover)
	# Array frame lip.
	for gx in [-1.0, 1.0]:
		_make_box(Vector3(0.014, 0.026, 0.76), Vector3(gx * 0.234, 0.13, 0.0), silver, rover)
	for gz in [-1.0, 1.0]:
		_make_box(Vector3(0.48, 0.026, 0.014), Vector3(0, 0.13, gz * 0.380), silver, rover)

	# 6 wheels on 3 axles — axles run ACROSS the width (constant z), so the
	# three wheel lines are spaced along the rover's LENGTH.
	var wheel_mesh_proto := CylinderMesh.new()
	wheel_mesh_proto.top_radius    = 0.13
	wheel_mesh_proto.bottom_radius = 0.13
	wheel_mesh_proto.height        = 0.085
	wheel_mesh_proto.radial_segments = 24
	# Pragyan's wheels are open titanium mesh, not solid drums.  A mid grey with
	# real metallic sheen reads far closer than the previous near-black puck.
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.34, 0.35, 0.37, 1.0)
	wheel_mat.metallic  = 0.62
	wheel_mat.roughness = 0.55
	for az in [-0.30, 0.0, 0.30]:
		for sx in [-1.0, 1.0]:
			var wx: float = sx * 0.28
			# Rocker arm out to the hub and the drop link down from the deck.
			_make_box(Vector3(0.20, 0.030, 0.030), Vector3(sx * 0.19, -0.19, az), silver, rover)
			_make_box(Vector3(0.030, 0.13, 0.030), Vector3(wx, -0.12, az), silver, rover)
			# Spin pivot: an UNROTATED Node3D at the hub, so a rotation about its
			# local X is exactly wheel spin (the axle lies along X).  Everything
			# that must turn with the road wheel — drum, hub, spokes, grousers — is
			# parented to it.  A rover that rolls along on frozen wheels is the
			# single most obvious "not real" tell in a drive shot.
			var spin := Node3D.new()
			spin.name = "WheelSpin"
			spin.position = Vector3(wx, -0.13, az)
			rover.add_child(spin)
			wheel_spins.append(spin)
			var wheel := MeshInstance3D.new()
			wheel.mesh              = wheel_mesh_proto
			wheel.rotation_degrees.z = 90.0
			wheel.material_override = wheel_mat
			spin.add_child(wheel)
			# Hub and the two spoke webs of the mesh wheel.
			var hub := MeshInstance3D.new()
			var hm  := CylinderMesh.new()
			hm.top_radius    = 0.045
			hm.bottom_radius = 0.045
			hm.height        = 0.095
			hm.radial_segments = 14
			hub.mesh              = hm
			hub.rotation_degrees.z = 90.0
			hub.material_override = silver
			spin.add_child(hub)
			for sw in range(3):
				var sa := float(sw) * PI / 3.0
				for wxo in [-0.028, 0.028]:
					var spoke := _make_box(Vector3(0.016, 0.215, 0.016),
						Vector3(wxo, 0.0, 0.0), silver, spin)
					spoke.rotation_degrees.x = rad_to_deg(sa)
			# Grousers — 8 teeth around the rim.  Twelve made the wheel read as a
			# cog and, worse, the teeth were so fine that the spin was invisible;
			# fewer, chunkier teeth give the eye something to track.
			for gi in 8:
				var ga := float(gi) * TAU / 8.0
				var grouser := _make_box(Vector3(0.085, 0.024, 0.034),
					Vector3(0.0, sin(ga) * 0.140, cos(ga) * 0.140),
					silver, spin)
				grouser.rotation_degrees.x = 90.0 - rad_to_deg(ga)

	# --- Science payload, all on the NOSE (local −Z, the direction of travel) --
	# IIT-T LIBS and IISER-R APXS on two short masts at the front corners: the
	# pair of "eyes" every Pragyan photograph shows looking down at the soil.
	for ix in [-1.0, 1.0]:
		var mx: float = ix * 0.17
		_make_box(Vector3(0.036, 0.26, 0.036), Vector3(mx, 0.24, -0.33), silver, rover)
		_make_box(Vector3(0.10, 0.095, 0.075), Vector3(mx, 0.41, -0.33), dark, rover)
		# Sensor aperture, tilted down toward the sample.
		var head := MeshInstance3D.new()
		var head_mesh := CylinderMesh.new()
		head_mesh.top_radius = 0.030
		head_mesh.bottom_radius = 0.042
		head_mesh.height = 0.035
		head_mesh.radial_segments = 12
		head.mesh = head_mesh
		head.position = Vector3(mx, 0.372, -0.375)
		head.rotation_degrees.x = 108.0
		head.material_override = silver
		rover.add_child(head)
	# NavCam — one mast-mounted stereo head above the instruments.
	_make_box(Vector3(0.045, 0.20, 0.045), Vector3(0.0, 0.30, -0.23), silver, rover)
	for cx in [-0.06, 0.06]:
		_make_box(Vector3(0.075, 0.062, 0.055), Vector3(cx, 0.43, -0.255), dark, rover)
		var lens := MeshInstance3D.new()
		var lens_mesh := CylinderMesh.new()
		lens_mesh.top_radius = 0.021
		lens_mesh.bottom_radius = 0.021
		lens_mesh.height = 0.014
		lens_mesh.radial_segments = 12
		lens.mesh = lens_mesh
		lens.position = Vector3(cx, 0.43, -0.290)
		lens.rotation_degrees.x = 90.0
		lens.material_override = silver
		rover.add_child(lens)
	# Aft-equipment deck: a dark electronics box behind the array.
	_make_box(Vector3(0.34, 0.09, 0.16), Vector3(0, 0.17, 0.26), dark, rover)
	# Whip antenna at the rear right — the telescoping rod for direct downlink.
	var whip := MeshInstance3D.new()
	var whip_mesh := CylinderMesh.new()
	whip_mesh.top_radius = 0.006
	whip_mesh.bottom_radius = 0.013
	whip_mesh.height = 0.52
	whip.mesh = whip_mesh
	whip.position = Vector3(0.20, 0.42, 0.34)
	whip.rotation_degrees.z = -16.0
	whip.material_override = silver
	rover.add_child(whip)
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.016
	tip_mesh.height = 0.032
	tip.mesh = tip_mesh
	tip.position = Vector3(0.27, 0.675, 0.34)
	tip.material_override = silver
	rover.add_child(tip)
	# Radiator on the rear face, with cooling fins.
	var rad_mat := StandardMaterial3D.new()
	rad_mat.albedo_color = Color(0.85, 0.86, 0.88)
	rad_mat.metallic = 0.7
	rad_mat.roughness = 0.35
	_make_box(Vector3(0.30, 0.17, 0.018), Vector3(0, 0.0, 0.410), rad_mat, rover)
	for ry in range(-2, 3):
		_make_box(Vector3(0.28, 0.008, 0.026), Vector3(0, ry * 0.033, 0.424), silver, rover)
	# ISRO emblem disc and the tricolour plate on the nose face.
	var emblem := MeshInstance3D.new()
	var em_mesh := CylinderMesh.new()
	em_mesh.top_radius    = 0.075
	em_mesh.bottom_radius = 0.075
	em_mesh.height        = 0.012
	em_mesh.radial_segments = 24
	emblem.mesh              = em_mesh
	emblem.position          = Vector3(0.13, 0.04, -0.408)
	emblem.rotation_degrees.x = 90.0
	emblem.material_override = silver
	rover.add_child(emblem)
	var rband_colors := [Color(0.98, 0.53, 0.12), Color(0.96, 0.96, 0.96), Color(0.06, 0.55, 0.22)]
	for bi in rband_colors.size():
		var rband := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.17, 0.032, 0.012)
		rband.mesh = rbm
		rband.position = Vector3(-0.11, 0.10 - bi * 0.034, -0.406)
		var rbmat := StandardMaterial3D.new()
		rbmat.albedo_color = rband_colors[bi]
		rbmat.emission_enabled = true
		rbmat.emission = rband_colors[bi]
		rbmat.emission_energy_multiplier = 0.25
		rband.material_override = rbmat
		rover.add_child(rband)

func _make_label(text: String, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 42
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.outline_size = 8
	l.modulate = color
	return l

## Vikram's solar wings fold to 1 (stowed, hugging the body so it fits inside
## the orbiter bay) and unfold to 0 (deployed, flat) for the descent.
func _set_vikram_fold(fold: float) -> void:
	for i in vikram_panel_pivots.size():
		var side: float = vikram_panel_sides[i]
		vikram_panel_pivots[i].rotation.z = deg_to_rad(side * 92.0 * clampf(fold, 0.0, 1.0))

## Bilinear wrap-sample of an n×n value-noise grid over uv in [0,1].
func _noise2(grid: PackedFloat32Array, n: int, u: float, v: float) -> float:
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

## Procedurally build a crinkled gold MLI thermal-blanket look: a quilted
## albedo (individual blanket sheets + darker seams + per-sheet tint) and a
## matching wrinkle normal map.  This is what makes the hull read as a real
## foil-wrapped spacecraft instead of a flat-painted cardboard box.
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
			heights[y * size + x] = 0.65 * _noise2(g1, n1, u, v) + 0.35 * _noise2(g2, n2, u, v)
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
			var tint := 0.82 + 0.34 * _noise2(g1, n1, (float(cx) + 0.5) / cells, (float(cy) + 0.5) / cells)
			var fu := u * cells - cx
			var fv := v * cells - cy
			var seam := minf(minf(fu, 1.0 - fu), minf(fv, 1.0 - fv))
			var seamf := clampf(seam / 0.07, 0.0, 1.0)
			var shade := lerpf(0.5, 1.0, seamf) * tint
			alb.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade))
	var albedo_tex := ImageTexture.create_from_image(alb)
	var normal_tex := ImageTexture.create_from_image(nrm)
	return [albedo_tex, normal_tex]

## The Chandrayaan-2-style orbiter the video shows carrying Vikram: a boxy bus
## with a single large blue solar wing, gold deck and a high-gain dish.
func _build_orbiter() -> void:
	orbiter = Node3D.new()
	orbiter.name = "ChandrayaanOrbiter"
	add_child(orbiter)
	var mli := _make_mli_textures()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(1, 1, 1)            # gold baked into the foil texture
	body_mat.albedo_texture = mli[0]
	body_mat.metallic = 0.55
	body_mat.roughness = 0.32
	body_mat.metallic_specular = 0.7
	body_mat.normal_enabled = true
	body_mat.normal_texture = mli[1]
	body_mat.normal_scale = 0.7
	body_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.16, 0.10, 0.02)
	body_mat.emission_energy_multiplier = 0.10
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.82, 0.84, 0.87)     # silver/white MLI equipment panels
	silver.metallic = 0.5
	silver.roughness = 0.4
	silver.normal_enabled = true
	silver.normal_texture = mli[1]
	silver.normal_scale = 0.5
	silver.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.55, 0.36, 0.05)       # darker amber blanket seams / thrusters
	gold.metallic = 0.9
	gold.roughness = 0.35
	var cell := StandardMaterial3D.new()
	cell.albedo_color = Color(0.04, 0.10, 0.45)
	cell.metallic = 0.15
	cell.roughness = 0.55
	cell.emission_enabled = true
	cell.emission = Color(0.02, 0.06, 0.30)
	cell.emission_energy_multiplier = 0.12
	# Closed carrier hull: a sealed bus that ENCLOSES Vikram during cruise —
	# the orbiter is a solid spacecraft, not an open frame, so the lander rides
	# hidden inside until separation reveals it.
	_make_box(Vector3(2.2, 2.5, 1.5), Vector3.ZERO, body_mat, orbiter)          # gold MLI bus
	_make_box(Vector3(2.26, 0.5, 1.56), Vector3(0, 0.95, 0), silver, orbiter)   # silver panel band
	_make_box(Vector3(2.26, 0.5, 1.56), Vector3(0, -0.95, 0), silver, orbiter)  # silver panel band
	_make_box(Vector3(1.5, 0.16, 1.0), Vector3(0, 1.28, 0), silver, orbiter)    # top deck
	# Quilted MLI blanket seams so the foil reads as wrapped panels, not a flat box.
	for sx in [-0.62, 0.0, 0.62]:
		_make_box(Vector3(0.035, 2.44, 0.02), Vector3(sx, 0, 0.76), gold, orbiter)
		_make_box(Vector3(0.035, 2.44, 0.02), Vector3(sx, 0, -0.76), gold, orbiter)
	for sy in [-0.35, 0.35]:
		_make_box(Vector3(2.22, 0.02, 0.035), Vector3(0, sy, 0.76), gold, orbiter)
		_make_box(Vector3(2.22, 0.02, 0.035), Vector3(0, sy, -0.76), gold, orbiter)
	# Reaction-control thruster cluster on the underside.
	for rx in [-0.5, 0.5]:
		for rz in [-0.5, 0.5]:
			_make_box(Vector3(0.14, 0.12, 0.14), Vector3(rx, -1.3, rz), gold, orbiter)
	# Separation push-off puffs.  A real lander/orbiter decoupling is a gentle
	# spring push, but a brief, faint RCS flare at the underside cluster sells the
	# moment the two vehicles part instead of them silently drifting apart.
	for rx in [-0.5, 0.5]:
		for rz in [-0.5, 0.5]:
			var sp := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.05
			sm.bottom_radius = 0.11
			sm.height = 0.28
			sm.radial_segments = 12
			sm.rings = 2
			sm.cap_top = false
			sm.cap_bottom = false
			sp.mesh = sm
			# Bell points straight down toward where Vikram was, so it reads as the
			# orbiter firing away from the lander.
			sp.position = Vector3(rx, -1.62, rz)
			var smp := StandardMaterial3D.new()
			smp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smp.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			smp.albedo_color = Color(0.55, 0.80, 1.0, 0.0)
			smp.emission_enabled = true
			smp.emission = Color(0.60, 0.85, 1.0)
			smp.emission_energy_multiplier = 2.0
			smp.cull_mode = BaseMaterial3D.CULL_DISABLED
			sp.material_override = smp
			sp.visible = false
			orbiter.add_child(sp)
			sep_rcs_jets.append(sp)
	# The orbiter's own solar wings (Vikram's are stowed inside, so the bus
	# powers the stack through cruise).
	for side in [-1.0, 1.0]:
		_make_box(Vector3(0.16, 0.05, 0.2), Vector3(side * 1.25, 0.0, 0.0), body_mat, orbiter)
		_make_box(Vector3(1.7, 0.03, 0.95), Vector3(side * 2.15, 0.0, 0.0), cell, orbiter)
	# High-gain comm dish on a short mast above the bay.
	var mast := _make_box(Vector3(0.05, 0.4, 0.05), Vector3(-0.5, 1.5, 0.0), body_mat, orbiter)
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.02
	dm.bottom_radius = 0.30
	dm.height = 0.18
	dish.mesh = dm
	dish.position = Vector3(-0.5, 1.72, 0.0)
	dish.material_override = body_mat
	orbiter.add_child(dish)

## Physical SENSOR and CAMERA hardware on Vikram plus the glowing in-world
## callout labels, matching the annotated close-up in the video.
func _build_callouts() -> void:
	if vikram_lander:
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.04, 0.06, 0.12)
		dark.metallic = 0.5
		dark.roughness = 0.45
		var silver := StandardMaterial3D.new()
		silver.albedo_color = Color(0.72, 0.72, 0.76)
		silver.metallic = 0.9
		silver.roughness = 0.22
		# Sensor head on a mast (topographic / hyper-spectral package).
		_make_box(Vector3(0.03, 0.3, 0.03), Vector3(-0.3, 0.9, 0.35), silver, vikram_lander)
		var sensor := _make_box(Vector3(0.18, 0.16, 0.16), Vector3(-0.3, 1.08, 0.35), dark, vikram_lander)
		sensor.name = "SensorHead"
		# Twin navigation camera on the flank.
		var cam := _make_box(Vector3(0.2, 0.12, 0.1), Vector3(0.35, 0.95, 0.42), silver, vikram_lander)
		cam.name = "NavCamera"
		_make_box(Vector3(0.06, 0.06, 0.05), Vector3(0.35, 0.95, 0.5), dark, vikram_lander)
	lbl_vikram = _make_label("Vikram Lander", Color(0.45, 1.0, 0.7))
	lbl_vikram.position = Vector3(0, 1.95, 0)
	if vikram_lander: vikram_lander.add_child(lbl_vikram)
	lbl_orbiter = _make_label("Orbiter", Color(0.85, 0.95, 1.0))
	lbl_orbiter.position = Vector3(0, 1.15, 0)
	if orbiter: orbiter.add_child(lbl_orbiter)
	lbl_sensor = _make_label("SENSOR", Color(0.4, 0.9, 1.0))
	lbl_sensor.position = Vector3(-1.05, 1.15, 0.35)
	if vikram_lander: vikram_lander.add_child(lbl_sensor)
	lbl_camera = _make_label("CAMERA", Color(0.4, 0.9, 1.0))
	lbl_camera.position = Vector3(1.15, 1.0, 0.42)
	if vikram_lander: vikram_lander.add_child(lbl_camera)
	for l in [lbl_vikram, lbl_orbiter, lbl_sensor, lbl_camera]:
		if l: l.visible = false

## Green rings marking the permanently-shadowed, ice-bearing craters — the
## survey payoff shot at the end of the video.  Hidden until the ice scan
## reveals them one by one after touchdown.
func _build_psr_markers() -> void:
	psr_root = Node3D.new()
	psr_root.name = "IceCraterHighlights"
	add_child(psr_root)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.2, 1.0, 0.45, 0.9)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for spec in [[-12.0, -6.0, 4.5], [9.0, -11.0, 6.0], [-15.0, 8.0, 5.5], [2.0, -14.0, 5.0], [-6.5, 11.5, 3.4]]:
		var cx: float = spec[0]
		var cz: float = spec[1]
		var r: float = spec[2]
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * 0.9
		tm.outer_radius = r
		tm.rings = 64
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = ring_mat
		ring.position = Vector3(cx, _moon_height(cx, cz) + 0.18, cz)
		ring.visible = false
		psr_root.add_child(ring)
		psr_rings.append(ring)
	lbl_ice = _make_label("WATER ICE (H2O)", Color(0.35, 1.0, 0.55))
	lbl_ice.position = Vector3(-12.0, _moon_height(-12.0, -6.0) + 3.4, -6.0)
	lbl_ice.visible = false
	add_child(lbl_ice)

## Vikram's onboard hazard-detection pass.  Before committing to the surface the
## lander sweeps its descent camera across the terrain, flags candidate landing
## sites, rejects the hazardous ones (a boulder cluster and a crater-rim slope)
## and locks the safest flat patch — the real Chandrayaan-3 coarse
## hazard-detection-and-avoidance beat that the scene was missing.  Markers live
## in world space on the regolith near the landing zone.
func _build_site_survey() -> void:
	survey_root = Node3D.new()
	survey_root.name = "SiteSurvey"
	add_child(survey_root)
	survey_root.visible = false
	# Descent-camera sensor funnel: a translucent cyan cone from Vikram down to
	# the ground track, rescaled every frame so it always reaches the soil as the
	# altitude drops.  Narrow end (top_radius) sits at the lander, wide end at the
	# surface — exactly how the onboard camera's field of view paints the ground.
	survey_cone = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 28
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	survey_cone.mesh = cone
	# A very faint, near-invisible funnel.  A bright solid cyan cone reads as a
	# sci-fi tractor beam; a real descent-camera field of view is barely there,
	# just a ghost outline, so the alpha is kept low and the emission is minimal.
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.albedo_color = Color(0.45, 0.80, 1.0, 0.05)
	cm.emission_enabled = true
	cm.emission = Color(0.30, 0.62, 0.95)
	cm.emission_energy_multiplier = 0.12
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	survey_cone.material_override = cm
	survey_cone.visible = false
	add_child(survey_cone)
	# Ground footprint: a soft radial glow lying flat on the soil where the cone
	# lands.  A hard-rimmed torus looked like a game marker; a radial gradient
	# that fades to nothing at the edge reads as a diffuse illuminated patch.
	survey_ring = MeshInstance3D.new()
	var fplane := PlaneMesh.new()
	fplane.size = Vector2(2.0, 2.0)
	survey_ring.mesh = fplane
	var frm := StandardMaterial3D.new()
	frm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	frm.albedo_texture = _radial_glow_texture()
	frm.albedo_color = Color(0.35, 0.72, 1.0, 0.28)
	frm.cull_mode = BaseMaterial3D.CULL_DISABLED
	survey_ring.material_override = frm
	survey_ring.visible = false
	add_child(survey_ring)
	# Candidate sites spread across the whole search area: [x, z, is_safe,
	# reveal_progress].  The safe one sits on the actual landing target (origin);
	# the hazards are scattered along the traverse so Vikram evaluates many spots
	# over a real distance before committing.
	var specs := [
		[-8.5, 2.4, false, 0.08],
		[-3.6, -3.4, false, 0.30],
		[4.6, -2.6, false, 0.52],
		[8.6, 1.8, false, 0.70],
		[0.0, 0.3, true, 0.90],
	]
	for s in specs:
		var gx: float = s[0]
		var gz: float = s[1]
		var safe: bool = s[2]
		var node := Node3D.new()
		node.position = Vector3(gx, _moon_height(gx, gz) + 0.10, gz)
		survey_root.add_child(node)
		var col := Color(0.35, 1.0, 0.5) if safe else Color(1.0, 0.42, 0.28)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.albedo_color = Color(col.r, col.g, col.b, 0.0)
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Corner brackets — the way a real hazard-detection overlay frames a
		# candidate zone (four L-shaped ticks), not a solid neon ring + crosshair.
		var h := 0.62
		var arm := 0.26
		var th := 0.035
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_make_box(Vector3(arm, 0.02, th), Vector3(sx * (h - arm * 0.5), 0, sz * h), rm, node)
				_make_box(Vector3(th, 0.02, arm), Vector3(sx * h, 0, sz * (h - arm * 0.5)), rm, node)
		var lbl := _make_label("SAFE" if safe else "HAZARD", col)
		lbl.font_size = 34
		lbl.position = Vector3(0, 0.55, 0)
		node.add_child(lbl)
		node.visible = false
		site_nodes.append(node)
		site_mats.append(rm)
		site_labels.append(lbl)
		site_safe.append(safe)
		site_reveal.append(s[3])
	# Status readout that floats with Vikram.
	survey_status = _make_label("SCANNING LANDING ZONE", Color(0.5, 0.9, 1.0))
	survey_status.visible = false
	add_child(survey_status)

## Drives the hazard-detection beat across the descent.  `sv` is survey progress
## 0..1 over the window; candidate sites pop in by threshold, hazards fade once
## the safe site locks, and the sensor cone narrows as the site resolves.
func _update_site_survey(mt: float) -> void:
	if not survey_root:
		return
	var active := mt >= 8.5 and mt < 16.0
	survey_root.visible = active
	survey_cone.visible = active
	survey_ring.visible = active
	survey_status.visible = active
	if not active:
		return
	var sv := clampf((mt - 8.5) / 7.5, 0.0, 1.0)
	# Sensor funnel from Vikram down to the ground track, reaching the soil.
	var gy := _moon_height(scout.position.x, scout.position.z)
	var span := maxf(scout.position.y - 0.2 - gy, 0.2)
	var rad := lerpf(2.4, 0.7, sv)
	survey_cone.position = Vector3(scout.position.x, gy + span * 0.5, scout.position.z)
	survey_cone.scale = Vector3(rad, span, rad)
	survey_ring.position = Vector3(scout.position.x, gy + 0.05, scout.position.z)
	var pulse := 1.0 + sin(mt * 6.0) * 0.06
	survey_ring.scale = Vector3(rad * pulse, 1.0, rad * pulse)
	# Reveal candidate sites in order; hazards get rejected, the safe one locks.
	var locked := false
	for i in site_nodes.size():
		site_nodes[i].visible = sv >= site_reveal[i]
		var rmat := site_mats[i]
		var ac := rmat.albedo_color
		if site_safe[i]:
			if sv >= site_reveal[i]:
				locked = true
				var p2 := 1.0 + sin(mt * 9.0) * 0.10
				site_nodes[i].scale = Vector3(p2, 1.0, p2)
				ac.a = 0.85
			else:
				ac.a = 0.0
		else:
			ac.a = lerpf(0.8, 0.10, clampf((sv - 0.90) / 0.10, 0.0, 1.0))
		rmat.albedo_color = ac
	if locked:
		survey_status.text = "SAFE SITE LOCKED - COMMITTING TO DESCENT"
	elif sv > 0.52:
		survey_status.text = "HAZARDS DETECTED - AVOIDING"
	else:
		survey_status.text = "SCANNING LANDING ZONE"
	survey_status.position = Vector3(scout.position.x, scout.position.y + 2.9, scout.position.z)

func _process(delta: float) -> void:
	if finishing:
		return
	mission_time += delta
	# The touchdown dust sheet lingers and settles even after the engine cuts,
	# so it decays on its own every frame rather than only in one branch.
	touchdown_dust = maxf(0.0, touchdown_dust - delta * 0.55)
	# The orbit phase circles the spherical globe; the descent/landing phase uses
	# the flat terrain.  Only one of the two Moons is ever visible.
	if moon_globe:
		moon_globe.visible = mission_time < 6.0
		# slow spin so the cratered surface reads as a real rotating body
		moon_globe.rotation.y += delta * 0.05
	if moon:
		moon.get_parent().visible = mission_time >= 6.0
	var plume_on := false
	var plume_thr := 0.0
	var plume_impinge := 0.0
	var dust_i := 0.0
	if mission_time < 6.0:
		# The stack sweeps across the CAMERA-FACING side of the Moon and finishes
		# directly over the landing site, so separation and descent are one
		# continuous motion.  The old path orbited the whole globe, which left the
		# stack on the far/underside at t=6 and then TELEPORTED it to the descent
		# start — the jarring cut the user saw.  Ending on the staging point means
		# Vikram is already exactly where the descent begins when the engine lights.
		var f := mission_time / 6.0
		var th := lerpf(1.55, 0.0, ease(f, 0.85))
		var arc := _globe_center + 14.0 * (cos(th) * Vector3(0.0, 1.0, 0.0) + sin(th) * Vector3(0.28, 0.0, 0.96))
		var stage := Vector3(1.5, 7.0, 2.5)
		scout.position = arc.lerp(stage, smoothstep(0.72, 1.0, f))
		scout.rotation = Vector3(0.0, lerpf(-1.3, 0.0, ease(f, 0.85)), 0.0)
		if mission_time < 4.0:
			phase_label.text = "LUNAR POLAR ORBIT — LANDING SITE IMAGING"
			orbit_label.text = "100 km polar orbit  |  South-pole hazard-map verification"
		else:
			phase_label.text = "ORBITER–VIKRAM SEPARATION — LANDER SET FOR DESCENT"
			orbit_label.text = "Orbiter holds polar orbit  |  Vikram lander separated, descent burn armed"
	elif mission_time < 18.0:
		# Three-beat terminal descent, matching the real hazard-detection pass:
		# brake down to a low hover, then FLY A LONG SEARCH TRAVERSE across the
		# south pole — covering real distance over many seconds while the descent
		# camera evaluates candidate sites — before returning and settling onto the
		# one safe patch above the landing target.
		var clr := 3.2
		var pts := [
			Vector2(-10.0, 3.0), Vector2(-4.0, -4.0), Vector2(4.0, -3.0),
			Vector2(9.0, 2.0), Vector2(0.0, 0.3),
		]
		var hs := Vector3(pts[0].x, _moon_height(pts[0].x, pts[0].y) + clr, pts[0].y)
		var sh := Vector3(pts[pts.size() - 1].x, _moon_height(pts[pts.size() - 1].x, pts[pts.size() - 1].y) + clr, pts[pts.size() - 1].y)
		var ground := _moon_height(scout.position.x, scout.position.z)
		var vv := 0.0
		if mission_time < 8.5:
			# A — braking burn from the staging point down to the search entry point.
			var a := (mission_time - 6.0) / 2.5
			scout.position = Vector3(1.5, 7.0, 2.5).lerp(hs, ease(a, 0.7))
			scout.rotation = Vector3.ZERO
			plume_thr = 1.0
			plume_impinge = 0.0
			vv = lerpf(22.0, 1.5, a)
			phase_label.text = "VIKRAM POWERED DESCENT — BRAKING BURN"
		elif mission_time < 16.0:
			# B — the long low-altitude search: Vikram flies a wide multi-waypoint
			# traverse across the terrain, holding clearance above the ground it
			# passes, banking into each turn.  This is the "cover real distance and
			# take time to find a site" beat the short in-place hover was missing.
			var b := (mission_time - 8.5) / 7.5
			var segf := b * float(pts.size() - 1)
			var si := int(minf(segf, float(pts.size() - 2)))
			var lt := smoothstep(0.0, 1.0, segf - float(si))
			var pxz: Vector2 = pts[si].lerp(pts[si + 1], lt)
			scout.position = Vector3(pxz.x, _moon_height(pxz.x, pxz.y) + clr + sin(mission_time * 1.6) * 0.12, pxz.y)
			scout.rotation = Vector3(0.0, 0.0, sin(b * PI * 2.0) * 0.12)
			plume_thr = 0.55
			plume_impinge = 0.35
			vv = 0.3
			phase_label.text = "HAZARD DETECTION — SEARCHING THE SOUTH POLE FOR A SAFE SITE"
		else:
			# C — commit: settle from the safe-site hover straight down to touchdown.
			var c := (mission_time - 16.0) / 2.0
			scout.position = sh.lerp(Vector3.ZERO, smoothstep(0.0, 1.0, c))
			scout.rotation = Vector3.ZERO
			plume_thr = lerpf(0.55, 0.35, c)
			plume_impinge = lerpf(0.35, 1.0, clampf((c - 0.4) / 0.6, 0.0, 1.0))
			vv = lerpf(2.0, 0.3, c)
			phase_label.text = "THROTTLE DOWN — FINAL APPROACH TO THE SURFACE"
		plume_on = true
		dust_i = plume_impinge * 0.85
		var alt_m := int(maxf(0.0, scout.position.y - ground) * 300.0)
		orbit_label.text = "Distance to surface: %d m  |  Vertical velocity: %.1f m/s  |  Engine throttle: %d%%" % [alt_m, vv, int(plume_thr * 100)]
	else:
		if not landed:
			landed = true
			touchdown_dust = 1.0
			_announce_touchdown()
			phase_label.text = "VIKRAM TOUCHDOWN CONFIRMED — LUNAR SOUTH POLE"
		scout.position = Vector3.ZERO
		scout.rotation = Vector3.ZERO
		orbit_label.text = "Lander stable  |  Permanently shadowed crater survey active"
		dust_i = touchdown_dust
		if mission_time > 22.0:
			_deploy_pragyan(delta)
	_set_descent_plume(plume_on, plume_thr, plume_impinge)
	_update_dust(dust_i)
	# Vikram's hazard-detection pass: sweep the descent camera, flag candidate
	# sites, reject the hazards and lock the safe one — a beat before the final
	# approach commits to the surface.
	_update_site_survey(mission_time)
	# Vikram is CARRIED INSIDE the orbiter's payload bay (panels stowed) through
	# the imaging orbit, then undocks: the orbiter pulls up into its holding
	# orbit while Vikram descends and unfolds its solar wings.
	if orbiter:
		if mission_time < 6.0:
			orbiter.position = scout.position + Vector3(0.0, 0.85, 0.0)
			orbiter.rotation = scout.rotation
			_set_vikram_fold(1.0)
		else:
			# Slow, gentle departure: the orbiter drifts up and away over ~6 s
			# instead of snapping off in 2.5 s, so the separation reads as a real
			# push-off and coast rather than a rushed cut.
			var sep := clampf((mission_time - 6.0) / 6.0, 0.0, 1.0)
			var oa := mission_time * 0.5
			var orbit_pos := Vector3(sin(oa) * 9.5, 8.0 + cos(oa) * 1.5, cos(oa) * 9.5)
			# Freeze the departure origin at the staging dock point.  Using the live
			# scout.position would make the orbiter dive down after the descending
			# lander instead of pulling cleanly away.
			var dock_pos := Vector3(1.5, 7.85, 2.5)
			# Peel UP and to screen-left first, then swing out onto the holding orbit.
			# Firing straight back along -Z hid the orbiter directly behind Vikram from
			# this camera, so the two merged into one blob instead of reading as a clean
			# separation; a vertical split (Vikram down, orbiter up) always reads.
			var up := dock_pos + Vector3(-3.4, 7.5, 1.5)
			orbiter.position = dock_pos.lerp(up, smoothstep(0.0, 0.55, sep)).lerp(orbit_pos, smoothstep(0.5, 1.0, sep))
			# Blend the orbiter's yaw up from the docked heading (0) instead of
			# snapping straight to the orbit spin, or it visibly pops at t=6.
			orbiter.rotation = Vector3(0.0, lerpf(0.0, -oa, ease(sep, 0.6)), 0.0)
			_set_vikram_fold(1.0 - sep)
			# Push-off flare.  A short soft impulse near the start, then the orbiter
			# coasts away on its own — a real separation is a brief burst, not a
			# sustained burn, so the jets fade out well before the slow climb ends.
			var bt := mission_time - 6.0
			var burst := clampf((bt - 0.3) / 0.5, 0.0, 1.0) * clampf(1.0 - (bt - 0.3) / 2.2, 0.0, 1.0)
			for sp in sep_rcs_jets:
				sp.visible = burst > 0.02
				sp.scale = Vector3(0.7 + burst * 0.5, maxf(burst, 0.02), 0.7 + burst * 0.5)
				var smat := sp.material_override as StandardMaterial3D
				var ac := smat.albedo_color
				ac.a = burst * 0.5
				smat.albedo_color = ac
				smat.emission_energy_multiplier = 0.6 + burst * 2.4
	if lbl_vikram: lbl_vikram.visible = mission_time >= 3.0 and mission_time < 9.5
	if lbl_orbiter: lbl_orbiter.visible = mission_time >= 3.0 and mission_time < 9.5
	if lbl_sensor: lbl_sensor.visible = mission_time >= 8.0 and mission_time < 9.0
	if lbl_camera: lbl_camera.visible = mission_time >= 8.0 and mission_time < 9.0
	# Reveal the ice-bearing shadowed craters one by one as the survey builds.
	for i in psr_rings.size():
		psr_rings[i].visible = landed and scan_progress >= float(i + 1) * 13.0
	if lbl_ice: lbl_ice.visible = landed and scan_progress >= 26.0
	if landed:
		scan_progress = minf(100.0, scan_progress + delta * 2.1)
		# Pragyan's egress is watched from a low SIDE view.  The default
		# three-quarter shot looks straight down the ramp axis, which collapses
		# the door, the ramp and the rover into one foreshortened vertical strip
		# — the door then reads as opening on the far side while the rover
		# arrives from the near one.  A profile view separates them.
		var egress := rover_deployed and not rover_egress_done
		if egress:
			camera.position = camera.position.lerp(Vector3(4.6, 1.30, 1.20), minf(delta * 2.4, 1.0))
			camera.look_at(Vector3(0, 0.45, 1.20), Vector3.UP)
		else:
			# Pan with Pragyan once it starts its traverse.  The fixed framing left
			# the rover driving straight out of shot while the caption still said
			# "TRAVERSE", so the drive was invisible for most of the surface phase.
			var follow := 0.0
			if rover_egress_done and rover:
				follow = clampf(rover.position.z * 0.42, 0.0, 1.9)
			camera.position = camera.position.lerp(
				Vector3(4.4, 2.5, 5.8 + follow * 0.55), minf(delta * .65, 1.0))
			camera.look_at(Vector3(0, .45, follow), Vector3.UP)
	else:
		if mission_time < 6.0:
			# Start on the wide globe framing so the stack reads as orbiting, then
			# push in onto Vikram across the last stretch of the approach.  Because
			# the camera is already at the close descent framing by t=6, there is no
			# cut when the descent branch takes over — the separation flows straight
			# into the powered descent.
			var f := mission_time / 6.0
			var k := smoothstep(0.70, 1.0, f)
			var wide_pos := Vector3(2.0, 4.0, 40.0)
			var close_pos := scout.position + Vector3(5.5, 3.1, 7.0)
			var tgt := (_globe_center + Vector3(0.0, 3.0, 0.0)).lerp(scout.position, k)
			camera.position = camera.position.lerp(wide_pos.lerp(close_pos, k), minf(delta * 0.9, 1.0))
			camera.look_at(tgt, Vector3.UP)
		else:
			camera.position = camera.position.lerp(scout.position + Vector3(5.5, 3.1, 7.0), minf(delta * .5, 1.0))
			camera.look_at(scout.position, Vector3.UP)
	if ice_bar: ice_bar.value = scan_progress
	if day_label: day_label.text = "Lunar Day %d / 180  |  " % (1 if landed else 0) + ("Surface operations" if landed else "Arrival & descent")
	if scan_label:
		var activity := "Landing system preparing descent"
		if landed: activity = "Pragyan rover sampling regolith" if rover_deployed else "Vikram systems checkout — ramp deployment"
		scan_label.text = "Water-ice survey: %.0f%%  |  %s" % [scan_progress, activity]
	_update_end_mission_button()
	# The survey has fully played out.  Stop short of an automatic cut: the
	# player presses END MISSION so the closing shot and the report are their
	# decision, not a scene swap out from under them.
	if landed and scan_progress >= 100.0 and not surface_complete_announced:
		surface_complete_announced = true
		phase_label.text = "SURFACE OPERATIONS COMPLETE — WATER-ICE SURVEY 100%"
		orbit_label.text = "Pragyan traverse archived  |  End Mission to file the report"

## The descent engine flame.  Throttle drives the length far more than the
## width, and the plume stays anchored at the engine exit as it grows or shrinks.
## In the last stretch the jet IMPINGES: it is choked back so it shortens and
## fans sideways instead of reaching down, because it can no longer expand into
## open vacuum — and that is exactly what lifts the radial dust sheet.
func _set_descent_plume(on: bool, throttle: float, impinge: float) -> void:
	if not descent_plume: return
	descent_plume.visible = on
	if not on:
		if plume_ground_glow: plume_ground_glow.visible = false
		for j in rcs_jets:
			j.visible = false
		return
	# Each part is scaled on its own instead of stretching the whole node, so the
	# white-hot throat and the Mach disks stay round no matter how long the jet is.
	# Combustion is never perfectly steady — a flame that does not move reads as a
	# decal stuck under the vehicle.
	var flick := 1.0 + sin(mission_time * 46.0) * 0.045 + sin(mission_time * 29.0) * 0.03
	var flame_len := (0.35 + throttle * 0.85) * (1.0 - impinge * 0.34) * flick
	var wid := (0.62 + throttle * 0.42) * (1.0 + impinge * 0.75)
	# Throat: pinned at the nozzle exit, only breathes a little.
	plume_throat.scale = Vector3(1.0, 0.7, 1.0) * (0.9 + throttle * 0.25) * flick
	# Drive the flame column from the engine.  Throttle sets how fast and how long
	# the exhaust streams (a longer, tighter column at full burn, since length is
	# velocity x lifetime), impingement fans it out as it can no longer expand into
	# open vacuum, and the per-frame flicker keeps the emission churning.
	if plume_flames:
		var pf := plume_flames.process_material as ParticleProcessMaterial
		pf.initial_velocity_min = 2.2 + throttle * 2.6
		pf.initial_velocity_max = 3.2 + throttle * 3.8
		pf.spread = lerpf(15.0, 6.0, throttle) + impinge * 12.0
		plume_flames.amount = int(80.0 + throttle * 170.0)
		plume_flames.lifetime = (0.32 + throttle * 0.28) * flick
	for di in plume_diamonds.size():
		var d := plume_diamonds[di]
		# Mach disks only stand up in a well-expanded supersonic jet.
		d.visible = throttle > 0.55
		# March them down the current flame length and let them fan out as the jet
		# over-expands, so the diamond chain tracks the flame instead of floating
		# at fixed heights when the throttle changes.
		d.position.y = (-0.10 - di * 0.17) * flame_len
		d.scale = Vector3(wid * (1.0 + impinge * 0.55), 1.0, wid * (1.0 + impinge * 0.55))
	# Attitude thrusters pulse on alternating pairs so the vehicle looks like it is
	# actively trimming its descent rather than just falling on one big flame.
	var rcs_on := throttle > 0.4
	for ri in rcs_jets.size():
		var j := rcs_jets[ri]
		var phase := sin(mission_time * 7.0 + ri * PI / 2.0)
		j.visible = rcs_on and phase > 0.55
		if j.visible:
			var s := 0.5 + (phase - 0.55) * 1.4
			j.scale = Vector3(s, s, s)
	# Ground glow: the jet hits the regolith, flattens, and the underside of the
	# dust cloud lights up blue from within.  Pinned to the soil under the lander.
	if plume_ground_glow:
		if impinge > 0.04:
			var gp := vikram_lander.global_position
			plume_ground_glow.visible = true
			plume_ground_glow.position = Vector3(gp.x, _moon_height(gp.x, gp.z) + 0.05, gp.z)
			var gs := 0.6 + impinge * 2.6
			# Flat quad, so only the horizontal spread matters; the gradient texture
			# already fades it softly to nothing at the rim.
			plume_ground_glow.scale = Vector3(gs, 1.0, gs)
			var gmat := plume_ground_glow.material_override as StandardMaterial3D
			gmat.albedo_color = Color(0.30, 0.60, 1.0, 0.55 * impinge)
		else:
			plume_ground_glow.visible = false

## The dust the exhaust lifts off the regolith.  A flat radial sheet with a
## gradient-faded edge, hugging the ground.  In vacuum there is no air to billow
## the ejecta into a cloud — it flies out ballistically and skims the surface, so
## a low spreading disc is the physically right shape; the gradient just kills the
## hard circular rim a plain cylinder mesh would show.
func _update_dust(intensity: float) -> void:
	if not dust: return
	if intensity <= 0.01:
		dust.visible = false
		return
	dust.visible = true
	var dm := dust.material_override as StandardMaterial3D
	var spread := 0.6 + intensity * 3.6
	dust.scale = Vector3(spread, 1.0, spread)
	if dm: dm.albedo_color.a = clampf(intensity * 0.6, 0.0, 0.7)

func _build_dust() -> void:
	dust = MeshInstance3D.new()
	dust.name = "TouchdownDust"
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(2.0, 2.0)
	dust.mesh = sheet
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_texture = _radial_glow_texture()
	dm.albedo_color = Color(0.63, 0.61, 0.57, 0.0)
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dust.material_override = dm
	dust.position = Vector3(0, 0.06, 0)
	dust.visible = false
	add_child(dust)

## Builds a soft radial falloff texture (opaque white centre fading to fully
## transparent at the edge) used to give the ground glow and the dust sheet a
## smooth round edge instead of the hard circle a plain mesh produces.  Shared by
## both because they need the same profile, only tinted differently.
func _radial_glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(0.5, 0.0)
	gtex.width = 256
	gtex.height = 256
	return gtex

func _build_tracks() -> void:
	track_root = Node3D.new()
	track_root.name = "RoverTracks"
	add_child(track_root)

## Pragyan leaves TWO ruts, one under each wheel line (±0.28 m), each broken
## into grouser ticks by the wheel teeth — not one wide scar.  This is the
## track-in-the-dust image the rover drive is famous for.
func _drop_track(z: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.31, 0.30, 0.28, 1.0)
	m.roughness = 1.0
	m.metallic = 0.0
	for wx in [-0.28, 0.28]:
		# Compacted rut floor.
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.095, 0.008, 0.17)
		seg.mesh = bm
		seg.material_override = m
		seg.position = Vector3(wx, _moon_height(wx, z) + 0.010, z)
		track_root.add_child(seg)
		# Three raised berms either side of the rut, thrown up by the grousers.
		for ti in 3:
			var tick := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.105, 0.012, 0.022)
			tick.mesh = tm
			tick.material_override = m
			var tz: float = z - 0.06 + float(ti) * 0.06
			tick.position = Vector3(wx, _moon_height(wx, tz) + 0.014, tz)
			track_root.add_child(tick)

func _build_callout() -> void:
	callout = Label.new()
	callout.name = "TouchdownCallout"
	callout.set_anchors_preset(Control.PRESET_CENTER)
	callout.position = Vector2(-380, -70)
	callout.size = Vector2(760, 140)
	callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	callout.add_theme_font_size_override("font_size", 34)
	callout.add_theme_color_override("font_color", Color("#FFFFFF"))
	callout.text = ""
	callout.modulate.a = 0.0
	get_node("UI").add_child(callout)

func _announce_touchdown() -> void:
	if touchdown_announced or callout == null: return
	touchdown_announced = true
	callout.text = "CHANDRAYAAN-3 HAS LANDED\nVIKRAM ON THE LUNAR SOUTH POLE"
	callout.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(callout, "modulate:a", 1.0, 0.6)
	tw.tween_interval(3.4)
	tw.tween_property(callout, "modulate:a", 0.0, 1.2)

func _deploy_pragyan(delta: float) -> void:
	# Real Chandrayaan-3 egress sequence, staged over ~8 seconds:
	#   0.0 – 1.5  : bay door unlatches and swings outward on its hinge
	#   1.5 – 3.1  : the ramp swings DOWN on its own hinge onto the door tip
	#   3.1 – 7.7  : Pragyan rolls out of the bay and down the ramp
	#   7.7+       : surface traverse (wheel tracks laid behind the rover)
	if not rover_deployed:
		rover_deployed = true
		deploy_timer = 0.0
		rover_travel = 0.0
		# Front faces +Z (direction of travel) so the rover exits nose-first.
		# The rover stays hidden inside the bay until the door is open —
		# otherwise it reads as materialising outside the lander like a ghost.
		rover.rotation = Vector3(0, PI, 0)
		rover.position = Vector3(0, 0.375 + _ROVER_CLEARANCE, 0.50)
		rover.visible = false
		# The ramp is switched on here, folded up on its hinge, so it is already
		# in shot before it moves instead of appearing out of nowhere.
		if ramp_group:
			ramp_group.visible = true
			ramp_pivot.rotation_degrees.x = -62.0
		phase_label.text = "VIKRAM BAY DOOR UNLATCHING — PRAGYAN EGRESS ARMED"
		return
	deploy_timer += delta
	if deploy_timer < 1.5:
		var p := clampf(deploy_timer / 1.5, 0.0, 1.0)
		door_pivot.rotation_degrees.x = 90.0 * ease(p, 0.4)
		phase_label.text = "VIKRAM BAY DOOR UNLATCHING — PRAGYAN EGRESS ARMED"
	elif deploy_timer < 3.1:
		door_pivot.rotation_degrees.x = 90.0
		# The ramp is a child of `ramp_pivot`, hinged at the bay sill, so this
		# swing is a real deployment motion.  It used to be a one-frame
		# visible=false -> true flip, which is why the stairs popped into the
		# scene already fully extended.
		var p := clampf((deploy_timer - 1.5) / 1.6, 0.0, 1.0)
		ramp_pivot.rotation_degrees.x = lerpf(-62.0, 0.0, ease(p, 0.6))
		phase_label.text = "RAMP SWINGING DOWN ONTO THE DOOR TIP"
	elif deploy_timer < 7.7:
		# The rover becomes visible at the sill and rolls forward; the lander
		# hull still hides its rear half, so it reads as emerging out of the
		# open bay rather than popping into existence.
		rover.visible = true
		var p := clampf((deploy_timer - 3.1) / 4.6, 0.0, 1.0)
		var prev_z := rover.position.z
		var zz := lerpf(0.50, ramp_foot_z, p)
		# Height is read straight off the deployed door/ramp surface instead of
		# a Bezier.  A quadratic Bezier cuts the corner where the flat door meets
		# the sloped ramp, and that is what buried Pragyan's wheels in the
		# stairs through the middle of the descent.
		rover.position = Vector3(0, _ramp_surface_height(zz) + _ROVER_CLEARANCE, zz)
		# Nose follows the surface: level on the door, down the solved ramp slope,
		# level again as the last wheel leaves the foot plate.
		var pitch_deg: float = lerpf(0.0, -ramp_slope_deg, clampf((zz - 0.97) / 0.30, 0.0, 1.0))
		pitch_deg = lerpf(pitch_deg, 0.0, clampf((zz - (ramp_foot_z - 0.21)) / 0.26, 0.0, 1.0))
		rover.rotation = Vector3(deg_to_rad(pitch_deg), PI, 0)
		_spin_wheels(zz - prev_z)
		# Wheel-thrown dust puff removed at user request (read as a white blob).
		phase_label.text = "PRAGYAN ROLLING OUT OF THE BAY, DOWN THE RAMP"
	else:
		if not rover_egress_done:
			rover_egress_done = true
			rover.position = Vector3(0, _moon_height(0.0, ramp_foot_z) + _ROVER_CLEARANCE, ramp_foot_z)
			rover.rotation = Vector3(0, PI, 0)
			last_track_z = rover.position.z
			phase_label.text = "PRAGYAN ROVER DEPLOYED — WATER-ICE TRAVERSE"
		var prev_z := rover.position.z
		# Keeps rolling for the whole surface phase.  Capping this short made the
		# rover sit still under a "TRAVERSE" caption, so the wheels had nothing
		# to turn with.
		rover.position.z = minf(4.35, rover.position.z + delta * .16)
		# Ride the regolith itself and pitch to its local slope, so the rover
		# follows the ground it is driving over instead of gliding over bumps at
		# a fixed altitude.
		var gy := _moon_height(0.0, rover.position.z)
		rover.position.y = gy + _ROVER_CLEARANCE
		var gslope := rad_to_deg(atan2(_moon_height(0.0, rover.position.z + 0.30) - gy, 0.30))
		rover.rotation = Vector3(deg_to_rad(clampf(gslope, -18.0, 18.0)),
			PI + sin(mission_time * 1.5) * .05, 0)
		_spin_wheels(rover.position.z - prev_z)
		# Wheel-thrown dust puff removed at user request (read as a white blob).
		# Lay a rut every fixed step the rover rolls, so the trail builds up
		# behind it instead of being painted in one go.
		while rover.position.z - last_track_z > 0.22:
			last_track_z += 0.22
			_drop_track(last_track_z)


## Fixed-point solve for the deployed ramp angle.  The panel is 1.30 m long and
## hinged at the bay sill (y=0.353, z=1.12); the regolith it has to reach is
## vertex-displaced, so the slope comes from iterating the foot position against
## _moon_height() rather than being guessed.  Also caches the resulting foot
## location, which is what the rover's ride height is measured against.
func _solve_ramp_slope() -> float:
	var slope := 15.9
	for i in 5:
		var r := deg_to_rad(slope)
		var fz: float = 1.12 + 1.30 * cos(r)
		var gy: float = _moon_height(0.0, fz)
		slope = clampf(rad_to_deg(atan2(0.353 - gy, fz - 1.12)), 8.0, 26.0)
	var rr := deg_to_rad(slope)
	ramp_foot_z = 1.12 + 1.30 * cos(rr)
	ramp_foot_y = _moon_height(0.0, ramp_foot_z)
	return slope


## Top rolling surface of the deployed door and ramp as a function of world z:
## flat across the laid-down door up to the sill at z=1.12, then down the ramp
## panel to the regolith at its foot.  Keeping this in one place is what lets
## the wheels sit ON the ramp instead of sinking into it.
func _ramp_surface_height(z: float) -> float:
	if z <= 1.12:
		return 0.375
	var f := clampf((z - 1.12) / (ramp_foot_z - 1.12), 0.0, 1.0)
	return lerpf(0.375, ramp_foot_y + 0.005, f)


## Turns every road wheel by the distance Pragyan actually travelled, divided by
## the wheel radius.  All six share the same radius, so one angle fits them all.
##
## The angle is NEGATIVE about the pivot's local X.  Rolling forward requires a
## positive spin about WORLD +X, but Pragyan carries a PI yaw, which maps the
## rover's local +X onto world -X — so the sign has to flip once on the way in.
## Left positive, the whole rover looks like it is sliding backwards on its
## wheels no matter how correct the travel distance is.
func _spin_wheels(distance: float) -> void:
	if distance <= 0.0:
		return
	rover_travel += distance
	var ang := -rover_travel / 0.13
	for w in wheel_spins:
		w.rotation.x = ang


## ---------------------------------------------------------------------------
## Mission end / report hand-off
## ---------------------------------------------------------------------------

## Builds the always-available mission control button.  Before touchdown it
## reads ABORT MISSION (flight data still files a partial report); after
## touchdown it becomes END MISSION and turns green once the ice survey is
## complete.
func _build_end_mission_controls() -> void:
	var ui: Control = get_node("UI")
	end_btn = Button.new()
	end_btn.name = "EndMissionButton"
	end_btn.text = "■  ABORT MISSION"
	end_btn.tooltip_text = "Conclude the lunar phase and file the mission report."
	end_btn.focus_mode = Control.FOCUS_NONE
	end_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	end_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	end_btn.offset_left = -286.0
	end_btn.offset_top = -76.0
	end_btn.offset_right = -28.0
	end_btn.offset_bottom = -26.0
	end_btn.add_theme_stylebox_override("normal", _hud_button_style(
		Color(0.067, 0.067, 0.067, 0.92), Color("#333333")))
	end_btn.add_theme_stylebox_override("hover", _hud_button_style(
		Color(0.125, 0.125, 0.125, 0.96), Color("#FFFFFF")))
	end_btn.add_theme_stylebox_override("pressed", _hud_button_style(
		Color(0, 0, 0, 0.96), Color("#FFFFFF")))
	end_btn.add_theme_stylebox_override("disabled", _hud_button_style(
		Color(0.039, 0.039, 0.039, 0.85), Color("#333333")))
	end_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	end_btn.add_theme_color_override("font_color", Color("#FFFFFF"))
	end_btn.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	end_btn.add_theme_color_override("font_disabled_color", Color("#777777"))
	end_btn.add_theme_font_size_override("font_size", 14)
	ui.add_child(end_btn)
	end_btn.pressed.connect(_on_end_mission_pressed)

	end_confirm = ConfirmationDialog.new()
	end_confirm.name = "EndMissionConfirm"
	end_confirm.title = "End Mission"
	end_confirm.dialog_text = "File the mission report and leave the lunar surface?"
	end_confirm.get_ok_button().text = "End Mission"
	end_confirm.get_cancel_button().text = "Keep Operating"
	MissionForge.style_button(end_confirm.get_ok_button(), true)
	MissionForge.style_button(end_confirm.get_cancel_button(), false)
	add_child(end_confirm)
	end_confirm.confirmed.connect(_finish_mission)


func _hud_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


func _update_end_mission_button() -> void:
	if end_btn == null:
		return
	if finishing:
		end_btn.disabled = true
		return
	end_btn.disabled = false
	if landed:
		if scan_progress >= 100.0:
			end_btn.text = "✓  END MISSION — SURVEY COMPLETE"
			end_btn.modulate = Color("#FFFFFF")
		else:
			end_btn.text = "■  END MISSION"
			end_btn.modulate = Color("#D9D9D9")
	else:
		end_btn.text = "■  ABORT MISSION"
		end_btn.modulate = Color("#B3B3B3")


func _on_end_mission_pressed() -> void:
	if finishing or end_confirm == null:
		return
	var state := "Touchdown not yet confirmed. Flight data will still be filed."
	if landed:
		state = "Ice survey archived at %d%%. The surface phase will close and the mission report will be generated." % int(scan_progress)
	end_confirm.dialog_text = state + "\n\nEnd this mission now?"
	end_confirm.popup_centered(Vector2i(520, 200))


## Builds the same result contract the orbit/Mars missions hand to the report,
## then transitions.  Score reflects how much of the ice survey actually ran.
func _finish_mission() -> void:
	if finishing:
		return
	finishing = true
	if end_btn:
		end_btn.disabled = true
		end_btn.text = "FILING REPORT…"

	var progress := clampf(scan_progress, 0.0, 100.0)
	var mission: Dictionary = GameManager.current_mission
	var config: Dictionary = GameManager.spacecraft_config
	var goal := float(mission.get("science_goal", 120.0))
	var ice_fraction := progress / 100.0
	var success := landed and progress >= 70.0
	var spent := float(config.get("total_cost", 0.0))
	var budget := float(mission.get("budget", 300.0))

	var objectives := int(round(35.0 * ice_fraction))
	var science := int(round(25.0 * ice_fraction))
	var reliability := 20 if landed else 8
	var efficiency := 15 if spent <= budget * 0.85 else (12 if spent <= budget else 8)
	var operations := 5 if rover_deployed else (3 if landed else 0)
	var score := clampi(objectives + science + reliability + efficiency + operations, 0, 100)

	if success:
		phase_label.text = "MISSION COMPLETE — SOUTH POLE WATER-ICE SURVEY"
		orbit_label.text = "Pragyan traverse archived  |  filing mission report"
	elif landed:
		phase_label.text = "PARTIAL SURVEY — RETURNING RESULTS"
		orbit_label.text = "Ice survey stopped at %d%%  |  filing mission report" % int(progress)
	else:
		phase_label.text = "MISSION ABORTED — FLIGHT DATA RETURNED"
		orbit_label.text = "Descent ended before touchdown  |  filing mission report"

	var events: Array = [
		{"day": 0, "orbit": 0, "msg": "Lunar polar orbit insertion — south-pole target locked.", "type": "info"},
		{
			"day": 0, "orbit": 0,
			"msg": "Orbiter/Vikram separation and powered descent complete." if landed else "Descent ended before touchdown; flight data preserved.",
			"type": "success" if landed else "warning",
		},
	]
	if landed:
		events.append({"day": 1, "orbit": 0, "msg": "Vikram touchdown confirmed at the lunar south pole.", "type": "success"})
	if rover_deployed:
		events.append({"day": 1, "orbit": 0, "msg": "Pragyan rover egress complete; regolith traverse under way.", "type": "success"})
	if progress >= 26.0:
		events.append({"day": 1, "orbit": 0, "msg": "Water-ice signatures confirmed in permanently shadowed crater rims.", "type": "success"})
	events.append({
		"day": 1, "orbit": 0,
		"msg": "Ice survey archived at %d%% — mission report filed." % int(progress),
		"type": "success" if success else "info",
	})

	var improvements: Array = []
	if not landed:
		improvements.append("Touchdown is the gateway objective — a stable descent preserves every surface science return.")
	elif progress < 100.0:
		improvements.append("The rover traverse ended early at %d%% coverage — let Pragyan finish the south-pole survey before extraction." % int(progress))
	if landed and not rover_deployed:
		improvements.append("Pragyan was still stowed when operations ended — deploy the rover before leaving the surface.")
	if spent > budget:
		improvements.append("The mission exceeded the %.0fM credit budget — a lighter bus would improve efficiency next time." % budget)
	improvements.append("NEXT PHASE (Artemis-style): ascend from the south pole, rendezvous with the orbiting relay, then trans-Earth injection — or stay through the 14-day lunar night to continue the ice survey.")

	var result := {
		"success": success,
		"score": score,
		"science_collected": round(goal * ice_fraction * 10.0) / 10.0,
		"science_goal": goal,
		"data_transmitted_gb": round((4.0 + 16.0 * ice_fraction) * 10.0) / 10.0,
		"total_orbits": 1,
		"mission_days": 1,
		"events_log": events,
		"score_breakdown": {
			"objectives": objectives,
			"science": science,
			"reliability": reliability,
			"efficiency": efficiency,
			"operations": operations,
		},
		"improvements": improvements,
	}
	GameManager.mission_result = result
	await get_tree().create_timer(2.2).timeout
	GameManager.go_to_report()
