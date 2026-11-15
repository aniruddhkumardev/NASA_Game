extends SceneTree

## Temporary verification harness for the upgraded Earth Climate Sentinel survey.
##
## It flies the mission with thermal + radar + spectrometer payloads, runs the
## simulation at 3600x, and checks: (1) real climate events actually get
## captured as the precessing ground track crosses them, (2) the J2 nodal drift
## matches the sun-synchronous requirement, (3) the four Earth objectives and
## the data-return manifest populate at mission end.  Autoloads resolve at
## runtime, so GameManager and SimulationEngine are fetched from /root.

var gm = null
var sim = null
var frames := 0
var configured := false

func _process(_delta: float) -> bool:
	frames += 1
	if not configured:
		if frames < 2:
			return false
		gm = root.get_node_or_null("/root/GameManager")
		sim = root.get_node_or_null("/root/SimulationEngine")
		if gm == null or sim == null:
			print("PROBE ABORT: autoloads missing")
			quit(1)
			return true
		_configure()
		configured = true
	# Step the engine directly: 0.016 × 3600× ≈ 57.6 sim-seconds per step, so the
	# ground point moves ~3.6° between checks — well inside the 15° footprint,
	# which is how the real per-frame loop samples too.
	for i in range(80000):
		sim._process(0.016)
		if int(sim.state.get("day", 0)) >= 40:
			break
	_report()
	quit(0)
	return true

func _find_comp(list_name: String, id: String) -> Dictionary:
	for c in gm.components.get(list_name, []):
		if String(c.get("id", "")) == id:
			return c.duplicate(true)
	return {}

func _configure() -> void:
	var mission: Dictionary = gm.missions[0].duplicate(true)
	assert(String(mission.get("id", "")) == "earth_climate")
	gm.current_mission = mission
	var cfg = gm.spacecraft_config
	cfg["bus"] = {"data_storage": 400.0, "reliability": 0.93}
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
	sim.start_simulation(20261106)
	sim.set_time_scale(4)   # 3600×

func _report() -> void:
	print("final: day %d | orbits %d | captured %d | sci %.1f | passes %d" % [
		int(sim.state.get("day", 0)), int(sim.state.get("total_orbits", 0)),
		int(sim.state.get("targets_captured", 0)), float(sim.state.get("science_points", 0)),
		int(sim.state.get("passes_completed", 0))])
	print("── captured targets ──")
	for t in sim.state.get("climate_targets", []):
		if bool(t.get("captured", false)):
			print("  Day %3d · %s [%s]" % [int(t["captured_day"]), t["name"], t["source"]])
	print("objectives_done: %s" % str(sim.state.get("objectives_done", [])))
	sim._end_mission()
	var r = gm.mission_result
	print("score=%d success=%s events_manifest=%d precession=%.4f" % [
		int(r.get("score", 0)), str(r.get("success", false)),
		(r.get("climate_events_observed", []) as Array).size(),
		float(r.get("nodal_precession_deg_day", 0.0))])
	print("bonuses: %s" % str(r.get("climate_bonus_objectives", [])))
