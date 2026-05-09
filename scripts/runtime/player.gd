class_name Player
extends CharacterBody2D

## Top-down player avatar. Conceptually = the camera = the party (README: 시스템 3).
## Owns the Camera2D and its CharacterVisual. Combat lives in battle_windows.

@export var speed: float = 80.0

@onready var _visual: CharacterVisual = $Visual
@onready var _camera: Camera2D = $Camera2D

var _pending_data: CharacterData


func _ready() -> void:
	_camera.make_current()
	if _pending_data:
		_visual.setup(_pending_data)


## Inject the character data (sprite sheet, stats). Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)


func _physics_process(_delta: float) -> void:
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()
	_visual.set_velocity(velocity)


## Drop the camera's smoothing for one frame — used after teleporting the
## player (e.g. start of a new stage) so the camera doesn't pan from the
## old spot.
func snap_camera() -> void:
	if _camera:
		_camera.reset_smoothing()
