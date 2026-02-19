extends Resource
class_name EquipmentTemplate

@export var id: String = ""
@export var name: String = ""
@export var slot: String = ""
@export var type: String = ""
@export var rarity: String = "common"
@export var two_handed: bool = false
@export var stats: Dictionary = {}
@export var special_effect: Dictionary = {}
@export var gear_score: int = 0
@export var extra: Dictionary = {}


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out["id"] = id
	out["name"] = name
	out["slot"] = slot
	out["type"] = type
	out["rarity"] = rarity
	out["two_handed"] = two_handed
	out["stats"] = stats.duplicate(true)
	out["special_effect"] = special_effect.duplicate(true)
	out["gear_score"] = gear_score
	return out
