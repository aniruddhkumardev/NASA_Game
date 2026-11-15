extends SceneTree

## Focused visual check: force the moon_scout launch scene straight into the
## SEPARATION / SATELLITE_DEPLOY state (skipping the ~15-min flight), let the
## new close deploy camera settle for a second, then save one screenshot.

const SHOT := "res://tools/_verify_deploy.png"
var gm = null
var ls = null
var frames := 0
var phase := 0
var settle := 0
var started := false

func _initialize() -> void:
	change_scene_to_file("res://scenes/launch/launch.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	gm = root.get_node_or_null("/root/GameManager")
	ls = _find_launch_node()
	if gm == null or ls == null:
		if frames > 120:
			print("VERIFY ABORT: gm=%s ls=%s" % [str(gm), str(ls)])
			quit(1)
			return true
		return false
	if not started:
		var missions = gm.get("missions")
		for m in missions:
			if String(m.get("id", "")) == "moon_scout":
				gm.set("current_mission", m.duplicate(true))
		gm.call("_init_spacecraft_config")
		var cfg = gm.get("spacecraft_config")
		cfg["rocket"] = {"id": "falcon9", "payload_kg": 1200.0}
		gm.set("is_paused", false)
		ls.call("_setup_from_mission")
		# Park the vehicle on a circular 200 km orbit and hand over to the space
		# frame so the deploy camera has a real backdrop to frame against.
		ls.set("altitude_km", 200.0)
		ls.set("velocity_ms", 7788.0)
		ls.set("horizontal_velocity_ms", 7788.0)
		ls.set("vertical_velocity_ms", 0.0)
		ls.set("insertion_phase", 3)   # InsertionPhase.DONE
		ls.set("seco_done", true)
		ls.call("_enter_space_frame")
		ls.call("_create_payload_craft")
		ls.call("_set_state", 7)        # LaunchState.SATELLITE_DEPLOY
		started = true
		return false
	# Let the scene's own _process drive _update_satellite_deploy so the camera
	# lerps to the close reveal, then capture.
	settle += 1
	if settle >= 70:
		var img := root.get_texture().get_image()
		img.save_png(SHOT)
		var pc = ls.get("payload_craft")
		var cam = ls.get("cam_space")
		var d := -1.0
		if pc != null and cam != null:
			d = pc.global_position.distance_to(cam.global_position)
		print("VERIFY DEPLOY shot saved. payload_children=%s cam_dist=%.2f state=%s" % [
			str(pc.get_child_count()) if pc != null else "null", d, str(ls.get("state"))])
		quit(0)
		return true
	return false

func _find_launch_node():
	for c in root.get_children():
		if c.has_method("_create_payload_craft"):
			return c
		for g in c.get_children():
			if g.has_method("_create_payload_craft"):
				return g
	return null
