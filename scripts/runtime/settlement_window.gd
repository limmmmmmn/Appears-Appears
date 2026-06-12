class_name SettlementWindow
extends Control

## 정산 창 — compressed to TWO beats (요약 페이지 삭제):
##   ① 장비 선택 (보물 상자를 주웠을 때만): 3지선다 + 파티 정보 스트립. 카드에
##      마우스를 올리면 "누구의 어느 슬롯에 · 효과가 얼마나" 미리보기가 뜬다.
##      장착할 아군이 없어도 획득 가능 — 가방으로 (전설템은 갖고 싶으니까 ㅎㅎ).
##   ② 최종 정산: 골드가 또로로록 굴러 올라가고 항목들이 팡팡팡 단계적으로
##      찍히는 쇼. 가방 전부 판매 버튼 포함. → [마을로] → 노드트리.
## The freeze opened here is released by the NODE TREE's [다음 웨이브].

const CARD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const PORTRAIT_SCENE: PackedScene = preload("res://scenes/ui/character_portrait.tscn")
const GOLD_COLOR: Color = Color(0.9, 0.71, 0.24, 1.0)
const DIM_TEXT: Color = Color(0.478, 0.427, 0.36, 1.0)
const INK: Color = Color(0.08627451, 0.08235294, 0.09411765, 1.0)
const GOOD_COLOR: Color = Color(0.3, 0.62, 0.32, 1.0)

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %TitleLabel
@onready var _content: VBoxContainer = %Content

var _wave: int = 0
var _tickets_total: int = 0
var _tickets_done: int = 0
var _pick_gold: int = 0   ## gold gained on the pick screen (gold-option + 전부 판매)
var _preview_label: Label
var _slot_boxes: Dictionary = {}      ## member index → Array[PanelContainer] (6 slots)
var _highlighted_box: PanelContainer
var _highlight_tween: Tween
# After a pick is made we stay on the screen (장착 결과 보기) until [다음 ▸].
var _pick_resolved: bool = false
var _pick_result_text: String = ""
var _pick_result_color: Color = Color.WHITE
var _last_equip_member: int = -1
var _last_equip_slot: int = -1
var _current_options: Array[Dictionary] = []   ## the 3 rolled cards (cached so re-renders don't re-roll)


func _ready() -> void:
	visible = false
	EventBus.wave_ended.connect(_on_wave_ended)


var _winding: bool = false


## 타임아웃 → 전투창은 다 끝낼 때까지 기다림 → 0.5초 줍기/흡수 → 정산. (전투창을
## 강제로 닫지 않아서 막판 전투도 성장에 보탬이 되고, 끝나는 걸 지켜보게 됨.)
func _on_wave_ended(wave: int) -> void:
	if visible or _winding:
		return
	_winding = true
	_wave = wave
	GameState.wave_winding_down = true  # block NEW windows; let open ones finish
	await _wait_for_battles_to_finish()
	if not is_inside_tree():
		return
	# 전투창 다 사라짐 → 1초 줍기 grace + 자동 줍기 흡수 연출.
	EventBus.wave_settle_prep.emit()
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	GameState.wave_winding_down = false
	_winding = false
	_open_settlement()


## Spin until every battle window has resolved (turn-based fights complete on
## their own; the player can smite to hurry them). A guard avoids any hang.
func _wait_for_battles_to_finish() -> void:
	var bm: Node = get_tree().get_first_node_in_group("battle_manager")
	if bm == null or not bm.has_method("has_active_windows"):
		return
	var guard: float = 0.0
	while bm.has_active_windows() and guard < 30.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
		if not is_inside_tree():
			return


func _open_settlement() -> void:
	_tickets_total = GameState.wave_item_tickets
	_tickets_done = 0
	_pick_gold = 0
	_pick_resolved = false
	_last_equip_member = -1
	GameState.open_event_window()
	visible = true
	if _tickets_total > 0:
		_current_options = GameState.roll_gear_options()
		_show_pick()
	else:
		_show_total()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_dim.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _clear_content() -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_highlight_tween = null
	_highlighted_box = null
	_slot_boxes.clear()
	for c in _content.get_children():
		c.queue_free()
	_preview_label = null


func _advance() -> void:
	if _tickets_done < _tickets_total:
		_pick_resolved = false
		_current_options = GameState.roll_gear_options()  # fresh roll per ticket
		_show_pick()
	else:
		_show_total()


