extends PanelContainer
class_name BattleWindow
## BattleWindow: 턴제 전투창
## - ATBManager에서 턴 순서를 관리 (DEX 기반)
## - 전투 중 적 동적 추가 지원

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated
signal turn_started(unit_name: String, is_hero: bool)
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



# === 보상 ===
var total_gold: int = 0
var drop_items: Array = []
var loot_multiplier: float = 1.0  # 루팅 배율 (아이템 등장 확률 배수)
var elite_gold: int = 0  # 엘리트 확정 보상 (페널티 면제)
var elite_items: Array = []  # 엘리트 확정 아이템 (페널티 면제)

# === 전투창 모드 ===
enum WindowMode { NORMAL, HOLD, CLOSE_RESERVED }
var window_mode: WindowMode = WindowMode.NORMAL
var is_blockaded: bool = false  # 봉쇄 모드 (적 추가 차단)

# === UI 참조 ===
@onready var enemy_container: HBoxContainer = $MainVBox/BattleArea/EnemyContainer
@onready var run_button: Button = %RunButton
@onready var close_button: Button = $MainVBox/TopBar/CloseButton
@onready var battle_area: PanelContainer = $MainVBox/BattleArea

# === 동적 생성 UI ===
var is_waiting_for_claim: bool = false  # 보상 대기 상태 (적 전멸 후)

# === 보상 UI (전투창 중앙) ===
var claim_reward_panel: CenterContainer = null
var claim_button: Button = null
var claim_gold_label: Label = null
var claim_item_list_label: Label = null

var is_waiting_for_enemies: bool = false  # 적 대기 모드 (반투명)

# === 활성 특성 ===
var active_traits: Array = []  # 현재 전투에 적용되는 특성 목록


# === 도주 설정 ===
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

# === 마우스 드래그 이동 ===
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

# === 적 호버 툴팁 ===
var _enemy_tooltip: PanelContainer = null
var _hovered_enemy: BattleEnemy = null


func _ready() -> void:
	visible = false
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS  # 게임 일시정지 중에도 입력 받기

	# 도망 버튼 연결
	if run_button:
		run_button.visible = true
		run_button.pressed.connect(_on_run_button_pressed)

	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# 마우스 GUI 입력 연결
	gui_input.connect(_on_gui_input)


	# 배경 셰이더 설정
	_setup_background_shader()

	# 보상 받기 UI 생성
	_setup_claim_reward_ui()

	# 봉쇄 버튼 생성
	_setup_blockade_button()

	# 적 호버 툴팁 생성
	_setup_enemy_tooltip()


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	if current_state != BattleState.RUNNING:
		return

	_update_background_effect(delta)


