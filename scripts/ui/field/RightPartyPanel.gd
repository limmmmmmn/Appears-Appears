extends PanelContainer
class_name RightPartyPanel
## 우측 파티 패널 - 정보 + 장비 목록
## 레이아웃: 이름+HP바, ATB바들, 장비목록(6줄)

const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# 색상
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)

# 시그널
signal equipment_dropped(hero_index: int, item_id: String)

# 슬롯 데이터
class HeroSlotUI:
	var container: VBoxContainer  # 전체 컨테이너
	var info_section: VBoxContainer  # 정보 섹션
	var name_hp_row: HBoxContainer  # 이름 + HP바
	var name_label: Label
	var hp_bar: ProgressBar
	var hp_label: Label  # HP 텍스트 (바 위에)
	var atb_rows: VBoxContainer  # ATB/스킬 바들
	var basic_atb_row: HBoxContainer  # 공격 ATB
	var basic_atb_label: Label
	var basic_atb_bar: ProgressBar
	var skill_rows: Dictionary = {}  # skill_id -> {row: HBoxContainer, bar: ProgressBar, label: Label}
	var equip_section: VBoxContainer  # 장비 섹션
	var equip_rows: Dictionary = {}  # slot_name -> HBoxContainer
	var drop_target: _EquipDropTarget  # 드롭 타겟
	var hero_index: int = -1
	var hero_id: String = ""

var hero_slots: Array[HeroSlotUI] = []
var main_vbox: VBoxContainer


func _ready() -> void:
	_setup_style()
	_build_ui()
	_connect_signals()
	update_display()


func _setup_style() -> void:
	# 패널 스타일
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.35, 0.5, 1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)


func _build_ui() -> void:
	# 기존 자식 제거
	for child in get_children():
		child.queue_free()

	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# 4명의 파티원 슬롯 생성
	for i in range(4):
		var slot := _create_hero_slot(i)
		hero_slots.append(slot)
		main_vbox.add_child(slot.container)


func _create_hero_slot(index: int) -> HeroSlotUI:
	var slot := HeroSlotUI.new()
	slot.hero_index = index

	# 전체 컨테이너
	slot.container = VBoxContainer.new()
	slot.container.add_theme_constant_override("separation", 2)
	slot.container.visible = false

	# 드롭 타겟 (전체 영역을 덮음)
	slot.drop_target = _EquipDropTarget.new()
	slot.drop_target.hero_index = index
	slot.drop_target.panel_ref = self
	slot.container.add_child(slot.drop_target)

	# === 정보 섹션 ===
	slot.info_section = VBoxContainer.new()
	slot.info_section.add_theme_constant_override("separation", 1)
	slot.info_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.drop_target.add_child(slot.info_section)

	# 이름 + HP바 행
	slot.name_hp_row = HBoxContainer.new()
	slot.name_hp_row.add_theme_constant_override("separation", 4)
	slot.name_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.info_section.add_child(slot.name_hp_row)

	# 이름 라벨 (큰 글씨)
	slot.name_label = Label.new()
	slot.name_label.text = "영웅"
	slot.name_label.add_theme_font_size_override("font_size", 11)
	slot.name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	slot.name_label.custom_minimum_size.x = 50
	slot.name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.name_hp_row.add_child(slot.name_label)

	# HP바 컨테이너
	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(60, 12)
	hp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.name_hp_row.add_child(hp_container)

	# HP바
	slot.hp_bar = ProgressBar.new()
	slot.hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.hp_bar.max_value = 100.0
	slot.hp_bar.value = 100.0
	slot.hp_bar.show_percentage = false
	slot.hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_hp_bar(slot.hp_bar)
	hp_container.add_child(slot.hp_bar)

	# HP 텍스트 (바 위에)
	slot.hp_label = Label.new()
	slot.hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.hp_label.add_theme_font_size_override("font_size", 8)
	slot.hp_label.add_theme_color_override("font_color", Color.WHITE)
	slot.hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	slot.hp_label.add_theme_constant_override("outline_size", 2)
	slot.hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_container.add_child(slot.hp_label)

	# === ATB 바들 ===
	slot.atb_rows = VBoxContainer.new()
	slot.atb_rows.add_theme_constant_override("separation", 1)
	slot.atb_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.info_section.add_child(slot.atb_rows)

	# 기본 공격 ATB 행
	slot.basic_atb_row = _create_atb_row("공격")
	slot.basic_atb_label = slot.basic_atb_row.get_node("Label")
	slot.basic_atb_bar = slot.basic_atb_row.get_node("Bar")
	slot.atb_rows.add_child(slot.basic_atb_row)

	# 스킬 쿨다운 행들은 update_display에서 동적으로 추가

	# === 장비 섹션 ===
	slot.equip_section = VBoxContainer.new()
	slot.equip_section.add_theme_constant_override("separation", 0)
	slot.equip_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.drop_target.add_child(slot.equip_section)

	# 구분선
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.equip_section.add_child(sep)

	# 6개 장비 슬롯 행 생성
	for slot_name in SLOT_ORDER:
		var row := _create_equip_row(slot_name)
		slot.equip_section.add_child(row)
		slot.equip_rows[slot_name] = row

	return slot


