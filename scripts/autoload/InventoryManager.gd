extends Node
## InventoryManager: 파티 공용 인벤토리 관리 (스택 방식)

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal item_equipped(hero_name: String, item_id: String, slot: String, replaced_id: String)
signal item_auto_equipped(hero_name: String, item_id: String, slot: String, replaced_id: String)

# 인벤토리: { item_id: quantity }
var items: Dictionary = {}

# 인벤토리 최대 슬롯 (루프히어로처럼 제한 없이 하려면 크게)
const MAX_SLOTS: int = 99

# 장비 타입 -> 한글 이름 매핑
const ITEM_TYPE_NAMES: Dictionary = {
	"sword": "검",
	"dagger": "단검",
	"staff": "지팡이",
	"bow": "활",
	"axe": "도끼",
	"mace": "철퇴",
	"spear": "창",
	"shield": "방패",
	"armor": "갑옷",
	"robe": "로브",
	"light_armor": "경갑",
	"helmet": "투구",
	"hat": "모자",
	"gloves": "장갑",
	"boots": "신발",
	"ring": "반지",
	"amulet": "목걸이",
}

# 희귀도 -> 색상 매핑
const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),      # 회색
	"uncommon": Color(0.4, 0.8, 0.4),    # 초록
	"magic": Color(0.4, 0.6, 1.0),       # 파랑
	"rare": Color(0.8, 0.5, 1.0),        # 보라
	"epic": Color(1.0, 0.5, 0.2),        # 주황
	"legendary": Color(1.0, 0.8, 0.2),   # 금색
}


func _ready() -> void:
	pass


#region 아이템 추가/제거
func add_item(item_id: String, quantity: int = 1) -> bool:
	## 아이템 추가
	if item_id.is_empty() or quantity <= 0:
		return false
	
	if items.has(item_id):
		items[item_id] = int(items[item_id]) + quantity
	else:
		if get_unique_item_count() >= MAX_SLOTS:
			push_warning("[InventoryManager] 인벤토리 가득 참!")
			return false
		items[item_id] = quantity
	
	item_added.emit(item_id, quantity)
	inventory_changed.emit()
	
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	## 아이템 제거
	if not items.has(item_id):
		return false
	
	var current: int = int(items[item_id])
	if current < quantity:
		return false
	
	items[item_id] = current - quantity
	if items[item_id] <= 0:
		items.erase(item_id)
	
	item_removed.emit(item_id, quantity)
	inventory_changed.emit()
	
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	## 아이템 보유 확인
	if not items.has(item_id):
		return false
	return int(items[item_id]) >= quantity


func get_quantity(item_id: String) -> int:
	## 아이템 수량 확인
	return int(items.get(item_id, 0))
#endregion


#region 장비 장착/해제
func equip_item(hero: RefCounted, item_id: String, slot: String) -> bool:
	## 장비 장착 (인벤에서 빼서 용사에게)
	if not has_item(item_id):
		push_warning("[InventoryManager] 인벤에 없음: " + item_id)
		return false
	
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		# 소비 아이템일 수 있음
		item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			return false

	var target_slot: String = _resolve_target_slot(hero, item_data, slot)
	if target_slot.is_empty() or not hero.equipment.has(target_slot):
		return false
	if target_slot == "off_hand" and hero.is_off_hand_disabled():
		return false

	# 이미 장착된 장비가 있으면 인벤으로 돌려보냄
	var current_equip: String = hero.equipment.get(target_slot, "")
	if not current_equip.is_empty():
		add_item(current_equip, 1)

	# 인벤에서 빼고 장착
	remove_item(item_id, 1)
	hero.equipment[target_slot] = item_id
	if item_data.get("two_handed", false) and target_slot == "main_hand":
		var old_off: String = str(hero.equipment.get("off_hand", ""))
		if not old_off.is_empty():
			add_item(old_off, 1)
			hero.equipment["off_hand"] = ""
	item_equipped.emit(hero.hero_name, item_id, target_slot, current_equip)
	
	PartyManager.party_changed.emit()
	
	# 자동 저장
	if SaveManager:
		SaveManager.auto_save("장비 장착")
	
	return true


