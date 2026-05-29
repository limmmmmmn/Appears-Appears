class_name PartyMemberBox
extends Panel

## One party member panel for HUD. A pure composition of sub-scenes:
##   • CharacterPortrait   — head-crop badge driven by CharacterData
##   • StatBar × 2         — HP and EXP bars (color/alignment set on instance)
##   • EquipSlot × 6       — equipment slot placeholders (authored in scene)
##
## Stateless beyond the live values pushed in via setters. HUD (or whoever
## owns this widget) is responsible for wiring EventBus signals → setters.
## This widget never reaches into GameState on its own — except for the
## one-shot read in `_apply()` to seed initial values when a character is
## injected. That keeps it portable to non-HUD contexts (preview screens,
## etc.) where GameState's per-index data may not be relevant.

const BOX_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

@onready var _portrait: CharacterPortrait = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _hp_bar: StatBar = %HPBar
@onready var _exp_bar: StatBar = %ExpBar
@onready var _equip_row: HBoxContainer = %EquipRow

var party_index: int = -1
var character: CharacterData
var _pending_setup: bool = false
## Lazily-created "쓰러짐" overlay tag, shown while this member is downed.
var _downed_tag: Label
## Lazily-created armor badge ("방N"), reflecting the party's equipped armor.
var _armor_badge: Label


## Inject the slot's identity. Safe to call before the node is in the tree.
func setup(index: int, data: CharacterData) -> void:
	party_index = index
	character = data
	if is_inside_tree():
		_apply()
	else:
		_pending_setup = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	if _pending_setup or character != null:
		_pending_setup = false
		_apply()


# ─── Live setters (called by the HUD root) ────────────────────────────
func set_hp(hp: int, max_hp: int) -> void:
	_hp_bar.set_label("%d/%d" % [hp, max_hp])
	_hp_bar.set_ratio(_safe_ratio(hp, max_hp))
	_refresh_tooltip()


## Downed state: dim the whole box and overlay a "쓰러짐" tag. The HP bar keeps
## filling (the "쫘라락" recovery) underneath until the member auto-stands.
func set_downed(is_down: bool) -> void:
	modulate = Color(0.55, 0.55, 0.62, 1.0) if is_down else Color(1, 1, 1, 1)
	if _downed_tag == null:
		_downed_tag = Label.new()
		_downed_tag.text = "쓰러짐"
		_downed_tag.add_theme_font_override("font", BOX_FONT)
		_downed_tag.add_theme_font_size_override("font_size", 9)
		_downed_tag.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45, 1.0))
		_downed_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_downed_tag.add_theme_constant_override("shadow_offset_x", 1)
		_downed_tag.add_theme_constant_override("shadow_offset_y", 1)
		_downed_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_downed_tag.set_anchors_preset(Control.PRESET_CENTER)
		_downed_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_downed_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_downed_tag)
	_downed_tag.visible = is_down


## Equipped armor reflection (top-right "방N" badge). Armor is a party-wide
## survival axis, so every member shows it. level 1 = no armor → hidden.
func set_armor(level: int, armor_name: String) -> void:
	if _armor_badge == null:
		_armor_badge = Label.new()
		_armor_badge.add_theme_font_override("font", BOX_FONT)
		_armor_badge.add_theme_font_size_override("font_size", 8)
		_armor_badge.add_theme_color_override("font_color", Color(0.66, 0.86, 0.9, 1.0))
		_armor_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_armor_badge.add_theme_constant_override("shadow_offset_x", 1)
		_armor_badge.add_theme_constant_override("shadow_offset_y", 1)
		_armor_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_armor_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_armor_badge.position = Vector2(-22.0, 1.0)
		add_child(_armor_badge)
	_armor_badge.text = "방%d" % level
	_armor_badge.tooltip_text = armor_name
	_armor_badge.visible = level > 1


func set_exp_ratio(ratio: float) -> void:
	_exp_bar.set_ratio(clampf(ratio, 0.0, 1.0))


func set_level(level: int) -> void:
	_exp_bar.set_label("LV %d" % maxi(level, 1))
	_refresh_tooltip()


## Paint a specific slot (placeholder until ItemData lands). Indices outside
## the slot count are ignored so callers don't have to range-check.
func set_equip_slot_color(slot_index: int, color: Color) -> void:
	var slot: EquipSlot = _equip_slot_at(slot_index)
	if slot:
		slot.set_paint(color)


func set_equipment(items: Array) -> void:
	for i in _equip_row.get_child_count():
		var slot: EquipSlot = _equip_slot_at(i)
		if slot:
			slot.set_empty_label(_slot_label(i))
			slot.set_item(items[i] if i < items.size() else null)
	_refresh_tooltip()


## Reset every equipment slot to the empty state.
func clear_equip_slots() -> void:
	for child in _equip_row.get_children():
		if child is EquipSlot:
			(child as EquipSlot).clear()


# ─── Internal ─────────────────────────────────────────────────────────
func _apply() -> void:
	if character == null:
		_name_label.text = "—"
		_portrait.clear()
		set_hp(0, 1)
		set_exp_ratio(0.0)
		set_level(1)
		tooltip_text = ""
		return
	_name_label.text = character.display_name
	_portrait.set_character(character)
	var max_hp: int = _resolve_max_hp()
	var hp: int = _resolve_current_hp(max_hp)
	set_hp(hp, max_hp)
	set_exp_ratio(GameState.party_xp_ratio(party_index))
	set_level(GameState.party_level(party_index))
	set_armor(GameState.armor_level, GameState.current_armor_name())
	set_equipment(GameState.equipment_for_member(party_index))
	_refresh_tooltip()


func _resolve_max_hp() -> int:
	if party_index < 0 or party_index >= GameState.party_size():
		return character.max_hp
	return GameState.effective_max_hp(party_index)


func _resolve_current_hp(max_hp: int) -> int:
	if party_index < 0 or party_index >= GameState.party_hp.size():
		return max_hp
	return GameState.party_hp[party_index]


func _equip_slot_at(slot_index: int) -> EquipSlot:
	if slot_index < 0 or slot_index >= _equip_row.get_child_count():
		return null
	return _equip_row.get_child(slot_index) as EquipSlot


func _safe_ratio(value: int, max_value: int) -> float:
	if max_value <= 0:
		return 0.0
	return clampf(float(value) / float(max_value), 0.0, 1.0)


func _refresh_tooltip() -> void:
	tooltip_text = GameState.party_member_stat_tooltip(party_index)


func _slot_label(slot_index: int) -> String:
	if slot_index == GameState.EQUIPMENT_ACCESSORY_SLOT_B:
		return "Accessory B"
	if slot_index == GameState.EQUIPMENT_ACCESSORY_SLOT_A:
		return "Accessory A"
	return GameState.equipment_slot_name(slot_index)
