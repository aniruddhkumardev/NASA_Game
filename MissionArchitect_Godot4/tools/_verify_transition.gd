extends SceneTree

## Live check of the transition continuity fix. Fires the real
## CinematicTransition.travel() and records the veil's alpha every frame while the
## handoff runs. The fix is proven if the live peak alpha is ~0.5 (a light dim),
## not 0.88 (the old near-blackout). No image readback needed.

const RESULT := "F:/Projects/Space_Mission_design_Game/MissionArchitect_Godot4/tools/_verify_tr_result.txt"
var ct = null
var frames := 0
var phase := 0        # 0 wait for load, 1 trigger travel, 2 watch veil alpha
var peak_alpha := 0.0
var min_alpha := 1.0
var samples := 0
var done := false

func _initialize() -> void:
	change_scene_to_file("res://scenes/lunar/lunar_transfer.tscn")

func _process(_d: float) -> bool:
	frames += 1
	ct = root.get_node_or_null("/root/CinematicTransition")
	if ct == null:
		if frames > 120:
			_finish("CinematicTransition autoload not found")
		return false
	if phase == 0:
		if frames > 30:
			phase = 1
		return false
	if phase == 1:
		ct.call_deferred("travel", "res://scenes/lunar/lunar_mission.tscn", "VERIFY", "verify")
		phase = 2
		return false
	if phase == 2:
		var a: float = ct.veil.color.a
		peak_alpha = maxf(peak_alpha, a)
		min_alpha = minf(min_alpha, a)
		samples += 1
		# travel() clears busy once the fade-out tween finishes.
		if bool(ct.get("busy")) == false and samples > 20:
			var verdict := "CONTINUOUS (light dim, not black)" if peak_alpha <= 0.6 else "STILL BLACK (fail)"
			_finish("LIVE peak veil alpha=%.3f  (pre-fix was 0.88)  samples=%d  verdict=%s" % [
				peak_alpha, samples, verdict])
			return true
		if frames > 400:
			_finish("TIMEOUT peak=%.3f samples=%d" % [peak_alpha, samples])
			return true
	return false

func _finish(line: String) -> void:
	if done:
		return
	done = true
	print(line)
	var f := FileAccess.open(RESULT, FileAccess.WRITE)
	if f != null:
		f.store_string(line + "\n")
		f.close()
	quit(0)
