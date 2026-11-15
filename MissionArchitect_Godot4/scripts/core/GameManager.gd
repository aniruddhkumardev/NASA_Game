## GameManager.gd
## Autoload singleton — manages all game state, mission data, scene transitions
## Access from anywhere: GameManager.current_mission, GameManager.go_to_scene(...)

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal mission_started(mission_data: Dictionary)
signal phase_changed(new_phase: int)
signal resource_updated(resource_name: String, value: float)
signal mission_completed(result: Dictionary)
signal event_triggered(event_data: Dictionary)

# ─── Game Phases ──────────────────────────────────────────────────────────────
enum Phase {
	MAIN_MENU,
	HANGAR,
	BUILDER,
	LAUNCH,
	ORBIT,
	MISSION_REPORT
}

# ─── Current State ────────────────────────────────────────────────────────────
var current_phase: Phase = Phase.MAIN_MENU
var current_mission: Dictionary = {}
var spacecraft_config: Dictionary = {}
var simulation_state: Dictionary = {}
var mission_result: Dictionary = {}
var is_paused: bool = false

# ─── Mission Catalog ──────────────────────────────────────────────────────────
var missions: Array[Dictionary] = [
	{
		"id": "earth_climate",
		"name": "Earth Climate Sentinel",
		"subtitle": "SWOT water survey — oceans, lakes and rivers",
		"target": "Low Earth Orbit",
		"altitude_km": 550,
		"inclination_deg": 97.6,
		"duration_days": 365,
		"budget": 120,
		"mass_limit": 500,
		"power_limit": 300,
		"science_goal": 80,
		"description": "NASA's climate observatories — Terra, Aqua, Suomi NPP, PACE, ICESat-2 — hold a continuous 25-year record of Earth, and aging sensors threaten it. Design and operate the next sentinel in that chain, built around the NASA/CNES SWOT mission: its KaRIn radar measures the height of water across oceans, lakes and rivers in a 120 km swath on a 21-day repeat orbit. Scan real water sites, return the records to the ground-station control room, and pair the water survey with real climate events NASA tracks every day — wildfire megaseasons, marine heatwaves, volcanic SO₂ plumes and ice-sheet melt.",
		"objectives": [
			"Observe 3+ real NASA-tracked climate events from orbit",
			"Scan ocean, lake and river surfaces with SWOT KaRIn",
			"Collect 80 science points from Earth observation",
			"Downlink data during 3+ ground station passes",
			"Keep total mission cost under 120M credits"
		],
		"bonus_objectives": [
			"All 6 climate events observed",
			"All 6 SWOT water records delivered to the control room",
			"No power failures (zero safe-mode entries)",
			"Deliver 1+ GB of climate data to Earth"
		],
		# Each box in the builder maps to the real NASA Earth-observation sensor it
		# stands in for. Only this mission carries the mapping, so other mission
		# screens are untouched.
		"sensor_analogs": {
			"camera_wide": "VIIRS Day/Night Band (Suomi NPP / NOAA-20)",
			"camera_hires": "OLI + TIRS (Landsat 8/9)",
			"spectrometer": "TEMPO + PACE OCI (aerosols, SO₂, NO₂)",
			"radar": "SWOT + NISAR (radar altimetry / SAR)",
			"magnetometer": "Swarm constellation (magnetometry)",
			"thermal": "ECOSTRESS + MODIS (fires, SST) via NASA FIRMS"
		},
		"difficulty": "Beginner",
		"color": Color(0.2, 0.6, 1.0),
		"icon_color": Color(0.2, 0.8, 0.4)
	},
	{
		"id": "moon_scout",
		"name": "Lunar South Pole Scout",
		"subtitle": "Search for water ice at the lunar poles",
		"target": "Lunar Polar Orbit",
		"altitude_km": 100,
		"inclination_deg": 90.0,
		"duration_days": 180,
		"budget": 300,
		"mass_limit": 1200,
		"power_limit": 600,
		"science_goal": 120,
		"description": "Explore the Moon's south pole for water ice deposits. The mission will map shadowed craters and analyze subsurface composition.",
		"objectives": [
			"Map 80% of the lunar south pole",
			"Detect water ice signatures",
			"Survive the 14-day lunar night",
			"Stay within 300M credit budget"
		],
		"bonus_objectives": [
			"100% polar coverage",
			"Detect 3+ ice deposits",
			"Operate for full 180 days"
		],
		"difficulty": "Intermediate",
		"color": Color(0.7, 0.7, 0.8),
		"icon_color": Color(0.5, 0.5, 0.9)
	},
	{
		"id": "mars_orbiter",
		"name": "Mars Climate Explorer",
		"subtitle": "Launch from Earth, land on Mars, complete the climate survey",
		"target": "Mars Orbit",
		"altitude_km": 400,
		"inclination_deg": 93.0,
		"duration_days": 687,
		"budget": 600,
		"mass_limit": 2200,
		"power_limit": 1200,
		"science_goal": 200,
		"description": "Build a climate lander, launch it from Earth, cruise across deep space, land on Amazonis Planitia, and finish the work this mission was sent to do: map dust storms, profile the atmosphere, and hunt for subsurface ice.",
		"objectives": [
			"Launch from Earth and complete trans-Mars cruise",
			"Land the climate station on Amazonis Planitia",
			"Map dust storms and collect an atmospheric profile",
			"Detect subsurface water-ice signatures"
		],
		"bonus_objectives": [
			"Full weather-mast deployment",
			"Rover traverse of the landing ellipse",
			"Downlink the climate dataset to Earth"
		],
		"difficulty": "Expert",
		"color": Color(1.0, 0.4, 0.2),
		"icon_color": Color(1.0, 0.3, 0.1)
	},
	{
		"id": "asteroid_probe",
		"name": "Asteroid Rendezvous",
		"subtitle": "Intercept and study a near-Earth asteroid",
		"target": "Asteroid 2025-XK7",
		"altitude_km": 5,
		"inclination_deg": 0.0,
		"duration_days": 400,
		"budget": 450,
		"mass_limit": 1800,
		"power_limit": 900,
		"science_goal": 160,
		"description": "Rendezvous with a near-Earth asteroid, enter orbit, and study its composition. Watch out for outgassing and micro-gravity challenges.",
		"objectives": [
			"Successfully rendezvous with asteroid",
			"Orbit the asteroid for 30 days",
			"Analyze surface composition",
			"Return data to Earth"
		],
		"bonus_objectives": [
			"Deploy surface impactor",
			"Detect organic compounds",
			"Full 3D shape model"
		],
		"difficulty": "Advanced",
		"color": Color(0.8, 0.6, 0.2),
		"icon_color": Color(1.0, 0.8, 0.2)
	}
]

