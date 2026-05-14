class_name FieldItemDrop
extends Area2D

## A dropped equipment pickup on the field.

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

@export var item: ItemData

@onready var _shadow: Polygon2D = $Shadow
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _collected: bool = false
var _base_y: float = 0.0
var _shadow_base_y: float = 0.0
var _bob_time: float = 0.0
var _tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_item()
	_base_y = position.y
	_shadow_base_y = _shadow.position.y


func setup(drop_item: ItemData) -> void:
	item = drop_item
	if is_inside_tree():
		_apply_item()


func reveal_with_pop() -> void:
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
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
	var bob: float = sin(_bob_time * 5.0) * 1.5
	position.y = _base_y + bob
	_shadow.position.y = _shadow_base_y - bob


func _apply_item() -> void:
	if item and item.icon and _sprite:
		_sprite.texture = item.icon


func _enable_pickup() -> void:
	monitoring = true
	monitorable = true
	_collision_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if _collected or body is not Player:
		return
	var equipped: bool = GameState.can_equip_item(item)
	if not GameState.collect_item(item):
		return
	_collected = true
	_spawn_pickup_popup(equipped)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_collision_shape.set_deferred("disabled", true)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_property(self, "scale", Vector2(1.4, 0.6), 0.18)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)


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
