extends CanvasLayer
class_name FieldHUD
## 필드 HUD: 상단바 + 우측 패널 (미니맵, 파티, 인벤토리, 로그) + 드래그앤드롭

signal menu_pressed
signal equipment_slot_clicked(hero_index: int, slot: String)
signal skill_toggled(hero_index: int, skill_id: String, enabled: bool)

# 상단 바
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var menu_button: Button = %MenuButton

# 우측 패널
@onready var minimap_panel: PanelContainer = %MinimapPanel
@onready var party_container: VBoxContainer = %PartyContainer
@onready var inventory_grid: GridContainer = %InventoryGrid
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var log_container: VBoxContainer = %LogContainer
@onready var log_scroll: ScrollContainer = %LogScroll

# 파티 슬롯 참조
var party_slots: Array[Control] = []

# 선택된 인벤토리 아이템
var selected_item_id: String = ""

# 툴팁
var tooltip: EquipmentTooltip = null

# 드래그 관련
var dragging_item_id: String = ""
var drag_preview: Control = null
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_source_type: String = ""  # "inventory" or "equipped"
var drag_source_hero_index: int = -1
var drag_source_slot: String = ""

# 컨텍스트 메뉴
var context_menu: PopupMenu = null
var context_menu_item_id: String = ""

# 로그 설정
const MAX_LOG_LINES: int = 20
const DRAG_THRESHOLD: float = 5.0  # 드래그 시작 임계값

# 장비 슬롯 이모지
const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️",
	"off_hand": "🛡️",
	"head": "👑",
	"body": "👕",
	"acc1": "💍",
	"acc2": "💎"
}

const ITEM_ICONS: Dictionary = {
	"weapon": "⚔️",
	"main_hand": "⚔️",
	"shield": "🛡️",
	"off_hand": "🛡️",
	"head": "👑",
	"helmet": "👑",
	"body": "👕",
	"armor": "👕",
	"accessory": "💍",
	"acc1": "💍",
	"acc2": "💎",
	"potion": "🧪",
	"seed": "🌱"
}

const RARITY_COLORS: Dictionary = {
	"common": Color.WHITE,
	"magic": Color(0.4, 0.6, 1.0),
	"legendary": Color(1.0, 0.7, 0.2)
}


func _ready() -> void:
	_setup_party_slots()
	_connect_signals()
	update_all()
	refresh_inventory()


func _input(event: InputEvent) -> void:
	# 드래그 중 마우스 이동
	if dragging_item_id and event is InputEventMouseMotion:
		if drag_preview:
			drag_preview.global_position = event.global_position - Vector2(12, 12)
	
	# 드래그 중 마우스 버튼 떼기
	if dragging_item_id and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag(event.global_position)


func _setup_party_slots() -> void:
	for i in range(4):
		var slot := _create_compact_party_slot(i)
		party_container.add_child(slot)
		party_slots.append(slot)


func _create_compact_party_slot(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PartySlot%d" % index
	panel.custom_minimum_size = Vector2(150, 58)
	panel.set_meta("hero_index", index)  # 드롭 타겟용 메타데이터
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)
	
	# === 1행: 페이스 + 이름 + HP/MP 바 ===
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 3)
	vbox.add_child(row1)
	
	# 페이스칩 (작게)
	var face := TextureRect.new()
	face.name = "Face"
	face.custom_minimum_size = Vector2(20, 20)
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row1.add_child(face)
	
	# 이름
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.custom_minimum_size.x = 45
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.clip_text = true
	row1.add_child(name_label)
	
	# HP/MP 컨테이너
	var bars_vbox := VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 0)
	bars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(bars_vbox)
	
	# HP 바 (얇게)
	var hp_row := _create_mini_bar("HP", Color(0.2, 0.75, 0.2))
	hp_row.name = "HPBar"
	bars_vbox.add_child(hp_row)
	
	# MP 바 (얇게)
	var mp_row := _create_mini_bar("MP", Color(0.3, 0.4, 0.85))
	mp_row.name = "MPBar"
	bars_vbox.add_child(mp_row)
	
	# === 2행: 장비 슬롯 ===
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 1)
	vbox.add_child(row2)
	
	# 장비 슬롯 6개 (작은 버튼)
	var equip_container := HBoxContainer.new()
	equip_container.name = "EquipContainer"
	equip_container.add_theme_constant_override("separation", 1)
	row2.add_child(equip_container)
	
	for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
		var equip_btn := Button.new()
		equip_btn.name = "Equip_" + slot_name
		equip_btn.custom_minimum_size = Vector2(18, 16)
		equip_btn.text = SLOT_ICONS.get(slot_name, "?")
		equip_btn.add_theme_font_size_override("font_size", 9)
		equip_btn.tooltip_text = slot_name
		equip_btn.set_meta("hero_index", index)
		equip_btn.set_meta("slot_name", slot_name)
		# 드래그/우클릭 이벤트
		equip_btn.gui_input.connect(_on_equip_slot_gui_input.bind(equip_btn, index, slot_name))
		equip_container.add_child(equip_btn)
	
	# === 3행: 스킬 토글 ===
	var row3 := HBoxContainer.new()
	row3.name = "SkillContainer"
	row3.add_theme_constant_override("separation", 2)
	vbox.add_child(row3)
	
	panel.visible = false
	return panel


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


