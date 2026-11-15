extends SceneTree

## MISSIONFORGE verification probe.
##
## Asserts the two halves of the design contract on a real, running scene:
##   1. UI coverage  — every CanvasItem outside a rendered 3D preview carries the
##                     monochrome material.
##   2. 3D isolation — no Node3D, MeshInstance3D or material anywhere in the
##                     scene references the monochrome shader.
##
## Run:
##   godot --headless --path . --script res://tools/_missionforge_probe.gd

const MONO_SHADER_PATH := "res://shaders/missionforge_mono.gdshader"
const PLATE_SHADER_PATH := "res://shaders/missionforge_plate.gdshader"

var frames := 0
var done := false
var scene_path := "res://scenes/ui/mission_select.tscn"

func _initialize() -> void:
	var forced := OS.get_environment("MA_PROBE_SCENE")
	if forced != "":
		scene_path = forced
	change_scene_to_file(scene_path)

func _process(_delta: float) -> bool:
	frames += 1
	if done:
		return true
	# Give the scene a few frames to build its runtime UI (mission select builds
	# its whole card rail and 3D hangar preview in _ready / _process).
	if frames < 45:
		return false
	done = true

	var mono_count := 0
	var live_count := 0
	var plate_count := 0
	var ui_total := 0
	var skipped_preview := 0
	var color_page := 0
	var unthemed: Array[String] = []

	for item in root.find_children("*", "CanvasItem", true, false):
		if _inside_rendered_viewport(item):
			skipped_preview += 1
			continue
		# The title screen is a deliberate colour exception.
		if _in_color_page(item):
			color_page += 1
			continue
		ui_total += 1
		# Live-value accents are an explicit, audited opt-out.
		if item.has_meta("missionforge_live"):
			live_count += 1
			continue
		var mat = item.material
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			var sp: String = (mat as ShaderMaterial).shader.resource_path
			if sp == MONO_SHADER_PATH:
				mono_count += 1
				continue
			if sp == PLATE_SHADER_PATH:
				plate_count += 1
				continue
		unthemed.append(item.get_path())

	var leaks: Array[String] = []
	for n in root.find_children("*", "Node3D", true, false):
		for prop in ["material", "material_override", "material_overlay", "surface_material_override/0"]:
			if not (prop in n):
				continue
			var v = n.get(prop)
			if v is ShaderMaterial and (v as ShaderMaterial).shader != null \
					and (v as ShaderMaterial).shader.resource_path == MONO_SHADER_PATH:
				leaks.append("%s.%s" % [n.get_path(), prop])

	print("PROBE scene=%s" % scene_path)
	print("PROBE UI items=%d mono=%d live_accent=%d white_plate=%d skipped_3d_preview=%d color_page=%d" % [
		ui_total, mono_count, live_count, plate_count, skipped_preview, color_page])
	if not unthemed.is_empty():
		var head := unthemed.slice(0, 8)
		print("PROBE UNTHEMED(%d): %s" % [unthemed.size(), ", ".join(head)])
	print("PROBE 3D LEAKS=%d" % leaks.size())
	if not leaks.is_empty():
		print("PROBE LEAK LIST: %s" % ", ".join(leaks.slice(0, 8)))

	var ok := leaks.is_empty() and unthemed.is_empty() and mono_count > 0
	print("PROBE RESULT ok=%s" % str(ok))
	quit(0 if ok else 1)
	return true

func _inside_rendered_viewport(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk is SubViewportContainer or walk is SubViewport:
			return true
		walk = walk.get_parent()
	return false

func _in_color_page(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk.has_meta("missionforge_color_page"):
			return true
		walk = walk.get_parent()
	return false