# ─── Component Catalog ────────────────────────────────────────────────────────
var components: Dictionary = {
	"bus": [
		{
			"id": "bus_small", "name": "SmallSat Bus",
			"desc": "Compact, affordable. Limited payload space.",
			"mass": 50, "power_draw": 20, "cost": 15,
			"reliability": 0.85, "data_storage": 50,
			"color": Color(0.4, 0.6, 1.0), "icon": "🔷"
		},
		{
			"id": "bus_medium", "name": "Medium Bus",
			"desc": "The workhorse of space exploration. Best balance.",
			"mass": 150, "power_draw": 40, "cost": 45,
			"reliability": 0.92, "data_storage": 200,
			"color": Color(0.2, 0.8, 0.4), "icon": "🟢"
		},
		{
			"id": "bus_large", "name": "Flagship Bus",
			"desc": "Heavy but highly capable. For complex missions.",
			"mass": 400, "power_draw": 80, "cost": 120,
			"reliability": 0.96, "data_storage": 1000,
			"color": Color(1.0, 0.8, 0.2), "icon": "⭐"
		}
	],
	"power": [
		{
			"id": "solar_small", "name": "Small Solar Array",
			"desc": "Lightweight panels. Good for inner solar system.",
			"mass": 15, "power_gen": 80, "power_draw": 0, "cost": 10,
			"works_deep_space": false, "color": Color(1.0, 0.9, 0.2), "icon": "☀️"
		},
		{
			"id": "solar_medium", "name": "Medium Solar Array",
			"desc": "Standard panels. Used on most Earth-orbit missions.",
			"mass": 35, "power_gen": 180, "power_draw": 0, "cost": 25,
			"works_deep_space": false, "color": Color(1.0, 0.7, 0.1), "icon": "⚡"
		},
		{
			"id": "solar_large", "name": "Large Solar Array",
			"desc": "High-output array. Heavy but generates lots of power.",
			"mass": 80, "power_gen": 400, "power_draw": 0, "cost": 55,
			"works_deep_space": false, "color": Color(1.0, 0.6, 0.0), "icon": "🌟"
		},
		{
			"id": "rtg", "name": "RTG Power System",
			"desc": "Nuclear battery. Works everywhere, even deep space.",
			"mass": 55, "power_gen": 300, "power_draw": 0, "cost": 150,
			"works_deep_space": true, "color": Color(0.8, 0.2, 1.0), "icon": "☢️"
		}
	],
	"battery": [
		{
			"id": "battery_100", "name": "100 Wh Battery",
			"desc": "Basic backup. Only lasts short eclipses.",
			"mass": 8, "capacity_wh": 100, "power_draw": 1, "cost": 5,
			"color": Color(0.4, 0.8, 0.4), "icon": "🔋"
		},
		{
			"id": "battery_300", "name": "300 Wh Battery",
			"desc": "Handles most eclipse periods comfortably.",
			"mass": 20, "capacity_wh": 300, "power_draw": 2, "cost": 12,
			"color": Color(0.2, 0.9, 0.5), "icon": "🔋"
		},
		{
			"id": "battery_600", "name": "600 Wh Battery",
			"desc": "Long eclipse survival. Essential for polar orbits.",
			"mass": 40, "capacity_wh": 600, "power_draw": 3, "cost": 22,
			"color": Color(0.1, 1.0, 0.6), "icon": "⚡"
		}
	],
	"comms": [
		{
			"id": "antenna_basic", "name": "Basic Omni Antenna",
			"desc": "Low bandwidth. Only works near Earth.",
			"mass": 3, "bandwidth_mbps": 1, "power_draw": 5, "cost": 8,
			"range_km": 2000, "color": Color(0.6, 0.6, 0.8), "icon": "📡"
		},
		{
			"id": "antenna_standard", "name": "Standard HGA",
			"desc": "Medium bandwidth high-gain antenna. Good for LEO/Lunar.",
			"mass": 12, "bandwidth_mbps": 10, "power_draw": 15, "cost": 20,
			"range_km": 400000, "color": Color(0.4, 0.7, 1.0), "icon": "📡"
		},
		{
			"id": "antenna_deep", "name": "Deep Space HGA",
			"desc": "High-power dish. Essential for Mars and beyond.",
			"mass": 35, "bandwidth_mbps": 2, "power_draw": 40, "cost": 50,
			"range_km": 999999999, "color": Color(0.2, 0.5, 1.0), "icon": "🛰️"
		}
	],
	"instruments": [
		{
			"id": "camera_wide", "name": "Wide-Angle Camera",
			"desc": "Images large areas. Low data rate.",
			"mass": 6, "power_draw": 12, "cost": 20, "data_rate_mbps": 5,
			"science_per_orbit": 4, "color": Color(0.3, 0.9, 0.9), "icon": "📷"
		},
		{
			"id": "camera_hires", "name": "High-Res Imager",
			"desc": "Extreme detail. High data volume. More science.",
			"mass": 22, "power_draw": 35, "cost": 55, "data_rate_mbps": 50,
			"science_per_orbit": 12, "color": Color(0.2, 0.7, 1.0), "icon": "🔭"
		},
		{
			"id": "spectrometer", "name": "Spectrometer",
			"desc": "Identifies atmospheric/surface chemistry.",
			"mass": 10, "power_draw": 18, "cost": 35, "data_rate_mbps": 8,
			"science_per_orbit": 8, "color": Color(1.0, 0.4, 0.8), "icon": "🌈"
		},
		{
			"id": "radar", "name": "SAR Radar",
			"desc": "Sees through clouds. Maps subsurface structures.",
			"mass": 40, "power_draw": 75, "cost": 85, "data_rate_mbps": 80,
			"science_per_orbit": 18, "color": Color(0.4, 1.0, 0.4), "icon": "📡"
		},
		{
			"id": "magnetometer", "name": "Magnetometer",
			"desc": "Maps magnetic fields. Very lightweight.",
			"mass": 4, "power_draw": 5, "cost": 12, "data_rate_mbps": 1,
			"science_per_orbit": 5, "color": Color(1.0, 0.6, 0.2), "icon": "🧲"
		},
		{
			"id": "thermal", "name": "Thermal Imager",
			"desc": "Measures surface temperature. Great for climate study.",
			"mass": 14, "power_draw": 22, "cost": 40, "data_rate_mbps": 15,
			"science_per_orbit": 10, "color": Color(1.0, 0.3, 0.3), "icon": "🌡️"
		}
	],
	"propulsion": [
		{
			"id": "prop_none", "name": "No Propulsion",
			"desc": "No thruster. Cheapest but no orbit correction.",
			"mass": 0, "power_draw": 0, "cost": 0,
			"delta_v": 0, "color": Color(0.5, 0.5, 0.5), "icon": "❌"
		},
		{
			"id": "prop_cold", "name": "Cold Gas Thrusters",
			"desc": "Simple attitude control. Very limited delta-v.",
			"mass": 8, "power_draw": 2, "cost": 8,
			"delta_v": 50, "color": Color(0.7, 0.8, 0.9), "icon": "💨"
		},
		{
			"id": "prop_ion", "name": "Ion Thruster",
			"desc": "Efficient. Low thrust but high delta-v. Needs power.",
			"mass": 20, "power_draw": 80, "cost": 45,
			"delta_v": 2000, "color": Color(0.4, 0.6, 1.0), "icon": "⚡"
		},
		{
			"id": "prop_chemical", "name": "Chemical Thruster",
			"desc": "High thrust for orbit insertion and deep space.",
			"mass": 60, "power_draw": 5, "cost": 60,
			"delta_v": 500, "color": Color(1.0, 0.5, 0.2), "icon": "🚀"
		}
	],
	"rocket": [
		{
			"id": "electron", "name": "Rocket Lab Electron",
			"desc": "Small launcher. Up to 300 kg to LEO only.",
			"payload_kg": 300, "cost": 8,
			"targets": ["Low Earth Orbit"],
			"reliability": 0.95, "color": Color(0.5, 0.5, 0.6), "icon": "🚀"
		},
		{
			"id": "falcon9", "name": "SpaceX Falcon 9",
			"desc": "Reusable medium-lift. Best cost-per-kg to LEO/Lunar.",
			"payload_kg": 2200, "cost": 70,
			"targets": ["Low Earth Orbit", "Lunar Polar Orbit"],
			"reliability": 0.97, "color": Color(0.3, 0.5, 1.0), "icon": "🚀"
		},
		{
			"id": "falcon_heavy", "name": "Falcon Heavy",
			"desc": "Heavy lift. Reaches Mars and asteroid belt.",
			"payload_kg": 4500, "cost": 150,
			"targets": ["Low Earth Orbit", "Lunar Polar Orbit", "Mars Orbit", "Asteroid 2025-XK7"],
			"reliability": 0.95, "color": Color(0.2, 0.7, 0.4), "icon": "🚀"
		},
		{
			"id": "sls", "name": "NASA SLS Block 1",
			"desc": "Super heavy-lift. Any destination. Very expensive.",
			"payload_kg": 8000, "cost": 600,
			"targets": ["Low Earth Orbit", "Lunar Polar Orbit", "Mars Orbit", "Asteroid 2025-XK7"],
			"reliability": 0.94, "color": Color(1.0, 0.6, 0.1), "icon": "🚀"
		},
		{
			"id": "starship", "name": "SpaceX Starship",
			"desc": "Next-gen fully reusable. Highest capacity of any rocket.",
			"payload_kg": 12000, "cost": 90,
			"targets": ["Low Earth Orbit", "Lunar Polar Orbit", "Mars Orbit", "Asteroid 2025-XK7"],
			"reliability": 0.88, "color": Color(0.3, 0.9, 0.9), "icon": "🚀"
		}
	]
}

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_init_spacecraft_config()
	# Verification-only: MA_MISSION preselects a mission id so the render probe
	# can reach a mission-specific launch/deploy path without the menu flow.
	var forced := OS.get_environment("MA_MISSION")
	if forced != "":
		for m in missions:
			if String(m.get("id", "")) == forced:
				current_mission = m.duplicate(true)
				break
	print("[GameManager] Ready — Mission Architect v1.0")

