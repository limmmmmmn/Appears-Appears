extends Resource

## A permanent upgrade node on the incremental skill tree.
## Runtime ownership lives in GameState; this resource is static catalog data.

@export var id: StringName = &""
@export var display_name: String = ""
@export var short_label: String = ""
@export_multiline var description: String = ""
@export var grid_position: Vector2i = Vector2i.ZERO
@export var cost: int = 0
@export_range(1, 99, 1) var max_level: int = 1
@export var prerequisite_ids: Array[StringName] = []
@export var linked_modifier: ModifierData
@export var effect_data: Dictionary = {}
