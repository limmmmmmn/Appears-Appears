class_name Town
extends CanvasLayer

## Home-base hub between field loops. The current screen is the incremental
## skill-tree screen plus a small persistent bottom bar.

signal closed(region_id: StringName)

const SKILL_TREE_VIEW_SCENE_SCRIPT: Script = preload("res://scripts/runtime/skill_tree_view.gd")

@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _continue_button: Button = %ContinueButton

var _title_override: String = ""
var _tree_view: Control
var _grass_button: Button
var _forest_button: Button
var _choosing_region: bool = false


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_title_label.text = _title_override if not _title_override.is_empty() else GameState.field_region_summary()
	_heal_party_to_full()
	_refresh_gold_label()
	_install_skill_tree()
	_install_region_buttons()
	_update_continue_button()
	_continue_button.pressed.connect(_on_continue_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.skill_node_purchase_succeeded.connect(_on_skill_node_purchase_succeeded)
	EventBus.skill_node_purchase_failed.connect(_on_skill_node_purchase_failed)
	_continue_button.grab_focus()


func _install_skill_tree() -> void:
	_tree_view = SKILL_TREE_VIEW_SCENE_SCRIPT.new() as Control
	_tree_view.name = "SkillTreeView"
	_tree_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tree_view)
	move_child(_tree_view, 2)
	_tree_view.purchase_requested.connect(_on_skill_node_purchase_requested)


func _install_region_buttons() -> void:
	var bottom_bar := _continue_button.get_parent()
	_grass_button = _make_region_button("초원")
	_forest_button = _make_region_button("숲")
	bottom_bar.add_child(_grass_button)
	bottom_bar.add_child(_forest_button)
	_grass_button.hide()
	_forest_button.hide()
	_grass_button.pressed.connect(_close_with_region.bind(GameState.FIELD_REGION_GRASS))
	_forest_button.pressed.connect(_close_with_region.bind(GameState.FIELD_REGION_FOREST))


func _make_region_button(label: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(70.0, 22.0)
	button.focus_mode = Control.FOCUS_ALL
	button.text = label
	button.add_theme_stylebox_override("normal", _continue_button.get_theme_stylebox("normal"))
	button.add_theme_stylebox_override("hover", _continue_button.get_theme_stylebox("hover"))
	button.add_theme_stylebox_override("pressed", _continue_button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", _continue_button.get_theme_stylebox("focus"))
	button.add_theme_color_override("font_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_color_override("font_focus_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_font_override("font", _continue_button.get_theme_font("font"))
	button.add_theme_font_size_override("font_size", 11)
	return button


func _heal_party_to_full() -> void:
	for i in GameState.party_size():
		var max_hp: int = GameState.effective_max_hp(i)
		if GameState.party_hp[i] < max_hp:
			GameState.heal_party_member(i, max_hp - GameState.party_hp[i])


func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()
	if _tree_view:
		_tree_view.refresh()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


func _on_skill_node_purchase_requested(node_id: StringName) -> void:
	GameState.purchase_skill_node(node_id)
	if _tree_view:
		_tree_view.refresh()


func _on_skill_node_purchase_succeeded(_node) -> void:
	_refresh_gold_label()
	_update_continue_button()
	if _tree_view:
		_tree_view.refresh()


func _on_skill_node_purchase_failed(_node) -> void:
	if _tree_view:
		_tree_view.refresh()


func _on_continue_pressed() -> void:
	if GameState.forest_region_unlocked():
		_show_region_choices()
		return
	_close_with_region(GameState.FIELD_REGION_GRASS)


func _show_region_choices() -> void:
	if _choosing_region:
		return
	_choosing_region = true
	_continue_button.hide()
	_grass_button.show()
	_forest_button.show()
	_grass_button.grab_focus()


func _update_continue_button() -> void:
	_continue_button.text = "필드로 나가기" if GameState.forest_region_unlocked() else "초원으로 나가기"


func _close_with_region(region_id: StringName) -> void:
	closed.emit(region_id)
	queue_free()
