class_name UnitPool extends Resource
# 마을 주점에서 등장할 수 있는 동료 목록
@export var candidates: Array[UnitData] = []

func pick_random(count: int = 1) -> Array[UnitData]:
	var result: Array[UnitData] = []
	var pool = candidates.duplicate()
	pool.shuffle()
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result
