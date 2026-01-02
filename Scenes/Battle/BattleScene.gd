extends CanvasLayer
class_name BattleScene

@export var enemy_slot_scene: PackedScene 

@onready var background_panel = $BackgroundPanel
@onready var enemy_container = $BackgroundPanel/EnemyContainer

# 전투 상태 변수
var active_enemies: Array = [] 
var battle_ended: bool = false
var spawn_table_ref: Array[SpawnEntry] = [] 

# 파티원 공격 쿨타임 관리용 딕셔너리
var party_cooldowns: Dictionary = {}

func _ready():
	# UI 정렬 설정
	enemy_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	if enemy_container is BoxContainer:
		enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER

func start_battle(main_enemy: EnemyData, spawn_table: Array[SpawnEntry]):
	spawn_table_ref = spawn_table
	
	set_window_position()
	generate_enemies(main_enemy)

# 팝업 위치를 플레이어에게 방해되지 않는 곳으로 설정
func set_window_position():
	var viewport_rect = get_viewport().get_visible_rect()
	var center = viewport_rect.size / 2
	var safe_zone = 150.0 
	
	var panel_size = background_panel.size
	var max_tries = 10
	
	for i in range(max_tries):
		var rand_x = randf_range(20, viewport_rect.size.x - panel_size.x - 20)
		var rand_y = randf_range(20, viewport_rect.size.y - panel_size.y - 20)
		var pos = Vector2(rand_x, rand_y)
		var panel_center = pos + (panel_size / 2)
		
		if panel_center.distance_to(center) > safe_zone:
			background_panel.position = pos 
			return
	
	background_panel.position = Vector2(20, 20) # 실패 시 기본 위치

# 적 생성 로직
func generate_enemies(main_enemy: EnemyData):
	var count = randi_range(1, 3)
	var enemies_to_spawn: Array[EnemyData] = []
	
	enemies_to_spawn.append(main_enemy)
	
	for i in range(count - 1):
		if not spawn_table_ref.is_empty() and randf() > 0.3:
			var random_entry = spawn_table_ref.pick_random()
			enemies_to_spawn.append(random_entry.enemy)
		else:
			enemies_to_spawn.append(main_enemy)
	
	# 슬롯 생성 및 배치
	for data in enemies_to_spawn:
		if enemy_slot_scene:
			var slot = enemy_slot_scene.instantiate()
			enemy_container.add_child(slot)
			# 슬롯 스크립트에 setup 함수가 있어야 함
			if slot.has_method("setup"):
				slot.setup(data)
			active_enemies.append(slot)

func _process(delta):
	if battle_ended: return
	
	process_party_attack(delta)
	process_enemy_attack(delta)
	check_victory()

# --- [핵심] 아군 공격 로직 (에러 방지 추가) ---
func process_party_attack(delta):
	for member in PartyManager.party_members:
		if member.is_dead(): continue
		
		# 쿨타임 초기화
		if not party_cooldowns.has(member):
			party_cooldowns[member] = randf_range(0.0, 1.0) # 첫 공격 약간 랜덤
		
		# ---------------------------------------------------------
		# [에러 방지] 변수가 없으면 기본값(1.0초) 사용
		# ---------------------------------------------------------
		var w_speed = 1.0
		var agi = 10.0
		
		if "weapon_speed" in member: w_speed = member.weapon_speed
		if "agility" in member: agi = member.agility
		
		# 쿨타임 계산 (민첩이 높으면 쿨타임 감소)
		var final_cooldown = w_speed / max(0.1, (1.0 + agi / 100.0))
		
		# 시간 흐름
		party_cooldowns[member] -= delta
		
		if party_cooldowns[member] <= 0:
			party_cooldowns[member] = final_cooldown # 쿨타임 리셋
			perform_party_attack(member)

func perform_party_attack(member: UnitData):
	if active_enemies.is_empty(): return
	
	var target_slot = active_enemies.pick_random()
	
	# 데미지 계산
	var atk = 10
	if "attack_power" in member: atk = member.attack_power
	
	var damage = max(1, atk + randi_range(-2, 2))
	
	# 적에게 데미지 적용
	if target_slot.has_method("take_damage"):
		target_slot.take_damage(damage)
		# (선택) 이펙트나 로그 출력

# --- 적군 공격 로직 ---
func process_enemy_attack(delta):
	for slot in active_enemies:
		# EnemySlot에 is_dead 함수나 변수가 있어야 함
		if slot.has_method("is_dead") and slot.is_dead(): continue
		
		# EnemySlot에 current_cooldown 변수가 있어야 함
		if "current_cooldown" in slot:
			slot.current_cooldown -= delta
			
			if slot.current_cooldown <= 0:
				# 쿨타임 리셋 (EnemySlot에 max_cooldown이 있어야 함)
				if "max_cooldown" in slot:
					slot.current_cooldown = slot.max_cooldown
				else:
					slot.current_cooldown = 2.0 # 기본값
				
				trigger_enemy_strike(slot)

func trigger_enemy_strike(slot):
	# 살아있는 파티원 찾기
	var live_members = PartyManager.party_members.filter(func(m): return not m.is_dead())
	if live_members.is_empty(): return
	
	var target = live_members.pick_random()
	
	# 적 데이터에서 공격력 가져오기
	var dmg = 5
	if "enemy_data" in slot and slot.enemy_data:
		dmg = slot.enemy_data.attack_power
	
	# 아군 피격
	target.take_damage(dmg)
	
	# UI 갱신 요청
	SignalBus.party_updated.emit()
	SignalBus.game_log.emit("%s의 공격! %s -%d HP" % [slot.enemy_data.name, target.name, dmg], Color.RED)
	
	# 적 공격 애니메이션 (함수가 있다면)
	if slot.has_method("animate_attack"):
		slot.animate_attack()

# --- 승리 조건 확인 ---
func check_victory():
	# 뒤에서부터 순회하며 죽은 적 제거 (배열 꼬임 방지)
	for i in range(active_enemies.size() - 1, -1, -1):
		var slot = active_enemies[i]
		
		# 슬롯이 삭제되었거나 죽었으면 처리
		if not is_instance_valid(slot) or (slot.has_method("is_dead") and slot.is_dead()):
			
			# 보상 처리 (골드 등)
			if is_instance_valid(slot) and "enemy_data" in slot:
				var gold = slot.enemy_data.drop_gold
				SignalBus.game_log.emit("%s 처치! +%d G" % [slot.enemy_data.name, gold], Color.YELLOW)
				# TODO: 실제 골드 증가 로직 추가 (InventoryManager.add_gold(gold) 등)
			
			# 리스트에서 제거 및 오브젝트 삭제
			active_enemies.remove_at(i)
			if is_instance_valid(slot):
				slot.queue_free()
	
	# 모든 적이 사라졌으면 승리
	if active_enemies.is_empty():
		battle_ended = true
		
		# 잠시 대기 후 창 닫기
		await get_tree().create_timer(0.1).timeout
		queue_free()
