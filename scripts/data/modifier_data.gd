class_name ModifierData
extends Resource

## Modifier (relic) data.
## Saved as .tres files under data/modifiers/{rarity}/.
## Loaded by ModifierDB autoload.

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
enum Category { QUANTITY, CONDITIONAL, TRANSFORM, COMPANION }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export var rarity: Rarity = Rarity.COMMON
@export var category: Category = Category.QUANTITY

## Free-form effect data. Read by battle calculation code.
## Example: { "atk_flat": 5 } or { "trigger": "single_target", "atk_mult": 2.0 }
@export var effect_data: Dictionary = {}