func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	
	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
	
	if PartyManager and PartyManager.has_signal("party_changed"):
		PartyManager.party_changed.connect(_on_party_changed)
	
	if InventoryManager:
		InventoryManager.inventory_changed.connect(refresh_inventory)


#region 업데이트 함수
func update_all() -> void:
	update_top_bar()
	update_party_display()


func update_top_bar() -> void:
	if stage_label and FieldManager:
		var field_name: String = FieldManager.get_current_field_name()
		if field_name.is_empty():
			stage_label.text = FieldManager.get_display_name()
		else:
			stage_label.text = FieldManager.get_display_name() + ": " + field_name
	
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func update_party_display() -> void:
	var party: Array = []
	if PartyManager:
		party = PartyManager.get_party()
	
	for i in range(4):
		if i < party.size():
			_update_party_slot(i, party[i])
			party_slots[i].visible = true
		else:
			party_slots[i].visible = false


func _update_party_slot(index: int, hero: RefCounted) -> void:
	var slot: Control = party_slots[index]
	
	# 이름
	var name_label: Label = slot.find_child("NameLabel", true, false)
	if name_label:
		name_label.text = hero.hero_name
	
	# 페이스칩
	var face: TextureRect = slot.find_child("Face", true, false)
	if face and SpriteManager:
		face.texture = SpriteManager.get_hero_face_sprite(hero.id)
	
	# HP 바
	_update_bar(slot, "HPBar", hero.current_hp, hero.get_max_hp())
	
	# MP 바
	_update_bar(slot, "MPBar", hero.current_mp, hero.get_max_mp())
	
	# 장비 슬롯 업데이트
	_update_equipment_display(slot, hero)
	
	# 스킬 토글 업데이트
	_update_skill_toggles(slot, index, hero)


func _update_bar(slot: Control, bar_name: String, current: int, maximum: int) -> void:
	var container: HBoxContainer = slot.find_child(bar_name, true, false)
	if not container:
		return
	
	var bar: ProgressBar = container.find_child("Bar", true, false)
	var label: Label = container.find_child("ValueLabel", true, false)
	
	if bar:
		bar.max_value = maximum
		bar.value = current
	
	if label:
		label.text = "%d/%d" % [current, maximum]


func _update_equipment_display(slot: Control, hero: RefCounted) -> void:
	var equip_container: HBoxContainer = slot.find_child("EquipContainer", true, false)
	if not equip_container:
		return
	
	for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
		var equip_btn: Button = equip_container.find_child("Equip_" + slot_name, true, false)
		if not equip_btn:
			continue
		
		var equip_id: String = hero.equipment.get(slot_name, "")
		
		if equip_id.is_empty():
			# 빈 슬롯
			equip_btn.text = SLOT_ICONS.get(slot_name, "?")
			equip_btn.modulate = Color(0.5, 0.5, 0.5, 0.7)
			equip_btn.tooltip_text = slot_name + ": (없음)"
		else:
			# 장착된 장비
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var item_type: String = str(equip_data.get("slot", slot_name))
			var rarity: String = str(equip_data.get("rarity", "common"))
			var equip_name: String = str(equip_data.get("name", equip_id))
			
			equip_btn.text = ITEM_ICONS.get(item_type, "📦")
			equip_btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
			equip_btn.tooltip_text = "%s: %s" % [slot_name, equip_name]


