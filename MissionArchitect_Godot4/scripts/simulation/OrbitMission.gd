## OrbitMission.gd
## The live orbital operations scene — satellite flying, mission control dashboard

extends Node3D

# ─── 3D Scene Nodes ───────────────────────────────────────────────────────────
var earth_sphere: MeshInstance3D
var earth_atmosphere: MeshInstance3D
var earth_clouds: MeshInstance3D
var satellite_node: Node3D
var satellite_visual: Node3D
var earth_node: Node3D
var satellite_mesh: MeshInstance3D
var solar_panel_l: MeshInstance3D
var solar_panel_r: MeshInstance3D
var orbit_path: MeshInstance3D
var ground_track: Node3D
var sun_light: DirectionalLight3D
var mission_camera: Camera3D
var orbit_camera: Camera3D

# ─── UI Nodes ─────────────────────────────────────────────────────────────────
var battery_bar: ProgressBar
var power_bar: ProgressBar
var science_bar: ProgressBar
var data_bar: ProgressBar
var battery_label: Label
var power_label: Label
var science_label: Label
var data_label: Label
var orbit_info: Label
var day_label: Label
var speed_label: Label
var eclipse_indicator: Label
var contact_indicator: Label
var event_log: VBoxContainer
var speed_btn_1x: Button
var speed_btn_10x: Button
var speed_btn_100x: Button
var transmit_btn: Button
var safemode_btn: Button
var end_mission_btn: Button
var orbital_map_panel: Control
var event_popup: PanelContainer
var event_popup_label: Label
var pause_menu: Control
var arrival_overlay: Control
var arrival_title: Label
var arrival_detail: Label
var arrival_fade: ColorRect
var rcs_thrusters: Array[MeshInstance3D] = []
var downlink_beam: MeshInstance3D
var solar_deployment: float = 0.0
var attitude_pulse: float = 0.0

# ─── State ────────────────────────────────────────────────────────────────────
var orbit_radius_3d: float = 3.5   # visual scale (Earth = radius 2)
var show_orbital_map: bool = false
var event_popup_timer: float = 0.0
var log_entries: Array = []
var arrival_active: bool = true
var arrival_timer: float = 0.0
var mars_operations: bool = false
var asteroid_operations: bool = false

# ─── Ground-station network + commissioning ────────────────────────────────────
# The scene and the simulation have to agree about where every station is and
# whether it can see the vehicle, or the picture contradicts the telemetry.  So
# the pins below are placed from the *same* functions the engine uses to decide
# contact, ride the *same* planet rotation, and the satellite itself is flown on
# the *same* sub-satellite direction — the beam is then simply a line between two
# points that both the model and the picture already know about.
var earth_surface_radius: float = 6.0
var stations_root: Node3D = null
var station_pins: Array[Node3D] = []
var station_halos: Array[MeshInstance3D] = []
const COMMISSION_TARGET_REVS: int = 2
var commissioning_active: bool = false
var commission_start_orbits: int = 0
var commission_revs_done: int = 0
var commission_passes: int = 0
var commission_mb: float = 0.0
var commission_complete: bool = false
var _last_contact: bool = false
var commission_overlay: Control = null
var commission_title: Label = null
var commission_detail: Label = null

# ─── Climate survey markers (Earth Climate Sentinel only) ─────────────────────
# One pin per real NASA-tracked event, placed with the same lat/lon→direction
# calibration as the ground stations so a marker sits on the actual place the
# headline happened.  They ride the planet's spin; the orbital plane does not,
# so the precessing ground track sweeps across them revolution by revolution.
var climate_root: Node3D = null
var climate_pins: Array[Node3D] = []
var climate_halos: Array[MeshInstance3D] = []

# ─── Capture flyover cinematic (Earth Climate Sentinel only) ─────────────────
# When the science model senses a real event, the camera flies to the exact
# lat/lon the marker sits on and a data card opens with the actual NASA
# WorldView scene — same pixel evidence a journalist would get, streamed
# live, cached for offline play, and degraded to numeric data when offline.
const ClimateMediaScript := preload("res://scripts/simulation/ClimateMedia.gd")
var climate_media: Node = null
var fly_time: float = 0.0
var fly_target: Dictionary = {}
var fly_pin: Node3D = null
var fly_panel: PanelContainer = null
var fly_image: TextureRect = null
var fly_title: Label = null
var fly_subtitle: Label = null
var fly_stat: Label = null
var fly_credit: Label = null
var fly_status: Label = null
var fly_head: Label = null

# ─── SWOT surface-water survey + mission control room ────────────────────────
# The Earth mission flies the SWOT (NASA/CNES) water survey alongside the
# climate-event record: the KaRIn radar swath scans real ocean, lake and river
# sites, records them onboard, and the ground-station network carries them to
# the control room monitors.  The 3D pins, the scan footprint and the monitor
# wall all read the same simulation state.
const SwotControlRoomScript := preload("res://scripts/ui/SwotControlRoom.gd")
var swot_root: Node3D = null
var swot_pins: Array[Node3D] = []
var swot_halos: Array[MeshInstance3D] = []
var swot_scan_beam: MeshInstance3D = null
var swot_scan_ring: MeshInstance3D = null
var control_room = null
var control_room_open: bool = false
var control_room_timer: float = 0.0

# ─── Surface area inspection (click-to-zoom + local temperature/weather) ──────
# The globe is not just a backdrop: clicking it casts a ray onto the actual
# sphere, converts the hit back into the planet's own lat/lon frame, and flies
# the camera down to that patch.  The readout is modelled from the same
# latitude, season and local solar time the orbit is already carrying, so the
# day/night terminator on screen and the "night side" label agree.
var area_layer: CanvasLayer = null
var area_panel: PanelContainer = null
var area_coords: Label = null
var area_place: Label = null
var area_temp: Label = null
var area_weather: Label = null
var area_wind: Label = null
var area_solar: Label = null
var area_site: Label = null
var area_source: Label = null
var area_zoom_label: Label = null
var area_hint: Label = null
var inspect_active: bool = false
var inspect_lat: float = 0.0
var inspect_lon: float = 0.0
var inspect_distance: float = 1.4     # camera altitude above the surface, world units
var inspect_timer: float = 0.0
var inspect_conditions: Dictionary = {}
var inspect_place: Dictionary = {}
var inspect_place_override: Dictionary = {}
var inspect_root: Node3D = null
var inspect_pin: Node3D = null
var inspect_ring: MeshInstance3D = null
var inspect_tag: Label3D = null
var view_fov: float = 60.0
var camera_return_timer: float = 0.0

# ─── Exterior globe camera (mouse-wheel dolly + zoom-to-cursor) ───────────────
# The camera orbits the globe on a spherical rig.  The wheel changes the rig
# radius (a real dolly, so the map gains detail instead of only narrowing the
# lens) and, when the cursor is over the planet, swings the rig toward the patch
# under the cursor.  That is what makes zooming feel anchored to the place the
# player is looking at rather than to the screen centre.
const VIEW_HOME := Vector3(-11.5, 7.5, 14.5)
const VIEW_HOME_DISTANCE := 19.98
const VIEW_MIN_DISTANCE := 6.30       # ~318 km above the 6-unit globe
const VIEW_MAX_DISTANCE := 34.0
var view_distance: float = VIEW_HOME_DISTANCE
var view_distance_target: float = VIEW_HOME_DISTANCE
var view_dir: Vector3 = VIEW_HOME.normalized()
var view_focus_local: Vector3 = Vector3.ZERO   # ZERO = look at globe centre

# ─── Offline place gazetteer + search (any city on Earth) ─────────────────────
# GeoNames cities15000 (CC BY 4.0), bundled as lat/lon/name records so the
# search box and the click-to-identify readout work with no network at all.
const WORLD_PLACES_PATH := "res://data/world_places.json"
const PLACE_NAME_KM := 1200.0
var world_places: Array = []
var place_search_layer: CanvasLayer = null
var place_search_edit: LineEdit = null
var place_results: ItemList = null

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# 3D nodes
	earth_sphere      = _g("Earth/EarthMesh")
	earth_atmosphere  = _g("Earth/AtmosphereMesh")
	satellite_node    = _g("Satellite")
	satellite_visual  = _g("Satellite/SatelliteModel")
	earth_node        = _g("Earth")
	satellite_mesh    = _g("Satellite/SatMesh")
	solar_panel_l     = _g("Satellite/SolarPanelL")
	solar_panel_r     = _g("Satellite/SolarPanelR")
	orbit_path        = _g("OrbitPath")
	sun_light         = _g("SunLight")
	mission_camera    = _g("MissionCamera")
	orbit_camera      = _g("OrbitCamera")

	# UI nodes
	battery_bar       = _g("UI/TelemetryPanel/VBox/BatteryBar")
	power_bar         = _g("UI/TelemetryPanel/VBox/PowerBar")
	science_bar       = _g("UI/TelemetryPanel/VBox/ScienceBar")
	data_bar          = _g("UI/TelemetryPanel/VBox/DataBar")
	battery_label     = _g("UI/TelemetryPanel/VBox/BatteryLabel")
	power_label       = _g("UI/TelemetryPanel/VBox/PowerLabel")
	science_label     = _g("UI/TelemetryPanel/VBox/ScienceLabel")
	data_label        = _g("UI/TelemetryPanel/VBox/DataLabel")
	orbit_info        = _g("UI/TelemetryPanel/VBox/OrbitInfoLabel")
	day_label         = _g("UI/HUD/DayLabel")
	speed_label       = _g("UI/HUD/SpeedLabel")
	eclipse_indicator = _g("UI/HUD/EclipseIndicator")
	contact_indicator = _g("UI/HUD/ContactIndicator")
	event_log         = _g("UI/EventLog/ScrollContainer/EventList")
	speed_btn_1x      = _g("UI/Controls/Speed1x")
	speed_btn_10x     = _g("UI/Controls/Speed10x")
	speed_btn_100x    = _g("UI/Controls/Speed100x")
	transmit_btn      = _g("UI/Controls/TransmitButton")
	safemode_btn      = _g("UI/Controls/SafeModeButton")
	end_mission_btn   = _g("UI/Controls/EndMissionButton")
	orbital_map_panel = _g("UI/OrbitalMapPanel")
	event_popup       = _g("UI/EventPopup")
	event_popup_label = _g("UI/EventPopup/EventLabel")
	pause_menu        = _g("UI/PauseMenu")
	arrival_overlay   = _g("UI/ArrivalOverlay")
	arrival_title     = _g("UI/ArrivalOverlay/ArrivalText/Title")
	arrival_detail    = _g("UI/ArrivalOverlay/ArrivalText/Detail")

	# Connect buttons
	if speed_btn_1x:    speed_btn_1x.pressed.connect(_on_speed_1x_pressed)
	if speed_btn_10x:   speed_btn_10x.pressed.connect(_on_speed_10x_pressed)
	if speed_btn_100x:  speed_btn_100x.pressed.connect(_on_speed_100x_pressed)
	var s1000 = _g("UI/Controls/Speed1000x")
	if s1000: s1000.pressed.connect(_on_speed_1000x_pressed)
	if transmit_btn:    transmit_btn.pressed.connect(_on_transmit_pressed)
	if safemode_btn:    safemode_btn.pressed.connect(_on_safemode_pressed)
	if end_mission_btn: end_mission_btn.pressed.connect(_on_end_mission_pressed)
	var resume_btn = _g("UI/PauseMenu/PauseVBox/ResumeButton")
	if resume_btn: resume_btn.pressed.connect(_on_resume_pressed)
	var quit_btn = _g("UI/PauseMenu/PauseVBox/QuitToMenuButton")
	if quit_btn: quit_btn.pressed.connect(_on_quit_to_menu_pressed)

	if orbital_map_panel: orbital_map_panel.hide()
	if event_popup: event_popup.hide()
	if pause_menu: pause_menu.hide()

	mars_operations = GameManager.is_mars_mission()
	asteroid_operations = GameManager.is_asteroid_mission()
	_setup_earth()
	_setup_orbit_path()
	if mars_operations and sun_light:
		sun_light.light_color = Color(1.0, 0.72, 0.48, 1.0)
		sun_light.light_energy = 1.55
	elif asteroid_operations and sun_light:
		sun_light.light_color = Color(0.92, 0.86, 0.72, 1.0)
		sun_light.light_energy = 1.35
	_setup_satellite_visuals()
	_create_starfield()
	if not mars_operations and not asteroid_operations:
		_build_ground_stations()
	if GameManager.is_earth_climate_mission():
		_build_climate_targets()
		_build_swot_water_targets()
		_create_swot_scan_visuals()
		_build_climate_flyover_ui()
		_build_control_room()
		_build_area_inspection()
	_create_arrival_fade()
	_begin_orbit_arrival()

	SimulationEngine.start_simulation(randi())
	SimulationEngine.state_updated.connect(_on_state_updated)
	SimulationEngine.event_occurred.connect(_on_event_occurred)
	SimulationEngine.mission_ended.connect(_on_mission_ended)

	_update_speed_buttons(1)
	_mark_live_telemetry()
	print("[OrbitMission] Ready")

