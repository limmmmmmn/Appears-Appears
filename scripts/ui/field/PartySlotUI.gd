extends PanelContainer
class_name PartySlotUI
## 개별 파티 슬롯 UI: 페이스칩, HP, ATB, 장비, 스탯패널 (MP 제거)

signal equipment_slot_clicked(slot_name: String)
signal equipment_slot_gui_input(event: InputEvent, slot_name: String)
signal stat_panel_toggled(is_open: bool)

var hero_index: int = -1
var hero: Hero = null

# UI 참조
var face_texture: TextureRect
var name_label: Label
var hp_bar: ProgressBar
var hp_label: Label
var atb_bar: ProgressBar
var equip_buttons: Dictionary = {}
var stat_toggle_btn: Button
var stat_panel: PanelContainer

# 상수
const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️", "off_hand": "🛡️", "head": "👑",
	"body": "👕", "acc1": "💍", "acc2": "💎"
}

const ITEM_ICONS: Dictionary = {
	"weapon": "⚔️", "main_hand": "⚔️", "shield": "🛡️", "off_hand": "🛡️",
	"head": "👑", "helmet": "👑", "body": "👕", "armor": "👕",
	"accessory": "💍", "acc1": "💍", "acc2": "💎"
}

const RARITY_COLORS: Dictionary = {
	"common": Color.WHITE,
	"magic": Color(0.4, 0.6, 1.0),
	"legendary": Color(1.0, 0.7, 0.2)
}


func _init() -> void:
	custom_minimum_size = Vector2(150, 46)


func setup(index: int) -> void:
	hero_index = index
	set_meta("hero_index", index)
	
	_setup_style()
	_create_layout()
	visible = false


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	add_theme_stylebox_override("panel", style)


func _create_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	add_child(vbox)
	
	# 1행: 페이스 + 이름 + HP/ATB
	_create_header_row(vbox)
	
	# 2행: 장비 슬롯 + 스탯 토글
	_create_equipment_row(vbox)
	
	# 3행: 스탯 패널 (접힘)
	stat_panel = _create_stat_panel()
	stat_panel.visible = false
	vbox.add_child(stat_panel)


func _create_header_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	
	# 페이스칩
	face_texture = TextureRect.new()
	face_texture.custom_minimum_size = Vector2(20, 20)
	face_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.add_child(face_texture)
	
	# 이름
	name_label = Label.new()
	name_label.custom_minimum_size.x = 45
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.clip_text = true
	row.add_child(name_label)
	
	# HP/ATB 바
	var bars_vbox := VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 1)
	bars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bars_vbox)
	
	# HP
	var hp_row := _create_mini_bar("HP", Color(0.2, 0.75, 0.2))
	hp_bar = hp_row.get_node("Bar")
	hp_label = hp_row.get_node("ValueLabel")
	bars_vbox.add_child(hp_row)
	
	# ATB (공격 게이지)
	var atb_row := _create_atb_bar()
	atb_bar = atb_row.get_node("Bar")
	bars_vbox.add_child(atb_row)


func _create_mini_bar(label_text: String, color: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 14
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	hbox.add_child(label)
	
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(40, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.value = 100
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 1
	fill_style.corner_radius_top_right = 1
	fill_style.corner_radius_bottom_left = 1
	fill_style.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.12)
	bg_style.corner_radius_top_left = 1
	bg_style.corner_radius_top_right = 1
	bg_style.corner_radius_bottom_left = 1
	bg_style.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("background", bg_style)
	
	hbox.add_child(bar)
	
	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.custom_minimum_size.x = 30
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 7)
	hbox.add_child(value_label)
	
	return hbox


