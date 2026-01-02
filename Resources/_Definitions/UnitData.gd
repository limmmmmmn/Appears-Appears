# res://Resources/_Definitions/UnitData.gd
class_name UnitData
extends Resource

@export_group("Identity")
@export var id: String = ""
@export var name: String = "Unknown"
@export var texture: Texture2D

@export_group("Stats")
@export var max_hp: int = 100
@export var current_hp: int = 100
@export var attack_power: int = 10
@export var agility: int = 10       # 쿨타임 속도에 영향 [cite: 7]
@export var base_defense: int = 0

@export_group("Equipment")
@export var weapon_speed: float = 1.0 # 낮을수록 빠름 (기본 1.0초) [cite: 7]

# 런타임 계산용 함수들
func is_dead() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> int:
	var damage = max(1, amount - base_defense)
	current_hp = max(0, current_hp - damage)
	return damage

# 전투 종료 후 상태 저장을 위한 함수
func sync_hp(new_hp: int):
	current_hp = new_hp
