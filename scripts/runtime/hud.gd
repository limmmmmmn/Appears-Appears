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
const HUD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
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
var _timer_urgent: bool = false
var _timer_pulse_time: float = 0.0
## Measured gold income per second (sampled from total_gold_earned each 1s),
## shown next to the gold total so upgrades read as a rising "+N/s".
var _income_timer: float = 0.0
var _income_marker: int = 0
var _income_per_sec: int = 0
## "상자 가득! 열어주세요" banner shown when the chest buffer is full (System 2).
var _chest_full_banner: PanelContainer


func _ready() -> void:
	EventBus.party_changed.connect(_rebuild_member_boxes)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_xp_changed.connect(_on_party_member_xp_changed)
	EventBus.party_member_downed.connect(_on_party_member_downed)
	EventBus.party_member_revived.connect(_on_party_member_revived)
	EventBus.party_equipment_changed.connect(_on_party_equipment_changed)
	EventBus.armor_equipped.connect(_on_armor_equipped.unbind(1))
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.field_loop_started.connect(_on_field_loop_started)
	EventBus.field_loop_timer_changed.connect(_on_field_loop_timer_changed)
	_debug_gold_button.pressed.connect(_on_debug_gold_button_pressed)
	_debug_finish_button.pressed.connect(_on_debug_finish_button_pressed)
	EventBus.chest_buffer_full_changed.connect(_on_chest_buffer_full_changed)
	_income_marker = GameState.total_gold_earned
	_build_chest_full_banner()
	_refresh_gold()
	_refresh_field_label()
	_build_inventory_slots()
	_rebuild_member_boxes()
	_refresh_inventory()


func _process(delta: float) -> void:
	_income_timer += delta
	if _income_timer >= 1.0:
		_income_per_sec = maxi(0, GameState.total_gold_earned - _income_marker)
		_income_marker = GameState.total_gold_earned
		_income_timer = 0.0
		_refresh_gold()
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
		_member_boxes.append(box)


func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_hp(new_hp, max_hp)


## XP gauge (party level-up, System: 레벨업). Drives the exp bar + LV label.
func _on_party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var ratio: float = 1.0 if level >= GameState.MAX_CHARACTER_LEVEL else clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	_member_boxes[index].set_exp_ratio(ratio)
	_member_boxes[index].set_level(level)


## Global armor changed — reflect the equipped armor badge on every box.
func _on_armor_equipped() -> void:
	for box in _member_boxes:
		if is_instance_valid(box):
			box.set_armor(GameState.armor_level, GameState.current_armor_name())


func _on_party_member_downed(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(true)


func _on_party_member_revived(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(false)


func _on_party_equipment_changed(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_equipment(GameState.equipment_for_member(index))


func _on_inventory_changed() -> void:
	_refresh_inventory()


# ─── Chest-buffer banner (System 2) ───────────────────────────────────
func _build_chest_full_banner() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.1, 0.08, 0.92)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.85, 0.4, 1.0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_chest_full_banner = PanelContainer.new()
	_chest_full_banner.add_theme_stylebox_override("panel", style)
	_chest_full_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = "상자 가득! 열어주세요"
	label.add_theme_font_override("font", HUD_FONT)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_full_banner.add_child(label)
	add_child(_chest_full_banner)
	# Centered over the field zone (between the left bar and right shop), near top.
	_chest_full_banner.position = Vector2(196.0, 30.0)
	_chest_full_banner.visible = false


func _on_chest_buffer_full_changed(is_full: bool) -> void:
	if _chest_full_banner:
		_chest_full_banner.visible = is_full


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
	if _income_per_sec > 0:
		_gold_label.text = "Gold %d   +%d/s" % [GameState.gold, _income_per_sec]
	else:
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
