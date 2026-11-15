## Persistent flight-continuity layer. It survives scene changes and replaces hard cuts
## with a short navigation-camera handoff.
extends CanvasLayer

var veil: ColorRect
var caption: Label
var detail: Label
var busy := false

func _ready() -> void:
	layer = 100
	veil = ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0, 0, 0, 0.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	caption.position = Vector2(-310, -38)
	caption.size = Vector2(620, 38)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color("#FFFFFF"))
	caption.visible = false
	add_child(caption)
	detail = Label.new()
	detail.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	detail.position = Vector2(-330, 8)
	detail.size = Vector2(660, 28)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 15)
	detail.add_theme_color_override("font_color", Color("#B3B3B3"))
	detail.visible = false
	add_child(detail)

func travel(scene_path: String, title: String, subtitle: String) -> void:
	if busy:
		return
	busy = true
	caption.text = title
	detail.text = subtitle
	caption.visible = true
	detail.visible = true
	# A light, quick cross-dissolve rather than a dip to black. The orbit shot
	# hands off to the transfer shot (and the transfer to the landing) with the
	# starfield and Earth still visible through the veil, so the flight reads as
	# one continuous move instead of cutting to a black screen in the middle.
	var fade_in := create_tween()
	fade_in.tween_property(veil, "color:a", 0.5, 0.42)
	await fade_in.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	var fade_out := create_tween()
	fade_out.tween_property(veil, "color:a", 0.0, 0.85)
	await fade_out.finished
	caption.visible = false
	detail.visible = false
	busy = false