func _init_spacecraft_config() -> void:
	spacecraft_config = {
		"bus": {},
		"power": {},
		"battery": {},
		"comms": {},
		"instruments": [],
		"propulsion": {},
		"rocket": {},
		# Computed totals
		"total_mass": 0.0,
		"total_cost": 0.0,
		"total_power_gen": 0.0,
		"total_power_draw": 0.0,
		"total_data_rate": 0.0,
		"total_science_per_orbit": 0.0,
		"battery_capacity": 0.0
	}

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause_game"):
		toggle_pause()

# ─── Scene Navigation ─────────────────────────────────────────────────────────
func go_to_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func go_to_hangar() -> void:
	current_phase = Phase.HANGAR
	phase_changed.emit(current_phase)
	go_to_scene("res://scenes/hangar/hangar.tscn")

func go_to_builder() -> void:
	current_phase = Phase.BUILDER
	phase_changed.emit(current_phase)
	go_to_scene("res://scenes/builder/builder.tscn")

func is_mars_mission() -> bool:
	return current_mission.get("id", "") == "mars_orbiter"

func is_earth_climate_mission() -> bool:
	return current_mission.get("id", "") == "earth_climate"

func is_asteroid_mission() -> bool:
	return current_mission.get("id", "") == "asteroid_probe"

