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
	{"slot": "main_hand", "label": "⚔"},
	{"slot": "off_hand", "label": "🛡"},
	{"slot": "head", "label": "🪖"},
	{"slot": "body", "label": "👕"},
	{"slot": "acc1", "label": "💍"},
	{"slot": "acc2", "label": "💎"},
]
const SORTIE_FONT_SIZE: int = 12
const SORTIE_FACE_PATH := "res://assets/sprites/heroes/%s.png"
const SORTIE_PANEL_MIN_SIZE: Vector2 = Vector2(720, 440)
const SORTIE_PANEL_PREFERRED_SIZE: Vector2 = Vector2(1040, 600)
const SORTIE_PANEL_MARGIN: float = 24.0
const SORTIE_FACE_BOX_SIZE: Vector2 = Vector2(112, 112)
const SORTIE_STANDBY_CARD_SIZE: Vector2 = Vector2(40, 58)
const SORTIE_SORTIE_CARD_SIZE: Vector2 = Vector2(72, 108)
const SORTIE_STANDBY_LABEL_FONT: int = 10
const SORTIE_STANDBY_ICON_SCALE: float = 1.2
const SORTIE_SORTIE_ICON_SCALE: float = 1.9
const SORTIE_SORTIE_PADDING: float = 8.0
const SORTIE_SORTIE_SLOTS: int = 4
const SORTIE_WALK_MIN_SPEED: float = 12.0
const SORTIE_WALK_MAX_SPEED: float = 24.0
const SORTIE_WALK_FRAME_TIME: float = 0.18
const SORTIE_IDLE_CHANCE: float = 0.22
const SORTIE_IDLE_MIN_TIME: float = 0.6
const SORTIE_IDLE_MAX_TIME: float = 1.4
const SORTIE_LOOK_DOWN_CHANCE: float = 0.15
const SORTIE_LOOK_DOWN_MIN_TIME: float = 0.35
const SORTIE_LOOK_DOWN_MAX_TIME: float = 0.8
const SORTIE_BUBBLE_MIN_TIME: float = 1.2
const SORTIE_BUBBLE_MAX_TIME: float = 2.4
const SORTIE_BUBBLE_CHANCE: float = 0.25

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
var sortie_root: VBoxContainer = null
var sortie_standby_grid: GridContainer = null
var sortie_sortie_area: Control = null
var sortie_face_rect: TextureRect = null
var sortie_equipment_rows: Dictionary = {}
var sortie_stat_labels: Dictionary = {}
var sortie_inventory_tab_buttons: Array[Button] = []
var sortie_inventory_list: VBoxContainer = null
var sortie_inventory_hint: Label = null
var sortie_selected_hero_id: String = ""
var sortie_pending_hero_id: String = ""
var sortie_selected_item_id: String = ""
var sortie_selected_equip_slot: String = "main_hand"
var sortie_inventory_tab: String = "무기"
var sortie_party_ids: Array[String] = ["", "", "", ""]
var sortie_scaled_icon_cache: Dictionary = {}
var sortie_sortie_walkers: Array[Dictionary] = []
var sortie_sortie_bubbles: Array[Label] = []
var sortie_sortie_placeholders: Array[Control] = []


class _SortieHeroEntryButton extends Button:
	var den_ref: Node = null
	var hero_id: String = ""
	var source_kind: String = "standby"
	var hide_on_drag: bool = false
	var was_dragging: bool = false

	func _get_drag_data(_pos: Vector2) -> Variant:
		if den_ref == null or not den_ref.has_method("_build_sortie_hero_drag_data"):
			return null
		var data: Variant = den_ref.call("_build_sortie_hero_drag_data", hero_id, source_kind)
		if not data is Dictionary:
			return null
		if str(data.get("hero_id", "")).is_empty():
			return null
		was_dragging = true
		var preview := self.duplicate(0)
		preview.size = size
		preview.custom_minimum_size = custom_minimum_size
		preview.position = -_pos
		preview.clip_contents = false
		preview.visible = true
		if hide_on_drag:
			visible = false
		set_drag_preview(preview)
		return data

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "hero_drag"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if den_ref and den_ref.has_method("_on_sortie_area_drop_from_child"):
			den_ref.call("_on_sortie_area_drop_from_child", data)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if den_ref and den_ref.has_method("_on_sortie_roster_right_clicked"):
				den_ref.call("_on_sortie_roster_right_clicked", hero_id)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			was_dragging = false
			visible = true


class _SortieListDropTarget extends PanelContainer:
	var den_ref: Node = null
	var target_kind: String = "standby"

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "hero_drag"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if den_ref == null:
			return
		if target_kind == "standby" and den_ref.has_method("_on_sortie_hero_dropped_to_standby"):
			den_ref.call("_on_sortie_hero_dropped_to_standby", data)
		if target_kind == "sortie" and den_ref.has_method("_on_sortie_hero_dropped_to_sortie"):
			den_ref.call("_on_sortie_hero_dropped_to_sortie", data)


