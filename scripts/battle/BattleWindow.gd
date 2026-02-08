extends PanelContainer
class_name BattleWindow
## BattleWindow: ATB 전투창
## - 물리: DEX 기반, 마법: INT 기반 ATB 게이지 충전
## - 게이지가 가득 차면 행동 (실시간 전투)
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

# === ATB 시스템 ===
# ATB (Active Time Battle) - 적만 로컬 관리 (영웅은 ATBManager에서 중앙 관리)
var enemy_atb_units: Array = []  # [{ref: BattleEnemy, atb: float, speed: int}]
var is_processing_action: bool = false
var action_delay_timer: float = 0.0
var atb_paused: bool = false  # ATBManager에서 일시정지 제어
var _is_hover_paused: bool = false  # 마우스 호버 시 일시정지
const ATB_FILL_RATE: float = 30.0  # 기본 ATB 충전 속도
const ATB_MAX: float = 100.0  # ATB 최대값
const ACTION_DELAY: float = 0.3  # 액션 후 딜레이


# === 보상 ===
var total_gold: int = 0
var drop_items: Array = []
var loot_multiplier: float = 1.0  # 루팅 배율 (아이템 등장 확률 배수)

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

# === 원념 (Grudge) 게이지 시스템 ===
var grudge_value: float = 0.0  # 현재 원념 수치 (0 ~ GRUDGE_MAX)
var grudge_level: int = 1  # 현재 원념 레벨 (1~5)
const GRUDGE_MAX: float = 100.0  # 전체 게이지 최대값
const GRUDGE_PER_KILL: float = 25.0  # 적 1마리 처치 시 증가량 (테스트: 킬당 레벨 1 상승)
const GRUDGE_LEVEL_THRESHOLDS: Array = [0.0, 25.0, 50.0, 75.0, 100.0]  # Lv1~5 경계값
const GRUDGE_LEVEL_ICONS: Array = ["⚔", "💢", "👁", "💀"]  # Lv2/3/4/5 노치 아이콘
const GRUDGE_LEVEL_LABELS: Array = ["증원", "분노", "전조", "엘리트"]  # 노치 설명
const GRUDGE_RAGE_ATB_MULT: float = 1.5  # Lv3+ 적 ATB 속도 배율

# 원념 UI 참조
var grudge_panel: PanelContainer = null
var grudge_bar: Control = null  # 게이지 바 배경
var grudge_fill: ColorRect = null  # 게이지 채움
var grudge_level_label: Label = null  # 레벨 텍스트
var grudge_notch_icons: Array = []  # 노치 아이콘들

# 원념 Lv4+ 테두리 펄스
var _grudge_border_style: StyleBoxFlat = null
var _grudge_border_pulse_time: float = 0.0


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

	# 원념 게이지 UI 생성
	_setup_grudge_ui()

	# 보상 받기 UI 생성
	_setup_claim_reward_ui()

	# 봉쇄 버튼 생성
	_setup_blockade_button()

	# 적 호버 툴팁 생성
	_setup_enemy_tooltip()


func _process(delta: float) -> void:
	if current_state != BattleState.RUNNING:
		return

	# 마우스 호버 일시정지 체크 (전투창 영역 전체)
	_is_hover_paused = get_global_rect().has_point(get_global_mouse_position())

	_update_atb_system(delta)
	_update_background_effect(delta)

	# 원념 Lv4+ 테두리 펄스
	if grudge_level >= 4 and _grudge_border_style:
		_update_grudge_border_pulse(delta)


