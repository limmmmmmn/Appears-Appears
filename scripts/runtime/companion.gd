class_name Companion
extends Node2D

## A non-combatant party member that trails a leader (player or another companion).
## Pure visual — no physics body, no collision. Lerps toward the leader and
## animates the sprite sheet via CharacterVisual.

@export var follow_distance: float = 14.0
@export var max_speed: float = 110.0
@export var catch_up_factor: float = 8.0  ## higher = snappier catch-up

var leader: Node2D
var _pending_data: CharacterData

@onready var _visual: CharacterVisual = $Visual


func _ready() -> void:
	if _pending_data:
		_visual.setup(_pending_data)


## Inject the character data. Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)


func _physics_process(delta: float) -> void:
	if leader == null:
		_visual.set_velocity(Vector2.ZERO)
		return
	var to_leader: Vector2 = leader.global_position - global_position
	var dist: float = to_leader.length()
	if dist > follow_distance:
		var dir: Vector2 = to_leader / dist
		var speed: float = minf(max_speed, (dist - follow_distance) * catch_up_factor)
		var velocity: Vector2 = dir * speed
		global_position += velocity * delta
		_visual.set_velocity(velocity)
	else:
		_visual.set_velocity(Vector2.ZERO)