class _SortieSortieArea extends Control:
	var den_ref: Node = null

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "hero_drag"

	func _drop_data(pos: Vector2, data: Variant) -> void:
		if den_ref == null:
			return
		if den_ref.has_method("_on_sortie_area_drop"):
			den_ref.call("_on_sortie_area_drop", pos, data)


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
	_update_sortie_walkers(delta)


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
	sortie_panel.custom_minimum_size = Vector2.ZERO
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

	sortie_root = VBoxContainer.new()
	sortie_root.add_theme_constant_override("separation", 10)
	sortie_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sortie_panel.add_child(sortie_root)

	var title := Label.new()
	title.text = "출격 준비"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
	sortie_root.add_child(title)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sortie_root.add_child(content)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.13, 0.18, 0.95)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.32, 0.42)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10

	var top_row_center := CenterContainer.new()
	top_row_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(top_row_center)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row_center.add_child(top_row)

	# 대기 영웅 카드
	var standby_col := _SortieListDropTarget.new()
	standby_col.target_kind = "standby"
	standby_col.den_ref = self
	standby_col.custom_minimum_size = Vector2(190, 240)
	standby_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	standby_col.add_theme_stylebox_override("panel", panel_style.duplicate())
	top_row.add_child(standby_col)

	var standby_v := VBoxContainer.new()
	standby_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	standby_v.add_theme_constant_override("separation", 6)
	standby_col.add_child(standby_v)
	var standby_title := Label.new()
	standby_title.text = "대기 영웅 카드"
	standby_title.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	standby_v.add_child(standby_title)
	sortie_standby_grid = GridContainer.new()
	sortie_standby_grid.columns = 7
	sortie_standby_grid.add_theme_constant_override("h_separation", 3)
	sortie_standby_grid.add_theme_constant_override("v_separation", 3)
	standby_v.add_child(sortie_standby_grid)

	# 선택 영웅 스탯 및 장비 패널
	var equip_col := PanelContainer.new()
	equip_col.custom_minimum_size = Vector2(340, 240)
	equip_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_col.add_theme_stylebox_override("panel", panel_style.duplicate())
	top_row.add_child(equip_col)

	var equip_v := VBoxContainer.new()
	equip_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_v.add_theme_constant_override("separation", 8)
	equip_col.add_child(equip_v)
	var equip_title := Label.new()
	equip_title.text = "선택 영웅 스탯 및 장비 패널"
	equip_title.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	equip_v.add_child(equip_title)

	var hero_top_row := HBoxContainer.new()
	hero_top_row.add_theme_constant_override("separation", 10)
	hero_top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_v.add_child(hero_top_row)
	var face_box := PanelContainer.new()
	face_box.custom_minimum_size = SORTIE_FACE_BOX_SIZE
	face_box.add_theme_stylebox_override("panel", panel_style.duplicate())
	hero_top_row.add_child(face_box)
	sortie_face_rect = TextureRect.new()
	sortie_face_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sortie_face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sortie_face_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	face_box.add_child(sortie_face_rect)

	var equip_rows_panel := PanelContainer.new()
	equip_rows_panel.custom_minimum_size.x = 200
	equip_rows_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	hero_top_row.add_child(equip_rows_panel)

	var equip_rows_v := VBoxContainer.new()
	equip_rows_v.add_theme_constant_override("separation", 4)
	equip_rows_panel.add_child(equip_rows_v)
	sortie_equipment_rows.clear()
	for row in SORTIE_EQUIP_ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		equip_rows_v.add_child(line)
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size.x = 24
		name_lbl.text = str(row.get("label", ""))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
		line.add_child(name_lbl)
		var slot: String = str(row.get("slot", ""))
		var value_btn := Button.new()
		value_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_btn.text = "비어 있음"
		value_btn.focus_mode = Control.FOCUS_NONE
		value_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		value_btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
		value_btn.pressed.connect(_on_sortie_equipment_row_pressed.bind(slot))
		line.add_child(value_btn)
		sortie_equipment_rows[slot] = value_btn

	var stat_panel := PanelContainer.new()
	stat_panel.custom_minimum_size = Vector2(0, 120)
	stat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stat_panel.add_theme_stylebox_override("panel", equip_rows_style.duplicate())
	equip_v.add_child(stat_panel)

	var stat_v := VBoxContainer.new()
	stat_v.add_theme_constant_override("separation", 2)
	stat_panel.add_child(stat_v)
	var stat_title := Label.new()
	stat_title.text = "스탯"
	stat_title.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	stat_v.add_child(stat_title)
	sortie_stat_labels.clear()
	for key in ["ATK", "DEF", "MATK", "SPD", "HP"]:
		var stat_lbl := Label.new()
		stat_lbl.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
		stat_v.add_child(stat_lbl)
		sortie_stat_labels[key] = stat_lbl

	# 인벤토리
	var inv_col := PanelContainer.new()
	inv_col.custom_minimum_size = Vector2(190, 240)
	inv_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_col.add_theme_stylebox_override("panel", panel_style.duplicate())
	top_row.add_child(inv_col)

	var inv_v := VBoxContainer.new()
	inv_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_v.add_theme_constant_override("separation", 8)
	inv_col.add_child(inv_v)
	var inv_title := Label.new()
	inv_title.text = "인벤토리"
	inv_title.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	inv_v.add_child(inv_title)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_v.add_child(tab_row)
	sortie_inventory_tab_buttons.clear()
	for tab_name in ["무기", "방패", "투구", "갑옷", "악세"]:
		var tab_btn := Button.new()
		tab_btn.text = _sortie_tab_label(tab_name)
		tab_btn.set_meta("tab_id", tab_name)
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.custom_minimum_size.x = 0
		tab_btn.focus_mode = Control.FOCUS_NONE
		tab_btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
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
	sortie_inventory_hint.text = "장비 선택 후 장비 슬롯 클릭: 장착"
	sortie_inventory_hint.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	sortie_inventory_hint.add_theme_color_override("font_color", Color(0.68, 0.7, 0.78))
	inv_v.add_child(sortie_inventory_hint)

	# 하단 출격 목록 + 출발 버튼
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(bottom_row)

	var back_cell := CenterContainer.new()
	back_cell.custom_minimum_size = Vector2(110, 60)
	back_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom_row.add_child(back_cell)

	var back_btn := Button.new()
	back_btn.text = "돌아가기"
	back_btn.focus_mode = Control.FOCUS_NONE
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.45, 0.12, 0.12, 0.95)
	back_style.border_width_left = 1
	back_style.border_width_top = 1
	back_style.border_width_right = 1
	back_style.border_width_bottom = 1
	back_style.border_color = Color(0.85, 0.35, 0.35, 0.95)
	back_style.corner_radius_top_left = 6
	back_style.corner_radius_top_right = 6
	back_style.corner_radius_bottom_left = 6
	back_style.corner_radius_bottom_right = 6
	back_style.content_margin_left = 8
	back_style.content_margin_right = 8
	back_style.content_margin_top = 4
	back_style.content_margin_bottom = 4
	back_btn.add_theme_stylebox_override("normal", back_style)
	back_btn.add_theme_stylebox_override("hover", back_style)
	back_btn.add_theme_stylebox_override("pressed", back_style)
	back_btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	back_btn.pressed.connect(_close_sortie_prep)
	back_cell.add_child(back_btn)

	var sortie_panel := _SortieListDropTarget.new()
	sortie_panel.target_kind = "sortie"
	sortie_panel.den_ref = self
	sortie_panel.custom_minimum_size = Vector2(480, 140)
	sortie_panel.add_theme_stylebox_override("panel", panel_style.duplicate())
	sortie_panel.clip_contents = false
	sortie_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(sortie_panel)
	var sortie_panel_v := VBoxContainer.new()
	sortie_panel_v.add_theme_constant_override("separation", 6)
	sortie_panel.add_child(sortie_panel_v)
	var sortie_panel_title := Label.new()
	sortie_panel_title.text = "출격 목록"
	sortie_panel_title.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	sortie_panel_v.add_child(sortie_panel_title)
	sortie_sortie_area = _SortieSortieArea.new()
	sortie_sortie_area.den_ref = self
	var sortie_min_w := SORTIE_SORTIE_CARD_SIZE.x * SORTIE_SORTIE_SLOTS + SORTIE_SORTIE_PADDING * maxf(0.0, float(SORTIE_SORTIE_SLOTS - 1))
	sortie_sortie_area.custom_minimum_size = Vector2(maxf(440.0, sortie_min_w), 90)
	sortie_sortie_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sortie_sortie_area.mouse_filter = Control.MOUSE_FILTER_STOP
	sortie_sortie_area.clip_contents = false
	sortie_sortie_area.resized.connect(_layout_sortie_walkers)
	sortie_panel_v.add_child(sortie_sortie_area)

	var start_cell := CenterContainer.new()
	start_cell.custom_minimum_size = Vector2(110, 60)
	start_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom_row.add_child(start_cell)

	var start_btn := Button.new()
	start_btn.text = "출발"
	start_btn.focus_mode = Control.FOCUS_NONE
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color(0.12, 0.4, 0.18, 0.95)
	start_style.border_width_left = 1
	start_style.border_width_top = 1
	start_style.border_width_right = 1
	start_style.border_width_bottom = 1
	start_style.border_color = Color(0.4, 0.9, 0.55, 0.95)
	start_style.corner_radius_top_left = 6
	start_style.corner_radius_top_right = 6
	start_style.corner_radius_bottom_left = 6
	start_style.corner_radius_bottom_right = 6
	start_style.content_margin_left = 8
	start_style.content_margin_right = 8
	start_style.content_margin_top = 4
	start_style.content_margin_bottom = 4
	start_btn.add_theme_stylebox_override("normal", start_style)
	start_btn.add_theme_stylebox_override("hover", start_style)
	start_btn.add_theme_stylebox_override("pressed", start_style)
	start_btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
	start_btn.pressed.connect(_on_sortie_start_pressed)
	start_cell.add_child(start_btn)

	_update_sortie_panel_size()


