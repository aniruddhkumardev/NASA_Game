extends SceneTree

## Temporary verification harness: flies the Earth Climate Sentinel mission end
## to end with the scene's own honest physics, printing telemetry whenever a
## phase changes plus a trace every ~15 mission seconds, and saving a screenshot
## per phase.  The mission now genuinely takes ~50-60 minutes of mission time
## (the coast to apogee is a real half-orbit), so the debug warp is set high and
## _debug_warp multiplies on top of the player's default 1x.
## GameManager is an autoload, so it is resolved at runtime rather than by name.

const WARP := 24.0
const OUT_DIR := "res://tools/"
# Reading the numbers is the actual verification; the stills are for judging the
# filmmaking, and a full-screen readback per shot costs enough memory that a
# tight machine crashes on it.  MA_PROBE_NO_SHOTS=1 keeps the trace and skips
# the pictures.
var no_shots := false

var ls = null
var gm = null
var frames := 0
var last_state := ""
var last_booster_phase := ""
var last_trace_met := -999.0
var lines: Array[String] = []
var pending_tag := ""
var pending_frames := 0
var final_pending := false
var started := false
const SHOT_TIMES := [15.0, 25.0, 42.0, 55.0, 70.0, 120.0, 165.0, 200.0, 260.0, 330.0, 480.0, 620.0, 745.0, 800.0, 1500.0, 2400.0, 3000.0, 3300.0, 3600.0, 3900.0]
# One still per moment of the first stage's return, so the recovery can be judged
# as a piece of filmmaking and not only as a table of numbers.
const SHOT_BOOSTER := {
	"FLIP AND LIGHT": "flip",
	"BOOSTBACK BURN": "boostback",
	"ENTRY INTERFACE": "entry",
	"ENTRY BURN": "entryburn",
	"GRID FIN DESCENT": "glide",
	"FINAL APPROACH": "approach",
	"LANDING BURN": "landburn",
	"TOUCHDOWN": "touchdown",
	"HARD IMPACT": "crash",
}
# Diagnostic switch: node names forced invisible for one run, to tell which of
# the concentric shells is drawing the bright straight-edged band at the limb.
const HIDE_NODES: Array[String] = []
# Same diagnostic for shells that are built in code without a stable node name.
const HIDE_VARS: Array[String] = []
var shot_idx := 0
var hide_targets: Array = []
# Orbit-presentation check: the animated sweep rate measured against the true
# omega = v_t / r, so "one orbit per orbit_period_min" can be verified without
# waiting a full period of wall time.
var last_sf_met := -1.0
var last_sf_angle := 0.0
var omega_measured := 0.0
var omega_true := 0.0

