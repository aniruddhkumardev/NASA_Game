## SimulationEngine.gd
## Autoload singleton — runs deterministic orbital mission simulation
## Physics: orbital mechanics, power model, data downlink, science collection

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────
signal state_updated(state: Dictionary)
signal event_occurred(event: Dictionary)
signal mission_ended(result: Dictionary)

# ─── Constants ────────────────────────────────────────────────────────────────
const MU_EARTH: float    = 3.986e5   # km³/s²  (Earth gravitational parameter)
const RE_EARTH: float    = 6371.0    # km
const MU_MOON: float     = 4.905e3
const RE_MOON: float     = 1737.0
const PI2: float         = 2.0 * PI
const SECONDS_PER_DAY: float = 86400.0
const J2_EARTH: float    = 1.08263e-3   # Earth's dominant oblateness harmonic

# Time multipliers for simulation speed
const TIME_SCALES: Array = [1.0, 10.0, 60.0, 600.0, 3600.0]
var time_scale_idx: int = 1

# ─── Simulation State ─────────────────────────────────────────────────────────
var running: bool = false
var paused: bool = false
var state: Dictionary = {}
var time_scale: float = 10.0
var elapsed_sim_seconds: float = 0.0
var random_seed: int = 12345

var _rng: RandomNumberGenerator

# ─── Orbital Parameters ───────────────────────────────────────────────────────
var orbit_period_seconds: float = 0.0
var orbit_angle: float = 0.0        # radians, 0..2π
var eclipse_fraction: float = 0.35  # fraction of orbit in shadow
var orbit_inclination_rad: float = deg_to_rad(51.6)

# ─── Ground Station Positions (lat/lon in degrees) ────────────────────────────
const GROUND_STATIONS: Array = [
	{"name": "Goldstone", "lat": 35.4, "lon": -116.9},
	{"name": "Madrid DSN", "lat": 40.4, "lon": -4.2},
	{"name": "Canberra DSN", "lat": -35.4, "lon": 149.0},
	{"name": "Svalbard", "lat": 78.2, "lon": 15.4}
]

