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

const LEVEL_UP_MARK_SCENE: PackedScene = preload("res://scenes/ui/level_up_mark.tscn")
## Reused name so a flurry of level-ups doesn't stack visible badges on the
## same portrait — one persistent "+" until the player clicks it.
const LEVEL_UP_MARK_NODE_NAME: StringName = &"LevelUpMark"
const LEVEL_UP_MARK_SIZE: Vector2 = Vector2(20, 20)
const LEVEL_UP_MARK_Y: float = -18.0

signal level_up_mark_pressed(index: int)

@onready var _portrait: CharacterPortrait = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _hp_bar: StatBar = %HPBar
@onready var _exp_bar: StatBar = %ExpBar
@onready var _equip_row: HBoxContainer = %EquipRow

var party_index: int = -1
var character: CharacterData
var _pending_setup: bool = false


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


## Spawn (or surface the existing) persistent level-up badge over the
## portrait. Returns the mark so callers can connect `dismissed` for
## follow-up UI (e.g. opening a stat-allocation panel) without this widget
## needing to know about that flow.
func show_level_up_mark() -> LevelUpMark:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		_position_level_up_mark(existing as LevelUpMark)
		return existing as LevelUpMark
	var mark: LevelUpMark = LEVEL_UP_MARK_SCENE.instantiate()
	mark.name = LEVEL_UP_MARK_NODE_NAME
	mark.mode = LevelUpMark.Mode.PERSISTENT
	_position_level_up_mark(mark)
	_portrait.add_child(mark)
	mark.dismissed.connect(_on_level_up_mark_dismissed)
	call_deferred("_position_level_up_mark", mark)
	return mark


func set_level_up_mark_visible(is_visible: bool) -> void:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		existing.visible = is_visible


func clear_level_up_mark() -> void:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		existing.queue_free()


# ─── Internal ─────────────────────────────────────────────────────────
func _on_level_up_mark_dismissed() -> void:
	level_up_mark_pressed.emit(party_index)


func _position_level_up_mark(mark: LevelUpMark) -> void:
	if not is_instance_valid(mark):
		return
	mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mark.custom_minimum_size = LEVEL_UP_MARK_SIZE
	mark.size = LEVEL_UP_MARK_SIZE
	mark.position = Vector2((_portrait.size.x - LEVEL_UP_MARK_SIZE.x) * 0.5, LEVEL_UP_MARK_Y)
	mark.z_index = 20


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
