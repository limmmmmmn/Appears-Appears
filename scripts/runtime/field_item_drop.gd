class_name FieldItemDrop
extends Area2D

## A dropped pickup on the field. Gold and equipment stay visible, then magnet
## into the player when close enough.

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")
const GOLD_TEXTURE: Texture2D = preload("res://assets/sprites/icons/gold.png")
const GOLD_DROP_HEIGHT_MIN: float = 14.0
const GOLD_DROP_HEIGHT_MAX: float = 24.0
const GOLD_DROP_SIDE_RANGE: float = 8.0
const GOLD_DROP_DURATION: float = 0.28
const GOLD_LAND_SETTLE_DURATION: float = 0.14
const DROP_MAGNET_RANGE: float = 42.0
const DROP_MAGNET_SPEED: float = 360.0
const DROP_MAGNET_DURATION_MIN: float = 0.18
const DROP_MAGNET_DURATION_MAX: float = 0.46
const DROP_MAGNET_ARC_HEIGHT: float = 12.0
const DROP_MAGNET_SIDE_SWAY: float = 5.0
const DROP_SHADOW_ALPHA: float = 0.28

@export var item: ItemData
@export var gold_amount: int = 0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _tooltip_area: Control = $TooltipArea

var _collected: bool = false
var _base_y: float = 0.0
var _bob_time: float = 0.0
var _tween: Tween
var _ready_for_magnet: bool = false
var _magnet_active: bool = false
var _magnet_elapsed: float = 0.0
var _magnet_duration: float = 0.0
var _magnet_start: Vector2 = Vector2.ZERO
var _magnet_phase: float = 0.0
var _magnet_target: Node2D
var _drop_shadow: Polygon2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_collision_shape.scale = Vector2.ONE * GameState.pickup_range_multiplier()
	_apply_item()
	_base_y = position.y


func setup(drop_item: ItemData) -> void:
	item = drop_item
	gold_amount = 0
	if is_inside_tree():
		_apply_item()


func setup_gold_drop(amount: int) -> void:
	item = null
	gold_amount = maxi(1, amount)
	if is_inside_tree():
		_apply_item()


func reveal_with_pop() -> void:
	_set_pickup_collision_enabled(false)
	scale = Vector2.ONE
	if gold_amount > 0:
		_play_gold_drop_motion()
		return
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_sprite.scale = Vector2(0.82, 0.82)
	_sprite.position = Vector2(0.0, -5.0)
	_set_drop_shadow_alpha(0.0)
	_set_drop_shadow_scale(0.72)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.10)
	_tween.parallel().tween_property(_sprite, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_sprite, "position", Vector2.ZERO, 0.18)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(_set_drop_shadow_alpha, 0.0, DROP_SHADOW_ALPHA, 0.18)
	_tween.parallel().tween_method(_set_drop_shadow_scale, 0.72, 1.0, 0.18)
	_tween.tween_callback(_on_reveal_finished)


func _process(delta: float) -> void:
	if _magnet_active:
		_update_drop_magnet(delta)
		return
	if _ready_for_magnet:
		_bob_time += delta
		position.y = _base_y + sin(_bob_time * 5.0) * 1.5
		_try_begin_drop_magnet()
		return
	if _collected:
		return
	_bob_time += delta
	position.y = _base_y + sin(_bob_time * 5.0) * 1.5


func _apply_item() -> void:
	if _sprite == null:
		return
	if gold_amount > 0:
		_sprite.texture = GOLD_TEXTURE
		_ensure_drop_shadow()
	elif item and item.icon:
		_sprite.texture = item.icon
		_ensure_drop_shadow()
		_set_drop_shadow_alpha(DROP_SHADOW_ALPHA)
		_set_drop_shadow_scale(1.0)
	_refresh_tooltip()


func _enable_pickup() -> void:
	_set_pickup_collision_enabled(true)


