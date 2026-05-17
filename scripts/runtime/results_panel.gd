class_name ResultsPanel
extends Node2D

## Step 1 of the field-end settlement: loot summary + level recap + sell.
## Two button choices:
##   [업그레이드] → opens NodeTreePanel before returning to the field
##   [계속]     → straight back to the field
##
## Node tree lives on a separate scene (node_tree_panel.tscn) so the user
## can skip it when they don't want to spend.

signal upgrade_pressed
signal continue_pressed

const PANEL_MARGIN: Vector2 = Vector2(8.0, 8.0)
const BG_OVERLAY: Color = Color(0.05, 0.04, 0.03, 0.86)
const PANEL_BG: Color = Color(0.12, 0.10, 0.08, 0.96)
const PANEL_BORDER: Color = Color(0.32, 0.24, 0.14, 1.0)
const HEADER_COLOR: Color = Color(1.0, 0.92, 0.42)
const GAIN_COLOR: Color = Color(0.6, 0.95, 0.55)

var _viewport_size: Vector2
var _gold_label: Label
var _level_label: Label
var _loot_label: Label
var _sell_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport_size = get_viewport_rect().size
	_build_camera()
	_build_overlay()
	_build_header()
	_build_level_section()
	_build_loot_section()
	_build_footer()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	_refresh_all()


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = _viewport_size * 0.5
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = BG_OVERLAY
	dim.position = Vector2.ZERO
	dim.size = _viewport_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel_origin: Vector2 = PANEL_MARGIN
	var panel_size: Vector2 = _viewport_size - PANEL_MARGIN * 2.0
	var border := ColorRect.new()
	border.color = PANEL_BORDER
	border.position = panel_origin - Vector2(2.0, 2.0)
	border.size = panel_size + Vector2(4.0, 4.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(border)

	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.position = panel_origin
	bg.size = panel_size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)


# ─── Header: 위치 / 마왕까지 / 골드 ────────────────────────────────────
func _build_header() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)

	var origin: Vector2 = PANEL_MARGIN + Vector2(10.0, 6.0)
	var here := Label.new()
	here.text = "당신의 위치"
	here.add_theme_font_size_override("font_size", 9)
	here.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
	here.position = origin
	layer.add_child(here)

	var location := Label.new()
	location.name = "LocationLabel"
	location.add_theme_font_size_override("font_size", 14)
	location.add_theme_color_override("font_color", HEADER_COLOR)
	location.position = origin + Vector2(0.0, 12.0)
	layer.add_child(location)

	var distance := Label.new()
	distance.name = "DistanceLabel"
	distance.add_theme_font_size_override("font_size", 9)
	distance.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	distance.position = origin + Vector2(0.0, 30.0)
	layer.add_child(distance)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_gold_label.position = Vector2(_viewport_size.x - PANEL_MARGIN.x - 90.0, origin.y + 4.0)
	layer.add_child(_gold_label)


# ─── Level recap ──────────────────────────────────────────────────────
func _build_level_section() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)

	var origin: Vector2 = Vector2(PANEL_MARGIN.x + 10.0, PANEL_MARGIN.y + 52.0)
	var title := Label.new()
	title.text = "파티 레벨"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	title.position = origin
	layer.add_child(title)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.add_theme_color_override("font_color", Color.WHITE)
	_level_label.position = origin + Vector2(0.0, 14.0)
	layer.add_child(_level_label)


# ─── Loot summary + sell ──────────────────────────────────────────────
func _build_loot_section() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)

	var origin: Vector2 = Vector2(PANEL_MARGIN.x + 10.0, PANEL_MARGIN.y + 100.0)
	var section_title := Label.new()
	section_title.text = "전리품"
	section_title.add_theme_font_size_override("font_size", 10)
	section_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	section_title.position = origin
	layer.add_child(section_title)

	_loot_label = Label.new()
	_loot_label.add_theme_font_size_override("font_size", 11)
	_loot_label.add_theme_color_override("font_color", Color.WHITE)
	_loot_label.position = origin + Vector2(0.0, 14.0)
	layer.add_child(_loot_label)

	_sell_button = Button.new()
	_sell_button.text = "전부 팔기"
	_sell_button.add_theme_font_size_override("font_size", 10)
	_sell_button.position = origin + Vector2(0.0, 32.0)
	_sell_button.size = Vector2(140.0, 18.0)
	_sell_button.pressed.connect(_on_sell_pressed)
	layer.add_child(_sell_button)


