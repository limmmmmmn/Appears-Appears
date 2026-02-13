extends Control
## Den(기지): 상단 정보 + 출발 버튼만 유지, 본문은 4x4 방 그리드

signal exit_requested

const GRID_COLS: int = 4
const GRID_ROWS: int = 4
const GRID_GAP: int = 10
const ROOM_RATIO: float = 1.5 # 3:2 (width:height)

const ROOM_BG: Color = Color(0.12, 0.11, 0.13)
const ROOM_BORDER: Color = Color(0.34, 0.32, 0.38)
const ROOM_PLACEHOLDER_TEXT: Color = Color(0.55, 0.55, 0.62)
const WORLD_MAP_NODES: Array[Dictionary] = [
	{"id": "north_ruins", "name": "북부 폐허", "pos": Vector2(0.22, 0.2)},
	{"id": "west_forest", "name": "서부 숲", "pos": Vector2(0.12, 0.55)},
	{"id": "central_plains", "name": "중앙 평원", "pos": Vector2(0.45, 0.48)},
	{"id": "east_mine", "name": "동부 광산", "pos": Vector2(0.75, 0.42)},
	{"id": "south_citadel", "name": "남부 성채", "pos": Vector2(0.58, 0.78)},
]
const SORTIE_EQUIP_ROWS: Array[Dictionary] = [
	{"slot": "main_hand", "label": "손(무기)"},
	{"slot": "off_hand", "label": "손(방패/보조무기)"},
	{"slot": "head", "label": "투구"},
	{"slot": "body", "label": "갑옷"},
	{"slot": "acc1", "label": "악세1"},
	{"slot": "acc2", "label": "악세2"},
]
const SORTIE_INV_TABS: Array[String] = ["무기", "방패", "투구", "갑옷", "악세"]

const WALKER_MIN_SPEED: float = 16.0
const WALKER_MAX_SPEED: float = 34.0
const WALKER_MIN_TURN_TIME: float = 1.0
const WALKER_MAX_TURN_TIME: float = 3.0
const WALKER_IDLE_CHANCE: float = 0.32
const WALKER_IDLE_MIN_TIME: float = 0.45
const WALKER_IDLE_MAX_TIME: float = 1.4
const WALKER_SCALE: float = 1.6
const WALKER_BASE_SIZE: Vector2 = Vector2(16.0, 24.0)

var gold_label: Label = null
var body_container: MarginContainer = null
var rooms_grid: GridContainer = null
var room_cells: Array[PanelContainer] = []

# 1번 방(테스트): 영웅 랜덤 좌우 이동
var room_one_view: Control = null
var room_one_sky: ColorRect = null
var room_one_floor: ColorRect = null
var room_one_floor_line: ColorRect = null
var room_one_walkers: Array[Dictionary] = []
var room_two_button: Button = null

var world_map_layer: CanvasLayer = null
var world_map_panel: PanelContainer = null
var world_map_nodes_root: Control = null
var world_map_selected_label: Label = null
var world_map_deploy_button: Button = null
var world_map_node_buttons: Array[Button] = []
var world_map_selected_id: String = ""

# 출격 준비 화면
var sortie_layer: CanvasLayer = null
var sortie_panel: PanelContainer = null
var sortie_party_slots: Array[Button] = []
var sortie_hero_list: VBoxContainer = null
var sortie_equipment_rows: Dictionary = {}
var sortie_stat_labels: Dictionary = {}
var sortie_inventory_tab_buttons: Array[Button] = []
var sortie_inventory_list: VBoxContainer = null
var sortie_inventory_hint: Label = null
var sortie_selected_hero_id: String = ""
var sortie_pending_hero_id: String = ""
var sortie_selected_item_id: String = ""
var sortie_selected_slot_index: int = 0
var sortie_inventory_tab: String = "무기"
var sortie_party_ids: Array[String] = ["", "", "", ""]


func _ready() -> void:
	if GameManager:
		GameManager.change_state(GameManager.GameState.DEN)
	_build_ui()
	_update_gold_display()
	if GameManager and GameManager.has_signal("gold_changed"):
		GameManager.gold_changed.connect(_on_gold_changed)
	if PartyManager and PartyManager.has_signal("party_changed"):
		PartyManager.party_changed.connect(_on_party_changed)
	resized.connect(_on_den_resized)
	_layout_rooms()
	call_deferred("_layout_rooms")
	_spawn_room_one_walkers()
	set_process(true)


func _process(delta: float) -> void:
	_update_room_one_walkers(delta)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_build_header(root)
	_build_rooms_grid(root)
	_build_world_map_popup()
	_build_sortie_prep_popup()


func _build_header(parent: VBoxContainer) -> void:
	var header := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", style)
	parent.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	header.add_child(hbox)

	var title := Label.new()
	title.text = "🏰 기지"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var gold_icon := Label.new()
	gold_icon.text = "💰"
	gold_icon.add_theme_font_size_override("font_size", 16)
	hbox.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	hbox.add_child(gold_label)

	var exit_btn := Button.new()
	exit_btn.text = "출발"
	exit_btn.custom_minimum_size = Vector2(74, 30)
	exit_btn.add_theme_font_size_override("font_size", 14)
	exit_btn.pressed.connect(_on_exit_pressed)
	hbox.add_child(exit_btn)


