extends Node

# 파티 인벤토리
var inventory: Array[ItemData] = []
var gold: int = 0

# 리더의 레벨을 반환 (적 AI가 도망갈지 말지 결정할 때 사용)
func get_leader_level() -> int:
	# 파티 유닛 그룹의 첫 번째 멤버를 리더로 가정
	var leader = get_tree().get_first_node_in_group("PartyUnit")
	if leader and leader.unit_data:
		# 현재는 레벨 시스템이 없으므로 임시로 1 반환하거나 스탯 기반 계산
		return 1 
	return 1

func add_item(item: ItemData) -> void:
	inventory.append(item)
	SignalBus.on_inventory_updated.emit()
	SignalBus.on_log_message.emit("%s 획득!" % item.item_name, Color.GREEN)
