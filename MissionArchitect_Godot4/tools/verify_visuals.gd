extends SceneTree

## Visual QA harness: loads one scene, waits for it to settle, runs structural
## assertions and saves a screenshot. One scene per invocation.
##
## Usage:
##   godot --path . -s res://tools/verify_visuals.gd -- <launch|lunar|transfer|mars_launch|mars_orbit|mars_transfer|mars_surface>
##
## Results (PASS/FAIL lines) are also written to res://tools/_verify_result.txt.

var frames := 0
var wait_frames := 300
var scene_key := ""
var scene_path := ""
var scene_node: Node = null
var results: Array[String] = []
var scene_requested := false

func _autoload(node_name: String) -> Node:
	return root.get_node_or_null(node_name)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	scene_key = args[0] if args.size() > 0 else "launch"
	match scene_key:
		"lunar":
			scene_path = "res://scenes/lunar/lunar_mission.tscn"
		"transfer":
			scene_path = "res://scenes/lunar/lunar_transfer.tscn"
		"mars_launch":
			scene_path = "res://scenes/launch/launch.tscn"
		"mars_orbit":
			scene_path = "res://scenes/orbit/orbit.tscn"
			wait_frames = 120
		"mars_transfer":
			scene_path = "res://scenes/mars/mars_transfer.tscn"
		"missionselect":
			scene_path = "res://scenes/ui/mission_select.tscn"
			wait_frames = 120
		"mars_surface":
			scene_path = "res://scenes/mars/mars_mission.tscn"
			wait_frames = 180
		_:
			scene_key = "launch"
			scene_path = "res://scenes/launch/launch.tscn"

func _select_mars(phase_name: String) -> bool:
	var gm := _autoload("GameManager")
	if gm == null:
		return false
	for m in gm.missions:
		if m.get("id", "") == "mars_orbiter":
			gm.current_mission = m.duplicate(true)
			gm._init_spacecraft_config()
			break
	# Phase enum: MAIN_MENU=0, HANGAR=1, BUILDER=2, LAUNCH=3, ORBIT=4
	gm.current_phase = 4 if phase_name == "ORBIT" else 3
	gm.phase_changed.emit(gm.current_phase)
	return true

