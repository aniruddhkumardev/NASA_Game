"""
Constants, colors, fonts, and all game data for Space Mission Design Game
"""

# ─── Screen ───────────────────────────────────────────────────────────────────
WIDTH, HEIGHT = 1280, 800
FPS = 60
TITLE = "Space Mission Design Game"

# ─── Colors ───────────────────────────────────────────────────────────────────
C = {
    # backgrounds
    "bg_dark":      (8,   10,  28),
    "bg_panel":     (15,  20,  50),
    "bg_card":      (20,  30,  70),
    "bg_card_hl":   (30,  50, 100),
    "bg_header":    (5,   10,  35),

    # text
    "white":        (255, 255, 255),
    "grey":         (170, 170, 200),
    "dim":          (100, 110, 150),
    "yellow":       (255, 220,  60),
    "orange":       (255, 140,  30),
    "red":          (220,  60,  60),
    "green":        (60,  220, 100),
    "cyan":         (60,  220, 255),
    "blue":         (80,  130, 255),
    "magenta":      (200,  80, 255),
    "gold":         (255, 195,   0),

    # UI
    "btn_normal":   (40,  70, 160),
    "btn_hover":    (60, 100, 220),
    "btn_active":   (30,  50, 120),
    "btn_green":    (30, 140,  70),
    "btn_green_h":  (40, 180,  90),
    "btn_red":      (160, 40,  40),
    "btn_red_h":    (210, 60,  60),
    "btn_disabled": (50,  55,  80),

    # bars
    "bar_bg":       (20,  25,  60),
    "bar_budget":   (60,  220, 100),
    "bar_mass":     (255, 140,  30),
    "bar_power":    (255, 220,  60),
    "bar_data":     (60,  220, 255),
    "bar_comms":    (200,  80, 255),

    # roles
    "role_0":       (60,  220, 100),
    "role_1":       (60,  180, 255),
    "role_2":       (255, 180,  60),
    "role_3":       (220,  80, 220),

    "border":       (40,  60, 130),
    "border_hl":    (80, 130, 255),
    "transparent":  (0,   0,   0,   0),
    "black":        (0,   0,   0),
}

ROLE_NAMES  = ["Mission Commander", "Spacecraft Engineer", "Science Lead", "Comms & Ops"]
ROLE_COLORS = [C["role_0"], C["role_1"], C["role_2"], C["role_3"]]

# ─── Mission Scenarios ────────────────────────────────────────────────────────
SCENARIOS = [
    {
        "id": "mars_orbiter",
        "name": "Mars Climate Orbiter",
        "icon": "♂",
        "description": (
            "Design an orbiter to study Mars' atmosphere, weather patterns, "
            "and surface temperature. Key challenge: high communication delay "
            "and tight mass budget for the long journey."
        ),
        "target": "Mars",
        "difficulty": "Medium",
        "budget_limit": 600,       # M USD
        "mass_limit":  2200,       # kg
        "power_limit": 1200,       # W
        "data_limit":  500,        # GB/day
        "comms_limit": 200,        # Mbps
        "min_science": 60,
        "bonus_objectives": ["Map full surface", "Detect water vapor", "Weather forecast model"],
        "color": C["orange"],
    },
    {
        "id": "lunar_lander",
        "name": "Lunar Surface Explorer",
        "icon": "☽",
        "description": (
            "Land a robotic explorer on the lunar south pole to hunt for water "
            "ice. Low budget but short travel time. Mass is critical — every "
            "kilogram costs fuel."
        ),
        "target": "Moon",
        "difficulty": "Easy",
        "budget_limit": 300,
        "mass_limit":  1500,
        "power_limit":  800,
        "data_limit":  200,
        "comms_limit": 150,
        "min_science": 40,
        "bonus_objectives": ["Detect water ice", "Measure radiation", "Geologic samples"],
        "color": C["grey"],
    },
    {
        "id": "asteroid_probe",
        "name": "Asteroid Rendezvous",
        "icon": "☄",
        "description": (
            "Intercept and study a near-Earth asteroid. You'll need a capable "
            "propulsion system, advanced instruments, and tight power management "
            "far from the Sun."
        ),
        "target": "Asteroid Belt",
        "difficulty": "Hard",
        "budget_limit": 900,
        "mass_limit":  3000,
        "power_limit": 1500,
        "data_limit":  300,
        "comms_limit": 100,
        "min_science": 80,
        "bonus_objectives": ["Sample return", "Orbit the asteroid", "Subsurface probe"],
        "color": C["cyan"],
    },
    {
        "id": "jupiter_flyby",
        "name": "Jupiter Deep Space Probe",
        "icon": "♃",
        "description": (
            "A flagship deep-space probe to study Jupiter's magnetosphere and "
            "the potential ocean under Europa's ice. Maximum science, maximum cost."
        ),
        "target": "Jupiter",
        "difficulty": "Expert",
        "budget_limit": 1500,
        "mass_limit":  4500,
        "power_limit": 2000,
        "data_limit":  800,
        "comms_limit": 80,
        "min_science": 100,
        "bonus_objectives": ["Europa ocean scan", "Io volcano mapping", "Magnetosphere model"],
        "color": C["gold"],
    },
]

