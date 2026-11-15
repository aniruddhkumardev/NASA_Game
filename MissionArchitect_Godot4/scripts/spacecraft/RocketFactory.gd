class_name RocketFactory
extends RefCounted

## Shared procedural launch-vehicle builder. Produces the SAME 5 detailed rockets
## as the Builder viewport so the rocket chosen in the Builder is the one that
## appears during the launch cinematic. Geometry is built in local space with the
## nose tip near y=0 extending downward; the caller sets the container transform.
##
## NOTE: this mirrors the rocket code in SpacecraftBuilder.gd. If you change a
## rocket's silhouette here, update SpacecraftBuilder._build_rocket to match.

const ROCKET_PAINT_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.90);
uniform vec3 line_color : source_color = vec3(0.05, 0.05, 0.07);
uniform float rings = 9.0;
uniform float seams = 16.0;
uniform float metallic_v = 0.35;
uniform float rough_v = 0.45;

void fragment() {
	float ring = fract(UV.y * rings);
	float rd = min(ring, 1.0 - ring);
	float wy = fwidth(UV.y * rings) + 1e-5;
	float line_h = 1.0 - smoothstep(0.012 - wy, 0.012 + wy, rd);

	float seam = fract(UV.x * seams);
	float sd = min(seam, 1.0 - seam);
	float wx = fwidth(UV.x * seams) + 1e-5;
	float line_v = 1.0 - smoothstep(0.008 - wx, 0.008 + wx, sd);

	float line = clamp(max(line_h, line_v * 0.5), 0.0, 1.0);
	ALBEDO = mix(base_color, line_color, line * 0.40);
	METALLIC = metallic_v;
	ROUGHNESS = mix(rough_v, rough_v + 0.2, line);
}
"""

const FLAME_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec3 c_hot  : source_color = vec3(1.00, 0.97, 0.82);
uniform vec3 c_mid  : source_color = vec3(1.00, 0.52, 0.14);
uniform vec3 c_cool : source_color = vec3(0.55, 0.07, 0.02);
uniform float flicker = 11.0;
uniform float intensity = 1.25;

void fragment() {
	float v = UV.y;
	vec3 col = mix(c_cool, c_mid, smoothstep(0.0, 0.5, v));
	col = mix(col, c_hot, smoothstep(0.5, 0.92, v));
	float a = smoothstep(0.0, 0.22, v);
	float f = 0.82 + 0.18 * sin(TIME * flicker + UV.x * 26.0 + v * 9.0);
	ALBEDO = col * (0.9 + 1.5 * v) * f * intensity;
	ALPHA = a * f * 0.95;
}
"""

static var _mats_ready: bool = false
static var _paint_white: ShaderMaterial
static var _paint_black: ShaderMaterial
static var _paint_carbon: ShaderMaterial
static var _paint_orange: ShaderMaterial
static var _paint_steel: ShaderMaterial
static var _mat_bell: StandardMaterial3D
static var _mat_flame: ShaderMaterial
static var _mat_dark: StandardMaterial3D
static var _flame_enabled: bool = true


static func _ensure_mats() -> void:
	if _mats_ready:
		return
	_paint_white = _mat_paint(Color(0.85, 0.86, 0.89), 0.5, 0.5, 5.0, 12.0)
	_paint_black = _mat_paint(Color(0.05, 0.055, 0.07), 0.4, 0.4, 8.0, 16.0)
	_paint_carbon = _mat_paint(Color(0.15, 0.16, 0.19), 0.55, 0.34, 11.0, 20.0)
	_paint_orange = _mat_paint(Color(0.85, 0.40, 0.09), 0.3, 0.5, 9.0, 16.0)
	_paint_steel = _mat_paint(Color(0.72, 0.74, 0.78), 0.85, 0.32, 8.0, 20.0)
	_mat_bell = StandardMaterial3D.new()
	_mat_bell.albedo_color = Color(0.06, 0.06, 0.08)
	_mat_bell.metallic = 0.85
	_mat_bell.roughness = 0.4
	_mat_bell.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_dark = StandardMaterial3D.new()
	_mat_dark.albedo_color = Color(0.17, 0.18, 0.21)
	_mat_dark.metallic = 0.6
	_mat_dark.roughness = 0.5
	var fsh := Shader.new(); fsh.code = FLAME_SHADER
	_mat_flame = ShaderMaterial.new(); _mat_flame.shader = fsh
	_mats_ready = true


## Body paint for the given vehicle, using the SAME panel-line shader as the
## launch model so a spent stage / fairing reads as the same rocket family.
## Starship is bare stainless steel; everything else flies a white upper stage.
static func body_paint(id: String) -> Material:
	_ensure_mats()
	match id:
		"starship":
			return _paint_steel
		"electron":
			return _paint_carbon
		_:
			return _paint_white


