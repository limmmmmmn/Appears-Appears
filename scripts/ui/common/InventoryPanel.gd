extends PanelContainer
class_name InventoryPanel
## 인벤토리 패널: 아이템 그리드 + 정보 + 장착/해제

signal closed
signal item_equipped(hero_index: int, item_id: String, slot: String)
signal item_unequipped(hero_index: int, slot: String)

@onready var grid: GridContainer = %ItemGrid
@onready var info_panel: VBoxContainer = %InfoPanel
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_stats_label: Label = %ItemStatsLabel
@onready var hero_dropdown: OptionButton = %HeroDropdown
@onready var slot_dropdown: OptionButton = %SlotDropdown
@onready var equip_button: Button = %EquipButton
@onready var unequip_button: Button = %UnequipButton
@onready var discard_button: Button = %DiscardButton
@onready var close_button: Button = %CloseButton

var selected_item_id: String = ""
var item_buttons: Array[Button] = []

const SLOT_NAMES: Dictionary = {
	"main_hand": "주무기",
	"off_hand": "보조",
	"head": "머리",
	"body": "몸통",
	"acc1": "악세1",
	"acc2": "악세2"
}

const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),      # 회색
	"uncommon": Color(0.4, 0.8, 0.4),    # 초록
	"magic": Color(0.4, 0.6, 1.0),       # 파랑
	"rare": Color(0.8, 0.5, 1.0),        # 보라
	"epic": Color(1.0, 0.5, 0.2),        # 주황
	"legendary": Color(1.0, 0.8, 0.2),   # 금색
}


func _ready() -> void:
	_setup_ui()
	_connect_signals()
	refresh_inventory()
	_clear_selection()


func _setup_ui() -> void:
	# 영웅 드롭다운 채우기
	_populate_hero_dropdown()
	
	# 슬롯 드롭다운 채우기
	for slot_key in SLOT_NAMES.keys():
		slot_dropdown.add_item(SLOT_NAMES[slot_key])
		slot_dropdown.set_item_metadata(slot_dropdown.item_count - 1, slot_key)


func _connect_signals() -> void:
	close_button.pressed.connect(_on_close_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	unequip_button.pressed.connect(_on_unequip_pressed)
	discard_button.pressed.connect(_on_discard_pressed)
	hero_dropdown.item_selected.connect(_on_hero_selected)
	
	if InventoryManager:
		InventoryManager.inventory_changed.connect(refresh_inventory)
	if PartyManager:
		PartyManager.party_changed.connect(_populate_hero_dropdown)


func _populate_hero_dropdown() -> void:
	hero_dropdown.clear()
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		var hero = party[i]
		hero_dropdown.add_item(hero.hero_name)
		hero_dropdown.set_item_metadata(i, i)


#region 인벤토리 표시
func refresh_inventory() -> void:
	# 기존 버튼 제거
	for btn in item_buttons:
		btn.queue_free()
	item_buttons.clear()
	
	# 그리드 초기화
	for child in grid.get_children():
		child.queue_free()
	
	# 아이템 버튼 생성
	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	
	for item_info in items:
		var btn := _create_item_button(item_info)
		grid.add_child(btn)
		item_buttons.append(btn)
	
	# 빈 슬롯 채우기 (최소 6개 표시, 2x3 그리드)
	var empty_count: int = max(0, 6 - items.size())
	for i in range(empty_count):
		var empty_btn := _create_empty_slot()
		grid.add_child(empty_btn)


func _create_item_button(item_info: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(36, 36)
	
	var item_id: String = str(item_info.get("id", ""))
	var quantity: int = int(item_info.get("quantity", 1))
	var data: Dictionary = item_info.get("data", {})
	var item_name: String = str(data.get("name", item_id))
	var rarity: String = str(data.get("rarity", "common"))
	var item_type: String = str(data.get("type", str(data.get("slot", ""))))
	
	# 아이콘 텍스트 (타입별)
	var icon: String = _get_item_icon(item_type)
	btn.text = icon
	if quantity > 1:
		btn.text += "\n%d" % quantity
	
	btn.add_theme_font_size_override("font_size", 14)
	btn.tooltip_text = "%s x%d" % [item_name, quantity]
	
	# 등급별 색상
	btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	
	# 클릭 이벤트
	btn.pressed.connect(_on_item_selected.bind(item_id))
	
	return btn


func _create_empty_slot() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(36, 36)
	btn.text = ""
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 0.5)
	return btn


func _get_item_icon(item_type: String) -> String:
	match item_type:
		"weapon", "main_hand":
			return "⚔️"
		"shield", "off_hand":
			return "🛡️"
		"head", "helmet":
			return "👑"
		"body", "armor":
			return "👕"
		"accessory", "acc1", "acc2":
			return "💍"
		"potion":
			return "🧪"
		"seed":
			return "🌱"
		_:
			return "📦"
#endregion


#region 아이템 선택/정보 표시
func _on_item_selected(item_id: String) -> void:
	selected_item_id = item_id
	_show_item_info(item_id)
	_update_buttons()


func _show_item_info(item_id: String) -> void:
	var data: Dictionary = DataManager.get_equipment(item_id)
	var is_equipment: bool = not data.is_empty()
	
	if data.is_empty():
		data = DataManager.get_item(item_id)
	
	if data.is_empty():
		_clear_selection()
		return
	
	var item_name: String = str(data.get("name", item_id))
	var rarity: String = str(data.get("rarity", "common"))
	var description: String = str(data.get("description", ""))
	
	# 이름 + 등급
	item_name_label.text = "%s (%s)" % [item_name, rarity.capitalize()]
	item_name_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, Color.WHITE))
	
	# 스탯
	var stats_text: String = ""
	if is_equipment:
		var stats: Dictionary = data.get("stats", {})
		for stat_key in stats:
			var value: int = int(stats[stat_key])
			stats_text += "%s +%d\n" % [stat_key.to_upper(), value]
		
		# 장착 가능 슬롯
		var slot: String = str(data.get("slot", ""))
		if not slot.is_empty():
			stats_text += "슬롯: %s\n" % SLOT_NAMES.get(slot, slot)
	else:
		# 소비 아이템
		var effect: String = str(data.get("effect", ""))
		if not effect.is_empty():
			stats_text += "효과: %s\n" % effect
	
	if not description.is_empty():
		stats_text += "\n" + description
	
	item_stats_label.text = stats_text
	
	# 슬롯 드롭다운 자동 선택
	if is_equipment:
		var equip_slot: String = str(data.get("slot", "main_hand"))
		for i in range(slot_dropdown.item_count):
			if slot_dropdown.get_item_metadata(i) == equip_slot:
				slot_dropdown.select(i)
				break


