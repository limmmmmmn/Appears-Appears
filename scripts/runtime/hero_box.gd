class_name HeroBox
extends Panel

## Compact town readout for one party member. Pure display: no input.

const ATTACK_COLOR: Color = Color(0.85, 0.18, 0.16, 1.0)
const DEFENSE_COLOR: Color = Color(0.55, 0.55, 0.58, 1.0)
const SUPPORT_COLOR: Color = Color(0.22, 0.68, 0.30, 1.0)
const MAGIC_COLOR: Color = Color(0.22, 0.42, 0.88, 1.0)
const SPECIAL_COLOR: Color = Color(0.95, 0.48, 0.12, 1.0)

@export var portrait_size: Vector2 = Vector2(36, 36)

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HpLabel
@onready var _atk_label: Label = %AtkLabel
@onready var _upgrades: HFlowContainer = %Upgrades
@onready var _popup_label: Label = %PopupLabel

var member_index: int = -1
var member_id: StringName = &""
var _flash_tween: Tween
var _popup_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.custom_minimum_size = portrait_size
	_popup_label.visible = false


func setup(index: int) -> void:
	member_index = index
	refresh()


func refresh() -> void:
	if member_index < 0 or member_index >= GameState.party_size():
		return
	var data: CharacterData = GameState.party[member_index]
	member_id = data.id
	_name_label.text = data.display_name
	_hp_label.text = "HP %d/%d  MP %d/%d" % [
		GameState.party_hp[member_index],
		GameState.effective_max_hp(member_index),
		GameState.party_mp[member_index],
		GameState.effective_max_mp(member_index),
	]
	_atk_label.text = "ATK %d" % GameState.effective_attack(member_index)
	_portrait.texture = _build_portrait_texture(data)
	_rebuild_upgrade_labels()


func play_modifier_feedback(mod: ModifierData, popup_text: String) -> void:
	refresh()
	_play_flash()
	if not popup_text.is_empty():
		_play_popup(popup_text)


func play_join_feedback() -> void:
	refresh()
	_play_flash()
	_play_popup("Joined")


func _play_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	self_modulate = Color(1.0, 0.95, 0.55, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "self_modulate", Color.WHITE, 0.3)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)


func _play_popup(text: String) -> void:
	if _popup_tween:
		_popup_tween.kill()
	_popup_label.text = text
	_popup_label.visible = true
	_popup_label.modulate = Color(1.0, 0.88, 0.25, 1.0)
	var box_width: float = maxf(size.x, custom_minimum_size.x)
	_popup_label.position = Vector2(box_width - 48.0, 6.0)
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup_label, "position:y", -8.0, 0.8)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 0.0, 0.8)\
		.set_delay(0.2)
	_popup_tween.tween_callback(func() -> void: _popup_label.visible = false)


func _rebuild_upgrade_labels() -> void:
	for child in _upgrades.get_children():
		child.free()
	var shown: Dictionary = {}
	for mod: ModifierData in GameState.active_modifiers:
		if shown.has(mod.id):
			continue
		if not _mod_applies_to_this_member(mod):
			continue
		shown[mod.id] = true
		_add_upgrade_label(_upgrade_label_text(mod), _color_for_modifier(mod))


func _mod_applies_to_this_member(mod: ModifierData) -> bool:
	if mod.required_party_member_id != &"":
		return mod.required_party_member_id == member_id
	return mod.category != ModifierData.Category.COMPANION


func _upgrade_label_text(mod: ModifierData) -> String:
	var level: int = GameState.modifier_level(mod.id)
	if mod.max_level > 1 and level > 0:
		return "%s LV.%d" % [mod.display_name, level]
	return mod.display_name


func _add_upgrade_label(text: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.05, 0.04, 0.03, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_upgrades.add_child(panel)
	panel.modulate.a = 0.0
	panel.scale = Vector2.ONE * 0.86
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)


func _color_for_modifier(mod: ModifierData) -> Color:
	if mod.required_party_member_id == &"mage" or mod.effect_data.has("mage_splash_extra_targets") or mod.effect_data.has("mage_firewall_damage_flat"):
		return MAGIC_COLOR
	if mod.effect_data.has("hp_flat") or mod.effect_data.has("priest_heal_flat") or mod.effect_data.has("window_collision_heal_flat"):
		return SUPPORT_COLOR
	if mod.effect_data.has("def_flat") or mod.effect_data.has("evade_chance"):
		return DEFENSE_COLOR
	if mod.effect_data.has("atk_flat") or mod.effect_data.has("hero_damage_bonus_mult"):
		return ATTACK_COLOR
	return SPECIAL_COLOR


func _build_portrait_texture(character: CharacterData) -> Texture2D:
	if character.portrait:
		return character.portrait
	if character.sprite_sheet == null:
		return null
	var atlas := AtlasTexture.new()
	var idle_col: int = clampi(1, 0, maxi(0, character.frames_per_direction - 1))
	atlas.atlas = character.sprite_sheet
	atlas.region = Rect2(idle_col * character.frame_size.x, 0, character.frame_size.x, character.frame_size.y)
	atlas.filter_clip = true
	return atlas
