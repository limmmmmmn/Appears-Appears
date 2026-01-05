extends Resource
class_name ItemData

# [설계도 82, 네이밍 사전 12] 아이템 이름
@export var item_name: String
# [설계도 83] 타입 (Enum 사용)
@export var type: GameConstants.ItemType
# [설계도 84] 착용 가능 직업
@export var allowed_jobs: Array[GameConstants.JobClass]
# [설계도 85] 스탯 보너스 (Dictionary)
@export var stat_bonuses: Dictionary = {"atk": 0, "def": 0, "hp": 0}
