extends CanvasLayer
class_name PauseMenu
## 일시정지 메뉴 UI
## - 파티 상태 (상세 스탯)
## - 장비 장착
## - 룬 장착
## - 게임 설정

signal resume_pressed
signal title_pressed
signal quit_pressed

var current_tab: int = 0
var is_showing: bool = false

# UI 참조
var tab_buttons: Array[Button] = []
var content_container: Control = null
var main_control: Control = null

# 장비/룬 선택 상태
var selected_hero: Hero = null
var selected_slot: String = ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func show_menu() -> void:
	if is_showing:
		return
	
	is_showing = true
	visible = true
	get_tree().paused = true
	
	_create_ui()


func hide_menu() -> void:
	if not is_showing:
		return
	
	is_showing = false
	visible = false
	get_tree().paused = false
	
	# UI 정리
	if main_control:
		main_control.queue_free()
		main_control = null
	tab_buttons.clear()
	content_container = null


func is_visible_menu() -> bool:
	return is_showing


func _create_ui() -> void:
	# 기존 UI 정리
	for child in get_children():
		child.queue_free()
	tab_buttons.clear()
	
	main_control = Control.new()
	main_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_control)
	
	# 어두운 배경
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	main_control.add_child(bg)
	
	# 메인 컨테이너
	var main_container := VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("separation", 0)
	main_control.add_child(main_container)
	
	# 상단: 타이틀 + 탭
	_create_header(main_container)
	
	# 중앙: 콘텐츠 영역
	content_container = Control.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(content_container)
	
	# 하단: 버튼
	_create_footer(main_container)
	
	# 기본 탭 표시
	_switch_tab(0)


func _create_header(parent_node: VBoxContainer) -> void:
	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	header_style.border_width_bottom = 1
	header_style.border_color = Color(0.3, 0.3, 0.35)
	header_style.content_margin_left = 12
	header_style.content_margin_right = 12
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", header_style)
	parent_node.add_child(header)
	
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 20)
	header.add_child(header_hbox)
	
	# 타이틀
	var title := Label.new()
	title.text = "[ 메뉴 ]"
	title.add_theme_font_size_override("font_size", 14)
	header_hbox.add_child(title)
	
	# 탭 버튼들
	var tab_container := HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 6)
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(tab_container)
	
	var tabs := ["파티 상태", "장비", "룬", "설정"]
	for i in range(tabs.size()):
		var tab_btn := Button.new()
		tab_btn.text = tabs[i]
		tab_btn.custom_minimum_size = Vector2(90, 26)
		tab_btn.add_theme_font_size_override("font_size", 11)
		tab_btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_container.add_child(tab_btn)
		tab_buttons.append(tab_btn)
	
	# ESC 힌트
	var hint := Label.new()
	hint.text = "[ESC] 닫기"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	header_hbox.add_child(hint)


func _create_footer(parent_node: VBoxContainer) -> void:
	var footer := PanelContainer.new()
	var footer_style := StyleBoxFlat.new()
	footer_style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	footer_style.border_width_top = 1
	footer_style.border_color = Color(0.3, 0.3, 0.35)
	footer_style.content_margin_left = 12
	footer_style.content_margin_right = 12
	footer_style.content_margin_top = 10
	footer_style.content_margin_bottom = 10
	footer.add_theme_stylebox_override("panel", footer_style)
	parent_node.add_child(footer)
	
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)
	footer_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(footer_hbox)
	
	var resume_btn := _create_button("게임 계속", Color(0.2, 0.5, 0.3))
	resume_btn.pressed.connect(_on_resume)
	footer_hbox.add_child(resume_btn)
	
	var title_btn := _create_button("타이틀로", Color(0.4, 0.35, 0.2))
	title_btn.pressed.connect(_on_title)
	footer_hbox.add_child(title_btn)
	
	var quit_btn := _create_button("게임 종료", Color(0.5, 0.2, 0.2))
	quit_btn.pressed.connect(_on_quit)
	footer_hbox.add_child(quit_btn)


func _create_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(110, 32)
	btn.add_theme_font_size_override("font_size", 12)
	
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style)
	
	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed := style.duplicate()
	pressed.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	return btn


func _on_tab_pressed(tab_index: int) -> void:
	_switch_tab(tab_index)