# ─── ① 장비 선택: 장비열 | 멤버 보드들 | 인벤토리 ─────────────────────────
## Hovering a gear card LIGHTS UP the exact slot box it would land in. Picking
## does NOT auto-advance — the board re-renders showing the result so you can
## admire the fit, then [다음 ▸] moves on.
func _show_pick() -> void:
	_title.text = "보물 상자 개봉  %d / %d" % [_tickets_done + 1, _tickets_total]
	_clear_content()
	_slot_boxes.clear()
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(main_row)
	# ── LEFT: gear choices, OR (once picked) the result + [다음 ▸].
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(112.0, 0.0)
	left.add_theme_constant_override("separation", 4)
	main_row.add_child(left)
	if _pick_resolved:
		_build_pick_result(left)
	else:
		_build_pick_choices(left)
	# ── MIDDLE: one equipment board per member.
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_child(mid)
	for i in GameState.party_size():
		mid.add_child(_make_member_board(i))
	# ── RIGHT: the inventory grid (6×2).
	main_row.add_child(_make_inventory_panel())
	# ── bottom preview line (stat math in words).
	_preview_label = Label.new()
	_preview_label.text = "" if _pick_resolved else "카드에 마우스를 올리면 장착될 칸이 빛난다"
	_preview_label.add_theme_font_override("font", CARD_FONT)
	_preview_label.add_theme_font_size_override("font_size", 7)
	_preview_label.add_theme_color_override("font_color", DIM_TEXT)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.custom_minimum_size = Vector2(0.0, 16.0)
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_preview_label)
	# Pulse the slot that just received the pick so the eye lands on it.
	if _pick_resolved and _last_equip_member >= 0:
		_highlight_slot(_last_equip_member, _last_equip_slot, false)


func _build_pick_choices(left: VBoxContainer) -> void:
	# Use the CACHED roll (set in _advance/_on_wave_ended) so re-renders — e.g.
	# after "전부 판매" — don't reshuffle the cards.
	var options: Array[Dictionary] = _current_options
	# "그냥 골드"는 최고 옵션의 판매가보다 살짝 높은 정도 — 장비를 포기하는 값이
	# 매각가보다 약간 나으면 충분(예전엔 너무 후했음).
	var best_sell: int = 0
	for option: Dictionary in options:
		var entry := {"item": option.get("item"), "level": int(option.get("level", 1)), "rarity": StringName(option.get("rarity", &"common"))}
		best_sell = maxi(best_sell, GameState.inventory_sell_value(entry))
	var gold_value: int = maxi(5, int(round(float(best_sell) * 1.2)))
	for option: Dictionary in options:
		left.add_child(_make_gear_card(option))
	var gold_card := _make_button("골드 +%dG" % gold_value)
	gold_card.add_theme_color_override("font_color", GOLD_COLOR)
	gold_card.mouse_entered.connect(func() -> void:
		_set_preview("장비 대신 확정 골드", DIM_TEXT))
	gold_card.mouse_exited.connect(_on_card_unhover)
	gold_card.pressed.connect(func() -> void:
		_pick_gold += gold_value
		GameState.add_gold(gold_value)
		_last_equip_member = -1
		_resolve_pick("골드 +%dG 획득" % gold_value, GOLD_COLOR))
	left.add_child(gold_card)


func _build_pick_result(left: VBoxContainer) -> void:
	var msg := Label.new()
	msg.text = _pick_result_text
	msg.add_theme_font_override("font", CARD_FONT)
	msg.add_theme_font_size_override("font_size", 8)
	msg.add_theme_color_override("font_color", _pick_result_color)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_child(msg)
	# Last box only → the 정산 button. Earlier boxes auto-advance (see _resolve_pick).
	if (_tickets_done + 1) >= _tickets_total:
		var settle := _make_button("정산하기 ▸")
		settle.pressed.connect(func() -> void:
			_tickets_done += 1
			_advance())
		left.add_child(settle)


## Apply a pick → show the result on the board (장착된 모습 + 펄스). If more boxes
## remain, AUTO-open the next one after a short beat; the last box waits for the
## [정산하기 ▸] button.
func _resolve_pick(result_text: String, color: Color) -> void:
	_pick_result_text = result_text
	_pick_result_color = color
	_pick_resolved = true
	_show_pick()
	if (_tickets_done + 1) < _tickets_total:
		await get_tree().create_timer(0.7).timeout
		if visible and _pick_resolved:
			_tickets_done += 1
			_advance()


