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
## Design viewport width (canvas_items stretch) — used to center HUD elements on
## the TRUE viewport center, ignoring the side panels.
const VIEWPORT_DESIGN_WIDTH: float = 640.0
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
## macOS-style inventory window (bottom-right): dropped gear stacks here; drag a
## slot onto a party member's equip slots to wear it. Scrolls when full.
var _inventory_window: PanelContainer
var _inv_grid: GridContainer
var _timer_urgent: bool = false
var _timer_pulse_time: float = 0.0
## Measured gold income per second (sampled from total_gold_earned each 1s),
## shown next to the gold total so upgrades read as a rising "+N/s".
var _income_timer: float = 0.0
var _income_marker: int = 0
var _income_per_sec: int = 0
## Always-on big gold readout, pinned top-center (gold is the #1 info — must be
## visible no matter which side of the screen you're looking at).
var _gold_center: PanelContainer
var _gold_center_label: Label
## Big centered "○○ 해금!" popup with the enemy sprite (tier unlock moment).
var _unlock_popup: PanelContainer
var _unlock_sprite: TextureRect
var _unlock_label: Label
var _unlock_tween: Tween
## Opening name prompt — "이름을 입력하세요" overlay shown before anything else.
var _name_overlay: Control
var _name_line_edit: LineEdit


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
	EventBus.tier_unlocked.connect(_on_tier_unlocked)
	# Compact top-bar fonts (centralized in UITheme).
	for lbl in [_gold_label, _field_label, _countdown_label]:
		lbl.add_theme_font_size_override("font_size", UITheme.FONT_HUD)
	# Gold now lives only in the right panel (no duplicate over the field).
	_gold_label.visible = false
	_income_marker = GameState.total_gold_earned
	_build_gold_center()
	_build_unlock_popup()
	if not GameState.name_entered:
		_build_name_overlay()
	_refresh_gold()
	_refresh_field_label()
	_build_inventory_window()
	_rebuild_member_boxes()


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
	_refresh_inventory_window()


# ─── Tier-unlock popup (big sprite + "○○ 해금!") ───────────────────────
func _build_unlock_popup() -> void:
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
	_unlock_popup = PanelContainer.new()
	_unlock_popup.add_theme_stylebox_override("panel", style)
	_unlock_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unlock_popup.add_child(col)
	_unlock_sprite = TextureRect.new()
	_unlock_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp big pixels
	_unlock_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_unlock_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_unlock_sprite.custom_minimum_size = Vector2(48, 48)
	_unlock_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unlock_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_unlock_sprite)
	_unlock_label = Label.new()
	_unlock_label.add_theme_font_override("font", HUD_FONT)
	_unlock_label.add_theme_font_size_override("font_size", 13)
	_unlock_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_unlock_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_unlock_label.add_theme_constant_override("shadow_offset_x", 1)
	_unlock_label.add_theme_constant_override("shadow_offset_y", 1)
	_unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_unlock_label)
	add_child(_unlock_popup)
	_unlock_popup.visible = false


