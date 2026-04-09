extends PanelContainer
## EventWindow: treasure / equipment / story 이벤트 팝업

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var title_label: Label = $Margin/VBox/Title
@onready var description_label: Label = $Margin/VBox/Description
@onready var button_container: HBoxContainer = $Margin/VBox/ButtonContainer

var _event: Dictionary = {}
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(460, 240)
	DQThemeScript.apply_full(self)
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	position = Vector2(
		randf_range(80, 1920 - 540),
		randf_range(120, 1080 - 340)
	)
	gui_input.connect(_on_gui_input)

func setup(event_data: Dictionary) -> void:
	_event = event_data.duplicate(true)
	call_deferred("_build")

func _build() -> void:
	for c in button_container.get_children():
		c.queue_free()
	var t := String(_event.get("type", ""))
	match t:
		"treasure":
			_build_treasure()
		"equipment":
			_build_equipment()
		"story":
			_build_story()
		_:
			_build_story()
	DQThemeScript.apply_label_color(self)

func _build_treasure() -> void:
	title_label.text = "보물 상자"
	var amount := int(_event.get("gold", 0))
	description_label.text = "보물 상자를 발견했다!\n%dG 들어있다." % amount
	var take := Button.new()
	take.text = "받기"
	take.pressed.connect(func() -> void:
		GameManager.add_gold(amount)
		_close()
	)
	button_container.add_child(take)

func _build_equipment() -> void:
	var pool: Array = _event.get("pool", [])
	if pool.is_empty():
		_close()
		return
	var picked_id := String(pool[randi() % pool.size()])
	var item: Dictionary = DataLoader.load_equipment(picked_id)
	title_label.text = "장비 발견"
	description_label.text = "%s 을(를) 발견했다.\n%s\n%s" % [
		item.get("name", "?"),
		item.get("description", ""),
		_stat_summary(item)
	]
	var equip := Button.new()
	equip.text = "장착"
	equip.pressed.connect(func() -> void:
		if GameManager.party_members.size() > 0:
			var first: Dictionary = GameManager.party_members[0]
			first["base_str"] = int(first.get("base_str", 0)) + int(item.get("str_bonus", 0))
			first["base_vit"] = int(first.get("base_vit", 0)) + int(item.get("vit_bonus", 0))
			first["base_agi"] = int(first.get("base_agi", 0)) + int(item.get("agi_bonus", 0))
			first["base_int"] = int(first.get("base_int", 0)) + int(item.get("int_bonus", 0))
		_close()
	)
	button_container.add_child(equip)
	var discard := Button.new()
	discard.text = "버리기"
	discard.pressed.connect(_close)
	button_container.add_child(discard)

func _build_story() -> void:
	title_label.text = String(_event.get("title", "이벤트"))
	description_label.text = String(_event.get("text", ""))
	var ok := Button.new()
	ok.text = "계속"
	ok.pressed.connect(_close)
	button_container.add_child(ok)

func _stat_summary(item: Dictionary) -> String:
	var parts: Array[String] = []
	if int(item.get("str_bonus", 0)) != 0: parts.append("STR%+d" % int(item["str_bonus"]))
	if int(item.get("vit_bonus", 0)) != 0: parts.append("VIT%+d" % int(item["vit_bonus"]))
	if int(item.get("agi_bonus", 0)) != 0: parts.append("AGI%+d" % int(item["agi_bonus"]))
	if int(item.get("int_bonus", 0)) != 0: parts.append("INT%+d" % int(item["int_bonus"]))
	return " ".join(parts) if parts.size() > 0 else ""

func _close() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_offset = get_global_mouse_position() - position
	elif event is InputEventMouseMotion and _dragging:
		position = get_global_mouse_position() - _drag_offset
