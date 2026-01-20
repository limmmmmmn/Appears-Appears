extends RefCounted
class_name Enemy
## Enemy: 적 인스턴스 데이터 관리

var id: String = ""
var enemy_name: String = ""
var enemy_type: String = ""  # normal, elite, boss

var max_hp: int = 0
var max_mp: int = 0
var str_stat: int = 0
var def_stat: int = 0
var int_stat: int = 0
var spd_stat: int = 0
var luk_stat: int = 0

var current_hp: int = 0
var current_mp: int = 0
var is_dead: bool = false

var exp_reward: int = 0
var gold_min: int = 0
var gold_max: int = 0
var drop_table: Array = []
var skills: Array = []
var sprite: String = ""
var tags: Array = []

var battle_uid: int = 0
static var _uid_counter: int = 0


static func create_from_id(enemy_id: String) -> Enemy:
	var enemy := Enemy.new()
	enemy._initialize(enemy_id)
	return enemy


func _initialize(enemy_id: String) -> void:
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		return
	
	_uid_counter += 1
	battle_uid = _uid_counter
	
	id = enemy_id
	enemy_name = data.get("name", "Unknown")
	enemy_type = data.get("type", "normal")
	sprite = data.get("sprite", "")
	tags = data.get("tags", [])
	skills = data.get("skills", ["basic_attack"])
	
	var stats: Dictionary = data.get("base_stats", {})
	max_hp = int(stats.get("hp", 10))
	max_mp = int(stats.get("mp", 0))
	str_stat = int(stats.get("str", 5))
	def_stat = int(stats.get("def", 5))
	int_stat = int(stats.get("int", 5))
	spd_stat = int(stats.get("spd", 5))
	luk_stat = int(stats.get("luk", 5))
	
	current_hp = max_hp
	current_mp = max_mp
	
	var rewards: Dictionary = data.get("rewards", {})
	exp_reward = int(rewards.get("exp", 0))
	gold_min = int(rewards.get("gold_min", 0))
	gold_max = int(rewards.get("gold_max", 0))
	drop_table = data.get("drop_table", [])


func get_atk() -> int:
	return str_stat

func get_p_def() -> int:
	return def_stat

func get_m_def() -> int:
	return int_stat

func get_eva() -> float:
	return spd_stat * 0.5 + luk_stat * 0.2

func get_crit() -> float:
	return luk_stat * 0.5 + 5.0


func take_damage(amount: int) -> int:
	var actual := maxi(1, amount)
	current_hp = maxi(0, current_hp - actual)
	if current_hp <= 0:
		is_dead = true
	return actual


func calculate_gold_drop() -> int:
	if gold_max <= gold_min:
		return gold_min
	return randi_range(gold_min, gold_max)


func calculate_drops(luk_bonus: float = 0.0) -> Array:
	var results: Array = []
	for drop_info in drop_table:
		var item_id: String = drop_info.get("item_id", "")
		var base_chance: float = drop_info.get("chance", 0.0)
		var final_chance: float = base_chance * (1.0 + luk_bonus / 100.0)
		results.append({"item_id": item_id, "dropped": randf() < final_chance})
	return results


func is_boss() -> bool:
	return enemy_type == "boss"

func is_elite() -> bool:
	return enemy_type == "elite"

func get_hp_percent() -> float:
	return float(current_hp) / float(max_hp)
