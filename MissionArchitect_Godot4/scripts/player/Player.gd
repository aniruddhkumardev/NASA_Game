## Player.gd
## Third-person astronaut controller
## Attach to: CharacterBody3D node named "Player"

extends CharacterBody3D

# ─── Export Variables ─────────────────────────────────────────────────────────
@export var walk_speed: float        = 5.0
@export var sprint_speed: float      = 10.0
@export var jump_velocity: float     = 5.0
@export var mouse_sensitivity: float = 0.002
@export var camera_distance: float   = 4.0
@export var camera_height: float     = 1.5
@export var gravity: float           = 9.8
@export var interact_range: float    = 3.0

# ─── Node References ──────────────────────────────────────────────────────────
@onready var camera_pivot: Node3D       = $CameraPivot
@onready var camera: Camera3D           = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D  = $BodyMesh
@onready var interact_ray: RayCast3D    = $InteractRayCast
var anim_player: AnimationPlayer = null

# ─── State ────────────────────────────────────────────────────────────────────
var camera_yaw: float   = 0.0
var camera_pitch: float = -0.3
var is_sprinting: bool  = false
var is_grounded: bool   = true
var near_interactable: Node = null
var mouse_captured: bool = false

# ─── Signals ──────────────────────────────────────────────────────────────────
signal interaction_available(node: Node, hint: String)
signal interaction_ended()

func _ready() -> void:
	# Position camera behind player
	if camera_pivot:
		camera_pivot.position = Vector3(0, camera_height, 0)
	if camera:
		camera.position = Vector3(0, 0, camera_distance)
	capture_mouse()
	print("[Player] Astronaut controller ready")

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and mouse_captured:
		camera_yaw   -= event.relative.x * mouse_sensitivity
		camera_pitch -= event.relative.y * mouse_sensitivity
		camera_pitch  = clamp(camera_pitch, -PI / 3.0, PI / 6.0)
		rotation.y    = camera_yaw
		if camera_pivot:
			camera_pivot.rotation.x = camera_pitch

	# Toggle mouse capture
	if event.is_action_pressed("pause_game"):
		if mouse_captured:
			release_mouse()
		else:
			capture_mouse()

func _physics_process(delta: float) -> void:
	if GameManager.is_paused:
		return

	_handle_movement(delta)
	_check_interaction()
	move_and_slide()

func _handle_movement(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0:
			velocity.y = 0.0

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint")
	var speed: float = sprint_speed if is_sprinting else walk_speed

	# Movement direction (relative to camera)
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

func _check_interaction() -> void:
	if not interact_ray:
		return
	if Input.is_action_just_pressed("interact"):
		if near_interactable and near_interactable.has_method("interact"):
			near_interactable.interact()
			return

	# Check raycast for interactable objects
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var collider: Object = interact_ray.get_collider()
		if collider and collider.has_method("get_interact_hint"):
			if near_interactable != collider:
				near_interactable = collider
				interaction_available.emit(collider, collider.get_interact_hint())
		else:
			if near_interactable != null:
				near_interactable = null
				interaction_ended.emit()
	else:
		if near_interactable != null:
			near_interactable = null
			interaction_ended.emit()

func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
