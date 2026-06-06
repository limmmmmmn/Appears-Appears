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
## True while this companion's party member is downed (shows the lying pose).
var _downed_visual: bool = false
## Battle formation: when on, the companion leaves the snake and walks to its
## assigned row slot below the windows, then faces UP (back to camera).
var _in_formation: bool = false
var _formation_target: Vector2 = Vector2.ZERO

@onready var _visual: CharacterVisual = $Visual


func _ready() -> void:
	add_to_group("party_member")
	_last_position = global_position
	_seed_trail()
	if _pending_data:
		_visual.setup(_pending_data)
	# Hit reaction only: flinch when this member is hit. No attack lunge.
	EventBus.party_damage_taken.connect(_on_party_damage_taken)


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
	# Battle formation: break off the snake, walk to the assigned slot, face up.
	if _in_formation:
		var to_slot: Vector2 = _formation_target - global_position
		if to_slot.length() > 1.0:
			var spd: float = minf(max_speed, maxf(60.0, to_slot.length() * catch_up_factor))
			var prev: Vector2 = global_position
			global_position = global_position.move_toward(_formation_target, spd * delta)
			_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
		else:
			global_position = _formation_target
			if _downed_visual:
				_visual.set_velocity(Vector2.ZERO)
			else:
				_visual.face_dir(CharacterVisual.Dir.UP)  # back to camera, facing the windows
		_last_position = global_position
		return
	_remember_player_position()
	# A downed member falls to the BACK of the snake (trails behind everyone) while
	# it's knocked out; alive members keep their normal slot spacing.
	var slots: float = float(slot_index)
	if _downed_visual:
		slots = float(GameState.party_size() + slot_index)
	var target_position: Vector2 = _trail_target(slots * follow_spacing)
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
	if _downed_visual:
		_visual.set_velocity(Vector2.ZERO)  # lying pose: no walk animation
	_last_position = global_position


## Field shows this companion lying down while its party member is downed.
func set_downed_visual(is_down: bool) -> void:
	_downed_visual = is_down
	if _visual:
		_visual.rotation = deg_to_rad(90.0) if is_down else 0.0
		_visual.modulate = Color(0.6, 0.6, 0.66, 1.0) if is_down else Color(1, 1, 1, 1)


func current_speed() -> float:
	return (global_position - _last_position).length() / maxf(get_physics_process_delta_time(), 0.001)


## BattleManager assigns this companion's battle-formation row slot (world pos).
func set_formation_slot(pos: Vector2) -> void:
	_in_formation = true
	_formation_target = pos


## Leave battle formation and rejoin the trailing snake.
func clear_formation() -> void:
	if not _in_formation:
		return
	_in_formation = false
	_seed_trail()  # restart the trail from here so the snake doesn't snap


# ─── Hit reaction ──────────────────────────────────────────────────────
## Field companion only reacts to being HIT now — no attack lunge. Flinch fires
## whenever this member takes damage in any battle window, wherever it's standing.
func _on_party_damage_taken(member_index: int, _amount: int) -> void:
	if member_index == slot_index and _visual != null and not _downed_visual:
		_visual.play_hit_flinch()


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
