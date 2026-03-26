extends Resource
class_name TraitTemplate

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: String = ""
@export var effect: Dictionary = {}
@export var extra: Dictionary = {}


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out["id"] = id
	out["name"] = name
	out["description"] = description
	out["icon"] = icon
	out["effect"] = effect.duplicate(true)
	return out
