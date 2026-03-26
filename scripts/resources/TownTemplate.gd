extends Resource
class_name TownTemplate

@export var id: String = ""
@export var name: String = ""
@export var scene: String = ""
@export var weight: float = 1.0


func to_runtime_dict(forced_type: String = "town") -> Dictionary:
	return {
		"id": id,
		"name": name,
		"scene": scene,
		"type": forced_type,
		"weight": weight,
	}