func unequip_item(hero: RefCounted, slot: String) -> bool:
	## 장비 해제 (용사에서 빼서 인벤으로)
	var equip_id: String = hero.equipment.get(slot, "")
	if equip_id.is_empty():
		return false
	
	# 인벤으로 이동
	if not add_item(equip_id, 1):
		push_warning("[InventoryManager] 인벤 가득 참 - 해제 불가")
		return false
	
	hero.equipment[slot] = ""
	
	PartyManager.party_changed.emit()
	
	# 자동 저장
	if SaveManager:
		SaveManager.auto_save("장비 해제")
	
	return true
#endregion


#region 조회
func get_all_items() -> Array:
	## 모든 아이템 목록 반환 [{id, quantity, data}, ...]
	var result: Array = []
	for item_id in items.keys():
		var quantity: int = int(items[item_id])
		var data: Dictionary = DataManager.get_equipment(item_id)
		if data.is_empty():
			data = DataManager.get_item(item_id)
		
		result.append({
			"id": item_id,
			"quantity": quantity,
			"data": data
		})
	return result


func get_equipment_items() -> Array:
	## 장비 아이템만 반환
	var result: Array = []
	for item_id in items.keys():
		var data: Dictionary = DataManager.get_equipment(item_id)
		if not data.is_empty():
			result.append({
				"id": item_id,
				"quantity": int(items[item_id]),
				"data": data
			})
	return result




func get_unique_item_count() -> int:
	## 고유 아이템 종류 수
	return items.size()


func get_total_item_count() -> int:
	## 전체 아이템 개수
	var total: int = 0
	for qty in items.values():
		total += int(qty)
	return total
#endregion


#region 아이템 정보
func get_item_type_name(item_id: String) -> String:
	## 아이템 타입의 한글 이름 반환
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		data = DataManager.get_item(item_id)

	var item_type: String = data.get("type", "unknown")
	var slot: String = data.get("slot", "")

	# slot 기반으로 먼저 확인
	if slot == "main_hand":
		item_type = data.get("type", "weapon")
	elif slot == "off_hand":
		item_type = data.get("type", "shield")
	elif slot in ["body", "head", "hands", "feet"]:
		item_type = data.get("type", slot)
	elif _is_accessory_slot(slot):
		item_type = "amulet"

	return ITEM_TYPE_NAMES.get(item_type, item_type)


func get_rarity_color(item_id: String) -> Color:
	## 아이템 희귀도 색상 반환
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		data = DataManager.get_item(item_id)

	var rarity: String = data.get("rarity", "common")
	return RARITY_COLORS.get(rarity, Color.WHITE)
#endregion


#region 자동 장착
func try_auto_equip(item_id: String) -> bool:
	## 아이템 자동 장착 시도
	## 반환: 장착 성공 여부
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		return false  # 장비가 아님

	var item_slot: String = item_data.get("slot", "")
	if item_slot.is_empty():
		return false

	var party: Array = PartyManager.get_party() if PartyManager else []
	if party.is_empty():
		return false

	# 1단계: 빈 슬롯에 장착 시도 (파티 순서대로)
	for hero in party:
		if hero == null:
			continue
		if not hero.can_equip(item_id):
			continue

		# 해당 슬롯이 비어있는지 확인
		var slots_to_check: Array = _get_slots_for_item(item_slot, hero)
		for slot in slots_to_check:
			var current: String = hero.equipment.get(slot, "")
			if current.is_empty():
				# 빈 슬롯 발견! 장착
				_do_auto_equip(hero, item_id, slot, "")
				return true

	# 2단계: 더 강한 아이템이면 교체 (파티 순서대로)
	var new_power: int = _calculate_item_power(item_id)

	for hero in party:
		if hero == null:
			continue
		if not hero.can_equip(item_id):
			continue

		var slots_to_check: Array = _get_slots_for_item(item_slot, hero)
		for slot in slots_to_check:
			var current: String = hero.equipment.get(slot, "")
			if current.is_empty():
				continue

			var current_power: int = _calculate_item_power(current)
			if new_power > current_power:
				# 더 강한 아이템! 교체
				_do_auto_equip(hero, item_id, slot, current)
				return true

	return false