## Flags the numeric readouts whose values are constantly rewritten by the
## simulation, so the MISSIONFORGE pass keeps them in the sanctioned live red.
func _mark_live_telemetry() -> void:
	var live_labels: Array[Label] = [
		battery_label, power_label, science_label, data_label,
		orbit_info, day_label, speed_label,
		area_coords, area_temp, area_weather, area_wind, area_solar,
		area_zoom_label,
	]
	for lbl in live_labels:
		if lbl:
			MissionForge.live(lbl)
	# These are built after _ready() on climate missions.
	if commission_detail:
		MissionForge.live(commission_detail)
	if fly_stat:
		MissionForge.live(fly_stat)

func _g(path: String) -> Node:
	if has_node(path): return get_node(path)
	return null

# ─── Earth Setup ─────────────────────────────────────────────────────────────
func _setup_earth() -> void:
	# A separate, slowly moving cloud shell keeps the NASA Blue Marble surface
	# readable while giving Earth a living, weather-scale layer.
	if not earth_node: return
	if asteroid_operations:
		if earth_sphere:
			var asteroid_shader := Shader.new()
			asteroid_shader.code = "shader_type spatial;\nrender_mode diffuse_burley, specular_schlick_ggx;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid vertex(){ float rough=sin(VERTEX.x*8.0+VERTEX.y*5.0)*sin(VERTEX.z*7.0+VERTEX.x*3.0); VERTEX += NORMAL*rough*0.055; }\nvoid fragment(){ vec2 uv=UV; float n=noise(uv*13.0)+0.45*noise(uv*31.0)+0.2*noise(uv*67.0); float pits=smoothstep(0.58,0.82,noise(uv*42.0)); vec3 rock=mix(vec3(0.12,0.095,0.075),vec3(0.43,0.32,0.22),smoothstep(0.42,1.0,n)); rock*=1.0-pits*0.32; ALBEDO=rock; ROUGHNESS=0.94; METALLIC=0.0; EMISSION=rock*0.025; }"
			var asteroid_material := ShaderMaterial.new()
			asteroid_material.shader = asteroid_shader
			earth_sphere.material_override = asteroid_material
			earth_sphere.scale = Vector3(1.25, 0.92, 1.08)
		if earth_atmosphere:
			earth_atmosphere.hide()
		if earth_clouds:
			earth_clouds.hide()
		return
	# Use one simple unshaded material for the NASA texture. This intentionally
	# avoids custom surface shader fallbacks while the presentation is verified.
	if earth_sphere:
		if mars_operations:
			var mars_shader := Shader.new()
			mars_shader.code = "shader_type spatial;\nrender_mode unshaded;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid fragment(){ vec2 uv=UV; float n=noise(uv*6.0)+0.5*noise(uv*14.0)+0.25*noise(uv*32.0); float polar=smoothstep(0.32,0.46,abs(uv.y-0.5)); vec3 rust=mix(vec3(0.42,0.18,0.08), vec3(0.78,0.42,0.18), n); vec3 dark=mix(vec3(0.18,0.08,0.04), vec3(0.34,0.16,0.08), n); vec3 land=mix(dark, rust, smoothstep(0.35,1.05,n)); vec3 ice=vec3(0.86,0.88,0.92); ALBEDO=mix(land, ice, polar*0.85); EMISSION=ALBEDO*0.22; }"
			var mars_mat := ShaderMaterial.new()
			mars_mat.shader = mars_shader
			earth_sphere.material_override = mars_mat
			earth_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if earth_atmosphere:
				var atmo := StandardMaterial3D.new()
				atmo.albedo_color = Color(0.72, 0.32, 0.12, 0.10)
				atmo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				atmo.cull_mode = BaseMaterial3D.CULL_FRONT
				atmo.emission_enabled = true
				atmo.emission = Color(0.55, 0.18, 0.05, 1.0)
				atmo.emission_energy_multiplier = 0.22
				earth_atmosphere.material_override = atmo
		else:
			# 8k NASA-derived Blue Marble imagery: the previous 2k map turned
			# into mush as soon as the new dolly-zoom brought the surface close.
			var earth_texture := load("res://assets/textures/earth-blue-marble-8k.jpg") as Texture2D
			if earth_texture:
				var earth_mat := StandardMaterial3D.new()
				earth_mat.albedo_texture = earth_texture
				earth_mat.albedo_color = Color.WHITE
				earth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				# Anisotropic filtering keeps coastlines and city grids sharp at
				# grazing angles instead of smearing them at close zoom.
				earth_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				earth_sphere.material_override = earth_mat
				earth_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	earth_clouds = MeshInstance3D.new()
	earth_clouds.name = "DynamicCloudLayer"
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = 1.0
	cloud_mesh.height = 2.0
	earth_clouds.mesh = cloud_mesh
	earth_clouds.scale = Vector3.ONE * 6.075
	var cloud_shader := Shader.new()
	cloud_shader.code = "shader_type spatial;\nrender_mode blend_mix, cull_back, unshaded;\nfloat hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }\nfloat noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y); }\nvoid fragment(){ vec2 uv=UV; uv.x += TIME*0.0018; float n=noise(uv*8.0)+0.5*noise(uv*19.0)+0.25*noise(uv*38.0); float clouds=smoothstep(1.03,1.38,n)*(0.52-smoothstep(0.40,0.51,abs(uv.y-0.5))); ALBEDO=vec3(0.82,0.91,1.0); EMISSION=vec3(0.12,0.18,0.30)*clouds; ALPHA=clouds*0.56; }"
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = cloud_shader
	earth_clouds.material_override = cloud_mat
	earth_node.add_child(earth_clouds)
	# The procedural cloud mask is intentionally kept off until it has a proper
	# cloud texture. Its current noise threshold can blanket the whole planet in
	# white and destroy the Blue Marble surface.
	earth_clouds.hide()

	# The beam is only shown during a real simulated ground-station pass.
	# It terminates at the nadir point beneath the spacecraft rather than
	# floating decoratively in space.
	downlink_beam = MeshInstance3D.new()
	downlink_beam.name = "ActiveGroundStationDownlink"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.018
	beam_mesh.bottom_radius = 0.052
	beam_mesh.height = 2.0
	beam_mesh.radial_segments = 12
	downlink_beam.mesh = beam_mesh
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(0.08, 0.82, 1.0, 0.42)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(0.04, 0.65, 1.0, 1.0)
	beam_mat.emission_energy_multiplier = 2.8
	downlink_beam.material_override = beam_mat
	downlink_beam.hide()
	add_child(downlink_beam)

func _setup_orbit_path() -> void:
	# Orbit radius based on mission altitude — scene material already set
	var alt: float = GameManager.current_mission.get("altitude_km", 550)
	var body_r: float = 3389.5 if mars_operations else 6371.0
	var scale_3d: float = 2.4 if asteroid_operations else 6.0 + (alt / body_r) * 3.0
	orbit_radius_3d = scale_3d
	if orbit_path:
		# An orbit is a trajectory, not a glowing hula hoop. Keep it for a future
		# tactical map, but never render it in the cinematic exterior shot.
		orbit_path.hide()

func _setup_satellite_visuals() -> void:
	# Add explicit deployable arrays around the imported bus model. The model
	# remains the spacecraft body while these panels communicate mission state.
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.015, 0.07, 0.34, 1.0)
	panel_mat.metallic = 0.55
	panel_mat.roughness = 0.28
	panel_mat.emission_enabled = true
	panel_mat.emission = Color(0.015, 0.05, 0.22, 1.0)
	panel_mat.emission_energy_multiplier = 0.55
	for panel in [solar_panel_l, solar_panel_r]:
		if panel:
			var panel_mesh := BoxMesh.new()
			panel_mesh.size = Vector3(3.2, 0.045, 0.62)
			panel.mesh = panel_mesh
			panel.show()
			panel.material_override = panel_mat
			panel.scale = Vector3(0.06, 1.0, 1.0)
	# An Earth-observation payload aperture makes the satellite's purpose legible
	# in close shots instead of reading as an anonymous cube with solar panels.
	if satellite_node:
		var payload_camera := MeshInstance3D.new()
		payload_camera.name = "AsteroidCompositionImager" if asteroid_operations else "MarsClimateImager" if mars_operations else "EarthObservationCamera"
		var camera_mesh := CylinderMesh.new()
		camera_mesh.top_radius = 0.14
		camera_mesh.bottom_radius = 0.20
		camera_mesh.height = 0.30
		camera_mesh.radial_segments = 20
		payload_camera.mesh = camera_mesh
		payload_camera.position = Vector3(0.0, -0.28, 0.08)
		payload_camera.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		var lens_mat := StandardMaterial3D.new()
		lens_mat.albedo_color = Color(0.008, 0.025, 0.055, 1.0)
		lens_mat.metallic = 0.75
		lens_mat.roughness = 0.12
		lens_mat.emission_enabled = true
		lens_mat.emission = Color(0.01, 0.10, 0.18, 1.0)
		lens_mat.emission_energy_multiplier = 0.8
		payload_camera.material_override = lens_mat
		satellite_node.add_child(payload_camera)
	_color_satellite_model()
	_create_rcs_thrusters()

## Gives the imported bus its real spacecraft palette: gold MLI foil on the
## body blankets, silver-white structure and dish, deep-blue solar arrays and
## gunmetal thrusters.  A whisper of emission keeps those colours readable in
## sunlight instead of collapsing to a grey silhouette at orbital distance.
func _color_satellite_model() -> void:
	if satellite_visual == null:
		return
	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.82, 0.84, 0.88, 1.0)
	silver.metallic = 0.82
	silver.roughness = 0.26
	silver.emission_enabled = true
	silver.emission = Color(0.13, 0.14, 0.16, 1.0)
	silver.emission_energy_multiplier = 0.30

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.96, 0.76, 0.36, 1.0)
	gold.metallic = 0.62
	gold.roughness = 0.34
	gold.emission_enabled = true
	gold.emission = Color(0.34, 0.21, 0.05, 1.0)
	gold.emission_energy_multiplier = 0.32

	var foil := StandardMaterial3D.new()
	foil.albedo_color = Color(1.0, 0.70, 0.18, 1.0)
	foil.metallic = 0.38
	foil.roughness = 0.42
	foil.emission_enabled = true
	foil.emission = Color(0.42, 0.24, 0.04, 1.0)
	foil.emission_energy_multiplier = 0.40

	var arrays := StandardMaterial3D.new()
	arrays.albedo_color = Color(0.040, 0.16, 0.52, 1.0)
	arrays.metallic = 0.42
	arrays.roughness = 0.20
	arrays.emission_enabled = true
	arrays.emission = Color(0.02, 0.11, 0.34, 1.0)
	arrays.emission_energy_multiplier = 0.72

	var thruster := StandardMaterial3D.new()
	thruster.albedo_color = Color(0.22, 0.23, 0.26, 1.0)
	thruster.metallic = 0.94
	thruster.roughness = 0.30

	var by_name := {
		"Bus": silver, "StarTracker": silver,
		"HGA": gold, "HGABoom": gold, "Yoke_L": gold, "Yoke_R": gold,
		"MLI_L": foil, "MLI_R": foil,
		"Panel_L": arrays, "Panel_R": arrays,
	}
	for child in satellite_visual.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		var key := String(piece.name)
		if by_name.has(key):
			piece.material_override = by_name[key]
		elif key.begins_with("Thr"):
			piece.material_override = thruster

func _create_rcs_thrusters() -> void:
	if not satellite_node: return
	var rcs_mat := StandardMaterial3D.new()
	rcs_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rcs_mat.emission_enabled = true
	rcs_mat.emission = Color(0.35, 0.72, 1.0, 1.0)
	rcs_mat.emission_energy_multiplier = 4.0
	for x in [-0.22, 0.22]:
		var puff := MeshInstance3D.new()
		puff.name = "RCSPuff"
		var mesh := SphereMesh.new()
		mesh.radius = 0.07
		mesh.height = 0.14
		puff.mesh = mesh
		puff.position = Vector3(x, 0.0, 0.32)
		puff.material_override = rcs_mat
		puff.hide()
		satellite_node.add_child(puff)
		rcs_thrusters.append(puff)

