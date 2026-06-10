class_name FieldNameChip
extends PanelContainer

## Top-strip chip showing the current field's name (지역 마일스톤 기준 — see
## GameState.field_region_name). Chrome is authored in field_name_chip.tscn;
## this only keeps the text current as milestones unlock.


@onready var _label: Label = %FieldNameLabel


func _ready() -> void:
	EventBus.world_started.connect(_refresh)
	EventBus.field_loop_started.connect(_refresh.unbind(1))
	EventBus.gold_changed.connect(_refresh.unbind(1))
	EventBus.skill_node_purchase_succeeded.connect(_refresh.unbind(1))
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var new_name: String = GameState.field_region_name()
	if _label.text == new_name:
		return
	_label.text = new_name
	# Milestone moment: the world itself got renamed — a little pop sells it.
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