#region 전투 초기화 (새 시스템)
func setup_new(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false, p_is_boss: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	is_boss_battle = p_is_boss

	# 보상 초기화
	total_gold = 0
	drop_items.clear()
	window_mode = WindowMode.HOLD  # 기본값: Hold 모드

	# 원념 초기화
	grudge_value = 0.0
	grudge_level = 1
	_grudge_border_style = null
	_grudge_border_pulse_time = 0.0
	modulate = Color.WHITE
	_update_grudge_ui()

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

	# ATB에 새 적 추가
	_add_enemy_to_atb(enemies.back())

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
	is_processing_action = false  # 액션 처리 상태 초기화
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


func _init_atb_system() -> void:
	## ATB 시스템 초기화 (적만 로컬 관리)
	enemy_atb_units.clear()
	is_processing_action = false
	action_delay_timer = 0.0
	atb_paused = false

	# 적들만 ATB에 추가 (영웅은 ATBManager에서 중앙 관리)
	for enemy in enemies:
		if enemy != null and enemy.is_alive():
			var enemy_spd: int = enemy.get_atb_speed()
			var initial_atb: float = randf_range(0, 20) + enemy_spd * 0.3
			enemy_atb_units.append({
				"ref": enemy,
				"atb": minf(initial_atb, ATB_MAX - 1),
				"speed": enemy_spd
			})

	_send_log("전투 시작!", Color.LIGHT_GRAY)


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	_init_atb_system()
	_update_buttons_for_enemies()
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


#region ATB 시스템
func _update_atb_system(delta: float) -> void:
	## ATB 게이지 충전 및 액션 처리 (적만 처리, 영웅은 ATBManager에서 중앙 관리)
	if is_processing_action or atb_paused or _is_hover_paused:
		return

	# 액션 딜레이 처리
	if action_delay_timer > 0:
		action_delay_timer -= delta
		return

	# 적 ATB 게이지 충전
	var ready_enemies: Array = []
	for unit in enemy_atb_units:
		var enemy: BattleEnemy = unit["ref"]
		if enemy == null or not enemy.is_alive():
			continue

		# 아직 행동 준비 안 된 적은 게이지 충전
		if unit["atb"] < ATB_MAX:
			var unit_speed: float = float(unit["speed"])
			var rage_mult: float = GRUDGE_RAGE_ATB_MULT if grudge_level >= 3 else 1.0
			var fill_amount: float = ATB_FILL_RATE * (unit_speed / 10.0) * rage_mult * delta
			unit["atb"] = minf(unit["atb"] + fill_amount, ATB_MAX)

		# 게이지가 가득 찬 적은 준비 목록에 추가
		if unit["atb"] >= ATB_MAX:
			ready_enemies.append(unit)

	# 준비된 적 중 가장 빠른 적이 행동
	if not ready_enemies.is_empty():
		ready_enemies.sort_custom(_compare_enemy_atb_priority)
		_execute_enemy_atb_action(ready_enemies[0])


func _compare_enemy_atb_priority(a: Dictionary, b: Dictionary) -> bool:
	## 적 ATB 우선순위 비교 (속도 높은 순)
	return a["speed"] > b["speed"]


func _execute_enemy_atb_action(unit: Dictionary) -> void:
	## 적 ATB 액션 실행
	is_processing_action = true
	var enemy: BattleEnemy = unit["ref"]
	var unit_name: String = enemy.enemy_name

	turn_started.emit(unit_name, false)
	_play_turn_effect()
	await _process_enemy_turn(enemy)

	# ATB 게이지 리셋
	unit["atb"] = 0.0

	# 전투 종료 체크
	if _check_battle_end():
		return

	# 다음 액션 준비
	is_processing_action = false
	action_delay_timer = ACTION_DELAY


func _add_enemy_to_atb(enemy: BattleEnemy) -> void:
	## 새로운 적을 ATB 시스템에 추가
	if enemy == null or not enemy.is_alive():
		return

	# 이미 추가되어 있는지 확인
	for unit in enemy_atb_units:
		if unit["ref"] == enemy:
			return

	var enemy_spd: int = enemy.get_atb_speed()
	var initial_atb: float = randf_range(0, 20) + enemy_spd * 0.3
	enemy_atb_units.append({
		"ref": enemy,
		"atb": minf(initial_atb, ATB_MAX - 1),
		"speed": enemy_spd
	})


func set_atb_paused(paused: bool) -> void:
	## ATBManager에서 호출하여 ATB 일시정지/재개
	atb_paused = paused


func get_alive_enemies() -> Array:
	## 살아있는 적 목록 반환
	var alive: Array = []
	for enemy in enemies:
		if enemy != null and enemy.is_alive():
			alive.append(enemy)
	return alive


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

	# 글로벌 킬 카운트 (HUD 표시용)
	BattleManager.add_global_kill_count(1)

	# 보상 계산 (특성 적용)
	var gold_trait_mult: float = 1.0 + _get_trait_effect_float("gold_mult")

	var gold_reward: int = int(enemy.get_gold_reward() * gold_trait_mult)
	var items: Array = enemy.roll_drops()

	total_gold += gold_reward
	drop_items.append_array(items)

	enemy.play_death_effect()

	# 원념 게이지 증가
	_add_grudge(GRUDGE_PER_KILL)

	# 모든 적이 처치되었는지 확인 후 보상 UI 표시
	call_deferred("_check_all_enemies_dead")


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
	## 적이 없을 때 버튼 상태 업데이트 (현재 고/스톱 시스템 사용)
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

	# 타겟 위치 (화면 상단 중앙 - 원념 패널 위치)
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


#region 도주 시스템 (미사용 - 고/스톱 시스템으로 대체)
func _on_run_pressed() -> void:
	## Run 버튼: 현재 사용 안함 (고/스톱 시스템 사용)
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
	## 이 전투창의 최대 적 수 반환 (기본 3 + 특성 효과 + 원념 보너스)
	var base_max: int = BattleManager.get_max_enemies_per_window()
	var trait_bonus: int = _get_trait_effect_value("max_enemies")
	# 원념 Lv2~4에서 각각 +1 (최대 +3)
	var grudge_bonus: int = clampi(grudge_level - 1, 0, 3)
	return maxi(1, base_max + trait_bonus + grudge_bonus)  # 최소 1


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
	## Run: 50% 보상만 받고 즉시 닫기
	var partial_gold: int = int(total_gold * 0.5)

	if partial_gold > 0:
		GameManager.add_gold(partial_gold)
		_send_log("도주! 보상 50%%만 획득: Gold +%d" % partial_gold, Color.ORANGE)
	else:
		_send_log("도주!", Color.ORANGE)

	# 드랍 아이템은 50% 확률로 획득
	var partial_drops: Array = []
	for item in drop_items:
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


#region 원념 (Grudge) 게이지 시스템
func _setup_grudge_ui() -> void:
	## 전투창 하단 바 위에 원념 게이지 UI 생성
	var main_vbox = get_node_or_null("MainVBox")
	if not main_vbox:
		return

	# 원념 패널 컨테이너
	grudge_panel = PanelContainer.new()
	grudge_panel.name = "GrudgePanel"
	grudge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.12, 0.95)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 2
	panel_style.content_margin_bottom = 2
	grudge_panel.add_theme_stylebox_override("panel", panel_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grudge_panel.add_child(hbox)

	# 레벨 표시 라벨
	grudge_level_label = Label.new()
	grudge_level_label.text = "Lv1"
	grudge_level_label.add_theme_font_size_override("font_size", 9)
	grudge_level_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
	grudge_level_label.custom_minimum_size.x = 22
	grudge_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(grudge_level_label)

	# 게이지 바 영역 (노치 포함)
	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 12)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(bar_container)

	# 게이지 바 배경
	grudge_bar = ColorRect.new()
	grudge_bar.color = Color(0.15, 0.12, 0.2)
	grudge_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	grudge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.add_child(grudge_bar)

	# 게이지 채움 바
	grudge_fill = ColorRect.new()
	grudge_fill.color = Color(0.6, 0.2, 0.8)
	grudge_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grudge_fill.anchor_right = 0.0
	grudge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_container.add_child(grudge_fill)

	# 노치(경계선) + 아이콘 4개 (Lv2/3/4/5 경계)
	grudge_notch_icons.clear()
	for i in range(4):
		var threshold_ratio: float = GRUDGE_LEVEL_THRESHOLDS[i + 1] / GRUDGE_MAX
		# 노치 세로선
		var notch := ColorRect.new()
		notch.color = Color(0.4, 0.3, 0.5, 0.8)
		notch.custom_minimum_size = Vector2(1, 0)
		notch.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		notch.anchor_left = threshold_ratio
		notch.anchor_right = threshold_ratio
		notch.offset_right = 1
		notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_container.add_child(notch)

		# 노치 위 아이콘 라벨
		var icon_label := Label.new()
		icon_label.text = GRUDGE_LEVEL_ICONS[i]
		icon_label.add_theme_font_size_override("font_size", 7)
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		icon_label.anchor_left = threshold_ratio
		icon_label.anchor_right = threshold_ratio
		icon_label.offset_left = -6
		icon_label.offset_right = 6
		icon_label.offset_top = -2
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_container.add_child(icon_label)
		grudge_notch_icons.append(icon_label)

	# BottomBar 바로 위에 삽입
	var bottom_bar = main_vbox.get_node_or_null("BottomBar")
	if bottom_bar:
		var idx: int = bottom_bar.get_index()
		main_vbox.add_child(grudge_panel)
		main_vbox.move_child(grudge_panel, idx)
	else:
		main_vbox.add_child(grudge_panel)


