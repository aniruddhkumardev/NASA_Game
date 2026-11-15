extends SceneTree

## Live verification for click-to-inspect + zoom on the Earth globe.
## Picks the Gulf Stream site on screen, checks the ray→lat/lon round-trip,
## zooms in, and saves before/after screenshots.

var gm = null
var sim = null
var frames := 0
var configured := false
var phase := 0
var settle := 0
var results: Array[String] = []
var target_lat := 36.0
var target_lon := -70.0

func _initialize() -> void:
	change_scene_to_file("res://scenes/orbit/orbit.tscn")

func _process(_delta: float) -> bool:
	frames += 1
	if not configured:
		if frames < 3:
			return false
		gm = root.get_node_or_null("/root/GameManager")
		sim = root.get_node_or_null("/root/SimulationEngine")
		if gm == null or sim == null or current_scene == null:
			if frames > 180:
				_finish(["ABORT: autoload/scene missing"])
				return true
			return false
		_configure()
		configured = true
		return false

	match phase:
		0:
			# Skip the scripted arrival + commissioning film; go straight to the
			# operations camera the player uses for clicking.
			current_scene._finish_orbit_arrival()
			if current_scene.commission_overlay:
				current_scene.commission_overlay.hide()
			current_scene.commissioning_active = false
			sim.set_time_scale(4)
			settle = frames + 30
			phase = 1
		1:
			if frames >= settle:
				# A sensed-event flyover can be holding the camera; the player can
				# only click after it clears, so clear it here too.
				current_scene.fly_time = 0.0
				if current_scene.fly_panel:
					current_scene.fly_panel.visible = false
				if current_scene.mission_camera:
					current_scene.mission_camera.position = Vector3(-11.5, 7.5, 14.5)
					current_scene.mission_camera.look_at(Vector3.ZERO, Vector3.UP)
					current_scene.mission_camera.fov = 60.0
				var pos := _site_screen_pos(target_lat, target_lon)
				print("PROBE click at screen %s (viewport %s)" % [str(pos), str(root.get_visible_rect().size)])
				current_scene._pick_surface_area(pos)
				settle = frames + 90
				phase = 2
		2:
			if frames >= settle:
				_check_pick()
				_shot("_diag_area_inspection.png")
				# Zoom in three notches on the same patch.
				for i in range(3):
					current_scene._zoom_step(1.0)
				settle = frames + 45
				phase = 3
		3:
			if frames >= settle:
				var panel = current_scene.find_child("AreaInspectionPanel", true, false)
				_assert(panel != null and panel.visible, "area panel still visible after zoom")
				_assert(current_scene.inspect_distance < 1.4, "zoom-in reduced camera altitude (%.2f)" % current_scene.inspect_distance)
				_shot("_diag_area_inspection_zoom.png")
				# Search a named place and fly there.
				current_scene.place_search_edit.text = "Syktyvkar"
				current_scene._on_place_query_changed("Syktyvkar")
				var results = current_scene.find_child("PlaceSearchResults", true, false)
				_assert(results != null and results.visible and results.item_count > 0,
					"search returns results for Syktyvkar")
				current_scene._choose_place_by_index(0)
				settle = frames + 90
				phase = 4
		4:
			if frames >= settle:
				var place_label = current_scene.find_child("AreaPlaceLabel", true, false)
				_assert(current_scene.inspect_active, "search selection activated inspection")
				_assert(absf(current_scene.inspect_lat - 61.66) < 1.0
					and absf(wrapf(current_scene.inspect_lon - 50.82, -180.0, 180.0)) < 2.0,
					"search flew to Syktyvkar (%.2f, %.2f)" % [current_scene.inspect_lat, current_scene.inspect_lon])
				_assert(place_label != null and place_label.text.contains("Syktyvkar")
					and place_label.text.contains("Russia"), "panel shows the searched place name")
				_shot("_diag_place_search.png")
				current_scene._exit_area_inspection()
				settle = frames + 80
				phase = 5
		5:
			if frames >= settle:
				var panel = current_scene.find_child("AreaInspectionPanel", true, false)
				_assert(panel != null and not panel.visible, "right-click/back closes the area panel")
				_assert(not current_scene.inspect_active, "inspection mode exited")
				_finish(results)
				return true
	return false