func is_deep_space_mission() -> bool:
	return is_mars_mission() or is_asteroid_mission()

func go_to_launch() -> void:
	current_phase = Phase.LAUNCH
	phase_changed.emit(current_phase)
	# Every mission lifts off from Earth. Destination gameplay starts after
	# parking orbit: lunar transfer, Mars climate operations, or Earth observation.
	go_to_scene("res://scenes/launch/launch.tscn")

func go_to_post_launch_destination() -> void:
	if current_mission.get("id", "") == "moon_scout":
		CinematicTransition.travel("res://scenes/lunar/lunar_transfer.tscn", "EARTH PARKING ORBIT ACQUIRED", "Upper stage separation complete — preparing translunar injection")
	elif is_mars_mission():
		current_phase = Phase.ORBIT
		phase_changed.emit(current_phase)
		CinematicTransition.travel("res://scenes/mars/mars_transfer.tscn", "TRANS-MARS INJECTION", "Earth departure complete — climate lander beginning the cruise to Mars")
	elif is_asteroid_mission():
		current_phase = Phase.ORBIT
		phase_changed.emit(current_phase)
		CinematicTransition.travel("res://scenes/orbit/orbit.tscn", "ASTEROID RENDEZVOUS", "Target lock acquired — intercept sequence beginning for 2025-XK7")
	else:
		go_to_orbit()

