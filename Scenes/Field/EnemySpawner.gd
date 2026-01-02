extends Node2D

@export var enemy_scene: PackedScene
@export var spawn_list: Array[EnemyData] = [] 

# [설정]
@export var initial_spawn_count: int = 5 
@export var spawn_interval: float = 2.0
@export var max_enemies: int = 15
@export var spawn_radius_min: float = 650.0
@export var spawn_radius_max: float = 800.0 

var spawned_enemies: Array[Node] = []
var player: Node2D = null

func _ready():
	# [NEW] 랜덤 시드 초기화 (매번 다른 결과가 나오도록 강제)
	randomize()
	
	var timer = Timer.new()
	timer.wait_time = spawn_interval
	timer.autostart = true
	timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(timer)
	
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if player:
		# 시작 시 주변에 5마리 소환
		for i in range(initial_spawn_count):
			spawn_enemy(200.0, 300.0)

func _process(_delta):
	if not player:
		player = get_tree().get_first_node_in_group("player")

func _on_spawn_timer_timeout():
	if not player: return
	spawned_enemies = spawned_enemies.filter(func(e): return is_instance_valid(e))
	
	if spawned_enemies.size() < max_enemies:
		spawn_enemy()

func spawn_enemy(min_dist: float = spawn_radius_min, max_dist: float = spawn_radius_max):
	if not enemy_scene or spawn_list.is_empty():
		return
		
	var enemy = enemy_scene.instantiate()
	
	# 리스트에서 랜덤 선택
	var random_data = spawn_list.pick_random()
	enemy.enemy_data = random_data
	
	# [NEW] 디버깅용 로그 출력 (어떤 녀석이 나왔는지 확인)
	print("적 생성됨: ", random_data.name) 
	
	# 위치 계산
	var random_angle = randf() * TAU
	var random_distance = randf_range(min_dist, max_dist)
	var offset_vector = Vector2.RIGHT.rotated(random_angle) * random_distance
	
	enemy.global_position = player.global_position + offset_vector
	
	get_parent().add_child(enemy)
	spawned_enemies.append(enemy)

func _draw():
	if player:
		draw_arc(to_local(player.global_position), spawn_radius_min, 0, TAU, 32, Color(1, 0, 0, 0.3))
		draw_arc(to_local(player.global_position), spawn_radius_max, 0, TAU, 32, Color(0, 1, 0, 0.3))
		draw_arc(to_local(player.global_position), 500.0, 0, TAU, 32, Color(0, 0.5, 1, 0.3))