func _initialize() -> void:
	no_shots = OS.get_environment("MA_PROBE_NO_SHOTS") == "1"
	change_scene_to_file("res://scenes/launch/launch.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	# Re-applied every frame because the scene's own per-frame backdrop swaps
	# would otherwise turn the shell straight back on.
	for ht in hide_targets:
		ht.set("visible", false)
	if not started:
		gm = root.get_node_or_null("/root/GameManager")
		ls = _find_launch_node()
		if gm == null or ls == null:
			if frames > 90:
				print("PROBE ABORT: gm=%s ls=%s" % [str(gm), str(ls)])
				quit(1)
				return true
			return false
		var missions = gm.get("missions")
		for m in missions:
			if String(m.get("id", "")) == "earth_climate":
				gm.set("current_mission", m.duplicate(true))
		gm.call("_init_spacecraft_config")
		var cfg = gm.get("spacecraft_config")
		cfg["rocket"] = {"id": "falcon9", "payload_kg": 1200.0}
		gm.set("is_paused", false)
		ls.set("_debug_warp", WARP)
		for hn in HIDE_NODES:
			var nd = ls.get_node_or_null("AtmosphereShell/" + hn)
			if nd == null:
				nd = ls.get_node_or_null(hn)
			if nd != null:
				hide_targets.append(nd)
				lines.append("DIAG hiding %s" % hn)
			else:
				lines.append("DIAG missing %s" % hn)
		for hv in HIDE_VARS:
			var vn = _get(hv)
			if vn != null:
				hide_targets.append(vn)
				lines.append("DIAG hiding var %s" % hv)
			else:
				lines.append("DIAG missing var %s" % hv)
		ls.call("_setup_from_mission")
		ls.call("_populate_mission_info")
		ls.call("_on_launch_pressed")
		started = true
		lines.append("mission=%s target=%s incl=%s" % [
			str(gm.get("current_mission").get("name")),
			str(gm.get("current_mission").get("altitude_km")),
			str(gm.get("current_mission").get("inclination_deg"))])
		return false

	if pending_tag != "":
		pending_frames -= 1
		if pending_frames <= 0:
			if not no_shots:
				var img := root.get_texture().get_image()
				img.save_png(OUT_DIR + "_diag_" + pending_tag + ".png")
				lines.append("shot %s" % pending_tag)
			pending_tag = ""
			if final_pending:
				_dump("complete")

	if frames % 3 == 0:
		_sample()
	if frames > 14000:
		_dump("frame cap")
		return true
	# A stuck run should say so in the log rather than look like a finished one.
	# The countdown is honest wall time (twelve seconds of it, plus scene boot),
	# so the budget is generous: a hundred seconds of wall time without the
	# mission clock leaving the pad means the flight never started.
	if started and not final_pending and float(_get("met_seconds")) < 1.0 and frames > 6000:
		lines.append("PROBE STUCK at frame %d state=%s met=%.1f" % [
			frames, StateName(int(_get("state"))), float(_get("met_seconds"))])
		_dump("stuck")
		return true
	return false

func _find_launch_node():
	for c in root.get_children():
		if c.has_method("_on_launch_pressed"):
			return c
		for g in c.get_children():
			if g.has_method("_on_launch_pressed"):
				return g
	return null

func _get(p):
	return ls.get(p)

func _sample() -> void:
	var sname: String = StateName(int(_get("state")))
	var met: float = float(_get("met_seconds"))
	if shot_idx < SHOT_TIMES.size() and met >= SHOT_TIMES[shot_idx] and pending_tag == "":
		pending_tag = "met%03d" % int(SHOT_TIMES[shot_idx])
		pending_frames = 2
		shot_idx += 1
	if sname != last_state:
		lines.append(">>> %-16s met=%7.1f alt=%8.2f km v=%8.1f m/s Ap=%9.1f Pe=%9.1f thr=%5.1f%% fuel=%5.1f%% att=%6.1f q=%6.2f g=%.2f" % [
			sname, met, _get("altitude_km"), _get("velocity_ms"), _get("apoapsis_km"), _get("periapsis_km"),
			_get("throttle"), _get("fuel_pct"), _get("attitude_deg"), _get("dynamic_pressure_kpa"), _get("axial_g")])
		_env_probe()
		pending_tag = sname.to_lower()
		pending_frames = 20
		last_state = sname
	if met - last_trace_met >= 15.0 and int(_get("state")) >= 2:
		last_trace_met = met
		_env_probe()
		lines.append("    %-16s t=%6.0f alt=%8.2f vv=%7.1f hv=%7.1f att=%5.1f fpa=%5.1f Ap=%8.0f Pe=%8.0f thr=%3.0f%% mass=%7.0fkg" % [
			sname, met, _get("altitude_km"), _get("vertical_velocity_ms"), _get("horizontal_velocity_ms"),
			_get("attitude_deg"), 90.0 - float(_get("attitude_deg")), _get("apoapsis_km"), _get("periapsis_km"),
			_get("throttle"), _get("rocket_mass")])
	# The scene can sit in COMPLETE for a long honest while: the first stage is
	# still flying home after SECO, so keep sampling until the return resolves.
	if sname == "COMPLETE" and (not bool(_get("booster_recoverable")) or bool(_get("booster_landed"))):
		final_pending = true

	# Sample the space-frame sweep rate: measured d(angle)/d(mission time)
	# against the physical omega for the current orbit radius.
	if bool(_get("in_space_frame")):
		var oa: float = float(_get("orbit_angle"))
		var r_km: float = float(_get("body_radius_km")) + maxf(float(_get("altitude_km")), 0.0)
		omega_true = (float(_get("horizontal_velocity_ms")) / 1000.0) / maxf(r_km, 1.0)
		if last_sf_met >= 0.0 and met > last_sf_met:
			var d_a: float = oa - last_sf_angle
			if d_a < -PI:
				d_a += TAU
			elif d_a > PI:
				d_a -= TAU
			var inst: float = d_a / (met - last_sf_met)
			omega_measured = inst if omega_measured == 0.0 else omega_measured * 0.7 + inst * 0.3
		last_sf_met = met
		last_sf_angle = oa

	# The returning first stage is a second guided vehicle, so it gets its own
	# trace: every phase change of the recovery profile, with the numbers the
	# recovery panel is showing and which camera shot is live.
	var bp: String = String(_get("booster_phase_name"))
	if bp != "" and bp != last_booster_phase:
		last_booster_phase = bp
		var bpos = Vector3.ZERO
		var cd: float = -1.0
		var camn = _get("cam_recovery")
		if _get("booster_node") != null:
			bpos = _get("booster_node").global_position
			if camn != null:
				cd = bpos.distance_to(camn.global_position)
		var vps = "none"
		var vp = _get("split_viewport")
		if vp != null:
			vps = "%dx%d upd=%s world=%s" % [vp.size.x, vp.size.y,
				str(vp.render_target_update_mode), str(vp.world_3d != null)]
		lines.append("### BOOSTER %-18s sep=%6.1f dt=%6.1f alt=%7.2f km spd=%7.0f m/s x=%6.1f vx=%6.0f vy=%6.0f prop=%5.1f t split=%d landed=%s warp=%s dist=%s rig=%s vp=%s pos=%s" % [
			bp, float(_get("booster_sep_met")), float(_get("booster_dt_now")),
			float(_get("booster_alt_km")), float(_get("booster_spd_ms")),
			float(_get("booster_x_km")), float(_get("booster_vx_ms")), float(_get("booster_vy_ms")),
			float(_get("booster_prop_t")), int(_get("booster_cam_window")),
			str(_get("booster_landed")),
			"%.1f" % float(_get("sim_speed")),
			"%.1f" % cd,
			str(_get("recovery_rig") != null and _get("recovery_rig").visible),
			vps, str(bpos)])
		if SHOT_BOOSTER.has(bp) and pending_tag == "":
			pending_tag = "boost_" + String(SHOT_BOOSTER[bp])
			pending_frames = 8

## Reports what the ascent backdrop is actually made of at each phase change,
## so a stray flat plane or a dead sky material can be told apart from the
## planetary shell in a screenshot.
func _env_probe() -> void:
	var parts: Array[String] = []
	parts.append("sky_mat=%s" % ("yes" if _get("sky_material") != null else "NULL"))
	parts.append("horizon=%s" % str(_get("horizon_active")))
	for n in ["Ground", "GroundDetail", "LaunchComplex"]:
		var nd = ls.get_node_or_null(n)
		if nd == null:
			parts.append("%s=missing" % n)
		else:
			var v: bool = nd.is_visible_in_tree()
			parts.append("%s=vis%s" % [n, str(v)])
	var we = ls.get_node_or_null("WorldEnvironment")
	if we != null:
		var e = we.get("environment")
		if e != null:
			parts.append("bg=%s" % str(e.get("background_mode")))
			parts.append("fog=%s" % str(e.get("fog_enabled")))
	lines.append("      ENV " + "  ".join(parts))
	# The new atmosphere feature: which phase/layer the HUD is claiming, how many
	# cloud decks are actually in the tree and visible, and the arc length flown.
	var ph = ls.call("_flight_phase")
	lines.append("      ATMO phase=%s  |  %s" % [
		str(ph.get("name", "?")), String(ls.call("_atmosphere_line"))])
	var decks: Array = _get("cloud_shells")
	var shown: int = 0
	for i in decks.size():
		var d = decks[i]
		if d != null and d.is_visible_in_tree():
			shown += 1
	lines.append("      DECKS n=%d visible=%d beats=%s path=%.1f km karman=%s" % [
		decks.size(), shown, str(_get("layer_beat_idx")),
		float(_get("path_distance_km")),
		str(_get("karman_shell") != null)])

func _dump(why: String) -> void:
	lines.append("FINAL state=%s met=%.1f alt=%.1f v=%.1f Ap=%.1f Pe=%.1f sim_state=%s" % [
		StateName(int(_get("state"))), float(_get("met_seconds")), float(_get("altitude_km")),
		float(_get("velocity_ms")), float(_get("apoapsis_km")), float(_get("periapsis_km")),
		JSON.stringify(gm.get("simulation_state"))])
	lines.append("BOOSTER recoverable=%s landed=%s crashed=%s touchdown_speed=%s alt=%s prop_start=%s prop_left(margin)=%s peak_entry_g=%s window=%s" % [
		str(_get("booster_recoverable")), str(_get("booster_landed")), str(_get("booster_crashed")),
		"%.2f" % float(_get("booster_touchdown_speed_ms")),
		str(float(_get("booster_alt_km"))),
		"%.1f t" % (float(_get("booster_prop_start_kg")) / 1000.0),
		"%.1f t" % (float(_get("booster_prop_kg")) / 1000.0),
		"%.2f" % float(_get("booster_peak_entry_g")),
		str(int(_get("booster_cam_window")))])
	# Orbit presentation: the animated sweep must match omega = v_t / r, i.e.
	# one orbit per orbit_period_min of mission time, within 1%.
	var p_true: float = float(_get("orbit_period_min"))
	var p_anim: float = (TAU / omega_measured / 60.0) if omega_measured > 0.0 else -1.0
	var err_pct: float = absf(p_anim - p_true) / p_true * 100.0 if p_anim > 0.0 and p_true > 0.0 else -1.0
	lines.append("ORBIT period_true=%s min period_animated=%s min err=%s%% downrange_touchdown=%s km" % [
		"%.2f" % p_true, "%.2f" % p_anim, "%.3f" % err_pct,
		"%.1f" % float(_get("booster_x_km"))])
	var f := FileAccess.open(OUT_DIR + "_probe_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("PROBE DONE (" + why + ")")
	quit()

func StateName(s: int) -> String:
	var names := ["PRE_LAUNCH", "COUNTDOWN", "LIFTOFF", "MAX_Q", "STAGE_SEP",
		"FAIRING_SEP", "ORBITAL_INSERT", "SATELLITE_DEPLOY", "COMPLETE"]
	return names[clampi(s, 0, 8)]
