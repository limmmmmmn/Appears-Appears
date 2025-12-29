# res://Scenes/Battle/BattleScene.gd (최종 리팩토링 버전)
extends Node

@onready var turn_system = $TurnSystem
@onready var stage_system = $BattleStageSystem # [New] 무대 관리자
@onready var window_positioner = $WindowPositioner

var allies: Array[BattleUnit] = []
var enemies: Array[BattleUnit] = []
var all_units: Array[BattleUnit] = []

func _ready():
	# 무대 관리자에게 캔버스(그림 그릴 곳) 알려주기
	stage_system.container = $UI/BattleContainer
	
	SignalBus.unit_damaged.connect(_on_unit_damaged)

func start_battle(player_data: JobData, base_enemy_data: EnemyData):
	# 1. 데이터 생성 (로직)
	var player_unit = BattleUnit.new(player_data, false)
	allies = [player_unit]
	all_units = [player_unit]
	
	var enemy_count = randi_range(1, 3)
	for i in range(enemy_count):
		var enemy = BattleUnit.new(base_enemy_data, true)
		enemy.unit_name = base_enemy_data.enemy_name + " " + String.chr(65 + i)
		enemies.append(enemy)
		all_units.append(enemy)

	# 2. [New] 무대 세팅은 '관리자'에게 위임! (좌표 계산 코드 삭제됨)
	stage_system.setup_enemies(enemies)
	
	# 3. 위치 및 턴 시작
	if window_positioner: window_positioner.apply_random_position()
	turn_system.turn_ready.connect(_on_turn_ready)
	turn_system.initialize(all_units)

# ------------------------------------------------------------------
# 전투 흐름 (Flow)
func _on_turn_ready(unit: BattleUnit):
	await get_tree().create_timer(0.3).timeout
	
	# 타겟 선정
	var targets = enemies if not unit.is_enemy else allies
	targets = targets.filter(func(u): return u.current_hp > 0)
	if targets.is_empty(): return

	_execute_attack(unit, targets.pick_random())

func _execute_attack(attacker: BattleUnit, target: BattleUnit):
	# [New] 애니메이션도 관리자에게 "틀어줘!" 한마디면 끝
	stage_system.play_attack(attacker)
	
	await get_tree().create_timer(0.3).timeout
	BattleManager.process_attack(attacker, target)
	
	# 종료 체크 로직 (여긴 로직이라 남겨둠)
	await get_tree().create_timer(0.3).timeout
	if allies.all(func(u): return u.current_hp <= 0): _finish(false)
	elif enemies.all(func(u): return u.current_hp <= 0): _finish(true)

func _on_unit_damaged(target, amount, is_crit):
	# [New] UI 업데이트도 관리자에게 위임
	stage_system.play_damage(target, amount, target.current_hp <= 0)

func _finish(is_victory):
	turn_system.stop()
	print("승리!" if is_victory else "패배...")
	await get_tree().create_timer(1.0).timeout
	queue_free()
