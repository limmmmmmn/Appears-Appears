class_name HUD
extends CanvasLayer

## Field HUD:
##   • Top bar:   field loop status (left) | "Gold N" (right)
##   • Bottom bar: a row of party member boxes — portrait + name on the left
##                 column, HP bar / EXP bar / equipment slots on the right.
##
## Pure presentation node. State comes from GameState, change notifications
## come through EventBus.

const MEMBER_BOX_SCENE: PackedScene = preload("res://scenes/ui/party_member_box.tscn")
const EQUIP_SLOT_SCENE: PackedScene = preload("res://scenes/ui/equip_slot.tscn")
const LEVEL_UP_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_panel.tscn")
const LEVEL_UP_SKILL_BY_CHARACTER_ID: Dictionary = {
	&"hero": preload("res://data/modifiers/prototype/heavy_strike.tres"),
	&"mage": preload("res://data/modifiers/prototype/fireburst.tres"),
	&"priest": preload("res://data/modifiers/prototype/battle_prayer.tres"),
	&"thief": preload("res://data/modifiers/prototype/pilfer.tres"),
}
const LEVEL_UP_STAT_CARD_KINDS: Array[String] = ["blade", "vigor", "step"]
const INVENTORY_SLOT_COUNT: int = 12
const TIMER_NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const TIMER_URGENT_COLOR: Color = Color(1.0, 0.16, 0.10, 1.0)
const TIMER_URGENT_PULSE_COLOR: Color = Color(1.0, 0.82, 0.24, 1.0)

@onready var _field_label: Label = %FieldLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _debug_gold_button: Button = %DebugGoldButton
@onready var _debug_finish_button: Button = %DebugFinishButton
@onready var _member_row: HBoxContainer = %MemberRow
@onready var _inventory_grid: GridContainer = %InventoryGrid

## Live member box references, parallel to GameState.party. Rebuilt from
## scratch on party_changed so we never have stale indices when a recruit
## or wipe shifts the party array.
var _member_boxes: Array[PartyMemberBox] = []
var _inventory_slots: Array[EquipSlot] = []
var _level_up_panel: LevelUpPanel
var _level_up_ui_enabled: bool = false
var _queued_level_up_members: Array[int] = []
var _level_up_pause_active: bool = false
var _timer_urgent: bool = false
var _timer_pulse_time: float = 0.0


