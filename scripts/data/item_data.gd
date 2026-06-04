class_name ItemData
extends Resource

## Equipment item definition. Runtime ownership lives in GameState.

enum Slot { WEAPON, SHIELD, HELMET, ARMOR, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.ACCESSORY
@export var icon: Texture2D
## Empty = any party member. Weapons can set this to hero/mage/priest/thief.
@export var allowed_character_id: StringName = &""

## Future stat hooks. Currently display-only equipment, but data is ready.
@export var attack_bonus: int = 0
@export var agility_bonus: int = 0
@export var max_hp_bonus: int = 0
