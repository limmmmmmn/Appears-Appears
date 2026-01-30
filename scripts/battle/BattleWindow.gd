extends PanelContainer
class_name BattleWindow
## BattleWindow: ATB 전투창 (전투창 증식 시스템)
## - 각 전투창이 독립적인 영웅 ATB + 적 ATB 관리
## - 전투 중 적 동적 추가 지원

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated
signal hero_atb_changed(battle_id: int, hero_id: String, value: float)
signal loot_drop_requested(item_id: String, start_global_pos: Vector2)

enum BattleState { STARTING, RUNNING, VICTORY, DEFEAT, ESCAPED, ENDED }

# === 전투 식별 ===
var battle_id: int = -1
var is_boss_battle: bool = false
var is_elite_battle: bool = false

# === 전투 상태 ===
var current_state: BattleState = BattleState.STARTING

# === 전투 참가자 ===
var enemies: Array = []
var enemy_data_list: Array = []

# === ATB 시스템 (전투창별 독립) ===
var enemy_atb: Dictionary = {}
var hero_atb: Dictionary = {}

# === 보상 ===
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []

# === UI 참조 ===
@onready var enemy_container: HBoxContainer = $MainVBox/BattleArea/EnemyContainer
@onready var run_button: Button = $MainVBox/BottomBar/RunButton
@onready var close_button: Button = $MainVBox/TopBar/CloseButton

# === ATB 설정 ===
const ENEMY_ATB_BASE: float = 0.08
const ENEMY_ATB_SPD_FACTOR: float = 0.008
const HERO_ATB_BASE: float = 0.15
const HERO_ATB_SPD_FACTOR: float = 0.012
const ATB_MAX: float = 1.0
const BASE_ESCAPE_RATE: float = 40.0

const BATTLE_ENEMY_SCENE = preload("res://scenes/battle/BattleEnemy.tscn")


func _ready() -> void:
	visible = false
	set_process(false)
	
	if run_button:
		run_button.pressed.connect(_on_run_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)


func _process(delta: float) -> void:
	if current_state != BattleState.RUNNING:
		return
	
	_update_hero_atb(delta)
	_update_enemy_atb(delta)


#region 전투 초기화 (새 시스템)
func setup_new(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false, p_is_boss: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	is_boss_battle = p_is_boss
	
	run_button.disabled = is_boss_battle
	
	for i in range(enemy_ids.size()):
		var enemy_id: String = str(enemy_ids[i])
		var make_elite: bool = (i == 0 and is_elite_battle)
		_spawn_single_enemy(enemy_id, make_elite)
	
	if is_elite_battle:
		_apply_elite_style()
	
	visible = true
	current_state = BattleState.STARTING
	
	await get_tree().create_timer(0.3).timeout
	_start_battle()


func add_enemy(enemy_id: String, is_elite: bool = false) -> void:
	if current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT:
		return
	
	enemy_data_list.append(enemy_id)
	_spawn_single_enemy(enemy_id, is_elite)
	
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var enemy_name: String = str(enemy_data.get("name", enemy_id))
	if is_elite:
		_send_log("⭐ 엘리트 %s 합류!" % enemy_name, Color.PURPLE)
	else:
		_send_log("%s 합류!" % enemy_name, Color.YELLOW)
	
	if current_state == BattleState.RUNNING:
		var idx: int = enemies.size() - 1
		enemy_atb[idx] = randf() * 0.3
	
	_shake_window()


func _spawn_single_enemy(enemy_id: String, make_elite: bool = false) -> void:
	var battle_enemy: BattleEnemy = BATTLE_ENEMY_SCENE.instantiate()
	enemy_container.add_child(battle_enemy)
	battle_enemy.setup(enemy_id, make_elite)
	enemies.append(battle_enemy)
	
	var idx: int = enemies.size() - 1
	enemy_atb[idx] = randf() * 0.6


func _shake_window() -> void:
	var original_pos: Vector2 = position
	var tween := create_tween()
	tween.tween_property(self, "position", original_pos + Vector2(5, 0), 0.05)
	tween.tween_property(self, "position", original_pos + Vector2(-5, 0), 0.05)
	tween.tween_property(self, "position", original_pos + Vector2(3, 0), 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)


func _apply_elite_style() -> void:
	var bg: Panel = get_node_or_null("Panel")
	if bg:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.1, 0.3, 0.95)
		bg.add_theme_stylebox_override("panel", style)