func _build_rooms_grid(parent: VBoxContainer) -> void:
	body_container = MarginContainer.new()
	body_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_container.add_theme_constant_override("margin_left", 16)
	body_container.add_theme_constant_override("margin_right", 16)
	body_container.add_theme_constant_override("margin_top", 16)
	body_container.add_theme_constant_override("margin_bottom", 16)
	parent.add_child(body_container)

	rooms_grid = GridContainer.new()
	rooms_grid.columns = GRID_COLS
	rooms_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rooms_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rooms_grid.add_theme_constant_override("h_separation", GRID_GAP)
	rooms_grid.add_theme_constant_override("v_separation", GRID_GAP)
	body_container.add_child(rooms_grid)

	room_cells.clear()
	for i in range(GRID_COLS * GRID_ROWS):
		var cell := _create_room_cell()
		rooms_grid.add_child(cell)
		room_cells.append(cell)
		if i == 0:
			_setup_room_one(cell)
		elif i == 1:
			_setup_room_two(cell)
		else:
			var placeholder := Label.new()
			placeholder.text = "빈 방"
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			placeholder.add_theme_font_size_override("font_size", 12)
			placeholder.add_theme_color_override("font_color", ROOM_PLACEHOLDER_TEXT)
			placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
			cell.add_child(placeholder)


func _create_room_cell() -> PanelContainer:
	var cell := PanelContainer.new()
	cell.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = ROOM_BG
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = ROOM_BORDER
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	cell.add_theme_stylebox_override("panel", style)
	return cell


func _setup_room_one(cell: PanelContainer) -> void:
	room_one_view = Control.new()
	room_one_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_one_view.clip_contents = true
	room_one_view.resized.connect(_layout_room_one)
	cell.add_child(room_one_view)

	room_one_sky = ColorRect.new()
	room_one_sky.color = Color(0.18, 0.17, 0.2)
	room_one_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_one_view.add_child(room_one_sky)

	room_one_floor = ColorRect.new()
	room_one_floor.color = Color(0.0, 0.0, 0.0, 0.0)
	room_one_floor.position = Vector2.ZERO
	room_one_floor.size = Vector2.ZERO
	room_one_view.add_child(room_one_floor)

	room_one_floor_line = ColorRect.new()
	room_one_floor_line.color = Color(0.5, 0.43, 0.3, 0.85)
	room_one_floor_line.position = Vector2.ZERO
	room_one_floor_line.size = Vector2.ZERO
	room_one_view.add_child(room_one_floor_line)

	var room_label := Label.new()
	room_label.text = "1번 방 · 광장"
	room_label.position = Vector2(6, 4)
	room_label.add_theme_font_size_override("font_size", 10)
	room_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92, 0.85))
	room_one_view.add_child(room_label)


func _setup_room_two(cell: PanelContainer) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.16, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell.add_child(bg)

	room_two_button = Button.new()
	room_two_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_two_button.text = "2번 방 · 지휘실\n(클릭: 세계지도)"
	room_two_button.add_theme_font_size_override("font_size", 12)
	room_two_button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	normal.content_margin_left = 8
	normal.content_margin_top = 8
	room_two_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.7, 0.7, 0.9, 0.07)
	room_two_button.add_theme_stylebox_override("hover", hover)
	room_two_button.pressed.connect(_open_world_map_popup)
	cell.add_child(room_two_button)


func _build_world_map_popup() -> void:
	world_map_layer = CanvasLayer.new()
	world_map_layer.layer = 100
	world_map_layer.visible = false
	add_child(world_map_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.gui_input.connect(_on_world_map_dim_input)
	world_map_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_map_layer.add_child(center)

	world_map_panel = PanelContainer.new()
	world_map_panel.custom_minimum_size = Vector2(760, 460)
	world_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.14, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.42, 0.4, 0.52)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	world_map_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(world_map_panel)

	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	world_map_panel.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "세계지도"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.9, 0.74))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(_close_world_map_popup)
	top.add_child(close_btn)

	var map_frame := PanelContainer.new()
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.12, 0.13, 0.17, 1.0)
	frame_style.border_width_left = 1
	frame_style.border_width_top = 1
	frame_style.border_width_right = 1
	frame_style.border_width_bottom = 1
	frame_style.border_color = Color(0.3, 0.35, 0.42)
	map_frame.add_theme_stylebox_override("panel", frame_style)
	root.add_child(map_frame)

	world_map_nodes_root = Control.new()
	world_map_nodes_root.custom_minimum_size = Vector2(720, 340)
	world_map_nodes_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_map_nodes_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_child(world_map_nodes_root)

	world_map_selected_label = Label.new()
	world_map_selected_label.text = "노드를 선택하세요."
	world_map_selected_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	root.add_child(world_map_selected_label)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bottom_spacer)
	world_map_deploy_button = Button.new()
	world_map_deploy_button.text = "출격 준비"
	world_map_deploy_button.visible = false
	world_map_deploy_button.focus_mode = Control.FOCUS_NONE
	world_map_deploy_button.add_theme_font_size_override("font_size", 14)
	world_map_deploy_button.pressed.connect(_on_world_map_deploy_pressed)
	bottom.add_child(world_map_deploy_button)

	_build_world_map_nodes()


func _build_world_map_nodes() -> void:
	if world_map_nodes_root == null:
		return
	for c in world_map_nodes_root.get_children():
		c.queue_free()
	world_map_node_buttons.clear()

	var area: Vector2 = world_map_nodes_root.custom_minimum_size
	for node_data in WORLD_MAP_NODES:
		var btn := Button.new()
		btn.size = Vector2(22, 22)
		btn.custom_minimum_size = Vector2(22, 22)
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("node_id", str(node_data.get("id", "")))
		btn.tooltip_text = str(node_data.get("name", "지역"))
		var p: Vector2 = node_data.get("pos", Vector2(0.5, 0.5))
		btn.position = Vector2(
			clampf(p.x, 0.03, 0.97) * area.x - 11.0,
			clampf(p.y, 0.03, 0.97) * area.y - 11.0
		)
		btn.pressed.connect(_on_world_map_node_pressed.bind(str(node_data.get("id", "")), str(node_data.get("name", ""))))
		_apply_world_node_style(btn, false)
		world_map_nodes_root.add_child(btn)
		world_map_node_buttons.append(btn)


