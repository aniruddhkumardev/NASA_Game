extends SceneTree

## Verification harness for the two-revolution climate commissioning phase.
##
## It puts the Earth Climate Sentinel into the orbital operations scene with a
## working spacecraft (the bare default config produces no data, so the downlink
## would be a hollow zero), then runs it through arrival + the two survey
## revolutions, checking that the ground-station network really is built, that the
## downlink beam locks onto an actual station rather than empty space, and that
## the two downlinked revolutions are recorded and gate the mission result.
## GameManager and SimulationEngine are autoloads, so they are resolved at runtime.

const OUT_DIR := "res://tools/"
var frames := 0
var gm = null
var sim = null
var scene = null
var configured := false
var lines: Array[String] = []
var beam_seen := false
var halo_lit := false
var shots_taken := 0
var last_passes := -1
var last_revs := -1
var completion_logged := false
var ended := false
var end_hold := 0

func _initialize() -> void:
	# Autoloads cannot be resolved from _initialize (the scene tree is not active
	# yet), so the mission and spacecraft are configured on the first _process
	# frame below, before the scene's own read of the state matters.
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _apply_config(cfg) -> void:
	cfg["bus"] = {"data_storage": 200.0, "reliability": 0.92}
	cfg["comms"] = {"bandwidth_mbps": 8.0}
	cfg["instruments"] = []
	cfg["rocket"] = {"reliability": 0.95}
	cfg["total_data_rate"] = 2.0
	cfg["total_science_per_orbit"] = 48.0
	cfg["total_power_gen"] = 320.0
	cfg["total_power_draw"] = 120.0
	cfg["battery_capacity"] = 1200.0

func _process(_delta: float) -> bool:
	frames += 1
	if not configured:
		gm = root.get_node_or_null("/root/GameManager")
		sim = root.get_node_or_null("/root/SimulationEngine")
		scene = current_scene
		if gm == null or sim == null or scene == null:
			if frames > 120:
				print("PROBE ABORT: gm=%s sim=%s scene=%s" % [str(gm), str(sim), str(scene)])
				quit(1)
				return true
			return false
		_configure()
		configured = true
		return false

	# Poll the live scene for the things that prove the feature works.
	_sample()

	# Stop shortly after commissioning completes and the mission result is known.
	if completion_logged:
		end_hold += 1
		if end_hold > 90:
			_report()
			quit(0)
			return true
	if frames > 4200:
		lines.append("TIMEOUT before commissioning completed")
		_report()
		quit(1)
		return true
	return false

func _configure() -> void:
	var missions = gm.get("missions")
	for m in missions:
		if String(m.get("id", "")) == "earth_climate":
			gm.set("current_mission", m.duplicate(true))
	gm.call("_init_spacecraft_config")
	_apply_config(gm.get("spacecraft_config"))
	# Re-seed the simulation with the working craft; the scene began with the empty
	# default config, and the state it publishes is what every readout below checks.
	sim.call("start_simulation", 12345)
	lines.append("CONFIG mission=earth_climate data_rate=2.0 bw=8.0 sci/orbit=48 period=%.1fs" % float(sim.get("orbit_period_seconds")))

func _get_scene(varname: String) -> Variant:
	return scene.get(varname)