func _update_skill_toggles(slot: Control, hero_index: int, hero: RefCounted) -> void:
	var skill_container: HBoxContainer = slot.find_child("SkillContainer", true, false)
	if not skill_container:
		return
	
	# 기존 토글 제거
	for child in skill_container.get_children():
		child.queue_free()
	
	# 스킬 목록 가져오기
	var class_data: Dictionary = DataManager.get_class_data(hero.class_id)
	var skill_ids: Array = class_data.get("skills", ["basic_attack"])
	
	for skill_id in skill_ids:
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		var skill_name: String = str(skill_data.get("name", skill_id))
		var default_on: bool = skill_data.get("default_on", true)
		
		# 토글 상태 확인
		var is_on: bool = hero.skill_toggles.get(skill_id, default_on)
		
		var toggle_btn := CheckBox.new()
		toggle_btn.name = "Skill_" + skill_id
		toggle_btn.text = skill_name.substr(0, 3)  # 앞 3글자만
		toggle_btn.button_pressed = is_on
		toggle_btn.add_theme_font_size_override("font_size", 8)
		toggle_btn.custom_minimum_size = Vector2(0, 12)
		toggle_btn.tooltip_text = skill_name
		toggle_btn.toggled.connect(_on_skill_toggled.bind(hero_index, skill_id))
		
		skill_container.add_child(toggle_btn)


func update_hero_stats(hero_index: int) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < party.size():
		_update_party_slot(hero_index, party[hero_index])
#endregion


#region 인벤토리 표시
func refresh_inventory() -> void:
	if not inventory_grid:
		return
	
	# 기존 버튼 제거
	for child in inventory_grid.get_children():
		child.queue_free()
	
	# 아이템 버튼 생성
	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	
	for item_info in items:
		var btn := _create_inventory_item_button(item_info)
		inventory_grid.add_child(btn)
	
	# 빈 슬롯 (최소 8개)
	var empty_count: int = max(0, 8 - items.size())
	for i in range(empty_count):
		var empty := _create_empty_inventory_slot()
		inventory_grid.add_child(empty)


func _create_inventory_item_button(item_info: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(18, 18)
	
	var item_id: String = str(item_info.get("id", ""))
	var quantity: int = int(item_info.get("quantity", 1))
	var data: Dictionary = item_info.get("data", {})
	var item_name: String = str(data.get("name", item_id))
	var rarity: String = str(data.get("rarity", "common"))
	var item_type: String = str(data.get("type", str(data.get("slot", ""))))
	
	# 아이콘
	btn.text = ITEM_ICONS.get(item_type, "📦")
	btn.add_theme_font_size_override("font_size", 10)
	
	# 등급 색상
	btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	
	# 메타데이터 저장 (드래그용)
	btn.set_meta("item_id", item_id)
	btn.set_meta("item_type", item_type)
	btn.set_meta("rarity", rarity)
	
	# 드래그 시작 (gui_input 사용)
	btn.gui_input.connect(_on_inventory_button_gui_input.bind(btn, item_id))
	
	# 마우스 hover 이벤트
	btn.mouse_entered.connect(_on_inventory_item_hover.bind(item_id))
	btn.mouse_exited.connect(_on_inventory_item_hover_end)
	
	return btn


func _create_empty_inventory_slot() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(18, 18)
	btn.text = ""
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 0.3)
	return btn
#endregion


