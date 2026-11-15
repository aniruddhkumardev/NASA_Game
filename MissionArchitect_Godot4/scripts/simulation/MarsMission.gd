## Mars climate-lander sequence: orbit capture, EDL, touchdown, then the survey
## that is the reason this spacecraft left Earth.
extends Node3D

var terrain: MeshInstance3D
var lander: Node3D
var camera: Camera3D
var scan_label: Label
var phase_label: Label
var orbit_label: Label
var day_label: Label
var science_bar: ProgressBar
var rover: Node3D
var weather_mast: Node3D
var parachute: MeshInstance3D
var heat_glow: MeshInstance3D
var mission_time := 0.0
var scan_progress := 0.0
var landed := false
var rover_deployed := false
var finishing := false
var _terrain_noise := FastNoiseLite.new()
const _DUNES := [
	[Vector2(-11.0, -7.0), 5.0, 0.85],
	[Vector2(10.0, -9.0), 6.2, 1.10],
	[Vector2(-7.0, 10.0), 4.0, 0.70],
	[Vector2(12.0, 6.0), 3.4, 0.55],
	[Vector2(1.5, -13.0), 4.8, 0.90],
	[Vector2(-14.0, 4.0), 5.2, 0.95],
]

func _ready() -> void:
	terrain = get_node("Mars/Surface")
	lander = get_node("ClimateLander")
	camera = get_node("MarsCamera")
	scan_label = get_node("UI/Telemetry/ScanLabel")
	phase_label = get_node("UI/HUD/PhaseLabel")
	orbit_label = get_node("UI/Telemetry/OrbitLabel")
	day_label = get_node("UI/HUD/DayLabel")
	science_bar = get_node("UI/Telemetry/ScienceBar")
	_build_terrain()
	_add_rocks()
	_add_stars()
	_add_earth_in_sky()
	_build_lander()
	phase_label.text = "MARS ORBIT INSERTION — AMAZONIS TARGET LOCKED"
	orbit_label.text = "400 km polar orbit  |  Climate lander separation pending"
	print("[MarsMission] Amazonis Planitia descent ready")

func _mars_height(x: float, z: float) -> float:
	var h := _terrain_noise.get_noise_2d(x, z) * 0.55
	h += _terrain_noise.get_noise_2d(x * 0.35, z * 2.4) * 0.28
	for c in _DUNES:
		var crater_xy: Vector2 = c[0]
		var d: float = (Vector2(x, z) - crater_xy).length()
		var r: float = c[1]
		if d < r * 1.4:
			var t := clampf(d / r, 0.0, 1.0)
			h += float(c[2]) * (1.0 - t) * sin(t * PI)
	h *= smoothstep(1.8, 8.0, Vector2(x, z).length())
	return h

func _build_terrain() -> void:
	_terrain_noise.seed = 19
	_terrain_noise.frequency = 0.04
	_terrain_noise.fractal_octaves = 5
	var size := 44.0
	var n := 90
	var step := size / n
	var half := size * 0.5
	var eps := 0.22
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for i in range(n):
		for j in range(n):
			var x0 := -half + float(i) * step
			var z0 := -half + float(j) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var corners := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
			for v in corners:
				st.set_normal(_grad_normal(v.x, v.y, eps))
				st.set_uv(Vector2((v.x + half) / size, (v.y + half) / size))
				st.add_vertex(Vector3(v.x, _mars_height(v.x, v.y), v.y))
			st.add_index(base + 0)
			st.add_index(base + 2)
			st.add_index(base + 1)
			st.add_index(base + 0)
			st.add_index(base + 3)
			st.add_index(base + 2)
			base += 4
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	terrain.mesh = mesh
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode specular_schlick_ggx;
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }
void fragment(){
	float n=noise(UV*18.0)+0.45*noise(UV*42.0)+0.2*noise(UV*90.0);
	vec3 rust=mix(vec3(0.46,0.22,0.10), vec3(0.78,0.42,0.18), n);
	vec3 dark=mix(vec3(0.22,0.10,0.05), vec3(0.38,0.18,0.08), n);
	ALBEDO=mix(dark, rust, smoothstep(0.28,0.92,n));
	ROUGHNESS=0.92;
	METALLIC=0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	terrain.material_override = mat

func _grad_normal(x: float, z: float, eps: float) -> Vector3:
	var dx := (_mars_height(x + eps, z) - _mars_height(x - eps, z)) / (2.0 * eps)
	var dz := (_mars_height(x, z + eps) - _mars_height(x, z - eps)) / (2.0 * eps)
	return Vector3(-dx, 1.0, -dz).normalized()

func _add_rocks() -> void:
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.38, 0.18, 0.08)
	rock_mat.roughness = 1.0
	var parent := get_node("Mars")
	for spec in [[-2.4, -0.6, 0.32], [-1.6, 1.4, 0.20], [1.8, 0.9, 0.22], [2.4, -1.2, 0.36], [4.1, 0.4, 0.24], [-3.6, 1.7, 0.26], [5.0, -2.1, 0.30], [-4.4, -2.8, 0.28]]:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.55
		sm.radial_segments = 10
		sm.rings = 6
		rock.mesh = sm
		rock.position = Vector3(spec[0], _mars_height(spec[0], spec[1]) + spec[2] * 0.5, spec[1])
		rock.scale = Vector3(spec[2] * 1.3, spec[2] * 0.7, spec[2] * 1.1)
		rock.material_override = rock_mat
		parent.add_child(rock)

