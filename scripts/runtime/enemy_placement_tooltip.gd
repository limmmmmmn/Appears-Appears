@tool
class_name EnemyPlacementTooltip
extends PanelContainer

## Standalone tooltip for the enemy / objet placement shelf.
## Position and size are authored in the scene, so it can be moved independently
## from the tile box in main.tscn.

@onready var _tip_label: Label = %TipLabel


func _ready() -> void:
	add_to_group("placement_tooltip")
	if Engine.is_editor_hint():
		visible = true
		return
	hide_tip()


func show_text(text: String) -> void:
	if _tip_label == null:
		return
	_tip_label.text = text
	visible = true


func hide_tip() -> void:
	visible = false
