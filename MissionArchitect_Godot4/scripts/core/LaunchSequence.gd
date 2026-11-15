## LaunchSequence.gd
## Cinematic rocket launch — ground to orbit with dynamic cameras, VFX, sky transition

extends Node3D

# Shared procedural launch-vehicle builder (preloaded by path so it works even
# before the editor registers the new global class name).
const RocketFactoryScript := preload("res://scripts/spacecraft/RocketFactory.gd")

# ─── Scene Nodes ──────────────────────────────────────────────────────────────
var rocket: Node3D                    = null
var rocket_mesh: MeshInstance3D       = null
var exhaust_particles: GPUParticles3D = null
var smoke_particles: GPUParticles3D = null
var dust_particles: GPUParticles3D = null
var engine_light: OmniLight3D = null
var plume_core: MeshInstance3D = null
var plume_outer: MeshInstance3D = null
var plume_diamonds: Array[MeshInstance3D] = []
var world_env: WorldEnvironment       = null
var sky_material: ProceduralSkyMaterial = null
var env_sun: DirectionalLight3D = null

# Multiple cameras for cinematic cuts
var cam_pad: Camera3D   = null   # ground-level close-up at pad
var cam_engine: Camera3D = null  # short ignition/engine close-up
var cam_chase: Camera3D = null   # follows rocket up
var cam_space: Camera3D = null   # wide angle in upper atmosphere
var cam_tower: Camera3D = null   # side view framed on the launch tower
var cam_wide: Camera3D = null    # distant wide establishing shot
var cam_recovery: Camera3D = null # films the returning first stage
var active_camera: Camera3D = null

# UI
var countdown_label: Label
var altitude_label: Label
var velocity_label: Label
var flight_path_label: Label
var acceleration_label: Label
var orbit_estimate_label: Label
var fuel_bar: ProgressBar
var throttle_bar: ProgressBar
var throttle_label: Label
var stage_label: Label
var phase_label: Label
var status_label: Label
var launch_btn: Button
var abort_btn: Button

# Themed "Launch Control" overlay (built in code; see _rebuild_launch_overlay).
var mission_name_label: Label
var vehicle_name_label: Label
var target_name_label: Label
var t_speed_label: Label
var t_accel_label: Label
var t_vspd_label: Label
var t_hspd_label: Label
var t_traj_label: Label
var t_fpa_label: Label
var t_downrange_label: Label
var step_dots: Array[Control] = []
var step_labels: Array[Label] = []
var step_counter_label: Label
var cam_buttons: Array[Button] = []
var cam_modes: Array = []
var cam_sel: int = 0
var fuel_pct_label: Label
var throttle_pct_label: Label
var fuel_caption_label: Label
var insertion_info_label: Label
var met_label: Label
var warp_label: Label
var left_panel: PanelContainer = null
var met_seconds_shown: int = -1

# Launch-Control theme (premium black & white HUD).
const UI_ACCENT  := Color("#FFFFFF")
const UI_ACCENT2 := Color("#B3B3B3")
const UI_BG      := Color(0, 0, 0, 0.80)
const UI_BG_SOFT := Color(0.039, 0.039, 0.039, 0.72)
const UI_BORDER  := Color("#333333")
const UI_TEXT    := Color("#FFFFFF")
const UI_DIM     := Color("#B3B3B3")
const UI_GREEN   := Color("#FFFFFF")
const UI_RED     := Color("#D9D9D9")

# ─── State Machine ────────────────────────────────────────────────────────────
enum LaunchState { PRE_LAUNCH, COUNTDOWN, LIFTOFF, MAX_Q,
                   STAGE_SEP, FAIRING_SEP, ORBITAL_INSERT,
                   SATELLITE_DEPLOY, COMPLETE }
var state: LaunchState = LaunchState.PRE_LAUNCH

# ─── Physics ──────────────────────────────────────────────────────────────────
# The ascent integrates a genuine two-body trajectory in *mission seconds*; the
# player watches a time-compressed version of it.  Every number on the HUD is
# therefore an honest number: Max-Q near 11 km, MECO near 70 km, and an orbit
# whose apogee and perigee converge on the mission's target altitude.
var altitude_km: float   = 0.0
var velocity_ms: float   = 0.0
var fuel_pct: float      = 100.0
var throttle: float      = 0.0
var rocket_mass: float   = 549000.0
var dry_mass: float      = 25000.0
var thrust_kN: float     = 7600.0
var isp: float           = 311.0
var gravity: float       = 9.8
var countdown_timer: float = 10.0
var state_timer: float   = 0.0
var auto_throttle: bool  = true
var stage_number: int = 1
var stage_2_thrust_kN: float = 981.0
var stage_2_propellant_kg: float = 110000.0
var stage_2_dry_mass_kg: float = 4500.0
var payload_mass_kg: float = 500.0
# Per-stage bookkeeping.  "Fuel" on the HUD is the *active* stage's propellant,
# which is what a real launch display shows; the caption changes at staging so a
# fresh 100 % after MECO reads as a stage switch rather than a refill glitch.
var stage_1_propellant_kg: float = 395000.0
var stage_1_dry_mass_kg: float = 22000.0
var fairing_mass_kg: float = 1700.0
var propellant_total_kg: float = 395000.0
var propellant_left_kg: float = 395000.0
var inert_mass_kg: float = 154000.0
var vertical_velocity_ms: float = 0.0
var horizontal_velocity_ms: float = 0.0
var downrange_km: float = 0.0
var dynamic_pressure_kpa: float = 0.0
var axial_g: float = 0.0
var apoapsis_km: float = 0.0
var periapsis_km: float = -6371.0
var gravity_turn_deg: float = 0.0
const EARTH_RADIUS_KM: float = 6371.0
const EARTH_MU_KM3_S2: float = 398600.4418
const REFERENCE_AREA_M2: float = 10.8
const DRAG_COEFFICIENT: float = 0.38
var mars_payload: bool = false
var body_radius_km: float = EARTH_RADIUS_KM
var body_mu: float = EARTH_MU_KM3_S2
var surface_gravity: float = 9.80665
var air_density_sl: float = 1.225
var scale_height_km: float = 8.5
var orbit_speed_target: float = 6500.0
var periapsis_ready_km: float = 120.0
var sky_top_day: Color = Color(0.08, 0.18, 0.52, 1.0)
var sky_horizon_day: Color = Color(0.55, 0.68, 0.90, 1.0)
var ground_bottom_day: Color = Color(0.18, 0.22, 0.16, 1.0)
var ground_horizon_day: Color = Color(0.38, 0.42, 0.32, 1.0)

# ─── Mission clock and guided flight ──────────────────────────────────────────
# Mission elapsed time in real seconds, and the factor by which the simulation
# is currently being run.  There is no phase-aware compression any more: the
# mission clock is wall time and `sim_speed` is purely the warp step the player
# selected (times the verification multiplier), so the flight really does take
# the minutes its clock prints.
var met_seconds: float = 0.0
var sim_speed: float = 1.0
var target_orbit_km: float = 550.0
var target_inclination_deg: float = 97.6
var attitude_deg: float = 90.0        # nose angle above the local horizon
var pitch_rate_limit_dps: float = 1.6 # gimbals slew, they do not snap
const MAX_AXIAL_G: float = 4.2        # structural load limit, throttles the engine
var max_q_kpa: float = 0.0
var max_q_throttle_pct: float = 100.0   # what the engines were actually held at
var max_q_declared: bool = false
var superq_beat_done: bool = false
var meco_done: bool = false
var fairing_jettisoned: bool = false
var seco_done: bool = false
enum InsertionPhase { NONE, RAISE_APOAPSIS, COAST_TO_APOGEE, CIRCULARISE, DONE }
var insertion_phase: InsertionPhase = InsertionPhase.NONE
var coast_timer: float = 0.0
var flight_id: String = "falcon9"
var _debug_warp: float = 1.0
const MAX_SIM_STEP_S: float = 0.1
var _sim_accumulator: float = 0.0

# ─── Visual ───────────────────────────────────────────────────────────────────
# Rocket starts at world Y = LAUNCH_PAD_Y (on top of pad)
# As altitude increases, rocket moves UP from there
const LAUNCH_PAD_Y: float   = 7.0     # matches scene transform
const KM_TO_UNITS: float    = 0.8     # visual scale near the pad
# Ascent height uses a saturating curve instead of a hard cap.  The old
# `min(altitude * 0.8, 300)` froze the vehicle at 375 km, so the whole orbital
# phase had no translation at all — the single biggest reason space read as a
# still image.
# The exponent is what makes the *ascent* read correctly: a near-linear rise
# leaves the vehicle only ~35 units above a 60-unit-wide spaceport after 8 km of
# real flight, so the pad still fills the frame and looks like a floating island
# on top of a planet.  A sub-linear power curve puts the vehicle more than a
# hundred units up by then, which is what an 8 km altitude actually looks like
# from a chase camera.
const ASCENT_VISUAL_RISE: float = 620.0
const ASCENT_VISUAL_KM_FULL: float = 130.0
const ASCENT_VISUAL_EXP: float = 0.4
# Once the vehicle is above the atmosphere it stops "going up" and starts
# *orbiting*: a fixed space-frame centre, a large Earth rotating underneath it,
# and a vehicle that arcs along the limb against a star shell that never
# translates with it.  That relative motion is what sells orbital velocity.
const SPACE_ALTITUDE_KM: float = 100.0
const ORBIT_EARTH_RADIUS_VIS: float = 340.0
const ORBIT_ALTITUDE_VIS: float = 46.0
const EARTH_SPIN_REAL: float = 7.292e-5   # rad/s, the planet's actual rate
# Stylised planet the vehicle climbs away from.  Deliberately far smaller than a
# true-scale Earth: at real scale the horizon dip at 20 km is two thirds of a
# degree and invisible, so nothing would ever read as altitude.
const HORIZON_RADIUS: float = 1500.0
const HORIZON_TAKEOVER_KM: float = 0.9
var horizon_world: Node3D = null
var horizon_pivot: Node3D = null
var horizon_body: MeshInstance3D = null
var horizon_haze: MeshInstance3D = null
var horizon_active: bool = false
var horizon_spin: float = 0.0
var pad_shrink: float = 1.0

# The atmosphere the vehicle actually climbs through.  Space begins 100 km up at
# the Kármán line, and between the pad and that line there is a stack of weather:
# a boundary-layer haze, two cumulus decks, the overcast layer and a cirrus veil,
# then the dry, cloud-free stratosphere.  Each deck is a translucent shell placed
# concentric with the planetary surface at the *scene* height the vehicle reaches
# at that true altitude, so the rocket passes through them in the right order.
const CLOUD_DECKS := [
	{"alt_km": 0.9,  "cover": 0.42, "freq": 0.0450, "opacity": 0.66, "soft": 0.30},
	{"alt_km": 3.4,  "cover": 0.62, "freq": 0.0300, "opacity": 0.82, "soft": 0.22},
	{"alt_km": 8.2,  "cover": 0.52, "freq": 0.0200, "opacity": 0.70, "soft": 0.26},
	# The top deck is cirrus, not overcast.  Kept thin and broken: seen from below
	# against a sky already going black, a high-coverage layer reads as a cow-pattern
	# stencil rather than as ice crystals eight kilometres up.
	{"alt_km": 12.6, "cover": 0.24, "freq": 0.0140, "opacity": 0.30, "soft": 0.34},
]
# Named flight layers, quoted on screen so the player can see which one the
# vehicle is in and how much air is left under it.
const ATMO_LAYERS := [
	{"name": "TROPOSPHERE",  "top_km": 13.0},
	{"name": "STRATOSPHERE", "top_km": 50.0},
	{"name": "MESOSPHERE",   "top_km": 85.0},
	{"name": "THERMOSPHERE", "top_km": 700.0},
]
# Announced crossings.  The Kármán line itself is handled by the space-frame
# handover, so it is deliberately not repeated here.
const LAYER_BEATS := [
	{"alt_km": 1.0,  "text": "CLOUD DECK — 1 KM", "line": "Punching through the low stratus. This is the weather the forecast warned about."},
	{"alt_km": 3.6,  "text": "SECOND CLOUD LAYER — 3.6 KM", "line": "Above the boundary layer now: the decks thin out and the sun gets sharper."},
	{"alt_km": 13.0, "text": "TROPOPAUSE — 13 KM, ABOVE ALL THE WEATHER", "line": "Every cloud on Earth is underneath you. The air ahead is dry and completely clear."},
	{"alt_km": 50.0, "text": "STRATOPAUSE — 50 KM", "line": "Less than one thousandth of sea-level air left below. The sky is going out."},
	{"alt_km": 85.0, "text": "MESOSPHERE — 85 KM", "line": "Fifteen kilometres from space. The atmosphere is now a rumour."},
]
# The flight profile, named the way a mission controller names it.  Reaching 100
# km is one line on this list and is *not* the mission: the vehicle is only in
# orbit once it is going sideways at orbital speed, so the last two phases are
# driven by the state machine, not by altitude.
const FLIGHT_PHASES := [
	{"alt_km": 0.0,   "name": "LIFTOFF",          "line": "Vertical rise. All the effort is going into height."},
	{"alt_km": 10.0,  "name": "GRAVITY TURN",     "line": "The nose comes over. Height is bought — now the mission wants sideways speed."},
	{"alt_km": 50.0,  "name": "UPPER ATMOSPHERE", "line": "The last of the air. Above 50 km there is nothing left to push against."},
	{"alt_km": 100.0, "name": "SPACE ASCENT",     "line": "Kármán line crossed, but still falling around the Earth. Speed is the only thing that fixes that."},
	{"alt_km": 180.0, "name": "COAST TO APOGEE",  "line": "Engines off, riding the ellipse uphill to the point where the orbit will be closed."},
]
# ─── First stage recovery ─────────────────────────────────────────────────────
# A modern launcher does not stop being interesting when it runs out of fuel.  The
# first stage flips over, relights three engines to throw away its downrange
# speed, catches itself again on the way back through the air and lands under
# power a few minutes after it left the pad.  The return is now *flown*, not
# replayed: _booster_physics() integrates the same two-body + drag equations the
# ascent uses, with a real propellant budget taken from the stage at separation.
# The table below is kept only as the tuning reference it grew from — the numbers
# a correct flight should land near — and nothing reads it any more.
const RECOVERY_PROFILE := [
	{"dt": 0.0,   "alt_km": 100.0, "spd_ms": 2480.0, "burn": 0.0, "prop_t": 41.0, "legs": 0.0, "phase": "SEPARATION"},
	{"dt": 3.0,   "alt_km": 100.0, "spd_ms": 2440.0, "burn": 0.0, "prop_t": 41.0, "legs": 0.0, "phase": "FLIP AND LIGHT"},
	{"dt": 7.0,   "alt_km": 99.0,  "spd_ms": 2350.0, "burn": 0.9, "prop_t": 38.0, "legs": 0.0, "phase": "BOOSTBACK BURN"},
	{"dt": 34.0,  "alt_km": 95.0,  "spd_ms": 1330.0, "burn": 0.9, "prop_t": 24.0, "legs": 0.0, "phase": "BOOSTBACK BURN"},
	{"dt": 40.0,  "alt_km": 94.0,  "spd_ms": 1260.0, "burn": 0.0, "prop_t": 23.5, "legs": 0.0, "phase": "COASTING BACK"},
	{"dt": 120.0, "alt_km": 80.0,  "spd_ms": 1560.0, "burn": 0.0, "prop_t": 23.5, "legs": 0.0, "phase": "COASTING BACK"},
	{"dt": 152.0, "alt_km": 71.0,  "spd_ms": 1890.0, "burn": 0.0, "prop_t": 23.0, "legs": 0.0, "phase": "ENTRY INTERFACE"},
	{"dt": 158.0, "alt_km": 68.0,  "spd_ms": 1860.0, "burn": 0.8, "prop_t": 20.0, "legs": 0.0, "phase": "ENTRY BURN"},
	{"dt": 196.0, "alt_km": 44.0,  "spd_ms": 820.0,  "burn": 0.8, "prop_t": 11.5, "legs": 0.0, "phase": "ENTRY BURN"},
	{"dt": 206.0, "alt_km": 38.0,  "spd_ms": 700.0,  "burn": 0.0, "prop_t": 11.0, "legs": 0.0, "phase": "GRID FIN DESCENT"},
	{"dt": 300.0, "alt_km": 12.0,  "spd_ms": 380.0,  "burn": 0.0, "prop_t": 10.0, "legs": 0.0, "phase": "GRID FIN DESCENT"},
	{"dt": 330.0, "alt_km": 5.0,   "spd_ms": 210.0,  "burn": 0.0, "prop_t": 9.0,  "legs": 0.4, "phase": "FINAL APPROACH"},
	{"dt": 345.0, "alt_km": 2.6,   "spd_ms": 165.0,  "burn": 1.0, "prop_t": 7.4,  "legs": 1.0, "phase": "LANDING BURN"},
	{"dt": 360.0, "alt_km": 1.1,   "spd_ms": 95.0,   "burn": 1.0, "prop_t": 5.2,  "legs": 1.0, "phase": "LANDING BURN"},
	{"dt": 375.0, "alt_km": 0.3,   "spd_ms": 42.0,   "burn": 1.0, "prop_t": 3.4,  "legs": 1.0, "phase": "LANDING BURN"},
	{"dt": 390.0, "alt_km": 0.02,  "spd_ms": 12.0,   "burn": 1.0, "prop_t": 2.5,  "legs": 1.0, "phase": "LANDING BURN"},
	{"dt": 396.0, "alt_km": 0.0,   "spd_ms": 2.0,    "burn": 0.0, "prop_t": 2.3,  "legs": 1.0, "phase": "TOUCHDOWN"},
]
const RECOVERY_SEP_ALT_KM: float = 100.0
const RECOVERY_SEP_SPD_MS: float = 2480.0
# What each moment of the return is called, and what it means.  The narration is
# kept next to the profile it belongs to so the two cannot drift apart.
const RECOVERY_BEATS := {
	"FLIP AND LIGHT": {
		"text": "BOOSTER FLIP — IT TURNS AROUND IN EMPTY SPACE",
		"line": "Cold gas thrusters swing the spent stage engines-first. Nine Merlin nozzles are now pointing at the planet.",
		"cue": 520.0,
	},
	"BOOSTBACK BURN": {
		"text": "BOOSTBACK BURN — THREE ENGINES, HEADING HOME",
		"line": "Three engines light to throw away the downrange speed. This is the part an expendable rocket never gets to do.",
		"cue": 150.0,
	},
	"ENTRY INTERFACE": {
		"text": "RE-ENTRY — THE STAGE HITS THE AIR AGAIN",
		"line": "Falling back into the atmosphere at over 1,500 m/s. Ahead of it the air is already beginning to slow it down.",
		"cue": 880.0,
	},
	"ENTRY BURN": {
		"text": "ENTRY BURN — SLOWING DOWN IN THE TOP OF THE AIR",
		"line": "Three engines again, this time against re-entry heating and peak deceleration. The plasma is the exhaust, not the air.",
		"cue": 168.0,
	},
	"GRID FIN DESCENT": {
		"text": "GRID FINS STEERING THE DESCENT",
		"line": "Engines off for now. Two lattice fins walk the stage down through the air, still correcting for the crosswind.",
		"cue": 700.0,
	},
	"FINAL APPROACH": {
		"text": "LANDING LEGS DOWN — FIVE KILOMETRES TO THE PAD",
		"line": "Four carbon legs swing out and lock. The centre engine relights fifteen seconds before it reaches them.",
		"cue": 980.0,
	},
	"LANDING BURN": {
		"text": "LANDING BURN — THRUST JUST ABOVE WEIGHT",
		"line": "A single engine, throttled to hover slightly above its own mass, walking down onto the pad it lifted off from.",
		"cue": 132.0,
	},
}
# How long the shot holds on the landed stage before cutting back to the vehicle.
# Wall seconds, because it is a beat rather than a phase of flight.
const RECOVERY_HOLD_S: float = 4.5
# The return is not a camera cut.  From the moment the stage parts company with
# the upper stage the screen owns two pictures at once: the left half films the
# stage coming home, the right half keeps filming the vehicle going to orbit, and
# because both are the same World3D at the same instant they cannot drift apart.
# The split is event-driven: it opens just after separation and closes a few
# seconds after whatever happens at the deck — the table clock it replaced no
# longer decides anything.
const SPLIT_WIDTH_FRACTION: float = 0.5
# The return is flown by physics, so the shot no longer follows a scripted
# speed curve — the player's warp control is the only compression in the scene
# and the camera's framing reads the stage's real altitude.  The constants below
# are the stage's own flight hardware: three engines for the boostback and entry
# burns, one for the landing, the drag areas its fins and gear add, and the
# guidance rules a real recovery uses (boost until the pad is reachable
# ballistically, flip the entry burn against the speed, relight at the height
# that just kills the descent).
# Visual stand-off of the deck above the space-frame planet, and the compressed
# height the descent is filmed in.  A 70 km fall is nine units on the orbital
# scale — the vehicle model alone is ten units long — so the descent gets its own
# saturating height curve, exactly the way the ascent climb does.
const RECOVERY_DECK_VIS: float = 2.2
# The stage's model is placed by its centre, and its deployed legs reach about
# eight units below that centre, so the centre has to stand that far off the deck
# for the feet to be *on* the deck rather than through it.  The engine bell ends
# up a unit or two above the surface, exactly as it does on the real vehicle.
const BOOSTER_STAND_UNITS: float = 8.0
const RECOVERY_VISUAL_SPAN: float = 172.0
const RECOVERY_VISUAL_KM_FULL: float = 110.0
const RECOVERY_VISUAL_EXP: float = 0.62
# The returning stage's flight hardware.  These are the numbers the booster's
# own integrator flies with; everything the shot shows is a consequence of them.
const BOOSTER_ISP_S := 280.0
const BOOSTER_BB_THR_FRAC := 0.77      # three engines, boostback and entry
const BOOSTER_LAND_THR_FRAC := 0.28    # one engine, landing burn
const BOOSTER_CD_A_FINNED := 60.0      # grid fins deployed, m² of drag area
const BOOSTER_CD_A_CLEAN := 12.0
const BOOSTER_HARDWARE_KG := 3600.0    # legs, fins, avionics on the dry stage
const BOOSTER_FLIP_S := 8.0
const BOOSTER_FLIP_BURN_LAG := 4.0
const BOOSTER_ENTRY_INTERFACE_KM := 70.0
const BOOSTER_ENTRY_IGNITE_LAG_S := 6.0
const BOOSTER_ENTRY_CUTOFF_MS := 450.0
const BOOSTER_ENTRY_MAX_S := 40.0
const BOOSTER_ENTRY_DECEL_G := 4.5     # throttle limit: the burn flies to this load
const BOOSTER_BB_FLOOR_KG := 16000.0   # never spend the entry/landing budget
const BOOSTER_LANDING_RESERVE_KG := 5000.0
const BOOSTER_GEAR_ALT_KM := 6.0
const BOOSTER_LAND_A_NET_G := 1.5
const BOOSTER_LAND_MARGIN_M := 300.0
const BOOSTER_LAND_PROFILE_MARGIN := 1.2   # overshoot the exact-stop decel slightly
const BOOSTER_LAND_CUTOFF_M := 1.2
const BOOSTER_OK_TOUCH_MS := 8.0
const BOOSTER_RETURN_COAST_S := 260.0  # ballistic time from cutoff to the air
const BOOSTER_RESERVE_FRAC := 0.145    # S1 propellant held back for recovery

