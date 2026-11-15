extends SceneTree

## Live check: if the player warped up to skip the coast, entering the
## SATELLITE_DEPLOY separation beat must drop the clock back to real time so the
## fairing reveal is actually shown, not flashed past. Reads the warp/speed index
## before and after _set_state(SATELLITE_DEPLOY).

var gm = null
var ls = null
var frames := 0
var done := false

func _initialize() -> void:
	change_scene_to_file("res://scenes/launch/launch.tscn")

func _process(_d: float) -> bool:
	frames += 1
	gm = root.get_node_or_null("/root/GameManager")
	ls = _find()
	if gm == null or ls == null:
		if frames > 180:
			_out("ABORT: ls not found")
		return false
	if frames < 20 or done:
		return false
	done = true
	ls.call("_setup_from_mission")
	ls.call("_enter_space_frame")
	ls.call("_create_payload_craft")
	ls.call("_set_warp_idx", 5)   # WARP x32
	ls.call("_set_speed_idx", 2)  # SPEED x3
	var bw = ls.get("player_warp_idx")
	var bs = ls.get("player_speed_idx")
	ls.call("_set_state", 7)      # LaunchState.SATELLITE_DEPLOY
	var aw = ls.get("player_warp_idx")
	var asp = ls.get("player_speed_idx")
	var verdict := "PASS - separation plays at real time" if (int(aw) == 0 and int(asp) == 0) else "FAIL"
	_out("before warp=%s speed=%s -> after SATELLITE_DEPLOY warp=%s speed=%s  %s" % [bw, bs, aw, asp, verdict])
	return true

func _out(l: String) -> void:
	print("SEPCHK " + l)
	quit(0)

func _find():
	for c in root.get_children():
		if c.has_method("_set_state"):
			return c
		for g in c.get_children():
			if g.has_method("_set_state"):
				return g
	return null
