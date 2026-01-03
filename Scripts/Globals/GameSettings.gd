# res://Scripts/Globals/GameSettings.gd
extends Node

var battle_speed: float = 1.0 # 전투 진행 속도 (기본 1배) [cite: 56]

# 파티 공용 자산
var current_gold: int = 0

# [변경] 이제 문자열이 아니라 'ItemData' 리소스를 담습니다!
var inventory: Array[ItemData] = []

func set_speed(speed: float):
	battle_speed = speed
	

# 골드 조작 함수
func add_gold(amount: int):
	current_gold += amount
	# 골드가 바뀌었다고 방송 (UI 갱신용)
	SignalBus.gold_updated.emit(current_gold)

# [NEW] 아이템 획득 함수
func add_item(item: ItemData):
	inventory.append(item)
	print("인벤토리 추가: " + item.name)

# [NEW] 아이템 삭제 함수 (장착할 때 씀)
func remove_item(item: ItemData):
	if item in inventory:
		inventory.erase(item)
