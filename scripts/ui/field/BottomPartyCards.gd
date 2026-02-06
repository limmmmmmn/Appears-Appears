extends Control
class_name BottomPartyCards
## 하단 파티 카드 UI (재구축)
## 영웅별 이름, HP바, ATB/쿨타임 바, 장비 슬롯을 카드 형태로 표시
## FieldHUD.STYLE 상수를 공유하여 일관된 비주얼 유지

const SLOT_ICONS := {
	"main_hand": "⚔", "off_hand": "🛡", "head": "👒",
	"body": "👕", "acc1": "💍", "acc2": "💍",
}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

const CARD_WIDTH := 108
const CARD_HEIGHT := 142

# HP바 색상 (일관된 3단계)
const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID  := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW  := Color(0.92, 0.22, 0.22)

# ATB/쿨타임 바 색상
const ATB_COLOR_CHARGING := Color(0.3, 0.7, 1.0)
const ATB_COLOR_READY    := Color(1.0, 0.8, 0.2)
const CD_COLOR_CHARGING  := Color(0.4, 0.4, 0.5)
const CD_COLOR_READY     := Color(0.3, 0.8, 0.3)

# 카드 스타일
const CARD_BG       := Color(0.04, 0.04, 0.07, 0.95)
const CARD_BORDER   := Color(0.3, 0.35, 0.5, 0.9)
const BAR_BG        := Color(0.12, 0.1, 0.15)

signal equipment_dropped(hero_index: int, item_id: String)

@onready var cards_container: HBoxContainer = %CardsContainer


#region 카드 데이터 구조
class HeroCard:
	var wrapper: Control
	var panel: PanelContainer
	var name_label: Label
	var hp_bar: ProgressBar
	var hp_label: Label
	var atb_section: VBoxContainer
	var basic_atb_bar: ProgressBar
	var skill_rows: Dictionary = {}  # skill_id -> { row, bar, label }
	var equip_section: VBoxContainer
	var equip_rows: Dictionary = {}  # slot_name -> { row: _EquipSlotRow, icon, name }
	var hero_index: int = -1
	var hero_id: String = ""
	var is_hovered: bool = false
#endregion


var hero_cards: Array[HeroCard] = []


#region 장비 슬롯 (드래그앤드롭 지원)
class _EquipSlotRow extends PanelContainer:
	var card_ref: BottomPartyCards
	var hero_index: int = -1
	var slot_name: String = ""
	var item_id: String = ""
	var icon_label: Label
	var name_label: Label
	var _normal_style: StyleBoxFlat
	var _hover_style: StyleBoxFlat

	func setup(p_ref: BottomPartyCards, p_idx: int, p_slot: String) -> void:
		card_ref = p_ref
		hero_index = p_idx
		slot_name = p_slot
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 14)

		_normal_style = FieldHUD._make_flat_style(Color(0.06, 0.06, 0.08, 0.0), Color(0.22, 0.22, 0.28, 0.5), 2, 1)
		_normal_style.content_margin_left = 2
		_normal_style.content_margin_right = 2
		add_theme_stylebox_override("panel", _normal_style)

		_hover_style = FieldHUD._make_flat_style(
			FieldHUD.STYLE.bg_btn_hover,
			Color(1.0, 0.95, 0.3, 1.0), 2, 2
		)
		_hover_style.content_margin_left = 2
		_hover_style.content_margin_right = 2

		mouse_entered.connect(func(): add_theme_stylebox_override("panel", _hover_style))
		mouse_exited.connect(func(): add_theme_stylebox_override("panel", _normal_style))

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary or data.get("type", "") != "equipment":
			return false
		var iid: String = data.get("item_id", "")
		if iid.is_empty():
			return false
		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
			return false
		var hero: Hero = party[hero_index]
		if not hero.can_equip(iid):
			return false
		var edata: Dictionary = DataManager.get_equipment(iid)
		var eslot: String = edata.get("slot", "")
		if eslot.is_empty():
			return false
		if eslot in ["accessory", "acc", "acc1", "acc2"]:
			return slot_name in ["acc1", "acc2"]
		return eslot == slot_name

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if data is Dictionary and card_ref:
			var iid: String = data.get("item_id", "")
			if not iid.is_empty():
				card_ref._handle_equipment_drop(hero_index, slot_name, iid, data)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_id.is_empty():
			return null
		var preview := Label.new()
		preview.text = "%s %s" % [SLOT_ICONS.get(slot_name, "?"), name_label.text]
		preview.add_theme_font_size_override("font_size", 9)
		preview.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		preview.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_theme_constant_override("outline_size", 2)
		set_drag_preview(preview)
		return {
			"type": "equipment", "item_id": item_id,
			"source": "equipment", "hero_index": hero_index,
			"source_slot": slot_name,
		}