## Patchy cloud decks.  Value-noise fbm evaluated on *world* position, which
## avoids the UV seam and the pole pinch a sphere's own UVs would give; the
## coverage threshold is anti-aliased with fwidth, because a hard threshold on a
## noise field crawls with alias as the camera sweeps across it.
const CLOUD_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform float cover   : hint_range(0.0, 1.0) = 0.55;
uniform float freq    = 0.005;
uniform float opacity = 0.6;
uniform float soft    = 0.25;
uniform float drift   = 0.0;
uniform float fade    = 1.0;
// No hint on the sun vector: Godot 4's `hint_normal` is a sampler hint, not a
// vec3 one, so the direction is normalised from GDScript instead.
uniform vec3  sun_dir = vec3(0.45, 0.72, 0.35);

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash13(vec3 p) {
	p = fract(p * 0.318309891 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
				   mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
				   mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float amp = 0.55;
	float sum = 0.0;
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	float n = fbm(wp * freq + vec3(drift, drift * 0.25, drift * 0.6));
	float th = mix(0.28, 0.68, cover);
	float w = fwidth(n) * 1.5 + soft * 0.05;
	float a = 1.0 - smoothstep(th - w, th + w, n);
	float lam = clamp(dot(wn, sun_dir) * 0.55 + 0.55, 0.0, 1.0);
	// Clouds have to carry their own contrast.  A pale grey body over a sunset sky
	// simply takes the sky's colour and the whole deck reads as peach cotton wool;
	// putting real shadow in the underside is what makes it look like water vapour
	// with thickness rather than a tinted veil.
	ALBEDO = mix(vec3(0.13, 0.16, 0.23), vec3(1.00, 0.995, 0.97), lam * lam);
	// A sheet that fills the whole frame the instant the vehicle touches it reads
	// as a screen wipe, not as weather.  Keep a little transparency at contact.
	float contact = smoothstep(4.0, 26.0, length(VERTEX));
	ALPHA = a * opacity * fade * mix(0.28, 1.0, contact);
}
"""
## The Kármán line, drawn as a rim rather than a surface.
##
## A uniform translucent sphere at 100 km is the wrong shape of idea: the vehicle
## flies *through* it, so for several kilometres the camera is inside a 2000-unit
## bubble and its near wall shears across the frame as a hard-edged bright wedge.
## A shell only reads as a line where you look along it — at its silhouette — so
## that is the only place this puts any alpha.  The result is a thin luminous
## circle tracking the horizon, which is what a boundary at 100 km should look
## like, and nothing at all when the camera is close enough to be inside it.
const KARMAN_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform vec4 line_color : source_color = vec4(0.42, 0.78, 1.0, 1.0);
uniform float thickness = 4.0;
uniform float strength  = 0.85;

void fragment() {
	// Both NORMAL and VERTEX arrive in view space, and in view space the fragment
	// sits on the camera ray, so the view direction is simply -VERTEX.  (Godot 4
	// has no world-space camera builtin to reach for here.)
	vec3 vd = normalize(-VERTEX);
	float rim = 1.0 - abs(dot(normalize(NORMAL), vd));
	ALBEDO = line_color.rgb;
	ALPHA = pow(clamp(rim, 0.0, 1.0), thickness) * strength;
}
"""

var cloud_shells: Array[MeshInstance3D] = []
var karman_shell: MeshInstance3D = null
var atmo_world: Node3D = null
var atmo_drift: float = 0.0
var layer_beat_idx: int = 0
var atmo_label: Label = null
var t_path_label: Label = null
# Total arc length flown, integrated from the true speed — deliberately a third,
# separate number from altitude and downrange.
var path_distance_km: float = 0.0
var flight_phase_name: String = ""
# Filled in at SECO so the closing report can quote the orbit the flight really
# produced instead of the one the mission card promised.
var orbit_period_min: float = 0.0
# Mission elapsed time at the Kármán line.  Carried into the shared simulation
# state so the orbital scenes can say how long the climb took instead of
# restarting the story from nothing.
var karman_cross_met_s: float = 0.0
var rocket_base_y: float    = LAUNCH_PAD_Y
# Launch hold-down clamp arms + strongback.  They grip the vehicle on the pad
# through pre-launch and countdown, then swing clear as it goes to fly.
var _holddown_pivots: Array = []      # each pivot's rest rotation is stored in meta
var _holddown_strongback: Node3D = null
var _holddown_release_t: float = -1.0 # <0 = still clamped; >=0 = seconds since release
# Orbital space-frame state
var in_space_frame: bool = false
var space_center: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var earth_spin_angle: float = 0.0
var earth_body: Node3D = null
var earth_atmo: Node3D = null

# Cinematic camera state
enum CamMode { PAD, ENGINE, CHASE, SPACE, TOWER, WIDE, RECOVERY }
var cam_mode: CamMode = CamMode.PAD
var cam_shake: float  = 0.0
var stage_debris: Array[Dictionary] = []
var fairing_separated: bool = false
var engine_audio: AudioStreamPlayer = null
var engine_playback: AudioStreamGeneratorPlayback = null
var engine_phase: float = 0.0
var cue_audio: AudioStreamPlayer = null
var cue_playback: AudioStreamGeneratorPlayback = null
var last_countdown_second: int = -1
var callout_label: Label = null
var callout_timer: float = 0.0
var payload_craft: Node3D = null
var upper_stage_visual: Node3D = null
var deployment_origin: Vector3 = Vector3.ZERO
var space_earth: Node3D = null
var space_clouds: Node3D = null
var space_stars: Node3D = null
var space_fill_light: DirectionalLight3D = null
var orbital_coast: bool = false
var handoff_fade: ColorRect = null
var plume_pulse: float = 0.0
var space_background_locked: bool = false
var pad_hidden_for_orbit: bool = false

# ─── First stage recovery state ───────────────────────────────────────────────
# The returned stage is *not* debris: it is a second guided vehicle, so it keeps
# its own node, its own clock and its own camera instead of being culled six
# seconds after it leaves the stack.
var booster_recoverable: bool = false
var booster_node: Node3D = null
var booster_legs: Array[Node3D] = []
var booster_fins: Array[Node3D] = []
var booster_plume: MeshInstance3D = null
var booster_burn_light: OmniLight3D = null
var booster_sep_met: float = -1.0
var booster_sep_alt_km: float = RECOVERY_SEP_ALT_KM
var booster_sep_spd_ms: float = RECOVERY_SEP_SPD_MS
var booster_nose_dir: Vector3 = Vector3.UP
var booster_alt_km: float = 0.0
var booster_spd_ms: float = 0.0
var booster_phase_name: String = ""
var booster_prop_t: float = 0.0
var booster_burn: float = 0.0
var booster_landed: bool = false
var booster_touchdown_met_s: float = 0.0
var booster_touchdown_hold: float = 0.0
var booster_beat_idx: int = 0
var booster_cam_window: int = 0
# The landing rig: a return-to-launch-site pad beside the launch tower, a
# touchdown dust blast and a few drifting cumulus puffs, placed on the
# space-frame planet under the descending stage.
var recovery_rig: Node3D = null
var recovery_ship: Node3D = null
var recovery_dust: MeshInstance3D = null
var recovery_dust_alpha: float = 0.0
var site_clouds: Array[Node3D] = []
var recovery_env: Environment = null
var recovery_panel: PanelContainer = null
var rec_alt_label: Label = null
var rec_spd_label: Label = null
var rec_prop_label: Label = null
var rec_phase_label: Label = null
var rec_fuel_bar: ProgressBar = null
var rec_note_label: Label = null
# Seconds since separation for the stage currently flying home, kept for the
# recovery readout so the panel can quote the same clock the profile runs on.
var booster_dt_now: float = 0.0
# The return's own clock.  It is accumulated rather than read off the mission
# clock because it has a gate: the stage holds at re-entry interface until the
# orbital vehicle has finished its insertion burn.  A player who watches the
# booster touch down while the upper stage is still climbing reads it as the
# launch vehicle landing before its own satellite reached orbit, however the
# mission clock numbers it.  After SECO the gate releases and the descent runs
# at coast compression, so the recovery beat lands in the story after the
# orbit beat, the way the real broadcast order works.
var booster_elapsed_s: float = 0.0
var booster_held_at_gate: bool = false
# How far down the return the shot has come, 0 at separation and 1 on the deck.
# Kept on the object rather than only in the local scope so the verification
# harness can read the same framing value the camera is using.
var booster_progress_shot: float = 0.0
# ─── First-stage physical return state ────────────────────────────────────────
# The stage coming home is a second integrated vehicle, not a lookup table: a
# 2D vertical-plane state over the curved Earth (downrange x, altitude y), its
# own propellant budget, and a condition-driven phase machine.  If the margin is
# short it does not land — it crashes, because that is what physics says.
var booster_x_km: float = 0.0
var booster_vx_ms: float = 0.0
var booster_vy_ms: float = 0.0
var booster_prop_kg: float = 0.0
var booster_prop_start_kg: float = 0.0
var booster_dry_kg: float = 0.0
var booster_mass_kg: float = 0.0
var booster_fins_out: bool = false
var booster_gear_out: bool = false
var booster_legs_anim: float = 0.0
var booster_at_interface: bool = false
var booster_interface_s: float = 0.0
var booster_entry_start_s: float = 0.0
var booster_interface_km: float = BOOSTER_ENTRY_INTERFACE_KM
var booster_crashed: bool = false
var booster_touchdown_speed_ms: float = 0.0
# Highest load the stage felt during its entry burn, in g — the number the
# verification harness checks against the structural limit, since the burn is
# throttled to it rather than flown at full engine authority.
var booster_peak_entry_g: float = 0.0
var booster_reserve_kg: float = 0.0
# The returning stage's own engine rating, captured at separation.  It must not
# read `thrust_kN` later: when the upper stage lights, that variable becomes the
# *second* stage's thrust, and a 1500 kN landing engine cannot catch a 55-tonne
# stage off the deck.
var booster_engine_kN: float = 0.0
var coast_suggest_done: bool = false
# Player-selected time compression.  The mission clock is honest 1:1 by default;
# warping is the player's choice, never the scene's secret.  MA_LAUNCH_WARP still
# multiplies on top for the verification probe.
const WARP_STEPS := [1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
var player_warp_idx: int = 0
var warp_btn: Button = null
# A simple, obvious speed lever beside the LAUNCH button: Normal / ×2 / ×3.
# Same honest principle as warp — it only runs the sim faster when the player
# asks — just an easier-to-find control than the 1-6 warp ladder.
const SPEED_STEPS := [1.0, 2.0, 3.0]
var player_speed_idx: int = 0
var speed_btn: Button = null

# ─── Split-screen plumbing ────────────────────────────────────────────────────
# The second picture is a viewport, not a screenshot: it renders the same world
# the main window is rendering, from the recovery camera, one frame behind none.
# It reaches the screen as a texture inside the overlay, added ahead of every
# other element, so the panels always sit on top of the picture.
var split_viewport: SubViewport = null
var split_picture: TextureRect = null
var split_divider: ColorRect = null
var split_caption_stage: Label = null
var split_caption_vehicle: Label = null
var split_is_open: bool = false

# The launch vehicle now mirrors whatever rocket was picked in the Builder.
# When a procedural model is mounted we hide the stock glb and the legacy
# screen-space plume (the mounted model carries its own animated exhaust).
var _selected_rocket: Node3D = null
var _hide_legacy_plume: bool = false
var model_flame_nodes: Array[Node3D] = []

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_debug_warp = maxf(1.0, float(OS.get_environment("MA_LAUNCH_WARP")))
	_setup_from_mission()

	rocket           = get_node_or_null("Rocket")
	rocket_mesh      = get_node_or_null("Rocket/RocketMesh")
	exhaust_particles = get_node_or_null("Rocket/ExhaustParticles")
	world_env        = get_node_or_null("WorldEnvironment")

	# Get sky material reference for space transition
	if world_env and world_env.environment:
		var sky = world_env.environment.sky
		if sky:
			sky_material = sky.sky_material as ProceduralSkyMaterial

	# Create cinematic cameras dynamically
	_create_split_view()
	_create_cameras()

	# UI — a themed "Launch Control" overlay built in code. It hides the plain
	# scene labels and re-points every HUD reference to the new styled widgets.
	_rebuild_launch_overlay()

	# Cinematic sunset grading of the pad environment (sky, sun, glow).
	_grade_environment()

	if exhaust_particles:
		exhaust_particles.emitting = false

	_setup_visuals()
	# Dress up the imported launch tower: the glb is a plain box column and it
	# reads as a featureless gray monolith in the master shot.
	_detail_launch_complex()
	# The pad sat on an empty tan plane; build the surrounding spaceport so the
	# floor, horizon and ground hardware read like the real world.
	_build_ground_detail()
	# A flat plane can never read as "20 km up", because the scene's own scale
	# only moves the vehicle ~90 units for 20 km.  A stylised curved planetary
	# shell gives the horizon an actual dip, so altitude starts to look like
	# altitude instead of a model on a tabletop.
	_create_horizon_shell()
	_set_engine_fx(false)
	_create_launch_audio()
	_create_mission_callouts()
	_create_payload_craft()
	_create_handoff_fade()

	# Set initial rocket position correctly on pad
	if rocket:
		rocket.position = Vector3(0.0, LAUNCH_PAD_Y, 0.0)

	_apply_selected_rocket()

	_set_camera(CamMode.PAD)
	_set_state(LaunchState.PRE_LAUNCH)
	print("[Launch] Ready — thrust: %.0f kN | rocket: %s" % [
		thrust_kN, rocket.name if rocket else "NULL"])
	# Verification-only: MA_LAUNCH_AUTOSTART begins the countdown immediately so the
	# headless render probe can reach the space frame without a keyboard press.
	if OS.get_environment("MA_LAUNCH_AUTOSTART") != "":
		_on_launch_pressed()

func _g(path: String) -> Node:
	if has_node(path): return get_node(path)
	return null

# ─── Camera Setup ─────────────────────────────────────────────────────────────
## The second picture of a split screen.  A SubViewport that renders the *same*
## World3D the window is rendering, from a different camera, is the whole trick:
## there is no duplicated scene and no second copy of the planet, so the two
## halves of the frame are literally the same mission at the same instant, and a
## stage that has just lit its landing engine in the left picture is the same
## stage that lit it in the right one.  Costs one extra render pass, which is the
## honest price of showing two vehicles at once.
func _create_split_view() -> void:
	# The scene's own camera would otherwise still be current in the window while
	# the cinematic cameras are being built.
	var existing := get_node_or_null("ChaseCamera") as Camera3D
	if existing: existing.current = false

	split_viewport = SubViewport.new()
	split_viewport.name = "StageReturnRender"
	split_viewport.transparent_bg = false
	split_viewport.size = Vector2i(640, 720)
	split_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var shared_world: World3D = get_viewport().get_world_3d()
	if shared_world:
		split_viewport.world_3d = shared_world
	add_child(split_viewport)

## The left half of the screen, the seam, and the two captions that say which
## vehicle each picture belongs to — without the labels a split reads as a bug.
## Built ahead of every other overlay element on purpose: sibling order is what
## decides what covers what here, and the panels must win.
func _build_split_overlay(ui: Control) -> void:
	split_picture = TextureRect.new()
	split_picture.name = "StageReturnView"
	if split_viewport:
		split_picture.texture = split_viewport.get_texture()
	split_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	split_picture.stretch_mode = TextureRect.STRETCH_SCALE
	# The picture is a picture: it must not swallow clicks meant for anything it
	# happens to be covering.
	split_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(split_picture)
	_anchor(split_picture, 0.0, 0.0, SPLIT_WIDTH_FRACTION, 1.0, 0.0, 0.0, 0.0, 0.0)

	split_divider = ColorRect.new()
	split_divider.name = "SplitDivider"
	split_divider.color = Color(1.0, 1.0, 1.0, 0.45)
	ui.add_child(split_divider)
	_anchor(split_divider, SPLIT_WIDTH_FRACTION, 0.0, SPLIT_WIDTH_FRACTION, 1.0, -1.0, 62.0, 1.0, -150.0)

	split_caption_stage = _mk_label("◀ FIRST STAGE — RETURNING", 13, UI_GREEN)
	split_caption_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui.add_child(split_caption_stage)
	_anchor(split_caption_stage, 0.0, 1.0, SPLIT_WIDTH_FRACTION, 1.0, 18.0, -172.0, 0.0, -150.0)

	split_caption_vehicle = _mk_label("ORBITAL VEHICLE — CLIMATE SENTINEL ▶", 13, UI_ACCENT)
	split_caption_vehicle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(split_caption_vehicle)
	_anchor(split_caption_vehicle, SPLIT_WIDTH_FRACTION, 1.0, 1.0, 1.0, 0.0, -172.0, -18.0, -150.0)

	split_picture.hide()
	split_divider.hide()
	split_caption_stage.hide()
	split_caption_vehicle.hide()

func _create_cameras() -> void:
	# CAM 1 — Ground pad camera (dramatic low angle looking up at rocket)
	cam_pad = Camera3D.new()
	cam_pad.name = "CamPad"
	# Keep the complete 22-unit vehicle and tower in frame. The earlier close,
	# low-angle composition clipped most of the rocket below the viewport.
	# Wider, higher master shot: keeps the full upgraded vehicle above the
	# bottom control strip instead of letting its engine section sit behind it.
	cam_pad.fov = 55.0
	cam_pad.position = Vector3(28.0, 24.0, 78.0)
	cam_pad.look_at_from_position(
		Vector3(28.0, 24.0, 78.0),
		Vector3(0.0, 13.0, 0.0), Vector3.UP)
	add_child(cam_pad)

	# CAM 2 — Chase camera (follows rocket up, zooms out)
	cam_engine = Camera3D.new()
	cam_engine.name = "CamEngine"
	cam_engine.fov = 48.0
	cam_engine.position = Vector3(8.0, 4.0, 17.0)
	add_child(cam_engine)

	# CAM 3 — Chase camera (follows rocket up, zooms out)
	cam_chase = Camera3D.new()
	cam_chase.name = "CamChase"
	cam_chase.fov = 55.0
	cam_chase.position = Vector3(15.0, LAUNCH_PAD_Y + 5.0, 20.0)
	add_child(cam_chase)

	# CAM 4 — Space wide angle (Earth curvature and payload separation)
	cam_space = Camera3D.new()
	cam_space.name = "CamSpace"
	cam_space.fov = 70.0
	add_child(cam_space)

	# CAM 5 — Tower view: framed side-on so the vehicle + gantry read together.
	cam_tower = Camera3D.new()
	cam_tower.name = "CamTower"
	cam_tower.fov = 50.0
	cam_tower.position = Vector3(-34.0, 18.0, 46.0)
	cam_tower.look_at_from_position(Vector3(-34.0, 18.0, 46.0), Vector3(-2.0, 15.0, 0.0), Vector3.UP)
	add_child(cam_tower)

	# CAM 6 — Wide establishing shot from far out on the pad.
	cam_wide = Camera3D.new()
	cam_wide.name = "CamWide"
	cam_wide.fov = 60.0
	cam_wide.position = Vector3(66.0, 36.0, 128.0)
	cam_wide.look_at_from_position(Vector3(66.0, 36.0, 128.0), Vector3(0.0, 14.0, 0.0), Vector3.UP)
	add_child(cam_wide)

	# CAM 7 — Recovery camera.  It belongs to the split-screen viewport rather
	# than to the window, so it films the returning stage in the left half while
	# the main camera keeps the orbital vehicle in the right half.  It is driven
	# entirely by `_update_recovery_camera()`.
	cam_recovery = Camera3D.new()
	cam_recovery.name = "CamRecovery"
	cam_recovery.fov = 58.0
	cam_recovery.current = false
	# The return is filmed in the space frame, whose shared world environment is
	# the black of orbit — the exact opposite of the blue atmosphere the ascent
	# promised, which is why the landing read as airless.  Because the split
	# renders the same world from a *separate* camera, that camera can carry its
	# own environment override: a hazy blue sky with depth fog and sky-lit
	# ambient, so the stage visibly comes back down into the air it left, while
	# the orbital half of the frame stays in vacuum.  It is graded every frame by
	# altitude in _update_recovery_atmosphere, mirroring the ascent's sky fade.
	recovery_env = _make_recovery_environment()
	cam_recovery.environment = recovery_env
	if split_viewport:
		split_viewport.add_child(cam_recovery)
	else:
		add_child(cam_recovery)

	# The spaceport reaches a distant coastline, and the ascent now flies inside a
	# 1500-unit planetary shell whose far side is ~3000 units away.  The old
	# 1700-unit far plane sliced straight through that shell, which is exactly the
	# hard-edged tan wedge that kept appearing in the corner of the gravity-turn
	# shot: not weather, not ground, just geometry running out of frustum.
	for c in [cam_pad, cam_engine, cam_chase, cam_space, cam_tower, cam_wide, cam_recovery]:
		if c != null:
			c.far = 4400.0
			# Push the near plane out with the far plane so the depth buffer keeps
			# enough precision for the pad hardware not to z-fight.
			c.near = 0.12

func _set_camera(mode: CamMode) -> void:
	cam_mode = mode
	var next_camera: Camera3D = cam_pad
	if mode == CamMode.ENGINE: next_camera = cam_engine
	elif mode == CamMode.CHASE: next_camera = cam_chase
	elif mode == CamMode.SPACE: next_camera = cam_space
	elif mode == CamMode.TOWER: next_camera = cam_tower
	elif mode == CamMode.WIDE: next_camera = cam_wide
	# RECOVERY is deliberately not routable here.  The returning stage is not a
	# camera the window ever cuts to — it is a second picture, owned by the split
	# viewport, and stealing the window from the orbital vehicle would be exactly
	# the discontinuity the split exists to remove.
	# Preserve the outgoing shot at each cut. The incoming camera then eases
	# toward its framing in its normal update, so liftoff → chase → orbit reads
	# as a continuous filmed ascent rather than four unrelated viewpoints.
	if active_camera and next_camera and active_camera != next_camera:
		next_camera.global_transform = active_camera.global_transform
		next_camera.fov = active_camera.fov
	if cam_pad: cam_pad.current = (next_camera == cam_pad)
	if cam_engine: cam_engine.current = (next_camera == cam_engine)
	if cam_chase: cam_chase.current = (next_camera == cam_chase)
	if cam_space: cam_space.current = (next_camera == cam_space)
	if cam_tower: cam_tower.current = (next_camera == cam_tower)
	if cam_wide: cam_wide.current = (next_camera == cam_wide)
	active_camera = next_camera

# ─── Visual Materials ─────────────────────────────────────────────────────────
## Builds the rocket chosen in the Builder (via the shared RocketFactory) and
## mounts it in place of the stock glb, sized to occupy the launch-pad footprint.
## If nothing is selected we keep the scene's default Falcon 9 model.
func _apply_selected_rocket() -> void:
	if not rocket:
		return
	var id: String = ""
	if GameManager and GameManager.spacecraft_config != null:
		id = GameManager.spacecraft_config.get("rocket", {}).get("id", "")
	if id == "":
		return  # no selection: leave the authored glb in place
	var glb := get_node_or_null("Rocket/RocketModel")
	if glb:
		glb.hide()
	_hide_legacy_plume = true
	var container := Node3D.new()
	container.name = "SelectedRocket"
	var s := 2.8
	# Rest the engine bell exits just on the pad surface. Aligning the flame tip
	# instead left every vehicle hovering several units above the slab.
	container.position = Vector3(0.0, PAD_TOP_LOCAL_Y - _rocket_engine_bottom(id) * s, 0.0)
	container.scale = Vector3(s, s, s)
	rocket.add_child(container)
	RocketFactoryScript.build(container, id, true)
	_selected_rocket = container
	model_flame_nodes.clear()
	for c in container.get_children():
		var mi := c as MeshInstance3D
		if mi != null and (mi.name == "FlameOuter" or mi.name == "FlameCore"):
			model_flame_nodes.append(mi)
		elif c is OmniLight3D:
			model_flame_nodes.append(c)
	_set_model_flame(false)
	print("[Launch] mounted selected rocket: %s" % id)

## Local-Y of the pad slab top inside the Rocket node (rocket sits at y=7).
const PAD_TOP_LOCAL_Y: float = -6.0

## Engine-exit plane of RocketFactory's model for `id` (bells, no exhaust).
func _rocket_engine_bottom(id: String) -> float:
	match id:
		"electron":
			return -4.5
		"falcon9", "falcon_heavy":
			return -6.7
		"sls":
			return -5.5
		"starship":
			return -6.1
		_:
			return -5.4

## Drives the mounted vehicle's own exhaust so it follows the engine FX state.
## Above ~80 km there is no air to scatter the plume, so the orange combustion
## cone (correct at the pad) becomes a faint, wide blue-white vapour expansion —
## the way real vacuum exhaust looks. Orange exhaust is an atmospheric effect.
func _set_model_flame(active: bool) -> void:
	for n in model_flame_nodes:
		if n is OmniLight3D:
			(n as OmniLight3D).light_energy = 3.6 if active else 0.0
		elif n is MeshInstance3D:
			(n as MeshInstance3D).visible = active
	_apply_plume_vacuum_tint()

## Recolours the exhaust for the surrounding medium.  Called every frame, not
## just on ignition, because the vehicle crosses the Kármán line while the same
## burn is still lit: a tint set once at stage-2 ignition would freeze at the
## orange used inside the atmosphere and then ride all the way to orbit wrong.
func _apply_plume_vacuum_tint() -> void:
	var vacuum := altitude_km > 80.0
	for n in model_flame_nodes:
		if n is OmniLight3D:
			(n as OmniLight3D).light_color = Color(0.6, 0.75, 1.0) if vacuum else Color(1.0, 0.6, 0.3)
		elif n is MeshInstance3D:
			var sm := (n as MeshInstance3D).material_override as ShaderMaterial
			if sm != null:
				if vacuum:
					sm.set_shader_parameter("c_hot", Color(0.80, 0.88, 1.0))
					sm.set_shader_parameter("c_mid", Color(0.42, 0.62, 1.0))
					sm.set_shader_parameter("c_cool", Color(0.08, 0.18, 0.55))
					sm.set_shader_parameter("intensity", 0.55)
				else:
					sm.set_shader_parameter("c_hot", Color(1.0, 0.97, 0.82))
					sm.set_shader_parameter("c_mid", Color(1.0, 0.52, 0.14))
					sm.set_shader_parameter("c_cool", Color(0.55, 0.07, 0.02))
					sm.set_shader_parameter("intensity", 1.25)
	# The stock glb vehicle uses the legacy solid-cylinder plume instead of the
	# procedural RocketFactory flame, so it needs the same vacuum recolour.
	if plume_core:
		var cm := plume_core.material_override as StandardMaterial3D
		if cm != null:
			if vacuum:
				cm.albedo_color = Color(0.72, 0.86, 1.0, 1.0)
				cm.emission = Color(0.5, 0.7, 1.0)
				cm.emission_energy_multiplier = 2.4
			else:
				cm.albedo_color = Color(1.0, 0.92, 0.5, 1.0)
				cm.emission = Color(1.0, 0.62, 0.08)
				cm.emission_energy_multiplier = 5.0
	if plume_outer:
		var om := plume_outer.material_override as StandardMaterial3D
		if om != null:
			if vacuum:
				om.albedo_color = Color(0.42, 0.62, 1.0, 0.34)
				om.emission = Color(0.2, 0.4, 0.9)
				om.emission_energy_multiplier = 1.1
			else:
				om.albedo_color = Color(1.0, 0.20, 0.015, 0.62)
				om.emission = Color(1.0, 0.08, 0.0)
				om.emission_energy_multiplier = 3.0

func _setup_visuals() -> void:
	# White metallic rocket body
	var body_mat := StandardMaterial3D.new()
	# A silver body reads against the bright daytime sky; pure white was being
	# lost in the sky and made the rocket look as if it were behind the UI.
	body_mat.albedo_color = Color(0.52, 0.56, 0.63, 1.0)
	body_mat.metallic     = 0.68
	body_mat.roughness    = 0.20
	if rocket_mesh: rocket_mesh.material_override = body_mat

	var nose := get_node_or_null("Rocket/Nosecone") as MeshInstance3D
	if nose: nose.material_override = body_mat

	# Dark engine nozzle
	var nozzle_mat := StandardMaterial3D.new()
	nozzle_mat.albedo_color = Color(0.14, 0.14, 0.16, 1.0)
	nozzle_mat.metallic = 0.95
	nozzle_mat.roughness = 0.25
	var nozzle := get_node_or_null("Rocket/EngineNozzle") as MeshInstance3D
	if nozzle: nozzle.material_override = nozzle_mat

	# Fins
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.82, 0.82, 0.84, 1.0)
	fin_mat.metallic = 0.55
	fin_mat.roughness = 0.28
	for n in ["Rocket/FinL","Rocket/FinR","Rocket/FinF","Rocket/FinB"]:
		var f := get_node_or_null(n) as MeshInstance3D
		if f: f.material_override = fin_mat

	# Concrete ground
	var gnd := get_node_or_null("Ground") as MeshInstance3D
	if gnd:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.19, 0.26, 0.15, 1.0)
		m.roughness = 0.95
		gnd.material_override = m

	# Concrete pad
	var pad := get_node_or_null("LaunchPad") as MeshInstance3D
	if pad:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.50, 0.48, 0.44, 1.0)
		m.roughness = 0.90
		m.metallic  = 0.05
		pad.material_override = m
	var arm := get_node_or_null("PadArm") as MeshInstance3D
	if arm:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.40, 0.36, 1.0)
		m.roughness = 0.82
		m.metallic  = 0.20
		arm.material_override = m

	# Exhaust particles — full fire+smoke setup
	if exhaust_particles:
		var pm := ParticleProcessMaterial.new()
		pm.direction             = Vector3(0.0, -1.0, 0.0)
		pm.spread                = 20.0
		pm.gravity               = Vector3(0.0, -0.5, 0.0)
		pm.initial_velocity_min  = 22.0
		pm.initial_velocity_max  = 42.0
		pm.angular_velocity_min  = -120.0
		pm.angular_velocity_max  = 120.0
		pm.scale_min             = 0.6
		pm.scale_max             = 2.2

		var g := Gradient.new()
		g.set_color(0,   Color(1.00, 1.00, 0.90, 1.0))  # bright white-yellow core
		g.add_point(0.12, Color(1.00, 0.80, 0.15, 1.0))  # yellow flame
		g.add_point(0.28, Color(1.00, 0.45, 0.05, 0.95)) # orange
		g.add_point(0.55, Color(0.70, 0.22, 0.02, 0.70)) # deep orange-red
		g.add_point(0.78, Color(0.30, 0.25, 0.22, 0.45)) # dark grey smoke
		g.add_point(1.00, Color(0.12, 0.10, 0.10, 0.00)) # fade out
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		pm.color_ramp = ramp

		# Flame stays on the nozzle; smoke/dust below are world-space systems so
		# the plume remains behind the vehicle rather than moving with it.
		exhaust_particles.local_coords     = true
		exhaust_particles.process_material = pm
		exhaust_particles.amount           = 120
		exhaust_particles.lifetime         = 1.6
		exhaust_particles.explosiveness    = 0.0
		exhaust_particles.randomness       = 0.35

		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_mat.vertex_color_use_as_albedo = true
		flame_mat.emission_enabled = true
		flame_mat.emission = Color(1.0, 0.28, 0.02, 1.0)
		flame_mat.emission_energy_multiplier = 1.6
		var smesh := SphereMesh.new()
		smesh.radius = 0.55
		smesh.height = 1.1
		smesh.material = flame_mat
		exhaust_particles.draw_pass_1 = smesh

		_create_smoke_and_dust()
		_create_engine_plume_meshes()
		engine_light = OmniLight3D.new()
		engine_light.name = "EngineGlow"
		engine_light.position = Vector3(0.0, -8.0, 0.0)
		engine_light.light_color = Color(1.0, 0.31, 0.06, 1.0)
		engine_light.light_energy = 0.0
		engine_light.omni_range = 18.0
		rocket.add_child(engine_light)

## The imported launch_pad.glb tower is a plain 5x5 box column in the master
## shot. These procedurally attached ribs, corner pipes, cross braces, walkway
## railings and a beacon give it genuine launch-complex hardware detail.
func _detail_launch_complex() -> void:
	var complex := get_node_or_null("LaunchComplex") as Node3D
	if not complex: return

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.43, 0.46, 1.0)
	steel.metallic = 0.85
	steel.roughness = 0.42
	var rusty := StandardMaterial3D.new()
	rusty.albedo_color = Color(0.36, 0.22, 0.12, 1.0)
	rusty.metallic = 0.40
	rusty.roughness = 0.85
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.52, 0.50, 0.46, 1.0)
	concrete.roughness = 0.94

	# Horizontal stiffening ribs wrapping the tower column (5x5 footprint).
	for y in [10, 18, 26, 34, 42, 50, 58, 66, 74]:
		var rib := MeshInstance3D.new()
		var rib_mesh := BoxMesh.new()
		rib_mesh.size = Vector3(6.1, 0.45, 6.1)
		rib.mesh = rib_mesh
		rib.position = Vector3(0.0, float(y), 0.0)
		rib.material_override = steel
		complex.add_child(rib)

	# Corner service pipes running the full height.
	for cx in [-2.85, 2.85]:
		for cz in [-2.85, 2.85]:
			var pipe := MeshInstance3D.new()
			var pipe_mesh := CylinderMesh.new()
			pipe_mesh.top_radius = 0.30
			pipe_mesh.bottom_radius = 0.30
			pipe_mesh.height = 79.0
			pipe_mesh.radial_segments = 12
			pipe.mesh = pipe_mesh
			pipe.position = Vector3(cx, 39.5, cz)
			pipe.material_override = steel if cz > 0.0 else rusty
			complex.add_child(pipe)

	# Diagonal cross bracing on each tower face inside every 16-unit band.
	var diag_len := sqrt(16.0 * 16.0 + 5.8 * 5.8)
	for band in [8, 24, 40, 56]:
		var mid := float(band) + 8.0
		# +Z and -Z faces: bracing slants in the x-y plane.
		for face in [2.9, -2.9]:
			var brace := MeshInstance3D.new()
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(diag_len, 0.14, 0.14)
			brace.mesh = brace_mesh
			brace.position = Vector3(0.0, mid, face)
			brace.rotation_degrees.z = 67.5
			brace.material_override = steel
			complex.add_child(brace)
			var brace2: MeshInstance3D = brace.duplicate()
			brace2.rotation_degrees.z = -67.5
			complex.add_child(brace2)
		# +X and -X faces: bracing slants in the y-z plane.
		for face in [2.9, -2.9]:
			var brace := MeshInstance3D.new()
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.14, 0.14, diag_len)
			brace.mesh = brace_mesh
			brace.position = Vector3(face, mid, 0.0)
			brace.rotation_degrees.x = 67.5 if face > 0.0 else -67.5
			brace.material_override = steel
			complex.add_child(brace)
			var brace2: MeshInstance3D = brace.duplicate()
			brace2.rotation_degrees.x = 112.5 if face > 0.0 else -112.5
			complex.add_child(brace2)

	# Wider service platforms at the existing arm heights, with railing posts.
	for arm_h in [18.0, 30.0, 48.0]:
		var deck := MeshInstance3D.new()
		var deck_mesh := BoxMesh.new()
		deck_mesh.size = Vector3(7.5, 0.35, 4.2)
		deck.mesh = deck_mesh
		deck.position = Vector3(5.5, arm_h + 1.3, 0.0)
		deck.material_override = rusty
		complex.add_child(deck)
		for rz in [-1.9, 1.9]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(7.5, 0.10, 0.10)
			rail.mesh = rail_mesh
			rail.position = Vector3(5.5, arm_h + 2.2, rz)
			rail.material_override = steel
			complex.add_child(rail)
		for px in [2.2, 5.5, 8.8]:
			for rz in [-1.9, 1.9]:
				var post := MeshInstance3D.new()
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(0.12, 0.8, 0.12)
				post.mesh = post_mesh
				post.position = Vector3(px, arm_h + 1.8, rz)
				post.material_override = steel
				complex.add_child(post)
		# Support struts back to the tower core.
		for strut_y in [arm_h - 1.6, arm_h + 0.6]:
			var strut := MeshInstance3D.new()
			var strut_mesh := BoxMesh.new()
			strut_mesh.size = Vector3(2.8, 0.14, 0.14)
			strut.mesh = strut_mesh
			strut.position = Vector3(1.4, strut_y, 0.0)
			strut.rotation_degrees.z = 40.0
			strut.material_override = steel
			complex.add_child(strut)

	# Have a proper round slab replace the bare 8-segment octagon look.
	var slab := MeshInstance3D.new()
	var slab_mesh := CylinderMesh.new()
	slab_mesh.top_radius = 28.4
	slab_mesh.bottom_radius = 28.4
	slab_mesh.height = 3.1
	slab_mesh.radial_segments = 40
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, 1.5, 0.0)
	slab.material_override = concrete
	complex.add_child(slab)
	var kerb := MeshInstance3D.new()
	var kerb_mesh := TorusMesh.new()
	kerb_mesh.inner_radius = 27.8
	kerb_mesh.outer_radius = 28.6
	kerb_mesh.rings = 48
	kerb_mesh.ring_segments = 6
	kerb.mesh = kerb_mesh
	kerb.position = Vector3(0.0, 2.95, 0.0)
	kerb.material_override = concrete
	complex.add_child(kerb)

	# Red aviation beacon on the masthead.
	var beacon_pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 2.4
	pole_mesh.radial_segments = 8
	beacon_pole.mesh = pole_mesh
	beacon_pole.position = Vector3(0.0, 80.0, 0.0)
	beacon_pole.material_override = steel
	complex.add_child(beacon_pole)
	var beacon := MeshInstance3D.new()
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.35
	beacon_mesh.height = 0.7
	beacon_mesh.radial_segments = 12
	beacon_mesh.rings = 6
	beacon.mesh = beacon_mesh
	beacon.position = Vector3(0.0, 81.4, 0.0)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(0.9, 0.12, 0.08, 1.0)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.1, 0.05, 1.0)
	beacon_mat.emission_energy_multiplier = 2.2
	beacon.material_override = beacon_mat
	beacon.name = "PadBeacon"
	complex.add_child(beacon)

## Small primitive helpers used only by the spaceport build-up.
func _pad_box(mat: Material, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	return mi

func _pad_cyl(mat: Material, top_r: float, bot_r: float, h: float, pos: Vector3, seg := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	return mi

## Procedural earthy ground: an albedo that blends grass, dry dirt and pale sand
## with fine speckle, plus a matching grain normal map.  Gives the terrain the
## colour variation a flat-tinted plane was missing without needing any assets.
func _make_ground_textures() -> Array:
	var size := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var n1 := 24
	var n2 := 96
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
			heights[y * size + x] = 0.7 * _mli_noise2(g1, n1, u, v) + 0.3 * _mli_noise2(g2, n2, u, v)
	var alb := Image.create(size, size, false, Image.FORMAT_RGB8)
	var grass := Color(0.15, 0.26, 0.09)
	var scrub := Color(0.22, 0.24, 0.11)
	var dirt := Color(0.36, 0.27, 0.15)
	var sand := Color(0.55, 0.49, 0.33)
	for y in range(size):
		for x in range(size):
			var u := float(x) / size
			var v := float(y) / size
			var coarse := _mli_noise2(g1, n1, u, v)
			var fine := _mli_noise2(g2, n2, u, v)
			var col := grass.lerp(scrub, clampf(coarse / 0.40, 0.0, 1.0))
			col = col.lerp(dirt, clampf((coarse - 0.42) / 0.36, 0.0, 1.0))
			col = col.lerp(sand, clampf((coarse - 0.70) / 0.30, 0.0, 1.0))
			col = col * (0.66 + 0.62 * fine)
			alb.set_pixel(x, y, col)
	var nrm := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in range(size):
		for x in range(size):
			var l := heights[y * size + ((x - 1 + size) % size)]
			var r := heights[y * size + ((x + 1) % size)]
			var dn := heights[((y - 1 + size) % size) * size + x]
			var up := heights[((y + 1) % size) * size + x]
			var nx := (l - r) * 1.6
			var ny := (dn - up) * 1.6
			var nlen := sqrt(nx * nx + ny * ny + 1.0)
			nrm.set_pixel(x, y, Color((nx / nlen) * 0.5 + 0.5, (ny / nlen) * 0.5 + 0.5, (1.0 / nlen) * 0.5 + 0.5))
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm)]

## Replaces the flat land cylinder with a gently rolling displaced grid.  The
## relief fades to dead flat within the apron radius so the pad and its hardware
## still sit on a level deck, while distant terrain gets real hills and shadowed
## slopes instead of a painted disc.
func _build_terrain_mesh(mat: Material) -> MeshInstance3D:
	var size := 3000.0
	var res := 180
	var half := size * 0.5
	var cell := size / float(res)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77103
	var n1 := 20
	var n2 := 64
	var g1 := PackedFloat32Array()
	for i in range(n1 * n1):
		g1.append(rng.randf())
	var g2 := PackedFloat32Array()
	for i in range(n2 * n2):
		g2.append(rng.randf())
	var flat_r := 70.0
	var fade_r := 260.0
	var amp := 14.0
	var stride := res + 1
	var hgt := PackedFloat32Array()
	hgt.resize(stride * stride)
	for iy in range(stride):
		for ix in range(stride):
			var wx := -half + float(ix) * cell
			var wz := -half + float(iy) * cell
			var u := (wx + half) / size
			var v := (wz + half) / size
			var dd := sqrt(wx * wx + wz * wz)
			var fade := smoothstep(flat_r, fade_r, dd)
			var nv := 0.68 * _mli_noise2(g1, n1, u, v) + 0.32 * _mli_noise2(g2, n2, u, v)
			var swell := smoothstep(fade_r, half, dd) * 40.0
			hgt[iy * stride + ix] = (nv - 0.5) * 2.0 * amp * fade + swell
	var tile := 8.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for iy in range(stride):
		for ix in range(stride):
			var wx := -half + float(ix) * cell
			var wz := -half + float(iy) * cell
			var h: float = hgt[iy * stride + ix]
			verts.append(Vector3(wx, h, wz))
			var xm := ix - 1
			if xm < 0: xm = 0
			var xp := ix + 1
			if xp >= stride: xp = stride - 1
			var zm := iy - 1
			if zm < 0: zm = 0
			var zp := iy + 1
			if zp >= stride: zp = stride - 1
			var dx: float = hgt[iy * stride + xp] - hgt[iy * stride + xm]
			var dz: float = hgt[zp * stride + ix] - hgt[zm * stride + ix]
			norms.append(Vector3(-dx, 2.0 * cell, -dz).normalized())
			uvs.append(Vector2(wx / tile, wz / tile))
	var idx := PackedInt32Array()
	for iy in range(res):
		for ix in range(res):
			var a := iy * stride + ix
			var b := a + 1
			var c := a + stride
			var d := c + 1
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

## Kick off the hold-down release.  Called the moment the engines pre-ignite on
## the T-3 beat: the strongback hinges back first, then the clamp arms swing
## down-and-clear so the vehicle is unbound by the time it rises off the mount.
func _begin_holddown_release() -> void:
	if _holddown_release_t < 0.0:
		_holddown_release_t = 0.0

## Re-grip the vehicle for a fresh run: clamps horizontal, strongback upright.
func _reset_holddowns() -> void:
	_holddown_release_t = -1.0
	for sw in _holddown_pivots:
		if is_instance_valid(sw):
			sw.rotation.z = 0.0
	if is_instance_valid(_holddown_strongback):
		_holddown_strongback.rotation.z = 0.0

## Drives the release animation every frame once it has been triggered.
func _update_holddowns(delta: float) -> void:
	if _holddown_release_t < 0.0:
		return
	_holddown_release_t += delta
	# Strongback hinges back over the first ~2 s of the ignition hold.
	if is_instance_valid(_holddown_strongback):
		var sb_p := clampf(_holddown_release_t / 2.0, 0.0, 1.0)
		_holddown_strongback.rotation.z = deg_to_rad(-40.0) * smoothstep(0.0, 1.0, sb_p)
	# Clamp arms swing down-and-out just after, over ~1.4 s starting 0.6 s in.
	var cl_p := clampf((_holddown_release_t - 0.6) / 1.4, 0.0, 1.0)
	var ang := deg_to_rad(102.0) * smoothstep(0.0, 1.0, cl_p)
	for sw in _holddown_pivots:
		if is_instance_valid(sw):
			sw.rotation.z = ang