#region 드래그 앤 드롭
func _on_inventory_button_gui_input(event: InputEvent, btn: Button, item_id: String) -> void:
	if event is InputEventMouseButton:
		# 우클릭 - 장착 대상 선택 메뉴
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var data: Dictionary = DataManager.get_equipment(item_id)
			if not data.is_empty():
				_show_equip_context_menu(item_id, event.global_position)
			return
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 드래그 시작 준비
				drag_start_pos = event.global_position
				dragging_item_id = item_id
				drag_source_type = "inventory"
				drag_source_hero_index = -1
				drag_source_slot = ""
			else:
				# 클릭 (드래그 안 했으면)
				if dragging_item_id == item_id and not drag_preview:
					_on_inventory_item_clicked(item_id)
				if drag_source_type == "inventory":
					dragging_item_id = ""
					drag_source_type = ""
	
	elif event is InputEventMouseMotion:
		# 드래그 임계값 체크
		if dragging_item_id == item_id and not drag_preview and drag_source_type == "inventory":
			var distance = event.global_position.distance_to(drag_start_pos)
			if distance > DRAG_THRESHOLD:
				_start_drag_from_inventory(btn, item_id)


func _on_equip_slot_gui_input(event: InputEvent, btn: Button, hero_index: int, slot_name: String) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero: Hero = party[hero_index]
	var equip_id: String = hero.equipment.get(slot_name, "")
	
	if event is InputEventMouseButton:
		# 우클릭 - 장비 해제
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not equip_id.is_empty():
				_unequip_item(hero_index, slot_name)
			return
		
		# 좌클릭 - 드래그 시작 or 정보 표시
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not equip_id.is_empty():
					drag_start_pos = event.global_position
					dragging_item_id = equip_id
					drag_source_type = "equipped"
					drag_source_hero_index = hero_index
					drag_source_slot = slot_name
				else:
					# 빈 슬롯 클릭 - 정보 표시
					_on_equip_clicked(hero_index, slot_name)
			else:
				# 클릭 (드래그 안 했으면)
				if dragging_item_id == equip_id and not drag_preview and drag_source_type == "equipped":
					_on_equip_clicked(hero_index, slot_name)
				if drag_source_type == "equipped" and drag_source_hero_index == hero_index:
					dragging_item_id = ""
					drag_source_type = ""
					drag_source_hero_index = -1
					drag_source_slot = ""
	
	elif event is InputEventMouseMotion:
		# 장착 아이템 드래그
		if not equip_id.is_empty() and dragging_item_id == equip_id and not drag_preview:
			if drag_source_type == "equipped" and drag_source_hero_index == hero_index:
				var distance = event.global_position.distance_to(drag_start_pos)
				if distance > DRAG_THRESHOLD:
					_start_drag_from_equipped(btn, equip_id, hero_index, slot_name)


func _unequip_item(hero_index: int, slot_name: String) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero: Hero = party[hero_index]
	var equip_id: String = hero.equipment.get(slot_name, "")
	
	if equip_id.is_empty():
		return
	
	var equip_data: Dictionary = DataManager.get_equipment(equip_id)
	var item_name: String = str(equip_data.get("name", equip_id))
	
	if InventoryManager.unequip_item(hero, slot_name):
		add_system_log("%s: %s 해제" % [hero.hero_name, item_name])
		update_party_display()
		refresh_inventory()
	else:
		add_system_log("해제 실패")


func _start_drag_from_inventory(btn: Button, item_id: String) -> void:
	_hide_tooltip()
	_create_drag_preview(item_id)
	_highlight_drop_targets(item_id, true)
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	add_system_log("드래그: %s" % str(data.get("name", item_id)))


func _start_drag_from_equipped(btn: Button, item_id: String, hero_index: int, slot_name: String) -> void:
	_hide_tooltip()
	_create_drag_preview(item_id)
	_highlight_drop_targets(item_id, true)
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	add_system_log("드래그 (장착): %s" % str(data.get("name", item_id)))


func _create_drag_preview(item_id: String) -> void:
	drag_preview = PanelContainer.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.7, 1.0)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	drag_preview.add_theme_stylebox_override("panel", style)
	
	var label := Label.new()
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_type: String = str(data.get("slot", ""))
	label.text = ITEM_ICONS.get(item_type, "📦")
	label.add_theme_font_size_override("font_size", 14)
	
	var rarity: String = str(data.get("rarity", "common"))
	label.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	
	drag_preview.add_child(label)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.z_index = 200
	
	var control_node = get_node_or_null("Control")
	if control_node:
		control_node.add_child(drag_preview)
	else:
		add_child(drag_preview)
	
	drag_preview.global_position = get_viewport().get_mouse_position() - Vector2(12, 12)


