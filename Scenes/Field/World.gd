# res://Scenes/Field/World.gd
extends Node2D

# 적은 리소스로 관리, 카메라 밖 랜덤 스폰
@export var enemy_scene: PackedScene # 방금 만든 Enemy.tscn
@export var enemy_data_list: Array[EnemyData] # 슬라임, 드래곤 등 데이터 리소스들
# [추가] 전투창 씬을 연결해야 함
@export var battle_window_scene: PackedScene

@onready var player = $Player
@onready var ui_layer = $UI # 방금 만든 CanvasLayer

# [추가] 최근 전투창 2개의 위치(Rect2)를 저장할 리스트
var battle_window_history: Array[Rect2] = []

func _on_spawn_timer_timeout():
	# 1. 플레이어가 없거나 데이터가 없으면 중단 (안전장치)
	if not player or enemy_data_list.is_empty():
		return
		
	# 2. 화면에 적이 너무 많으면 스폰 중단 (최적화)
	# "Enemies" 그룹에 있는 놈들을 세어봅니다.
	if get_tree().get_nodes_in_group("Enemies").size() >= 100:
		return

	# 3. 랜덤 위치 계산 
	# 플레이어 위치 + 랜덤 방향 * 거리(화면 밖)
	var angle = randf() * PI * 2
	var distance = randf_range(300, 300) # 화면 밖 거리 (해상도에 따라 조절)
	var spawn_pos = player.global_position + Vector2(cos(angle), sin(angle)) * distance
	
	# 4. 적 생성
	var new_enemy = enemy_scene.instantiate()
	new_enemy.global_position = spawn_pos
	
	# 5. 랜덤한 몬스터 종류 선택
	var random_data = enemy_data_list.pick_random()
	
# 6. 월드에 추가 및 설정
	add_child(new_enemy)
	new_enemy.setup(random_data, player)
	
	# [추가] 적이 보내는 '전투 신호'를 내 함수(on_battle_requested)에 연결
	new_enemy.battle_requested.connect(_on_battle_requested)

func _on_battle_requested(enemy_data: EnemyData):
	var battle_window = battle_window_scene.instantiate()
	ui_layer.add_child(battle_window)
	
	# [핵심 변경] setup 함수가 돌려주는 '최종 위치(final_rect)'를 받아서 변수에 담습니다.
	var final_rect = battle_window.setup(enemy_data, battle_window_history)
	
	# 받은 정확한 위치를 족보(history)에 기록합니다.
	battle_window_history.push_front(final_rect)
	
	# 디버깅용: 콘솔에 좌표가 잘 찍히는지 확인해보세요!
	print("전투창 생성됨: ", final_rect)
	
	# 기억은 2개까지만
	if battle_window_history.size() > 2:
		battle_window_history.pop_back()