func _on_reveal_finished() -> void:
	_finish_drop_motion()


func _on_body_entered(body: Node) -> void:
	if _collected or body is not Player:
		return
	_collected = true
	call_deferred("_finish_collect")


func _finish_collect() -> void:
	if gold_amount > 0:
		_collect_gold()
		return
	var equipped: bool = GameState.can_equip_item(item)
	if not GameState.collect_item(item):
		_collected = false
		_set_pickup_collision_enabled(true)
		return
	_spawn_pickup_popup(equipped)
	_play_collect_animation()


func _collect_gold() -> void:
	GameState.add_gold(gold_amount)
	_spawn_gold_popup()
	_play_collect_animation()


func _play_gold_drop_motion() -> void:
	_collected = true
	_magnet_active = false
	_ensure_drop_shadow()
	if _tween and _tween.is_valid():
		_tween.kill()
	var landed_position: Vector2 = position
	position = landed_position + Vector2(
		randf_range(-GOLD_DROP_SIDE_RANGE, GOLD_DROP_SIDE_RANGE),
		-randf_range(GOLD_DROP_HEIGHT_MIN, GOLD_DROP_HEIGHT_MAX)
	)
	rotation = randf_range(-0.12, 0.12)
	scale = Vector2.ONE
	_sprite.scale = Vector2.ONE
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_set_drop_shadow_alpha(0.0)
	_set_drop_shadow_scale(0.55)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position", landed_position, GOLD_DROP_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 1.0, 0.08)
	_tween.tween_property(self, "rotation", randf_range(-0.08, 0.08), GOLD_DROP_DURATION)
	if _drop_shadow:
		_tween.tween_method(_set_drop_shadow_alpha, 0.0, DROP_SHADOW_ALPHA, GOLD_DROP_DURATION)
		_tween.tween_method(_set_drop_shadow_scale, 0.55, 1.0, GOLD_DROP_DURATION)
	_tween.chain().tween_property(_sprite, "scale", Vector2(1.0, 0.88), GOLD_LAND_SETTLE_DURATION * 0.45)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_sprite, "scale", Vector2.ONE, GOLD_LAND_SETTLE_DURATION * 0.55)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish_drop_motion)


func _finish_drop_motion() -> void:
	_collected = false
	_ready_for_magnet = true
	_base_y = position.y
	_bob_time = randf() * TAU


func _try_begin_drop_magnet() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var range: float = DROP_MAGNET_RANGE * GameState.pickup_range_multiplier()
	if global_position.distance_to(player.global_position) <= range:
		_begin_drop_magnet(player)


func _begin_drop_magnet(target: Node2D) -> void:
	if gold_amount <= 0 and item == null:
		return
	_collected = true
	_ready_for_magnet = false
	_set_pickup_collision_enabled(false)
	_magnet_target = target
	_magnet_active = true
	_magnet_elapsed = 0.0
	_magnet_start = global_position
	_magnet_phase = randf() * TAU
	var distance: float = global_position.distance_to(target.global_position)
	_magnet_duration = clampf(distance / DROP_MAGNET_SPEED, DROP_MAGNET_DURATION_MIN, DROP_MAGNET_DURATION_MAX)
	z_index = 80


