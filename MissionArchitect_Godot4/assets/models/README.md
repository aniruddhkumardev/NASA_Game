# 3D Models — How to Generate

## Step 1 — Run the Blender Script

1. Blender kholo
2. Top mein **Scripting** tab click karo
3. **Open** click karo → `generate_models.py` select karo
   (Path: `f:\Projects\Space_Mission_design_Game\MissionArchitect_Godot4\assets\models\generate_models.py`)
4. **Run Script** (▶ button) click karo
5. ~30 seconds mein 4 `.glb` files ban jaayengi is folder mein:
   - `falcon9_rocket.glb`
   - `launch_pad.glb`
   - `satellite.glb`
   - `earth.glb`

## Step 2 — Godot mein Auto-Import

Godot automatically `.glb` files import karta hai jab aap game run karo.
Koi extra step nahi.

## Step 3 — Scene mein Use

Models generate hone ke baad Kiro ko batao:
**"models ban gaye"**

Kiro automatically:
- `launch.tscn` mein Falcon 9 + launch pad replace karega
- `orbit.tscn` mein proper satellite + Earth replace karega
- Materials aur lighting set karega