## Surrounds the pad with the ground, coastline and support hardware that the
## bare tan plane was missing: a concrete apron with expansion joints, a blast
## scorch, ring road, lightning towers, crawler, tank farm and floodlights.
func _build_ground_detail() -> void:
	var root := get_node_or_null("GroundDetail") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "GroundDetail"
		add_child(root)

	# The authored 200x200 "Ground" plane sat exactly at y=0 and would z-fight
	# with the new terrain; retire it and recolor the octagon pad as a deck.
	var old_ground := get_node_or_null("Ground") as Node3D
	if old_ground: old_ground.visible = false
	var old_pad := get_node_or_null("LaunchPad") as MeshInstance3D
	if old_pad:
		var deck := StandardMaterial3D.new()
		deck.albedo_color = Color(0.40, 0.39, 0.36, 1.0)
		deck.roughness = 0.93
		deck.metallic = 0.05
		old_pad.material_override = deck

	# --- materials --------------------------------------------------------
	var terrain := StandardMaterial3D.new()
	terrain.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	terrain.roughness = 0.98
	terrain.metallic = 0.0
	var _gtex := _make_ground_textures()
	terrain.albedo_texture = _gtex[0]
	terrain.normal_enabled = true
	terrain.normal_texture = _gtex[1]
	terrain.texture_repeat = true
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.42, 0.38, 0.28, 1.0)
	sand.roughness = 0.96
	var ocean := StandardMaterial3D.new()
	ocean.albedo_color = Color(0.04, 0.12, 0.20, 1.0)
	ocean.roughness = 0.10
	ocean.metallic = 0.35
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.13, 0.16, 0.13, 1.0)
	hill_mat.roughness = 0.98
	var apron := StandardMaterial3D.new()
	apron.albedo_color = Color(0.46, 0.45, 0.42, 1.0)
	apron.roughness = 0.92
	apron.metallic = 0.04
	var apron_dark := StandardMaterial3D.new()
	apron_dark.albedo_color = Color(0.33, 0.32, 0.30, 1.0)
	apron_dark.roughness = 0.95
	var scorch := StandardMaterial3D.new()
	scorch.albedo_color = Color(0.10, 0.09, 0.09, 1.0)
	scorch.roughness = 1.0
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.13, 0.13, 0.14, 1.0)
	asphalt.roughness = 0.90
	var paint_steel := StandardMaterial3D.new()
	paint_steel.albedo_color = Color(0.55, 0.56, 0.58, 1.0)
	paint_steel.metallic = 0.75
	paint_steel.roughness = 0.45
	var paint_red := StandardMaterial3D.new()
	paint_red.albedo_color = Color(0.62, 0.16, 0.12, 1.0)
	paint_red.metallic = 0.30
	paint_red.roughness = 0.60
	var paint_white := StandardMaterial3D.new()
	paint_white.albedo_color = Color(0.80, 0.80, 0.78, 1.0)
	paint_white.roughness = 0.70
	var paint_yellow := StandardMaterial3D.new()
	paint_yellow.albedo_color = Color(0.78, 0.66, 0.20, 1.0)
	paint_yellow.metallic = 0.40
	paint_yellow.roughness = 0.55
	var rusty_line := StandardMaterial3D.new()
	rusty_line.albedo_color = Color(0.34, 0.24, 0.15, 1.0)
	rusty_line.metallic = 0.35
	rusty_line.roughness = 0.85

	# --- land, sea and far hills ------------------------------------------
	# Rolling textured terrain replaces the old flat land disc; its relief is
	# faded to dead flat under the pad so the apron and hardware still sit level.
	var land := _build_terrain_mesh(terrain)
	root.add_child(land)
	var sea := MeshInstance3D.new()
	var sea_mesh := PlaneMesh.new()
	sea_mesh.size = Vector2(6000.0, 6000.0)
	sea.mesh = sea_mesh
	sea.position = Vector3(0.0, -14.0, 0.0)
	sea.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.material_override = ocean
	root.add_child(sea)
	var hill_spots := [
		Vector3(-620, 0, -540), Vector3(-180, 0, -720), Vector3(300, 0, -660),
		Vector3(680, 0, -300), Vector3(720, 0, 260), Vector3(-540, 0, 480),
	]
	for i in hill_spots.size():
		var hs: Vector3 = hill_spots[i]
		var h_r := 120.0 + float(i % 3) * 55.0
		var hill := _pad_cyl(hill_mat, h_r, h_r * 1.4, 26.0 + float(i % 2) * 16.0, Vector3(hs.x, 6.0, hs.z), 20)
		hill.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hill)

	# --- concrete apron with expansion joints ------------------------------
	var apron_mesh := _pad_cyl(apron, 46.0, 47.5, 0.5, Vector3(0.0, -0.22, 0.0), 64)
	apron_mesh.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(apron_mesh)
	var lip := MeshInstance3D.new()
	var lip_mesh := TorusMesh.new()
	lip_mesh.inner_radius = 45.4
	lip_mesh.outer_radius = 46.4
	lip_mesh.rings = 64
	lip_mesh.ring_segments = 6
	lip.mesh = lip_mesh
	lip.position = Vector3(0.0, 0.04, 0.0)
	lip.material_override = apron_dark
	root.add_child(lip)
	for r in [14.0, 24.0, 34.0, 43.0]:
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = r - 0.16
		rm.outer_radius = r + 0.16
		rm.rings = 64
		rm.ring_segments = 6
		ring.mesh = rm
		ring.position = Vector3(0.0, 0.05, 0.0)
		ring.material_override = apron_dark
		root.add_child(ring)
	for a in range(0, 12):
		var ang := TAU * float(a) / 12.0
		var seam := _pad_box(apron_dark, Vector3(44.0, 0.06, 0.35),
			Vector3(cos(ang) * 22.0, 0.05, sin(ang) * 22.0), Vector3(0.0, rad_to_deg(-ang), 0.0))
		root.add_child(seam)
	# Exhaust deflection channel running down-slope from the mount.
	root.add_child(_pad_box(apron_dark, Vector3(6.0, 0.10, 40.0), Vector3(-4.0, 0.06, 26.0)))
	root.add_child(_pad_box(scorch, Vector3(9.0, 0.5, 9.0), Vector3(-4.0, 0.6, 3.0)))

	# --- launch mount hardware ---------------------------------------------
	# The vehicle used to stand on a bare concrete disc; a real mount has a
	# key ring, hold-down posts, a flame trench grille and a strongback arm.
	root.add_child(_pad_cyl(paint_steel, 3.4, 3.6, 0.7, Vector3(0.0, 1.15, 0.0), 32))
	var grille := _pad_cyl(scorch, 3.0, 3.0, 0.14, Vector3(0.0, 1.52, 0.0), 32)
	root.add_child(grille)
	for gi in range(0, 8):
		var ga := TAU * float(gi) / 8.0
		root.add_child(_pad_box(apron_dark, Vector3(5.6, 0.10, 0.28),
			Vector3(cos(ga) * 1.4, 1.61, sin(ga) * 1.4), Vector3(0.0, rad_to_deg(-ga), 0.0)))
	# Hold-down clamp arms: eight levers that reach in and bear on the vehicle's
	# base ring while it sits safed, then swing down-and-clear the instant it is
	# about to fly.  Each is a hinge (oriented tangentially) with a swinging lever
	# so the release is a real rotation, not a pop.
	for ci in range(0, 8):
		var ca := TAU * float(ci) / 8.0
		var hinge := Node3D.new()
		hinge.position = Vector3(cos(ca) * 3.6, 2.35, sin(ca) * 3.6)
		hinge.rotation.y = -ca
		root.add_child(hinge)
		# Vertical support post from the mount ring up to the hinge pin.
		hinge.add_child(_pad_box(paint_steel, Vector3(0.34, 1.5, 0.44), Vector3(0.0, -0.75, 0.0)))
		var swing := Node3D.new()
		hinge.add_child(swing)
		# Lever reaching inward to the airframe.
		swing.add_child(_pad_box(paint_steel, Vector3(1.75, 0.30, 0.46), Vector3(-0.85, 0.0, 0.0)))
		# Clamp pad that actually bears on the vehicle.
		swing.add_child(_pad_box(paint_red, Vector3(0.34, 1.0, 0.66), Vector3(-1.72, 0.05, 0.0)))
		# Hydraulic actuator strut riding along the lever.
		swing.add_child(_pad_cyl(paint_steel, 0.11, 0.11, 1.3, Vector3(-0.5, 0.42, 0.0), 8))
		_holddown_pivots.append(swing)
	# Umbilical quick-disconnect lines running out to the trench edge.
	for i in 4:
		var ha := TAU * (float(i) + 0.5) / 4.0
		var hx := cos(ha) * 2.7
		var hz := sin(ha) * 2.7
		root.add_child(_pad_box(rusty_line, Vector3(0.5, 0.35, 9.0),
			Vector3(hx * 2.6, 0.35, hz * 2.6), Vector3(0.0, rad_to_deg(-ha), 0.0)))
	# Strongback: a tower standing beside the vehicle that hinges back clear
	# after ignition.  Wrapped in a base pivot so it swings away as one body.
	var sb := Node3D.new()
	sb.position = Vector3(5.6, 0.6, 0.0)
	root.add_child(sb)
	sb.add_child(_pad_box(apron_dark, Vector3(4.0, 1.2, 4.0), Vector3(0.0, 0.0, 0.0)))
	sb.add_child(_pad_box(paint_steel, Vector3(1.1, 10.5, 1.1), Vector3(-0.6, 5.2, 0.0),
		Vector3(0.0, 0.0, 6.0)))
	for sy in [2.5, 5.5, 8.5]:
		sb.add_child(_pad_box(paint_steel, Vector3(3.4, 0.28, 0.28), Vector3(-2.2, sy - 0.6, 0.0)))
	sb.add_child(_pad_cyl(paint_steel, 0.16, 0.16, 10.0, Vector3(-0.4, 5.2, 0.9), 8))
	sb.add_child(_pad_cyl(paint_steel, 0.16, 0.16, 10.0, Vector3(-0.4, 5.2, -0.9), 8))
	_holddown_strongback = sb

	# --- ring road and perimeter -------------------------------------------
	var road := MeshInstance3D.new()
	var road_mesh := TorusMesh.new()
	road_mesh.inner_radius = 56.0
	road_mesh.outer_radius = 64.0
	road_mesh.rings = 72
	road_mesh.ring_segments = 6
	road.mesh = road_mesh
	road.position = Vector3(0.0, 0.06, 0.0)
	road.material_override = asphalt
	root.add_child(road)
	for a in range(0, 24):
		var ang2 := TAU * float(a) / 24.0
		root.add_child(_pad_box(paint_white, Vector3(1.4, 0.08, 0.25),
			Vector3(cos(ang2) * 60.0, 0.11, sin(ang2) * 60.0),
			Vector3(0.0, rad_to_deg(-(ang2 + PI / 2.0)), 0.0)))

	# --- lightning protection towers ---------------------------------------
	for i in 4:
		var la := TAU * (float(i) + 0.5) / 4.0
		var lx := cos(la) * 34.0
		var lz := sin(la) * 34.0
		root.add_child(_pad_cyl(paint_steel, 0.18, 0.45, 30.0, Vector3(lx, 15.0, lz), 8))
		for leg in 3:
			var lg := TAU * float(leg) / 3.0
			root.add_child(_pad_box(paint_steel, Vector3(0.16, 7.0, 0.16),
				Vector3(lx + cos(lg) * 1.6, 3.5, lz + sin(lg) * 1.6),
				Vector3(sin(lg) * 14.0, 0.0, -cos(lg) * 14.0)))
		root.add_child(_pad_cyl(paint_red, 0.30, 0.30, 1.2, Vector3(lx, 30.6, lz), 8))

	# --- crawler-transporter under the pad ---------------------------------
	var crawler := Node3D.new()
	crawler.name = "Crawler"
	crawler.position = Vector3(0.0, 0.0, -22.0)
	root.add_child(crawler)
	crawler.add_child(_pad_box(paint_yellow, Vector3(20.0, 2.2, 13.0), Vector3(0.0, 2.6, 0.0)))
	crawler.add_child(_pad_box(paint_yellow, Vector3(16.0, 1.0, 10.0), Vector3(0.0, 4.0, 0.0)))
	for sx in [-8.2, 8.2]:
		for sz in [-5.0, 5.0]:
			crawler.add_child(_pad_box(asphalt, Vector3(3.6, 2.6, 9.0), Vector3(sx, 1.3, sz)))
			for wz in [-3.4, 0.0, 3.4]:
				var wheel := _pad_cyl(paint_steel, 1.1, 1.1, 0.6, Vector3(sx, 1.3, sz + wz), 10)
				wheel.rotation_degrees.z = 90.0
				crawler.add_child(wheel)

	# --- tank farm, ops building, water tower ------------------------------
	for i in 5:
		var tx := -34.0 + float(i) * 5.0
		root.add_child(_pad_cyl(paint_white, 2.2, 2.2, 6.0, Vector3(tx, 3.0, -38.0), 16))
		root.add_child(_pad_cyl(apron_dark, 2.35, 2.35, 0.4, Vector3(tx, 6.1, -38.0), 16))
	root.add_child(_pad_box(paint_steel, Vector3(1.2, 4.0, 1.2), Vector3(-22.0, 2.0, -30.0)))
	root.add_child(_pad_box(paint_red, Vector3(14.0, 5.0, 9.0), Vector3(34.0, 2.5, -30.0)))
	root.add_child(_pad_box(paint_steel, Vector3(14.6, 0.6, 9.6), Vector3(34.0, 5.3, -30.0)))
	for cx in [30.0, 34.0, 38.0]:
		root.add_child(_pad_box(paint_white, Vector3(1.6, 1.4, 0.1), Vector3(cx, 2.2, -25.45)))
	root.add_child(_pad_cyl(paint_steel, 3.0, 3.0, 12.0, Vector3(-40.0, 14.0, 18.0), 16))
	for i in 4:
		var ba := TAU * float(i) / 4.0
		root.add_child(_pad_box(paint_steel, Vector3(0.3, 14.0, 0.3),
			Vector3(-40.0 + cos(ba) * 2.4, 7.0, 18.0 + sin(ba) * 2.4),
			Vector3(sin(ba) * 6.0, 0.0, -cos(ba) * 6.0)))
	root.add_child(_pad_cyl(paint_red, 0.4, 3.2, 2.6, Vector3(-40.0, 21.3, 18.0), 16))

	# --- perimeter floodlight masts ---------------------------------------
	for i in 6:
		var fa := TAU * float(i) / 6.0 + 0.35
		var fx := cos(fa) * 42.0
		var fz := sin(fa) * 42.0
		root.add_child(_pad_cyl(paint_steel, 0.14, 0.22, 11.0, Vector3(fx, 5.5, fz), 8))
		var head := _pad_box(paint_steel, Vector3(1.8, 0.7, 0.7), Vector3(fx, 11.2, fz),
			Vector3(0.0, rad_to_deg(fa + PI / 2.0), 0.0))
		root.add_child(head)
		var lamp_mat := StandardMaterial3D.new()
		lamp_mat.albedo_color = Color(0.95, 0.93, 0.80, 1.0)
		lamp_mat.emission_enabled = true
		lamp_mat.emission = Color(1.0, 0.95, 0.78, 1.0)
		lamp_mat.emission_energy_multiplier = 1.6
		root.add_child(_pad_box(lamp_mat, Vector3(1.5, 0.45, 0.12),
			Vector3(fx - sin(fa) * 0.4, 11.2, fz + cos(fa) * 0.4), Vector3(0.0, rad_to_deg(fa + PI / 2.0), 0.0)))

func _create_smoke_and_dust() -> void:
	if not rocket: return
	smoke_particles = GPUParticles3D.new()
	smoke_particles.name = "ExhaustSmoke"
	smoke_particles.position = Vector3(0.0, -8.2, 0.0)
	smoke_particles.local_coords = false
	smoke_particles.amount = 80
	smoke_particles.lifetime = 1.4
	smoke_particles.randomness = 0.55
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.direction = Vector3(0.0, -1.0, 0.0)
	smoke_process.spread = 38.0
	smoke_process.gravity = Vector3(0.0, 1.7, 0.0)
	smoke_process.initial_velocity_min = 7.0
	smoke_process.initial_velocity_max = 18.0
	smoke_process.scale_min = 0.18
	smoke_process.scale_max = 0.65
	var smoke_gradient := Gradient.new()
	smoke_gradient.set_color(0, Color(0.82, 0.72, 0.58, 0.42))
	smoke_gradient.add_point(0.35, Color(0.36, 0.34, 0.32, 0.25))
	smoke_gradient.add_point(1.0, Color(0.12, 0.12, 0.13, 0.0))
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke_gradient
	smoke_process.color_ramp = smoke_ramp
	smoke_particles.process_material = smoke_process
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.75
	smoke_mesh.height = 1.5
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color(0.34, 0.30, 0.24, 0.38)
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mesh.material = smoke_mat
	smoke_particles.draw_pass_1 = smoke_mesh
	rocket.add_child(smoke_particles)

	dust_particles = GPUParticles3D.new()
	dust_particles.name = "PadDust"
	dust_particles.position = Vector3(0.0, -8.4, 0.0)
	dust_particles.local_coords = false
	dust_particles.amount = 100
	dust_particles.lifetime = 1.1
	dust_particles.randomness = 0.7
	var dust_process := ParticleProcessMaterial.new()
	dust_process.direction = Vector3(0.0, 0.15, 0.0)
	dust_process.spread = 180.0
	dust_process.gravity = Vector3(0.0, 0.25, 0.0)
	dust_process.initial_velocity_min = 4.0
	dust_process.initial_velocity_max = 13.0
	dust_process.scale_min = 0.16
	dust_process.scale_max = 0.55
	var dust_gradient := Gradient.new()
	dust_gradient.set_color(0, Color(0.42, 0.36, 0.28, 0.34))
	dust_gradient.add_point(0.5, Color(0.28, 0.26, 0.22, 0.18))
	dust_gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0.0))
	var dust_ramp := GradientTexture1D.new()
	dust_ramp.gradient = dust_gradient
	dust_process.color_ramp = dust_ramp
	dust_particles.process_material = dust_process
	dust_particles.draw_pass_1 = smoke_mesh
	rocket.add_child(dust_particles)

func _create_engine_plume_meshes() -> void:
	if not rocket: return
	# Solid tapered meshes provide a continuous white-hot exhaust core. The GPU
	# particles are now only the turbulent edge and smoke, not a chain of balls.
	plume_outer = MeshInstance3D.new()
	plume_outer.name = "PlumeOuter"
	var outer_mesh := CylinderMesh.new()
	outer_mesh.top_radius = 0.48
	outer_mesh.bottom_radius = 1.8
	outer_mesh.height = 10.0
	plume_outer.mesh = outer_mesh
	plume_outer.position.y = -12.3
	var outer_mat := StandardMaterial3D.new()
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.albedo_color = Color(1.0, 0.20, 0.015, 0.62)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(1.0, 0.08, 0.0, 1.0)
	outer_mat.emission_energy_multiplier = 3.0
	plume_outer.material_override = outer_mat
	rocket.add_child(plume_outer)

	plume_core = MeshInstance3D.new()
	plume_core.name = "PlumeCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.23
	core_mesh.bottom_radius = 0.78
	core_mesh.height = 8.5
	plume_core.mesh = core_mesh
	plume_core.position.y = -11.0
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.92, 0.5, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.62, 0.08, 1.0)
	core_mat.emission_energy_multiplier = 5.0
	plume_core.material_override = core_mat
	rocket.add_child(plume_core)

	# In thin air the nozzle plume develops bright expansion cells ("shock
	# diamonds"). These are subtle and only appear after the dense-atmosphere
	# smoke has dropped away, keeping liftoff visually grounded.
	var diamond_mat := StandardMaterial3D.new()
	diamond_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	diamond_mat.albedo_color = Color(0.42, 0.76, 1.0, 0.82)
	diamond_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	diamond_mat.emission_enabled = true
	diamond_mat.emission = Color(0.15, 0.55, 1.0, 1.0)
	diamond_mat.emission_energy_multiplier = 3.8
	for i in 3:
		var diamond := MeshInstance3D.new()
		diamond.name = "ExpansionCell%d" % i
		var diamond_mesh := CylinderMesh.new()
		diamond_mesh.top_radius = 0.18 + i * 0.08
		diamond_mesh.bottom_radius = 0.42 + i * 0.16
		diamond_mesh.height = 1.15 + i * 0.22
		diamond.mesh = diamond_mesh
		diamond.position = Vector3(0.0, -16.0 - i * 1.7, 0.0)
		diamond.material_override = diamond_mat
		diamond.hide()
		rocket.add_child(diamond)
		plume_diamonds.append(diamond)
	plume_core.hide()
	plume_outer.hide()

func _set_engine_fx(active: bool, ground_cloud: bool = false) -> void:
	# The old sphere-particle flame read as floating bubbles. The tapered plume
	# meshes carry the combustion flame; particles are reserved for smoke/dust.
	if exhaust_particles: exhaust_particles.emitting = false
	if smoke_particles: smoke_particles.emitting = active
	if dust_particles: dust_particles.emitting = active and ground_cloud
	if plume_core: plume_core.visible = active and not _hide_legacy_plume
	if plume_outer: plume_outer.visible = active and not _hide_legacy_plume
	for diamond in plume_diamonds:
		diamond.visible = active and altitude_km > 18.0 and not _hide_legacy_plume
	_set_model_flame(active)
	if engine_light: engine_light.light_energy = 2.0 if active else 0.0

func _update_plume_animation(delta: float) -> void:
	if not plume_core or not plume_core.visible: return
	plume_pulse += delta * (7.0 + throttle * 0.05)
	var flicker := 1.0 + sin(plume_pulse) * 0.055 + sin(plume_pulse * 2.71) * 0.025
	plume_core.scale = Vector3(flicker, 0.94 + flicker * 0.06, flicker)
	if plume_outer:
		plume_outer.scale = Vector3(1.0 + (flicker - 1.0) * 1.8, 0.95 + flicker * 0.05, 1.0 + (flicker - 1.0) * 1.8)
	for i in plume_diamonds.size():
		var diamond := plume_diamonds[i]
		diamond.visible = altitude_km > 18.0 and state != LaunchState.STAGE_SEP
		diamond.scale = Vector3.ONE * (0.86 + sin(plume_pulse * 1.7 + i) * 0.12)

func _create_launch_audio() -> void:
	# A lightweight synthesized rumble gives the launch physical weight until
	# recorded engine assets are added in a later sound-design pass.
	engine_audio = AudioStreamPlayer.new()
	engine_audio.name = "EngineRumble"
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.5
	engine_audio.stream = stream
	# The old level was effectively inaudible on typical laptop speakers.
	engine_audio.volume_db = -4.0
	add_child(engine_audio)
	engine_audio.play()

	cue_audio = AudioStreamPlayer.new()
	cue_audio.name = "MissionCue"
	var cue_stream := AudioStreamGenerator.new()
	cue_stream.mix_rate = 22050.0
	cue_stream.buffer_length = 0.35
	cue_audio.stream = cue_stream
	cue_audio.volume_db = -4.0
	add_child(cue_audio)
	cue_audio.play()

func _create_mission_callouts() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	callout_label = Label.new()
	callout_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	callout_label.position = Vector2(-330.0, 32.0)
	callout_label.size = Vector2(660.0, 46.0)
	callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callout_label.add_theme_font_size_override("font_size", 19)
	callout_label.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0, 1.0))
	callout_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	callout_label.add_theme_constant_override("shadow_offset_x", 2)
	callout_label.add_theme_constant_override("shadow_offset_y", 2)
	callout_label.hide()
	layer.add_child(callout_label)

func _show_callout(message: String, duration: float = 2.6) -> void:
	if not callout_label: return
	callout_label.text = message
	callout_label.show()
	callout_label.modulate.a = 1.0
	callout_timer = duration

func _play_cue(frequency: float, duration: float = 0.12) -> void:
	if not cue_audio: return
	if not cue_playback:
		cue_playback = cue_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if not cue_playback: return
	var frames: int = min(int(22050.0 * duration), cue_playback.get_frames_available())
	for i in frames:
		var envelope: float = 1.0 - float(i) / maxf(float(frames), 1.0)
		var sample: float = sin(float(i) * TAU * frequency / 22050.0) * 0.24 * envelope
		cue_playback.push_frame(Vector2(sample, sample))

func _update_engine_audio() -> void:
	if not engine_audio: return
	if not engine_playback:
		engine_playback = engine_audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if not engine_playback: return
	var frames: int = min(engine_playback.get_frames_available(), 768)
	var intensity := (throttle / 100.0) if state >= LaunchState.LIFTOFF else 0.0
	for i in frames:
		var low := sin(engine_phase * TAU * 46.0)
		var growl := sin(engine_phase * TAU * 93.0) * 0.42
		var vibration := sin(engine_phase * TAU * 7.0) * 0.18
		var roar := sin(engine_phase * TAU * 183.0) * 0.16
		var sample := (low + growl + vibration + roar) * 0.19 * intensity
		engine_playback.push_frame(Vector2(sample, sample))
		engine_phase += 1.0 / 22050.0

# ─── Mission Config ───────────────────────────────────────────────────────────
func _setup_from_mission() -> void:
	var rd: Dictionary = GameManager.spacecraft_config.get("rocket", {})
	var id: String = rd.get("id", "falcon9")
	flight_id = id
	var tm: Dictionary = {
		"electron":160.0,"falcon9":7600.0,
		"falcon_heavy":22800.0,"sls":39000.0,"starship":74000.0}
	# Each launcher needs its own wet mass. A universal Falcon-class tank made
	# Electron's thrust-to-weight ratio below 1, so it burned fuel on the pad.
	var first_stage_propellant: Dictionary = {
		"electron": 9000.0, "falcon9": 395000.0,
		"falcon_heavy": 1200000.0, "sls": 900000.0, "starship": 1000000.0}
	var vehicle_dry_mass: Dictionary = {
		"electron": 1800.0, "falcon9": 22000.0,
		"falcon_heavy": 142000.0, "sls": 130000.0, "starship": 120000.0}
	thrust_kN   = tm.get(id, 7600.0)
	# Gameplay-scale upper stages: each begins with a positive TWR, including
	# Electron. This prevents a second-stage burn that appears to hang in place.
	var upper_stage: Dictionary = {
		"electron": {"thrust": 55.0, "propellant": 2000.0, "dry_mass": 600.0},
		"falcon9": {"thrust": 1500.0, "propellant": 110000.0, "dry_mass": 4500.0},
		"falcon_heavy": {"thrust": 1500.0, "propellant": 110000.0, "dry_mass": 4500.0},
		"sls": {"thrust": 1800.0, "propellant": 80000.0, "dry_mass": 8000.0},
		"starship": {"thrust": 3500.0, "propellant": 100000.0, "dry_mass": 9000.0}}
	var upper_config: Dictionary = upper_stage.get(id, upper_stage["falcon9"])
	stage_2_thrust_kN = float(upper_config["thrust"])
	stage_2_propellant_kg = float(upper_config["propellant"])
	stage_2_dry_mass_kg = float(upper_config["dry_mass"])
	payload_mass_kg = float(rd.get("payload_kg", 500))
	stage_1_propellant_kg = float(first_stage_propellant.get(id, 395000.0))
	stage_1_dry_mass_kg = float(vehicle_dry_mass.get(id, 22000.0))
	# Everything that is not first-stage propellant rides along on burn one:
	# the first stage's own structure, the whole upper stage, the fairing and
	# the payload.  Getting this right is what makes the acceleration curve,
	# the MECO timing and the peak-g figure come out like the real thing.
	inert_mass_kg = stage_1_dry_mass_kg + stage_2_dry_mass_kg \
		+ stage_2_propellant_kg + fairing_mass_kg + payload_mass_kg
	propellant_total_kg = stage_1_propellant_kg
	propellant_left_kg = stage_1_propellant_kg
	rocket_mass = inert_mass_kg + propellant_left_kg
	dry_mass = inert_mass_kg
	var mission: Dictionary = GameManager.current_mission
	# An Earth-parking orbit is what the launch actually delivers; deep-space
	# missions state their *destination* altitude, which is not a launch target.
	target_orbit_km = maxf(200.0, float(mission.get("altitude_km", 550)))
	if String(mission.get("id", "")) == "moon_scout" or String(mission.get("id", "")) == "mars_orbiter" \
			or String(mission.get("id", "")) == "asteroid_probe":
		target_orbit_km = 200.0
	target_inclination_deg = float(mission.get("inclination_deg", 51.6))
	var r_target: float = body_radius_km + target_orbit_km
	orbit_speed_target = sqrt(body_mu / r_target) * 1000.0
	periapsis_ready_km = target_orbit_km - 10.0
	mars_payload = GameManager.is_mars_mission()
	# Only two of the vehicles in the catalogue come back.  Saying so honestly is
	# part of the simulation: an Electron first stage or an SLS core is not going
	# to stand itself up on a deck in the ocean, and the flight should admit that
	# instead of staging in an invented landing.
	# Player request: the reusable-landing system and its split-screen return are
	# switched OFF.  Every stage now separates as expendable debris, the split
	# never opens, and the handover to the destination scene (lunar transfer for
	# moon_scout) fires on the normal post-SECO timer instead of waiting on a
	# booster touchdown that may never resolve.  To bring the recovery film back,
	# restore: booster_recoverable = id == "falcon9" or id == "falcon_heavy"
	booster_recoverable = false
	# The stage that comes home pays for its own return out of stage 1's tanks:
	# MECO cuts at the reserve line, not at empty, and the booster then flies
	# boostback, entry and landing burns against that real propellant budget.
	# If the reserve is short, the stage runs out over the deck and crashes —
	# which is the honest consequence, not a scripted outcome.
	# MA_BOOSTER_RESERVE_KG overrides it for verification (starve/crash tests).
	booster_reserve_kg = stage_1_propellant_kg * BOOSTER_RESERVE_FRAC if booster_recoverable else 0.0
	var reserve_env: String = OS.get_environment("MA_BOOSTER_RESERVE_KG")
	if reserve_env != "":
		booster_reserve_kg = float(reserve_env)
	print("[Launch] Vehicle %s | %.0f kN | %.0f kg wet | TWR %.2f | target %.0f km @ %.1f° | v_circ %.0f m/s" % [
		id, thrust_kN, rocket_mass, (thrust_kN * 1000.0) / (rocket_mass * gravity),
		target_orbit_km, target_inclination_deg, orbit_speed_target])

# ─── Process Loop ─────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if GameManager.is_paused: return
	state_timer += delta
	# Honest time compression.  The mission runs at wall-clock 1x by default;
	# the only speed-up in the simulation is the warp factor the player picks
	# from the bottom bar (or keys 1-6, or the mouse wheel).  Nothing in the
	# flight secretly runs faster than the HUD says it does.
	sim_speed = _compute_sim_speed()
	var sim_delta: float = delta * sim_speed
	if state != LaunchState.PRE_LAUNCH and state != LaunchState.COUNTDOWN:
		met_seconds += sim_delta
	_update_engine_audio()
	# Fixed-step integration.  Mission time is compressed, so a single rendered
	# frame can represent a third of a second of flight; feeding that whole span
	# to an explicit Euler step on a slow frame would make the trajectory jitter
	# or overshoot its event gates.  Physics always advances in small, identical
	# slices, which keeps the flight path smooth and reproducible.
	_sim_accumulator += sim_delta
	var guard: int = 0
	# The bound has to clear the highest warp on the slowest plausible frame:
	# 32x on a two-second hitch is 640 slices, so the guard carries real mission
	# time rather than silently discarding it.
	while _sim_accumulator >= MAX_SIM_STEP_S and guard < 900:
		_advance_flight(MAX_SIM_STEP_S)
		_sim_accumulator -= MAX_SIM_STEP_S
		guard += 1
	if guard >= 900:
		_sim_accumulator = 0.0

	_update_plume_animation(delta)
	_apply_plume_vacuum_tint()
	_update_stage_debris(delta)
	_update_holddowns(delta)
	_update_hud()
	_update_sky_transition()
	# The planet has to turn under the vehicle.  Without it the ascent is a model
	# rising past a still photograph; with the ground track rolling off and the
	# planet rotating beneath it, the same shot reads as a vehicle moving at
	# hundreds of metres per second over a real surface.
	if horizon_active and horizon_world:
		horizon_spin += delta * 0.05
		horizon_world.rotation.y = horizon_spin - downrange_km * 0.014
	_update_cloud_fade(delta)
	# The orbital angle advances before the vehicle is placed, so the model is
	# never one frame behind the planet it is circling.
	var flown: bool = state != LaunchState.PRE_LAUNCH and state != LaunchState.COUNTDOWN
	if flown:
		# The space frame advances on the *mission* clock, not the render clock:
		# one orbit really does take orbit_period_min of mission time whatever
		# the frame rate is, and warp is the only way to see it faster.
		_update_space_frame(sim_delta)
	# The returning stage is flown after the space frame advances, so its position
	# on the planet is computed from the orbital angle of *this* frame rather than
	# trailing it by one.
	if flown:
		_update_booster(delta)
	if state == LaunchState.PRE_LAUNCH:
		_update_pad_camera_idle(delta)
	elif state == LaunchState.COUNTDOWN:
		pass
	elif state == LaunchState.SATELLITE_DEPLOY:
		_position_vehicle()
		_update_satellite_deploy(delta)
	else:
		_update_ascent_cameras(delta)
	if callout_timer > 0.0:
		callout_timer -= delta
		if callout_label:
			callout_label.modulate.a = clampf(callout_timer / 0.45, 0.0, 1.0)
			if callout_timer <= 0.0: callout_label.hide()
	if handoff_fade and state == LaunchState.COMPLETE:
		handoff_fade.color.a = clampf(state_timer / 4.5, 0.0, 1.0)
	if flown:
		_update_space_camera()
		_update_chase_camera(rocket.position.y if rocket else 0.0)

## One slice of the flight, driven by the state machine.
func _advance_flight(dt: float) -> void:
	match state:
		LaunchState.COUNTDOWN:      _update_countdown(dt)
		LaunchState.LIFTOFF, LaunchState.MAX_Q, LaunchState.STAGE_SEP, LaunchState.FAIRING_SEP:
			_update_ascent(dt)
		LaunchState.ORBITAL_INSERT: _update_orbital_insert(dt)
		LaunchState.SATELLITE_DEPLOY:
			_update_orbital_insert(dt)
		LaunchState.COMPLETE:       _update_orbital_insert(dt)
		_: pass
	# The returning stage is integrated on the same fixed slices as the ascent,
	# so its burns, its drag and its propellant budget stay honest at any warp.
	_booster_physics(dt)

## Compression factor for the current moment of the flight.  There is no
## phase-based compression any more: the mission clock is real time, and the
## player chooses a warp step.  MA_LAUNCH_WARP is a verification-only
## multiplier on top of that, used by the headless trajectory probe so a
## twenty-minute mission can still be replayed in a couple of wall minutes.
func _compute_sim_speed() -> float:
	if state == LaunchState.PRE_LAUNCH or state == LaunchState.COUNTDOWN:
		# The pad and the countdown are always shown at real speed.
		return 1.0
	return WARP_STEPS[player_warp_idx] * SPEED_STEPS[player_speed_idx] * _debug_warp

## Piecewise-linear lookup through a table keyed on seconds after separation.
## No flight logic uses it any more — only the reference profile's own shape,
## if a future readout ever needs it — and nothing drives the vehicle with it.
func _keyed_at(keys: Array, dt: float, field: String) -> float:
	var lo: Dictionary = keys[0]
	var hi: Dictionary = keys[keys.size() - 1]
	for i in keys.size() - 1:
		var this_key: Dictionary = keys[i]
		var next_key: Dictionary = keys[i + 1]
		if dt >= float(this_key["dt"]) and dt <= float(next_key["dt"]):
			lo = this_key
			hi = next_key
			break
		if dt > float(next_key["dt"]):
			lo = next_key
			hi = next_key
	var span: float = maxf(float(hi["dt"]) - float(lo["dt"]), 0.0001)
	var w: float = clampf((dt - float(lo["dt"])) / span, 0.0, 1.0)
	return lerpf(float(lo[field]), float(hi[field]), w)

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard launch is useful for desktop play and gives the cinematic a
	# dependable control path if a UI overlay has focus.
	if state == LaunchState.PRE_LAUNCH and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_launch_pressed()
	# Warp shortcuts: keys 1-6 select the six steps, and the mouse wheel over
	# the viewport walks them up and down.  This is the player's only control
	# over the flight — there are no handling inputs; the film is honest.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_set_warp_idx(int(event.keycode) - int(KEY_1))
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_warp_idx(mini(player_warp_idx + 1, WARP_STEPS.size() - 1))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_warp_idx(maxi(player_warp_idx - 1, 0))

## Change the player's warp step from anywhere (button, keys, wheel, probe).
func _set_warp_idx(idx: int) -> void:
	player_warp_idx = clampi(idx, 0, WARP_STEPS.size() - 1)
	if warp_btn:
		warp_btn.text = "WARP ×%d" % int(WARP_STEPS[player_warp_idx])

## Change the LAUNCH-adjacent speed lever (Normal / ×2 / ×3).
func _set_speed_idx(idx: int) -> void:
	player_speed_idx = clampi(idx, 0, SPEED_STEPS.size() - 1)
	if speed_btn:
		var m: float = SPEED_STEPS[player_speed_idx]
		speed_btn.text = "SPEED: NORMAL" if m <= 1.0 else ("SPEED: ×%d" % int(m))

# ─── Sky transition: blue → black as altitude increases ───────────────────────
## ProceduralSky fade.  Kept separate from the environment cooling so a missing
## sky material cannot disable the rest of the altitude grading.
func _update_sky_colors() -> void:
	# The first portion of ascent stays recognisably blue.  The former 0–80 km
	# linear fade made the sky turn black while the rocket was still in its
	# gravity-turn shot.  This 5–95 km curve reaches space gradually.
	var t: float = smoothstep(5.0, 95.0, altitude_km)
	sky_material.sky_top_color     = sky_top_day.lerp(Color(0.0, 0.0, 0.02, 1.0), t)
	# The pad shot is graded for a sunset, and the sunset has to be *gone* the
	# moment the vehicle is clear of the tower — a rocket at 2 km cannot still be
	# flying against an amber horizon, and every cloud deck above it would inherit
	# that amber and lose all contrast of its own.  So the first leg is keyed to
	# altitude directly and finishes by the first cloud layer, handing the band over
	# to daytime blue; the second leg is the air itself going out on the way to the
	# Kármán line.
	var off_pad: float = smoothstep(0.15, 2.4, altitude_km)
	var leg2: float = clampf((t - 0.20) / 0.80, 0.0, 1.0)
	sky_material.sky_horizon_color = sky_horizon_day.lerp(Color(0.24, 0.52, 0.88, 1.0), off_pad) \
		.lerp(Color(0.0, 0.0, 0.05, 1.0), leg2)
	# Everything below the planetary limb is space, not lit desert.  ProceduralSky
	# paints its ground hemisphere with these two colours, so unless they go dark
	# the instant the shell takes over a warm wedge shows up outside the planet's
	# silhouette — the one artefact that made the whole ascent read as a set.
	var ground_out: float = smoothstep(0.9, 3.5, altitude_km)
	sky_material.ground_bottom_color = ground_bottom_day.lerp(Color(0.0, 0.0, 0.0, 1.0), ground_out)
	sky_material.ground_horizon_color = ground_horizon_day.lerp(Color(0.004, 0.010, 0.030, 1.0), ground_out)
	# The limb haze on the planetary shell strengthens as the camera pulls away
	# from it, so the edge of the planet keeps reading as air rather than as the
	# rim of a prop.  Keyed to the same off-pad ramp, because the shell only
	# exists above the tower.
	if horizon_haze:
		var hm := horizon_haze.material_override as StandardMaterial3D
		if hm:
			hm.emission_energy_multiplier = lerpf(0.55, 1.7, ground_out)
			hm.albedo_color.a = lerpf(0.08, 0.34, ground_out)

