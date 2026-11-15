## Orbit globes / live-accent verification probe.
##
## Loads the real orbit scene and asserts the new interaction and colour rules:
##   • wheel zoom dollies the exterior camera closer and anchors on the pointer
##   • the globe uses the 8k Blue Marble map with anisotropic filtering
##   • the satellite model carries its gold / silver / blue spacecraft palette
##   • live numeric readouts hold the sanctioned red accent and no mono shader
##
## Run:
##   $env:MA_MISSION="earth_climate"
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 `
##         --script res://tools/_orbit_globe_probe.gd

extends SceneTree

var frames := 0
var phase := 0
var target: Node = null
var home_distance := 0.0
var failures: Array[String] = []

func _initialize() -> void:
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 8:
		target = current_scene
		if target and target.has_method("_finish_orbit_arrival"):
			# Skip the arrival film so the probe exercises the operations view.
			target._finish_orbit_arrival()
		return false
	if frames == 20 and target:
		home_distance = float(target.view_distance)
		var before: Vector3 = target.mission_camera.global_position
		target._zoom_step(1.0, Vector2(640.0, 360.0))
		print("PROBE zoom before=%s dist=%.2f target=%.2f" % [
			before, home_distance, float(target.view_distance_target)])
		if float(target.view_distance_target) >= home_distance:
			failures.append("wheel zoom did not reduce view_distance_target")
		phase = 1
		return false
	if frames == 90 and phase == 1:
		var dist := float(target.view_distance)
		var cam: Vector3 = target.mission_camera.global_position
		print("PROBE zoom after dist=%.2f cam=%s" % [dist, cam])
		if dist >= home_distance - 0.5:
			failures.append("camera did not dolly in")
		# Cursor anchor: a ray through the globe centre must hit the surface.
		var hit: Vector3 = target._earth_hit_direction(Vector2(640.0, 360.0))
		print("PROBE cursor_hit=%s" % hit)
		if hit == Vector3.ZERO:
			failures.append("cursor ray missed the globe")
		_check_earth()
		_check_satellite()
		_check_live()
		var ok := failures.is_empty()
		if not ok:
			print("PROBE FAILURES: %s" % "; ".join(failures))
		print("PROBE RESULT ok=%s" % str(ok))
		quit(0 if ok else 1)
		return true
	return false

func _check_earth() -> void:
	var mesh := target._g("Earth/EarthMesh") as MeshInstance3D
	if mesh == null:
		failures.append("EarthMesh missing")
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		failures.append("Earth has no material_override")
		return
	var path := mat.albedo_texture.resource_path if mat.albedo_texture else "none"
	print("PROBE earth texture=%s filter=%d size=%s" % [
		path, int(mat.texture_filter), mat.albedo_texture.get_size() if mat.albedo_texture else Vector2i.ZERO])
	if not path.ends_with("earth-blue-marble-8k.jpg"):
		failures.append("Earth texture is not the 8k map: " + path)
	if mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
		failures.append("Earth texture filter is not anisotropic")
	if mesh.mesh is SphereMesh and (mesh.mesh as SphereMesh).radial_segments < 96:
		failures.append("Earth sphere is too coarse for close zoom")

func _check_satellite() -> void:
	var model: Node = target._g("Satellite/SatelliteModel")
	if model == null:
		failures.append("SatelliteModel missing")
		return
	var gold := 0
	var blue := 0
	var silver := 0
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var sm := mi.material_override as StandardMaterial3D
		if sm == null:
			continue
		var n := String(mi.name)
		print("PROBE sat %-12s albedo=%s" % [n, sm.albedo_color])
		if sm.albedo_color.r > 0.9 and sm.albedo_color.g > 0.55 and sm.albedo_color.b < 0.45:
			gold += 1
		if sm.albedo_color.b > 0.4 and sm.albedo_color.b > sm.albedo_color.r * 2.0:
			blue += 1
		if sm.albedo_color.r > 0.7 and sm.albedo_color.g > 0.7 and sm.albedo_color.b > 0.7:
			silver += 1
	print("PROBE sat palette gold=%d silver=%d blue=%d" % [gold, silver, blue])
	if gold < 2 or blue < 2 or silver < 1:
		failures.append("satellite palette incomplete")

func _check_live() -> void:
	var live := 0
	var bad: Array[String] = []
	for item in root.find_children("*", "CanvasItem", true, false):
		if not item.has_meta("missionforge_live"):
			continue
		live += 1
		if not (item is Label):
			continue
		var label := item as Label
		var c: Color = label.get_theme_color("font_color")
		if absf(c.r - 1.0) > 0.02 or absf(c.g - 0.30) > 0.03 or absf(c.b - 0.26) > 0.03:
			bad.append("%s=%s" % [label.name, c])
		if label.material != null:
			bad.append("%s still carries a UI material" % label.name)
	print("PROBE live_labels=%d bad=%d" % [live, bad.size()])
	if live < 10:
		failures.append("too few live-accent labels (%d)" % live)
	if not bad.is_empty():
		failures.append("live accent wrong: " + ", ".join(bad.slice(0, 6)))