func _update_satellite_operations(delta: float, angle_rad: float) -> void:
	if not satellite_node: return
	# Earth-pointing attitude for an observation satellite, with small periodic
	# reaction-control corrections rather than an inert static model.
	satellite_node.look_at(Vector3.ZERO, Vector3.UP)
	attitude_pulse += delta * SimulationEngine.time_scale
	var correcting: bool = fmod(attitude_pulse, 8.0) < 0.16
	for puff in rcs_thrusters:
		puff.visible = correcting
		if correcting: puff.scale = Vector3.ONE * (0.7 + sin(attitude_pulse * 42.0) * 0.25)

	# Arrays track the sun when available; in eclipse they retain attitude and
	# the satellite visibly darkens with its real power-generation state.
	var in_eclipse: bool = SimulationEngine.state.get("in_eclipse", false)
	var target_panel_angle: float = 0.0 if not in_eclipse else 0.25
	for panel in [solar_panel_l, solar_panel_r]:
		if panel:
			panel.scale.x = lerpf(panel.scale.x, solar_deployment, min(delta * 1.8, 1.0))
			panel.rotation.z = lerpf(panel.rotation.z, target_panel_angle, min(delta * 1.4, 1.0))
			var panel_mat := panel.material_override as StandardMaterial3D
			if panel_mat:
				panel_mat.emission_energy_multiplier = 0.15 if in_eclipse else 0.85
	_update_downlink_visual()

