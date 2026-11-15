extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://scenes/ui/mission_select.tscn").instantiate()
	root.add_child(scene)
	await process_frame

	var viewport: SubViewport = scene.get("hangar_viewport") as SubViewport
	var cards: Array = scene.get("_card_data")
	if not viewport or viewport.size != Vector2i(1280, 720):
		push_error("Mission hangar viewport setup failed.")
		quit(1)
		return
	if cards.size() != 4 or scene.get_node("ScrollContainer/MissionGrid").get_child_count() != 4:
		push_error("Expected four mission cards.")
		quit(1)
		return
	if scene.get_node_or_null("MissionHangar3D") == null:
		push_error("3D hangar container is missing.")
		quit(1)
		return
	var environment_node := viewport.get_node_or_null("MissionHangarWorld/WorldEnvironment") as WorldEnvironment
	if not environment_node or not environment_node.environment.sky:
		push_error("Starfield sky is missing from the hangar environment.")
		quit(1)
		return
	if viewport.get_node_or_null("MissionHangarWorld/NASA_VAB_Photo_Backdrop") != null:
		push_error("NASA photo billboard must not cover the hangar scene.")
		quit(1)
		return
	var sky_material := environment_node.environment.sky.sky_material as PanoramaSkyMaterial
	if not sky_material or sky_material.panorama == null:
		push_error("Starfield panorama failed to load.")
		quit(1)
		return
	for index in range(cards.size()):
		var rocket: Node3D = cards[index].get("rocket")
		if not rocket or rocket.get_node_or_null("DetailedLaunchVehicle") == null:
			push_error("Detailed launch vehicle missing for mission %d." % (index + 1))
			quit(1)
			return
	if scene.get_node_or_null("DetailPanel") != null:
		push_error("Legacy detail panel still occupies the mission-card area.")
		quit(1)
		return
	print("3D mission selection layout smoke test passed.")
	quit(0)