#region 전투 초기화 (새 시스템)
func setup_new(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false, p_is_boss: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	is_boss_battle = p_is_boss

	# 보상 초기화
	total_gold = 0
	drop_items.clear()
	elite_gold = 0
	elite_items.clear()
	window_mode = WindowMode.HOLD  # 기본값: Hold 모드

	# 루팅 배율 계산 (엘리트: x2, 보스: x4, 기본: x1)
	if is_boss_battle:
		loot_multiplier = 4.0
	elif is_elite_battle:
		loot_multiplier = 2.0
	else:
		loot_multiplier = 1.0

	for i in range(enemy_ids.size()):
		var enemy_id: String = str(enemy_ids[i])
		var make_elite: bool = (i == 0 and is_elite_battle)
		_spawn_single_enemy(enemy_id, make_elite)

	if is_elite_battle:
		_apply_elite_style()

	visible = true
	current_state = BattleState.STARTING

	# 배경 효과 초기화 (한 번만)
	_init_background_effect()

	# 파티 특성 수집 및 적용
	_collect_party_traits()
	_apply_trait_bonuses()

	await get_tree().create_timer(0.3).timeout
	_start_battle()


func add_enemy(enemy_id: String, is_elite: bool = false) -> void:
	# 패배/봉쇄 상태에서는 적 추가 불가
	if current_state == BattleState.DEFEAT or is_blockaded:
		return

	enemy_data_list.append(enemy_id)
	_spawn_single_enemy(enemy_id, is_elite)

	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var enemy_name: String = str(enemy_data.get("name", enemy_id))
	if is_elite:
		_send_log("⭐ 엘리트 %s 합류!" % enemy_name, Color.PURPLE)
	else:
		_send_log("%s 합류!" % enemy_name, Color.YELLOW)

	# 대기 모드에서 적이 추가되면 활성화
	if is_waiting_for_enemies:
		_exit_waiting_mode()
	# 보상 대기 중 적이 추가되면 전투 재개
	elif is_waiting_for_claim:
		_cancel_claim_waiting()
		_send_log("전투 재개!", Color.GREEN)
	# 승리 상태에서 적이 추가되면 전투 재개
	elif current_state == BattleState.VICTORY:
		current_state = BattleState.RUNNING
		set_process(true)
		_send_log("전투 재개!", Color.GREEN)

	_update_buttons_for_enemies()
	_shake_window()


func _cancel_claim_waiting() -> void:
	## 보상 대기 상태 취소 (적이 추가되었을 때)
	is_waiting_for_claim = false
	_hide_claim_ui()


func _update_buttons_for_enemies() -> void:
	## 적 존재 여부에 따라 버튼 상태 업데이트
	if run_button:
		run_button.disabled = not has_alive_enemies()


func _spawn_single_enemy(enemy_id: String, make_elite: bool = false) -> void:
	var battle_enemy: BattleEnemy = BATTLE_ENEMY_SCENE.instantiate()
	enemy_container.add_child(battle_enemy)
	battle_enemy.setup(enemy_id, make_elite)
	enemies.append(battle_enemy)
	# 마우스 호버 이벤트 연결
	_connect_enemy_hover(battle_enemy)


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


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	_update_buttons_for_enemies()
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


func get_alive_enemies() -> Array:
	## 살아있는 적 목록 반환
	var alive: Array = []
	for enemy in enemies:
		if enemy != null and enemy.is_alive():
			alive.append(enemy)
	return alive


func execute_enemy_turn(enemy: BattleEnemy) -> void:
	## ATBManager에서 호출하여 적의 턴 실행
	if current_state != BattleState.RUNNING:
		return
	if enemy == null or not enemy.is_alive():
		return

	turn_started.emit(enemy.enemy_name, false)
	_play_turn_effect()
	await _process_enemy_turn(enemy)

	_check_battle_end()


func execute_hero_attack(hero: Hero, skill_id: String, target: BattleEnemy) -> void:
	## ATBManager에서 호출하여 특정 적에게 영웅 공격 실행
	if hero == null or hero.is_dead:
		return

	if target == null or not target.is_alive():
		return

	_bring_to_front()
	BattleManager.hero_attacked.emit(hero.id)

	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	if skill_data.is_empty():
		skill_id = "basic_attack"
		skill_data = DataManager.get_skill("basic_attack")

	var skill_name: String = skill_data.get("name", "공격")
	var skill_type: String = skill_data.get("type", "physical")

	# 로그에 누구의 턴인지 표시
	_send_log("▶ %s의 턴" % hero.hero_name, Color.CYAN)

	# 짧은 대기 (연출)
	await get_tree().create_timer(0.15).timeout

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

	# 클래스별 공격 사운드
	if SoundManager:
		SoundManager.play_attack(hero.class_id, is_crit)

	target.take_damage(damage)
	target.play_hit_effect(is_crit)
	target.show_damage_number(damage, is_crit)

	# 강타 등 강력한 스킬 사용 시 진동 효과
	if skill_id == "power_strike" or skill_id == "shield_bash":
		play_skill_shake()
	elif is_crit:
		play_critical_shake()

	# 로그 색상: 스킬별 구분
	var log_color: Color
	if is_crit:
		log_color = Color.ORANGE
	elif skill_id == "power_strike":
		log_color = Color.TOMATO  # 강타는 붉은색
	elif skill_id == "shield_bash":
		log_color = Color.STEEL_BLUE  # 방패 강타는 파란색
	elif skill_type == "magic":
		log_color = Color.CYAN
	else:
		log_color = Color.WHITE

	var crit_text: String = " ⭐" if is_crit else ""

	if skill_id == "basic_attack":
		_send_log("%s → %s에게 %d%s" % [hero.hero_name, target.enemy_name, damage, crit_text], log_color)
	else:
		_send_log("%s ★%s★ → %s에게 %d%s" % [hero.hero_name, skill_name, target.enemy_name, damage, crit_text], log_color)

	if not target.is_alive():
		on_enemy_defeated(target)


func on_enemy_defeated(enemy: BattleEnemy) -> void:
	## 적 처치 처리 (ATBManager에서도 호출 가능)
	_on_enemy_defeated(enemy)


func _process_hero_turn(hero: Hero) -> void:
	## 영웅의 턴 처리
	if hero == null or hero.is_dead:
		return

	_bring_to_front()

	# 클래스별 스킬 선택 (간단한 AI)
	var skill_id: String = _select_hero_skill(hero)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)

	if skill_data.is_empty():
		skill_id = "basic_attack"
		skill_data = DataManager.get_skill("basic_attack")

	var target_type: String = skill_data.get("target", "single_enemy")

	# 로그에 누구의 턴인지 표시
	_send_log("▶ %s의 턴" % hero.hero_name, Color.CYAN)

	# 짧은 대기 (연출)
	await get_tree().create_timer(0.2).timeout

	# 타겟 타입에 따른 처리
	match target_type:
		"single_ally", "all_allies":
			_execute_ally_skill(hero, skill_id, skill_data, target_type)
		"all_enemies":
			_execute_aoe_attack(hero, skill_id, skill_data)
		_:  # single_enemy
			_execute_single_attack(hero, skill_id, skill_data)

	# 스킬 쿨타임 시작
	CooldownManager.start_cooldown(hero.id, skill_id)

	# 행동 후 잠시 대기
	await get_tree().create_timer(0.3).timeout


func _process_enemy_turn(enemy: BattleEnemy) -> void:
	## 적의 턴 처리
	if enemy == null or not enemy.is_alive():
		return

	_bring_to_front()

	# 로그에 누구의 턴인지 표시
	_send_log("▶ %s의 턴" % enemy.enemy_name, Color.ORANGE_RED)

	# 짧은 대기 (연출)
	await get_tree().create_timer(0.2).timeout

	_enemy_attack(enemy)

	# 행동 후 잠시 대기
	await get_tree().create_timer(0.3).timeout