## Dark accent paint (interstage / engine section / stencilled band) matching
## the launch model's treatment, so separation detail is consistent.
static func accent_paint() -> Material:
	_ensure_mats()
	return _paint_black


## Engine-bell material shared with the launch model.
static func bell_paint() -> Material:
	_ensure_mats()
	return _mat_bell


## Clears `parent` and builds the rocket for `id`. `with_flame` toggles the
## animated exhaust (disable it when the caller has its own engine FX).
static func build(parent: Node3D, id: String, with_flame: bool = true) -> void:
	_ensure_mats()
	_flame_enabled = with_flame
	for c in parent.get_children():
		c.queue_free()
	match id:
		"electron":
			_add_ogive(parent, 0.28, 0.85, Vector3(0, -0.9, 0), _paint_black)
			parent.add_child(_mi_cyl(0.29, 0.29, 0.45, _paint_white, Vector3(0, -1.12, 0)))
			parent.add_child(_mi_cyl(0.275, 0.275, 2.5, _paint_carbon, Vector3(0, -2.6, 0)))
			parent.add_child(_mi_cyl(0.29, 0.27, 0.35, _paint_carbon, Vector3(0, -4.0, 0)))
			_add_engine_cluster(parent, 0.05, 0.1, 0.32, Vector3(0, -4.16, 0), 0.15, 9, _mat_bell)
			_flame(parent, Vector3(0, -4.48, 0), 0.17, 1.5)
		"falcon9":
			_falcon_core(parent, Vector3.ZERO, true, true)
		"falcon_heavy":
			_falcon_core(parent, Vector3.ZERO, true, true)
			_falcon_core(parent, Vector3(-0.98, -1.3, 0), true, false)
			_falcon_core(parent, Vector3(0.98, -1.3, 0), true, false)
		"sls":
			parent.add_child(_mi_cyl(0.5, 0.5, 3.1, _paint_orange, Vector3(0, -2.75, 0)))
			_add_ogive(parent, 0.34, 1.15, Vector3(0, -1.2, 0), _paint_white)
			parent.add_child(_mi_cyl(0.52, 0.42, 0.4, _paint_black, Vector3(0, -4.5, 0)))
			_add_engine_cluster(parent, 0.1, 0.17, 0.5, Vector3(0, -4.68, 0), 0.22, 4, _mat_bell)
			_flame(parent, Vector3(0, -5.18, 0), 0.26, 1.9)
			for sx in [-0.92, 0.92]:
				_add_ogive(parent, 0.3, 0.8, Vector3(sx, -0.85, 0), _paint_black)
				parent.add_child(_mi_cyl(0.3, 0.3, 3.7, _paint_white, Vector3(sx, -3.1, 0)))
				for ry in [-1.6, -2.6, -3.6, -4.6]:
					parent.add_child(_mi_cyl(0.315, 0.315, 0.06, _mat_dark, Vector3(sx, ry, 0)))
				_add_bell(parent, 0.12, 0.28, 0.5, Vector3(sx, -4.95, 0), _mat_bell)
				_flame(parent, Vector3(sx, -5.45, 0), 0.22, 1.7)
		"starship":
			_add_ogive(parent, 0.62, 1.6, Vector3(0, -1.65, 0), _paint_steel)
			parent.add_child(_mi_cyl(0.62, 0.62, 1.7, _paint_steel, Vector3(0, -2.5, 0)))
			parent.add_child(_mi_cyl(0.628, 0.628, 0.12, _mat_dark, Vector3(0, -2.1, 0)))
			for sx in [-0.62, 0.62]:
				var ff := _mi_box(Vector3(0.06, 0.7, 0.42), _paint_steel, Vector3(sx, -2.2, 0))
				ff.rotation_degrees = Vector3(0, 0, -22.0 * sign(sx))
				parent.add_child(ff)
			parent.add_child(_mi_cyl(0.64, 0.64, 0.16, _paint_black, Vector3(0, -3.44, 0)))
			parent.add_child(_mi_cyl(0.62, 0.62, 1.9, _paint_steel, Vector3(0, -4.47, 0)))
			for sx in [-0.62, 0.62]:
				var af := _mi_box(Vector3(0.06, 0.9, 0.5), _paint_steel, Vector3(sx, -4.3, 0))
				af.rotation_degrees = Vector3(0, 0, -15.0 * sign(sx))
				parent.add_child(af)
			parent.add_child(_mi_cyl(0.62, 0.66, 0.4, _paint_black, Vector3(0, -5.5, 0)))
			_add_engine_cluster(parent, 0.08, 0.15, 0.45, Vector3(0, -5.68, 0), 0.4, 13, _mat_bell)
			_flame(parent, Vector3(0, -6.13, 0), 0.46, 2.2)
		_:
			_add_ogive(parent, 0.42, 1.1, Vector3(0, -1.15, 0), _paint_white)
			parent.add_child(_mi_cyl(0.42, 0.42, 2.8, _paint_white, Vector3(0, -3.15, 0)))
			parent.add_child(_mi_cyl(0.44, 0.36, 0.4, _paint_black, Vector3(0, -4.75, 0)))
			_add_engine_cluster(parent, 0.07, 0.13, 0.4, Vector3(0, -4.93, 0), 0.18, 5, _mat_bell)
			_flame(parent, Vector3(0, -5.33, 0), 0.22, 1.5)