func get_enemy_count() -> int:
	var count: int = 0
	for e in enemies:
		if e != null and e.is_alive():
			count += 1
	return count


func get_total_enemy_count() -> int:
	return enemies.size()
#endregion


#region 레거시 호환
func setup(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false) -> void:
	var is_boss: bool = _check_is_boss_battle(enemy_ids)
	setup_new(p_battle_id, enemy_ids, p_is_elite, is_boss)


func _check_is_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var data: Dictionary = DataManager.get_enemy(str(enemy_id))
		if data.get("type", "") == "boss":
			return true
	return false


func _init_hero_atb() -> void:
	hero_atb.clear()
	for hero in PartyManager.get_alive_heroes():
		hero_atb[hero.id] = randf() * 0.4


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	_init_hero_atb()
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


#region 영웅 ATB 시스템
func _update_hero_atb(delta: float) -> void:
	var speed_delta: float = delta * BattleManager.get_battle_speed()
	
	for hero in PartyManager.get_alive_heroes():
		if not hero_atb.has(hero.id):
			hero_atb[hero.id] = 0.0
		
		var charge_rate: float = HERO_ATB_BASE + (hero.get_spd() * HERO_ATB_SPD_FACTOR)
		hero_atb[hero.id] = minf(hero_atb[hero.id] + charge_rate * speed_delta, ATB_MAX)
		
		hero_atb_changed.emit(battle_id, hero.id, hero_atb[hero.id])
		
		if hero_atb[hero.id] >= ATB_MAX:
			_hero_attack(hero)
			hero_atb[hero.id] = 0.0
			hero_atb_changed.emit(battle_id, hero.id, 0.0)
			
			if _check_battle_end():
				return


func _hero_attack(hero: Hero) -> void:
	if hero == null or hero.is_dead:
		return

	if not has_alive_enemies():
		return

	_bring_to_front()
	BattleManager.hero_attacked.emit(hero.id)

	# 스킬 선택
	var skill_id: String = _select_skill_for_hero(hero)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)

	# 스킬 데이터가 없으면 기본 공격으로 폴백
	if skill_data.is_empty():
		skill_id = "basic_attack"
		skill_data = DataManager.get_skill("basic_attack")

	var target_type: String = skill_data.get("target", "single_enemy")

	# MP 소모
	var mp_cost: int = int(skill_data.get("mp_cost", 0))
	if mp_cost > 0:
		hero.use_mp(mp_cost)
		call_deferred("_emit_party_updated")

	# 타겟 타입에 따른 처리
	match target_type:
		"single_ally", "all_allies":
			_execute_ally_skill(hero, skill_id, skill_data, target_type)
		"all_enemies":
			_execute_aoe_attack(hero, skill_id, skill_data)
		_:  # single_enemy
			_execute_single_attack(hero, skill_id, skill_data)


func _select_skill_for_hero(hero: Hero) -> String:
	## 영웅이 사용할 스킬 선택 (AI)
	var usable_skills: Array = hero.get_usable_skills()

	# 힐러인 경우 아군 체력 확인
	if "heal" in hero.get_available_skills():
		var wounded := _get_wounded_heroes()
		if not wounded.is_empty() and hero.can_use_skill("heal"):
			return "heal"

	# 사용 가능한 스킬 중 랜덤 선택 (70% 확률로 스킬 사용)
	if not usable_skills.is_empty() and randf() < 0.7:
		return usable_skills[randi() % usable_skills.size()]

	return "basic_attack"


func _get_wounded_heroes() -> Array:
	## HP가 50% 이하인 아군 반환
	var result: Array = []
	for hero in PartyManager.get_alive_heroes():
		if hero.get_hp_percent() < 0.5:
			result.append(hero)
	return result


