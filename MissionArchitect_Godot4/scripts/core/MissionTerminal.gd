## MissionTerminal.gd
## Interactable mission terminal in the hangar.
## Player walks up, presses E, mission selection opens.

extends StaticBody3D

@export var terminal_label: String = "Mission Control Terminal"
@onready var glow_mesh: MeshInstance3D = $GlowMesh if has_node("GlowMesh") else null
@onready var label_3d: Label3D = $Label3D if has_node("Label3D") else null

var _tween: Tween = null

func _ready() -> void:
	if label_3d:
		label_3d.text = terminal_label

func get_interact_hint() -> String:
	return "Access Mission Terminal"

func interact() -> void:
	# Find hangar root and open mission panel
	var hangar: Node = get_tree().get_first_node_in_group("hangar")
	if hangar and hangar.has_method("open_mission_panel"):
		hangar.open_mission_panel()
	else:
		# Fallback: go directly to mission selection screen
		GameManager.go_to_scene("res://scenes/ui/mission_select.tscn")

func _on_player_near() -> void:
	# Glow animation when player approaches
	if glow_mesh:
		if _tween:
			_tween.kill()
		_tween = create_tween().set_loops()
		_tween.tween_property(glow_mesh, "transparency", 0.2, 0.8)
		_tween.tween_property(glow_mesh, "transparency", 0.7, 0.8)

func _on_player_far() -> void:
	if _tween:
		_tween.kill()
	if glow_mesh:
		glow_mesh.transparency = 0.5