func _apply_world_node_style(btn: Button, selected: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1.0, 0.86, 0.38) if selected else Color(0.75, 0.77, 0.86)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = Color(1.0, 0.95, 0.7) if selected else Color(0.36, 0.4, 0.5)
	s.corner_radius_top_left = 11
	s.corner_radius_top_right = 11
	s.corner_radius_bottom_left = 11
	s.corner_radius_bottom_right = 11
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)


func _open_world_map_popup() -> void:
	world_map_selected_id = ""
	if world_map_selected_label:
		world_map_selected_label.text = "노드를 선택하세요."
	if world_map_deploy_button:
		world_map_deploy_button.visible = false
	for btn in world_map_node_buttons:
		_apply_world_node_style(btn, false)
	if world_map_layer:
		world_map_layer.visible = true


func _close_world_map_popup() -> void:
	if world_map_layer:
		world_map_layer.visible = false


func _on_world_map_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_world_map_popup()


func _on_world_map_node_pressed(node_id: String, node_name: String) -> void:
	world_map_selected_id = node_id
	if world_map_selected_label:
		world_map_selected_label.text = "선택 지역: %s" % node_name
	if world_map_deploy_button:
		world_map_deploy_button.visible = true

	for btn in world_map_node_buttons:
		var is_selected := (str(btn.get_meta("node_id", "")) == node_id)
		_apply_world_node_style(btn, is_selected)


func _on_world_map_deploy_pressed() -> void:
	if world_map_selected_id.is_empty():
		return
	_close_world_map_popup()
	_open_sortie_prep()