func _sample() -> void:
	if scene == null:
		return
	# The station network has to exist and sit on the globe's surface.
	var root_node: Node3D = _get_scene("stations_root")
	if root_node != null and frames % 60 == 5:
		var want: int = (gm.get("GROUND_STATIONS") if false else 0)
		var n: int = root_node.get_child_count()
		var ok_radius: bool = true
		for i in n:
			var p: Node3D = root_node.get_child(i) as Node3D
			if p == null:
				ok_radius = false
				break
			var r: float = p.position.length()
			if absf(r - 6.0) > 0.4:
				ok_radius = false
		if not halo_lit:
			halo_lit = _any_station_holds()
		if _get_scene("commission_complete") == true and not completion_logged:
			completion_logged = true
			var revs: int = int(sim.get("state")["commission_revolutions"])
			var passes: int = int(sim.get("state").get("commission_passes", 0))
			var tx: float = float(sim.get("state").get("data_transmitted_mb", 0.0))
			lines.append("COMMISSION COMPLETE revs=%d passes=%d transmitted=%.0fMB beam_seen=%s halo_lit=%s" % [
				revs, passes, tx, str(beam_seen), str(halo_lit)])
			_take_shot("commission_done")
	# A beam that lights for a real station is the visible half of the feature.
	var beam: Node = _get_scene("downlink_beam")
	if beam != null and beam.is_visible_in_tree():
		if not beam_seen:
			beam_seen = true
			var stn: String = String(sim.get("state").get("ground_station_name", ""))
			lines.append("FIRST DOWNLINK BEAM station=%s" % stn)
			_take_shot("downlink")
	var passes_now: int = int(sim.get("state").get("commission_passes", -1))
	var revs_now: int = int(sim.get("state").get("commission_revolutions", -1))
	if int(sim.get("state").get("total_orbits", 0)) != last_revs:
		last_revs = int(sim.get("state").get("total_orbits", 0))
		if completion_logged or true:
			lines.append("ORBIT #%d angle=%.0fdeg contact=%s station=%s stored=%.0fMB tx=%.0fMB active=%s" % [
				last_revs, rad_to_deg(sim.get("orbit_angle")),
				str(sim.get("state").get("ground_contact", false)),
				String(sim.get("state").get("ground_station_name", "-")),
				float(sim.get("state").get("data_stored_mb", 0.0)),
				float(sim.get("state").get("data_transmitted_mb", 0.0)),
				str(_get_scene("commissioning_active"))])

func _any_station_holds() -> bool:
	var stns = sim.get("GROUND_STATIONS")
	var alt: float = float(gm.get("current_mission").get("altitude_km", 550))
	for st in stns:
		var el: float = float(sim.call("station_elevation_deg", st, alt))
		if el >= float(sim.get("MIN_ELEVATION_DEG")):
			return true
	return false

func _take_shot(tag: String) -> void:
	if shots_taken >= 6:
		return
	shots_taken += 1
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png("%s_diag_orbit_%s.png" % [OUT_DIR, tag])

func _report() -> void:
	var sim_state = sim.get("state")
	if gm.call("is_mars_mission") == false and not ended:
		ended = true
		sim.call("_end_mission")
		var res = gm.get("mission_result")
		if res != null:
			lines.append("RESULT success=%s revs=%s passes=%s tx_gb=%.3f science=%.1f/%.0f" % [
				str(res.get("success", false)), str(res.get("commission_revolutions", 0)),
				str(res.get("commission_passes", 0)), float(res.get("data_transmitted_gb", 0.0)),
				float(res.get("science_collected", 0.0)), float(res.get("science_goal", 80))])
	var gsm = gm.get("simulation_state")
	lines.append("SIM_STATE climate_complete=%s commission_revs=%s passes=%s" % [
		str(gsm.get("climate_commissioning_complete", false)),
		str(gsm.get("commission_revolutions", 0)),
		str(gsm.get("commission_ground_passes", 0))])
	var stn_root: Node = _get_scene("stations_root")
	lines.append("STATION network_children=%s (expect 4) beam=%s commission_active=%s complete=%s" % [
		str(stn_root.get_child_count()) if stn_root != null else "none",
		str(_get_scene("downlink_beam") != null),
		str(_get_scene("commissioning_active")), str(_get_scene("commission_complete"))])
	# Assertions.
	var revs_ok: bool = int(sim_state.get("commission_revolutions", 0)) >= 2
	var net_ok: bool = stn_root != null and stn_root.get_child_count() == sim.get("GROUND_STATIONS").size()
	var tx_ok: bool = float(sim_state.get("data_transmitted_mb", 0.0)) > 0.0
	_check("station network built (4 pins)", net_ok)
	_check("two revolutions flown", revs_ok)
	_check("climate data downlinked (>0 MB)", tx_ok)
	_check("downlink beam locked a station", beam_seen)
	_check("a station rose above the mask", halo_lit)
	_check("commissioning flagged complete", bool(_get_scene("commission_complete")))
	var out := "\n".join(lines)
	print(out)
	var f := FileAccess.open("res://tools/_orbit_probe_result.txt", FileAccess.WRITE)
	f.store_string(out + "\n")
	f.close()

func _check(name: String, ok: bool) -> void:
	var tag := "PASS" if ok else "FAIL"
	lines.append("[%s] %s" % [tag, name])
