class_name Player
extends CharacterBody2D

## Top-down player avatar. Conceptually = the camera = the party (README: 시스템 3).
## Owns the Camera2D and its CharacterVisual. Combat lives in battle_windows.

@export var speed: float = 60.0

@onready var _visual: CharacterVisual = $Visual
@onready var _camera: Camera2D = $Camera2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _pending_data: CharacterData
var _field_bounds := Rect2(Vector2.ZERO, Vector2(960, 540))


func _ready() -> void:
	# Field enemies look us up via this group. Set before anything else so
	# enemies spawned on the same frame find us.
	add_to_group("player")
	add_to_group("party_member")
	_camera.make_current()
	# Match the camera update to CharacterBody2D movement. With pixel snapping
	# enabled, an idle-updated camera can visibly jitter during vertical walks.
	_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	# Party_changed re-creates the player mid-run (e.g. after recruiting a
	# companion). Snap so the camera doesn't pan from wherever it was.
	_camera.reset_smoothing()
	if _pending_data:
		_visual.setup(_pending_data)
		_apply_character_layout()


## Inject the character data (sprite sheet, stats). Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)
		_apply_character_layout()


func _apply_character_layout() -> void:
	if _pending_data == null:
		return
	if _camera:
		_camera.position = _pending_data.visual_center_local()
	if _collision_shape:
		var rect_shape := _collision_shape.shape as RectangleShape2D
		if rect_shape == null:
			rect_shape = RectangleShape2D.new()
			_collision_shape.shape = rect_shape
		rect_shape.size = _pending_data.body_size
		_collision_shape.position = _pending_data.body_center_local()


func set_field_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	_field_bounds = Rect2(min_pos, max_pos - min_pos)
	if _camera:
		_camera.limit_left = -10000000
		_camera.limit_right = 10000000
		_camera.limit_top = -10000000
		_camera.limit_bottom = 10000000


func _physics_process(_delta: float) -> void:
	if GameState.is_field_battle_paused():
		velocity = Vector2.ZERO
		_visual.set_velocity(velocity)
		return
	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	velocity = dir * GameState.effective_move_speed(speed)
	move_and_slide()
	global_position = Vector2(
		clampf(global_position.x, _field_bounds.position.x, _field_bounds.end.x),
		clampf(global_position.y, _field_bounds.position.y, _field_bounds.end.y)
	)
	_visual.set_velocity(velocity)


## Drop the camera's smoothing for one frame — used after teleporting the
## player (e.g. start of a new field loop) so the camera doesn't pan from the
## old spot.
func snap_camera() -> void:
	if _camera:
		_camera.reset_smoothing()