func _select_hero_skill(hero: Hero) -> String:
	## 영웅의 스킬 선택 (간단한 AI)
	var skills: Array = hero.get_available_skills()

	# 클레릭은 체력이 낮은 아군이 있으면 힐 우선
	if hero.class_id == "cleric":
		var wounded: Array = _get_wounded_heroes()
		if not wounded.is_empty():
			for s in skills:
				var data: Dictionary = DataManager.get_skill(s)
				if data.get("type", "") == "heal":
					return s

	# 마법사는 적이 2마리 이상이면 전체 공격 우선
	if hero.class_id == "mage":
		if get_enemy_count() >= 2:
			for s in skills:
				var data: Dictionary = DataManager.get_skill(s)
				if data.get("target", "") == "all_enemies":
					return s

	# 도적은 확률적으로 특수 스킬 사용
	if hero.class_id == "thief":
		if randf() < 0.3:  # 30% 확률로 특수 스킬
			for s in skills:
				if s != "basic_attack":
					return s

	# 기본: 기본 공격
	return "basic_attack"


func _play_turn_effect() -> void:
	## 턴 시작 시각 효과
	if background:
		var tween := create_tween()
		tween.tween_property(background, "modulate", Color(1.2, 1.2, 1.2), 0.08)
		tween.tween_property(background, "modulate", Color.WHITE, 0.15)


func _hero_attack(hero: Hero, skill_id: String = "basic_attack") -> void:
	if hero == null or hero.is_dead:
		return

	if not has_alive_enemies():
		return

	_bring_to_front()
	BattleManager.hero_attacked.emit(hero.id)

	var skill_data: Dictionary = DataManager.get_skill(skill_id)

	# 스킬 데이터가 없으면 기본 공격으로 폴백
	if skill_data.is_empty():
		skill_id = "basic_attack"
		skill_data = DataManager.get_skill("basic_attack")

	var target_type: String = skill_data.get("target", "single_enemy")

	# 타겟 타입에 따른 처리
	match target_type:
		"single_ally", "all_allies":
			_execute_ally_skill(hero, skill_id, skill_data, target_type)
		"all_enemies":
			_execute_aoe_attack(hero, skill_id, skill_data)
		_:  # single_enemy
			_execute_single_attack(hero, skill_id, skill_data)

	# 스킬 쿨타임 시작
	CooldownManager.start_cooldown(hero.id, skill_id)


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

	# 클래스별 공격 사운드
	if SoundManager:
		SoundManager.play_attack(hero.class_id, is_crit)

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
		_send_log("%s [%s] → %s에게 %d%s" % [hero.hero_name, skill_name, target.enemy_name, damage, crit_text], log_color)

	# 도발 효과 적용 (방패 강타 등)
	var taunt_count: int = _get_skill_effect_int(skill_data, "taunt", 0)
	if taunt_count > 0:
		hero.apply_taunt(taunt_count)
		_send_log("%s 도발! (다음 %d회 공격 흡수)" % [hero.hero_name, taunt_count], Color.STEEL_BLUE)

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

	# 클래스별 공격 사운드
	if SoundManager:
		SoundManager.play_attack(hero.class_id, false)

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
		"dex": stat_value = hero.get_dex()
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


func _get_skill_effect_int(skill_data: Dictionary, effect_type: String, default_value: int) -> int:
	## 스킬 효과 정수 값 가져오기 (count 또는 value)
	var effects: Array = skill_data.get("effects", [])
	for effect in effects:
		if effect.get("type", "") == effect_type:
			# count 먼저 확인, 없으면 value
			if effect.has("count"):
				return int(effect.get("count", default_value))
			return int(effect.get("value", default_value))
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


func has_alive_enemies() -> bool:
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false
#endregion