func _update_sortie_panel_size() -> void:
	if sortie_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var available := viewport_size - Vector2(SORTIE_PANEL_MARGIN * 2.0, SORTIE_PANEL_MARGIN * 2.0)
	var desired := Vector2.ZERO
	if sortie_root:
		desired = sortie_root.get_combined_minimum_size() + Vector2(24, 24)
	var panel_w := minf(available.x, maxf(desired.x, 0.0))
	var panel_h := minf(available.y, maxf(desired.y, 0.0))
	sortie_panel.custom_minimum_size = Vector2(panel_w, panel_h)


func _open_sortie_prep() -> void:
	sortie_selected_item_id = ""
	sortie_selected_equip_slot = "main_hand"
	sortie_inventory_tab = "무기"
	sortie_pending_hero_id = ""
	sortie_selected_hero_id = ""
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(sortie_party_ids.size()):
		sortie_party_ids[i] = str(party[i].id) if i < party.size() else ""
	for id in sortie_party_ids:
		if not id.is_empty():
			sortie_selected_hero_id = id
			break
	if sortie_layer:
		sortie_layer.visible = true
	_update_sortie_panel_size()
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
	_refresh_sortie_sortie_list()
	_refresh_sortie_hero_list()
	_refresh_sortie_equipment_rows()
	_refresh_sortie_stats()
	_refresh_sortie_inventory_tabs()
	_refresh_sortie_inventory()


