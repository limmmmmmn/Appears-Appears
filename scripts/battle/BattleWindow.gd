extends PanelContainer
class_name BattleWindow
## BattleWindow: 비트 전투창 (템포 기반 비트 시스템)
## - BPM은 BattleManager에서 관리 (Largo 60 ~ Presto 180)
## - 각 전투창이 독립적인 비트 타이밍 관리
## - 전투 중 적 동적 추가 지원

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated
signal beat_occurred(beat_index: int)
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

# === 비트 시스템 ===
# BPM은 BattleManager에서 관리 (60/80/110/140/180 BPM)
var beat_timer: float = 0.0
var current_beat: int = 0

# 클래스별 비트 패턴 (0=없음, 1=스킬1, 2=스킬2)
const CLASS_PATTERNS := {
	"warrior": [1, 1, 1, 1],                 # 용사: 매 비트 기본공격
	"mage": [0, 0, 0, 2],                    # 마법사: 4비트마다 스킬2
	"thief": [0, 1, 0, 2],                   # 도적: 2비트에 기본공격, 4비트에 스킬2
	"cleric": [0, 0, 0, 1, 0, 0, 0, 2],      # 성직자: 4비트에 기본공격, 8비트에 힐
	"archer": [0, 0, 1, 0, 0, 0, 1, 2],      # 궁수: 3비트에 공격, 7비트에 공격, 8비트에 스킬2
	"knight": [2, 0, 0, 1, 0, 0, 0, 1],      # 기사: 1비트에 스킬2, 4비트/8비트에 공격
}
const DEFAULT_PATTERN := [1, 0, 1, 0]        # 기본 패턴

# 클래스별 엇박 오프셋 (초 단위) - 용사만 정박, 나머지는 살짝 엇박
const CLASS_OFFBEAT := {
	"warrior": 0.0,    # 정박
	"mage": 0.12,      # 살짝 느림
	"thief": 0.08,     # 약간 느림
	"cleric": 0.15,    # 조금 느림
	"archer": 0.06,    # 미세하게 느림
	"knight": 0.10,    # 약간 느림
}

# 영웅별 비트 인덱스 추적
var hero_beat_index: Dictionary = {}
var hero_pending_action: Dictionary = {}  # 엇박 대기 중인 액션 {hero_id: {action, skill_id, timer}}

# 적 비트 시스템 (2비트마다 공격)
var enemy_beat_offset: Dictionary = {}  # 적별 시작 오프셋 (0 또는 1)

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
@onready var battle_area: PanelContainer = $MainVBox/BattleArea

# === 동적 생성 UI ===
var claim_reward_button: Button = null

# === 활성 특성 ===
var active_traits: Array = []  # 현재 전투에 적용되는 특성 목록

# === 보상 UI 참조 ===
@onready var gold_label: Label = %GoldLabel
@onready var exp_label: Label = %ExpLabel
@onready var loot_label: Label = %LootLabel
@onready var kill_count_label: Label = %KillCountLabel

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

# === 위험도 테두리 효과 ===
var danger_level: int = 0
var border_style: StyleBoxFlat = null
var border_pulse_time: float = 0.0

# 위험도별 테두리 색상 (레벨 0~5+)
# 위험도 레벨 설정
const DANGER_LEVEL_INTERVAL: int = 5  # 킬카운트 N마다 위험도 1 증가

const DANGER_BORDER_COLORS: Array = [
	Color(0.3, 0.3, 0.3),      # 0: 회색 (기본)
	Color(0.8, 0.7, 0.2),      # 1: 노란색
	Color(1.0, 0.5, 0.1),      # 2: 주황색
	Color(1.0, 0.2, 0.2),      # 3: 빨간색
	Color(0.8, 0.1, 0.3),      # 4: 진홍색
	Color(0.6, 0.0, 0.6),      # 5+: 보라색 (최고 위험)
]