func _execute_single_attack(hero: Hero, skill_id: String, skill_data: Dictionary) -> void:
	## 단일 대상 공격 실행
	if not has_alive_enemies():
		return

	var target: BattleEnemy = _select_smart_target(hero)
	if target == null:
		return

	var skill_name: String = skill_data.get("name", "공격")
	var skill_type: String = skill_data.get("type", "physical")

	# 회피 판정
	var eva_ignore: float = _get_skill_effect_value(skill_data, "ignore_eva", 0.0)
	var effective_eva: float = target.get_eva() * (1.0 - eva_ignore)
	var is_evaded: bool = randf() * 100 < effective_eva

	if is_evaded:
		target.show_miss_text()
		target.play_evade_effect()
		_send_log("%s의 %s을(를) %s이(가) 회피!" % [hero.hero_name, skill_name, target.enemy_name], Color.GRAY)
		return

	# 크리티컬 판정
	var crit_bonus: float = _get_skill_effect_value(skill_data, "crit_bonus", 0.0)
	var crit_chance: float = hero.get_crit() + crit_bonus
	var is_crit: bool = randf() * 100 < crit_chance

	# 데미지 계산
	var damage: int = _calc_skill_damage(hero, target, skill_data, is_crit)

	target.take_damage(damage)
	target.play_hit_effect(is_crit)
	target.show_damage_number(damage, is_crit)

	var log_color: Color = Color.ORANGE if is_crit else (Color.CYAN if skill_type == "magic" else Color.WHITE)
	var crit_text: String = " ⭐" if is_crit else ""

	if skill_id == "basic_attack":
		_send_log("%s → %s에게 %d%s" % [hero.hero_name, target.enemy_name, damage, crit_text], log_color)
	else:
		_send_log("%s [%s] → ⭐ %s에게 %d%s" % [hero.hero_name, skill_name, target.enemy_name, damage, crit_text], log_color)

	if not target.is_alive():
		_on_enemy_defeated(target)


func _execute_aoe_attack(hero: Hero, skill_id: String, skill_data: Dictionary) -> void:
	## 전체 공격 실행
	var skill_name: String = skill_data.get("name", "공격")
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)

	if alive_enemies.is_empty():
		return

	_send_log("%s [%s] 발동!" % [hero.hero_name, skill_name], Color.YELLOW)

	for target in alive_enemies:
		var is_crit: bool = randf() * 100 < hero.get_crit()
		var damage: int = _calc_skill_damage(hero, target, skill_data, is_crit)

		target.take_damage(damage)
		target.play_hit_effect(is_crit)
		target.show_damage_number(damage, is_crit)

		if not target.is_alive():
			_on_enemy_defeated(target)


func _execute_ally_skill(hero: Hero, skill_id: String, skill_data: Dictionary, target_type: String) -> void:
	## 아군 대상 스킬 실행 (힐 등)
	var skill_name: String = skill_data.get("name", "스킬")
	var skill_type: String = skill_data.get("type", "utility")

	if skill_type == "heal":
		var targets: Array = []
		if target_type == "single_ally":
			# 가장 체력이 낮은 아군 선택
			var lowest_hp_hero: Hero = null
			var lowest_percent: float = 1.0
			for h in PartyManager.get_alive_heroes():
				var hp_percent := h.get_hp_percent()
				if hp_percent < lowest_percent:
					lowest_percent = hp_percent
					lowest_hp_hero = h
			if lowest_hp_hero:
				targets.append(lowest_hp_hero)
		else:  # all_allies
			targets = PartyManager.get_alive_heroes()

		# 회복 사운드 재생
		if targets.size() > 0:
			if SoundManager != null:
				SoundManager.play_heal()

		for target in targets:
			var heal_amount: int = _calc_heal_amount(hero, skill_data)
			var actual_heal: int = target.heal(heal_amount)
			_send_log("%s [%s] → %s HP +%d" % [hero.hero_name, skill_name, target.hero_name, actual_heal], Color.GREEN)

		call_deferred("_emit_party_updated")
	else:
		# 유틸리티 스킬 (도발 등) - 추후 구현
		_send_log("%s [%s] 발동!" % [hero.hero_name, skill_name], Color.PURPLE)


