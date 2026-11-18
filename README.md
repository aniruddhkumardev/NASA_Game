# Mission Architect: Beyond Earth

\<p align="center">   \<strong>Design. Build. Launch. Explore.\</strong>\<br>   A 3D Space Mission Design and Simulation Game \</p>

\<p align="center">   \<img src="[https://img.shields.io/badge/Godot-4.7-478CBF?style=for-the-badge&logo=godot-engine&logoColor=white](https://img.shields.io/badge/Godot-4.7-478CBF?style=for-the-badge\&logo=godot-engine\&logoColor=white)">   \<img src="[https://img.shields.io/badge/Version-1.0.0-333333?style=for-the-badge](https://img.shields.io/badge/Version-1.0.0-333333?style=for-the-badge)">   \<img src="[https://img.shields.io/badge/Language-GDScript-478CBF?style=for-the-badge](https://img.shields.io/badge/Language-GDScript-478CBF?style=for-the-badge)">   \<img src="[https://img.shields.io/badge/Platform-PC-111111?style=for-the-badge](https://img.shields.io/badge/Platform-PC-111111?style=for-the-badge)"> \</p>

**Mission Architect: Beyond Earth** is a 3D space mission design game where players plan missions, assemble spacecraft, select launch vehicles, and operate missions across the Solar System.

Developed by **Team CodeStorm1** for **NASA Space Apps Challenge 2026**.

---

## 🚀 Overview

Space exploration requires careful planning. Every spacecraft must balance mass, power, communications, propulsion, launch capacity, and mission budget while achieving scientific objectives.

Mission Architect transforms these engineering concepts into an interactive experience. Select a mission, design your spacecraft, launch from Earth, operate at your destination, and evaluate your mission results.

## ✨ Features

- Mission selection across Earth, Moon, Mars, and asteroid exploration.
- Spacecraft construction and component configuration.
- Launch vehicle selection based on payload and destination.
- Mass, budget, power, battery, and data-rate management.
- Orbital and mission simulation systems.
- Scientific data collection and transmission.
- Ground-station communication opportunities.
- Primary and bonus mission objectives.
- 3D space environments and cinematic transitions.
- MissionForge black-and-white interface design.

## 🌍 Available Missions

| Mission                | Destination         | Objective                                 |
| ---------------------- | ------------------- | ----------------------------------------- |
| Earth Climate Sentinel | Low Earth Orbit     | Observe Earth's climate and water systems |
| Lunar South Pole Scout | Lunar Polar Orbit   | Search for lunar water-ice signatures     |
| Mars Climate Explorer  | Mars                | Explore Martian climate and surface       |
| Asteroid Rendezvous    | Near-Earth Asteroid | Rendezvous and study asteroid composition |

## 🛰️ Spacecraft Design

Configure your spacecraft using different component categories:

| Component              | Purpose                        |
| ---------------------- | ------------------------------ |
| Spacecraft Bus         | Main spacecraft platform       |
| Power System           | Electrical power generation    |
| Battery                | Energy storage                 |
| Communications         | Data transmission              |
| Scientific Instruments | Scientific observations        |
| Propulsion             | Orbital manoeuvres             |
| Launch Vehicle         | Spacecraft launch and delivery |

The builder tracks mass, cost, power generation, power consumption, data rate, and science capability.

## ⚙️ Simulation Systems

- Orbital state and mission-time progression
- Simulation speed controls
- Power generation and consumption
- Science-data collection
- Data storage and downlink
- Ground-station communication
- Mission events and objectives
- Mission completion reports

## 🛠️ Technology Stack

- **Game Engine:** Godot Engine 4.7
- **Programming Language:** GDScript
- **Renderer:** Godot Forward+
- **UI:** Godot Control Nodes
- **Design System:** MissionForge Monochrome Theme
- **Version Control:** Git and GitHub

## 💻 Getting Started

### Prerequisites

- Godot Engine 4.7
- Windows, Linux, or macOS
- Git (optional)

### 1. Clone the repository

```bash
git clone https://github.com/roshancodestorm/NASA-GAME-.git
cd NASA-GAME-
```

### 2. Open the project

1. Launch Godot Engine.
2. Open the Project Manager.
3. Select Import.
4. Browse to `MissionArchitect_Godot4/project.godot`.
5. Import and open the project.

### 3. Run the game

Press **F5** in Godot to run the configured main scene.

Main scene:

```text
res://scenes/ui/main_menu.tscn
```

The first launch may take additional time while Godot imports assets and generates its local cache.

## 🎮 Controls

| Action                   | Key        |
| ------------------------ | ---------- |
| Move Forward             | W          |
| Move Backward            | S          |
| Move Left                | A          |
| Move Right               | D          |
| Jump                     | Space      |
| Sprint                   | Shift      |
| Interact                 | E          |
| Orbital Map              | M          |
| Control Room             | C          |
| Pause                    | Esc        |
| Increase Throttle        | Up Arrow   |
| Decrease Throttle        | Down Arrow |
| Transmit Data            | T          |
| Science Scan             | I          |
| Increase Simulation Time | .          |
| Decrease Simulation Time | ,          |

Some controls are available only in their relevant gameplay scenes.

## 📁 Project Structure

```text
NASA-GAME-/
└── MissionArchitect_Godot4/
    ├── project.godot
    ├── assets/
    ├── data/
    ├── scenes/
    │   ├── ui/
    │   ├── hangar/
    │   ├── builder/
    │   ├── launch/
    │   ├── orbit/
    │   ├── lunar/
    │   └── mars/
    ├── scripts/
    │   ├── core/
    │   ├── simulation/
    │   └── ui/
    └── shaders/
```

## 📌 Development Notes

- Open the project using `MissionArchitect_Godot4/project.godot`.
- The `.godot/` directory contains generated local editor data and is excluded from version control.
- Avoid committing temporary logs, generated exports, and machine-specific files.
- Keep scene and script references consistent when adding new features.

## 👨‍🚀 Team

**Team CodeStorm1**
NASA Space Apps Challenge 2026

GitHub: [roshancodestorm](https://github.com/roshancodestorm)

Repository: [NASA-GAME-](https://github.com/roshancodestorm/NASA-GAME-)

## ⚠️ Disclaimer

This project is an educational game and simulation experience. Its models simplify complex aerospace systems and must not be used for real-world spacecraft engineering, launch planning, navigation, or operational decisions.

This is an independent community project and is not an official NASA product or endorsed by NASA.

---

\<p align="center">
&#x20; \<strong>Plan the Mission. Build the Spacecraft. Explore Beyond Earth.\</strong>
\</p>
