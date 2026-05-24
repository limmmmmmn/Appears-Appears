class_name Town
extends CanvasLayer

## Home-base hub between field loops. The current screen is the incremental
## skill-tree screen plus a small persistent bottom bar.

signal closed

const SKILL_TREE_VIEW_SCENE_SCRIPT: Script = preload("res://scripts/runtime/skill_tree_view.gd")

@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _continue_button: Button = %ContinueButton

var _title_override: String = ""
var _tree_view: Control


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_title_label.text = _title_override if not _title_override.is_empty() else GameState.field_region_summary()
	_heal_party_to_full()
	_refresh_gold_label()
	_install_skill_tree()
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
	if _tree_view:
		_tree_view.refresh()


func _on_skill_node_purchase_failed(_node) -> void:
	if _tree_view:
		_tree_view.refresh()


func _on_continue_pressed() -> void:
	closed.emit()
	queue_free()
