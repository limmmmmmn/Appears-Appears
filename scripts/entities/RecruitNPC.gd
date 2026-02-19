extends Node2D
class_name RecruitNPC

@export var sprite_offset: Vector2 = Vector2(0.0, -12.0)
@export var bubble_scene: PackedScene = preload("res://scenes/ui/PartyChatterBubble.tscn")
@export var bubble_offset: Vector2 = Vector2(0.0, -52.0)
@export var bubble_tint: Color = Color(0.96, 0.96, 1.0, 1.0)
@export var bubble_float_amplitude: float = 2.0
@export var bubble_float_speed: float = 2.6
@export var bubble_min_width: float = -1.0
@export var bubble_font_size: int = -1

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var recruit_hero_id: String = ""
var bubble_node: PanelContainer = null
var bubble_text: String = ""
var bubble_float_t: float = 0.0


func _ready() -> void:
	if sprite != null:
		sprite.position = sprite_offset


func setup_recruit(hero_id: String) -> void:
	recruit_hero_id = hero_id
	if sprite == null:
		return
	if SpriteManager != null and SpriteManager.has_method("get_hero_sprite_frames"):
		sprite.sprite_frames = SpriteManager.get_hero_sprite_frames(hero_id)
		sprite.animation = "walk_down"
		sprite.frame = 1
		sprite.stop()


func set_bubble_text(text: String, tint: Color = bubble_tint) -> void:
	bubble_text = text
	bubble_tint = tint
	if text.is_empty():
		if bubble_node != null and is_instance_valid(bubble_node):
			bubble_node.visible = false
		return

	_ensure_bubble()
	if bubble_node == null or not is_instance_valid(bubble_node):
		return
	_apply_bubble_style_defaults()
	bubble_node.visible = true
	if bubble_node.has_method("configure"):
		bubble_node.call("configure", bubble_text, bubble_tint)
	else:
		var label: Label = bubble_node.get_node_or_null("TextLabel") as Label
		if label != null:
			label.text = bubble_text
	call_deferred("_refresh_bubble_position")


func tick_bubble_float(delta: float) -> void:
	if bubble_node == null or not is_instance_valid(bubble_node) or not bubble_node.visible:
		return
	bubble_float_t += delta
	_refresh_bubble_position()


func _ensure_bubble() -> void:
	if bubble_node != null and is_instance_valid(bubble_node):
		return
	var existing_bubble: PanelContainer = get_node_or_null("Bubble") as PanelContainer
	if existing_bubble != null and is_instance_valid(existing_bubble):
		bubble_node = existing_bubble
		_apply_bubble_style_defaults()
		return
	var scene: PackedScene = bubble_scene
	if scene == null:
		scene = load("res://scenes/ui/PartyChatterBubble.tscn")
	if scene == null:
		return
	var node: Node = scene.instantiate()
	var panel: PanelContainer = node as PanelContainer
	if panel == null:
		if node != null and is_instance_valid(node):
			node.queue_free()
		return
	panel.name = "Bubble"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	bubble_node = panel
	_apply_bubble_style_defaults()
	_refresh_bubble_position()


func _refresh_bubble_position() -> void:
	if bubble_node == null or not is_instance_valid(bubble_node):
		return
	if bubble_node.size.x <= 0.0 or bubble_node.size.y <= 0.0:
		bubble_node.size = bubble_node.custom_minimum_size
	var float_y: float = sin(bubble_float_t * bubble_float_speed) * bubble_float_amplitude
	var x: float = -bubble_node.size.x * 0.5 + bubble_offset.x
	var y: float = bubble_offset.y + float_y
	bubble_node.position = Vector2(x, y)


func _apply_bubble_style_defaults() -> void:
	if bubble_node == null or not is_instance_valid(bubble_node):
		return
	bubble_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chatter_bubble: PartyChatterBubble = bubble_node as PartyChatterBubble
	if chatter_bubble != null:
		if bubble_min_width >= 0.0:
			chatter_bubble.min_width = bubble_min_width
		else:
			chatter_bubble.min_width = 0.0
		if bubble_font_size > 0:
			chatter_bubble.font_size = bubble_font_size
		else:
			chatter_bubble.font_size = 11
		return
	var label: Label = bubble_node.get_node_or_null("TextLabel") as Label
	if label != null:
		if bubble_min_width >= 0.0:
			label.custom_minimum_size = Vector2(bubble_min_width, 0.0)
		else:
			label.custom_minimum_size = Vector2.ZERO
		if bubble_font_size > 0:
			label.add_theme_font_size_override("font_size", bubble_font_size)
		else:
			label.add_theme_font_size_override("font_size", 11)