func _update_sky_transition() -> void:
	# The sky fade and the environment cooling are independent: losing the sky
	# material must not also disable the sun/fog ramp, which would leave the
	# whole ascent amber.
	if sky_material:
		_update_sky_colors()
	# The pad is graded for a warm sunset, which is precisely the look that has to
	# burn off as the vehicle climbs: above the atmosphere sunlight is white and
	# unfiltered, and there is no haze layer left to tint anything amber.  Cooling
	# the ambient, fog and sun together is what stops 40 km from reading as a tan
	# void instead of a lit planet under a black sky.
	if world_env and world_env.environment and not in_space_frame:
		var env := world_env.environment
		var cool: float = smoothstep(6.0, 70.0, altitude_km)
		# The pad is graded for a sunset, and that grade has to leave the picture
		# almost as soon as the vehicle is airborne.  Left in, it tinted every cloud
		# deck the climb passes through the same peach as the sky, so the weather had
		# no contrast of its own and the first kilometre of the ascent read as a
		# single flat colour.  Two stages: amber out, then blue out.
		var warm_out: float = smoothstep(0.15, 2.6, altitude_km)
		env.ambient_light_color = Color(0.60, 0.66, 0.72).lerp(Color(0.86, 0.90, 0.98), warm_out) \
			.lerp(Color(0.52, 0.60, 0.78), cool)
		env.fog_light_color = Color(0.68, 0.74, 0.82).lerp(Color(0.72, 0.84, 0.98), warm_out) \
			.lerp(Color(0.28, 0.44, 0.74), cool)
		env.fog_light_energy = lerpf(0.60, 0.55, warm_out) * lerpf(1.0, 0.35, cool)
		if altitude_km > 6.0:
			# Volumetric fog near the camera is what was painting the whole
			# upper frame amber. Once airborne it only ever lies below.
			env.fog_enabled = false
		if env_sun:
			env_sun.light_color = Color(1.0, 0.88, 0.74).lerp(Color(1.0, 0.93, 0.86), warm_out) \
				.lerp(Color(1.0, 0.97, 0.92), cool)
			env_sun.light_energy = lerpf(1.50, 1.80, cool)
			env_sun.rotation_degrees = Vector3(lerpf(-30.0, -52.0, cool), 40.0, 0.0)
	# Crossing the Kármán line hands the scene over to the space frame, which
	# owns the planet, the star shell and the sun grading from here on.
	if altitude_km > SPACE_ALTITUDE_KM and not in_space_frame:
		_enter_space_frame()
	if in_space_frame and not space_background_locked and world_env and world_env.environment:
		space_background_locked = true
		world_env.environment.background_mode = Environment.BG_COLOR
		world_env.environment.background_color = Color(0.0, 0.0, 0.008, 1.0)
		world_env.environment.fog_enabled = false
		# Cinematic, physically-plausible space grading.  Filmic tonemapping keeps
		# the sunlit limb and the pitch-black sky in the same frame without the flat,
		# posterised look it gave here; ACES rolls the highlights off like a real
		# camera.  Deep space is lit only by the sun and earthshine, so the pad-era
		# ambient wash is cut hard — that is what lets the craft's shadow side go
		# black and the terminator read crisp instead of cartoon.  Glow stays
		# restrained because ACES already handles the bright rolloff.
		world_env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		world_env.environment.tonemap_exposure = 1.12
		world_env.environment.tonemap_white = 6.0
		world_env.environment.ambient_light_energy = 0.06
		world_env.environment.ambient_light_color = Color(0.30, 0.38, 0.55)
		world_env.environment.glow_enabled = true
		world_env.environment.glow_intensity = 0.55
		world_env.environment.glow_strength = 0.55
		world_env.environment.glow_bloom = 0.06
		world_env.environment.glow_hdr_threshold = 1.1
		# The star shell sits far outside the pad-era clipping plane.
		for c in [cam_pad, cam_engine, cam_chase, cam_space, cam_tower, cam_wide]:
			if c != null:
				c.far = 9000.0

# ─── Idle pad camera slowly pans ──────────────────────────────────────────────
func _update_pad_camera_idle(delta: float) -> void:
	if not cam_pad: return
	# Lock the ready-to-launch composition. A continuously orbiting camera could
	# place the vehicle at the bottom edge, behind the control panel.
	var desired_position: Vector3 = Vector3(25.0, 21.0, 64.0)
	cam_pad.position = cam_pad.position.lerp(desired_position, min(delta * 3.0, 1.0))
	cam_pad.look_at(Vector3(0.0, 10.5, 0.0), Vector3.UP)

# ─── State Machine ────────────────────────────────────────────────────────────
# Every entry here is a *response to a physical event* that has already happened
# in the integrator, and every status line quotes the numbers that caused it, so
# the text on screen can never disagree with the vehicle's behaviour.
func _set_state(new_state: LaunchState) -> void:
	state       = new_state
	state_timer = 0.0
	match new_state:
		LaunchState.PRE_LAUNCH:
			_set_camera(CamMode.PAD)
			if countdown_label: countdown_label.text = "AWAITING LAUNCH"
			if status_label:
				status_label.text = "Earth pad — all systems nominal. Press LAUNCH."
			if launch_btn: launch_btn.disabled = false

		LaunchState.COUNTDOWN:
			countdown_timer = 12.0
			# Re-grip the vehicle so a relaunch opens clamped to the mount, not
			# still standing in the last flight's released pose.
			_reset_holddowns()
			# Clear every flight-history value at the start of a run, so a second
			# launch in the same session can never report the previous vehicle's
			# peak load or the previous insertion time.
			max_q_kpa = 0.0
			max_q_throttle_pct = 100.0
			max_q_declared = false
			meco_done = false
			fairing_jettisoned = false
			seco_done = false
			superq_beat_done = false
			# Weather crossings and phase announcements are per-flight too: without
			# this a relaunch would fly a silent, empty sky.
			layer_beat_idx = 0
			flight_phase_name = ""
			path_distance_km = 0.0
			orbit_period_min = 0.0
			karman_cross_met_s = 0.0
			horizon_spin = 0.0
			# Force the visual swap logic to re-evaluate on the first flight
			# frame instead of trusting state left over from a previous run.
			pad_shrink = -1.0
			horizon_active = true
			if horizon_world:
				horizon_world.hide()
			for reset_name in ["GroundDetail"]:
				var rn := get_node_or_null(reset_name) as Node3D
				if rn:
					rn.show()
			fairing_separated = false
			# A relaunch flies a brand-new first stage.  Everything about the
			# previous vehicle's return — its clock, its landing, its half of the
			# screen and the deck it stood on — is cleared, or a second flight
			# would open on a stage that had already touched down.
			_close_split()
			_clear_booster()
			booster_sep_met = -1.0
			booster_sep_alt_km = RECOVERY_SEP_ALT_KM
			booster_sep_spd_ms = RECOVERY_SEP_SPD_MS
			booster_nose_dir = Vector3.UP
			booster_alt_km = 0.0
			booster_spd_ms = 0.0
			booster_phase_name = ""
			booster_prop_t = 0.0
			booster_burn = 0.0
			booster_landed = false
			booster_touchdown_met_s = 0.0
			booster_touchdown_hold = 0.0
			booster_beat_idx = 0
			booster_dt_now = 0.0
			# The physical return state, so a relaunch flies a stage with a full
			# tank and no memory of the previous vehicle's landing or crash.
			booster_x_km = 0.0
			booster_vx_ms = 0.0
			booster_vy_ms = 0.0
			booster_prop_kg = 0.0
			booster_prop_start_kg = 0.0
			booster_dry_kg = 0.0
			booster_mass_kg = 0.0
			booster_fins_out = false
			booster_gear_out = false
			booster_legs_anim = 0.0
			booster_at_interface = false
			booster_interface_s = 0.0
			booster_entry_start_s = 0.0
			booster_interface_km = BOOSTER_ENTRY_INTERFACE_KM
			booster_crashed = false
			booster_touchdown_speed_ms = 0.0
			booster_peak_entry_g = 0.0
			# A new run starts at honest 1x and may suggest the coast warp again.
			coast_suggest_done = false
			_set_warp_idx(0)
			recovery_dust_alpha = 0.0
			_clear_stage_debris()
			if rocket: rocket.show()
			met_seconds = 0.0
			_sim_accumulator = 0.0
			orbit_angle = 0.0
			coast_timer = 0.0
			# NONE, not RAISE_APOAPSIS: the terminal-insertion guidance law must
			# stay off until the upper stage is actually flying, or it overrides
			# the gravity turn from the pad and the vehicle never climbs.
			insertion_phase = InsertionPhase.NONE
			if launch_btn: launch_btn.disabled = true
			if status_label: status_label.text = "Initiating launch sequence..."
			last_countdown_second = -1
			_show_callout("FLIGHT DIRECTOR: GO FOR LAUNCH")

		LaunchState.LIFTOFF:
			throttle = 100.0
			cam_shake = 1.0
			_set_camera(CamMode.ENGINE)
			_set_engine_fx(true, true)
			_play_cue(92.0, 0.32)
			_show_callout("LIFTOFF — WE HAVE A LIFTOFF", 3.0)
			_set_headline("LIFTOFF", UI_GREEN)
			if status_label:
				status_label.text = "Full thrust, %.0f kN. TWR %.2f — climbing vertically off the pad." % [
					thrust_kN, (thrust_kN * 1000.0) / (rocket_mass * surface_gravity)]

		LaunchState.MAX_Q:
			_set_camera(CamMode.CHASE)
			_play_cue(660.0, 0.09)
			_show_callout("MAX-Q — MAXIMUM DYNAMIC PRESSURE")
			_set_headline("MAX-Q", Color(1.0, 0.62, 0.15))
			if status_label:
				status_label.text = "Max-Q passed: peak load %.1f kPa at %.1f km, %.0f m/s. Engines were held at %.0f%% through the transonic region and are now back to %.0f%%." % [
					max_q_kpa, altitude_km, velocity_ms, max_q_throttle_pct, throttle]

		LaunchState.STAGE_SEP:
			_set_engine_fx(false)
			_play_cue(160.0, 0.22)
			_show_callout("MECO — MAIN ENGINE CUTOFF")
			_set_headline("MECO", UI_ACCENT)
			if status_label:
				if booster_recoverable:
					status_label.text = "MECO at %.0f km, %.0f m/s — first stage holds %.1f t of propellant in reserve for its ride home. Engine cutoff, preparing separation." % [
						altitude_km, velocity_ms, booster_reserve_kg / 1000.0]
				else:
					status_label.text = "First stage propellant exhausted at %.0f km, %.0f m/s. Engine cutoff — preparing separation." % [
						altitude_km, velocity_ms]
			if stage_number == 1:
				_set_rocket_model_parts_visible([
					"S1_Body", "S1_Band", "EngMount", "Interstage", "Stripe",
					"GFin0", "GFin90", "GFin180", "GFin270",
					"Leg45", "Leg135", "Leg225", "Leg315",
					"Noz0", "Noz1", "Noz2", "Noz3", "Noz4", "Noz5", "Noz6", "Noz7", "Noz8"], false)
				_spawn_stage_separation()
				get_tree().create_timer(2.6).timeout.connect(func():
					if state == LaunchState.STAGE_SEP:
						_ignite_second_stage()
						_set_state(LaunchState.FAIRING_SEP))
			else:
				_set_state(LaunchState.ORBITAL_INSERT)

		LaunchState.FAIRING_SEP:
			throttle = 100.0
			insertion_phase = InsertionPhase.RAISE_APOAPSIS
			_play_cue(420.0, 0.14)
			_show_callout("SECOND STAGE BURN — RAISING APOAPSIS")
			_set_headline("STAGE 2 BURN", UI_ACCENT)
			if status_label:
				status_label.text = "Vacuum engine lit. Building the horizontal velocity an orbit is actually made of."

		LaunchState.ORBITAL_INSERT:
			_set_camera(CamMode.SPACE)
			if insertion_phase == InsertionPhase.RAISE_APOAPSIS:
				insertion_phase = InsertionPhase.COAST_TO_APOGEE
				coast_timer = 0.0
				throttle = 0.0
				_set_engine_fx(false)
				_show_callout("APOAPSIS REACHED — COASTING")
				_set_headline("ORBITAL COAST", UI_ACCENT)
				if status_label:
					status_label.text = "Engine cutoff at %.0f km apogee. Coasting to the far side of the orbit for the circularisation burn." % apoapsis_km
			elif insertion_phase == InsertionPhase.COAST_TO_APOGEE:
				insertion_phase = InsertionPhase.CIRCULARISE
				throttle = 100.0
				_set_engine_fx(true)
				_play_cue(500.0, 0.18)
				_show_callout("ORBITAL INSERTION BURN")
				_set_headline("INSERTION BURN", UI_GREEN)
				if status_label:
					status_label.text = "Prograde burn at apogee — raising perigee to %.0f km." % target_orbit_km
			elif insertion_phase == InsertionPhase.CIRCULARISE:
				_finish_orbit_insertion()

		LaunchState.SATELLITE_DEPLOY:
			throttle = 0.0
			_set_engine_fx(false)
			_set_camera(CamMode.SPACE)
			# The separation reveal is a beat the player should actually see. Drop
			# the clock back to real time so a coast skipped at high warp does not
			# also flash the fairing reveal past in a fraction of a second.
			_set_warp_idx(0)
			_set_speed_idx(0)
			_begin_payload_deployment()
			_play_cue(980.0, 0.16)
			var lunar_flight := String(GameManager.current_mission.get("id", "")) == "moon_scout"
			if lunar_flight:
				_show_callout("PAYLOAD SEPARATION — LUNAR STACK RELEASED")
				if status_label: status_label.text = "Stack released — propulsion module and Vikram clear of the upper stage."
			elif mars_payload:
				_show_callout("PAYLOAD SEPARATION — MARS CLIMATE LANDER RELEASED")
				if status_label: status_label.text = "Climate lander clear — trans-Mars injection sequencing."
			else:
				_show_callout("PAYLOAD SEPARATION — SATELLITE RELEASED")
				if status_label:
					status_label.text = "%s released into %.0f km, %.1f° inclination." % [
						GameManager.current_mission.get("name", "Satellite"), target_orbit_km, target_inclination_deg]
			_set_headline("SEPARATION ✓", UI_GREEN)

		LaunchState.COMPLETE:
			# Success is not "reached 100 km".  The mission closes only here: orbit
			# achieved, payload released, and the payload now doing the job it was
			# launched for.  Every number quoted is one the flight actually produced,
			# which is what makes it read as a mission report rather than a stock
			# congratulation.
			_set_headline("MISSION COMPLETE ✓", UI_GREEN)
			_play_cue(1320.0, 0.18)
			if mars_payload:
				_show_callout("TRANS-MARS INJECTION — CLIMATE LANDER DEPARTING EARTH", 5.0)
				if status_label:
					status_label.text = "Lander on its departure trajectory. %.0f km flown, %.0f km downrange from the pad." % [
						path_distance_km, downrange_km]
			else:
				_show_callout("SATELLITE OPERATIONAL — CLIMATE OBSERVATION BEGINS", 5.0)
				if status_label:
					var recovery_line: String = ""
					if booster_landed and not booster_crashed:
						# The first stage is part of the mission report now, because
						# coming home is a thing the vehicle did, not a courtesy.
						recovery_line = " First stage recovered on its deck at T+%0.0f s, touchdown %.1f m/s, %.1f t of propellant to spare." % [
							booster_touchdown_met_s, booster_touchdown_speed_ms, booster_prop_kg / 1000.0]
					elif booster_crashed:
						recovery_line = " First stage lost on return: hard impact at %.0f m/s after its propellant ran out." % [
							booster_touchdown_speed_ms]
					status_label.text = "Orbit held at %.0f km, %.0f m/s, period %.1f min. %.0f km flown from the pad to get here. Instruments powering up.%s" % [
						altitude_km, velocity_ms, orbit_period_min, path_distance_km, recovery_line]
			# Fade through black so the operational camera is a continuation of the
			# launch shot, not an abrupt new scene.  But the film is not over while
			# the first stage is still coming home on its honest clock: the handover
			# waits for the deck, and the player's warp is the only way to shorten
			# the wait.
			get_tree().create_timer(6.5).timeout.connect(func():
				if booster_recoverable and booster_sep_met >= 0.0 and not booster_landed:
					_show_callout("PAYLOAD IN ORBIT — WAITING ON THE FIRST STAGE'S RETURN", 4.0)
					_wait_booster_before_handoff()
				else:
					GameManager.go_to_post_launch_destination())

## Polls once a second until the return has resolved itself, so the scene never
## cuts away mid-descent now that the descent really takes its own minutes.
func _wait_booster_before_handoff() -> void:
	if booster_landed or not is_inside_tree():
		if is_inside_tree():
			GameManager.go_to_post_launch_destination()
		return
	get_tree().create_timer(1.0).timeout.connect(_wait_booster_before_handoff)

## Big centred headline.  It always carries the mission clock so the player can
## see how far into the flight they are, instead of a stale word stuck on screen.
func _set_headline(text: String, color: Color) -> void:
	if countdown_label:
		countdown_label.text = text
		countdown_label.add_theme_color_override("font_color", color)

# ─── Countdown ────────────────────────────────────────────────────────────────
func _update_countdown(delta: float) -> void:
	countdown_timer -= delta
	_update_pad_camera_idle(delta)   # keep orbiting camera
	var t: int = ceili(countdown_timer)
	if countdown_timer > 0.0:
		if t != last_countdown_second:
			last_countdown_second = t
			_play_cue(520.0 if t > 3 else 760.0, 0.07)
			_show_callout("T−%d — ALL SYSTEMS GO" % t, 0.72)
		if countdown_label:
			countdown_label.text = "T-%d" % t
			var col := Color(1.0, 0.85, 0.0, 1.0) if t > 3 else Color(1.0, 0.15, 0.1, 1.0)
			countdown_label.add_theme_color_override("font_color", col)
		# Ignition pre-fire at T-3, and the hold-downs release on the same beat:
		# the strongback swings back and the clamp arms drop away while the vehicle
		# is still framed on the pad camera, so the player sees it come unbound.
		if countdown_timer <= 3.0:
			_begin_holddown_release()
			if exhaust_particles and not exhaust_particles.emitting:
				_set_engine_fx(true) # pre-ignition flame and lingering exhaust
	else:
		_set_state(LaunchState.LIFTOFF)

# ─── Ascent ───────────────────────────────────────────────────────────────────
# A real launch vehicle is *guided*, not tilted on a slider.  The flight-computer
# commands a flight-path angle, the gimbals slew the nose toward it at a limited
# rate, thrust is applied along the nose, and the velocity vector follows a
# beat behind.  That is why the model always points where it is actually going.
func _update_ascent(dt: float) -> void:
	# The first stage no longer burns to dry: what sits above the reserve line at
	# MECO is the returning stage's flight budget, spent later by _booster_physics.
	var prop_floor_kg: float = _prop_floor_kg()
	var burning: bool = propellant_left_kg > prop_floor_kg and throttle > 0.0

	# ── Atmosphere and dynamic pressure ──
	var air_density: float = air_density_sl * exp(-maxf(altitude_km, 0.0) / scale_height_km)
	var speed_ms: float = sqrt(vertical_velocity_ms * vertical_velocity_ms + horizontal_velocity_ms * horizontal_velocity_ms)
	dynamic_pressure_kpa = 0.5 * air_density * speed_ms * speed_ms / 1000.0
	gravity = surface_gravity * pow(body_radius_km / (body_radius_km + maxf(altitude_km, 0.0)), 2.0)

	# ── Throttle programme ──
	# Two real flight-rules, in order: throttle down through the region of peak
	# aerodynamic load, and throttle down again near burnout so the vehicle never
	# exceeds its structural acceleration limit.  Without the second rule a
	# Falcon-class first stage reads out over 5 g at MECO, which no crewed or
	# satellite stack is flown at.
	if auto_throttle and burning:
		# The bucket is a *region*, not a spike: a real vehicle stays at about
		# 72% for the whole transonic stretch, which is several kilometres of
		# flight and a visible, quotable engine event.
		var load_limited: bool = altitude_km < 45.0 and altitude_km > 6.0 \
			and dynamic_pressure_kpa > 12.0
		var max_throttle_pct: float = (MAX_AXIAL_G * surface_gravity * rocket_mass) \
			/ (thrust_kN * 1000.0) * 100.0
		if load_limited:
			throttle = minf(72.0, max_throttle_pct)
		else:
			throttle = minf(100.0, max_throttle_pct)
		# Remember the deepest cut actually flown inside the transonic region, so
		# the Max-Q read-out can quote the engines' real setting rather than an
		# assumed full-throttle figure.
		if altitude_km < 45.0 and throttle < max_q_throttle_pct:
			max_q_throttle_pct = throttle

	# ── Guidance command + limited slew rate ──
	var commanded_deg: float = _guidance_path_angle_deg()
	attitude_deg = move_toward(attitude_deg, commanded_deg, pitch_rate_limit_dps * dt)
	gravity_turn_deg = 90.0 - attitude_deg
	var pitch_rad: float = deg_to_rad(attitude_deg)

	var thrust_N: float = thrust_kN * 1000.0 * (throttle / 100.0)
	var thrust_accel: float = (thrust_N / rocket_mass) if burning else 0.0
	if burning:
		var fuel_flow: float = thrust_N / (isp * surface_gravity)   # kg/s
		propellant_left_kg = maxf(prop_floor_kg, propellant_left_kg - fuel_flow * dt)
		rocket_mass = inert_mass_kg + propellant_left_kg
		fuel_pct = (propellant_left_kg / propellant_total_kg) * 100.0

	# Drag opposes the velocity vector, not the vertical axis.
	var drag_force: float = 0.5 * air_density * speed_ms * speed_ms * DRAG_COEFFICIENT * REFERENCE_AREA_M2
	var drag_ax: float = 0.0
	var drag_ay: float = 0.0
	if speed_ms > 1.0:
		drag_ax = -drag_force / rocket_mass * (horizontal_velocity_ms / speed_ms)
		drag_ay = -drag_force / rocket_mass * (vertical_velocity_ms / speed_ms)

	# Attitude is measured from the local horizon, so 90° is straight up: the
	# thrust component along +Y (up) is sin(att) and the one along +X (downrange)
	# is cos(att).  The mesh's nose maps to exactly this same pair of components,
	# which is what guarantees the model always points where it is accelerating.
	#
	# The two curvature terms are what make this an orbital simulation rather
	# than a ballistics table.  The local vertical rotates as the vehicle travels
	# downrange, so the "up" axis is an accelerating frame: +v_tangential²/r is
	# the centrifugal term that lets a coasting vehicle stay up, and −2·v_r·v_t/r
	# is the Coriolis term that bends a climbing trajectory back over.  Without
	# them a coasting rocket would read 9.4 m/s of pure vertical decay and fall
	# out of the sky instead of sweeping an ellipse out to its apogee.
	var radius_m: float = (body_radius_km + maxf(altitude_km, 0.0)) * 1000.0
	var centrifugal: float = horizontal_velocity_ms * horizontal_velocity_ms / radius_m
	var coriolis: float = 2.0 * vertical_velocity_ms * horizontal_velocity_ms / radius_m
	var ax: float = thrust_accel * cos(pitch_rad) + drag_ax - coriolis
	var ay: float = thrust_accel * sin(pitch_rad) + drag_ay - gravity + centrifugal

	# One integrator for both powered and coasting flight: with the engine off,
	# thrust_accel is zero and the same equations trace the ellipse.  Splitting
	# the coast into a simplified "gravity only" branch is what makes a launch
	# simulation lose the plot, because it silently drops the curvature terms
	# that let a vehicle above the atmosphere keep its altitude.
	horizontal_velocity_ms = maxf(0.0, horizontal_velocity_ms + ax * dt)
	vertical_velocity_ms += ay * dt

	altitude_km = maxf(0.0, altitude_km + vertical_velocity_ms * dt / 1000.0)
	downrange_km += horizontal_velocity_ms * dt / 1000.0
	velocity_ms = sqrt(vertical_velocity_ms * vertical_velocity_ms + horizontal_velocity_ms * horizontal_velocity_ms)
	# Arc length actually flown.  This is a third, independent number: altitude is
	# height above the surface, downrange is distance along it, and this is the
	# length of the path itself — which is what a range safety officer quotes.
	path_distance_km += velocity_ms * dt / 1000.0
	# What the astronauts actually feel is the thrust acceleration, not gravity.
	axial_g = (thrust_accel / surface_gravity) if burning else 0.0

	_update_orbit_estimate()
	_launch_events()

	if not auto_throttle:
		if Input.is_action_pressed("throttle_up"):
			throttle = minf(100.0, throttle + 50.0 * dt)
		if Input.is_action_pressed("throttle_down"):
			throttle = maxf(0.0, throttle - 50.0 * dt)

## Camera work runs once per rendered frame, never per physics slice: a lerped
## camera smoothed 200 times inside one frame would snap rigidly to the vehicle
## instead of drifting cinematically behind it.
func _update_ascent_cameras(delta: float) -> void:
	_position_vehicle()
	if cam_shake > 0.0:
		cam_shake = maxf(0.0, cam_shake - delta * 0.12)
	_update_engine_camera()

## The pitch programme.  A real vehicle climbs away from the pad vertically to
## clear the tower, stays steep while the air is thick, and only then lays over.
## The turn is spread across the whole 3→130 km range so it reads as a graceful
## gravity turn instead of the old instant sideways snap.
func _guidance_path_angle_deg() -> float:
	match insertion_phase:
		InsertionPhase.CIRCULARISE:
			# Prograde at apogee: burning along the velocity vector there raises
			# the opposite side of the orbit, i.e. circularises the perigee.
			return 0.0
		InsertionPhase.COAST_TO_APOGEE:
			# Engine off: the nose simply rides the velocity vector, which is the
			# only attitude that keeps a coasting vehicle pointed where it goes.
			return rad_to_deg(atan2(vertical_velocity_ms, maxf(horizontal_velocity_ms, 400.0)))
		InsertionPhase.RAISE_APOAPSIS:
			# Guided terminal ascent: aim the velocity vector at the insertion
			# point.  Vertical speed is bled off as the target altitude nears, so
			# the vehicle arrives horizontal instead of stalling upward.
			var vv_need: float = clampf((target_orbit_km - altitude_km) * 3.4, 0.0, 1500.0)
			var vh: float = maxf(horizontal_velocity_ms, 120.0)
			return rad_to_deg(atan2(vv_need, vh))
		_:
			pass
	var a: float = altitude_km
	if a < 2.0:
		return 90.0                                  # pitch and roll programme
	elif a < 12.0:
		return math_lerp(90.0, 82.0, (a - 2.0) / 10.0)
	elif a < 30.0:
		return math_lerp(82.0, 62.0, (a - 12.0) / 18.0)
	elif a < 60.0:
		return math_lerp(62.0, 32.0, (a - 30.0) / 30.0)
	elif a < 90.0:
		return math_lerp(32.0, 12.0, (a - 60.0) / 30.0)
	else:
		return math_lerp(12.0, 2.0, (a - 90.0) / 40.0)

func math_lerp(from: float, to: float, w: float) -> float:
	return from + (to - from) * clampf(w, 0.0, 1.0)

## The propellant that must stay in the tanks: for a recoverable first stage it
## is the return budget the booster's own integrator spends on the way home;
## everything else — upper stages, expendable vehicles — burns down to empty.
func _prop_floor_kg() -> float:
	return booster_reserve_kg if (booster_recoverable and stage_number == 1) else 0.0

## Event triggers driven by the *physics*, not by arbitrary altitude gates, so a
## phase label can never disagree with what the vehicle is doing.
func _launch_events() -> void:
	# Weather and atmospheric layers first: these are the events the player sees
	# out of the window, and they have to be spoken before anything else on the
	# list can overwrite the callout.
	_atmosphere_events()
	# Max-Q is the peak of dynamic pressure.  We track the running maximum and
	# declare it once the load starts falling while still inside the thick air.
	if state == LaunchState.LIFTOFF or state == LaunchState.COUNTDOWN:
		if altitude_km < 45.0:
			if dynamic_pressure_kpa > max_q_kpa:
				max_q_kpa = dynamic_pressure_kpa
			elif max_q_kpa > 20.0 and dynamic_pressure_kpa < max_q_kpa * 0.93:
				_set_state(LaunchState.MAX_Q)
			elif altitude_km > 20.0:
				_set_state(LaunchState.MAX_Q)
		elif altitude_km > 25.0:
			# Small launchers never build a sharp pressure peak; do not strand
			# the sequence waiting for one.
			_set_state(LaunchState.MAX_Q)
	elif state == LaunchState.MAX_Q and altitude_km < 45.0:
		if dynamic_pressure_kpa > max_q_kpa:
			max_q_kpa = dynamic_pressure_kpa

	# Max-Q is an *instant*, not a two-minute phase.  Leaving the headline frozen
	# on it for the rest of the first-stage burn is precisely the telemetry lag the
	# player notices: the vehicle is doing something new and the screen is still
	# talking about something that ended forty seconds ago.
	if state == LaunchState.MAX_Q and not superq_beat_done and altitude_km > 32.0:
		superq_beat_done = true
		_set_headline("STAGE 1 BURN", UI_ACCENT)
		_play_cue(540.0, 0.10)
		_show_callout("CLEAR OF THE THICK AIR — BUILDING ORBITAL SPEED", 3.0)
		if status_label:
			status_label.text = "First stage still burning. Now the job is sideways speed: %.0f m/s at %.0f km, apogee climbing toward %.0f km." % [
				velocity_ms, altitude_km, apoapsis_km]

	if propellant_left_kg <= _prop_floor_kg() and stage_number == 1 and not meco_done:
		meco_done = true
		throttle = 0.0
		_set_state(LaunchState.STAGE_SEP)

	if not fairing_jettisoned and altitude_km > 110.0:
		fairing_jettisoned = true
		# The fairing is dead weight above the atmosphere; dropping it is a real
		# mass change, so the inert mass goes down with it.
		inert_mass_kg = maxf(0.0, inert_mass_kg - fairing_mass_kg)
		rocket_mass = inert_mass_kg + propellant_left_kg
		_spawn_fairing_separation()
		_play_cue(840.0, 0.12)
		_show_callout("FAIRING JETTISON — PAYLOAD EXPOSED")

	if altitude_km > SPACE_ALTITUDE_KM and not in_space_frame:
		_enter_space_frame()

	# Insertion sequencing.  The engine is cut once the *apogee* has been lifted
	# to the mission altitude, which is what a real upper stage does: no vehicle
	# climbs all the way to 550 km under power, it burns to an apogee, coasts up
	# to it, and circularises there.
	if insertion_phase == InsertionPhase.RAISE_APOAPSIS:
		if apoapsis_km >= target_orbit_km and altitude_km > 130.0:
			_set_state(LaunchState.ORBITAL_INSERT)
		elif propellant_left_kg <= 0.0:
			# Out of propellant short of the target: coast to whatever apogee we
			# managed and circularise there rather than stalling the sequence.
			target_orbit_km = minf(target_orbit_km, maxf(180.0, apoapsis_km))
			_set_state(LaunchState.ORBITAL_INSERT)

## Maps true altitude to the scene's visual height.  Monotonic and bounded, but
## weighted toward the early climb so the vehicle pulls away from the launch
## complex at the rate an observer would actually expect.
func _ascent_visual_y(alt_km: float) -> float:
	return LAUNCH_PAD_Y + ASCENT_VISUAL_RISE \
		* pow(clampf(alt_km / ASCENT_VISUAL_KM_FULL, 0.0, 1.0), ASCENT_VISUAL_EXP)

## Places the vehicle: a saturating climb while it is still in the air, then an
## orbital arc around the space-frame Earth once it is above the atmosphere.
func _position_vehicle() -> void:
	if rocket == null:
		return
	if in_space_frame:
		# The vehicle rides a circular arc of the space-frame planet. Its nose is
		# the local vertical rotated toward prograde by (90° - attitude), so at a
		# 0° flight-path angle it lies exactly along the direction of orbital
		# travel — which is what a circularised satellite actually does.
		var local := Vector3(0.0, ORBIT_EARTH_RADIUS_VIS + ORBIT_ALTITUDE_VIS, 0.0)
		local = local.rotated(Vector3.RIGHT, orbit_angle)
		rocket.global_position = space_center + local
		rocket.rotation = Vector3(orbit_angle + deg_to_rad(90.0 - attitude_deg), 0.0, 0.0)
	else:
		rocket.position.y = _ascent_visual_y(altitude_km)
		rocket.position.x = downrange_km * 0.12
		rocket.rotation = Vector3(0.0, 0.0, deg_to_rad(attitude_deg - 90.0))
	# Past the tower the flat plane is replaced by the curved planetary shell.
	# These swaps only ever *remove* authored geometry.  Ground, LaunchPad and
	# PadArm are authored invisible in the scene — they are the old placeholders
	# the code-built spaceport replaced — so switching them back on here would
	# put a bare slab in the middle of a shot that is already correct.
	# Applied every frame rather than on the edge: the 4000-unit sea plane inside
	# GroundDetail is far larger than the planetary shell's silhouette, so a
	# single missed transition left a lit tan wedge poking out past the limb for
	# the rest of the ascent.
	var want_horizon: bool = altitude_km > HORIZON_TAKEOVER_KM and not in_space_frame
	horizon_active = want_horizon
	if horizon_world:
		horizon_world.visible = want_horizon
	var detail := get_node_or_null("GroundDetail") as Node3D
	if detail and not pad_hidden_for_orbit:
		detail.visible = not want_horizon
	var gnd := get_node_or_null("Ground") as Node3D
	if gnd:
		gnd.visible = false
	# The authored spaceport only reads from pad level.  A few kilometres up its
	# slab fills the frame as a floating tan wedge sitting on top of the planet,
	# which is the single most obvious "model railway" tell in the whole ascent.
	# Rather than popping it out of existence mid-shot, it shrinks away beneath
	# the vehicle — which is precisely what the real thing looks like.
	var pad_scale: float = clampf(1.0 - (altitude_km - 2.0) / 7.0, 0.0, 1.0)
	pad_shrink = pad_scale
	var complex := get_node_or_null("LaunchComplex") as Node3D
	if complex:
		complex.visible = pad_scale > 0.015 and not in_space_frame
		if pad_scale > 0.015:
			complex.scale = Vector3.ONE * maxf(pad_scale, 0.02)
	# The weather belongs to the atmosphere.  Once the vehicle is orbiting it must
	# not be left hanging outside the window as a set of glowing bubbles, and the
	# Kármán shell stays a little longer than the decks so the player can see the
	# line they have just put behind them.
	if atmo_world:
		atmo_world.visible = not in_space_frame
	if karman_shell:
		karman_shell.visible = not in_space_frame and altitude_km < SPACE_ALTITUDE_KM + 25.0
	if dust_particles and altitude_km > 1.4:
		dust_particles.emitting = false
	if smoke_particles and altitude_km > 2.0:
		smoke_particles.emitting = false

# ─── Chase Camera ─────────────────────────────────────────────────────────────
func _update_chase_camera(visual_y: float) -> void:
	if not cam_chase or not rocket: return
	if in_space_frame:
		# "Tracking" in orbit must read like the orbital shot, not a downward look
		# onto the planet. Parking the camera high on the radial vector (radial*34)
		# and looking down framed the huge blue Earth across the whole screen — a
		# flat sky-blue wash with no horizon. Instead ride AHEAD along the track and
		# barely above the vehicle, looking forward along the local tangent with up
		# set to the local radial, so the limb sinks to the bottom edge and black
		# space fills the frame. Also track the released payload once it exists, not
		# the hidden rocket node, or the shot drifts off the empty spot it left.
		var focus_node: Node3D = rocket
		if payload_craft and is_instance_valid(payload_craft) and payload_craft.visible:
			focus_node = payload_craft
		var radial := (focus_node.global_position - space_center).normalized()
		var fwd := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, orbit_angle)
		var want := focus_node.global_position + fwd * 10.0 + radial * 2.5
		cam_chase.global_position = cam_chase.global_position.lerp(want, 0.07)
		cam_chase.look_at(focus_node.global_position + fwd * 1.5 + radial * 0.8, radial)
		return
	# Distance scales with how far the vehicle has actually travelled up the
	# frame, not with raw altitude — the scene's height curve is deliberately
	# non-linear, and keying the camera to true kilometres would leave it
	# level with the horizon while the vehicle is already hundreds of units up.
	# The camera also climbs *above* the vehicle and pitches down as the rocket
	# gains height, so the planet's surface and its limb occupy the frame.  A
	# level camera at these altitudes only ever films the sky, which is why the
	# old framing read as a model floating in a tan void.
	var alt_norm: float = clampf((_ascent_visual_y(altitude_km) - LAUNCH_PAD_Y) / 300.0, 0.0, 1.0)
	var side: float  = lerp(12.0, 32.0, alt_norm)
	var up: float    = lerp(4.0,  46.0, alt_norm)
	var back: float  = lerp(18.0, 56.0, alt_norm)
	var look_drop: float = lerp(3.0, 8.0, alt_norm)

	var target_pos  := rocket.position + Vector3(side, up, back)
	var look_target := rocket.position - Vector3(0.0, look_drop, 0.0)

	# Camera shake on liftoff
	if cam_shake > 0.0:
		target_pos += Vector3(
			randf_range(-cam_shake * 0.3, cam_shake * 0.3),
			randf_range(-cam_shake * 0.1, cam_shake * 0.1),
			randf_range(-cam_shake * 0.3, cam_shake * 0.3))

	# Smooth but tight follow
	cam_chase.position = cam_chase.position.lerp(target_pos, 0.12)
	cam_chase.look_at(look_target, Vector3.UP)

