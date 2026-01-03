extends CanvasLayer
class_name BattleScene

@export var enemy_slot_scene: PackedScene 

@onready var battle_spawner = $BattleSpawner
@onready var turn_manager = $TurnManager
@onready var background_panel = $BackgroundPanel
@onready var enemy_container = $BackgroundPanel/EnemyContainer

var active_enemies: Array = [] 
var battle_ended: bool = false

func _ready():
	enemy_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	if enemy_container is BoxContainer:
		enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# [이름 변경] 스포너 초기화
	battle_spawner.setup(enemy_container, background_panel, enemy_slot_scene)
	
	turn_manager.turn_ready.connect(execute_turn)

func start_battle(main_enemy: EnemyData, spawn_table: Array[SpawnEntry]):
	# [이름 변경] 적 생성 위임
	active_enemies = battle_spawner.spawn_enemies(main_enemy, spawn_table)
	
	# 턴 시스템 가동
	var all_units = []
	for m in PartyManager.party_members: all_units.append(m)
	all_units.append_array(active_enemies)
	
	turn_manager.initialize(all_units)

func _process(delta):
	if battle_ended: return
	
	# 3. 턴 계산 (매니저에게 위임)
	# (매니저가 계산하다가 100 차면 signal을 보냄 -> execute_turn 실행됨)
	var all_units = []
	for m in PartyManager.party_members: all_units.append(m)
	all_units.append_array(active_enemies)
	
	turn_manager.process_turn(delta, all_units)

# --- 행동 실행 (신호 받으면 실행됨) ---
func execute_turn(actor):
	# 누구 턴인지 판별해서 행동
	if actor is UnitData:
		await perform_party_attack(actor)
	else:
		await perform_enemy_attack(actor)
	
	# 전투 종료 체크
	check_victory()
	
	if not battle_ended:
		turn_manager.resume_turn() # 다음 턴 계산 재개

# --- (아래 공격 로직은 연출과 UI가 섞여있어서 일단 여기에 둡니다) ---

func perform_party_attack(member: UnitData):
	if active_enemies.is_empty(): return
	var target_slot = active_enemies.pick_random()
	
	# 데미지 계산 (UnitData에 위임하면 더 좋음)
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

func check_victory():
	for i in range(active_enemies.size() - 1, -1, -1):
		var slot = active_enemies[i]
		if not is_instance_valid(slot) or (slot.has_method("is_dead") and slot.is_dead()):
			if is_instance_valid(slot) and slot.enemy_data:
				SignalBus.game_log.emit("%s 처치! +%d G" % [slot.enemy_data.name, slot.enemy_data.drop_gold], Color.YELLOW)
				slot.queue_free()
			active_enemies.remove_at(i)
	
	if active_enemies.is_empty():
		battle_ended = true
		await get_tree().create_timer(1.0).timeout
		queue_free()
