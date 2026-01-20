extends Node2D
class_name FieldController
## 필드 컨트롤러: 파티 배치, 적 스폰, 전투 연결 총괄

signal field_cleared
signal exit_reached(next_destination: String)

@export var tilemap: TileMapLayer
@export var spawn_point: Marker2D  # 파티 시작 위치
@export var exit_point: Area2D  # 출구

# 프리로드 - 씬이 없으면 런타임 로드
var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene

func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyLeader.tscn")
	party_follower_scene = load("res://scenes/field/PartyFollower.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")

var party_leader: PartyLeader
var party_followers: Array[PartyFollower] = []
var field_enemies: Array[FieldEnemy] = []

# 타일 타입 매핑 (타일셋 소스 ID 또는 타일 이름 -> tile_type)
# 이건 실제 타일셋에 맞춰 수정 필요!
@export var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest", 
	2: "road",
	3: "water",
	4: "stone",
	5: "cave"
}


func _ready() -> void:
	_load_scenes()
	_spawn_party()
	_spawn_field_enemies()
	
	if exit_point:
		exit_point.body_entered.connect(_on_exit_body_entered)


#region Party Setup
func _spawn_party() -> void:
	var start_pos: Vector2 = spawn_point.global_position if spawn_point else Vector2(100, 100)
	
	# 파티 멤버 가져오기
	var party_members: Array = PartyManager.get_party_members()
	if party_members.is_empty():
		push_warning("[FieldController] 파티 멤버 없음!")
		return
	
	# 리더 생성
	party_leader = party_leader_scene.instantiate() as PartyLeader
	party_leader.global_position = start_pos
	add_child(party_leader)
	
	# TODO: 리더 스프라이트 설정
	# var leader_data = party_members[0]
	# party_leader.sprite.texture = load(...)
	
	# 팔로워 생성 (2~4번째 파티원)
	for i in range(1, party_members.size()):
		var follower := party_follower_scene.instantiate() as PartyFollower
		add_child(follower)
		follower.setup(party_leader, i)
		party_followers.append(follower)
		
		# TODO: 팔로워 스프라이트 설정
	
	print("[FieldController] 파티 생성 완료: 리더 + ", party_followers.size(), " 팔로워")
#endregion


#region Enemy Spawning
func _spawn_field_enemies() -> void:
	# 타일맵에서 스폰 가능한 타일 수집
	var spawn_tiles := _collect_spawnable_tiles()
	
	if spawn_tiles.is_empty():
		push_warning("[FieldController] 스폰 가능한 타일 없음!")
		return
	
	# FieldManager에게 스폰 요청
	var spawn_data: Array = FieldManager.spawn_field_enemies(spawn_tiles)
	
	for data in spawn_data:
		var enemy := field_enemy_scene.instantiate() as FieldEnemy
		add_child(enemy)
		enemy.setup(data["enemy_id"], data["tile_type"], data["position"])
		enemy.player_contacted.connect(_on_field_enemy_contacted)
		field_enemies.append(enemy)
	
	print("[FieldController] 필드 에너미 스폰: ", field_enemies.size(), "마리")


func _collect_spawnable_tiles() -> Array:
	## 타일맵에서 스폰 가능한 타일 목록 수집
	var result: Array = []
	
	if not tilemap:
		push_warning("[FieldController] 타일맵 없음!")
		return result
	
	var used_cells := tilemap.get_used_cells()
	
	for cell in used_cells:
		var tile_data := tilemap.get_cell_tile_data(cell)
		if not tile_data:
			continue
		
		# 타일 소스 ID로 타입 결정 (실제 타일셋에 맞춰 수정 필요)
		var source_id := tilemap.get_cell_source_id(cell)
		var tile_type: String = tile_type_map.get(source_id, "grass")
		
		if FieldManager.can_spawn_on_tile(tile_type):
			var world_pos := tilemap.map_to_local(cell)
			result.append({
				"position": world_pos,
				"tile_type": tile_type,
				"cell": cell
			})
	
	return result
#endregion


#region Battle Connection
func _on_field_enemy_contacted(field_enemy: FieldEnemy) -> void:
	print("[FieldController] 적 접촉: ", field_enemy.enemy_id)
	
	# 전투 에너미 생성
	var battle_enemies: Array = FieldManager.generate_battle_enemies(
		field_enemy.enemy_id,
		field_enemy.tile_type
	)
	
	print("[FieldController] 전투 시작: ", battle_enemies)
	
	# BattleManager에게 전투 시작 요청
	var battle_id := BattleManager.start_battle(battle_enemies)
	
	# 필드 에너미 제거 (전투 시작했으니)
	field_enemies.erase(field_enemy)
	field_enemy.despawn()
	
	# TODO: BattleWindow 생성 및 표시
	# _create_battle_window(battle_id, battle_enemies)


func _on_exit_body_entered(body: Node2D) -> void:
	if body.is_in_group("party_leader"):
		# 진행 중인 전투 확인
		if BattleManager.get_active_battle_count() > 0:
			print("[FieldController] 전투 중에는 출구 사용 불가!")
			return
		
		# 보스 필드인데 보스 안 잡았으면
		if FieldManager.is_boss_field():
			# TODO: 보스 처치 여부 확인
			pass
		
		var next := FieldManager.get_next_destination()
		print("[FieldController] 출구 도달! 다음: ", next)
		exit_reached.emit(next)
#endregion


#region Public Methods
func get_party_leader() -> PartyLeader:
	return party_leader


func get_remaining_enemies() -> int:
	return field_enemies.size()
#endregion
