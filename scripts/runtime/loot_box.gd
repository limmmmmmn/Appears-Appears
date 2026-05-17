class_name LootBox
extends Control

signal closed

const BOX_CENTER: Vector2 = Vector2(320.0, 190.0)
const BOX_SIZE: Vector2 = Vector2(420.0, 104.0)
const WALL_THICKNESS: float = 10.0
const ITEM_BODY_SIZE: Vector2 = Vector2(18.0, 18.0)
const DROP_ORIGIN: Vector2 = Vector2(320.0, 66.0)
const SELL_TICK_SECONDS: float = 0.022
const SELL_MAX_TICKS: int = 42

@onready var _box_panel: Panel = %BoxPanel
@onready var _physics_root: Node2D = %PhysicsRoot
@onready var _box_root: Node2D = %BoxRoot
@onready var _sell_button: Button = %SellButton
@onready var _summary_label: Label = %SummaryLabel

var _items: Array[ItemData] = []
var _sell_value: int = 0
var _item_bodies: Array[RigidBody2D] = []
var _selling: bool = false


func setup(items: Array[ItemData], sell_value: int) -> void:
	_items = items.duplicate()
	_sell_value = sell_value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_box_panel.position = BOX_CENTER - BOX_SIZE * 0.5
	_box_panel.size = BOX_SIZE
	_box_root.position = BOX_CENTER
	_summary_label.text = "아이템 %d개  /  +%d G" % [_items.size(), _sell_value]
	_sell_button.text = "전부 팔기  +%d G" % _sell_value
	_sell_button.disabled = true
	_sell_button.pressed.connect(_on_sell_pressed)
	_build_physics_box()
	call_deferred("_drop_items")
	var timer := get_tree().create_timer(0.85, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(_sell_button):
			_sell_button.disabled = false
	)


func _build_physics_box() -> void:
	_add_wall(Vector2(0.0, BOX_SIZE.y * 0.5), Vector2(BOX_SIZE.x, WALL_THICKNESS))
	_add_wall(Vector2(-BOX_SIZE.x * 0.5, 0.0), Vector2(WALL_THICKNESS, BOX_SIZE.y))
	_add_wall(Vector2(BOX_SIZE.x * 0.5, 0.0), Vector2(WALL_THICKNESS, BOX_SIZE.y))


func _add_wall(local_position: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	body.position = local_position
	body.collision_layer = 1
	body.collision_mask = 1
	_box_root.add_child(body)

	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


func _drop_items() -> void:
	for i in _items.size():
		var item: ItemData = _items[i]
		var body := RigidBody2D.new()
		body.name = "LootItem"
		body.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		body.collision_layer = 1
		body.collision_mask = 1
		body.gravity_scale = randf_range(1.15, 1.55)
		body.position = DROP_ORIGIN + Vector2(randf_range(-170.0, 170.0), -float(i) * 10.0)
		body.rotation = randf_range(-0.9, 0.9)
		body.linear_velocity = Vector2(randf_range(-95.0, 95.0), randf_range(-20.0, 35.0))
		body.angular_velocity = randf_range(-8.0, 8.0)
		var mat := PhysicsMaterial.new()
		mat.bounce = 0.38
		mat.friction = 0.78
		body.physics_material_override = mat
		_physics_root.add_child(body)

		var shape := RectangleShape2D.new()
		shape.size = ITEM_BODY_SIZE
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		_add_item_visual(body, item)
		_item_bodies.append(body)


func _add_item_visual(body: RigidBody2D, item: ItemData) -> void:
	if item != null and item.icon != null:
		var sprite := Sprite2D.new()
		sprite.texture = item.icon
		sprite.scale = _icon_scale(item.icon)
		body.add_child(sprite)
		return
	var fallback := ColorRect.new()
	fallback.color = Color(1.0, 0.82, 0.22, 1.0)
	fallback.size = ITEM_BODY_SIZE
	fallback.position = -ITEM_BODY_SIZE * 0.5
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(fallback)


func _icon_scale(texture: Texture2D) -> Vector2:
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ONE
	var longest: float = maxf(texture_size.x, texture_size.y)
	return Vector2.ONE * (20.0 / longest)


func _on_sell_pressed() -> void:
	if _selling:
		return
	var sale_value: int = GameState.sell_inventory_items()
	if sale_value <= 0:
		_finish()
		return
	_selling = true
	_sell_button.disabled = true
	_sell_button.text = "판매중..."
	_vanish_items()
	await _roll_gold_gain(sale_value)
	await get_tree().create_timer(0.32, true).timeout
	_finish()


func _vanish_items() -> void:
	for i in _item_bodies.size():
		var body: RigidBody2D = _item_bodies[i]
		if body == null or not is_instance_valid(body):
			continue
		body.freeze = true
		var target: Vector2 = Vector2(565.0, 18.0) + Vector2(randf_range(-16.0, 16.0), randf_range(-6.0, 8.0))
		var tween := body.create_tween()
		tween.tween_interval(float(i) * 0.025)
		tween.set_parallel(true)
		tween.tween_property(body, "position", target, 0.28)\
			.set_trans(Tween.TRANS_CUBIC)\
			.set_ease(Tween.EASE_IN)
		tween.tween_property(body, "scale", Vector2(0.1, 0.1), 0.24)\
			.set_trans(Tween.TRANS_BACK)\
			.set_ease(Tween.EASE_IN)
		tween.tween_property(body, "modulate:a", 0.0, 0.22)
		tween.set_parallel(false)
		tween.chain().tween_callback(body.queue_free)


func _roll_gold_gain(amount: int) -> void:
	var ticks: int = mini(SELL_MAX_TICKS, maxi(1, amount))
	var base: int = int(floor(float(amount) / float(ticks)))
	var remainder: int = amount - base * ticks
	for i in ticks:
		var gain: int = base + (1 if i < remainder else 0)
		if gain > 0:
			GameState.add_gold(gain)
		await get_tree().create_timer(SELL_TICK_SECONDS, true).timeout


func _finish() -> void:
	closed.emit()
	queue_free()
