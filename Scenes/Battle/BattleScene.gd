extends CanvasLayer
class_name BattleScene

@export var enemy_slot_scene: PackedScene 

@onready var battle_spawner = $BattleSpawner 
@onready var turn_manager = $TurnManager
@onready var background_panel = $BackgroundPanel
@onready var enemy_container = $BackgroundPanel/EnemyContainer

var active_enemies: Array = [] 
var battle_ended: bool = false

# 보상 계산용 변수
var total_gold_reward: int = 0
var total_exp_reward: int = 0

func _ready():
	enemy_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	if enemy_container is BoxContainer:
		enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	battle_spawner.setup(enemy_container, background_panel, enemy_slot_scene)
	turn_manager.turn_ready.connect(execute_turn)

func start_battle(main_enemy: EnemyData, spawn_table: Array[SpawnEntry]):
	active_enemies = battle_spawner.spawn_enemies(main_enemy, spawn_table)
	
	var all_units = []
	for m in PartyManager.party_members: all_units.append(m)
	all_units.append_array(active_enemies)
	
	turn_manager.initialize(all_units)

func _process(delta):
	if battle_ended: return
	
	var all_units = []
	for m in PartyManager.party_members: all_units.append(m)
	all_units.append_array(active_enemies)
	
	turn_manager.process_turn(delta, all_units)

func execute_turn(actor):
	if actor is UnitData:
		await perform_party_attack(actor)
	else:
		await perform_enemy_attack(actor)
	
	check_victory()
	
	if not battle_ended:
		turn_manager.resume_turn()

# --- 공격 로직 ---
func perform_party_attack(member: UnitData):
	if active_enemies.is_empty(): return
	var target_slot = active_enemies.pick_random()
	
	var dmg = max(1, member.attack_power + randi_range(-2, 2))
	
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(target_slot):
		target_slot.take_damage(dmg)
		SignalBus.game_log.emit("%s의 공격! %s에게 %d 피해" % [member.name, target_slot.enemy_data.name, dmg], Color.WHITE)
	await get_tree().create_timer(0.5).timeout

func perform_enemy_attack(slot):
	var live_members = PartyManager.party_members.filter(func(m): return not m.is_dead())
	if live_members.is_empty(): return
	var target = live_members.pick_random()
	
	var dmg = 5
	if slot.enemy_data: dmg = slot.enemy_data.attack_power
	
	if slot.has_method("animate_attack"): slot.animate_attack()
	await get_tree().create_timer(0.3).timeout
	
	target.take_damage(dmg)
	SignalBus.party_updated.emit()
	SignalBus.game_log.emit("%s의 공격! %s -%d HP" % [slot.enemy_data.name, target.name, dmg], Color.RED)
	await get_tree().create_timer(0.5).timeout

# --- [핵심] 승리 체크 및 보상 지급 ---
func check_victory():
	for i in range(active_enemies.size() - 1, -1, -1):
		var slot = active_enemies[i]
		
		# 적이 죽었거나 유효하지 않으면
		if not is_instance_valid(slot) or (slot.has_method("is_dead") and slot.is_dead()):
			
			# [보상 축적]
			if is_instance_valid(slot) and slot.enemy_data:
				var gold = slot.enemy_data.drop_gold
				
				# 에러 방지: drop_exp가 없으면 0으로 처리
				var exp_val = 0
				if "drop_exp" in slot.enemy_data:
					exp_val = slot.enemy_data.drop_exp
				
				total_gold_reward += gold
				total_exp_reward += exp_val
				
				SignalBus.game_log.emit("%s 처치! (+%d G)" % [slot.enemy_data.name, gold], Color.YELLOW)
				
			if is_instance_valid(slot):
				slot.queue_free()
			active_enemies.remove_at(i)
	
	# 모든 적을 처치했다면?
	if active_enemies.is_empty():
		battle_ended = true
		
		# 보상 지급 실행
		distribute_rewards()
		
		await get_tree().create_timer(1.5).timeout
		queue_free()

	# (추가) 아군 전멸 체크
	var live_members = PartyManager.party_members.filter(func(m): return not m.is_dead())
	if live_members.is_empty():
		battle_ended = true
		SignalBus.game_log.emit("전멸했습니다...", Color.RED)
		await get_tree().create_timer(2.0).timeout
		queue_free()

# --- [NEW] 보상 지급 함수 ---
func distribute_rewards():
	# 1. 골드 지급
	if total_gold_reward > 0:
		GameSettings.add_gold(total_gold_reward)
		SignalBus.game_log.emit("전투 승리! 총 %d 골드 획득." % total_gold_reward, Color.GOLD)
	
	# 2. 경험치 지급
	if total_exp_reward > 0:
		var live_members = PartyManager.party_members.filter(func(m): return not m.is_dead())
		if not live_members.is_empty():
			for member in live_members:
				# member.gain_exp(total_exp_reward) 함수가 있어야 함!
				if member.has_method("gain_exp"):
					member.gain_exp(total_exp_reward)
			
			SignalBus.game_log.emit("파티원 전원 +%d 경험치 획득!" % total_exp_reward, Color.CYAN)
			SignalBus.party_updated.emit()