## The inventory grid (6 columns × 2 rows = 12) on the far right — display-only
## for now; full management lives in the node tree's 장비 탭.
func _make_inventory_panel() -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 2)
	var cap := Label.new()
	cap.text = "가방 %d" % GameState.inventory.size()
	cap.add_theme_font_override("font", CARD_FONT)
	cap.add_theme_font_size_override("font_size", 6)
	cap.add_theme_color_override("font_color", DIM_TEXT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	for i in 12:
		grid.add_child(_make_inventory_box(i))
	# 가방 전부 판매 — moved here (장비 획득 화면). One 팡 then the grid refreshes.
	var sale_total: int = GameState.inventory_sell_total()
	if sale_total > 0:
		var sell := _make_button("전부 판매 +%dG" % sale_total)
		sell.add_theme_font_size_override("font_size", 7)
		sell.add_theme_color_override("font_color", GOOD_COLOR)
		sell.pressed.connect(func() -> void:
			_pick_gold += GameState.sell_all_inventory()
			_show_pick())  # rebuild → empty bag + updated count
		col.add_child(sell)
	return col


func _make_inventory_box(index: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(17.0, 17.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.9, 0.83, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.65, 0.6, 0.52, 1.0)
	style.anti_aliasing = false
	box.add_theme_stylebox_override("panel", style)
	if index < GameState.inventory.size():
		var entry = GameState.inventory[index]
		var item: ItemData = GameState.item_entry_data(entry)
		if item != null:
			var rcol: Color = GameState.entry_rarity_color(entry)
			style.border_color = rcol
			style.bg_color = rcol.lerp(Color(0.96862745, 0.9411765, 0.87058824, 1.0), 0.45)
			box.tooltip_text = GameState.entry_display_name(entry)
			var inv_affix: String = GameState.entry_affix_text(entry)
			if inv_affix != "":
				box.tooltip_text += "\n" + inv_affix
			if item.icon != null:
				var icon := TextureRect.new()
				icon.texture = item.icon
				icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.custom_minimum_size = Vector2(13.0, 13.0)
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(icon)
				_add_level_badge(icon, GameState.item_entry_level(entry))
			# 클릭 = 장착 · 호버 = 갈 슬롯 빛남.
			box.mouse_filter = Control.MOUSE_FILTER_STOP
			box.tooltip_text += "\n클릭: 장착"
			var inv_index: int = index
			box.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_equip_from_bag(inv_index))
			box.mouse_entered.connect(_on_bag_item_hover.bind(item))
			box.mouse_exited.connect(_on_card_unhover)
	return box


## Equip a bag item to its best eligible slot (replaced gear → bag). Then refresh.
func _equip_from_bag(inv_index: int) -> void:
	if inv_index < 0 or inv_index >= GameState.inventory.size():
		return
	var item: ItemData = GameState.item_entry_data(GameState.inventory[inv_index])
	var tgt: Dictionary = GameState.settlement_target_for(item)
	if tgt.is_empty():
		_set_preview("장착할 아군이 없다", DIM_TEXT)
		return
	GameState.equip_inventory_item_to(inv_index, int(tgt["member"]), int(tgt["slot"]))
	_show_pick()


## Hovering a bag item → light up the slot it would land in + name the target.
func _on_bag_item_hover(item: ItemData) -> void:
	var tgt: Dictionary = GameState.settlement_target_for(item)
	if tgt.is_empty():
		_set_preview("장착할 아군이 없다", DIM_TEXT)
		return
	var member: int = int(tgt["member"])
	var slot: int = int(tgt["slot"])
	var replaces: bool = GameState.item_entry_data(GameState.party_equipment[member][slot]) != null
	_highlight_slot(member, slot, replaces)
	var note: String = " (기존→가방)" if replaces else ""
	_set_preview("%s → %s %s%s" % [item.display_name, GameState.party[member].display_name,
		GameState.EQUIP_SLOT_NAMES_KR[slot], note], INK)


## One member's board: portrait, "이름 Lv", then the six slot boxes (ㅁ×6).
func _make_member_board(index: int) -> Control:
	var board := VBoxContainer.new()
	board.alignment = BoxContainer.ALIGNMENT_BEGIN
	board.add_theme_constant_override("separation", 2)
	var portrait := PORTRAIT_SCENE.instantiate()
	portrait.custom_minimum_size = Vector2(20.0, 20.0)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(portrait)
	if portrait.has_method("set_character"):
		portrait.set_character(GameState.party[index])
	var nm := Label.new()
	nm.text = "%s Lv%d" % [GameState.party[index].display_name, GameState.party_level(index)]
	nm.add_theme_font_override("font", CARD_FONT)
	nm.add_theme_font_size_override("font_size", 6)
	nm.add_theme_color_override("font_color", INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(nm)
	var boxes: Array = []
	for slot in GameState.EQUIPMENT_SLOT_COUNT:
		var box := _make_slot_box(index, slot)
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		board.add_child(box)
		boxes.append(box)
	_slot_boxes[index] = boxes
	return board


## A single ㅁ: cream square, equipped item's icon inside (rarity-tinted border).
func _make_slot_box(member: int, slot: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(17.0, 17.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.9, 0.83, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.65, 0.6, 0.52, 1.0)
	style.anti_aliasing = false
	box.add_theme_stylebox_override("panel", style)
	box.set_meta("style", style)
	box.tooltip_text = GameState.EQUIP_SLOT_NAMES_KR[slot]
	var entry = GameState.party_equipment[member][slot] if member < GameState.party_equipment.size() else null
	var item: ItemData = GameState.item_entry_data(entry)
	if item != null:
		# 등급색을 칸 배경으로 — 어느 칸에 어떤 등급이 박혔는지 한눈에.
		var rcol: Color = GameState.entry_rarity_color(entry)
		style.border_color = rcol
		style.bg_color = rcol.lerp(Color(0.96862745, 0.9411765, 0.87058824, 1.0), 0.45)
		if item.icon != null:
			var icon := TextureRect.new()
			icon.texture = item.icon
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.custom_minimum_size = Vector2(13.0, 13.0)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(icon)
			_add_level_badge(icon, GameState.item_entry_level(entry))
		box.tooltip_text = GameState.entry_display_name(entry)
		var slot_affix: String = GameState.entry_affix_text(entry)
		if slot_affix != "":
			box.tooltip_text += "\n" + slot_affix
		box.tooltip_text += "\n클릭: 해제"
		# 클릭 = 가방으로 해제.
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				GameState.unequip_to_bag(member, slot)
				_show_pick())
	box.set_meta("base_border", style.border_color)
	box.set_meta("base_bg", style.bg_color)
	return box


## A tiny outlined level number in the box's bottom-right corner. The label FILLS
## the icon and bottom-right-aligns its text — robust regardless of icon size.
func _add_level_badge(icon: TextureRect, level: int) -> void:
	var box := icon.get_parent()
	if box is Control:
		(box as Control).clip_contents = true
	var lv := Label.new()
	lv.text = str(level)
	lv.add_theme_font_override("font", CARD_FONT)
	lv.add_theme_font_size_override("font_size", 7)
	lv.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lv.add_theme_color_override("font_outline_color", INK)
	lv.add_theme_constant_override("outline_size", 2)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.offset_right = -1.0
	lv.offset_bottom = 1.0
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	icon.add_child(lv)


## Light up the slot a hovered card would land in (green = empty, gold = replace).
func _highlight_slot(member: int, slot: int, replaces: bool) -> void:
	_clear_highlight()
	if not _slot_boxes.has(member):
		return
	var boxes: Array = _slot_boxes[member]
	if slot < 0 or slot >= boxes.size():
		return
	var box: PanelContainer = boxes[slot]
	if not is_instance_valid(box):
		return
	# Emphasis = a THICK yellow rim only — keep the rarity bg so 등급색이 안 사라진다.
	var style: StyleBoxFlat = box.get_meta("style")
	style.set_border_width_all(3)
	style.border_color = GOLD_COLOR if replaces else GOOD_COLOR
	box.pivot_offset = box.size * 0.5
	_highlight_tween = create_tween().set_loops()
	_highlight_tween.tween_property(box, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_SINE)
	_highlight_tween.tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE)
	_highlighted_box = box


func _clear_highlight() -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_highlight_tween = null
	if _highlighted_box != null and is_instance_valid(_highlighted_box):
		var style: StyleBoxFlat = _highlighted_box.get_meta("style")
		style.set_border_width_all(1)
		style.bg_color = _highlighted_box.get_meta("base_bg", Color(0.93, 0.9, 0.83, 1.0))
		style.border_color = _highlighted_box.get_meta("base_border", Color(0.65, 0.6, 0.52, 1.0))
		_highlighted_box.scale = Vector2.ONE
	_highlighted_box = null


func _on_card_unhover() -> void:
	_clear_preview()
	_clear_highlight()


func _set_preview(text: String, color: Color) -> void:
	if _preview_label != null and is_instance_valid(_preview_label):
		_preview_label.text = text
		_preview_label.add_theme_color_override("font_color", color)


func _clear_preview() -> void:
	_set_preview("카드에 마우스를 올리면 장착 정보가 보인다", DIM_TEXT)


## Where would this option land + what changes? "용사의 무기 · 공격 +12 (+4)".
func _preview_for_option(option: Dictionary) -> String:
	var item: ItemData = option.get("item", null)
	var level: int = int(option.get("level", 1))
	var rarity_mult: float = float(Balance.gear_rarity_by_id(StringName(option.get("rarity", &"common"))).get("mult", 1.0))
	var tgt: Dictionary = GameState.settlement_target_for(item)
	if tgt.is_empty():
		return "장착할 아군 없음 → 가방으로 보관 (장비 탭에서 관리)"
	var target: int = int(tgt["member"])
	var slot: int = int(tgt["slot"])
	var old_entry = GameState.party_equipment[target][slot]
	var parts: Array[String] = []
	for stat: Array in [["attack_bonus", "공격"], ["max_hp_bonus", "HP"], ["agility_bonus", "민첩"]]:
		var new_v: int = int(round(float(int(item.get(stat[0])) * level) * rarity_mult))
		var old_v: int = 0
		var old_item: ItemData = GameState.item_entry_data(old_entry)
		if old_item != null:
			old_v = int(round(float(int(old_item.get(stat[0])) * GameState.item_entry_level(old_entry)) * GameState.entry_rarity_mult(old_entry)))
		if new_v == 0 and old_v == 0:
			continue
		var delta: int = new_v - old_v
		var delta_str: String = "  (%+d)" % delta if old_v != 0 else ""
		parts.append("%s +%d%s" % [stat[1], new_v, delta_str])
	# 어픽스 (등급 보너스): 무기 = 치명, 그 외 = 회피 — 픽 전에 한눈에.
	var affix_txt: String = GameState.entry_affix_text(
		{"item": item, "level": level, "rarity": StringName(option.get("rarity", &"common"))})
	if affix_txt != "":
		parts.append(affix_txt)
	var member_name: String = GameState.party[target].display_name
	var slot_name: String = GameState.EQUIP_SLOT_NAMES_KR[slot]
	var stats_str: String = " · ".join(parts) if not parts.is_empty() else "외형용"
	var replace_note: String = ""
	if GameState.item_entry_data(old_entry) != null:
		replace_note = "  (기존 장비는 가방으로)"
	return "%s의 %s에 장착 · %s%s" % [member_name, slot_name, stats_str, replace_note]


func _make_gear_card(option: Dictionary) -> Button:
	var item: ItemData = option.get("item", null)
	var level: int = int(option.get("level", 1))
	var rarity_id: StringName = StringName(option.get("rarity", &"common"))
	var rarity: Dictionary = Balance.gear_rarity_by_id(rarity_id)
	var eligible: Array[int] = GameState.eligible_members_for_item(item)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 26.0)
	# 등급색을 카드 배경으로 — 한눈에 등급이 읽힌다. 흔한 등급은 옅게, 희귀할수록 진하게.
	var accent: Color = rarity.get("color", Color.WHITE)
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = accent.lerp(Color(0.96862745, 0.9411765, 0.87058824, 1.0), 0.55)
		if style_name == "hover":
			sb.bg_color = accent.lerp(Color(1, 1, 1, 1), 0.35)  # brighter on hover
		sb.set_border_width_all(2)
		sb.border_color = accent
		sb.set_corner_radius_all(2)
		sb.set_content_margin_all(3.0)
		sb.anti_aliasing = false
		b.add_theme_stylebox_override(style_name, sb)
	# 장착 불가여도 획득 가능 — 가방으로 (전설템 소장욕 존중 ㅎㅎ). 픽 후 결과를
	# 보드에 보여주고 [다음 ▸]을 기다린다(바로 안 넘어감).
	var rarity_name2: String = str(rarity.get("name", ""))
	var pfx2: String = "" if rarity_id == &"common" else "[%s] " % rarity_name2
	var label_name: String = "%s%s Lv%d" % [pfx2, item.display_name, level]
	b.pressed.connect(func() -> void:
		if eligible.is_empty():
			GameState.gain_gear_to_bag(item, level, rarity_id)
			_last_equip_member = -1
			_resolve_pick("%s\n→ 가방에 보관" % label_name, rarity.get("color", Color.WHITE))
		else:
			var tgt: Dictionary = GameState.settlement_target_for(item)
			var replaced: bool = GameState.item_entry_data(GameState.party_equipment[int(tgt["member"])][int(tgt["slot"])]) != null
			GameState.equip_settlement_gear(item, level, rarity_id)
			_last_equip_member = int(tgt["member"])
			_last_equip_slot = int(tgt["slot"])
			var note: String = " (기존 장비는 가방으로)" if replaced else ""
			_resolve_pick("%s\n→ %s 장착!%s" % [label_name, GameState.party[_last_equip_member].display_name, note], rarity.get("color", Color.WHITE)))
	# Hover = the destination slot box LIGHTS UP + the stat line below.
	b.mouse_entered.connect(func() -> void:
		_set_preview(_preview_for_option(option), INK if not eligible.is_empty() else DIM_TEXT)
		var tgt: Dictionary = GameState.settlement_target_for(item)
		if not tgt.is_empty():
			var replaces: bool = GameState.item_entry_data(GameState.party_equipment[int(tgt["member"])][int(tgt["slot"])]) != null
			_highlight_slot(int(tgt["member"]), int(tgt["slot"]), replaces))
	b.mouse_exited.connect(_on_card_unhover)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4.0
	row.offset_right = -4.0
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	if item.icon != null:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var name_label := Label.new()
	var rarity_name: String = str(rarity.get("name", ""))
	var prefix: String = "" if rarity_id == &"common" else "[%s] " % rarity_name
	name_label.text = "%s%s Lv%d" % [prefix, item.display_name, level] \
		+ ("" if not eligible.is_empty() else "\n(가방행)")
	name_label.add_theme_font_override("font", CARD_FONT)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", rarity.get("color", Color.WHITE))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	return b