func _refresh_sortie_sortie_list() -> void:
	if sortie_sortie_area == null:
		return
	for c in sortie_sortie_area.get_children():
		c.queue_free()
	for bubble in sortie_sortie_bubbles:
		if bubble:
			bubble.queue_free()
	sortie_sortie_bubbles.clear()
	sortie_sortie_walkers.clear()
	for ph in sortie_sortie_placeholders:
		if ph:
			ph.queue_free()
	sortie_sortie_placeholders.clear()

	for i in range(sortie_party_ids.size()):
		var hero_id := str(sortie_party_ids[i])
		if hero_id.is_empty():
			var placeholder := PanelContainer.new()
			placeholder.custom_minimum_size = SORTIE_SORTIE_CARD_SIZE
			var ph_style := StyleBoxFlat.new()
			ph_style.bg_color = Color(0.1, 0.1, 0.14, 0.95)
			ph_style.border_width_left = 1
			ph_style.border_width_top = 1
			ph_style.border_width_right = 1
			ph_style.border_width_bottom = 1
			ph_style.border_color = Color(0.3, 0.32, 0.4)
			placeholder.add_theme_stylebox_override("panel", ph_style)
			placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			placeholder.set_meta("slot_index", i)
			sortie_sortie_area.add_child(placeholder)
			sortie_sortie_placeholders.append(placeholder)
			continue
		var hero := _find_recruited_hero_by_id(hero_id)
		if hero == null:
			continue
		var btn := _SortieHeroEntryButton.new()
		btn.den_ref = self
		btn.hero_id = hero.id
		btn.source_kind = "sortie"
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
		btn.custom_minimum_size = SORTIE_SORTIE_CARD_SIZE
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.icon = _get_sortie_field_texture_scaled(hero, SORTIE_SORTIE_ICON_SCALE)
		btn.text = ""
		btn.hide_on_drag = true
		btn.pressed.connect(_on_sortie_roster_clicked.bind(hero.id, btn))
		if hero.id == sortie_selected_hero_id:
			var sel_style := StyleBoxFlat.new()
			sel_style.bg_color = Color(0.18, 0.18, 0.22, 0.95)
			sel_style.border_width_left = 1
			sel_style.border_width_top = 1
			sel_style.border_width_right = 1
			sel_style.border_width_bottom = 1
			sel_style.border_color = Color(0.95, 0.8, 0.35, 0.95)
			btn.add_theme_stylebox_override("normal", sel_style)
			btn.add_theme_stylebox_override("hover", sel_style)
		sortie_sortie_area.add_child(btn)
		btn.set_meta("slot_index", i)

		var bubble := Label.new()
		bubble.visible = false
		bubble.text = ""
		bubble.add_theme_font_size_override("font_size", SORTIE_STANDBY_LABEL_FONT)
		bubble.add_theme_color_override("font_color", Color(0.1, 0.08, 0.1))
		var bubble_style := StyleBoxFlat.new()
		bubble_style.bg_color = Color(0.95, 0.95, 0.98, 0.95)
		bubble_style.border_width_left = 1
		bubble_style.border_width_top = 1
		bubble_style.border_width_right = 1
		bubble_style.border_width_bottom = 1
		bubble_style.border_color = Color(0.2, 0.2, 0.25, 0.9)
		bubble_style.corner_radius_top_left = 6
		bubble_style.corner_radius_top_right = 6
		bubble_style.corner_radius_bottom_left = 6
		bubble_style.corner_radius_bottom_right = 6
		bubble_style.content_margin_left = 6
		bubble_style.content_margin_right = 6
		bubble_style.content_margin_top = 2
		bubble_style.content_margin_bottom = 2
		bubble.add_theme_stylebox_override("normal", bubble_style)
		bubble.z_index = 50
		bubble.top_level = true
		sortie_layer.add_child(bubble)
		sortie_sortie_bubbles.append(bubble)

		sortie_sortie_walkers.append({
			"hero_id": hero.id,
			"node": btn,
			"bubble": bubble,
			"slot_index": i,
			"dir": (1 if randi() % 2 == 0 else -1),
			"speed": randf_range(SORTIE_WALK_MIN_SPEED, SORTIE_WALK_MAX_SPEED),
			"frame_time": 0.0,
			"frame": 0,
			"look_down": 0.0,
			"idle": 0.0,
			"bubble_time": 0.0,
			"bubble_cool": randf_range(0.4, 1.2),
		})
	call_deferred("_layout_sortie_walkers")


