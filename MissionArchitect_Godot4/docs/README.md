# Mission Architect: Beyond Earth
### NASA Space Apps Challenge 2026 — 3D Space Mission Design Game

---

## How to Run

1. **Download Godot 4.7** from https://godotengine.org (already installed at `F:\DownloadedApps\GodotEngine\Godot_v4.7.2-stable_win64.exe`)
2. Open Godot → **Import Project** → select `project.godot` from this folder
3. Press **F5** to run the game

---

## Game Overview

**Mission Architect: Beyond Earth** is a 3D space mission design game where you play as a NASA engineer who must:

1. **Select a mission** — Earth observation, Lunar scout, Mars orbiter, or Asteroid probe
2. **Design your spacecraft** — Choose bus, power system, instruments, antenna, propulsion
3. **Launch your rocket** — Watch (or control) the rocket ascent to orbit
4. **Operate in orbit** — Manage battery, science collection, data downlinks, and emergencies
5. **Report results** — See your score, what went wrong, and how to improve

---

## Controls

| Key | Action |
|-----|--------|
| W/A/S/D | Move astronaut |
| Mouse | Look around / rotate spacecraft |
| Shift | Sprint |
| Space | Jump |
| E | Interact with terminals |
| M | Open orbital map |
| C | Open the SWOT mission control room (Earth mission) |
| Left-click Earth | Inspect that area: real place name, local temperature, weather, wind, humidity, solar time |
| Mouse wheel / 🔍 + − | Zoom in / out on the inspected area (or the orbit view) |
| Right-click | Leave the area inspection and return to orbit |
| 🔎 Search box (top center) | Type any city or place, Enter to fly there and read its weather/temperature |
| T | Manually transmit data |
| . (period) | Speed up simulation |
| , (comma) | Slow down simulation |
| Esc | Pause menu |

---

## Game Scenes

```
Main Menu → Mission Select → Spacecraft Builder → Launch → Orbit → Mission Report
```

### Scene Files
| Scene | Path | Purpose |
|-------|------|---------|
| Main Menu | `scenes/ui/main_menu.tscn` | Start screen with animated Earth |
| Mission Select | `scenes/ui/mission_select.tscn` | Choose your mission |
| Spacecraft Builder | `scenes/builder/builder.tscn` | 3D component assembly |
| Launch Sequence | `scenes/launch/launch.tscn` | Rocket launch cinematic |
| Orbital Operations | `scenes/orbit/orbit.tscn` | Live mission control |
| Mission Report | `scenes/ui/mission_report.tscn` | Score and debrief |
| Hangar | `scenes/hangar/hangar.tscn` | 3D walkaround (optional entry) |

---

## Engineering Systems

### Resource Management
- **Mass** — Total spacecraft + instruments must fit within mission limit
- **Power** — Solar generation must exceed system draw (especially in eclipse)
- **Budget** — Total hardware + launch cost must fit within mission budget
- **Data Rate** — Science instruments generate data; antenna must downlink it

### Orbital Mechanics
Orbital period calculated using Kepler's third law:
```
T = 2π × √((RE + h)³ / μ)
```
Where:
- `RE` = planetary radius (km)
- `h` = orbital altitude (km)  
- `μ` = gravitational parameter (km³/s²)

### Power Simulation
Battery charge updated each timestep:
```
E(t+Δt) = clamp(E(t) + (P_solar - P_load) × Δt, 0, E_max)
```
- Solar power = 0 during eclipse
- If battery reaches 0 → automatic safe mode

---

## Mission Scenarios

| Mission | Target | Difficulty | Budget |
|---------|--------|------------|--------|
| Earth Climate Sentinel | LEO 550km | Beginner | $120M |
| Lunar South Pole Scout | Lunar Orbit | Intermediate | $300M |
| Mars Climate Explorer | Mars Orbit | Expert | $600M |
| Asteroid Rendezvous | NEA 2025-XK7 | Advanced | $450M |

### Earth Climate Sentinel Mission Rules
- The mission is a survey of **real events NASA tracks**: the 2023 Canadian wildfire megaseason (NASA FIRMS), the Lahaina burn scar (Landsat 8/9), the 2022 Mediterranean marine heatwave (MODIS SST on Aqua), the Rio Madeira flood pulse (SWOT), the Sundhnúkur SO₂ plume (TEMPO) and Greenland ice-sheet mass loss (ICESat-2).
- An event is only sensed when the spacecraft **carries the instrument whose NASA analogue made the discovery** (thermal → FIRMS/MODIS, hi-res → Landsat OLI, spectrometer → TEMPO, SAR/altimeter → SWOT/ICESat-2) and flies its footprint within 15° of the event location. Optical instruments need sunlight; thermal, SAR and the Day/Night Band work in the dark.
- The orbit is genuinely **sun-synchronous**: 550 km at 97.6° gives a 95.5-minute Kepler period, and the simulation applies the real J2 nodal precession (~0.986°/day vs the 0.9856°/day sun-sync requirement) to the orbital plane — only this mission precesses.
- Four listed objectives (3+ events, 80 science, 3+ station passes, budget) drive the 35-point objectives score; the mission report prints a data-return manifest citing every event observed.

