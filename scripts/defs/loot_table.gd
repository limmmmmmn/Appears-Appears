# scripts/defs/loot_table.gd
extends Resource
class_name LootTable

@export var drops: Array[LootEntry] = []

func roll_loot() -> ItemData:
	var total := 0
	for e in drops:
		if e == null: continue
		total += max(0, e.weight)
	
	if total <= 0: return null
	
	var r := randi() % total
	var acc := 0
	
	for e in drops:
		if e == null: continue
		acc += max(0, e.weight)
		if r < acc: return e.item
	
	return null