func _create_atb_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 라벨
	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	label.custom_minimum_size.x = 30
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	# ATB 바
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(80, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_atb_bar(bar, false)
	row.add_child(bar)

	return row


func _create_equip_row(slot_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 아이콘
	var icon_lbl := Label.new()
	icon_lbl.name = "Icon"
	icon_lbl.text = SLOT_ICONS.get(slot_name, "?")
	icon_lbl.add_theme_font_size_override("font_size", 9)
	icon_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	icon_lbl.custom_minimum_size.x = 14
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_lbl)

	# 이름
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = "-"
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	name_lbl.custom_minimum_size.x = 70
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	return row


func _style_hp_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.1, 0.1)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_COLOR_HIGH
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)


func _style_atb_bar(bar: ProgressBar, is_ready: bool) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.2) if is_ready else Color(0.3, 0.7, 1.0)
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)


func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(update_display):
			PartyManager.party_changed.connect(update_display)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(update_display):
				BattleManager.party_hp_changed.connect(update_display)

	if ATBManager and ATBManager.has_signal("atb_updated"):
		if not ATBManager.atb_updated.is_connected(_on_atb_updated):
			ATBManager.atb_updated.connect(_on_atb_updated)


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(hero_slots.size()):
		var slot := hero_slots[i]

		if i < party.size() and party[i] != null:
			var hero: Hero = party[i]
			slot.container.visible = true
			slot.hero_id = hero.id

			# 이름 업데이트
			slot.name_label.text = hero.hero_name

			# HP 업데이트
			var max_hp := hero.get_max_hp()
			var hp_percent: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
			slot.hp_bar.value = hp_percent * 100.0
			slot.hp_label.text = "%d/%d" % [hero.current_hp, max_hp]
			_update_hp_bar_color(slot, hp_percent)

			# 장비 목록 업데이트
			_update_equip_list(slot, hero)

			# 스킬 ATB 바들 업데이트
			_update_skill_atb_bars(slot, hero)
		else:
			slot.container.visible = false


func _update_hp_bar_color(slot: HeroSlotUI, hp_percent: float) -> void:
	var fill := StyleBoxFlat.new()
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2

	if hp_percent <= 0.25:
		fill.bg_color = HP_COLOR_LOW
	elif hp_percent <= 0.5:
		fill.bg_color = HP_COLOR_MID
	else:
		fill.bg_color = HP_COLOR_HIGH

	slot.hp_bar.add_theme_stylebox_override("fill", fill)


func _update_equip_list(slot: HeroSlotUI, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var row: HBoxContainer = slot.equip_rows.get(slot_name)
		if not row:
			continue

		var icon_lbl: Label = row.get_node_or_null("Icon")
		var name_lbl: Label = row.get_node_or_null("Name")
		if not icon_lbl or not name_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if equip_id.is_empty():
			icon_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			name_lbl.text = "-"
			name_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var rarity: String = equip_data.get("rarity", "common")
			var rarity_color: Color = _get_rarity_color(rarity)

			icon_lbl.add_theme_color_override("font_color", rarity_color)
			name_lbl.text = equip_data.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", rarity_color)


func _update_skill_atb_bars(slot: HeroSlotUI, hero: Hero) -> void:
	## 스킬 쿨다운 바 생성/업데이트
	var skills: Array = hero.get_available_skills()

	# 기존에 없는 스킬 행 추가
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue

		if not slot.skill_rows.has(skill_id):
			var skill_data: Dictionary = DataManager.get_skill(skill_id)
			var skill_name: String = skill_data.get("name", skill_id)

			var row := _create_cooldown_row(skill_name)
			slot.atb_rows.add_child(row)
			slot.skill_rows[skill_id] = {
				"row": row,
				"bar": row.get_node("Bar"),
				"label": row.get_node("Label")
			}

	# 더 이상 없는 스킬 행 제거
	var to_remove: Array = []
	for skill_id in slot.skill_rows.keys():
		if skill_id not in skills:
			to_remove.append(skill_id)

	for skill_id in to_remove:
		var row_data: Dictionary = slot.skill_rows[skill_id]
		row_data["row"].queue_free()
		slot.skill_rows.erase(skill_id)


func _create_cooldown_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 라벨 (스킬 이름)
	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	label.custom_minimum_size.x = 30
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	# 쿨다운 바 (역방향: 100% = 쿨다운 중, 0% = 준비완료)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(80, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_cooldown_bar(bar, true)
	row.add_child(bar)

	return row


func _style_cooldown_bar(bar: ProgressBar, is_ready: bool) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	# 준비 완료면 초록색, 쿨다운 중이면 회색
	fill.bg_color = Color(0.3, 0.8, 0.3) if is_ready else Color(0.4, 0.4, 0.5)
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)


