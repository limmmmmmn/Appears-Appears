extends Resource
class_name ClassTemplate

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var base_stats: Dictionary = {}
@export var growth: Dictionary = {}
@export var equip_restrictions: Dictionary = {}
@export var tags: Array[String] = []
@export var skills: Array[String] = []
@export var growth_per_level: Dictionary = {}
@export var skill_unlocks: Dictionary = {}
@export var action_speed: float = 2.0  ## 기본공격 ATB 기준 속도 (초). 낮을수록 빠름


func to_dict() -> Dictionary:
	var out: Dictionary = {
		"id": id,
		"name": name,
		"description": description,
		"base_stats": base_stats.duplicate(true),
		"growth": growth.duplicate(true),
		"equip_restrictions": equip_restrictions.duplicate(true),
		"tags": tags.duplicate(),
		"skills": skills.duplicate(),
	}
	if not growth_per_level.is_empty():
		out["growth_per_level"] = growth_per_level.duplicate(true)
	if not skill_unlocks.is_empty():
		out["skill_unlocks"] = skill_unlocks.duplicate(true)
	out["action_speed"] = action_speed
	return out
