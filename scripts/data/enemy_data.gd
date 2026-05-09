class_name EnemyData
extends Resource

## Enemy archetype data.
## Saved as .tres files under data/enemies/.
## A single .tres = one enemy *species* (Slime, Bat, ...).
## Per-instance state (current HP) lives on the Enemy node, not here.

@export var id: StringName = &""
@export var display_name: String = ""
@export var sprite: Texture2D

## Combat stats.
@export var max_hp: int = 10
@export var attack: int = 2
@export var defense: int = 0

## Reward on defeat.
@export var gold_reward: int = 1
@export var xp_reward: int = 1
