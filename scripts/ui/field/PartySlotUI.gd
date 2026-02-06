extends PanelContainer
class_name PartySlotUI
## 간소화된 파티 슬롯 UI: 페이스칩, HP바, 장비 슬롯만
## 상세 스탯은 메뉴에서 확인

signal equipment_slot_gui_input(event: InputEvent, slot_name: String)
signal equipment_slot_hovered(slot_name: String, item_id: String)
signal equipment_slot_unhovered()

var hero_index: int = -1
var hero: Hero = null

# UI 참조
var face_texture: TextureRect
var name_label: Label
var hp_bar: ProgressBar
var hp_label: Label
var equip_container: HBoxContainer
var equip_buttons: Dictionary = {}

# 상수
const SLOT_SIZE: Vector2 = Vector2(24, 22)
const SLOT_FONT_SIZE: int = 12

const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️", "off_hand": "🛡️", "head": "👑",
	"body": "👕", "acc1": "💍", "acc2": "💎"
}

const SLOT_NAMES_KR: Dictionary = {
	"main_hand": "주무기", "off_hand": "보조", "head": "머리",
	"body": "몸통", "acc1": "장신구1", "acc2": "장신구2"
}

const ITEM_ICONS: Dictionary = {
	"sword": "🗡️", "dagger": "🔪", "axe": "🪓", "staff": "🪄", "bow": "🏹",
	"shield": "🛡️", "helmet": "⛑️", "light_armor": "👘", "medium_armor": "🦺",
	"heavy_armor": "🛡️", "robe": "👗", "ring": "💍", "amulet": "📿",
	"weapon": "⚔️", "head": "👑", "body": "👕", "accessory": "💍"
}

const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),      # 회색
	"uncommon": Color(0.4, 0.8, 0.4),    # 초록
	"magic": Color(0.4, 0.6, 1.0),       # 파랑
	"rare": Color(0.8, 0.5, 1.0),        # 보라
	"epic": Color(1.0, 0.5, 0.2),        # 주황
	"legendary": Color(1.0, 0.8, 0.2),   # 금색
}


func _init() -> void:
	custom_minimum_size = Vector2(152, 44)


func setup(index: int) -> void:
	hero_index = index
	set_meta("hero_index", index)
	
	_setup_style()
	_create_layout()
	visible = false


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)


func _create_layout() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)
	
	# 1행: 페이스 + 이름 + HP바
	_create_header_row(vbox)
	
	# 2행: 장비 슬롯
	_create_equipment_row(vbox)


func _create_header_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	
	# 페이스칩
	face_texture = TextureRect.new()
	face_texture.custom_minimum_size = Vector2(20, 20)
	face_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.add_child(face_texture)
	
	# 이름 + HP 수직
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 1)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_vbox)
	
	# 이름
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.clip_text = true
	info_vbox.add_child(name_label)
	
	# HP 바
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 2)
	info_vbox.add_child(hp_row)
	
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(60, 8)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	hp_bar.value = 100
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.75, 0.2)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.1, 0.1)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("background", bg_style)
	hp_row.add_child(hp_bar)
	
	hp_label = Label.new()
	hp_label.custom_minimum_size.x = 42
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.add_theme_font_size_override("font_size", 8)
	hp_row.add_child(hp_label)


func _create_equipment_row(parent: VBoxContainer) -> void:
	equip_container = HBoxContainer.new()
	equip_container.add_theme_constant_override("separation", 2)
	parent.add_child(equip_container)
	
	for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
		var btn := Button.new()
		btn.name = "Equip_" + slot_name
		btn.custom_minimum_size = SLOT_SIZE
		btn.text = SLOT_ICONS.get(slot_name, "?")
		btn.add_theme_font_size_override("font_size", SLOT_FONT_SIZE)
		btn.tooltip_text = SLOT_NAMES_KR.get(slot_name, slot_name) + ": (없음)"
		btn.set_meta("slot_name", slot_name)

		btn.gui_input.connect(_on_equip_gui_input.bind(slot_name))
		btn.mouse_entered.connect(_on_equip_mouse_entered.bind(btn, slot_name))
		btn.mouse_exited.connect(_on_equip_mouse_exited.bind(btn))

		_apply_equip_button_style(btn, false)
		equip_container.add_child(btn)
		equip_buttons[slot_name] = btn