func _build_sortie_prep_popup() -> void:
	sortie_layer = CanvasLayer.new()
	sortie_layer.layer = 120
	sortie_layer.visible = false
	add_child(sortie_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	sortie_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	sortie_layer.add_child(center)

	sortie_panel = PanelContainer.new()
	sortie_panel.custom_minimum_size = Vector2(1240, 680)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.border_color = Color(0.45, 0.42, 0.5)
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	sortie_panel.add_theme_stylebox_override("panel", s)
	center.add_child(sortie_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sortie_panel.add_child(root)

	var title := Label.new()
	title.text = "출격 준비"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	root.add_child(title)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	# 좌측 컬럼: 출격 영웅(상단) + 영웅 목록(하단)
	var hero_col := VBoxContainer.new()
	hero_col.custom_minimum_size.x = 320
	hero_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_col.add_theme_constant_override("separation", 8)
	content.add_child(hero_col)

	var hero_top := PanelContainer.new()
	hero_top.custom_minimum_size.y = 170
	var hero_top_style := StyleBoxFlat.new()
	hero_top_style.bg_color = Color(0.13, 0.13, 0.18, 0.95)
	hero_top_style.border_width_left = 1
	hero_top_style.border_width_top = 1
	hero_top_style.border_width_right = 1
	hero_top_style.border_width_bottom = 1
	hero_top_style.border_color = Color(0.3, 0.32, 0.42)
	hero_top_style.content_margin_left = 8
	hero_top_style.content_margin_right = 8
	hero_top_style.content_margin_top = 8
	hero_top_style.content_margin_bottom = 8
	hero_top.add_theme_stylebox_override("panel", hero_top_style)
	hero_col.add_child(hero_top)

	var hero_top_v := VBoxContainer.new()
	hero_top_v.add_theme_constant_override("separation", 6)
	hero_top.add_child(hero_top_v)
	var top_title := Label.new()
	top_title.text = "출격 영웅"
	top_title.add_theme_font_size_override("font_size", 14)
	hero_top_v.add_child(top_title)

	var slot_grid := GridContainer.new()
	slot_grid.columns = 2
	slot_grid.add_theme_constant_override("h_separation", 6)
	slot_grid.add_theme_constant_override("v_separation", 6)
	hero_top_v.add_child(slot_grid)
	sortie_party_slots.clear()
	for i in range(4):
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = Vector2(146, 50)
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.text = "빈 슬롯"
		slot_btn.pressed.connect(_on_sortie_party_slot_pressed.bind(i))
		slot_grid.add_child(slot_btn)
		sortie_party_slots.append(slot_btn)

	var hero_bottom := PanelContainer.new()
	hero_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero_bottom_style := hero_top_style.duplicate()
	hero_bottom.add_theme_stylebox_override("panel", hero_bottom_style)
	hero_col.add_child(hero_bottom)

	var hero_bottom_v := VBoxContainer.new()
	hero_bottom_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_bottom_v.add_theme_constant_override("separation", 6)
	hero_bottom.add_child(hero_bottom_v)
	var hero_list_title := Label.new()
	hero_list_title.text = "영웅 목록"
	hero_list_title.add_theme_font_size_override("font_size", 14)
	hero_bottom_v.add_child(hero_list_title)
	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_bottom_v.add_child(hero_scroll)
	sortie_hero_list = VBoxContainer.new()
	sortie_hero_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sortie_hero_list.add_theme_constant_override("separation", 4)
	hero_scroll.add_child(sortie_hero_list)

	# 중앙 컬럼: 정비 (장비 6줄 + 스탯)
	var equip_col := PanelContainer.new()
	equip_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var equip_col_style := hero_top_style.duplicate()
	equip_col.add_theme_stylebox_override("panel", equip_col_style)
	content.add_child(equip_col)

	var equip_v := VBoxContainer.new()
	equip_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_v.add_theme_constant_override("separation", 8)
	equip_col.add_child(equip_v)
	var equip_title := Label.new()
	equip_title.text = "정비"
	equip_title.add_theme_font_size_override("font_size", 14)
	equip_v.add_child(equip_title)

	var equip_rows_panel := PanelContainer.new()
	var equip_rows_style := StyleBoxFlat.new()
	equip_rows_style.bg_color = Color(0.09, 0.09, 0.13, 0.9)
	equip_rows_style.border_width_left = 1
	equip_rows_style.border_width_top = 1
	equip_rows_style.border_width_right = 1
	equip_rows_style.border_width_bottom = 1
	equip_rows_style.border_color = Color(0.26, 0.28, 0.36)
	equip_rows_style.content_margin_left = 8
	equip_rows_style.content_margin_right = 8
	equip_rows_style.content_margin_top = 8
	equip_rows_style.content_margin_bottom = 8
	equip_rows_panel.add_theme_stylebox_override("panel", equip_rows_style)
	equip_v.add_child(equip_rows_panel)

	var equip_rows_v := VBoxContainer.new()
	equip_rows_v.add_theme_constant_override("separation", 4)
	equip_rows_panel.add_child(equip_rows_v)
	sortie_equipment_rows.clear()
	for row in SORTIE_EQUIP_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		equip_rows_v.add_child(line)
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size.x = 120
		name_lbl.text = str(row.get("label", ""))
		name_lbl.add_theme_font_size_override("font_size", 12)
		line.add_child(name_lbl)
		var value_lbl := Label.new()
		value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_lbl.text = "비어 있음"
		value_lbl.add_theme_font_size_override("font_size", 12)
		value_lbl.add_theme_color_override("font_color", Color(0.8, 0.83, 0.9))
		line.add_child(value_lbl)
		sortie_equipment_rows[str(row.get("slot", ""))] = value_lbl

	var stat_panel := PanelContainer.new()
	stat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_panel.add_theme_stylebox_override("panel", equip_rows_style.duplicate())
	equip_v.add_child(stat_panel)

	var stat_v := VBoxContainer.new()
	stat_v.add_theme_constant_override("separation", 4)
	stat_panel.add_child(stat_v)
	var stat_title := Label.new()
	stat_title.text = "스탯"
	stat_title.add_theme_font_size_override("font_size", 13)
	stat_v.add_child(stat_title)
	sortie_stat_labels.clear()
	for key in ["ATK", "DEF", "MATK", "SPD", "HP"]:
		var stat_lbl := Label.new()
		stat_lbl.add_theme_font_size_override("font_size", 12)
		stat_v.add_child(stat_lbl)
		sortie_stat_labels[key] = stat_lbl

	# 우측 컬럼: 인벤토리 (5탭 + 목록)
	var inv_col := PanelContainer.new()
	inv_col.custom_minimum_size.x = 360
	inv_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_col.add_theme_stylebox_override("panel", hero_top_style.duplicate())
	content.add_child(inv_col)

	var inv_v := VBoxContainer.new()
	inv_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_v.add_theme_constant_override("separation", 8)
	inv_col.add_child(inv_v)
	var inv_title := Label.new()
	inv_title.text = "인벤토리"
	inv_title.add_theme_font_size_override("font_size", 14)
	inv_v.add_child(inv_title)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	inv_v.add_child(tab_row)
	sortie_inventory_tab_buttons.clear()
	for tab_name in SORTIE_INV_TABS:
		var tab_btn := Button.new()
		tab_btn.text = tab_name
		tab_btn.custom_minimum_size.x = 62
		tab_btn.focus_mode = Control.FOCUS_NONE
		tab_btn.pressed.connect(_on_sortie_inventory_tab_pressed.bind(tab_name))
		tab_row.add_child(tab_btn)
		sortie_inventory_tab_buttons.append(tab_btn)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_v.add_child(inv_scroll)
	sortie_inventory_list = VBoxContainer.new()
	sortie_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sortie_inventory_list.add_theme_constant_override("separation", 4)
	inv_scroll.add_child(sortie_inventory_list)

	sortie_inventory_hint = Label.new()
	sortie_inventory_hint.text = "아이템을 선택하면 스탯 비교가 표시됩니다."
	sortie_inventory_hint.add_theme_font_size_override("font_size", 11)
	sortie_inventory_hint.add_theme_color_override("font_color", Color(0.68, 0.7, 0.78))
	inv_v.add_child(sortie_inventory_hint)

	# 하단 버튼
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(bottom_spacer)
	var back_btn := Button.new()
	back_btn.text = "돌아가기"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(_close_sortie_prep)
	bottom.add_child(back_btn)
	var start_btn := Button.new()
	start_btn.text = "출발"
	start_btn.focus_mode = Control.FOCUS_NONE
	start_btn.pressed.connect(_on_sortie_start_pressed)
	bottom.add_child(start_btn)


func _open_sortie_prep() -> void:
	sortie_selected_item_id = ""
	sortie_inventory_tab = SORTIE_INV_TABS[0]
	sortie_pending_hero_id = ""
	sortie_selected_hero_id = ""
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(sortie_party_ids.size()):
		sortie_party_ids[i] = str(party[i].id) if i < party.size() else ""
	for i in range(sortie_party_ids.size()):
		if not sortie_party_ids[i].is_empty():
			sortie_selected_slot_index = i
			break
	for id in sortie_party_ids:
		if not id.is_empty():
			sortie_selected_hero_id = id
			break
	if sortie_layer:
		sortie_layer.visible = true
	_refresh_sortie_ui()


func _close_sortie_prep() -> void:
	if sortie_layer:
		sortie_layer.visible = false


func _get_recruited_heroes() -> Array:
	var arr: Array = []
	var seen: Dictionary = {}
	if PartyManager == null:
		return arr
	for h_any in PartyManager.get_party():
		var h: Hero = h_any as Hero
		if h == null or seen.has(h.id):
			continue
		seen[h.id] = true
		arr.append(h)
	if PartyManager.has_method("get_bench_heroes"):
		for h_any in PartyManager.get_bench_heroes():
			var h: Hero = h_any as Hero
			if h == null or seen.has(h.id):
				continue
			seen[h.id] = true
			arr.append(h)
	return arr


func _refresh_sortie_ui() -> void:
	_refresh_sortie_party_slots()
	_refresh_sortie_hero_list()
	_refresh_sortie_equipment_rows()
	_refresh_sortie_stats()
	_refresh_sortie_inventory_tabs()
	_refresh_sortie_inventory()


func _refresh_sortie_party_slots() -> void:
	for i in range(sortie_party_slots.size()):
		var btn: Button = sortie_party_slots[i]
		var hero_id: String = sortie_party_ids[i]
		if hero_id.is_empty():
			btn.text = "빈 슬롯"
		else:
			var hero := _find_recruited_hero_by_id(hero_id)
			btn.text = hero.hero_name if hero else hero_id
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.12, 0.12, 0.18, 0.92) if i == sortie_selected_slot_index else Color(0.1, 0.1, 0.14, 0.9)
		normal.border_width_left = 1
		normal.border_width_top = 1
		normal.border_width_right = 1
		normal.border_width_bottom = 1
		normal.border_color = Color(0.95, 0.8, 0.35, 0.95) if i == sortie_selected_slot_index else Color(0.3, 0.32, 0.4, 0.9)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", normal)


func _refresh_sortie_hero_list() -> void:
	if sortie_hero_list == null:
		return
	for c in sortie_hero_list.get_children():
		c.queue_free()

	for hero_any in _get_recruited_heroes():
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var assigned_slot := sortie_party_ids.find(hero.id)
		var marker := "[%d] " % int(assigned_slot + 1) if assigned_slot >= 0 else ""
		btn.text = "%s%s  Lv.%d" % [marker, hero.hero_name, int(hero.level)]
		if hero.id == sortie_selected_hero_id:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.25, 0.22, 0.14, 0.95)
			selected_style.border_width_left = 1
			selected_style.border_width_top = 1
			selected_style.border_width_right = 1
			selected_style.border_width_bottom = 1
			selected_style.border_color = Color(0.95, 0.8, 0.35, 0.95)
			btn.add_theme_stylebox_override("normal", selected_style)
			btn.add_theme_stylebox_override("hover", selected_style)
		btn.pressed.connect(_on_sortie_roster_clicked.bind(hero.id))
		sortie_hero_list.add_child(btn)