func _end_drag(drop_pos: Vector2) -> void:
	if not dragging_item_id:
		return
	
	var item_id := dragging_item_id
	var source_type := drag_source_type
	var source_hero_index := drag_source_hero_index
	var source_slot := drag_source_slot
	
	# 드롭 타겟 찾기
	var drop_target := _find_drop_target(drop_pos)
	
	if drop_target:
		var target_hero_index: int = drop_target.get("hero_index", -1)
		var target_slot: String = drop_target.get("slot_name", "")
		
		if target_hero_index >= 0:
			if source_type == "inventory":
				# 인벤토리 → 영웅
				_try_equip_to_hero(item_id, target_hero_index, target_slot)
			elif source_type == "equipped":
				# 장착 → 다른 영웅 or 같은 영웅 다른 슬롯
				if target_hero_index == source_hero_index and target_slot == source_slot:
					# 같은 위치 - 아무것도 안 함
					pass
				else:
					_try_move_equipment(item_id, source_hero_index, source_slot, target_hero_index, target_slot)
	else:
		# 드롭 타겟 없음
		if source_type == "equipped":
			# 장착 아이템을 빈 곳에 드롭 - 인벤토리로 해제
			if _is_drop_on_inventory(drop_pos):
				_unequip_item(source_hero_index, source_slot)
	
	# 정리
	_highlight_drop_targets(item_id, false)
	
	if drag_preview:
		drag_preview.queue_free()
		drag_preview = null
	
	dragging_item_id = ""
	drag_source_type = ""
	drag_source_hero_index = -1
	drag_source_slot = ""


func _is_drop_on_inventory(pos: Vector2) -> bool:
	if inventory_panel and is_instance_valid(inventory_panel):
		return inventory_panel.get_global_rect().has_point(pos)
	if inventory_grid and is_instance_valid(inventory_grid):
		return inventory_grid.get_global_rect().has_point(pos)
	return false


func _try_move_equipment(item_id: String, from_hero_index: int, from_slot: String, to_hero_index: int, to_slot: String) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	if from_hero_index >= party.size() or to_hero_index >= party.size():
		return
	
	var from_hero: Hero = party[from_hero_index]
	var to_hero: Hero = party[to_hero_index]
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	var item_slot: String = str(data.get("slot", ""))
	
	# 타겟 슬롯 결정
	if to_slot.is_empty():
		to_slot = _determine_best_slot(to_hero, item_slot)
	
	# 슬롯 호환성 체크
	if not _is_slot_compatible(item_slot, to_slot):
		add_system_log("슬롯 불일치")
		return
	
	# 기존 장비 해제
	if not InventoryManager.unequip_item(from_hero, from_slot):
		add_system_log("해제 실패")
		return
	
	# 새로운 영웅에게 장착
	if InventoryManager.equip_item(to_hero, item_id, to_slot):
		if from_hero_index == to_hero_index:
			add_system_log("%s: %s 슬롯 변경" % [to_hero.hero_name, item_name])
		else:
			add_system_log("%s → %s: %s" % [from_hero.hero_name, to_hero.hero_name, item_name])
		update_party_display()
		refresh_inventory()
	else:
		# 장착 실패 시 원래대로
		InventoryManager.equip_item(from_hero, item_id, from_slot)
		add_system_log("이동 실패")


func _determine_best_slot(hero: Hero, item_slot: String) -> String:
	# 아이템의 기본 슬롯 결정
	var target_slot := item_slot
	
	if item_slot == "accessory":
		# 악세서리는 빈 슬롯 우선
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"
	
	return target_slot


func _find_drop_target(pos: Vector2) -> Dictionary:
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	# 각 파티 슬롯 체크
	for i in range(party_slots.size()):
		if i >= party.size():
			continue
		
		var slot: Control = party_slots[i]
		if not slot.visible:
			continue
		
		var slot_rect: Rect2 = slot.get_global_rect()
		
		if slot_rect.has_point(pos):
			# 특정 장비 슬롯 버튼 위인지 체크
			var equip_container: HBoxContainer = slot.find_child("EquipContainer", true, false)
			if equip_container:
				for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
					var equip_btn: Button = equip_container.find_child("Equip_" + slot_name, true, false)
					if equip_btn and equip_btn.get_global_rect().has_point(pos):
						return {"hero_index": i, "slot_name": slot_name}
			
			# 파티 슬롯 전체 (자동 슬롯 결정)
			return {"hero_index": i, "slot_name": ""}
	
	return {}


