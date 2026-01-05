class_name UnitRuntime extends RefCounted
# [Blueprint v1.4] 4. 런타임 상태 - 동적 데이터 관리 [cite: 33]

# 원본 데이터 참조 (Read-only 권장)
var _data: UnitData

# 가변 상태 (현재 HP 등)
var current_hp: int
var is_dead: bool = false

# 초기화: 데이터를 주입받아 실시간 객체 생성
func _init(p_data: UnitData) -> void:
	_data = p_data
	current_hp = _data.base_hp

# 데이터 접근 래퍼 (Wrapper) - 필요 시 버프/디버프 연산 추가 용이
func get_speed() -> float:
	return _data.base_speed

func get_texture() -> Texture2D:
	return _data.texture
