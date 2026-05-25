class_name Companion
extends Node2D

## A non-combatant party member that follows the player's path like a classic
## JRPG party line. Pure visual — no physics body, no collision.

@export var follow_spacing: float = 18.0
@export var trail_min_step: float = 0.5
@export var trail_max_points: int = 240
@export var diagonal_trail_step: float = 0.5
@export var max_speed: float = 180.0
@export var catch_up_factor: float = 12.0  ## higher = snappier catch-up
@export var stop_distance: float = 0.5

var player: CharacterBody2D
var slot_index: int = 1
var _pending_data: CharacterData
var _last_position: Vector2
var _player_trail: Array[Vector2] = []

@onready var _visual: CharacterVisual = $Visual


func _ready() -> void:
	add_to_group("party_member")
	_last_position = global_position
	_seed_trail()
	if _pending_data:
		_visual.setup(_pending_data)


## Inject the character data. Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)


func _physics_process(delta: float) -> void:
	if player == null:
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	_remember_player_position()
	var target_position: Vector2 = _trail_target(float(slot_index) * follow_spacing)
	var to_target: Vector2 = target_position - global_position
	var dist_to_target: float = to_target.length()
	if dist_to_target > stop_distance:
		var player_speed: float = player.velocity.length()
		var speed: float = minf(max_speed, maxf(player_speed + follow_spacing * 2.0, dist_to_target * catch_up_factor))
		var previous_position: Vector2 = global_position
		global_position = global_position.move_toward(target_position, speed * delta)
		var velocity: Vector2 = (global_position - previous_position) / maxf(delta, 0.001)
		_visual.set_velocity(velocity)
	else:
		global_position = target_position
		_visual.set_velocity(Vector2.ZERO)
	_last_position = global_position


func current_speed() -> float:
	return (global_position - _last_position).length() / maxf(get_physics_process_delta_time(), 0.001)


func snap_to_formation() -> void:
	if player == null:
		return
	_seed_trail()
	global_position = _trail_target(float(slot_index) * follow_spacing)
	_last_position = global_position


func _seed_trail() -> void:
	_player_trail.clear()
	if player == null:
		return
	_player_trail.append(player.global_position)
	for i in range(1, maxi(slot_index + 4, 8)):
		_player_trail.append(player.global_position + Vector2.UP * follow_spacing * float(i))


func _remember_player_position() -> void:
	if _player_trail.is_empty():
		_seed_trail()
		return
	var pos: Vector2 = player.global_position
	var step: float = _current_trail_step()
	if pos.distance_squared_to(_player_trail[0]) >= step * step:
		_player_trail.push_front(pos)
	while _player_trail.size() > trail_max_points:
		_player_trail.pop_back()


func _current_trail_step() -> float:
	if absf(player.velocity.x) > 0.01 and absf(player.velocity.y) > 0.01:
		return diagonal_trail_step
	return trail_min_step


func _trail_target(distance: float) -> Vector2:
	if _player_trail.is_empty():
		return player.global_position if player else global_position
	var previous: Vector2 = _player_trail[0]
	var traveled: float = 0.0
	for i in range(1, _player_trail.size()):
		var point: Vector2 = _player_trail[i]
		var segment: float = previous.distance_to(point)
		if segment <= 0.001:
			previous = point
			continue
		if traveled + segment >= distance:
			var t: float = (distance - traveled) / segment
			return previous.lerp(point, t)
		traveled += segment
		previous = point
	return _player_trail.back()