func _switch_tab(tab_index: int) -> void:
	current_tab = tab_index
	
	# 탭 버튼 스타일 업데이트
	for i in range(tab_buttons.size()):
		var btn := tab_buttons[i]
		if i == tab_index:
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.modulate = Color(1.2, 1.2, 1.2)
		else:
			btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			btn.modulate = Color.WHITE
	
	# 콘텐츠 교체
	if content_container:
		for child in content_container.get_children():
			child.queue_free()
	
	match tab_index:
		0:
			_create_party_content()
		1:
			_create_equipment_content()
		2:
			_create_rune_content()
		3:
			_create_settings_content()


#region 파티 상태 탭
func _create_party_content() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(scroll)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)
	
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(main_hbox)
	
	# 각 파티원 카드
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		var card := _create_hero_card(hero)
		main_hbox.add_child(card)


func _create_hero_card(hero: Hero) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(120, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)
	
	# 헤더: 페이스 + 이름
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(32, 32)
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if SpriteManager:
		face.texture = SpriteManager.get_hero_face_sprite(hero.id)
	header.add_child(face)
	
	var name_vbox := VBoxContainer.new()
	name_vbox.add_theme_constant_override("separation", 0)
	header.add_child(name_vbox)
	
	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_vbox.add_child(name_label)
	
	var class_label := Label.new()
	class_label.text = "Lv.%d %s" % [hero.level, hero.class_id]
	class_label.add_theme_font_size_override("font_size", 9)
	class_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	name_vbox.add_child(class_label)
	
	# 구분선
	vbox.add_child(HSeparator.new())
	
	# HP/MP
	_add_bar_row(vbox, "HP", hero.current_hp, hero.get_max_hp(), Color(0.2, 0.75, 0.2))
	_add_bar_row(vbox, "MP", hero.current_mp, hero.get_max_mp(), Color(0.3, 0.4, 0.9))
	_add_bar_row(vbox, "EXP", hero.exp, hero.exp_to_next, Color(0.8, 0.7, 0.2))
	
	# 구분선
	vbox.add_child(HSeparator.new())
	
	# 기본 스탯
	_add_stat_row(vbox, "STR", hero.get_str())
	_add_stat_row(vbox, "DEF", hero.get_def())
	_add_stat_row(vbox, "INT", hero.get_int())
	_add_stat_row(vbox, "SPD", hero.get_spd())
	_add_stat_row(vbox, "LUK", hero.get_luk())
	
	# 구분선
	vbox.add_child(HSeparator.new())
	
	# 파생 스탯
	_add_stat_row(vbox, "ATK", hero.get_atk(), Color(1.0, 0.6, 0.6))
	_add_stat_row(vbox, "P.DEF", hero.get_p_def(), Color(0.6, 0.8, 1.0))
	_add_stat_row(vbox, "M.DEF", hero.get_m_def(), Color(0.8, 0.6, 1.0))
	
	return card


func _add_bar_row(parent_vbox: VBoxContainer, label_text: String, current: int, max_val: int, color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent_vbox.add_child(hbox)
	
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 28
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	hbox.add_child(label)
	
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(50, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = max(max_val, 1)
	bar.value = current
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)
	hbox.add_child(bar)
	
	var value_label := Label.new()
	value_label.text = "%d/%d" % [current, max_val]
	value_label.custom_minimum_size.x = 45
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 8)
	value_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	hbox.add_child(value_label)


func _add_stat_row(parent_vbox: VBoxContainer, stat_name: String, value: int, color: Color = Color.WHITE) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent_vbox.add_child(hbox)
	
	var name_label := Label.new()
	name_label.text = stat_name
	name_label.custom_minimum_size.x = 40
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hbox.add_child(name_label)
	
	var value_label := Label.new()
	value_label.text = str(value)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", color)
	hbox.add_child(value_label)
#endregion


#region 장비 탭
func _create_equipment_content() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(main_hbox)

	# 각 파티원 장비 카드
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		var card := _create_equipment_card(hero)
		main_hbox.add_child(card)


