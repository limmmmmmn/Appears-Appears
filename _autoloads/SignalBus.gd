# _autoloads/signal_bus.gd
extends Node

# UI 로그 표시용
signal log_message(text: String)

# 전투 관련 알림 (데이터 전달 최소화)
signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, won: bool)
