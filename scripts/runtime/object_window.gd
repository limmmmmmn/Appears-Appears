class_name ObjectWindow
extends Control

## 방문 창 — the game's third window type (전투창 / 이벤트창 / 방문 창).
## The hero walks to a placed object tile (마을, 모닥불, 성소 …) and this big
## centered window opens: upgrades, purchases, rest. The FIELD HOLDS STILL while
## it's open (GameState.open_object_window) and resumes on close — RPG-style
## "entering the building", not a desktop app.
##
## Chrome is authored in object_window.tscn (minimal RPG frame — no titlebar
## buttons). Content comes from the visited structure's get_inspector_data():
##   { name, info, sprite, actions[{label, cost, enabled, on_press, close_after?}],
##     shop: bool (마을 여관+장비), upgrade_shop: bool (강화 리스트) }

const UPGRADE_SHOP_SCRIPT = preload("res://scripts/runtime/upgrade_shop.gd")

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _sprite: TextureRect = %ObjectSprite
@onready var _name_label: Label = %NameLabel
@onready var _info_label: Label = %InfoLabel
@onready var _content: VBoxContainer = %Content
@onready var _close_button: Button = %CloseButton

var _structure: Node = null


func _ready() -> void:
	visible = false
	if Engine.is_editor_hint():
		return
	_close_button.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	EventBus.object_window_requested.connect(open_for)
	# Live refresh while open: purchases / equips change prices and lists.
	EventBus.gold_changed.connect(_on_state_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_state_changed.unbind(1))
	EventBus.inventory_changed.connect(_on_state_changed)
	EventBus.party_equipment_changed.connect(_on_state_changed.unbind(1))
	EventBus.weapon_equipped.connect(_on_state_changed.unbind(1))
	EventBus.armor_equipped.connect(_on_state_changed.unbind(1))


func open_for(structure: Node) -> void:
	if structure == null or not structure.has_method("get_inspector_data"):
		return
	_structure = structure
	# The visited object can despawn under us (loop reset) — close with it.
	if not structure.tree_exited.is_connected(_on_structure_gone):
		structure.tree_exited.connect(_on_structure_gone)
	GameState.open_object_window()
	visible = true
	_render()
	# Pop-in: the window swings up like an RPG menu, dim fades behind it.
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_dim.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	_structure = null
	GameState.close_object_window()


func _on_structure_gone() -> void:
	close()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_state_changed() -> void:
	if visible and is_instance_valid(_structure):
		_render()


func _render() -> void:
	var data: Dictionary = _structure.get_inspector_data()
	_name_label.text = str(data.get("name", ""))
	var tex: Texture2D = data.get("sprite", null)
	_sprite.texture = tex
	_sprite.visible = tex != null
	var info: String = str(data.get("info", ""))
	_info_label.text = info
	_info_label.visible = not info.is_empty()
	for c in _content.get_children():
		c.queue_free()
	for action: Dictionary in data.get("actions", []):
		_content.add_child(_make_action_button(action))
	if bool(data.get("shop", false)):
		GearShop.build(_content)
	if bool(data.get("upgrade_shop", false)):
		UPGRADE_SHOP_SCRIPT.build(_content)


func _make_action_button(action: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
	var label: String = str(action.get("label", "강화"))
	var cost: int = int(action.get("cost", 0))
	var enabled: bool = bool(action.get("enabled", false))
	b.text = "%s  %dG" % [label, cost] if cost > 0 else label
	b.disabled = not enabled
	var cb: Callable = action.get("on_press", Callable())
	if enabled and cb.is_valid():
		b.pressed.connect(cb)
		# e.g. 쉰다: the action plays out ON the field, so the window steps aside.
		if bool(action.get("close_after", false)):
			b.pressed.connect(close)
	return b