func go_to_orbit() -> void:
	current_phase = Phase.ORBIT
	phase_changed.emit(current_phase)
	# Destination missions own their operation scene. Earth observation is not
	# reused as a moon mission with different labels.
	if current_mission.get("id", "") == "moon_scout":
		go_to_scene("res://scenes/lunar/lunar_mission.tscn")
	elif is_mars_mission():
		go_to_scene("res://scenes/mars/mars_mission.tscn")
	elif is_asteroid_mission():
		go_to_scene("res://scenes/orbit/orbit.tscn")
	else:
		go_to_scene("res://scenes/orbit/orbit.tscn")

func go_to_report() -> void:
	current_phase = Phase.MISSION_REPORT
	phase_changed.emit(current_phase)
	go_to_scene("res://scenes/ui/mission_report.tscn")

func go_to_main_menu() -> void:
	current_phase = Phase.MAIN_MENU
	go_to_scene("res://scenes/ui/main_menu.tscn")

# ─── Mission Setup ────────────────────────────────────────────────────────────
func start_mission(mission_id: String) -> void:
	for m in missions:
		if m["id"] == mission_id:
			current_mission = m.duplicate(true)
			_init_spacecraft_config()
			mission_started.emit(current_mission)
			go_to_builder()
			return
	push_error("[GameManager] Mission not found: " + mission_id)

