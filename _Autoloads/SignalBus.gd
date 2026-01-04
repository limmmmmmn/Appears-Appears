extends Node

# 로그 메시지 출력 (UI 로그창용)
signal on_log_message(text: String, color: Color)

# 전투 시작 알림 (적 정보를 넘겨줌)
signal on_battle_started(enemy_actor: Node)

# 골드량 변화 알림
signal on_gold_changed(new_amount: int)

# 인벤토리 변경(획득/사용) 알림
signal on_inventory_updated()
