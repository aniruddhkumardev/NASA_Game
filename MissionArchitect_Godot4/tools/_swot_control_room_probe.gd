extends SceneTree

## Live verification for the SWOT surface-water survey and control room.
## Flies the Earth mission with the radar payload, waits for KaRIn swaths to be
## scanned and downlinked, opens the control room, and saves a screenshot.

var gm = null
var sim = null
var frames := 0
var configured := false
var phase := 0
var settle := 0
var results: Array[String] = []

func _initialize() -> void:
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if not configured:
		if frames < 3:
			return false
		gm = root.get_node_or_null("/root/GameManager")
		sim = root.get_node_or_null("/root/SimulationEngine")
		if gm == null or sim == null or current_scene == null:
			if frames > 180:
				_finish(["ABORT: autoload/scene missing"])
				return true
			return false
		_configure()
		configured = true
		return false

	match phase:
		0:
			for i in range(80000):
				sim._process(0.016)
			var scanned: int = int(sim.state.get("swot_scanned", 0))
			var received: int = int(sim.state.get("swot_received", 0))
			print("PROBE day %d · scanned %d · received %d · classes %s" % [
				int(sim.state.get("day", 0)), scanned, received,
				str(sim.state.get("swot_classes_scanned", {}))])
			if (scanned >= 3 and received >= 1) or int(sim.state.get("day", 0)) >= 120 or frames > 2400:
				phase = 1
		1:
			_check_nodes()
			var cr = current_scene.find_child("SwotControlRoom", true, false)
			if cr == null:
				_finish(results)
				return true
			current_scene._toggle_control_room()
			settle = frames + 45
			phase = 2
		2:
			if frames >= settle:
				var cr = current_scene.find_child("SwotControlRoom", true, false)
				_assert(cr != null and cr.visible, "control room open and visible")
				if cr != null:
					cr.update_data({
						"state": sim.state,
						"clock": "T+ probe",
						"sat_lat": 20.0,
						"sat_lon": -60.0,
						"time_scale": 3600.0,
					})
				_shot("_diag_swot_control_room.png")
				phase = 3
		3:
			_finish(results)
			return true
	return false

func _configure() -> void:
	var mission: Dictionary = gm.missions[0].duplicate(true)
	assert(String(mission.get("id", "")) == "earth_climate")
	gm.current_mission = mission
	var cfg = gm.spacecraft_config
	cfg["bus"] = {"data_storage": 900.0, "reliability": 0.93}
	cfg["comms"] = {"bandwidth_mbps": 10.0}
	cfg["instruments"] = [
		_find_comp("instruments", "thermal"),
		_find_comp("instruments", "radar"),
		_find_comp("instruments", "spectrometer"),
	]
	cfg["rocket"] = {"reliability": 0.95}
	cfg["total_data_rate"] = 20.0
	cfg["total_science_per_orbit"] = 30.0
	cfg["total_power_gen"] = 320.0
	cfg["total_power_draw"] = 150.0
	cfg["battery_capacity"] = 1500.0
	cfg["total_cost"] = 118.0
	# The orbit scene already started a run in _ready with the menu-era config;
	# restart so the radar payload and SWOT state are the ones under test.
	sim.start_simulation(20261106)
	sim.set_time_scale(4)

func _find_comp(list_name: String, id: String) -> Dictionary:
	for c in gm.components.get(list_name, []):
		if String(c.get("id", "")) == id:
			return c.duplicate(true)
	return {}

func _check_nodes() -> void:
	var water_root = current_scene.find_child("SwotWaterTargets", true, false)
	_assert(water_root != null, "SwotWaterTargets node exists")
	if water_root != null:
		_assert(water_root.get_child_count() == 6, "6 SWOT water pins built (got %d)" % water_root.get_child_count())
	_assert(current_scene.find_child("SwotKaRInScanBeam", true, false) != null, "KaRIn scan beam created")
	_assert(current_scene.find_child("SwotFootprintRing", true, false) != null, "KaRIn footprint ring created")
	_assert(current_scene.find_child("ControlRoomButton", true, false) != null, "control room button added to HUD")
	var screens = current_scene.find_child("SwotControlRoom", true, false)
	_assert(screens != null, "SwotControlRoom built")
	_assert(int(sim.state.get("swot_scanned", 0)) >= 3,
		"3+ SWOT water sites scanned (got %d)" % int(sim.state.get("swot_scanned", 0)))
	_assert(int(sim.state.get("swot_received", 0)) >= 1,
		"1+ records downlinked to control room (got %d)" % int(sim.state.get("swot_received", 0)))
	var classes: Dictionary = sim.state.get("swot_classes_scanned", {})
	_assert(int(classes.get("ocean", 0)) > 0 and int(classes.get("lake", 0)) > 0 and int(classes.get("river", 0)) > 0,
		"ocean, lake and river all scanned (%s)" % str(classes))
	var objectives: Array = sim.state.get("objectives_done", [])
	var want := "Scan ocean, lake and river surfaces with SWOT KaRIn"
	_assert(objectives.has(want), "SWOT objective completed")

func _assert(cond: bool, label: String) -> void:
	results.append(("PASS: " if cond else "FAIL: ") + label)

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png("res://tools/" + name)
	results.append("SHOT: %s err=%d %dx%d" % [name, err, img.get_width(), img.get_height()])

func _finish(lines: Array[String]) -> void:
	for l in lines:
		print(l)
	var f := FileAccess.open("res://tools/_swot_probe_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit(0)
