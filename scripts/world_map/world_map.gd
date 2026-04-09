extends Control
## WorldMap: 여정 노드를 가로로 배치. 출발 버튼으로 현재 노드로 진입.

signal depart_requested

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var node_container: Control = $NodeContainer
@onready var start_button: Button = $StartButton
@onready var title_label: Label = $Title
@onready var current_label: Label = $CurrentLabel
@onready var panel: PanelContainer = $Panel

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	DQThemeScript.apply_full(self)
	start_button.pressed.connect(func() -> void: depart_requested.emit())
	start_button.grab_focus()
	_build_nodes()
	_update_current_label()

func _build_nodes() -> void:
	for c in node_container.get_children():
		c.queue_free()
	var nodes := GameManager.get_journey_nodes()
	if nodes.is_empty():
		return
	var count := nodes.size()
	var margin_x := 160.0
	var area_width := (get_viewport_rect().size.x - margin_x * 2) if get_viewport() else 1600.0
	var step: float = area_width / float(maxi(1, count - 1)) if count > 1 else 0.0
	var base_y := 520.0
	for i in range(count):
		var node_data: Dictionary = nodes[i]
		var x := margin_x + step * i
		var y := base_y + (20.0 if i % 2 == 0 else -20.0)
		var icon := Label.new()
		icon.text = _icon_for(String(node_data.get("type", "")))
		icon.add_theme_font_size_override("font_size", 40)
		icon.position = Vector2(x - 20, y - 30)
		icon.add_theme_color_override("font_color", Color.WHITE if i >= GameManager.current_node_index else DQThemeScript.DIM_TEXT_COLOR)
		node_container.add_child(icon)

		var name_label := Label.new()
		name_label.text = String(node_data.get("name", ""))
		name_label.position = Vector2(x - 80, y + 24)
		name_label.size = Vector2(160, 24)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", Color.WHITE if i >= GameManager.current_node_index else DQThemeScript.DIM_TEXT_COLOR)
		node_container.add_child(name_label)

		if i == GameManager.current_node_index:
			var marker := Label.new()
			marker.text = "▼"
			marker.position = Vector2(x - 10, y - 70)
			marker.add_theme_font_size_override("font_size", 28)
			marker.add_theme_color_override("font_color", Color.WHITE)
			node_container.add_child(marker)
			_animate_marker(marker)

func _animate_marker(marker: Label) -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(marker, "position:y", marker.position.y - 8.0, 0.5)
	tween.tween_property(marker, "position:y", marker.position.y, 0.5)

func _icon_for(type_str: String) -> String:
	match type_str:
		"field": return "⚔"
		"town": return "🏠"
		"boss": return "💀"
		_: return "●"

func _update_current_label() -> void:
	var nodes := GameManager.get_journey_nodes()
	if nodes.is_empty():
		current_label.text = ""
		return
	var idx := GameManager.current_node_index
	if idx >= nodes.size():
		current_label.text = "여정 완료"
		return
	var d: Dictionary = nodes[idx]
	current_label.text = "다음: %s" % d.get("name", "")
