# scripts/autoload/GameManager.gd
extends Node

signal party_changed
signal inventory_changed
signal gold_changed(new_gold: int)
signal level_up(hero_id: String)

# 파티
var party: Array = []

# 인벤토리
var inventory: Array = []
var inventory_max: int = 20

# 골드
var gold: int = 1000

# 레벨
var party_level: int = 1
var current_exp: int = 0
var exp_to_next_level: int = 100

# 스테이지
var current_stage: int = 1

# 통계
var total_kills: int = 0
var total_gold_earned: int = 0
var total_items_found: int = 0

func _ready() -> void:
	print("[GameManager] Ready!")

# ========================================
# 파티 관리
# ========================================

func add_to_party(hero_id: String) -> bool:
	if party.size() >= 4:
		return false
	
	var hero_data = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return false
	
	var hero_instance = hero_data.duplicate(true)
	hero_instance["current_hp"] = hero_instance.base_stats.hp
	hero_instance["level"] = 1
	hero_instance["equipped"] = {}
	
	party.append(hero_instance)
	party_changed.emit()
	print("Party +: ", hero_instance.name)
	return true

func remove_from_party(hero: Dictionary) -> void:
	party.erase(hero)
	party_changed.emit()

# ========================================
# 인벤토리
# ========================================

func add_item(item_id: String) -> bool:
	if inventory.size() >= inventory_max:
		return false
	
	var item_data = DataManager.get_item(item_id)
	if item_data.is_empty():
		return false
	
	inventory.append(item_data)
	inventory_changed.emit()
	total_items_found += 1
	print("Item +: ", item_data.name)
	return true

func remove_item(item: Dictionary) -> void:
	inventory.erase(item)
	inventory_changed.emit()

# ========================================
# 골드
# ========================================

func add_gold(amount: int) -> void:
	gold += amount
	total_gold_earned += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

# ========================================
# 경험치 & 레벨업
# ========================================

func add_exp(amount: int) -> void:
	current_exp += amount
	
	while current_exp >= exp_to_next_level:
		level_up_party()

func level_up_party() -> void:
	party_level += 1
	current_exp -= exp_to_next_level
	exp_to_next_level = int(exp_to_next_level * 1.5)
	
	print("=== LEVEL UP! Lv.%d ===" % party_level)
	
	for hero in party:
		hero.level += 1
		var growth = hero.growth_rates
		hero.base_stats.hp += growth.hp
		hero.base_stats.attack += growth.attack
		hero.base_stats.defense += growth.defense
		hero.current_hp = hero.base_stats.hp
	
	level_up.emit("")

# ========================================
# 전투
# ========================================

func on_enemy_killed():
	total_kills += 1

# ========================================
# 회복
# ========================================

func heal_party_full() -> void:
	for hero in party:
		hero.current_hp = hero.base_stats.hp

# ========================================
# 게임 리셋
# ========================================

func reset_game() -> void:
	print("[GameManager] Resetting game...")
	
	party.clear()
	inventory.clear()
	gold = 1000
	party_level = 1
	current_exp = 0
	exp_to_next_level = 100
	current_stage = 1
	total_kills = 0
	total_gold_earned = 0
	total_items_found = 0
	
	party_changed.emit()
	inventory_changed.emit()
	gold_changed.emit(gold)

# ========================================
# 테스트
# ========================================

func setup_test_party() -> void:
	print("=== Test Party ===")
	add_to_party("hero_001")
	add_to_party("hero_002")
	add_to_party("hero_003")
