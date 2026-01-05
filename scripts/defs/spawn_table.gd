class_name SpawnTable extends Resource
# [Blueprint v1.4] 3. 데이터 카드 - 가중치 기반 스폰 관리자

@export var entries: Array[SpawnEntry] = []

# 가중치 랜덤 뽑기 (Weighted Random)
func pick_unit() -> UnitData:
	if entries.is_empty():
		return null
	
	# 1. 전체 가중치 합 계산
	var total_weight = 0
	for entry in entries:
		if entry.unit: # UnitData가 있는 경우만 계산
			total_weight += entry.weight
	
	if total_weight == 0:
		return null

	# 2. 랜덤 값 뽑기
	var random_val = randi() % total_weight
	var current_weight = 0
	
	# 3. 누적 가중치로 대상 찾기
	for entry in entries:
		if not entry.unit: continue
		
		current_weight += entry.weight
		if random_val < current_weight:
			return entry.unit
			
	return entries[0].unit # 안전 장치
