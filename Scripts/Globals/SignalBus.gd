# res://Scripts/Globals/SignalBus.gd
extends Node

# UI 관련
signal game_log(text: String, color: Color) # 로그 출력 [cite: 82]
signal party_updated() # 파티원 상태 변경 시 (HUD 갱신용)

# 전투 관련
signal request_battle(enemies: Array[EnemyData]) # 전투 시작 요청 [cite: 77]
signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)
