class_name FieldEnemy
extends Area2D

## Enemy as it appears on the field (top-down).
## Carries an EnemyData reference. On player collision, emits the
## enemy_encountered signal and frees itself — the battle_window takes over.

@export var data: EnemyData

@onready var _sprite: Sprite2D = $Sprite2D

var _triggered: bool = false


func _ready() -> void:
	_apply_data()
	body_entered.connect(_on_body_entered)


## Allow callers to inject data after instantiate().
func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data and data.sprite and _sprite:
		_sprite.texture = data.sprite


func _on_body_entered(body: Node) -> void:
	if _triggered or body is not Player:
		return
	_triggered = true
	EventBus.enemy_encountered.emit(self)
	queue_free()