func _layout_sortie_walkers() -> void:
	if sortie_sortie_area == null:
		return
	var area_size := sortie_sortie_area.size
	if area_size.x <= 0.0 or area_size.y <= 0.0:
		return
	var padding := SORTIE_SORTIE_PADDING
	var count := sortie_party_ids.size()
	var cell_w := SORTIE_SORTIE_CARD_SIZE.x
	var total_w := cell_w * count + padding * maxf(0.0, float(count - 1))
	var start_x := maxf(padding, (area_size.x - total_w) * 0.5)
	for node in sortie_sortie_area.get_children():
		if node == null or not node.has_meta("slot_index"):
			continue
		var idx := int(node.get_meta("slot_index"))
		var x: float = start_x + idx * (cell_w + padding)
		var y: float = (area_size.y - node.size.y) * 0.5
		node.position = Vector2(x, y)
	for i in range(sortie_sortie_walkers.size()):
		var w: Dictionary = sortie_sortie_walkers[i]
		var idx: int = int(w.get("slot_index", i))
		var x := start_x + idx * (cell_w + padding)
		w["min_x"] = x
		w["max_x"] = x
		w["base_y"] = (area_size.y - SORTIE_SORTIE_CARD_SIZE.y) * 0.5
		sortie_sortie_walkers[i] = w


func _update_sortie_walkers(delta: float) -> void:
	if sortie_layer == null or not sortie_layer.visible:
		return
	if sortie_sortie_walkers.is_empty():
		return
	for i in range(sortie_sortie_walkers.size()):
		var w: Dictionary = sortie_sortie_walkers[i]
		var node: Control = w.get("node")
		if node == null or sortie_sortie_area == null:
			continue
		var hero := _find_recruited_hero_by_id(str(w.get("hero_id", "")))
		if hero == null:
			continue
		var base_y: float = float(w.get("base_y", (sortie_sortie_area.size.y - node.size.y) * 0.5))
		var frame_time: float = float(w.get("frame_time", 0.0))
		var frame: int = int(w.get("frame", 0))
		var idle_time: float = float(w.get("idle", 0.0))

		var pos := node.position
		pos.y = base_y
		node.position = pos

		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id) if SpriteManager else null
		var max_frames := frames.get_frame_count("walk_down") if frames and frames.has_animation("walk_down") else 1
		if idle_time <= 0.0 and randf() < SORTIE_IDLE_CHANCE * delta:
			idle_time = randf_range(SORTIE_IDLE_MIN_TIME, SORTIE_IDLE_MAX_TIME)

		if idle_time > 0.0:
			idle_time -= delta
			frame = (max_frames / 2) if max_frames > 0 else 0
		else:
			frame_time += delta
			if frame_time >= SORTIE_WALK_FRAME_TIME:
				frame_time = 0.0
				frame = (frame + 1) % max_frames

		var tex := _get_sortie_anim_texture_scaled(hero, "walk_down", frame, SORTIE_SORTIE_ICON_SCALE)
		if tex != null:
			node.icon = tex

		var bubble: Label = w.get("bubble")
		if bubble:
			var bubble_time: float = float(w.get("bubble_time", 0.0))
			var bubble_cool: float = float(w.get("bubble_cool", 0.0))
			if bubble_time > 0.0:
				bubble_time -= delta
				bubble.visible = true
			else:
				bubble.visible = false
				bubble_cool -= delta
				if bubble_cool <= 0.0 and randf() < SORTIE_BUBBLE_CHANCE * delta:
					bubble_time = randf_range(SORTIE_BUBBLE_MIN_TIME, SORTIE_BUBBLE_MAX_TIME)
					bubble_cool = randf_range(1.0, 2.0)
					bubble.text = _pick_sortie_bubble_text()
					bubble.reset_size()
			if bubble.visible:
				var global_pos := node.global_position
				bubble.global_position = global_pos + Vector2(node.size.x * 0.5 - bubble.size.x * 0.5, -18.0)
			w["bubble_time"] = bubble_time
			w["bubble_cool"] = bubble_cool

		w["frame_time"] = frame_time
		w["frame"] = frame
		w["idle"] = idle_time
		sortie_sortie_walkers[i] = w


