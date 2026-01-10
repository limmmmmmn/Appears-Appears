class_name TownDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""

# [마을 기능 설정]
@export var shop_table_id: String = ""    # 상점 물품 테이블 ID
@export var recruit_table_id: String = "" # 영입 가능한 영웅 테이블 ID
@export var heal_cost: int = 10           # 회복 비용
