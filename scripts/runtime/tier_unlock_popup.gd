class_name TierUnlockPopup
extends PanelContainer

## Big centered "○○ 해금!" popup with the enemy sprite, fired the moment a new tile
## appears. Split out of the HUD into its own scene. Hidden by default; the contents are
## built in code, so the scene is just this root + the script.

const HUD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
## Design viewport width — center on the TRUE viewport center, ignoring side panels.
const VIEWPORT_DESIGN_WIDTH: float = 640.0

var _sprite: TextureRect
var _label: Label
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.tier_available.connect(_on_tier_unlocked)


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.35, 1.0)  # gold frame
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_sprite = TextureRect.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.custom_minimum_size = Vector2(48, 48)
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_sprite)
	_label = Label.new()
	_label.add_theme_font_override("font", HUD_FONT)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_label)


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
