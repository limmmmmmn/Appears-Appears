extends Node
# [Blueprint v1.4] 7. 매니저 카드 - 파티 및 재화 관리 

var gold: int = 1000
var party: Array[UnitRuntime] = [] # 최대 4명 [cite: 39]
var inventory: Array[ItemData] = []

# 게임 내 존재하는 모든 영웅의 데이터 (여기에 4명을 드래그해서 넣으세요)
@export var all_heroes_pool: Array[UnitData] = []

const MAX_PARTY_SIZE = 4

# 영입 기능
func add_to_party(unit_data: UnitData) -> bool:
	if party.size() >= MAX_PARTY_SIZE: return false
	party.append(UnitRuntime.new(unit_data))
	return true

# 해고 기능
func fire_hero(index: int) -> void:
	if index >= 0 and index < party.size():
		var fired_hero = party[index]
		party.remove_at(index)
		print("%s를 해고했습니다." % fired_hero._data.name)

# 현재 파티에 포함되지 않은 영웅들만 필터링해서 반환
func get_available_heroes() -> Array[UnitData]:
	var available: Array[UnitData] = []
	for data in all_heroes_pool:
		var is_in_party = false
		for member in party:
			if member._data == data:
				is_in_party = true
				break
		if not is_in_party:
			available.append(data)
	return available