func _update_grudge_ui() -> void:
	## 원념 게이지 UI 업데이트
	if grudge_fill == null:
		return

	# 채움 바 비율 업데이트
	var fill_ratio: float = clampf(grudge_value / GRUDGE_MAX, 0.0, 1.0)
	grudge_fill.anchor_right = fill_ratio

	# 레벨에 따른 색상 변화
	var level_colors: Array = [
		Color(0.5, 0.3, 0.7),   # Lv1: 연보라
		Color(0.6, 0.2, 0.8),   # Lv2: 보라
		Color(0.8, 0.2, 0.5),   # Lv3: 자홍
		Color(0.9, 0.15, 0.2),  # Lv4: 붉은색
		Color(1.0, 0.1, 0.1),   # Lv5: 진홍
	]
	var color_idx: int = clampi(grudge_level - 1, 0, level_colors.size() - 1)
	grudge_fill.color = level_colors[color_idx]

	# 레벨 라벨 업데이트
	if grudge_level_label:
		grudge_level_label.text = "Lv%d" % grudge_level
		grudge_level_label.add_theme_color_override("font_color", level_colors[color_idx].lightened(0.3))

	# 통과한 노치 아이콘 밝게, 미통과 어둡게
	for i in range(grudge_notch_icons.size()):
		var icon: Label = grudge_notch_icons[i]
		if grudge_level >= (i + 2):  # Lv2부터 시작
			icon.modulate = Color.WHITE
		else:
			icon.modulate = Color(1, 1, 1, 0.3)