# ─── Spacecraft Bus Options ───────────────────────────────────────────────────
SPACECRAFT_BUS = [
    {
        "id": "cubesat",
        "name": "CubeSat Bus",
        "desc": "Ultra-compact platform. Very limited payload capacity.",
        "mass": 12, "power": 30, "cost": 15, "data": 10, "comms": 20,
        "reliability": 0.70, "icon": "▪",
        "color": C["dim"],
    },
    {
        "id": "small_sat",
        "name": "Small Satellite Bus",
        "desc": "Compact and affordable. Good for simple missions.",
        "mass": 200, "power": 200, "cost": 80, "data": 50, "comms": 60,
        "reliability": 0.82, "icon": "◈",
        "color": C["blue"],
    },
    {
        "id": "medium_bus",
        "name": "Medium Class Bus",
        "desc": "The workhorse of space exploration. Balanced performance.",
        "mass": 800, "power": 700, "cost": 200, "data": 200, "comms": 120,
        "reliability": 0.90, "icon": "⬡",
        "color": C["green"],
    },
    {
        "id": "large_bus",
        "name": "Large Flagship Bus",
        "desc": "Heavy, expensive, but highly capable. For flagship missions.",
        "mass": 2500, "power": 1500, "cost": 500, "data": 600, "comms": 250,
        "reliability": 0.95, "icon": "⬢",
        "color": C["yellow"],
    },
]

# ─── Power Systems ────────────────────────────────────────────────────────────
POWER_SYSTEMS = [
    {
        "id": "solar_small",
        "name": "Small Solar Panels",
        "desc": "Lightweight, works well in inner solar system.",
        "mass": 30, "power_gen": 200, "cost": 20,
        "icon": "☀", "works_far": False, "color": C["yellow"],
    },
    {
        "id": "solar_large",
        "name": "Large Solar Array",
        "desc": "High output. Heavier. Less effective beyond Mars.",
        "mass": 120, "power_gen": 800, "cost": 60,
        "icon": "⊞", "works_far": False, "color": C["gold"],
    },
    {
        "id": "rtg",
        "name": "RTG (Nuclear Battery)",
        "desc": "Reliable power anywhere in the solar system. Expensive.",
        "mass": 55, "power_gen": 400, "cost": 150,
        "icon": "☢", "works_far": True, "color": C["magenta"],
    },
    {
        "id": "rtg_advanced",
        "name": "Advanced RTG Array",
        "desc": "Best for deep space. Very high cost and regulatory approval needed.",
        "mass": 160, "power_gen": 1000, "cost": 350,
        "icon": "⚛", "works_far": True, "color": C["cyan"],
    },
]

