extends Node2D

@export var enemy_scene: PackedScene
@export var max_enemy_count: int = 10

# [추가됨] 스폰 주기 (초 단위): 작을수록 적이 빨리 나옵니다.
@export var spawn_interval: float = 2.0 

@export var min_spawn_distance: float = 500.0
@export var max_spawn_distance: float = 700.0

@onready var timer: Timer = $SpawnTimer

func _ready() -> void:
	# [추가됨] 인스펙터에서 설정한 시간으로 타이머 주기 업데이트
	timer.wait_time = spawn_interval
	
	timer.timeout.connect(_on_spawn_timer_timeout)
	
	# [선택 사항] 시작하자마자 바로 한 마리 뽑고 시작하려면 주석 해제
	# _on_spawn_timer_timeout()

func _on_spawn_timer_timeout() -> void:
	# (나머지 코드는 이전과 동일합니다)
	var current_enemies = get_tree().get_nodes_in_group("FieldEnemy")
	if current_enemies.size() >= max_enemy_count:
		return
	
	if enemy_scene == null: return

	var spawn_pos = _get_random_spawn_position()
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_pos
	get_tree().current_scene.add_child(enemy)

func _get_random_spawn_position() -> Vector2:
	# (이전 코드 유지)
	var camera = get_viewport().get_camera_2d()
	var center_pos = Vector2.ZERO
	if camera:
		center_pos = camera.get_screen_center_position()
	else:
		center_pos = global_position
		
	var distance = randf_range(min_spawn_distance, max_spawn_distance)
	var angle = randf() * TAU
	
	return center_pos + Vector2(cos(angle), sin(angle)) * distance
