extends SceneTree

## Live check of the new LAUNCH-adjacent SPEED lever. Loads the launch scene,
## drives the speed button through its cycle, and reads the real computed sim
## speed + button label at each step, proving Normal/×2/×3 actually changes speed.

var gm = null
var ls = null
var frames := 0
var done := false

func _initialize() -> void:
	change_scene_to_file("res://scenes/launch/launch.tscn")

func _process(_d: float) -> bool:
	frames += 1
	gm = root.get_node_or_null("/root/GameManager")
	ls = _find_launch_node()
	if gm == null or ls == null:
		if frames > 180:
			_out("ABORT: gm=%s ls=%s" % [str(gm), str(ls)])
		return false
	if frames < 20:
		return false
	if done:
		return false
	done = true
	# Put the flight into a state where compression applies (past countdown).
	ls.set("state", 2)  # LaunchState.LIFTOFF
	var lines := []
	for i in 3:
		ls.call("_set_speed_idx", i)
		var sp: float = ls.call("_compute_sim_speed")
		var btn = ls.get("speed_btn")
		var label: String = btn.text if btn != null else "<no button>"
		lines.append("idx=%d  label='%s'  sim_speed=%.2f" % [i, label, sp])
	_out(" | ".join(lines))
	return true

func _out(line: String) -> void:
	print("SPEEDCHECK " + line)
	quit(0)

func _find_launch_node():
	for c in root.get_children():
		if c.has_method("_compute_sim_speed"):
			return c
		for g in c.get_children():
			if g.has_method("_compute_sim_speed"):
				return g
	return null
