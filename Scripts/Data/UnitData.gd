class_name UnitData extends Resource

# [신호 정의] 로드맵: 데미지, 체력 변경 알림 [cite: 12]
signal hp_changed(new_hp: int, max_hp: int)
signal damage_taken(amount: int)

# [핵심 변수] 로드맵: 체력, 공격 주기, 이미지 등 [cite: 13]
@export var character_name: String = "Hero"
@export var sprite_texture: Texture2D
@export var max_hp: int = 100
@export var attack_interval: float = 1.0

# 현재 체력은 게임 중 변하므로 export할 필요는 없지만, 디버깅용으로 두기도 합니다.
var current_hp: int:
	set(value):
		current_hp = clamp(value, 0, max_hp)
		hp_changed.emit(current_hp, max_hp) # 값이 변하면 신호 방출

# 초기화 함수
func initialize():
	current_hp = max_hp
