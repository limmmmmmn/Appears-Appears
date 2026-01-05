class_name BattleInstance extends RefCounted
# [Blueprint v1.4] 4. 런타임 상태 - 개별 전투 데이터

var id: int
var enemies: Array[UnitRuntime] = [] # 전투에 참여하는 적 목록

# 전투 종료 콜백 (승리 여부 전달)
var on_battle_end: Callable 

func _init(p_enemies: Array[UnitRuntime]) -> void:
	enemies = p_enemies
