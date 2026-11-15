extends SceneTree

## Verifies the new lunar "End Mission" path: the button exists, the result
## dictionary is built, and the report hand-off has valid data.  Runs the real
## scene so missing nodes / GDScript errors surface here.

var frames := 0
var done := false
var lm = null

func _initialize() -> void:
	change_scene_to_file("res://scenes/lunar/lunar_mission.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if done:
		return true
	if lm == null:
		lm = _find_lunar()
		if lm == null:
			if frames > 240:
				print("PROBE FAIL: lunar node not found")
				quit(1)
				done = true
				return true
			return false
	if frames == 20:
		var gm = root.get_node_or_null("/root/GameManager")
		if gm == null:
			print("PROBE FAIL: GameManager autoload missing")
			quit(1)
			done = true
			return true
		for m in gm.get("missions"):
			if String(m.get("id", "")) == "moon_scout":
				gm.set("current_mission", m.duplicate(true))
		if lm.get("end_btn") == null:
			print("PROBE FAIL: end_btn missing")
			quit(1)
			done = true
			return true
		lm.set("landed", true)
		lm.set("rover_deployed", true)
		lm.set("scan_progress", 100.0)
		lm.call("_update_end_mission_button")
		var btn = lm.get("end_btn")
		print("PROBE UI OK button='%s' disabled=%s" % [btn.text, str(btn.disabled)])
		lm.call("_finish_mission")
	if frames == 60:
		var gm = root.get_node_or_null("/root/GameManager")
		var r: Dictionary = gm.get("mission_result") if gm else {}
		if r.is_empty():
			print("PROBE FAIL: mission_result empty")
			quit(1)
			done = true
			return true
		print("PROBE RESULT success=%s score=%s science=%.1f/%.0f data=%.1fGB events=%d improvements=%d" % [
			str(r.get("success")), str(r.get("score")),
			float(r.get("science_collected", 0.0)), float(r.get("science_goal", 0.0)),
			float(r.get("data_transmitted_gb", 0.0)),
			(r.get("events_log", []) as Array).size(),
			(r.get("improvements", []) as Array).size()])
		quit(0)
		done = true
		return true
	return false

func _find_lunar():
	for c in root.get_children():
		if c.has_method("_finish_mission"):
			return c
	return null