# ─── Scientific Instruments ───────────────────────────────────────────────────
INSTRUMENTS = [
    {
        "id": "camera_wide",
        "name": "Wide-Angle Camera",
        "desc": "Images large surface areas. Low data rate.",
        "mass": 8, "power": 15, "cost": 25, "data": 30, "science": 15,
        "icon": "📷", "color": C["cyan"],
        "category": "Imaging",
    },
    {
        "id": "camera_hires",
        "name": "High-Res Imager",
        "desc": "Extreme detail images. High data volume.",
        "mass": 25, "power": 40, "cost": 60, "data": 150, "science": 35,
        "icon": "🔭", "color": C["blue"],
        "category": "Imaging",
    },
    {
        "id": "spectrometer",
        "name": "Spectrometer",
        "desc": "Identifies atmospheric and surface composition.",
        "mass": 12, "power": 20, "cost": 40, "data": 60, "science": 30,
        "icon": "🌈", "color": C["magenta"],
        "category": "Spectroscopy",
    },
    {
        "id": "radar",
        "name": "Ground-Penetrating Radar",
        "desc": "Sees beneath surface. Heavy but reveals hidden structures.",
        "mass": 45, "power": 80, "cost": 90, "data": 120, "science": 45,
        "icon": "📡", "color": C["green"],
        "category": "Radar",
    },
    {
        "id": "magnetometer",
        "name": "Magnetometer",
        "desc": "Maps magnetic fields. Lightweight, low power.",
        "mass": 4, "power": 5, "cost": 15, "data": 10, "science": 18,
        "icon": "🧲", "color": C["orange"],
        "category": "Fields",
    },
    {
        "id": "seismometer",
        "name": "Seismometer",
        "desc": "Detects subsurface activity. Requires landing.",
        "mass": 18, "power": 10, "cost": 35, "data": 20, "science": 28,
        "icon": "📊", "color": C["yellow"],
        "category": "Geology",
    },
    {
        "id": "plasma_analyzer",
        "name": "Plasma Analyzer",
        "desc": "Studies particle environment and solar wind.",
        "mass": 10, "power": 25, "cost": 45, "data": 40, "science": 25,
        "icon": "⚡", "color": C["cyan"],
        "category": "Particles",
    },
    {
        "id": "mass_spec",
        "name": "Mass Spectrometer",
        "desc": "Precise chemical composition analysis. High science value.",
        "mass": 30, "power": 35, "cost": 75, "data": 80, "science": 50,
        "icon": "⚗", "color": C["magenta"],
        "category": "Chemistry",
    },
    {
        "id": "lidar",
        "name": "LiDAR Altimeter",
        "desc": "Precise topographic mapping with laser pulses.",
        "mass": 20, "power": 30, "cost": 55, "data": 70, "science": 32,
        "icon": "⬦", "color": C["green"],
        "category": "Mapping",
    },
    {
        "id": "radio_science",
        "name": "Radio Science Package",
        "desc": "Studies gravity field via Doppler tracking. Minimal mass.",
        "mass": 3, "power": 8, "cost": 20, "data": 15, "science": 22,
        "icon": "📻", "color": C["grey"],
        "category": "Radio",
    },
]