func _process(_delta: float) -> bool:
	if not scene_requested:
		if scene_key.begins_with("mars"):
			var mars_phase := "LAUNCH" if scene_key == "mars_launch" else "ORBIT"
			if not _select_mars(mars_phase):
				return false
		change_scene_to_file(scene_path)
		scene_requested = true
		return false
	frames += 1
	if scene_node == null:
		scene_node = current_scene
		if scene_node == null:
			return false
	if frames != wait_frames:
		return false

	match scene_key:
		"launch":
			_test_launch(scene_node)
		"lunar":
			_test_lunar(scene_node)
		"transfer":
			_test_transfer(scene_node)
		"mars_launch":
			_test_mars_launch(scene_node)
		"mars_orbit":
			_test_mars_orbit(scene_node)
		"mars_transfer":
			_test_mars_transfer(scene_node)
		"mars_surface":
			_test_mars_surface(scene_node)
		"missionselect":
			_test_mission_select(scene_node)

	_save_shot()

	var f := FileAccess.open("res://tools/_verify_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(results) + "\n")
	f.close()

	quit()
	return false

func _check(name: String, ok: bool) -> void:
	results.append("[%s] %s %s" % ["PASS" if ok else "FAIL", scene_key, name])

func _count_meshes(root: Node) -> int:
	var found := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			found += 1
		found += _count_meshes(child)
	return found

func _test_mission_select(s: Node) -> void:
	_check("script attached", s.get_script() != null)
	_check("cards built (>0)", s.get("_card_data").size() > 0)
	var gm := _autoload("GameManager")
	var missions := 0
	if gm:
		missions = gm.missions.size()
	_check("GameManager missions present", missions > 0)
	var begin_btn: Node = s.get("begin_btn")
	_check("begin button wired", begin_btn != null and begin_btn.button_pressed == false)

func _test_launch(s: Node) -> void:
	var rocket := s.get_node_or_null("Rocket")
	_check("rocket node exists", rocket != null)
	if rocket:
		_check("rocket on pad (y=7)", absf(rocket.position.y - 7.0) < 0.01)
	var script_ok: bool = s.get_script() != null and s.get("rocket") != null
	_check("LaunchSequence script attached & ready", script_ok)
	var cam: Node3D = s.get("active_camera")
	_check("pad camera active", cam != null and cam.name == "CamPad")
	var complex: Node3D = s.get_node_or_null("LaunchComplex")
	if complex:
		_check("tower greebles attached (>40 meshes)", _count_meshes(complex) > 40)
		_check("pad beacon exists", complex.get_node_or_null("PadBeacon") != null)
	else:
		_check("LaunchComplex exists", false)

func _test_lunar(s: Node) -> void:
	_check("script attached", s.get_script() != null)
	var moon: MeshInstance3D = s.get("moon")
	if moon:
		var mat: StandardMaterial3D = moon.material_override
		_check("regolith override applied", mat != null)
		if mat:
			_check("anisotropic filtering", mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
		var mesh: Mesh = moon.mesh
		if mesh:
			var arrays: Array = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check("displaced terrain cratered (10k+ verts)", verts.size() > 10000)
		else:
			_check("terrain mesh built", false)
	else:
		_check("moon surface found", false)
	var scout: Node3D = s.get("scout")
	_check("scout exists (in orbit phase)", scout != null and not s.get("landed"))
	_check("vikram subtree built", s.get_node_or_null("LunarScout/VikramLander") != null)

func _test_transfer(s: Node) -> void:
	_check("script attached", s.get_script() != null)
	_check("earth rendered", s.get("earth") != null)
	_check("moon rendered", s.get("moon") != null)
	_check("transfer vehicle built", s.get("vehicle") != null)
	_check("transfer arc exists", s.get("transfer_arc") != null)
	var cinematic_active: bool = s.get("active")
	_check("cinematic auto-started", cinematic_active)

func _test_mars_launch(s: Node) -> void:
	var gm := _autoload("GameManager")
	_check("mars mission selected", gm != null and gm.is_mars_mission())
	_check("mars_payload flag", bool(s.get("mars_payload")))
	_check("Earth pad gravity (~9.81)", absf(float(s.get("surface_gravity")) - 9.80665) < 0.01)
	_check("Earth radius (not Mars 3389.5)", absf(float(s.get("body_radius_km")) - 6371.0) < 0.1)
	var rocket := s.get_node_or_null("Rocket")
	_check("rocket on Earth pad (y=7)", rocket != null and absf(rocket.position.y - 7.0) < 0.01)
	var sky: ProceduralSkyMaterial = s.get("sky_material")
	if sky:
		_check("Earth blue sky (not butterscotch)", sky.sky_top_color.b > sky.sky_top_color.r)
	else:
		_check("Earth sky material present", false)
	_check("LaunchComplex still Earth pad", s.get_node_or_null("LaunchComplex") != null)
	_check("no Amazonis terrain node", s.get_node_or_null("MarsTerrain") == null)

func _test_mars_orbit(s: Node) -> void:
	var gm := _autoload("GameManager")
	_check("mars mission selected", gm != null and gm.is_mars_mission())
	_check("mars_operations enabled", bool(s.get("mars_operations")))
	var globe: MeshInstance3D = s.get("earth_sphere")
	if globe and globe.material_override:
		_check("Mars shader on globe", globe.material_override is ShaderMaterial)
	else:
		_check("Mars shader on globe", false)
	var atmo: MeshInstance3D = s.get("earth_atmosphere")
	if atmo and atmo.material_override is StandardMaterial3D:
		var atmo_mat: StandardMaterial3D = atmo.material_override
		_check("thin rusty atmosphere", atmo_mat.albedo_color.r > atmo_mat.albedo_color.b)
	else:
		_check("thin rusty atmosphere", false)
	var sun: DirectionalLight3D = s.get("sun_light")
	_check("warm Mars sunlight", sun != null and sun.light_color.r > sun.light_color.b)
	_check("Mars climate imager payload", s.get_node_or_null("Satellite/MarsClimateImager") != null)
	var title: Label = s.get("arrival_title")
	var title_text := title.text if title else ""
	_check("Mars arrival overlay", "MARS" in title_text)
	var sim := _autoload("SimulationEngine")
	var period: float = float(sim.orbit_period_seconds) if sim else 0.0
	# Mars 400 km circular period is ~2.0 hours (about 7200s), not LEO ~95 min.
	_check("Mars Kepler period (~2h)", period > 6000.0 and period < 9000.0)

func _test_mars_transfer(s: Node) -> void:
	var gm := _autoload("GameManager")
	_check("mars mission selected", gm != null and gm.is_mars_mission())
	_check("script attached", s.get_script() != null)
	_check("earth rendered", s.get("earth") != null)
	_check("mars globe rendered", s.get("mars") != null)
	_check("cruise vehicle built", s.get("vehicle") != null)
	_check("transfer arc exists", s.get("transfer_arc") != null)
	_check("cinematic auto-started", bool(s.get("active")))

func _test_mars_surface(s: Node) -> void:
	var gm := _autoload("GameManager")
	_check("mars mission selected", gm != null and gm.is_mars_mission())
	_check("script attached", s.get_script() != null)
	_check("terrain mesh built", s.get("terrain") != null)
	_check("lander node exists", s.get("lander") != null)
	_check("Ares lander subtree", s.get_node_or_null("ClimateLander/AresLander") != null)
	_check("still in descent (not landed yet)", s.get("landed") != true)
	var sky_env: WorldEnvironment = s.get_node_or_null("WorldEnvironment")
	if sky_env and sky_env.environment and sky_env.environment.sky:
		var sky_mat = sky_env.environment.sky.sky_material
		if sky_mat is ProceduralSkyMaterial:
			_check("butterscotch Mars sky", sky_mat.sky_top_color.r > sky_mat.sky_top_color.b)
		else:
			_check("butterscotch Mars sky", false)
	else:
		_check("butterscotch Mars sky", false)

func _save_shot() -> void:
	var img := root.get_texture().get_image()
	var out := "res://tools/_diag_%s.png" % scene_key
	img.save_png(out)