func _add_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var star_root := Node3D.new()
	star_root.name = "Starfield"
	add_child(star_root)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1, 0.95, 0.88)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1, 0.92, 0.8)
	star_mat.emission_energy_multiplier = 2.2
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(420):
		var theta := rng.randf_range(0.0, TAU)
		var phi := acos(rng.randf_range(-0.2, 1.0))
		var r := 170.0
		var pos := Vector3(r * sin(phi) * cos(theta), r * cos(phi) * 0.55 + 40.0, r * sin(phi) * sin(theta))
		if pos.y < 4.0:
			continue
		var star := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var size := rng.randf_range(0.08, 0.26)
		qm.size = Vector2(size, size)
		star.mesh = qm
		star.material_override = star_mat
		star.position = pos
		star_root.add_child(star)

func _add_earth_in_sky() -> void:
	var earth := MeshInstance3D.new()
	earth.name = "EarthInSky"
	var sm := SphereMesh.new()
	sm.radius = 1.15
	sm.height = 2.3
	earth.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.42, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(0.08, 0.22, 0.7)
	mat.emission_energy_multiplier = 0.7
	earth.material_override = mat
	earth.position = Vector3(-36.0, 42.0, -70.0)
	add_child(earth)

func _make_box(size: Vector3, position: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = material
	parent.add_child(node)
	return node

func _build_lander() -> void:
	var body_root := Node3D.new()
	body_root.name = "AresLander"
	lander.add_child(body_root)
	var cream := StandardMaterial3D.new()
	cream.albedo_color = Color(0.86, 0.82, 0.74)
	cream.metallic = 0.35
	cream.roughness = 0.42
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.72, 0.48, 0.08)
	gold.metallic = 0.85
	gold.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	dark.metallic = 0.5
	dark.roughness = 0.45
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.74, 0.74, 0.78)
	silver.metallic = 0.9
	silver.roughness = 0.22
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.55
	body_mesh.bottom_radius = 0.78
	body_mesh.height = 0.55
	body_mesh.radial_segments = 8
	body.mesh = body_mesh
	body.position.y = 0.78
	body.material_override = cream
	body_root.add_child(body)
	_make_box(Vector3(1.05, 0.08, 0.72), Vector3(0, 1.08, 0), gold, body_root)
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var leg := _make_box(Vector3(0.07, 0.88, 0.07), Vector3(cos(a) * 0.62, 0.4, sin(a) * 0.62), silver, body_root)
		leg.rotation_degrees.z = -sin(a) * 26.0
		leg.rotation_degrees.x = cos(a) * 26.0
		leg.visible = true
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.18
		fm.bottom_radius = 0.18
		fm.height = 0.05
		foot.mesh = fm
		foot.position = Vector3(cos(a) * 0.86, 0.05, sin(a) * 0.86)
		foot.material_override = silver
		body_root.add_child(foot)
	for side in [-1.0, 1.0]:
		var cell := StandardMaterial3D.new()
		cell.albedo_color = Color(0.05, 0.12, 0.42)
		cell.emission_enabled = true
		cell.emission = Color(0.02, 0.06, 0.28)
		cell.emission_energy_multiplier = 0.18
		_make_box(Vector3(1.4, 0.03, 0.42), Vector3(side * 1.12, 0.78, 0), cell, body_root)
	weather_mast = Node3D.new()
	weather_mast.name = "WeatherMast"
	weather_mast.visible = false
	body_root.add_child(weather_mast)
	_make_box(Vector3(0.05, 1.15, 0.05), Vector3(0.22, 1.55, 0.1), silver, weather_mast)
	_make_box(Vector3(0.28, 0.08, 0.12), Vector3(0.22, 2.12, 0.1), dark, weather_mast)
	parachute = MeshInstance3D.new()
	parachute.name = "Parachute"
	var chute := CylinderMesh.new()
	chute.top_radius = 0.15
	chute.bottom_radius = 2.4
	chute.height = 1.6
	parachute.mesh = chute
	parachute.position.y = 3.2
	var chute_mat := StandardMaterial3D.new()
	chute_mat.albedo_color = Color(0.92, 0.55, 0.18, 0.72)
	chute_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	parachute.material_override = chute_mat
	parachute.visible = false
	lander.add_child(parachute)
	heat_glow = MeshInstance3D.new()
	heat_glow.name = "PlasmaSheath"
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 1.15
	glow_mesh.height = 1.4
	heat_glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.45, 0.12, 0.35)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.35, 0.05)
	glow_mat.emission_energy_multiplier = 2.4
	heat_glow.material_override = glow_mat
	heat_glow.visible = false
	lander.add_child(heat_glow)
	rover = Node3D.new()
	rover.name = "ClimateRover"
	rover.visible = false
	add_child(rover)
	_make_box(Vector3(0.92, 0.28, 0.62), Vector3.ZERO, cream, rover)
	var panel := StandardMaterial3D.new()
	panel.albedo_color = Color(0.04, 0.10, 0.44)
	_make_box(Vector3(0.82, 0.03, 0.5), Vector3(0, 0.16, 0), panel, rover)
	for xi in [-0.28, 0.0, 0.28]:
		for zi in [-0.32, 0.32]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.12
			wm.bottom_radius = 0.12
			wm.height = 0.09
			wheel.mesh = wm
			wheel.position = Vector3(xi, -0.14, zi)
			wheel.rotation_degrees.z = 90.0
			wheel.material_override = dark
			rover.add_child(wheel)
	_make_box(Vector3(0.04, 0.42, 0.04), Vector3(-0.18, 0.36, 0.0), silver, rover)
	_make_box(Vector3(0.16, 0.08, 0.1), Vector3(-0.18, 0.58, 0.0), dark, rover)