#region 적 공격 시스템
func _enemy_attack(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		return

	var alive_heroes: Array = PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return

	_bring_to_front()

	# 도발 상태인 영웅이 있으면 우선 타겟
	var target: Hero = _find_taunt_target(alive_heroes)
	if target == null:
		target = alive_heroes[randi() % alive_heroes.size()]

	enemy.play_attack_effect()

	# 적 공격 사운드
	if SoundManager:
		SoundManager.play_enemy_attack()

	var is_evaded := randf() * 100 < target.get_eva()
	if is_evaded:
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
		return

	var is_crit := randf() * 100 < enemy.get_crit()
	var damage := _calc_enemy_damage(enemy, target, is_crit)

	# 도발 상태였으면 카운트 소모
	var was_taunting := target.consume_taunt()

	PartyManager.on_hero_damaged(target, damage)
	BattleManager.hero_damaged.emit(target.id)
	call_deferred("_emit_party_updated")

	var log_color: Color = Color.RED if is_crit else Color.YELLOW
	var crit_text: String = " (강타!)" if is_crit else ""
	var taunt_text: String = " [도발]" if was_taunting else ""
	_send_log("%s → %s에게 %d%s%s" % [enemy.enemy_name, target.hero_name, damage, crit_text, taunt_text], log_color)
	
	if target.is_dead:
		_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
		call_deferred("_emit_party_updated")


func _calc_enemy_damage(enemy: BattleEnemy, target: Hero, is_crit: bool) -> int:
	var atk := enemy.get_atk()
	var p_def := target.get_p_def()
	if is_crit:
		return maxi(1, atk)
	return maxi(1, atk - int(p_def / 2))


func _find_taunt_target(alive_heroes: Array) -> Hero:
	## 도발 상태인 영웅 찾기
	for hero in alive_heroes:
		if hero.has_taunt():
			return hero
	return null
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	_send_log("%s 처치!" % enemy.enemy_name, Color.LIME)

	# 보상 계산 (특성 적용)
	var gold_trait_mult: float = 1.0 + _get_trait_effect_float("gold_mult")

	var gold_reward: int = int(enemy.get_gold_reward() * gold_trait_mult)
	var items: Array = enemy.roll_drops()

	total_gold += gold_reward
	drop_items.append_array(items)

	# 엘리트 보상은 별도 저장 (도주 페널티 면제)
	if enemy.is_elite_version:
		elite_gold += gold_reward
		elite_items.append_array(items)

	# 엘리트 처치 시 특수 연출
	if enemy.is_elite_version:
		_play_elite_death_cinematic(enemy)
		return

	enemy.play_death_effect()

	# 모든 적이 처치되었는지 확인 후 보상 UI 표시
	call_deferred("_check_all_enemies_dead")


func _play_elite_death_cinematic(elite: BattleEnemy) -> void:
	## 엘리트 처치 특수 연출: 느려짐 → 나머지 해산 → 자동 보상

	# 1) 엘리트 느려지며 떨림 + "으어어…"
	_send_log("⭐ %s: 으어어…!" % elite.enemy_name, Color.MAGENTA)

	if elite.sprite:
		var slow_tween := create_tween()
		# 느리게 떨림
		for i in range(6):
			slow_tween.tween_property(elite, "position:x", elite.position.x + 3, 0.08)
			slow_tween.tween_property(elite, "position:x", elite.position.x - 3, 0.08)
		slow_tween.tween_property(elite, "position:x", elite.position.x, 0.05)
		await slow_tween.finished

	# 2) 엘리트 폭발 이펙트
	if elite.sprite:
		var burst_tween := create_tween()
		burst_tween.tween_property(elite, "scale", Vector2(1.3, 1.3), 0.1)
		burst_tween.tween_property(elite, "modulate", Color(2.0, 1.0, 2.0, 1.0), 0.1)
		burst_tween.tween_property(elite, "modulate:a", 0.0, 0.15)
		burst_tween.tween_property(elite, "scale", Vector2(0.0, 0.0), 0.1)
		await burst_tween.finished
	elite.visible = false

	# 3) 메시지: 엘리트 처치 + 전의 상실
	_send_log("⭐ 엘리트 적을 처치했다!", Color.GOLD)
	await get_tree().create_timer(0.3).timeout
	_send_log("적들은 전의를 상실했다.", Color.LIGHT_CORAL)
	await get_tree().create_timer(0.2).timeout

	# 4) 남은 적 즉시 해산 (보상 없이 소멸)
	for enemy in enemies:
		if enemy != null and enemy.is_alive() and enemy != elite:
			if enemy.sprite:
				var fade := create_tween()
				fade.tween_property(enemy, "modulate:a", 0.0, 0.3)
				fade.tween_callback(func(): enemy.visible = false)
			enemy.current_hp = 0

	await get_tree().create_timer(0.4).timeout

	# 5) 자동 보상 → 자동 닫기 (팡!)
	is_waiting_for_claim = false
	_hide_claim_ui()
	_end_battle_victory()


func _show_popup_text(title: String, subtitle: String, color: Color) -> void:
	## 전투창 중앙에 팝업 텍스트 표시
	# 가장 상위 노드(루트)에 직접 추가
	var root := get_tree().root

	# CanvasLayer를 루트에 추가
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	root.add_child(canvas_layer)

	# 배경 패널
	var bg := PanelContainer.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.9)
	bg_style.corner_radius_top_left = 8
	bg_style.corner_radius_top_right = 8
	bg_style.corner_radius_bottom_left = 8
	bg_style.corner_radius_bottom_right = 8
	bg_style.content_margin_left = 20
	bg_style.content_margin_right = 20
	bg_style.content_margin_top = 12
	bg_style.content_margin_bottom = 12
	bg.add_theme_stylebox_override("panel", bg_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(bg)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bg.add_child(inner_vbox)

	# 제목 라벨
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", color)
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	title_label.add_theme_constant_override("outline_size", 5)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(title_label)

	# 부제목 라벨
	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", Color.YELLOW)
	sub_label.add_theme_color_override("font_outline_color", Color.BLACK)
	sub_label.add_theme_constant_override("outline_size", 3)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(sub_label)

	# 즉시 위치 설정 (레이아웃 계산 전이라 수동으로 크기 추정)
	var estimated_width: float = 150.0
	var estimated_height: float = 80.0
	var window_center: Vector2 = global_position + size / 2
	bg.position = window_center - Vector2(estimated_width, estimated_height) / 2

	# 애니메이션 (call_deferred로 실제 크기 반영)
	_animate_popup.call_deferred(canvas_layer, bg)


func _animate_popup(canvas_layer: CanvasLayer, bg: PanelContainer) -> void:
	## 팝업 애니메이션
	if not is_instance_valid(canvas_layer) or not is_instance_valid(bg):
		return

	# 실제 크기로 위치 재조정
	var window_center: Vector2 = global_position + size / 2
	var popup_size: Vector2 = bg.size
	bg.position = window_center - popup_size / 2
	bg.pivot_offset = popup_size / 2

	# 애니메이션 시작 (처음엔 보이게)
	bg.modulate.a = 1.0
	bg.scale = Vector2(1.0, 1.0)

	# 2초 후 페이드 아웃
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(bg, "modulate:a", 0.0, 0.4)
	tween.tween_callback(canvas_layer.queue_free)


func _check_all_enemies_dead() -> void:
	## 모든 적이 처치되었는지 확인하고 보상 UI 표시
	_update_buttons_for_enemies()

	if is_waiting_for_claim:
		return  # 이미 보상 대기 중

	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)

	if alive_enemies.is_empty():
		_show_claim_reward_button()


