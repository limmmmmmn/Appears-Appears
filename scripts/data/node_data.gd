class_name NodeData
extends Resource

## Skill-tree node. Permanent unlock purchased with meta gold at HomeBase.
## Created in code by SkillTreeDB for now — once the catalog stabilizes
## we can move these to .tres files like ModifierData.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var cost: int = 50

## Other node ids that must be unlocked before this becomes purchasable.
## Empty array = root node.
@export var prereq_ids: Array[StringName] = []

## Free-form effect payload. Read by GameState/main when applying the unlock.
## Examples:
##   { "recruit_character_id": "mage" }
##   { "max_concurrent_battles_delta": 1 }
##   { "field_combat_movement": true }
@export var effect_data: Dictionary = {}

## Optional layout hint for the tree UI. (column, row) in node-grid space.
@export var grid_position: Vector2i = Vector2i.ZERO
