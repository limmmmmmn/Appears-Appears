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
var game_over_ui: GameOverUI
var loot_select_ui: LootSelectUI  # 3지선다 UI

var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene
var hud_scene: PackedScene

#=============================================================================
# 🎮 에너미 스포너 설정 (여기서 조절하세요!)
#=============================================================================
var respawn_timer: Timer

# 리스폰 간격 (초) - 낮출수록 더 자주 스폰됨
# 예: 1.0 = 1초마다, 5.0 = 5초마다
const RESPAWN_INTERVAL: float = 3.0

# 필드에 존재할 수 있는 최대 적 수
# 예: 10 = 최대 10마리, 30 = 최대 30마리
const MAX_ENEMIES: int = 15

# 한 번에 스폰되는 적 수 (최소, 최대)
# _on_respawn_timer() 함수에서 randi_range(1, 2)로 설정됨
# 더 많이 스폰하려면 randi_range(2, 4) 등으로 변경

# 플레이어로부터 최소 스폰 거리 (픽셀)
# 너무 가까이 스폰되지 않도록 함
const MIN_SPAWN_DISTANCE: float = 150.0

# 엘리트 스폰 확률 (0.0 ~ 1.0)
# 0.15 = 15% 확률로 엘리트 스폰
const ELITE_SPAWN_CHANCE: float = 0.15

# 초기 스폰 수는 stages.json의 enemy_count에서 설정
# "enemy_count": { "min": 8, "max": 12 }
#=============================================================================

var spawnable_tiles: Array = []

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
	_setup_game_over_ui()
	_spawn_party()
	
	# 스폰 가능한 타일 캐싱
	spawnable_tiles = _collect_spawnable_tiles()
	
	_spawn_field_enemies()
	_setup_exit()
	_setup_respawn_timer()
	
	# 파티 전멸 시그널 연결
	if PartyManager:
		if not PartyManager.party_wiped.is_connected(_on_party_wiped):
			PartyManager.party_wiped.connect(_on_party_wiped)
			print("[Field] PartyManager.party_wiped 연결됨")
	
	# GameManager 게임오버 시그널도 연결
	if GameManager:
		if not GameManager.game_over.is_connected(_on_party_wiped):
			GameManager.game_over.connect(_on_party_wiped)
			print("[Field] GameManager.game_over 연결됨")
	
	# 엘리트 전투 승리 시그널 연결
	if BattleManager:
		if not BattleManager.elite_victory.is_connected(_on_elite_victory):
			BattleManager.elite_victory.connect(_on_elite_victory)
			print("[Field] BattleManager.elite_victory 연결됨")
	
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


func _setup_game_over_ui() -> void:
	game_over_ui = GameOverUI.new()
	add_child(game_over_ui)
	game_over_ui.restart_pressed.connect(_on_restart_game)
	game_over_ui.quit_pressed.connect(_on_quit_game)
	
	# 3지선다 루트 UI
	loot_select_ui = LootSelectUI.new()
	add_child(loot_select_ui)
	loot_select_ui.item_selected.connect(_on_loot_item_selected)


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
	var spawn_data: Array = FieldManager.spawn_field_enemies(spawnable_tiles)
	
	for data in spawn_data:
		_spawn_single_enemy(data)
	
	print("[Field] 적 스폰: ", field_enemies.size())


func _spawn_single_enemy(data: Dictionary, force_elite: bool = false) -> void:
	var enemy: FieldEnemy = field_enemy_scene.instantiate() as FieldEnemy
	add_child(enemy)
	
	# 엘리트 여부 결정
	var is_elite: bool = force_elite or (randf() < ELITE_SPAWN_CHANCE)
	
	enemy.setup(
		str(data.get("enemy_id", "slime")),
		str(data.get("tile_type", "grass")),
		data.get("position", Vector2.ZERO) as Vector2,
		is_elite
	)
	enemy.player_contacted.connect(_on_field_enemy_contacted)
	field_enemies.append(enemy)
	
	if is_elite:
		print("[Field] 엘리트 스폰: ", data.get("enemy_id", "slime"))


func _setup_respawn_timer() -> void:
	respawn_timer = Timer.new()
	respawn_timer.wait_time = RESPAWN_INTERVAL
	respawn_timer.one_shot = false
	respawn_timer.timeout.connect(_on_respawn_timer)
	add_child(respawn_timer)
	respawn_timer.start()
	print("[Field] 리스폰 타이머 시작")


func _on_respawn_timer() -> void:
	# 최대 적 수 미만이면 리스폰
	if field_enemies.size() >= MAX_ENEMIES:
		return
	
	# 플레이어 위치에서 멀리 스폰
	var safe_tiles: Array = _get_safe_spawn_tiles()
	if safe_tiles.is_empty():
		return
	
	#=============================================================================
	# 🎮 한 번에 스폰되는 적 수 조절
	# randi_range(최소, 최대) - 예: (1, 2) = 1~2마리, (3, 5) = 3~5마리
	#=============================================================================
	var spawn_count: int = randi_range(1, 2)
	
	for i in range(spawn_count):
		if field_enemies.size() >= MAX_ENEMIES:
			break
		if safe_tiles.is_empty():
			break
		
		var tile_idx: int = randi() % safe_tiles.size()
		var tile_data: Dictionary = safe_tiles[tile_idx]
		safe_tiles.remove_at(tile_idx)
		
		var tile_type: String = str(tile_data.get("tile_type", "grass"))
		var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
		
		var spawn_data: Dictionary = {
			"enemy_id": enemy_id,
			"position": tile_data.get("position", Vector2.ZERO),
			"tile_type": tile_type
		}
		_spawn_single_enemy(spawn_data)
	
	print("[Field] 리스폰! 현재 적: ", field_enemies.size())


