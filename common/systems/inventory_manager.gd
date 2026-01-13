extends Node

# 4-1. 내부 상태(고정)
var gold: int = 0
var items: Dictionary = {} # key: String(item_id), value: int(count)

func reset_new_game() -> void:
	gold = 0
	items.clear()
	_emit_gold_changed()
	_emit_inventory_changed()

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	_emit_gold_changed()
	_emit_inventory_changed()

func try_spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	_emit_gold_changed()
	_emit_inventory_changed()
	return true

func add_item(item_id: String, amount: int = 1) -> void:
	if item_id == "" or amount <= 0:
		return
	var cur := get_item_count(item_id)
	items[item_id] = cur + amount
	_emit_inventory_changed()

func remove_item(item_id: String, amount: int = 1) -> bool:
	if item_id == "" or amount <= 0:
		return false
	var cur := get_item_count(item_id)
	if cur < amount:
		return false
	var next := cur - amount
	if next <= 0:
		items.erase(item_id)
	else:
		items[item_id] = next
	_emit_inventory_changed()
	return true

func get_item_count(item_id: String) -> int:
	if item_id == "":
		return 0
	if not items.has(item_id):
		return 0
	var v = items[item_id]
	return int(v)

func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount

# --- Save hooks (고정) ---
func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"items": items.duplicate(true),
	}

func from_save_dict(data: Dictionary) -> void:
	# SaveManager가 직접 필드 만지면 규칙 위반 → 여기서만 복원
	gold = int(data.get("gold", 0))

	items.clear()
	var raw_items = data.get("items", {})
	if typeof(raw_items) == TYPE_DICTIONARY:
		for k in raw_items.keys():
			if typeof(k) != TYPE_STRING:
				continue
			var c := int(raw_items[k])
			if c > 0:
				items[String(k)] = c

	_emit_gold_changed()
	_emit_inventory_changed()

# --- Events emit 규칙(고정) ---
func _emit_gold_changed() -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).gold_changed.emit(gold)

func _emit_inventory_changed() -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).inventory_changed.emit()