func _process(delta: float) -> void:
	mission_time += delta
	if mission_time < 6.0:
		var a := mission_time * 0.62
		lander.position = Vector3(sin(a) * 7.2, 4.2 + cos(a) * 1.4, cos(a) * 7.2)
		heat_glow.visible = false
		parachute.visible = false
		phase_label.text = "MARS ORBIT — LANDING ELLIPSE IMAGING"
		orbit_label.text = "400 km orbit  |  Amazonis Planitia hazard map  |  dust forecast GREEN"
	elif mission_time < 12.0:
		var t := (mission_time - 6.0) / 6.0
		lander.position = Vector3(2.4 * (1.0 - t), 18.0 - t * 8.0, 3.2 * (1.0 - t))
		heat_glow.visible = true
		heat_glow.scale = Vector3.ONE * (1.2 + t * 0.4)
		parachute.visible = false
		phase_label.text = "ENTRY INTERFACE — PLASMA BLACKOUT"
		orbit_label.text = "Altitude: %d km  |  Peak heating  |  heatshield forward" % int((1.0 - t) * 125)
	elif mission_time < 18.0:
		var t := (mission_time - 12.0) / 6.0
		lander.position = Vector3(1.2 * (1.0 - t), 10.0 * (1.0 - t) + 2.4, 1.6 * (1.0 - t))
		heat_glow.visible = false
		parachute.visible = true
		phase_label.text = "SUPERSONIC PARACHUTE — TERMINAL DESCENT"
		orbit_label.text = "Altitude: %d m  |  Chute inflated  |  radar altimeter lock" % int((1.0 - t) * 8200 + 400)
	elif mission_time < 24.0:
		var t := (mission_time - 18.0) / 6.0
		lander.position = Vector3(0.4 * (1.0 - t), 2.4 * (1.0 - t) + 0.04, 0.5 * (1.0 - t))
		parachute.visible = t < 0.55
		phase_label.text = "POWERED DESCENT — SKYCRANE RELEASE"
		orbit_label.text = "Altitude: %d m  |  Vertical velocity: %.1f m/s" % [int((1.0 - t) * 380), maxf(0.8, 18.0 * (1.0 - t))]
	else:
		if not landed:
			landed = true
			parachute.visible = false
			heat_glow.visible = false
			phase_label.text = "TOUCHDOWN CONFIRMED — AMAZONIS PLANITIA"
		lander.position = Vector3.ZERO
		orbit_label.text = "Lander stable  |  3.71 m/s²  |  climate station boot"
		if mission_time > 27.0:
			_deploy_surface(delta)
	if landed:
		scan_progress = minf(100.0, scan_progress + delta * 3.4)
		if Input.is_action_pressed("science_scan"):
			scan_progress = minf(100.0, scan_progress + delta * 10.0)
		camera.position = camera.position.lerp(Vector3(4.6, 2.6, 6.0), minf(delta * 0.65, 1.0))
		camera.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	else:
		camera.position = camera.position.lerp(lander.position + Vector3(5.8, 3.2, 7.4), minf(delta * 0.5, 1.0))
		camera.look_at(lander.position, Vector3.UP)
	if science_bar:
		science_bar.value = scan_progress
	if day_label:
		day_label.text = "Sol 0 / 687  |  " + ("Surface climate survey" if landed else "Arrival, entry, descent")
	if scan_label:
		var activity := "EDL sequence running"
		if landed:
			if rover_deployed:
				activity = "Rover sampling dust + weather mast live"
			else:
				activity = "Station checkout — mast deployment"
		scan_label.text = "Climate objective: %.0f%%  |  %s  |  hold I to scan faster" % [scan_progress, activity]
	if scan_progress >= 100.0 and landed and not finishing:
		finishing = true
		phase_label.text = "CLIMATE SURVEY COMPLETE — DUST, WEATHER, WATER ICE"
		_finish_mission()

