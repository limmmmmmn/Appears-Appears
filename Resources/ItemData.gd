# res://Resources/ItemData.gd
extends Resource
class_name ItemData

# 1. 아이템 종류 명찰 (다시 부활!)
enum ItemType { CONSUMABLE, EQUIPMENT, ETC }

@export_group("기본 정보")
@export var item_name: String = "Item"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var price: int = 100

# 2. 내 타입이 뭔지 저장하는 변수
# (기본값은 ETC / 자식들이 태어날 때 알아서 바꿀 것임)
@export var type: ItemType = ItemType.ETC
