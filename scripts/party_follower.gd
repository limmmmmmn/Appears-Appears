extends Node2D
class_name PartyFollower
## 리더를 따라다니는 파티원

@export var follow_distance: float = 20.0  # 앞 캐릭터와의 거리
@export var follower_index: int = 0  # 0=리더, 1=첫번째 동료, 2=두번째...

var leader: Node2D = null
var position_history: Array[Vector2] = []
var history_max_size: int = 100

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	pass


func setup(target: Node2D, index: int, hero_id: String) -> void:
	leader = target
	follower_index = index
	
	# 히스토리 초기화 (리더 위치로)
	if leader:
		for i in range(history_max_size):
			position_history.append(leader.global_position)
	
	# 스프라이트 로드
	_load_hero_sprite(hero_id)


func _load_hero_sprite(hero_id: String) -> void:
	var hero_data := DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var sprite_path: String = hero_data.get("visuals", {}).get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)


func _process(_delta: float) -> void:
	if leader == null:
		return
	
	# 리더 위치 기록
	var leader_pos := leader.global_position
	
	# 이전 위치와 다르면 히스토리에 추가
	if position_history.is_empty() or leader_pos.distance_to(position_history[-1]) > 2.0:
		position_history.append(leader_pos)
		
		if position_history.size() > history_max_size:
			position_history.pop_front()
	
	# 히스토리에서 적절한 위치 찾기
	var target_distance := follow_distance * follower_index
	var accumulated_distance := 0.0
	var target_pos := leader_pos
	
	# 히스토리를 역순으로 탐색해서 목표 거리에 해당하는 위치 찾기
	for i in range(position_history.size() - 1, 0, -1):
		var segment_length := position_history[i].distance_to(position_history[i - 1])
		accumulated_distance += segment_length
		
		if accumulated_distance >= target_distance:
			target_pos = position_history[i]
			break
	
	# 위치 이동
	global_position = target_pos
	
	# 스프라이트 방향 (리더 기준)
	if leader_pos.x < global_position.x:
		sprite.flip_h = true
	elif leader_pos.x > global_position.x:
		sprite.flip_h = false
