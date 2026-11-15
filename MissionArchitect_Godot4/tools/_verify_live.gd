extends SceneTree

# LIVE verify: run the real launch scene headless, auto-launch, fly fast via
# _debug_warp until it actually reaches SATELLITE_DEPLOY, then dump the live
# camera + environment state and compute how much of the frame is Earth vs space.

const DEPLOY_STATE := 7  # LaunchState.SATELLITE_DEPLOY
const R := 340.0
const FOV_V := 70.0

var node: Node = null
var frames := 0
var deploy_frames := 0
var tracking_done := false

func _init() -> void:
	var ps := load("res://scenes/launch/launch.tscn") as PackedScene
	var scene := ps.instantiate()
	root.add_child(scene)
	node = _find_seq(scene)
	if node == null:
		print("PROBE-ERR: LaunchSequence node not found")
		quit(1); return
	node.set("_debug_warp", 600.0)
	process_frame.connect(_on_frame)

func _find_seq(n: Node) -> Node:
	if n.has_method("_update_satellite_deploy"):
		return n
	for c in n.get_children():
		var r := _find_seq(c)
		if r: return r
	return null

func _on_frame() -> void:
	frames += 1
	if frames == 3:
		node.call("_on_launch_pressed")
	var st: int = node.get("state")
	if st == DEPLOY_STATE:
		deploy_frames += 1
		if deploy_frames == 40 and not tracking_done:
			# reproduce the user's screenshot: select the "Tracking" thumbnail
			node.call("_select_cam_view", 4)
			tracking_done = true
		if deploy_frames >= 120:
			_dump()
			quit(); return
	if frames > 8000:
		print("PROBE-TIMEOUT last_state=", st, " frames=", frames)
		quit(); return

func _coverage(cam: Camera3D, center: Vector3) -> String:
	if cam == null:
		return "cam=null"
	var pos := cam.global_position
	var alt := pos.distance_to(center)
	var earth_aa := rad_to_deg(asin(clampf(R / alt, -1.0, 1.0)))
	var nadir := (center - pos).normalized()
	var axis := -cam.global_transform.basis.z  # camera looks along -Z
	var axis_from_nadir := rad_to_deg(acos(clampf(axis.dot(nadir), -1.0, 1.0)))
	var lo: float = axis_from_nadir - FOV_V * 0.5
	var hi: float = axis_from_nadir + FOV_V * 0.5
	var earth_span: float = clampf(minf(hi, earth_aa) - maxf(lo, 0.0), 0.0, FOV_V)
	var pct: float = earth_span / FOV_V * 100.0
	return "alt=%.1f earthAA=%.1f axisFromNadir=%.1f EARTH=%.0f%% SPACE=%.0f%%" % [alt, earth_aa, axis_from_nadir, pct, 100.0 - pct]

func _dump() -> void:
	var center: Vector3 = node.get("space_center") as Vector3
	var active: Camera3D = node.get("active_camera") as Camera3D
	var cam_space: Camera3D = node.get("cam_space") as Camera3D
	var cam_chase: Camera3D = node.get("cam_chase") as Camera3D
	var payload = node.get("payload_craft")
	var world_env = node.get("world_env")
	print("=== LIVE DEPLOY DUMP (Tracking selected) ===")
	print("active_camera = ", active.name if active else "NULL", " | cam_mode = ", node.get("cam_mode"))
	print("cam_space.current=", cam_space.current if cam_space else "?", " cam_chase.current=", cam_chase.current if cam_chase else "?")
	if payload and payload is Node3D:
		print("payload.global_position=", payload.global_position, " visible=", payload.visible)
	print("space_center=", center)
	if world_env != null and world_env.environment != null:
		var e = world_env.environment
		print("bg_mode=", e.background_mode, " bg_color=", e.background_color, " fog=", e.fog_enabled)
	print("SPACE-CAM coverage : ", _coverage(cam_space, center))
	print("CHASE-CAM coverage : ", _coverage(cam_chase, center))
	print("ACTIVE  coverage   : ", _coverage(active, center))
	print("PROBE-DONE")