func _calc_skill_damage(hero: Hero, target: BattleEnemy, skill_data: Dictionary, is_crit: bool) -> int:
	## 스킬 데미지 계산
	var damage_base: int = int(skill_data.get("damage_base", 0))
	var scaling: Dictionary = skill_data.get("damage_scaling", {"stat": "str", "multiplier": 1.0})
	var stat_name: String = scaling.get("stat", "str")
	var multiplier: float = scaling.get("multiplier", 1.0)

	var stat_value: int = 0
	match stat_name:
		"str": stat_value = hero.get_str()
		"int": stat_value = hero.get_int()
		"def": stat_value = hero.get_def()
		"spd": stat_value = hero.get_spd()
		"luk": stat_value = hero.get_luk()

	var base_damage: int = damage_base + int(stat_value * multiplier)

	# 방어력 적용
	var skill_type: String = skill_data.get("type", "physical")
	var defense: int = 0
	if skill_type == "physical":
		defense = target.get_p_def()
	elif skill_type == "magic":
		defense = target.get_m_def()

	if is_crit:
		return maxi(1, base_damage)  # 크리티컬은 방어 무시

	return maxi(1, base_damage - int(defense / 2))


func _calc_heal_amount(hero: Hero, skill_data: Dictionary) -> int:
	## 힐량 계산
	var heal_base: int = int(skill_data.get("heal_base", 0))
	var scaling: Dictionary = skill_data.get("heal_scaling", {"stat": "int", "multiplier": 0.5})
	var stat_name: String = scaling.get("stat", "int")
	var multiplier: float = scaling.get("multiplier", 0.5)

	var stat_value: int = 0
	match stat_name:
		"str": stat_value = hero.get_str()
		"int": stat_value = hero.get_int()
		_: stat_value = hero.get_int()

	return heal_base + int(stat_value * multiplier)


func _get_skill_effect_value(skill_data: Dictionary, effect_type: String, default_value: float) -> float:
	## 스킬 효과 값 가져오기
	var effects: Array = skill_data.get("effects", [])
	for effect in effects:
		if effect.get("type", "") == effect_type:
			return float(effect.get("value", default_value))
	return default_value


func _select_smart_target(hero: Hero) -> BattleEnemy:
	var alive: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive.append(e)
	
	if alive.is_empty():
		return null
	
	var atk := hero.get_atk()
	for enemy in alive:
		var expected := maxi(1, atk - int(enemy.get_p_def() / 2))
		if expected >= enemy.current_hp:
			return enemy
	
	return alive[randi() % alive.size()]


func get_hero_atb_value(hero_id: String) -> float:
	return hero_atb.get(hero_id, 0.0)


func has_alive_enemies() -> bool:
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false
#endregion


#region 적 ATB 시스템
func _update_enemy_atb(delta: float) -> void:
	var speed_delta: float = delta * BattleManager.get_battle_speed()
	
	for i in range(enemies.size()):
		var enemy: BattleEnemy = enemies[i]
		if not enemy.is_alive():
			continue
		
		if not enemy_atb.has(i):
			enemy_atb[i] = randf() * 0.4
		
		var charge_rate: float = ENEMY_ATB_BASE + (enemy.get_spd() * ENEMY_ATB_SPD_FACTOR)
		enemy_atb[i] = minf(enemy_atb[i] + charge_rate * speed_delta, ATB_MAX)
		
		enemy.update_atb_bar(enemy_atb[i])
		
		if enemy_atb[i] >= ATB_MAX:
			_enemy_attack(enemy)
			enemy_atb[i] = 0.0
			
			if _check_battle_end():
				return


