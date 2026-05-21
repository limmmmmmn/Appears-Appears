class_name FieldTreasureChest
extends Area2D

## One-shot field reward. Appears after enough enemies are defeated, then
## grants a chunky gold bonus when the leader touches it.

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

@export var gold_amount: int = 50

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _collected: bool = false
var _tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_collision_shape.scale = Vector2.ONE * GameState.pickup_range_multiplier()


func reveal_with_pop() -> void:
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	scale = Vector2(0.25, 0.25)
	modulate = Color(1.0, 0.9, 0.45, 0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.parallel().tween_property(self, "scale", Vector2(1.18, 0.84), 0.16)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2(0.92, 1.08), 0.12)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_enable_pickup)


func _enable_pickup() -> void:
	monitoring = true
	monitorable = true
	_collision_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if _collected or body is not Player:
		return
	_collected = true
	GameState.add_gold(gold_amount)
	_spawn_gold_popup()
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.22)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "scale", Vector2(1.35, 0.65), 0.22)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)


func _spawn_gold_popup() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	parent_node.add_child(num)
	num.global_position = global_position + Vector2(0, -14)
	num.z_index = 50
	num.setup_gold(gold_amount)
