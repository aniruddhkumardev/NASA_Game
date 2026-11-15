# MISSIONFORGE — monochrome interface system

MISSIONFORGE is the design language for every **interface** surface in Mission
Architect. It has one hard rule:

> **UI is monochrome. The simulation is not.**

* Interface: black, white and grey only — no hue anywhere, with the single
  documented exception of the coloured title screen plate.
* 3D simulation: fully natural colour — blue oceans, green/brown continents,
  white clouds, orange/red plume, metallic silver and gold spacecraft, blue
  rain and water, natural glacier ice, deep black space.

The two colour systems are structurally independent, which is what keeps them
from leaking into each other.

## How it is enforced

| Piece | Role |
|---|---|
| `scripts/ui/MissionForgeTheme.gd` | `MissionForge` autoload. Walks the live scene tree and puts every `CanvasItem` into the monochrome pass. |
| `shaders/missionforge_mono.gdshader` | Per-item luminance pass. Desaturates font glyphs, StyleBox fills, textures, icons and glow. Alpha is untouched. |
| `shaders/missionforge_plate.gdshader` | First-page white-ink pass. Keeps the title plate's dark space but pushes its lettering, icons and rules to pure white. |
| `project.godot` → `[autoload]` | Registers `MissionForge` next to `GameManager`. |

### Why this cannot touch 3D

`Node3D`, `MeshInstance3D` and `StandardMaterial3D` are **not** `CanvasItem`s.
The autoload only ever visits `CanvasItem`s and `Control` theme overrides, so a
rocket material, planet texture, particle colour or light colour is unreachable
from the theme layer. There is no viewport filter, no camera effect and no
global canvas modulate.

`SubViewportContainer` and `SubViewport` subtrees are explicitly skipped: those
host live 3D previews (hangar, spacecraft builder, mission select), which must
keep their real colours.

### What gets neutralised

* `theme_override_colors/*` → luminance grey
* `theme_override_styles/*` → `StyleBoxFlat.bg_color`, `border_color`,
  `shadow_color`, `StyleBoxLine.color`, `StyleBoxTexture.modulate_color`
* assigned `Theme` resources (colours and styleboxes)
* every drawn pixel of a `Control` / `Node2D` UI item via the shader (covers
  emoji glyphs, textures, gradients and runtime colour changes)

### The title-screen exception

The main menu is the one page allowed to keep its colours: its background plate
is the approved concept art, so `MainMenu.gd` calls `MissionForge.colorize()` on
the plate, its letterbox backing and the five menu hit areas. Everything else —
including the settings and how-to overlays opened from that screen — stays on the
monochrome palette. Probe runs report those items as `color_page=N` rather than
counting them as unthemed.

Luminance uses Rec.709 weights, so hierarchy survives: a bright "GO" stays
brighter than a dim "ABORT" without either one carrying hue.

## Palette

Use these for new UI code instead of inventing colours:

| Token | Value | Use |
|---|---|---|
| `MissionForge.BLACK` | `#000000` | space / full-screen fades |
| `MissionForge.BG` | `#0A0A0A` | app background |
| `MissionForge.CARD` | `#151515` | cards and panels |
| `MissionForge.RAISED` | `#202020` | elevated / hovered panels |
| `MissionForge.BORDER` | `#333333` | panel borders and dividers |
| `MissionForge.TEXT_MUTED` | `#777777` | disabled / tertiary text |
| `MissionForge.TEXT_SECONDARY` | `#B3B3B3` | secondary text |
| `MissionForge.HOVER` | `#D9D9D9` | hovered surfaces |
| `MissionForge.TEXT_PRIMARY` | `#FFFFFF` | primary text, emphasis, success |
| `MissionForge.SECONDARY_BG` | `#111111` | secondary button fill |

Legacy aliases (`INK`, `PANEL`, `PANEL_SOFT`, `LINE_SOFT`, `LINE`, `MUTED`,
`DIM`, `TEXT`, `WHITE`, `SUCCESS`, `ALERT`, `LIVE`) resolve to the tokens above,
so older call sites keep compiling and stay on-palette.

### Live telemetry

Live numeric readouts (altitude, speed, power, battery, science, data, day,
survey %, temperatures and so on) opt out of the mono pass with
`MissionForge.live(label)`. That call marks the control, removes the shader from
that one item and sets it to `MissionForge.TEXT_PRIMARY`. The accent is white,
not a hue: the interface has no sanctioned colour accent left. Labels, chrome,
panels, buttons and every 3D material remain neutral.

`MissionForge.token(color)` snaps a source colour to the nearest ramp step by
luminance, which is how StyleBox overrides land on the exact hex values above
instead of drifting to arbitrary greys.

Colour literal checks for the React HUD live in
`frontend/src/components/LunarOperationsHUD.jsx`; every value there is also a
neutral grey.

## Development switch

```powershell
# Render the UI with its original source colours, for A/B comparison
$env:MA_MONO = "0"
```

Everything else is unchanged. Gameplay, physics, APIs and mission logic are not
modified by this layer.

## Verification

```powershell
# UI coverage + 3D isolation, per scene
$env:MA_PROBE_SCENE = "res://scenes/ui/main_menu.tscn"
godot --headless --path . --script res://tools/_missionforge_probe.gd
```

Expected output:

```
PROBE UI items=144 mono=143 live_accent=0 white_plate=1 skipped_3d_preview=0
PROBE 3D LEAKS=0
PROBE RESULT ok=true
```

`mono + live_accent + white_plate == items` means every UI canvas item is
accounted for; `LEAKS=0` means no 3D node or material references the UI shader.
`live_accent` is non-zero on live mission HUDs and is the audited red opt-out.

```powershell
# Globe zoom, 8k map, satellite palette and live-accent audit
$env:MA_MISSION = "earth_climate"
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 `
      --script res://tools/_orbit_globe_probe.gd
```

For a pixel-level check, sample a screenshot and compare saturation: a
monochrome UI region reports `mean saturation < 0.02`, while the 3D viewport
region keeps a high value (e.g. Earth ≈ 0.85).
