# scripts/autoload/EventBus.gd
extends Node

signal enemy_died(enemy_id: String)
signal battle_started(battle_id: String)
signal battle_ended(battle_id: String)
signal battle_victory()
signal battle_defeat()
signal item_obtained(item_id: String)
signal item_dropped(item_id: String)
signal synergy_activated(synergy_id: String)
signal player_damaged(damage: int)
signal player_healed(amount: int)
signal scene_transition_requested(target_scene: String)
signal field_entered(field_id: String)
signal town_entered(town_id: String)
signal game_over()

func _ready() -> void:
	print("[EventBus] Ready")