# ─── Spacecraft Configuration ─────────────────────────────────────────────────
func set_component(category: String, component: Dictionary) -> void:
	spacecraft_config[category] = component.duplicate(true)
	_recompute_totals()
	resource_updated.emit("all", 0.0)

func toggle_instrument(instrument: Dictionary) -> void:
	var instruments: Array = spacecraft_config["instruments"]
	var found_idx: int = -1
	for i in range(instruments.size()):
		if instruments[i]["id"] == instrument["id"]:
			found_idx = i
			break
	if found_idx >= 0:
		instruments.remove_at(found_idx)
	else:
		instruments.append(instrument.duplicate(true))
	spacecraft_config["instruments"] = instruments
	_recompute_totals()
	resource_updated.emit("all", 0.0)

func has_instrument(instrument_id: String) -> bool:
	for inst in spacecraft_config["instruments"]:
		if inst["id"] == instrument_id:
			return true
	return false

func _recompute_totals() -> void:
	var total_mass: float = 0.0
	var total_cost: float = 0.0
	var total_power_gen: float = 0.0
	var total_power_draw: float = 0.0
	var total_data_rate: float = 0.0
	var total_science: float = 0.0
	var battery_cap: float = 0.0

	var categories_single: Array = ["bus", "power", "battery", "comms", "propulsion"]
	for cat in categories_single:
		var comp: Dictionary = spacecraft_config.get(cat, {})
		if comp.is_empty():
			continue
		total_mass += comp.get("mass", 0)
		total_cost += comp.get("cost", 0)
		total_power_gen += comp.get("power_gen", 0)
		total_power_draw += comp.get("power_draw", 0)
		battery_cap += comp.get("capacity_wh", 0)

	for inst in spacecraft_config["instruments"]:
		total_mass += inst.get("mass", 0)
		total_cost += inst.get("cost", 0)
		total_power_draw += inst.get("power_draw", 0)
		total_data_rate += inst.get("data_rate_mbps", 0)
		total_science += inst.get("science_per_orbit", 0)

	spacecraft_config["total_mass"] = total_mass
	spacecraft_config["total_cost"] = total_cost
	spacecraft_config["total_power_gen"] = total_power_gen
	spacecraft_config["total_power_draw"] = total_power_draw
	spacecraft_config["total_data_rate"] = total_data_rate
	spacecraft_config["total_science_per_orbit"] = total_science
	spacecraft_config["battery_capacity"] = battery_cap

