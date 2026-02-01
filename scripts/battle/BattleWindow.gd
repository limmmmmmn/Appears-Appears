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
var loot_multiplier: float = 1.0  # 루팅 배율 (아이템 등장 확률 배수)
var kill_count: int = 0  # 원념 (적 처치 횟수)

# === 전투창 모드 ===
enum WindowMode { NORMAL, HOLD, CLOSE_RESERVED }
var window_mode: WindowMode = WindowMode.NORMAL

# === UI 참조 ===
@onready var enemy_container: HBoxContainer = $MainVBox/BattleArea/EnemyContainer
@onready var run_button: Button = %RunButton
@onready var close_button: Button = $MainVBox/TopBar/CloseButton
@onready var hold_button: Button = %HoldButton
@onready var close_reserve_button: Button = %CloseReserveButton

# === 보상 UI 참조 ===
@onready var gold_label: Label = %GoldLabel
@onready var exp_label: Label = %ExpLabel
@onready var loot_label: Label = %LootLabel
@onready var kill_count_label: Label = %KillCountLabel

# === ATB 설정 ===
const ENEMY_ATB_BASE: float = 0.08
const ENEMY_ATB_SPD_FACTOR: float = 0.008
const HERO_ATB_BASE: float = 0.15
const HERO_ATB_SPD_FACTOR: float = 0.012
const ATB_MAX: float = 1.0
const BASE_ESCAPE_RATE: float = 40.0

const BATTLE_ENEMY_SCENE = preload("res://scenes/battle/BattleEnemy.tscn")

# === Mother 2 스타일 배경 효과 ===
var background: ColorRect = null
var bg_material: ShaderMaterial = null
var effect_time: float = 0.0
var current_effect: int = 0

# 색상 팔레트
const COLOR_PALETTES: Array = [
	[Color(0.2, 0.1, 0.3), Color(0.4, 0.2, 0.5)],  # 보라
	[Color(0.1, 0.2, 0.3), Color(0.2, 0.4, 0.5)],  # 파랑
	[Color(0.3, 0.1, 0.1), Color(0.5, 0.2, 0.2)],  # 빨강
	[Color(0.1, 0.3, 0.1), Color(0.2, 0.5, 0.2)],  # 초록
	[Color(0.3, 0.2, 0.1), Color(0.5, 0.4, 0.2)],  # 주황
	[Color(0.2, 0.2, 0.2), Color(0.4, 0.4, 0.4)],  # 회색
	[Color(0.3, 0.1, 0.2), Color(0.5, 0.2, 0.4)],  # 핑크
	[Color(0.1, 0.2, 0.2), Color(0.2, 0.4, 0.4)],  # 청록
]

