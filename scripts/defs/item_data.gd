# scripts/defs/item_data.gd
extends Resource
class_name ItemData

enum ItemType { WEAPON, ARMOR, ACCESSORY, CONSUMABLE }
# JobClass는 아직 구현 안 했으므로 일단 주석 처리하거나 String으로 대체
# enum JobClass { WARRIOR, MAGE, ... }

@export var item_name: String
@export var type: ItemType
# @export var allowed_jobs: Array[JobClass] = [] 
@export var stat_bonuses: StatsData # 기존에 만든 StatsData 재사용
