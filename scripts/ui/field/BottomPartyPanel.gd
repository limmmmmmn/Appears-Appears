extends PanelContainer
class_name BottomPartyPanel
## 하단 파티 패널 - Face + HP/MP/ATB 바 + 스킬 토글 + 작전 선택

signal tactic_changed(hero_index: int, tactic_id: String)

## 작전 정의 (드래곤퀘스트 스타일)
const TACTICS := {
	"all_out": {
		"name": "전력으로 싸워라",
		"description": "모든 기술을 자유롭게 사용",
		"icon": "⚔️",
		"allow_skills": true,
		"allow_mp": true,
		"prefer_heal": false
	},
	"no_mp": {
		"name": "MP 사용 금지",
		"description": "기본 공격만 사용",
		"icon": "🚫",
		"allow_skills": false,
		"allow_mp": false,
		"prefer_heal": false
	},
	"heal_first": {
		"name": "회복 우선",
		"description": "HP가 낮은 아군 우선 치료",
		"icon": "💚",
		"allow_skills": true,
		"allow_mp": true,
		"prefer_heal": true
	},
	"conserve_mp": {
		"name": "MP 아껴라",
		"description": "MP 소모가 적은 기술 위주",
		"icon": "💧",
		"allow_skills": true,
		"allow_mp": true,
		"prefer_heal": false,
		"conserve_mp": true
	},
	"defend": {
		"name": "방어 집중",
		"description": "방어 위주로 행동",
		"icon": "🛡️",
		"allow_skills": true,
		"allow_mp": true,
		"prefer_heal": false,
		"defensive": true
	}
}

const TACTIC_ORDER := ["all_out", "no_mp", "heal_first", "conserve_mp", "defend"]

# 슬롯 데이터 클래스
class SlotUI:
	var container: PanelContainer
	var face: TextureRect
	var hp_bar: ProgressBar
	var mp_bar: ProgressBar
	var atb_bar: ProgressBar
	var skill_row: HBoxContainer
	var skill_buttons: Dictionary = {}  # skill_id -> Button
	var tactic_btn: Button
	var hero_index: int = -1
	var current_tactic: String = "all_out"

# 색상 상수
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)
const MP_COLOR_HIGH := Color(0.3, 0.5, 0.9)
const MP_COLOR_MID := Color(0.4, 0.5, 0.85)
const MP_COLOR_LOW := Color(0.6, 0.3, 0.7)
const ATB_COLOR_CHARGING := Color(0.7, 0.6, 0.2)
const ATB_COLOR_READY := Color(1.0, 0.9, 0.3)

const SKILL_ICONS := {
	"basic_attack": "⚔️", "power_strike": "💥", "fireball": "🔥",
	"heal": "💚", "quick_slash": "⚡", "power_shot": "🏹",
	"shield_bash": "🛡️", "ice_bolt": "❄️", "blessing": "✨", 
	"double_shot": "🎯", "backstab": "🗡️", "steal": "💰",
	"aimed_shot": "🎯", "arrow_rain": "🌧️", "smite": "✝️",
	"provoke": "😤"
}

var slots: Array[SlotUI] = []
var tactic_popup: PopupMenu
var active_slot_index: int = -1


func _ready() -> void:
	_setup_slots()
	_setup_tactic_popup()
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
		
		var vbox = slot_node.get_node_or_null("VBox")
		if vbox:
			var top_row = vbox.get_node_or_null("TopRow")
			if top_row:
				slot.face = top_row.get_node_or_null("Face")
				var bars = top_row.get_node_or_null("Bars")
				if bars:
					slot.hp_bar = bars.get_node_or_null("HPBar")
					slot.mp_bar = bars.get_node_or_null("MPBar")
					slot.atb_bar = bars.get_node_or_null("ATBBar")
			
			var bottom_row = vbox.get_node_or_null("BottomRow")
			if bottom_row:
				slot.skill_row = bottom_row.get_node_or_null("SkillRow")
				slot.tactic_btn = bottom_row.get_node_or_null("TacticBtn")
				
				if slot.tactic_btn:
					slot.tactic_btn.pressed.connect(_on_tactic_btn_pressed.bind(i))
					_update_tactic_button(slot)
		
		slots.append(slot)


func _setup_tactic_popup() -> void:
	tactic_popup = $TacticPopup
	if not tactic_popup:
		tactic_popup = PopupMenu.new()
		add_child(tactic_popup)
	
	tactic_popup.clear()
	for tactic_id in TACTIC_ORDER:
		var tactic: Dictionary = TACTICS[tactic_id]
		var text := "%s %s" % [tactic.icon, tactic.name]
		tactic_popup.add_item(text)
		tactic_popup.set_item_metadata(tactic_popup.item_count - 1, tactic_id)
	
	if not tactic_popup.id_pressed.is_connected(_on_tactic_selected):
		tactic_popup.id_pressed.connect(_on_tactic_selected)


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
			
			# 스킬 토글 업데이트
			_update_skill_toggles(slot, hero)
			
			# 작전 버튼 업데이트
			_update_tactic_button(slot)
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
			_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero, slot.current_tactic)
		else:
			var btn := _create_skill_button(skill_id, hero, slot.hero_index, slot.current_tactic)
			slot.skill_row.add_child(btn)
			slot.skill_buttons[skill_id] = btn


