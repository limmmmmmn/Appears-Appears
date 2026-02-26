extends Node
## PartyManager: 파티 구성 및 인벤토리 관리

signal party_changed
signal inventory_changed
signal hero_died(hero: Hero)
signal party_wiped
signal synergies_updated(active_synergies: Array)
signal unite_attack_updated(unite_attack_id: String)

const MAX_PARTY_SIZE: int = 4
var party: Array[Hero] = []
var reserve_party: Array[Hero] = []
var inventory: Dictionary = {}  # item_id -> 수량

const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# === 시너지 & 합체공격 ===
var active_synergies: Array = []        # 발동 중인 시너지 ID 목록
var current_unite_attack: String = ""   # 현재 매칭된 합체공격 ID
var discovered_synergies: Dictionary = {}     # synergy_id -> true (한번이라도 발동한 것)
var discovered_unite_attacks: Dictionary = {} # unite_id -> true


func _ready() -> void:
	party_changed.connect(_on_party_changed_check_composition)


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
	## 비전투 대기 용사 목록
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
	## ID로 용사 찾기
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
		party_changed.emit()
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


#region 시너지 & 합체공격
func _on_party_changed_check_composition() -> void:
	## 파티 변경 시 시너지/합체공격 재계산
	refresh_synergies_and_unite()


func refresh_synergies_and_unite() -> void:
	## 현재 파티 기준으로 시너지/합체공격 갱신
	active_synergies = _evaluate_synergies()
	current_unite_attack = _evaluate_unite_attack()
	synergies_updated.emit(active_synergies)
	unite_attack_updated.emit(current_unite_attack)


func _evaluate_synergies() -> Array:
	## 모든 시너지 조건 체크, 충족하는 것 전부 반환
	var result: Array = []
	if party.is_empty():
		return result
	var all_synergies: Dictionary = DataManager.get_all_synergies()
	for synergy_id in all_synergies:
		var synergy_data: Dictionary = all_synergies[synergy_id]
		var condition: Dictionary = synergy_data.get("condition", {})
		if _check_condition(condition):
			result.append(str(synergy_id))
			discovered_synergies[str(synergy_id)] = true
	return result


func _evaluate_unite_attack() -> String:
	## 조건 충족하는 합체공격 중 priority 최고인 것 선택 (4인 파티 필수)
	if party.size() < MAX_PARTY_SIZE:
		return ""
	var all_unites: Dictionary = DataManager.get_all_unite_attacks()
	var best_id: String = ""
	var best_priority: int = -1
	for unite_id in all_unites:
		var unite_data: Dictionary = all_unites[unite_id]
		var condition: Dictionary = unite_data.get("condition", {})
		var priority: int = int(unite_data.get("priority", 0))
		if condition.get("type", "") == "default":
			if best_id.is_empty():
				best_id = str(unite_id)
				best_priority = priority
			continue
		if _check_condition(condition) and priority > best_priority:
			best_id = str(unite_id)
			best_priority = priority
			discovered_unite_attacks[str(unite_id)] = true
	if best_id.is_empty():
		best_id = "default_unite"
	return best_id


func _check_condition(condition: Dictionary) -> bool:
	## 시너지/합체공격 조건 체크 (공용)
	var cond_type: String = str(condition.get("type", ""))
	match cond_type:
		"class_all":
			return _check_class_all(condition)
		"tag_count":
			return _check_tag_count(condition)
		"hero_ids":
			return _check_hero_ids(condition)
		"default":
			return true
		_:
			return false


func _check_class_all(condition: Dictionary) -> bool:
	## 필요한 클래스를 모두 가진 파티원이 있는지 체크
	var required: Array = condition.get("required_classes", [])
	if required.is_empty():
		return false
	for req_class in required:
		var found := false
		for hero in party:
			if hero.class_id == str(req_class):
				found = true
				break
		if not found:
			return false
	return true