func _try_equip_to_hero(item_id: String, hero_index: int, target_slot: String) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero: Hero = party[hero_index]
	var data: Dictionary = DataManager.get_equipment(item_id)
	
	if data.is_empty():
		add_system_log("장비 데이터 없음")
		return
	
	var item_name: String = str(data.get("name", item_id))
	var item_slot: String = str(data.get("slot", ""))
	
	# 타겟 슬롯이 지정되지 않으면 자동 결정
	if target_slot.is_empty():
		target_slot = _determine_best_slot(hero, item_slot)
	
	# 슬롯 호환성 체크
	if not _is_slot_compatible(item_slot, target_slot):
		add_system_log("슬롯 불일치: %s → %s" % [item_slot, target_slot])
		return
	
	# 장착 시도
	if InventoryManager.equip_item(hero, item_id, target_slot):
		add_system_log("%s: %s 장착!" % [hero.hero_name, item_name])
		update_party_display()
		refresh_inventory()
	else:
		add_system_log("장착 실패: %s" % item_name)


func _is_slot_compatible(item_slot: String, target_slot: String) -> bool:
	if item_slot == target_slot:
		return true
	if item_slot == "accessory" and target_slot in ["acc1", "acc2"]:
		return true
	if item_slot == "weapon" and target_slot == "main_hand":
		return true
	if item_slot == "shield" and target_slot == "off_hand":
		return true
	return false


func _highlight_drop_targets(item_id: String, highlight: bool) -> void:
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_slot: String = str(data.get("slot", ""))
	
	for slot in party_slots:
		if not slot.visible:
			continue
		
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		
		if highlight:
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
		
		slot.add_theme_stylebox_override("panel", style)
#endregion


#region 컨텍스트 메뉴
func _show_equip_context_menu(item_id: String, pos: Vector2) -> void:
	_hide_context_menu()
	_hide_tooltip()
	
	context_menu_item_id = item_id
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	var item_slot: String = str(data.get("slot", ""))
	
	context_menu = PopupMenu.new()
	context_menu.add_theme_font_size_override("font_size", 10)
	
	# 타이틀 (비활성)
	context_menu.add_item("[ %s ]" % item_name, -1)
	context_menu.set_item_disabled(0, true)
	context_menu.add_separator()
	
	# 파티원 목록
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	for i in range(party.size()):
		var hero: Hero = party[i]
		
		# 현재 장착 정보
		var check_slot := item_slot
		if item_slot == "accessory":
			check_slot = "acc1"
		
		var equipped_id: String = hero.equipment.get(check_slot, "")
		var equipped_name: String = ""
		if not equipped_id.is_empty():
			var equipped_data: Dictionary = DataManager.get_equipment(equipped_id)
			equipped_name = str(equipped_data.get("name", ""))
		
		# 스탯 변화 계산
		var stat_change := _calculate_stat_change(hero, item_id, item_slot)
		
		var menu_text: String = hero.hero_name
		if not stat_change.is_empty():
			menu_text += "  %s" % stat_change
		if not equipped_name.is_empty():
			menu_text += "  [%s]" % equipped_name
		
		context_menu.add_item(menu_text, i)
		
		# 사망한 영웅은 비활성
		if hero.is_dead:
			context_menu.set_item_disabled(context_menu.item_count - 1, true)
	
	context_menu.add_separator()
	context_menu.add_item("취소", -2)
	
	# 시그널 연결
	context_menu.id_pressed.connect(_on_context_menu_selected)
	context_menu.popup_hide.connect(_hide_context_menu)
	
	# Control 노드에 추가
	var control_node = get_node_or_null("Control")
	if control_node:
		control_node.add_child(context_menu)
	else:
		add_child(context_menu)
	
	# 위치 조정 (화면 밖으로 안 나가게)
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()
	
	# 팝업 후 위치 재조정
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var menu_size: Vector2 = context_menu.size
	
	if pos.x + menu_size.x > viewport_size.x:
		context_menu.position.x = int(pos.x - menu_size.x)
	if pos.y + menu_size.y > viewport_size.y:
		context_menu.position.y = int(pos.y - menu_size.y)


