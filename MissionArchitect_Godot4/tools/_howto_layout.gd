extends SceneTree

## Temporary probe: open the How To Play modal and dump every control's size
## and visibility so the broken layout can be located. Deleted after use.

func _initialize() -> void:
	var scene: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(scene)
	for i in 6:
		await process_frame
	var ov: Control = scene.get_node_or_null("HowToPlayOverlay")
	if ov == null:
		_dump("NOT FOUND")
		return
	ov.call("open")
	for i in 10:
		await process_frame
	var lines := PackedStringArray([
		"viewport=%s" % str(root.get_visible_rect().size),
		"overlay size=%s global=%s visible=%s" % [str(ov.size), str(ov.get_global_rect()), str(ov.visible)],
		"",
	])
	_walk(ov, 0, lines)
	_dump("\n".join(lines))

func _walk(n: Node, depth: int, lines: PackedStringArray) -> void:
	if n is Control:
		var c := n as Control
		var pad := "".lpad(depth * 2, " ")
		lines.append("%s%s (%s) size=%s pos=%s vis=%s min=%s" % [
			pad, c.name, c.get_class(), str(c.size), str(c.position),
			str(c.visible), str(c.custom_minimum_size)])
	for ch in n.get_children():
		_walk(ch, depth + 1, lines)

func _dump(text: String) -> void:
	var f := FileAccess.open("res://tools/_howto_layout.txt", FileAccess.WRITE)
	f.store_string(text + "\n")
	f.close()
	quit()
