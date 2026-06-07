class_name FieldStructure
extends Node2D

## A field-placed building (structure system). Generic: it builds its own small
## marker from a Balance building dict, so 대장간 / 상점 etc. reuse this as-is.
## No sprite art yet — a stone base + colored roof + short-name label.

const STRUCT_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var building_id: StringName

var _glow: ColorRect
var _roof: ColorRect
var _pulse_tween: Tween


## Inject the building's Balance dict (id / name / short / color). Call before
## or after adding to the tree — the visual is built immediately.
func setup(building: Dictionary) -> void:
	building_id = StringName(building.get("id", &""))
	for child in get_children():
		child.queue_free()
	var accent: Color = building.get("color", Color(0.7, 0.85, 1.0, 1.0))

	# Soft glow behind (animated on pulse).
	_glow = ColorRect.new()
	_glow.color = Color(accent.r, accent.g, accent.b, 0.0)
	_glow.size = Vector2(26, 26)
	_glow.position = Vector2(-13, -16)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	# Clickable hotspot over the structure (it can't be moved — click just opens its
	# action panel). A world-space Control gets the click like the battle windows do.
	var hotspot := Control.new()
	hotspot.size = Vector2(22, 26)
	hotspot.position = Vector2(-11, -20)
	hotspot.mouse_filter = Control.MOUSE_FILTER_STOP
	hotspot.gui_input.connect(_on_hotspot_input)
	add_child(hotspot)

	# If the building supplies a sprite, draw THAT (so the placed thing matches the
	# panel icon exactly) and skip the generic block/label.
	var sprite_path: String = str(building.get("sprite", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		var spr := Sprite2D.new()
		spr.texture = load(sprite_path)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.position = Vector2(0, -8)  # sit just above the ground point
		add_child(spr)
		return

	# Stone base.
	var base := ColorRect.new()
	base.color = Color(0.28, 0.3, 0.34, 1.0)
	base.size = Vector2(16, 14)
	base.position = Vector2(-8, -10)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# Colored roof/accent band.
	_roof = ColorRect.new()
	_roof.color = accent
	_roof.size = Vector2(18, 5)
	_roof.position = Vector2(-9, -13)
	_roof.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roof)

	# Short-name label above.
	var label := Label.new()
	label.text = str(building.get("short", "?"))
	label.add_theme_font_override("font", STRUCT_FONT)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", accent)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-8, -28)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


## Click → open this structure's action panel (ObjectActionPanel) AND show it in the
## right property inspector.
func _on_hotspot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		EventBus.structure_clicked.emit(building_id, global_position)
		EventBus.inspector_target_selected.emit(self)
		get_viewport().set_input_as_handled()


## Right property inspector: objet — header (이름/스프라이트) + 설명 한 줄, ③ 준비 중.
func get_inspector_data() -> Dictionary:
	var info: Dictionary = Balance.tile_by_id(building_id)
	if info.is_empty():
		info = Balance.building_by_id(building_id)
	var sprite: Texture2D = null
	var sprite_path: String = str(info.get("sprite", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		sprite = load(sprite_path)
	return {
		"name": str(info.get("name", building_id)),
		"info": str(info.get("desc", "")),
		"sprite": sprite,
		"actions": [],
	}


## Quick glow + scale pop — used when the building's effect fires (e.g. the
## sanctuary reviving someone) so the player sees it working.
func pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	scale = Vector2.ONE
	_pulse_tween = create_tween()
	if _glow:
		_glow.color = Color(_glow.color.r, _glow.color.g, _glow.color.b, 0.85)
		_pulse_tween.parallel().tween_property(_glow, "color:a", 0.0, 0.5)
	_pulse_tween.parallel().tween_property(self, "scale", Vector2(1.35, 1.35), 0.12) \
		.set_trans(Tween.TRANS_BACK)
	_pulse_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_SINE)