func _get_sortie_face_texture(hero: Hero) -> Texture2D:
	if hero == null:
		return null
	var sprite_key: String = hero.portrait if not hero.portrait.is_empty() else hero.field_sprite
	if sprite_key.is_empty():
		return null
	var path := SORTIE_FACE_PATH % sprite_key
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _get_sortie_field_texture(hero: Hero) -> Texture2D:
	if hero == null:
		return null
	if hero.field_sprite.is_empty() and hero.portrait.is_empty():
		return null
	if SpriteManager:
		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id)
		if frames and frames.has_animation("walk_down") and frames.get_frame_count("walk_down") > 0:
			return frames.get_frame_texture("walk_down", 0)
	return _get_sortie_face_texture(hero)


func _get_sortie_field_texture_scaled(hero: Hero, scale: float) -> Texture2D:
	var base := _get_sortie_field_texture(hero)
	if base == null or is_equal_approx(scale, 1.0):
		return base
	var key := "%s|%s" % [hero.id, str(scale)]
	if sortie_scaled_icon_cache.has(key):
		return sortie_scaled_icon_cache[key]
	var img := base.get_image()
	if img == null:
		return base
	var target := Vector2i(maxi(1, int(round(img.get_width() * scale))), maxi(1, int(round(img.get_height() * scale))))
	img.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	sortie_scaled_icon_cache[key] = tex
	return tex


func _get_sortie_anim_texture_scaled(hero: Hero, anim: String, frame_idx: int, scale: float) -> Texture2D:
	if hero == null:
		return null
	var base: Texture2D = null
	if SpriteManager:
		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id)
		if frames and frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var idx := clampi(frame_idx, 0, frames.get_frame_count(anim) - 1)
			base = frames.get_frame_texture(anim, idx)
	if base == null:
		return _get_sortie_field_texture_scaled(hero, scale)
	if is_equal_approx(scale, 1.0):
		return base
	var key := "%s|%s|%d|%s" % [hero.id, anim, frame_idx, str(scale)]
	if sortie_scaled_icon_cache.has(key):
		return sortie_scaled_icon_cache[key]
	var img := base.get_image()
	if img == null:
		return base
	var target := Vector2i(maxi(1, int(round(img.get_width() * scale))), maxi(1, int(round(img.get_height() * scale))))
	img.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	sortie_scaled_icon_cache[key] = tex
	return tex


func _refresh_sortie_hero_list() -> void:
	if sortie_standby_grid == null:
		return
	for c in sortie_standby_grid.get_children():
		c.queue_free()

	for hero_any in _get_recruited_heroes():
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		var assigned_slot := sortie_party_ids.find(hero.id)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		sortie_standby_grid.add_child(card)

		var btn := _SortieHeroEntryButton.new()
		btn.den_ref = self
		btn.hero_id = hero.id
		btn.source_kind = "standby"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = SORTIE_STANDBY_CARD_SIZE
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
		btn.icon = _get_sortie_field_texture_scaled(hero, SORTIE_STANDBY_ICON_SCALE)
		btn.text = ""
		btn.hide_on_drag = false
		if assigned_slot >= 0:
			btn.modulate = Color(0.6, 0.6, 0.65, 1.0)
			btn.disabled = true
		if hero.id == sortie_selected_hero_id:
			var sel_style := StyleBoxFlat.new()
			sel_style.bg_color = Color(0.18, 0.18, 0.22, 0.95)
			sel_style.border_width_left = 1
			sel_style.border_width_top = 1
			sel_style.border_width_right = 1
			sel_style.border_width_bottom = 1
			sel_style.border_color = Color(0.95, 0.8, 0.35, 0.95)
			btn.add_theme_stylebox_override("normal", sel_style)
			btn.add_theme_stylebox_override("hover", sel_style)
		btn.pressed.connect(_on_sortie_roster_clicked.bind(hero.id, btn))
		card.add_child(btn)

		var name_lbl := Label.new()
		name_lbl.text = "%s Lv.%s" % [hero.hero_name, str(hero.level)]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", SORTIE_STANDBY_LABEL_FONT)
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.56, 0.62) if assigned_slot >= 0 else Color(0.78, 0.8, 0.9))
		name_lbl.custom_minimum_size.x = SORTIE_STANDBY_CARD_SIZE.x
		name_lbl.clip_text = true
		card.add_child(name_lbl)