func _clear_selection() -> void:
	selected_item_id = ""
	item_name_label.text = "(아이템 선택)"
	item_stats_label.text = ""
	_update_buttons()


func _update_buttons() -> void:
	var has_selection: bool = not selected_item_id.is_empty()
	var is_equipment: bool = not DataManager.get_equipment(selected_item_id).is_empty()
	
	equip_button.disabled = not (has_selection and is_equipment)
	unequip_button.disabled = hero_dropdown.selected < 0
	discard_button.disabled = not has_selection
#endregion


#region 버튼 이벤트
func _on_equip_pressed() -> void:
	if selected_item_id.is_empty():
		return
	
	var hero_index: int = hero_dropdown.get_selected_metadata()
	var slot_index: int = slot_dropdown.selected
	if slot_index < 0:
		return
	
	var slot: String = slot_dropdown.get_item_metadata(slot_index)
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	if hero_index >= party.size():
		return
	
	var hero = party[hero_index]
	
	if InventoryManager.equip_item(hero, selected_item_id, slot):
		item_equipped.emit(hero_index, selected_item_id, slot)
		refresh_inventory()
		_clear_selection()


func _on_unequip_pressed() -> void:
	var hero_index: int = hero_dropdown.get_selected_metadata()
	var slot_index: int = slot_dropdown.selected
	if slot_index < 0:
		return
	
	var slot: String = slot_dropdown.get_item_metadata(slot_index)
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	if hero_index >= party.size():
		return
	
	var hero = party[hero_index]
	
	if InventoryManager.unequip_item(hero, slot):
		item_unequipped.emit(hero_index, slot)
		refresh_inventory()


func _on_discard_pressed() -> void:
	if selected_item_id.is_empty():
		return
	
	# 1개만 버리기
	InventoryManager.remove_item(selected_item_id, 1)
	
	# 남은 수량 확인
	if InventoryManager.get_quantity(selected_item_id) <= 0:
		_clear_selection()


func _on_hero_selected(_index: int) -> void:
	_update_buttons()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
#endregion


#region 입력 처리
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
#endregion
