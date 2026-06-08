class_name DQStatus
extends PanelContainer

## Dragon-Quest top status window (NAME / LV / HP / MP), shown only during MANUAL combat
## (before the 자동 전투 upgrade). Split out of the HUD into its own scene. Hidden by
## default; the grid is built in code (dynamic per party), so the scene is just this
## root + the script.

const HUD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var _grid: GridContainer


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	offset_top = 4.0
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 0)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	EventBus.battle_window_opened.connect(_on_battle_opened.unbind(1))
	EventBus.all_battles_resolved.connect(_on_hide)
	EventBus.party_member_hp_changed.connect(_refresh.unbind(3))
	EventBus.party_member_xp_changed.connect(_refresh.unbind(4))
	EventBus.party_changed.connect(_refresh)


func _on_battle_opened() -> void:
	if GameState.auto_battle_unlocked:
		return  # auto combat = card game, no DQ status window
	visible = true
	_refresh()


func _on_hide() -> void:
	visible = false


func _refresh() -> void:
	if not visible:
		return
	for c in _grid.get_children():
		c.queue_free()
	_cell("NAME", HORIZONTAL_ALIGNMENT_LEFT, 50.0)
	_cell("LV", HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
	_cell("HP", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	_cell("MP", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	for i in GameState.party_size():
		_cell(GameState.party[i].display_name, HORIZONTAL_ALIGNMENT_LEFT, 50.0)
		_cell(str(GameState.party_level(i)), HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
		_cell(str(GameState.party_hp[i]) if i < GameState.party_hp.size() else "-", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
		_cell(str(GameState.party_mp[i]) if i < GameState.party_mp.size() else "-", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)


func _cell(text: String, align: int, min_w: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HUD_FONT)
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(min_w, 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(l)