func _update_engine_camera() -> void:
	if not cam_engine or not rocket: return
	# A brief low tracking shot holds through initial liftoff, then the chase
	# camera takes over for ascent. This avoids one static all-purpose camera.
	var engine_target := rocket.position + Vector3(0.0, -3.5, 0.0)
	var desired := rocket.position + Vector3(8.0, 2.5, 17.0)
	cam_engine.position = cam_engine.position.lerp(desired, 0.1)
	cam_engine.look_at(engine_target, Vector3.UP)

func _update_orbit_estimate() -> void:
	# Classical two-body estimate from altitude and the integrated velocity
	# vector. Negative periapsis means the current trajectory still intersects
	# the launch planet and requires more horizontal velocity.
	var radius_km: float = body_radius_km + maxf(altitude_km, 0.0)
	var speed_km_s: float = velocity_ms / 1000.0
	if radius_km <= 0.0 or speed_km_s <= 0.01:
		apoapsis_km = altitude_km
		periapsis_km = -body_radius_km
		return
	var specific_energy: float = speed_km_s * speed_km_s * 0.5 - body_mu / radius_km
	var angular_momentum: float = radius_km * (horizontal_velocity_ms / 1000.0)
	var eccentricity_sq: float = 1.0 + (2.0 * specific_energy * angular_momentum * angular_momentum) / (body_mu * body_mu)
	var eccentricity: float = sqrt(maxf(0.0, eccentricity_sq))
	if specific_energy >= 0.0:
		apoapsis_km = 99999.0
		periapsis_km = maxf(-body_radius_km, angular_momentum * angular_momentum / (body_mu * maxf(1.0 + eccentricity, 0.001)) - body_radius_km)
		return
	var semi_major_axis: float = -body_mu / (2.0 * specific_energy)
	apoapsis_km = semi_major_axis * (1.0 + eccentricity) - body_radius_km
	periapsis_km = semi_major_axis * (1.0 - eccentricity) - body_radius_km

func _spawn_stage_separation() -> void:
	if not rocket: return
	# The flying vehicle keeps its streamlined upper-stage silhouette while the
	# spent first stage leaves it.  On a recoverable launcher that stage is a
	# second *guided* vehicle with four more burns to fly, so it gets its own node,
	# its own profile and its own camera.  On an expendable one it is just debris,
	# and the narration says that instead of pretending.
	var nose: Vector3 = rocket.global_transform.basis.y
	var aft: Vector3 = -nose
	var spawn_pos := rocket.global_position + aft * 4.8
	var spawn_rot := rocket.global_rotation
	booster_sep_met = met_seconds
	booster_sep_alt_km = maxf(altitude_km, 1.0)
	booster_sep_spd_ms = maxf(velocity_ms, 1.0)
	booster_nose_dir = nose.normalized()
	booster_elapsed_s = 0.0
	booster_held_at_gate = false
	if not booster_recoverable:
		var junk := Node3D.new()
		junk.name = "DiscardedStage"
		var junk_body := MeshInstance3D.new()
		var junk_mesh := CylinderMesh.new()
		junk_mesh.top_radius = 0.63
		junk_mesh.bottom_radius = 0.76
		junk_mesh.height = 8.8
		junk_body.mesh = junk_mesh
		var junk_mat := StandardMaterial3D.new()
		junk_mat.albedo_color = Color(0.48, 0.48, 0.5, 1.0)
		junk_mat.metallic = 0.65
		junk_mat.roughness = 0.35
		junk_body.material_override = junk_mat
		junk.add_child(junk_body)
		add_child(junk)
		junk.global_position = spawn_pos
		junk.global_rotation = spawn_rot
		stage_debris.append({
			"node": junk,
			"velocity": aft * 14.0 + Vector3(-4.0, 0.0, 3.0),
			"spin": Vector3(0.5, 0.8, -0.35),
			"life": 0.0})
		return
	# Hand the spent stage its full physical state: where it is over the curved
	# Earth, how fast it is going in the vertical plane, and — the part that used
	# to be thrown away — the propellant still standing in its tanks.  That fuel
	# is the entire budget for the flight home; when it runs out the stage stops
	# being a rocket and becomes a 100-tonne stone.
	booster_x_km = downrange_km
	booster_vx_ms = horizontal_velocity_ms
	booster_vy_ms = vertical_velocity_ms
	booster_prop_kg = propellant_left_kg
	booster_prop_start_kg = propellant_left_kg
	booster_dry_kg = stage_1_dry_mass_kg + BOOSTER_HARDWARE_KG
	booster_mass_kg = booster_dry_kg + booster_prop_kg
	booster_alt_km = altitude_km
	booster_fins_out = false
	booster_gear_out = false
	booster_legs_anim = 0.0
	booster_at_interface = false
	booster_interface_s = 0.0
	booster_entry_start_s = 0.0
	# The interface is the height where the air is thick enough to steer and
	# slow in.  If separation already happened below the nominal line, the
	# stage is effectively at interface the moment it starts falling back.
	booster_interface_km = minf(BOOSTER_ENTRY_INTERFACE_KM, maxf(altitude_km - 2.0, 20.0))
	booster_crashed = false
	booster_touchdown_speed_ms = 0.0
	booster_peak_entry_g = 0.0
	booster_engine_kN = thrust_kN
	booster_prop_t = booster_prop_kg / 1000.0
	booster_spd_ms = velocity_ms
	booster_node = _build_returning_booster()
	add_child(booster_node)
	booster_node.global_position = spawn_pos
	booster_node.global_rotation = spawn_rot
	booster_node.visible = true
	_build_recovery_rig()

## The returning first stage, built as a vehicle rather than as a discarded
## cylinder.  Grid fins, four folding legs and a relightable engine skirt are the
## three things an audience reads a recovery by, so they have to exist and they
## have to move on cue.
func _build_returning_booster() -> Node3D:
	var b := Node3D.new()
	b.name = "ReturningBooster"
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.42, 0.41, 0.40)
	soot.metallic = 0.42
	soot.roughness = 0.78
	var clean := StandardMaterial3D.new()
	clean.albedo_color = Color(0.84, 0.87, 0.92)
	clean.metallic = 0.22
	clean.roughness = 0.52
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.11)
	dark.metallic = 0.35
	dark.roughness = 0.82
	var bell := StandardMaterial3D.new()
	bell.albedo_color = Color(0.19, 0.20, 0.23)
	bell.metallic = 0.90
	bell.roughness = 0.36
	# Local frame: the nose of the vehicle is +Y, the engines are at -Y.  This is
	# the same convention the mounted launch model uses, so the stage leaves the
	# stack in the attitude the stack was already flying.
	b.add_child(_pad_cyl(soot, 0.63, 0.76, 8.8, Vector3.ZERO, 22))
	b.add_child(_pad_cyl(clean, 0.78, 0.78, 0.45, Vector3(0.0, 4.6, 0.0), 22))
	b.add_child(_pad_cyl(dark, 0.76, 0.60, 0.95, Vector3(0.0, -5.05, 0.0), 22))
	b.add_child(_pad_cyl(bell, 0.10, 0.17, 0.55, Vector3(0.0, -5.78, 0.0), 14))
	for k in range(8):
		var ring_a := TAU * float(k) / 8.0
		b.add_child(_pad_cyl(bell, 0.085, 0.145, 0.5,
			Vector3(cos(ring_a) * 0.44, -5.72, sin(ring_a) * 0.44), 12))
	for sx in [-1.0, 1.0]:
		var fin := Node3D.new()
		fin.name = "GridFin"
		fin.position = Vector3(sx * 0.62, 3.7, 0.0)
		# Sizes stay positive and only the offsets mirror: a BoxMesh with a
		# negative dimension inside a Vector3 comes out inside-out and vanishes
		# under back-face culling.
		fin.add_child(_pad_box(dark, Vector3(0.92, 0.10, 0.56), Vector3(sx * 0.46, 0.0, 0.0)))
		fin.add_child(_pad_box(clean, Vector3(0.10, 0.14, 0.56), Vector3(sx * 0.86, 0.0, 0.0)))
		b.add_child(fin)
		booster_fins.append(fin)
	for k in range(4):
		var leg_a := TAU * float(k) / 4.0 + PI / 4.0
		var outward := Vector3(cos(leg_a), 0.0, sin(leg_a))
		var pivot := Node3D.new()
		pivot.name = "LandingLeg"
		pivot.position = outward * 0.62 + Vector3(0.0, -4.5, 0.0)
		pivot.add_child(_pad_box(clean, Vector3(0.10, 3.5, 0.13), Vector3(0.0, -1.72, 0.0)))
		pivot.add_child(_pad_box(dark, Vector3(0.36, 0.11, 0.36), Vector3(0.0, -3.44, 0.0)))
		# Stowed: swung up flat against the body, the way it flies for 90 % of the
		# mission.  Deployed by `_update_booster()` on final approach.
		pivot.basis = Basis(outward, deg_to_rad(157.0))
		b.add_child(pivot)
		booster_legs.append(pivot)
	booster_plume = MeshInstance3D.new()
	booster_plume.name = "BoosterPlume"
	var plume_mesh := CylinderMesh.new()
	plume_mesh.top_radius = 0.66
	plume_mesh.bottom_radius = 0.08
	plume_mesh.height = 4.6
	plume_mesh.radial_segments = 16
	plume_mesh.rings = 2
	booster_plume.mesh = plume_mesh
	booster_plume.position = Vector3(0.0, -8.0, 0.0)
	var plume_mat := StandardMaterial3D.new()
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Kept deliberately short of pure white.  An emissive plume bright enough to
	# clip blows out into a featureless disc against the planet, which is both
	# wrong (kerosene exhaust is amber at its edges) and the fastest way to make
	# the shot unreadable.
	plume_mat.albedo_color = Color(1.0, 0.52, 0.18, 0.34)
	plume_mat.emission_enabled = true
	plume_mat.emission = Color(1.0, 0.58, 0.24)
	plume_mat.emission_energy_multiplier = 1.15
	booster_plume.material_override = plume_mat
	booster_plume.visible = false
	b.add_child(booster_plume)
	# A near-white inner core inside the cooler amber cone: kerosene flames are
	# bright at the shock diamonds near the nozzle and only tint orange at their
	# edges, and a single-colour flame reads as a coloured spotlight instead.
	var plume_core2 := MeshInstance3D.new()
	plume_core2.name = "BoosterPlumeCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.30
	core_mesh.bottom_radius = 0.05
	core_mesh.height = 2.4
	core_mesh.radial_segments = 12
	core_mesh.rings = 2
	plume_core2.mesh = core_mesh
	plume_core2.position = Vector3(0.0, -6.6, 0.0)
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	core_mat.albedo_color = Color(1.0, 0.88, 0.66, 0.55)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.85, 0.58)
	core_mat.emission_energy_multiplier = 1.6
	plume_core2.material_override = core_mat
	plume_core2.visible = false
	b.add_child(plume_core2)
	booster_burn_light = OmniLight3D.new()
	booster_burn_light.name = "BoosterBurnGlow"
	booster_burn_light.position = Vector3(0.0, -6.8, 0.0)
	booster_burn_light.light_color = Color(1.0, 0.62, 0.26)
	booster_burn_light.light_energy = 0.0
	booster_burn_light.omni_range = 26.0
	booster_burn_light.shadow_enabled = false
	b.add_child(booster_burn_light)
	return b

func _spawn_fairing_separation() -> void:
	if fairing_separated or not rocket: return
	fairing_separated = true
	var nose := -rocket.global_transform.basis.z
	var right := rocket.global_transform.basis.x
	var nose_pos := rocket.global_position + nose * 8.2
	var nosecone := get_node_or_null("Rocket/Nosecone") as MeshInstance3D
	if nosecone: nosecone.hide()
	_set_rocket_model_parts_visible(["Fairing", "Tip"], false)
	# Two lightweight fairing shells open and fall away on either side of the
	# flight path. They are the heaviest-looking objects in the shot, so they
	# must leave it: real halves tumble earthward and are out of frame in seconds.
	for side in [-1.0, 1.0]:
		var shell := MeshInstance3D.new()
		shell.name = "FairingHalf"
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = 0.78
		shell_mesh.height = 4.6
		shell.mesh = shell_mesh
		shell.scale = Vector3(0.72, 1.0, 0.72)
		var shell_mat := StandardMaterial3D.new()
		shell_mat.albedo_color = Color(0.72, 0.75, 0.8, 1.0)
		shell_mat.metallic = 0.48
		shell_mat.roughness = 0.3
		shell.material_override = shell_mat
		# The node must be in the tree before a global transform can be written
		# to it; outside the tree there is no parent transform to resolve against.
		add_child(shell)
		shell.global_rotation = rocket.global_rotation
		shell.global_position = nose_pos + right * (side * 0.85)
		stage_debris.append({
			"node": shell,
			"velocity": right * (side * 11.0) - nose * 6.0,
			"spin": Vector3(1.4, side * 1.8, 0.8),
			"life": 0.0})

func _ignite_second_stage() -> void:
	stage_number = 2
	# Staging genuinely discards mass: the first stage's dry structure leaves the
	# stack, so the remaining inert mass is the upper stage plus fairing plus
	# payload.  Propellant resets to a *full tank of the new stage*, and the HUD
	# caption changes to say so rather than looking like a refill glitch.
	inert_mass_kg = stage_2_dry_mass_kg + fairing_mass_kg + payload_mass_kg
	propellant_total_kg = stage_2_propellant_kg
	propellant_left_kg = stage_2_propellant_kg
	rocket_mass = inert_mass_kg + propellant_left_kg
	fuel_pct = 100.0
	thrust_kN = stage_2_thrust_kN
	isp = 348.0
	throttle = 100.0
	# The detailed vehicle's upper-stage nozzle is above the separated first
	# stage, so move the exhaust emitter to the real engine position.
	if exhaust_particles: exhaust_particles.position.y = 6.3
	if smoke_particles: smoke_particles.position.y = 6.1
	if engine_light: engine_light.position.y = 6.3
	if plume_core: plume_core.position.y = 2.3
	if plume_outer: plume_outer.position.y = 1.5
	_set_engine_fx(true)
	# A single-engine vacuum burn is visibly weaker and slower than nine engines
	# at sea level; the camera and the audio both need to reflect that change.
	_play_cue(300.0, 0.2)
	_show_callout("SECOND STAGE IGNITION")

func _set_rocket_model_parts_visible(part_names: Array[String], is_visible: bool) -> void:
	var model := get_node_or_null("Rocket/RocketModel")
	if model:
		_set_model_parts_visible_recursive(model, part_names, is_visible)

func _set_model_parts_visible_recursive(parent: Node, part_names: Array[String], is_visible: bool) -> void:
	for child in parent.get_children():
		if child is Node3D and part_names.has(String(child.name)):
			(child as Node3D).visible = is_visible
		_set_model_parts_visible_recursive(child, part_names, is_visible)

## The recovery camera's own atmosphere.  A per-camera Environment override is
## the only way to give the return shot a sky without painting the orbital half
## of the split blue too, because both halves share one World3D.  A flat hazy
## blue background plus exponential depth fog does two jobs at once: it fills
## the black of orbit with atmosphere, and it fades the far side of the planet
## into haze so the eye reads a genuine ground-level horizon instead of a globe
## floating in void.  Sky-derived ambient lifts the terrain out of the night
## side it would otherwise land on.
func _make_recovery_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.40, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.55, 0.32)
	env.fog_density = 0.0060
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_strength = 0.40
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.10
	return env

## Grades the recovery camera's atmosphere by how far down the stage still is.
## The ascent faded a bright blue sky out to black as it climbed; the return has
## to run that fade in reverse or the whole descent sits under a flat pale sheet
## that hides the stage and contradicts the black of orbit it just left.  High up
## it is near-space — deep, dark, almost no fog, so the sunlit stage reads
## against the globe; coming down the haze, the blue and the ambient all swell
## together until the pad is landing in the same air it lifted off in.
func _update_recovery_atmosphere() -> void:
	if recovery_env == null or not is_instance_valid(recovery_env):
		return
	var sky_in: float = 1.0 - clampf(booster_alt_km / 55.0, 0.0, 1.0)
	# Golden hour, not midday: the liftoff was graded to a warm sunset, so the
	# return has to come home into the same low amber light.  High up it is the
	# dark of orbit with a faint dusk purple; descending, a warm gold sky, a
	# strong amber haze off the ground and warm sky-ambient swell together.
	var space_col := Color(0.02, 0.02, 0.05)
	var atmo_col := Color(0.64, 0.42, 0.26)
	recovery_env.background_color = space_col.lerp(atmo_col, sky_in)
	recovery_env.fog_density = lerpf(0.0, 0.0075, sky_in)
	recovery_env.fog_light_color = Color(0.28, 0.22, 0.26).lerp(Color(0.90, 0.56, 0.30), sky_in)
	recovery_env.ambient_light_energy = lerpf(0.26, 0.85, sky_in)

## The landing site for the returning stage: a landing pad on the ground right
## beside the launch tower it lifted off from, plus the touchdown dust.
##
## This is a return to the launch site, not a droneship landing.  The boostback
## burn that opens the whole return only makes sense for an RTLS profile — a
## downrange ship landing never throws away the downrange speed — so the picture
## has to show the stage coming home to the pad it started on.  It lives on the
## space-frame planet because that is the only place in the scene with a curved
## horizon and a sky going out, which is what a stage coming down from 70 km
## actually looks like.
func _build_recovery_rig() -> void:
	recovery_rig = Node3D.new()
	recovery_rig.name = "RecoveryRig"
	add_child(recovery_rig)
	recovery_ship = Node3D.new()
	recovery_ship.name = "LandingSite"
	# The coast the launch site sits on.  A real spaceport is a barrier island —
	# water on most sides, a point of land under the pad — and that is exactly
	# what turns a flat green disc into a place.  The base cap is the sea: deep
	# blue with just enough specular for the low sun to throw a gold path across
	# it.  On top of it a cluster of flattened land discs forms an irregular
	# headland, ringed by a broken sand beach, so the booster comes down onto a
	# coastline rather than a colour swatch.
	var ground_r: float = ORBIT_EARTH_RADIUS_VIS + RECOVERY_DECK_VIS
	var sea := MeshInstance3D.new()
	sea.name = "SeaCap"
	var sea_sphere := SphereMesh.new()
	sea_sphere.radius = ground_r
	sea_sphere.height = ground_r * (2.0 - 2.0 * cos(deg_to_rad(62.0)))
	sea_sphere.rings = 28
	sea_sphere.radial_segments = 112
	sea.mesh = sea_sphere
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.03, 0.11, 0.24)
	sea_mat.roughness = 0.14
	sea_mat.metallic = 0.25
	sea_mat.metallic_specular = 0.7
	sea.material_override = sea_mat
	sea.position = Vector3(0.0, -ground_r, 0.0)
	recovery_ship.add_child(sea)
	# The headland: overlapping low land discs of varied earth tone, centred
	# under the pad and reaching out toward the water.
	var land_tones := [
		Color(0.22, 0.24, 0.13), Color(0.26, 0.27, 0.15), Color(0.19, 0.22, 0.12),
		Color(0.24, 0.23, 0.16),
	]
	var headland := [
		Vector3(0.0, 0.0, 0.0), Vector3(-4.0, 0.0, 2.0), Vector3(3.0, 0.0, -3.0),
		Vector3(-2.0, 0.0, -4.0), Vector3(4.0, 0.0, 3.0), Vector3(-5.0, 0.0, -1.0),
	]
	for i in headland.size():
		var lm := StandardMaterial3D.new()
		lm.albedo_color = land_tones[i % land_tones.size()]
		lm.roughness = 0.98
		lm.metallic = 0.0
		lm.metallic_specular = 0.0
		recovery_ship.add_child(_pad_cyl(lm, randf_range(5.5, 8.0), randf_range(5.8, 8.4),
			0.4, Vector3(headland[i].x, 0.12, headland[i].z), 28))
	# A broken sand ring where the land meets the sea — the coastline.
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.52, 0.44, 0.30)
	sand.roughness = 0.95
	sand.metallic_specular = 0.0
	for a in range(0, 12):
		var ang := TAU * a / 12.0
		recovery_ship.add_child(_pad_cyl(sand, 3.0, 3.2, 0.34,
			Vector3(cos(ang) * 12.5, 0.05, sin(ang) * 12.5), 16))
	# The landing pad: a concrete circle with a painted ring-and-cross marking,
	# exactly what a return-to-launch-site zone carries, sitting right under the
	# descent so the stage visibly touches down on it.
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.42, 0.42, 0.44)
	concrete.roughness = 0.92
	concrete.metallic = 0.05
	recovery_ship.add_child(_pad_cyl(concrete, 6.2, 6.4, 0.5, Vector3(0.0, 0.05, 0.0), 40))
	var mark := StandardMaterial3D.new()
	mark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.albedo_color = Color(0.9, 0.9, 0.92)
	recovery_ship.add_child(_pad_box(mark, Vector3(9.0, 0.06, 0.7), Vector3(0.0, 0.33, 0.0)))
	recovery_ship.add_child(_pad_box(mark, Vector3(0.7, 0.06, 9.0), Vector3(0.0, 0.33, 0.0)))
	var scorch := StandardMaterial3D.new()
	scorch.albedo_color = Color(0.06, 0.06, 0.07)
	scorch.roughness = 1.0
	recovery_ship.add_child(_pad_cyl(scorch, 1.5, 1.7, 0.08, Vector3(0.0, 0.34, 0.0), 20))
	# The launch tower it lifted off from, standing a few metres to one side so
	# the frame reads as *the same place*.  This is the object that turns "a
	# rocket landed somewhere" into "the rocket came back to its own pad".
	# A single mast reads as set dressing; a real strongback is a lattice — four
	# corner legs laced together with horizontal girts and diagonal braces every
	# few metres, a cab and service arms up top, red/white aviation paint at the
	# masthead — and it is that density of detail that sells the scale of the
	# stage standing next to it.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.60)
	steel.metallic = 0.7
	steel.roughness = 0.45
	steel.metallic_specular = 0.2
	var tower := Node3D.new()
	tower.name = "LaunchTower"
	tower.position = Vector3(-11.0, 0.0, 1.5)
	recovery_ship.add_child(tower)
	for lx in [-1.1, 1.1]:
		for lz in [-1.1, 1.1]:
			tower.add_child(_pad_box(steel, Vector3(0.42, 18.0, 0.42), Vector3(lx, 9.0, lz)))
	for gy in [2.0, 5.0, 8.0, 11.0, 14.0, 17.0]:
		tower.add_child(_pad_box(steel, Vector3(2.6, 0.22, 0.22), Vector3(0.0, gy, 1.1)))
		tower.add_child(_pad_box(steel, Vector3(2.6, 0.22, 0.22), Vector3(0.0, gy, -1.1)))
		tower.add_child(_pad_box(steel, Vector3(0.22, 0.22, 2.6), Vector3(1.1, gy, 0.0)))
		tower.add_child(_pad_box(steel, Vector3(0.22, 0.22, 2.6), Vector3(-1.1, gy, 0.0)))
	# Diagonal X-bracing on the two faces that point toward the camera's side of
	# the pad.  Without the criss-cross a lattice just reads as a table.
	for by in [2.0, 8.0, 14.0]:
		for side in [-1.0, 1.0]:
			tower.add_child(_pad_box(steel, Vector3(0.16, 3.6, 0.16),
				Vector3(side * 1.1, by + 1.5, 0.0), Vector3(deg_to_rad(45.0), 0.0, 0.0)))
			tower.add_child(_pad_box(steel, Vector3(0.16, 3.6, 0.16),
				Vector3(side * 1.1, by + 1.5, 0.0), Vector3(deg_to_rad(-45.0), 0.0, 0.0)))
	# Masthead cab, service arms that reached the vehicle before flight, and the
	# concrete base the whole structure stands on.
	tower.add_child(_pad_box(steel, Vector3(2.4, 1.4, 2.4), Vector3(0.0, 18.6, 0.0)))
	tower.add_child(_pad_box(steel, Vector3(4.0, 0.42, 0.8), Vector3(3.0, 12.0, 0.0)))
	tower.add_child(_pad_box(steel, Vector3(3.2, 0.36, 0.6), Vector3(2.6, 6.4, 0.0)))
	tower.add_child(_pad_box(steel, Vector3(3.0, 1.1, 3.0), Vector3(0.0, 0.55, 0.0)))
	# Red/white aviation stripes at the masthead, the one paint job that makes a
	# tower read as airfield furniture at any distance.
	var stripe := StandardMaterial3D.new()
	stripe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stripe.albedo_color = Color(0.85, 0.16, 0.12)
	for sy in [15.2, 16.4, 17.6]:
		tower.add_child(_pad_box(stripe, Vector3(2.7, 0.55, 0.5), Vector3(0.0, sy, 1.12)))
	var beacon := StandardMaterial3D.new()
	beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.albedo_color = Color(1.0, 0.2, 0.16)
	beacon.emission_enabled = true
	beacon.emission = Color(1.0, 0.16, 0.12)
	beacon.emission_energy_multiplier = 2.2
	tower.add_child(_pad_box(beacon, Vector3(0.5, 0.5, 0.5), Vector3(0.0, 19.5, 0.0)))
	# The launch mount: the flame-bucket pedestal the stage actually lifted from,
	# sitting on the pad a few metres from the landing target — the exact spot the
	# rocket occupied at T-0, now empty again.
	var mount_mat := StandardMaterial3D.new()
	mount_mat.albedo_color = Color(0.32, 0.32, 0.35)
	mount_mat.roughness = 0.85
	mount_mat.metallic = 0.3
	recovery_ship.add_child(_pad_cyl(mount_mat, 2.3, 2.7, 0.9, Vector3(5.5, 0.6, -0.5), 20))
	# White perimeter ring around the pad edge.
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = 6.5
	ring_mesh.inner_radius = 6.1
	ring_mesh.rings = 60
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.position = Vector3(0.0, 0.34, 0.0)
	ring.material_override = mark
	recovery_ship.add_child(ring)
	# A film light over the site.  The recovery arc can drop the landing into the
	# planet's own night side, which left the terrain and tower unreadable black;
	# a local OmniLight lights only this neighbourhood (not the orbital half of
	# the split).  Set low and to one side in warm amber, it reads as a sun just
	# above the horizon and rakes long shadows across the pad instead of the
	# flat, sourceless wash a lamp directly overhead produced; a dim cool fill
	# from the opposite side keeps the shadow faces from crushing to black.
	var site_light := OmniLight3D.new()
	site_light.name = "SiteLight"
	site_light.light_energy = 1.65
	site_light.light_color = Color(1.0, 0.70, 0.42)
	site_light.omni_range = 60.0
	site_light.shadow_enabled = false
	site_light.position = Vector3(-12.0, 9.0, 9.0)
	recovery_ship.add_child(site_light)
	var site_fill := OmniLight3D.new()
	site_fill.name = "SiteFillLight"
	site_fill.light_energy = 0.5
	site_fill.light_color = Color(0.55, 0.62, 0.85)
	site_fill.omni_range = 55.0
	site_fill.shadow_enabled = false
	site_fill.position = Vector3(11.0, 7.0, -8.0)
	recovery_ship.add_child(site_fill)
	# Drifting cumulus over the site.  The ascent promised weather; the return
	# should pass back through it, which is the missing piece that made the
	# landing read as airless.  Opaque soft puffs rather than transparent
	# sprites — transparency depth-sorts badly inside the split sub-viewport —
	# sitting low and flat just above the ground so they read as a cloud deck
	# over the landscape, shaded so the site light gives them form instead of
	# the flat white plates an unshaded material produced.
	# scattered field rather than six evenly-spaced props.
	site_clouds.clear()
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(0.82, 0.72, 0.64)
	cloud_mat.roughness = 1.0
	cloud_mat.metallic = 0.0
	cloud_mat.metallic_specular = 0.0
	# Kept well above the deck: the recovery camera films from a few metres up,
	# so a cloud at eye level fills the frame as a white wall instead of reading
	# as weather overhead.  Bases at eleven metres and up clear even the closest
	# touchdown framing, so the deck shot keeps the sky to itself.
	var cloud_spots := [
		Vector3(-12.0, 11.4, 6.0), Vector3(9.5, 12.9, -9.0), Vector3(-5.0, 13.2, -12.5),
		Vector3(12.5, 11.1, 3.5), Vector3(-13.5, 12.7, -3.0), Vector3(4.0, 14.6, 11.5),
		Vector3(0.5, 15.4, 8.0), Vector3(-8.0, 13.8, -7.5), Vector3(14.0, 12.6, -2.0),
	]
	for spot in cloud_spots:
		# Each cloud is a cluster of overlapping lobes rather than one clean
		# sphere, so it reads as cumulus with a lumpy outline instead of a
		# floating ellipse.  Grouping them under a Node3D lets the whole cloud
		# drift and wrap as one body instead of shredding apart.
		var cluster := Node3D.new()
		cluster.position = spot
		recovery_ship.add_child(cluster)
		for l in randi_range(6, 9):
			var puff := MeshInstance3D.new()
			var p_mesh := SphereMesh.new()
			p_mesh.radius = 1.0
			p_mesh.height = 2.0
			p_mesh.radial_segments = 10
			p_mesh.rings = 6
			puff.mesh = p_mesh
			puff.scale = Vector3(randf_range(1.1, 2.6), randf_range(0.45, 0.95), randf_range(1.0, 2.2))
			puff.position = Vector3(randf_range(-2.4, 2.4), randf_range(-0.4, 0.55), randf_range(-1.8, 1.8))
			puff.material_override = cloud_mat
			cluster.add_child(puff)
		site_clouds.append(cluster)
	recovery_rig.add_child(recovery_ship)
	recovery_dust = MeshInstance3D.new()
	recovery_dust.name = "TouchdownBlast"
	var dust_mesh := CylinderMesh.new()
	dust_mesh.top_radius = 1.0
	dust_mesh.bottom_radius = 4.2
	dust_mesh.height = 1.2
	dust_mesh.radial_segments = 24
	recovery_dust.mesh = dust_mesh
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Sunset-lit tan rather than cool white: the blast is ground dust and steam
	# caught in golden-hour light, not smoke from the engines.
	dust_mat.albedo_color = Color(0.62, 0.52, 0.38, 0.0)
	recovery_dust.material_override = dust_mat
	recovery_dust.position = Vector3(0.0, 0.7, 0.0)
	recovery_dust.visible = false
	recovery_rig.add_child(recovery_dust)
	recovery_rig.visible = false

## Where the descent is filmed, in the space frame.  The stage's arc position
## comes straight from its physical downrange distance: measured from the pad's
## current arc angle, so the patch of ground under the returning stage really
## is the launch site.  Returns the local vertical, the prograde direction and
## the stage's world position for this frame.
func _booster_frame(alt_km: float, progress: float) -> Dictionary:
	var pad_angle: float = orbit_angle - downrange_km / body_radius_km
	var angle: float = pad_angle + booster_x_km / body_radius_km - progress * 0.02
	var radial := Vector3(0.0, 1.0, 0.0).rotated(Vector3.RIGHT, angle)
	var prograde := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, angle)
	var pad_radial := Vector3(0.0, 1.0, 0.0).rotated(Vector3.RIGHT, pad_angle)
	var stand_off: float = RECOVERY_DECK_VIS + BOOSTER_STAND_UNITS + _recovery_visual_alt(alt_km)
	return {
		"radial": radial,
		"prograde": prograde,
		"pos": space_center + radial * (ORBIT_EARTH_RADIUS_VIS + stand_off),
		# The deck sits at the *pad's* arc position, not under the stage.  While
		# the guidance was fake the distinction was invisible; now a stage that
		# misses its return budget visibly comes down short of the tower, which
		# is the honest picture the failure branch is talking about.
		"pad_radial": pad_radial,
		"deck": space_center + pad_radial * (ORBIT_EARTH_RADIUS_VIS + RECOVERY_DECK_VIS),
	}

## Compressed visual height of the descent.  On the orbital scale 70 km is under
## six units — less than the height of the stage itself — so the fall would be
## invisible.  This is the same compromise the ascent climb already makes, with
## the same shape: fast near the ground, saturating far from it.
func _recovery_visual_alt(alt_km: float) -> float:
	return RECOVERY_VISUAL_SPAN * pow(clampf(alt_km / RECOVERY_VISUAL_KM_FULL, 0.0, 1.0), RECOVERY_VISUAL_EXP)