func _ready() -> void:
	visible = false
	set_process(false)

	if run_button:
		run_button.pressed.connect(_on_run_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# 배경 셰이더 설정
	_setup_background_shader()

	# 위험도 테두리 설정
	_setup_danger_border()

	# 보상 UI 초기화
	_update_rewards_ui()


func _process(delta: float) -> void:
	if current_state != BattleState.RUNNING:
		return

	_update_beat_system(delta)
	_update_background_effect(delta)
	_update_danger_border_pulse(delta)


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
	window_mode = WindowMode.HOLD  # 기본값: Hold 모드

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

	# 위험도 테두리 초기화
	_setup_danger_border()

	# 파티 특성 수집 및 적용
	_collect_party_traits()
	_apply_trait_bonuses()

	await get_tree().create_timer(0.3).timeout
	_start_battle()


func add_enemy(enemy_id: String, is_elite: bool = false) -> void:
	# 패배 상태에서는 적 추가 불가
	if current_state == BattleState.DEFEAT:
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
	enemy_beat_offset[idx] = randi() % 2  # 랜덤 비트 오프셋

	# 적이 추가되면 전투 재개
	if current_state == BattleState.VICTORY:
		current_state = BattleState.RUNNING
		set_process(true)
		_send_log("전투 재개!", Color.GREEN)
		_hide_claim_reward_button()
		_update_buttons_for_enemies()

	_shake_window()


func _hide_claim_reward_button() -> void:
	## 보상 받기 버튼 제거
	if claim_reward_button != null and is_instance_valid(claim_reward_button):
		var parent = claim_reward_button.get_parent()
		if parent:
			parent.queue_free()  # CenterContainer도 함께 제거
		claim_reward_button = null


func _update_buttons_for_enemies() -> void:
	## 적이 있을 때 버튼 상태 업데이트
	if run_button:
		run_button.disabled = is_boss_battle
		run_button.tooltip_text = "즉시 도주 (보상 50%)"


func _spawn_single_enemy(enemy_id: String, make_elite: bool = false) -> void:
	var battle_enemy: BattleEnemy = BATTLE_ENEMY_SCENE.instantiate()
	enemy_container.add_child(battle_enemy)
	# 전투창별 위험도를 적에게 전달
	battle_enemy.setup(enemy_id, make_elite, get_local_danger_level())
	enemies.append(battle_enemy)

	var idx: int = enemies.size() - 1
	enemy_beat_offset[idx] = randi() % 2  # 랜덤 비트 오프셋 (0 또는 1)


func get_local_danger_level() -> int:
	## 이 전투창의 위험도 (킬카운트 / DANGER_LEVEL_INTERVAL)
	return kill_count / DANGER_LEVEL_INTERVAL


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


func _init_beat_system() -> void:
	## 비트 시스템 초기화
	beat_timer = 0.0
	current_beat = 0
	hero_beat_index.clear()
	hero_pending_action.clear()
	enemy_beat_offset.clear()

	# 영웅별 비트 인덱스 초기화
	for hero in PartyManager.get_alive_heroes():
		hero_beat_index[hero.id] = 0

	# 적별 시작 오프셋 (0 또는 1로 랜덤)
	for i in range(enemies.size()):
		enemy_beat_offset[i] = randi() % 2


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	_init_beat_system()
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


#region 비트 시스템
func _update_beat_system(delta: float) -> void:
	## 비트 타이밍 업데이트 (BPM은 BattleManager에서 관리)
	beat_timer += delta

	# 엇박 대기 중인 액션 처리
	_update_pending_actions(delta)

	# 비트 발생 체크
	var beat_interval: float = BattleManager.get_beat_interval()
	if beat_timer >= beat_interval:
		beat_timer -= beat_interval
		_on_beat_occurred()


func _update_pending_actions(delta: float) -> void:
	## 엇박 타이밍으로 대기 중인 액션 처리
	var to_execute: Array = []

	for hero_id in hero_pending_action.keys():
		var pending: Dictionary = hero_pending_action[hero_id]
		pending["timer"] -= delta

		if pending["timer"] <= 0:
			to_execute.append(hero_id)

	for hero_id in to_execute:
		var pending: Dictionary = hero_pending_action[hero_id]
		var hero: Hero = PartyManager.get_hero_by_id(hero_id)
		if hero and not hero.is_dead:
			_hero_attack(hero, pending["skill_id"])
		hero_pending_action.erase(hero_id)

		if _check_battle_end():
			return


func _on_beat_occurred() -> void:
	## 비트 발생 시 영웅과 적의 행동 처리
	current_beat += 1
	beat_occurred.emit(current_beat)

	# 비트 시각 효과
	_play_beat_effect()

	# 영웅 행동 처리 (용사는 즉시, 나머지는 엇박으로 지연)
	for hero in PartyManager.get_alive_heroes():
		if hero.is_dead:
			continue
		_process_hero_beat(hero)

	# 용사 공격 후 전투 종료 체크
	if _check_battle_end():
		return

	# 적 행동 처리 (2비트마다)
	for i in range(enemies.size()):
		var enemy: BattleEnemy = enemies[i]
		if not enemy.is_alive():
			continue
		_process_enemy_beat(enemy, i)
		if _check_battle_end():
			return


func _process_hero_beat(hero: Hero) -> void:
	## 영웅의 비트 패턴 처리
	if not hero_beat_index.has(hero.id):
		hero_beat_index[hero.id] = 0

	var pattern: Array = CLASS_PATTERNS.get(hero.class_id, DEFAULT_PATTERN)
	var beat_idx: int = hero_beat_index[hero.id]
	var action: int = pattern[beat_idx]

	# 다음 비트로 이동
	hero_beat_index[hero.id] = (beat_idx + 1) % pattern.size()

	# 행동 없음
	if action == 0:
		return

	# 스킬 ID 결정
	var skill_id: String = "basic_attack"
	if action >= 2:
		skill_id = _get_hero_skill(hero, action)

	# 엇박 오프셋 적용
	var offbeat: float = CLASS_OFFBEAT.get(hero.class_id, 0.0)

	if offbeat <= 0.0:
		# 정박 (용사) - 즉시 실행
		_hero_attack(hero, skill_id)
	else:
		# 엇박 - 지연 실행
		hero_pending_action[hero.id] = {
			"skill_id": skill_id,
			"timer": offbeat
		}


func _process_enemy_beat(enemy: BattleEnemy, enemy_index: int) -> void:
	## 적의 비트 패턴 처리 (2비트마다 공격)
	if not enemy_beat_offset.has(enemy_index):
		enemy_beat_offset[enemy_index] = randi() % 2

	var offset: int = enemy_beat_offset[enemy_index]
	# 2비트마다 공격 (오프셋 적용)
	if (current_beat + offset) % 2 == 0:
		_enemy_attack(enemy)


func _get_hero_skill(hero: Hero, skill_num: int) -> String:
	## 영웅의 스킬 번호에 해당하는 스킬 ID 반환
	var skills := hero.get_available_skills()
	# 기본 공격 제외한 스킬 목록
	var non_basic: Array = []
	for s in skills:
		if s != "basic_attack":
			non_basic.append(s)

	if non_basic.is_empty():
		return "basic_attack"

	# skill_num 2 = 첫 번째 스킬, 3 = 두 번째 스킬...
	var idx: int = skill_num - 2
	if idx >= 0 and idx < non_basic.size():
		return non_basic[idx]
	return non_basic[0]


func _play_beat_effect() -> void:
	## 비트 시각 효과
	if background:
		var tween := create_tween()
		tween.tween_property(background, "modulate", Color(1.2, 1.2, 1.2), 0.05)
		tween.tween_property(background, "modulate", Color.WHITE, 0.1)


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
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	_bring_to_front()

	var target: Hero = alive_heroes[randi() % alive_heroes.size()]

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

	# 원념 증가 (로컬만)
	kill_count += 1

	# 특성: 적 3마리 이상일 때 보너스 원념
	if _check_trait_condition("enemies_gte_3"):
		var bonus_kill: int = _get_trait_effect_value("bonus_kill_count", "enemies_gte_3")
		if bonus_kill > 0:
			kill_count += bonus_kill

	# 위험도 레벨 변경 시 테두리 업데이트 + 드라마틱 메시지
	var new_danger: int = get_local_danger_level()
	if new_danger > danger_level:
		_show_danger_level_up_message(new_danger)
		update_danger_level()

	# 보상 계산 (위험도 + 특성 적용)
	var danger_reward_mult: float = 1.0 + (danger_level * 0.1)  # 위험도당 10% 보상 증가
	var gold_trait_mult: float = 1.0 + _get_trait_effect_float("gold_mult")
	var exp_trait_mult: float = 1.0 + _get_trait_effect_float("exp_mult")

	var exp_reward: int = int(enemy.exp_reward * danger_reward_mult * exp_trait_mult)
	var gold_reward: int = int(enemy.get_gold_reward() * danger_reward_mult * gold_trait_mult)
	var items: Array = enemy.roll_drops()

	total_exp += exp_reward
	total_gold += gold_reward
	drop_items.append_array(items)
	_update_rewards_ui()

	var idx := enemies.find(enemy)
	if idx >= 0:
		enemy_beat_offset.erase(idx)

	enemy.play_death_effect()


func _show_danger_level_up_message(new_level: int) -> void:
	## 위험도 상승 시 드라마틱 메시지 표시
	var messages: Array[String] = [
		"",  # 레벨 0 (사용 안함)
		"적들의 원념이 깨어나기 시작한다...",
		"원념이 짙어진다!",
		"분노한 영혼들이 힘을 불어넣는다!",
		"원념이 폭발한다!",
		"죽음의 기운으로 가득 찼다!",
	]

	var msg_idx: int = mini(new_level, messages.size() - 1)
	var message: String = messages[msg_idx]

	# 로그에도 보내기
	_send_log("━━━ 원념 %d단계 ━━━" % new_level, Color.ORANGE_RED)
	_send_log(message, Color.ORANGE)

	# 전투창 중앙에 큰 텍스트 표시
	_show_popup_text("원념 %d단계" % new_level, message, DANGER_BORDER_COLORS[mini(new_level, DANGER_BORDER_COLORS.size() - 1)])

	# 화면 흔들림 효과
	_shake_window()


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


func _check_battle_end() -> bool:
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)

	var alive_heroes := PartyManager.get_alive_heroes()

	if alive_enemies.is_empty():
		# 적이 없으면 도주 버튼 비활성화 + 보상 받기 버튼 표시
		set_process(false)
		current_state = BattleState.VICTORY
		_update_buttons_for_no_enemies()
		_show_claim_reward_button()
		return false

	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true

	return false


