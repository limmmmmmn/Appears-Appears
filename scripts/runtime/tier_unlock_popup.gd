class_name TierUnlockPopup
extends PanelContainer

## Big centered "○○ 해금!" popup with the enemy sprite, fired the moment a new tile
## appears. Split out of the HUD into its own scene. Hidden by default; the contents are
## authored in the scene so the popup can be designed without touching code.

## Design viewport width — center on the TRUE viewport center, ignoring side panels.
const VIEWPORT_DESIGN_WIDTH: float = 640.0

@onready var _sprite: TextureRect = %Sprite
@onready var _label: Label = %Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	EventBus.tier_available.connect(_on_tier_unlocked)


func _on_tier_unlocked(tier_id: StringName) -> void:
	var tier: Dictionary = Balance.tier_by_id(tier_id)
	_label.text = "%s 해금!" % str(tier.get("name", "?"))
	_sprite.texture = _tier_sprite(tier)
	visible = true
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	await get_tree().process_frame  # let it size to content first
	var center_x: float = VIEWPORT_DESIGN_WIDTH * 0.5
	pivot_offset = size * 0.5
	position = Vector2(center_x, 120.0) - size * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	scale = Vector2(0.6, 0.6)
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(1.4)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func() -> void: visible = false)


func _tier_sprite(tier: Dictionary) -> Texture2D:
	var path: String = str(tier.get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ed := load(path) as EnemyData
	return ed.sprite if ed != null else null
