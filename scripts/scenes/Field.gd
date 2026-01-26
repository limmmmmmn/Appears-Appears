extends Node2D
## 필드 씬 컨트롤러 (리팩토링 버전)

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal town_entered
signal field_cleared

@export var spawn_point: Marker2D
@export var exit_area: Area2D
@export var town_area: Area2D
@export var tilemap: TileMapLayer

var party_leader: PartyLeader
var party_followers: Array[PartyFollower] = []
var field_enemies: Array[FieldEnemy] = []
var hud: FieldHUD
var game_over_ui: GameOverUI
var loot_select_ui: LootSelectUI

# 씬 리소스
var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene
var hud_scene: PackedScene

# 분리된 시스템들
var spawner: EnemySpawner
var town_barrier: TownBarrier
var pause_menu: PauseMenu


func _ready() -> void:
	_load_scenes()
	_find_tilemap()
	_setup_systems()
	_spawn_party()
	_spawn_field_enemies()
	_setup_exit()
	_connect_signals()
	
	if hud:
		hud.add_system_log("필드에 입장했다.")


func _process(_delta: float) -> void:
	# 이동 기반 적 스폰 체크
	if spawner and not FieldManager.is_boss_field():
		spawner.update_movement_spawn(field_enemies)
		
		# 새로 스폰된 적에게 시그널 연결
		for enemy in field_enemies:
			if not enemy.player_contacted.is_connected(_on_field_enemy_contacted):
				enemy.player_contacted.connect(_on_field_enemy_contacted)


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyLeader.tscn")
	party_follower_scene = load("res://scenes/field/PartyFollower.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")


func _find_tilemap() -> void:
	if tilemap:
		return
	
	# 직접 자식에서 찾기
	for child in get_children():
		if child is TileMapLayer:
			tilemap = child
			return
	
	# 재귀 탐색
	tilemap = _find_node_recursive(self, TileMapLayer) as TileMapLayer


func _find_node_recursive(node: Node, type) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found = _find_node_recursive(child, type)
		if found:
			return found
	return null


func _setup_systems() -> void:
	# HUD
	var old_hud = get_node_or_null("CanvasLayer")
	if old_hud:
		old_hud.queue_free()
	
	hud = hud_scene.instantiate() as FieldHUD
	add_child(hud)
	hud.menu_pressed.connect(_on_menu_pressed)
	
	# 게임오버 UI
	game_over_ui = GameOverUI.new()
	add_child(game_over_ui)
	game_over_ui.restart_pressed.connect(_on_restart_game)
	game_over_ui.quit_pressed.connect(_on_quit_game)
	
	# 루트 선택 UI
	loot_select_ui = LootSelectUI.new()
	add_child(loot_select_ui)
	loot_select_ui.item_selected.connect(_on_loot_item_selected)
	
	# 스포너
	spawner = EnemySpawner.new()
	spawner.setup(self, tilemap)
	
	# 일시정지 메뉴
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_pressed.connect(_on_resume_pressed)
	pause_menu.title_pressed.connect(_on_title_pressed)
	pause_menu.quit_pressed.connect(_on_quit_game)


func _connect_signals() -> void:
	if PartyManager and not PartyManager.party_wiped.is_connected(_on_party_wiped):
		PartyManager.party_wiped.connect(_on_party_wiped)
	
	if GameManager and not GameManager.game_over.is_connected(_on_party_wiped):
		GameManager.game_over.connect(_on_party_wiped)
	
	if BattleManager:
		if not BattleManager.elite_victory.is_connected(_on_elite_victory):
			BattleManager.elite_victory.connect(_on_elite_victory)
		if not BattleManager.boss_victory.is_connected(_on_boss_victory):
			BattleManager.boss_victory.connect(_on_boss_victory)


#=============================================================================
# 파티 스폰
#=============================================================================
func _spawn_party() -> void:
	var start_pos: Vector2 = _get_start_position()
	var party_members: Array = PartyManager.get_party() if PartyManager else []
	
	# 리더 생성
	party_leader = party_leader_scene.instantiate() as PartyLeader
	party_leader.global_position = start_pos
	add_child(party_leader)
	
	if party_members.size() > 0:
		party_leader.setup_hero(party_members[0])
	
	# 팔로워 생성
	if party_members.size() > 1:
		await get_tree().create_timer(0.1).timeout
		
		for i in range(1, party_members.size()):
			var follower: PartyFollower = party_follower_scene.instantiate()
			add_child(follower)
			follower.setup(party_leader, i, party_members[i])
			party_followers.append(follower)
	
	SaveManager.last_field_position = Vector2.ZERO


func _get_start_position() -> Vector2:
	var saved_pos: Vector2 = SaveManager.get_saved_field_position()
	if saved_pos != Vector2.ZERO:
		return saved_pos
	if spawn_point:
		return spawn_point.global_position
	return Vector2(100, 100)


#=============================================================================
# 적 스폰
#=============================================================================
func _spawn_field_enemies() -> void:
	spawner.spawn_initial_enemies(field_enemies)
	
	# 보스 로그
	if FieldManager.is_boss_field() and not field_enemies.is_empty():
		var boss = field_enemies[0]
		boss.player_contacted.connect(_on_field_enemy_contacted)
		var boss_data: Dictionary = DataManager.get_enemy(boss.enemy_id)
		if hud:
			hud.add_system_log("⚠ %s이(가) 앞을 막아서고 있다!" % boss_data.get("name", boss.enemy_id))
	else:
		# 일반 적 시그널 연결
		for enemy in field_enemies:
			enemy.player_contacted.connect(_on_field_enemy_contacted)


