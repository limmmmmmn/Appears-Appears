extends PanelContainer
class_name InventoryGridUI
## 인벤토리 그리드 UI: 아이템 표시, 클릭/호버 이벤트

signal item_clicked(item_id: String)
signal item_hover_started(item_id: String)
signal item_hover_ended()
signal item_drag_started(item_id: String)
signal item_right_clicked(item_id: String, global_pos: Vector2)

var grid: GridContainer
var tooltip: EquipmentTooltip = null

# 드래그 관련
var drag_start_pos: Vector2 = Vector2.ZERO
var pending_drag_item: String = ""

const DRAG_THRESHOLD: float = 5.0
const MIN_SLOTS: int = 8
const ITEM_SIZE: Vector2 = Vector2(28, 26)
const ITEM_FONT_SIZE: int = 14

const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️",
	"off_hand": "🛡️",
	"head": "⛑️",
	"body": "🛡️",
	"gloves": "🧤",
	"boots": "👢",
	"necklace": "📿",
	"ring1": "💍",
	"ring2": "💎"
}

const TYPE_ICONS: Dictionary = {
	# 무기류
	"sword": "🗡️",
	"dagger": "🔪",
	"axe": "🪓",
	"staff": "🪄",
	"bow": "🏹",
	# 방어구류
	"shield": "🛡️",
	"helmet": "⛑️",
	"light_armor": "👘",
	"medium_armor": "🦺",
	"heavy_armor": "🛡️",
	"robe": "👗",
	# 악세서리
	"ring": "💍",
	"necklace": "💍",
	"shoes": "💍",
	"acc": "💍"
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
	_setup_style()
	_create_grid()
	
	if InventoryManager:
		InventoryManager.inventory_changed.connect(refresh)


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)


func _create_grid() -> void:
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)


func refresh() -> void:
	if not grid:
		return
	
	# 기존 버튼 제거
	for child in grid.get_children():
		child.queue_free()
	
	# 아이템 버튼 생성
	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	
	for item_info in items:
		var btn := _create_item_button(item_info)
		grid.add_child(btn)
	
	# 빈 슬롯
	var empty_count: int = max(0, MIN_SLOTS - items.size())
	for i in range(empty_count):
		var empty := _create_empty_slot()
		grid.add_child(empty)


func _create_item_button(item_info: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = ITEM_SIZE
	
	var item_id: String = str(item_info.get("id", ""))
	var quantity: int = int(item_info.get("quantity", 1))
	var data: Dictionary = item_info.get("data", {})
	var rarity: String = str(data.get("rarity", "common"))
	var item_type: String = str(data.get("type", ""))
	var item_slot: String = str(data.get("slot", ""))
	
	# 아이콘 결정: type > slot > 기본
	var icon: String = TYPE_ICONS.get(item_type, "")
	if icon.is_empty():
		icon = SLOT_ICONS.get(item_slot, "📦")
	
	# 수량이 2개 이상이면 숫자 표시
	if quantity > 1:
		btn.text = icon + str(quantity)
	else:
		btn.text = icon
	
	btn.add_theme_font_size_override("font_size", ITEM_FONT_SIZE)
	btn.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	
	btn.set_meta("item_id", item_id)
	btn.set_meta("item_type", item_type)
	btn.set_meta("rarity", rarity)
	btn.set_meta("quantity", quantity)
	
	btn.gui_input.connect(_on_button_gui_input.bind(btn, item_id))
	btn.mouse_entered.connect(_on_item_hover.bind(btn, item_id))
	btn.mouse_exited.connect(_on_item_hover_end.bind(btn))

	# 기본 스타일 설정
	_apply_button_style(btn, false)

	return btn


func _create_empty_slot() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = ITEM_SIZE
	btn.text = ""
	btn.disabled = true
	btn.modulate = Color(0.3, 0.3, 0.3, 0.3)
	return btn


func _on_button_gui_input(event: InputEvent, btn: Button, item_id: String) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			item_right_clicked.emit(item_id, event.global_position)
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_start_pos = event.global_position
				pending_drag_item = item_id
			else:
				# 드래그 안 했으면 클릭
				if pending_drag_item == item_id:
					item_clicked.emit(item_id)
				pending_drag_item = ""

	elif event is InputEventMouseMotion:
		if pending_drag_item == item_id:
			var distance = event.global_position.distance_to(drag_start_pos)
			if distance > DRAG_THRESHOLD:
				item_drag_started.emit(item_id)
				pending_drag_item = ""


func _on_item_hover(btn: Button, item_id: String) -> void:
	_apply_button_style(btn, true)
	item_hover_started.emit(item_id)


func _on_item_hover_end(btn: Button) -> void:
	_apply_button_style(btn, false)
	item_hover_ended.emit()


func _apply_button_style(btn: Button, hovered: bool) -> void:
	## 버튼 스타일 적용 (호버 시 테두리)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.9)

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
		style.border_color = Color(0.3, 0.3, 0.35, 0.8)

	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)


#region 툴팁
func show_tooltip(item_id: String) -> void:
	hide_tooltip()
	
	# 장비 또는 소비 아이템 데이터 확인
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		data = DataManager.get_item(item_id)
	
	if data.is_empty():
		return
	
	tooltip = EquipmentTooltip.new()
	add_child(tooltip)
	tooltip.setup_for_item(item_id, self)


func hide_tooltip() -> void:
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
		tooltip = null
#endregion


func clear_pending_drag() -> void:
	pending_drag_item = ""