func _add_grudge(amount: float) -> void:
	## 원념 수치 증가 및 레벨업 체크
	var old_level: int = grudge_level
	grudge_value = minf(grudge_value + amount, GRUDGE_MAX)

	# 레벨 재계산
	grudge_level = 1
	for i in range(GRUDGE_LEVEL_THRESHOLDS.size() - 1, 0, -1):
		if grudge_value >= GRUDGE_LEVEL_THRESHOLDS[i]:
			grudge_level = i + 1
			break

	_update_grudge_ui()

	# 레벨업 시 연출 + 효과
	if grudge_level > old_level:
		_on_grudge_level_up(old_level, grudge_level)


func _on_grudge_level_up(old_level: int, new_level: int) -> void:
	## 원념 레벨업 시 모든 연출 + 효과 처리
	# 1) 전투창 흔들기
	_shake_window()

	# 2) 해당 레벨 노치 아이콘 튀어오르기
	_bounce_grudge_notch_icon(new_level)

	# 3) 레벨업 메시지 표시
	_show_grudge_level_up_message(new_level)

	# 4) Lv2~4: 최대 적 수 +1 알림
	if new_level >= 2 and new_level <= 4:
		_send_log("⚠ 원념 Lv%d! 전투창 적 슬롯 +1" % new_level, Color(1.0, 0.5, 0.2))

	# 5) Lv2 효과: 증원 - 즉시 적 1마리 추가
	if new_level == 2:
		call_deferred("_grudge_spawn_reinforcement")

	# 6) Lv3 효과: 분노 - 적 ATB 속도 증가 (ATB 시스템에서 자동 적용)
	if new_level == 3:
		_send_log("💢 적의 공격 속도가 빨라졌다!", Color.ORANGE_RED)

	# 7) Lv4 효과: 전조 - 위험 테두리 활성화
	if new_level == 4:
		_activate_grudge_danger_border()

	# 8) Lv5 효과: 엘리트 등장
	if new_level == 5:
		call_deferred("_grudge_spawn_elite")