func _on_tier_unlocked(tier_id: StringName) -> void:
	if _unlock_popup == null:
		return
	var tier: Dictionary = Balance.tier_by_id(tier_id)
	_unlock_label.text = "%s 해금!" % str(tier.get("name", "?"))
	_unlock_sprite.texture = _tier_sprite(tier)
	_unlock_popup.visible = true
	_unlock_popup.modulate = Color(1, 1, 1, 1)
	_unlock_popup.scale = Vector2.ONE
	# Centered on the true viewport center (panels just overlay the edges).
	await get_tree().process_frame  # let it size to content first
	var center_x: float = VIEWPORT_DESIGN_WIDTH * 0.5
	_unlock_popup.pivot_offset = _unlock_popup.size * 0.5
	_unlock_popup.position = Vector2(center_x, 120.0) - _unlock_popup.size * 0.5
	if _unlock_tween != null and _unlock_tween.is_valid():
		_unlock_tween.kill()
	_unlock_popup.scale = Vector2(0.6, 0.6)
	_unlock_tween = create_tween()
	_unlock_tween.tween_property(_unlock_popup, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_unlock_tween.tween_interval(1.4)
	_unlock_tween.tween_property(_unlock_popup, "modulate:a", 0.0, 0.5)
	_unlock_tween.tween_callback(func() -> void: _unlock_popup.visible = false)


func _tier_sprite(tier: Dictionary) -> Texture2D:
	var path: String = str(tier.get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ed := load(path) as EnemyData
	return ed.sprite if ed != null else null


# ─── Opening: name the hero ────────────────────────────────────────────
func _build_name_overlay() -> void:
	_name_overlay = Control.new()
	_name_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # block the world behind
	add_child(_name_overlay)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.45)  # dim, but the lone hero still shows through
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_overlay.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_overlay.add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.35, 0.9)
	style.set_corner_radius_all(7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)

	var title := Label.new()
	title.text = "이름을 입력하세요"
	title.add_theme_font_override("font", HUD_FONT)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_name_line_edit = LineEdit.new()
	_name_line_edit.custom_minimum_size = Vector2(160.0, 22.0)
	_name_line_edit.placeholder_text = "용사"
	_name_line_edit.max_length = 10
	_name_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_line_edit.add_theme_font_override("font", HUD_FONT)
	_name_line_edit.add_theme_font_size_override("font_size", 12)
	_name_line_edit.text_submitted.connect(_on_name_submitted)
	col.add_child(_name_line_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(_make_name_button("확인", Color(1.0, 0.85, 0.35, 1.0), _on_name_confirm))
	row.add_child(_make_name_button("랜덤", Color(0.6, 0.78, 0.95, 1.0), _on_name_random))

	_name_line_edit.call_deferred("grab_focus")


func _make_name_button(text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56.0, 22.0)
	b.add_theme_font_override("font", HUD_FONT)
	b.add_theme_font_size_override("font_size", 11)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Color(0.08, 0.07, 0.05, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.lightened(0.18)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(handler)
	return b


func _on_name_submitted(_text: String) -> void:
	_on_name_confirm()


func _on_name_confirm() -> void:
	GameState.set_player_name(_name_line_edit.text if _name_line_edit != null else "")
	_dismiss_name_overlay()


func _on_name_random() -> void:
	if _name_line_edit != null:
		_name_line_edit.text = GameState.random_hero_name()  # fill so the player sees it


func _dismiss_name_overlay() -> void:
	if _name_overlay != null:
		_name_overlay.queue_free()
		_name_overlay = null


# ─── Inventory window (macOS style, bottom-right) ──────────────────────
func _build_inventory_window() -> void:
	# Hide the legacy scene panel — this code-built window replaces it.
	var legacy := get_node_or_null("InventoryPanel")
	if legacy:
		legacy.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.180, 0.133, 0.184, 1.0)  # #2e222f dark interior
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.12)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 3
	_inventory_window = PanelContainer.new()
	_inventory_window.add_theme_stylebox_override("panel", style)
	_inventory_window.clip_contents = true
	_inventory_window.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Bottom-LEFT corner (just right of the left dock), above the party strip.
	_inventory_window.offset_left = 6.0
	_inventory_window.offset_top = -120.0
	_inventory_window.offset_right = 98.0
	_inventory_window.offset_bottom = -46.0
	add_child(_inventory_window)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_inventory_window.add_child(col)

	# Title bar (Resurrect 64 teal) — matches the strengthen windows.
	var tbar_style := StyleBoxFlat.new()
	tbar_style.bg_color = Color(0.055, 0.686, 0.608, 1.0)  # #0eaf9b teal
	tbar_style.corner_radius_top_left = 5
	tbar_style.corner_radius_top_right = 5
	tbar_style.content_margin_left = 5
	tbar_style.content_margin_right = 4
	tbar_style.content_margin_top = 2
	tbar_style.content_margin_bottom = 2
	var titlebar := PanelContainer.new()
	titlebar.add_theme_stylebox_override("panel", tbar_style)
	col.add_child(titlebar)
	var title := Label.new()
	title.text = "인벤토리"
	title.add_theme_font_override("font", HUD_FONT)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.05, 0.08, 0.07, 1.0))
	titlebar.add_child(title)

	# Scrollable grid — fills up, scrolls when there's no room.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 4
	_inv_grid.add_theme_constant_override("h_separation", 2)
	_inv_grid.add_theme_constant_override("v_separation", 2)
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_grid)
	_refresh_inventory_window()


func _refresh_inventory_window() -> void:
	if _inv_grid == null:
		return
	for child in _inv_grid.get_children():
		child.queue_free()
	var items: Array = GameState.inventory_items()
	var count: int = maxi(items.size() + 4, 12)  # items + spare empties, ScrollContainer scrolls
	for i in count:
		var slot: EquipSlot = EQUIP_SLOT_SCENE.instantiate()
		slot.custom_minimum_size = Vector2(18, 18)
		slot.drag_role = &"inventory"
		slot.inv_index = i
		_inv_grid.add_child(slot)
		slot.set_empty_label("빈 칸")
		slot.set_item(items[i] if i < items.size() else null)


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
	var text: String
	if _income_per_sec > 0:
		text = "Gold %d   +%d/s" % [GameState.gold, _income_per_sec]
	else:
		text = "Gold %d" % GameState.gold
	_gold_label.text = text
	if _gold_center_label != null:
		_gold_center_label.text = text
		_reposition_gold_center()


# ─── Top-center gold readout (always visible) ──────────────────────────
func _build_gold_center() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.04, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 0.84, 0.3, 0.85)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	_gold_center = PanelContainer.new()
	_gold_center.add_theme_stylebox_override("panel", style)
	_gold_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_center_label = Label.new()
	_gold_center_label.add_theme_font_override("font", HUD_FONT)
	_gold_center_label.add_theme_font_size_override("font_size", 16)  # big — top priority
	_gold_center_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	_gold_center_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_gold_center_label.add_theme_constant_override("shadow_offset_x", 1)
	_gold_center_label.add_theme_constant_override("shadow_offset_y", 1)
	_gold_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_center.add_child(_gold_center_label)
	add_child(_gold_center)
	_gold_center.position = Vector2(280.0, 6.0)


## Keep the pill centered on the play field as its width changes with the number.
func _reposition_gold_center() -> void:
	if _gold_center == null:
		return
	await get_tree().process_frame
	if _gold_center == null:
		return
	var center_x: float = VIEWPORT_DESIGN_WIDTH * 0.5  # true viewport center
	_gold_center.position = Vector2(center_x - _gold_center.size.x * 0.5, 6.0)


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