# ─── Orbits ───────────────────────────────────────────────────────────────────
ORBITS = [
    {
        "id": "leo",
        "name": "Low Earth Orbit",
        "desc": "Fast passes, easy comms, but only for Earth missions.",
        "altitude": "400 km",
        "coverage": "Partial",
        "comms_boost": 1.5,
        "power_factor": 1.0,
        "mass_penalty": 0,
        "cost": 10,
        "suitable_for": ["Moon"],
        "icon": "🌍",
        "color": C["blue"],
    },
    {
        "id": "polar",
        "name": "Polar / Sun-Synchronous",
        "desc": "Full surface coverage over time. Ideal for mappers.",
        "altitude": "700 km",
        "coverage": "Full surface",
        "comms_boost": 1.2,
        "power_factor": 1.1,
        "mass_penalty": 50,
        "cost": 20,
        "suitable_for": ["Moon", "Mars", "Asteroid Belt"],
        "icon": "🌐",
        "color": C["green"],
    },
    {
        "id": "geo",
        "name": "Geostationary Orbit",
        "desc": "Fixed position over one region. Great for comms.",
        "altitude": "35,786 km",
        "coverage": "Fixed region",
        "comms_boost": 2.0,
        "power_factor": 0.9,
        "mass_penalty": 200,
        "cost": 40,
        "suitable_for": ["Moon"],
        "icon": "📡",
        "color": C["yellow"],
    },
    {
        "id": "elliptical",
        "name": "Highly Elliptical Orbit",
        "desc": "Long dwell time over one pole. Good for deep space relay.",
        "altitude": "500–40,000 km",
        "coverage": "Polar regions",
        "comms_boost": 1.3,
        "power_factor": 1.2,
        "mass_penalty": 100,
        "cost": 30,
        "suitable_for": ["Moon", "Mars", "Jupiter"],
        "icon": "🔀",
        "color": C["orange"],
    },
    {
        "id": "transfer",
        "name": "Interplanetary Transfer",
        "desc": "Hohmann or gravity-assist trajectory to target body.",
        "altitude": "Varies",
        "coverage": "Target body",
        "comms_boost": 0.8,
        "power_factor": 1.3,
        "mass_penalty": 300,
        "cost": 60,
        "suitable_for": ["Mars", "Asteroid Belt", "Jupiter"],
        "icon": "🚀",
        "color": C["cyan"],
    },
    {
        "id": "lagrange",
        "name": "Lagrange Point (L2)",
        "desc": "Stable deep-space position. Ideal for large telescopes.",
        "altitude": "1.5M km from Earth",
        "coverage": "Deep space",
        "comms_boost": 0.9,
        "power_factor": 0.85,
        "mass_penalty": 150,
        "cost": 50,
        "suitable_for": ["Asteroid Belt", "Jupiter"],
        "icon": "✦",
        "color": C["magenta"],
    },
]

# ─── Launch Vehicles ──────────────────────────────────────────────────────────
LAUNCH_VEHICLES = [
    {
        "id": "rocket_lab",
        "name": "Rocket Lab Electron",
        "desc": "Small launcher for lightweight payloads to LEO/SSO.",
        "capacity": 300,    # kg
        "cost": 8,          # M USD
        "reliability": 0.95,
        "targets": ["Moon"],
        "icon": "🚀",
        "color": C["dim"],
    },
    {
        "id": "falcon9",
        "name": "SpaceX Falcon 9",
        "desc": "Reusable medium-lift. Excellent cost per kg.",
        "capacity": 2200,
        "cost": 70,
        "reliability": 0.97,
        "targets": ["Moon", "Mars"],
        "icon": "🚀",
        "color": C["blue"],
    },
    {
        "id": "falcon_heavy",
        "name": "SpaceX Falcon Heavy",
        "desc": "Heavy lift. Can reach inner planets with large payloads.",
        "capacity": 4500,
        "cost": 150,
        "reliability": 0.95,
        "targets": ["Moon", "Mars", "Asteroid Belt"],
        "icon": "🚀",
        "color": C["green"],
    },
    {
        "id": "atlas5",
        "name": "ULA Atlas V",
        "desc": "Proven heavy launcher with high reliability.",
        "capacity": 3500,
        "cost": 200,
        "reliability": 0.98,
        "targets": ["Moon", "Mars", "Asteroid Belt"],
        "icon": "🚀",
        "color": C["yellow"],
    },
    {
        "id": "sls",
        "name": "NASA SLS Block 1",
        "desc": "Flagship super-heavy launcher. Huge capacity, huge cost.",
        "capacity": 8000,
        "cost": 600,
        "reliability": 0.94,
        "targets": ["Moon", "Mars", "Asteroid Belt", "Jupiter"],
        "icon": "🚀",
        "color": C["orange"],
    },
    {
        "id": "starship",
        "name": "SpaceX Starship",
        "desc": "Next-gen fully reusable super-heavy. Highest capacity.",
        "capacity": 12000,
        "cost": 90,
        "reliability": 0.88,
        "targets": ["Moon", "Mars", "Asteroid Belt", "Jupiter"],
        "icon": "🚀",
        "color": C["cyan"],
    },
]

