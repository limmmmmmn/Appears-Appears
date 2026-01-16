extends Node2D
## 파티 전체를 관리 (리더 + 따라다니는 동료들)

@export var follower_distance: float = 18.0  # 동료 간 거리

var leader: Player = null
var followers: Array[PartyFollower] = []

var follower_scene: PackedScene = preload("res://scenes/player/party_follower.tscn")


func _ready() -> void:
	# 플레이어(리더) 찾기
	await get_tree().process_frame
	leader = get_tree().get_first_node_in_group("player") as Player
	
	if leader == null:
		push_error("[PartyManager] 플레이어를 찾을 수 없음")
		return
	
	# 파티원 생성 (리더 제외, 인덱스 1부터)
	_spawn_followers()


func _spawn_followers() -> void:
	var party := GameManager.party
	
	# 첫 번째는 리더(플레이어)이므로 스킵, 나머지 동료 생성
	for i in range(1, party.size()):
		var hero_id: String = party[i]
		_spawn_follower(hero_id, i)


func _spawn_follower(hero_id: String, index: int) -> void:
	var follower := follower_scene.instantiate() as PartyFollower
	
	# 이전 캐릭터를 따라가게 설정
	var target: Node2D
	if index == 1:
		target = leader
	else:
		target = followers[index - 2]  # followers 배열은 0부터 시작
	
	follower.follow_distance = follower_distance
	add_child(follower)
	
	follower.setup(target, index, hero_id)
	followers.append(follower)
	
	print("[PartyManager] 동료 생성: %s (index: %d)" % [hero_id, index])