func _on_atb_updated() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(hero_slots.size()):
		if i >= party.size() or party[i] == null:
			continue

		var slot := hero_slots[i]
		var hero: Hero = party[i]

		# 기본 공격 ATB 업데이트
		var atb_percent: float = ATBManager.get_hero_atb_percent(hero.id) if ATBManager else 0.0
		slot.basic_atb_bar.value = atb_percent * 100.0
		_style_atb_bar(slot.basic_atb_bar, atb_percent >= 1.0)

		# 스킬 쿨다운 업데이트
		for skill_id in slot.skill_rows.keys():
			var row_data: Dictionary = slot.skill_rows[skill_id]
			var bar: ProgressBar = row_data["bar"]

			# 쿨다운 퍼센트 가져오기 (0 = 준비완료, 1 = 막 사용)
			var cooldown_percent: float = CooldownManager.get_cooldown_percent(hero.id, skill_id) if CooldownManager else 0.0
			var is_ready: bool = cooldown_percent <= 0.0

			# 바 업데이트 (준비 완료면 100%, 쿨다운 중이면 남은 비율)
			bar.value = 100.0 if is_ready else (1.0 - cooldown_percent) * 100.0
			_style_cooldown_bar(bar, is_ready)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
	return Color.WHITE


#region 장비 드래그 앤 드롭
func _on_equipment_dropped(hero_index: int, item_id: String) -> void:
	## 장비가 드롭되었을 때 호출
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size():
		return

	var hero: Hero = party[hero_index]
	if hero == null:
		return

	# 장비 가능 여부 확인
	if not hero.can_equip(item_id):
		_show_equip_fail_feedback(hero_index)
		return

	# 장비 장착 시도
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_slot: String = item_data.get("slot", "")

	# 악세사리 슬롯 처리
	var target_slot: String = item_slot
	if item_slot in ["accessory", "acc", "acc1", "acc2"]:
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"

	if InventoryManager.equip_item(hero, item_id, target_slot):
		_show_equip_success_feedback(hero_index)
		update_display()
		equipment_dropped.emit(hero_index, item_id)
	else:
		_show_equip_fail_feedback(hero_index)


func _show_equip_success_feedback(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= hero_slots.size():
		return
	var slot := hero_slots[hero_index]
	if not slot.name_label:
		return

	var tween := create_tween()
	tween.tween_property(slot.name_label, "modulate", Color(0.5, 1.0, 0.5), 0.1)
	tween.tween_property(slot.name_label, "modulate", Color.WHITE, 0.15)


func _show_equip_fail_feedback(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= hero_slots.size():
		return
	var slot := hero_slots[hero_index]
	if not slot.name_label:
		return

	var tween := create_tween()
	tween.tween_property(slot.name_label, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	tween.tween_property(slot.name_label, "modulate", Color.WHITE, 0.15)


## 드롭 타겟 컨트롤
class _EquipDropTarget extends Control:
	var hero_index: int = -1
	var panel_ref: RightPartyPanel = null
	var highlight: ColorRect = null

	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL

		highlight = ColorRect.new()
		highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
		highlight.color = Color(0.3, 0.8, 0.3, 0.3)
		highlight.visible = false
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(highlight)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		if data.get("type") != "equipment":
			return false

		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size():
			return false

		var hero: Hero = party[hero_index]
		if hero == null:
			return false

		var item_id: String = data.get("item_id", "")
		var can_equip: bool = hero.can_equip(item_id)

		if highlight:
			highlight.visible = true
			highlight.color = Color(0.3, 0.8, 0.3, 0.3) if can_equip else Color(0.8, 0.3, 0.3, 0.3)

		return can_equip

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if highlight:
			highlight.visible = false

		if not data is Dictionary:
			return

		var item_id: String = data.get("item_id", "")
		if item_id.is_empty():
			return

		if panel_ref:
			panel_ref._on_equipment_dropped(hero_index, item_id)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			if highlight:
				highlight.visible = false
#endregion
