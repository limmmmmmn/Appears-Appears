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
## The hero always auto-walks toward the nearest valid field enemy (this is an
## auto-move game). WASD / arrows now pan the CAMERA, not the hero.
@export var auto_move_to_enemies: bool = true
## Click radius (world px) around the hero that counts as "click the hero" to snap
## the free-look camera back onto it.
@export var hero_click_radius: float = 24.0
## How fast the follow-camera eases toward the hero (higher = snappier). Kept
## gentle so the roam doesn't feel jerky / nauseating.
const CAMERA_SMOOTHING_SPEED: float = 4.0
## Keyboard pan speed (world px/sec) for WASD / arrow-key camera nudging.
const KEYBOARD_PAN_SPEED: float = 220.0
## Speed (world px/sec) the hero rushes to its battle-formation slot. The roam base
## speed (~60) lags behind the companions (≤180), so formation uses this snappy one.
const FORMATION_MOVE_SPEED: float = 175.0
## Mouse-wheel zoom range + step. zoom 1 = default; lower = see more (zoom out),
## higher = closer. MIN 0.32 shows ≈2000×1125 of world, framing the whole 1200×900
## board with a clear void margin all around (~400px sides, ~110px top/bottom) so a
## full zoom-out reads as a board floating in the void; MAX 3 is a close-up.
const ZOOM_MIN: float = 0.32
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.15

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
## Battle formation: show the hero's back (face UP) while settled in formation.
var _force_face_up: bool = false
## Battle formation: rush to this world slot (fast), then face up. Same interface as
## Companion so BattleManager drives the whole party uniformly.
var _formation_slot_active: bool = false
var _formation_slot: Vector2 = Vector2.ZERO
## Camera mode. While following, the camera is glued to the hero. The first pan
## input (WASD / arrows / mouse drag) DETACHES it into free-look — the hero can
## then walk anywhere without moving the view. Clicking the hero or a party box
## re-attaches it (see focus_camera_on_hero). The camera is top_level, so we drive
## its global_position directly in both modes.
var _camera_following: bool = true
## World position the free-look camera holds while detached.
var _free_camera_pos: Vector2 = Vector2.ZERO
## Mouse drag-pan state — fully polled in _update_camera_pan (no reliance on
## _unhandled_input, which a full-rect UI Control or Area2D physics picking can
## swallow). _drag_last_mouse is the cursor position last frame; _was_mouse_pressed
## tracks the button edge so we only test "started over UI?" once, on press.
var _is_drag_panning: bool = false
var _drag_last_mouse: Vector2 = Vector2.ZERO
var _was_mouse_pressed: bool = false


func set_forced_move_target(pos: Vector2) -> void:
	_forced_target = pos
	_forced_target_active = true


func clear_forced_move_target() -> void:
	_forced_target_active = false


## Battle formation: when on, the hero shows its back (faces UP toward the enemy
## windows) once it stops moving. BattleManager toggles this on arrival at the
## formation point and off when the fight ends.
func set_formation_facing(on: bool) -> void:
	_force_face_up = on


## Battle formation: rush to this world slot at FORMATION_MOVE_SPEED, then (settled)
## face up. BattleManager calls this on every party member (hero + companions).
func set_formation_slot(pos: Vector2) -> void:
	_formation_slot_active = true
	_formation_slot = pos
	_force_face_up = true


## Leave battle formation and resume auto-roam.
func clear_formation() -> void:
	_formation_slot_active = false
	_force_face_up = false


# ─── Battle-formation juice (only while facing up in formation) ─────────
func _on_party_member_attacked(index: int) -> void:
	if index == 0 and _force_face_up and _visual != null:
		_visual.play_attack_lunge()


func _on_party_damage_taken(member_index: int, _amount: int) -> void:
	if member_index == 0 and _force_face_up and _visual != null and not _downed_visual:
		_visual.play_hit_flinch()


func _ready() -> void:
	# Field enemies look us up via this group. Set before anything else so
	# enemies spawned on the same frame find us.
	add_to_group("player")
	add_to_group("party_member")
	# Camera is TOP-LEVEL (world space, not parented to our transform) so free-look
	# can hold a fixed world point while the hero walks off. In follow mode we drive
	# its global_position onto the hero each frame; smoothing eases both the roam and
	# the glide back when re-focusing.
	_camera.top_level = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = CAMERA_SMOOTHING_SPEED
	_camera.global_position = global_position
	_free_camera_pos = global_position
	_apply_zoom(GameState.field_camera_zoom)  # restore the player's last wheel zoom
	_camera.make_current()
	# Party-panel boxes emit this on click → snap the view back onto the hero.
	EventBus.camera_focus_hero_requested.connect(focus_camera_on_hero)
	# Battle-formation juice: the hero (party index 0) lunges on its attack, flinches
	# when hit — but only while standing in formation (facing up).
	EventBus.party_member_attacked.connect(_on_party_member_attacked)
	EventBus.party_damage_taken.connect(_on_party_damage_taken)
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
## Drag-pan is NOT handled here — it's fully polled in _update_camera_pan, because
## a full-rect UI Control (or Area2D physics picking) was eating the button/motion
## events before they reached this node. Wheel zoom still comes through fine.
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


