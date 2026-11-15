## Temporary: compare candidate Earth textures to find the dark-surface cause.
extends SceneTree

const OUT := "C:/Users/USER/AppData/Local/Temp/opencode/"
var frame := 0
var plan: Array = []
var idx := -1
var earth: MeshInstance3D
var mat: StandardMaterial3D

func _initialize() -> void:
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 20:
		var scene := current_scene
		scene.set_process(false)
		earth = scene._g("Earth/EarthMesh") as MeshInstance3D
		var atmo := scene._g("Earth/AtmosphereMesh") as MeshInstance3D
		if atmo:
			atmo.visible = false
		var test_cam := Camera3D.new()
		scene.add_child(test_cam)
		test_cam.global_position = Vector3(0.0, 0.0, 20.0)
		test_cam.look_at(Vector3.ZERO, Vector3.UP)
		test_cam.current = true
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		earth.material_override = mat
		plan = [
			{"tag": "flat_green", "color": Color(0.2, 0.9, 0.3), "tex": null},
			{"tag": "tex_8k", "color": Color.WHITE, "tex": load("res://assets/textures/earth-blue-marble-8k.jpg")},
			{"tag": "tex_2k", "color": Color.WHITE, "tex": load("res://assets/textures/nasa-blue-marble-2048.png")},
			{"tag": "tex_8k_nomip", "color": Color.WHITE, "tex": load("res://assets/textures/earth-blue-marble-8k.jpg")},
			{"tag": "flat_green2", "color": Color(0.9, 0.2, 0.2), "tex": null},
		]
	# Every 10 frames: apply the next plan entry, then measure the one before it.
	if plan.size() > 0 and frame >= 50 and (frame - 50) % 12 == 0:
		_measure_current()
		idx += 1
		if idx >= plan.size():
			quit(0)
			return true
		var step: Dictionary = plan[idx]
		print("DIAG apply %s" % step["tag"])
		mat.albedo_texture = step["tex"]
		mat.albedo_color = step["color"]
		if step["tag"] == "tex_8k_nomip":
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return false

func _measure_current() -> void:
	if idx < 0:
		return
	var tag: String = plan[idx]["tag"]
	var img := root.get_texture().get_image()
	img.save_png(OUT + "cmp_" + tag + ".png")
	var w := img.get_width()
	var h := img.get_height()
	var centre := img.get_pixel(w / 2, h / 2)
	var n := 0
	var sum := 0.0
	for y in range(int(h * 0.3), int(h * 0.7), 4):
		for x in range(int(w * 0.3), int(w * 0.7), 4):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	print("DIAG %-14s centre=%s mean_l(box)=%.3f" % [tag, centre, sum / n])