func _update_buttons_for_no_enemies() -> void:
	## 적이 없을 때 버튼 상태 업데이트
	if run_button:
		run_button.disabled = true
		run_button.tooltip_text = "적이 없습니다"


func _show_claim_reward_button() -> void:
	## 보상 받기 버튼을 전투 영역 중앙에 표시
	if claim_reward_button != null:
		return  # 이미 생성됨

	claim_reward_button = Button.new()
	claim_reward_button.text = "보상 받기"
	claim_reward_button.custom_minimum_size = Vector2(100, 36)
	claim_reward_button.pressed.connect(_on_claim_reward_pressed)

	# 스타일 설정
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.6, 0.3, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.8, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	claim_reward_button.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.3, 0.7, 0.4, 0.95)
	claim_reward_button.add_theme_stylebox_override("hover", hover_style)

	claim_reward_button.add_theme_font_size_override("font_size", 14)

	# CenterContainer로 중앙 배치
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(claim_reward_button)

	if battle_area:
		battle_area.add_child(center)

	# 등장 애니메이션
	claim_reward_button.modulate.a = 0.0
	claim_reward_button.scale = Vector2(0.8, 0.8)
	claim_reward_button.pivot_offset = claim_reward_button.size / 2

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(claim_reward_button, "modulate:a", 1.0, 0.2)
	tween.tween_property(claim_reward_button, "scale", Vector2(1.0, 1.0), 0.2).set_ease(Tween.EASE_OUT)