func _update_downlink_visual() -> void:
	if not downlink_beam or not satellite_node:
		return
	if asteroid_operations:
		downlink_beam.hide()
		return
	var spacecraft_pos: Vector3 = satellite_node.global_position
	var station_pos: Vector3
	if mars_operations:
		# Deep-space operations keep the simplified contact model; there is no
		# local station network to point at, so the beam stands in for the long
		# link home and terminates at the sub-spacecraft point.
		if not SimulationEngine.state.get("ground_contact", false):
			downlink_beam.hide()
			return
		station_pos = spacecraft_pos.normalized() * earth_surface_radius * 1.02
	else:
		# The beam runs to whichever station the *simulation* currently sees the
		# vehicle above — the very same best_visible_station() that moves the
		# telemetry — so the line on screen is the reason the number on screen is
		# climbing.  It used to aim straight down at the point beneath the craft,
		# which is not a station and does not receive anything.  Eclipse no longer
		# hides it either: a dish on the night side still sees the satellite, and
		# the contact model never stopped downloading in shadow, so neither does
		# the picture.
		var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
		var visible: Dictionary = SimulationEngine.best_visible_station(alt)
		if visible.is_empty():
			downlink_beam.hide()
			return
		var station_dir: Vector3 = visible.get("direction", Vector3.ZERO)
		if station_dir.length_squared() < 0.01:
			downlink_beam.hide()
			return
		station_pos = station_dir.normalized() * earth_surface_radius
	var direction := station_pos - spacecraft_pos
	var beam_length := direction.length()
	if beam_length < 0.1:
		downlink_beam.hide()
		return
	var up_axis := Vector3.UP if abs(direction.normalized().dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	downlink_beam.show()
	downlink_beam.global_position = (spacecraft_pos + station_pos) * 0.5
	# Cylinder meshes run along local Y. Looking-at aligns -Z, then the local
	# X rotation turns that axis into the actual spacecraft-to-ground vector.
	downlink_beam.basis = Basis.looking_at(direction.normalized(), up_axis) * Basis(Vector3.RIGHT, -PI * 0.5)
	downlink_beam.scale = Vector3(1.0, beam_length * 0.5, 1.0)

# ─── Ground-station network ───────────────────────────────────────────────────
## One marker per real station in the network, placed from the same
## lat/lon→direction function the simulation uses to decide contact.  They are
## children of the globe's own frame, so as the planet turns the dishes turn with
## it and stay over their continents, and the downlink beam — which is aimed with
## that identical function — always lands on the pin it claims to be talking to.
func _build_ground_stations() -> void:
	if not earth_node:
		return
	stations_root = Node3D.new()
	stations_root.name = "GroundStationNetwork"
	earth_node.add_child(stations_root)
	for station in SimulationEngine.GROUND_STATIONS:
		var lat: float = float(station["lat"])
		var lon: float = float(station["lon"])
		var dir: Vector3 = SimulationEngine.station_local_direction(lat, lon)
		var pin := Node3D.new()
		pin.name = "Station_" + String(station["name"])
		pin.position = dir * earth_surface_radius
		stations_root.add_child(pin)
		# A short mast stood up on the local vertical, so each site reads as an
		# installed dish rather than a dot painted onto the map.
		var mast := MeshInstance3D.new()
		mast.name = "Mast"
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.015
		mast_mesh.bottom_radius = 0.055
		mast_mesh.height = 0.24
		mast_mesh.radial_segments = 8
		mast.mesh = mast_mesh
		var mmat := StandardMaterial3D.new()
		mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mmat.albedo_color = Color(0.80, 0.87, 1.0)
		mast.material_override = mmat
		mast.position = dir * 0.12
		mast.basis = Basis(Quaternion(Vector3.UP, dir))
		pin.add_child(mast)
		# A halo that brightens green for exactly as long as this station can see
		# the vehicle — the pass on the globe and the pass in the telemetry are the
		# same event, seen two ways.
		var halo := MeshInstance3D.new()
		halo.name = "ContactHalo"
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.09
		hmesh.height = 0.18
		halo.mesh = hmesh
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(0.35, 0.6, 1.0, 0.3)
		hmat.emission_enabled = true
		hmat.emission = Color(0.3, 0.6, 1.0)
		hmat.emission_energy_multiplier = 0.5
		halo.material_override = hmat
		halo.position = dir * 0.26
		pin.add_child(halo)
		var tag := Label3D.new()
		tag.text = String(station["name"])
		tag.font_size = 30
		tag.outline_size = 12
		tag.pixel_size = 0.012
		tag.modulate = Color(0.65, 0.9, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = dir * 0.55
		pin.add_child(tag)
		station_pins.append(pin)
		station_halos.append(halo)

## Repaint the network every frame from the live elevation of each station, so a
## dish glows only while it genuinely holds the satellite above ten degrees.
func _update_station_visuals() -> void:
	var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
	var stations: Array = SimulationEngine.GROUND_STATIONS
	for i in range(station_halos.size()):
		if i >= stations.size():
			break
		var halo: MeshInstance3D = station_halos[i]
		var mat := halo.material_override as StandardMaterial3D
		if mat == null:
			continue
		var el: float = SimulationEngine.station_elevation_deg(stations[i], alt)
		var holds: bool = el >= SimulationEngine.MIN_ELEVATION_DEG
		mat.emission = Color(0.2, 0.95, 0.5) if holds else Color(0.3, 0.6, 1.0)
		mat.emission_energy_multiplier = 3.4 if holds else 0.5
		mat.albedo_color.a = 0.9 if holds else 0.25
		var s: float = 1.35 if holds else 0.75
		halo.scale = Vector3.ONE * s

## One pin per real climate event, placed from the same lat/lon→direction
## calibration the stations and the simulation use, so the wildfire marker is
## genuinely over Canada and the SO₂ marker genuinely over Iceland.  Unobserved
## targets pulse cyan; once the simulation captures one it locks to green — the
## survey progress on the globe is the survey progress in the telemetry.
func _build_climate_targets() -> void:
	if not earth_node or not stations_root:
		return
	climate_root = Node3D.new()
	climate_root.name = "ClimateSurveyTargets"
	earth_node.add_child(climate_root)
	for t in SimulationEngine.CLIMATE_TARGETS:
		var dir: Vector3 = SimulationEngine.station_local_direction(float(t["lat"]), float(t["lon"]))
		var pin := Node3D.new()
		pin.name = "Target_" + String(t["name"]).replace(" ", "_")
		pin.position = dir * earth_surface_radius * 1.005
		climate_root.add_child(pin)
		var halo := MeshInstance3D.new()
		halo.name = "SurveyHalo"
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.075
		hmesh.height = 0.15
		halo.mesh = hmesh
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(0.2, 0.85, 1.0, 0.75)
		hmat.emission_enabled = true
		hmat.emission = Color(0.15, 0.75, 1.0)
		hmat.emission_energy_multiplier = 2.0
		halo.material_override = hmat
		halo.position = dir * 0.03
		pin.add_child(halo)
		var tag := Label3D.new()
		tag.text = "◉ " + String(t["name"])
		tag.font_size = 24
		tag.outline_size = 10
		tag.pixel_size = 0.010
		tag.modulate = Color(0.55, 0.9, 1.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = dir * 0.42
		pin.add_child(tag)
		climate_pins.append(pin)
		climate_halos.append(halo)

## Repaint the survey pins from the simulation's own capture state every frame,
## so "observed" means observed by the science model — not by a separate guess.
func _update_climate_target_visuals() -> void:
	var targets: Array = SimulationEngine.state.get("climate_targets", [])
	var pulse: float = sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
	for i in range(climate_halos.size()):
		if i >= targets.size():
			break
		var captured: bool = bool(targets[i].get("captured", false))
		var mat := climate_halos[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		if captured:
			mat.emission = Color(0.2, 0.95, 0.45)
			mat.albedo_color = Color(0.35, 1.0, 0.55, 0.95)
			mat.emission_energy_multiplier = 3.2
			climate_halos[i].scale = Vector3.ONE * 1.3
			for c in climate_pins[i].get_children():
				if c is Label3D:
					(c as Label3D).text = "✅ " + String(targets[i]["name"])
					(c as Label3D).modulate = Color(0.55, 1.0, 0.65)
		else:
			mat.emission = Color(0.15, 0.75, 1.0)
			mat.albedo_color = Color(0.2, 0.85, 1.0, 0.4 + pulse * 0.4)
			mat.emission_energy_multiplier = 1.2 + pulse * 1.6
			climate_halos[i].scale = Vector3.ONE * (0.85 + pulse * 0.35)

# ─── SWOT surface-water survey ────────────────────────────────────────────────
## One pin per real SWOT water site, colour-coded by surface type and placed with
## the same lat/lon→direction calibration as the stations and climate markers.
func _build_swot_water_targets() -> void:
	if not earth_node or not stations_root:
		return
	swot_root = Node3D.new()
	swot_root.name = "SwotWaterTargets"
	earth_node.add_child(swot_root)
	for t in SimulationEngine.SWOT_WATER_TARGETS:
		var cls: String = String(t["water_class"])
		var col: Color = _water_class_color(cls)
		var dir: Vector3 = SimulationEngine.station_local_direction(float(t["lat"]), float(t["lon"]))
		var pin := Node3D.new()
		pin.name = "Water_" + String(t["name"]).replace(" ", "_")
		pin.position = dir * earth_surface_radius * 1.006
		swot_root.add_child(pin)
		var halo := MeshInstance3D.new()
		halo.name = "WaterHalo"
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.07
		hmesh.height = 0.14
		halo.mesh = hmesh
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.albedo_color = Color(col.r, col.g, col.b, 0.7)
		hmat.emission_enabled = true
		hmat.emission = col
		hmat.emission_energy_multiplier = 1.8
		halo.material_override = hmat
		halo.position = dir * 0.03
		pin.add_child(halo)
		var tag := Label3D.new()
		tag.text = _water_class_label(cls) + " · " + String(t["name"])
		tag.font_size = 22
		tag.outline_size = 10
		tag.pixel_size = 0.0095
		tag.modulate = col.lightened(0.15)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = dir * 0.40
		pin.add_child(tag)
		swot_pins.append(pin)
		swot_halos.append(halo)

## Repaint the water pins from the simulation's own scan/downlink state.
func _update_swot_target_visuals() -> void:
	var targets: Array = SimulationEngine.state.get("swot_water_targets", [])
	var pulse: float = sin(Time.get_ticks_msec() * 0.004) * 0.5 + 0.5
	for i in range(swot_halos.size()):
		if i >= targets.size():
			break
		var scanned: bool = bool(targets[i].get("scanned", false))
		var downlinked: bool = bool(targets[i].get("downlinked", false))
		var cls: String = String(targets[i].get("water_class", "ocean"))
		var col: Color = _water_class_color(cls)
		var mat := swot_halos[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		if downlinked:
			mat.emission = Color(0.25, 1.0, 0.5)
			mat.albedo_color = Color(0.4, 1.0, 0.6, 0.95)
			mat.emission_energy_multiplier = 3.2
			swot_halos[i].scale = Vector3.ONE * 1.3
		elif scanned:
			mat.emission = Color(1.0, 0.75, 0.25)
			mat.albedo_color = Color(1.0, 0.82, 0.35, 0.9)
			mat.emission_energy_multiplier = 2.6
			swot_halos[i].scale = Vector3.ONE * 1.15
		else:
			mat.emission = col
			mat.albedo_color = Color(col.r, col.g, col.b, 0.35 + pulse * 0.35)
			mat.emission_energy_multiplier = 1.0 + pulse * 1.4
			swot_halos[i].scale = Vector3.ONE * (0.85 + pulse * 0.3)
		for c in swot_pins[i].get_children():
			if c is Label3D:
				var lbl := c as Label3D
				lbl.text = ("✅ " if downlinked else ("◉ " if scanned else "")) + _water_class_label(cls) + " · " + String(targets[i]["name"])
				lbl.modulate = Color(0.55, 1.0, 0.65) if downlinked else (Color(1.0, 0.85, 0.4) if scanned else col.lightened(0.15))

func _water_class_color(cls: String) -> Color:
	match cls:
		"lake":
			return Color(0.16, 0.95, 0.78)
		"river":
			return Color(0.36, 0.82, 1.0)
		_:
			return Color(0.30, 0.52, 1.0)

func _water_class_label(cls: String) -> String:
	match cls:
		"lake":
			return "LAKE"
		"river":
			return "RIVER"
		_:
			return "OCEAN"

## The visible KaRIn swath: a scan cone from the spacecraft to the sub-point and
## a footprint ring on the surface, both driven by the same geometry that decides
## which water site the simulation can see.
func _create_swot_scan_visuals() -> void:
	swot_scan_beam = MeshInstance3D.new()
	swot_scan_beam.name = "SwotKaRInScanBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.02
	beam_mesh.bottom_radius = 0.11
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 16
	swot_scan_beam.mesh = beam_mesh
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(0.16, 0.9, 0.8, 0.16)
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(0.1, 0.85, 0.75, 1.0)
	beam_mat.emission_energy_multiplier = 1.6
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	swot_scan_beam.material_override = beam_mat
	swot_scan_beam.hide()
	add_child(swot_scan_beam)

	swot_scan_ring = MeshInstance3D.new()
	swot_scan_ring.name = "SwotFootprintRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.30
	torus.outer_radius = 0.37
	torus.rings = 32
	torus.ring_segments = 8
	swot_scan_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.2, 1.0, 0.9, 0.45)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.1, 0.9, 0.8, 1.0)
	ring_mat.emission_energy_multiplier = 2.4
	swot_scan_ring.material_override = ring_mat
	swot_scan_ring.hide()
	add_child(swot_scan_ring)

func _update_swot_scan_visuals(_delta: float) -> void:
	if swot_scan_beam == null or swot_scan_ring == null or satellite_node == null:
		return
	var active: bool = bool(SimulationEngine.state.get("instruments_active", true)) \
		and not SimulationEngine.state.is_empty()
	if not active:
		swot_scan_beam.hide()
		swot_scan_ring.hide()
		return
	var sub: Vector3 = SimulationEngine.sub_point_direction()
	var surface: Vector3 = sub * earth_surface_radius
	var sat: Vector3 = satellite_node.global_position
	var direction: Vector3 = surface - sat
	var length: float = direction.length()
	if length < 0.1:
		swot_scan_beam.hide()
		swot_scan_ring.hide()
		return
	var up_axis: Vector3 = Vector3.UP if abs(direction.normalized().dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	swot_scan_beam.show()
	swot_scan_beam.global_position = (sat + surface) * 0.5
	swot_scan_beam.basis = Basis.looking_at(direction.normalized(), up_axis) * Basis(Vector3.RIGHT, -PI * 0.5)
	swot_scan_beam.scale = Vector3(0.9, length * 0.5, 0.9)
	var bmat := swot_scan_beam.material_override as StandardMaterial3D
	if bmat:
		bmat.emission_energy_multiplier = 1.3 + sin(Time.get_ticks_msec() * 0.008) * 0.5
	var pulse: float = sin(Time.get_ticks_msec() * 0.006) * 0.5 + 0.5
	swot_scan_ring.show()
	swot_scan_ring.global_position = surface + sub * 0.02
	swot_scan_ring.basis = Basis(Quaternion(Vector3.UP, sub))
	swot_scan_ring.scale = Vector3(0.9 + pulse * 0.25, 1.0, 0.9 + pulse * 0.25)

# ─── SWOT mission control room ────────────────────────────────────────────────
func _build_control_room() -> void:
	if control_room != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "SwotControlRoomLayer"
	layer.layer = 65
	add_child(layer)
	control_room = SwotControlRoomScript.new()
	control_room.name = "SwotControlRoom"
	layer.add_child(control_room)
	control_room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control_room.hide()
	control_room.connect("close_requested", _toggle_control_room)
	var controls := _g("UI/Controls")
	if controls is HBoxContainer:
		var btn := Button.new()
		btn.name = "ControlRoomButton"
		btn.text = "CONTROL ROOM [C]"
		btn.tooltip_text = "Open the SWOT ground-segment monitor wall (C)"
		MissionForge.style_button(btn, false)
		btn.add_theme_font_size_override("font_size", 12)
		controls.add_child(btn)
		btn.pressed.connect(_toggle_control_room)

func _toggle_control_room() -> void:
	if control_room == null:
		return
	control_room_open = not control_room_open
	control_room.visible = control_room_open
	if place_search_layer:
		place_search_layer.visible = not control_room_open
	if control_room_open:
		control_room_timer = 0.0
		_refresh_control_room()
		if event_popup:
			event_popup.hide()
		if pause_menu and pause_menu.visible:
			pause_menu.hide()
			SimulationEngine.paused = false

func _refresh_control_room() -> void:
	if control_room == null:
		return
	var d: Vector3 = SimulationEngine.sub_point_direction()
	var lat: float = rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var lon: float = fposmod(rad_to_deg(atan2(d.z, d.x)) - 180.0 + 180.0, 360.0) - 180.0
	var secs: int = int(SimulationEngine.elapsed_sim_seconds)
	var day: int = secs / 86400
	var hour: int = (secs % 86400) / 3600
	var minute: int = (secs % 3600) / 60
	control_room.update_data({
		"state": SimulationEngine.state,
		"clock": "T+ %dd %02dh %02dm" % [day, hour, minute],
		"sat_lat": lat,
		"sat_lon": lon,
		"time_scale": SimulationEngine.time_scale,
	})

# ─── Surface area inspection ──────────────────────────────────────────────────
## The observation globe is clickable.  A ray is cast against the same sphere
## the simulation draws, the hit point is un-rotated by the planet's current
## spin back into its geographic frame, and the camera descends onto that patch.
## The local conditions are estimated from latitude, season and the local solar
## hour derived from the sun direction already lighting the scene, so the
## terminator in the picture and the day/night state in the panel agree.
func _build_area_inspection() -> void:
	area_layer = CanvasLayer.new()
	area_layer.name = "AreaInspectionLayer"
	area_layer.layer = 58
	add_child(area_layer)

	area_hint = Label.new()
	area_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	area_hint.anchor_left = 1.0
	area_hint.anchor_top = 1.0
	area_hint.anchor_right = 1.0
	area_hint.anchor_bottom = 1.0
	area_hint.offset_left = -620.0
	area_hint.offset_top = -44.0
	area_hint.offset_right = -18.0
	area_hint.offset_bottom = -16.0
	area_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	area_hint.text = "Click Earth to inspect an area  ·  Scroll to zoom  ·  Right-click to exit"
	area_hint.add_theme_font_size_override("font_size", 12)
	area_hint.add_theme_color_override("font_color", Color("#B3B3B3"))
	area_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area_hint.visible = false
	area_layer.add_child(area_hint)

	area_panel = PanelContainer.new()
	area_panel.name = "AreaInspectionPanel"
	area_panel.anchor_left = 1.0
	area_panel.anchor_right = 1.0
	area_panel.offset_left = -410.0
	area_panel.offset_right = -18.0
	area_panel.offset_top = 64.0
	area_panel.offset_bottom = 560.0
	area_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.94)
	sb.border_color = Color("#333333")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 15.0
	sb.content_margin_right = 15.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	area_panel.add_theme_stylebox_override("panel", sb)
	area_layer.add_child(area_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	area_panel.add_child(v)

	var title := Label.new()
	title.text = "AREA INSPECTION"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("#FFFFFF"))
	v.add_child(title)

	area_coords = Label.new()
	area_coords.add_theme_font_size_override("font_size", 16)
	area_coords.add_theme_color_override("font_color", Color("#FFFFFF"))
	v.add_child(area_coords)

	area_place = Label.new()
	area_place.name = "AreaPlaceLabel"
	area_place.add_theme_font_size_override("font_size", 13)
	area_place.add_theme_color_override("font_color", Color("#B3B3B3"))
	area_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_place)

	area_temp = Label.new()
	area_temp.add_theme_font_size_override("font_size", 34)
	v.add_child(area_temp)

	area_weather = Label.new()
	area_weather.add_theme_font_size_override("font_size", 15)
	area_weather.add_theme_color_override("font_color", Color("#FFFFFF"))
	area_weather.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_weather)

	area_wind = Label.new()
	area_wind.add_theme_font_size_override("font_size", 13)
	area_wind.add_theme_color_override("font_color", Color("#B3B3B3"))
	area_wind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_wind)

	area_solar = Label.new()
	area_solar.add_theme_font_size_override("font_size", 13)
	area_solar.add_theme_color_override("font_color", Color("#B3B3B3"))
	area_solar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_solar)

	area_site = Label.new()
	area_site.add_theme_font_size_override("font_size", 11)
	area_site.add_theme_color_override("font_color", Color("#777777"))
	area_site.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_site)

	area_source = Label.new()
	area_source.add_theme_font_size_override("font_size", 11)
	area_source.add_theme_color_override("font_color", Color("#777777"))
	area_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(area_source)

	area_zoom_label = Label.new()
	area_zoom_label.add_theme_font_size_override("font_size", 12)
	area_zoom_label.add_theme_color_override("font_color", Color("#777777"))
	v.add_child(area_zoom_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	v.add_child(buttons)
	var zoom_in := Button.new()
	zoom_in.text = "Zoom +"
	zoom_in.tooltip_text = "Zoom in on this area (mouse wheel up)"
	zoom_in.add_theme_font_size_override("font_size", 12)
	zoom_in.pressed.connect(func(): _zoom_step(1.0))
	_apply_blue_button_theme(zoom_in)
	buttons.add_child(zoom_in)
	var zoom_out := Button.new()
	zoom_out.text = "Zoom −"
	zoom_out.tooltip_text = "Zoom out (mouse wheel down)"
	zoom_out.add_theme_font_size_override("font_size", 12)
	zoom_out.pressed.connect(func(): _zoom_step(-1.0))
	_apply_blue_button_theme(zoom_out)
	buttons.add_child(zoom_out)
	var back := Button.new()
	back.text = "BACK TO ORBIT"
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(_exit_area_inspection)
	_apply_orange_button_theme(back)
	buttons.add_child(back)

	var note := Label.new()
	note.text = "Temperature and weather are estimated from the area's latitude, season and local solar time — the same sunlight the orbit is flying through."
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color("#777777"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)

	_load_world_places()
	_build_place_search()

func _apply_blue_button_theme(btn: Button) -> void:
	MissionForge.style_button(btn, false)

func _apply_orange_button_theme(btn: Button) -> void:
	MissionForge.style_button(btn, true)

func _load_world_places() -> void:
	if not world_places.is_empty():
		return
	var file := FileAccess.open(WORLD_PLACES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.has("cities"):
		world_places = parsed["cities"]

func _build_place_search() -> void:
	if place_search_layer != null:
		return
	place_search_layer = CanvasLayer.new()
	place_search_layer.name = "PlaceSearchLayer"
	place_search_layer.layer = 59
	add_child(place_search_layer)

	var box := VBoxContainer.new()
	box.name = "PlaceSearchBox"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -225.0
	box.offset_right = 225.0
	box.offset_top = 10.0
	box.offset_bottom = 52.0
	box.add_theme_constant_override("separation", 4)
	place_search_layer.add_child(box)

	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.95)
	sb.border_color = Color("#333333")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	bar.add_theme_stylebox_override("panel", sb)
	box.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	place_search_edit = LineEdit.new()
	place_search_edit.name = "PlaceSearchEdit"
	place_search_edit.placeholder_text = "Search any city or place…"
	place_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_search_edit.add_theme_font_size_override("font_size", 14)
	place_search_edit.add_theme_color_override("font_color", Color("#FFFFFF"))
	place_search_edit.add_theme_color_override("font_placeholder_color", Color("#777777"))
	row.add_child(place_search_edit)

	var go := Button.new()
	go.text = "SEARCH"
	go.add_theme_font_size_override("font_size", 12)
	_apply_orange_button_theme(go)
	go.pressed.connect(_on_place_search_submit)
	row.add_child(go)

	place_results = ItemList.new()
	place_results.name = "PlaceSearchResults"
	place_results.custom_minimum_size = Vector2(0, 210)
	place_results.add_theme_font_size_override("font_size", 13)
	place_results.add_theme_color_override("font_color", Color("#FFFFFF"))
	place_results.add_theme_color_override("font_selected_color", Color("#FFFFFF"))
	place_results.add_theme_color_override("font_hovered_color", Color("#B3B3B3"))
	place_results.add_theme_stylebox_override("panel", sb)
	place_results.visible = false
	box.add_child(place_results)

	place_search_edit.text_changed.connect(_on_place_query_changed)
	place_search_edit.text_submitted.connect(func(_t): _on_place_search_submit())
	place_results.item_selected.connect(_choose_place_by_index)

func _on_place_query_changed(query: String) -> void:
	var q: String = query.strip_edges().to_lower()
	if q.length() < 2 or world_places.is_empty():
		place_results.clear()
		place_results.visible = false
		return
	var matches: Array = []
	for i in range(world_places.size()):
		var score: int = _place_match_score(world_places[i], q)
		if score >= 0:
			matches.append({"i": i, "score": score, "pop": int(world_places[i][6])})
	matches.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		return a["pop"] > b["pop"])
	place_results.clear()
	var count: int = mini(matches.size(), 8)
	for k in range(count):
		var city: Array = world_places[matches[k]["i"]]
		var label := String(city[0])
		if String(city[3]) != "":
			label += " · " + String(city[3])
		label += ", " + String(city[2])
		place_results.add_item(label)
		place_results.set_item_metadata(k, matches[k]["i"])
	place_results.visible = count > 0

