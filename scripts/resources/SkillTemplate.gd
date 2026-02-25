extends Resource
class_name SkillTemplate

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var type: String = ""
@export var target: String = ""
@export var cooldown: float = 0.0
@export var damage_base: int = 0
@export var damage_scaling: Dictionary = {}
@export var effects: Array[Dictionary] = []
@export var default_on: bool = true
@export var base_damage: int = 0
@export var scaling: float = 0.0
@export var usable_on_field: bool = false
@export var extra: Dictionary = {}


func to_dict() -> Dictionary:
	var out: Dictionary = extra.duplicate(true)
	out["id"] = id
	out["name"] = name
	out["description"] = description
	out["type"] = type
	out["target"] = target
	out["cooldown"] = cooldown
	out["damage_base"] = damage_base
	out["damage_scaling"] = damage_scaling.duplicate(true)
	out["effects"] = effects.duplicate(true)
	out["default_on"] = default_on
	out["base_damage"] = base_damage
	out["scaling"] = scaling
	out["usable_on_field"] = usable_on_field
	return out