#endregion


func _ready() -> void:
	_connect_signals()
	call_deferred("_initial_setup")


func _initial_setup() -> void:
	if cards_container:
		update_display()
	else:
		push_error("[BottomPartyCards] CardsContainer not found!")


#region 시그널 연결
func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(_on_party_changed):
			PartyManager.party_changed.connect(_on_party_changed)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(update_display):
				BattleManager.party_hp_changed.connect(update_display)
		if BattleManager.has_signal("hero_attacked"):
			if not BattleManager.hero_attacked.is_connected(_on_hero_attacked):
				BattleManager.hero_attacked.connect(_on_hero_attacked)
		if BattleManager.has_signal("hero_damaged"):
			if not BattleManager.hero_damaged.is_connected(_on_hero_damaged):
				BattleManager.hero_damaged.connect(_on_hero_damaged)

	if ATBManager and ATBManager.has_signal("atb_updated"):
		if not ATBManager.atb_updated.is_connected(_on_atb_updated):
			ATBManager.atb_updated.connect(_on_atb_updated)
#endregion


func _on_party_changed() -> void:
	_rebuild_cards()
	update_display()


#region 카드 생성
func _rebuild_cards() -> void:
	hero_cards.clear()
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.free()

	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		if party[i] == null:
			continue
		var card := _create_hero_card(i)
		hero_cards.append(card)
		cards_container.add_child(card.wrapper)


func _create_hero_card(index: int) -> HeroCard:
	var card := HeroCard.new()
	card.hero_index = index

	# 래퍼 (클리핑 컨테이너)
	card.wrapper = Control.new()
	card.wrapper.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	# 메인 패널
	card.panel = PanelContainer.new()
	card.panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.panel.set_meta("card_index", index)
	var panel_style := FieldHUD._make_flat_style(CARD_BG, CARD_BORDER, 6, 2)
	card.panel.add_theme_stylebox_override("panel", panel_style)
	card.panel.gui_input.connect(_on_card_gui_input.bind(card))
	card.panel.mouse_entered.connect(func(): card.is_hovered = true)
	card.panel.mouse_exited.connect(func(): card.is_hovered = false)
	card.wrapper.add_child(card.panel)

	# 내부 레이아웃
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 5
	vbox.offset_right = -5
	vbox.offset_top = 4
	vbox.offset_bottom = -4
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.panel.add_child(vbox)

	# 이름
	card.name_label = _make_label("영웅", FieldHUD.STYLE.font_small, Color(0.95, 0.95, 0.95))
	card.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(card.name_label)

	# HP바
	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(0, 12)
	hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_container)

	card.hp_bar = _make_progress_bar(BAR_BG, HP_COLOR_HIGH, 3)
	card.hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_container.add_child(card.hp_bar)

	card.hp_label = _make_label("", FieldHUD.STYLE.font_tiny, Color.WHITE)
	card.hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	card.hp_label.add_theme_constant_override("outline_size", 2)
	hp_container.add_child(card.hp_label)

	# ATB 섹션
	card.atb_section = VBoxContainer.new()
	card.atb_section.add_theme_constant_override("separation", 1)
	card.atb_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.atb_section)

	var basic_row := _create_bar_row("공격", ATB_COLOR_CHARGING)
	card.basic_atb_bar = basic_row.get_node("Bar")
	card.atb_section.add_child(basic_row)

	# 구분선
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# 장비 섹션
	card.equip_section = VBoxContainer.new()
	card.equip_section.add_theme_constant_override("separation", 0)
	card.equip_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.equip_section)

	for slot_name in SLOT_ORDER:
		var row_data := _create_equip_row(slot_name, index)
		card.equip_section.add_child(row_data["row"])
		card.equip_rows[slot_name] = row_data

	return card
#endregion


#region UI 팩토리 유틸리티
func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_progress_bar(bg_color: Color, fill_color: Color, radius: int = 3) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.corner_radius_top_left = radius
	bg.corner_radius_top_right = radius
	bg.corner_radius_bottom_left = radius
	bg.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = radius
	fill.corner_radius_top_right = radius
	fill.corner_radius_bottom_left = radius
	fill.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("fill", fill)

	return bar


