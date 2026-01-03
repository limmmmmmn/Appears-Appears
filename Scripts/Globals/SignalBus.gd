# res://Scripts/Globals/SignalBus.gd
extends Node

# UI 관련
signal game_log(text: String, color: Color) # 로그 출력 [cite: 82]
signal party_updated() # 파티원 상태 변경 시 (HUD 갱신용)

# 전투 관련
# 변경: 적 하나(Main)와 친구목록(Table)을 받음
signal request_battle(main_enemy: EnemyData, spawn_table: Array[SpawnEntry])
signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)

signal gold_updated(new_amount) # 골드 변경 알림