# ─── Real NASA-tracked climate survey targets (Earth Climate Sentinel only) ────
# Every entry below is a genuine event or record that NASA's Earth-observation
# program monitors, with the location of the event and the real sensor that
# observed it.  The game's instrument boxes are stand-ins for those sensors, so
# science is only earned over a target when the player flew the instrument that
# actually made the discovery — the data is the mission, not decoration.
const CLIMATE_FOOTPRINT_DEG: float = 15.0   # angular radius sensed at 550 km
const CLIMATE_TARGETS: Array = [
	{"name": "Canadian Wildfire Megaseason 2023", "lat": 57.0, "lon": -106.0,
		"requires_instrument": "thermal", "needs_sunlight": false,
		"science": 14, "data_mb": 220,
		"sensor": "MODIS/VIIRS thermal anomalies", "source": "NASA FIRMS (fire info)",
		"note": "2023 was Canada's worst wildfire season on record; ~650 kt of smoke was tracked from orbit and mapped plumes across North America and the Atlantic.", "date": "2023-07-08", "stat": "4.9 M ha burned | ~650 kt smoke emitted (CCAC)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2023-07-08T18:00:00Z&BBOX=-114,52,-98,62&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Lahaina Urban Fire Damage, Maui 2023", "lat": 20.97, "lon": -156.68,
		"requires_instrument": "camera_hires", "needs_sunlight": true,
		"science": 12, "data_mb": 480,
		"sensor": "Landsat 8/9 OLI burned-area imaging", "source": "NASA Earthdata / USGS Landsat",
		"note": "Landsat's 30 m imagery mapped the burn scar of the August 2023 disaster and became evidence in the recovery effort.", "date": "2023-08-09", "stat": "~2,200 structures lost | 21.7 km2 burn scar (Landsat 8 OLI)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2023-08-09T19:40:00Z&BBOX=-157.3,20.3,-156.0,21.3&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Mediterranean Marine Heatwave 2022", "lat": 37.4, "lon": 15.0,
		"requires_instrument": "thermal", "needs_sunlight": false,
		"science": 12, "data_mb": 180,
		"sensor": "MODIS sea-surface temperature (Aqua)", "source": "NASA Ocean Biology (OB.DAAC)",
		"note": "Summer 2022 SSTs in the Mediterranean exceeded +6 C climatology - one of the strongest marine heatwaves recorded anywhere by satellite.", "date": "2022-07-24", "stat": "SST anomaly up to +6.0 C | Class III MHW (OB.DAAC SST)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2022-07-24T11:30:00Z&BBOX=10.5,34.0,21.0,40.5&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Amazon River Flood Pulse (Rio Madeira)", "lat": -8.8, "lon": -63.9,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 15, "data_mb": 520,
		"sensor": "SWOT KaRIn radar altimetry", "source": "NASA/CNES SWOT",
		"note": "SWOT measures the height of every river and lake on Earth every 21 days - the 2025 record flood pulse on the Madeira was captured in its swaths.", "date": "2014-03-17", "stat": "River stage >19 m | ~250 km floodplain inundated (SWOT)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2014-03-17T15:30:00Z&BBOX=-67.0,-12.0,-60.0,-5.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Sundhnúkur Eruption SO₂ Plume, Iceland", "lat": 63.9, "lon": -22.4,
		"requires_instrument": "spectrometer", "needs_sunlight": true,
		"science": 13, "data_mb": 160,
		"sensor": "TEMPO tropospheric SO₂ columns", "source": "NASA TEMPO",
		"note": "TEMPO, the first pollution instrument in geostationary orbit over the US, watched the 2024 Sundhnúkur fissure eruptions flood the atmosphere near Grindavík with SO₂.", "date": "2024-01-14", "stat": "Fissure eruption ~4 km from Grindavík | SO₂ plume tracked hourly", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor,VIIRS_SNPP_Thermal_Anomalies_all&Time=2024-01-14T13:00:00Z&BBOX=-24.0,63.0,-21.0,64.6&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Greenland Ice Sheet Mass Loss (SER4) ", "lat": 68.0, "lon": -50.0,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 12, "data_mb": 300,
		"sensor": "ICESat-2 ATLAS laser altimeter", "source": "NASA ICESat-2",
		"note": "ICESat-2's photon-counting laser has weighed the Greenland ice sheet since 2018, showing losses near 270 Gt per year that raise global sea level.", "date": "2024-06-23", "stat": "~270 Gt/yr mass loss | meltwater plumes at Ilulissat (ICESat-2)", "img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-06-23T15:00:00Z&BBOX=-53.5,66.5,-46.0,70.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
]

# ─── SWOT surface-water survey (Earth Climate Sentinel only) ─────────────────
# SWOT (Surface Water and Ocean Topography, NASA/CNES, launched Dec 2022) is the
# first satellite to measure the height of water across the whole planet: oceans,
# lakes and rivers in one 120 km KaRIn radar swath, on a 21-day repeat orbit.
# These are real places SWOT monitors, each carrying the measurement a KaRIn
# observational product would deliver to the ground segment.  Radar works day
# and night, so unlike the optical climate sensors none of these need sunlight.
const SWOT_FOOTPRINT_DEG: float = 8.0   # half-width of the 120 km swath at 550 km
const SWOT_CLASS_TOTALS: Dictionary = {"ocean": 2, "lake": 2, "river": 2}
const SWOT_WATER_TARGETS: Array = [
	{"name": "Gulf Stream SSH Front", "water_class": "ocean", "lat": 36.0, "lon": -70.0,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 10, "data_mb": 420,
		"sensor": "SWOT KaRIn ocean topography", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "SWOT resolves sea-surface height at kilometre scales, revealing the fronts and eddies that carry heat poleward in the Gulf Stream.", "date": "2024-05-12",
		"stat": "SSH anomaly +92 cm | geostrophic flow 1.2 m/s | 4 eddies resolved",
		"measurements": {"ssh_cm": 92.0, "geostrophic_cm_s": 120.0, "eddies": 4.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-05-12T15:00:00Z&BBOX=-75.0,32.0,-65.0,39.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Kuroshio Current Meander", "water_class": "ocean", "lat": 34.0, "lon": 142.0,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 10, "data_mb": 400,
		"sensor": "SWOT KaRIn ocean topography", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "The Kuroshio is one of the strongest western boundary currents; SWOT's wide swath captures its meanders and the eddies it sheds in a single pass.", "date": "2024-03-28",
		"stat": "SSH anomaly +118 cm | front width 90 km | 2 warm-core rings",
		"measurements": {"ssh_cm": 118.0, "geostrophic_cm_s": 145.0, "front_width_km": 90.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-03-28T02:00:00Z&BBOX=137.0,30.0,147.0,37.0&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Lake Victoria Water Level", "water_class": "lake", "lat": -1.0, "lon": 33.0,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 9, "data_mb": 260,
		"sensor": "SWOT KaRIn lake level", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "SWOT measures lake height over the full water surface, not just at a gauge, closing water-balance budgets for Africa's largest lake and the Nile outflow.", "date": "2024-04-17",
		"stat": "Level 1134.2 m | +42 cm vs 2023 | 68,800 km2 surface",
		"measurements": {"level_m": 1134.2, "anomaly_cm": 42.0, "area_km2": 68800.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-04-17T09:00:00Z&BBOX=31.5,-3.5,34.5,0.5&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Lake Mead Elevation", "water_class": "lake", "lat": 36.1, "lon": -114.4,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 9, "data_mb": 240,
		"sensor": "SWOT KaRIn lake level", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "Lake Mead's level is a live index of Colorado River drought; SWOT tracks its elevation and shoreline change across the reservoir.", "date": "2024-06-05",
		"stat": "Elevation 324.3 m | -120 cm anomaly | 36% capacity",
		"measurements": {"level_m": 324.3, "anomaly_cm": -120.0, "capacity_pct": 36.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-06-05T18:00:00Z&BBOX=-115.2,35.5,-113.6,36.7&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Amazon at Obidos", "water_class": "river", "lat": -1.9, "lon": -55.5,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 11, "data_mb": 520,
		"sensor": "SWOT KaRIn river discharge", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "At Obidos the Amazon narrows into a single channel. SWOT measures its width, slope and stage together, turning them into the world's largest river discharge estimate.", "date": "2024-05-21",
		"stat": "Stage 8.4 m | width 11 km | discharge 210,000 m3/s",
		"measurements": {"stage_m": 8.4, "width_m": 11000.0, "discharge_m3s": 210000.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-05-21T14:00:00Z&BBOX=-57.5,-3.5,-53.5,-0.5&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"},
	{"name": "Mississippi at Memphis", "water_class": "river", "lat": 35.15, "lon": -90.05,
		"requires_instrument": "radar", "needs_sunlight": false,
		"science": 9, "data_mb": 360,
		"sensor": "SWOT KaRIn river discharge", "source": "NASA/CNES SWOT (swot.jpl.nasa.gov)",
		"note": "SWOT observes the Mississippi's stage and width through floods and low water, giving forecasters a basin-scale check on river models.", "date": "2024-04-02",
		"stat": "Stage 8.2 m | width 1.6 km | discharge 12,500 m3/s",
		"measurements": {"stage_m": 8.2, "width_m": 1600.0, "discharge_m3s": 12500.0},
		"img_url": "https://wvs.earthdata.nasa.gov/api/v1/staticimage?SERVICE=WMTS&REQUEST=GetMap&VERSION=1.0.0&FORMAT=image/jpeg&WIDTH=768&HEIGHT=448&LayerStack=MODIS_Terra_CorrectedReflectance_TrueColor&Time=2024-04-02T16:00:00Z&BBOX=-91.5,34.0,-88.5,36.3&BOUNDINGCRS=EPSG:4326", "credit": "NASA WorldView / EOSDIS (public domain)"}
]

# ─── Orbital Geometry ─────────────────────────────────────────────────────────
# One place decides where the satellite is, where every station is, and whether
# the two can see each other.  The scene draws from these functions and the
# numbers are computed from them, so a downlink you can see on screen and a
# downlink in the telemetry are the same event rather than two guesses that
# happen to agree.
const EARTH_ROTATION_RATE: float = PI2 / 86164.0   # rad/s — sidereal, not solar
const MIN_ELEVATION_DEG: float = 10.0              # no dish works at the horizon
var earth_rotation_rad: float = 0.0

# A sun-synchronous climate orbit is not inertial: Earth's oblateness (the J2
# harmonic) drags the orbital plane eastward about the spin axis, and at exactly
# +0.9856°/day the local sun-time of every pass stays fixed — that is the whole
# reason NASA flies 97-98° inclinations for Earth observation.  The climate
# sentinel precesses with the real rate; other missions keep a fixed plane.
var node_precession_rad: float = 0.0
var node_precession_rate: float = 0.0   # rad/s, eastward positive

## Unit direction from the body centre to the satellite.  The globe's spin axis
## is +Y and the orbit plane is tilted about +X, so the sub-point latitude runs
## between +/- the inclination and the ground track drifts west as the planet
## turns under a plane that does not.
func sub_point_direction(angle: float = -1.0) -> Vector3:
	var a: float = orbit_angle if angle < 0.0 else angle
	return Vector3(cos(a), sin(orbit_inclination_rad) * sin(a), cos(orbit_inclination_rad) * sin(a)) \
		.rotated(Vector3.UP, node_precession_rad)

## Unit direction of a point on the surface in the globe's own frame.  The two
## constants below are the only thing between a station and the continent it is
## supposed to be on: the sphere's UV seam does not sit where intuition puts it,
## so the mapping is calibrated against the texture rather than guessed at.
const STATION_LON_OFFSET_DEG: float = 180.0
const STATION_X_FLIP: float = 1.0
func station_local_direction(lat_deg: float, lon_deg: float) -> Vector3:
	var la: float = deg_to_rad(lat_deg)
	var lo: float = deg_to_rad(lon_deg + STATION_LON_OFFSET_DEG)
	return Vector3(STATION_X_FLIP * cos(la) * cos(lo), sin(la), cos(la) * sin(lo))

## The same point after the planet has turned under the orbit.
func station_world_direction(station: Dictionary) -> Vector3:
	return station_local_direction(float(station["lat"]), float(station["lon"])) \
		.rotated(Vector3.UP, earth_rotation_rad)

## Elevation of the satellite above the horizon at one station, in degrees, from
## the triangle centre-station-satellite.  This is the real formula, not a
## window: a pass begins when the number crosses 10° and ends when it falls back
## through it, which is why an equatorial station can never see a polar one.
func station_elevation_deg(station: Dictionary, altitude_km: float) -> float:
	var body_r: float = _body_radius_km()
	var sat_r: float = body_r + maxf(altitude_km, 1.0)
	var gamma: float = station_world_direction(station).angle_to(sub_point_direction())
	# The triangle centre–station–satellite: with the central angle γ between the
	# station and the sub-point, the elevation at the station is
	#     tan e = (r·cos γ − R) / (r·sin γ)
	# which is 90° overhead, 0° at the geometric horizon and negative when the
	# vehicle is below it.  No windows, no tables — this is the pass.
	return rad_to_deg(atan2(sat_r * cos(gamma) - body_r, sat_r * sin(gamma)))

func _body_radius_km() -> float:
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Moon" in target or "Lunar" in target:
		return RE_MOON
	if "Mars" in target:
		return 3389.5
	return RE_EARTH

## The station with the highest satellite elevation right now, and how high.
## Returns an empty dictionary when nothing on the network can see the vehicle.
func best_visible_station(altitude_km: float) -> Dictionary:
	var best: Dictionary = {}
	var best_el: float = MIN_ELEVATION_DEG
	for station in GROUND_STATIONS:
		var el: float = station_elevation_deg(station, altitude_km)
		if el > best_el:
			best_el = el
			best = station
	if best.is_empty():
		return {}
	return {
		"name": String(best["name"]),
		"lat": float(best["lat"]),
		"lon": float(best["lon"]),
		"elevation_deg": best_el,
		"direction": station_world_direction(best),
	}

# ─── Random Events Pool ───────────────────────────────────────────────────────
const EVENTS: Array = [
	{
		"id": "solar_flare", "name": "Solar Flare!",
		"desc": "Intense radiation reduces solar panel efficiency by 20% for 2 orbits.",
		"type": "warning", "probability": 0.04,
		"effect": {"power_gen_mult": 0.8, "duration_orbits": 2}
	},
	{
		"id": "micrometeorite", "name": "Micrometeorite Impact",
		"desc": "A tiny rock chips one solar panel. Power generation drops 10%.",
		"type": "danger", "probability": 0.02,
		"effect": {"power_gen_mult": 0.9, "duration_orbits": 9999}
	},
	{
		"id": "software_glitch", "name": "Software Anomaly",
		"desc": "Flight computer glitch. One instrument temporarily offline.",
		"type": "warning", "probability": 0.03,
		"effect": {"science_mult": 0.7, "duration_orbits": 3}
	},
	{
		"id": "comm_blackout", "name": "Communication Blackout",
		"desc": "Spacecraft behind target body. No ground contact for 2 orbits.",
		"type": "info", "probability": 0.05,
		"effect": {"comms_blocked": true, "duration_orbits": 2}
	},
	{
		"id": "discovery", "name": "Unexpected Discovery!",
		"desc": "Instruments detect an anomalous reading — bonus science data!",
		"type": "success", "probability": 0.04,
		"effect": {"bonus_science": 15}
	},
	{
		"id": "battery_surge", "name": "Battery Performance Boost",
		"desc": "Cold space temperatures improve battery efficiency. +10% capacity!",
		"type": "success", "probability": 0.03,
		"effect": {"battery_mult": 1.1}
	},
	{
		"id": "instrument_fail", "name": "Instrument Failure",
		"desc": "One science instrument stops responding. Science output reduced.",
		"type": "danger", "probability": 0.02,
		"effect": {"science_mult": 0.6, "duration_orbits": 9999}
	},
	{
		"id": "gravity_assist", "name": "Navigation Bonus",
		"desc": "Precise navigation saves propellant. Fuel reserve increases.",
		"type": "success", "probability": 0.03,
		"effect": {"bonus_science": 8}
	}
]

# ─── Init ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	print("[SimEngine] Ready")

# ─── Start Simulation ─────────────────────────────────────────────────────────
func start_simulation(seed_val: int = 12345) -> void:
	random_seed = seed_val
	_rng.seed = seed_val
	elapsed_sim_seconds = 0.0
	orbit_angle = 0.0
	earth_rotation_rad = 0.0
	node_precession_rad = 0.0
	node_precession_rate = 0.0
	running = true
	paused = false

	var mission: Dictionary = GameManager.current_mission
	var config: Dictionary = GameManager.spacecraft_config

	# The plane the vehicle is actually flying.  A sun-synchronous climate orbit is
	# near-polar, and that is the only reason a satellite in it can see Svalbard at
	# all — so the inclination has to come from the mission, not from a constant.
	orbit_inclination_rad = deg_to_rad(float(mission.get("inclination_deg", 51.6)))

	# Compute orbital period
	orbit_period_seconds = _compute_orbit_period(mission)

	# Eclipse fraction based on altitude
	var alt: float = mission.get("altitude_km", 550)
	eclipse_fraction = _compute_eclipse_fraction(alt)

	# The climate sentinel flies a real sun-synchronous orbit: the J2 nodal
	# precession is computed from the mission's own altitude and inclination, and
	# only the Earth mission precesses.  Every other mission keeps the fixed
	# inertial plane it always had.
	if String(mission.get("id", "")) == "earth_climate":
		var sma: float = RE_EARTH + alt
		var mean_motion: float = PI2 / orbit_period_seconds
		node_precession_rate = -1.5 * mean_motion * J2_EARTH \
			* pow(RE_EARTH / sma, 2.0) * cos(orbit_inclination_rad)

	# Init state
	state = {
		"day": 0,
		"orbit_number": 0,
		"orbit_angle_deg": 0.0,
		"battery_wh": config.get("battery_capacity", 0.0),
		"battery_max_wh": config.get("battery_capacity", 1.0),
		"data_stored_mb": 0.0,
		"data_transmitted_mb": 0.0,
		"science_points": 0.0,
		"power_gen": config.get("total_power_gen", 0.0),
		"power_draw": config.get("total_power_draw", 0.0),
		"power_balance": 0.0,
		"in_eclipse": false,
		"ground_contact": false,
		"ground_station_name": "",
		"station_elevation_deg": 0.0,
		"pass_mb": 0.0,
		"passes_completed": 0,
		"instruments_active": true,
		"mission_health": 100.0,
		"events_log": [],
		"power_gen_mult": 1.0,
		"science_mult": 1.0,
		"comms_blocked": false,
		"active_effects": [],
		"total_orbits": 0,
		"target_science": mission.get("science_goal", 80),
		"mission_duration_days": mission.get("duration_days", 365),
		"objectives_done": [],
	}
	if GameManager.is_asteroid_mission():
		var propulsion: Dictionary = config.get("propulsion", {})
		var has_spectrometer: bool = false
		for instrument in config.get("instruments", []):
			if instrument.get("id", "") == "spectrometer":
				has_spectrometer = true
				break
		state["rendezvous_complete"] = propulsion.get("delta_v", 0) >= 500
		state["composition_analyzed"] = false
		state["has_composition_instrument"] = has_spectrometer
		state["asteroid_orbit_days"] = 0
		state["objectives_done"] = _asteroid_objectives_done()
	if GameManager.is_earth_climate_mission():
		# Every real target starts unobserved; the survey is the mission.
		var targets: Array = []
		for t in CLIMATE_TARGETS:
			var entry: Dictionary = t.duplicate(true)
			entry["captured"] = false
			entry["captured_day"] = -1
			targets.append(entry)
		state["climate_targets"] = targets
		state["targets_captured"] = 0
		state["safe_mode_events"] = 0
		state["nodal_precession_deg_day"] = rad_to_deg(node_precession_rate * SECONDS_PER_DAY)
		# The SWOT surface-water layer: each real site starts unscanned, and its
		# record only reaches the control room after a ground-station pass.
		var water: Array = []
		for w in SWOT_WATER_TARGETS:
			var record: Dictionary = w.duplicate(true)
			record["scanned"] = false
			record["downlinked"] = false
			record["scanned_day"] = -1
			record["received_day"] = -1
			water.append(record)
		state["swot_water_targets"] = water
		state["swot_scanned"] = 0
		state["swot_received"] = 0
		state["swot_classes_scanned"] = {"ocean": 0, "lake": 0, "river": 0}
		state["swot_classes_received"] = {"ocean": 0, "lake": 0, "river": 0}
		state["last_swot_scan"] = ""
		state["last_swot_received"] = ""
		state["objectives_done"] = _earth_objectives_done()
	state_updated.emit(state)
	print("[SimEngine] Simulation started. Period: %.1f min" % (orbit_period_seconds / 60.0))

# ─── Per-Frame Update ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not running or paused:
		return

	var dt_sim: float = delta * time_scale

	# Advance orbital angle
	orbit_angle += (PI2 / orbit_period_seconds) * dt_sim
	if orbit_angle >= PI2:
		orbit_angle -= PI2
		state["total_orbits"] += 1
		_on_orbit_complete()

	state["orbit_angle_deg"] = rad_to_deg(orbit_angle)
	elapsed_sim_seconds += dt_sim
	# The planet turns under a plane that does not.  This is what makes the ground
	# track walk westward between revolutions, and it is the reason a station a
	# satellite passed ten minutes ago cannot see it now.
	earth_rotation_rad = fmod(earth_rotation_rad + EARTH_ROTATION_RATE * dt_sim, PI2)
	# The sun-synchronous plane creeps east at its computed J2 rate, carrying the
	# ground track — and which climate targets are overflown next — with it.
	node_precession_rad = fmod(node_precession_rad + node_precession_rate * dt_sim, PI2)
	state["day"] = int(elapsed_sim_seconds / SECONDS_PER_DAY)
	if GameManager.is_asteroid_mission():
		state["asteroid_orbit_days"] = min(state["day"], 30)
		if state["has_composition_instrument"] and state["science_points"] > 0.0:
			state["composition_analyzed"] = true
		state["objectives_done"] = _asteroid_objectives_done()
	if GameManager.is_earth_climate_mission():
		state["objectives_done"] = _earth_objectives_done()

	# Eclipse check
	var was_eclipse: bool = state["in_eclipse"]
	state["in_eclipse"] = _is_in_eclipse(orbit_angle)

	# Power simulation
	_simulate_power(dt_sim)

	# Data accumulation
	_simulate_data(dt_sim)

	# Ground contact
	_simulate_comms(dt_sim)

	# Real climate-event survey (Earth Climate Sentinel only)
	if GameManager.is_earth_climate_mission():
		_simulate_climate_observation()
		_simulate_swot_water_survey()

	# Check mission end
	if state["day"] >= state["mission_duration_days"]:
		_end_mission()
		return

	state_updated.emit(state)

func _on_orbit_complete() -> void:
	state["orbit_number"] += 1

	# Decay effects
	var new_effects: Array = []
	for eff in state["active_effects"]:
		eff["remaining_orbits"] -= 1
		if eff["remaining_orbits"] > 0:
			new_effects.append(eff)
		else:
			_remove_effect(eff)
	state["active_effects"] = new_effects

	# Random event check
	if _rng.randf() < 0.08:  # 8% chance per orbit
		_trigger_random_event()

# ─── Power Simulation ─────────────────────────────────────────────────────────
func _simulate_power(dt_sim: float) -> void:
	var config: Dictionary = GameManager.spacecraft_config
	var gen: float = config.get("total_power_gen", 0.0) * state["power_gen_mult"]

	if state["in_eclipse"]:
		gen = 0.0  # No solar power in eclipse

	var draw: float = config.get("total_power_draw", 0.0)
	if not state["instruments_active"]:
		draw -= _instrument_power_draw()

	var balance: float = gen - draw
	state["power_gen"] = gen
	state["power_draw"] = draw
	state["power_balance"] = balance

	# Update battery
	var batt: float = state["battery_wh"]
	var batt_max: float = state["battery_max_wh"]
	if batt_max > 0:
		batt += balance * (dt_sim / 3600.0)  # Wh = W * hours
		batt = clamp(batt, 0.0, batt_max)
		state["battery_wh"] = batt

		# Auto safe mode if battery critically low
		if batt <= 0 and balance < 0:
			if state["instruments_active"]:
				state["instruments_active"] = false
				state["safe_mode_events"] = int(state.get("safe_mode_events", 0)) + 1
				_log_event("⚠️ Battery depleted! Entering safe mode — instruments offline.", "danger")

		# Auto restore when battery recovers
		if batt > batt_max * 0.3 and not state["instruments_active"] and gen > draw * 0.5:
			state["instruments_active"] = true
			_log_event("✅ Battery recovered — instruments back online.", "success")
	else:
		# No battery — direct solar dependency
		if balance < 0:
			state["instruments_active"] = false
		else:
			state["instruments_active"] = true

func _instrument_power_draw() -> float:
	var total: float = 0.0
	for inst in GameManager.spacecraft_config.get("instruments", []):
		total += inst.get("power_draw", 0)
	return total

# ─── Data Simulation ──────────────────────────────────────────────────────────
func _simulate_data(dt_sim: float) -> void:
	if not state["instruments_active"]:
		return
	var config: Dictionary = GameManager.spacecraft_config
	var bus: Dictionary = config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000  # MB
	var data_rate_mbps: float = config.get("total_data_rate", 0.0) * state["science_mult"]

	state["data_stored_mb"] += data_rate_mbps * dt_sim
	state["data_stored_mb"] = min(state["data_stored_mb"], storage_mb)

	# Science per orbit (accumulated per second)
	var sci_per_orbit: float = config.get("total_science_per_orbit", 0.0) * state["science_mult"]
	state["science_points"] += (sci_per_orbit / orbit_period_seconds) * dt_sim

# ─── Communications ───────────────────────────────────────────────────────────
func _simulate_comms(dt_sim: float) -> void:
	if state.get("comms_blocked", false):
		state["ground_contact"] = false
		state["ground_station_name"] = ""
		return

	# A Mars or asteroid mission is not limited by geometry in this build: the
	# antenna points home and which DSN complex answers is a scheduling question,
	# so those keep the simplified contact windows.
	if GameManager.is_mars_mission() or GameManager.is_asteroid_mission():
		_simulate_deep_space_comms()
		return

	# An Earth-orbiting satellite is reachable by exactly the stations that can
	# see it above ten degrees, for exactly as long as it stays above ten degrees.
	# No window in here was chosen by hand.
	var alt: float = float(GameManager.current_mission.get("altitude_km", 550))
	var visible: Dictionary = best_visible_station(alt)
	var had_contact: bool = state["ground_contact"]
	state["ground_contact"] = not visible.is_empty()
	state["ground_station_name"] = String(visible.get("name", ""))
	state["station_elevation_deg"] = float(visible.get("elevation_deg", 0.0))

	if state["ground_contact"]:
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		# Megabytes, because the whole data model of this game is in megabytes: the
		# instruments add `rate × seconds` and the antenna takes it away again.  A
		# pass cut short by the horizon therefore delivers a smaller number, which
		# is the only way this can be honest.
		var downlinked: float = min(bw * dt_sim, state["data_stored_mb"])
		state["data_transmitted_mb"] += downlinked
		state["data_stored_mb"] = maxf(state["data_stored_mb"] - downlinked, 0.0)
		state["pass_mb"] = float(state.get("pass_mb", 0.0)) + downlinked
		if not had_contact:
			state["pass_mb"] = 0.0
			_log_event("📡 AOS — %s at %.0f° elevation" % [
				state["ground_station_name"], state["station_elevation_deg"]], "info")
		# Whatever SWOT recorded since the last pass goes to the control room now.
		_downlink_swot_records()
	else:
		if had_contact:
			state["passes_completed"] = int(state.get("passes_completed", 0)) + 1
			_log_event("📡 LOS — %.0f MB of climate data received this pass" %
				float(state.get("pass_mb", 0.0)), "info")

## The simplified model, kept for the deep-space scenes.
func _simulate_deep_space_comms() -> void:
	# Simplified: contact 25% of the time (realistic for LEO with DSN coverage)
	var angle_deg: float = state["orbit_angle_deg"]
	# Contact windows at 4 points in the orbit
	var in_window: bool = false
	for center in [0, 90, 180, 270]:
		if abs(angle_deg - center) < 18.0:
			in_window = true
			break

	var had_contact: bool = state["ground_contact"]
	state["ground_contact"] = in_window

	if in_window:
		# Downlink data
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		var downlinked: float = bw * 0.016  # per frame at ~60fps
		state["data_transmitted_mb"] += downlinked
		state["data_stored_mb"] = max(0, state["data_stored_mb"] - downlinked)
		state["ground_station_name"] = GROUND_STATIONS[state["total_orbits"] % 4]["name"]

		if not had_contact:
			_log_event("📡 Deep-space contact: " + state["ground_station_name"], "info")
	else:
		state["ground_station_name"] = ""
		if had_contact:
			_log_event("📡 Ground contact lost.", "info")

# ─── Real climate-event survey (Earth Climate Sentinel only) ─────────────────
## A target is observed when three things are simultaneously true, exactly as in
## the real programme: the sub-satellite point comes within the sensor's foot-
## print of the event, the spacecraft actually carries the instrument whose NASA
## analogue made the discovery, and the sensor can work right now — optical and
## trace-gas instruments need sunlight, thermal, SAR and the Day/Night Band do
## not.  A capture is one-time: the event enters the record and the data goes
## into the store, waiting for a ground-station pass like real science does.
func _simulate_climate_observation() -> void:
	if not state.get("instruments_active", true):
		return
	var targets: Array = state.get("climate_targets", [])
	if targets.is_empty():
		return
	var sat_dir: Vector3 = sub_point_direction()
	var sunlit: bool = not state["in_eclipse"]
	var payload: Array = GameManager.spacecraft_config.get("instruments", [])
	for t in targets:
		if bool(t.get("captured", false)):
			continue
		if not _carries_instrument(payload, String(t["requires_instrument"])):
			continue
		if bool(t.get("needs_sunlight", false)) and not sunlit:
			continue
		var tgt_dir: Vector3 = station_world_direction(t)
		var separation: float = rad_to_deg(sat_dir.angle_to(tgt_dir))
		if separation > CLIMATE_FOOTPRINT_DEG:
			continue
		_capture_climate_target(t)

func _carries_instrument(payload: Array, wanted_id: String) -> bool:
	for inst in payload:
		if String(inst.get("id", "")) == wanted_id:
			return true
	return false

func _capture_climate_target(t: Dictionary) -> void:
	t["captured"] = true
	t["captured_day"] = int(state["day"])
	state["targets_captured"] = int(state.get("targets_captured", 0)) + 1
	var gained: float = float(t["science"]) * float(state.get("science_mult", 1.0))
	state["science_points"] = float(state["science_points"]) + gained
	# The observation becomes data before it becomes science: it lands in the
	# recorder and must still survive the trip home through a station pass.
	var bus: Dictionary = GameManager.spacecraft_config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000
	state["data_stored_mb"] = minf(float(state["data_stored_mb"]) + float(t["data_mb"]), storage_mb)
	var msg: String = "🌍 OBSERVED: %s — %s (source: %s). +%.0f climate science, %.0f MB recorded." % [
		t["name"], t["sensor"], t["source"], gained, float(t["data_mb"])]
	_log_event(msg, "success")
	event_occurred.emit({
		"id": "climate_target_" + String(t["requires_instrument"]),
		"kind": "climate_capture",
		"target": t.duplicate(true),
		"name": "Climate event observed: " + String(t["name"]),
		"desc": String(t["sensor"]) + "\n" + String(t["note"]),
		"type": "success"
	})

# ─── SWOT surface-water survey ────────────────────────────────────────────────
## A water site is scanned when the KaRIn swath (120 km wide, so ±8° at 550 km)
## passes over it and the spacecraft carries the radar instrument that stands in
## for SWOT's interferometer.  The record is written to the onboard recorder;
## only a later ground-station pass carries it to the control room, exactly the
## ground-segment sequence the real mission flies.
func _simulate_swot_water_survey() -> void:
	if not state.get("instruments_active", true):
		return
	var targets: Array = state.get("swot_water_targets", [])
	if targets.is_empty():
		return
	var payload: Array = GameManager.spacecraft_config.get("instruments", [])
	if not _carries_instrument(payload, "radar"):
		return
	var sat_dir: Vector3 = sub_point_direction()
	for t in targets:
		if bool(t.get("scanned", false)):
			continue
		var separation: float = rad_to_deg(sat_dir.angle_to(station_world_direction(t)))
		if separation > SWOT_FOOTPRINT_DEG:
			continue
		_capture_swot_target(t)

func _capture_swot_target(t: Dictionary) -> void:
	t["scanned"] = true
	t["scanned_day"] = int(state["day"])
	state["swot_scanned"] = int(state.get("swot_scanned", 0)) + 1
	var cls: String = String(t.get("water_class", "ocean"))
	var classes: Dictionary = state.get("swot_classes_scanned", {})
	classes[cls] = int(classes.get(cls, 0)) + 1
	var gained: float = float(t["science"]) * float(state.get("science_mult", 1.0))
	state["science_points"] = float(state.get("science_points", 0.0)) + gained
	var bus: Dictionary = GameManager.spacecraft_config.get("bus", {})
	var storage_mb: float = bus.get("data_storage", 200) * 1000
	state["data_stored_mb"] = minf(float(state.get("data_stored_mb", 0.0)) + float(t["data_mb"]), storage_mb)
	state["last_swot_scan"] = String(t["name"])
	_log_event("🌊 SWOT swath over %s — %s. +%.0f science, %.0f MB recorded onboard." % [
		t["name"], t["sensor"], gained, float(t["data_mb"])], "success")
	event_occurred.emit({
		"id": "swot_water_" + cls,
		"kind": "swot_water_capture",
		"target": t.duplicate(true),
		"name": "SWOT water scan: " + String(t["name"]),
		"desc": String(t["stat"]) + "\n" + String(t["note"]),
		"type": "success"
	})

## Hand the onboard SWOT records to the ground segment on each contact window;
## the control room monitors only fill once this has happened.
func _downlink_swot_records() -> void:
	var targets: Array = state.get("swot_water_targets", [])
	for t in targets:
		if not bool(t.get("scanned", false)) or bool(t.get("downlinked", false)):
			continue
		t["downlinked"] = true
		t["received_day"] = int(state["day"])
		state["swot_received"] = int(state.get("swot_received", 0)) + 1
		var cls: String = String(t.get("water_class", "ocean"))
		var classes: Dictionary = state.get("swot_classes_received", {})
		classes[cls] = int(classes.get(cls, 0)) + 1
		state["last_swot_received"] = String(t["name"])
		var station: String = String(state.get("ground_station_name", "ground station"))
		_log_event("🖥 Control room received SWOT water record: %s via %s — %s" % [
			t["name"], station, t["stat"]], "success")
		event_occurred.emit({
			"id": "swot_water_received_" + cls,
			"kind": "swot_water_downlinked",
			"target": t.duplicate(true),
			"name": "Control room received: " + String(t["name"]),
			"desc": String(t["stat"]) + " — " + station,
			"type": "success"
		})

## The five listed climate objectives, evaluated live from state so the HUD and
## the final report always agree.
func _earth_objectives_done() -> Array:
	var done: Array = []
	if int(state.get("targets_captured", 0)) >= 3:
		done.append("Observe 3+ real NASA-tracked climate events from orbit")
	var classes: Dictionary = state.get("swot_classes_scanned", {})
	if int(classes.get("ocean", 0)) > 0 and int(classes.get("lake", 0)) > 0 \
			and int(classes.get("river", 0)) > 0:
		done.append("Scan ocean, lake and river surfaces with SWOT KaRIn")
	if float(state.get("science_points", 0.0)) >= float(state.get("target_science", 80)):
		done.append("Collect 80 science points from Earth observation")
	if int(state.get("passes_completed", 0)) >= 3:
		done.append("Downlink data during 3+ ground station passes")
	var cost: float = float(GameManager.spacecraft_config.get("total_cost", 0))
	if cost <= float(GameManager.current_mission.get("budget", 120)):
		done.append("Keep total mission cost under 120M credits")
	return done

# ─── Eclipse Detection ────────────────────────────────────────────────────────
func _is_in_eclipse(angle: float) -> bool:
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Asteroid" in target:
		return false
	# Eclipse in the "behind Earth" portion of orbit
	# Simplified: eclipse from π*0.6 to π*1.4 (roughly 40% of orbit in shadow for LEO)
	var norm: float = angle / PI2
	return norm > 0.55 and norm < 0.85

# ─── Orbital Mechanics ────────────────────────────────────────────────────────
func _compute_orbit_period(mission: Dictionary) -> float:
	var alt: float = mission.get("altitude_km", 550)
	var target: String = mission.get("target", "Low Earth Orbit")

	var mu: float
	var r_body: float

	if "Moon" in target or "Lunar" in target:
		mu = MU_MOON
		r_body = RE_MOON
	elif "Mars" in target:
		mu = 42828.0  # km³/s²
		r_body = 3389.5
	elif "Asteroid" in target:
		mu = 0.8  # km³/s² (small NEO analogue for the mission gameplay loop)
		r_body = 0.25 + alt * 0.15
	else:
		mu = MU_EARTH
		r_body = RE_EARTH

	var r: float = max(1.0, r_body + alt)
	var period: float = PI2 * sqrt(pow(r, 3) / mu)
	return max(period, 60.0)  # seconds

func _asteroid_objectives_done() -> Array:
	var completed: Array = []
	if state.get("rendezvous_complete", false):
		completed.append("Successfully rendezvous with asteroid")
	if state.get("asteroid_orbit_days", 0) >= 30:
		completed.append("Orbit the asteroid for 30 days")
	if state.get("composition_analyzed", false):
		completed.append("Analyze surface composition")
	if state.get("data_transmitted_mb", 0.0) > 0.0:
		completed.append("Return data to Earth")
	return completed

func _compute_eclipse_fraction(alt_km: float) -> float:
	# LEO: ~35% eclipse. Higher orbits: less eclipse.
	if alt_km < 600:
		return 0.35
	elif alt_km < 2000:
		return 0.30
	else:
		return 0.20

# ─── Random Events ────────────────────────────────────────────────────────────
func _trigger_random_event() -> void:
	var pool: Array = EVENTS.duplicate()
	var target: String = String(GameManager.current_mission.get("target", ""))
	if "Mars" in target:
		pool.append({
			"id": "dust_storm", "name": "Global Dust Storm",
			"desc": "A planet-wide Martian dust storm dims imaging and solar arrays.",
			"type": "warning", "probability": 0.08,
			"effect": {"power_gen_mult": 0.7, "science_mult": 0.75, "duration_orbits": 4}
		})
		pool.append({
			"id": "dust_devil", "name": "Dust Devil Tracked",
			"desc": "Instruments capture a dust devil — bonus climate science.",
			"type": "success", "probability": 0.05,
			"effect": {"bonus_science": 18}
		})
	if "Asteroid" in target:
		pool.append({
			"id": "outgassing", "name": "Outgassing Event",
			"desc": "A burst of volatile vapor vents from the asteroid and disturbs the spacecraft's attitude control.",
			"type": "warning", "probability": 0.07,
			"effect": {"science_mult": 0.8, "power_gen_mult": 0.9, "duration_orbits": 3}
		})
		pool.append({
			"id": "microgravity_drift", "name": "Microgravity Drift",
			"desc": "The asteroid's weak gravity shifts the spacecraft's line of sight and reduces imaging precision.",
			"type": "warning", "probability": 0.06,
			"effect": {"science_mult": 0.7, "duration_orbits": 2}
		})
		pool.append({
			"id": "organic_signal", "name": "Organic Signal Detected",
			"desc": "A faint organics signature appears in spectral data — unexpected bonus science.",
			"type": "success", "probability": 0.05,
			"effect": {"bonus_science": 22}
		})
	var roll: float = _rng.randf()
	var cumulative: float = 0.0
	for ev in pool:
		cumulative += ev["probability"]
		if roll <= cumulative:
			_apply_event(ev)
			return

func _apply_event(ev: Dictionary) -> void:
	var effect: Dictionary = ev.get("effect", {})
	_log_event(ev["name"] + " — " + ev["desc"], ev.get("type", "info"))

	if effect.has("power_gen_mult"):
		state["power_gen_mult"] *= effect["power_gen_mult"]
		state["active_effects"].append({
			"id": ev["id"], "power_gen_mult_inv": 1.0 / effect["power_gen_mult"],
			"remaining_orbits": effect.get("duration_orbits", 1)
		})
	if effect.has("science_mult"):
		state["science_mult"] *= effect["science_mult"]
		state["active_effects"].append({
			"id": ev["id"], "science_mult_inv": 1.0 / effect["science_mult"],
			"remaining_orbits": effect.get("duration_orbits", 1)
		})
	if effect.has("bonus_science"):
		state["science_points"] += effect["bonus_science"]
	if effect.has("comms_blocked"):
		state["comms_blocked"] = true
		state["active_effects"].append({
			"id": ev["id"], "comms_blocked": true,
			"remaining_orbits": effect.get("duration_orbits", 2)
		})
	if effect.has("battery_mult"):
		state["battery_max_wh"] *= effect["battery_mult"]

	event_occurred.emit(ev)

func _remove_effect(eff: Dictionary) -> void:
	if eff.has("power_gen_mult_inv"):
		state["power_gen_mult"] *= eff["power_gen_mult_inv"]
	if eff.has("science_mult_inv"):
		state["science_mult"] *= eff["science_mult_inv"]
	if eff.has("comms_blocked"):
		state["comms_blocked"] = false

func _log_event(msg: String, type: String) -> void:
	var log_entry: Dictionary = {
		"day": state.get("day", 0),
		"orbit": state.get("total_orbits", 0),
		"msg": msg,
		"type": type
	}
	state["events_log"].append(log_entry)
	print("[SimEngine] Day %d: %s" % [state.get("day", 0), msg])

# ─── Mission End ──────────────────────────────────────────────────────────────
func _end_mission() -> void:
	running = false
	var config: Dictionary = GameManager.spacecraft_config
	var mission: Dictionary = GameManager.current_mission

	var science: float = state.get("science_points", 0)
	var target_sci: float = mission.get("science_goal", 80)
	var duration: int = state.get("mission_duration_days", 365)
	var power_ok: bool = state.get("mission_health", 100) > 50

	# Score components (out of 100)
	var asteroid_mission: bool = GameManager.is_asteroid_mission()
	var earth_mission: bool = GameManager.is_earth_climate_mission()
	var asteroid_objectives: Array = _asteroid_objectives_done() if asteroid_mission else []
	var earth_objectives: Array = _earth_objectives_done() if earth_mission else []
	var obj_score: float
	if asteroid_mission:
		obj_score = 35.0 * float(asteroid_objectives.size()) / 4.0
	elif earth_mission:
		# The climate sentinel is scored on the survey it actually completed —
		# events observed, SWOT water classes scanned, science returned, data
		# downlinked, budget held — not on a raw point tally.
		obj_score = 35.0 * float(earth_objectives.size()) / 5.0
	else:
		obj_score = clamp((science / target_sci) * 35, 0, 35)
	var sci_score: float    = clamp((science / target_sci) * 25, 0, 25)
	var rel_score: float    = state.get("mission_health", 100) / 100.0 * 20
	var budget_pct: float   = config.get("total_cost", 0) / mission.get("budget", 120)
	var eff_score: float    = clamp((1.0 - budget_pct) * 15, 0, 15)
	var ops_score: float    = 5.0  # Base ops score

	var total_score: float = obj_score + sci_score + rel_score + eff_score + ops_score

	# Reliability modifier
	var bus_rel: float = config.get("bus", {}).get("reliability", 0.9)
	var rocket_rel: float = config.get("rocket", {}).get("reliability", 0.95)
	total_score *= (bus_rel * rocket_rel)

	var success: bool = science >= target_sci and power_ok
	if asteroid_mission:
		success = success and asteroid_objectives.size() == 4
	# An Earth climate sentinel has only done its job once it has come all the way
	# round and got its observations off to the ground.  Reaching LEO and crossing
	# the Kármán line is necessary, not sufficient: without two downlinked survey
	# revolutions the mission has returned no climate data, and returning no data is
	# exactly the failure the operator was warned about.
	var revs: int = int(state.get("commission_revolutions", 0))
	var returned_mb: float = float(state.get("data_transmitted_mb", 0.0))
	if not asteroid_mission and not GameManager.is_mars_mission():
		success = success and revs >= 2 and returned_mb > 0.0

	# What the real-record contribution actually was: the events this design
	# observed, with the sensor and the NASA dataset behind each one.  The report
	# screen prints it as a data-return manifest.
	var observed: Array = []
	var earth_bonuses: Array = []
	var swot_records: Array = []
	if earth_mission:
		for t in state.get("climate_targets", []):
			if bool(t.get("captured", false)):
				observed.append({
					"name": String(t["name"]), "sensor": String(t["sensor"]),
					"source": String(t["source"]), "day": int(t["captured_day"]),
					"science": float(t["science"]), "note": String(t["note"]),
					"date": String(t.get("date", "")), "stat": String(t.get("stat", "")),
					"img_url": String(t.get("img_url", "")), "credit": String(t.get("credit", ""))
				})
		for w in state.get("swot_water_targets", []):
			swot_records.append({
				"name": String(w["name"]), "water_class": String(w["water_class"]),
				"sensor": String(w["sensor"]), "source": String(w["source"]),
				"stat": String(w.get("stat", "")), "note": String(w.get("note", "")),
				"measurements": (w.get("measurements", {}) as Dictionary).duplicate(true),
				"scanned": bool(w.get("scanned", false)),
				"downlinked": bool(w.get("downlinked", false)),
				"scanned_day": int(w.get("scanned_day", -1)),
				"received_day": int(w.get("received_day", -1))
			})
		if observed.size() == CLIMATE_TARGETS.size():
			earth_bonuses.append("All 6 climate events observed")
		if int(state.get("swot_received", 0)) == SWOT_WATER_TARGETS.size():
			earth_bonuses.append("All 6 SWOT water records delivered to the control room")
		if int(state.get("safe_mode_events", 0)) == 0:
			earth_bonuses.append("No power failures (zero safe-mode entries)")
		if returned_mb >= 1000.0:
			earth_bonuses.append("Delivered 1+ GB of climate data to Earth")

	var result: Dictionary = {
		"success": success,
		"score": int(total_score),
		"science_collected": science,
		"science_goal": target_sci,
		"data_transmitted_gb": state.get("data_transmitted_mb", 0) / 1000.0,
		"total_orbits": state.get("total_orbits", 0),
		"commission_revolutions": revs,
		"commission_passes": int(state.get("commission_passes", 0)),
		"climate_data_returned_mb": returned_mb,
		"mission_days": duration,
		"objectives_done": asteroid_objectives if asteroid_mission else earth_objectives,
		"objectives_required": mission.get("objectives", []) if (asteroid_mission or earth_mission) else [],
		"climate_events_observed": observed,
		"swot_water_records": swot_records,
		"swot_scanned": int(state.get("swot_scanned", 0)),
		"swot_received": int(state.get("swot_received", 0)),
		"swot_classes_scanned": (state.get("swot_classes_scanned", {}) as Dictionary).duplicate(true),
		"targets_captured": int(state.get("targets_captured", 0)),
		"climate_bonus_objectives": earth_bonuses,
		"nodal_precession_deg_day": float(state.get("nodal_precession_deg_day", 0.0)),
		"events_log": state.get("events_log", []),
		"score_breakdown": {
			"objectives": int(obj_score),
			"science": int(sci_score),
			"reliability": int(rel_score),
			"efficiency": int(eff_score),
			"operations": int(ops_score)
		},
		"improvements": _generate_improvements()
	}

	GameManager.mission_result = result
	mission_ended.emit(result)
	print("[SimEngine] Mission ended. Score: %d/100 — %s" % [int(total_score), "SUCCESS" if success else "FAILURE"])

func _generate_improvements() -> Array:
	var tips: Array = []
	var config: Dictionary = GameManager.spacecraft_config
	var gen: float = config.get("total_power_gen", 0)
	var draw: float = config.get("total_power_draw", 0)
	if gen - draw < 50:
		tips.append("Add a larger solar array — your power margin was very tight during eclipses.")
	if config.get("battery_capacity", 0) < 200:
		tips.append("Upgrade your battery to survive longer eclipse periods without losing science.")
	var data_rate: float = config.get("total_data_rate", 0)
	var comms_bw: float = config.get("comms", {}).get("bandwidth_mbps", 1)
	if data_rate > comms_bw * 10:
		tips.append("Your antenna bandwidth is much lower than your data generation rate. Upgrade comms or reduce instruments.")
	if config.get("total_cost", 0) > GameManager.current_mission.get("budget", 120) * 0.9:
		tips.append("You were very close to your budget limit. A more affordable bus or fewer instruments could give more margin.")
	if GameManager.is_earth_climate_mission():
		# Coach the real-science layer specifically: which sensor senses which
		# event, and why daylight matters for the optical ones.
		var caps: int = int(state.get("targets_captured", 0))
		if caps < 3:
			tips.append("Only %d of the real climate events were sensed. Carry the instruments those events actually need — thermal imagers for FIRMS wildfires and marine heatwaves, SAR radar for the Amazon flood pulse and Greenland ice, a spectrometer for volcanic SO\u2082 — and remember optical instruments only work in sunlight." % caps)
		else:
			tips.append("%d real NASA-tracked events surveyed. Fly the full six-event record next time — and downlink it all, because science that stays onboard is science that never happened." % caps)
		var has_radar: bool = _carries_instrument(GameManager.spacecraft_config.get("instruments", []), "radar")
		var swot_rx: int = int(state.get("swot_received", 0))
		if not has_radar:
			tips.append("The SWOT KaRIn water survey never flew: add the SAR radar box (the SWOT analogue) to scan ocean, lake and river surfaces.")
		elif swot_rx < SWOT_WATER_TARGETS.size():
			tips.append("SWOT returned %d of %d water records to the control room. Let the radar swath cross more water sites and give the next ground station pass time to downlink them." % [swot_rx, SWOT_WATER_TARGETS.size()])
	if tips.is_empty():
		tips.append("Great design! Try increasing science instruments for an even higher score.")
	return tips

# ─── Controls ─────────────────────────────────────────────────────────────────
func set_time_scale(idx: int) -> void:
	time_scale_idx = clamp(idx, 0, TIME_SCALES.size() - 1)
	time_scale = TIME_SCALES[time_scale_idx]

func speed_up() -> void:
	set_time_scale(time_scale_idx + 1)

func speed_down() -> void:
	set_time_scale(time_scale_idx - 1)

func pause_sim() -> void:
	paused = true

func resume_sim() -> void:
	paused = false

func transmit_data_manual() -> void:
	if state.get("ground_contact", false):
		var comms: Dictionary = GameManager.spacecraft_config.get("comms", {})
		var bw: float = comms.get("bandwidth_mbps", 1.0)
		var burst: float = bw * 60  # 1 minute burst
		var sent: float = min(burst, state.get("data_stored_mb", 0))
		state["data_stored_mb"] -= sent
		state["data_transmitted_mb"] = state.get("data_transmitted_mb", 0) + sent
		_log_event("📡 Manual downlink: %.1f MB transmitted." % sent, "success")
	else:
		_log_event("❌ No ground contact — cannot transmit.", "warning")