func _get_safe_spawn_tiles() -> Array:
	## 플레이어에서 일정 거리 이상 떨어진 타일만 반환
	var safe_tiles: Array = []
	var player_pos: Vector2 = party_leader.global_position if party_leader else Vector2.ZERO
	
	for tile_data in spawnable_tiles:
		var tile_dict: Dictionary = tile_data as Dictionary
		var tile_pos: Vector2 = tile_dict.get("position", Vector2.ZERO) as Vector2
		
		if tile_pos.distance_to(player_pos) > MIN_SPAWN_DISTANCE:
			safe_tiles.append(tile_dict)
	
	return safe_tiles


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
	print("[Field] 적 접촉: ", field_enemy.enemy_id, " (엘리트:", field_enemy.is_elite, ")")
	
	var enemy_data: Dictionary = DataManager.get_enemy(field_enemy.enemy_id)
	var enemy_name: String = str(enemy_data.get("name", field_enemy.enemy_id))
	
	var battle_enemies: Array = FieldManager.generate_battle_enemies(
		field_enemy.enemy_id,
		field_enemy.tile_type
	)
	
	print("[Field] 전투 구성: ", battle_enemies)
	
	# 로그 추가
	if hud:
		var log_msg: String = ""
		if field_enemy.is_elite:
			log_msg = "⭐ 엘리트 %s이(가) 나타났다!" % enemy_name
		elif battle_enemies.size() > 1:
			log_msg = "%s 외 %d마리가 나타났다!" % [enemy_name, battle_enemies.size() - 1]
		else:
			log_msg = "%s이(가) 나타났다!" % enemy_name
		hud.add_battle_log(log_msg)
	
	field_enemies.erase(field_enemy)
	var was_elite: bool = field_enemy.is_elite
	field_enemy.despawn()
	
	if BattleManager:
		# 엘리트 정보를 BattleManager에 전달
		var battle_id: int = BattleManager.start_battle(battle_enemies, self, was_elite)
		print("[Field] 전투 ID: ", battle_id, " 엘리트전투:", was_elite)
	
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


#=============================================================================
# 🎮 게임오버 & 다시하기
#=============================================================================
func _on_party_wiped() -> void:
	print("[Field] ====== 파티 전멸! 게임오버 ======")
	
	# 리스폰 타이머 정지
	if respawn_timer:
		respawn_timer.stop()
		print("[Field] 리스폰 타이머 정지")
	
	# 모든 전투창 닫기
	if BattleManager:
		BattleManager.close_all_battles()
		print("[Field] 모든 전투창 닫음")
	
	# 게임오버 UI 표시
	if game_over_ui:
		print("[Field] 게임오버 UI 표시")
		game_over_ui.show_game_over("파티가 전멸했습니다...")
	else:
		print("[Field] ERROR: game_over_ui가 없음!")


func _on_restart_game() -> void:
	print("[Field] 게임 재시작!")
	
	# 파티 완전 회복
	if PartyManager:
		PartyManager.full_restore_party()
	
	# 현재 씬 다시 로드
	get_tree().reload_current_scene()


func _on_quit_game() -> void:
	print("[Field] 게임 종료")
	
	# 메인 메뉴로 이동 (또는 게임 종료)
	# get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")
	get_tree().quit()


func _on_loot_item_selected(item_id: String) -> void:
	print("[Field] 루트 선택: ", item_id)
	
	# 아이템 지급
	InventoryManager.add_item(item_id)
	
	# 로그 표시
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		item_data = DataManager.get_item(item_id)
	var item_name: String = str(item_data.get("name", item_id))
	
	if hud:
		hud.add_log("🎁 %s 획득!" % item_name, Color.GOLD)


func show_elite_loot() -> void:
	## 엘리트 전투 승리 시 3지선다 표시
	var loot_pool: Array[String] = _generate_elite_loot_pool()
	if loot_pool.size() >= 3 and loot_select_ui:
		loot_select_ui.show_loot_selection(loot_pool)


func _on_elite_victory(_battle_id: int) -> void:
	print("[Field] 엘리트 전투 승리! 3지선다 표시")
	show_elite_loot()


func _generate_elite_loot_pool() -> Array[String]:
	## 매직 이상 등급 아이템 3개 생성
	var pool: Array[String] = []
	var magic_items: Array[String] = [
		"sword_magic", "axe_magic", "staff_magic",
		"leather_armor_magic", "heavy_armor_magic", "robe_magic",
		"shield_magic", "iron_helm_magic"
	]
	var legendary_items: Array[String] = [
		"excalibur", "crown_legendary"
	]
	
	# 셔플
	magic_items.shuffle()
	legendary_items.shuffle()
	
	# 20% 확률로 레전더리 포함
	if randf() < 0.2 and not legendary_items.is_empty():
		pool.append(legendary_items[0])
	
	# 나머지는 매직 아이템으로 채움
	for item_id in magic_items:
		if pool.size() >= 3:
			break
		if not pool.has(item_id):
			pool.append(item_id)
	
	return pool
