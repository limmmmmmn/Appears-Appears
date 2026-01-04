# scripts/runtime/battle/battle_instance.gd
extends RefCounted
class_name BattleInstance

# 전투 상태 정의
enum BattleState { ACTIVE, WON, LOST }

var id: int
var party: Array[UnitRuntime] = []
var enemies: Array[UnitRuntime] = []
var state: BattleState = BattleState.ACTIVE

# 전투 시간 경과 (BattleManager가 호출함)
func tick(delta: float) -> void:
	if state != BattleState.ACTIVE: return
	
	# 1. 아군 행동 처리
	for unit in party:
		_process_unit(unit, enemies, delta)
		
	# 2. 적군 행동 처리
	for unit in enemies:
		_process_unit(unit, party, delta)
		
	# 3. 전투 종료 체크 (승패 판정)
	_check_battle_end()

# 개별 유닛 로직 (쿨타임 감소 -> 공격)
func _process_unit(actor: UnitRuntime, targets: Array[UnitRuntime], delta: float) -> void:
	if actor.is_dead(): return
	
	# 쿨타임 감소 (기본 공격 쿨타임이라 가정)
	# UnitRuntime에 'action_cooldown' 변수가 필요합니다 (아래 4단계에서 추가 예정)
	actor.action_cooldown -= delta
	
	if actor.action_cooldown <= 0:
		# 타겟 선정 (가장 가까운 적, 혹은 랜덤) - MVP는 랜덤으로 갑니다.
		var valid_targets = targets.filter(func(t): return not t.is_dead())
		if valid_targets.is_empty(): return
		
		var target = valid_targets.pick_random()
		
		# 공격 수행
		_execute_attack(actor, target)
		
		# 쿨타임 리셋 (예: 1.5초)
		actor.action_cooldown = 1.5 

# 실제 데미지 계산 및 로그
func _execute_attack(attacker: UnitRuntime, defender: UnitRuntime) -> void:
	# 데미지 공식: 공격력 - 방어력 (최소 1)
	var damage = max(1, attacker.data.base_stats.atk - defender.data.base_stats.def)
	
	defender.take_damage(damage)
	
	# SignalBus를 통해 로그 출력 (UI 갱신용)
	SignalBus.log_message.emit(
		"%s attacks %s for %d damage!" % [attacker.data.name, defender.data.name, damage]
	)

func _check_battle_end() -> void:
	var all_enemies_dead = enemies.all(func(e): return e.is_dead())
	var all_party_dead = party.all(func(p): return p.is_dead())
	
	if all_enemies_dead:
		state = BattleState.WON
		SignalBus.battle_ended.emit(id, true)
		print("Battle %d Won!" % id)
		
	elif all_party_dead:
		state = BattleState.LOST
		SignalBus.battle_ended.emit(id, false)
		print("Battle %d Lost..." % id)