func _create_equipment_card(hero: Hero) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 헤더: 이름
	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	vbox.add_child(HSeparator.new())

	# 장비 슬롯들
	var slots := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]
	var slot_names := {"main_hand": "주무기", "off_hand": "보조", "head": "머리", "body": "몸통", "acc1": "악세1", "acc2": "악세2"}

	for slot in slots:
		var equip_id: String = hero.equipment.get(slot, "")
		var equip_data: Dictionary = DataManager.get_equipment(equip_id) if not equip_id.is_empty() else {}

		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(0, 28)
		slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if equip_data.is_empty():
			slot_btn.text = "[%s] -" % slot_names[slot]
			slot_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			var rarity: String = equip_data.get("rarity", "common")
			var color := _get_rarity_color(rarity)
			slot_btn.text = "[%s] %s" % [slot_names[slot], equip_data.get("name", "?")]
			slot_btn.add_theme_color_override("font_color", color)

		slot_btn.add_theme_font_size_override("font_size", 9)
		slot_btn.pressed.connect(_on_equipment_slot_pressed.bind(hero, slot))
		vbox.add_child(slot_btn)

	return card


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.8, 0.8, 0.8)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
		_: return Color.WHITE


func _on_equipment_slot_pressed(hero: Hero, slot: String) -> void:
	selected_hero = hero
	selected_slot = slot
	_show_equipment_selection_popup(hero, slot)


func _show_equipment_selection_popup(hero: Hero, slot: String) -> void:
	# 기존 팝업 제거
	var existing := main_control.get_node_or_null("EquipPopup")
	if existing:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "EquipPopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(280, 320)

	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.12, 0.98)
	popup_style.border_width_left = 2
	popup_style.border_width_right = 2
	popup_style.border_width_top = 2
	popup_style.border_width_bottom = 2
	popup_style.border_color = Color(0.4, 0.4, 0.5)
	popup_style.corner_radius_top_left = 8
	popup_style.corner_radius_top_right = 8
	popup_style.corner_radius_bottom_left = 8
	popup_style.corner_radius_bottom_right = 8
	popup_style.content_margin_left = 12
	popup_style.content_margin_right = 12
	popup_style.content_margin_top = 12
	popup_style.content_margin_bottom = 12
	popup.add_theme_stylebox_override("panel", popup_style)
	main_control.add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	# 제목
	var title := Label.new()
	var slot_names := {"main_hand": "주무기", "off_hand": "보조", "head": "머리", "body": "몸통", "acc1": "악세1", "acc2": "악세2"}
	title.text = "%s - %s 선택" % [hero.hero_name, slot_names.get(slot, slot)]
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# 장착 해제 버튼
	var unequip_btn := Button.new()
	unequip_btn.text = "[ 장착 해제 ]"
	unequip_btn.add_theme_font_size_override("font_size", 10)
	unequip_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
	unequip_btn.pressed.connect(_on_equip_selected.bind(hero, slot, ""))
	vbox.add_child(unequip_btn)

	vbox.add_child(HSeparator.new())

	# 스크롤 영역
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var items_vbox := VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 4)
	items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(items_vbox)

	# 인벤토리에서 장착 가능한 아이템 목록
	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}
	var slot_type := _get_slot_type(slot)

	for item_id in inventory:
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if equip_data.is_empty():
			continue

		var item_slot: String = equip_data.get("slot", "")
		if item_slot != slot_type:
			continue

		if not hero.can_equip(item_id):
			continue

		var qty: int = inventory[item_id]
		var rarity: String = equip_data.get("rarity", "common")
		var color := _get_rarity_color(rarity)

		var item_btn := Button.new()
		item_btn.text = "%s x%d" % [equip_data.get("name", item_id), qty]
		item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_btn.add_theme_font_size_override("font_size", 10)
		item_btn.add_theme_color_override("font_color", color)
		item_btn.pressed.connect(_on_equip_selected.bind(hero, slot, item_id))
		items_vbox.add_child(item_btn)

		# 스탯 미리보기
		var stats: Dictionary = equip_data.get("stats", {})
		if not stats.is_empty():
			var stat_text := "  "
			for stat_name in stats:
				stat_text += "%s+%d " % [stat_name.to_upper(), stats[stat_name]]
			var stat_label := Label.new()
			stat_label.text = stat_text
			stat_label.add_theme_font_size_override("font_size", 8)
			stat_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			items_vbox.add_child(stat_label)

	# 닫기 버튼
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)


func _get_slot_type(slot: String) -> String:
	match slot:
		"main_hand": return "weapon"
		"off_hand": return "shield"
		"head": return "head"
		"body": return "body"
		"acc1", "acc2": return "accessory"
		_: return ""


