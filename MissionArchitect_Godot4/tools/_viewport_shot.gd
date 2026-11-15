extends SceneTree

## Deterministic viewport capture for design verification.
##
## Reads pixels straight out of the game viewport instead of the desktop, so it
## works no matter which OS window happens to be in front.  Use it to compare the
## monochrome UI against the natural-colour 3D simulation.
##
## Environment:
##   MA_SHOT_SCENE  scene to load        (default res://scenes/ui/main_menu.tscn)
##   MA_SHOT_OUT    output png           (default user://missionforge_shot.png)
##   MA_SHOT_DELAY  seconds to wait      (default 6)
##   MA_MISSION     mission id preselect (used by GameManager)
##   MA_SHOT_SKIP_ARRIVAL  "1" skips the orbit arrival film
##   MA_SHOT_ZOOM   wheel notches to dolly the globe camera in (orbit scene)
##
## Example:
##   godot --path . --script res://tools/_viewport_shot.gd

var scene_path := "res://scenes/ui/main_menu.tscn"
var out_path := "user://missionforge_shot.png"
var delay := 6.0
var elapsed := 0.0
var capturing := false
var done := false
var skip_arrival := false
var zoom_notches := 0
var zoomed := false

func _initialize() -> void:
	if OS.get_environment("MA_SHOT_SCENE") != "":
		scene_path = OS.get_environment("MA_SHOT_SCENE")
	if OS.get_environment("MA_SHOT_OUT") != "":
		out_path = OS.get_environment("MA_SHOT_OUT")
	if OS.get_environment("MA_SHOT_DELAY") != "":
		delay = float(OS.get_environment("MA_SHOT_DELAY"))
	skip_arrival = OS.get_environment("MA_SHOT_SKIP_ARRIVAL") == "1"
	zoom_notches = int(OS.get_environment("MA_SHOT_ZOOM"))
	change_scene_to_file(scene_path)

func _process(delta: float) -> bool:
	if done:
		return true
	if capturing:
		return false
	elapsed += delta
	# The arrival film would mask the operations view; skipping it lets the
	# screenshot show what the player actually interacts with.
	if skip_arrival and elapsed > 0.4 and current_scene and current_scene.has_method("_finish_orbit_arrival"):
		current_scene._finish_orbit_arrival()
	# Apply the globe zoom once, early enough that the dolly lerp has settled by
	# the time the frame is grabbed.
	if zoom_notches > 0 and elapsed > 1.2 and current_scene and current_scene.has_method("_zoom_step"):
		var centre: Vector2 = root.get_visible_rect().size * 0.5
		# A climate auto-flyover would hold the camera on a ground pin; cancel it
		# so the capture shows the player-controlled globe view.
		if "fly_time" in current_scene:
			current_scene.set("fly_time", 0.0)
		for i in zoom_notches:
			current_scene._zoom_step(1.0, centre)
		zoom_notches = 0
		zoomed = true
	if elapsed >= delay:
		capturing = true
		_capture()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(abs_path)
	print("SHOT %s err=%d %dx%d zoomed=%s" % [abs_path, err, img.get_width(), img.get_height(), str(zoomed)])
	done = true
	quit(0 if err == OK else 1)