func _create_bar_row(label_text: String, bar_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := _make_label(label_text, FieldHUD.STYLE.font_tiny, Color(0.7, 0.7, 0.7))
	label.name = "Label"
	label.custom_minimum_size.x = 24
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(60, 5)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_bar_style(bar, BAR_BG, bar_color, 2)
	row.add_child(bar)

	return row


func _create_equip_row(slot_name: String, hero_index: int) -> Dictionary:
	var row := _EquipSlotRow.new()
	row.setup(self, hero_index, slot_name)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon_lbl := _make_label(SLOT_ICONS.get(slot_name, "?"), FieldHUD.STYLE.font_tiny, FieldHUD.STYLE.text_dim)
	icon_lbl.name = "Icon"
	icon_lbl.custom_minimum_size.x = 12
	hbox.add_child(icon_lbl)

	var name_lbl := _make_label("-", FieldHUD.STYLE.font_tiny, FieldHUD.STYLE.text_dim)
	name_lbl.name = "Name"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_lbl)

	row.icon_label = icon_lbl
	row.name_label = name_lbl

	return {"row": row, "icon": icon_lbl, "name": name_lbl}


static func _apply_bar_style(bar: ProgressBar, bg_color: Color, fill_color: Color, radius: int = 2) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = bg_color
	bg.corner_radius_top_left = radius
	bg.corner_radius_top_right = radius
	bg.corner_radius_bottom_left = radius
	bg.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = radius
	fill.corner_radius_top_right = radius
	fill.corner_radius_bottom_left = radius
	fill.corner_radius_bottom_right = radius
	bar.add_theme_stylebox_override("fill", fill)
#endregion


#region 디스플레이 업데이트
func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	if hero_cards.size() != party.size():
		_rebuild_cards()

	for i in range(hero_cards.size()):
		if i >= party.size() or party[i] == null:
			continue
		var card := hero_cards[i]
		var hero: Hero = party[i]
		card.hero_id = hero.id
		card.name_label.text = hero.hero_name
		_update_hp(card, hero)
		_update_equips(card, hero)
		_update_skill_bars(card, hero)


func _update_hp(card: HeroCard, hero: Hero) -> void:
	var max_hp := hero.get_max_hp()
	var pct: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
	card.hp_bar.value = pct * 100.0
	card.hp_label.text = "%d/%d" % [hero.current_hp, max_hp]

	# HP 색상 업데이트
	var color: Color
	if pct <= 0.25:
		color = HP_COLOR_LOW
	elif pct <= 0.5:
		color = HP_COLOR_MID
	else:
		color = HP_COLOR_HIGH

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	card.hp_bar.add_theme_stylebox_override("fill", fill)