## Builds the SPENT UPPER STAGE shown after stage separation, nose-up, reusing
## the SAME primitives and paint as `build()` so it reads unmistakably as the
## chosen vehicle's second stage: vehicle-coloured body, black interstage,
## vacuum engine bell, grid fins on the Falcon family, and an open payload
## fairing (mouth near local y=+4.4) that the stack rises out of during deploy.
static func build_upper_stage(parent: Node3D, id: String) -> void:
	_ensure_mats()
	var body := body_paint(id)
	var r := 0.62
	# Engine section and vacuum bell at the base.
	parent.add_child(_mi_cyl(r, r * 0.86, 0.7, _paint_black, Vector3(0, -3.6, 0)))
	_add_bell(parent, 0.30, 0.55, 0.8, Vector3(0, -4.15, 0), _mat_bell)
	# Main propellant body wearing the vehicle's own panel-line paint.
	parent.add_child(_mi_cyl(r, r, 4.6, body, Vector3(0, -1.1, 0)))
	# Dark interstage / stencilled band near the top of the stage.
	parent.add_child(_mi_cyl(r + 0.02, r + 0.02, 0.35, _paint_black, Vector3(0, 1.05, 0)))
	# Grid fins only on the steerable Falcon family (matches the launch core).
	if id == "falcon9" or id == "falcon_heavy":
		for sx in [-1.0, 1.0]:
			_add_grid_fin(parent, Vector3(sx * (r + 0.04), 0.4, 0.0), 0.42, _mat_dark)
	# Four small RCS thruster pods around the avionics ring.
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		parent.add_child(_mi_box(Vector3(0.12, 0.12, 0.2), _mat_dark,
			Vector3(cos(a) * (r + 0.05), 1.35, sin(a) * (r + 0.05))))
	# Adapter cone joining the stage top to the payload fairing.
	parent.add_child(_mi_cyl(0.92, r, 0.7, body, Vector3(0, 1.75, 0)))
	# The payload shroud, built as two real half-shells hinged at their base so the
	# deploy can peel them open like a clamshell and let the orbiter rise out of
	# the middle.  A single closed tube read as "a hole in a can", not "the head
	# opened", which is exactly the reference the user is holding this to.
	var fairing_mat := StandardMaterial3D.new()
	fairing_mat.albedo_color = Color(0.86, 0.88, 0.92)
	fairing_mat.metallic = 0.1
	fairing_mat.roughness = 0.55
	fairing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fair_prof := PackedVector2Array([
		Vector2(0.98, 0.0), Vector2(0.96, 0.7), Vector2(0.85, 1.6),
		Vector2(0.66, 2.4), Vector2(0.55, 2.8),
	])
	var half_f := Node3D.new()
	half_f.name = "FairingHalfF"
	half_f.position = Vector3(0, 2.05, 0)
	half_f.add_child(_make_revolve_arc(fair_prof, fairing_mat, 16, 0.0, PI))
	parent.add_child(half_f)
	var half_b := Node3D.new()
	half_b.name = "FairingHalfB"
	half_b.position = Vector3(0, 2.05, 0)
	half_b.add_child(_make_revolve_arc(fair_prof, fairing_mat, 16, PI, PI))
	parent.add_child(half_b)