func _on_equip_selected(hero: Hero, slot: String, item_id: String) -> void:
	# 기존 장비 인벤토리로 반환
	var old_equip: String = hero.equipment.get(slot, "")
	if not old_equip.is_empty():
		InventoryManager.add_item(old_equip)

	# 새 장비 장착
	if not item_id.is_empty():
		InventoryManager.remove_item(item_id)
		hero.equip_item(item_id, slot)
	else:
		hero.unequip_slot(slot)

	# 팝업 닫기 및 새로고침
	var popup := main_control.get_node_or_null("EquipPopup")
	if popup:
		popup.queue_free()

	_switch_tab(1)  # 장비 탭 새로고침
#endregion


#region 룬 탭
func _create_rune_content() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(main_hbox)

	# 각 파티원 룬 카드
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		var card := _create_rune_card(hero)
		main_hbox.add_child(card)


func _create_rune_card(hero: Hero) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# 헤더: 이름
	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	vbox.add_child(HSeparator.new())

	# 현재 장착 룬
	var rune_data: Dictionary = hero.get_equipped_rune()
	var trait_data: Dictionary = {}
	if not rune_data.is_empty():
		trait_data = DataManager.get_rune_trait(hero.equipped_rune_id)

	var rune_container := VBoxContainer.new()
	rune_container.add_theme_constant_override("separation", 2)
	vbox.add_child(rune_container)

	if rune_data.is_empty():
		var empty_label := Label.new()
		empty_label.text = "[ 룬 없음 ]"
		empty_label.add_theme_font_size_override("font_size", 10)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rune_container.add_child(empty_label)
	else:
		# 룬 이름
		var rune_hbox := HBoxContainer.new()
		rune_hbox.add_theme_constant_override("separation", 4)
		rune_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		rune_container.add_child(rune_hbox)

		var rune_icon := Label.new()
		rune_icon.text = rune_data.get("icon", "")
		rune_icon.add_theme_font_size_override("font_size", 14)
		rune_hbox.add_child(rune_icon)

		var rune_name := Label.new()
		rune_name.text = rune_data.get("name", "")
		rune_name.add_theme_font_size_override("font_size", 10)
		rune_name.add_theme_color_override("font_color", _get_rarity_color(rune_data.get("rarity", "common")))
		rune_hbox.add_child(rune_name)

		# 특성 정보
		if not trait_data.is_empty():
			var trait_hbox := HBoxContainer.new()
			trait_hbox.add_theme_constant_override("separation", 4)
			trait_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			rune_container.add_child(trait_hbox)

			var trait_icon := Label.new()
			trait_icon.text = trait_data.get("icon", "")
			trait_icon.add_theme_font_size_override("font_size", 10)
			trait_hbox.add_child(trait_icon)

			var trait_name := Label.new()
			trait_name.text = trait_data.get("name", "")
			trait_name.add_theme_font_size_override("font_size", 9)
			trait_name.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
			trait_hbox.add_child(trait_name)

			var desc_label := Label.new()
			desc_label.text = trait_data.get("description", "")
			desc_label.add_theme_font_size_override("font_size", 8)
			desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			rune_container.add_child(desc_label)

	vbox.add_child(HSeparator.new())

	# 변경 버튼
	var change_btn := Button.new()
	change_btn.text = "룬 변경"
	change_btn.add_theme_font_size_override("font_size", 10)
	change_btn.pressed.connect(_on_rune_slot_pressed.bind(hero))
	vbox.add_child(change_btn)

	return card


func _on_rune_slot_pressed(hero: Hero) -> void:
	selected_hero = hero
	_show_rune_selection_popup(hero)