func _on_claim_reward_pressed() -> void:
	## 보상 받기 버튼 클릭
	if claim_reward_button:
		claim_reward_button.disabled = true
	_end_battle_victory()


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

	battle_ended.emit(battle_id, true)

	# 닫힘 이펙트와 함께 창 닫기
	_play_close_effect()


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

	battle_ended.emit(battle_id, false)

	# 패배 시에도 닫힘 이펙트
	_play_close_effect()
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
		# 루팅 배율 + 위험도 보너스 표시
		var total_mult: float = loot_multiplier * (1.0 + danger_level * 0.1)
		if danger_level > 0:
			loot_label.text = "x%.1f" % total_mult
		else:
			loot_label.text = "x%d" % int(loot_multiplier)
	if kill_count_label:
		# 킬카운트 + 위험도 레벨 표시
		if danger_level > 0:
			kill_count_label.text = "%d (Lv.%d)" % [kill_count, danger_level]
		else:
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


#region 위험도 테두리 효과
func _setup_danger_border() -> void:
	## 위험도에 따른 테두리 스타일 설정 (전투창별 로컬)
	danger_level = get_local_danger_level()

	# StyleBoxFlat 생성
	border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0.1, 0.1, 0.1, 0.95)

	# 테두리 두께 설정 (위험도에 따라 증가)
	var border_width: int = 2 + mini(danger_level, 4)
	border_style.border_width_left = border_width
	border_style.border_width_top = border_width
	border_style.border_width_right = border_width
	border_style.border_width_bottom = border_width

	# 테두리 색상 설정
	var color_idx: int = mini(danger_level, DANGER_BORDER_COLORS.size() - 1)
	var border_color: Color = DANGER_BORDER_COLORS[color_idx]
	border_style.border_color = border_color

	# 코너 라운드
	border_style.corner_radius_top_left = 4
	border_style.corner_radius_top_right = 4
	border_style.corner_radius_bottom_left = 4
	border_style.corner_radius_bottom_right = 4

	# 스타일 적용
	add_theme_stylebox_override("panel", border_style)


