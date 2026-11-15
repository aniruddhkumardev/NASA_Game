## Hangar.gd
## The starting level — player walks around the space agency hangar,
## approaches mission terminals, and selects a mission.

extends Node3D

@onready var mission_ui: Control      = $HangarUI
@onready var player: CharacterBody3D  = $Player
@onready var interact_hint: Label     = $HUD/InteractHint
@onready var mission_panel: Control   = $HangarUI/MissionPanel

var showing_mission_panel: bool = false

func _ready() -> void:
	interact_hint.hide()
	mission_panel.hide()
	if player.has_signal("interaction_available"):
		player.interaction_available.connect(_on_interaction_available)
		player.interaction_ended.connect(_on_interaction_ended)
	print("[Hangar] Scene ready")

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause_game") and showing_mission_panel:
		_close_mission_panel()

func _on_interaction_available(_node: Node, hint: String) -> void:
	interact_hint.text = "[E] " + hint
	interact_hint.show()

func _on_interaction_ended() -> void:
	interact_hint.hide()

func open_mission_panel() -> void:
	showing_mission_panel = true
	mission_panel.show()
	player.release_mouse()
	_populate_mission_panel()

func _close_mission_panel() -> void:
	showing_mission_panel = false
	mission_panel.hide()
	player.capture_mouse()

func _populate_mission_panel() -> void:
	# This is called by the UI scene — missions are populated from GameManager
	pass

func start_selected_mission(mission_id: String) -> void:
	_close_mission_panel()
	GameManager.start_mission(mission_id)