# ─── ② 최종 정산 (또로로록 + 팡팡팡) ─────────────────────────────────────
func _show_total() -> void:
	_title.text = "정산"
	_clear_content()
	_run_tally()


## The show: each earnings line lands with a POP, then the total rolls up
## (또로로록), then 보유 골드 stamps in. Sell-all gives one more 팡.
func _run_tally() -> void:
	var lines: Array = []
	lines.append(["스테이지 골드", GameState.wave_gold_earned])
	if _pick_gold > 0:
		lines.append(["상자 골드", _pick_gold])
	# "이자" 노드: 보유 골드의 % — one juicy extra line when bought.
	var interest: int = GameState.collect_wave_interest()
	if interest > 0:
		lines.append(["이자", interest])
	var total: int = GameState.wave_gold_earned + _pick_gold + interest
	for line: Array in lines:
		if not visible:
			return
		_pop_line("%s  +%dG" % [line[0], int(line[1])], DIM_TEXT, 8)
		await get_tree().create_timer(0.28).timeout
	# 또로로록: the wave's take rolls up on a counter.
	var counter := _add_line("이번 수익  0G", GOLD_COLOR, 12)
	var ct := create_tween()
	ct.tween_method(func(v: float) -> void:
		if is_instance_valid(counter):
			counter.text = "이번 수익  %dG" % int(v),
		0.0, float(total), clampf(0.25 + float(total) * 0.004, 0.3, 1.1))
	await ct.finished
	if not visible:
		return
	_pop_existing(counter)
	await get_tree().create_timer(0.2).timeout
	if not visible:
		return
	_pop_line("보유 골드  %dG" % GameState.gold, GOLD_COLOR, 10)
	# 가방 전부 판매는 장비 획득(픽) 화면으로 이동 — 여기 정산 탤리는 깔끔하게 합계만.
	var go := _make_button("마을로 ▸")
	go.pressed.connect(_open_node_tree)
	_content.add_child(go)


func _open_node_tree() -> void:
	visible = false  # the freeze stays — the node tree owns the release
	var tree := get_tree().get_first_node_in_group("node_tree_window")
	if tree != null and tree.has_method("open"):
		tree.open()
	else:
		GameState.close_event_window()
		GameState.start_next_wave()


# ─── helpers ────────────────────────────────────────────────────────────
func _add_line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", CARD_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(l)
	return l


## A line that lands with a 팡 (overshoot scale pop).
func _pop_line(text: String, color: Color, size: int) -> Label:
	var l := _add_line(text, color, size)
	_pop_existing(l)
	return l


func _pop_existing(l: Label) -> void:
	if l == null or not is_instance_valid(l):
		return
	l.pivot_offset = Vector2(_content.size.x * 0.5, l.size.y * 0.5)
	l.scale = Vector2(0.4, 0.4)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2(1.18, 1.18), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector2.ONE, 0.08)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 16.0)
	return b