func _update_drop_magnet(delta: float) -> void:
	if not is_instance_valid(_magnet_target):
		queue_free()
		return
	_magnet_elapsed += delta
	var raw_t: float = clampf(_magnet_elapsed / _magnet_duration, 0.0, 1.0)
	var eased_t: float = pow(raw_t, 1.35)
	var target_pos: Vector2 = _magnet_target.global_position + Vector2(0, -8)
	var arc: Vector2 = Vector2(0, -sin(raw_t * PI) * DROP_MAGNET_ARC_HEIGHT)
	var travel: Vector2 = target_pos - _magnet_start
	var perp: Vector2 = Vector2(-travel.y, travel.x).normalized() if travel.length() > 0.01 else Vector2.RIGHT
	var side: Vector2 = perp * sin(raw_t * PI) * DROP_MAGNET_SIDE_SWAY * sin(_magnet_phase)
	global_position = _magnet_start.lerp(target_pos, eased_t) + arc + side
	rotation = sin(raw_t * PI * 1.4 + _magnet_phase) * 0.16
	scale = Vector2.ONE * lerpf(1.0, 0.42, eased_t)
	modulate.a = lerpf(1.0, 0.18, maxf(0.0, raw_t - 0.78) / 0.22)
	_set_drop_shadow_alpha(lerpf(DROP_SHADOW_ALPHA, 0.0, raw_t))
	_set_drop_shadow_scale(lerpf(1.0, 0.25, raw_t))
	if raw_t >= 1.0:
		_finish_magnet_collect()


func _finish_magnet_collect() -> void:
	if gold_amount > 0:
		GameState.add_gold(gold_amount)
		_spawn_gold_popup()
		queue_free()
		return
	var equipped: bool = GameState.can_equip_item(item)
	if GameState.collect_item(item):
		_spawn_pickup_popup(equipped)
		queue_free()
		return
	_collected = false
	_ready_for_magnet = true
	_magnet_active = false
	modulate.a = 1.0
	scale = Vector2.ONE


func _ensure_drop_shadow() -> void:
	if _drop_shadow:
		return
	_drop_shadow = Polygon2D.new()
	_drop_shadow.name = "DropShadow"
	_drop_shadow.z_index = -1
	_drop_shadow.position = Vector2(3, 5)
	_drop_shadow.polygon = PackedVector2Array([
		Vector2(-6, 0),
		Vector2(-4, -2),
		Vector2(0, -3),
		Vector2(4, -2),
		Vector2(6, 0),
		Vector2(4, 2),
		Vector2(0, 3),
		Vector2(-4, 2),
	])
	_drop_shadow.color = Color(0, 0, 0, 0.0)
	add_child(_drop_shadow)


func _set_drop_shadow_alpha(alpha: float) -> void:
	if _drop_shadow == null:
		return
	_drop_shadow.visible = alpha > 0.0
	_drop_shadow.color = Color(0, 0, 0, alpha)


func _set_drop_shadow_scale(value: float) -> void:
	if _drop_shadow:
		_drop_shadow.scale = Vector2(value, value)


func _set_pickup_collision_enabled(enabled: bool) -> void:
	monitoring = enabled
	monitorable = enabled
	_collision_shape.disabled = not enabled


func _play_collect_animation() -> void:
	_set_pickup_collision_enabled(false)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_property(_sprite, "scale", Vector2(1.2, 0.62), 0.18)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	_tween.tween_method(_set_drop_shadow_alpha, DROP_SHADOW_ALPHA, 0.0, 0.18)
	_tween.chain().tween_callback(queue_free)


func _spawn_gold_popup() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	parent_node.add_child(num)
	num.global_position = global_position + Vector2(0, -12)
	num.z_index = 50
	num.setup_gold(gold_amount)


func _spawn_pickup_popup(equipped: bool) -> void:
	var parent_node: Node = get_parent()
	if parent_node == null or item == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	parent_node.add_child(num)
	num.global_position = global_position + Vector2(0, -12)
	num.z_index = 50
	var prefix: String = "" if equipped else "Bag: "
	var color: Color = Color(0.75, 1.0, 0.55, 1.0) if equipped else Color(1.0, 0.86, 0.42, 1.0)
	num.setup_text("%s%s" % [prefix, item.display_name], color)


func _refresh_tooltip() -> void:
	if _tooltip_area == null:
		return
	if gold_amount > 0:
		_tooltip_area.tooltip_text = "Gold\nAmount %dG" % gold_amount
	else:
		_tooltip_area.tooltip_text = GameState.item_entry_tooltip({"item": item, "level": 1})