static func _falcon_core(parent: Node3D, origin: Vector3, with_legs: bool, with_fairing: bool) -> void:
	var r := 0.4
	var nose_h := 1.6 if with_fairing else 0.6
	var nb := origin.y - nose_h
	_add_ogive(parent, r, nose_h, Vector3(origin.x, nb, origin.z), _paint_white)
	parent.add_child(_mi_cyl(r, r, 2.0, _paint_white, Vector3(origin.x, nb - 1.0, origin.z)))
	parent.add_child(_mi_cyl(r + 0.015, r + 0.015, 0.5, _paint_black, Vector3(origin.x, nb - 2.25, origin.z)))
	parent.add_child(_mi_cyl(r, r, 1.6, _paint_white, Vector3(origin.x, nb - 3.3, origin.z)))
	var es := nb - 4.35
	parent.add_child(_mi_cyl(r, r * 0.85, 0.7, _paint_black, Vector3(origin.x, es, origin.z)))
	for sx in [-1.0, 1.0]:
		_add_grid_fin(parent, Vector3(origin.x + sx * (r + 0.04), nb - 0.7, origin.z), 0.42, _mat_dark)
	if with_legs:
		for k in range(4):
			var a := TAU * float(k) / 4.0 + PI / 4.0
			parent.add_child(_mi_box(Vector3(0.07, 2.3, 0.07), _paint_black,
				Vector3(origin.x + cos(a) * r * 0.92, nb - 3.2, origin.z + sin(a) * r * 0.92)))
	_add_engine_cluster(parent, 0.055, 0.11, 0.42, Vector3(origin.x, es - 0.33, origin.z), 0.2, 9, _mat_bell)
	_flame(parent, Vector3(origin.x, es - 0.75, origin.z), 0.24, 1.7)


static func _flame(parent: Node3D, nozzle: Vector3, radius: float, length: float) -> void:
	if not _flame_enabled:
		return
	var outer := _mi_flame_cone(radius, radius * 0.10, length, _mat_flame, nozzle + Vector3(0, -length * 0.5, 0))
	outer.name = "FlameOuter"
	parent.add_child(outer)
	var core := _mi_flame_cone(radius * 0.55, radius * 0.04, length * 0.72, _mat_flame, nozzle + Vector3(0, -length * 0.36, 0))
	core.name = "FlameCore"
	parent.add_child(core)
	var light := OmniLight3D.new()
	light.name = "EngineGlow"
	light.position = nozzle + Vector3(0, -length * 0.25, 0)
	light.light_color = Color(1.0, 0.5, 0.16)
	light.light_energy = 3.6
	light.omni_range = 4.0
	light.shadow_enabled = false
	parent.add_child(light)


static func _mat_paint(base: Color, metallic: float, rough: float, rings: float, seams: float) -> ShaderMaterial:
	var sh := Shader.new(); sh.code = ROCKET_PAINT_SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("metallic_v", metallic)
	m.set_shader_parameter("rough_v", rough)
	m.set_shader_parameter("rings", rings)
	m.set_shader_parameter("seams", seams)
	return m


static func _mi_box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	return mi


