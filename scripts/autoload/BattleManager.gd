extends Node
## BattleManager: 전투창 시스템
## - 필드 조우 시 전투창 1개 생성 (1~3마리)
## - 전투창 최대 MAX_BATTLE_WINDOWS 개

const BATTLE_WINDOW_SCENE = preload("res://scenes/battle/BattleWindow.tscn")

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)
signal all_battles_ended
signal battle_log_received(message: String, color: Color)
signal hud_notice_requested(message: String, duration: float, color: Color)
signal party_hp_changed
signal elite_victory(battle_id: int)
signal boss_victory(battle_id: int)
signal boss_battle_started(battle_id: int)  # 보스전 시작 시그널 (관전 시스템용)
signal boss_battle_ended(battle_id: int)  # 보스전 종료 시그널
signal turn_changed(unit_name: String, is_hero: bool)  # 턴 변경 시그널
signal hero_attacked(hero_id: String)
signal hero_damaged(hero_id: String)  # 영웅 피격 시그널
signal loot_animation_requested(item_id: String, start_pos: Vector2)
signal accumulated_rewards_changed(gold: int, items: Array)
signal field_drops_requested(hp_orbs: int, mp_orbs: int, world_pos: Vector2, window_rect: Rect2)

# === 전투창 시스템 설정 ===
const MAX_BATTLE_WINDOWS: int = 5      # 최대 전투창 개수

# === 누적 보상 시스템 ===
var accumulated_exp: int = 0
var accumulated_gold: int = 0
var accumulated_items: Array = []  # [{id, type, rarity, identified}]

# === 창 생성 효과 (비워둠) ===
signal window_created(window_count: int)      # 새 전투창 생성 시
signal threshold_reached(window_count: int)   # 임계치 도달 시

var active_battles: Dictionary = {}  # battle_id -> {window, is_boss, is_elite, collision_pos}
var _battle_id_counter: int = 0
var last_battle_pos: Vector2 = Vector2.ZERO
var last_window_rect: Rect2 = Rect2()

# === 전투 정지 ===
var is_battle_paused: bool = false
signal battle_pause_changed(paused: bool)

# 전투창 배치 설정
const WINDOW_SIZE := Vector2(280, 200)
const BOSS_WINDOW_SIZE := Vector2(420, 300)  # 보스전 전투창 (약 2배 크기)
const CENTER_SAFE_SIZE: float = 100.0
const WINDOW_MARGIN: float = 20.0  # 화면 가장자리 여유

var battle_container: CanvasLayer = null


func _ready() -> void:
	pass


