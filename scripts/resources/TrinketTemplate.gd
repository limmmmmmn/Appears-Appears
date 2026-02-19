extends Resource
class_name TrinketTemplate

@export var id: String = ""
@export var name: String = ""
@export var emoji: String = ""
@export_multiline var description: String = ""
@export var sources: Array[String] = ["boss", "shop", "event"]

# Reward / Difficulty / Battle system modifiers
@export var reward_gold_multiplier: float = 1.0
@export var reward_exp_multiplier: float = 1.0
@export var enemy_stat_multiplier: float = 1.0
@export var field_enemy_count_multiplier: float = 1.0
@export var battle_enemy_bonus: int = 0
@export var max_enemies_per_window_bonus: int = 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"emoji": emoji,
		"description": description,
		"sources": sources.duplicate(),
		"reward_gold_multiplier": reward_gold_multiplier,
		"reward_exp_multiplier": reward_exp_multiplier,
		"enemy_stat_multiplier": enemy_stat_multiplier,
		"field_enemy_count_multiplier": field_enemy_count_multiplier,
		"battle_enemy_bonus": battle_enemy_bonus,
		"max_enemies_per_window_bonus": max_enemies_per_window_bonus,
	}