# ─── Random Events during simulation ─────────────────────────────────────────
RANDOM_EVENTS = [
    {
        "id": "solar_flare",
        "name": "Solar Flare!",
        "desc": "A powerful solar flare bombards the spacecraft with radiation.",
        "effect": {"power": -10, "reliability": -0.05},
        "icon": "☀", "color": C["orange"],
        "mitigation": "radiation_shield",
    },
    {
        "id": "micrometeorite",
        "name": "Micrometeorite Impact",
        "desc": "A tiny rock punches a small hole in the solar panel.",
        "effect": {"power": -15, "comms": -5},
        "icon": "☄", "color": C["red"],
        "mitigation": None,
    },
    {
        "id": "software_glitch",
        "name": "Software Anomaly",
        "desc": "A bug in the flight software causes instrument dropout.",
        "effect": {"science": -10, "data": -20},
        "icon": "⚠", "color": C["yellow"],
        "mitigation": None,
    },
    {
        "id": "comm_blackout",
        "name": "Communication Blackout",
        "desc": "The spacecraft passes behind the target body. No contact for 48h.",
        "effect": {"comms": -20},
        "icon": "📡", "color": C["magenta"],
        "mitigation": None,
    },
    {
        "id": "discovery",
        "name": "Unexpected Discovery!",
        "desc": "An anomalous reading leads to a major scientific finding!",
        "effect": {"science": +20},
        "icon": "✨", "color": C["gold"],
        "mitigation": None,
    },
    {
        "id": "power_surge",
        "name": "Battery Power Surge",
        "desc": "Batteries perform better than expected in the cold.",
        "effect": {"power": +10},
        "icon": "⚡", "color": C["green"],
        "mitigation": None,
    },
    {
        "id": "dust_storm",
        "name": "Dust Storm (Mars)",
        "desc": "A regional dust storm reduces solar panel efficiency.",
        "effect": {"power": -25},
        "icon": "🌪", "color": C["orange"],
        "mitigation": "rtg",
    },
    {
        "id": "instrument_fail",
        "name": "Instrument Failure",
        "desc": "One of your instruments stops responding. Data loss.",
        "effect": {"science": -15, "data": -30},
        "icon": "💀", "color": C["red"],
        "mitigation": None,
    },
    {
        "id": "gravity_assist",
        "name": "Perfect Gravity Assist",
        "desc": "Flawless navigation saves propellant and boosts mission life.",
        "effect": {"budget": +20, "science": +10},
        "icon": "🌙", "color": C["cyan"],
        "mitigation": None,
    },
    {
        "id": "antenna_bonus",
        "name": "DSN Priority Access",
        "desc": "NASA grants extra deep space network time for your mission.",
        "effect": {"comms": +15},
        "icon": "📻", "color": C["green"],
        "mitigation": None,
    },
]

# ─── Difficulty Settings ──────────────────────────────────────────────────────
DIFFICULTIES = {
    "Cadet":     {"budget_mult": 1.3, "events": 2, "label": "Cadet",     "color": C["green"]},
    "Engineer":  {"budget_mult": 1.0, "events": 4, "label": "Engineer",  "color": C["yellow"]},
    "Director":  {"budget_mult": 0.8, "events": 6, "label": "Director",  "color": C["orange"]},
    "Legend":    {"budget_mult": 0.6, "events": 8, "label": "Legend",    "color": C["red"]},
}

# ─── Game Phases ──────────────────────────────────────────────────────────────
PHASES = [
    "Main Menu",
    "Player Setup",
    "Scenario Select",
    "Spacecraft Bus",
    "Power System",
    "Instruments",
    "Orbit Select",
    "Launch Vehicle",
    "Review & Launch",
    "Simulation",
    "Mission Report",
]
