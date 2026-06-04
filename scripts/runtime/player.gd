class_name Player
extends CharacterBody2D

## Top-down player avatar. Conceptually = the camera = the party (README: 시스템 3).
## Owns the Camera2D and its CharacterVisual. Combat lives in battle_windows.

@export var speed: float = 60.0
## Camera is fixed in world space, not parented to the player's transform.
## Centered on the FIELD center so the hero sits at the true viewport center
## (the left dock / right panel just overlay the edges — they don't shift the
## center). The Field updates this each loop via recenter_camera(). The field now
## spans the full 640 viewport width, so its center == viewport center (320).
@export var camera_world_position: Vector2 = Vector2(320.0, 180.0)
## When no WASD input is detected, auto-walk toward the nearest valid field enemy.
@export var auto_move_to_enemies: bool = true
## How fast the follow-camera eases toward the hero (higher = snappier). Kept
## gentle so the roam doesn't feel jerky / nauseating.
const CAMERA_SMOOTHING_SPEED: float = 4.0
## Mouse-wheel zoom range + step. zoom 1 = default; lower = see more of the map
## (zoom out), higher = closer (zoom in). MIN ~0.4 lets you see almost the whole
## 3×3 map at once; MAX 3 is a close-up.
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.15
## Below this magnitude of input we consider the player to be idle and let
## auto-move take over. Just above zero so digital keys still feel snappy.
const MANUAL_INPUT_THRESHOLD: float = 0.1

@onready var _visual: CharacterVisual = $Visual
@onready var _camera: Camera2D = $Camera2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _pending_data: CharacterData
var _field_bounds := Rect2(Vector2.ZERO, Vector2(960, 540))
var _camera_shake_tween: Tween
## True while this avatar's party member is downed (shows the lying pose).
var _downed_visual: bool = false
## One-time scripted walk target (campfire mage event). Overrides auto-move.
var _forced_target_active: bool = false
var _forced_target: Vector2 = Vector2.ZERO


func set_forced_move_target(pos: Vector2) -> void:
	_forced_target = pos
	_forced_target_active = true


func clear_forced_move_target() -> void:
	_forced_target_active = false


func _ready() -> void:
	# Field enemies look us up via this group. Set before anything else so
	# enemies spawned on the same frame find us.
	add_to_group("player")
	add_to_group("party_member")
	# Camera FOLLOWS the hero across the large world: it's a child of the player,
	# so leaving top_level off keeps it locked onto us. Smoothing eases the roam.
	_camera.top_level = false
	_camera.position = Vector2.ZERO  # local zero → sits exactly on the hero
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = CAMERA_SMOOTHING_SPEED
	_apply_zoom(GameState.field_camera_zoom)  # restore the player's last wheel zoom
	_camera.make_current()
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
	# Camera is top-level / fixed — its position is set once in _ready and is
	# not re-derived from the character data. We only update body collision
	# here so different party leaders (hero vs companion) still get a hitbox
	# that matches their sprite.
	if _collision_shape:
		var rect_shape := _collision_shape.shape as RectangleShape2D
		if rect_shape == null:
			rect_shape = RectangleShape2D.new()
			_collision_shape.shape = rect_shape
		rect_shape.size = _pending_data.body_size
		_collision_shape.position = _pending_data.body_center_local()


func set_field_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	_field_bounds = Rect2(min_pos, max_pos - min_pos)
	# Clamp the follow-camera to the map edges → bounded map (no endless roam).
	if _camera:
		_camera.limit_left = int(min_pos.x)
		_camera.limit_top = int(min_pos.y)
		_camera.limit_right = int(max_pos.x)
		_camera.limit_bottom = int(max_pos.y)


# ─── Mouse-wheel zoom ──────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(GameState.field_camera_zoom + ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(GameState.field_camera_zoom - ZOOM_STEP)


func _apply_zoom(z: float) -> void:
	var clamped: float = clampf(z, ZOOM_MIN, ZOOM_MAX)
	GameState.field_camera_zoom = clamped
	if _camera:
		_camera.zoom = Vector2(clamped, clamped)


