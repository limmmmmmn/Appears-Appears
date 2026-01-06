extends Node
# [Blueprint v1.4] 7. 매니저 카드 - 파티 및 재화 관리 

var gold: int = 1000
var party: Array[UnitRuntime] = [] # 최대 4명 [cite: 39]
var inventory: Array[ItemData] = []

const MAX_PARTY_SIZE = 4

func add_to_party(unit_data: UnitData) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		return false
	party.append(UnitRuntime.new(unit_data))
	return true

func remove_from_party(index: int) -> void:
	if index >= 0 and index < party.size():
		party.remove_at(index)
		
