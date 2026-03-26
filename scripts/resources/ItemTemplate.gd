extends Resource
class_name ItemTemplate

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var type: String = ""
@export var category: String = ""
@export var consumable: bool = false
@export var target_id: String = ""
@export var stage: int = -1
@export var readable: bool = false
@export var content: String = ""
@export var sell_price: int = -1
@export var quest_id: String = ""
@export var count_required: int = -1
@export var event_id: String = ""
@export var unlock_shop: String = ""
@export var extra: Dictionary = {}


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out["id"] = id
	out["name"] = name
	out["description"] = description
	out["type"] = type
	out["category"] = category
	out["consumable"] = consumable

	if not target_id.is_empty():
		out["target_id"] = target_id
	if stage >= 0:
		out["stage"] = stage
	if readable:
		out["readable"] = true
	if not content.is_empty():
		out["content"] = content
	if sell_price >= 0:
		out["sell_price"] = sell_price
	if not quest_id.is_empty():
		out["quest_id"] = quest_id
	if count_required >= 0:
		out["count_required"] = count_required
	if not event_id.is_empty():
		out["event_id"] = event_id
	if not unlock_shop.is_empty():
		out["unlock_shop"] = unlock_shop
	return out
