class_name LootTableDef
extends Resource

# 내부 클래스 정의
class Entry extends Resource:
	@export var item_id: String = "" # 비워두면 꽝
	@export var weight: int = 10
	@export var min_qty: int = 1
	@export var max_qty: int = 1

@export var id: String = ""
@export var entries: Array[Entry] = []

func pick() -> Dictionary:
	if entries.is_empty(): return {"item_id": "", "qty": 0}
	
	var total_weight := 0
	for e in entries:
		if e.weight > 0: total_weight += e.weight
	if total_weight <= 0: return {"item_id": "", "qty": 0}
	
	var roll := randi() % total_weight
	var current := 0
	
	for e in entries:
		if e.weight <= 0: continue
		current += e.weight
		if roll < current:
			var qty := randi_range(e.min_qty, e.max_qty)
			return {"item_id": e.item_id, "qty": qty}
			
	return {"item_id": entries[0].item_id, "qty": 1}
