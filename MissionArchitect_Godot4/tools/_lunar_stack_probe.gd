extends SceneTree

## Runtime check for the rebuilt Chandrayaan-3 lunar stack.  Builds the actual
## payload craft through the scene's own _create_payload_craft / _build_lunar_stack
## so any mesh-property or null-node error surfaces here instead of in-game.

var gm = null
var ls = null
var frames := 0
var done := false

func _initialize() -> void:
	change_scene_to_file("res://scenes/launch/launch.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if done:
		return true
	gm = root.get_node_or_null("/root/GameManager")
	ls = _find_launch_node()
	if gm == null or ls == null:
		if frames > 120:
			print("LUNAR STACK PROBE ABORT: gm=%s ls=%s" % [str(gm), str(ls)])
			quit(1)
			return true
		return false
	var missions = gm.get("missions")
	for m in missions:
		if String(m.get("id", "")) == "moon_scout":
			gm.set("current_mission", m.duplicate(true))
	# Build the lunar craft through the real code path.
	ls.call("_create_payload_craft")
	var craft = ls.get("payload_craft")
	if craft == null:
		print("LUNAR STACK FAIL: payload_craft is null")
		quit(1)
		done = true
		return true
	var count: int = craft.get_child_count()
	var names: Array = []
	for c in craft.get_children():
		names.append(c.name)
	print("LUNAR STACK OK children=%d names=%s" % [count, str(names)])
	quit(0)
	done = true
	return true

func _find_launch_node():
	for c in root.get_children():
		if c.has_method("_create_payload_craft"):
			return c
		for g in c.get_children():
			if g.has_method("_create_payload_craft"):
				return g
	return null