func _refresh_sortie_equipment_rows() -> void:
	var hero := _find_recruited_hero_by_id(sortie_selected_hero_id)
	for row in SORTIE_EQUIP_ROWS:
		var slot: String = str(row.get("slot", ""))
		var value_btn: Button = sortie_equipment_rows.get(slot) as Button
		if value_btn == null:
			continue
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.2, 0.17, 0.1, 0.95) if slot == sortie_selected_equip_slot else Color(0.1, 0.1, 0.14, 0.95)
		row_style.border_width_left = 1
		row_style.border_width_top = 1
		row_style.border_width_right = 1
		row_style.border_width_bottom = 1
		row_style.border_color = Color(0.95, 0.8, 0.35) if slot == sortie_selected_equip_slot else Color(0.3, 0.32, 0.4)
		value_btn.add_theme_stylebox_override("normal", row_style)
		value_btn.add_theme_stylebox_override("hover", row_style)

		if hero == null:
			value_btn.text = "비어 있음"
			continue
		var equip_id: String = str(hero.equipment.get(slot, ""))
		if equip_id.is_empty():
			value_btn.text = "비어 있음"
			continue
		var data: Dictionary = DataManager.get_equipment(equip_id)
		value_btn.text = str(data.get("name", equip_id))


func _refresh_sortie_stats() -> void:
	if sortie_stat_labels.is_empty():
		return
	var hero := _find_recruited_hero_by_id(sortie_selected_hero_id)
	if hero == null:
		if sortie_face_rect:
			sortie_face_rect.texture = null
		for key in sortie_stat_labels.keys():
			var empty_lbl: Label = sortie_stat_labels[key]
			empty_lbl.text = "%s -" % str(key)
		return
	if sortie_face_rect:
		sortie_face_rect.texture = _get_sortie_face_texture(hero)
	var base := {
		"ATK": hero.get_atk(),
		"DEF": hero.get_def(),
		"MATK": hero.get_magic_attack(),
		"SPD": hero.get_spd(),
		"HP": hero.get_max_hp(),
	}
	var delta := _calc_sortie_item_delta(hero, sortie_selected_item_id, sortie_selected_equip_slot)
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
		var tab_id: String = str(btn.get_meta("tab_id", btn.text))
		var selected: bool = (tab_id == sortie_inventory_tab)
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
		empty_lbl.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
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
		btn.add_theme_font_size_override("font_size", SORTIE_FONT_SIZE)
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
			sortie_inventory_hint.text = "장비 선택 후 장비 슬롯 클릭: 장착"
		else:
			sortie_inventory_hint.text = "선택: %s" % str(selected_data.get("name", sortie_selected_item_id))


func _on_sortie_roster_clicked(hero_id: String, btn: _SortieHeroEntryButton = null) -> void:
	if btn != null and btn.was_dragging:
		btn.was_dragging = false
		return
	var was_selected := (hero_id == sortie_selected_hero_id)
	var is_in_sortie := sortie_party_ids.has(hero_id)
	if was_selected:
		if is_in_sortie:
			_move_hero_to_standby(hero_id)
		else:
			_move_hero_to_sortie(hero_id)
	else:
		sortie_selected_hero_id = hero_id
	_refresh_sortie_ui()


func _on_sortie_roster_right_clicked(hero_id: String) -> void:
	if hero_id.is_empty():
		return
	var is_in_sortie := sortie_party_ids.has(hero_id)
	if is_in_sortie:
		_move_hero_to_standby(hero_id)
	else:
		_move_hero_to_sortie(hero_id)
	sortie_selected_hero_id = hero_id
	_refresh_sortie_ui()


func _build_sortie_hero_drag_data(hero_id: String, source_kind: String) -> Dictionary:
	if hero_id.is_empty():
		return {}
	var hero := _find_recruited_hero_by_id(hero_id)
	var label := hero.hero_name if hero else hero_id
	return {
		"type": "hero_drag",
		"hero_id": hero_id,
		"source": source_kind,
		"label": label,
	}


func _on_sortie_area_drop(pos: Vector2, data: Dictionary) -> void:
	var hero_id: String = str(data.get("hero_id", ""))
	if hero_id.is_empty():
		return
	var source: String = str(data.get("source", ""))
	if source == "sortie":
		_reorder_sortie_by_drop(hero_id, pos.x)
	else:
		_reorder_sortie_by_drop(hero_id, pos.x)
	_refresh_sortie_ui()


func _on_sortie_area_drop_from_child(data: Dictionary) -> void:
	if sortie_sortie_area == null:
		return
	var local_pos: Vector2 = get_viewport().get_mouse_position() - sortie_sortie_area.get_global_position()
	_on_sortie_area_drop(local_pos, data)


func _reorder_sortie_by_drop(hero_id: String, drop_x: float) -> void:
	var area_w := sortie_sortie_area.size.x if sortie_sortie_area else 0.0
	var count := sortie_party_ids.size()
	var cell_w := SORTIE_SORTIE_CARD_SIZE.x
	var total_w := cell_w * count + SORTIE_SORTIE_PADDING * maxf(0.0, float(count - 1))
	var start_x := maxf(SORTIE_SORTIE_PADDING, (area_w - total_w) * 0.5)
	var step := cell_w + SORTIE_SORTIE_PADDING
	var target := int(floor((drop_x - start_x) / step))
	target = clampi(target, 0, count - 1)

	var from := sortie_party_ids.find(hero_id)
	if from < 0:
		# insert from standby
		var shifted := sortie_party_ids.duplicate()
		shifted.insert(target, hero_id)
		shifted.resize(count)
		for i in range(count):
			sortie_party_ids[i] = str(shifted[i])
		return

	if from == target:
		return
	if target < from:
		for i in range(from, target, -1):
			sortie_party_ids[i] = sortie_party_ids[i - 1]
		sortie_party_ids[target] = hero_id
	else:
		for i in range(from, target):
			sortie_party_ids[i] = sortie_party_ids[i + 1]
		sortie_party_ids[target] = hero_id