## One fixed slice of the returning stage's flight.  This is the same style of
## physics the ascent uses — two-body gravity, exponential air, thrust along
## the chosen direction, curvature terms for the rotating frame — applied to a
## 2D vertical-plane state (downrange x, altitude y) over the curved Earth.
## Every burn spends the propellant actually left in the tanks at separation,
## and every phase change is driven by a physical condition, never by a clock
## lookup.  If the fuel runs out the stage falls out of the sky: that outcome
## is as real as the landing one.
func _booster_physics(dt: float) -> void:
	if not booster_recoverable or booster_sep_met < 0.0 or booster_landed:
		return
	# Held at the interface gate the stage's own clock is frozen: velocities
	# stay exactly as they were, the integrator takes no steps, and the visual
	# "parked at re-entry interface" behaviour is what the player sees.
	if booster_held_at_gate:
		return
	# The gate is enforced on the physics slice itself, not on the render frame.
	# At high warp a single frame can consume hundreds of slices, and a frame-
	# level check would let the stage fall clean through the interface lag and
	# into the entry burn before the hold ever engaged.  If the orbital vehicle
	# has not cut its engines yet, the stage stops at the interface here.
	if booster_at_interface and booster_phase_name == "ENTRY INTERFACE" and not seco_done:
		booster_held_at_gate = true
		_show_callout("FIRST STAGE HOLDING AT RE-ENTRY — WAITING FOR SECO", 3.4)
		return
	booster_elapsed_s += dt

	var alt_km: float = maxf(booster_alt_km, 0.0001)
	var r_km: float = body_radius_km + alt_km
	var radius_m: float = r_km * 1000.0
	var g_local: float = surface_gravity * pow(body_radius_km / r_km, 2.0)
	var density: float = air_density_sl * exp(-alt_km / scale_height_km)
	var speed: float = sqrt(booster_vx_ms * booster_vx_ms + booster_vy_ms * booster_vy_ms)
	# Boostback guidance target, recomputed every slice: where the stage will
	# cross the pad's meridian if it stopped thrusting now.  Positive means the
	# ballistic coast still falls downrange of the pad, so there is more up-range
	# velocity to buy; zero is the cutoff.  Doing this as a projection rather
	# than a fixed target speed matters, because the stage keeps travelling
	# downrange while it is burning — a precomputed cutoff number is always
	# either wasteful or short.
	var bb_range_err: float = booster_x_km * 1000.0 + booster_vx_ms * BOOSTER_RETURN_COAST_S

	# ── Phase machine: transitions on physical conditions only ──
	var t: float = booster_elapsed_s
	match booster_phase_name:
		"":
			_booster_set_phase("SEPARATION")
		"SEPARATION":
			if t >= 1.0:
				_booster_set_phase("FLIP AND LIGHT")
		"FLIP AND LIGHT":
			if t >= BOOSTER_FLIP_S + BOOSTER_FLIP_BURN_LAG:
				_booster_set_phase("BOOSTBACK BURN")
		"BOOSTBACK BURN":
			# Cut when the pad is reachable on the ballistic coast, or when the
			# boostback floor threatens the entry and landing budget.
			if bb_range_err <= 0.0 or booster_prop_kg <= BOOSTER_BB_FLOOR_KG:
				_booster_set_phase("COASTING BACK")
		"COASTING BACK":
			if booster_vy_ms < 0.0 and alt_km <= booster_interface_km:
				booster_at_interface = true
				booster_interface_s = t
				_booster_set_phase("ENTRY INTERFACE")
		"ENTRY INTERFACE":
			# The lag is measured on the stage's own clock, so the hold gate in
			# _update_booster() keeps the ignition waiting for SECO too.
			if t >= booster_interface_s + BOOSTER_ENTRY_IGNITE_LAG_S:
				booster_entry_start_s = t
				_booster_set_phase("ENTRY BURN")
		"ENTRY BURN":
			if speed <= BOOSTER_ENTRY_CUTOFF_MS \
					or t >= booster_entry_start_s + BOOSTER_ENTRY_MAX_S \
					or booster_prop_kg <= BOOSTER_LANDING_RESERVE_KG \
					or density > 0.02:
				booster_fins_out = true
				_booster_set_phase("GRID FIN DESCENT")
		"GRID FIN DESCENT":
			if alt_km <= BOOSTER_GEAR_ALT_KM:
				booster_gear_out = true
				_booster_set_phase("FINAL APPROACH")
		"FINAL APPROACH":
			# The honest gravity-turn landing formula: light when the remaining
			# height just kills the descent at the net deceleration, plus margin.
			var v_down: float = maxf(-booster_vy_ms, 0.0)
			var h_ignite_m: float = v_down * v_down / (2.0 * BOOSTER_LAND_A_NET_G * surface_gravity) \
				+ BOOSTER_LAND_MARGIN_M
			if alt_km * 1000.0 <= h_ignite_m:
				_booster_set_phase("LANDING BURN")
		"LANDING BURN":
			if alt_km * 1000.0 <= BOOSTER_LAND_CUTOFF_M:
				_booster_finish(booster_vy_ms, BOOSTER_LAND_CUTOFF_M)
				return
	# Surface contact in any other phase is exactly what it reads as: an impact.
	if booster_alt_km <= 0.001 and booster_vy_ms <= 0.0:
		_booster_finish(booster_vy_ms)
		return

	# ── Thrust: direction and magnitude are the phase's, fuel is the tanks' ──
	var t_max_n: float = maxf(booster_engine_kN, 1.0) * 1000.0
	var thr_n: float = 0.0
	var dir_x: float = 0.0
	var dir_y: float = 0.0
	match booster_phase_name:
		"BOOSTBACK BURN":
			thr_n = BOOSTER_BB_THR_FRAC * t_max_n
			# Fly the burn the way a real boostback is flown: throw the horizontal
			# speed back up-range with just enough tilt to carry the stage's own
			# weight, rather than pointing every newton at the velocity vector and
			# ending up stopped in mid-air over the wrong state.  Pure retrograde
			# is thrifty in none of the ways that matter: it spends the budget
			# killing vertical speed the coast was going to give back anyway.
			if thr_n > 0.0:
				var a_max: float = thr_n / booster_mass_kg
				var vert_frac: float = clampf(g_local / a_max, 0.0, 0.98)
				dir_y = vert_frac
				dir_x = -sqrt(maxf(1.0 - vert_frac * vert_frac, 0.0)) * signf(bb_range_err)
		"ENTRY BURN":
			# Three engines again, but flown to a load rather than to full
			# throttle: at re-entry speed the engine authority alone is over
			# nine g, which the stage would survive only by luck, so the burn
			# is throttled to the deceleration a real recovery holds.
			thr_n = minf(BOOSTER_BB_THR_FRAC * t_max_n, \
					booster_mass_kg * BOOSTER_ENTRY_DECEL_G * surface_gravity)
			if speed > 10.0:
				dir_x = -booster_vx_ms / speed
				dir_y = -booster_vy_ms / speed
		"LANDING BURN":
			# Feed-forward powered descent.  The exact deceleration that carries
			# the stage from its current descent rate to zero precisely at the
			# deck is v²/(2h), so that is what the engine is commanded to — plus
			# gravity, plus a small margin for the integrator's lag.  Following a
			# velocity setpoint instead always arrives late: the stage is asked to
			# be at a slower speed than the height it has left can still buy, so
			# it either hangs above the pad burning its reserve or arrives on the
			# deck at whatever speed the loop had not yet taken off.
			var h_left: float = maxf(alt_km * 1000.0 - BOOSTER_LAND_CUTOFF_M, 1.0)
			var v_down: float = maxf(-booster_vy_ms, 0.0)
			# Scale-free by design: the commanded deceleration is a fixed multiple
			# of the exact stop-at-deck value, so the descent follows v ∝ h^0.6 and
			# arrives slow whatever the ignition height was.  Adding a velocity
			# term on top would make it a hover law — the stage would brake to
			# nothing five hundred metres up and then spend the rest of its fuel
			# waiting there, which is a crash caused by the guidance.
			var a_profile: float = BOOSTER_LAND_PROFILE_MARGIN * v_down * v_down / (2.0 * h_left)
			var a_cmd: float = g_local + a_profile
			var thr_hold: float = booster_mass_kg * a_cmd
			var land_max: float = BOOSTER_LAND_THR_FRAC * t_max_n
			# The idle setting has to sit *below* weight or the stage cannot
			# descend under thrust at all; the ceiling is one engine at full.
			thr_n = clampf(thr_hold, land_max * 0.12, land_max)
			dir_x = 0.0
			dir_y = 1.0
	if booster_prop_kg <= 0.0:
		thr_n = 0.0

	# ── Forces in the vertical plane over the curved surface ──
	var cd_a: float = BOOSTER_CD_A_FINNED if booster_fins_out else BOOSTER_CD_A_CLEAN
	var drag_n: float = 0.5 * density * speed * speed * cd_a
	var drag_ax: float = 0.0
	var drag_ay: float = 0.0
	if speed > 1.0:
		drag_ax = -drag_n / booster_mass_kg * (booster_vx_ms / speed)
		drag_ay = -drag_n / booster_mass_kg * (booster_vy_ms / speed)
	var centrifugal: float = booster_vx_ms * booster_vx_ms / radius_m
	var coriolis: float = 2.0 * booster_vy_ms * booster_vx_ms / radius_m
	var ax: float = drag_ax - coriolis
	var ay: float = drag_ay - g_local + centrifugal
	if thr_n > 0.0:
		var thr_a: float = thr_n / booster_mass_kg
		ax += thr_a * dir_x
		ay += thr_a * dir_y
		# Steer gently back toward the pad while there is thrust to spare; the
		# bias is an acceleration, not a hard heading, so the arc still bends
		# with the physics rather than snapping to a bearing.
		if booster_phase_name == "BOOSTBACK BURN" or booster_phase_name == "ENTRY BURN":
			ax += clampf(-booster_x_km * 0.15 - booster_vx_ms * 0.08, -3.0, 3.0)
		elif booster_phase_name == "LANDING BURN":
			ax += clampf(-booster_x_km * 0.5 - booster_vx_ms * 0.10, -4.0, 4.0)
	# Grid fins: real steering authority only once there is air and speed to
	# push on, aiming the descent at an intercept with the pad rather than
	# merely at the pad — the target horizontal speed accounts for the time
	# the rest of the fall will take.
	if booster_phase_name == "GRID FIN DESCENT" or booster_phase_name == "FINAL APPROACH":
		var q_dyn: float = 0.5 * density * speed * speed / 1000.0
		var authority: float = clampf(q_dyn / 2.0, 0.0, 1.0)
		var t_go: float = clampf(booster_alt_km * 1000.0 / maxf(-booster_vy_ms, 20.0), 10.0, 400.0)
		var v_x_target: float = clampf(-booster_x_km * 1000.0 / t_go, -220.0, 220.0)
		ax += clampf((v_x_target - booster_vx_ms) * 0.16, -5.0, 5.0) * authority

	# ── Integrate one slice ──
	# What the airframe actually feels: everything except gravity.  The entry
	# burn's throttle limit is only a claim until the realised load is measured.
	var felt_g: float = sqrt(ax * ax + (ay + g_local) * (ay + g_local)) / surface_gravity
	if booster_phase_name == "ENTRY BURN":
		booster_peak_entry_g = maxf(booster_peak_entry_g, felt_g)
	booster_vx_ms += ax * dt
	booster_vy_ms += ay * dt
	booster_x_km += booster_vx_ms * dt / 1000.0
	booster_alt_km = maxf(0.0, booster_alt_km + booster_vy_ms * dt / 1000.0)
	if thr_n > 0.0:
		var flow: float = thr_n / (BOOSTER_ISP_S * surface_gravity)
		booster_prop_kg = maxf(0.0, booster_prop_kg - flow * dt)
		booster_mass_kg = booster_dry_kg + booster_prop_kg
	# Telemetry the shot and the panel read: burn strength is normalised to one
	# engine so the plume sizing keeps its meaning at three-engine levels.
	booster_spd_ms = speed
	booster_prop_t = booster_prop_kg / 1000.0
	booster_burn = clampf(thr_n / maxf(BOOSTER_LAND_THR_FRAC * t_max_n, 1.0), 0.0, 1.0)

## The one way the phase label changes, so the narration beat always fires with
## the physical moment that caused it.
func _booster_set_phase(phase: String) -> void:
	if phase == booster_phase_name:
		return
	booster_phase_name = phase
	_booster_beats(phase, booster_elapsed_s)

## The end of the return, in both of its forms: soft enough is a landing,
## anything else is a loss.  Which one happened is decided by the touchdown
## speed the integrator actually produced, never by the script.
func _booster_finish(vy_touch: float, drop_m: float = 0.0) -> void:
	booster_alt_km = 0.0
	# The engine is shut down a metre or so above the deck, which is what a real
	# landing burn does on purpose — the last stretch is a fall, and gravity
	# does not forgive it.  Reporting the cutoff speed instead of the arriving
	# speed would be the one place the film disagreed with the physics.
	var v_touch: float = absf(vy_touch)
	if drop_m > 0.0:
		v_touch = sqrt(v_touch * v_touch + 2.0 * surface_gravity * drop_m)
	booster_touchdown_speed_ms = v_touch
	booster_landed = true
	# Three honest ways to lose the stage: arriving too fast, arriving with
	# empty tanks, and arriving somewhere other than the deck.  The third is
	# new now that the position is real — guidance that leaves it 40 km downrange
	# has missed the pad, however gently it touches the water.
	booster_crashed = booster_touchdown_speed_ms >= BOOSTER_OK_TOUCH_MS \
		or booster_prop_kg <= 0.0 or absf(booster_x_km) > 5.0
	booster_burn = 0.0
	if booster_crashed:
		booster_phase_name = "HARD IMPACT"
		_play_cue(70.0, 0.5)
		recovery_dust_alpha = 1.6
		_show_callout("HARD IMPACT — STAGE LOST", 5.0)
		_set_headline("STAGE LOST", UI_RED)
		if status_label:
			status_label.text = "The stage came down at %.1f m/s, %.1f km %s of the pad, with %.1f t of propellant left. That is not a recovery." % [
				booster_touchdown_speed_ms, absf(booster_x_km), "east" if booster_x_km > 0.0 else "west", booster_prop_kg / 1000.0]
		GameManager.simulation_state["booster_landed"] = false
		GameManager.simulation_state["booster_recovered"] = false
		GameManager.simulation_state["booster_crashed"] = true
	else:
		booster_phase_name = "TOUCHDOWN"
		booster_touchdown_met_s = met_seconds
		booster_touchdown_hold = RECOVERY_HOLD_S
		recovery_dust_alpha = 1.0
		_play_cue(240.0, 0.26)
		_show_callout("FIRST STAGE TOUCHDOWN — HOME AT THE LAUNCH SITE", 4.5)
		_set_headline("STAGE RECOVERED", UI_GREEN)
		if status_label:
			status_label.text = "The stage that lifted this vehicle is standing back at its launch pad at T+%0.0f s, touchdown %.1f m/s, %.1f t of propellant left." % [
				met_seconds, booster_touchdown_speed_ms, booster_prop_kg / 1000.0]
		GameManager.simulation_state["booster_landed"] = true
		GameManager.simulation_state["booster_recovered"] = true
		GameManager.simulation_state["booster_touchdown_met_s"] = booster_touchdown_met_s

## Whether the split screen owns the left half right now.  Timing is event
## driven — open just after separation, close a few wall seconds after whatever
## happened at the deck — because the table clock it replaced no longer exists.
func _split_live(dt: float) -> bool:
	if booster_landed and booster_touchdown_hold > 0.0:
		return true
	return not booster_landed

## Drives the returned stage's *presentation*: readouts, hardware, placement
## and the cut to its camera.  The flight numbers themselves come from
## _booster_physics() on the fixed slices; this runs on rendered frames and
## consumes that state, with wall-time only for the animation.
func _update_booster(wall_dt: float) -> void:
	if not booster_recoverable or booster_node == null or booster_sep_met < 0.0:
		return
	var dt: float = booster_elapsed_s
	_update_recovery_atmosphere()
	var live: bool = _split_live(dt)
	booster_touchdown_hold = maxf(booster_touchdown_hold - wall_dt, 0.0)
	# After touchdown the stage simply stands on the deck with its beacon running.
	# It is hidden once the split closes: a rocket parked on the ocean fifty degrees
	# of arc away has no business floating in the orbital vehicle's frame.
	var progress: float = clampf(1.0 - booster_alt_km / maxf(booster_sep_alt_km * 0.7, 1.0), 0.0, 1.0)
	booster_progress_shot = progress
	var frame: Dictionary = _booster_frame(booster_alt_km, progress)
	var radial: Vector3 = frame["radial"]
	var prograde: Vector3 = frame["prograde"]
	booster_node.visible = live
	if booster_node.visible:
		booster_node.global_position = frame["pos"]
		# The attitude is a consequence of the flight rather than a schedule:
		# the flip swings the stage from its separation attitude to
		# engines-down over its own short window, powered phases hold the
		# engines at the planet, and coasting flight rides the retrograde
		# vector — the actual velocity, blended toward vertical so the shot
		# keeps its composition.
		var axis := radial
		if dt < BOOSTER_FLIP_S + 4.0:
			var flip_t: float = clampf((dt - 1.0) / BOOSTER_FLIP_S, 0.0, 1.0)
			axis = booster_nose_dir.lerp(radial, flip_t).normalized()
		elif booster_burn <= 0.05 and not booster_landed:
			var vel := prograde * booster_vx_ms + radial * booster_vy_ms
			if vel.length_squared() > 100.0:
				axis = (-vel.normalized()).lerp(radial, 0.35).normalized()
		booster_node.basis = Basis(Quaternion(Vector3.UP, axis))
		booster_node.rotate_object_local(Vector3.UP, sin(met_seconds * 1.7) * 0.05)
	# Landing gear and grid fins.
	booster_legs_anim = move_toward(booster_legs_anim, 1.0 if booster_gear_out else 0.0, wall_dt * 0.45)
	for leg in booster_legs:
		var outward := Vector3(leg.position.x, 0.0, leg.position.z).normalized()
		if outward.length_squared() < 0.5:
			continue
		leg.basis = Basis(outward, lerpf(deg_to_rad(157.0), deg_to_rad(12.0), booster_legs_anim))
	for f in booster_fins:
		f.rotate_y(wall_dt * 0.6 * sin(met_seconds * 2.4))
	# Engine plume and the light it throws on the vehicle.
	if booster_plume:
		var burning: bool = booster_burn > 0.05 and not booster_landed
		booster_plume.visible = burning
		var pcore := booster_node.get_node_or_null("BoosterPlumeCore") as MeshInstance3D
		if pcore:
			pcore.visible = burning
		if burning:
			# Throttle changes the length of the flame far more than its width, and
			# the plume has to stay attached to the engine exit as it grows, so the
			# node is re-parked rather than merely scaled about its own centre.
			var flick: float = 0.90 + 0.10 * sin(met_seconds * 41.0)
			var plume_w: float = (0.62 + 0.42 * booster_burn) * flick
			var plume_len: float = (0.34 + 0.78 * booster_burn) * flick
			booster_plume.scale = Vector3(plume_w, plume_len, plume_w)
			booster_plume.position = Vector3(0.0, -6.0 - 2.3 * plume_len, 0.0)
			if pcore:
				var core_flick: float = 0.92 + 0.08 * sin(met_seconds * 57.0)
				pcore.scale = Vector3(plume_w * 0.9, plume_len * core_flick, plume_w * 0.9)
				pcore.position = Vector3(0.0, -6.0 - 1.2 * plume_len, 0.0)
	if booster_burn_light:
		booster_burn_light.light_energy = 0.0 if booster_landed else booster_burn * 2.6
	# The landing rig rides the planet at the launch site, whether or not the
	# stage is anywhere near it.
	if recovery_rig:
		recovery_rig.visible = live
		if recovery_rig.visible:
			var deck: Vector3 = frame["deck"]
			var pad_up: Vector3 = frame["pad_radial"]
			recovery_rig.global_position = deck
			recovery_rig.basis = Basis(Quaternion(Vector3.UP, pad_up))
			if recovery_dust:
				recovery_dust.visible = recovery_dust_alpha > 0.01
				if recovery_dust.visible:
					recovery_dust_alpha = maxf(recovery_dust_alpha - wall_dt * 0.75, 0.0)
					# A shallow ring of kicked-up vapour at deck level, not a growing
					# sphere: an unshaded white ball scaled up around the vehicle turns
					# the payoff shot of the whole sequence into a blown-out blob.
					var blast: float = 1.0 - recovery_dust_alpha
					recovery_dust.scale = Vector3(1.0 + blast * 1.6, 0.5 + blast * 0.5, 1.0 + blast * 1.6)
					var dm := recovery_dust.material_override as StandardMaterial3D
					if dm:
						dm.albedo_color.a = recovery_dust_alpha * 0.5
	# Split handling: the left picture opens with the stage and closes on the deck.
	booster_dt_now = dt
	# The gate itself.  Before the orbital vehicle has cut its engines the stage
	# holds at re-entry interface — the integrator takes no slices and its
	# velocities freeze in place — while the mission clock keeps coasting, so
	# touchdown always plays *after* the orbit beat the player has just watched.
	# The shot says so out loud rather than letting the frozen booster look like
	# a stall.
	if not booster_landed and booster_held_at_gate and seco_done:
		# Engagement happens inside the physics slice (so no warp can sneak past
		# the interface); the release is a broadcast beat, so it lives here.
		booster_held_at_gate = false
		_show_callout("SECO BOOKED — FIRST STAGE RESUMES ITS DESCENT", 3.2)
	if split_caption_stage:
		split_caption_stage.text = "◀ FIRST STAGE — HOLDING FOR ORBITAL INSERTION" if booster_held_at_gate else "◀ FIRST STAGE — RETURNING"
	_update_recovery_panel(live, booster_legs_anim)
	if live and not split_is_open:
		_open_split()
	elif not live and split_is_open:
		_close_split()
	if split_is_open:
		_update_recovery_camera(dt, frame)

## The side panel that belongs to the returning stage.  It is deliberately a
## separate readout: the main telemetry column is still reporting the orbital
## vehicle, and mixing the two sets of numbers would imply they were the same
## object flying.
func _build_recovery_panel(ui: Control) -> void:
	var d := _glass("FIRST STAGE — RETURN")
	recovery_panel = d["panel"] as PanelContainer
	var v: VBoxContainer = d["box"] as VBoxContainer
	_anchor(recovery_panel, 0, 0, 0, 0, 16, 128, 336, 520)
	ui.add_child(recovery_panel)
	rec_phase_label = _mk_label("SEPARATION", 16, UI_ACCENT)
	v.add_child(rec_phase_label)
	rec_alt_label = _tele_row(v, "Altitude", "▼")
	rec_spd_label = _tele_row(v, "Speed", "●")
	var prop_row := _bar_row(v, "◆", "S1 Prop", UI_GREEN)
	rec_fuel_bar = prop_row["bar"] as ProgressBar
	rec_prop_label = prop_row["pct"] as Label
	rec_note_label = _mk_label("", 12, UI_DIM)
	rec_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rec_note_label.custom_minimum_size = Vector2(290, 0)
	v.add_child(rec_note_label)
	recovery_panel.hide()

func _update_recovery_panel(live: bool, legs_out: float) -> void:
	if recovery_panel == null or not live:
		return
	if rec_phase_label:
		rec_phase_label.text = booster_phase_name
		rec_phase_label.add_theme_color_override("font_color",
			UI_GREEN if booster_landed else UI_ACCENT)
	if rec_alt_label:
		if booster_alt_km >= 0.1:
			rec_alt_label.text = "%.1f km" % booster_alt_km
		else:
			rec_alt_label.text = "%.0f m" % (booster_alt_km * 1000.0)
	if rec_spd_label:
		rec_spd_label.text = "%.0f m/s" % booster_spd_ms
	if rec_fuel_bar:
		# The denominator is the propellant this stage actually carried away from
		# the stack — the budget the flight is being spent from — not a table.
		var start_prop_t: float = maxf(booster_prop_start_kg / 1000.0, 1.0)
		rec_fuel_bar.value = clampf(booster_prop_t / start_prop_t, 0.0, 1.0) * 100.0
	if rec_phase_label:
		rec_phase_label.add_theme_color_override("font_color",
			(UI_RED if booster_crashed else UI_GREEN) if booster_landed else UI_ACCENT)
	if rec_prop_label:
		rec_prop_label.text = "%.1f t" % booster_prop_t
	if rec_note_label:
		var how: String = ""
		if booster_held_at_gate:
			rec_note_label.text = "Holding at re-entry interface. The orbital vehicle is still firing — the stage comes home after its payload is in orbit."
		elif booster_crashed:
			rec_note_label.text = "Impact at %.0f m/s with %.1f t left. The stage is lost." % [
				booster_touchdown_speed_ms, booster_prop_kg / 1000.0]
		elif booster_landed:
			rec_note_label.text = "On the pad at the launch site. Touchdown %.1f m/s, %.1f t of propellant to spare." % [
				booster_touchdown_speed_ms, booster_prop_kg / 1000.0]
		else:
			var tail: String = ""
			if booster_burn > 0.05:
				tail = "Engines lit at %.0f%% — thrust holding it against its own mass." % [booster_burn * 100.0]
			elif booster_legs_anim > 0.05:
				tail = "Engines cold. Gear deployed, grid fins walking it down."
			else:
				tail = "Engines cold. Falling back under its own momentum."
			rec_note_label.text = "%.0f s since separation — %s" % [booster_dt_now, tail]

## The announced moments of the return.  Fired by _booster_set_phase() on the
## physical phase edge, so the words always arrive with the thing the player can
## see happening.  Touchdown and hard impact are narrated in _booster_finish()
## itself, because they end the flight rather than label a stretch of it.
func _booster_beats(phase: String, dt: float) -> void:
	booster_beat_idx += 1
	var beat: Dictionary = RECOVERY_BEATS.get(phase, {})
	if beat.is_empty():
		return
	var text := String(beat["text"])
	var line := String(beat["line"])
	# Any number the beat quotes is one this flight actually produced, not one
	# inherited from the reference profile.
	if phase == "ENTRY INTERFACE":
		line = "Falling back into the atmosphere at %.0f m/s. Ahead of it the air is already beginning to slow it down." % booster_spd_ms
	elif phase == "FINAL APPROACH":
		text = "LANDING LEGS DOWN — %.0f KILOMETRES TO THE PAD" % maxf(booster_alt_km, 1.0)
		line = "Four carbon legs swing out and lock. The centre engine relights when the fall can still be killed above the deck."
	elif phase == "BOOSTBACK BURN":
		line = "Three engines light to throw away the %.0f m/s of downrange speed. This is the part an expendable rocket never gets to do." % absf(booster_vx_ms)
	elif phase == "ENTRY BURN":
		line = "Three engines again, but flown to a load of %.1f g rather than to full throttle: at %.0f m/s the engines could hold far more than the airframe should ever see." % [
			BOOSTER_ENTRY_DECEL_G, booster_spd_ms]
	elif phase == "LANDING BURN":
		line = "A single engine at %.0f%% of its thrust, coming down at %.0f m/s onto the pad it lifted off from." % [
			booster_burn * 100.0, maxf(-booster_vy_ms, 0.0)]
	_play_cue(float(beat["cue"]), 0.16)
	_show_callout(text, 3.4)
	if status_label:
		status_label.text = line

## Opens the second picture.  The viewport renders on demand rather than always:
## an extra full render pass for a shot nobody is looking at is frame budget that
## was never asked to be spent.
func _open_split() -> void:
	booster_cam_window = 1
	split_is_open = true
	if split_picture: split_picture.show()
	if split_divider: split_divider.show()
	if split_caption_stage: split_caption_stage.show()
	if split_caption_vehicle: split_caption_vehicle.show()
	if split_viewport:
		split_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Current *in its own viewport only*.  The window keeps its camera, which is
	# the entire reason the two halves can exist at the same time.
	if cam_recovery: cam_recovery.current = true
	if recovery_panel:
		recovery_panel.show()
	# The mission-card panel is the one thing on the overlay that has no business
	# competing with the shot, and the stage readout needs its slot: the two never
	# appear together.
	if left_panel:
		left_panel.hide()
	_resize_split()

func _close_split() -> void:
	booster_cam_window = 0
	split_is_open = false
	if split_viewport:
		split_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if cam_recovery: cam_recovery.current = false
	if split_picture: split_picture.hide()
	if split_divider: split_divider.hide()
	if split_caption_stage: split_caption_stage.hide()
	if split_caption_vehicle: split_caption_vehicle.hide()
	if recovery_panel:
		recovery_panel.hide()
	if left_panel:
		left_panel.show()
	# Nothing is handed back to the window camera, because the window camera never
	# moved.  That is the whole point of the split.

## Keeps the render target at the size the picture is actually displayed at.  A
## viewport stretched into a rectangle of a different shape gives a soft, wrongly
## proportioned half of the screen, and a camera's framing depends on the
## proportion, so this is not a detail.
func _resize_split() -> void:
	if split_viewport == null or split_picture == null:
		return
	var s: Vector2 = split_picture.size
	if s.x < 2.0 or s.y < 2.0:
		return
	var pixel_scale: float = 1.0
	if get_window():
		pixel_scale = maxf(get_window().content_scale_factor, 0.25)
	var want := Vector2i(int(s.x * pixel_scale), int(s.y * pixel_scale))
	if split_viewport.size != want:
		split_viewport.size = want

## Frames the returning stage against the planet, inside the left picture.  The
## stage's long axis is the local vertical — its nose is held along `radial` and
## its engines point down at the deck — so the camera's up-vector has to be
## `radial` as well.  Filming it with `prograde` as up turned the booster on its
## side and pushed the planet into one edge of frame, which is what made the
## return read as a rocket stuck to a flat blue ball instead of a vertical
## powered landing.  The body of the shot sits in the side-prograde plane so the
## view direction stays close to perpendicular to that up-vector and `look_at`
## never degenerates; a small radial lift looks down onto the deck.  The distance
## and the aim point read the altitude the stage is actually flying at, so the
## shot closes when the physics says it should and never a table ahead of it.
func _update_recovery_camera(dt: float, frame: Dictionary) -> void:
	if not cam_recovery or booster_node == null:
		return
	_resize_split()
	var radial: Vector3 = frame["radial"]
	var prograde: Vector3 = frame["prograde"]
	var side := radial.cross(prograde).normalized()
	var pos: Vector3 = booster_node.global_position
	# Framing follows the stage's real altitude rather than a table clock: wide
	# while it is still high, closing as it descends, tight on the deck once the
	# flight is over.  Physics decides when each moment happens; the shot reacts.
	var closeness: float = clampf(1.0 - booster_alt_km / 40.0, 0.0, 1.0)
	var distance: float = 17.0 if booster_landed else lerpf(42.0, 20.0, closeness)
	var aim_below: float = lerpf(1.5, 5.5, closeness)
	# Placed exactly, every frame, rather than flown toward the shot.  The stage is
	# riding a ground track that sweeps tens of units per second, and a smoothed
	# follow always trails it by a distance comparable to the framing itself — the
	# camera ends up somewhere off to one side, looking along the limb instead of
	# down at the deck.  A rigidly attached camera is how the orbital shot beside it
	# already works.
	cam_recovery.global_position = pos + side * distance * 0.90 + prograde * distance * 0.30 + radial * distance * 0.16
	cam_recovery.look_at(pos - radial * aim_below, radial)

func _clear_booster() -> void:
	booster_legs.clear()
	booster_fins.clear()
	booster_plume = null
	booster_burn_light = null
	site_clouds.clear()
	recovery_ship = null
	recovery_dust = null
	if recovery_rig and is_instance_valid(recovery_rig):
		recovery_rig.queue_free()
	recovery_rig = null
	if booster_node and is_instance_valid(booster_node):
		booster_node.queue_free()
	booster_node = null

func _update_stage_debris(delta: float) -> void:
	var surviving_debris: Array[Dictionary] = []
	for piece in stage_debris:
		# Do not cast first: a Variant can still hold a reference to an object
		# already freed by queue_free(), and casting that stale reference throws.
		var raw_node: Variant = piece.get("node", null)
		if raw_node == null or not is_instance_valid(raw_node):
			continue
		var node := raw_node as Node3D
		if node == null:
			continue
		piece["life"] = float(piece.get("life", 0.0)) + delta
		var velocity := piece.get("velocity", Vector3.ZERO) as Vector3
		# A discarded stage is no longer guided: it keeps its separation impulse,
		# feels gravity, and is quickly outrun by the still-accelerating vehicle.
		velocity += Vector3(0.0, -9.8, 0.0) * delta
		velocity *= (1.0 - 0.06 * delta)
		piece["velocity"] = velocity
		node.position += velocity * delta
		var spin := piece.get("spin", Vector3.ZERO) as Vector3
		node.rotate_object_local(Vector3.RIGHT, spin.x * delta)
		node.rotate_object_local(Vector3.FORWARD, spin.z * delta)
		# Real debris is gone from the shot within seconds. Keeping it in frame
		# beside an orbital vehicle is the single most immersion-breaking thing
		# this scene could do, so it is culled on distance as well as on time.
		var distance_from_vehicle: float = 10000.0
		if rocket:
			distance_from_vehicle = node.global_position.distance_to(rocket.global_position)
		if float(piece["life"]) > 6.0 or distance_from_vehicle > 260.0:
			node.queue_free()
		else:
			surviving_debris.append(piece)
	stage_debris = surviving_debris

## Removes every discarded component.  Called the moment the vehicle crosses into
## the space frame, because nothing that was jettisoned in the atmosphere should
## still be sharing the screen with a satellite.
func _clear_stage_debris() -> void:
	for piece in stage_debris:
		var raw_node: Variant = piece.get("node", null)
		if raw_node != null and is_instance_valid(raw_node):
			(raw_node as Node3D).queue_free()
	stage_debris.clear()
	if upper_stage_visual and is_instance_valid(upper_stage_visual):
		upper_stage_visual.queue_free()
	upper_stage_visual = null

# ─── Orbital Insert + Deploy ──────────────────────────────────────────────────
# A real vehicle does not simply "burn until high enough".  It flies two burns:
#   1. raise the apogee to the target altitude, then cut and coast,
#   2. at apogee, burn prograde until the *opposite* side of the orbit is lifted
#      to the same height — which is what turns an ellipse into a circle.
# The result is that Ap and Pe converge on the mission altitude and the final
# speed is the honest circular velocity sqrt(mu/r), so the operational orbit
# scene inherits exactly the numbers the launch screen just displayed.
func _update_orbital_insert(dt: float) -> void:
	_update_ascent(dt)
	match insertion_phase:
		InsertionPhase.COAST_TO_APOGEE:
			coast_timer += dt
			# The coast to apogee is the one honest stretch of a real launch with
			# minutes of nothing visible in it.  Point out the warp control once,
			# while nothing is burning — never during Max-Q, staging, SECO or the
			# landing burn, and never by moving the clock without being asked.
			if not coast_suggest_done and player_warp_idx == 0 and coast_timer > 20.0:
				coast_suggest_done = true
				_show_callout("LONG COAST — PRESS WARP (1-6 OR WHEEL) TO SKIP AHEAD", 4.0)
			var at_apogee: bool = coast_timer > 25.0 and (
				vertical_velocity_ms <= 0.0 or altitude_km >= apoapsis_km - 2.0)
			if at_apogee or coast_timer > 1500.0:
				_set_state(LaunchState.ORBITAL_INSERT)
		InsertionPhase.CIRCULARISE:
			# The honest end-of-burn cue at apogee is *speed*, not altitude: the
			# moment the vehicle reaches circular velocity for the target radius,
			# the ellipse is a circle.  Waiting for the perigee figure to catch up
			# means the engine keeps adding metres per second it no longer needs,
			# which is exactly how the old code flew a 550 km mission out to
			# 42,000 km apogee.
			if velocity_ms >= orbit_speed_target * 0.997 or propellant_left_kg <= 0.0:
				_set_state(LaunchState.ORBITAL_INSERT)
		_:
			pass

## SECO — the moment the mission orbit actually exists.  The values are written
## into GameManager so the handover to orbit operations is continuous, not a cut
## to a scene that invents its own numbers.
func _finish_orbit_insertion() -> void:
	if seco_done:
		return
	seco_done = true
	insertion_phase = InsertionPhase.DONE
	throttle = 0.0
	_set_engine_fx(false)
	var r_km: float = body_radius_km + target_orbit_km
	var v_circ: float = sqrt(body_mu / r_km) * 1000.0
	# Snap the trajectory to the orbit we asked for; the residual error from the
	# discrete burn is noise, and showing it would look like a guidance failure.
	apoapsis_km = target_orbit_km
	periapsis_km = target_orbit_km
	altitude_km = target_orbit_km
	vertical_velocity_ms = 0.0
	horizontal_velocity_ms = v_circ
	velocity_ms = v_circ
	axial_g = 0.0
	dynamic_pressure_kpa = 0.0
	var period_s: float = 2.0 * PI * sqrt(pow(r_km, 3.0) / body_mu)
	var period_min: float = period_s / 60.0
	orbit_period_min = period_min
	GameManager.simulation_state["orbit_altitude_km"] = target_orbit_km
	GameManager.simulation_state["orbit_speed_ms"] = v_circ
	GameManager.simulation_state["orbit_period_min"] = period_min
	GameManager.simulation_state["insertion_met_s"] = met_seconds
	GameManager.simulation_state["karman_met_s"] = karman_cross_met_s
	GameManager.simulation_state["distance_flown_km"] = path_distance_km
	GameManager.simulation_state["downrange_km"] = downrange_km
	_show_callout("SECO — %.0f KM × %.0f KM ORBIT CONFIRMED" % [apoapsis_km, periapsis_km], 4.0)
	_set_headline("ORBIT ACHIEVED", UI_GREEN)
	if status_label:
		status_label.text = "Engine cutoff. %.0f km circular orbit at %.0f m/s, period %.0f min. Preparing payload release." % [
			target_orbit_km, v_circ, period_min]
	if state_timer < 0.5:
		get_tree().create_timer(3.0).timeout.connect(func():
			if state == LaunchState.ORBITAL_INSERT:
				_set_state(LaunchState.SATELLITE_DEPLOY))

# ─── Space frame: the part that finally makes orbit *look* like orbit ─────────
func _enter_space_frame() -> void:
	in_space_frame = true
	if rocket:
		space_center = rocket.global_position - Vector3(0.0, ORBIT_EARTH_RADIUS_VIS + ORBIT_ALTITUDE_VIS, 0.0)
	else:
		space_center = Vector3(0.0, 400.0, 0.0)
	orbit_angle = 0.0
	_show_space_backdrop()
	# Above the atmosphere the pad cameras have nothing left to film — the pad is
	# hundreds of kilometres below the horizon. Hand the shot to the orbital rig.
	_set_camera(CamMode.SPACE)
	# Anything still falling back from the pad is now hundreds of kilometres
	# behind us and must not appear next to an orbital vehicle.
	_clear_stage_debris()
	_hide_ground_complex()
	# The single most quotable moment of any launch, and the point where the
	# audience's whole frame of reference changes: no more sky, only a planet.
	karman_cross_met_s = met_seconds
	_play_cue(1180.0, 0.14)
	_show_callout("KÁRMÁN LINE — 100 KM. YOU ARE IN SPACE.", 4.0)
	_set_headline("IN SPACE", UI_GREEN)
	if status_label:
		status_label.text = "Above the atmosphere at %.0f km, %.0f m/s. The sky has gone black — now the only thing that matters is sideways speed." % [
			altitude_km, velocity_ms]

