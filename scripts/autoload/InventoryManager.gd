extends Node
## InventoryManager: 파티 공용 인벤토리 관리 (스택 방식)

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)

# 인벤토리: { item_id: quantity }
var items: Dictionary = {}

# 인벤토리 최대 슬롯 (루프히어로처럼 제한 없이 하려면 크게)
const MAX_SLOTS: int = 99


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
	
	# 마을에서만 자동 저장 (필드에서는 전투 중 드랍이 많으니 제외)
	if SaveManager and GameManager and GameManager.current_state == GameManager.GameState.TOWN:
		SaveManager.auto_save("아이템 획득")
	
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
	
	# 마을에서만 자동 저장
	if SaveManager and GameManager and GameManager.current_state == GameManager.GameState.TOWN:
		SaveManager.auto_save("아이템 사용/판매")
	
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
	## 장비 장착 (인벤에서 빼서 영웅에게)
	if not has_item(item_id):
		push_warning("[InventoryManager] 인벤에 없음: " + item_id)
		return false
	
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		# 소비 아이템일 수 있음
		item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			return false
	
	# 이미 장착된 장비가 있으면 인벤으로 돌려보냄
	var current_equip: String = hero.equipment.get(slot, "")
	if not current_equip.is_empty():
		add_item(current_equip, 1)
	
	# 인벤에서 빼고 장착
	remove_item(item_id, 1)
	hero.equipment[slot] = item_id
	
	PartyManager.party_changed.emit()
	
	# 자동 저장
	if SaveManager:
		SaveManager.auto_save("장비 장착")
	
	return true


func unequip_item(hero: RefCounted, slot: String) -> bool:
	## 장비 해제 (영웅에서 빼서 인벤으로)
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


func get_consumable_items() -> Array:
	## 소비 아이템만 반환
	var result: Array = []
	for item_id in items.keys():
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if equip_data.is_empty():
			var item_data: Dictionary = DataManager.get_item(item_id)
			if not item_data.is_empty():
				result.append({
					"id": item_id,
					"quantity": int(items[item_id]),
					"data": item_data
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


#region 유틸리티
func clear() -> void:
	## 인벤토리 초기화
	items.clear()
	inventory_changed.emit()


func add_starting_items() -> void:
	## 시작 아이템 지급
	add_item("potion_small", 3)
#endregion