func _get_slots_for_item(item_slot: String, hero: Hero) -> Array:
	## 아이템이 장착될 수 있는 슬롯 목록 반환
	if _is_accessory_slot(item_slot):
		return ["acc1", "acc2"]
	elif item_slot == "main_hand":
		if hero.can_dual_wield() and not hero.is_off_hand_disabled():
			return ["main_hand", "off_hand"]
		return ["main_hand"]
	elif item_slot == "off_hand":
		# 양손무기 체크
		if hero.is_off_hand_disabled():
			return []
		return ["off_hand"]
	else:
		return [item_slot]


func _is_accessory_slot(slot: String) -> bool:
	var normalized: String = Hero.normalize_equipment_slot(slot)
	return normalized == "acc"


func _resolve_target_slot(hero: Hero, item_data: Dictionary, requested_slot: String) -> String:
	var req_norm: String = Hero.normalize_equipment_slot(requested_slot)
	if req_norm == "acc":
		req_norm = "acc1"

	var item_slot: String = str(item_data.get("slot", ""))
	var item_norm: String = Hero.normalize_equipment_slot(item_slot)

	if item_norm == "acc":
		if req_norm in ["acc1", "acc2"]:
			return req_norm
		if str(hero.equipment.get("acc1", "")).is_empty():
			return "acc1"
		if str(hero.equipment.get("acc2", "")).is_empty():
			return "acc2"
		return "acc1"

	if item_norm == "main_hand":
		if req_norm == "off_hand" and hero.can_dual_wield():
			return "off_hand"
		return "main_hand"

	if item_norm == "off_hand":
		return "off_hand"

	return item_norm


func _calculate_item_power(item_id: String) -> int:
	## 아이템의 총 스탯 파워 계산
	if item_id.is_empty():
		return 0

	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return 0

	var stats: Dictionary = data.get("stats", {})
	var power: int = 0

	# 모든 스탯 합산 (가중치 적용)
	power += int(stats.get("hp", 0)) / 5  # HP는 5로 나눔
	power += int(stats.get("str", 0)) * 2
	power += int(stats.get("def", 0)) * 2
	power += int(stats.get("int", 0)) * 2
	power += int(stats.get("dex", 0)) * 2
	power += int(stats.get("luk", 0))
	power += int(stats.get("atk", 0)) * 2

	# 희귀도 보너스
	var rarity: String = data.get("rarity", "common")
	match rarity:
		"magic": power += 5
		"rare": power += 15
		"unique": power += 30
		"legendary": power += 50

	return power


func _do_auto_equip(hero: Hero, item_id: String, slot: String, replaced_id: String) -> void:
	## 실제 자동 장착 수행
	# 인벤에서 제거
	remove_item(item_id, 1)

	# 기존 장비를 인벤으로 (교체인 경우)
	if not replaced_id.is_empty():
		add_item(replaced_id, 1)

	# 새 장비 장착
	hero.equipment[slot] = item_id

	# 시그널 발송 (알림 UI용)
	item_equipped.emit(hero.hero_name, item_id, slot, replaced_id)
	item_auto_equipped.emit(hero.hero_name, item_id, slot, replaced_id)

	PartyManager.party_changed.emit()
#endregion


#region 유틸리티
func clear() -> void:
	## 인벤토리 초기화
	items.clear()
	inventory_changed.emit()


func add_starting_items() -> void:
	## 시작 아이템 지급
	pass
#endregion
