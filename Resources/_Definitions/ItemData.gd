# res://Resources/_Definitions/ItemData.gd
class_name ItemData
extends Resource

@export var name: String = "Item"
@export var description: String = ""
@export var icon: Texture2D
@export var price: int = 0
@export var is_consumable: bool = false
