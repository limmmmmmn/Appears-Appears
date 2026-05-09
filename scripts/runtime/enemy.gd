class_name Enemy
extends Node2D

## Generic enemy node. Data-driven via EnemyData.
## One scene (enemy.tscn) handles every species; the .tres swaps stats + sprite.

signal hp_changed(current: int, max_hp: int)
signal died()

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

@export var data: EnemyData

@onready var _sprite: Sprite2D = $Sprite2D

var current_hp: int = 0


func _ready() -> void:
	if data:
		_apply_data()


## Allows callers to inject data after instantiate() but before adding to tree.
func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data == null:
		return
	current_hp = data.max_hp
	if data.sprite and _sprite:
		_sprite.texture = data.sprite
	hp_changed.emit(current_hp, data.max_hp)


func is_alive() -> bool:
	return current_hp > 0


func take_damage(amount: int, is_crit: bool = false) -> int:
	if not is_alive() or data == null:
		return 0
	var dealt: int = max(1, amount - data.defense)
	current_hp = max(0, current_hp - dealt)
	hp_changed.emit(current_hp, data.max_hp)
	EventBus.damage_dealt.emit(self, dealt, global_position)
	_spawn_damage_number(dealt, is_crit)
	if current_hp == 0:
		_die()
	return dealt


func _spawn_damage_number(amount: int, is_crit: bool) -> void:
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	add_child(num)
	num.position = Vector2(randf_range(-4, 4), randf_range(-12, -6))
	num.setup(amount, is_crit)


func _die() -> void:
	died.emit()
	EventBus.enemy_defeated.emit(self, data.gold_reward, global_position)