func _show_rune_selection_popup(hero: Hero) -> void:
	# 기존 팝업 제거
	var existing := main_control.get_node_or_null("RunePopup")
	if existing:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "RunePopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(300, 350)

	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.12, 0.98)
	popup_style.border_width_left = 2
	popup_style.border_width_right = 2
	popup_style.border_width_top = 2
	popup_style.border_width_bottom = 2
	popup_style.border_color = Color(0.5, 0.4, 0.6)
	popup_style.corner_radius_top_left = 8
	popup_style.corner_radius_top_right = 8
	popup_style.corner_radius_bottom_left = 8
	popup_style.corner_radius_bottom_right = 8
	popup_style.content_margin_left = 12
	popup_style.content_margin_right = 12
	popup_style.content_margin_top = 12
	popup_style.content_margin_bottom = 12
	popup.add_theme_stylebox_override("panel", popup_style)
	main_control.add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "%s - 룬 선택" % hero.hero_name
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# 장착 해제 버튼
	var unequip_btn := Button.new()
	unequip_btn.text = "[ 룬 해제 ]"
	unequip_btn.add_theme_font_size_override("font_size", 10)
	unequip_btn.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
	unequip_btn.pressed.connect(_on_rune_selected.bind(hero, ""))
	vbox.add_child(unequip_btn)

	vbox.add_child(HSeparator.new())

	# 스크롤 영역
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var items_vbox := VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 6)
	items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(items_vbox)

	# 인벤토리에서 룬 목록
	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}

	for item_id in inventory:
		var rune_data: Dictionary = DataManager.get_rune(item_id)
		if rune_data.is_empty():
			continue

		var trait_data: Dictionary = DataManager.get_rune_trait(item_id)
		var qty: int = inventory[item_id]
		var rarity: String = rune_data.get("rarity", "common")
		var color := _get_rarity_color(rarity)

		var rune_container := VBoxContainer.new()
		rune_container.add_theme_constant_override("separation", 2)
		items_vbox.add_child(rune_container)

		var item_btn := Button.new()
		item_btn.text = "%s %s x%d" % [rune_data.get("icon", ""), rune_data.get("name", item_id), qty]
		item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_btn.add_theme_font_size_override("font_size", 10)
		item_btn.add_theme_color_override("font_color", color)
		item_btn.pressed.connect(_on_rune_selected.bind(hero, item_id))
		rune_container.add_child(item_btn)

		# 특성 미리보기
		if not trait_data.is_empty():
			var trait_label := Label.new()
			trait_label.text = "  %s %s: %s" % [trait_data.get("icon", ""), trait_data.get("name", ""), trait_data.get("description", "")]
			trait_label.add_theme_font_size_override("font_size", 8)
			trait_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
			rune_container.add_child(trait_label)

	# 닫기 버튼
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)


func _on_rune_selected(hero: Hero, rune_id: String) -> void:
	# 기존 룬 인벤토리로 반환
	var old_rune: String = hero.equipped_rune_id
	if not old_rune.is_empty():
		InventoryManager.add_item(old_rune)

	# 새 룬 장착
	if not rune_id.is_empty():
		InventoryManager.remove_item(rune_id)
		hero.equip_rune(rune_id)
	else:
		hero.unequip_rune()

	# FieldHUD 특성 표시 갱신
	var field_hud = get_tree().get_first_node_in_group("field_hud")
	if field_hud and field_hud.has_method("refresh_traits"):
		field_hud.refresh_traits()

	# 팝업 닫기 및 새로고침
	var popup := main_control.get_node_or_null("RunePopup")
	if popup:
		popup.queue_free()

	_switch_tab(2)  # 룬 탭 새로고침
#endregion


#region 설정 탭
func _create_settings_content() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center)
	
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# 전투 속도
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 12)
	vbox.add_child(speed_row)
	
	var speed_label := Label.new()
	speed_label.text = "전투 속도:"
	speed_label.custom_minimum_size.x = 90
	speed_label.add_theme_font_size_override("font_size", 12)
	speed_row.add_child(speed_label)
	
	var current_speed: float = BattleManager.battle_speed if BattleManager else 1.0
	for spd in [1, 2, 4]:
		var btn := Button.new()
		btn.text = "x%d" % spd
		btn.custom_minimum_size = Vector2(50, 28)
		btn.add_theme_font_size_override("font_size", 11)
		if int(current_speed) == spd:
			btn.modulate = Color(1.3, 1.3, 0.8)
		btn.pressed.connect(_on_speed_selected.bind(spd))
		speed_row.add_child(btn)
	
	# 게임 정보
	vbox.add_child(HSeparator.new())
	
	var info_label := Label.new()
	info_label.text = "HyperQuest v0.1"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)


func _on_speed_selected(speed: int) -> void:
	if BattleManager:
		BattleManager.set_battle_speed(float(speed))
	_switch_tab(1)
#endregion


#region 버튼 핸들러
func _on_resume() -> void:
	hide_menu()
	resume_pressed.emit()


func _on_title() -> void:
	hide_menu()
	title_pressed.emit()


func _on_quit() -> void:
	hide_menu()
	quit_pressed.emit()
#endregion


# 하위 호환성을 위한 별칭 (CanvasLayer와 충돌 방지를 위해 다른 이름 사용)
func open(p_parent: Node) -> void:
	if not is_inside_tree():
		p_parent.add_child(self)
	show_menu()


func close() -> void:
	hide_menu()


func is_open() -> bool:
	return is_showing