func _check_tag_count(condition: Dictionary) -> bool:
	## 특정 태그를 가진 파티원 수 체크 (tags + hidden_tags + class tags)
	var tag: String = str(condition.get("tag", ""))
	var min_count: int = int(condition.get("min_count", 1))
	if tag.is_empty():
		return false
	var count: int = 0
	for hero in party:
		if hero.has_tag(tag):
			count += 1
	return count >= min_count


func _check_hero_ids(condition: Dictionary) -> bool:
	## 특정 캐릭터 ID 조합 체크
	var required_ids: Array = condition.get("required_ids", [])
	if required_ids.is_empty():
		return false
	for req_id in required_ids:
		var found := false
		for hero in party:
			if hero.id == str(req_id):
				found = true
				break
		if not found:
			return false
	return true


func get_active_synergy_data() -> Array:
	## 활성 시너지의 전체 데이터 반환
	var result: Array = []
	for synergy_id in active_synergies:
		var data: Dictionary = DataManager.get_synergy(synergy_id)
		if not data.is_empty():
			result.append(data)
	return result


func get_current_unite_attack_data() -> Dictionary:
	## 현재 합체공격 데이터 반환
	if current_unite_attack.is_empty():
		return {}
	return DataManager.get_unite_attack(current_unite_attack)


func get_synergy_effects() -> Array:
	## 모든 활성 시너지의 effects를 평탄화하여 반환
	var result: Array = []
	for synergy_id in active_synergies:
		var data: Dictionary = DataManager.get_synergy(synergy_id)
		var effects: Array = data.get("effects", [])
		result.append_array(effects)
	return result


func is_synergy_uses_hidden_tag(synergy_id: String) -> bool:
	## 해당 시너지가 히든 태그로 발동하는지 체크
	var data: Dictionary = DataManager.get_synergy(synergy_id)
	var condition: Dictionary = data.get("condition", {})
	if condition.get("type", "") != "tag_count":
		return false
	var tag: String = str(condition.get("tag", ""))
	if tag.is_empty():
		return false
	# 파티원 중 해당 태그가 hidden_tags에만 있는 캐릭터가 있으면 히든
	for hero in party:
		if tag in hero.hidden_tags and tag not in hero.tags:
			var class_data: Dictionary = DataManager.get_class_data(hero.class_id)
			var class_tags: Array = class_data.get("tags", [])
			if tag not in class_tags:
				return true
	return false


func is_unite_uses_hidden_tag(unite_id: String) -> bool:
	## 해당 합체공격이 히든 태그로 발동하는지 체크
	var data: Dictionary = DataManager.get_unite_attack(unite_id)
	var condition: Dictionary = data.get("condition", {})
	if condition.get("type", "") != "tag_count":
		return false
	var tag: String = str(condition.get("tag", ""))
	if tag.is_empty():
		return false
	for hero in party:
		if tag in hero.hidden_tags and tag not in hero.tags:
			var class_data: Dictionary = DataManager.get_class_data(hero.class_id)
			var class_tags: Array = class_data.get("tags", [])
			if tag not in class_tags:
				return true
	return false


func get_party_average_stat(stat: String) -> float:
	## 파티 전원의 특정 스탯 평균
	if party.is_empty():
		return 0.0
	var total: float = 0.0
	for hero in party:
		match stat:
			"str":
				total += hero.get_str()
			"int", "wis":
				total += hero.get_int()
			"dex", "agi":
				total += hero.get_dex()
			"luk":
				total += hero.get_luk()
			"atk":
				total += hero.get_atk()
			"def":
				total += hero.get_def()
			_:
				total += hero.get_str()
	return total / float(party.size())
#endregion


func _reorder_party_alive_first() -> void:
	if party.is_empty():
		return
	var alive: Array[Hero] = []
	var dead: Array[Hero] = []
	for h in party:
		if h == null:
			continue
		if h.is_dead:
			dead.append(h)
		else:
			alive.append(h)
	party.clear()
	party.append_array(alive)
	party.append_array(dead)
