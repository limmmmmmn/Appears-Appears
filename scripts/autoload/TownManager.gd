extends Node
## TownManager: 마을 상태 관리 (선술집 영웅 풀 등)

signal tavern_updated
signal explore_result(text: String, effect: Dictionary)

# 선술집에 있는 영웅들 (게임 시작 시 5명 랜덤 배치)
var tavern_heroes: Array[String] = []

# 영입 가능 횟수
var recruit_remaining: int = 3

# 오늘 탐색 횟수 (필드 나갔다 오면 리셋)
var explore_count: int = 0
const MAX_EXPLORE_PER_VISIT: int = 3


func _ready() -> void:
	pass


func init_new_game() -> void:
	## 새 게임 시작 시 호출
	recruit_remaining = 3
	explore_count = 0
	_populate_tavern()


func _populate_tavern() -> void:
	## 선술집에 영웅 5명 배치 (롤랜드 제외)
	tavern_heroes.clear()
	
	var all_heroes := DataManager.get_all_hero_ids()
	var available: Array[String] = []
	
	for hero_id in all_heroes:
		if hero_id != "roland":  # 용사(롤랜드)는 제외
			available.append(hero_id)
	
	# 셔플해서 5명 선택
	available.shuffle()
	for i in range(mini(5, available.size())):
		tavern_heroes.append(available[i])
	
	tavern_updated.emit()


func get_tavern_heroes() -> Array[String]:
	return tavern_heroes


func can_recruit() -> bool:
	return recruit_remaining > 0


func recruit_hero(hero_id: String) -> bool:
	## 영웅 영입
	if not can_recruit():
		return false
	
	if hero_id not in tavern_heroes:
		return false
	
	if PartyManager.get_party().size() >= PartyManager.MAX_PARTY_SIZE:
		return false
	
	# 파티에 추가
	if PartyManager.add_hero_by_id(hero_id):
		tavern_heroes.erase(hero_id)
		recruit_remaining -= 1
		tavern_updated.emit()
		
		# 자동 저장
		if SaveManager:
			SaveManager.auto_save("영웅 영입")
		
		return true
	
	return false


func on_enter_town() -> void:
	## 마을 입장 시 (필드에서 돌아올 때)
	explore_count = 0
	
	# 자동 저장
	if SaveManager:
		SaveManager.auto_save("마을 진입")


func can_explore() -> bool:
	return explore_count < MAX_EXPLORE_PER_VISIT


func do_explore() -> Dictionary:
	## 마을 탐색 실행
	if not can_explore():
		return {"text": "오늘은 충분히 돌아다녔다.", "effect": {"type": "none"}}
	
	explore_count += 1
	
	var events := DataManager.get_town_events()
	if events.is_empty():
		return {"text": "아무 일도 없었다.", "effect": {"type": "none"}}
	
	# 가중치 기반 랜덤 선택
	var total_weight: int = 0
	for event in events:
		total_weight += int(event.get("weight", 10))
	
	var roll := randi() % total_weight
	var cumulative: int = 0
	var selected: Dictionary = events[0]
	
	for event in events:
		cumulative += int(event.get("weight", 10))
		if roll < cumulative:
			selected = event
			break
	
	# 효과 적용
	var effect: Dictionary = selected.get("effect", {})
	_apply_explore_effect(effect)
	
	var result := {
		"text": selected.get("text", ""),
		"effect": effect
	}
	
	explore_result.emit(result["text"], effect)
	return result


func _apply_explore_effect(effect: Dictionary) -> void:
	var effect_type: String = effect.get("type", "none")
	
	match effect_type:
		"gold":
			var min_val: int = int(effect.get("min", 0))
			var max_val: int = int(effect.get("max", 0))
			var amount: int = randi_range(min_val, max_val)
			if amount > 0:
				GameManager.add_gold(amount)
			elif amount < 0:
				GameManager.spend_gold(-amount)
		
		"item":
			var item_id: String = effect.get("item_id", "")
			var count: int = int(effect.get("count", 1))
			if not item_id.is_empty():
				PartyManager.add_item(item_id, count)
		
		"info", "none":
			pass  # 정보나 없음은 텍스트만 표시