#=============================================================================
# 출구/마을 설정
#=============================================================================
func _setup_exit() -> void:
	if not exit_area:
		exit_area = get_node_or_null("ExitArea")
	if exit_area and not exit_area.body_entered.is_connected(_on_exit_body_entered):
		exit_area.body_entered.connect(_on_exit_body_entered)
	
	if not town_area:
		town_area = get_node_or_null("TownArea")
	if town_area:
		if not town_area.body_entered.is_connected(_on_town_body_entered):
			town_area.body_entered.connect(_on_town_body_entered)
		# 결계 시스템
		town_barrier = TownBarrier.new()
		town_barrier.setup(self, town_area)
	
	# 위치 자동 저장 타이머
	var save_timer := Timer.new()
	save_timer.wait_time = 3.0
	save_timer.one_shot = false
	save_timer.timeout.connect(_save_field_position)
	add_child(save_timer)
	save_timer.start()


func _save_field_position() -> void:
	if party_leader and SaveManager:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
		SaveManager.auto_save("필드 위치 저장")


#=============================================================================
# 이벤트 핸들러
#=============================================================================
func _on_field_enemy_contacted(field_enemy: FieldEnemy) -> void:
	var enemy_data: Dictionary = DataManager.get_enemy(field_enemy.enemy_id)
	var enemy_name: String = str(enemy_data.get("name", field_enemy.enemy_id))
	
	var battle_enemies: Array = FieldManager.generate_battle_enemies(
		field_enemy.enemy_id, field_enemy.tile_type
	)
	
	# 충돌 위치 계산 (적과 플레이어 사이)
	var collision_pos: Vector2 = field_enemy.global_position
	if party_leader:
		collision_pos = (field_enemy.global_position + party_leader.global_position) / 2
	
	# 로그
	if hud:
		var msg: String
		if field_enemy.is_elite:
			msg = "⭐ 엘리트 %s이(가) 나타났다!" % enemy_name
		elif battle_enemies.size() > 1:
			msg = "%s 외 %d마리가 나타났다!" % [enemy_name, battle_enemies.size() - 1]
		else:
			msg = "%s이(가) 나타났다!" % enemy_name
		hud.add_battle_log(msg)
	
	var was_elite: bool = field_enemy.is_elite
	field_enemies.erase(field_enemy)
	field_enemy.despawn()
	
	if BattleManager:
		BattleManager.start_battle(battle_enemies, self, was_elite, collision_pos)
	
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
	if hud:
		hud.add_system_log("다음 구역으로 이동한다...")
	
	exit_reached.emit(next)
	if GameManager:
		GameManager.go_to_next_from_field()


func _on_town_body_entered(body: Node2D) -> void:
	if not body.is_in_group("party_leader"):
		return
	
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return
	
	if hud:
		hud.add_system_log("마을로 향한다...")
	
	town_entered.emit()
	GameManager.advance_to_next_field()
	if GameManager:
		GameManager.go_to_town()


#=============================================================================
# 메뉴 & 게임오버
#=============================================================================
func _on_menu_pressed() -> void:
	pause_menu.show_menu()


func _on_resume_pressed() -> void:
	# 메뉴에서 돌아올 때 특별한 처리가 필요하면 여기에
	pass


func _on_title_pressed() -> void:
	if party_leader:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_party_wiped() -> void:
	spawner.stop_respawn()
	
	if BattleManager:
		BattleManager.close_all_battles()
	
	SaveManager.delete_save()
	
	if game_over_ui:
		game_over_ui.show_game_over("파티가 전멸했습니다...")


func _on_restart_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_game() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if pause_menu.is_visible_menu():
			pause_menu.hide_menu()
		else:
			pause_menu.show_menu()


#=============================================================================
# 루트 시스템
#=============================================================================
func _on_loot_item_selected(item_id: String) -> void:
	InventoryManager.add_item(item_id)
	
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		item_data = DataManager.get_item(item_id)
	
	if hud:
		hud.add_log("🎁 %s 획득!" % item_data.get("name", item_id), Color.GOLD)


func _on_elite_victory(_battle_id: int) -> void:
	var loot: Array[String] = LootGenerator.generate_elite_loot()
	if loot.size() >= 3 and loot_select_ui:
		loot_select_ui.show_loot_selection(loot)


func _on_boss_victory(_battle_id: int) -> void:
	if hud:
		hud.add_system_log("🎉 보스를 처치했다!")
		hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")
	
	spawner.stop_respawn()
	
	var loot: Array[String] = LootGenerator.generate_boss_loot()
	if loot.size() >= 3 and loot_select_ui:
		loot_select_ui.show_loot_selection(loot)


#=============================================================================
# 유틸리티
#=============================================================================
func get_remaining_enemies() -> int:
	return field_enemies.size()


func get_party_leader() -> PartyLeader:
	return party_leader


func get_hud() -> FieldHUD:
	return hud
