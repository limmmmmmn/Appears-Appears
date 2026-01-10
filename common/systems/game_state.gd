extends Node

# 절대 규칙: 여기에는 상태 변수만 둔다. 로직(AI, 계산) 금지. [cite: 31, 42]

var currency: int = 0
var inventory: Array = []
var progress: Dictionary = {}

# 파티와 대기실 [cite: 34]
var party: Array[UnitRuntime] = [] 
var roster: Array[UnitRuntime] = [] 

# 현재 활성화된 전투 인스턴스 목록 (관리용)
var active_battles: Array = []
