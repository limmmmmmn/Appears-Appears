# res://Components/TurnSystem.gd
class_name TurnSystem extends Node

# 턴이 준비되면 알리는 신호
signal turn_ready(unit: BattleUnit)

var units: Array[BattleUnit] = []
var active: bool = false

# 전투 시작 시 유닛 명단 받기
func initialize(battle_units: Array[BattleUnit]):
	units = battle_units
	active = true

func stop():
	active = false

func _process(delta):
	if not active: return
	
	for unit in units:
		# 죽은 유닛은 턴 계산 안 함
		if unit.current_hp <= 0: continue
		
		# 쿨타임 감소 (속도가 빠르면 더 빨리 감소)
		# 공식: 기본 1초 감소 * (속도 보정)
		var speed_factor = unit.speed / 5.0 # 속도 5가 기준
		unit.cooldown -= delta * speed_factor
		
		if unit.cooldown <= 0:
			# 턴 준비 완료!
			turn_ready.emit(unit)
			unit.cooldown = 3.0 # 행동 후 쿨타임 리셋 (기본 3초)