# ─── Footer: [업그레이드] [계속] ──────────────────────────────────────
func _build_footer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)

	var button_width: float = 110.0
	var button_height: float = 24.0
	var gap: float = 10.0
	var total_width: float = button_width * 2.0 + gap
	var origin_x: float = (_viewport_size.x - total_width) * 0.5
	var origin_y: float = _viewport_size.y - PANEL_MARGIN.y - 14.0 - button_height

	var upgrade := Button.new()
	upgrade.text = "업그레이드"
	upgrade.add_theme_font_size_override("font_size", 12)
	upgrade.position = Vector2(origin_x, origin_y)
	upgrade.size = Vector2(button_width, button_height)
	upgrade.pressed.connect(_on_upgrade_pressed)
	layer.add_child(upgrade)

	var cont := Button.new()
	cont.text = "계속  ▶"
	cont.add_theme_font_size_override("font_size", 12)
	cont.position = Vector2(origin_x + button_width + gap, origin_y)
	cont.size = Vector2(button_width, button_height)
	cont.pressed.connect(_on_continue_pressed)
	layer.add_child(cont)
	cont.grab_focus()


# ─── Refresh ──────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh_header()
	_refresh_level()
	_refresh_loot()


func _refresh_header() -> void:
	var loc_label: Label = _find_descendant_label("LocationLabel")
	var dist_label: Label = _find_descendant_label("DistanceLabel")
	if loc_label != null:
		loc_label.text = GameState.current_location_label()
	if dist_label != null:
		var remaining: int = GameState.gold_to_next_location()
		if remaining <= 0:
			dist_label.text = "최종 위치"
		else:
			dist_label.text = "다음 위치: %s — %d g 더" % [GameState.next_location_label(), remaining]
	if _gold_label != null and is_instance_valid(_gold_label):
		_gold_label.text = "골드  %d" % GameState.gold


func _refresh_level() -> void:
	if _level_label == null or not is_instance_valid(_level_label):
		return
	var delta: int = GameState.current_level - GameState.level_at_field_start
	if delta > 0:
		_level_label.text = "Lv %d  (+%d)" % [GameState.current_level, delta]
		_level_label.add_theme_color_override("font_color", GAIN_COLOR)
	else:
		_level_label.text = "Lv %d" % GameState.current_level
		_level_label.add_theme_color_override("font_color", Color.WHITE)


func _refresh_loot() -> void:
	if _loot_label == null or not is_instance_valid(_loot_label):
		return
	var count: int = GameState.inventory.size()
	var value: int = GameState.inventory_sell_value()
	if count <= 0:
		_loot_label.text = "전리품 없음"
		_sell_button.disabled = true
		_sell_button.text = "전부 팔기"
		return
	_loot_label.text = "아이템 %d개  ·  +%d g" % [count, value]
	_sell_button.disabled = false
	_sell_button.text = "전부 팔기 (+%d g)" % value


# ─── Find helpers ─────────────────────────────────────────────────────
func _find_descendant_label(target_name: String) -> Label:
	for child: Node in _walk_descendants(self):
		if child is Label and child.name == target_name:
			return child
	return null


func _walk_descendants(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			out.append(c)
			stack.append(c)
	return out


# ─── Signal handlers ──────────────────────────────────────────────────
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_header()


func _on_inventory_changed() -> void:
	_refresh_loot()


func _on_sell_pressed() -> void:
	var earned: int = GameState.sell_inventory_items()
	if earned > 0:
		GameState.add_gold(earned)
	_refresh_loot()


func _on_upgrade_pressed() -> void:
	upgrade_pressed.emit()


func _on_continue_pressed() -> void:
	continue_pressed.emit()
