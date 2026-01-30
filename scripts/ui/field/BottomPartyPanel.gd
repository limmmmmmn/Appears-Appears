extends PanelContainer
class_name BottomPartyPanel
## 하단 파티 패널 - Face + HP/MP 바 + 장비 슬롯 + 스킬 토글

signal equipment_clicked(hero_index: int, slot_name: String, item_id: String)
signal equipment_right_clicked(hero_index: int, slot_name: String, item_id: String)

# 슬롯 데이터 클래스
class SlotUI:
	var container: VBoxContainer
	var face: TextureRect
	var hp_bar: ProgressBar
	var mp_bar: ProgressBar
	var atb_bar: ProgressBar
	var equip_buttons: Dictionary = {}  # slot_name -> Button
	var skill_row: HBoxContainer
	var skill_buttons: Dictionary = {}  # skill_id -> Button
	var hero_index: int = -1

# 색상 상수
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)
const MP_COLOR_HIGH := Color(0.3, 0.5, 0.9)
const MP_COLOR_MID := Color(0.4, 0.5, 0.85)
const MP_COLOR_LOW := Color(0.6, 0.3, 0.7)
const ATB_COLOR_CHARGING := Color(0.7, 0.6, 0.2)
const ATB_COLOR_READY := Color(1.0, 0.9, 0.3)

const SLOT_ICONS := {
	"main_hand": "⚔️", "off_hand": "🛡️", "head": "👑",
	"body": "👕", "acc1": "💍", "acc2": "💎"
}

const SLOT_NAMES_KR := {
	"main_hand": "주무기", "off_hand": "보조", "head": "머리",
	"body": "몸통", "acc1": "장신구1", "acc2": "장신구2"
}

const ITEM_ICONS := {
	"sword": "🗡️", "dagger": "🔪", "axe": "🪓", "staff": "🪄", "bow": "🏹",
	"shield": "🛡️", "helmet": "⛑️", "light_armor": "👘", "medium_armor": "🦺",
	"heavy_armor": "🛡️", "robe": "👗", "ring": "💍", "amulet": "📿",
	"weapon": "⚔️", "head": "👑", "body": "👕", "accessory": "💍"
}

const SKILL_ICONS := {
	"basic_attack": "⚔️", "power_strike": "💥", "fireball": "🔥",
	"heal": "💚", "quick_slash": "⚡", "power_shot": "🏹",
	"shield_bash": "🛡️", "ice_bolt": "❄️", "blessing": "✨", "double_shot": "🎯"
}

const RARITY_COLORS := {
	"common": Color.WHITE,
	"magic": Color(0.4, 0.6, 1.0),
	"legendary": Color(1.0, 0.7, 0.2)
}

var slots: Array[SlotUI] = []


func _ready() -> void:
	_setup_slots()
	_connect_signals()
	for slot in slots:
		slot.container.visible = false


func _setup_slots() -> void:
	var hbox = $HBox
	for i in range(4):
		var slot_node = hbox.get_node_or_null("Slot%d" % i)
		if not slot_node:
			continue
		
		var slot := SlotUI.new()
		slot.container = slot_node
		slot.hero_index = i
		slot.face = slot_node.get_node_or_null("Face")
		slot.hp_bar = slot_node.get_node_or_null("Bars/HPBar")
		slot.mp_bar = slot_node.get_node_or_null("Bars/MPBar")
		slot.atb_bar = slot_node.get_node_or_null("Bars/ATBBar")
		slot.skill_row = slot_node.get_node_or_null("SkillRow")
		
		# 장비 버튼 참조
		var equip_row1 = slot_node.get_node_or_null("EquipRow1")
		var equip_row2 = slot_node.get_node_or_null("EquipRow2")
		
		if equip_row1:
			slot.equip_buttons["main_hand"] = equip_row1.get_node_or_null("MainHand")
			slot.equip_buttons["off_hand"] = equip_row1.get_node_or_null("OffHand")
			slot.equip_buttons["head"] = equip_row1.get_node_or_null("Head")
		
		if equip_row2:
			slot.equip_buttons["body"] = equip_row2.get_node_or_null("Body")
			slot.equip_buttons["acc1"] = equip_row2.get_node_or_null("Acc1")
			slot.equip_buttons["acc2"] = equip_row2.get_node_or_null("Acc2")
		
		# 장비 버튼 시그널 연결
		for slot_name in slot.equip_buttons:
			var btn: Button = slot.equip_buttons[slot_name]
			if btn:
				btn.gui_input.connect(_on_equip_gui_input.bind(i, slot_name))
				btn.tooltip_text = SLOT_NAMES_KR.get(slot_name, slot_name) + ": (없음)"
		
		slots.append(slot)