func _calculate_stat_change(hero: Hero, item_id: String, item_slot: String) -> String:
	var new_data: Dictionary = DataManager.get_equipment(item_id)
	var new_stats: Dictionary = new_data.get("stats", {})
	
	var check_slot := item_slot
	if item_slot == "accessory":
		check_slot = "acc1"
	
	var equipped_id: String = hero.equipment.get(check_slot, "")
	var old_stats: Dictionary = {}
	if not equipped_id.is_empty():
		var old_data: Dictionary = DataManager.get_equipment(equipped_id)
		old_stats = old_data.get("stats", {})
	
	# 주요 스탯 변화만 표시
	var changes: Array = []
	
	# ATK 변화
	var atk_diff: int = int(new_stats.get("atk", 0)) - int(old_stats.get("atk", 0))
	if atk_diff != 0:
		if atk_diff > 0:
			changes.append("[color=lime]ATK+%d[/color]" % atk_diff)
		else:
			changes.append("[color=red]ATK%d[/color]" % atk_diff)
	
	# DEF 변화
	var def_diff: int = int(new_stats.get("def", 0)) - int(old_stats.get("def", 0))
	if def_diff != 0:
		if def_diff > 0:
			changes.append("[color=lime]DEF+%d[/color]" % def_diff)
		else:
			changes.append("[color=red]DEF%d[/color]" % def_diff)
	
	if changes.is_empty():
		return ""
	
	return " ".join(changes)


func _on_context_menu_selected(id: int) -> void:
	if id < 0:
		# 취소 또는 타이틀
		_hide_context_menu()
		return
	
	var party: Array = PartyManager.get_party() if PartyManager else []
	if id >= party.size():
		_hide_context_menu()
		return
	
	var hero: Hero = party[id]
	var item_id := context_menu_item_id
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_slot: String = str(data.get("slot", ""))
	
	# 타겟 슬롯 결정
	var target_slot := _determine_best_slot(hero, item_slot)
	
	# 장착
	_try_equip_to_hero(item_id, id, target_slot)
	
	_hide_context_menu()


func _hide_context_menu() -> void:
	if context_menu and is_instance_valid(context_menu):
		context_menu.queue_free()
		context_menu = null
	context_menu_item_id = ""


#region 인벤토리 클릭/호버
func _on_inventory_item_clicked(item_id: String) -> void:
	selected_item_id = item_id
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	var is_equipment: bool = not data.is_empty()
	
	if data.is_empty():
		data = DataManager.get_item(item_id)
	
	if data.is_empty():
		return
	
	var item_name: String = str(data.get("name", item_id))
	
	if is_equipment:
		# 장비면 첫 번째 파티원에게 자동 장착 시도
		var slot: String = str(data.get("slot", "main_hand"))
		var party: Array = PartyManager.get_party() if PartyManager else []
		
		if party.size() > 0:
			var hero = party[0]
			
			# 악세서리 슬롯 결정
			if slot == "accessory":
				if hero.equipment.get("acc1", "").is_empty():
					slot = "acc1"
				elif hero.equipment.get("acc2", "").is_empty():
					slot = "acc2"
				else:
					slot = "acc1"
			
			if InventoryManager.equip_item(hero, item_id, slot):
				add_system_log("%s: %s 장착" % [hero.hero_name, item_name])
				update_party_display()
				_hide_tooltip()
			else:
				add_system_log("장착 실패: %s" % item_name)
		else:
			# 로그에 정보 표시
			var stats: Dictionary = data.get("stats", {})
			var stat_text: String = ""
			for key in stats:
				stat_text += "%s+%d " % [key.to_upper(), int(stats[key])]
			add_stat_description(item_name, stat_text)
	else:
		# 소비 아이템 정보 표시
		var effect: String = str(data.get("effect", ""))
		add_stat_description(item_name, effect)


