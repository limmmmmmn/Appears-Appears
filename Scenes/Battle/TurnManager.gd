extends Node
class_name TurnManager

# 턴이 준비되면 알리는 신호
signal turn_ready(actor)

var turn_gauges: Dictionary = {}
var battle_speed: float = 100.0
var is_active: bool = false

func initialize(all_units: Array):
	turn_gauges.clear()
	is_active = true
	
	# 초기 게이지 설정 (선제공권 랜덤성)
	for unit in all_units:
		var bonus = 0.0
		# 아군이면 민첩 보너스
		if unit is UnitData:
			bonus = min(50.0, unit.agility * 0.5)
		
		turn_gauges[unit] = randf_range(0.0, 10.0) + bonus

func process_turn(delta: float, all_units: Array):
	if not is_active: return

	var ready_units = []
	
	for unit in all_units:
		# 죽은 유닛 제외
		if _is_dead(unit): continue
			
		if not turn_gauges.has(unit): turn_gauges[unit] = 0.0
		
		var agi = _get_agility(unit)
		var increase = (battle_speed + agi) * delta
		
		turn_gauges[unit] += increase
		
		if turn_gauges[unit] >= 100.0:
			ready_units.append(unit)
	
	# 턴 결정
	if not ready_units.is_empty():
		ready_units.sort_custom(func(a, b): return turn_gauges[a] > turn_gauges[b])
		var actor = ready_units[0]
		
		# 게이지 소비 및 턴 정지
		turn_gauges[actor] -= 100.0
		is_active = false 
		
		# 메인 씬에 "얘 차례야!" 라고 알려줌
		turn_ready.emit(actor)

func resume_turn():
	is_active = true

# 유틸리티 함수들
func _is_dead(unit) -> bool:
	if unit is UnitData: return unit.is_dead()
	if unit.has_method("is_dead"): return unit.is_dead()
	return false

func _get_agility(unit) -> float:
	if unit is UnitData: 
		# [수정] agility 대신 get_total_agility() 사용!
		return unit.get_total_agility()
		
	if "enemy_data" in unit and unit.enemy_data: 
		return float(unit.enemy_data.agility)
	return 10.0