func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(update_display):
			PartyManager.party_changed.connect(update_display)
	
	if BattleManager and BattleManager.has_signal("party_hp_changed"):
		if not BattleManager.party_hp_changed.is_connected(update_display):
			BattleManager.party_hp_changed.connect(update_display)


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	for i in range(slots.size()):
		var slot := slots[i]
		
		if i < party.size() and party[i] != null:
			var hero: Hero = party[i]
			slot.container.visible = true
			
			# 페이스 업데이트
			if SpriteManager and slot.face:
				slot.face.texture = SpriteManager.get_hero_face_sprite(hero.id)
			
			# HP 바 업데이트
			if slot.hp_bar:
				var max_hp := hero.get_max_hp()
				slot.hp_bar.max_value = max_hp
				slot.hp_bar.value = hero.current_hp
				_update_hp_color(slot, float(hero.current_hp) / float(max_hp))
			
			# MP 바 업데이트
			if slot.mp_bar:
				var max_mp := hero.get_max_mp()
				slot.mp_bar.max_value = max_mp
				slot.mp_bar.value = hero.current_mp
				_update_mp_color(slot, float(hero.current_mp) / float(max_mp) if max_mp > 0 else 1.0)
			
			# 장비 업데이트
			_update_equipment(slot, hero)
			
			# 스킬 토글 업데이트
			_update_skill_toggles(slot, hero)
		else:
			slot.container.visible = false


func _update_hp_color(slot: SlotUI, hp_percent: float) -> void:
	var fill_style: StyleBoxFlat = slot.hp_bar.get_theme_stylebox("fill")
	if fill_style:
		fill_style = fill_style.duplicate()
		if hp_percent <= 0.25:
			fill_style.bg_color = HP_COLOR_LOW
		elif hp_percent <= 0.5:
			fill_style.bg_color = HP_COLOR_MID
		else:
			fill_style.bg_color = HP_COLOR_HIGH
		slot.hp_bar.add_theme_stylebox_override("fill", fill_style)


func _update_mp_color(slot: SlotUI, mp_percent: float) -> void:
	var fill_style: StyleBoxFlat = slot.mp_bar.get_theme_stylebox("fill")
	if fill_style:
		fill_style = fill_style.duplicate()
		if mp_percent <= 0.2:
			fill_style.bg_color = MP_COLOR_LOW
		elif mp_percent <= 0.5:
			fill_style.bg_color = MP_COLOR_MID
		else:
			fill_style.bg_color = MP_COLOR_HIGH
		slot.mp_bar.add_theme_stylebox_override("fill", fill_style)


func _update_equipment(slot: SlotUI, hero: Hero) -> void:
	for slot_name in slot.equip_buttons:
		var btn: Button = slot.equip_buttons[slot_name]
		if not btn:
			continue
		
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