func _bounce_grudge_notch_icon(level: int) -> void:
	## 레벨업한 노치 아이콘 튀어오르기 연출
	var icon_idx: int = level - 2  # Lv2 → index 0, Lv3 → 1, ...
	if icon_idx < 0 or icon_idx >= grudge_notch_icons.size():
		return

	var icon: Label = grudge_notch_icons[icon_idx]
	var original_pos: float = icon.offset_top
	var bounce_tween := create_tween()
	bounce_tween.tween_property(icon, "offset_top", original_pos - 8, 0.1).set_ease(Tween.EASE_OUT)
	bounce_tween.tween_property(icon, "offset_top", original_pos, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	# 깜빡이기
	var flash_tween := create_tween()
	flash_tween.tween_property(icon, "modulate", Color(1.5, 1.5, 0.5), 0.1)
	flash_tween.tween_property(icon, "modulate", Color.WHITE, 0.2)


func _show_grudge_level_up_message(new_level: int) -> void:
	## 원념 레벨업 메시지를 전투창 안에 짧게 표시 (0.7초)
	var messages: Array = [
		"",
		"원념이 강해졌다. 적이 더 몰려온다!",  # Lv2
		"원념이 폭발했다. 적이 분노했다!",  # Lv3
		"무언가가 오고 있다…",  # Lv4
		"원념이 극에 달했습니다!!",  # Lv5
	]
	var msg_idx: int = clampi(new_level - 1, 0, messages.size() - 1)
	var msg: String = messages[msg_idx]
	if msg.is_empty():
		return

	# 전투창 내부에 메시지 라벨 생성
	var msg_label := Label.new()
	msg_label.text = "⚠ Lv%d - %s" % [new_level, msg]
	msg_label.add_theme_font_size_override("font_size", 9)
	msg_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	msg_label.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_label.add_theme_constant_override("outline_size", 3)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	msg_label.anchor_top = 0.3
	msg_label.anchor_bottom = 0.3
	msg_label.anchor_left = 0.0
	msg_label.anchor_right = 1.0
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	battle_area.add_child(msg_label)

	# 0.7초 후 자동 제거
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_property(msg_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(msg_label.queue_free)


func _grudge_spawn_reinforcement() -> void:
	## 원념 증원: 현재 전투창 적 목록에서 랜덤 1마리 추가 소환
	if current_state != BattleState.RUNNING:
		return
	if enemy_data_list.is_empty():
		return

	# 현재 전투창에 있던 적 종류 중 랜덤 선택
	var random_enemy_id: String = enemy_data_list[randi() % enemy_data_list.size()]
	add_enemy(random_enemy_id, false)


func _activate_grudge_danger_border() -> void:
	## Lv4 전조: 위험한 빨간 테두리 펄스 활성화
	_grudge_border_style = StyleBoxFlat.new()
	_grudge_border_style.bg_color = Color(0.1, 0.05, 0.05, 0.95)

	_grudge_border_style.border_width_left = 3
	_grudge_border_style.border_width_top = 3
	_grudge_border_style.border_width_right = 3
	_grudge_border_style.border_width_bottom = 3
	_grudge_border_style.border_color = Color(0.8, 0.1, 0.1)

	_grudge_border_style.corner_radius_top_left = 4
	_grudge_border_style.corner_radius_top_right = 4
	_grudge_border_style.corner_radius_bottom_left = 4
	_grudge_border_style.corner_radius_bottom_right = 4

	add_theme_stylebox_override("panel", _grudge_border_style)
	_grudge_border_pulse_time = 0.0


func _update_grudge_border_pulse(delta: float) -> void:
	## Lv4+ 테두리 펄스 연출
	_grudge_border_pulse_time += delta
	var pulse_speed: float = 3.0 if grudge_level >= 5 else 2.0
	var pulse: float = (sin(_grudge_border_pulse_time * pulse_speed) + 1.0) / 2.0

	var base_color := Color(0.8, 0.1, 0.1)
	if grudge_level >= 5:
		base_color = Color(0.9, 0.05, 0.4)  # Lv5: 더 강렬한 색
	var bright_color: Color = base_color.lightened(0.4)
	_grudge_border_style.border_color = base_color.lerp(bright_color, pulse)

	# Lv5에서 배경 살짝 붉게
	if grudge_level >= 5:
		var bg_tint: float = pulse * 0.08
		modulate = Color(1.0 + bg_tint, 1.0 - bg_tint * 0.3, 1.0 - bg_tint * 0.3)


func _grudge_spawn_elite() -> void:
	## 원념 Lv5: 엘리트 적 1마리 소환
	if current_state != BattleState.RUNNING:
		return
	if enemy_data_list.is_empty():
		return

	var random_enemy_id: String = enemy_data_list[randi() % enemy_data_list.size()]
	add_enemy(random_enemy_id, true)  # is_elite = true
	_send_log("💀 엘리트가 나타났다!", Color.DARK_MAGENTA)


func get_grudge_level() -> int:
	return grudge_level


func get_grudge_value() -> float:
	return grudge_value
#endregion


