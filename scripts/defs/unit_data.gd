class_name UnitData extends Resource
# [Blueprint v1.4] 3. 데이터 카드 - 정적 데이터 정의 [cite: 24]

@export_group("Identity")
@export var id: String = "unit_001"
@export var name: String = "Unknown"
@export var texture: Texture2D # 월드 및 전투 창 공용 스프라이트

@export_group("Base Stats")
@export var base_hp: int = 100
@export var base_speed: float = 150.0 # 필드 이동 속도
