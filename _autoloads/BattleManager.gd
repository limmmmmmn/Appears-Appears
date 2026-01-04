# _autoloads/battle_manager.gd
extends Node

var _battles: Array[BattleInstance] = []

func _physics_process(delta: float) -> void:
	# 역순 순회 (전투 종료 시 배열에서 제거하기 위해)
	for i in range(_battles.size() - 1, -1, -1):
		var b = _battles[i]
		
		# 전투 로직 실행 (Tick)
		b.tick(delta)
		
		# 전투 종료 처리
		if b.state != BattleInstance.BattleState.ACTIVE:
			_battles.remove_at(i)
			# 추후 여기에 UI 윈도우 닫기 로직 연결 필요

func start_battle(party: Array[UnitRuntime], enemies: Array[UnitRuntime]) -> void:
	var new_battle = BattleInstance.new()
	new_battle.id = randi()
	new_battle.party = party
	new_battle.enemies = enemies
	new_battle.state = BattleInstance.BattleState.ACTIVE # 명시적 활성화
	
	_battles.append(new_battle)
	SignalBus.battle_started.emit(new_battle.id)
	
	print("Battle Started! ID: %d" % new_battle.id)