func _update_equips(card: HeroCard, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var row_data: Dictionary = card.equip_rows.get(slot_name, {})
		if row_data.is_empty():
			continue

		var row: _EquipSlotRow = row_data.get("row")
		var icon_lbl: Label = row_data.get("icon")
		var name_lbl: Label = row_data.get("name")
		if not icon_lbl or not name_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if row:
			row.item_id = equip_id

		if equip_id.is_empty():
			icon_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
			name_lbl.text = "-"
			name_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
		else:
			var edata: Dictionary = DataManager.get_equipment(equip_id)
			var rarity: String = edata.get("rarity", "common")
			var rcolor: Color = _get_rarity_color(rarity)
			icon_lbl.add_theme_color_override("font_color", rcolor)
			name_lbl.text = edata.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", rcolor)


func _update_skill_bars(card: HeroCard, hero: Hero) -> void:
	var skills: Array = hero.get_available_skills()

	# 새 스킬 추가
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue
		if not card.skill_rows.has(skill_id):
			var skill_data: Dictionary = DataManager.get_skill(skill_id)
			var skill_name: String = skill_data.get("name", skill_id)
			var row := _create_bar_row(skill_name, CD_COLOR_READY)
			card.atb_section.add_child(row)
			card.skill_rows[skill_id] = {
				"row": row,
				"bar": row.get_node("Bar"),
				"label": row.get_node("Label"),
			}

	# 삭제된 스킬 제거
	var to_remove: Array = []
	for skill_id in card.skill_rows.keys():
		if skill_id not in skills:
			to_remove.append(skill_id)
	for skill_id in to_remove:
		var rd: Dictionary = card.skill_rows[skill_id]
		rd["row"].queue_free()
		card.skill_rows.erase(skill_id)
#endregion


#region ATB 업데이트
func _on_atb_updated() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(hero_cards.size()):
		if i >= party.size() or party[i] == null:
			continue
		var card := hero_cards[i]
		var hero: Hero = party[i]

		# 기본 ATB
		var atb_pct: float = ATBManager.get_hero_atb_percent(hero.id) if ATBManager else 0.0
		card.basic_atb_bar.value = atb_pct * 100.0
		var atb_color: Color = ATB_COLOR_READY if atb_pct >= 1.0 else ATB_COLOR_CHARGING
		_apply_bar_style(card.basic_atb_bar, BAR_BG, atb_color, 2)

		# 스킬 쿨타임
		for skill_id in card.skill_rows.keys():
			var rd: Dictionary = card.skill_rows[skill_id]
			var bar: ProgressBar = rd["bar"]
			var cd_pct: float = CooldownManager.get_cooldown_percent(hero.id, skill_id) if CooldownManager else 0.0
			var is_ready: bool = cd_pct <= 0.0
			bar.value = 100.0 if is_ready else (1.0 - cd_pct) * 100.0
			var cd_color: Color = CD_COLOR_READY if is_ready else CD_COLOR_CHARGING
			_apply_bar_style(bar, BAR_BG, cd_color, 2)
#endregion


#region 장비 드롭 처리
func _handle_equipment_drop(hero_index: int, target_slot: String, item_id: String, data: Dictionary) -> void:
	if data.get("source", "inventory") == "equipment":
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
		return

	var hero: Hero = party[hero_index]
	if not hero.can_equip(item_id):
		return

	var edata: Dictionary = DataManager.get_equipment(item_id)
	var eslot: String = edata.get("slot", "")
	if eslot.is_empty():
		return

	if eslot in ["accessory", "acc", "acc1", "acc2"]:
		if target_slot not in ["acc1", "acc2"]:
			return
	elif eslot != target_slot:
		return

	if InventoryManager and InventoryManager.equip_item(hero, item_id, target_slot):
		update_display()
		equipment_dropped.emit(hero_index, item_id)
#endregion


#region 카드 애니메이션
func _find_card_by_hero_id(hero_id: String) -> HeroCard:
	for card in hero_cards:
		if card.hero_id == hero_id:
			return card
	return null


func _on_hero_attacked(hero_id: String) -> void:
	var card := _find_card_by_hero_id(hero_id)
	if card and is_instance_valid(card.panel) and not card.is_hovered:
		var panel := card.panel
		var original_y := panel.position.y
		var tween := create_tween()
		tween.tween_property(panel, "position:y", original_y - 15, 0.1).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "position:y", original_y, 0.15).set_ease(Tween.EASE_IN)


func _on_hero_damaged(hero_id: String) -> void:
	var card := _find_card_by_hero_id(hero_id)
	if card and is_instance_valid(card.panel) and not card.is_hovered:
		var panel := card.panel
		var ox := panel.position.x
		var tween := create_tween()
		tween.tween_property(panel, "position:x", ox + 4, 0.03)
		tween.tween_property(panel, "position:x", ox - 4, 0.03)
		tween.tween_property(panel, "position:x", ox + 3, 0.03)
		tween.tween_property(panel, "position:x", ox - 3, 0.03)
		tween.tween_property(panel, "position:x", ox + 2, 0.03)
		tween.tween_property(panel, "position:x", ox, 0.03)
#endregion


#region 필드 힐
func _on_card_gui_input(event: InputEvent, card: HeroCard) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_field_heal(card)


func _try_field_heal(card: HeroCard) -> void:
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if card.hero_index >= party.size():
		return

	var target: Hero = party[card.hero_index]
	if target == null or target.is_dead:
		return
	if target.current_hp >= target.get_max_hp():
		return

	var healer := _find_available_healer()
	if healer == null:
		return

	_execute_field_heal(healer, target)


func _find_available_healer() -> Hero:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		if hero == null or hero.is_dead:
			continue
		if hero.class_id != "cleric":
			continue
		if CooldownManager and not CooldownManager.is_skill_ready(hero.id, "heal"):
			continue
		return hero
	return null


func _execute_field_heal(healer: Hero, target: Hero) -> void:
	var skill_data: Dictionary = DataManager.get_skill("heal")
	var base_value: int = int(skill_data.get("base_damage", 25))
	var scaling: float = skill_data.get("scaling", 1.2)
	var int_stat: int = healer.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	var actual_heal := target.heal(heal_amount)

	if CooldownManager:
		CooldownManager.start_cooldown(healer.id, "heal")
	if SoundManager:
		SoundManager.play_heal()

	update_display()

	if BattleManager:
		BattleManager.battle_log_received.emit(
			"[필드] %s → %s HP +%d" % [healer.hero_name, target.hero_name, actual_heal],
			Color.LIGHT_GREEN
		)
#endregion


#region 유틸리티
func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
	return Color.WHITE
#endregion