func _place_match_score(city: Array, q: String) -> int:
	var display_name: String = String(city[0]).to_lower()
	var keys: String = String(city[1])
	if display_name == q:
		return 0
	if display_name.begins_with(q):
		return 1
	if ("|" + keys + "|").contains("|" + q + "|"):
		return 1
	if keys.begins_with(q) or keys.contains("|" + q):
		return 2
	if display_name.contains(q):
		return 3
	if keys.contains(q):
		return 4
	return -1

func _on_place_search_submit() -> void:
	_on_place_query_changed(place_search_edit.text)
	if place_results.visible and place_results.item_count > 0:
		_choose_place_by_index(0)

func _choose_place_by_index(index: int) -> void:
	if index < 0 or index >= place_results.item_count:
		return
	var city_index = place_results.get_item_metadata(index)
	if city_index == null:
		return
	var city: Array = world_places[int(city_index)]
	var chosen := {
		"name": String(city[0]),
		"region": String(city[3]),
		"country": String(city[2]),
		"lat": float(city[4]),
		"lon": float(city[5]),
	}
	place_results.visible = false
	place_search_edit.text = ""
	place_search_edit.release_focus()
	_begin_area_inspection(float(city[4]), float(city[5]), chosen)

## Nearest bundled settlement to a clicked patch, so a click reports a real
## place name instead of only a coordinate.  Beyond 1,200 km the patch is
## honestly reported as remote.
func _nearest_place(lat: float, lon: float) -> Dictionary:
	if world_places.is_empty():
		return {}
	var plat: float = deg_to_rad(lat)
	var plon: float = deg_to_rad(lon)
	var px: float = cos(plat) * cos(plon)
	var py: float = sin(plat)
	var pz: float = cos(plat) * sin(plon)
	var best: Array = []
	var best_angle: float = PI
	for city in world_places:
		var clat: float = deg_to_rad(float(city[4]))
		var clon: float = deg_to_rad(float(city[5]))
		var dot: float = clampf(
			px * cos(clat) * cos(clon) + py * sin(clat) + pz * cos(clat) * sin(clon),
			-1.0, 1.0)
		var angle: float = acos(dot)
		if angle < best_angle:
			best_angle = angle
			best = city
	var km: float = best_angle * 6371.0
	if km > PLACE_NAME_KM:
		return {}
	return {
		"name": String(best[0]),
		"region": String(best[3]),
		"country": String(best[2]),
		"lat": float(best[4]),
		"lon": float(best[5]),
		"distance_km": km,
	}

func _place_label(place: Dictionary, near: bool) -> String:
	var label := String(place.get("name", ""))
	if String(place.get("region", "")) != "":
		label += " · " + String(place.get("region", ""))
	label += ", " + String(place.get("country", ""))
	if near:
		label = "Near " + label + "  ·  %.0f km away" % float(place.get("distance_km", 0.0))
	return label

func _unhandled_input(event: InputEvent) -> void:
	if arrival_active or SimulationEngine.paused or control_room_open:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if GameManager.is_earth_climate_mission() and fly_time <= 0.0:
				_pick_surface_area(mb.position)
		MOUSE_BUTTON_RIGHT:
			_exit_area_inspection()
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(1.0, mb.position)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(-1.0, mb.position)
			get_viewport().set_input_as_handled()

## Total yaw between the globe's geographic frame and world space: the sim's
## sidereal spin plus any residual node rotation.  Clicks and the inspection
## camera both invert/apply this, so the marker and the readout agree with the
## patch under the cursor.
func _earth_world_angle() -> float:
	return SimulationEngine.earth_rotation_rad + (earth_node.rotation.y if earth_node else 0.0)

func _pick_surface_area(screen_pos: Vector2) -> void:
	if mission_camera == null:
		return
	var origin: Vector3 = mission_camera.project_ray_origin(screen_pos)
	var direction: Vector3 = mission_camera.project_ray_normal(screen_pos).normalized()
	var radius: float = earth_surface_radius
	var b: float = origin.dot(direction)
	var c: float = origin.dot(origin) - radius * radius
	var disc: float = b * b - c
	if disc < 0.0:
		return
	var t: float = -b - sqrt(disc)
	if t <= 0.0:
		return
	var hit: Vector3 = origin + direction * t
	var local: Vector3 = hit.rotated(Vector3.UP, -_earth_world_angle())
	var lat: float = rad_to_deg(asin(clampf(local.y / radius, -1.0, 1.0)))
	var lon: float = wrapf(rad_to_deg(atan2(local.z, local.x)) - 180.0, -180.0, 180.0)
	_begin_area_inspection(lat, lon)

func _begin_area_inspection(lat: float, lon: float, chosen_place: Dictionary = {}) -> void:
	if area_panel == null:
		_build_area_inspection()
	inspect_active = true
	inspect_lat = lat
	inspect_lon = lon
	inspect_place_override = chosen_place
	inspect_place = chosen_place if not chosen_place.is_empty() else _nearest_place(lat, lon)
	camera_return_timer = 0.0
	inspect_timer = 0.0
	# An event flyover owns the camera and the right-hand screen space; close it
	# so the inspection readout can never hide behind the event card.
	if fly_panel:
		fly_panel.visible = false
	fly_time = 0.0
	area_panel.visible = true
	area_hint.visible = false
	if inspect_root == null:
		_build_inspect_marker()
	var dir: Vector3 = SimulationEngine.station_local_direction(lat, lon)
	inspect_pin.position = dir * earth_surface_radius * 1.004
	inspect_pin.visible = true
	if inspect_ring:
		inspect_ring.basis = Basis(Quaternion(Vector3.UP, dir))
		inspect_ring.position = dir * 0.03
	if inspect_tag:
		inspect_tag.position = dir * 0.42
	_update_area_readout()

func _build_inspect_marker() -> void:
	inspect_root = Node3D.new()
	inspect_root.name = "SurfaceInspector"
	earth_node.add_child(inspect_root)
	inspect_pin = Node3D.new()
	inspect_pin.name = "InspectPin"
	inspect_root.add_child(inspect_pin)

	inspect_ring = MeshInstance3D.new()
	inspect_ring.name = "InspectRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.105
	ring.outer_radius = 0.145
	ring.rings = 32
	ring.ring_segments = 8
	inspect_ring.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.55, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.45, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	inspect_ring.material_override = mat
	inspect_pin.add_child(inspect_ring)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.045
	core_mesh.height = 0.09
	core.mesh = core_mesh
	core.material_override = mat
	inspect_pin.add_child(core)

	inspect_tag = Label3D.new()
	inspect_tag.font_size = 28
	inspect_tag.outline_size = 12
	inspect_tag.pixel_size = 0.010
	inspect_tag.modulate = Color(0.78, 0.88, 1.0)
	inspect_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	inspect_tag.no_depth_test = true
	inspect_pin.add_child(inspect_tag)

func _exit_area_inspection() -> void:
	if not inspect_active:
		return
	inspect_active = false
	if area_panel:
		area_panel.visible = false
	if area_hint:
		area_hint.visible = true
	if inspect_pin:
		inspect_pin.visible = false
	camera_return_timer = 1.3
	_reset_orbit_view()

