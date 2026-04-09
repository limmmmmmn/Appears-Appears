extends PanelContainer
## ForkChoice: 갈림길 선택 UI

signal option_selected(option: Dictionary)

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var button_container: VBoxContainer = $Margin/VBox/ButtonContainer

var _options: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(480, 260)
	DQThemeScript.apply_full(self)
	# 화면 중앙에 배치
	var vp := get_viewport_rect().size
	position = (vp - custom_minimum_size) * 0.5

func setup(options: Array) -> void:
	_options = options
	call_deferred("_build")

func _build() -> void:
	for c in button_container.get_children():
		c.queue_free()
	for opt in _options:
		var btn := Button.new()
		btn.text = String(opt.get("label", "?"))
		btn.pressed.connect(func() -> void: _choose(opt))
		button_container.add_child(btn)
	DQThemeScript.apply_label_color(self)

func _choose(opt: Dictionary) -> void:
	option_selected.emit(opt)
	queue_free()