func _update_danger_border_pulse(delta: float) -> void:
	## 높은 위험도에서 테두리 펄스 효과
	if danger_level < 2 or border_style == null:
		return

	border_pulse_time += delta * BattleManager.get_battle_speed()

	# 펄스 속도는 위험도에 따라 증가
	var pulse_speed: float = 2.0 + (danger_level * 0.5)
	var pulse: float = (sin(border_pulse_time * pulse_speed) + 1.0) / 2.0

	# 테두리 색상 펄스
	var color_idx: int = mini(danger_level, DANGER_BORDER_COLORS.size() - 1)
	var base_color: Color = DANGER_BORDER_COLORS[color_idx]
	var bright_color: Color = base_color.lightened(0.3 + (danger_level * 0.05))

	border_style.border_color = base_color.lerp(bright_color, pulse)

	# 높은 위험도(4+)에서는 배경도 살짝 붉게
	if danger_level >= 4 and background:
		var bg_tint: float = pulse * 0.1
		modulate = Color(1.0 + bg_tint, 1.0 - bg_tint * 0.5, 1.0 - bg_tint * 0.5)


func update_danger_level() -> void:
	## 위험도 레벨 업데이트 (전투창별 로컬)
	var new_level: int = get_local_danger_level()
	if new_level != danger_level:
		danger_level = new_level
		_setup_danger_border()
#endregion
