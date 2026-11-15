## Dedicated Earth-to-Mars cruise. Follows Earth launch; hands off to landing.
extends Node3D

const EARTH_TEXTURE := preload("res://assets/textures/earth-blue-marble-8k.jpg")

var phase_label: Label
var detail_label: Label
var telemetry_label: Label
var begin_button: Button
var camera: Camera3D
var earth: MeshInstance3D
var mars: MeshInstance3D
var vehicle: Node3D
var transfer_arc: MeshInstance3D
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
	active = true
	begin_button.hide()
	phase_label.text = "EARTH PARKING ORBIT — TRANS-MARS ALIGNMENT"
	detail_label.text = "Climate lander stack coasts above Earth while guidance times the departure burn for Mars intercept."
	_update_cinematic(0.0)

func _build_space_scene() -> void:
	earth = _sphere(3.05, EARTH_TEXTURE, Color.WHITE, true)
	earth.position = Vector3(-7.2, -1.1, -10.2)
	add_child(earth)
	mars = _mars_globe(2.15)
	mars.position = Vector3(11.4, 1.6, -20.0)
	add_child(mars)
	vehicle = Node3D.new()
	vehicle.name = "CruiseStack"
	add_child(vehicle)
	var cruise := MeshInstance3D.new()
	var cruise_mesh := CylinderMesh.new()
	cruise_mesh.top_radius = 0.28
	cruise_mesh.bottom_radius = 0.36
	cruise_mesh.height = 1.15
	cruise.mesh = cruise_mesh
	cruise.position.y = -0.38
	cruise.material_override = _metal(Color(0.78, 0.80, 0.84))
	vehicle.add_child(cruise)
	var lander := MeshInstance3D.new()
	var lander_mesh := CylinderMesh.new()
	lander_mesh.top_radius = 0.32
	lander_mesh.bottom_radius = 0.48
	lander_mesh.height = 0.48
	lander.mesh = lander_mesh
	lander.position.y = 0.42
	lander.material_override = _metal(Color(0.86, 0.82, 0.74))
	vehicle.add_child(lander)
	var heatshield := MeshInstance3D.new()
	var shield_mesh := CylinderMesh.new()
	shield_mesh.top_radius = 0.12
	shield_mesh.bottom_radius = 0.58
	shield_mesh.height = 0.18
	heatshield.mesh = shield_mesh
	heatshield.position.y = 0.72
	heatshield.material_override = _metal(Color(0.22, 0.10, 0.05))
	vehicle.add_child(heatshield)
	var solar := MeshInstance3D.new()
	var solar_mesh := BoxMesh.new()
	solar_mesh.size = Vector3(2.6, 0.03, 0.55)
	solar.mesh = solar_mesh
	solar.position.y = 0.12
	solar.material_override = _metal(Color(0.02, 0.08, 0.28))
	vehicle.add_child(solar)
	var hga := MeshInstance3D.new()
	var hga_mesh := SphereMesh.new()
	hga_mesh.radius = 0.18
	hga_mesh.height = 0.10
	hga.mesh = hga_mesh
	hga.position = Vector3(0.0, 0.95, 0.12)
	hga.material_override = _metal(Color(0.85, 0.85, 0.82))
	vehicle.add_child(hga)
	transfer_arc = MeshInstance3D.new()
	var arc := TorusMesh.new()
	arc.inner_radius = 6.35
	arc.outer_radius = 6.42
	arc.rings = 96
	arc.ring_segments = 10
	transfer_arc.mesh = arc
	transfer_arc.material_override = _glow(Color(0.95, 0.42, 0.12, 0.32))
	transfer_arc.position = earth.position
	transfer_arc.rotation_degrees = Vector3(62, -22, 18)
	transfer_arc.visible = false
	add_child(transfer_arc)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -48, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.86, 0.68)
	add_child(sun)
	_add_stars()

