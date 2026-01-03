# res://Scripts/Globals/GameSettings.gd
extends Node

var battle_speed: float = 1.0 # 전투 진행 속도 (기본 1배) [cite: 56]

# 파티 공용 자산
var current_gold: int = 0
var inventory: Array[String] = [] # 아이템 이름(또는 ID)을 저장하는 가방


func set_speed(speed: float):
	battle_speed = speed
	

# 골드 조작 함수
func add_gold(amount: int):
	current_gold += amount
	# 골드가 바뀌었다고 방송 (UI 갱신용)
	SignalBus.gold_updated.emit(current_gold)

func add_item(item_name: String):
	inventory.append(item_name)
	print("획득 아이템: " + item_name)
	# 나중에 인벤토리 UI 갱신 신호도 필요하면 추가
