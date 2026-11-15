## HUD.gd
## In-game HUD overlay — works across hangar, launch, and orbit scenes

extends CanvasLayer

@onready var fps_label: Label = $FPSLabel if has_node("FPSLabel") else null
@onready var phase_label: Label = $PhaseLabel if has_node("PhaseLabel") else null

func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)

func _process(_delta: float) -> void:
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _on_phase_changed(phase: int) -> void:
	var phase_names: Array = [
		"Main Menu", "Hangar", "Spacecraft Builder",
		"Launch Sequence", "Orbital Operations", "Mission Report"
	]
	if phase_label and phase < phase_names.size():
		if phase == GameManager.Phase.ORBIT and GameManager.is_mars_mission():
			phase_label.text = "Mars Climate Expedition"
		else:
			phase_label.text = phase_names[phase]