func push_hud_notice(message: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	## 필드 HUD 중앙 하단 알림 요청
	if message.is_empty():
		return
	hud_notice_requested.emit(message, duration, color)


#region 전투창 시스템 - 핵심 로직
func add_enemy_to_battle(enemy_ids: Array, parent_node: Node = null, is_elite: bool = false, collision_pos: Vector2 = Vector2.ZERO) -> int:
	## 필드에서 적과 충돌 시 호출
	## 전투창 1개 생성 (1~3마리)

	if enemy_ids.is_empty():
		return -1

	var first_enemy_id: String = str(enemy_ids[0])
	var is_boss := _check_boss_enemy(first_enemy_id)

	# 보스전 시작 시 다른 전투 모두 강제 종료
	if is_boss:
		force_end_all_non_boss()
		return _create_new_battle(enemy_ids, parent_node, is_elite, is_boss, collision_pos)

	# 최대 전투창 도달 시 무시
	if get_active_battle_count() >= MAX_BATTLE_WINDOWS:
		return -1

	# 새 전투창 생성
	return _create_new_battle(enemy_ids, parent_node, is_elite, false, collision_pos)


func start_boss_battle(enemy_id: String, parent_node: Node = null, is_elite: bool = false, collision_pos: Vector2 = Vector2.ZERO) -> int:
	## 보스 전투 시작 (Field에서 직접 호출)
	force_end_all_non_boss()
	return _create_new_battle([enemy_id], parent_node, is_elite, true, collision_pos)


func _create_new_battle(enemy_ids: Array, parent_node: Node, is_elite: bool, is_boss: bool, _collision_pos: Vector2) -> int:
	## 새 전투창 생성
	_battle_id_counter += 1
	var battle_id := _battle_id_counter

	# 적 조우 사운드 재생
	if SoundManager:
		SoundManager.play_encounter()

	# BattleWindow 씬 인스턴스 생성
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()

	# 컨테이너 설정
	if battle_container == null:
		_create_battle_container(parent_node)

	battle_container.add_child(window)

	# 시작 위치: 화면 중앙
	var viewport_size := Vector2(480, 270)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size

	# 보스전은 크게, 가운데 고정
	var window_size: Vector2
	var target_pos: Vector2
	if is_boss:
		window_size = BOSS_WINDOW_SIZE
		target_pos = viewport_size / 2 - window_size / 2
		window.custom_minimum_size = window_size
	else:
		window_size = WINDOW_SIZE
		target_pos = _calculate_window_position()

	# 시작 위치에 배치 (목표 위치에서 투명하게 시작)
	window.position = target_pos
	window.modulate.a = 0.0
	window.scale = Vector2(0.8, 0.8)

	# 전투 초기화 (새 시스템용)
	window.setup_new(battle_id, enemy_ids, is_elite, is_boss)

	# 전투 정지 상태면 새 전투창도 정지
	if is_battle_paused:
		window.set_battle_paused(true)
	window.battle_ended.connect(_on_battle_window_ended)
	window.battle_log.connect(_on_battle_log)
	window.party_updated.connect(_on_party_updated)
	window.loot_drop_requested.connect(_on_loot_drop_requested)

	# 등장 애니메이션
	_animate_window_appear(window, target_pos)

	# 등록
	active_battles[battle_id] = {
		"window": window,
		"is_boss": is_boss,
		"is_elite": is_elite,
		"collision_pos": _collision_pos
	}
	last_battle_pos = _collision_pos

	# === 창 생성 효과 (비워둠) ===
	var window_count := get_active_battle_count()
	window_created.emit(window_count)
	_on_window_created_effect(window_count)

	# 임계치 체크
	_check_threshold(window_count)

	battle_started.emit(battle_id)

	# 보스전 시작 시그널 (관전 시스템용)
	if is_boss:
		boss_battle_started.emit(battle_id)

	return battle_id


func _on_window_created_effect(_window_count: int) -> void:
	## 전투창 생성 시 발동하는 효과 (현재 비워둠)
	## TODO: 파티 보호막, 힐 토큰, 디버프, 보상 배율 등
	pass


func _check_threshold(window_count: int) -> void:
	## 전투창 개수 임계치 체크 및 효과 발동 (현재 비워둠)
	if window_count == 3:
		threshold_reached.emit(3)
		_on_threshold_3_effect()
	elif window_count == 5:
		threshold_reached.emit(5)
		_on_threshold_5_effect()
	elif window_count == MAX_BATTLE_WINDOWS:
		threshold_reached.emit(MAX_BATTLE_WINDOWS)
		_on_threshold_max_effect()


func _on_threshold_3_effect() -> void:
	## 전투창 3개 도달 효과 (비워둠)
	pass


func _on_threshold_5_effect() -> void:
	## 전투창 5개 도달 효과 (비워둠)
	pass


func _on_threshold_max_effect() -> void:
	## 전투창 최대치 도달 효과 (비워둠)
	pass
#endregion


#region 레거시 호환 - start_battle
func start_battle(enemy_ids: Array, parent_node: Node = null, is_elite: bool = false, collision_pos: Vector2 = Vector2.ZERO) -> int:
	## 레거시 호환용: 여러 적을 한번에 전투에 추가
	## 전체를 하나의 전투창에 생성
	return add_enemy_to_battle(enemy_ids, parent_node, is_elite, collision_pos)
#endregion


#region 전투창 등장 애니메이션
func _animate_window_appear(window: BattleWindow, _target_pos: Vector2) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# 위치 이동 없이 제자리에서 나타남
	tween.tween_property(window, "modulate:a", 1.0, 0.2)
	tween.tween_property(window, "scale", Vector2.ONE, 0.25)
#endregion


#region 전투 종료
func end_battle(battle_id: int, victory: bool) -> void:
	if not active_battles.has(battle_id):
		return

	var battle_data: Dictionary = active_battles[battle_id]
	var window_ref = battle_data.get("window")

	if window_ref != null and is_instance_valid(window_ref):
		window_ref.queue_free()

	active_battles.erase(battle_id)
	battle_ended.emit(battle_id, victory)
	
	if active_battles.is_empty():
		ATBManager.reset()
		all_battles_ended.emit()


func _on_battle_window_ended(battle_id: int, victory: bool) -> void:
	var was_elite: bool = false
	var was_boss: bool = false
	var window_gold: int = 0
	var window_items: Array = []
	var battle_pos: Vector2 = Vector2.ZERO
	var window_screen_rect: Rect2 = Rect2()

	if active_battles.has(battle_id):
		var bd: Dictionary = active_battles[battle_id]
		was_elite = bd.get("is_elite", false)
		was_boss = bd.get("is_boss", false)
		battle_pos = bd.get("collision_pos", Vector2.ZERO)
		# 전투창 보상 데이터 및 위치 읽기 (닫히기 전)
		if victory:
			var window = bd.get("window")
			if window != null and is_instance_valid(window):
				window_gold = window.total_gold
				window_items = window.drop_items.duplicate()
				window_screen_rect = Rect2(window.position, window.size)
				last_window_rect = window_screen_rect

	end_battle(battle_id, victory)

	# 승리 보상: 골드/아이템 즉시 지급 + 날아가는 연출 + HP/MP 오브 드롭
	if victory and (window_gold > 0 or not window_items.is_empty()):
		var start_pos: Vector2 = window_screen_rect.get_center()

		# 골드 즉시 지급
		if window_gold > 0 and GameManager:
			GameManager.add_gold(window_gold)

		# 아이템 즉시 지급 (자동장착 또는 인벤토리) + 타겟 추적
		var item_targets: Array = []  # [{item_id, auto_equipped, hero_index}]
		for item_id in window_items:
			if InventoryManager:
				var equipped := InventoryManager.try_auto_equip(item_id)
				var hero_idx := -1
				if equipped:
					hero_idx = _find_equipped_hero_index(item_id)
				else:
					InventoryManager.add_item(item_id)
				item_targets.append({"item_id": item_id, "auto_equipped": equipped, "hero_index": hero_idx})

		# 날아가는 연출
		_spawn_reward_fly_anim(start_pos, window_gold, item_targets)

		# 보상 규모에 따라 오브 개수 결정
		var hp_orbs: int = _calc_orb_count(window_gold, window_items.size())
		var mp_orbs: int = _calc_orb_count(window_gold, window_items.size())
		field_drops_requested.emit(hp_orbs, mp_orbs, battle_pos, window_screen_rect)

	if was_boss:
		boss_battle_ended.emit(battle_id)
		if victory:
			boss_victory.emit(battle_id)
	elif victory and was_elite:
		elite_victory.emit(battle_id)

	if victory and SaveManager:
		SaveManager.auto_save("전투 승리")

	if not victory and PartyManager.is_party_wiped():
		GameManager.trigger_game_over()


func _on_battle_log(message: String, color: Color) -> void:
	battle_log_received.emit(message, color)


func _on_party_updated() -> void:
	party_hp_changed.emit()


func _on_loot_drop_requested(item_id: String, start_pos: Vector2) -> void:
	loot_animation_requested.emit(item_id, start_pos)
#endregion


#region 누적 보상 시스템
func add_accumulated_reward(_exp: int, gold: int, items: Array = []) -> void:
	## 전투창에서 보상 누적
	accumulated_exp += maxi(0, _exp)
	accumulated_gold += gold

	# 아이템 추가
	for item_id in items:
		# 장비 데이터 먼저 확인, 없으면 일반 아이템 확인
		var item_data: Dictionary = DataManager.get_equipment(item_id)
		if item_data.is_empty():
			item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue

		var reward_item := {
			"id": item_id,
			"type": item_data.get("type", "unknown"),
			"slot": item_data.get("slot", ""),
			"rarity": item_data.get("rarity", "common")
		}
		accumulated_items.append(reward_item)

	accumulated_rewards_changed.emit(accumulated_gold, accumulated_items)


func claim_accumulated_rewards() -> void:
	## 누적 보상 수령 → 즉시 지급 + 오브 드롭
	if accumulated_exp > 0:
		var party: Array = PartyManager.get_party() if PartyManager else []
		for hero in party:
			if hero != null:
				hero.gain_exp(accumulated_exp)

	var items_arr: Array = []
	for item in accumulated_items:
		items_arr.append(item.id)

	if accumulated_gold > 0 or not items_arr.is_empty():
		if accumulated_gold > 0 and GameManager:
			GameManager.add_gold(accumulated_gold)
		for item_id in items_arr:
			if InventoryManager:
				if not InventoryManager.try_auto_equip(item_id):
					InventoryManager.add_item(item_id)
		var hp_orbs: int = _calc_orb_count(accumulated_gold, items_arr.size())
		var mp_orbs: int = _calc_orb_count(accumulated_gold, items_arr.size())
		field_drops_requested.emit(hp_orbs, mp_orbs, last_battle_pos, last_window_rect)

	# 초기화
	reset_accumulated_rewards()


func _calc_orb_count(gold: int, item_count: int) -> int:
	## 보상 규모에 따라 오브 개수 결정 (최소 1, 최대 5)
	var score: float = gold * 0.05 + item_count * 2.0
	return clampi(int(score), 1, 5)


func reset_accumulated_rewards() -> void:
	## 보상 초기화
	accumulated_exp = 0
	accumulated_gold = 0
	accumulated_items.clear()
	accumulated_rewards_changed.emit(0, [])


func get_accumulated_rewards() -> Dictionary:
	return {
		"exp": accumulated_exp,
		"gold": accumulated_gold,
		"items": accumulated_items,
	}
#endregion


#region 전투창 컨테이너
func _create_battle_container(parent: Node) -> void:
	battle_container = CanvasLayer.new()
	battle_container.name = "BattleContainer"
	battle_container.layer = 10
	
	if parent:
		parent.add_child(battle_container)
	else:
		var tree := get_tree()
		if tree and tree.current_scene:
			tree.current_scene.add_child(battle_container)


func clear_battle_container() -> void:
	if battle_container and is_instance_valid(battle_container):
		battle_container.queue_free()
		battle_container = null
	active_battles.clear()
	ATBManager.reset()
#endregion


#region 전투창 위치 계산
# HUD 영역 설정
const HUD_TOP_HEIGHT: float = 32.0  # TopBar 높이 + 여유
const HUD_BOTTOM_HEIGHT: float = 60.0  # BottomPartyPanel 높이 + 여유

func _calculate_window_position() -> Vector2:
	var viewport_size := Vector2(640, 360)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size

	# HUD를 피한 안전 영역 계산
	var safe_left: float = WINDOW_MARGIN
	var safe_top: float = HUD_TOP_HEIGHT
	var safe_right: float = viewport_size.x - WINDOW_SIZE.x - WINDOW_MARGIN
	var safe_bottom: float = viewport_size.y - WINDOW_SIZE.y - HUD_BOTTOM_HEIGHT

	safe_left = maxf(safe_left, 0)
	safe_top = maxf(safe_top, 0)
	safe_right = maxf(safe_right, safe_left)
	safe_bottom = maxf(safe_bottom, safe_top)

	# 중앙 회피 영역
	var center := viewport_size / 2
	var center_avoid := Rect2(
		center.x - CENTER_SAFE_SIZE * 0.5,
		center.y - CENTER_SAFE_SIZE * 0.5,
		CENTER_SAFE_SIZE,
		CENTER_SAFE_SIZE
	)

	# 기존 전투창 위치 수집
	var existing_rects: Array = []
	for bid in active_battles:
		var battle_data: Dictionary = active_battles[bid]
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			existing_rects.append(Rect2(window_ref.position, WINDOW_SIZE))

	# 후보 위치 생성 및 겹침 점수 평가 (낮을수록 좋음)
	var best_pos := Vector2(randf_range(safe_left, safe_right), randf_range(safe_top, safe_bottom))
	var best_score: float = -1.0

	for _i in range(40):
		var x := randf_range(safe_left, safe_right)
		var y := randf_range(safe_top, safe_bottom)
		var candidate := Rect2(x, y, WINDOW_SIZE.x, WINDOW_SIZE.y)

		# 중앙 영역 겹치면 스킵
		if candidate.intersects(center_avoid):
			continue

		# 기존 전투창과의 겹침 면적 합산
		var overlap_score: float = 0.0
		for existing in existing_rects:
			var overlap := candidate.intersection(existing)
			overlap_score += overlap.get_area()

		# 겹침이 가장 적은 후보 선택
		if best_score < 0.0 or overlap_score < best_score:
			best_score = overlap_score
			best_pos = Vector2(x, y)

			# 겹침 없으면 즉시 채택
			if overlap_score == 0.0:
				break

	return best_pos


func _is_position_available(pos: Vector2) -> bool:
	## 해당 위치에 다른 전투창이 없는지 확인
	for bid in active_battles:
		var battle_data: Dictionary = active_battles[bid]
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			if pos.distance_to(window_ref.position) < WINDOW_SIZE.x * 0.8:
				return false
	return true
#endregion





#region 유틸리티
func get_active_battle_count() -> int:
	return active_battles.size()


func get_total_enemy_count() -> int:
	## 모든 전투창의 적 수 합계
	var total: int = 0
	for battle_id in active_battles:
		var window: BattleWindow = active_battles[battle_id].get("window")
		if window and is_instance_valid(window):
			total += window.get_enemy_count()
	return total


func has_boss_battle() -> bool:
	for battle_id in active_battles:
		if active_battles[battle_id].get("is_boss", false):
			return true
	return false


func _check_boss_enemy(enemy_id: String) -> bool:
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	return enemy_data.get("type", "") == "boss"


func force_end_all_non_boss() -> void:
	var to_remove: Array = []
	for battle_id in active_battles:
		if not active_battles[battle_id].get("is_boss", false):
			to_remove.append(battle_id)

	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			window_ref.queue_free()
		active_battles.erase(battle_id)
		battle_ended.emit(battle_id, false)


func close_all_battles() -> void:
	var to_remove: Array = active_battles.keys().duplicate()

	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			window_ref.queue_free()
		active_battles.erase(battle_id)
#endregion


#region 전투 정지
func toggle_battle_pause() -> void:
	set_battle_paused(not is_battle_paused)


func set_battle_paused(paused: bool) -> void:
	is_battle_paused = paused
	for battle_id in active_battles:
		var battle_data: Dictionary = active_battles[battle_id]
		var window = battle_data.get("window")
		if window != null and is_instance_valid(window):
			window.set_battle_paused(paused)
	battle_pause_changed.emit(paused)
#endregion


#region 보상 날아가는 연출
func _spawn_reward_fly_anim(start_pos: Vector2, gold: int, item_targets: Array) -> void:
	## 전투창 위치에서 골드/아이템이 HUD로 날아가는 연출
	var hud := _get_field_hud()
	if hud == null:
		return

	var fly_layer := CanvasLayer.new()
	fly_layer.layer = 100
	fly_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(fly_layer)

	var delay: float = 0.0
	var delay_step: float = 0.12

	# 골드 날아가기
	if gold > 0:
		var gold_target := _get_gold_label_pos(hud)
		if gold_target != Vector2.ZERO:
			_create_fly_icon(fly_layer, "🪙", Color(1.0, 0.9, 0.3), start_pos, gold_target, delay)
			delay += delay_step

	# 아이템 날아가기
	for data in item_targets:
		var item_id: String = data.item_id
		var equip_data: Dictionary = DataManager.get_equipment(item_id) if DataManager else {}
		var i_type: String = str(equip_data.get("type", equip_data.get("slot", "")))
		var i_rarity: String = str(equip_data.get("rarity", "common"))
		var icon: String = FieldDrop.ITEM_TYPE_ICONS.get(i_type, "📦")
		var color: Color = FieldDrop.RARITY_COLORS.get(i_rarity, Color.WHITE)

		var target_pos: Vector2 = Vector2.ZERO
		if data.auto_equipped and data.hero_index >= 0:
			target_pos = _get_hero_card_pos(hud, data.hero_index)
		else:
			target_pos = _get_inventory_card_pos(hud)

		if target_pos != Vector2.ZERO:
			_create_fly_icon(fly_layer, icon, color, start_pos, target_pos, delay)
			delay += delay_step

	# 모든 애니메이션 완료 후 레이어 정리
	var cleanup := get_tree().create_tween()
	cleanup.tween_interval(delay + 0.6)
	cleanup.tween_callback(fly_layer.queue_free)


func _create_fly_icon(parent: Node, icon_text: String, icon_color: Color, from: Vector2, to: Vector2, delay: float) -> void:
	var fly := Label.new()
	fly.text = icon_text
	fly.add_theme_font_size_override("font_size", 14)
	fly.add_theme_color_override("font_color", icon_color)
	fly.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fly.add_theme_constant_override("outline_size", 3)
	fly.z_index = 200
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.position = from
	fly.pivot_offset = Vector2(8, 8)
	fly.modulate.a = 0.0
	fly.scale = Vector2(1.5, 1.5)
	parent.add_child(fly)

	var tween := fly.create_tween()
	# 대기
	if delay > 0.0:
		tween.tween_interval(delay)
	# Phase 1: 팝업 등장
	tween.tween_property(fly, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(fly, "scale", Vector2(1.2, 1.2), 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(fly, "scale", Vector2(1.0, 1.0), 0.06)
	# Phase 2: 포물선으로 목표 이동
	var mid_y: float = minf(from.y, to.y) - 30.0
	tween.set_parallel(true)
	tween.tween_property(fly, "position:x", to.x, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(fly, "position:y", mid_y, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.chain()
	tween.set_parallel(true)
	tween.tween_property(fly, "position:y", to.y, 0.20).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(fly, "scale", Vector2(0.4, 0.4), 0.20).set_ease(Tween.EASE_IN)
	tween.tween_property(fly, "modulate:a", 0.0, 0.10).set_delay(0.10)
	tween.chain().tween_callback(fly.queue_free)


func _get_field_hud() -> FieldHUD:
	var hud_nodes: Array = get_tree().get_nodes_in_group("field_hud")
	if hud_nodes.is_empty():
		return null
	return hud_nodes[0] as FieldHUD


func _get_gold_label_pos(hud: FieldHUD) -> Vector2:
	if hud.gold_label and is_instance_valid(hud.gold_label):
		return hud.gold_label.get_global_rect().get_center()
	return Vector2.ZERO


func _get_hero_card_pos(hud: FieldHUD, hero_idx: int) -> Vector2:
	if hud.bottom_party_cards == null:
		return Vector2.ZERO
	var bpc: BottomPartyCards = hud.bottom_party_cards
	if hero_idx < bpc.cards.size():
		var card: HeroCard = bpc.cards[hero_idx]
		if card and is_instance_valid(card):
			return card.get_global_rect().get_center()
	return Vector2.ZERO


func _get_inventory_card_pos(hud: FieldHUD) -> Vector2:
	# 인벤토리 카드 삭제됨 → 첫 번째 히어로 카드 위치로 대체
	return _get_hero_card_pos(hud, 0)


func _find_equipped_hero_index(p_item_id: String) -> int:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		var hero = party[i]
		if hero == null:
			continue
		for slot in hero.equipment:
			if hero.equipment[slot] == p_item_id:
				return i
	return -1
#endregion
