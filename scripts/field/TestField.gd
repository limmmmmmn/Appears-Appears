# scripts/field/TestField.gd
extends Node2D

@onready var enemy_spawner = $EnemySpawner

var hud: CanvasLayer = null
var boss_scene: PackedScene = null

func _ready():
	print("========================================")
	print("  HYPER QUEST - Stage %d" % StageManager.current_stage)
	print("========================================")
	
	# 보스 씬 로드
	boss_scene = preload("res://scenes/enemies/Boss.tscn")
	
	await get_tree().create_timer(0.5).timeout
	
	setup_hud()
	setup_spawner()
	connect_signals()

func setup_hud():
	# HUD 생성
	hud = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child(hud)
	print("[Field] HUD created")

func setup_spawner():
	if not enemy_spawner:
		print("WARNING: EnemySpawner not found!")
		return
	
	enemy_spawner.spawn_interval = 3.0
	enemy_spawner.max_enemies = 15
	
	# ⭐ 수정: clear 후 append 방식으로 변경
	enemy_spawner.enemy_pool.clear()
	enemy_spawner.enemy_pool.append("enemy_001")
	enemy_spawner.enemy_pool.append("enemy_002")
	enemy_spawner.enemy_pool.append("enemy_003")
	
	enemy_spawner.start_spawning()
	
	print("[Field] Spawner ready")

func connect_signals():
	# 스테이지 매니저 시그널
	StageManager.boss_spawned.connect(_on_boss_spawned)
	StageManager.stage_cleared.connect(_on_stage_cleared)
	StageManager.game_over.connect(_on_game_over)
	StageManager.dungeon_cleared.connect(_on_dungeon_cleared)
	
	# 전투 시그널
	EventBus.battle_defeat.connect(_on_battle_defeat)

# ========================================
# 보스 스폰
# ========================================

func _on_boss_spawned(boss_id: String):
	print("\n⚠️ BOSS SPAWNING! ⚠️\n")
	
	# 일반 적 제거
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.queue_free()
	
	# 보스 데이터
	var boss_data = DataManager.get_enemy(boss_id)
	if boss_data.is_empty():
		boss_data = {
			"id": boss_id,
			"name": "Giant Slime",
			"base_stats": {
				"hp": 500,
				"attack": 25,
				"defense": 10,
				"attack_speed": 0.6
			},
			"drop_table": {
				"gold_min": 100,
				"gold_max": 200,
				"item_drop_rate": 1.0,
				"item_pool": ["item_005", "item_010"]
			}
		}
	
	# 보스 생성
	var boss = boss_scene.instantiate()
	
	# 플레이어 위치 기반 스폰
	var player = get_tree().root.find_child("Player", true, false)
	if player:
		var spawn_offset = Vector2(300, 0).rotated(randf() * TAU)
		boss.global_position = player.global_position + spawn_offset
	else:
		boss.global_position = Vector2(200, 0)
	
	add_child(boss)
	boss.add_to_group("enemies")
	boss.init_boss(boss_data)
	
	print("[Field] Boss spawned!")

# ========================================
# 스테이지 클리어
# ========================================

func _on_stage_cleared():
	print("\n=== STAGE %d CLEARED! ===" % (StageManager.current_stage - 1))
	
	# 파티 약간 회복
	for hero in GameManager.party:
		hero.current_hp = min(hero.current_hp + 50, hero.base_stats.hp)
	
	# 스포너 설정 업데이트
	if enemy_spawner:
		enemy_spawner.spawn_interval = 3.0 / StageManager.stage_spawn_rate
		enemy_spawner.start_spawning()

# ========================================
# 던전 클리어
# ========================================

func _on_dungeon_cleared():
	print("\n🎉 DUNGEON CLEARED! 🎉\n")
	show_victory_screen()

func show_victory_screen():
	var victory_ui = preload("res://scenes/ui/GameOverUI.tscn").instantiate()
	
	var canvas = CanvasLayer.new()
	canvas.name = "GameOverCanvas"
	canvas.layer = 200
	canvas.add_child(victory_ui)
	get_tree().root.add_child(canvas)
	
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	victory_ui.position = Vector2(
		viewport_size.x / 2 - 200,
		viewport_size.y / 2 - 200
	)
	
	victory_ui.show_victory()

# ========================================
# 게임 오버
# ========================================

func _on_game_over():
	print("\n💀 GAME OVER 💀\n")
	show_game_over_screen()

func _on_battle_defeat():
	# 모든 영웅 죽었는지 체크
	var alive = 0
	for hero in GameManager.party:
		if hero.current_hp > 0:
			alive += 1
	
	if alive == 0:
		StageManager.trigger_game_over()

func show_game_over_screen():
	var gameover_ui = preload("res://scenes/ui/GameOverUI.tscn").instantiate()
	
	var canvas = CanvasLayer.new()
	canvas.name = "GameOverCanvas"
	canvas.layer = 200
	canvas.add_child(gameover_ui)
	get_tree().root.add_child(canvas)
	
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	gameover_ui.position = Vector2(
		viewport_size.x / 2 - 200,
		viewport_size.y / 2 - 200
	)
	
	gameover_ui.show_game_over()

# ========================================
# 세이브 (P 키)
# ========================================

func _input(event):
	# ⭐ 직접 키코드 체크 (Input Map 필요 없음)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			print("[Field] Saving game...")
			SaveManager.save_game()
