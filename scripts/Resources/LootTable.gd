extends Resource
class_name LootTable

# [설계도 89] 드랍 목록
@export var drops: Array[LootEntry]

# [설계도 92] 가중치 랜덤 뽑기 구현
func roll_loot() -> ItemData:
	var total_weight = 0
	for entry in drops:
		# 안전장치: entry가 비어있을 경우 대비
		if entry:
			total_weight += entry.weight
	
	if total_weight == 0:
		return null
		
	var random_val = randi_range(0, total_weight - 1)
	var current_weight = 0
	
	for entry in drops:
		if entry:
			current_weight += entry.weight
			if random_val < current_weight:
				return entry.item
	
	return null
