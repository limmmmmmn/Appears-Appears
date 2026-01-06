class_name ItemPool extends Resource
# 마을 상점에서 판매할 아이템 목록
@export var items: Array[ItemData] = []

# 특정 개수만큼 랜덤하게 진열하거나 전체를 보여줄 때 사용
func get_inventory() -> Array[ItemData]:
	return items