## The ground-track sweep is true orbital motion: the angular rate omega =
## v_t / r integrated on *mission* time, so one revolution of the animation
## takes exactly orbit_period_min and the warp readout on the HUD is the only
## thing that makes it faster.  The planet turns at its real 7.292e-5 rad/s,
## so the ground track drifts westward at the honest rate — visibly only over
## minutes, which is precisely how long real orbital footage waits for it.
func _update_space_frame(dt: float) -> void:
	if not in_space_frame:
		return
	var r_km: float = body_radius_km + maxf(altitude_km, 0.0)
	var omega: float = (horizontal_velocity_ms / 1000.0) / maxf(r_km, 1.0)
	orbit_angle += omega * dt
	if orbit_angle > TAU:
		orbit_angle -= TAU
	earth_spin_angle += EARTH_SPIN_REAL * dt
	if earth_body:
		earth_body.rotation.y = earth_spin_angle

## Runs after the vehicle has been placed for this frame.
func _update_space_camera() -> void:
	if not in_space_frame:
		return
	# During the separation reveal the deploy shot owns cam_space. Running the
	# orbital camera here as well overwrote its position and look target every
	# frame (this function runs after _update_satellite_deploy), dragging the
	# view back down onto the planet — the flat blue screen the reveal kept
	# showing despite the tangential framing.
	if state == LaunchState.SATELLITE_DEPLOY:
		return
	_update_orbital_camera()

## The vehicle's true speed is ~7.6 km/s, but a camera that simply parks behind
## it shows nothing moving.  This frames the vehicle against the planet's limb
## and the fixed star shell, so the ground track and the drifting stars carry
## the sense of motion the way real orbital footage does.
func _update_orbital_camera() -> void:
	if not cam_space or not rocket:
		return
	# After separation the rocket node is hidden and the released stack carries on
	# ahead of it, so frame the payload once it exists — otherwise the camera keeps
	# parking on the empty spot the vehicle left behind and the shot goes black.
	var focus_node: Node3D = rocket
	if payload_craft and is_instance_valid(payload_craft) and payload_craft.visible:
		focus_node = payload_craft
	var radial := (focus_node.global_position - space_center).normalized()
	var prograde := radial.cross(Vector3.FORWARD).normalized()
	if prograde.length_squared() < 0.1:
		prograde = Vector3(0.0, 0.0, -1.0)
	# A slow inertial drift breaks the frozen co-rotating frame. The camera rides
	# AHEAD of the vehicle along the track and barely above it, looking forward
	# along the local tangent (up = local radial). That keeps the optical axis near
	# the horizon, so the planet's curved limb sits low in the frame and black space
	# fills the rest. Parking directly overhead (a large radial offset) pointed the
	# camera down and washed the whole shot flat blue with no horizon or stars.
	var drift := sin(met_seconds * 0.05)
	var desired := focus_node.global_position + prograde * (24.0 + drift * 10.0) \
		+ radial * (3.0 + drift * 2.0)
	cam_space.global_position = cam_space.global_position.lerp(desired, 0.05)
	cam_space.look_at(focus_node.global_position + radial * 1.5, radial)

func _hide_ground_complex() -> void:
	if pad_hidden_for_orbit:
		return
	pad_hidden_for_orbit = true
	for node_name in ["Ground", "LaunchPad", "PadArm", "LaunchComplex", "GroundDetail"]:
		var pad_node := get_node_or_null(node_name) as Node3D
		if pad_node: pad_node.hide()
	# The ascent shell is replaced by the real space-frame planet; leaving both
	# would put two planets in the same shot.
	if horizon_world:
		horizon_world.hide()
	horizon_active = false

func _create_payload_craft() -> void:
	# Lunar flights release a propulsion module carrying Vikram, not a satellite.
	payload_craft = Node3D.new()
	var lunar_flight := String(GameManager.current_mission.get("id", "")) == "moon_scout"
	payload_craft.name = "LunarPropulsionAndVikram" if lunar_flight else "MissionSatellite"
	if lunar_flight:
		_build_lunar_stack(payload_craft)
	else:
		var packed := load("res://assets/models/satellite.glb") as PackedScene
		if packed:
			var model := packed.instantiate() as Node3D
			if model:
				model.scale = Vector3.ONE * 0.16
				payload_craft.add_child(model)
		else:
			var bus := MeshInstance3D.new()
			var body := BoxMesh.new()
			body.size = Vector3(1.1, 0.7, 1.4)
			bus.mesh = body
			var body_mat := StandardMaterial3D.new()
			body_mat.albedo_color = Color(0.62, 0.68, 0.76)
			body_mat.metallic = 0.8
			bus.material_override = body_mat
			payload_craft.add_child(bus)
		for x in [-1.45, 1.45]:
			var panel := MeshInstance3D.new()
			var panel_mesh := BoxMesh.new()
			panel_mesh.size = Vector3(1.8, 0.06, 0.7)
			panel.mesh = panel_mesh
			panel.position.x = x
			var panel_mat := StandardMaterial3D.new()
			panel_mat.albedo_color = Color(0.02, 0.08, 0.36)
			panel_mat.metallic = 0.45
			panel.material_override = panel_mat
			payload_craft.add_child(panel)
	add_child(payload_craft)
	payload_craft.hide()

## Chandrayaan-3's lunar stack rendered as an actual spacecraft rather than two
## cylinders and a flat plate.  Vikram rides on top of the propulsion module,
## both wrapped in faceted gold MLI foil, with an engine bell, thruster pods,
## interstage rings, folded landing legs, a high-gain dish, the ISRO tricolour
## and a segmented solar wing — the details the real fairing-reveal footage is
## read by.  Kept to the same ~±1.1 footprint the deployment camera already
## frames, so nothing needs reframing.
func _build_lunar_stack(craft: Node3D) -> void:
	# The foil texture is what separates a real spacecraft from a painted box, so
	# the same quilted MLI albedo + wrinkle normal the lunar orbiter uses is
	# baked onto the transfer craft's gold surfaces here too.
	var mli := _make_mli_textures()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1, 1, 1)
	gold.albedo_texture = mli[0]
	gold.metallic = 0.55
	gold.roughness = 0.30
	gold.metallic_specular = 0.7
	gold.normal_enabled = true
	gold.normal_texture = mli[1]
	gold.normal_scale = 0.7
	gold.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	gold.emission_enabled = true
	gold.emission = Color(0.16, 0.10, 0.02)
	gold.emission_energy_multiplier = 0.10
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.82, 0.83, 0.85)
	white.metallic = 0.35
	white.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.13)
	dark.metallic = 0.3
	dark.roughness = 0.6
	var cell := StandardMaterial3D.new()
	cell.albedo_color = Color(0.03, 0.08, 0.30)
	cell.metallic = 0.3
	cell.roughness = 0.45
	cell.emission_enabled = true
	cell.emission = Color(0.03, 0.07, 0.30)
	cell.emission_energy_multiplier = 0.18
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.72, 0.52, 0.16)
	frame.metallic = 0.5
	frame.roughness = 0.35

	# ── Propulsion module: the lower stage that carries Vikram to the Moon ──
	var pm := _craft_cyl(0.42, 0.46, 1.05, 0, Vector3(0, -0.55, 0), white)
	pm.name = "PropulsionModule"
	craft.add_child(pm)
	for ry in [-0.25, -0.85]:
		craft.add_child(_craft_ring(0.47, 0.03, Vector3(0, ry, 0), frame))
	# Engine bell — a tapered nozzle with a dark throat, the module's signature.
	craft.add_child(_craft_cyl(0.16, 0.34, 0.5, 0, Vector3(0, -1.32, 0), dark))
	craft.add_child(_craft_cyl(0.12, 0.30, 0.05, 0, Vector3(0, -1.55, 0), gold))
	# ── Main engine plume ──
	# The propulsion module fires to leave Earth orbit, so a real separation shows
	# a blue-white exhaust trailing from the bell (the reference footage is lit by
	# exactly this). Additive, unshaded cones + a point light read as a vacuum
	# plume with no dependency on surface lighting.
	var plume_mat := StandardMaterial3D.new()
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume_mat.albedo_color = Color(0.45, 0.68, 1.0, 0.62)
	plume_mat.emission_enabled = true
	plume_mat.emission = Color(0.42, 0.66, 1.0)
	plume_mat.emission_energy_multiplier = 2.6
	var plume_grp := Node3D.new()
	plume_grp.name = "EnginePlumeGroup"
	# Hidden at first: firing while the stack is still nested in the fairing makes
	# the plume glow back through the mouth, so the rocket reads as transparent.
	# The deploy script only lights it once the payload has clearly cleared.
	plume_grp.visible = false
	craft.add_child(plume_grp)
	var plume := MeshInstance3D.new()
	plume.name = "EnginePlume"
	var pcm := CylinderMesh.new()
	pcm.top_radius = 0.05
	pcm.bottom_radius = 0.34
	pcm.height = 3.4
	pcm.radial_segments = 16
	pcm.rings = 6
	plume.mesh = pcm
	plume.material_override = plume_mat
	plume.position = Vector3(0, -3.7, 0)
	plume_grp.add_child(plume)
	var core_mat := StandardMaterial3D.new()
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.7)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.8, 0.92, 1.0)
	core_mat.emission_energy_multiplier = 3.2
	var core := MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.04
	ccm.bottom_radius = 0.18
	ccm.height = 2.6
	ccm.radial_segments = 12
	core.mesh = ccm
	core.material_override = core_mat
	core.position = Vector3(0, -3.0, 0)
	plume_grp.add_child(core)
	var plume_light := OmniLight3D.new()
	plume_light.light_color = Color(0.5, 0.72, 1.0)
	plume_light.light_energy = 3.6
	plume_light.omni_range = 5.5
	plume_light.position = Vector3(0, -2.4, 0)
	plume_grp.add_child(plume_light)
	# Four attitude thruster pods clustered around the module skirt.
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var pod := _craft_cyl(0.05, 0.08, 0.16, 0, Vector3(cos(a) * 0.44, -1.0, sin(a) * 0.44), dark)
		pod.rotation_degrees.z = -sin(a) * 20.0
		pod.rotation_degrees.x = cos(a) * 20.0
		craft.add_child(pod)

	# ── Vikram lander: a faceted gold MLI bus, NOT a round drum ──
	# The reference footage reads Vikram as a boxy foil-wrapped prism with a big
	# blue cell array on one face; a low-segment cylinder looked like a rounded
	# gold blob, so the body is now an actual cuboid with flat, sun-catching faces.
	var body := _craft_box(0.72, 0.62, 0.72, Vector3(0, 0.40, 0), gold)
	body.name = "VikramBody"
	craft.add_child(body)
	# Gold MLI panel seams: thin raised ribs across the faces so the blanket looks
	# like separate foiled panels rather than one smooth box.
	for fy in [0.22, 0.40, 0.58]:
		craft.add_child(_craft_box(0.74, 0.02, 0.02, Vector3(0, fy, 0.37), frame))
	craft.add_child(_craft_box(0.02, 0.60, 0.74, Vector3(0.37, 0.40, 0), frame))
	# The signature: a large blue solar cell array covering the sun-facing face,
	# gridded into cells like the real Vikram panel in the footage.
	var vpanel := Node3D.new()
	vpanel.name = "VikramSolarArray"
	vpanel.position = Vector3(0, 0.40, 0.38)
	craft.add_child(vpanel)
	vpanel.add_child(_craft_box(0.66, 0.56, 0.02, Vector3(0, 0, 0), cell))
	for gx in [-0.165, 0.0, 0.165]:
		vpanel.add_child(_craft_box(0.015, 0.56, 0.03, Vector3(gx, 0, 0.012), frame))
	for gy in [-0.14, 0.0, 0.14]:
		vpanel.add_child(_craft_box(0.66, 0.015, 0.03, Vector3(0, gy, 0.012), frame))
	# A light instrument/thermal panel on the opposite face (the silver side in
	# the second reference frame).
	craft.add_child(_craft_box(0.60, 0.50, 0.02, Vector3(0, 0.40, -0.38), white))
	# Sensor deck on top — a small boxy equipment platform, not a round cap.
	craft.add_child(_craft_box(0.42, 0.14, 0.42, Vector3(0, 0.74, 0), white))
	# Four folded landing legs tucked against the body.
	for i in 4:
		var a := float(i) * PI * 0.5 + PI * 0.25
		var leg := _craft_box(0.07, 0.6, 0.07, Vector3(cos(a) * 0.5, 0.34, sin(a) * 0.5), white)
		leg.rotation_degrees.z = -sin(a) * 10.0
		leg.rotation_degrees.x = cos(a) * 10.0
		craft.add_child(leg)
	# High-gain antenna: mast + shallow dish.
	craft.add_child(_craft_box(0.02, 0.4, 0.02, Vector3(0.35, 0.95, 0.0), white))
	var dish := _craft_cyl(0.18, 0.02, 0.09, 0, Vector3(0.35, 1.16, 0.0), white)
	dish.rotation_degrees.x = 24.0
	craft.add_child(dish)
	# ISRO tricolour on the lander flank.
	var tri := [Color(0.98, 0.53, 0.12), Color(0.96, 0.96, 0.96), Color(0.06, 0.55, 0.22)]
	for bi in tri.size():
		craft.add_child(_craft_box(0.22, 0.04, 0.02, Vector3(0.0, 0.46 - bi * 0.05, 0.51), _solid(tri[bi])))

	# ── Segmented solar wing across the propulsion module ──
	var wing := Node3D.new()
	wing.name = "PropulsionSolarArray"
	wing.position = Vector3(0, 0.15, 0)
	craft.add_child(wing)
	var cells := 4
	var cw := 0.5
	var total := float(cells) * cw
	wing.add_child(_craft_box(total + 0.12, 0.02, 0.06, Vector3(0, 0, 0), frame))
	var x0 := -total * 0.5 + cw * 0.5
	for c in cells:
		var cx := x0 + float(c) * cw
		wing.add_child(_craft_box(cw - 0.04, 0.03, 0.6, Vector3(cx, 0, 0), cell))