func _update_skill_toggles(slot: SlotUI, hero: Hero) -> void:
	if not slot.skill_row:
		return
	
	var current_skills := hero.get_available_skills()
	
	# 기존 버튼 중 없는 스킬 제거
	var to_remove: Array = []
	for skill_id in slot.skill_buttons:
		if skill_id not in current_skills:
			to_remove.append(skill_id)
	
	for skill_id in to_remove:
		slot.skill_buttons[skill_id].queue_free()
		slot.skill_buttons.erase(skill_id)
	
	# 새 스킬 버튼 추가 또는 업데이트
	for skill_id in current_skills:
		if slot.skill_buttons.has(skill_id):
			_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero)
		else:
			var btn := _create_skill_button(skill_id, hero, slot.hero_index)
			slot.skill_row.add_child(btn)
			slot.skill_buttons[skill_id] = btn


func _create_skill_button(skill_id: String, hero: Hero, hero_index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(20, 18)
	btn.toggle_mode = true
	btn.button_pressed = hero.is_skill_enabled(skill_id)
	
	var icon: String = SKILL_ICONS.get(skill_id, "⚡")
	btn.text = icon
	btn.add_theme_font_size_override("font_size", 10)
	
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = skill_data.get("name", skill_id)
	var mp_cost: int = int(skill_data.get("mp_cost", 0))
	btn.tooltip_text = "%s (MP %d)" % [skill_name, mp_cost] if mp_cost > 0 else skill_name
	
	btn.toggled.connect(_on_skill_toggled.bind(skill_id, hero_index))
	_update_skill_button_state(btn, skill_id, hero)
	
	return btn


func _update_skill_button_state(btn: Button, skill_id: String, hero: Hero) -> void:
	var is_enabled: bool = hero.is_skill_enabled(skill_id)
	btn.button_pressed = is_enabled
	
	var mp_cost: int = DataManager.get_skill_mp_cost(skill_id)
	var has_mp: bool = hero.current_mp >= mp_cost
	
	if is_enabled:
		btn.modulate = Color.WHITE if has_mp else Color(1.0, 0.5, 0.5, 0.8)
	else:
		btn.modulate = Color(0.5, 0.5, 0.5, 0.6)


func _on_skill_toggled(toggled_on: bool, skill_id: String, hero_index: int) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero: Hero = party[hero_index]
	hero.skill_toggles[skill_id] = toggled_on
	
	if SoundManager != null:
		SoundManager.play_select()
	
	# 버튼 상태 업데이트
	if hero_index < slots.size():
		var slot := slots[hero_index]
		if slot.skill_buttons.has(skill_id):
			_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero)


func _on_equip_gui_input(event: InputEvent, hero_index: int, slot_name: String) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero: Hero = party[hero_index]
	var equip_id: String = hero.equipment.get(slot_name, "")
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and not equip_id.is_empty():
			# 우클릭: 장비 해제
			if InventoryManager.unequip_item(hero, slot_name):
				var equip_name = str(DataManager.get_equipment(equip_id).get("name", equip_id))
				if BattleManager:
					BattleManager.emit_battle_log("%s: %s 해제" % [hero.hero_name, equip_name], Color.GRAY)
				update_display()
			equipment_right_clicked.emit(hero_index, slot_name, equip_id)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			equipment_clicked.emit(hero_index, slot_name, equip_id)


func update_hero_atb(hero_id: String, atb_value: float) -> void:
	## 특정 영웅의 ATB 바 업데이트
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	for i in range(mini(slots.size(), party.size())):
		var hero: Hero = party[i]
		if hero.id == hero_id:
			var slot := slots[i]
			if slot.atb_bar:
				slot.atb_bar.value = atb_value * 100.0
				_update_atb_color(slot, atb_value)
			break


func _update_atb_color(slot: SlotUI, atb_percent: float) -> void:
	if not slot.atb_bar:
		return
	var fill_style: StyleBoxFlat = slot.atb_bar.get_theme_stylebox("fill")
	if fill_style:
		fill_style = fill_style.duplicate()
		if atb_percent >= 1.0:
			fill_style.bg_color = ATB_COLOR_READY
		else:
			fill_style.bg_color = ATB_COLOR_CHARGING
		slot.atb_bar.add_theme_stylebox_override("fill", fill_style)