func _ready() -> void:
	EventBus.party_changed.connect(_rebuild_member_boxes)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_xp_changed.connect(_on_party_member_xp_changed)
	EventBus.party_member_leveled_up.connect(_on_party_member_leveled_up)
	EventBus.party_equipment_changed.connect(_on_party_equipment_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.field_loop_started.connect(_on_field_loop_started)
	EventBus.field_loop_timer_changed.connect(_on_field_loop_timer_changed)
	_debug_gold_button.pressed.connect(_on_debug_gold_button_pressed)
	_debug_finish_button.pressed.connect(_on_debug_finish_button_pressed)
	_refresh_gold()
	_refresh_field_label()
	_build_inventory_slots()
	_rebuild_member_boxes()
	_refresh_inventory()


func _process(delta: float) -> void:
	if not _timer_urgent:
		return
	_timer_pulse_time += delta
	var pulse: float = (sin(_timer_pulse_time * 12.0) + 1.0) * 0.5
	_countdown_label.modulate = TIMER_URGENT_COLOR.lerp(TIMER_URGENT_PULSE_COLOR, pulse)


# ─── Bottom row ───────────────────────────────────────────────────────
func _rebuild_member_boxes() -> void:
	for box in _member_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_member_boxes.clear()
	for i in GameState.party_size():
		# Layout flags are authored on the box scene root, so each member
		# keeps its natural size and stays pinned to the bottom row.
		var box: PartyMemberBox = MEMBER_BOX_SCENE.instantiate()
		_member_row.add_child(box)
		box.setup(i, GameState.party[i])
		box.level_up_mark_pressed.connect(_on_level_up_mark_pressed)
		box.set_level_up_mark_visible(_level_up_ui_enabled)
		_member_boxes.append(box)


func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_hp(new_hp, max_hp)


func _on_party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var ratio: float = 1.0 if level >= GameState.MAX_CHARACTER_LEVEL else clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	_member_boxes[index].set_exp_ratio(ratio)
	_member_boxes[index].set_level(level)


## Persistent "+" badge over the leveled-up member's portrait. The box owns
## the layout / dedupe; we just route the signal to the right slot.
func _on_party_member_leveled_up(index: int, _new_level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_refresh_member_box(index)


func _on_level_up_mark_pressed(index: int) -> void:
	if not _level_up_ui_enabled:
		return
	if index < 0 or index >= GameState.party_size():
		return
	_queue_level_up_choice(index)


func _queue_level_up_choice(index: int) -> void:
	_queued_level_up_members.append(index)
	_open_next_level_up_choice()


func _open_next_level_up_choice() -> void:
	if not _level_up_ui_enabled or is_instance_valid(_level_up_panel):
		return
	while not _queued_level_up_members.is_empty():
		var index: int = _queued_level_up_members.pop_front()
		if index < 0 or index >= GameState.party_size():
			continue
		var offers: Array[ModifierData] = _level_up_offers_for_member(index)
		if offers.is_empty():
			_clear_level_up_mark(index)
			continue
		_open_level_up_panel(index, offers)
		return


func _open_level_up_panel(index: int, offers: Array[ModifierData]) -> void:
	if offers.is_empty():
		return
	if is_instance_valid(_level_up_panel):
		_level_up_panel.queue_free()
	var member_name: String = GameState.party[index].display_name
	_level_up_panel = LEVEL_UP_PANEL_SCENE.instantiate()
	add_child(_level_up_panel)
	_level_up_panel.setup(index, member_name, offers)
	_level_up_panel.modifier_chosen.connect(_on_level_up_modifier_chosen)
	_level_up_pause_active = true
	get_tree().paused = true


func _on_level_up_modifier_chosen(index: int, mod: ModifierData) -> void:
	var accepted: bool = false
	if index < 0 or index >= GameState.party_size():
		_finish_level_up_choice(index, accepted)
		return
	if _modifier_matches_member(mod, GameState.party[index].id) and GameState.can_add_modifier(mod):
		GameState.add_modifier(mod)
		EventBus.modifier_purchased.emit(mod)
		_refresh_member_box(index)
		accepted = true
	_finish_level_up_choice(index, accepted)


func _finish_level_up_choice(index: int, accepted: bool) -> void:
	if accepted:
		_clear_level_up_mark(index)
	_level_up_panel = null
	if _queued_level_up_members.is_empty():
		_level_up_pause_active = false
		get_tree().paused = false
	else:
		call_deferred("_open_next_level_up_choice")


func _clear_level_up_mark(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].clear_level_up_mark()


func _level_up_offers_for_member(index: int) -> Array[ModifierData]:
	var offers: Array[ModifierData] = []
	if index < 0 or index >= GameState.party_size():
		return offers
	var member_id: StringName = GameState.party[index].id
	var skill: ModifierData = LEVEL_UP_SKILL_BY_CHARACTER_ID.get(member_id, null)
	if skill and GameState.can_add_modifier(skill):
		offers.append(skill)
	for kind: String in LEVEL_UP_STAT_CARD_KINDS:
		var path: String = "res://data/modifiers/archived/%s_%s.tres" % [String(member_id), kind]
		if not ResourceLoader.exists(path):
			continue
		var mod: ModifierData = load(path) as ModifierData
		if mod and GameState.can_add_modifier(mod):
			offers.append(mod)
	return offers


func _modifier_matches_member(mod: ModifierData, member_id: StringName) -> bool:
	return mod != null and mod.required_party_member_id == member_id


func _refresh_member_box(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var box: PartyMemberBox = _member_boxes[index]
	var max_hp: int = GameState.effective_max_hp(index)
	box.set_hp(GameState.party_hp[index], max_hp)
	box.set_exp_ratio(GameState.party_xp_ratio(index))
	box.set_level(GameState.party_level(index))


func set_level_up_ui_enabled(is_enabled: bool) -> void:
	_level_up_ui_enabled = false
	for box in _member_boxes:
		if is_instance_valid(box):
			box.set_level_up_mark_visible(false)
	if is_instance_valid(_level_up_panel):
		_level_up_panel.queue_free()
		_level_up_panel = null
		_queued_level_up_members.clear()
		if _level_up_pause_active:
			_level_up_pause_active = false
			get_tree().paused = false


func _on_party_equipment_changed(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_equipment(GameState.equipment_for_member(index))


func _on_inventory_changed() -> void:
	_refresh_inventory()


func _build_inventory_slots() -> void:
	for child in _inventory_grid.get_children():
		child.queue_free()
	_inventory_slots.clear()
	for i in INVENTORY_SLOT_COUNT:
		var slot: EquipSlot = EQUIP_SLOT_SCENE.instantiate()
		slot.custom_minimum_size = Vector2(14, 14)
		_inventory_grid.add_child(slot)
		slot.set_empty_label("Inventory %d" % (i + 1))
		_inventory_slots.append(slot)


func _refresh_inventory() -> void:
	var items: Array = GameState.inventory_items()
	for i in _inventory_slots.size():
		_inventory_slots[i].set_item(items[i] if i < items.size() else null)


# ─── Top bar ──────────────────────────────────────────────────────────
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold()


func _on_field_loop_started(_loop_num: int) -> void:
	_refresh_field_label()


func _on_field_loop_timer_changed(remaining_seconds: int) -> void:
	if remaining_seconds < 0:
		_countdown_label.text = ""
		_set_timer_urgent(false)
		return
	_countdown_label.text = str(maxi(0, remaining_seconds))
	_set_timer_urgent(remaining_seconds > 0 and remaining_seconds <= 3)


func _refresh_gold() -> void:
	_gold_label.text = "Gold %d" % GameState.gold


func _on_debug_gold_button_pressed() -> void:
	GameState.add_gold(1000)


func _on_debug_finish_button_pressed() -> void:
	EventBus.field_loop_finish_requested.emit()


func _refresh_field_label() -> void:
	_field_label.text = "Field %d" % maxi(1, GameState.field_loop_count)


func _set_timer_urgent(is_urgent: bool) -> void:
	if _timer_urgent == is_urgent:
		return
	_timer_urgent = is_urgent
	_timer_pulse_time = 0.0
	if not is_urgent:
		_countdown_label.modulate = TIMER_NORMAL_COLOR
