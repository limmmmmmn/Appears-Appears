class_name TileCardPopup
extends CanvasLayer

## Centered "you got a new tile" card. Shows the tile's sprite, name, and a
## one-liner description, then drops onto the map when dismissed. Used the
## first time the player unlocks a tile this run — subsequent stages just
## place the tile silently (no popup).
##
## Pause behavior: caller is expected to set `get_tree().paused = true` before
## adding this node, so the field freezes underneath; the popup itself runs
## with PROCESS_MODE_WHEN_PAUSED so its tweens still tick.

signal closed

const POP_IN_DURATION: float = 0.22
const POP_OUT_DURATION: float = 0.16
const AUTO_DISMISS_DELAY: float = 3.5

@onready var _card: Panel = %Card
@onready var _title_label: Label = %TitleLabel
@onready var _sprite_rect: TextureRect = %TileSprite
@onready var _desc_label: Label = %DescLabel
@onready var _dim_button: Button = %DimRect

var _closing: bool = false
var _pending_title: String = ""
var _pending_sprite: Texture2D
var _pending_desc: String = ""


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


## Inject card content. Safe to call before the popup is added to the tree.
func setup(title: String, sprite: Texture2D, description: String) -> void:
	_pending_title = title
	_pending_sprite = sprite
	_pending_desc = description
	if is_inside_tree():
		_apply_pending()


func _ready() -> void:
	_dim_button.pressed.connect(_on_dim_pressed)
	_apply_pending()
	_card.scale = Vector2(0.7, 0.7)
	_card.modulate = Color(1, 1, 1, 0)
	_dim_button.modulate = Color(1, 1, 1, 0)
	_animate_in()
	# Auto-dismiss as a safety net so the field never freezes if the player
	# wanders off without clicking.
	get_tree().create_timer(AUTO_DISMISS_DELAY, false, true).timeout.connect(_close_if_open)


func _apply_pending() -> void:
	_title_label.text = _pending_title
	_sprite_rect.texture = _pending_sprite
	_desc_label.text = _pending_desc


func _animate_in() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dim_button, "modulate:a", 1.0, POP_IN_DURATION * 0.6)
	tween.tween_property(_card, "modulate:a", 1.0, POP_IN_DURATION)
	tween.tween_property(_card, "scale", Vector2.ONE, POP_IN_DURATION)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)


func _on_dim_pressed() -> void:
	_close_if_open()


func _close_if_open() -> void:
	if _closing:
		return
	_closing = true
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_card, "scale", Vector2(0.88, 0.88), POP_OUT_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_card, "modulate:a", 0.0, POP_OUT_DURATION)
	tween.tween_property(_dim_button, "modulate:a", 0.0, POP_OUT_DURATION)
	tween.chain().tween_callback(_finish)


func _finish() -> void:
	closed.emit()
	queue_free()
