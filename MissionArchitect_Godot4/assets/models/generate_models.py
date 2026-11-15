"""
Mission Architect: Beyond Earth — Blender Model Generator v3
Blender 5.2 LTS compatible
Run: Scripting tab -> Open this file -> Run Script
"""

import bpy, bmesh, math, os

OUTPUT_DIR = r"f:\Projects\Space_Mission_design_Game\MissionArchitect_Godot4\assets\models"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ─── Helpers ──────────────────────────────────────────────────────────────────

def clear_all():
    """Remove all mesh objects and orphan data"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)

def mat(name, rgb, metal=0.0, rough=0.5, alpha=1.0, emit_rgb=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    nodes.clear()
    o = nodes.new('ShaderNodeOutputMaterial')
    p = nodes.new('ShaderNodeBsdfPrincipled')
    links.new(p.outputs[0], o.inputs[0])
    p.inputs['Base Color'].default_value  = (rgb[0], rgb[1], rgb[2], alpha)
    p.inputs['Metallic'].default_value    = metal
    p.inputs['Roughness'].default_value   = rough
    if alpha < 1.0:
        m.blend_method = 'BLEND'
        p.inputs['Alpha'].default_value   = alpha
    if emit_rgb:
        p.inputs['Emission Color'].default_value    = (emit_rgb[0], emit_rgb[1], emit_rgb[2], 1.0)
        p.inputs['Emission Strength'].default_value = 0.8
    return m

def cyl(r, h, verts=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False,
                          segments=verts, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new("cyl")
    bm.to_mesh(me); bm.free()
    return me

def cone(r1, r2, h, verts=32):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True,
                          segments=verts, radius1=r1, radius2=r2, depth=h)
    me = bpy.data.meshes.new("cone")
    bm.to_mesh(me); bm.free()
    return me

def box(sx, sy, sz):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    me = bpy.data.meshes.new("box")
    bm.to_mesh(me); bm.free()
    return me

def sphere(r, segs=32, rings=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    me = bpy.data.meshes.new("sphere")
    bm.to_mesh(me); bm.free()
    return me

def obj(mesh, name, material, loc=(0,0,0), rot=(0,0,0), scl=(1,1,1)):
    o = bpy.data.objects.new(name, mesh)
    o.location        = loc
    o.rotation_euler  = rot
    o.scale           = scl
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(material)
    return o

def export_selected(filepath):
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_materials='EXPORT',
        export_yup=True,
    )
    sz = os.path.getsize(filepath) if os.path.exists(filepath) else 0
    print(f"  OK  {os.path.basename(filepath)}  ({sz//1024} KB)")

def select_all_export(filename):
    bpy.ops.object.select_all(action='SELECT')
    export_selected(os.path.join(OUTPUT_DIR, filename))

# ─── 1. FALCON 9 ──────────────────────────────────────────────────────────────

def build_falcon9():
    print("\n[1/4] Falcon 9...")
    clear_all()

    mW = mat("white",  (.96,.96,.96), metal=0.35, rough=0.22)
    mB = mat("black",  (.04,.04,.05), metal=0.80, rough=0.20)
    mN = mat("nozzle", (.30,.26,.22), metal=0.95, rough=0.28)
    mI = mat("inter",  (.10,.10,.12), metal=0.60, rough=0.35)
    mL = mat("logo",   (.04,.04,.04), metal=0.00, rough=0.90)
    mA = mat("aluminum", (.48,.50,.54), metal=0.92, rough=0.18)
    mR = mat("thermal", (.16,.055,.035), metal=0.20, rough=0.62)

    # Primary tanks and fairing.  Separate sections give the vehicle the
    # recognizable Falcon-style production hardware rather than one plain tube.
    obj(cyl(1.85,42,64),  "S1_Body",    mW, loc=(0,0,21))
    obj(sphere(1.85,48,24), "S1_LOXDome", mW, loc=(0,0,41.0), scl=(1,1,.23))
    obj(sphere(1.85,48,24), "S1_FuelDome", mW, loc=(0,0,1.1), scl=(1,1,.16))
    obj(cyl(1.87,0.8,64), "S1_Band",    mB, loc=(0,0,41.6))
    obj(cyl(1.85,4,64),   "Interstage", mI, loc=(0,0,44))
    obj(cyl(1.85,14,64),  "S2_Body",    mW, loc=(0,0,53))
    obj(sphere(1.85,48,24), "S2_Dome", mW, loc=(0,0,59.6), scl=(1,1,.21))
    obj(cone(1.85,0,13,64),"Fairing",   mW, loc=(0,0,66.5))
    obj(sphere(.3,16,8),  "Tip",        mB, loc=(0,0,73))

    # Tank weld rings, access collars and a small thermal-protection skirt.
    # These catch light in close launch-pad shots and remove the toy-like finish.
    for z in [5.0, 10.5, 16.0, 21.5, 27.0, 32.5, 37.0, 48.0, 52.0, 56.0]:
        obj(cyl(1.87,.09,64), f"WeldRing{z}", mA, loc=(0,0,z))
    for z in [3.0, 39.0, 46.1, 61.1]:
        obj(cyl(1.90,.34,64), f"ThermalCollar{z}", mR, loc=(0,0,z))
    obj(cyl(1.88,1.0,64), "SootSkirt", mR, loc=(0,0,2.2))

    # Grid fins: thick root struts plus crossed vanes so they read as actual
    # hypersonic-control hardware instead of flat black blocks.
    for a in [0,90,180,270]:
        r = math.radians(a)
        obj(box(.18,1.9,1.7), f"GFin{a}", mB,
            loc=(math.sin(r)*2.05, math.cos(r)*2.05, 39.5),
            rot=(0,0,r))
        for vane in [-.55, -.18, .18, .55]:
            obj(box(.10,1.7,.055), f"GridVane{a}_{vane}", mB,
                loc=(math.sin(r)*2.19, math.cos(r)*2.19, 39.5+vane),
                rot=(0,0,r))

    # Four deployed-style leg struts give a convincing pad silhouette.
    for a in [45,135,225,315]:
        r = math.radians(a)
        obj(box(.16,.13,7.2), f"Leg{a}", mB,
            loc=(math.sin(r)*2.6, math.cos(r)*2.6, 3.5),
            rot=(0,math.radians(-12),r))
        obj(box(.85,.16,.15), f"Foot{a}", mB,
            loc=(math.sin(r)*3.25, math.cos(r)*3.25, .6), rot=(0,0,r))

    # Octaweb engine section: one center bell plus eight surrounding Merlin-like
    # bells, each with a mount and turbopump housing.
    obj(cyl(1.8,.4,32), "EngMount", mB, loc=(0,0,.2))
    npos = [(0,0)] + [(math.sin(math.radians(i*45))*1.1,
                       math.cos(math.radians(i*45))*1.1) for i in range(8)]
    for i,(nx,ny) in enumerate(npos):
        obj(cyl(.28,.28,24), f"EngineMount{i}", mB, loc=(nx,ny,-.15))
        obj(cone(.34,.17,1.18,32), f"Noz{i}", mN, loc=(nx,ny,-.78))
        obj(sphere(.18,16,8), f"Pump{i}", mA, loc=(nx*.86,ny*.86,-.14), scl=(1,1,.65))

    # Vertical raceway / marking panel and small red service markings.
    obj(box(.05,.9,28), "Stripe", mL, loc=(1.86,0,25))
    obj(box(.052,.55,5.2), "ServiceMark", mR, loc=(1.865,.68,31.2))
    obj(box(.052,.55,2.8), "UpperMark", mR, loc=(1.865,.68,55.0))

    select_all_export("falcon9_rocket.glb")

# ─── 2. LAUNCH PAD ────────────────────────────────────────────────────────────

def build_launch_pad():
    print("\n[2/4] Launch Pad...")
    clear_all()

    mC = mat("concrete", (.50,.48,.44), rough=0.92)
    mS = mat("steel",    (.40,.38,.35), metal=0.75, rough=0.45)
    mG = mat("ground",   (.20,.26,.15), rough=0.95)
    mD = mat("dark",     (.12,.10,.08), rough=0.98)

    obj(box(300,300,.5),  "Ground",    mG, loc=(0,0,-.25))
    obj(cyl(28,3,8),      "PadSlab",   mC, loc=(0,0,1.5))
    obj(box(10,50,6),     "Trench",    mD, loc=(0,0,-3))
    obj(cone(5,.5,4,4),   "Deflector", mC, loc=(0,0,-1))
    obj(box(5,5,80),      "TEL",       mS, loc=(0,0,40))

    for h in [20,40,60]:
        obj(box(20,.8,.8), f"BrH{h}", mS, loc=(0,0,h))
        obj(box(.8,20,.8), f"BrV{h}", mS, loc=(0,0,h))

    for h,ln in [(18,18),(30,14),(48,10)]:
        obj(box(ln,1.2,1), f"Arm{h}", mS, loc=(ln/2+2.5,0,h))

    for px,py in [(6,6),(-6,6),(6,-6),(-6,-6)]:
        obj(cyl(.3,10,8), f"Pipe{px}{py}", mS, loc=(px,py,8))

    select_all_export("launch_pad.glb")

# ─── 3. SATELLITE ─────────────────────────────────────────────────────────────

def build_satellite():
    print("\n[3/4] Satellite...")
    clear_all()

    mBd = mat("sat_body",    (.62,.65,.70), metal=0.85, rough=0.20)
    mPn = mat("sat_panel",   (.06,.12,.55), metal=0.20, rough=0.40)
    mGo = mat("sat_gold",    (.88,.72,.20), metal=0.10, rough=0.55)
    mAn = mat("sat_ant",     (.80,.78,.76), metal=0.90, rough=0.15)
    mDk = mat("sat_dark",    (.12,.12,.14), metal=0.95, rough=0.20)

    obj(box(2,1.6,2.4),    "Bus",  mBd)
    obj(box(.05,1.5,2.3),  "MLI_L",mGo, loc=(-1.03,0,0))
    obj(box(.05,1.5,2.3),  "MLI_R",mGo, loc=( 1.03,0,0))

    for s in [-1,1]:
        tag = 'L' if s<0 else 'R'
        obj(box(3.8,.06,1.6), f"Panel_{tag}", mPn, loc=(s*3.5,0,0))
        obj(cyl(.07,1.5,8), f"Yoke_{tag}", mAn,
            loc=(s*1.05,0,0), rot=(0,math.radians(90),0))

    obj(cone(.55,.48,.1,32), "HGA", mAn,
        loc=(0,-.95,.9), rot=(math.radians(30),0,0))
    obj(cyl(.04,.7,8), "HGABoom", mAn,
        loc=(0,-.72,.58), rot=(math.radians(30),0,0))

    for tx,ty in [(.6,.4),(-.6,.4),(.6,-.4),(-.6,-.4)]:
        obj(cone(.09,.05,.18,8), f"Thr{tx}", mDk, loc=(tx,ty,-1.3))

    obj(box(.4,.4,.25), "StarTracker", mBd, loc=(.9,0,1.25))

    select_all_export("satellite.glb")

# ─── 4. EARTH ─────────────────────────────────────────────────────────────────

def build_earth():
    print("\n[4/4] Earth...")
    clear_all()

    mE = mat("earth", (.08,.30,.68), metal=0.0, rough=0.75)
    mA = mat("atmo",  (.28,.55,1.0), metal=0.0, rough=1.0, alpha=0.12)

    obj(sphere(1.0,128,64), "EarthSphere", mE)
    obj(sphere(1.03,64,32), "Atmosphere",  mA)

    select_all_export("earth.glb")

# ─── RUN ──────────────────────────────────────────────────────────────────────

print("\n" + "="*50)
print("  Mission Architect — Model Generator v3")
print("="*50)

try:
    build_falcon9()
    build_launch_pad()
    build_satellite()
    build_earth()

    print("\n" + "="*50)
    print("  ALL DONE!")
    for f in ["falcon9_rocket.glb","launch_pad.glb","satellite.glb","earth.glb"]:
        p = os.path.join(OUTPUT_DIR, f)
        if os.path.exists(p):
            print(f"  OK  {f}  ({os.path.getsize(p)//1024} KB)")
        else:
            print(f"  MISSING  {f}")
    print("="*50)

except Exception as e:
    import traceback
    print("\n!!! ERROR !!!")
    traceback.print_exc()
    print("!!!!!!!!!!!!")
