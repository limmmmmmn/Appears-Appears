class_name UnitRuntime
# Node 상속 안 함 (가벼운 객체)

var def: CombatantDef  # 원본 데이터 참조 (읽기 전용) [cite: 55]
var id: String         # 편의상 ID 보관 [cite: 63]

# 가변 상태 (여기에만 존재해야 함) [cite: 57, 59]
var current_hp: int
var level: int = 1
var exp: int = 0

func _init(_def: CombatantDef):
	def = _def
	id = _def.id
	current_hp = def.base_stats.get("hp", 100) # 초기화