func _zoom_step(direction: float, screen_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if inspect_active:
		# Constant-ratio zoom keeps the same feel from 6,300 km down to 300 km.
		inspect_distance = clampf(inspect_distance * pow(0.82, direction), 0.28, 6.0)
		_update_area_readout()
		return
	# Exterior view: dolly the camera instead of only narrowing the lens, so
	# the surface actually resolves more detail as the player zooms in.
	view_distance_target = clampf(
		view_distance_target * pow(0.84, direction),
		VIEW_MIN_DISTANCE, VIEW_MAX_DISTANCE)
	if direction > 0.0:
		var pos: Vector2 = screen_pos
		if pos.x < 0.0:
			pos = get_viewport().get_mouse_position()
		var hit: Vector3 = _earth_hit_direction(pos)
		if hit != Vector3.ZERO:
			# Anchor the focus in the globe's own frame so it keeps tracking the
			# same patch while the planet spins underneath the camera.
			view_focus_local = hit.rotated(Vector3.UP, -_earth_world_angle()).normalized()
	elif view_distance_target >= VIEW_MAX_DISTANCE * 0.94:
		view_focus_local = Vector3.ZERO

## A ray/globe intersection in world space.  Returns the unit direction of the
## surface point under the cursor, or ZERO when the cursor misses the planet.
func _earth_hit_direction(screen_pos: Vector2) -> Vector3:
	if mission_camera == null:
		return Vector3.ZERO
	var origin: Vector3 = mission_camera.project_ray_origin(screen_pos)
	var ray: Vector3 = mission_camera.project_ray_normal(screen_pos).normalized()
	var radius: float = earth_surface_radius
	var b: float = origin.dot(ray)
	var c: float = origin.length_squared() - radius * radius
	var disc: float = b * b - c
	if disc <= 0.0:
		return Vector3.ZERO
	var t: float = -b - sqrt(disc)
	if t <= 0.0:
		t = -b + sqrt(disc)
	if t <= 0.0:
		return Vector3.ZERO
	return (origin + ray * t).normalized()

func _reset_orbit_view() -> void:
	view_distance = VIEW_HOME_DISTANCE
	view_distance_target = VIEW_HOME_DISTANCE
	view_dir = VIEW_HOME.normalized()
	view_focus_local = Vector3.ZERO
	view_fov = 60.0

func _update_area_inspection(delta: float) -> void:
	if fly_time > 0.0:
		return
	if inspect_active and mission_camera:
		inspect_timer -= delta
		if inspect_timer <= 0.0:
			inspect_timer = 0.25
			_update_area_readout()
		if inspect_ring:
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			inspect_ring.scale = Vector3.ONE * (1.0 + pulse * 0.22)
		_update_inspect_camera(delta)
	elif camera_return_timer > 0.0 and mission_camera:
		camera_return_timer -= delta
		var home := VIEW_HOME
		mission_camera.global_position = mission_camera.global_position.lerp(home, minf(delta * 2.4, 1.0))
		mission_camera.look_at(Vector3.ZERO, Vector3.UP)
		mission_camera.fov = lerpf(mission_camera.fov, 60.0, minf(delta * 3.0, 1.0))
	elif mission_camera:
		_update_exterior_camera(delta)

## Smoothly flies the free exterior camera to its dollied radius and to the
## cursor-anchored patch.  The globe keeps filling the frame at every distance.
func _update_exterior_camera(delta: float) -> void:
	var home_dir: Vector3 = VIEW_HOME.normalized()
	var want_dir: Vector3 = home_dir
	if view_focus_local != Vector3.ZERO:
		want_dir = view_focus_local.rotated(Vector3.UP, _earth_world_angle()).normalized()
	view_dir = view_dir.slerp(want_dir, clampf(delta * 2.6, 0.0, 1.0)).normalized()
	view_distance = lerpf(view_distance, view_distance_target, clampf(delta * 6.0, 0.0, 1.0))
	var closeness: float = clampf(
		(VIEW_HOME_DISTANCE - view_distance) / (VIEW_HOME_DISTANCE - VIEW_MIN_DISTANCE),
		0.0, 1.0)
	var look: Vector3 = view_dir * earth_surface_radius if view_focus_local != Vector3.ZERO else Vector3.ZERO
	mission_camera.global_position = view_dir * view_distance
	var up: Vector3 = Vector3.UP
	if absf(view_dir.dot(Vector3.UP)) > 0.97:
		up = Vector3.RIGHT
	mission_camera.look_at(look, up)
	mission_camera.fov = lerpf(mission_camera.fov, lerpf(60.0, 52.0, closeness), minf(delta * 4.0, 1.0))

func _update_inspect_camera(delta: float) -> void:
	var local_dir: Vector3 = SimulationEngine.station_local_direction(inspect_lat, inspect_lon)
	var dir: Vector3 = local_dir.rotated(Vector3.UP, _earth_world_angle()).normalized()
	var target: Vector3 = dir * earth_surface_radius
	var tangent: Vector3 = Vector3.UP.cross(dir)
	if tangent.length_squared() < 0.02:
		tangent = Vector3.RIGHT
	tangent = tangent.normalized()
	var cam_pos: Vector3 = target + dir * inspect_distance + tangent * (inspect_distance * 0.28)
	mission_camera.global_position = mission_camera.global_position.lerp(cam_pos, minf(delta * 3.2, 1.0))
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.93:
		up = tangent
	mission_camera.look_at(target, up)
	mission_camera.fov = lerpf(mission_camera.fov, 40.0, minf(delta * 4.0, 1.0))

func _hash01(v: float) -> float:
	return fposmod(sin(v * 12.9898 + 4.1414) * 43758.5453, 1.0)

## Deterministic local conditions for a geographic point.  Latitude sets the
## base climate, the day of the year sets the season, and the point's angle
## away from the sun direction already lighting the scene sets the local solar
## hour and therefore the diurnal swing.  No network call, no random flicker.
func _surface_conditions(lat: float, lon: float) -> Dictionary:
	var day: int = int(SimulationEngine.state.get("day", 0))
	var abs_lat: float = absf(lat)
	var local: Vector3 = SimulationEngine.station_local_direction(lat, lon)
	var world: Vector3 = local.rotated(Vector3.UP, SimulationEngine.earth_rotation_rad)
	var sun_dir := Vector3(1.0, 0.0, 0.0)
	if sun_light:
		sun_dir = sun_light.global_transform.basis.z.normalized()
	var sun_az: float = atan2(sun_dir.z, sun_dir.x)
	var point_az: float = atan2(world.z, world.x)
	var hour_angle: float = wrapf(rad_to_deg(point_az - sun_az), -180.0, 180.0)
	var solar_hour: float = fposmod(12.0 - hour_angle / 15.0, 24.0)
	var daylight: bool = absf(hour_angle) < 90.0

	var h1: float = _hash01(lat * 7.13 + lon * 3.71 + day * 0.63)
	var h2: float = _hash01(lat * 11.7 + lon * 5.37 + day * 1.7 + 9.23)
	var h3: float = _hash01(lat * 3.19 + lon * 13.3 + day * 2.3 + 41.7)
	var humidity: float = clampf(0.28 + h2 * 0.55 + absf(sin(deg_to_rad(lat * 1.7))) * 0.12, 0.18, 0.97)
	var cloud: float = clampf(h1 * 0.85 + (humidity - 0.55) * 0.5, 0.0, 1.0)
	var base: float = 27.0 - 46.0 * pow(abs_lat / 90.0, 1.35)
	var season: float = -8.0 * cos(TAU * (float(day) + 40.0) / 365.0) * signf(lat)
	var diurnal: float = 5.8 * cos(deg_to_rad((solar_hour - 14.0) * 15.0))
	var temp: float = base + season + diurnal * (1.0 - cloud * 0.25) - cloud * 1.8 + (h3 - 0.5) * 2.0 + 1.0

	var condition := "Clear sky"
	if temp <= 0.5 and cloud > 0.45:
		condition = "Snow"
	elif cloud > 0.8:
		condition = "Thunderstorm" if (h2 > 0.6 and temp > 17.0) else "Heavy rain"
	elif cloud > 0.6:
		condition = "Rain showers"
	elif cloud > 0.38:
		condition = "Overcast"
	elif cloud > 0.18:
		condition = "Partly cloudy"

	return {
		"temp_c": temp,
		"condition": condition,
		"cloud_pct": int(round(cloud * 100.0)),
		"humidity_pct": int(round(humidity * 100.0)),
		"wind_kmh": 6.0 + h1 * h1 * 42.0,
		"solar_hour": solar_hour,
		"daylight": daylight,
		"site": _nearest_survey_site(lat, lon),
	}

func _nearest_survey_site(lat: float, lon: float) -> Dictionary:
	var best: Dictionary = {}
	var best_sep: float = 9.0
	var local: Vector3 = SimulationEngine.station_local_direction(lat, lon)
	for group in [SimulationEngine.CLIMATE_TARGETS, SimulationEngine.SWOT_WATER_TARGETS]:
		for t in group:
			var site_dir: Vector3 = SimulationEngine.station_local_direction(float(t["lat"]), float(t["lon"]))
			var sep: float = rad_to_deg(local.angle_to(site_dir))
			if sep < best_sep:
				best_sep = sep
				best = t
	if best.is_empty():
		return {}
	var out: Dictionary = best.duplicate(true)
	out["separation_deg"] = best_sep
	return out

func _update_area_readout() -> void:
	if area_panel == null or not inspect_active:
		return
	inspect_conditions = _surface_conditions(inspect_lat, inspect_lon)
	var lat_txt: String = "%.1f°%s" % [absf(inspect_lat), "N" if inspect_lat >= 0.0 else "S"]
	var lon_txt: String = "%.1f°%s" % [absf(inspect_lon), "E" if inspect_lon >= 0.0 else "W"]
	area_coords.text = "%s  ·  %s" % [lat_txt, lon_txt]
	if inspect_place.is_empty():
		area_place.text = "Remote area — no settlement within 1,200 km"
		area_place.add_theme_color_override("font_color", Color("#777777"))
	else:
		area_place.text = _place_label(inspect_place, inspect_place_override.is_empty())
		area_place.add_theme_color_override("font_color", Color("#B3B3B3"))
	var temp: float = float(inspect_conditions["temp_c"])
	area_temp.text = "%.1f °C" % temp
	area_temp.add_theme_color_override("font_color",
		Color("#B3B3B3") if temp < 5.0 else Color("#D9D9D9") if temp > 30.0 else Color("#FFFFFF"))
	area_weather.text = "%s  ·  cloud cover %d%%" % [inspect_conditions["condition"], inspect_conditions["cloud_pct"]]
	area_wind.text = "Wind %.0f km/h  ·  humidity %d%%" % [inspect_conditions["wind_kmh"], inspect_conditions["humidity_pct"]]
	var solar_hour: float = float(inspect_conditions["solar_hour"])
	var solar_txt: String = "%02d:%02d" % [int(solar_hour), int(fposmod(solar_hour, 1.0) * 60.0)]
	area_solar.text = "Local solar time %s  ·  %s" % [solar_txt, "daylight" if inspect_conditions["daylight"] else "night side"]
	var site: Dictionary = inspect_conditions.get("site", {})
	if site.is_empty():
		area_site.text = "Open patch — no named survey site within 9°"
		area_source.text = "No NASA mission record here — temperature/weather is the in-game model, not a live feed"
	else:
		area_site.text = "Near %s  ·  %.1f° away\n%s" % [site.get("name", ""), float(site.get("separation_deg", 0.0)), site.get("stat", "")]
		area_source.text = "Site data: %s  ·  %s\nTemp/weather: in-game estimate, not a live mission feed" % [site.get("source", ""), site.get("sensor", "")]
	var view_alt_km: float = inspect_distance * 6371.0 / earth_surface_radius
	area_zoom_label.text = "View altitude ≈ %.0f km  ·  scroll or ± to zoom" % view_alt_km
	if inspect_tag:
		inspect_tag.text = "%.0f°C · %s" % [temp, inspect_conditions["condition"]]

# ─── Commissioning: the two climate-survey revolutions ────────────────────────
## Once the satellite is deployed it does not simply hand over to the free-running
## simulation: the first thing a climate sentinel must prove is that it can come
## all the way round twice and get its observations off to the ground.  So the
## operations screen opens on that, flown at 600× so two ninety-five-minute
## revolutions read as twenty seconds of film rather than three hours of waiting,
## and said out loud on the banner because a clock that names its own compression
## is honest and one that hides it is not.
func _begin_commissioning() -> void:
	if mars_operations or asteroid_operations:
		return
	if commissioning_active or commission_complete:
		return
	commissioning_active = true
	commission_start_orbits = int(SimulationEngine.state.get("total_orbits", 0))
	commission_revs_done = 0
	commission_passes = 0
	commission_mb = 0.0
	_last_contact = bool(SimulationEngine.state.get("ground_contact", false))
	_build_commissioning_overlay()
	if commission_overlay:
		commission_overlay.show()
	SimulationEngine.set_time_scale(3)   # 600× — TIME_SCALES index 3
	_update_speed_buttons(3)

func _update_commissioning() -> void:
	var orbits: int = int(SimulationEngine.state.get("total_orbits", 0))
	commission_revs_done = orbits - commission_start_orbits
	# A downlink is complete when the station loses the vehicle: everything the
	# dish collected between acquisition and loss came off in that one pass.
	var contact: bool = bool(SimulationEngine.state.get("ground_contact", false))
	if _last_contact and not contact:
		commission_passes += 1
	_last_contact = contact
	commission_mb = float(SimulationEngine.state.get("data_transmitted_mb", 0.0))
	if commission_overlay and commission_title and commission_detail:
		var rev: int = clampi(commission_revs_done + 1, 1, COMMISSION_TARGET_REVS)
		commission_title.text = "CLIMATE SURVEY COMMISSIONING — REVOLUTION %d OF %d" % [rev, COMMISSION_TARGET_REVS]
		var st_name: String = String(SimulationEngine.state.get("ground_station_name", ""))
		if st_name == "":
			st_name = "no station in view"
		commission_detail.text = "Now talking to %s   ·   Passes returned: %d   ·   Climate data downlinked: %.0f MB   ·   600× time" % [
			st_name, commission_passes, commission_mb]
	if commission_revs_done >= COMMISSION_TARGET_REVS:
		_finish_commissioning()

func _finish_commissioning() -> void:
	commissioning_active = false
	commission_complete = true
	SimulationEngine.state["commission_revolutions"] = commission_revs_done
	SimulationEngine.state["commission_passes"] = commission_passes
	GameManager.simulation_state["climate_commissioning_complete"] = true
	GameManager.simulation_state["commission_revolutions"] = commission_revs_done
	GameManager.simulation_state["commission_ground_passes"] = commission_passes
	if commission_title:
		commission_title.text = "COMMISSIONING COMPLETE"
	if commission_detail:
		commission_detail.text = "Two revolutions flown, %d station passes, %.0f MB of climate data returned to Earth." % [
			commission_passes, commission_mb]
	SimulationEngine._log_event("✅ Commissioning complete — %d revolutions, climate data returned from the ground-station network." %
		commission_revs_done, "success")
	_collapse_commission_overlay.call_deferred()

## Leave the finished banner up long enough to be read, then take it away so the
## operator's own dashboard is not permanently covered by a message that has
## already been delivered.
func _collapse_commission_overlay() -> void:
	await get_tree().create_timer(5.0).timeout
	if commission_overlay:
		commission_overlay.hide()

func _build_commissioning_overlay() -> void:
	if commission_overlay:
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	commission_overlay = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.039, 0.039, 0.039, 0.88)
	box.border_color = Color("#333333")
	box.set_border_width_all(1)
	box.set_content_margin_all(14)
	commission_overlay.add_theme_stylebox_override("panel", box)
	layer.add_child(commission_overlay)
	commission_overlay.set_anchors_preset(Control.PRESET_TOP_WIDE)
	commission_overlay.offset_left = 0.0
	commission_overlay.offset_right = 0.0
	commission_overlay.offset_top = 96.0
	commission_overlay.offset_bottom = 96.0 + 96.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	commission_overlay.add_child(v)
	commission_title = Label.new()
	commission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commission_title.add_theme_font_size_override("font_size", 22)
	commission_title.add_theme_color_override("font_color", Color("#FFFFFF"))
	v.add_child(commission_title)
	commission_detail = Label.new()
	commission_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commission_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	commission_detail.add_theme_font_size_override("font_size", 15)
	commission_detail.add_theme_color_override("font_color", Color("#B3B3B3"))
	v.add_child(commission_detail)
	MissionForge.live(commission_detail)
	commission_overlay.hide()

