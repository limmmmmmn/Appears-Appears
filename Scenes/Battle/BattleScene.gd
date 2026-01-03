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
var loot_items: Array[ItemData] = [] # [NEW] 이번 전투에서 얻은 아이템 목록

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
	
	# [수정] attack_power 대신 get_total_attack() 사용!
	var final_atk = member.get_total_attack()
	var dmg = max(1, final_atk + randi_range(-2, 2))
	
	await get_tree().create_timer(0.1).timeout # 공격 전 뜸 들이는 시간
	if is_instance_valid(target_slot):
		target_slot.take_damage(dmg)
		SignalBus.game_log.emit("%s의 공격! %s에게 %d 피해" % [member.name, target_slot.enemy_data.name, dmg], Color.WHITE)
	await get_tree().create_timer(0.1).timeout # [2] 공격 후 대기 시간

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
		
		# 적 처치 확인
		if not is_instance_valid(slot) or (slot.has_method("is_dead") and slot.is_dead()):
			
			if is_instance_valid(slot) and slot.enemy_data:
				var data = slot.enemy_data
				
				# 1. 골드/경험치 축적
				total_gold_reward += data.drop_gold
				if "drop_exp" in data: total_exp_reward += data.drop_exp
				
				# 2. [NEW] 아이템 드랍 체크!
				if data.drop_item and randf() <= data.drop_chance:
					loot_items.append(data.drop_item)
					# 로그에 초록색으로 표시
					SignalBus.game_log.emit("%s 획득!" % data.drop_item.name, Color.GREEN)
				
				# 처치 로그
				SignalBus.game_log.emit("%s 처치! (+%d G)" % [data.name, data.drop_gold], Color.YELLOW)
				
			if is_instance_valid(slot): slot.queue_free()
			active_enemies.remove_at(i)
	
	# 승리 확정 시
	if active_enemies.is_empty():
		battle_ended = true
		distribute_rewards()
		await get_tree().create_timer(0.1).timeout # 루팅 메시지 볼 시간 줌
		queue_free()

# --- [NEW] 보상 지급 함수 ---
func distribute_rewards():
	# 1. 골드 지급
	if total_gold_reward > 0:
		GameSettings.add_gold(total_gold_reward)
	
	# 2. 경험치 지급
	if total_exp_reward > 0:
		var live_members = PartyManager.party_members.filter(func(m): return not m.is_dead())
		for member in live_members:
			if member.has_method("gain_exp"): member.gain_exp(total_exp_reward)
		SignalBus.party_updated.emit()

	# 3. [NEW] 아이템 인벤토리에 넣기
	if not loot_items.is_empty():
		for item in loot_items:
			GameSettings.add_item(item)
		SignalBus.game_log.emit("총 %d개의 아이템을 획득했습니다." % loot_items.size(), Color.CYAN)