func _craft_cyl(top_r: float, bot_r: float, h: float, seg: int, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	if seg > 0:
		cm.radial_segments = seg
	m.mesh = cm
	m.position = pos
	m.material_override = mat
	return m

func _craft_box(sx: float, sy: float, sz: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, sy, sz)
	m.mesh = bm
	m.position = pos
	m.material_override = mat
	return m

func _craft_ring(radius: float, tube: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	tm.rings = 24
	tm.ring_segments = 8
	m.mesh = tm
	m.position = pos
	m.material_override = mat
	return m

func _solid(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.5
	m.roughness = 0.5
	return m

## Bilinear value-noise sample over a seeded grid, used by the MLI foil builder.
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
## wrinkle normal map.  Ported from the lunar orbiter so the transfer craft reads
## as a real foil-wrapped spacecraft instead of a flat-painted gold blob.
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


## A point on the orbital arc: `radial` metres out from the vehicle's altitude
## and `prograde` metres along the direction of travel.  Everything released in
## the space frame has to be positioned through this, or it would sit still in
## the world while the vehicle carried on without it.
func _orbit_point(radial: float, prograde: float) -> Vector3:
	var up_dir := Vector3(0.0, 1.0, 0.0).rotated(Vector3.RIGHT, orbit_angle)
	var fwd := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, orbit_angle)
	return space_center + up_dir * (ORBIT_EARTH_RADIUS_VIS + ORBIT_ALTITUDE_VIS + radial) + fwd * prograde

func _begin_payload_deployment() -> void:
	if not rocket: return
	_show_space_backdrop()
	deployment_origin = rocket.global_position + Vector3(0.0, 2.0, 0.0)
	if payload_craft:
		payload_craft.global_position = deployment_origin
		payload_craft.global_rotation = rocket.global_rotation
		payload_craft.show()
		if GameManager.current_mission.get("id", "") == "moon_scout":
			GameManager.simulation_state["lunar_stack_released"] = true
	# The launch vehicle has reached orbit; replace it with a white second stage
	# still wearing its open payload fairing, so separation is the Chandrayaan
	# reveal — the gold stack sliding out of the shroud — not a bare cylinder.
	rocket.hide()
	upper_stage_visual = Node3D.new()
	upper_stage_visual.name = "CoastingUpperStage"
	# Build the spent upper stage with the SAME primitives, paint and detailing
	# as the launch model (RocketFactory), so it is unmistakably the chosen
	# vehicle's second stage: vehicle-coloured body, black interstage, vacuum
	# engine bell, grid fins on the Falcon family, and an open payload fairing
	# (mouth ~ +4.4) that the gold stack rises out of during deployment.
	RocketFactoryScript.build_upper_stage(upper_stage_visual, flight_id)
	add_child(upper_stage_visual)
	# A brief vacuum flare off the spent stage's own bell: after releasing the
	# payload the upper stage fires once to pitch and back away, so the rocket
	# reads as an active vehicle clearing the deck rather than inert debris.
	var stage_plume := MeshInstance3D.new()
	stage_plume.name = "StagePlume"
	var spm := CylinderMesh.new()
	spm.top_radius = 0.50
	spm.bottom_radius = 0.06
	spm.height = 2.8
	spm.radial_segments = 16
	spm.rings = 6
	stage_plume.mesh = spm
	stage_plume.position = Vector3(0, -6.0, 0)
	var spm_mat := StandardMaterial3D.new()
	spm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spm_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spm_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spm_mat.albedo_color = Color(0.55, 0.75, 1.0, 0.5)
	spm_mat.emission_enabled = true
	spm_mat.emission = Color(0.5, 0.72, 1.0)
	spm_mat.emission_energy_multiplier = 3.4
	stage_plume.material_override = spm_mat
	stage_plume.visible = false
	upper_stage_visual.add_child(stage_plume)
	_update_orbital_camera()

func _update_satellite_deploy(delta: float) -> void:
	# Twenty seconds of unbroken orbital footage: a slow-motion emergence from the
	# fairing, panel deployment, then acquisition. Only afterwards do we hand off.
	var raw: float = clampf(state_timer / 16.0, 0.0, 1.0)
	# A real upper-stage/payload separation is a gentle, near-constant drift: a
	# small spring push, then a slow coast at a few tenths of a metre per second.
	# The old cubic swell surged through the middle and the huge drift distances
	# (payload 22 ahead, stage 30 back) made the two bodies fly apart — which read
	# as a sudden jump. Smoothstep starts and ends at zero velocity and the
	# distances are now small, so the payload eases off the interface and simply
	# keeps drifting away from the stage, the way the real footage looks.
	var release: float = smoothstep(0.0, 1.0, raw)
	if upper_stage_visual:
		upper_stage_visual.global_position = _orbit_point(-release * 1.2, -release * 5.0)
		upper_stage_visual.rotation = Vector3(orbit_angle + deg_to_rad(90.0), 0.0, 0.0)
		upper_stage_visual.rotate_z(delta * 0.05)
		var stage_plume := upper_stage_visual.get_node_or_null("StagePlume") as MeshInstance3D
		if stage_plume:
			# The stage's clear-deck burn: lit for the first beat after release then
			# cut, so the rocket is seen fire away from the payload instead of just
			# sitting there as inert metal.
			var firing := raw > 0.0 and raw < 0.55
			stage_plume.visible = firing
			if firing:
				var sf := 0.85 + 0.15 * sin(state_timer * 24.0)
				stage_plume.scale = Vector3(sf, 1.0, sf)
		# The shroud peels open as two half-shells before the orbiter is allowed
		# clear, so the beat reads as "the head opened and the craft came out of it"
		# rather than a craft appearing beside a closed tube. Once swung apart the
		# halves tumble down and away, exactly like a real fairing jettison.
		var hf := upper_stage_visual.get_node_or_null("FairingHalfF") as Node3D
		var hb := upper_stage_visual.get_node_or_null("FairingHalfB") as Node3D
		var openf := clampf(raw / 0.42, 0.0, 1.0)
		var swing := ease(openf, 0.7) * 1.55
		var drift := maxf(raw - 0.42, 0.0) * 9.0
		if hf:
			hf.rotation.x = swing
			hf.position = Vector3(0, 2.05 - drift * 0.28, drift * 0.7)
		if hb:
			hb.rotation.x = -swing
			hb.position = Vector3(0, 2.05 - drift * 0.28, -drift * 0.7)
	# The stack's own up axis in the world frame (the stage is rotated only about
	# RIGHT), and the prograde direction it drifts along once clear of the shroud.
	var stage_up := Vector3(0.0, 1.0, 0.0).rotated(Vector3.RIGHT, orbit_angle + deg_to_rad(90.0))
	var radial0: Vector3 = Vector3.UP
	var ahead := Vector3(0.0, 0.0, -1.0)
	if upper_stage_visual:
		radial0 = (upper_stage_visual.global_position - space_center).normalized()
		ahead = radial0.cross(Vector3.FORWARD).normalized()
	if payload_craft:
		# Starts nested inside the shroud, then rises out through the opening as the
		# halves swing apart and drifts gently ahead — the real separation beat.
		var shroud_base: Vector3 = (upper_stage_visual.global_position + stage_up * 2.2) \
			if upper_stage_visual else deployment_origin
		payload_craft.global_position = shroud_base + stage_up * (release * 4.6) + ahead * (release * 8.5)
		payload_craft.rotation = Vector3(orbit_angle + deg_to_rad(90.0), 0.0, 0.0)
		payload_craft.rotate_y(delta * 0.22)
		# Only the generic satellite folds its arrays out; the lunar stack is shown
		# fully built (matching the reference), so we don't squash its legs/panels.
		if String(GameManager.current_mission.get("id", "")) != "moon_scout":
			for child in payload_craft.get_children():
				if child is MeshInstance3D and child.position.x != 0.0:
					child.scale.x = lerp(0.08, 1.0, release)
		var plume_grp := payload_craft.get_node_or_null("EnginePlumeGroup") as Node3D
		if plume_grp:
			# Light the engine as soon as the stack has clearly cleared the fairing
			# mouth and keep the pull-away burn lit through the free-flight, so the
			# separation reads as a powered manoeuvre instead of two silent hulls
			# drifting apart. Firing earlier would send the aft plume back into the
			# open shroud, which reads as the rocket being transparent.
			plume_grp.visible = release > 0.30
			if plume_grp.visible:
				var plume := plume_grp.get_node_or_null("EnginePlume") as MeshInstance3D
				if plume:
					var f := 0.9 + 0.12 * sin(state_timer * 22.0)
					plume.scale = Vector3(f, 1.0 + 0.08 * sin(state_timer * 15.0), f)
	if cam_space and payload_craft:
		# Frame the payload CLOSE so the detailed gold stack (engine bell, thruster
		# pods, Vikram bus, legs, antenna, solar wing) actually reads, with the white
		# stage kept just behind it so the gentle separation stays legible. Sitting
		# off to the side along `side` keeps the local tangent as the view axis, so
		# the Earth limb stays low and black space fills the frame.
		var stage_pos: Vector3 = upper_stage_visual.global_position if upper_stage_visual else deployment_origin
		var pay_pos: Vector3 = payload_craft.global_position
		var focus: Vector3 = pay_pos.lerp(stage_pos, 0.28)
		var gap := stage_pos.distance_to(pay_pos)
		var radial := (focus - space_center).normalized()
		var prograde := radial.cross(Vector3.FORWARD).normalized()
		if prograde.length_squared() < 0.1:
			prograde = Vector3(0.0, 0.0, -1.0)
		var side := prograde.cross(radial).normalized()
		var dist := 7.0 + gap * 0.55
		var ang := state_timer * 0.12
		var desired := focus + side * (dist * 0.82) + prograde * (dist * 0.42) \
			+ radial * (dist * 0.20) + side * (dist * 0.10 * sin(ang))
		cam_space.global_position = cam_space.global_position.lerp(desired, min(delta * 2.0, 1.0))
		cam_space.look_at(focus + radial * 0.4, radial)
	if state_timer < 3.5:
		if status_label:
			if GameManager.current_mission.get("id", "") == "moon_scout":
				status_label.text = "Lunar stack separation confirmed — clearing upper stage."
			elif mars_payload:
				status_label.text = "Mars climate lander separated — clearing upper stage."
			else:
				status_label.text = "Payload separation confirmed — clearing upper stage."
	elif state_timer < 10.5:
		if status_label:
			if GameManager.current_mission.get("id", "") == "moon_scout":
				status_label.text = "Propulsion module free-flight — lunar transfer systems active."
			elif mars_payload:
				status_label.text = "Lander free-flight — trans-Mars systems coming online."
			elif GameManager.is_asteroid_mission():
				status_label.text = "Asteroid probe free-flight — autonomous intercept navigation active."
			else:
				status_label.text = "Satellite free-flight — solar arrays deploying."
	else:
		if status_label:
			if GameManager.current_mission.get("id", "") == "moon_scout":
				status_label.text = "Lunar stack acquired — preparing translunar injection."
			elif mars_payload:
				status_label.text = "Earth parking orbit confirmed — preparing trans-Mars injection."
			elif GameManager.is_asteroid_mission():
				status_label.text = "Earth parking orbit confirmed — beginning intercept to 2025-XK7."
			else:
				status_label.text = "Satellite acquired — stable orbit confirmed."
	if state_timer > 20.0:
		_set_state(LaunchState.COMPLETE)

func _create_handoff_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	handoff_fade = ColorRect.new()
	handoff_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	handoff_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handoff_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	layer.add_child(handoff_fade)

## A curved planetary shell for the whole of the ascent.
## The scene cannot be geometrically honest — 20 km of flight is only ~90 units
## of travel here — so instead of a flat plane that always looks like a tabletop,
## the vehicle climbs away from a sphere with a real horizon dip and a lit
## atmospheric limb.  That is what makes Max-Q at 20 km *look* like 20 km.
func _create_horizon_shell() -> void:
	horizon_world = Node3D.new()
	horizon_world.name = "HorizonWorld"
	# The sphere's poles run along its local Y, which would put dead ice over the
	# apex the vehicle climbs away from.  Tilting the body 90° puts an equatorial,
	# continent-bearing band under the rocket, which is what launch footage from
	# altitude actually shows.
	var pivot := Node3D.new()
	pivot.name = "HorizonPivot"
	pivot.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	horizon_world.add_child(pivot)
	horizon_pivot = pivot
	var surface := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = HORIZON_RADIUS
	sphere.height = HORIZON_RADIUS * 2.0
	sphere.radial_segments = 256
	sphere.rings = 128
	surface.mesh = sphere
	var surf_mat := StandardMaterial3D.new()
	var earth_tex := load("res://assets/textures/earth-blue-marble-8k.jpg") as Texture2D
	if earth_tex:
		surf_mat.albedo_texture = earth_tex
		surf_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		surf_mat.albedo_color = Color(0.80, 0.85, 0.94, 1.0)
		# The shell is deliberately a small planet, so a single wrap of a 2048px
		# map would magnify one ocean until it was a flat colour — which is
		# exactly what it looked like.  Tiling it brings continents and coastlines
		# back at a size the camera can actually resolve.
		#
		# Longitude only.  Tiling V as well repeats the map from pole to pole, and
		# the top and bottom rows of an equirectangular Earth map are the ice caps,
		# so a V-scaled copy lays bright white bands of Antarctica straight across
		# the planet — the hard-edged white wedge that kept showing at the limb.
		surf_mat.uv1_scale = Vector3(2.0, 1.0, 1.0)
	else:
		surf_mat.albedo_color = Color(0.13, 0.21, 0.17, 1.0)
	surf_mat.roughness = 0.88
	surf_mat.metallic = 0.0
	surface.material_override = surf_mat
	pivot.add_child(surface)
	horizon_body = surface
	# The limb glow: a hair larger than the surface, unlit and double-sided, so
	# from any altitude the edge of the planet carries a blue atmospheric line.
	var haze := MeshInstance3D.new()
	var haze_sphere := SphereMesh.new()
	haze_sphere.radius = HORIZON_RADIUS * 1.0075
	haze_sphere.height = HORIZON_RADIUS * 2.015
	haze_sphere.radial_segments = 192
	haze_sphere.rings = 96
	haze.mesh = haze_sphere
	var haze_mat := StandardMaterial3D.new()
	haze_mat.albedo_color = Color(0.32, 0.62, 1.0, 0.20)
	haze_mat.emission = Color(0.24, 0.52, 0.98, 1.0)
	haze_mat.emission_enabled = true
	haze_mat.emission_energy_multiplier = 1.15
	haze_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	haze_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	haze_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	haze.material_override = haze_mat
	horizon_world.add_child(haze)
	horizon_haze = haze
	# Apex sits a little under the pad slab so the authored ground plane and the
	# shell never share a surface and flicker at the start of the show.
	horizon_world.position = Vector3(0.0, -(HORIZON_RADIUS + 8.0), 0.0)
	add_child(horizon_world)
	horizon_world.hide()
	_build_cloud_decks()

## One translucent shell per cloud deck, plus the Kármán line.
##
## Each shell is concentric with the planetary surface and sits at the radius the
## vehicle actually reaches at that deck's true altitude, so the rocket passes
## through the weather in the right order instead of the clouds being scenery.
## Everything below about 13 km is where clouds exist at all; above that the
## stratosphere is dry and clear, which is why the climb goes bright and then
## very deliberately empty.
##
## These live in their own node rather than inside `horizon_world`, because the
## horizon shell only takes over at ~0.9 km and the weather has to be there from
## the pad: you can see clouds standing up off a launch complex, and a launch
## that suddenly grows a sky full of cloud decks sixteen seconds in is the kind
## of discontinuity that breaks the whole illusion.
func _build_cloud_decks() -> void:
	atmo_world = Node3D.new()
	atmo_world.name = "AtmosphereShell"
	atmo_world.position = Vector3(0.0, -(HORIZON_RADIUS + 8.0), 0.0)
	add_child(atmo_world)
	# One shader, four materials.  The uniforms are per-material, so each deck can
	# have its own coverage and scale without recompiling anything.
	var cloud_sh := Shader.new()
	cloud_sh.code = CLOUD_SHADER
	for deck: Dictionary in CLOUD_DECKS:
		var alt_km: float = float(deck["alt_km"])
		var radius: float = _ascent_visual_y(alt_km) + HORIZON_RADIUS + 8.0
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		# Fewer rings than the surface shell: these are translucent, heavily
		# overdrawn, and the pattern is resolved by the shader, not the tessellation.
		mesh.radial_segments = 96
		mesh.rings = 48
		var mi := MeshInstance3D.new()
		mi.name = "CloudDeck_%s" % ("%.0f" % (alt_km * 1000.0))
		mi.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = cloud_sh
		mat.set_shader_parameter("cover", float(deck["cover"]))
		mat.set_shader_parameter("freq", float(deck["freq"]))
		mat.set_shader_parameter("opacity", float(deck["opacity"]))
		mat.set_shader_parameter("soft", float(deck["soft"]))
		mat.set_shader_parameter("sun_dir", Vector3(0.45, 0.72, 0.35).normalized())
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		atmo_world.add_child(mi)
		cloud_shells.append(mi)

	# The line itself: a thin, faintly luminous ring at 100 km.  Crossing it is the
	# mission's most quotable moment and the player should be able to *see* it.
	var k_radius: float = _ascent_visual_y(SPACE_ALTITUDE_KM) + HORIZON_RADIUS + 8.0
	var k_mesh := SphereMesh.new()
	k_mesh.radius = k_radius
	k_mesh.height = k_radius * 2.0
	k_mesh.radial_segments = 96
	k_mesh.rings = 48
	karman_shell = MeshInstance3D.new()
	karman_shell.name = "KarmanLine"
	karman_shell.mesh = k_mesh
	var k_mat := ShaderMaterial.new()
	var k_sh := Shader.new()
	k_sh.code = KARMAN_SHADER
	k_mat.shader = k_sh
	k_mat.set_shader_parameter("line_color", Color(0.42, 0.78, 1.0, 1.0))
	karman_shell.material_override = k_mat
	karman_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	atmo_world.add_child(karman_shell)

## Each deck fades out as the vehicle climbs past it, and drifts slowly the whole
## time.
##
## The fade is not decoration.  The decks are concentric shells, so once the
## vehicle is above them their silhouette stops reading as "a cloud layer" and
## becomes a hard white wedge shearing across the frame — the same artefact the
## old flat ground plane used to produce.  Real weather behaves the same way: at
## thirty kilometres the troposphere is a thin bright band at the limb, not
## objects you can pick out, so fading them out is the honest presentation.
##
## The drift matters for a different reason.  The cloud pattern is sampled from
## world position to avoid the sphere's UV seam, which means it is anchored in
## space rather than to the mesh — without drift the weather is a frozen texture
## and the ascent loses the sense that the vehicle is moving through something.
func _update_cloud_fade(delta: float) -> void:
	atmo_drift += delta * 0.6
	for i in cloud_shells.size():
		var mi: MeshInstance3D = cloud_shells[i]
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		var deck_alt: float = float(CLOUD_DECKS[i]["alt_km"])
		mat.set_shader_parameter("fade", maxf(1.0 - smoothstep(3.0, 18.0, altitude_km - deck_alt), 0.0))
		mat.set_shader_parameter("drift", atmo_drift * (0.5 + float(i) * 0.35))
	# The landing-site cumulus drifts on the same clock, so the return shot has
	# live weather over the pad instead of a frozen texture.  Empty during the
	# ascent, so this only costs anything while the recovery rig is up.
	for cluster in site_clouds:
		if cluster == null or not is_instance_valid(cluster):
			continue
		var pp := cluster.position
		pp.x += delta * 0.7
		if pp.x > 16.0:
			pp.x = -16.0
		cluster.position = pp

func _show_space_backdrop() -> void:
	if space_earth: return
	# The planet is placed at the *space-frame centre*, not pinned behind the
	# vehicle.  That is the whole trick: the vehicle arcs around a fixed globe
	# while a star shell that never translates drifts past the camera, so the
	# player sees genuine orbital motion instead of a still frame.
	var centre: Vector3 = space_center if in_space_frame else (
		rocket.global_position - Vector3(0.0, ORBIT_EARTH_RADIUS_VIS + ORBIT_ALTITUDE_VIS, 0.0) if rocket
		else Vector3(0.0, 400.0, 0.0))
	space_center = centre
	space_earth = Node3D.new()
	space_earth.name = "EarthHorizon"
	var earth_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = ORBIT_EARTH_RADIUS_VIS
	sphere.height = ORBIT_EARTH_RADIUS_VIS * 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	earth_mesh.mesh = sphere
	var earth_mat := StandardMaterial3D.new()
	var earth_texture := load("res://assets/textures/earth-blue-marble-8k.jpg") as Texture2D
	if earth_texture:
		earth_mat.albedo_texture = earth_texture
		earth_mat.albedo_color = Color(0.86, 0.90, 1.0, 1.0)
	else:
		earth_mat.albedo_color = Color(0.012, 0.09, 0.28, 1.0)
	earth_mat.roughness = 0.62
	earth_mat.metallic = 0.0
	# Kill the sun's specular lobe on the planet.  A mid roughness plus the
	# default Schlick specular throws a broad white highlight across the lit
	# disc, and the scene glow blooms it into the blown-out white wash that used
	# to swallow the whole orbital-vehicle shot.  An Earth seen from orbit is
	# diffuse ocean and cloud, not a mirror.
	earth_mat.metallic_specular = 0.0
	earth_mesh.material_override = earth_mat
	space_earth.add_child(earth_mesh)
	earth_body = earth_mesh

	# A scattering rim is what separates "sphere in a black void" from a planet
	# with an atmosphere, and it is the brightest motion cue on the limb.
	var atmosphere := MeshInstance3D.new()
	var atmosphere_sphere := SphereMesh.new()
	atmosphere_sphere.radius = ORBIT_EARTH_RADIUS_VIS * 1.012
	atmosphere_sphere.height = ORBIT_EARTH_RADIUS_VIS * 2.024
	atmosphere_sphere.radial_segments = 96
	atmosphere_sphere.rings = 48
	atmosphere.mesh = atmosphere_sphere
	# A real atmosphere is not a painted-on blue disc — the scattering is thin and
	# only lights up where the line of sight grazes the limb.  A fresnel rim does
	# exactly that: transparent straight down onto the planet, a soft glow only at
	# the edge, so the previous hard cyan band across the whole disc is gone.
	var atmo_shader := Shader.new()
	atmo_shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;
uniform vec3 rim_color : source_color = vec3(0.34, 0.58, 1.0);
uniform float power = 3.4;
uniform float intensity = 0.9;
void fragment() {
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(fres, power);
	ALBEDO = rim_color * intensity;
	ALPHA = rim;
}
"""
	var atmo_mat := ShaderMaterial.new()
	atmo_mat.shader = atmo_shader
	atmosphere.material_override = atmo_mat
	space_earth.add_child(atmosphere)
	earth_atmo = atmosphere

	# A cloud deck is the single strongest cue that this is Earth and not a
	# painted ball.  Sampled from the sphere NORMAL (not UV) so it is seamless
	# across the pole, semi-transparent, and lit by the same sun as the surface
	# — so the clouds go dark across the night terminator instead of glowing.
	var clouds := MeshInstance3D.new()
	clouds.name = "EarthClouds"
	var cloud_sphere := SphereMesh.new()
	cloud_sphere.radius = ORBIT_EARTH_RADIUS_VIS * 1.004
	cloud_sphere.height = ORBIT_EARTH_RADIUS_VIS * 2.008
	cloud_sphere.radial_segments = 64
	cloud_sphere.rings = 32
	clouds.mesh = cloud_sphere
	var cloud_shader := Shader.new()
	cloud_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never;
uniform float coverage = 0.5;
varying vec3 vdir;
float chash(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float cnoise(vec3 x){
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(chash(i+vec3(0,0,0)), chash(i+vec3(1,0,0)), f.x),
		mix(chash(i+vec3(0,1,0)), chash(i+vec3(1,1,0)), f.x), f.y),
		mix(mix(chash(i+vec3(0,0,1)), chash(i+vec3(1,0,1)), f.x),
		mix(chash(i+vec3(0,1,1)), chash(i+vec3(1,1,1)), f.x), f.y), f.z);
}
float cfbm(vec3 p){ float a = 0.5; float r = 0.0; for (int i = 0; i < 4; i++){ r += a * cnoise(p); p = p * 2.03 + vec3(1.7); a *= 0.5; } return r; }
void vertex(){ vdir = NORMAL; }
void fragment(){
	vec3 p = vdir * 7.5 + vec3(TIME * 0.015, 0.0, TIME * 0.008);
	float c = cfbm(p);
	float cloud = smoothstep(coverage - 0.06, coverage + 0.22, c);
	ALBEDO = vec3(1.0, 1.0, 1.0);
	ROUGHNESS = 0.95;
	ALPHA = cloud * 0.9;
}
"""
	var cloud_mat := ShaderMaterial.new()
	cloud_mat.shader = cloud_shader
	clouds.material_override = cloud_mat
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	space_earth.add_child(clouds)
	space_clouds = clouds
	add_child(space_earth)
	space_earth.global_position = centre
	# Earthshine: a soft bluish fill rising from the planet so the night side of
	# the stack is not pure black. Real orbital footage is lit by the sun on one
	# face and a cool glow bounced off the Earth below on the other; without it a
	# metallic craft against a black sky loses all its shadow-side form.
	if space_fill_light == null:
		space_fill_light = DirectionalLight3D.new()
		space_fill_light.name = "EarthShineFill"
		space_fill_light.light_color = Color(0.36, 0.52, 0.85)
		space_fill_light.light_energy = 0.55
		space_fill_light.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		space_fill_light.shadow_enabled = false
		add_child(space_fill_light)

	# Stars live on a shell hundreds of times larger than the planet and are
	# parented to the world, not to the vehicle, so they hold still while
	# everything else moves.  That contrast is what reads as "in orbit".
	space_stars = Node3D.new()
	space_stars.name = "LaunchStarfield"
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 1.6
	star_mesh.height = 3.2
	star_mesh.radial_segments = 6
	star_mesh.rings = 4
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = Color(0.9, 0.94, 1.0, 1.0)
	star_mat.emission_enabled = true
	star_mat.emission = Color(0.85, 0.92, 1.0, 1.0)
	star_mat.emission_energy_multiplier = 1.2
	star_mesh.material = star_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261102
	for i in 520:
		var star := MeshInstance3D.new()
		star.mesh = star_mesh
		# Uniform directions on a large sphere shell.
		var u: float = rng.randf_range(-1.0, 1.0)
		var phi: float = rng.randf_range(0.0, TAU)
		var s: float = sqrt(maxf(0.0, 1.0 - u * u))
		var dir := Vector3(s * cos(phi), u, s * sin(phi))
		star.position = dir * rng.randf_range(2600.0, 3400.0)
		star.scale = Vector3.ONE * rng.randf_range(0.4, 2.2)
		space_stars.add_child(star)
	add_child(space_stars)
	space_stars.global_position = centre

	# Sunlight in space is unfiltered: hard, white and strong. The warm pad
	# grading has to go, or the planet looks like it is lit at sunset.
	var sun := get_node_or_null("WorldLight") as DirectionalLight3D
	if sun:
		sun.light_color = Color(1.0, 0.97, 0.92)
		sun.light_energy = 1.75
		sun.rotation_degrees = Vector3(-24.0, 55.0, 0.0)
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill:
		fill.light_energy = 0.05
	if world_env and world_env.environment:
		world_env.environment.ambient_light_color = Color(0.55, 0.62, 0.78)
		world_env.environment.ambient_light_energy = 0.22

# ─── HUD ──────────────────────────────────────────────────────────────────────
func _update_hud() -> void:
	# The flight-path angle is reported from the *velocity vector*, so if the
	# nose and the track ever diverge the player can see it, exactly like a real
	# console.  With the guided turn they stay within a couple of degrees.
	var fpa: float = rad_to_deg(atan2(vertical_velocity_ms, maxf(horizontal_velocity_ms, 0.1)))
	if met_label:
		var whole: int = int(met_seconds)
		if whole != met_seconds_shown:
			met_seconds_shown = whole
			met_label.text = "T+ %02d:%02d:%02d" % [
				floori(whole / 3600.0), floori((whole % 3600) / 60.0), whole % 60]
	if warp_label:
		warp_label.text = ("SIM ×%.1f — mission clock is real time" % sim_speed) if sim_speed > 1.05 else "REAL TIME"
		if booster_cam_window > 0:
			# Say what the two pictures are, because the left one is of a
			# different object than the telemetry column beside it — and both are
			# running on the one mission clock printed above them.
			warp_label.text = "SPLIT · TWO VEHICLES, ONE CLOCK · " + warp_label.text
			warp_label.add_theme_color_override("font_color", UI_GREEN)
		else:
			warp_label.add_theme_color_override("font_color", UI_DIM)
	if altitude_label: altitude_label.text = "%.1f km" % altitude_km
	if velocity_label: velocity_label.text = "%.0f km/h  (%.0f m/s)" % [velocity_ms * 3.6, velocity_ms]
	if acceleration_label: acceleration_label.text = "%.2f g" % axial_g
	if t_vspd_label: t_vspd_label.text = "%.0f m/s" % vertical_velocity_ms
	if t_hspd_label: t_hspd_label.text = "%.0f m/s" % horizontal_velocity_ms
	if orbit_estimate_label:
		# A perigee below the surface is not a number worth showing; it means
		# "you will come back down", so say that instead.
		if periapsis_km < -500.0:
			orbit_estimate_label.text = "SUBORBITAL  |  Ap %.0f km" % maxf(apoapsis_km, 0.0)
		else:
			var ap_text: String = "escape" if apoapsis_km > 99000.0 else "%.0f km" % maxf(apoapsis_km, 0.0)
			orbit_estimate_label.text = "Ap %s  |  Pe %.0f km" % [ap_text, periapsis_km]
	if t_fpa_label: t_fpa_label.text = "%.1f°" % fpa
	if t_downrange_label: t_downrange_label.text = "%.0f km" % downrange_km
	if t_path_label:
		t_path_label.text = "%.0f km" % path_distance_km
	if atmo_label:
		atmo_label.text = _atmosphere_line()
	if stage_label:
		# The badge is the *flight phase*, not a restatement of the state enum: the
		# profile (liftoff → gravity turn → upper atmosphere → space ascent →
		# insertion → deployment) is what tells the player where they are in a
		# launch, and it is derived from the same altitude the HUD is showing.
		var ph: Dictionary = _flight_phase()
		stage_label.text = String(ph["name"])
	if fuel_caption_label:
		fuel_caption_label.text = "S1 Prop" if stage_number == 1 else "S2 Prop"
	if fuel_bar:
		fuel_bar.value = fuel_pct
		_color_bar(fuel_bar, (100.0 - fuel_pct) / 100.0)
	if fuel_pct_label: fuel_pct_label.text = "%.0f%%" % fuel_pct
	if throttle_bar: throttle_bar.value = throttle
	if throttle_pct_label: throttle_pct_label.text = "%.0f%%" % throttle
	if throttle_label:
		# Not a second copy of the throttle percentage — a statement of *why* the
		# engines are where they are, derived from the same numbers the
		# integrator used this frame so it cannot disagree with the vehicle.
		throttle_label.text = _engine_state_line()
	_update_stepper()

## The current phase of the flight profile.  Altitude drives the climb phases;
## the state machine drives the two that are events rather than heights.  Both
## the phase badge and the phase-change callout read from here, so the words on
## screen cannot disagree with the trajectory the integrator produced.
func _flight_phase() -> Dictionary:
	if state == LaunchState.PRE_LAUNCH or state == LaunchState.COUNTDOWN:
		return {"name": "STANDING BY", "line": "Vehicle safed, engines at hold-down."}
	if state == LaunchState.ORBITAL_INSERT:
		return {"name": "ORBIT INSERTION",
			"line": "Upper stage closing the ellipse into a circular orbit at %.0f km." % target_orbit_km}
	if state == LaunchState.SATELLITE_DEPLOY:
		return {"name": "SATELLITE DEPLOY",
			"line": "Climate Sentinel leaving the adapter. Solar arrays unfold after release."}
	if state == LaunchState.COMPLETE:
		return {"name": "OPERATIONAL",
			"line": "Sentinel is powering its instruments and beginning the climate record."}
	var best: Dictionary = FLIGHT_PHASES[0]
	for i in FLIGHT_PHASES.size():
		# The profile puts the turn at ten kilometres, but the badge has to agree
		# with what the player can actually see: until the nose comes off vertical
		# the vehicle is still in its vertical rise, and calling it a gravity turn
		# then would be exactly the telemetry-versus-motion mismatch that makes a
		# launch feel fake.
		if i == 1 and attitude_deg > 86.0:
			continue
		if altitude_km >= float(FLIGHT_PHASES[i]["alt_km"]):
			best = FLIGHT_PHASES[i]
	return best

## Which layer the vehicle is in and how much air is still under it.  The
## density fraction is the same exponential model the drag term uses, so this is
## the number the physics actually integrated, not a caption painted over it.
func _atmosphere_line() -> String:
	if altitude_km >= SPACE_ALTITUDE_KM:
		return "SPACE · KÁRMÁN LINE"
	var layer_name: String = "THERMOSPHERE"
	for layer: Dictionary in ATMO_LAYERS:
		if altitude_km < float(layer["top_km"]):
			layer_name = String(layer["name"])
			break
	var frac: float = exp(-altitude_km / scale_height_km)
	# Kept short on purpose: this sits in the telemetry column, and a value that
	# gets clipped by the panel is a value the player cannot read.
	var frac_text: String = "%.0f%%" % (frac * 100.0)
	if frac < 0.1:
		frac_text = "%.2f%%" % (frac * 100.0)
	elif frac < 0.5:
		frac_text = "%.1f%%" % (frac * 100.0)
	return "%s · %s air" % [layer_name, frac_text]

## Cloud decks and layer crossings, announced as the vehicle reaches them.  The
## flight-phase badge is allowed to announce itself too, but only on the frame
## the phase actually changes, and never on top of a layer crossing that already
## said the same thing a metre earlier.
func _atmosphere_events() -> void:
	var beat_fired: bool = false
	while layer_beat_idx < LAYER_BEATS.size() \
			and altitude_km >= float(LAYER_BEATS[layer_beat_idx]["alt_km"]):
		var beat: Dictionary = LAYER_BEATS[layer_beat_idx]
		layer_beat_idx += 1
		_show_callout(String(beat["text"]), 3.2)
		if status_label:
			status_label.text = String(beat["line"])
		_play_cue(620.0, 0.09)
		beat_fired = true
	var phase: Dictionary = _flight_phase()
	var pname: String = String(phase["name"])
	if pname == flight_phase_name:
		return
	var previous: String = flight_phase_name
	flight_phase_name = pname
	# Nothing worth announcing before the vehicle is clear of the tower, and the
	# liftoff itself already has its own event further up the file.  The move into
	# space is the same deal: the Kármán line beat says it properly, and a second
	# caption on top of it would only step on the one that matters.
	if previous == "" or beat_fired or altitude_km < 2.0: return
	if pname == "LIFTOFF" or pname == "SPACE ASCENT": return
	_show_callout("PHASE — " + pname, 2.6)
	if status_label:
		status_label.text = String(phase["line"])
	_play_cue(480.0, 0.08)

## Which flight-rule is currently setting the engine thrust, in plain language.
func _engine_state_line() -> String:
	if state == LaunchState.PRE_LAUNCH or state == LaunchState.COUNTDOWN:
		return "Engines at hold-down clamp"
	if throttle <= 0.5:
		if insertion_phase == InsertionPhase.COAST_TO_APOGEE:
			return "Coasting uphill to apogee — %.0f km to go" % maxf(0.0, apoapsis_km - altitude_km)
		return "Engines shut down — flying the trajectory already built"
	if altitude_km < 45.0 and altitude_km > 6.0 and dynamic_pressure_kpa > 12.0:
		return "Cut to %.0f%% for aerodynamic load, %.1f kPa" % [throttle, dynamic_pressure_kpa]
	if axial_g >= MAX_AXIAL_G - 0.08:
		return "Held at the %.1f g structural limit, %.0f%%" % [MAX_AXIAL_G, throttle]
	return "Unrestricted at %.0f%%, %.0f kN" % [throttle, thrust_kN * throttle / 100.0]

func _color_bar(bar: ProgressBar, frac: float) -> void:
	bar.add_theme_color_override("font_color",
		Color("#FFFFFF") if frac < 0.5 else (Color("#D9D9D9") if frac < 0.8 else Color("#777777")))

# ─── Buttons ──────────────────────────────────────────────────────────────────
func _on_launch_pressed() -> void: _set_state(LaunchState.COUNTDOWN)
func _on_abort_pressed() -> void:
	get_tree().paused = false
	GameManager.go_to_builder()
func _on_auto_throttle_toggled(v: bool) -> void:
	auto_throttle = v
	if not v and status_label:
		status_label.text = "Manual throttle — use throttle_up/down keys."

# ─── Launch Control Overlay (themed UI, built in code) ────────────────────────
func _rebuild_launch_overlay() -> void:
	var ui := get_node_or_null("UI") as Control
	if ui == null:
		var cl := CanvasLayer.new(); cl.layer = 10; add_child(cl)
		ui = Control.new()
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cl.add_child(ui)
	var old_hud := get_node_or_null("UI/HUD")
	if old_hud: old_hud.hide()
	var old_cp := get_node_or_null("UI/ControlPanel")
	if old_cp: old_cp.hide()

	_build_split_overlay(ui)
	_build_nav_bar(ui)
	_build_left_panel(ui)
	_build_right_panel(ui)
	_build_bottom_bar(ui)
	_build_recovery_panel(ui)

	countdown_label = _mk_label("AWAITING LAUNCH", 30, UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	countdown_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	countdown_label.position = Vector2(-260, 74)
	countdown_label.size = Vector2(520, 44)
	ui.add_child(countdown_label)

	# Mission elapsed time and the current compression factor.  Showing the warp
	# honestly is what lets a 9-minute flight be playable without the numbers
	# feeling invented.
	met_label = _mk_label("T+ 00:00:00", 17, UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	met_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	met_label.position = Vector2(-160, 118)
	met_label.size = Vector2(320, 24)
	ui.add_child(met_label)
	warp_label = _mk_label("", 12, UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	warp_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	warp_label.position = Vector2(-160, 142)
	warp_label.size = Vector2(320, 20)
	ui.add_child(warp_label)

	_populate_mission_info()

func _mk_label(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# Small glyph icon (Unicode, no texture assets needed) tinted like the mockup's row icons.
func _mk_icon(glyph: String, size: int = 13, color: Color = UI_ACCENT) -> Label:
	var l := _mk_label(glyph, size, color)
	l.custom_minimum_size = Vector2(18, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _anchor(c: Control, a_l: float, a_t: float, a_r: float, a_b: float, o_l: float, o_t: float, o_r: float, o_b: float) -> void:
	c.anchor_left = a_l; c.anchor_top = a_t; c.anchor_right = a_r; c.anchor_bottom = a_b
	c.offset_left = o_l; c.offset_top = o_t; c.offset_right = o_r; c.offset_bottom = o_b

func _sb_glass() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UI_BG
	s.border_color = UI_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 12; s.content_margin_bottom = 12
	s.shadow_size = 10; s.shadow_color = Color(0, 0, 0, 0.55)
	return s

func _glass(title: String) -> Dictionary:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb_glass())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if title != "":
		v.add_child(_mk_label(title, 18, UI_ACCENT))
		v.add_child(HSeparator.new())
	return {"panel": p, "box": v}

func _build_nav_bar(ui: Control) -> void:
	var bar := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.039, 0.039, 0.039, 0.92)
	s.border_color = UI_BORDER
	s.set_border_width_all(0); s.border_width_bottom = 1
	s.content_margin_left = 18; s.content_margin_right = 18
	_anchor(bar, 0, 0, 1, 0, 0, 0, 0, 58)
	bar.add_theme_stylebox_override("panel", s)
	ui.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	row.add_child(_mk_label("MISSION ARCHITECT", 20, UI_TEXT))
	row.add_child(_mk_label("Beyond Earth", 13, UI_DIM))
	row.add_child(_spacer())
	for tab in ["Design", "Validate", "Launch"]:
		var b := _nav_tab(tab, tab == "Launch")
		if tab == "Design" or tab == "Validate":
			b.text = tab + "  ✓"
			b.add_theme_color_override("font_color", UI_DIM)
			b.pressed.connect(func() -> void: GameManager.go_to_builder())
		row.add_child(b)
	row.add_child(_spacer())
	for ic in ["CAM", "SET", "INFO"]:
		var ib := Button.new(); ib.text = ic; ib.flat = true
		ib.add_theme_color_override("font_color", UI_DIM)
		ib.add_theme_color_override("font_hover_color", UI_TEXT)
		row.add_child(ib)

func _nav_tab(text: String, active: bool) -> Button:
	var b := Button.new(); b.text = text; b.flat = not active
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color("#FFFFFF") if active else Color(0, 0, 0, 0)
	ns.set_corner_radius_all(2)
	ns.content_margin_left = 12; ns.content_margin_right = 12
	ns.content_margin_top = 6; ns.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", ns)
	if active:
		b.add_theme_color_override("font_color", Color("#000000"))
		b.add_theme_color_override("font_hover_color", Color("#000000"))
		b.add_theme_color_override("font_pressed_color", Color("#000000"))
	else:
		b.add_theme_color_override("font_color", UI_DIM)
		b.add_theme_color_override("font_hover_color", UI_TEXT)
	b.add_theme_font_size_override("font_size", 15)
	return b

func _info_row(v: VBoxContainer, caption: String) -> Label:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
	var c := _mk_label(caption + ":", 14, UI_DIM)
	var val := _mk_label("—", 14, UI_TEXT)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c); h.add_child(val); v.add_child(h)
	return val

func _build_left_panel(ui: Control) -> void:
	var d := _glass("LAUNCH CONTROL")
	var p: PanelContainer = d["panel"]; var v: VBoxContainer = d["box"]
	_anchor(p, 0, 0, 0, 0, 16, 128, 336, 520)
	left_panel = p
	ui.add_child(p)
	mission_name_label = _info_row(v, "Mission")
	vehicle_name_label = _info_row(v, "Vehicle")
	target_name_label  = _info_row(v, "Target")
	insertion_info_label = _info_row(v, "Insertion")
	v.add_child(HSeparator.new())
	v.add_child(_mk_label("MISSION PHASE", 12, UI_DIM))
	stage_label = _mk_label("Pre-Launch", 16, UI_TEXT)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chip := PanelContainer.new()
	var cs := _sb_glass(); cs.bg_color = UI_BG_SOFT; cs.border_color = UI_ACCENT
	cs.shadow_size = 0; chip.add_theme_stylebox_override("panel", cs)
	chip.add_child(stage_label); v.add_child(chip)
	var ph_head := HBoxContainer.new()
	var ph_cap := _mk_label("PHASE PROGRESS", 12, UI_DIM)
	ph_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph_head.add_child(ph_cap)
	step_counter_label = _mk_label("0 / 5", 12, UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	ph_head.add_child(step_counter_label)
	v.add_child(ph_head)
	_build_stepper(v)
	status_label = _mk_label("All systems nominal. Press LAUNCH.", 13, UI_DIM)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(status_label)

func _build_stepper(parent: Control) -> void:
	step_dots.clear(); step_labels.clear()
	var names := ["Pre-Launch", "Liftoff", "Max-Q", "Staging", "Orbit"]
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	for i in range(5):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(dot)
		var lbl := _mk_label(names[i], 10, UI_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lbl)
		row.add_child(cell)
		step_dots.append(dot); step_labels.append(lbl)
	_update_stepper()

func _phase_index() -> int:
	match state:
		LaunchState.PRE_LAUNCH, LaunchState.COUNTDOWN: return 0
		LaunchState.LIFTOFF:      return 1
		LaunchState.MAX_Q:        return 2
		LaunchState.STAGE_SEP, LaunchState.FAIRING_SEP: return 3
		_: return 4

func _update_stepper() -> void:
	var cur := _phase_index()
	if step_counter_label: step_counter_label.text = "%d / 5" % cur
	for i in range(step_dots.size()):
		var s := StyleBoxFlat.new(); s.set_corner_radius_all(7); s.set_border_width_all(2)
		if i < cur:
			s.bg_color = Color("#333333"); s.border_color = Color("#B3B3B3")
		elif i == cur:
			s.bg_color = Color("#FFFFFF"); s.border_color = Color("#FFFFFF")
		else:
			s.bg_color = Color("#202020"); s.border_color = UI_BORDER
		step_dots[i].add_theme_stylebox_override("panel", s)
		step_labels[i].add_theme_color_override("font_color", UI_TEXT if i <= cur else Color("#777777"))

func _tele_row(v: VBoxContainer, caption: String, icon: String = "") -> Label:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8)
	if icon != "":
		h.add_child(_mk_icon(icon))
	var c := _mk_label(caption, 13, UI_DIM); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := _mk_label("—", 14, UI_TEXT); val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(c); h.add_child(val); v.add_child(h)
	return val

func _make_bar(color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 14)
	pb.min_value = 0; pb.max_value = 100; pb.show_percentage = false
	var bg := StyleBoxFlat.new(); bg.bg_color = Color("#202020"); bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new(); fg.bg_color = color; fg.set_corner_radius_all(2)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb

func _bar_row(v: VBoxContainer, icon: String, caption: String, color: Color) -> Dictionary:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 8)
	h.add_child(_mk_icon(icon))
	var c := _mk_label(caption, 12, UI_DIM)
	c.custom_minimum_size = Vector2(64, 0)
	h.add_child(c)
	var pb := _make_bar(color)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.custom_minimum_size = Vector2(0, 14)
	h.add_child(pb)
	var pct := _mk_label("0%", 12, UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	pct.custom_minimum_size = Vector2(40, 0)
	h.add_child(pct)
	v.add_child(h)
	return {"bar": pb, "pct": pct, "cap": c}

func _build_right_panel(ui: Control) -> void:
	var d := _glass("LAUNCH TELEMETRY")
	var p: PanelContainer = d["panel"]; var v: VBoxContainer = d["box"]
	_anchor(p, 1, 0, 1, 0, -344, 128, -16, 520)
	ui.add_child(p)
	altitude_label = _tele_row(v, "Altitude", "▲")
	velocity_label = _tele_row(v, "Speed", "●")
	acceleration_label = _tele_row(v, "Acceleration", "⇈")
	t_vspd_label = _tele_row(v, "Vertical Speed", "↑")
	t_hspd_label = _tele_row(v, "Horizontal Speed", "→")
	orbit_estimate_label = _tele_row(v, "Trajectory", "◐")
	t_fpa_label = _tele_row(v, "Flight Path Angle", "∠")
	t_downrange_label = _tele_row(v, "Downrange", "⇥")
	t_path_label = _tele_row(v, "Distance Flown", "↗")
	atmo_label = _tele_row(v, "Atmosphere", "≈")
	v.add_child(HSeparator.new())
	var fuel_row := _bar_row(v, "◆", "S1 Prop", UI_GREEN)
	fuel_bar = fuel_row["bar"] as ProgressBar
	fuel_pct_label = fuel_row["pct"] as Label
	fuel_caption_label = fuel_row["cap"] as Label
	var thr_row := _bar_row(v, "≣", "Throttle", UI_ACCENT)
	throttle_bar = thr_row["bar"] as ProgressBar
	throttle_pct_label = thr_row["pct"] as Label
	throttle_label = _mk_label("Engines at hold-down clamp", 12, UI_DIM); v.add_child(throttle_label)
	# Numeric launch telemetry is rewritten every frame, so it carries the
	# MISSIONFORGE live-value accent; captions, stage names and chrome stay
	# neutral so the accent still means "this number is changing".
	for lbl in [altitude_label, velocity_label, acceleration_label,
			t_vspd_label, t_hspd_label, orbit_estimate_label, t_fpa_label,
			t_downrange_label, t_path_label, atmo_label,
			fuel_pct_label, throttle_pct_label, met_label,
			step_counter_label]:
		if lbl:
			MissionForge.live(lbl)

func _big_button(text: String, color: Color, icon: String = "") -> Button:
	var b := Button.new()
	if icon != "":
		b.text = icon + "   " + text
	else:
		b.text = text
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color("#111111")
	ns.border_color = Color("#333333"); ns.set_border_width_all(1); ns.set_corner_radius_all(3)
	ns.content_margin_left = 16; ns.content_margin_right = 16
	ns.content_margin_top = 10; ns.content_margin_bottom = 10
	var hs := ns.duplicate() as StyleBoxFlat
	hs.bg_color = Color("#202020"); hs.border_color = Color("#B3B3B3")
	b.add_theme_stylebox_override("normal", ns)
	b.add_theme_stylebox_override("hover", hs)
	b.add_theme_stylebox_override("pressed", MissionForge.flat(Color("#FFFFFF"), Color("#FFFFFF"), 0, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", MissionForge.flat(Color("#0A0A0A"), Color("#333333"), 1, 3))
	# `color` still decides the label brightness (white for actions, grey for abort).
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	b.add_theme_color_override("font_pressed_color", Color("#000000"))
	b.add_theme_color_override("font_disabled_color", Color("#777777"))
	b.add_theme_font_size_override("font_size", 20)
	return b

func _mini_arrow(ch: String) -> Button:
	var b := Button.new(); b.text = ch; b.flat = true
	b.add_theme_color_override("font_color", UI_ACCENT)
	b.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(26, 46)
	return b

func _cam_thumb(name: String, preview: Texture2D = null) -> Button:
	var b := Button.new(); b.text = ""; b.toggle_mode = true
	b.custom_minimum_size = Vector2(96, 64)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 2)
	b.add_child(stack)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(0, 34)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preview != null: tr.texture = preview
	stack.add_child(tr)
	var cap := _mk_label(name, 10, UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(cap)
	var ns := StyleBoxFlat.new(); ns.bg_color = Color(0.039, 0.039, 0.039, 0.72)
	ns.border_color = UI_BORDER; ns.set_border_width_all(1); ns.set_corner_radius_all(3)
	var ts := ns.duplicate() as StyleBoxFlat; ts.border_color = UI_ACCENT; ts.set_border_width_all(1)
	ts.bg_color = Color(0.125, 0.125, 0.125, 0.92)
	b.add_theme_stylebox_override("normal", ns)
	b.add_theme_stylebox_override("hover", ts)
	b.add_theme_stylebox_override("pressed", ts)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UI_TEXT)
	b.add_theme_font_size_override("font_size", 12)
	return b

func _build_bottom_bar(ui: Control) -> void:
	var bar := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.039, 0.039, 0.039, 0.92); s.border_color = UI_BORDER
	s.set_border_width_all(0); s.border_width_top = 1
	s.content_margin_left = 18; s.content_margin_right = 18
	s.content_margin_top = 10; s.content_margin_bottom = 10
	_anchor(bar, 0, 1, 1, 1, 0, -112, 0, -8)
	bar.add_theme_stylebox_override("panel", s)
	ui.add_child(bar)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	launch_btn = _big_button("LAUNCH", Color("#FFFFFF"), "▲")
	MissionForge.style_button(launch_btn, true)
	launch_btn.custom_minimum_size = Vector2(170, 56)
	launch_btn.pressed.connect(_on_launch_pressed)
	row.add_child(launch_btn)
	# The SPEED lever was removed at the player's request; the sim runs at Normal.
	var cb := CheckBox.new(); cb.text = "Auto Throttle"; cb.button_pressed = true
	cb.add_theme_color_override("font_color", UI_TEXT)
	cb.add_theme_color_override("font_hover_color", Color("#FFFFFF"))
	cb.add_theme_color_override("font_pressed_color", Color("#FFFFFF"))
	cb.toggled.connect(_on_auto_throttle_toggled)
	row.add_child(cb)
	# The player's only flight-adjacent control: a warp selector, cycling
	# 1 → 2 → 4 → 8 → 16 → 32.  Nothing in the simulation runs faster than
	# this button says it does.
	warp_btn = _big_button("WARP ×1", UI_ACCENT)
	warp_btn.custom_minimum_size = Vector2(140, 56)
	warp_btn.pressed.connect(func(): _set_warp_idx((player_warp_idx + 1) % WARP_STEPS.size()))
	row.add_child(warp_btn)
	_set_warp_idx(player_warp_idx)
	row.add_child(_spacer())
	_build_cam_selector(row)
	row.add_child(_spacer())
	abort_btn = _big_button("ABORT", UI_RED, "✕")
	abort_btn.custom_minimum_size = Vector2(150, 56)
	abort_btn.pressed.connect(_on_abort_pressed)
	row.add_child(abort_btn)

# Tiny procedural "photo" for each camera view (mockup-style thumbnail, no assets needed).
func _cam_preview(mode: CamMode) -> Texture2D:
	var w := 96; var h := 34
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sunset_top := Color(0.16, 0.24, 0.48)
	var sunset_mid := Color(0.93, 0.55, 0.32)
	var ground := Color(0.28, 0.20, 0.18)
	var white := Color(0.92, 0.94, 0.96)
	var steel := Color(0.45, 0.50, 0.56)
	for y in h:
		for x in w:
			var c := Color(0.03, 0.06, 0.12)
			var t := float(y) / float(h)
			match mode:
				CamMode.PAD:
					c = sunset_top.lerp(sunset_mid, clampf(t * 1.6, 0.0, 1.0)) if y < h - 7 else ground
					if absf(float(x) - 48.0) < 3.0 and y > 8 and y < h - 6: c = white
					if x >= 30 and x <= 34 and y > 12: c = steel
				CamMode.ENGINE:
					c = Color(0.10, 0.12, 0.16).lerp(Color(0.02, 0.03, 0.05), t)
					if x > 34 and x < 62 and y > 6:
						if y < 18: c = steel
						else: c = Color(1.0, 0.55, 0.18).lerp(Color(1.0, 0.85, 0.4), clampf((y - 18) / 14.0, 0.0, 1.0))
				CamMode.TOWER:
					c = sunset_top.lerp(sunset_mid, clampf(t * 1.4, 0.0, 1.0))
					if x >= 40 and x <= 58:
						if (x + y) % 6 < 2 or x == 40 or x == 58: c = steel
					if absf(float(x) - 70.0) < 2.5 and y > 10: c = white
				CamMode.WIDE:
					c = sunset_top.lerp(sunset_mid, clampf(t * 1.8, 0.0, 1.0)) if y < h - 5 else ground
					if y >= h - 6 and y <= h - 5: c = Color(0.50, 0.34, 0.26)
					if absf(float(x) - 48.0) < 1.5 and y > 16 and y < h - 5: c = white
				CamMode.CHASE:
					c = Color(0.01, 0.02, 0.06)
					if (x * 7 + y * 13) % 41 == 0: c = Color(0.85, 0.90, 1.0)
					if x + y > w: c = Color(0.05, 0.15, 0.35)
					if absf(float(x) - 60.0) < 2.0 and y > 4 and y < 20: c = white
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _build_cam_selector(parent: Control) -> void:
	var box := HBoxContainer.new(); box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var prev := _mini_arrow("<")
	prev.pressed.connect(func() -> void: _select_cam_view(cam_sel - 1))
	box.add_child(prev)
	cam_buttons.clear()
	cam_modes = [CamMode.PAD, CamMode.ENGINE, CamMode.TOWER, CamMode.WIDE, CamMode.CHASE]
	var names := ["Launch Pad", "Close Up", "Tower View", "Wide View", "Tracking"]
	for i in range(names.size()):
		var b := _cam_thumb(names[i], _cam_preview(cam_modes[i]))
		var idx := i
		b.pressed.connect(func() -> void: _select_cam_view(idx))
		box.add_child(b); cam_buttons.append(b)
	var nxt := _mini_arrow(">")
	nxt.pressed.connect(func() -> void: _select_cam_view(cam_sel + 1))
	box.add_child(nxt)
	_select_cam_view(0)

func _select_cam_view(i: int) -> void:
	if cam_modes.is_empty():
		return
	# A recovery shot is a scripted cut, not a camera the player is browsing; a
	# click in the middle of it would leave the thumbnail lit and the shot gone.
	if booster_cam_window > 0:
		return
	var n := cam_modes.size()
	cam_sel = ((i % n) + n) % n
	var wanted: CamMode = cam_modes[cam_sel]
	# Once orbit has been reached the ground cameras are pointed at empty sky.
	# Rather than showing a broken frame, any pad view resolves to the orbital
	# tracking shot, which is the only thing still filming the vehicle.
	if in_space_frame and wanted != CamMode.CHASE:
		wanted = CamMode.SPACE
	_set_camera(wanted)
	for k in range(cam_buttons.size()):
		cam_buttons[k].button_pressed = (k == cam_sel)

func _populate_mission_info() -> void:
	var m: Dictionary = GameManager.current_mission
	var rd: Dictionary = GameManager.spacecraft_config.get("rocket", {})
	if mission_name_label: mission_name_label.text = m.get("name", "—")
	if target_name_label:  target_name_label.text = m.get("target", "—")
	if vehicle_name_label: vehicle_name_label.text = _vehicle_display(rd)
	# Naming the actual orbital parameters up front is what makes a launch feel
	# like a mission rather than a fireworks display.
	if insertion_info_label:
		var regime := "Sun-synchronous" if target_inclination_deg > 95.0 else "Inclined"
		insertion_info_label.text = "%.0f km %s @ %.1f°" % [target_orbit_km, regime, target_inclination_deg]

func _vehicle_display(rd: Dictionary) -> String:
	var nm: String = rd.get("name", "")
	if nm != "":
		return nm
	var id: String = rd.get("id", "")
	return id.capitalize() if id != "" else "—"

# ─── Cinematic environment grading (sunset pad mood) ──────────────────────────
func _grade_environment() -> void:
	sky_top_day = Color(0.10, 0.28, 0.60, 1.0)
	sky_horizon_day = Color(0.60, 0.72, 0.86, 1.0)
	ground_horizon_day = Color(0.44, 0.52, 0.60, 1.0)
	ground_bottom_day = Color(0.14, 0.18, 0.20, 1.0)
	if sky_material:
		sky_material.sky_top_color = sky_top_day
		sky_material.sky_horizon_color = sky_horizon_day
		sky_material.ground_horizon_color = ground_horizon_day
		sky_material.ground_bottom_color = ground_bottom_day
	if world_env and world_env.environment:
		var env := world_env.environment
		env.ambient_light_color = Color(0.62, 0.68, 0.76)
		env.glow_enabled = true
		env.glow_intensity = 0.40
		env.glow_bloom = 0.06
		env.fog_light_color = Color(0.70, 0.76, 0.84)
	var sun := get_node_or_null("WorldLight") as DirectionalLight3D
	if sun:
		env_sun = sun
		sun.light_color = Color(1.0, 0.92, 0.82)
		sun.light_energy = 1.45
		sun.rotation_degrees = Vector3(-32.0, 40.0, 0.0)
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill:
		fill.light_color = Color(0.55, 0.65, 1.0)
		fill.light_energy = 0.30