const EFFECT_CHANGE_INTERVAL: float = 4.0
var effect_timer: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)

	if run_button:
		run_button.pressed.connect(_on_run_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if hold_button:
		hold_button.toggled.connect(_on_hold_toggled)
	if close_reserve_button:
		close_reserve_button.toggled.connect(_on_close_reserve_toggled)

	# 배경 셰이더 설정
	_setup_background_shader()

	# 보상 UI 초기화
	_update_rewards_ui()


func _process(delta: float) -> void:
	if current_state != BattleState.RUNNING:
		return
	
	_update_hero_atb(delta)
	_update_enemy_atb(delta)
	_update_background_effect(delta)


#region 전투 초기화 (새 시스템)
func setup_new(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false, p_is_boss: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	is_boss_battle = p_is_boss

	# 보상 초기화
	total_exp = 0
	total_gold = 0
	drop_items.clear()
	kill_count = 0
	window_mode = WindowMode.NORMAL

	# 루팅 배율 계산 (엘리트: x2, 보스: x4, 기본: x1)
	if is_boss_battle:
		loot_multiplier = 4.0
	elif is_elite_battle:
		loot_multiplier = 2.0
	else:
		loot_multiplier = 1.0

	# 버튼 초기화
	if run_button:
		run_button.disabled = is_boss_battle
		run_button.visible = true
	if hold_button:
		hold_button.button_pressed = false
		hold_button.visible = true
	if close_reserve_button:
		close_reserve_button.button_pressed = false
		close_reserve_button.visible = true

	for i in range(enemy_ids.size()):
		var enemy_id: String = str(enemy_ids[i])
		var make_elite: bool = (i == 0 and is_elite_battle)
		_spawn_single_enemy(enemy_id, make_elite)

	if is_elite_battle:
		_apply_elite_style()

	visible = true
	current_state = BattleState.STARTING

	# 보상 UI 업데이트
	_update_rewards_ui()

	# 배경 효과 초기화 (한 번만)
	_init_background_effect()

	await get_tree().create_timer(0.3).timeout
	_start_battle()


func add_enemy(enemy_id: String, is_elite: bool = false) -> void:
	# Hold 모드에서는 VICTORY 상태에서도 적 추가 가능
	if current_state == BattleState.DEFEAT:
		return
	if current_state == BattleState.VICTORY and window_mode != WindowMode.HOLD:
		return

	enemy_data_list.append(enemy_id)
	_spawn_single_enemy(enemy_id, is_elite)

	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var enemy_name: String = str(enemy_data.get("name", enemy_id))
	if is_elite:
		_send_log("⭐ 엘리트 %s 합류!" % enemy_name, Color.PURPLE)
	else:
		_send_log("%s 합류!" % enemy_name, Color.YELLOW)

	var idx: int = enemies.size() - 1
	enemy_atb[idx] = randf() * 0.3

	# Hold 모드에서 적이 추가되면 전투 재개
	if window_mode == WindowMode.HOLD and current_state == BattleState.VICTORY:
		current_state = BattleState.RUNNING
		set_process(true)
		_send_log("전투 재개!", Color.GREEN)

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
		
		# BattleManager 시그널로 HUD 업데이트
		BattleManager.hero_atb_changed.emit(hero.id, hero_atb[hero.id])
		
		if hero_atb[hero.id] >= ATB_MAX:
			_hero_attack(hero)
			hero_atb[hero.id] = 0.0
			BattleManager.hero_atb_changed.emit(hero.id, 0.0)
			
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
	## 영웅이 사용할 스킬 선택 - 토글된 스킬 우선 사용
	var usable_skills: Array = hero.get_usable_skills()
	
	# 힐러인 경우 아군 체력 확인
	if hero.is_skill_enabled("heal") and hero.can_use_skill("heal"):
		var wounded := _get_wounded_heroes()
		if not wounded.is_empty():
			return "heal"
	
	# 토글 ON이고 MP 충분한 스킬이 있으면 우선 사용
	if not usable_skills.is_empty():
		# 랜덤하게 선택
		return usable_skills[randi() % usable_skills.size()]
	
	# 토글된 스킬이 없거나 MP 부족하면 기본 공격
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
	
	# 크리티컬 시 진동 효과
	if is_crit:
		play_critical_shake()

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

	# 전체 공격 플래시 효과
	play_aoe_flash()
	
	_send_log("%s [%s] 발동!" % [hero.hero_name, skill_name], Color.YELLOW)

	var any_crit: bool = false
	for target in alive_enemies:
		var is_crit: bool = randf() * 100 < hero.get_crit()
		if is_crit:
			any_crit = true
		var damage: int = _calc_skill_damage(hero, target, skill_data, is_crit)

		target.take_damage(damage)
		target.play_hit_effect(is_crit)
		target.show_damage_number(damage, is_crit)

		if not target.is_alive():
			_on_enemy_defeated(target)
	
	# 크리티컬이 하나라도 있으면 진동
	if any_crit:
		play_critical_shake()


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

	# 원념 증가
	kill_count += 1

	# 보상은 항상 전투창에 쌓임 (아직 파티가 획득하지 않음)
	var exp_reward: int = enemy.exp_reward
	var gold_reward: int = enemy.get_gold_reward()
	var items: Array = enemy.roll_drops()

	total_exp += exp_reward
	total_gold += gold_reward
	drop_items.append_array(items)
	_update_rewards_ui()

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
		# Hold 모드: 적이 죽어도 창 유지 (보상 획득 지연)
		if window_mode == WindowMode.HOLD:
			set_process(false)  # 전투 멈춤
			current_state = BattleState.VICTORY
			_send_log("모든 적 처치! (보상 대기 중...)", Color.YELLOW)
			return false

		# Close 모드 또는 일반 모드: 보상 획득 + 창 닫기
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

	# 버튼 상태 업데이트
	if hold_button:
		hold_button.visible = false
	if close_reserve_button:
		close_reserve_button.visible = false
	if run_button:
		run_button.visible = false
	if close_button:
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

	# 버튼 상태 업데이트
	if hold_button:
		hold_button.visible = false
	if close_reserve_button:
		close_reserve_button.visible = false
	if run_button:
		run_button.visible = false
	if close_button:
		close_button.visible = true

	battle_ended.emit(battle_id, false)
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	## Run 버튼: 50% 보상만 받고 즉시 도주
	if is_boss_battle:
		_send_log("보스전에서는 도주할 수 없습니다!", Color.RED)
		return

	if current_state != BattleState.RUNNING and current_state != BattleState.VICTORY:
		return

	run_button.disabled = true
	hold_button.disabled = true
	close_reserve_button.disabled = true

	# 즉시 도주 (확률 판정 없음, 대신 50% 보상만)
	_run_with_partial_rewards()


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


#region 보상 UI 시스템
func _update_rewards_ui() -> void:
	## 상단 보상 패널 UI 업데이트
	if gold_label:
		gold_label.text = str(total_gold)
	if exp_label:
		exp_label.text = str(total_exp)
	if loot_label:
		loot_label.text = "x%d" % int(loot_multiplier)
	if kill_count_label:
		kill_count_label.text = str(kill_count)


func set_loot_multiplier(multiplier: float) -> void:
	## 루팅 배율 설정 (외부에서 호출 가능)
	loot_multiplier = maxf(1.0, multiplier)
	_update_rewards_ui()


func get_kill_count() -> int:
	## 원념 (적 처치 횟수) 반환
	return kill_count


func _add_rewards(exp: int, gold: int, items: Array) -> void:
	## 보상 추가 (전투창에 쌓임)
	total_exp += exp
	total_gold += gold
	drop_items.append_array(items)
	_update_rewards_ui()
#endregion


func get_max_enemies() -> int:
	## 이 전투창의 최대 적 수 반환 (기본 3 + BattleManager charm 효과)
	return BattleManager.get_max_enemies_per_window()


#region 전투창 모드 시스템
func _on_hold_toggled(button_pressed: bool) -> void:
	## Hold 모드 토글: 보상 계속 쌓기 + 적 다 죽어도 창 유지 (보상 획득 지연)
	if button_pressed:
		window_mode = WindowMode.HOLD
		if close_reserve_button:
			close_reserve_button.button_pressed = false
		_send_log("Hold: 전투창 유지 (보상 지연)", Color.ORANGE)
	else:
		window_mode = WindowMode.NORMAL
		_send_log("Hold 해제", Color.GREEN)
		# Hold 해제 시 적이 없으면 바로 승리 처리
		if not has_alive_enemies():
			_end_battle_victory()


func _on_close_reserve_toggled(button_pressed: bool) -> void:
	## Close 모드 토글: 적이 사라지면 자동 닫기 예약
	if button_pressed:
		window_mode = WindowMode.CLOSE_RESERVED
		if hold_button:
			hold_button.button_pressed = false
		_send_log("Close: 적 소멸 시 보상 획득", Color.YELLOW)

		# 이미 적이 없으면 바로 닫기
		if not has_alive_enemies():
			_close_with_rewards()
	else:
		window_mode = WindowMode.NORMAL
		_send_log("Close 예약 해제", Color.GRAY)


func _close_with_rewards() -> void:
	## 현재까지 쌓인 보상을 받고 창 닫기
	if total_exp > 0 or total_gold > 0:
		PartyManager.distribute_exp(total_exp)
		GameManager.add_gold(total_gold)
		_send_log("보상 획득! EXP +%d, Gold +%d" % [total_exp, total_gold], Color.CYAN)

	if not drop_items.is_empty():
		_start_loot_animations()

	call_deferred("_emit_party_updated")
	current_state = BattleState.ENDED
	battle_ended.emit(battle_id, true)

	# 잠시 후 창 닫기 (애니메이션 시간)
	await get_tree().create_timer(0.3).timeout
	queue_free()


func _run_with_partial_rewards() -> void:
	## Run: 50% 보상만 받고 즉시 닫기
	var partial_exp: int = int(total_exp * 0.5)
	var partial_gold: int = int(total_gold * 0.5)

	if partial_exp > 0 or partial_gold > 0:
		PartyManager.distribute_exp(partial_exp)
		GameManager.add_gold(partial_gold)
		_send_log("도주! 보상 50%%만 획득: EXP +%d, Gold +%d" % [partial_exp, partial_gold], Color.ORANGE)
	else:
		_send_log("도주!", Color.ORANGE)

	# 드랍 아이템은 50% 확률로 획득
	var partial_drops: Array = []
	for item in drop_items:
		if randf() < 0.5:
			partial_drops.append(item)

	if not partial_drops.is_empty():
		drop_items = partial_drops
		_start_loot_animations()

	call_deferred("_emit_party_updated")
	current_state = BattleState.ESCAPED
	set_process(false)
	battle_ended.emit(battle_id, false)

	await get_tree().create_timer(0.3).timeout
	queue_free()
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


#region Mother 2 스타일 배경 효과
var is_shaking: bool = false
var shake_time: float = 0.0
var shake_intensity: float = 0.0
var shake_original_pos: Vector2 = Vector2.ZERO

func _setup_background_shader() -> void:
	background = get_node_or_null("MainVBox/BattleArea/Background")
	if not background:
		return
	
	# 셰이더 로드
	var shader: Shader = load("res://resources/shaders/mother2_bg.gdshader")
	if shader:
		bg_material = ShaderMaterial.new()
		bg_material.shader = shader
		background.material = bg_material
	else:
		# 셰이더가 없으면 기본 색상 애니메이션 사용
		bg_material = null


func _update_background_effect(delta: float) -> void:
	var speed_mult: float = BattleManager.get_battle_speed()
	effect_time += delta * speed_mult
	
	# 셰이더 시간 업데이트
	if bg_material:
		bg_material.set_shader_parameter("time", effect_time)
	elif background:
		# 셰이더 없으면 간단한 색상 애니메이션
		var t: float = (sin(effect_time * 2.0) + 1.0) / 2.0
		var palette: Array = COLOR_PALETTES[current_effect % COLOR_PALETTES.size()]
		background.color = palette[0].lerp(palette[1], t)
	
	# 진동 효과 업데이트
	if is_shaking:
		shake_time -= delta
		if shake_time <= 0:
			is_shaking = false
			position = shake_original_pos
		else:
			var shake_x: float = (randf() - 0.5) * shake_intensity
			var shake_y: float = (randf() - 0.5) * shake_intensity
			position = shake_original_pos + Vector2(shake_x, shake_y)


func _init_background_effect() -> void:
	# 전투 시작 시 한 번만 랜덤 선택 (변경 없음)
	current_effect = randi() % 8
	effect_time = 0.0
	
	# 랜덤 색상 팔레트 선택
	var palette_idx: int = randi() % COLOR_PALETTES.size()
	var palette: Array = COLOR_PALETTES[palette_idx]
	
	if bg_material:
		bg_material.set_shader_parameter("effect_type", current_effect)
		bg_material.set_shader_parameter("color1", Vector3(palette[0].r, palette[0].g, palette[0].b))
		bg_material.set_shader_parameter("color2", Vector3(palette[1].r, palette[1].g, palette[1].b))
	elif background:
		background.color = palette[0]


func play_critical_shake() -> void:
	## 크리티컬 공격 시 진동 효과
	if not is_shaking:
		shake_original_pos = position  # 현재 위치 저장
	is_shaking = true
	shake_time = 0.3
	shake_intensity = 8.0


func play_aoe_flash() -> void:
	## 전체 공격 시 흰색 번쩍 효과
	if background:
		var original_color: Color = background.color
		var original_material = background.material
		
		# 흰색 플래시
		background.material = null
		background.color = Color.WHITE
		
		# 0.1초 후 원래대로
		var tween := create_tween()
		tween.tween_interval(0.1)
		tween.tween_callback(func():
			background.material = original_material
			if bg_material:
				background.color = Color.WHITE  # 셰이더가 색상 덮어씀
			else:
				background.color = original_color
		)
#endregion