func _deploy_surface(delta: float) -> void:
	if not rover_deployed:
		rover_deployed = true
		rover.visible = true
		weather_mast.visible = true
		rover.position = Vector3(0.2, 0.26, 1.2)
		phase_label.text = "WEATHER MAST LIVE — DUST & ATMOSPHERE SURVEY"
	else:
		rover.position.z = minf(3.4, rover.position.z + delta * 0.16)
		rover.rotation.y = sin(mission_time * 1.2) * 0.05

func _finish_mission() -> void:
	var mission: Dictionary = GameManager.current_mission
	var config: Dictionary = GameManager.spacecraft_config
	var science: float = float(mission.get("science_goal", 200))
	var result := {
		"success": true,
		"score": 92,
		"science_collected": science,
		"science_goal": science,
		"data_transmitted_gb": 18.4,
		"total_orbits": 12,
		"mission_days": 1,
		"events_log": [
			{"day": 0, "orbit": 0, "msg": "Earth launch and trans-Mars injection complete.", "type": "success"},
			{"day": 0, "orbit": 0, "msg": "Amazonis Planitia touchdown confirmed.", "type": "success"},
			{"day": 0, "orbit": 0, "msg": "Dust-storm map, atmospheric profile, and subsurface ice signatures downlinked.", "type": "success"}
		],
		"score_breakdown": {
			"objectives": 35,
			"science": 25,
			"reliability": 18,
			"efficiency": 9,
			"operations": 5
		},
		"improvements": [
			"You completed the reason this mission left Earth: a working climate station on Mars."
		]
	}
	if config.get("total_cost", 0) > mission.get("budget", 600) * 0.9:
		result["improvements"].append("Budget was tight — a cheaper bus would leave more margin next time.")
	GameManager.mission_result = result
	await get_tree().create_timer(4.5).timeout
	GameManager.go_to_report()