func _check_battle_end() -> bool:
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)

	var alive_heroes: Array = PartyManager.get_alive_heroes()

	if alive_enemies.is_empty():
		# 적이 모두 사라짐 - 보상 버튼 표시 (각 전투창 독립 보상)
		_update_buttons_for_enemies()
		_show_claim_reward_button()
		return true

	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true

	return false


func _report_rewards_and_close() -> void:
	## 보상을 BattleManager에 누적하고 전투창 닫기
	BattleManager.add_accumulated_reward(0, total_gold, drop_items)

	_send_log("전투 종료! (Gold +%d)" % total_gold, Color.LIME)

	# 전투창 종료 (승리)
	current_state = BattleState.VICTORY
	set_process(false)
	battle_ended.emit(battle_id, true)

	_play_close_effect()


func _update_buttons_for_no_enemies() -> void:
	## 적이 없을 때 버튼 상태 업데이트
	pass


func _show_claim_reward_button() -> void:
	## 적이 모두 처치됨 - 보상 대기 상태로 전환
	is_waiting_for_claim = true

	# 보상 UI 표시
	_show_claim_ui()


func _claim_rewards_now() -> void:
	## 즉시 보상 획득 후 종료
	if not is_waiting_for_claim:
		return
	is_waiting_for_claim = false
	_hide_claim_ui()
	_end_battle_victory()


func _end_battle_victory() -> void:
	current_state = BattleState.VICTORY
	set_process(false)

	# 승리 사운드 재생
	if SoundManager != null:
		SoundManager.play_victory()

	_send_log("승리! Gold +%d" % total_gold, Color.CYAN)

	# 보상은 BattleManager에서 필드 드롭으로 처리
	call_deferred("_emit_party_updated")

	battle_ended.emit(battle_id, true)

	_play_close_effect()


