extends Resource
class_name HeroTemplate

@export var id: String = ""
@export var name: String = ""
@export var class_id: String = ""
@export var sprite_field: String = ""
@export var sprite_face: String = ""
@export var tags: Array[String] = []
@export var traits: Array[String] = []
@export var description: String = ""


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"class_id": class_id,
		"sprite_field": sprite_field,
		"sprite_face": sprite_face,
		"tags": tags.duplicate(),
		"traits": traits.duplicate(),
		"description": description,
	}