func _on_sortie_hero_dropped_to_sortie(data: Dictionary) -> void:
	var hero_id: String = str(data.get("hero_id", ""))
	if hero_id.is_empty():
		return
	_move_hero_to_sortie(hero_id)
	_refresh_sortie_ui()


func _on_sortie_hero_dropped_to_standby(data: Dictionary) -> void:
	var hero_id: String = str(data.get("hero_id", ""))
	if hero_id.is_empty():
		return
	_move_hero_to_standby(hero_id)
	_refresh_sortie_ui()


func _move_hero_to_sortie(hero_id: String) -> void:
	if hero_id.is_empty():
		return
	if sortie_party_ids.has(hero_id):
		sortie_selected_hero_id = hero_id
		return
	var open_index := sortie_party_ids.find("")
	if open_index < 0:
		return
	sortie_party_ids[open_index] = hero_id
	sortie_selected_hero_id = hero_id


func _move_hero_to_standby(hero_id: String) -> void:
	if hero_id.is_empty():
		return
	for i in range(sortie_party_ids.size()):
		if sortie_party_ids[i] == hero_id:
			sortie_party_ids[i] = ""


func _on_sortie_hero_double_clicked(hero_id: String, source_kind: String) -> void:
	if source_kind == "standby":
		_move_hero_to_sortie(hero_id)
	else:
		_move_hero_to_standby(hero_id)
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


func _on_sortie_equipment_row_pressed(slot: String) -> void:
	sortie_selected_equip_slot = slot
	var hero := _find_recruited_hero_by_id(sortie_selected_hero_id)
	if hero == null:
		_refresh_sortie_ui()
		return

	if not sortie_selected_item_id.is_empty() and _can_sortie_item_fit_slot(hero, sortie_selected_item_id, slot):
		if InventoryManager and InventoryManager.equip_item(hero, sortie_selected_item_id, slot):
			sortie_selected_item_id = ""
	else:
		var equipped_id: String = str(hero.equipment.get(slot, ""))
		if not equipped_id.is_empty() and InventoryManager:
			InventoryManager.unequip_item(hero, slot)
	_refresh_sortie_ui()


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


func _sortie_tab_label(tab_name: String) -> String:
	match tab_name:
		"무기":
			return "⚔"
		"방패":
			return "🛡"
		"투구":
			return "🪖"
		"갑옷":
			return "👕"
		"악세":
			return "💎"
	return tab_name


func _pick_sortie_bubble_text() -> String:
	var options := [
		"준비됐어.",
		"출격 준비 완료.",
		"잠깐, 장비 체크.",
		"오늘 날씨 괜찮네.",
		"음, 몸이 조금 굳었네.",
		"서둘러야 하나?",
		"물 좀 마실까.",
		"좋아, 가자!",
		"잠깐 쉬었다 가자.",
		"정비는 끝났어.",
		"오케이, 문제 없어.",
		"대기 중이야.",
		"배고프네.",
		"이거 맞지?",
		"조심해서 가자.",
		"나부터?",
		"한숨 돌리자.",
		"좋은 예감이야.",
		"응? 뭐라고?",
		"알겠어.",
	]
	return options[randi() % options.size()]


func _resolve_sortie_target_slot(hero: Hero, data: Dictionary, preferred_slot: String = "") -> String:
	var slot := Hero.normalize_equipment_slot(str(data.get("slot", "")))
	var preferred := Hero.normalize_equipment_slot(preferred_slot)
	if preferred in ["acc1", "acc2"]:
		if slot == "acc":
			return preferred
	if slot in ["main_hand", "off_hand", "head", "body"] and preferred == slot:
		return preferred
	if slot == "main_hand" and preferred == "off_hand" and hero.can_dual_wield() and not hero.is_off_hand_disabled():
		return "off_hand"
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


func _can_sortie_item_fit_slot(hero: Hero, item_id: String, target_slot: String) -> bool:
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return false
	var resolved := _resolve_sortie_target_slot(hero, data, target_slot)
	return not resolved.is_empty() and resolved == target_slot


func _calc_sortie_item_delta(hero: Hero, item_id: String, preferred_slot: String = "") -> Dictionary:
	var result := {"ATK": 0, "DEF": 0, "MATK": 0, "SPD": 0, "HP": 0}
	if hero == null or item_id.is_empty():
		return result
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return result
	var target_slot: String = _resolve_sortie_target_slot(hero, data, preferred_slot)
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
	_update_sortie_panel_size()


func _on_exit_pressed() -> void:
	exit_requested.emit()
	GameManager.go_to_field()
