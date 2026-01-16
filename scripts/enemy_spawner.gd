extends Node2D
class_name EnemySpawner
## 카메라 바로 바깥에서 적을 생성하는 스포너 (뱀서 방식)

@export var spawn_interval: float = 0.5
@export var max_enemies: int = 100
@export var spawn_margin: float = 32.0  # 카메라 바깥 여백

# 스폰 가능한 적 목록 (태그 또는 id 배열)
@export var enemy_pool: Array[String] = ["slime", "bat", "skeleton"]

var spawn_timer: float = 0.0
var current_enemies: Array[FieldEnemy] = []

@onready var player: Player = null

# 적 씬 프리로드
var enemy_scene: PackedScene = preload("res://scenes/enemy/field_enemy.tscn")


func _ready() -> void:
	# 플레이어 찾기
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player") as Player
	
	if player == null:
		push_error("[EnemySpawner] 플레이어를 찾을 수 없음")


func _process(delta: float) -> void:
	if player == null:
		return
	
	# 죽은 적 정리
	_cleanup_dead_enemies()
	
	# 스폰 타이머
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		_try_spawn_enemy()


func _cleanup_dead_enemies() -> void:
	current_enemies = current_enemies.filter(func(e): return is_instance_valid(e))


func _try_spawn_enemy() -> void:
	if current_enemies.size() >= max_enemies:
		return
	
	if enemy_pool.is_empty():
		return
	
	var spawn_pos := _get_spawn_position()
	var enemy_id := enemy_pool[randi() % enemy_pool.size()]
	
	_spawn_enemy(enemy_id, spawn_pos)


func _get_spawn_position() -> Vector2:
	## 카메라 바로 바깥 위치 계산
	var viewport_size := get_viewport_rect().size
	var camera_center := player.global_position
	
	# 화면 반 크기 + 여백
	var half_width := viewport_size.x / 2 + spawn_margin
	var half_height := viewport_size.y / 2 + spawn_margin
	
	# 4방향 중 랜덤 선택
	var side := randi() % 4
	var pos := Vector2.ZERO
	
	match side:
		0:  # 위
			pos.x = randf_range(-half_width, half_width)
			pos.y = -half_height
		1:  # 아래
			pos.x = randf_range(-half_width, half_width)
			pos.y = half_height
		2:  # 왼쪽
			pos.x = -half_width
			pos.y = randf_range(-half_height, half_height)
		3:  # 오른쪽
			pos.x = half_width
			pos.y = randf_range(-half_height, half_height)
	
	return camera_center + pos


func _spawn_enemy(id: String, pos: Vector2) -> void:
	var enemy := enemy_scene.instantiate() as FieldEnemy
	enemy.setup(id, pos)
	
	get_parent().add_child(enemy)
	current_enemies.append(enemy)
	
	print("[EnemySpawner] 스폰: %s at %s" % [id, pos])
