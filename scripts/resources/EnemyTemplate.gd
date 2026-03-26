extends Resource
class_name EnemyTemplate

@export var id: String = ""
@export var name: String = ""
@export var type: String = "normal"
@export var stats: Dictionary = {}
@export var rewards: Dictionary = {}
@export var drop_table: Array[Dictionary] = []
@export var skills: Array[String] = []
@export var sprite: String = ""
@export var tags: Array[String] = []
@export var damage_type: String = "physical"


func to_dict() -> Dictionary:
	var out: Dictionary = {
		"id": id,
		"name": name,
		"type": type,
		"stats": stats.duplicate(true),
		"rewards": rewards.duplicate(true),
		"drop_table": drop_table.duplicate(true),
		"skills": skills.duplicate(),
		"sprite": sprite,
		"tags": tags.duplicate(),
		"damage_type": damage_type,
	}
	return out
