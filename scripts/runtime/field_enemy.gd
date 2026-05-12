class_name FieldEnemy
extends Area2D

## Enemy as it appears on the field (top-down).
## Wanders until the party gets close, pops an alert, then chases the player.
## On player collision, emits enemy_encountered and frees itself — the
## battle_window takes over from there.

@export var data: EnemyData
@export var wander_speed: float = 18.0
@export var chase_speed: float = 58.0  ## pixels/sec. Player is 80.
@export var detect_radius: float = 92.0
@export var lose_radius: float = 180.0
@export var charge_enabled: bool = false
@export var charge_trigger_radius: float = 72.0
@export var charge_speed: float = 180.0
@export var charge_duration: float = 0.28
@export var charge_cooldown: float = 1.1
@export var alert_duration: float = 0.45
@export var wander_turn_time_min: float = 0.7
@export var wander_turn_time_max: float = 1.8
@export var wander_pause_time_min: float = 0.35
@export var wander_pause_time_max: float = 1.1
@export var wander_pause_chance: float = 0.45
@export var spawn_telegraph_duration: float = 0.75
@export var wander_bounds_min: Vector2 = Vector2(16, 16)
@export var wander_bounds_max: Vector2 = Vector2(1264, 704)
@export var chase_squish_amount: float = 0.08
@export var chase_squish_speed: float = 10.0
@export var wander_squish_amount: float = 0.035
@export var wander_squish_speed: float = 5.5
@export var charge_squish_amount: float = 0.14
@export var squish_recover_speed: float = 10.0
## Enemy sprites are authored facing left. Flip only when moving right.
## When |velocity.x| is below this we leave flip_h alone so vertical chases
## don't jitter the sprite back and forth between frames.
@export var flip_threshold: float = 1.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _alert_bubble: Control = $AlertBubble
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _player: Node2D
var _target: Node2D
var _triggered: bool = false
var _spawning: bool = true
var _state: int = State.WANDER
var _wander_mode: int = WanderMode.MOVE
var _alert_timer: float = 0.0
var _charge_timer: float = 0.0
var _charge_cooldown_timer: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _wander_dir: Vector2 = Vector2.RIGHT
var _squish_time: float = 0.0
var _despawning: bool = false

enum State { WANDER, ALERT, CHASE, CHARGE }
enum WanderMode { MOVE, PAUSE }

func _ready() -> void:
	_apply_data()
	body_entered.connect(_on_body_entered)
	_player = _find_player()
	_pick_new_wander_dir()
	_start_spawn_telegraph()


## Allow callers to inject data after instantiate().
func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data and data.sprite and _sprite:
		_sprite.texture = data.sprite
	if data == null:
		return
	wander_speed = data.field_wander_speed
	chase_speed = data.field_chase_speed
	detect_radius = data.field_detect_radius
	lose_radius = data.field_lose_radius
	charge_enabled = data.field_charge_enabled
	charge_trigger_radius = data.field_charge_trigger_radius
	charge_speed = data.field_charge_speed
	charge_duration = data.field_charge_duration
	charge_cooldown = data.field_charge_cooldown


func _physics_process(delta: float) -> void:
	if _triggered or _spawning or _despawning:
		return
	_charge_cooldown_timer = maxf(0.0, _charge_cooldown_timer - delta)
	if _state == State.WANDER:
		_process_wander(delta)
	elif _state == State.ALERT:
		_process_alert(delta)
		_recover_sprite_scale(delta)
	elif _state == State.CHASE:
		_process_chase(delta)
	else:
		_process_charge(delta)


func _process_wander(delta: float) -> void:
	if _can_chase_player():
		var detected := _find_nearest_party_member(detect_radius)
		if detected:
			_target = detected
			_enter_alert()
			return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_next_wander_action()
	if _wander_mode == WanderMode.PAUSE:
		_recover_sprite_scale(delta)
		return
	var velocity: Vector2 = _wander_dir * wander_speed
	global_position += velocity * delta
	_keep_inside_field()
	_update_sprite_flip(velocity)
	_apply_wander_squish(delta)


func _process_alert(delta: float) -> void:
	_alert_timer -= delta
	if _alert_timer <= 0.0:
		_enter_chase()


func _process_chase(delta: float) -> void:
	_refresh_target()
	if _target == null:
		_enter_wander()
		return
	var to_target: Vector2 = _target.global_position - global_position
	if to_target.length() > lose_radius:
		_enter_wander()
		return
	if to_target.length_squared() < 1.0:
		return
	if _can_charge(to_target):
		_enter_charge(to_target.normalized())
		return
	var velocity: Vector2 = to_target.normalized() * chase_speed
	global_position += velocity * delta
	_keep_inside_field()
	_update_sprite_flip(velocity)
	_apply_chase_squish(delta, chase_squish_amount)


func _process_charge(delta: float) -> void:
	_charge_timer -= delta
	var velocity: Vector2 = _charge_dir * charge_speed
	global_position += velocity * delta
	_keep_inside_field()
	_update_sprite_flip(velocity)
	_apply_chase_squish(delta, charge_squish_amount)
	if _charge_timer <= 0.0:
		_sprite.modulate = Color.WHITE
		_enter_chase()


func _can_charge(to_target: Vector2) -> bool:
	return (
		charge_enabled
		and _charge_cooldown_timer <= 0.0
		and to_target.length() <= charge_trigger_radius
		and to_target.length_squared() >= 1.0
	)


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _can_chase_player() -> bool:
	return data == null or data.chases_player_on_field