func _enemy_attack(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		return
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	_bring_to_front()
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	
	enemy.play_attack_effect()
	
	var is_evaded := randf() * 100 < target.get_eva()
	if is_evaded:
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
		return
	
	var is_crit := randf() * 100 < enemy.get_crit()
	var damage := _calc_enemy_damage(enemy, target, is_crit)
	
	PartyManager.on_hero_damaged(target, damage)
	call_deferred("_emit_party_updated")
	
	var log_color: Color = Color.RED if is_crit else Color.YELLOW
	var crit_text: String = " (강타!)" if is_crit else ""
	_send_log("%s → %s에게 %d%s" % [enemy.enemy_name, target.hero_name, damage, crit_text], log_color)
	
	if target.is_dead:
		_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
		call_deferred("_emit_party_updated")


func _calc_enemy_damage(enemy: BattleEnemy, target: Hero, is_crit: bool) -> int:
	var atk := enemy.get_atk()
	var p_def := target.get_p_def()
	if is_crit:
		return maxi(1, atk)
	return maxi(1, atk - int(p_def / 2))
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	_send_log("%s 처치!" % enemy.enemy_name, Color.LIME)
	
	total_exp += enemy.exp_reward
	total_gold += enemy.get_gold_reward()
	drop_items.append_array(enemy.roll_drops())
	
	var idx := enemies.find(enemy)
	if idx >= 0:
		enemy_atb.erase(idx)
	
	enemy.play_death_effect()


func _check_battle_end() -> bool:
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)
	
	var alive_heroes := PartyManager.get_alive_heroes()
	
	if alive_enemies.is_empty():
		_end_battle_victory()
		return true
	
	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true
	
	return false


func _end_battle_victory() -> void:
	current_state = BattleState.VICTORY
	set_process(false)
	
	# 승리 사운드 재생
	if SoundManager != null:
		SoundManager.play_victory()
	
	_send_log("승리! EXP +%d, Gold +%d" % [total_exp, total_gold], Color.CYAN)
	
	PartyManager.distribute_exp(total_exp)
	GameManager.add_gold(total_gold)
	
	if not drop_items.is_empty():
		_start_loot_animations()
	
	call_deferred("_emit_party_updated")
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, true)


func _start_loot_animations() -> void:
	var delay: float = 0.0
	var delay_interval: float = 0.15
	
	for item_id in drop_items:
		var start_pos: Vector2 = global_position + size / 2
		_delayed_loot_drop(item_id, start_pos, delay)
		
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if not equip_data.is_empty():
			var rarity: String = str(equip_data.get("rarity", "common"))
			var item_name: String = str(equip_data.get("name", item_id))
			var color: Color = Color.WHITE
			match rarity:
				"magic": color = Color(0.4, 0.6, 1.0)
				"legendary": color = Color(1.0, 0.7, 0.2)
			_send_log("⚔️ %s 획득!" % item_name, color)
		else:
			var item_data: Dictionary = DataManager.get_item(item_id)
			_send_log("%s 획득!" % str(item_data.get("name", item_id)), Color.YELLOW)
		
		delay += delay_interval


func _delayed_loot_drop(item_id: String, start_pos: Vector2, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	
	InventoryManager.add_item(item_id)
	loot_drop_requested.emit(item_id, start_pos)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	set_process(false)
	
	# 패배 사운드 재생
	if SoundManager != null:
		SoundManager.play_defeat()
	
	_send_log("전멸...", Color.DARK_RED)
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, false)
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	if is_boss_battle or current_state != BattleState.RUNNING:
		return
	
	run_button.disabled = true
	
	var escape_chance := _calculate_escape_chance()
	var roll := randf() * 100
	
	if roll < escape_chance:
		current_state = BattleState.ESCAPED
		set_process(false)
		_send_log("도주 성공!", Color.CYAN)
		run_button.visible = false
		close_button.visible = true
		battle_ended.emit(battle_id, false)
	else:
		_send_log("도주 실패!", Color.GRAY)
		run_button.disabled = false


func _calculate_escape_chance() -> float:
	var party_avg_spd := PartyManager.get_party_average_spd()
	
	var enemy_total_spd: float = 0.0
	var alive_count: int = 0
	for enemy in enemies:
		if enemy.is_alive():
			enemy_total_spd += enemy.get_spd()
			alive_count += 1
	var enemy_avg_spd: float = enemy_total_spd / maxf(1.0, float(alive_count))
	
	var chance := BASE_ESCAPE_RATE + (party_avg_spd - enemy_avg_spd) * 2.0
	return clampf(chance, 5.0, 95.0)
#endregion


#region 유틸리티
func _bring_to_front() -> void:
	var parent = get_parent()
	if parent:
		parent.move_child(self, -1)


func _emit_party_updated() -> void:
	party_updated.emit()


func _send_log(msg: String, color: Color = Color.WHITE) -> void:
	battle_log.emit(msg, color)


func _on_close_pressed() -> void:
	current_state = BattleState.ENDED
	queue_free()
#endregion