func _play_reward_fly_animation() -> void:
	## 보상이 HUD로 날아가는 연출
	# 보상이 없으면 바로 닫기
	if total_gold <= 0 and drop_items.is_empty():
		_play_close_effect()
		return

	# 전투창의 화면상 위치 계산 (스크린 좌표)
	var start_pos: Vector2 = get_global_rect().get_center()

	# 타겟 위치 (화면 상단 중앙)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_pos: Vector2 = Vector2(viewport_size.x / 2, 60)

	# 최상위 레이어에 보상 아이콘들 생성 (일시정지 중에도 실행)
	var root := get_tree().root
	var fly_container := CanvasLayer.new()
	fly_container.layer = 100  # 최상위
	fly_container.process_mode = Node.PROCESS_MODE_ALWAYS  # 일시정지 중에도 애니메이션 실행
	root.add_child(fly_container)

	var fly_nodes: Array = []
	var delay: float = 0.0
	var delay_interval: float = 0.12

	# Gold 아이콘 생성
	if total_gold > 0:
		var gold_node := _create_fly_reward_node("💰 +%d G" % total_gold, Color(1.0, 0.9, 0.3))
		gold_node.position = start_pos
		fly_container.add_child(gold_node)
		fly_nodes.append({"node": gold_node, "delay": delay, "start": start_pos})
		delay += delay_interval

	# 아이템 아이콘들 생성 (최대 3개)
	var item_count: int = mini(drop_items.size(), 3)
	for i in range(item_count):
		var item_node := _create_fly_reward_node("🎁 아이템!", Color(0.9, 0.6, 1.0))
		item_node.position = start_pos
		fly_container.add_child(item_node)
		fly_nodes.append({"node": item_node, "delay": delay, "start": start_pos})
		delay += delay_interval

	# 날아가는 애니메이션 (get_tree().create_tween() 사용 - BattleWindow가 닫혀도 계속 실행)
	var total_duration: float = 0.5
	for fly_data in fly_nodes:
		var node: Control = fly_data.node
		var node_delay: float = fly_data.delay
		var node_start: Vector2 = fly_data.start

		# 초기 상태 - 보이는 상태로 시작
		node.modulate.a = 1.0
		node.scale = Vector2(0.5, 0.5)

		# 애니메이션 시작 (SceneTree에서 생성, 일시정지 중에도 실행)
		var tween := get_tree().create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 일시정지 중에도 실행
		tween.tween_interval(node_delay)

		# 팝업 효과로 나타나기
		tween.tween_property(node, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "scale", Vector2(1.0, 1.0), 0.08)

		# 날아가기 (곡선 경로) - position 사용
		var mid_pos: Vector2 = node_start.lerp(target_pos, 0.5) + Vector2(0, -40)
		tween.tween_property(node, "position", mid_pos, total_duration * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(node, "position", target_pos, total_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(node, "scale", Vector2(0.4, 0.4), total_duration * 0.5)
		tween.parallel().tween_property(node, "modulate:a", 0.0, 0.15)

	# 모든 애니메이션 완료 후 정리 및 닫기
	var cleanup_delay: float = delay + total_duration + 0.2
	var cleanup_tween := create_tween()
	cleanup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # 일시정지 중에도 실행
	cleanup_tween.tween_interval(cleanup_delay)
	cleanup_tween.tween_callback(fly_container.queue_free)
	cleanup_tween.tween_callback(_play_close_effect)


func _create_fly_reward_node(text: String, color: Color) -> Control:
	## 날아가는 보상 노드 생성
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.z_index = 100

	# 배경 패널
	var bg := PanelContainer.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = color
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	bg_style.content_margin_left = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_top = 4
	bg_style.content_margin_bottom = 4
	bg.add_theme_stylebox_override("panel", bg_style)
	container.add_child(bg)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bg.add_child(label)

	# 컨테이너 위치 오프셋 (중앙 정렬)
	container.position = Vector2(-60, -15)

	return container


func _play_close_effect() -> void:
	## 전투창 닫힘 이펙트
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.3).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _start_loot_animations() -> void:
	var delay: float = 0.0
	var delay_interval: float = 0.15

	# 먼저 모든 아이템을 즉시 처리 (자동 장착 또는 인벤토리 추가)
	for item_id in drop_items:
		if not InventoryManager.try_auto_equip(item_id):
			InventoryManager.add_item(item_id)

	# 그 후 애니메이션과 로그만 표시
	for item_id in drop_items:
		var start_pos: Vector2 = global_position + size / 2
		_delayed_loot_visual(item_id, start_pos, delay)

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


func _delayed_loot_visual(item_id: String, start_pos: Vector2, delay: float) -> void:
	## 아이템 드롭 시각 효과만 (아이템은 이미 처리됨)
	if delay > 0.0:
		var timer := get_tree().create_timer(delay)
		if timer:
			await timer.timeout
	loot_drop_requested.emit(item_id, start_pos)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	set_process(false)

	# 패배 사운드 재생
	if SoundManager != null:
		SoundManager.play_defeat()

	_send_log("전멸...", Color.DARK_RED)

	battle_ended.emit(battle_id, false)

	# 패배 시에도 닫힘 이펙트
	_play_close_effect()
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	pass


func _calculate_escape_chance() -> float:
	var party_avg_dex: int = PartyManager.get_party_average_dex()

	var enemy_total_dex: float = 0.0
	var alive_count: int = 0
	for enemy in enemies:
		if enemy.is_alive():
			enemy_total_dex += enemy.get_dex()
			alive_count += 1
	var enemy_avg_dex: float = enemy_total_dex / maxf(1.0, float(alive_count))

	var chance := BASE_ESCAPE_RATE + (party_avg_dex - enemy_avg_dex) * 2.0
	return clampf(chance, 5.0, 95.0)
#endregion


#region 보상 UI 시스템


func set_loot_multiplier(multiplier: float) -> void:
	## 루팅 배율 설정 (외부에서 호출 가능)
	loot_multiplier = maxf(1.0, multiplier)


func _add_rewards(_exp: int, gold: int, items: Array) -> void:
	## 보상 추가 (전투창에 쌓임)
	total_gold += gold
	drop_items.append_array(items)
#endregion


func get_max_enemies() -> int:
	## 이 전투창의 최대 적 수 반환 (기본 3 + 특성 효과)
	var base_max: int = BattleManager.get_max_enemies_per_window()
	var trait_bonus: int = _get_trait_effect_value("max_enemies")
	return maxi(1, base_max + trait_bonus)  # 최소 1


#region 특성 시스템
func _collect_party_traits() -> void:
	## 파티원들의 특성 수집
	active_traits.clear()
	for hero in PartyManager.get_alive_heroes():
		for trait_data in hero.get_traits():
			if not trait_data.is_empty():
				active_traits.append(trait_data)


func _apply_trait_bonuses() -> void:
	## 특성 보너스 적용 (전투 시작 시)
	# 루팅 배율 보너스
	var loot_trait_mult: float = _get_trait_effect_float("loot_mult")
	if loot_trait_mult > 0:
		loot_multiplier += loot_multiplier * loot_trait_mult


func _get_trait_effect_value(effect_type: String, condition: String = "") -> int:
	## 특정 효과 타입의 총합 반환
	var total: int = 0
	for trait_data in active_traits:
		var effect: Dictionary = trait_data.get("effect", {})
		if effect.get("type", "") == effect_type:
			var trait_condition: String = effect.get("condition", "")
			if condition.is_empty() or trait_condition.is_empty() or trait_condition == condition:
				total += int(effect.get("value", 0))
	return total


func _get_trait_effect_float(effect_type: String, condition: String = "") -> float:
	## 특정 효과 타입의 총합 반환 (실수)
	var total: float = 0.0
	for trait_data in active_traits:
		var effect: Dictionary = trait_data.get("effect", {})
		if effect.get("type", "") == effect_type:
			var trait_condition: String = effect.get("condition", "")
			if condition.is_empty() or trait_condition.is_empty() or trait_condition == condition:
				total += float(effect.get("value", 0.0))
	return total


func _check_trait_condition(condition: String) -> bool:
	## 특성 조건 확인
	match condition:
		"enemies_gte_3":
			return get_enemy_count() >= 3
		"enemies_eq_1":
			return get_enemy_count() == 1
		_:
			return true
#endregion


#region 전투창 모드 시스템
func _close_with_rewards() -> void:
	## 현재까지 쌓인 보상을 받고 창 닫기
	## 골드/아이템은 필드 드롭으로 처리됨 (FieldDrop에서 수집 시 지급)
	if total_gold > 0:
		_send_log("보상 획득! Gold +%d" % total_gold, Color.CYAN)

	call_deferred("_emit_party_updated")
	current_state = BattleState.ENDED
	battle_ended.emit(battle_id, true)


func _run_with_partial_rewards() -> void:
	## Run: 50% 보상만 받고 즉시 닫기 (엘리트 보상은 100% 보장)
	# 일반 보상에서 엘리트 보상 분리
	var normal_gold: int = total_gold - elite_gold
	var partial_gold: int = int(normal_gold * 0.5) + elite_gold  # 엘리트 골드는 전액

	if partial_gold > 0:
		GameManager.add_gold(partial_gold)
		if elite_gold > 0:
			_send_log("도주! 보상 50%% + 엘리트 보상: Gold +%d" % partial_gold, Color.ORANGE)
		else:
			_send_log("도주! 보상 50%%만 획득: Gold +%d" % partial_gold, Color.ORANGE)
	else:
		_send_log("도주!", Color.ORANGE)

	# 드랍 아이템: 일반은 50% 확률, 엘리트는 확정
	var partial_drops: Array = []
	# 엘리트 아이템 전부 확보
	partial_drops.append_array(elite_items)
	# 일반 아이템은 50% 확률
	for item in drop_items:
		if item in elite_items:
			continue  # 이미 추가됨
		if randf() < 0.5:
			partial_drops.append(item)

	if not partial_drops.is_empty():
		drop_items = partial_drops
		for item_id in drop_items:
			if not InventoryManager.try_auto_equip(item_id):
				InventoryManager.add_item(item_id)

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


func _on_run_button_pressed() -> void:
	## 도망 버튼 클릭 - 50% 보상만 받고 즉시 종료
	if current_state != BattleState.RUNNING:
		return
	_run_with_partial_rewards()
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
	effect_time += delta
	
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


func play_skill_shake() -> void:
	## 강타 등 스킬 사용 시 진동 효과
	if not is_shaking:
		shake_original_pos = position
	is_shaking = true
	shake_time = 0.2
	shake_intensity = 5.0


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


#region 보상 받기 UI
func _setup_claim_reward_ui() -> void:
	## 전투창 중앙에 보상받기 UI 생성 (숨겨진 상태로)
	claim_reward_panel = CenterContainer.new()
	claim_reward_panel.visible = false
	claim_reward_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	claim_reward_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.8, 0.4)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 15
	panel_style.content_margin_right = 15
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	claim_reward_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# --- 상단: 아이템 목록 ---
	# 골드 라벨
	claim_gold_label = Label.new()
	claim_gold_label.text = "💰 0 Gold"
	claim_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claim_gold_label.add_theme_font_size_override("font_size", 11)
	claim_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(claim_gold_label)

	# 아이템 목록 라벨 (멀티라인)
	claim_item_list_label = Label.new()
	claim_item_list_label.text = ""
	claim_item_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claim_item_list_label.add_theme_font_size_override("font_size", 10)
	claim_item_list_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(claim_item_list_label)

	# 보상받기 버튼
	claim_button = Button.new()
	claim_button.text = "보상받기"
	claim_button.custom_minimum_size = Vector2(80, 32)
	claim_button.add_theme_font_size_override("font_size", 14)
	claim_button.pressed.connect(_on_claim_button_pressed)
	vbox.add_child(claim_button)

	battle_area.add_child(claim_reward_panel)


