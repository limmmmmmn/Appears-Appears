class_name Companion
extends Node2D

## A non-combatant party member that trails a leader (player or another companion).
## Pure visual — no physics body, no collision. Lerps toward the leader and
## animates the sprite sheet via CharacterVisual.

@export var follow_distance: float = 14.0
@export var leader_follow_distance: float = 22.0
@export var max_gap: float = 28.0
@export var leader_max_gap: float = 40.0
@export var max_speed: float = 160.0
@export var catch_up_factor: float = 9.0  ## higher = snappier catch-up
@export var leader_speed_margin: float = 28.0
@export var trail_min_step: float = 1.0
@export var trail_max_points: int = 36

var leader: Node2D
var _pending_data: CharacterData
var _last_position: Vector2
var _leader_trail: Array[Vector2] = []

@onready var _visual: CharacterVisual = $Visual


func _ready() -> void:
	add_to_group("party_member")
	_last_position = global_position
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
		_leader_trail.clear()
		_last_position = global_position
		return
	_remember_leader_position()
	var target_distance: float = _target_follow_distance()
	var target_position: Vector2 = _leader_trail_target(target_distance)
	var to_target: Vector2 = target_position - global_position
	var dist_to_target: float = to_target.length()
	if dist_to_target > 0.5:
		var dir: Vector2 = to_target / dist_to_target
		var leader_speed: float = _leader_speed()
		var leader_dist: float = global_position.distance_to(leader.global_position)
		var gap_range: float = maxf(_target_max_gap() - target_distance, 1.0)
		var gap_ratio: float = clampf((leader_dist - target_distance) / gap_range, 0.0, 1.0)
		var desired_speed: float = dist_to_target * catch_up_factor
		var speed: float = minf(maxf(max_speed, leader_speed + leader_speed_margin), desired_speed + leader_speed * gap_ratio)
		var velocity: Vector2 = dir * speed
		global_position += velocity * delta
		_limit_gap_to_leader()
		_visual.set_velocity(velocity)
	else:
		_visual.set_velocity(Vector2.ZERO)
	_last_position = global_position


func _leader_speed() -> float:
	if leader is CharacterBody2D:
		return (leader as CharacterBody2D).velocity.length()
	if leader is Companion:
		return (leader as Companion).current_speed()
	return 0.0


func current_speed() -> float:
	return (global_position - _last_position).length() / maxf(get_physics_process_delta_time(), 0.001)


func _target_follow_distance() -> float:
	return leader_follow_distance if leader is Player else follow_distance


func _target_max_gap() -> float:
	return leader_max_gap if leader is Player else max_gap


func _remember_leader_position() -> void:
	var pos: Vector2 = leader.global_position
	if _leader_trail.is_empty():
		_leader_trail.append(pos)
		return
	if pos.distance_squared_to(_leader_trail[0]) >= trail_min_step * trail_min_step:
		_leader_trail.push_front(pos)
	while _leader_trail.size() > trail_max_points:
		_leader_trail.pop_back()


func _leader_trail_target(distance: float) -> Vector2:
	if _leader_trail.is_empty():
		return leader.global_position
	var previous: Vector2 = _leader_trail[0]
	var traveled: float = 0.0
	for i in range(1, _leader_trail.size()):
		var point: Vector2 = _leader_trail[i]
		var segment: float = previous.distance_to(point)
		if segment <= 0.001:
			previous = point
			continue
		if traveled + segment >= distance:
			var t: float = (distance - traveled) / segment
			return previous.lerp(point, t)
		traveled += segment
		previous = point
	return _leader_trail.back()


func _limit_gap_to_leader() -> void:
	var offset: Vector2 = global_position - leader.global_position
	var dist: float = offset.length()
	var allowed_gap: float = _target_max_gap()
	if dist <= allowed_gap or dist <= 0.001:
		return
	global_position = leader.global_position + offset.normalized() * allowed_gap