func _physics_process(delta: float) -> void:
	# Camera pan runs first so you can look around even while combat is paused.
	_update_camera_pan(delta)
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
	# Auto-move game: the hero always walks itself. WASD/arrows pan the camera now.
	var move_dir := Vector2.ZERO
	var move_speed: float = GameState.effective_move_speed(speed)
	if _formation_slot_active:
		# Battle formation: hustle to the slot fast (the slow roam speed lagged the
		# companions). Facing up is handled below once settled.
		var to_slot: Vector2 = _formation_slot - global_position
		if to_slot.length() > 2.0:
			move_dir = to_slot.normalized()
		move_speed = FORMATION_MOVE_SPEED
	elif _forced_target_active:
		# Scripted walk (campfire mage event) overrides enemy-seeking until the
		# field clears the target on arrival.
		var to_fire: Vector2 = _forced_target - global_position
		if to_fire.length() > 1.0:
			move_dir = to_fire.normalized()
	elif auto_move_to_enemies:
		# Drift toward the nearest field enemy. Touching one triggers the encounter
		# automatically via FieldEnemy.body_entered. When no enemies remain, fall
		# back to chasing the nearest gold/item drop so idle moments stay productive.
		var target := _find_nearest_in_group(&"field_enemy")
		if target == null:
			target = _find_nearest_in_group(&"field_pickup")
		if target != null:
			var to_target: Vector2 = target.global_position - global_position
			if to_target.length() > 0.01:
				move_dir = to_target.normalized()
	velocity = move_dir * move_speed
	move_and_slide()
	global_position = Vector2(
		clampf(global_position.x, _field_bounds.position.x, _field_bounds.end.x),
		clampf(global_position.y, _field_bounds.position.y, _field_bounds.end.y)
	)
	# While downed, show the lying pose (idle frame) even if dragged along.
	# In battle formation, once settled, force the back-view (facing UP toward the
	# enemy windows) instead of the last walk direction.
	if _force_face_up and not _downed_visual and velocity.length_squared() < 1.0:
		_visual.face_dir(CharacterVisual.Dir.UP)
	else:
		_visual.set_velocity(Vector2.ZERO if _downed_visual else velocity)


## Drive the camera each frame. WASD / arrows and mouse drag pan a FREE-LOOK camera
## that detaches from the hero on first input; clicking the hero (or a party box →
## focus_camera_on_hero) re-attaches it. While following, the camera tracks the hero.
func _update_camera_pan(delta: float) -> void:
	if _camera == null:
		return
	# Keyboard pan (WASD / arrows).
	var pan := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	var key_panning: bool = pan != Vector2.ZERO

	# Mouse drag pan — fully polled so no UI/picking layer can swallow it. On the
	# press edge: a click ON the hero re-focuses; a click on empty field starts a
	# drag; a click on a UI Control (dock/shop/menu) is left alone.
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if pressed and not _was_mouse_pressed:
		var on_ui: bool = get_viewport().gui_get_hovered_control() != null
		if not on_ui and get_global_mouse_position().distance_to(global_position) <= hero_click_radius:
			focus_camera_on_hero()  # clicked the field hero → snap back
			_is_drag_panning = false
		else:
			_is_drag_panning = not on_ui
		_drag_last_mouse = mouse  # reset so the first frame has no jump
	elif not pressed:
		_is_drag_panning = false
	_was_mouse_pressed = pressed

	var drag_delta := Vector2.ZERO
	if _is_drag_panning:
		# Grab-the-world: drag right → view slides right (camera moves left). Divide
		# by zoom so the world tracks the cursor 1:1 at any zoom level.
		drag_delta = -(mouse - _drag_last_mouse) / _camera.zoom.x
	_drag_last_mouse = mouse

	# Any pan input detaches the camera into free-look and moves the held point.
	if key_panning or _is_drag_panning:
		if _camera_following:
			_detach_camera()
		if key_panning:
			_free_camera_pos += pan.normalized() * KEYBOARD_PAN_SPEED * delta
		_free_camera_pos += drag_delta
		_free_camera_pos = _free_camera_pos.clamp(_field_bounds.position, _field_bounds.end)

	# Drive the camera: glued to the hero, or holding the free-look point.
	_camera.global_position = global_position if _camera_following else _free_camera_pos


## Detach the camera from the hero into free-look. Smoothing off so the pan tracks
## the cursor / keys crisply (no rubber-banding while you're actively moving it).
func _detach_camera() -> void:
	_camera_following = false
	_free_camera_pos = _camera.global_position
	_camera.position_smoothing_enabled = false


## Re-attach the camera to the hero. Smoothing on so it glides back instead of
## snapping. Safe to call any time (party-box click, field-hero click, loop start).
func focus_camera_on_hero() -> void:
	_camera_following = true
	if _camera:
		_camera.position_smoothing_enabled = true


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


## Re-attach to the hero and cancel easing so the view snaps straight onto it
## (no glide). Kept so existing callers (Field on loop start) still work.
func snap_camera() -> void:
	_camera_following = true
	if _camera:
		_camera.position_smoothing_enabled = true
		_camera.global_position = global_position
		_free_camera_pos = global_position
		_camera.reset_smoothing()


## Re-center the view on the hero (leaves free-look, snaps on). Called by the Field
## on each loop start. Param kept for call-site compatibility.
func recenter_camera(_world_center: Vector2 = Vector2.ZERO) -> void:
	snap_camera()


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