func _on_inventory_item_hover(item_id: String) -> void:
	# 드래그 중이면 툴팁 안 띄움
	if dragging_item_id:
		return
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return
	
	_show_tooltip(item_id)


func _on_inventory_item_hover_end() -> void:
	_hide_tooltip()
#endregion


#region 툴팁
func _show_tooltip(item_id: String) -> void:
	_hide_tooltip()
	
	tooltip = EquipmentTooltip.new()
	
	var control_node = get_node_or_null("Control")
	if control_node:
		control_node.add_child(tooltip)
	else:
		add_child(tooltip)
	
	var anchor: Control = null
	if inventory_panel and is_instance_valid(inventory_panel):
		anchor = inventory_panel
	elif inventory_grid and is_instance_valid(inventory_grid):
		anchor = inventory_grid
	
	tooltip.setup_for_item(item_id, anchor)


func _hide_tooltip() -> void:
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
		tooltip = null
#endregion


#region 로그 시스템
func add_log(message: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 9)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	log_container.add_child(label)
	
	while log_container.get_child_count() > MAX_LOG_LINES:
		var old: Node = log_container.get_child(0)
		old.queue_free()
	
	await get_tree().process_frame
	if log_scroll:
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func add_battle_log(message: String) -> void:
	add_log(message, Color.WHITE)


func add_damage_log(attacker: String, target: String, damage: int, is_crit: bool = false) -> void:
	var msg: String
	if is_crit:
		msg = "💥%s→%s 크리티컬 %d!" % [attacker, target, damage]
		add_log(msg, Color.YELLOW)
	else:
		msg = "⚔️%s→%s %d" % [attacker, target, damage]
		add_log(msg, Color.WHITE)


func add_heal_log(healer: String, target: String, amount: int) -> void:
	add_log("💚%s→%s +%d" % [healer, target, amount], Color.GREEN)


func add_defeat_log(target: String) -> void:
	add_log("💀%s 쓰러짐!" % target, Color.ORANGE_RED)


func add_exp_log(exp: int) -> void:
	add_log("✨+%d EXP" % exp, Color.CYAN)


func add_gold_log(gold: int) -> void:
	add_log("💰+%d G" % gold, Color.GOLD)


func add_item_log(item_name: String) -> void:
	add_log("📦%s 획득" % item_name, Color.MEDIUM_PURPLE)


func add_system_log(message: String) -> void:
	add_log(message, Color.GRAY)


func add_stat_description(stat_name: String, value: String) -> void:
	add_log("[%s] %s" % [stat_name, value], Color.LIGHT_BLUE)


func clear_logs() -> void:
	for child in log_container.get_children():
		child.queue_free()
#endregion


#region 시그널 핸들러
func _on_menu_pressed() -> void:
	menu_pressed.emit()


func _on_gold_changed(_new_gold: int) -> void:
	update_top_bar()


func _on_party_changed() -> void:
	update_party_display()


func _on_equip_clicked(hero_index: int, slot_name: String) -> void:
	equipment_slot_clicked.emit(hero_index, slot_name)
	
	# 장비 정보 로그에 표시
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero = party[hero_index]
	var equip_id: String = hero.equipment.get(slot_name, "")
	
	if equip_id.is_empty():
		add_system_log("%s의 %s: (없음)" % [hero.hero_name, slot_name])
	else:
		var equip_data: Dictionary = DataManager.get_equipment(equip_id)
		var equip_name: String = str(equip_data.get("name", equip_id))
		var stats: Dictionary = equip_data.get("stats", {})
		
		var stat_text: String = ""
		for stat_key in stats:
			stat_text += " %s+%d" % [stat_key.to_upper(), int(stats[stat_key])]
		
		add_stat_description(equip_name, stat_text)


func _on_skill_toggled(enabled: bool, hero_index: int, skill_id: String) -> void:
	skill_toggled.emit(hero_index, skill_id, enabled)
	
	# Hero 객체에 토글 상태 저장
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return
	
	var hero = party[hero_index]
	hero.skill_toggles[skill_id] = enabled
	
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = str(skill_data.get("name", skill_id))
	var status: String = "ON" if enabled else "OFF"
	add_system_log("%s: %s %s" % [hero.hero_name, skill_name, status])
#endregion