func _create_skill_button(skill_id: String, hero: Hero, hero_index: int, tactic: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(18, 16)
	btn.toggle_mode = true
	btn.button_pressed = hero.is_skill_enabled(skill_id)
	
	var icon: String = SKILL_ICONS.get(skill_id, "⚡")
	btn.text = icon
	btn.add_theme_font_size_override("font_size", 9)
	
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = skill_data.get("name", skill_id)
	var mp_cost: int = int(skill_data.get("mp_cost", 0))
	btn.tooltip_text = "%s (MP %d)" % [skill_name, mp_cost] if mp_cost > 0 else skill_name
	
	btn.toggled.connect(_on_skill_toggled.bind(skill_id, hero_index))
	_update_skill_button_state(btn, skill_id, hero, tactic)
	
	return btn


func _update_skill_button_state(btn: Button, skill_id: String, hero: Hero, tactic: String) -> void:
	var is_enabled: bool = hero.is_skill_enabled(skill_id)
	btn.button_pressed = is_enabled
	
	var mp_cost: int = DataManager.get_skill_mp_cost(skill_id)
	var has_mp: bool = hero.current_mp >= mp_cost
	
	# 작전에 따른 비활성화 체크
	var tactic_data: Dictionary = TACTICS.get(tactic, TACTICS["all_out"])
	var tactic_allows: bool = true
	
	if mp_cost > 0 and not tactic_data.get("allow_mp", true):
		tactic_allows = false
	
	if is_enabled and tactic_allows:
		btn.modulate = Color.WHITE if has_mp else Color(1.0, 0.5, 0.5, 0.8)
	else:
		btn.modulate = Color(0.5, 0.5, 0.5, 0.6)
	
	# MP 사용 금지 작전일 때 MP 소모 스킬 비활성화 표시
	if not tactic_allows:
		btn.modulate = Color(0.4, 0.4, 0.5, 0.5)


func _update_tactic_button(slot: SlotUI) -> void:
	if not slot.tactic_btn:
		return
	
	var tactic_data: Dictionary = TACTICS.get(slot.current_tactic, TACTICS["all_out"])
	slot.tactic_btn.text = tactic_data.get("icon", "▼")
	slot.tactic_btn.tooltip_text = "%s: %s" % [tactic_data.name, tactic_data.description]


func _on_tactic_btn_pressed(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= slots.size():
		return
	
	active_slot_index = hero_index
	
	# 팝업 위치 설정
	var slot := slots[hero_index]
	var btn_pos := slot.tactic_btn.global_position
	var popup_pos := Vector2(btn_pos.x, btn_pos.y - tactic_popup.size.y)
	
	# 화면 밖으로 나가지 않도록 조정
	var viewport_size := get_viewport().get_visible_rect().size
	if popup_pos.y < 0:
		popup_pos.y = btn_pos.y + slot.tactic_btn.size.y
	if popup_pos.x + tactic_popup.size.x > viewport_size.x:
		popup_pos.x = viewport_size.x - tactic_popup.size.x
	
	# 현재 선택된 작전 체크 표시
	var current_tactic := slot.current_tactic
	for i in range(tactic_popup.item_count):
		var item_tactic: String = tactic_popup.get_item_metadata(i)
		tactic_popup.set_item_checked(i, item_tactic == current_tactic)
	
	tactic_popup.position = Vector2i(int(popup_pos.x), int(popup_pos.y))
	tactic_popup.popup()


func _on_tactic_selected(index: int) -> void:
	if active_slot_index < 0 or active_slot_index >= slots.size():
		return
	
	var tactic_id: String = tactic_popup.get_item_metadata(index)
	var slot := slots[active_slot_index]
	slot.current_tactic = tactic_id
	
	_update_tactic_button(slot)
	
	# 스킬 버튼 상태 업데이트
	var party: Array = PartyManager.get_party() if PartyManager else []
	if active_slot_index < party.size():
		var hero: Hero = party[active_slot_index]
		for skill_id in slot.skill_buttons:
			_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero, tactic_id)
	
	if SoundManager != null:
		SoundManager.play_select()
	
	tactic_changed.emit(active_slot_index, tactic_id)
	active_slot_index = -1


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
			_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero, slot.current_tactic)


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


func get_hero_tactic(hero_index: int) -> String:
	## 특정 영웅의 현재 작전 반환
	if hero_index >= 0 and hero_index < slots.size():
		return slots[hero_index].current_tactic
	return "all_out"


func set_hero_tactic(hero_index: int, tactic_id: String) -> void:
	## 특정 영웅의 작전 설정
	if hero_index >= 0 and hero_index < slots.size():
		if TACTICS.has(tactic_id):
			slots[hero_index].current_tactic = tactic_id
			_update_tactic_button(slots[hero_index])
			
			# 스킬 버튼 상태도 업데이트
			var party: Array = PartyManager.get_party() if PartyManager else []
			if hero_index < party.size():
				var hero: Hero = party[hero_index]
				var slot := slots[hero_index]
				for skill_id in slot.skill_buttons:
					_update_skill_button_state(slot.skill_buttons[skill_id], skill_id, hero, tactic_id)


func get_tactic_data(tactic_id: String) -> Dictionary:
	## 작전 데이터 반환 (전투 AI에서 사용)
	return TACTICS.get(tactic_id, TACTICS["all_out"])
