extends RefCounted
class_name LootGenerator
## 전리품(루트) 생성 시스템


static func generate_elite_loot() -> Array[String]:
	## 엘리트 3지선다 - 매직 이상 1개 보장
	var pool: Array[String] = []
	
	var common: Array[String] = DataManager.get_equipment_by_rarity("common")
	var magic: Array[String] = DataManager.get_equipment_by_rarity("magic")
	var legendary: Array[String] = DataManager.get_equipment_by_rarity("legendary")
	
	common.shuffle()
	magic.shuffle()
	legendary.shuffle()
	
	# 1. 매직 이상 1개 확정 (20% 레전더리)
	if randf() < 0.2 and not legendary.is_empty():
		pool.append(legendary[0])
	elif not magic.is_empty():
		pool.append(magic[0])
	elif not legendary.is_empty():
		pool.append(legendary[0])
	
	# 2. 나머지 2개는 전체에서 랜덤
	var all: Array[String] = []
	all.append_array(common)
	all.append_array(magic)
	all.append_array(legendary)
	all.shuffle()
	
	for item_id in all:
		if pool.size() >= 3:
			break
		if not pool.has(item_id):
			pool.append(item_id)
	
	pool.shuffle()
	return pool


static func generate_boss_loot() -> Array[String]:
	## 보스 3지선다 - 레전더리 1개 + 매직 2개 보장
	var pool: Array[String] = []
	
	var magic: Array[String] = DataManager.get_equipment_by_rarity("magic")
	var legendary: Array[String] = DataManager.get_equipment_by_rarity("legendary")
	
	magic.shuffle()
	legendary.shuffle()
	
	# 1. 레전더리 1개 확정
	if not legendary.is_empty():
		pool.append(legendary[0])
	elif not magic.is_empty():
		pool.append(magic[0])
	
	# 2. 매직 2개 추가
	for item_id in magic:
		if pool.size() >= 3:
			break
		if not pool.has(item_id):
			pool.append(item_id)
	
	pool.shuffle()
	return pool