func _create_starfield() -> void:
	# Low-cost hand-placed stars give depth without a large panorama texture.
	# They are intentionally subtle so they do not compete with Earth or the HUD.
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.025
	star_mesh.height = 0.05
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.72, 0.82, 1.0, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.32, 0.52, 1.0, 1.0)
	star_mat.emission_energy_multiplier = 1.8
	star_mesh.material = star_mat
	var stars := Node3D.new()
	stars.name = "CinematicStarfield"
	add_child(stars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in 120:
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.65, 0.65), rng.randf_range(-1.0, 1.0)).normalized()
		star.position = direction * rng.randf_range(22.0, 36.0)
		var s := rng.randf_range(0.65, 2.2)
		star.scale = Vector3.ONE * s
		stars.add_child(star)

func _begin_orbit_arrival() -> void:
	# The operations screen is intentionally withheld until the player has seen
	# their spacecraft reach orbit and separate from the launch vehicle.
	arrival_active = true
	arrival_timer = 0.0
	_set_operations_visible(false)
	if place_search_layer:
		place_search_layer.visible = false
	if arrival_overlay: arrival_overlay.show()
	if mission_camera:
		mission_camera.position = Vector3(0.0, 3.0, 24.0)
		mission_camera.fov = 48.0
		mission_camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

func _create_arrival_fade() -> void:
	# The launch scene finishes on black. Fade this matching orbital view in so
	# the player perceives one continuous mission rather than a scene switch.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	arrival_fade = ColorRect.new()
	arrival_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrival_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrival_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	layer.add_child(arrival_fade)

func _finish_orbit_arrival() -> void:
	arrival_active = false
	if arrival_overlay: arrival_overlay.hide()
	# If the film is skipped rather than played out, the black fade is still
	# part-way opaque; clearing it here keeps the operations view at full
	# brightness instead of leaving a grey wash over the whole screen.
	if arrival_fade:
		arrival_fade.color = Color(0.0, 0.0, 0.0, 0.0)
		arrival_fade.hide()
	# The arrival film nudged the whole Earth node for a slow cinematic turn.
	# Once operations begin only the simulation's sidereal spin may move the
	# globe, or every lat/lon picked off the texture would inherit that offset.
	if earth_node:
		earth_node.rotation.y = 0.0
	_set_operations_visible(true)
	if place_search_layer:
		place_search_layer.visible = true
	if area_hint:
		area_hint.visible = true
	_reset_orbit_view()
	if mission_camera:
		# Clear complete-Earth shot. It is deliberately pulled back from the
		# satellite rather than attempting an extreme close external camera.
		mission_camera.position = Vector3(-11.5, 7.5, 14.5)
		mission_camera.fov = 60.0
		mission_camera.look_at(Vector3.ZERO, Vector3.UP)
	# The deployment is not the end of the story for a climate satellite: it has
	# to prove it can circle the planet and get the data home.  Open on that.
	_begin_commissioning()

func _set_operations_visible(is_visible: bool) -> void:
	for path in ["UI/HUD", "UI/TelemetryPanel", "UI/EventLog", "UI/Controls"]:
		var node := _g(path) as CanvasItem
		if node: node.visible = is_visible

func _update_orbit_camera_composition() -> void:
	# A low-Earth-orbit exterior camera sits beside the spacecraft and looks
	# diagonally over its shoulder toward Earth. At 550 km, Earth should fill
	# most of the lower view as a curved horizon—not appear as a small toy globe.
	if not mission_camera or not satellite_node:
		return
	var radial := satellite_node.global_position.normalized()
	var tangent := Vector3.UP.cross(radial)
	if tangent.length_squared() < 0.01:
		tangent = Vector3.RIGHT
	else:
		tangent = tangent.normalized()
	# Keep several spacecraft lengths of separation: the prior close position
	# filled the screen with a solar panel and hid the Earth horizon.
	var desired_camera := satellite_node.global_position + radial * 4.0 + tangent * 4.8 + Vector3.UP * 1.2
	var desired_target := satellite_node.global_position - radial * 3.9 - tangent * 0.55
	mission_camera.position = mission_camera.position.lerp(desired_camera, 0.045)
	mission_camera.look_at(desired_target, Vector3.UP)

# ─── Per-Frame Update ─────────────────────────────────────────────────────────
## The right-hand data card that opens when a real event is sensed. Built
## once, hidden until a capture happens; every field is filled from the
## simulation's own target record, never re-typed here.
func _build_climate_flyover_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ClimateFlyoverLayer"
	layer.layer = 60
	add_child(layer)
	fly_panel = PanelContainer.new()
	fly_panel.anchor_left = 1.0
	fly_panel.anchor_right = 1.0
	fly_panel.offset_left = -660.0
	fly_panel.offset_right = -24.0
	fly_panel.offset_top = 70.0
	fly_panel.offset_bottom = 0.0
	fly_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#151515")
	sb.border_color = Color("#333333")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	fly_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(fly_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	fly_panel.add_child(box)
	fly_head = Label.new()
	fly_head.text = "REAL DATA RETURNED FROM ORBIT"
	fly_head.add_theme_color_override("font_color", Color("#FFFFFF"))
	fly_head.add_theme_font_size_override("font_size", 18)
	box.add_child(fly_head)
	fly_image = TextureRect.new()
	fly_image.custom_minimum_size = Vector2(590, 330)
	fly_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	box.add_child(fly_image)
	fly_title = Label.new()
	fly_title.add_theme_color_override("font_color", Color("#FFFFFF"))
	fly_title.add_theme_font_size_override("font_size", 20)
	fly_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_title)
	fly_subtitle = Label.new()
	fly_subtitle.add_theme_color_override("font_color", Color("#B3B3B3"))
	fly_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_subtitle)
	fly_stat = Label.new()
	fly_stat.add_theme_color_override("font_color", Color("#FFFFFF"))
	fly_stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_stat)
	fly_credit = Label.new()
	fly_credit.add_theme_color_override("font_color", Color("#777777"))
	fly_credit.add_theme_font_size_override("font_size", 13)
	fly_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(fly_credit)
	fly_status = Label.new()
	fly_status.add_theme_color_override("font_color", Color("#B3B3B3"))
	fly_status.add_theme_font_size_override("font_size", 13)
	box.add_child(fly_status)

func _begin_climate_flyover(t: Dictionary) -> void:
	if t.is_empty() or fly_panel == null:
		return
	# While the player is inspecting a patch the inspection panel and its close-up
	# camera take priority; the observation still lands in the event log.
	if inspect_active:
		return
	fly_target = t
	fly_time = 5.5
	fly_pin = _find_sensor_pin(String(t.get("name", "")))
	if fly_head:
		fly_head.text = "SWOT KaRIn SWATH — WATER SURFACE SCAN" if t.has("water_class") \
			else "REAL DATA RETURNED FROM ORBIT"
	fly_title.text = String(t.get("name", ""))
	fly_subtitle.text = "%s · sensed %s · %s" % [t.get("sensor", ""), t.get("date", ""), t.get("requires_instrument", "")]
	fly_stat.text = String(t.get("stat", ""))
	fly_credit.text = "Source: %s · %s" % [t.get("source", "NASA"), t.get("credit", "")]
	fly_status.text = "Streaming real imagery from NASA WorldView…"
	fly_image.texture = null
	var cached: Texture2D = ClimateMediaScript.load_cached(String(t.get("img_url", "")))
	if cached:
		fly_image.texture = cached
		fly_status.text = "Real NASA WorldView imagery (cached — plays offline next time)"
	fly_panel.visible = true
	if climate_media == null:
		climate_media = ClimateMediaScript.new()
		climate_media.name = "ClimateMedia"
		climate_media.image_ready.connect(_on_fly_image)
		add_child(climate_media)
	if not cached:
		climate_media.fetch(String(t.get("img_url", "")))

func _find_sensor_pin(target_name: String) -> Node3D:
	if target_name.is_empty():
		return null
	for i in range(SimulationEngine.CLIMATE_TARGETS.size()):
		if String(SimulationEngine.CLIMATE_TARGETS[i].get("name", "")) == target_name and i < climate_pins.size():
			return climate_pins[i]
	for i in range(SimulationEngine.SWOT_WATER_TARGETS.size()):
		if String(SimulationEngine.SWOT_WATER_TARGETS[i].get("name", "")) == target_name and i < swot_pins.size():
			return swot_pins[i]
	return null

func _on_fly_image(tex: Texture2D) -> void:
	if not fly_panel or not fly_panel.visible:
		return
	if tex:
		fly_image.texture = tex
		fly_status.text = "✅ Real NASA WorldView imagery (cached — plays offline next time)"
	else:
		fly_status.text = "⚠ Offline — numeric data from the same observation shown instead"

func _update_climate_flyover(delta: float) -> void:
	if fly_time <= 0.0:
		return
	if inspect_active:
		fly_time = 0.0
		fly_panel.visible = false
		return
	fly_time -= delta
	if fly_time <= 0.0:
		fly_panel.visible = false
		return
	if fly_pin and mission_camera:
		var pin_pos: Vector3 = fly_pin.global_position
		var outward: Vector3 = (pin_pos - earth_node.global_position).normalized()
		var wanted: Vector3 = pin_pos + outward * 2.4 + Vector3(0.0, 0.55, 0.0)
		mission_camera.global_position = mission_camera.global_position.lerp(wanted, minf(delta * 4.5, 1.0))
		mission_camera.look_at(pin_pos, Vector3.UP)

func _process(delta: float) -> void:
	if arrival_active:
		_update_orbit_arrival(delta)
		return
	# The picture is driven directly off the simulation's own geometry: the
	# satellite sits on the sub-satellite direction the engine uses to decide
	# contact, and the planet turns by the same angle the ground-station model
	# turns by.  Nothing here re-derives an orbit, so what the player sees and
	# what the telemetry reports are one calculation, not two that merely look
	# alike — which is the whole difference between a data model and a picture.
	var sub_dir: Vector3 = SimulationEngine.sub_point_direction()
	satellite_node.position = sub_dir * orbit_radius_3d
	var angle_rad: float = SimulationEngine.orbit_angle
	_update_satellite_operations(delta, angle_rad)
	_update_swot_scan_visuals(delta)

	# The globe spins at its real sidereal rate under a plane that does not, and
	# the station network rides that same spin so every dish stays on its own
	# continent while the ground track walks westward beneath it.
	var spin: float = SimulationEngine.earth_rotation_rad
	if earth_sphere:
		earth_sphere.rotation.y = spin
	if earth_clouds:
		earth_clouds.rotation.y = spin
	if stations_root:
		stations_root.rotation.y = spin
		_update_station_visuals()
	if climate_root:
		climate_root.rotation.y = spin
		_update_climate_target_visuals()
	if swot_root:
		swot_root.rotation.y = spin
		_update_swot_target_visuals()
	if inspect_root:
		inspect_root.rotation.y = spin
	if commissioning_active:
		_update_commissioning()

	# The control room is a live wall, not a snapshot: refresh it four times a
	# second from the same state the 3D operations view is drawing.
	if control_room_open:
		control_room_timer -= delta
		if control_room_timer <= 0.0:
			control_room_timer = 0.25
			_refresh_control_room()

	# Solar panel orientation toward sun
	var sun_dir: Vector3 = sun_light.global_transform.basis.z if sun_light else Vector3.RIGHT
	if solar_panel_l:
		solar_panel_l.rotation.x = angle_rad

	# Eclipse: darken satellite when in eclipse
	var in_eclipse: bool = SimulationEngine.state.get("in_eclipse", false)
	if satellite_mesh:
		var brightness: float = 0.3 if in_eclipse else 1.0
		var mat := satellite_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission = Color(0.7, 0.75, 0.8) * brightness * 0.2
			mat.emission_enabled = true

	# The flyover takes the camera last, after every routine follow-shot lerp,
	# so the close-up of the real location is what actually lands on screen.
	_update_climate_flyover(delta)
	_update_area_inspection(delta)

	# Popup timer
	if event_popup_timer > 0:
		event_popup_timer -= delta
		if event_popup_timer <= 0:
			event_popup.hide()

	# Input handling
	if Input.is_action_just_pressed("orbital_map"):
		_toggle_orbital_map()
	if Input.is_action_just_pressed("control_room"):
		_toggle_control_room()
	if Input.is_action_just_pressed("transmit_data"):
		SimulationEngine.transmit_data_manual()
	if Input.is_action_just_pressed("time_accel"):
		SimulationEngine.speed_up()
		_update_speed_buttons(SimulationEngine.time_scale_idx)
	if Input.is_action_just_pressed("time_decel"):
		SimulationEngine.speed_down()
		_update_speed_buttons(SimulationEngine.time_scale_idx)
	if Input.is_action_just_pressed("pause_game"):
		_toggle_pause()

