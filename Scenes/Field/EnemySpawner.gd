extends Node2D

@export var enemy_scene: PackedScene

# [핵심 변경] 맵마다 다른 확률을 주기 위해 'EnemyData' 대신 'SpawnEntry' 리스트 사용
# 인스펙터에서 이 리스트에 (적 데이터 + 가중치) 쌍을 등록해야 합니다.
@export var spawn_table: Array[SpawnEntry] = [] 

# [설정]
@export var initial_spawn_count: int = 5    # 게임 시작 시 바로 소환할 마릿수
@export var spawn_interval: float = 2.0     # 적 생성 간격 (초)
@export var max_enemies: int = 15           # 화면에 유지될 최대 적 수
@export var spawn_radius_min: float = 650.0 # 평소 스폰 최소 거리 (화면 밖)
@export var spawn_radius_max: float = 800.0 # 평소 스폰 최대 거리

var spawned_enemies: Array[Node] = []
var player: Node2D = null

func _ready():
	# 랜덤 시드 초기화 (실행할 때마다 다른 결과 보장)
	randomize()
	
	# 스폰 타이머 설정
	var timer = Timer.new()
	timer.wait_time = spawn_interval
	timer.autostart = true
	timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(timer)
	
	# 안전하게 플레이어 찾기 (씬 로딩 대기)
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if player:
		# [초기 스폰] 게임 시작 직후 플레이어 화면 안(근처)에 적 소환
		# 200~500 거리: 너무 가깝지도 않고, 화면 밖으로 나가지도 않는 적당한 거리
		for i in range(initial_spawn_count):
			spawn_enemy(200.0, 500.0)

func _process(_delta):
	# 플레이어를 놓쳤을 경우 다시 찾기 (방어 코드)
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	# (선택 사항) 디버그용 원을 플레이어 따라다니게 그리려면 아래 주석 해제
	# queue_redraw() 

func _on_spawn_timer_timeout():
	if not player: return
	
	# 이미 죽거나 사라진 적(null)을 리스트에서 청소
	spawned_enemies = spawned_enemies.filter(func(e): return is_instance_valid(e))
	
	# 최대 마릿수 제한 확인
	if spawned_enemies.size() < max_enemies:
		# 평소에는 기본값(화면 밖 650~800) 사용
		spawn_enemy()

# [가중치 로직] SpawnEntry 리스트를 기반으로 확률적 뽑기
func get_random_enemy_by_weight() -> EnemyData:
	var total_weight = 0
	
	# 1. 전체 가중치 합계 계산
	for entry in spawn_table:
		total_weight += entry.weight
	
	# 2. 0 ~ (총합-1) 사이의 랜덤 숫자 뽑기
	var random_val = randi_range(0, total_weight - 1)
	var current_weight = 0
	
	# 3. 누적 가중치와 비교하여 당첨자 선정
	for entry in spawn_table:
		current_weight += entry.weight
		if random_val < current_weight:
			return entry.enemy # 껍데기(Entry) 안의 실제 적 데이터 반환
			
	# 혹시 테이블이 비었거나 계산 오류 시 안전하게 첫 번째 적 반환
	if spawn_table.size() > 0:
		return spawn_table[0].enemy
	return null

# 적 생성 실행 함수
func spawn_enemy(min_dist: float = spawn_radius_min, max_dist: float = spawn_radius_max):
	# 테이블이 비어있으면 생성 중단 (에러 방지)
	if not enemy_scene or spawn_table.is_empty():
		return
		
	var enemy = enemy_scene.instantiate()
	
	# 가중치 함수를 통해 적 데이터 결정
	var enemy_data_selected = get_random_enemy_by_weight()
	
	# 데이터가 없으면 중단 (안전장치)
	if not enemy_data_selected: return

	enemy.enemy_data = enemy_data_selected
	
	# [NEW] 적에게 스폰 테이블 정보 주입 (친구들 불러오라고)
	enemy.my_spawn_table = spawn_table
	
	# 디버깅용: 콘솔에 생성된 적 이름 출력
	# print("적 생성: ", enemy_data_selected.name) 
	
	# [위치 계산] 플레이어 기준 랜덤 위치 (뱀서 스타일)
	var random_angle = randf() * TAU # 360도 랜덤
	var random_distance = randf_range(min_dist, max_dist) # 거리 랜덤
	var offset_vector = Vector2.RIGHT.rotated(random_angle) * random_distance
	
	enemy.global_position = player.global_position + offset_vector
	
	# 월드맵(EnemySpawner의 부모)에 추가
	get_parent().add_child(enemy)
	spawned_enemies.append(enemy)

# 에디터 및 디버그용 시각화
func _draw():
	if player:
		# 평소 스폰 범위 (빨강 ~ 초록 사이)
		draw_arc(to_local(player.global_position), spawn_radius_min, 0, TAU, 32, Color(1, 0, 0, 0.3))
		draw_arc(to_local(player.global_position), spawn_radius_max, 0, TAU, 32, Color(0, 1, 0, 0.3))
		# 초기 스폰 범위 (파랑)
		draw_arc(to_local(player.global_position), 500.0, 0, TAU, 32, Color(0, 0.5, 1, 0.3))