func _create_atb_bar() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	
	var label := Label.new()
	label.text = "⚡"
	label.custom_minimum_size.x = 14
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	hbox.add_child(label)
	
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(40, 5)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.value = 0
	bar.max_value = 100
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(1.0, 0.8, 0.2)
	fill_style.corner_radius_top_left = 1
	fill_style.corner_radius_top_right = 1
	fill_style.corner_radius_bottom_left = 1
	fill_style.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.12, 0.05)
	bg_style.corner_radius_top_left = 1
	bg_style.corner_radius_top_right = 1
	bg_style.corner_radius_bottom_left = 1
	bg_style.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("background", bg_style)
	
	hbox.add_child(bar)
	
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 30
	hbox.add_child(spacer)
	
	return hbox


func _create_equipment_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)
	
	var equip_container := HBoxContainer.new()
	equip_container.add_theme_constant_override("separation", 1)
	row.add_child(equip_container)
	
	for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
		var btn := Button.new()
		btn.name = "Equip_" + slot_name
		btn.custom_minimum_size = Vector2(18, 16)
		btn.text = SLOT_ICONS.get(slot_name, "?")
		btn.add_theme_font_size_override("font_size", 9)
		btn.tooltip_text = slot_name
		btn.set_meta("slot_name", slot_name)
		btn.gui_input.connect(_on_equip_gui_input.bind(slot_name))
		equip_container.add_child(btn)
		equip_buttons[slot_name] = btn
	
	stat_toggle_btn = Button.new()
	stat_toggle_btn.text = "▶"
	stat_toggle_btn.custom_minimum_size = Vector2(16, 16)
	stat_toggle_btn.add_theme_font_size_override("font_size", 8)
	stat_toggle_btn.tooltip_text = "스탯 보기"
	stat_toggle_btn.pressed.connect(_on_stat_toggle_pressed)
	row.add_child(stat_toggle_btn)


func _create_stat_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatPanel"
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_width_top = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	
	# 기본 스탯 1행
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	vbox.add_child(row1)
	row1.add_child(_create_stat_label("STR", "STRValue"))
	row1.add_child(_create_stat_label("DEF", "DEFValue"))
	row1.add_child(_create_stat_label("INT", "INTValue"))
	
	# 기본 스탯 2행
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	vbox.add_child(row2)
	row2.add_child(_create_stat_label("SPD", "SPDValue"))
	row2.add_child(_create_stat_label("LUK", "LUKValue"))
	
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	vbox.add_child(separator)
	
	# 파생 스탯
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	vbox.add_child(row3)
	row3.add_child(_create_stat_label("ATK", "ATKValue", Color(1.0, 0.6, 0.6)))
	row3.add_child(_create_stat_label("P.DEF", "PDEFValue", Color(0.6, 0.8, 1.0)))
	row3.add_child(_create_stat_label("M.DEF", "MDEFValue", Color(0.8, 0.6, 1.0)))
	
	# 경험치
	var exp_row := HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 4)
	vbox.add_child(exp_row)
	
	var exp_label := Label.new()
	exp_label.text = "EXP"
	exp_label.custom_minimum_size.x = 28
	exp_label.add_theme_font_size_override("font_size", 8)
	exp_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	exp_row.add_child(exp_label)
	
	var exp_value := Label.new()
	exp_value.name = "EXPValue"
	exp_value.text = "0/100"
	exp_value.add_theme_font_size_override("font_size", 8)
	exp_value.add_theme_color_override("font_color", Color.GOLD)
	exp_row.add_child(exp_value)
	
	return panel


func _create_stat_label(stat_name: String, value_name: String, color: Color = Color.WHITE) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	
	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.custom_minimum_size.x = 28
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hbox.add_child(name_lbl)
	
	var value_lbl := Label.new()
	value_lbl.name = value_name
	value_lbl.text = "0"
	value_lbl.custom_minimum_size.x = 20
	value_lbl.add_theme_font_size_override("font_size", 8)
	value_lbl.add_theme_color_override("font_color", color)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_lbl)
	
	return hbox


#region 업데이트
func update_display(new_hero: Hero) -> void:
	hero = new_hero
	if not hero:
		visible = false
		return
	
	visible = true
	name_label.text = "Lv.%d %s" % [hero.level, hero.hero_name]
	
	if SpriteManager:
		face_texture.texture = SpriteManager.get_hero_face_sprite(hero.id)
	
	_update_bars()
	_update_equipment()
	
	if stat_panel.visible:
		_update_stat_values()


