extends CharacterBody2D
class_name FieldEnemy

@export var enemy_id: String = "slime"

var is_active: bool = true
var spawn_position: Vector2
var wander_range: float = 48.0
var move_speed: float = 20.0

var wander_target: Vector2
var wander_timer: float = 0.0
var wander_wait_time: float = 2.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	spawn_position = global_position
	_load_enemy_data()
	_pick_new_wander_target()
	hitbox.add_to_group("enemy_hitbox")


func _load_enemy_data() -> void:
	var data = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		return
	
	var field_data = data.get("field", {})
	wander_range = float(field_data.get("wander_range", 48))
	move_speed = float(field_data.get("move_speed", 20))
	
	var sprite_path = str(field_data.get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_process_wander(delta)


func _process_wander(delta: float) -> void:
	var distance_to_target = global_position.distance_to(wander_target)
	
	if distance_to_target < 4.0:
		wander_timer += delta
		velocity = Vector2.ZERO
		if wander_timer >= wander_wait_time:
			wander_timer = 0.0
			_pick_new_wander_target()
	else:
		var direction = global_position.direction_to(wander_target)
		velocity = direction * move_speed
		if direction.x < 0:
			sprite.flip_h = true
		elif direction.x > 0:
			sprite.flip_h = false
	
	move_and_slide()


func _pick_new_wander_target() -> void:
	var angle = randf() * TAU
	var distance = randf() * wander_range
	wander_target = spawn_position + Vector2(cos(angle), sin(angle)) * distance
	wander_wait_time = randf_range(1.0, 3.0)


func on_encountered() -> void:
	is_active = false
	visible = false
	collision.set_deferred("disabled", true)
	hitbox.set_deferred("monitoring", false)
	await get_tree().create_timer(0.5).timeout
	queue_free()


func setup(id: String, pos: Vector2) -> void:
	enemy_id = id
	global_position = pos
