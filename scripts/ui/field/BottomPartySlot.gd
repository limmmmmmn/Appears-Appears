extends VBoxContainer
class_name BottomPartySlot
## 하단 파티 슬롯 UI: 세로 배치 (페이스칩, HP바, 장비 슬롯)

signal equipment_slot_gui_input(event: InputEvent, slot_name: String)
signal equipment_slot_hovered(slot_name: String, item_id: String)
signal equipment_slot_unhovered()

var hero_index: int = -1
var hero: Hero = null

# UI 참조
var face_texture: TextureRect
var hp_bar: ProgressBar
var equip_row1: HBoxContainer  # 주무기, 보조, 머리
var equip_row2: HBoxContainer  # 몸통, 장신구1, 장신구2
var equip_buttons: Dictionary = {}

# 상수
const SLOT_SIZE: Vector2 = Vector2(18, 16)
const SLOT_FONT_SIZE: int = 10

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
	"common": Color.WHITE,
	"magic": Color(0.4, 0.6, 1.0),
	"legendary": Color(1.0, 0.7, 0.2)
}


func _init() -> void:
	add_theme_constant_override("separation", 2)


func setup(index: int) -> void:
	hero_index = index
	set_meta("hero_index", index)
	_create_layout()
	visible = false


func _create_layout() -> void:
	# 1행: 페이스칩
	face_texture = TextureRect.new()
	face_texture.custom_minimum_size = Vector2(32, 32)
	face_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(face_texture)
	
	# 2행: HP 바
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(56, 6)
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
	add_child(hp_bar)
	
	# 3행: 장비 슬롯 (주무기, 보조, 머리)
	equip_row1 = HBoxContainer.new()
	equip_row1.add_theme_constant_override("separation", 1)
	add_child(equip_row1)
	
	for slot_name in ["main_hand", "off_hand", "head"]:
		_create_equip_button(equip_row1, slot_name)
	
	# 4행: 장비 슬롯 (몸통, 장신구1, 장신구2)
	equip_row2 = HBoxContainer.new()
	equip_row2.add_theme_constant_override("separation", 1)
	add_child(equip_row2)
	
	for slot_name in ["body", "acc1", "acc2"]:
		_create_equip_button(equip_row2, slot_name)


func _create_equip_button(parent: HBoxContainer, slot_name: String) -> void:
	var btn := Button.new()
	btn.name = "Equip_" + slot_name
	btn.custom_minimum_size = SLOT_SIZE
	btn.text = SLOT_ICONS.get(slot_name, "?")
	btn.add_theme_font_size_override("font_size", SLOT_FONT_SIZE)
	btn.tooltip_text = SLOT_NAMES_KR.get(slot_name, slot_name) + ": (없음)"
	btn.set_meta("slot_name", slot_name)
	
	btn.gui_input.connect(_on_equip_gui_input.bind(slot_name))
	btn.mouse_entered.connect(_on_equip_mouse_entered.bind(slot_name))
	btn.mouse_exited.connect(_on_equip_mouse_exited)
	
	parent.add_child(btn)
	equip_buttons[slot_name] = btn


#region 업데이트
func update_display(new_hero: Hero) -> void:
	hero = new_hero
	if not hero:
		visible = false
		return
	
	visible = true
	
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


func _on_equip_mouse_entered(slot_name: String) -> void:
	if not hero:
		return
	var equip_id: String = hero.equipment.get(slot_name, "")
	equipment_slot_hovered.emit(slot_name, equip_id)


func _on_equip_mouse_exited() -> void:
	equipment_slot_unhovered.emit()
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
	if enabled:
		modulate = Color(1.2, 1.2, 1.0)
	else:
		modulate = Color.WHITE
#endregion
