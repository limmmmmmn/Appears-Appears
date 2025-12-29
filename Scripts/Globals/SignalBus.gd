# res://Scripts/Globals/SignalBus.gd
extends Node

# [전투 관련 신호]
signal battle_requested(enemy_data) # 적 만남!
signal battle_ended(victory: bool)  # 전투 끝!

# [전투 내부 신호]
# UI가 이 신호를 듣고 HP바를 깎습니다. (누가, 얼마나, 크리티컬?)
signal unit_damaged(target_node, amount, is_crit) 
signal unit_healed(target_node, amount)
signal turn_changed(unit_name)

# [로그 시스템]
signal log_message(msg)
