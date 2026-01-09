extends Node

# 지침서 3. GameState 구조 확정 [cite: 108, 109]
var currency: int = 0

# 파티: 현재 전투에 참여하는 인원 (최대 4명)
# 배열의 요소는 UnitRuntime 객체 [cite: 109]
var party: Array[UnitRuntime] = []

# 로스터: 대기 중인 모든 동료 (108명 풀)
# ★중요: 대기실 동료도 UnitRuntime으로 관리하여 상태 유지 [cite: 112]
var roster: Array[UnitRuntime] = []

# 인벤토리 및 진행도 (추후 확장)
var inventory: Array = []
var current_stage: int = 1

# 초기화 (테스트용)
func _ready():
	print("✅ GameState Initialized")
