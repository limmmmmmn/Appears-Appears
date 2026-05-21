class_name FieldItemDrop
extends Area2D

## A dropped equipment pickup on the field.

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")
const GOLD_TEXTURE: Texture2D = preload("res://assets/sprites/icons/gold.png")

@export var item: ItemData
@export var gold_amount: int = 0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _tooltip_area: Control = $TooltipArea

var _collected: bool = false
var _base_y: float = 0.0
var _bob_time: float = 0.0
var _tween: Tween


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
	scale = Vector2(0.4, 0.4)
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.10)
	_tween.parallel().tween_property(self, "scale", Vector2(1.18, 0.82), 0.14)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_enable_pickup)


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_time += delta
	position.y = _base_y + sin(_bob_time * 5.0) * 1.5


func _apply_item() -> void:
	if _sprite == null:
		return
	if gold_amount > 0:
		_sprite.texture = GOLD_TEXTURE
	elif item and item.icon:
		_sprite.texture = item.icon
	_refresh_tooltip()


func _enable_pickup() -> void:
	_set_pickup_collision_enabled(true)


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
	_tween.tween_property(self, "scale", Vector2(1.4, 0.6), 0.18)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
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