# ─── Design Validation ────────────────────────────────────────────────────────
func validate_design() -> Array:
	var errors: Array = []
	var config: Dictionary = spacecraft_config
	var mission: Dictionary = current_mission

	if config["bus"].is_empty():
		errors.append({"type": "error", "msg": "No spacecraft bus selected!", "fix": "Select a bus from the Bus category."})
	if config["power"].is_empty():
		errors.append({"type": "error", "msg": "No power system selected!", "fix": "Select solar panels or RTG from Power category."})
	if config["comms"].is_empty():
		errors.append({"type": "error", "msg": "No communication system!", "fix": "Select an antenna from Comms category."})
	if config["instruments"].is_empty():
		errors.append({"type": "warning", "msg": "No science instruments selected.", "fix": "Add at least one instrument to collect science data."})
	if config["rocket"].is_empty():
		errors.append({"type": "error", "msg": "No launch vehicle selected!", "fix": "Select a rocket from the Launch Vehicle tab."})

	var mass: float = config["total_mass"]
	var mass_limit: float = mission.get("mass_limit", 9999)
	if mass > mass_limit:
		errors.append({
			"type": "error",
			"msg": "Spacecraft too heavy! %.0f kg > %.0f kg limit" % [mass, mass_limit],
			"fix": "Remove heavy instruments or choose a larger rocket."
		})

	var rocket: Dictionary = config.get("rocket", {})
	if not rocket.is_empty():
		var cap: float = rocket.get("payload_kg", 0)
		if mass > cap:
			errors.append({
				"type": "error",
				"msg": "Rocket can't lift this! %.0f kg > %s capacity (%.0f kg)" % [mass, rocket.get("name","?"), cap],
				"fix": "Choose a more powerful rocket or reduce spacecraft mass."
			})
		var target: String = mission.get("target", "")
		var targets: Array = rocket.get("targets", [])
		if not target in targets:
			errors.append({
				"type": "error",
				"msg": "%s cannot reach %s" % [rocket.get("name","Rocket"), target],
				"fix": "Choose a rocket capable of reaching " + target + "."
			})

	var power_gen: float = config["total_power_gen"]
	var power_draw: float = config["total_power_draw"]
	if power_draw > power_gen:
		errors.append({
			"type": "error",
			"msg": "Power deficit! Drawing %.0fW but generating %.0fW" % [power_draw, power_gen],
			"fix": "Add more solar panels, RTG, or remove power-hungry instruments."
		})
	elif power_draw > power_gen * 0.85:
		errors.append({
			"type": "warning",
			"msg": "Power margin very tight (%.0fW surplus)" % (power_gen - power_draw),
			"fix": "Consider adding more power generation for eclipse periods."
		})

	var cost: float = config["total_cost"]
	var budget: float = mission.get("budget", 9999)
	if cost > budget:
		errors.append({
			"type": "error",
			"msg": "Over budget! $%.0fM > $%.0fM limit" % [cost, budget],
			"fix": "Choose cheaper components or a smaller spacecraft bus."
		})

	var target_str: String = mission.get("target", "")
	var power_comp: Dictionary = config.get("power", {})
	if ("Mars" in target_str or "Asteroid" in target_str) and not power_comp.get("works_deep_space", false):
		errors.append({
			"type": "warning",
			"msg": "Solar panels weaken at this distance from the Sun.",
			"fix": "Consider an RTG (nuclear battery) for deep space missions."
		})

	if is_asteroid_mission():
		var propulsion: Dictionary = config.get("propulsion", {})
		if propulsion.get("delta_v", 0) < 500:
			errors.append({
				"type": "error",
				"msg": "Asteroid intercept needs at least 500 m/s of propulsion delta-v.",
				"fix": "Select a chemical or ion propulsion system for rendezvous and orbit insertion."
			})
		if not has_instrument("spectrometer"):
			errors.append({
				"type": "error",
				"msg": "No instrument can analyze the asteroid's surface composition.",
				"fix": "Add the Spectrometer to identify surface chemistry."
			})

	return errors

func is_design_valid() -> bool:
	var errors: Array = validate_design()
	for e in errors:
		if e["type"] == "error":
			return false
	return true

# ─── Pause ────────────────────────────────────────────────────────────────────
func toggle_pause() -> void:
	is_paused = !is_paused
	get_tree().paused = is_paused

# ─── Save / Load ─────────────────────────────────────────────────────────────
func save_game() -> void:
	var save_data: Dictionary = {
		"mission_id": current_mission.get("id", ""),
		"spacecraft_config": spacecraft_config,
		"mission_result": mission_result
	}
	var file: FileAccess = FileAccess.open("user://savegame.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("[GameManager] Game saved.")

func load_game() -> bool:
	if not FileAccess.file_exists("user://savegame.json"):
		return false
	var file: FileAccess = FileAccess.open("user://savegame.json", FileAccess.READ)
	if file:
		var text: String = file.get_as_text()
		file.close()
		var data: Variant = JSON.parse_string(text)
		if data is Dictionary:
			spacecraft_config = data.get("spacecraft_config", {})
			mission_result = data.get("mission_result", {})
			var mid: String = data.get("mission_id", "")
			for m in missions:
				if m["id"] == mid:
					current_mission = m.duplicate(true)
			_recompute_totals()
			print("[GameManager] Game loaded.")
			return true
	return false