func _configure() -> void:
	var mission: Dictionary = gm.missions[0].duplicate(true)
	assert(String(mission.get("id", "")) == "earth_climate")
	gm.current_mission = mission
	var cfg = gm.spacecraft_config
	cfg["bus"] = {"data_storage": 900.0, "reliability": 0.93}
	cfg["comms"] = {"bandwidth_mbps": 10.0}
	cfg["instruments"] = [
		_find_comp("instruments", "thermal"),
		_find_comp("instruments", "radar"),
		_find_comp("instruments", "spectrometer"),
	]
	cfg["rocket"] = {"reliability": 0.95}
	cfg["total_data_rate"] = 20.0
	cfg["total_science_per_orbit"] = 30.0
	cfg["total_power_gen"] = 320.0
	cfg["total_power_draw"] = 150.0
	cfg["battery_capacity"] = 1500.0
	cfg["total_cost"] = 118.0
	sim.start_simulation(20261106)
	sim.set_time_scale(4)

func _find_comp(list_name: String, id: String) -> Dictionary:
	for c in gm.components.get(list_name, []):
		if String(c.get("id", "")) == id:
			return c.duplicate(true)
	return {}

func _site_screen_pos(lat: float, lon: float) -> Vector2:
	var world_angle: float = sim.earth_rotation_rad + current_scene.earth_node.rotation.y
	var dir: Vector3 = sim.station_local_direction(lat, lon).rotated(Vector3.UP, world_angle)
	return current_scene.mission_camera.unproject_position(dir * current_scene.earth_surface_radius)

func _check_pick() -> void:
	_assert(current_scene.inspect_active, "click activated area inspection")
	var panel = current_scene.find_child("AreaInspectionPanel", true, false)
	_assert(panel != null and panel.visible, "area panel visible")
	_assert(current_scene.area_panel.visible, "area_panel reference visible")
	var dlat: float = absf(current_scene.inspect_lat - target_lat)
	var dlon: float = absf(wrapf(current_scene.inspect_lon - target_lon, -180.0, 180.0))
	_assert(dlat < 1.0 and dlon < 1.0,
		"ray hit round-trips to site (%.2f, %.2f vs %.1f, %.1f)" % [
			current_scene.inspect_lat, current_scene.inspect_lon, target_lat, target_lon])
	var readout: String = current_scene.area_coords.text + " | " + current_scene.area_place.text \
		+ " | " + current_scene.area_temp.text \
		+ " | " + current_scene.area_weather.text + " | " + current_scene.area_wind.text \
		+ " | " + current_scene.area_solar.text + " | " + current_scene.area_site.text \
		+ " | " + current_scene.area_source.text
	print("PROBE readout: " + readout)
	var temp: float = float(current_scene.inspect_conditions.get("temp_c", 999.0))
	_assert(temp > -70.0 and temp < 60.0, "temperature in a plausible range (%.1f C)" % temp)
	_assert(String(current_scene.inspect_conditions.get("condition", "")) != "", "weather condition populated")
	_assert(not current_scene.inspect_place.is_empty(), "click resolved a real place name (%s)" % current_scene.area_place.text)
	var near: Dictionary = current_scene._nearest_place(60.5, 51.0)
	_assert(String(near.get("name", "")) == "Syktyvkar",
		"reverse lookup at 60.5N 51.0E finds Syktyvkar (%s)" % String(near.get("name", "")))
	_assert(current_scene.area_site.text.contains("Gulf Stream"), "nearest real SWOT site identified")
	_assert(current_scene.area_source.text.contains("SWOT"), "panel names the source mission for the site data")
	_assert(current_scene.area_source.text.contains("in-game estimate"), "panel labels temperature/weather as an in-game estimate")
	_assert(current_scene.inspect_pin != null and current_scene.inspect_pin.visible, "surface marker pinned")
	_assert(current_scene.inspect_ring != null, "surface ring marker built")
	var hint = current_scene.find_child("AreaInspectionLayer", true, false)
	_assert(hint != null, "area inspection layer built")

func _assert(cond: bool, label: String) -> void:
	results.append(("PASS: " if cond else "FAIL: ") + label)

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png("res://tools/" + name)
	results.append("SHOT: %s err=%d %dx%d" % [name, err, img.get_width(), img.get_height()])

func _finish(lines: Array[String]) -> void:
	for l in lines:
		print(l)
	var f := FileAccess.open("res://tools/_area_probe_result.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	quit(0)