func _update_bars() -> void:
	if not hero:
		return
	
	var max_hp := hero.get_max_hp()
	hp_bar.max_value = max_hp
	hp_bar.value = hero.current_hp
	hp_label.text = "%d/%d" % [hero.current_hp, max_hp]


func update_atb(value: float) -> void:
	if atb_bar:
		atb_bar.value = value * 100.0
		
		var fill_style: StyleBoxFlat = atb_bar.get_theme_stylebox("fill").duplicate()
		if value >= 0.9:
			fill_style.bg_color = Color(1.0, 1.0, 0.5)
		elif value >= 0.7:
			fill_style.bg_color = Color(1.0, 0.9, 0.3)
		else:
			fill_style.bg_color = Color(1.0, 0.8, 0.2)
		atb_bar.add_theme_stylebox_override("fill", fill_style)


func _update_equipment() -> void:
	if not hero:
		return
	
	for slot_name in equip_buttons:
		var btn: Button = equip_buttons[slot_name]
		var equip_id: String = hero.equipment.get(slot_name, "")
		
		if equip_id.is_empty():
			btn.text = SLOT_ICONS.get(slot_name, "?")
			btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
			btn.tooltip_text = slot_name + ": (없음)"
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var item_type: String = str(equip_data.get("slot", slot_name))
			var rarity: String = str(equip_data.get("rarity", "common"))
			var equip_name: String = str(equip_data.get("name", equip_id))
			
			btn.text = ITEM_ICONS.get(item_type, "📦")
			btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
			btn.tooltip_text = "%s: %s" % [slot_name, equip_name]


func _update_stat_values() -> void:
	if not hero or not stat_panel:
		return
	
	_set_stat_value("STRValue", hero.get_str())
	_set_stat_value("DEFValue", hero.get_def())
	_set_stat_value("INTValue", hero.get_int())
	_set_stat_value("SPDValue", hero.get_spd())
	_set_stat_value("LUKValue", hero.get_luk())
	_set_stat_value("ATKValue", hero.get_atk())
	_set_stat_value("PDEFValue", hero.get_p_def())
	_set_stat_value("MDEFValue", hero.get_m_def())
	
	var exp_label: Label = stat_panel.find_child("EXPValue", true, false)
	if exp_label:
		exp_label.text = "%d/%d" % [hero.exp, hero.exp_to_next]


func _set_stat_value(label_name: String, value: int) -> void:
	var label: Label = stat_panel.find_child(label_name, true, false)
	if label:
		label.text = str(value)
#endregion


#region 시그널 핸들러
func _on_stat_toggle_pressed() -> void:
	stat_panel.visible = not stat_panel.visible
	
	if stat_panel.visible:
		stat_toggle_btn.text = "▼"
		stat_toggle_btn.tooltip_text = "스탯 숨기기"
		_update_stat_values()
	else:
		stat_toggle_btn.text = "▶"
		stat_toggle_btn.tooltip_text = "스탯 보기"
	
	stat_panel_toggled.emit(stat_panel.visible)


func _on_equip_gui_input(event: InputEvent, slot_name: String) -> void:
	equipment_slot_gui_input.emit(event, slot_name)
#endregion


#region 외부 접근
func get_equipment_button(slot_name: String) -> Button:
	return equip_buttons.get(slot_name)


func get_equipped_item_id(slot_name: String) -> String:
	if hero:
		return hero.equipment.get(slot_name, "")
	return ""


func get_hero_id() -> String:
	if hero:
		return hero.id
	return ""


func set_highlight(enabled: bool) -> void:
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	
	if enabled:
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3, 0.7, 1.0, 0.8)
	else:
		style.border_width_left = 0
		style.border_width_right = 0
		style.border_width_top = 0
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.35)
	
	add_theme_stylebox_override("panel", style)
#endregion
