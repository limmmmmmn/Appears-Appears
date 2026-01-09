class_name UnitRuntime
extends RefCounted

# 지침서 5. Runtime 객체 규칙 [cite: 131]
var def: UnitData       # 원본 데이터 참조
var id: String          # 저장/로드용 ID (반반 전략) [cite: 138]

# 변하는 값 (가변 데이터)
var current_hp: int
var level: int = 1
var exp: int = 0

# 초기화 함수: 데이터를 받아서 런타임 객체 생성
func _init(_def: UnitData):
	def = _def
	id = _def.id
	
	# 초기 스탯 설정 (나중에 레벨업 공식 적용)
	current_hp = def.base_hp
	level = 1
	exp = 0

# 기획서 3.4: HP가 0이면 사망 [cite: 226]
func is_dead() -> bool:
	return current_hp <= 0