func _on_claim_button_pressed() -> void:
	## 보상 받기 버튼 클릭
	if is_waiting_for_claim:
		_claim_rewards_now()


func _show_claim_ui() -> void:
	## 보상 UI 표시 및 업데이트
	if not claim_reward_panel:
		return

	claim_gold_label.text = "💰 %d Gold" % total_gold

	if drop_items.is_empty():
		claim_item_list_label.text = ""
		claim_item_list_label.visible = false
	else:
		var item_lines: Array = []
		for item_id in drop_items:
			var item_name: String = _get_item_display_name(item_id)
			item_lines.append(item_name)
		claim_item_list_label.text = "\n".join(item_lines)
		claim_item_list_label.visible = true

	claim_reward_panel.visible = true


func _get_item_display_name(item_id: String) -> String:
	## 아이템 ID로 표시용 이름 반환
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if not equip_data.is_empty():
		var rarity: String = str(equip_data.get("rarity", "common"))
		var item_name: String = str(equip_data.get("name", item_id))
		match rarity:
			"magic":
				return "🔷 %s" % item_name
			"legendary":
				return "🌟 %s" % item_name
			_:
				return "⚔️ %s" % item_name
	var item_data: Dictionary = DataManager.get_item(item_id)
	if not item_data.is_empty():
		return "📜 %s" % str(item_data.get("name", item_id))
	return item_id


func _hide_claim_ui() -> void:
	## 보상 UI 숨기기
	if claim_reward_panel:
		claim_reward_panel.visible = false
