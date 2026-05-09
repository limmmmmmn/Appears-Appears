class_name FieldTownTile
extends Area2D

## Field tile that sends the party to town.
## Entering town is an escape: active battle windows are aborted by Main, so no
## pending combat rewards are paid out.

@onready var _sprite: Sprite2D = $Sprite2D

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func reset() -> void:
	_triggered = false


func _on_body_entered(body: Node) -> void:
	if _triggered or body is not Player:
		return
	_triggered = true
	EventBus.town_entered.emit(self)
