extends Node
## ATBManager: 전투 액션 시그널 허브
## - 각 전투창이 독립적으로 턴을 관리
## - 이 노드는 UI 업데이트용 시그널만 제공

signal action_executed  # 액션 실행됨 (RightPartyPanel 쿨다운 업데이트용)


func _ready() -> void:
	pass


func initialize_battle() -> void:
	## 레거시 호환 (각 전투창이 자체적으로 턴 시작)
	pass


func reset() -> void:
	## 레거시 호환
	pass


func set_paused(_paused: bool) -> void:
	## 레거시 호환
	pass
