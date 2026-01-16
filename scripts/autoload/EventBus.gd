extends Node
## EventBus.gd
## 전역 시그널 버스 - 씬 간 통신용

# ===== 게임 흐름 =====
signal game_started
signal game_over
signal game_paused
signal game_resumed

# ===== 스테이지/노드 =====
signal stage_clear_ready
signal stage_cleared(stage_num: int)
signal node_entered(node_type: String, node_index: int)
signal node_completed(node_type: String)
signal world_map_transition_start(from_node: int, to_node: int)
signal world_map_transition_end

# ===== 필드 =====
signal field_entered(stage: int, node_type: String)
signal field_exited
signal player_moved(position: Vector2)
signal enemy_spawned(enemy_id: String, position: Vector2)
signal enemy_touched(enemy_data: Dictionary)
signal tile_entered(tile_type: String, tile_position: Vector2)
signal town_tile_entered

# ===== 전투 =====
signal battle_start(enemies: Array)
signal battle_end(result: String)  # "victory", "defeat", "escape"
signal battle_turn_start(is_player_turn: bool)
signal battle_turn_end
signal battle_action_selected(action: String, target_index: int)

# ===== 데미지/힐 =====
signal damage_dealt(target_type: String, target_index: int, amount: int, is_critical: bool)
signal heal_applied(target_type: String, target_index: int, amount: int)
signal enemy_defeated(enemy_data: Dictionary)
signal party_member_died(member_index: int)

# ===== 파티 =====
signal party_member_joined(member_data: Dictionary)
signal party_member_left(member_index: int)
signal party_hp_changed(member_index: int, current_hp: int, max_hp: int)
signal party_mp_changed(member_index: int, current_mp: int, max_mp: int)
signal party_exp_gained(member_index: int, amount: int)
signal party_level_up(member_index: int, new_level: int)

# ===== 아이템/인벤토리 =====
signal item_acquired(item_data: Dictionary, quantity: int)
signal item_used(item_id: String, target_index: int)
signal item_dropped(item_id: String)
signal gold_acquired(amount: int)

# ===== UI =====
signal show_dialog(title: String, message: String)
signal hide_dialog
signal show_tooltip(text: String, position: Vector2)
signal hide_tooltip
signal battle_log_message(message: String)
signal damage_popup_requested(position: Vector2, amount: int, popup_type: String)

# ===== 마을/상점 =====
signal town_entered(town_id: String)
signal town_exited
signal shop_opened(shop_type: String)
signal shop_closed
signal item_purchased(item_id: String, price: int)
signal item_sold(item_id: String, price: int)

# ===== 오디오 =====
signal play_bgm(track_name: String)
signal stop_bgm
signal play_sfx(sfx_name: String)


# ===== 유틸리티 함수 =====
func emit_battle_log(message: String) -> void:
	battle_log_message.emit(message)


func emit_damage_popup(pos: Vector2, amount: int, is_heal: bool = false, is_critical: bool = false) -> void:
	var popup_type = "heal" if is_heal else ("critical" if is_critical else "normal")
	damage_popup_requested.emit(pos, amount, popup_type)


func emit_dialog(title: String, message: String) -> void:
	show_dialog.emit(title, message)