### Surface Area Inspection (Earth Climate Sentinel)
- Left-click any patch of the globe and the camera flies down to it: the panel shows the nearest real settlement (name, region, country, distance), an estimated temperature, weather condition, cloud cover, wind, humidity and local solar time.
- The place gazetteer is bundled offline (GeoNames cities15000, CC BY 4.0) so search and place identification work with no network; type any city in the top search box and press Enter to fly straight to it.
- Temperature/weather is an in-game estimate from latitude, season and local solar time — it is not a live weather feed. Nearby NASA survey sites (SWOT, MODIS, FIRMS, Landsat, TEMPO, ICESat-2) show their real mission source separately.

### NASA Data Integration (Earth Climate Sentinel)
| In-game target | Real NASA sensor | Data source |
|---|---|---|
| Canadian Wildfire Megaseason 2023 | MODIS/VIIRS thermal anomalies | NASA FIRMS (firms.fire.nasa.gov) |
| Lahaina Urban Fire Damage 2023 | Landsat 8/9 OLI 30 m imaging | NASA Earthdata / USGS |
| Mediterranean Marine Heatwave 2022 | MODIS sea-surface temperature | NASA OB.DAAC (Aqua MODIS) |
| Amazon Flood Pulse (Rio Madeira) | SWOT KaRIn radar altimetry | NASA/CNES SWOT (swot.jpl.nasa.gov) |
| Sundhnúkur Eruption SO₂ Plume | TEMPO tropospheric SO₂ columns | NASA TEMPO (tempo.si.edu) |
| Greenland Ice Sheet Mass Loss | ICESat-2 ATLAS laser altimetry | NASA ICESat-2 (icesat2.gsfc.nasa.gov) |

### SWOT Surface Water Survey & Control Room (Earth Climate Sentinel)
- The Earth mission also flies the **NASA/CNES SWOT** (Surface Water and Ocean Topography) water survey — the first mission to measure the height of water across the whole planet.
- Carry the **SAR Radar** box (the SWOT KaRIn analogue). The 120 km swath scans six real water sites — two oceans (Gulf Stream, Kuroshio), two lakes (Victoria, Mead) and two rivers (Amazon at Óbidos, Mississippi at Memphis) — day or night.
- A scan is recorded **onboard**; it only reaches the **SWOT Mission Control Center** after a ground-station pass. Press **C** (or the CONTROL ROOM button) to open the monitor wall: ground track/station contact, KaRIn swath detections, live water-level/discharge telemetry and the downlink record queue.
- Real SWOT mission facts used in-game: 891 km orbit, 120 km swath, 21-day repeat cycle, KaRIn interferometer, joint NASA/CNES mission. Source: https://swot.jpl.nasa.gov/

### Asteroid Rendezvous Mission Rules
- Bring a propulsion system with at least 500 m/s of delta-v to complete intercept and orbit insertion.
- Carry a spectrometer to analyze the asteroid's surface composition.
- Maintain asteroid orbit for at least 30 mission days and transmit collected data during a DSN contact window.
- Complete the four listed objectives and reach the 160-point science goal for mission success.
- Outgassing and microgravity drift can temporarily reduce power generation or science output; the asteroid operations scene has no Earth-eclipse periods.

---

## Scoring System (0–100)

| Category | Weight | Notes |
|----------|--------|-------|
| Mission Objectives | 35% | Science collected vs. goal |
| Scientific Discoveries | 25% | Instruments + data delivered |
| Engineering Reliability | 20% | System uptime |
| Resource Efficiency | 15% | Budget usage |
| Operational Decisions | 5% | Responses to events |

Score is multiplied by bus reliability × rocket reliability.

---

## Project Structure

```
MissionArchitect_Godot4/
├── project.godot          ← Godot project file (open this)
├── scenes/
│   ├── ui/                ← Main menu, mission select, report
│   ├── hangar/            ← 3D walkable hangar
│   ├── builder/           ← Spacecraft assembly
│   ├── launch/            ← Rocket launch cinematic
│   └── orbit/             ← Live orbital operations
├── scripts/
│   ├── core/              ← GameManager, Hangar, LaunchSequence, Terminal
│   ├── player/            ← Astronaut controller
│   ├── spacecraft/        ← SpacecraftBuilder
│   ├── simulation/        ← SimulationEngine, OrbitMission
│   └── ui/                ← MainMenu, MissionSelect, MissionReport, HUD
├── assets/
│   ├── textures/          ← Textures and icons
│   └── sounds/            ← Sound effects (add your own .ogg files)
└── docs/
    └── README.md          ← This file
```

---

## NASA Challenge Alignment

This game directly addresses the NASA Space Apps challenge by:

1. **Engineering trade-offs** — Every component choice has mass, power, cost, and science consequences
2. **Complete mission lifecycle** — From concept to operation in one experience
3. **Educational feedback** — Detailed failure analysis explains WHY missions succeed or fail
4. **Real physics** — Orbital mechanics, power simulation, eclipse detection
5. **Multiplayer ready** — Architecture supports up to 4 collaborative players

---

*Built for NASA Space Apps Challenge 2026 — "Space Mission Design Game" challenge*