func _physics_process(_delta: float) -> void:
	if GameState.is_field_battle_paused():
		velocity = Vector2.ZERO
		_visual.set_velocity(velocity)
		return
	# Whole party collapsed → hold still until everyone has fully recovered, then
	# resume together (movement latch in GameState).
	if GameState.is_movement_frozen():
		velocity = Vector2.ZERO
		_visual.set_velocity(Vector2.ZERO)
		return
	var manual_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var move_dir: Vector2 = manual_dir
	if move_dir.length() < MANUAL_INPUT_THRESHOLD and _forced_target_active:
		# Scripted walk (campfire mage event) overrides enemy-seeking until the
		# field clears the target on arrival.
		var to_fire: Vector2 = _forced_target - global_position
		if to_fire.length() > 1.0:
			move_dir = to_fire.normalized()
	elif move_dir.length() < MANUAL_INPUT_THRESHOLD and auto_move_to_enemies:
		# No WASD pressed → drift toward the nearest field enemy. Touching one
		# triggers the encounter automatically via FieldEnemy.body_entered.
		# When no enemies remain on the field, fall back to chasing the nearest
		# gold/item drop so idle moments still feel productive.
		var target := _find_nearest_in_group(&"field_enemy")
		if target == null:
			target = _find_nearest_in_group(&"field_pickup")
		if target != null:
			var to_target: Vector2 = target.global_position - global_position
			if to_target.length() > 0.01:
				move_dir = to_target.normalized()
	velocity = move_dir * GameState.effective_move_speed(speed)
	move_and_slide()
	global_position = Vector2(
		clampf(global_position.x, _field_bounds.position.x, _field_bounds.end.x),
		clampf(global_position.y, _field_bounds.position.y, _field_bounds.end.y)
	)
	# While downed, show the lying pose (idle frame) even if dragged along.
	_visual.set_velocity(Vector2.ZERO if _downed_visual else velocity)


## Field shows this avatar lying down while its party member is downed/refilling.
func set_downed_visual(is_down: bool) -> void:
	_downed_visual = is_down
	if _visual:
		_visual.rotation = deg_to_rad(90.0) if is_down else 0.0
		_visual.modulate = Color(0.6, 0.6, 0.66, 1.0) if is_down else Color(1, 1, 1, 1)


## Linear scan over a node group, returning the nearest Node2D whose
## `is_auto_move_target()` (if present) is still true. Used for both the
## `field_enemy` and `field_pickup` groups; lists are small (≤30) so a per-
## frame walk is fine.
func _find_nearest_in_group(group: StringName) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist_sq: float = INF
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_auto_move_target") and not node.is_auto_move_target():
			continue
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var d: float = global_position.distance_squared_to(node_2d.global_position)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = node_2d
	return nearest


## Follow-camera: cancel easing so it snaps straight onto the hero. Kept so
## existing callers (Field on loop start) still work.
func snap_camera() -> void:
	if _camera:
		_camera.reset_smoothing()


## Was "fix the camera on a world point"; now the camera follows the hero, so this
## just resets smoothing (no fixed target). Param kept for call-site compatibility.
func recenter_camera(_world_center: Vector2 = Vector2.ZERO) -> void:
	if _camera:
		_camera.reset_smoothing()


## Quick decaying screen shake. Tweens the camera offset (separate from the
## smoothed follow position) so it always returns cleanly to zero. Runs even
## while the field is battle-paused since tweens ignore our pause flag.
func shake_camera(strength: float = 4.0, duration: float = 0.25) -> void:
	if _camera == null:
		return
	if _camera_shake_tween and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()
	_camera_shake_tween = create_tween()
	var steps: int = 6
	var step_time: float = duration / float(steps)
	for i in steps:
		var falloff: float = 1.0 - float(i) / float(steps)
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		_camera_shake_tween.tween_property(_camera, "offset", offset, step_time)\
			.set_trans(Tween.TRANS_SINE)
	_camera_shake_tween.tween_property(_camera, "offset", Vector2.ZERO, step_time)