#endregion

#region 봉쇄 버튼
var blockade_button: Button = null

func _setup_blockade_button() -> void:
	## 좌측 하단에 봉쇄 토글 버튼 생성
	var bottom_bar = get_node_or_null("MainVBox/BottomBar")
	if not bottom_bar:
		return

	blockade_button = Button.new()
	blockade_button.text = "봉쇄"
	blockade_button.toggle_mode = true
	blockade_button.tooltip_text = "활성화 시 적이 더 이상 이 전투창에 들어오지 않습니다"
	blockade_button.custom_minimum_size = Vector2(50, 26)
	blockade_button.add_theme_font_size_override("font_size", 10)
	blockade_button.toggled.connect(_on_blockade_toggled)
	bottom_bar.add_child(blockade_button)
	bottom_bar.move_child(blockade_button, 0)


func _on_blockade_toggled(toggled_on: bool) -> void:
	is_blockaded = toggled_on
	if blockade_button:
		if toggled_on:
			blockade_button.modulate = Color(1.0, 0.5, 0.5)
		else:
			blockade_button.modulate = Color.WHITE
#endregion


func _enter_waiting_mode() -> void:
	## 적 대기 모드 진입 (반투명 + 비활성화)
	current_state = BattleState.VICTORY  # 임시 상태
	set_process(false)
	modulate.a = 0.4  # 반투명


func _exit_waiting_mode() -> void:
	## 적 대기 모드 해제 (활성화)
	is_waiting_for_enemies = false
	modulate.a = 1.0  # 불투명
	current_state = BattleState.RUNNING
	set_process(true)
	_send_log("전투 재개!", Color.GREEN)


#region 마우스 인터랙션
func _on_gui_input(event: InputEvent) -> void:
	## 마우스 드래그로 전투창 이동
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_dragging = true
				_drag_offset = event.global_position - global_position
				_bring_to_front()
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		global_position = event.global_position - _drag_offset
		# 화면 밖으로 나가지 않도록 제한
		var vp_size := get_viewport().get_visible_rect().size
		global_position.x = clampf(global_position.x, -size.x + 40, vp_size.x - 40)
		global_position.y = clampf(global_position.y, 0, vp_size.y - 30)


func _setup_enemy_tooltip() -> void:
	## 적 호버 시 표시할 툴팁 패널 생성
	_enemy_tooltip = PanelContainer.new()
	_enemy_tooltip.name = "EnemyTooltip"
	_enemy_tooltip.visible = false
	_enemy_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_tooltip.z_index = 200

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_enemy_tooltip.add_theme_stylebox_override("panel", style)

	add_child(_enemy_tooltip)


func _connect_enemy_hover(enemy: BattleEnemy) -> void:
	## 적 스프라이트에 마우스 호버 이벤트 연결
	if enemy == null:
		return

	# 적 Control에 마우스 이벤트 수신 설정
	enemy.mouse_filter = Control.MOUSE_FILTER_STOP
	enemy.mouse_entered.connect(_on_enemy_mouse_entered.bind(enemy))
	enemy.mouse_exited.connect(_on_enemy_mouse_exited.bind(enemy))


func _on_enemy_mouse_entered(enemy: BattleEnemy) -> void:
	if enemy == null or not enemy.is_alive():
		return
	_hovered_enemy = enemy
	_show_enemy_tooltip(enemy)


func _on_enemy_mouse_exited(enemy: BattleEnemy) -> void:
	if _hovered_enemy == enemy:
		_hovered_enemy = null
		_hide_enemy_tooltip()


func _show_enemy_tooltip(enemy: BattleEnemy) -> void:
	## 적 정보 툴팁 표시
	if _enemy_tooltip == null:
		return

	# 기존 내용 제거
	for child in _enemy_tooltip.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_tooltip.add_child(vbox)

	# 이름
	var name_label := Label.new()
	name_label.text = enemy.enemy_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if enemy.is_elite_version:
		name_label.add_theme_color_override("font_color", Color.PURPLE)
	elif enemy.enemy_type == "boss":
		name_label.add_theme_color_override("font_color", Color.ORANGE)
	else:
		name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(name_label)

	# HP
	var hp_label := Label.new()
	hp_label.text = "HP: %d/%d" % [enemy.current_hp, enemy.max_hp]
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_label)

	# 스탯
	var stats_label := Label.new()
	stats_label.text = "ATK:%d DEF:%d SPD:%d" % [enemy.get_atk(), enemy.get_p_def(), enemy.get_dex()]
	stats_label.add_theme_font_size_override("font_size", 8)
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stats_label)

	# 타입
	var type_label := Label.new()
	type_label.text = "타입: %s" % enemy.damage_type
	type_label.add_theme_font_size_override("font_size", 8)
	type_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(type_label)

	# 위치: 적 위 또는 아래
	_enemy_tooltip.visible = true
	await get_tree().process_frame
	var tooltip_pos := enemy.global_position + Vector2(0, -_enemy_tooltip.size.y - 4)
	if tooltip_pos.y < global_position.y:
		tooltip_pos = enemy.global_position + Vector2(0, enemy.size.y + 2)
	_enemy_tooltip.global_position = tooltip_pos


func _hide_enemy_tooltip() -> void:
	if _enemy_tooltip:
		_enemy_tooltip.visible = false
#endregion