#region 업데이트
func update_display(new_hero: Hero) -> void:
	hero = new_hero
	if not hero:
		visible = false
		return
	
	visible = true
	name_label.text = "%s (%s)" % [hero.hero_name, hero.hero_class_name]
	
	if SpriteManager:
		face_texture.texture = SpriteManager.get_hero_face_sprite(hero.id)
	
	_update_hp_bar()
	_update_equipment()


func _update_hp_bar() -> void:
	if not hero:
		return
	
	var max_hp := hero.get_max_hp()
	hp_bar.max_value = max_hp
	hp_bar.value = hero.current_hp
	hp_label.text = "%d/%d" % [hero.current_hp, max_hp]
	
	# HP 비율에 따른 색상 변경
	var hp_ratio: float = float(hero.current_hp) / float(max_hp)
	var fill_style: StyleBoxFlat = hp_bar.get_theme_stylebox("fill").duplicate()
	if hp_ratio <= 0.25:
		fill_style.bg_color = Color(0.9, 0.2, 0.2)
	elif hp_ratio <= 0.5:
		fill_style.bg_color = Color(0.9, 0.7, 0.2)
	else:
		fill_style.bg_color = Color(0.2, 0.75, 0.2)
	hp_bar.add_theme_stylebox_override("fill", fill_style)


func _update_equipment() -> void:
	if not hero:
		return
	
	for slot_name in equip_buttons:
		var btn: Button = equip_buttons[slot_name]
		var equip_id: String = hero.equipment.get(slot_name, "")
		
		if equip_id.is_empty():
			btn.text = SLOT_ICONS.get(slot_name, "?")
			btn.modulate = Color(0.4, 0.4, 0.4, 0.6)
			btn.tooltip_text = SLOT_NAMES_KR.get(slot_name, slot_name) + ": (없음)"
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var item_type: String = str(equip_data.get("type", ""))
			var item_slot: String = str(equip_data.get("slot", ""))
			var rarity: String = str(equip_data.get("rarity", "common"))
			var equip_name: String = str(equip_data.get("name", equip_id))
			
			var icon: String = ITEM_ICONS.get(item_type, "")
			if icon.is_empty():
				icon = ITEM_ICONS.get(item_slot, SLOT_ICONS.get(slot_name, "📦"))
			
			btn.text = icon
			btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
			btn.tooltip_text = SLOT_NAMES_KR.get(slot_name, slot_name) + ": " + equip_name
#endregion


#region 시그널
func _on_equip_gui_input(event: InputEvent, slot_name: String) -> void:
	equipment_slot_gui_input.emit(event, slot_name)


func _on_equip_mouse_entered(btn: Button, slot_name: String) -> void:
	_apply_equip_button_style(btn, true)
	if not hero:
		return
	var equip_id: String = hero.equipment.get(slot_name, "")
	equipment_slot_hovered.emit(slot_name, equip_id)


func _on_equip_mouse_exited(btn: Button) -> void:
	_apply_equip_button_style(btn, false)
	equipment_slot_unhovered.emit()


func _apply_equip_button_style(btn: Button, hovered: bool) -> void:
	## 장비 버튼 스타일 적용 (호버 시 테두리)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.9)

	if hovered:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.8, 0.8, 0.3, 1.0)
	else:
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.35, 0.6)

	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
#endregion


#region 외부 접근
func get_equipment_button(slot_name: String) -> Button:
	return equip_buttons.get(slot_name)


func get_equipped_item_id(slot_name: String) -> String:
	if hero:
		return hero.equipment.get(slot_name, "")
	return ""


func get_hero_id() -> String:
	return hero.id if hero else ""


func get_hero() -> Hero:
	return hero


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
		style.border_color = Color(0.25, 0.25, 0.3)
	add_theme_stylebox_override("panel", style)
#endregion