func _update_orbit_arrival(delta: float) -> void:
	arrival_timer += delta
	if arrival_fade:
		arrival_fade.color.a = clampf(1.0 - arrival_timer / 1.6, 0.0, 1.0)
	# This is the same already-released spacecraft, now viewed by mission control.
	# Keep the deployment sequence on screen long enough for the player to read
	# it. The former 6-second version was easy to miss during a scene handoff.
	var drift: float = min(arrival_timer / 11.5, 1.0)
	if satellite_node:
		satellite_node.position = Vector3(lerp(-1.4, 3.8, drift), 0.8 + sin(arrival_timer * 1.2) * 0.25, 6.2)
		satellite_node.rotation_degrees = Vector3(8.0, -20.0 + arrival_timer * 7.0, 0.0)
	if satellite_visual:
		# The model begins compact against the upper stage and eases to its full
		# deployed span, making the handoff visibly feel like a mission event.
		var deployment: float = clamp((arrival_timer - 3.2) / 5.0, 0.0, 1.0)
		var scale_value: float = lerp(0.055, 0.22, deployment)
		satellite_visual.scale = Vector3.ONE * scale_value
		solar_deployment = deployment
	for panel in [solar_panel_l, solar_panel_r]:
		if panel: panel.scale.x = maxf(0.06, solar_deployment)
	if earth_node:
		earth_node.rotation.y += delta * 0.025
	if mission_camera:
		var target_camera := Vector3(-1.7, 3.0, 15.5)
		mission_camera.position = mission_camera.position.lerp(target_camera, min(delta * 0.42, 1.0))
		mission_camera.look_at(Vector3(0.4, 0.4, 4.8), Vector3.UP)
	if arrival_timer < 3.2:
		if arrival_title:
			arrival_title.text = "ASTEROID RENDEZVOUS" if asteroid_operations else "MARS ORBIT ACQUISITION" if mars_operations else "ORBIT ACQUISITION"
		if arrival_detail:
			arrival_detail.text = "Relative navigation lock established with 2025-XK7" if asteroid_operations else "DSN has acquired the climate orbiter arriving at Mars" if mars_operations else "Ground tracking has acquired the satellite released by the upper stage"
	elif arrival_timer < 8.4:
		if arrival_title: arrival_title.text = "SOLAR ARRAY DEPLOYMENT"
		if arrival_detail: arrival_detail.text = "Port and starboard arrays extending — hold attitude"
	elif arrival_timer < 11.8:
		if arrival_title: arrival_title.text = "ATTITUDE ACQUISITION"
		if arrival_detail:
			arrival_detail.text = "Low-thrust corrections holding a safe station around the asteroid" if asteroid_operations else "Reaction-control system pointing weather payload at Mars" if mars_operations else "Reaction-control system orienting payload toward Earth"
	elif arrival_timer < 14.0:
		if arrival_title:
			arrival_title.text = "2025-XK7 ORBIT ESTABLISHED" if asteroid_operations else "MARS CLIMATE ORBITER DEPLOYED" if mars_operations else "SATELLITE DEPLOYED"
		if arrival_detail:
			arrival_detail.text = "Rendezvous confirmed. Begin surface composition survey." if asteroid_operations else "Arrays locked. Mars-pointing climate survey confirmed." if mars_operations else "Arrays locked. Earth-pointing observation mode confirmed."
	else:
		_finish_orbit_arrival()

# ─── State Update from Simulation ────────────────────────────────────────────
func _on_state_updated(sim_state: Dictionary) -> void:
	_update_telemetry(sim_state)
	_update_indicators(sim_state)

func _update_telemetry(s: Dictionary) -> void:
	var batt_pct: float = 0.0
	var batt_max: float = s.get("battery_max_wh", 1.0)
	if batt_max > 0:
		batt_pct = (s.get("battery_wh", 0.0) / batt_max) * 100.0

	var sci: float    = s.get("science_points", 0)
	var sci_goal: float = s.get("target_science", 80)
	var data_stored: float = s.get("data_stored_mb", 0)
	var bus: Dictionary = GameManager.spacecraft_config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000.0
	var gen: float    = s.get("power_gen", 0)
	var draw: float   = s.get("power_draw", 0)

	if battery_bar:
		battery_bar.value = batt_pct
		_color_bar(battery_bar, 1.0 - batt_pct / 100.0)
	if battery_label:
		battery_label.text = "🔋 Battery: %.0f%% (%.0fWh)" % [batt_pct, s.get("battery_wh", 0)]

	if power_bar:
		var bal: float = gen - draw
		power_bar.value = clamp(gen / max(draw, 1) * 50, 0, 100)
		_color_bar(power_bar, 0.1 if gen >= draw else 0.95)
	if power_label:
		var bal: float = gen - draw
		power_label.text = "⚡ Power: %.0fW gen | %.0fW draw | %s%.0fW" % [
			gen, draw, "+" if bal >= 0 else "", bal
		]

	if science_bar:
		science_bar.max_value = sci_goal
		science_bar.value = sci
		_color_bar(science_bar, 1.0 - sci / max(sci_goal, 1))
	if science_label:
		science_label.text = "🔬 Science: %.1f / %.0f pts" % [sci, sci_goal]
		if GameManager.is_earth_climate_mission():
			var captured_n: int = int(s.get("targets_captured", 0))
			science_label.text += "  |  🌍 Real events %d/%d" % [captured_n, SimulationEngine.CLIMATE_TARGETS.size()]

	if data_bar:
		data_bar.max_value = max(storage_mb, 1)
		data_bar.value = data_stored
		_color_bar(data_bar, data_stored / max(storage_mb, 1))
	if data_label:
		var tx: float = s.get("data_transmitted_mb", 0)
		data_label.text = "📊 Data: %.0f MB stored | %.0f MB sent" % [data_stored, tx]

	if day_label:
		var day: int = s.get("day", 0)
		var total: int = s.get("mission_duration_days", 365)
		day_label.text = "Day %d / %d   |   Orbit #%d" % [day, total, s.get("total_orbits", 0)]

	if orbit_info:
		var mission: Dictionary = GameManager.current_mission
		orbit_info.text = "Orbit: %s at %d km  |  Period: %.0f min" % [
			mission.get("target", "?"),
			mission.get("altitude_km", 550),
			SimulationEngine.orbit_period_seconds / 60.0
		]
		if GameManager.is_earth_climate_mission():
			# Show the two numbers a real flight-dynamics officer would check: the
			# Kepler period and the J2 nodal drift against the 0.9856°/day that makes
			# an orbit sun-synchronous.  Both are the live simulation's own values.
			var prec: float = float(s.get("nodal_precession_deg_day", 0.0))
			var sync_err: float = absf(prec - 0.9856)
			orbit_info.text += "\nKepler period ✓  |  J2 nodal drift %.4f °/day (sun-sync needs 0.9856, Δ=%.4f)" % [prec, sync_err]
			var classes: Dictionary = s.get("swot_classes_scanned", {})
			orbit_info.text += "\nSWOT KaRIn: ocean %d/%d · lake %d/%d · river %d/%d  |  control room %d/%d records" % [
				int(classes.get("ocean", 0)), int(SimulationEngine.SWOT_CLASS_TOTALS.get("ocean", 0)),
				int(classes.get("lake", 0)), int(SimulationEngine.SWOT_CLASS_TOTALS.get("lake", 0)),
				int(classes.get("river", 0)), int(SimulationEngine.SWOT_CLASS_TOTALS.get("river", 0)),
				int(s.get("swot_received", 0)), SimulationEngine.SWOT_WATER_TARGETS.size()]

func _update_indicators(s: Dictionary) -> void:
	if eclipse_indicator:
		if asteroid_operations:
			eclipse_indicator.text = "DEEP SPACE"
			eclipse_indicator.add_theme_color_override("font_color", Color("#B3B3B3"))
		elif s.get("in_eclipse", false):
			eclipse_indicator.text = "ECLIPSE"
			eclipse_indicator.add_theme_color_override("font_color", Color("#777777"))
		else:
			eclipse_indicator.text = "SUNLIGHT"
			eclipse_indicator.add_theme_color_override("font_color", Color("#FFFFFF"))

	if contact_indicator:
		if s.get("ground_contact", false):
			contact_indicator.text = "DSN CONTACT: " + s.get("ground_station_name", "DSN") if asteroid_operations else "CONTACT: " + s.get("ground_station_name", "DSN")
			contact_indicator.add_theme_color_override("font_color", Color("#FFFFFF"))
		else:
			contact_indicator.text = "NO CONTACT"
			contact_indicator.add_theme_color_override("font_color", Color("#777777"))

	if speed_label:
		speed_label.text = "%dx" % int(SimulationEngine.time_scale)

# ─── Event Popup ─────────────────────────────────────────────────────────────
func _on_event_occurred(event: Dictionary) -> void:
	# Add to log
	var lbl: Label = Label.new()
	var type_col: Dictionary = {
		"success": Color("#FFFFFF"),
		"danger":  Color("#FFFFFF"),
		"warning": Color("#D9D9D9"),
		"info":    Color("#B3B3B3")
	}
	lbl.text = "Day %d: %s" % [SimulationEngine.state.get("day", 0), event.get("name", "?")]
	lbl.add_theme_color_override("font_color", type_col.get(event.get("type", "info"), Color("#FFFFFF")))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	if event_log:
		event_log.add_child(lbl)
		# Keep last 12 entries.  queue_free() alone is not enough here: the node
		# is only deleted at end of frame, so the loop must detach it explicitly
		# or it spins on the same child and can crash the engine at high time
		# scales when many events land in one frame.
		while event_log.get_child_count() > 12:
			var old_entry := event_log.get_child(0)
			event_log.remove_child(old_entry)
			old_entry.queue_free()

	# A climate capture gets its own flyover + imagery card; the generic popup
	# would only repeat what that panel already shows better.
	var kind: String = String(event.get("kind", ""))
	if kind == "climate_capture" or kind == "swot_water_capture":
		_begin_climate_flyover(event.get("target", {}))
		return
	if kind == "swot_water_downlinked" and control_room_open:
		_refresh_control_room()

	# Show popup
	if event_popup and event_popup_label:
		event_popup_label.text = "%s\n%s" % [event.get("name", ""), event.get("desc", "")]
		event_popup_label.add_theme_color_override("font_color",
			type_col.get(event.get("type", "info"), Color("#FFFFFF")))
		event_popup.show()
		event_popup_timer = 5.0

# ─── Mission End ──────────────────────────────────────────────────────────────
func _on_mission_ended(result: Dictionary) -> void:
	GameManager.mission_result = result
	await get_tree().create_timer(2.0).timeout
	GameManager.go_to_report()

# ─── Controls ────────────────────────────────────────────────────────────────
func _on_speed_1x_pressed() -> void:
	SimulationEngine.set_time_scale(0)
	_update_speed_buttons(0)

func _on_speed_10x_pressed() -> void:
	SimulationEngine.set_time_scale(1)
	_update_speed_buttons(1)

func _on_speed_100x_pressed() -> void:
	SimulationEngine.set_time_scale(2)
	_update_speed_buttons(2)

func _on_speed_1000x_pressed() -> void:
	SimulationEngine.set_time_scale(3)
	_update_speed_buttons(3)

func _update_speed_buttons(active_idx: int) -> void:
	var btns: Array = [speed_btn_1x, speed_btn_10x, speed_btn_100x]
	for i in range(btns.size()):
		if btns[i]:
			btns[i].button_pressed = (i == active_idx)

func _on_transmit_pressed() -> void:
	SimulationEngine.transmit_data_manual()

func _on_safemode_pressed() -> void:
	var s: Dictionary = SimulationEngine.state
	s["instruments_active"] = not s.get("instruments_active", true)
	var mode_str: String = "nominal" if s["instruments_active"] else "SAFE MODE"
	SimulationEngine._log_event("🛡️ Operator command: Instruments set to " + mode_str, "info")

func _on_end_mission_pressed() -> void:
	SimulationEngine._end_mission()

func _toggle_orbital_map() -> void:
	show_orbital_map = not show_orbital_map
	orbital_map_panel.visible = show_orbital_map

func _toggle_pause() -> void:
	var is_paused: bool = not SimulationEngine.paused
	SimulationEngine.paused = is_paused
	pause_menu.visible = is_paused
	if is_paused and control_room_open:
		control_room_open = false
		if control_room:
			control_room.visible = false

func _on_resume_pressed() -> void:
	SimulationEngine.paused = false
	pause_menu.hide()

func _on_quit_to_menu_pressed() -> void:
	SimulationEngine.running = false
	GameManager.go_to_main_menu()

func _color_bar(bar: ProgressBar, frac: float) -> void:
	var col: Color = Color("#FFFFFF") if frac < 0.4 else Color("#D9D9D9") if frac < 0.75 else Color("#777777")
	bar.add_theme_color_override("font_color", col)
