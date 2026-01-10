class_name ItemDef
extends Resource

@export var id: String = ""
@export var price: int = 100
@export var type: String = "weapon" # weapon, armor, accessory
@export var stat_mods: Dictionary = {} # {"atk": 5}