func _refresh_sortie_equipment_rows() -> void:
	var hero := _find_recruited_hero_by_id(sortie_selected_hero_id)
	for row in SORTIE_EQUIP_ROWS:
		var slot: String = str(row.get("slot", ""))
		var value_lbl: Label = sortie_equipment_rows.get(slot) as Label
		if value_lbl == null:
			continue
		if hero == null:
			value_lbl.text = "비어 있음"
			continue
		var equip_id: String = str(hero.equipment.get(slot, ""))
		if equip_id.is_empty():
			value_lbl.text = "비어 있음"
			continue
		var data: Dictionary = DataManager.get_equipment(equip_id)
		value_lbl.text = str(data.get("name", equip_id))


func _refresh_sortie_stats() -> void:
	if sortie_stat_labels.is_empty():
		return
	var hero := _find_recruited_hero_by_id(sortie_selected_hero_id)
	if hero == null:
		for key in sortie_stat_labels.keys():
			var empty_lbl: Label = sortie_stat_labels[key]
			empty_lbl.text = "%s -" % str(key)
		return
	var base := {
		"ATK": hero.get_atk(),
		"DEF": hero.get_def(),
		"MATK": hero.get_magic_attack(),
		"SPD": hero.get_spd(),
		"HP": hero.get_max_hp(),
	}
	var delta := _calc_sortie_item_delta(hero, sortie_selected_item_id)
	for key in ["ATK", "DEF", "MATK", "SPD", "HP"]:
		var lbl: Label = sortie_stat_labels.get(key) as Label
		if lbl == null:
			continue
		var cur: int = int(base.get(key, 0))
		var diff: int = int(delta.get(key, 0))
		if diff == 0:
			lbl.text = "%s %d" % [key, cur]
			lbl.add_theme_color_override("font_color", Color(0.83, 0.85, 0.9))
		else:
			var sign := "+" if diff > 0 else ""
			lbl.text = "%s %d (%s%d)" % [key, cur, sign, diff]
			lbl.add_theme_color_override("font_color", Color(0.5, 0.95, 0.56) if diff > 0 else Color(1.0, 0.55, 0.55))


