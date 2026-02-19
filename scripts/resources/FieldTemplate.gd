extends Resource
class_name FieldTemplate

@export var id: String = ""
@export var name: String = ""
@export var scene: String = ""
@export var weight: float = 1.0

@export var enemy_count: Dictionary = {}
@export var enemy_pool: Dictionary = {}
@export var elite_chance: float = 0.0
@export var field_boss_id: String = ""
@export var elite_pool: Array[String] = []
@export var boss_enemy_id: String = ""


func to_runtime_dict(forced_type: String = "field") -> Dictionary:
	var out: Dictionary = {
		"id": id,
		"name": name,
		"scene": scene,
		"type": forced_type,
		"weight": weight,
	}
	if not enemy_count.is_empty():
		out["enemy_count"] = enemy_count.duplicate(true)
	if not enemy_pool.is_empty():
		out["enemy_pool"] = enemy_pool.duplicate(true)
	if elite_chance > 0.0:
		out["elite_chance"] = elite_chance
	if not field_boss_id.is_empty():
		out["field_boss_id"] = field_boss_id
	if not elite_pool.is_empty():
		out["elite_pool"] = elite_pool.duplicate()
	if not boss_enemy_id.is_empty():
		out["boss_enemy_id"] = boss_enemy_id
	return out