static func _mi_cyl(r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = r_top; cm.bottom_radius = r_bot; cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi


static func _mi_flame_cone(top_r: float, bot_r: float, h: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = top_r; cm.bottom_radius = bot_r; cm.height = h
	cm.radial_segments = 16; cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _make_revolve(profile: PackedVector2Array, mat: Material, seg: int = 28) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last := profile.size() - 1
	var nrm := PackedVector2Array()
	for j in range(profile.size()):
		var tan: Vector2 = profile[mini(j + 1, last)] - profile[maxi(j - 1, 0)]
		if tan.length() < 1e-6:
			tan = Vector2(1.0, 0.0)
		nrm.append(Vector2(-tan.y, tan.x).normalized())
	for i in range(seg):
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var c0 := cos(a0); var s0 := sin(a0)
		var c1 := cos(a1); var s1 := sin(a1)
		for j in range(last):
			var p0 := profile[j]; var p1 := profile[j + 1]
			var q0 := nrm[j]; var q1 := nrm[j + 1]
			var v00 := Vector3(p0.x * c0, p0.y, p0.x * s0)
			var v01 := Vector3(p0.x * c1, p0.y, p0.x * s1)
			var v10 := Vector3(p1.x * c0, p1.y, p1.x * s0)
			var v11 := Vector3(p1.x * c1, p1.y, p1.x * s1)
			var n00 := Vector3(q0.x * c0, q0.y, q0.x * s0)
			var n01 := Vector3(q0.x * c1, q0.y, q0.x * s1)
			var n10 := Vector3(q1.x * c0, q1.y, q1.x * s0)
			var n11 := Vector3(q1.x * c1, q1.y, q1.x * s1)
			var u0 := float(i) / seg; var u1 := float(i + 1) / seg
			var t0 := float(j) / last; var t1 := float(j + 1) / last
			_tri(st, v00, n00, Vector2(u0, t0), v10, n10, Vector2(u0, t1), v11, n11, Vector2(u1, t1))
			_tri(st, v00, n00, Vector2(u0, t0), v11, n11, Vector2(u1, t1), v01, n01, Vector2(u1, t0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _tri(st: SurfaceTool, a: Vector3, na: Vector3, ta: Vector2, b: Vector3, nb: Vector3, tb: Vector2, c: Vector3, nc: Vector3, tc: Vector2) -> void:
	st.set_normal(na); st.set_uv(ta); st.add_vertex(a)
	st.set_normal(nb); st.set_uv(tb); st.add_vertex(b)
	st.set_normal(nc); st.set_uv(tc); st.add_vertex(c)


## Revolve a profile over only part of the full circle (start..start+span) so a
## payload shroud can be built as two genuine half-shells that hinge apart, the
## way a real fairing peels open to release the orbiter from inside it.
static func _make_revolve_arc(profile: PackedVector2Array, mat: Material, seg: int, start: float, span: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var last := profile.size() - 1
	var nrm := PackedVector2Array()
	for j in range(profile.size()):
		var tan: Vector2 = profile[mini(j + 1, last)] - profile[maxi(j - 1, 0)]
		if tan.length() < 1e-6:
			tan = Vector2(1.0, 0.0)
		nrm.append(Vector2(-tan.y, tan.x).normalized())
	for i in range(seg):
		var a0 := start + span * float(i) / seg
		var a1 := start + span * float(i + 1) / seg
		var c0 := cos(a0); var s0 := sin(a0)
		var c1 := cos(a1); var s1 := sin(a1)
		for j in range(last):
			var p0 := profile[j]; var p1 := profile[j + 1]
			var q0 := nrm[j]; var q1 := nrm[j + 1]
			var v00 := Vector3(p0.x * c0, p0.y, p0.x * s0)
			var v01 := Vector3(p0.x * c1, p0.y, p0.x * s1)
			var v10 := Vector3(p1.x * c0, p1.y, p1.x * s0)
			var v11 := Vector3(p1.x * c1, p1.y, p1.x * s1)
			var n00 := Vector3(q0.x * c0, q0.y, q0.x * s0)
			var n01 := Vector3(q0.x * c1, q0.y, q0.x * s1)
			var n10 := Vector3(q1.x * c0, q1.y, q1.x * s0)
			var n11 := Vector3(q1.x * c1, q1.y, q1.x * s1)
			var u0 := float(i) / seg; var u1 := float(i + 1) / seg
			var t0 := float(j) / last; var t1 := float(j + 1) / last
			_tri(st, v00, n00, Vector2(u0, t0), v10, n10, Vector2(u0, t1), v11, n11, Vector2(u1, t1))
			_tri(st, v00, n00, Vector2(u0, t0), v11, n11, Vector2(u1, t1), v01, n01, Vector2(u1, t0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _add_ogive(parent: Node, radius: float, height: float, base: Vector3, mat: Material) -> void:
	var prof := PackedVector2Array([
		Vector2(0.001, height),
		Vector2(radius * 0.5, height * 0.72),
		Vector2(radius * 0.8, height * 0.42),
		Vector2(radius * 0.96, height * 0.14),
		Vector2(radius, 0.0),
	])
	var mi := _make_revolve(prof, mat)
	mi.position = base
	parent.add_child(mi)


static func _add_bell(parent: Node, throat_r: float, exit_r: float, length: float, center: Vector3, mat: Material) -> void:
	var prof := PackedVector2Array([
		Vector2(throat_r, 0.0),
		Vector2(throat_r * 1.05, -length * 0.12),
		Vector2(exit_r * 0.62, -length * 0.5),
		Vector2(exit_r * 0.86, -length * 0.82),
		Vector2(exit_r, -length),
	])
	var mi := _make_revolve(prof, mat, 20)
	mi.position = center
	parent.add_child(mi)


static func _add_engine_cluster(parent: Node, throat_r: float, exit_r: float, length: float, center: Vector3, ring_r: float, count: int, mat: Material) -> void:
	_add_bell(parent, throat_r, exit_r, length, center, mat)
	if count > 1:
		var n := count - 1
		for i in range(n):
			var a := TAU * float(i) / n
			_add_bell(parent, throat_r, exit_r, length, center + Vector3(cos(a) * ring_r, 0.0, sin(a) * ring_r), mat)


static func _add_grid_fin(parent: Node, pos: Vector3, size: float, mat: Material) -> void:
	for k in range(4):
		parent.add_child(_mi_box(Vector3(size, size, 0.02), mat, pos + Vector3(0, 0, -size * 0.5 + size * k / 3.0)))
	parent.add_child(_mi_box(Vector3(0.03, size, size), mat, pos))