func _refresh_sortie_inventory_tabs() -> void:
	for btn in sortie_inventory_tab_buttons:
		if btn == null:
			continue
		var selected: bool = (btn.text == sortie_inventory_tab)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.17, 0.1, 0.95) if selected else Color(0.11, 0.11, 0.15, 0.95)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.95, 0.8, 0.35) if selected else Color(0.32, 0.34, 0.4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)


func _refresh_sortie_inventory() -> void:
	if sortie_inventory_list == null:
		return
	for c in sortie_inventory_list.get_children():
		c.queue_free()
	if InventoryManager == null:
		return
	var equips: Array = InventoryManager.get_equipment_items()
	equips = equips.filter(func(it): return _sortie_item_group(str(it.get("data", {}).get("slot", ""))) == sortie_inventory_tab)
	equips.sort_custom(func(a, b): return str(a.get("data", {}).get("name", a.get("id", ""))) < str(b.get("data", {}).get("name", b.get("id", ""))))
	if equips.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "표시할 장비 없음"
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.62, 0.64, 0.72))
		sortie_inventory_list.add_child(empty_lbl)
		if sortie_inventory_hint:
			sortie_inventory_hint.text = "%s 탭 장비가 없습니다." % sortie_inventory_tab
		return
	for e_any in equips:
		var e: Dictionary = e_any
		var item_id: String = str(e.get("id", ""))
		var data: Dictionary = e.get("data", {})
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s x%d" % [str(data.get("name", item_id)), int(e.get("quantity", 0))]
		if item_id == sortie_selected_item_id:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.22, 0.19, 0.11, 0.95)
			selected_style.border_width_left = 1
			selected_style.border_width_top = 1
			selected_style.border_width_right = 1
			selected_style.border_width_bottom = 1
			selected_style.border_color = Color(0.95, 0.8, 0.35)
			btn.add_theme_stylebox_override("normal", selected_style)
			btn.add_theme_stylebox_override("hover", selected_style)
		btn.pressed.connect(_on_sortie_inventory_item_pressed.bind(item_id))
		sortie_inventory_list.add_child(btn)
	if sortie_inventory_hint:
		var selected_data := DataManager.get_equipment(sortie_selected_item_id) if not sortie_selected_item_id.is_empty() else {}
		if selected_data.is_empty():
			sortie_inventory_hint.text = "아이템을 선택하면 스탯 비교가 표시됩니다."
		else:
			sortie_inventory_hint.text = "선택: %s" % str(selected_data.get("name", sortie_selected_item_id))


func _on_sortie_roster_clicked(hero_id: String) -> void:
	sortie_selected_hero_id = hero_id
	sortie_pending_hero_id = hero_id
	if sortie_party_ids.find(hero_id) < 0:
		sortie_party_ids[sortie_selected_slot_index] = hero_id
		for i in range(sortie_party_ids.size()):
			if i != sortie_selected_slot_index and sortie_party_ids[i] == hero_id:
				sortie_party_ids[i] = ""
	_refresh_sortie_ui()


func _on_sortie_party_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= sortie_party_ids.size():
		return
	sortie_selected_slot_index = slot_index
	if not sortie_pending_hero_id.is_empty():
		for i in range(sortie_party_ids.size()):
			if sortie_party_ids[i] == sortie_pending_hero_id:
				sortie_party_ids[i] = ""
		sortie_party_ids[slot_index] = sortie_pending_hero_id
		sortie_selected_hero_id = sortie_pending_hero_id
		sortie_pending_hero_id = ""
	else:
		var id: String = sortie_party_ids[slot_index]
		if id == sortie_selected_hero_id:
			sortie_party_ids[slot_index] = ""
		else:
			sortie_selected_hero_id = id
	_refresh_sortie_ui()


func _on_sortie_inventory_tab_pressed(tab_name: String) -> void:
	sortie_inventory_tab = tab_name
	sortie_selected_item_id = ""
	_refresh_sortie_inventory_tabs()
	_refresh_sortie_inventory()
	_refresh_sortie_stats()


func _on_sortie_inventory_item_pressed(item_id: String) -> void:
	sortie_selected_item_id = item_id
	_refresh_sortie_inventory()
	_refresh_sortie_stats()


func _find_recruited_hero_by_id(hero_id: String) -> Hero:
	if hero_id.is_empty():
		return null
	for hero_any in _get_recruited_heroes():
		var hero: Hero = hero_any as Hero
		if hero and hero.id == hero_id:
			return hero
	return null


func _sortie_item_group(raw_slot: String) -> String:
	var slot := Hero.normalize_equipment_slot(raw_slot)
	match slot:
		"main_hand":
			return "무기"
		"off_hand":
			return "방패"
		"head":
			return "투구"
		"body":
			return "갑옷"
		_:
			return "악세"


func _resolve_sortie_target_slot(hero: Hero, data: Dictionary) -> String:
	var slot := Hero.normalize_equipment_slot(str(data.get("slot", "")))
	if slot == "acc":
		var left: String = str(hero.equipment.get("acc1", ""))
		var right: String = str(hero.equipment.get("acc2", ""))
		if left.is_empty():
			return "acc1"
		if right.is_empty():
			return "acc2"
		return "acc1"
	if slot == "off_hand" and hero.is_off_hand_disabled():
		return ""
	return slot


