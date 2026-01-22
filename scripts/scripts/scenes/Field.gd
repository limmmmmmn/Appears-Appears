extends Node2D
## 필드 씬 컨트롤러

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal field_cleared

@export var spawn_point: Marker2D
@export var exit_area: Area2D
@export var tilemap: TileMapLayer

var party_leader: PartyLeader
var party_followers: Array[PartyFollower] = []
var field_enemies: Array[FieldEnemy] = []
var hud: FieldHUD

var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene
var hud_scene: PackedScene

@export var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest",
	2: "road",
	3: "water",
	4: "cave"
}


func _ready() -> void:
	_load_scenes()
	_setup_hud()
	_spawn_party()
	_spawn_field_enemies()
	_setup_exit()
	
	# 테스트: 인벤토리에 아이템 추가
	if InventoryManager:
		InventoryManager.add_item("sword_common", 2)
		InventoryManager.add_item("potion_small", 5)
		InventoryManager.add_item("leather_armor", 1)
		print("[Field] 테스트 아이템 추가됨")
	
	hud.add_system_log("필드에 입장했다.")


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyLeader.tscn")
	party_follower_scene = load("res://scenes/field/PartyFollower.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")


func _setup_hud() -> void:
	# 기존 HUD 제거 (씬에 미리 있으면)
	var old_hud = get_node_or_null("CanvasLayer")
	if old_hud:
		old_hud.queue_free()
	
	hud = hud_scene.instantiate() as FieldHUD
	add_child(hud)
	hud.menu_pressed.connect(_on_menu_pressed)


func _spawn_party() -> void:
	var start_pos: Vector2 = Vector2(100, 100)
	if spawn_point:
		start_pos = spawn_point.global_position
	
	# PartyManager.get_party() 사용
	var party_members: Array = []
	if PartyManager:
		party_members = PartyManager.get_party()
	
	# 리더 생성
	party_leader = party_leader_scene.instantiate() as PartyLeader
	party_leader.global_position = start_pos
	add_child(party_leader)
	
	if party_members.size() > 0:
		party_leader.setup_hero(party_members[0])
	
	print("[Field] 리더 생성 at ", start_pos)
	
	# 팔로워 생성
	if party_members.size() > 1:
		await get_tree().create_timer(0.1).timeout
		
		for i in range(1, party_members.size()):
			var follower: PartyFollower = party_follower_scene.instantiate() as PartyFollower
			add_child(follower)
			follower.setup(party_leader, i, party_members[i])
			party_followers.append(follower)
		
		print("[Field] 팔로워: ", party_followers.size())


func _spawn_field_enemies() -> void:
	var spawn_tiles: Array = _collect_spawnable_tiles()
	var spawn_data: Array = FieldManager.spawn_field_enemies(spawn_tiles)
	
	for data in spawn_data:
		var data_dict: Dictionary = data as Dictionary
		var enemy: FieldEnemy = field_enemy_scene.instantiate() as FieldEnemy
		add_child(enemy)
		enemy.setup(
			str(data_dict.get("enemy_id", "slime")),
			str(data_dict.get("tile_type", "grass")),
			data_dict.get("position", Vector2.ZERO) as Vector2
		)
		enemy.player_contacted.connect(_on_field_enemy_contacted)
		field_enemies.append(enemy)
	
	print("[Field] 적 스폰: ", field_enemies.size())


func _collect_spawnable_tiles() -> Array:
	var result: Array = []
	
	if tilemap:
		var used_cells: Array = tilemap.get_used_cells()
		for cell in used_cells:
			var cell_vec: Vector2i = cell as Vector2i
			var source_id: int = tilemap.get_cell_source_id(cell_vec)
			var tile_type: String = str(tile_type_map.get(source_id, "grass"))
			
			if FieldManager.can_spawn_on_tile(tile_type):
				result.append({
					"position": tilemap.map_to_local(cell_vec),
					"tile_type": tile_type
				})
	
	if result.is_empty():
		for i in range(8):
			result.append({
				"position": Vector2(150 + (i % 4) * 100, 100 + (i / 4) * 80),
				"tile_type": "grass"
			})
	
	return result


func _setup_exit() -> void:
	if exit_area:
		exit_area.body_entered.connect(_on_exit_body_entered)


func _update_hud() -> void:
	var hud_label: Label = get_node_or_null("CanvasLayer/HUD/StageLabel") as Label
	if hud_label:
		hud_label.text = FieldManager.get_display_name()
	
	var enemy_label: Label = get_node_or_null("CanvasLayer/HUD/EnemyCount") as Label
	if enemy_label:
		enemy_label.text = "적: %d" % field_enemies.size()
	
	var gold_label: Label = get_node_or_null("CanvasLayer/HUD/GoldLabel") as Label
	if gold_label and GameManager:
		gold_label.text = "Gold: %d" % GameManager.gold


func _on_field_enemy_contacted(field_enemy: FieldEnemy) -> void:
	print("[Field] 적 접촉: ", field_enemy.enemy_id)
	
	var enemy_data: Dictionary = DataManager.get_enemy(field_enemy.enemy_id)
	var enemy_name: String = str(enemy_data.get("name", field_enemy.enemy_id))
	
	var battle_enemies: Array = FieldManager.generate_battle_enemies(
		field_enemy.enemy_id,
		field_enemy.tile_type
	)
	
	print("[Field] 전투 구성: ", battle_enemies)
	
	# 로그 추가
	if hud:
		var log_msg: String = "%s이(가) 나타났다!" % enemy_name
		if battle_enemies.size() > 1:
			log_msg = "%s 외 %d마리가 나타났다!" % [enemy_name, battle_enemies.size() - 1]
		hud.add_battle_log(log_msg)
	
	field_enemies.erase(field_enemy)
	field_enemy.despawn()
	
	if BattleManager:
		# self를 전달하여 전투창이 이 씬에 생성되도록 함
		var battle_id: int = BattleManager.start_battle(battle_enemies, self)
		print("[Field] 전투 ID: ", battle_id)
	
	battle_triggered.emit(battle_enemies)


func _on_exit_body_entered(body: Node2D) -> void:
	if not body.is_in_group("party_leader"):
		return
	
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		if hud:
			hud.add_system_log("전투 중에는 출구를 사용할 수 없다!")
		return
	
	if FieldManager.is_boss_field() and field_enemies.size() > 0:
		if hud:
			hud.add_system_log("보스를 처치해야 진행할 수 있다!")
		return
	
	var next: String = FieldManager.get_next_destination()
	print("[Field] 출구! 다음: ", next)
	
	if hud:
		hud.add_system_log("다음 구역으로 이동한다...")
	
	exit_reached.emit(next)
	
	if GameManager:
		GameManager.go_to_next_from_field()


func _on_menu_pressed() -> void:
	# TODO: 메뉴 열기
	if hud:
		hud.add_system_log("메뉴 (미구현)")


func get_remaining_enemies() -> int:
	return field_enemies.size()


func get_party_leader() -> PartyLeader:
	return party_leader


func get_hud() -> FieldHUD:
	return hud
