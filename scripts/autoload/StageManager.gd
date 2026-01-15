# scripts/autoload/StageManager.gd
# 스테이지 & 던전 진행 관리
extends Node

signal stage_changed(stage: int)
signal boss_spawned(boss_id: String)
signal stage_cleared
signal dungeon_cleared
signal game_over

# 현재 상태
var current_stage: int = 1
var current_dungeon: String = "dungeon_001"
var kills_this_stage: int = 0
var kills_for_boss: int = 20  # 20킬마다 보스

# 스테이지 설정
var stage_enemy_multiplier: float = 1.0  # 적 스탯 배율
var stage_spawn_rate: float = 1.0  # 스폰 속도 배율
var max_stage: int = 10  # 최종 스테이지

# 보스 상태
var boss_active: bool = false
var boss_defeated: bool = false

func _ready():
	print("[StageManager] Ready")
	
	# 시그널 연결
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.battle_victory.connect(_on_battle_victory)

# ========================================
# 적 처치 & 스테이지 진행
# ========================================

func _on_enemy_died(enemy_id: String):
	kills_this_stage += 1
	
	print("[Stage %d] Kills: %d/%d" % [current_stage, kills_this_stage, kills_for_boss])
	
	# 보스 소환 체크
	if kills_this_stage >= kills_for_boss and not boss_active:
		spawn_boss()

func _on_battle_victory():
	# 보스 처치 체크
	if boss_active:
		boss_defeated = true
		boss_active = false
		advance_stage()

# ========================================
# 보스 소환
# ========================================

func spawn_boss():
	boss_active = true
	boss_defeated = false
	
	print("=== BOSS INCOMING! ===")
	
	# 보스 ID 결정
	var boss_id = get_stage_boss()
	
	boss_spawned.emit(boss_id)
	
	# 일반 적 스폰 중지
	var spawner = get_tree().root.find_child("EnemySpawner", true, false)
	if spawner:
		spawner.stop_spawning()

func get_stage_boss() -> String:
	# 스테이지별 보스
	match current_stage:
		1, 2:
			return "boss_001"  # 자이언트 슬라임
		3, 4:
			return "boss_001"
		5:
			return "boss_002"  # 챕터 1 최종 보스
		_:
			return "boss_001"

# ========================================
# 스테이지 진행
# ========================================

func advance_stage():
	current_stage += 1
	kills_this_stage = 0
	boss_active = false
	
	print("=== STAGE %d ===" % current_stage)
	
	# 난이도 증가
	stage_enemy_multiplier = 1.0 + (current_stage - 1) * 0.2  # 스테이지당 20% 증가
	stage_spawn_rate = 1.0 + (current_stage - 1) * 0.1  # 스폰 속도 10% 증가
	
	# 보스 킬 요구량 증가
	kills_for_boss = 20 + (current_stage - 1) * 5
	
	stage_changed.emit(current_stage)
	stage_cleared.emit()
	
	# 최종 스테이지 클리어 체크
	if current_stage > max_stage:
		dungeon_clear()
		return
	
	# 스포너 재시작
	var spawner = get_tree().root.find_child("EnemySpawner", true, false)
	if spawner:
		spawner.spawn_interval = 3.0 / stage_spawn_rate
		spawner.start_spawning()

func dungeon_clear():
	print("=== DUNGEON CLEARED! ===")
	dungeon_cleared.emit()

# ========================================
# 게임 오버
# ========================================

func check_game_over():
	var alive_count = 0
	for hero in GameManager.party:
		if hero.current_hp > 0:
			alive_count += 1
	
	if alive_count == 0:
		trigger_game_over()

func trigger_game_over():
	print("=== GAME OVER ===")
	game_over.emit()

# ========================================
# 스테이지 정보
# ========================================

func get_stage_info() -> Dictionary:
	return {
		"stage": current_stage,
		"kills": kills_this_stage,
		"kills_needed": kills_for_boss,
		"boss_active": boss_active,
		"enemy_multiplier": stage_enemy_multiplier
	}

func get_enemy_stats_multiplier() -> float:
	return stage_enemy_multiplier

# ========================================
# 리셋
# ========================================

func reset():
	current_stage = 1
	kills_this_stage = 0
	boss_active = false
	boss_defeated = false
	stage_enemy_multiplier = 1.0
	stage_spawn_rate = 1.0
