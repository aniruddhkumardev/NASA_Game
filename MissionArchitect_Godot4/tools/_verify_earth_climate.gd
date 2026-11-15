extends SceneTree

## Live visual verification for the upgraded Earth Climate Sentinel.
##
## Runs in normal window rendering (not headless), flies the survey, and saves
## four screenshots: orbit with pulsing unobserved target markers, orbit after
## real events are captured (green ✅ pins), the mission report data-return
## manifest, and the builder instrument cards naming their NASA sensors.
##
## Usage:
##   $env:MA_MISSION="earth_climate"
##   godot --path . -s res://tools/_verify_earth_climate.gd

var frames := 0
var gm = null
var sim = null
var configured := false
var phase := "orbit"          # orbit -> captured -> report -> builder -> done
var results: Array[String] = []
var settle := 0

func _initialize() -> void:
	# With -s the project's main scene is not loaded automatically; ask for the
	# orbital operations scene directly.
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(delta: float) -> bool:
	frames += 1
	if not configured:
		if frames < 2:
			return false
		gm = root.get_node_or_null("/root/GameManager")
		sim = root.get_node_or_null("/root/SimulationEngine")
		if gm == null or sim == null or current_scene == null:
			if frames > 60:
				_finish(["ABORT: autoload/scene missing"])
				return true
			return false
		_configure()
		configured = true
		return false

	match phase:
		"orbit":
			# Manual steps run at 3600× (set in _configure); 300 × 57.6 s per
			# probe frame walks the precessing track over the targets quickly.
			for i in range(300):
				sim._process(0.016)
			if int(sim.state.get("targets_captured", 0)) >= 3:
				_check_markers()
				var layer = current_scene.find_child("ClimateFlyoverLayer", true, false)
				_assert(layer != null, "flyover UI layer built")
				settle = frames + 12
				phase = "flyover_shot"
			if frames > 3000:
				_assert(false, "TIMEOUT: no captures after 3000 frames")
				_finish(results)
				return true
		"flyover_shot":
			# Let the panel and the camera lerp land on a few rendered frames,
			# then shoot the cinematic mid-flight.
			if frames >= settle:
				var panel = current_scene.find_child("PanelContainer", true, false)
				_assert(panel != null and panel.visible, "flyover data card is on screen")
				_shot("_diag_earth_flyover.png")
				_shot("_diag_earth_captured.png")
				phase = "captured"
		"captured":
			# Spread the fast-forward over frames; a single-frame burst would stall
			# the live OrbitMission UI listeners on every emitted event.
			for i in range(300):
				sim._process(0.016)
			if int(sim.state.get("day", 0)) >= 40 or frames > 1200:
				_assert(int(sim.state.get("targets_captured", 0)) >= 3,
					"captured>=3 (got %d)" % int(sim.state.get("targets_captured", 0)))
				_assert(absf(float(sim.state.get("nodal_precession_deg_day", 0.0)) - 0.9856) < 0.02,
					"J2 drift ≈ sun-sync (got %.4f)" % float(sim.state.get("nodal_precession_deg_day", 0.0)))
				sim._end_mission()   # OrbitMission will hop to the report itself
				settle = frames + 240
				phase = "report"
		"report":
			var rn := String(current_scene.name)
			if "Report" in rn or "report" in rn:
				_assert(true, "auto-switched to report (scene=%s)" % rn)
				_shot("_diag_earth_report.png")
				change_scene_to_file("res://scenes/builder/builder.tscn")
				settle = frames + 90
				phase = "builder"
			elif frames >= settle:
				_assert(false, "auto-switch stalled (scene=%s); manual switch" % rn)
				change_scene_to_file("res://scenes/ui/mission_report.tscn")
				settle = frames + 120
				phase = "report_manual"
		"report_manual":
			if frames >= settle:
				_shot("_diag_earth_report.png")
				change_scene_to_file("res://scenes/builder/builder.tscn")
				settle = frames + 90
				phase = "builder"
		"builder":
			if frames >= settle:
				_shot("_diag_earth_builder.png")
				var ok := true
				for m in gm.missions:
					if m.get("id", "") == "earth_climate":
						ok = (m.get("sensor_analogs", {}) as Dictionary).size() == 6
				_assert(ok, "sensor_analogs map has 6 entries")
				_finish(results)
				return true
	return false

func _configure() -> void:
	var cfg = gm.spacecraft_config
	cfg["bus"] = {"data_storage": 400.0, "reliability": 0.93}
	cfg["comms"] = {"bandwidth_mbps": 10.0}
	cfg["instruments"] = []
	for want in ["thermal", "radar", "spectrometer"]:
		for c in gm.components.get("instruments", []):
			if String(c.get("id", "")) == want:
				cfg["instruments"].append(c.duplicate(true))
	cfg["rocket"] = {"reliability": 0.95}
	cfg["total_data_rate"] = 20.0
	cfg["total_science_per_orbit"] = 30.0
	cfg["total_power_gen"] = 320.0
	cfg["total_power_draw"] = 150.0
	cfg["battery_capacity"] = 1500.0
	cfg["total_cost"] = 118.0
	# The probe drives the engine itself; pick the fastest honest sampling rate.
	sim.set_time_scale(4)

func _check_markers() -> void:
	var root_node = current_scene.find_child("ClimateSurveyTargets", true, false)
	_assert(root_node != null, "ClimateSurveyTargets node exists in orbit scene")
	if root_node != null:
		_assert(root_node.get_child_count() == 6, "6 survey pins built (got %d)" % root_node.get_child_count())

func _assert(cond: bool, label: String) -> void:
	results.append(("PASS: " if cond else "FAIL: ") + label)

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png("res://tools/" + name)
	results.append("SHOT: %s err=%d %dx%d" % [name, err, img.get_width(), img.get_height()])

func _finish(lines: Array[String]) -> void:
	for l in lines:
		print(l)
	var f := FileAccess.open("res://tools/_earth_verify_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
