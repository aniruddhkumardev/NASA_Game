extends SceneTree

## Temporary diagnostic: opens the launch scene, lets it settle, saves a
## screenshot, then quits. Deleted after use.

var frames := 0
var elapsed := 0.0
var cam_applied := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := "res://scenes/launch/launch.tscn"
	if args.size() > 0 and args[0] == "lunar":
		scene = "res://scenes/lunar/lunar_mission.tscn"
	elif args.size() > 0 and args[0] == "transfer":
		scene = "res://scenes/lunar/lunar_transfer.tscn"
	elif args.size() > 0 and args[0] == "menu":
		scene = "res://scenes/ui/main_menu.tscn"
	change_scene_to_file(scene)
	if args.size() > 1:
		var spec := String(args[1])
		# "s<seconds>" waits on accumulated frame time instead of a raw frame
		# count.  The real frame rate swings between runs, so a fixed count lands
		# on wildly different mission times; seconds make the shot reproducible.
		if spec.begins_with("s") and spec.substr(1).to_float() > 0.0:
			set_meta("shot_secs", spec.substr(1).to_float())
		else:
			set_meta("shot_delay", int(spec))
	if args.size() > 2:
		set_meta("tag", args[2])
	if args.size() > 3:
		set_meta("cam", String(args[3]))
	if args.size() > 4 and String(args[4]) == "cd":
		set_meta("start_cd", true)

func _process(delta: float) -> bool:
	frames += 1
	elapsed += delta
	# Switch the camera a few frames in so Godot can make it current and let it
	# ease into framing before the capture; current=true only takes effect at
	# end-of-frame, so switching in the same frame as the shot would miss.
	if not cam_applied and has_meta("cam") and frames > 3:
		var cur := current_scene
		if cur != null and cur.has_method("_set_camera"):
			match str(get_meta("cam")):
				"wide": cur._set_camera(5)
				"tower": cur._set_camera(4)
				"pad": cur._set_camera(0)
			cam_applied = true
	if has_meta("start_cd") and frames == 5:
		var cur2 := current_scene
		if cur2 != null and cur2.has_method("_set_state"):
			cur2._set_state(1)  # LaunchState.COUNTDOWN
	var due := false
	if has_meta("shot_secs"):
		due = elapsed >= float(get_meta("shot_secs"))
	else:
		var wait := 120
		if has_meta("shot_delay"):
			wait = int(get_meta("shot_delay"))
		due = frames == wait
	if due:
		var img := root.get_texture().get_image()
		var out := "D:/Temp/opencode/shot.png"
		if has_meta("tag"):
			out = str(get_meta("tag"))
		var f := FileAccess.open("res://tools/_shot_debug.txt", FileAccess.WRITE)
		var name := "res://tools/_diag_launch.png"
		if has_meta("tag"):
			name = "res://tools/_diag_" + str(get_meta("tag")) + ".png"
		var r1 := img.save_png(name)
		f.store_string("w=%d h=%d empty=%s save=%d name=%s\n" % [img.get_width(), img.get_height(), str(img.is_empty()), r1, name])
		f.close()
		quit()
	return false
