extends Resource
class_name BaseDef

@export var id: String = ""
@export var display_name: String = ""
@export var desc: String = ""
@export var tags: Array[String] = []

# Validator가 사용하는 "참조 ID 목록" 훅
# 규약: { "item": ["item_iron_sword"], "skill": ["skill_fireball"] }
func get_ref_map() -> Dictionary:
	return {}