func _find_nearest_party_member(radius: float) -> Node2D:
	var nearest: Node2D
	var nearest_dist_sq := radius * radius
	for node in get_tree().get_nodes_in_group("party_member"):
		var party_member := node as Node2D
		if party_member == null or not is_instance_valid(party_member):
			continue
		var dist_sq := global_position.distance_squared_to(party_member.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest = party_member
			nearest_dist_sq = dist_sq
	return nearest


func _refresh_target() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player:
		_target = _player
	elif _target == null or not is_instance_valid(_target):
		_target = _find_nearest_party_member(lose_radius)


func _enter_alert() -> void:
	_state = State.ALERT
	_alert_timer = alert_duration
	_alert_bubble.visible = true


func _enter_chase() -> void:
	_state = State.CHASE
	_alert_bubble.visible = false
	_sprite.modulate = Color.WHITE
	_refresh_target()


func _enter_wander() -> void:
	_state = State.WANDER
	_target = null
	_alert_bubble.visible = false
	_sprite.modulate = Color.WHITE
	_pick_next_wander_action()


func _enter_charge(direction: Vector2) -> void:
	_state = State.CHARGE
	_charge_dir = direction
	_charge_timer = charge_duration
	_charge_cooldown_timer = charge_cooldown
	_alert_bubble.visible = false
	_sprite.modulate = Color(1.0, 0.55, 0.36, 1.0)


func _pick_new_wander_dir() -> void:
	_wander_mode = WanderMode.MOVE
	_wander_timer = randf_range(wander_turn_time_min, wander_turn_time_max)
	_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)


func _pick_next_wander_action() -> void:
	if randf() < wander_pause_chance:
		_wander_mode = WanderMode.PAUSE
		_wander_timer = randf_range(wander_pause_time_min, wander_pause_time_max)
		return
	_pick_new_wander_dir()


func _keep_inside_field() -> void:
	var clamped := Vector2(
		clampf(global_position.x, wander_bounds_min.x, wander_bounds_max.x),
		clampf(global_position.y, wander_bounds_min.y, wander_bounds_max.y)
	)
	if clamped != global_position:
		global_position = clamped
		_pick_new_wander_dir()


func _update_sprite_flip(velocity: Vector2) -> void:
	if absf(velocity.x) > flip_threshold:
		_sprite.flip_h = velocity.x > 0


func _apply_chase_squish(delta: float, amount: float) -> void:
	_squish_time += delta * chase_squish_speed
	var wave: float = sin(_squish_time)
	_sprite.scale = Vector2(1.0 + wave * amount, 1.0 - wave * amount * 0.65)


func _apply_wander_squish(delta: float) -> void:
	_squish_time += delta * wander_squish_speed
	var wave: float = sin(_squish_time)
	_sprite.scale = Vector2(1.0 + wave * wander_squish_amount, 1.0 - wave * wander_squish_amount * 0.55)


func _recover_sprite_scale(delta: float) -> void:
	_sprite.scale = _sprite.scale.move_toward(Vector2.ONE, squish_recover_speed * delta)


func _start_spawn_telegraph() -> void:
	_spawning = true
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	_alert_bubble.visible = false
	_sprite.visible = false
	var sparkle: Node2D = _build_spawn_sparkle()
	add_child(sparkle)
	var tween: Tween = create_tween().set_loops(3)
	tween.tween_property(sparkle, "scale", Vector2.ONE * 1.25, spawn_telegraph_duration / 6.0)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(sparkle, "scale", Vector2.ONE * 0.72, spawn_telegraph_duration / 6.0)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	await get_tree().create_timer(spawn_telegraph_duration).timeout
	if not is_instance_valid(self):
		return
	sparkle.queue_free()
	_sprite.visible = true
	_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var reveal: Tween = create_tween()
	reveal.tween_property(_sprite, "modulate", Color.WHITE, 0.16)
	_collision_shape.disabled = false
	monitoring = true
	monitorable = true
	_spawning = false


func despawn_with_pop() -> void:
	if _despawning or _triggered:
		return
	_despawning = true
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	_alert_bubble.visible = false
	_sprite.visible = true
	var drift: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-12.0, -6.0))
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position", position + drift, 0.24)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(1.45, 0.55), 0.10)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "scale", Vector2(0.05, 1.65), 0.18)\
		.set_delay(0.08)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	tween.tween_property(_sprite, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.16)\
		.set_delay(0.08)
	tween.chain().tween_callback(queue_free)


func _build_spawn_sparkle() -> Node2D:
	var root := Node2D.new()
	root.name = "SpawnSparkle"
	root.z_index = 4
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(-8, -3),
		Vector2(8, -3),
		Vector2(-4, 7),
		Vector2(5, 6),
	]
	for i in offsets.size():
		var sparkle := Polygon2D.new()
		sparkle.polygon = PackedVector2Array([
			Vector2(0, -4),
			Vector2(3, 0),
			Vector2(0, 4),
			Vector2(-3, 0),
		])
		sparkle.position = offsets[i]
		sparkle.color = Color(1.0, 0.94, 0.35, 1.0) if i % 2 == 0 else Color(1.0, 1.0, 1.0, 1.0)
		sparkle.scale = Vector2.ONE * (0.8 if i == 0 else 0.55)
		root.add_child(sparkle)
	return root


func _on_body_entered(body: Node) -> void:
	if _triggered or _spawning or body is not Player:
		return
	_triggered = true
	EventBus.enemy_encountered.emit(self)
	queue_free()