func _calc_sortie_item_delta(hero: Hero, item_id: String) -> Dictionary:
	var result := {"ATK": 0, "DEF": 0, "MATK": 0, "SPD": 0, "HP": 0}
	if hero == null or item_id.is_empty():
		return result
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return result
	var target_slot: String = _resolve_sortie_target_slot(hero, data)
	if target_slot.is_empty():
		return result
	var current_id: String = str(hero.equipment.get(target_slot, ""))
	var old_data: Dictionary = DataManager.get_equipment(current_id)
	var new_stats: Dictionary = data.get("stats", {})
	var old_stats: Dictionary = old_data.get("stats", {})

	result["ATK"] = int(new_stats.get("atk", 0)) - int(old_stats.get("atk", 0))
	result["DEF"] = int(new_stats.get("p_def", new_stats.get("def", 0))) - int(old_stats.get("p_def", old_stats.get("def", 0)))
	result["SPD"] = int(new_stats.get("spd", 0)) - int(old_stats.get("spd", 0))
	result["HP"] = int(new_stats.get("hp", 0)) - int(old_stats.get("hp", 0))
	var new_matk: int = int(new_stats.get("mag", 0)) + int(new_stats.get("int", 0)) + int(new_stats.get("wis", 0))
	var old_matk: int = int(old_stats.get("mag", 0)) + int(old_stats.get("int", 0)) + int(old_stats.get("wis", 0))
	result["MATK"] = new_matk - old_matk
	return result


func _on_sortie_start_pressed() -> void:
	if PartyManager == null:
		return
	var all: Array = _get_recruited_heroes()
	var chosen: Array[Hero] = []
	for hero_id in sortie_party_ids:
		if hero_id.is_empty():
			continue
		for h_any in all:
			var h: Hero = h_any
			if h and h.id == hero_id and not chosen.has(h):
				chosen.append(h)
				break
	var required_count: int = mini(4, all.size())
	if chosen.size() < required_count:
		return
	var reserve: Array[Hero] = []
	for h_any in all:
		var h: Hero = h_any
		if h and not chosen.has(h):
			reserve.append(h)
	PartyManager.party = chosen
	PartyManager.reserve_party = reserve
	PartyManager.party_changed.emit()
	_close_sortie_prep()
	GameManager.go_to_field()


func _layout_rooms() -> void:
	if rooms_grid == null or body_container == null:
		return

	var area_size: Vector2 = body_container.size
	if area_size.x <= 64.0 or area_size.y <= 64.0:
		var vp: Vector2 = get_viewport_rect().size
		area_size = Vector2(maxf(0.0, vp.x - 32.0), maxf(0.0, vp.y - 110.0))
		if area_size.x <= 64.0 or area_size.y <= 64.0:
			return

	# 화면을 거의 채우되, 약간의 여백은 유지
	var fill_w: float = area_size.x * 0.93
	var fill_h: float = area_size.y * 0.9
	var avail_w: float = fill_w - float(GRID_GAP * (GRID_COLS - 1))
	var avail_h: float = fill_h - float(GRID_GAP * (GRID_ROWS - 1))
	var by_width: float = avail_w / float(GRID_COLS)
	var by_height: float = (avail_h / float(GRID_ROWS)) * ROOM_RATIO
	var cell_w: float = floor(minf(by_width, by_height))
	var cell_h: float = floor(cell_w / ROOM_RATIO)
	if cell_w < 96.0:
		cell_w = 96.0
		cell_h = floor(cell_w / ROOM_RATIO)

	for cell in room_cells:
		if cell and is_instance_valid(cell):
			cell.custom_minimum_size = Vector2(cell_w, cell_h)

	call_deferred("_layout_room_one")


func _layout_room_one() -> void:
	if room_one_view == null or room_one_floor == null:
		return
	var w: float = room_one_view.size.x
	var h: float = room_one_view.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var floor_y: float = floor(h * 0.8)
	room_one_floor.position = Vector2(0.0, floor_y)
	room_one_floor.size = Vector2(w, 0.0)
	if room_one_floor_line:
		room_one_floor_line.position = Vector2(-1.0, floor_y - 1.0)
		room_one_floor_line.size = Vector2(w + 2.0, 2.0)
	_refresh_room_one_walker_bounds()


func _spawn_room_one_walkers() -> void:
	if room_one_view == null:
		return

	for walker in room_one_walkers:
		var node: AnimatedSprite2D = walker.get("node") as AnimatedSprite2D
		if node and is_instance_valid(node):
			node.queue_free()
	room_one_walkers.clear()

	if PartyManager == null:
		return
	var heroes: Array = []
	heroes.append_array(PartyManager.get_party())
	if PartyManager.has_method("get_bench_heroes"):
		heroes.append_array(PartyManager.get_bench_heroes())
	if heroes.is_empty():
		return

	var max_count: int = mini(6, heroes.size())
	for i in range(max_count):
		var hero: Hero = heroes[i] as Hero
		if hero == null:
			continue
		var walker := AnimatedSprite2D.new()
		walker.centered = false
		walker.scale = Vector2(WALKER_SCALE, WALKER_SCALE)
		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id) if SpriteManager else null
		if frames:
			walker.sprite_frames = frames
		room_one_view.add_child(walker)

		var dir: int = -1 if randf() < 0.5 else 1
		var anim_name: String = "walk_right" if dir > 0 else "walk_left"
		if walker.sprite_frames and walker.sprite_frames.has_animation(anim_name):
			walker.play(anim_name)
		var walker_size: Vector2 = WALKER_BASE_SIZE
		if walker.sprite_frames and walker.sprite_frames.has_animation("walk_right") and walker.sprite_frames.get_frame_count("walk_right") > 0:
			var frame_tex: Texture2D = walker.sprite_frames.get_frame_texture("walk_right", 0)
			if frame_tex:
				walker_size = frame_tex.get_size()
		walker_size *= WALKER_SCALE
		room_one_walkers.append({
			"node": walker,
			"dir": dir,
			"speed": randf_range(WALKER_MIN_SPEED, WALKER_MAX_SPEED),
			"turn_timer": randf_range(WALKER_MIN_TURN_TIME, WALKER_MAX_TURN_TIME),
			"is_idle": false,
			"idle_timer": 0.0,
			"min_x": 4.0,
			"max_x": 32.0,
			"y": 0.0,
			"w": walker_size.x,
			"h": walker_size.y,
			"spawn_index": i,
			"initialized": false,
		})

	call_deferred("_layout_room_one")


