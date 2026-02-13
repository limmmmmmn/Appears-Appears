extends Node
## PartyManager: 파티 구성 및 인벤토리 관리

signal party_changed
signal inventory_changed
signal hero_died(hero: Hero)
signal party_wiped

const MAX_PARTY_SIZE: int = 4
var party: Array[Hero] = []
var reserve_party: Array[Hero] = []
var inventory: Dictionary = {}  # item_id -> 수량

const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]


func _ready() -> void:
	pass


#region 파티 관리
func add_hero_by_id(hero_id: String) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		return false
	var hero := Hero.create_from_id(hero_id)
	if hero.id.is_empty():
		return false
	party.append(hero)
	party_changed.emit()
	return true


func get_party() -> Array[Hero]:
	return party


func get_bench_heroes() -> Array[Hero]:
	## 비전투 대기 영웅 목록
	return reserve_party


func get_hero_at(index: int) -> Hero:
	if index >= 0 and index < party.size():
		return party[index]
	return null


func get_leader() -> Hero:
	for hero in party:
		if not hero.is_dead:
			return hero
	return null


func get_hero_by_id(hero_id: String) -> Hero:
	## ID로 영웅 찾기
	for hero in party:
		if hero.id == hero_id:
			return hero
	return null


func get_alive_heroes() -> Array[Hero]:
	var result: Array[Hero] = []
	for hero in party:
		if not hero.is_dead:
			result.append(hero)
	return result


func get_dead_heroes() -> Array[Hero]:
	var result: Array[Hero] = []
	for hero in party:
		if hero.is_dead:
			result.append(hero)
	return result


func is_party_wiped() -> bool:
	for hero in party:
		if not hero.is_dead:
			return false
	return true
#endregion


#region 파티 스탯
func get_party_average_dex() -> float:
	var alive := get_alive_heroes()
	if alive.is_empty():
		return 0.0
	var total: float = 0.0
	for hero in alive:
		total += hero.get_dex()
	return total / alive.size()


func get_party_average_luk() -> float:
	var alive := get_alive_heroes()
	if alive.is_empty():
		return 0.0
	var total: float = 0.0
	for hero in alive:
		total += hero.get_luk()
	return total / alive.size()
#endregion


#region 전투 처리
func on_hero_damaged(hero: Hero, damage: int) -> void:
	hero.take_damage(damage)
	if hero.is_dead:
		hero_died.emit(hero)
		if is_party_wiped():
			party_wiped.emit()


func full_restore_party() -> void:
	for hero in party:
		hero.full_restore()
	party_changed.emit()
#endregion


#region 인벤토리
func add_item(item_id: String, amount: int = 1) -> void:
	if inventory.has(item_id):
		inventory[item_id] += amount
	else:
		inventory[item_id] = amount
	inventory_changed.emit()


func remove_item(item_id: String, amount: int = 1) -> bool:
	if not inventory.has(item_id) or inventory[item_id] < amount:
		return false
	inventory[item_id] -= amount
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	inventory_changed.emit()
	return true


func get_item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount


func get_all_items() -> Dictionary:
	return inventory.duplicate()
#endregion


#region 장비
func equip_to_hero(hero: Hero, equip_id: String, slot: String) -> bool:
	if not hero.can_equip(equip_id):
		return false
	if not remove_item(equip_id):
		return false
	
	var old_equip := hero.equip_item(equip_id, slot)
	if not old_equip.is_empty():
		add_item(old_equip)
	
	var equip_data: Dictionary = DataManager.get_equipment(equip_id)
	if equip_data.get("two_handed", false) and slot == "main_hand":
		var old_off: String = hero.equipment["off_hand"]
		if not old_off.is_empty():
			add_item(old_off)
			hero.equipment["off_hand"] = ""
	
	party_changed.emit()
	return true


func unequip_from_hero(hero: Hero, slot: String) -> bool:
	var old_equip := hero.unequip_slot(slot)
	if old_equip.is_empty():
		return false
	add_item(old_equip)
	party_changed.emit()
	return true


func auto_equip_to_party(equip_id: String) -> bool:
	var equip_data: Dictionary = DataManager.get_equipment(equip_id)
	if equip_data.is_empty():
		return false
	
	var slot: String = Hero.normalize_equipment_slot(str(equip_data.get("slot", "")))
	if slot == "acc":
		for hero in party:
			if hero.can_equip(equip_id):
				for s in ["acc1", "acc2"]:
					if hero.equipment[s].is_empty():
						return equip_to_hero(hero, equip_id, s)
	elif slot == "main_hand":
		for hero in party:
			if not hero.can_equip(equip_id):
				continue
			if hero.equipment["main_hand"].is_empty():
				if equip_data.get("two_handed", false):
					if hero.equipment["off_hand"].is_empty():
						return equip_to_hero(hero, equip_id, "main_hand")
				else:
					return equip_to_hero(hero, equip_id, "main_hand")
			elif hero.can_dual_wield() and hero.equipment["off_hand"].is_empty() and not hero.is_off_hand_disabled():
				return equip_to_hero(hero, equip_id, "off_hand")
	else:
		for hero in party:
			if hero.can_equip(equip_id) and hero.equipment[slot].is_empty():
				if equip_data.get("two_handed", false):
					if hero.equipment["off_hand"].is_empty():
						return equip_to_hero(hero, equip_id, slot)
				else:
					return equip_to_hero(hero, equip_id, slot)
	return false
#endregion


func print_party_status() -> void:
	pass