func _mars_globe(radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "MarsGlobe"
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 64
	node.mesh = mesh
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid fragment(){ vec2 uv=UV; float n=noise(uv*6.0)+0.5*noise(uv*14.0)+0.25*noise(uv*32.0); float polar=smoothstep(0.32,0.46,abs(uv.y-0.5)); vec3 rust=mix(vec3(0.42,0.18,0.08), vec3(0.78,0.42,0.18), n); vec3 dark=mix(vec3(0.18,0.08,0.04), vec3(0.34,0.16,0.08), n); vec3 land=mix(dark, rust, smoothstep(0.35,1.05,n)); vec3 ice=vec3(0.86,0.88,0.92); ALBEDO=mix(land, ice, polar*0.85); EMISSION=ALBEDO*0.22; }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	node.material_override = mat
	return node

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
	begin_button.text = "TRANS-MARS CRUISE IN PROGRESS"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		if not handoff_requested:
			handoff_requested = true
			CinematicTransition.travel("res://scenes/mars/mars_mission.tscn", "MARS APPROACH", "Cruise complete — climate lander entering the Martian atmosphere")

func _process(delta: float) -> void:
	if not active:
		return
	timer += delta
	_update_cinematic(timer)
	if timer < 6.0:
		phase_label.text = "1 / 4  •  EARTH DEPARTURE"
		detail_label.text = "Upper stage coasts in parking orbit. Trans-Mars injection burn is timed for the Mars intercept window."
	elif timer < 14.0:
		phase_label.text = "2 / 4  •  TRANS-MARS INJECTION"
		detail_label.text = "The cruise stage leaves Earth. Blue marble recedes; the climate lander is now a deep-space vehicle."
	elif timer < 22.0:
		phase_label.text = "3 / 4  •  INTERPLANETARY CRUISE"
		detail_label.text = "Nine months compressed: mid-course correction, RTG health check, and weather-payload calibration."
	elif timer < 28.0:
		phase_label.text = "4 / 4  •  MARS ARRIVAL"
		detail_label.text = "Mars fills the window. Heatshield forward. Entry, descent, and landing sequence armed."
	elif not handoff_requested:
		handoff_requested = true
		CinematicTransition.travel("res://scenes/mars/mars_mission.tscn", "MARS ORBIT CAPTURE", "Braking burn complete — climate lander preparing for Amazonis descent")

func _update_cinematic(t: float) -> void:
	var transfer: float = clampf((t - 6.0) / 8.0, 0.0, 1.0)
	var cruise: float = clampf((t - 14.0) / 8.0, 0.0, 1.0)
	var approach: float = clampf((t - 22.0) / 6.0, 0.0, 1.0)
	transfer_arc.visible = t >= 6.0 and t < 16.0
	var departure := earth.position + Vector3(4.1, 2.4, 2.6)
	var midcourse := Vector3(2.2, 3.6, -11.0)
	var far_cruise := Vector3(6.4, 2.8, -15.5)
	var arrival := mars.position + Vector3(-3.4, -1.4, 2.6)
	if t < 6.0:
		vehicle.position = earth.position + Vector3(cos(t * 1.15) * 4.2, sin(t * 1.15) * 1.15, 2.8)
	elif t < 14.0:
		vehicle.position = departure.bezier_interpolate(midcourse, Vector3(-0.4, 5.4, -13.0), far_cruise, transfer)
	elif t < 22.0:
		vehicle.position = far_cruise.lerp(arrival, cruise)
	else:
		vehicle.position = arrival.lerp(mars.position + Vector3(-1.8, -2.2, 3.0), approach)
	vehicle.rotation_degrees = Vector3(16.0, -t * 14.0, 74.0)
	if t < 22.0:
		camera.position = vehicle.position + Vector3(6.8, 3.8, 9.8)
	else:
		camera.position = mars.position + Vector3(-7.0, 3.6, 10.2)
	camera.look_at(vehicle.position, Vector3.UP)
	telemetry_label.text = "CRUISE ELAPSED  %02d:%02d  |  RANGE TO MARS  %s  |  SPACE to skip" % [int(t) / 60, int(t) % 60, _distance_text(t)]

func _distance_text(t: float) -> String:
	if t < 6.0:
		return "225 million km"
	if t < 14.0:
		return "%.0f million km" % (225.0 * (1.0 - clampf((t - 6.0) / 8.0, 0.0, 1.0)) + 18.0)
	if t < 22.0:
		return "%.0f million km" % (18.0 * (1.0 - clampf((t - 14.0) / 8.0, 0.0, 1.0)) + 0.8)
	return "%d km" % max(400, int(800000.0 * (1.0 - clampf((t - 22.0) / 6.0, 0.0, 1.0))))