func _refresh_room_one_walker_bounds() -> void:
	if room_one_view == null:
		return
	if room_one_walkers.is_empty():
		return

	var floor_y: float = room_one_floor.position.y
	for i in range(room_one_walkers.size()):
		var w: Dictionary = room_one_walkers[i]
		var node: AnimatedSprite2D = w.get("node") as AnimatedSprite2D
		if node == null or not is_instance_valid(node):
			continue
		var min_x: float = 2.0
		var walker_w: float = float(w.get("w", WALKER_BASE_SIZE.x * WALKER_SCALE))
		var walker_h: float = float(w.get("h", WALKER_BASE_SIZE.y * WALKER_SCALE))
		var max_x: float = maxf(min_x + 1.0, room_one_view.size.x - walker_w - 2.0)
		var y: float = floor_y - walker_h + 8.0
		w["min_x"] = min_x
		w["max_x"] = max_x
		w["y"] = y
		var initialized: bool = bool(w.get("initialized", false))
		if not initialized:
			var count: int = maxi(1, room_one_walkers.size())
			var idx: int = int(w.get("spawn_index", i))
			var t: float = (float(idx) + 0.5) / float(count)
			var base_x: float = lerpf(min_x, max_x, t)
			var jitter: float = randf_range(-10.0, 10.0)
			node.position.x = clampf(base_x + jitter, min_x, max_x)
			w["initialized"] = true
		elif node.position.x < min_x or node.position.x > max_x:
			node.position.x = clampf(node.position.x, min_x, max_x)
		node.position.y = y
		var dir_now: int = int(w.get("dir", 1))
		_play_walker_anim(node, dir_now)
		room_one_walkers[i] = w


func _update_room_one_walkers(delta: float) -> void:
	if room_one_walkers.is_empty():
		return

	for i in range(room_one_walkers.size()):
		var w: Dictionary = room_one_walkers[i]
		var node: AnimatedSprite2D = w.get("node") as AnimatedSprite2D
		if node == null or not is_instance_valid(node):
			continue

		var prev_dir: int = int(w.get("dir", 1))
		var dir: int = prev_dir
		var speed: float = float(w.get("speed", WALKER_MIN_SPEED))
		var min_x: float = float(w.get("min_x", 4.0))
		var max_x: float = float(w.get("max_x", min_x + 1.0))
		var is_idle: bool = bool(w.get("is_idle", false))
		var idle_timer: float = float(w.get("idle_timer", 0.0))

		if is_idle:
			idle_timer -= delta
			if idle_timer <= 0.0:
				is_idle = false
				_play_walker_anim(node, dir, false)
		else:
			node.position.x += float(dir) * speed * delta
			if node.position.x <= min_x:
				node.position.x = min_x
				dir = 1
			elif node.position.x >= max_x:
				node.position.x = max_x
				dir = -1

			var turn_timer: float = float(w.get("turn_timer", 1.0)) - delta
			if turn_timer <= 0.0:
				if randf() < WALKER_IDLE_CHANCE:
					is_idle = true
					idle_timer = randf_range(WALKER_IDLE_MIN_TIME, WALKER_IDLE_MAX_TIME)
					_play_walker_anim(node, dir, true)
				else:
					if randf() < 0.35:
						dir *= -1
					_play_walker_anim(node, dir, false)
				turn_timer = randf_range(WALKER_MIN_TURN_TIME, WALKER_MAX_TURN_TIME)
			w["turn_timer"] = turn_timer

		if dir != prev_dir:
			_play_walker_anim(node, dir, is_idle)
		w["dir"] = dir
		w["is_idle"] = is_idle
		w["idle_timer"] = idle_timer
		room_one_walkers[i] = w


func _play_walker_anim(node: AnimatedSprite2D, dir: int, idle: bool = false) -> void:
	if node == null:
		return
	if node.sprite_frames == null:
		return
	var walk_anim: String = "walk_right" if dir > 0 else "walk_left"
	var idle_anim: String = "idle_right" if dir > 0 else "idle_left"
	if idle and node.sprite_frames.has_animation(idle_anim):
		if node.animation != idle_anim or not node.is_playing():
			node.play(idle_anim)
		return
	if idle:
		if node.sprite_frames.has_animation(walk_anim):
			if node.animation != walk_anim:
				node.play(walk_anim)
			node.stop()
		return
	if node.sprite_frames.has_animation(walk_anim):
		if node.animation != walk_anim or not node.is_playing():
			node.play(walk_anim)


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = str(GameManager.gold)


func _on_gold_changed(_new_gold: int) -> void:
	_update_gold_display()


func _on_party_changed() -> void:
	_spawn_room_one_walkers()
	if sortie_layer and sortie_layer.visible:
		_refresh_sortie_ui()


func _on_den_resized() -> void:
	_layout_rooms()


func _on_exit_pressed() -> void:
	exit_requested.emit()
	GameManager.go_to_field()
