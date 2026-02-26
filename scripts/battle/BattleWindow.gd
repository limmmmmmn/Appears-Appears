extends "res://scripts/ui/window/WindowShell.gd"
class_name BattleWindow
## BattleWindow: 실시간 전투창
## - 행동 타이머: DEX 비례로 충전, 가득 차면 즉시 행동 (턴 없음)

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated
signal turn_started(unit_name: String, is_hero: bool)
signal event_finished(result: Dictionary)

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
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []
var loot_multiplier: float = 1.0  # 루팅 배율 (아이템 등장 확률 배수)
var elite_gold: int = 0  # 엘리트 확정 보상 (페널티 면제)
var elite_items: Array = []  # 엘리트 확정 아이템 (페널티 면제)

# === 전투창 모드 ===
enum WindowMode { NORMAL, HOLD, CLOSE_RESERVED }
var window_mode: WindowMode = WindowMode.NORMAL

# === UI 참조 ===
@onready var enemy_container: Container = $MainVBox/BattleArea/EnemyContainer
@onready var battle_area: PanelContainer = $MainVBox/BattleArea
@onready var main_vbox: VBoxContainer = $MainVBox
var run_button: Button = null
var block_entry_button: Button = null  # 더 이상 사용하지 않음
var battle_close_button: Button = null  # 더 이상 사용하지 않음
var top_bar: HBoxContainer = null  # 더 이상 사용하지 않음
var info_bar: PanelContainer = null  # 더 이상 사용하지 않음
var info_label: Label = null  # 더 이상 사용하지 않음
var entry_blocked: bool = false
var top_left_status_label: Label = null
var top_right_status_label: Label = null
var grudge_gauge_bar: ProgressBar = null
var _wave_clear_processed: bool = false
var local_grudge_level: int = 0
var local_grudge_kill_gauge: int = 0
var local_reward_level: int = 0
var reward_hearts: int = 0
var reward_chests: Array[String] = []
var reward_preview_items: Array[String] = []
var trinket_loot_mult: float = 1.0
var _activated_trinket_ids: Dictionary = {}


# === 활성 특성 ===
var active_traits: Array = []  # 현재 전투에 적용되는 특성 목록

# === 기사 첫 행동 추적 ===
var _knight_used_first: Dictionary = {}  # hero_id -> bool (전투창당 첫 공격 스킬 사용 여부)

# === 행동 처리 ===
const ACTION_DELAY: float = 0.3  # 행동 사이 딜레이 (초)
var is_processing_action: bool = false
var is_battle_paused: bool = false  # 전투 정지 상태
var _event_step_mode: bool = false
const MIN_BATTLE_VISIBLE_TIME: float = 0.4
const VICTORY_POST_KILL_DELAY: float = 0.18
var battle_started_ms: int = 0
var pending_victory: bool = false
var pending_victory_ready_ms: int = 0
var waiting_reward_claim: bool = false

# === 행동 타임아웃 안전장치 ===
var _action_process_timer: float = 0.0
const ACTION_TIMEOUT: float = 8.0  # 행동 처리 최대 시간 (초)




# === 레벨업 스킬 선택 ===
const SKILL_SELECT_POPUP_SCENE = preload("res://scenes/ui/SkillSelectPopup.tscn")
const SKILL_SELECT_CHOICE_COUNT: int = 3
var _skill_select_queue: Array = []  # Array of { hero_id, hero_name }
var _skill_select_popup: SkillSelectPopup = null
var _skill_select_in_victory: bool = false  # 승리 흐름에서 팝업 처리 중인지

# === 도주 설정 (formulas.json에서 로드) ===
var BASE_ESCAPE_RATE: float = 40.0
var GRUDGE_KILLS_PER_LEVEL: int = 5
const BATTLE_ENEMY_SCENE = preload("res://scenes/battle/BattleEnemy.tscn")
const BATTLE_WINDOW_UNIT_TOKEN_SCENE = preload("res://scenes/battle/BattleWindowUnitToken.tscn")
const TOOLTIP_SCENE = preload("res://scenes/ui/Tooltip.tscn")
const BASE_ENEMIES_PER_WINDOW: int = 3
const ENEMY_ROW_GAP: int = 5
const SHOW_HERO_FACE_CHIPS: bool = false

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
var _battle_is_dragging: bool = false
var _battle_drag_offset: Vector2 = Vector2.ZERO

# === 적 호버 툴팁 ===
var _enemy_tooltip: PanelContainer = null
var _hovered_enemy: BattleEnemy = null
var _enemy_tooltip_hide_token: int = 0
var _tooltip_owner: String = ""

# === 전투창 호버 하이라이트 ===
var _is_window_hovered: bool = false
var _normal_panel_style: StyleBoxFlat = null
var _hover_panel_style: StyleBoxFlat = null
var _pause_hover_focus: bool = false
var _pause_overlay: ColorRect = null

# === 전투창 드래그 머지 ===
var _merge_target: BattleWindow = null
static var _global_face_chip_owner_window_id: int = -1
var _face_chip_last_ms: Dictionary = {}  # key: "<hero_id>" -> last_ms
var _face_chip_panels: Dictionary = {}  # key: "<hero_id>" -> PanelContainer
var _face_chip_order: Array[String] = []
var _face_chip_layer: Control = null
var _face_chip_dragging: bool = false
var _face_chip_drag_hero_id: String = ""
var _face_chip_drag_panel: PanelContainer = null
var _face_chip_drag_offset: Vector2 = Vector2.ZERO
const FACE_CHIP_SIZE: Vector2 = Vector2(28, 28)
const FACE_CHIP_SPACING: float = 6.0

# === 이벤트 모드 ===
var is_event_mode: bool = false
var event_context: Dictionary = {}
var event_lines: Array[Dictionary] = []
var event_line_index: int = -1
var event_line_timer: float = 0.0
var event_line_interval: float = 1.5
var event_waiting_choice: bool = false
var event_last_choice_id: String = ""
var event_overlay_root: Control = null
var event_left_face_panel: PanelContainer = null
var event_right_face_panel: PanelContainer = null
var event_speaker_label: Label = null
var event_text_label: RichTextLabel = null
var event_choice_panel: VBoxContainer = null
var event_left_bubble: PanelContainer = null
var event_right_bubble: PanelContainer = null
var event_left_bubble_label: Label = null
var event_right_bubble_label: Label = null

# === 전투 로그 (고전 RPG 스타일 + 타이핑 연출) ===
@onready var battle_log_panel: PanelContainer = $MainVBox/BattleLogPanel
@onready var battle_log_label: RichTextLabel = $MainVBox/BattleLogPanel/BattleLogLabel
const BATTLE_LOG_FONT_SIZE: int = 10
const TYPEWRITER_CHAR_DELAY: float = 0.006  # 한 글자당 대기 시간 (초고속 타이핑)
const TYPEWRITER_LINE_PAUSE: float = 0.03  # 줄 사이 대기 (빠르게)
var _tw_lines: Array[String] = []  # 순차 표시할 줄 목록
var _tw_current_line: int = 0  # 현재 표시 중인 줄 인덱스
var _tw_char_index: int = 0  # 현재 줄에서 표시된 글자 수
var _tw_timer: float = 0.0  # 타이핑 타이머
var _tw_done: bool = true  # 모든 줄 타이핑 완료 여부
var _tw_displayed: Array[String] = []  # 이미 완료된 줄들
var _tw_callback: Callable = Callable()  # 줄 사이 콜백 (공격 연출용)
var _tw_callback_after_line: int = -1  # 콜백 실행 시점 (이 줄 타이핑 후)
var _tw_callback_fired: bool = false
var _tw_pause_timer: float = 0.0  # 줄 사이/콜백 후 대기


func _ready() -> void:
	visible = false
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS  # 게임 일시정지 중에도 입력 받기
	add_to_group("battle_windows")

	# formulas.json에서 전투 상수 로드
	var battle_f: Dictionary = DataManager.get_formula("battle") as Dictionary
	BASE_ESCAPE_RATE = float(battle_f.get("base_escape_rate", 40.0))
	GRUDGE_KILLS_PER_LEVEL = int(battle_f.get("grudge_kills_per_level", 5))

	# 마우스 GUI 입력 연결
	gui_input.connect(_on_gui_input)

	# 전투창 호버 하이라이트 설정
	_setup_hover_highlight()

	# 배경 셰이더 설정
	_setup_background_shader()

	# 적 호버 툴팁 생성
	_setup_enemy_tooltip()
	_setup_pause_controls()

	# DQ 스타일 전투 UI 생성
	_create_run_button_overlay()
	_setup_battle_log()
	if SHOW_HERO_FACE_CHIPS:
		_ensure_face_chip_layer()
	_reset_local_progression()


func _process(delta: float) -> void:
	_update_pause_visual(delta)
	if _face_chip_dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _face_chip_drag_panel != null and is_instance_valid(_face_chip_drag_panel):
				_face_chip_drag_panel.global_position = get_global_mouse_position() - _face_chip_drag_offset
		else:
			var drop_window: BattleWindow = _find_face_chip_drop_window(get_global_mouse_position())
			if drop_window != null and is_instance_valid(drop_window) and not _face_chip_drag_hero_id.is_empty():
				_transfer_face_chip_to_window(_face_chip_drag_hero_id, drop_window)
			_finish_face_chip_drag()

	if get_tree().paused:
		return

	if is_event_mode:
		if _event_step_mode:
			return
		_process_event_dialog(delta)
		return

	if current_state != BattleState.RUNNING:
		return

	if pending_victory:
		var now_ms: int = Time.get_ticks_msec()
		var min_visible_ms: int = int(MIN_BATTLE_VISIBLE_TIME * 1000.0)
		var can_finish: bool = (now_ms - battle_started_ms) >= min_visible_ms and now_ms >= pending_victory_ready_ms
		if can_finish:
			pending_victory = false
			clear_battle_log()
			_end_battle_victory()
			return

	_update_background_effect(delta)
	_update_run_button_position()

	# === ATB 모드 ===
	# 적 행동 타이머 충전 (ATBManager 중앙 관리)
	ATBManager.update_enemy_timers(enemies, delta, is_battle_paused)

	# 버프/디버프 틱
	for hero in _get_alive_heroes_in_battle():
		hero.tick_buffs(delta)
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
			enemy.tick_debuffs(delta)
			if not enemy.is_alive():
				_on_enemy_defeated(enemy)

	# 행동 타임아웃 안전장치
	if is_processing_action:
		_action_process_timer += delta
		if _action_process_timer > ACTION_TIMEOUT:
			push_warning("[BattleWindow] 행동 처리 타임아웃 (%.1fs) - 강제 해제" % ACTION_TIMEOUT)
			is_processing_action = false
			_action_process_timer = 0.0

	# 행동 준비된 유닛 즉시 행동 (정지 상태면 스킵)
	if not is_processing_action and not is_battle_paused:
		_action_process_timer = 0.0
		_process_ready_unit()


func _setup_pause_controls() -> void:
	var pause_parent: Control = battle_area
	if pause_parent == null:
		pause_parent = self
	if _pause_overlay == null:
		_pause_overlay = ColorRect.new()
		_pause_overlay.name = "PauseOverlay"
		_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pause_overlay.color = Color(0.0, 0.0, 0.0, 0.34)
		_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_overlay.visible = false
		pause_parent.add_child(_pause_overlay)


func _update_pause_visual(delta: float) -> void:
	var tree_paused: bool = false
	if get_tree():
		tree_paused = get_tree().paused
	if is_event_mode and tree_paused:
		_event_step_mode = true

	var paused_context: bool = tree_paused or (is_event_mode and _event_step_mode)
	if not paused_context:
		if _pause_overlay:
			_pause_overlay.visible = false
		modulate = Color.WHITE
		return

	var focused: bool = false
	if is_event_mode:
		focused = _is_window_hovered
	else:
		focused = _pause_hover_focus

	var dim: float = 1.0 if focused else 0.62
	modulate = Color(dim, dim, dim, 1.0)

	if _pause_overlay:
		_pause_overlay.visible = true
		_pause_overlay.color.a = 0.18 if focused else 0.34


func _apply_run_button_style() -> void:
	if run_button == null:
		return
	run_button.text = "도주"
	run_button.add_theme_font_size_override("font_size", 9)
	run_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	run_button.custom_minimum_size = Vector2(44, 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(1.0, 1.0, 1.0, 0.8)
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 2
	normal.corner_radius_bottom_right = 2
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	if hover:
		hover.bg_color = Color(0.66, 0.52, 0.16, 0.98)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	if pressed:
		pressed.bg_color = Color(0.45, 0.35, 0.1, 0.98)
	run_button.add_theme_stylebox_override("normal", normal)
	if hover:
		run_button.add_theme_stylebox_override("hover", hover)
	if pressed:
		run_button.add_theme_stylebox_override("pressed", pressed)


func _apply_claim_button_style() -> void:
	if run_button == null:
		return
	run_button.text = "보상"
	run_button.add_theme_font_size_override("font_size", 9)
	run_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	run_button.custom_minimum_size = Vector2(44, 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.42, 0.2, 0.96)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.38, 0.88, 0.48, 0.95)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	if hover:
		hover.bg_color = Color(0.2, 0.5, 0.26, 0.98)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	if pressed:
		pressed.bg_color = Color(0.12, 0.34, 0.17, 0.98)
	run_button.add_theme_stylebox_override("normal", normal)
	if hover:
		run_button.add_theme_stylebox_override("hover", hover)
	if pressed:
		run_button.add_theme_stylebox_override("pressed", pressed)


func _setup_info_bar() -> void:
	if info_bar == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.74)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.24, 0.32, 0.9)
	info_bar.add_theme_stylebox_override("panel", style)
	if info_label:
		info_label.add_theme_font_size_override("font_size", 9)
		info_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95, 0.95))
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _on_block_entry_toggled(pressed: bool) -> void:
	entry_blocked = pressed
	_update_block_entry_button_state()


func _update_block_entry_button_state() -> void:
	if block_entry_button == null or not is_instance_valid(block_entry_button):
		return
	block_entry_button.button_pressed = entry_blocked
	block_entry_button.tooltip_text = "봉쇄 ON: 적 난입 차단" if entry_blocked else "봉쇄 OFF: 적 난입 허용"
	block_entry_button.focus_mode = Control.FOCUS_NONE
	block_entry_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	block_entry_button.custom_minimum_size = Vector2(104, 24)
	block_entry_button.add_theme_font_size_override("font_size", 10)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.17, 0.19, 0.22, 0.96)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.45, 0.46, 0.52, 0.9)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	var active := normal.duplicate() as StyleBoxFlat
	if active:
		active.bg_color = Color(0.45, 0.15, 0.16, 0.96)
		active.border_color = Color(0.95, 0.35, 0.38, 0.95)
	block_entry_button.add_theme_stylebox_override("normal", active if entry_blocked and active else normal)
	block_entry_button.add_theme_stylebox_override("hover", active if entry_blocked and active else normal)
	block_entry_button.add_theme_stylebox_override("pressed", active if entry_blocked and active else normal)


func is_enemy_entry_blocked() -> bool:
	return entry_blocked


#region 전투 초기화 (새 시스템)
func setup_new(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false, p_is_boss: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	is_boss_battle = p_is_boss
	_reset_local_progression()
	waiting_reward_claim = false
	_clear_reward_claim_button()
	entry_blocked = false
	clear_battle_log()
	if run_button:
		_apply_run_button_style()
		run_button.visible = true

	# 보상 초기화
	total_exp = 0
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
		_spawn_single_enemy(enemy_id, make_elite, false)

	_refresh_enemy_layout()
	_check_trinket_loot_activation()

	if is_elite_battle:
		_apply_elite_style()

	visible = true
	current_state = BattleState.STARTING

	# 배경 효과 초기화 (한 번만)
	_init_background_effect()

	# 파티 특성 수집 및 적용
	_collect_party_traits()
	_apply_trait_bonuses()

	call_deferred("_start_battle")


func _update_buttons_for_enemies() -> void:
	## 적 존재 여부에 따라 우측 버튼 상태 전환 (도주/보상받기)
	if run_button == null:
		return
	_update_fold_layout_for_enemy_state()
	_apply_run_button_style()
	run_button.disabled = not has_alive_enemies()


func _update_fold_layout_for_enemy_state() -> void:
	## 접힘 기능 삭제: 항상 기본 레이아웃 유지
	if battle_area and is_instance_valid(battle_area):
		battle_area.visible = true
	if info_bar and is_instance_valid(info_bar):
		info_bar.visible = true


func _set_folded_window_state(folded: bool) -> void:
	return


func _spawn_single_enemy(enemy_id: String, make_elite: bool = false, refresh_layout: bool = true) -> void:
	var battle_enemy: BattleEnemy = BATTLE_ENEMY_SCENE.instantiate()
	add_child(battle_enemy)
	battle_enemy.setup(enemy_id, make_elite)
	_apply_local_grudge_to_enemy(battle_enemy)
	enemies.append(battle_enemy)
	if refresh_layout:
		_refresh_enemy_layout()
	# 마우스 호버 이벤트 연결
	_connect_enemy_hover(battle_enemy)


func add_field_enemies(enemy_ids: Array, is_elite: bool = false) -> int:
	## 필드 조우로 들어온 적을 현재 전투창에 추가 (최대: 3 + 원념레벨)
	if entry_blocked:
		return 0
	if enemy_ids.is_empty():
		return 0

	var alive_count: int = get_enemy_count()
	var space: int = get_max_enemies_per_window() - alive_count
	if space <= 0:
		return 0

	var added: int = 0
	for i in range(enemy_ids.size()):
		if added >= space:
			break
		var enemy_id: String = str(enemy_ids[i]).strip_edges()
		if enemy_id.is_empty():
			continue
		_spawn_single_enemy(enemy_id, is_elite and added == 0, false)
		added += 1

	if added > 0:
		pending_victory = false
		pending_victory_ready_ms = 0
		_wave_clear_processed = false
		_refresh_enemy_layout()
		_update_buttons_for_enemies()
		_check_trinket_loot_activation()
	return added


func can_accept_field_enemies(additional_count: int = 1) -> bool:
	if entry_blocked:
		return false
	if additional_count <= 0:
		return true
	return get_enemy_count() + additional_count <= get_max_enemies_per_window()


func get_max_enemies_per_window() -> int:
	var trinket_bonus: int = 0
	if GameManager != null and GameManager.has_method("get_trinket_max_enemies_per_window_bonus"):
		trinket_bonus = int(GameManager.call("get_trinket_max_enemies_per_window_bonus"))
	return BASE_ENEMIES_PER_WINDOW + maxi(0, local_grudge_level) + maxi(0, trinket_bonus)


func _refresh_enemy_layout() -> void:
	if enemy_container == null:
		return

	var living_nodes: Array = []
	for e_any in enemies:
		if e_any == null:
			continue
		if not is_instance_valid(e_any):
			continue
		if not (e_any is BattleEnemy):
			continue
		var e: BattleEnemy = e_any as BattleEnemy
		if e == null:
			continue
		if not e.is_alive():
			continue
		living_nodes.append(e)

	for e in living_nodes:
		var enemy_node: BattleEnemy = e as BattleEnemy
		if enemy_node == null:
			continue
		var p: Node = enemy_node.get_parent()
		if p != null:
			p.remove_child(enemy_node)

	for child in enemy_container.get_children():
		child.queue_free()

	if living_nodes.is_empty():
		return

	var rows: Array = []
	var count: int = living_nodes.size()
	if count <= 3:
		rows.append(living_nodes)
	elif count == 4:
		rows.append([living_nodes[0], living_nodes[1]])
		rows.append([living_nodes[2], living_nodes[3]])
	else:
		rows.append([living_nodes[0], living_nodes[1]])
		rows.append([living_nodes[2], living_nodes[3], living_nodes[4]])

	for row_nodes in rows:
		if not (row_nodes is Array):
			continue
		var row_list: Array = row_nodes as Array
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", ENEMY_ROW_GAP)
		enemy_container.add_child(row)
		for enemy_node_any in row_list:
			var enemy_node: BattleEnemy = enemy_node_any as BattleEnemy
			if enemy_node == null:
				continue
			row.add_child(enemy_node)


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


func apply_damage_to_all_enemies(damage: int) -> void:
	## 합체공격: 모든 적에게 고정 데미지
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.is_alive():
			continue
		enemy.take_damage(damage)
		enemy.play_hit_effect(false)
		enemy.show_damage_number(damage, false)
		if not enemy.is_alive():
			_on_enemy_defeated(enemy)
	_check_all_enemies_dead()


func apply_blind_to_all_enemies(duration: float) -> void:
	## 합체공격: 모든 적에게 명중률 감소
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.is_alive():
			continue
		if enemy.has_method("apply_debuff"):
			enemy.apply_debuff("blind", duration, -30.0)
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
	battle_started_ms = Time.get_ticks_msec()
	pending_victory = false
	pending_victory_ready_ms = 0
	waiting_reward_claim = false
	_skill_select_queue.clear()
	_skill_select_in_victory = false
	_clear_reward_claim_button()
	entry_blocked = false
	_update_block_entry_button_state()
	if block_entry_button and is_instance_valid(block_entry_button):
		block_entry_button.visible = true
	if top_left_status_label:
		top_left_status_label.visible = true
	if top_right_status_label:
		top_right_status_label.visible = true
	if grudge_gauge_bar:
		grudge_gauge_bar.visible = true
	_refresh_top_bar_status()
	_clear_reward_claim_button()
	_update_buttons_for_enemies()
	_prime_party_face_chips_and_locks()
	set_process(true)
	_reset_enemy_timers()

#endregion


func setup_event_dialog(
		title: String,
		left_hero_id: String,
		right_hero_id: String,
		lines: Array[Dictionary],
		context: Dictionary = {}
	) -> void:
	## 전투창을 이벤트창으로 재사용
	_reset_event_mode_state()
	_set_folded_window_state(false)
	is_event_mode = true
	_event_step_mode = false
	event_context = context.duplicate(true)
	event_lines = lines.duplicate(true)
	event_line_interval = float(event_context.get("line_interval", 1.5))
	event_line_index = -1
	event_line_timer = 0.0
	event_waiting_choice = false
	event_last_choice_id = ""

	visible = true
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	current_state = BattleState.RUNNING
	set_process(true)

	if run_button:
		run_button.visible = false
	if block_entry_button and is_instance_valid(block_entry_button):
		block_entry_button.visible = false
	if top_left_status_label:
		top_left_status_label.visible = false
	if top_right_status_label:
		top_right_status_label.visible = false
	if grudge_gauge_bar:
		grudge_gauge_bar.visible = false

	var top_bar := get_node_or_null("MainVBox/TopBar") as Control
	if top_bar:
		top_bar.visible = true
	if battle_close_button:
		battle_close_button.visible = true

	var title_label := Label.new()
	title_label.name = "EventTitleRuntime"
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.65, 1.0))
	if top_bar:
		top_bar.add_child(title_label)
		top_bar.move_child(title_label, 0)

	if background:
		background.material = null
		background.color = Color(0, 0, 0, 0.93)
	if battle_area:
		battle_area.visible = true
	if info_bar:
		info_bar.visible = true
	if enemy_container:
		enemy_container.visible = false

	_build_event_overlay(left_hero_id, right_hero_id)

	var appear := create_tween()
	appear.set_parallel(true)
	appear.set_ease(Tween.EASE_OUT)
	appear.set_trans(Tween.TRANS_BACK)
	appear.tween_property(self, "modulate:a", 1.0, 0.2)
	appear.tween_property(self, "scale", Vector2.ONE, 0.25)

	_advance_event_line()


func _setup_battle_top_bar() -> void:
	if top_bar == null:
		return
	top_bar.visible = true
	top_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.custom_minimum_size.y = 22

	for child in top_bar.get_children():
		if child == battle_close_button:
			continue
		child.queue_free()

	top_left_status_label = Label.new()
	top_left_status_label.add_theme_font_size_override("font_size", 10)
	top_left_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42, 1.0))
	top_bar.add_child(top_left_status_label)

	grudge_gauge_bar = ProgressBar.new()
	grudge_gauge_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grudge_gauge_bar.custom_minimum_size = Vector2(90, 8)
	grudge_gauge_bar.show_percentage = false
	grudge_gauge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grudge_gauge_bar.max_value = float(GRUDGE_KILLS_PER_LEVEL)
	grudge_gauge_bar.value = 0.0
	var gauge_bg := StyleBoxFlat.new()
	gauge_bg.bg_color = Color(0.14, 0.08, 0.08, 0.92)
	gauge_bg.corner_radius_top_left = 3
	gauge_bg.corner_radius_top_right = 3
	gauge_bg.corner_radius_bottom_left = 3
	gauge_bg.corner_radius_bottom_right = 3
	var gauge_fill := StyleBoxFlat.new()
	gauge_fill.bg_color = Color(0.95, 0.22, 0.2, 0.95)
	gauge_fill.corner_radius_top_left = 3
	gauge_fill.corner_radius_top_right = 3
	gauge_fill.corner_radius_bottom_left = 3
	gauge_fill.corner_radius_bottom_right = 3
	grudge_gauge_bar.add_theme_stylebox_override("background", gauge_bg)
	grudge_gauge_bar.add_theme_stylebox_override("fill", gauge_fill)
	top_bar.add_child(grudge_gauge_bar)

	top_right_status_label = Label.new()
	top_right_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right_status_label.add_theme_font_size_override("font_size", 10)
	top_right_status_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
	top_bar.add_child(top_right_status_label)

	if battle_close_button:
		battle_close_button.visible = false


func _init_reward_preview_ui() -> void:
	return


func _reset_local_progression() -> void:
	local_grudge_level = 0
	local_grudge_kill_gauge = 0
	local_reward_level = 0
	reward_hearts = 0
	reward_chests.clear()
	reward_preview_items.clear()
	_wave_clear_processed = false
	_refresh_grudge_ui()
	_refresh_reward_preview_ui()
	_refresh_top_bar_status()


func _refresh_grudge_ui() -> void:
	if grudge_gauge_bar:
		grudge_gauge_bar.max_value = GRUDGE_KILLS_PER_LEVEL
		grudge_gauge_bar.value = local_grudge_kill_gauge


func _refresh_top_bar_status() -> void:
	if top_left_status_label:
		top_left_status_label.text = "🔥%d" % local_grudge_level
	if top_right_status_label:
		top_right_status_label.text = "⭐%d" % local_reward_level


func get_local_grudge_level() -> int:
	return local_grudge_level


func _refresh_reward_preview_ui() -> void:
	if info_label == null:
		return
	info_label.text = "💰%d  📦%d" % [total_gold, reward_preview_items.size()]


func _on_local_grudge_kill() -> void:
	local_grudge_kill_gauge += 1
	var leveled: bool = false
	while local_grudge_kill_gauge >= GRUDGE_KILLS_PER_LEVEL:
		local_grudge_kill_gauge -= GRUDGE_KILLS_PER_LEVEL
		local_grudge_level += 1
		leveled = true
		_play_grudge_levelup_effect()
		_sync_reward_level_with_grudge()

	if leveled:
		_apply_local_grudge_to_all_enemies()

	_refresh_grudge_ui()
	_refresh_top_bar_status()


func _sync_reward_level_with_grudge() -> void:
	# 원념/보상 레벨을 같은 값으로 동기화 (원념 기준)
	if local_reward_level >= local_grudge_level:
		return
	while local_reward_level < local_grudge_level:
		local_reward_level += 1
		_apply_reward_level_bundle(local_reward_level)
		_play_reward_levelup_effect(local_reward_level)
	_refresh_top_bar_status()
	_refresh_reward_preview_ui()


func _apply_local_grudge_to_all_enemies() -> void:
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		if not (e is BattleEnemy):
			continue
		_apply_local_grudge_to_enemy(e as BattleEnemy)


func _apply_local_grudge_to_enemy(enemy: BattleEnemy) -> void:
	if enemy == null:
		return
	var mults: Dictionary = _get_grudge_multipliers(local_grudge_level)
	enemy.set_grudge_scaling(float(mults.get("atk", 1.0)), float(mults.get("hp", 1.0)))


func _get_grudge_multipliers(level: int) -> Dictionary:
	match level:
		0:
			return {"atk": 1.0, "hp": 1.0}
		1:
			return {"atk": 1.3, "hp": 1.05}
		2:
			return {"atk": 1.6, "hp": 1.1}
		3:
			return {"atk": 2.0, "hp": 1.15}
		4:
			return {"atk": 2.5, "hp": 1.2}
		5:
			return {"atk": 3.0, "hp": 1.25}
		_:
			var bonus_lv: int = maxi(0, level - 5)
			return {
				"atk": 3.0 + 0.5 * float(bonus_lv),
				"hp": 1.25 + 0.05 * float(bonus_lv),
			}


func _play_grudge_levelup_effect() -> void:
	# 전투창 테두리 붉은 번쩍임
	var panel_style_variant: Variant = get_theme_stylebox("panel")
	if panel_style_variant is StyleBoxFlat:
		var original_style: StyleBoxFlat = panel_style_variant.duplicate() as StyleBoxFlat
		var flash_style: StyleBoxFlat = original_style.duplicate() as StyleBoxFlat
		flash_style.border_width_left = maxi(flash_style.border_width_left, 2)
		flash_style.border_width_top = maxi(flash_style.border_width_top, 2)
		flash_style.border_width_right = maxi(flash_style.border_width_right, 2)
		flash_style.border_width_bottom = maxi(flash_style.border_width_bottom, 2)
		flash_style.border_color = Color(1.0, 0.2, 0.2, 1.0)
		add_theme_stylebox_override("panel", flash_style)
		var restore_timer := get_tree().create_timer(0.3)
		restore_timer.timeout.connect(func():
			add_theme_stylebox_override("panel", original_style)
		)

	# 적 붉은 오라
	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue
		var enemy: BattleEnemy = e as BattleEnemy
		if enemy == null or enemy.sprite == null or not enemy.is_alive():
			continue
		var tw := create_tween()
		tw.tween_property(enemy.sprite, "modulate", Color(1.8, 0.5, 0.5, 1.0), 0.12)
		tw.tween_property(enemy.sprite, "modulate", Color.WHITE, 0.18)


func _on_wave_cleared() -> void:
	# 보상 레벨은 원념 레벨과 같은 경로로만 증가
	_sync_reward_level_with_grudge()


func _apply_reward_level_bundle(level: int) -> void:
	var bonus_gold: int = 0
	var item_ids: Array[String] = []
	var hearts: int = 0
	match level:
		1:
			bonus_gold = 8
			_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("common"))
		2:
			bonus_gold = 14
			_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("common"))
			if randf() < 0.3:
				_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("common"))
			if randf() < 0.35:
				_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("uncommon"))
			reward_chests.append("🪵")
		3:
			bonus_gold = 20
			if randf() < 0.25:
				_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("rare"))
			hearts = 1
			reward_chests.append("🥈")
		4:
			bonus_gold = 28
			if randf() < 0.45:
				_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("rare"))
			hearts = 1
			reward_chests.append("🥇")
		5:
			bonus_gold = 36
			_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("rare"))
			hearts = 1
			reward_chests.append("✨")
		_:
			bonus_gold = 36 + max(0, level - 5) * 6
			_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("rare"))
			if randf() < 0.2:
				_append_if_not_empty(item_ids, _roll_reward_item_by_rarity("uncommon"))
			if randf() < 0.15:
				hearts = 1
			reward_chests.append("✨")

	total_gold += bonus_gold
	drop_items.append_array(item_ids)
	reward_preview_items.append_array(item_ids)
	reward_hearts += hearts


func _roll_reward_item_by_rarity(rarity: String) -> String:
	if DataManager == null:
		return ""
	var pool: Array[String] = DataManager.get_equipment_by_rarity(rarity)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


func _append_if_not_empty(arr: Array[String], value: String) -> void:
	var v: String = value.strip_edges()
	if not v.is_empty():
		arr.append(v)


func _play_reward_levelup_effect(level: int) -> void:
	if info_bar and is_instance_valid(info_bar):
		var tw := create_tween()
		tw.tween_property(info_bar, "modulate", Color(1.2, 1.2, 0.9, 1.0), 0.1)
		tw.tween_property(info_bar, "modulate", Color.WHITE, 0.16)


func _build_event_overlay(left_hero_id: String, right_hero_id: String) -> void:
	if battle_area == null:
		return
	if event_overlay_root and is_instance_valid(event_overlay_root):
		event_overlay_root.queue_free()
	event_overlay_root = Control.new()
	event_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	event_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_area.add_child(event_overlay_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	event_overlay_root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var face_row := HBoxContainer.new()
	face_row.alignment = BoxContainer.ALIGNMENT_CENTER
	face_row.add_theme_constant_override("separation", 24)
	vbox.add_child(face_row)

	event_left_face_panel = PanelContainer.new()
	event_left_face_panel.custom_minimum_size = Vector2(64, 64)
	face_row.add_child(event_left_face_panel)

	var left_face := TextureRect.new()
	left_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	left_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	event_left_face_panel.add_child(left_face)

	event_right_face_panel = PanelContainer.new()
	event_right_face_panel.custom_minimum_size = Vector2(64, 64)
	face_row.add_child(event_right_face_panel)

	var right_face := TextureRect.new()
	right_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	right_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	event_right_face_panel.add_child(right_face)

	if SpriteManager:
		left_face.texture = SpriteManager.get_hero_face_sprite(left_hero_id)
		right_face.texture = SpriteManager.get_hero_face_sprite(right_hero_id)

	var bubble_row := HBoxContainer.new()
	bubble_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bubble_row.add_theme_constant_override("separation", 24)
	vbox.add_child(bubble_row)

	event_left_bubble = PanelContainer.new()
	event_left_bubble.custom_minimum_size = Vector2(110, 44)
	event_left_bubble.visible = false
	_apply_event_bubble_style(event_left_bubble)
	bubble_row.add_child(event_left_bubble)
	event_left_bubble_label = Label.new()
	event_left_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_left_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	event_left_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_left_bubble_label.add_theme_font_size_override("font_size", 8)
	event_left_bubble_label.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0, 1.0))
	event_left_bubble.add_child(event_left_bubble_label)

	event_right_bubble = PanelContainer.new()
	event_right_bubble.custom_minimum_size = Vector2(110, 44)
	event_right_bubble.visible = false
	_apply_event_bubble_style(event_right_bubble)
	bubble_row.add_child(event_right_bubble)
	event_right_bubble_label = Label.new()
	event_right_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_right_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	event_right_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_right_bubble_label.add_theme_font_size_override("font_size", 8)
	event_right_bubble_label.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0, 1.0))
	event_right_bubble.add_child(event_right_bubble_label)

	var dialog_panel := PanelContainer.new()
	dialog_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dialog_panel)

	var dialog_margin := MarginContainer.new()
	dialog_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_margin.add_theme_constant_override("margin_left", 8)
	dialog_margin.add_theme_constant_override("margin_top", 6)
	dialog_margin.add_theme_constant_override("margin_right", 8)
	dialog_margin.add_theme_constant_override("margin_bottom", 6)
	dialog_panel.add_child(dialog_margin)

	var dialog_vbox := VBoxContainer.new()
	dialog_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_vbox.add_theme_constant_override("separation", 4)
	dialog_margin.add_child(dialog_vbox)

	event_speaker_label = Label.new()
	event_speaker_label.add_theme_font_size_override("font_size", 10)
	event_speaker_label.add_theme_color_override("font_color", Color(0.99, 0.93, 0.65, 1.0))
	event_speaker_label.visible = false
	dialog_vbox.add_child(event_speaker_label)

	event_text_label = RichTextLabel.new()
	event_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_text_label.scroll_active = false
	event_text_label.fit_content = true
	event_text_label.bbcode_enabled = false
	event_text_label.add_theme_font_size_override("normal_font_size", 9)
	event_text_label.visible = false
	dialog_vbox.add_child(event_text_label)

	event_choice_panel = VBoxContainer.new()
	event_choice_panel.visible = false
	event_choice_panel.add_theme_constant_override("separation", 3)
	dialog_vbox.add_child(event_choice_panel)


func _process_event_dialog(delta: float) -> void:
	if not is_event_mode:
		return
	if event_waiting_choice:
		return
	event_line_timer -= delta
	if event_line_timer <= 0.0:
		_advance_event_line()


func _advance_event_line() -> void:
	event_line_index += 1
	if event_line_index >= event_lines.size():
		_finish_event_dialog({"choice_id": event_last_choice_id})
		return

	var line: Dictionary = event_lines[event_line_index]
	var speaker: String = str(line.get("speaker", "left"))
	var speaker_name: String = str(line.get("name", ""))
	var text: String = str(line.get("text", ""))

	if event_speaker_label:
		event_speaker_label.text = speaker_name
	if event_text_label:
		event_text_label.text = text
	_show_event_speech_bubble(speaker, speaker_name, text)
	_set_event_speaker_highlight(speaker)

	var choices: Array = line.get("choices", []) as Array
	if not choices.is_empty():
		event_waiting_choice = true
		_show_event_choices(choices)
		return

	event_waiting_choice = false
	_hide_event_choices()
	event_line_timer = float(line.get("duration", event_line_interval))


func _show_event_choices(choices: Array) -> void:
	_hide_event_choices()
	if event_choice_panel == null:
		return
	event_choice_panel.visible = true
	for raw_choice in choices:
		var choice: Dictionary = raw_choice as Dictionary
		var button := Button.new()
		button.text = str(choice.get("text", "선택"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 9)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_event_choice_pressed.bind(choice))
		event_choice_panel.add_child(button)


func _hide_event_choices() -> void:
	if event_choice_panel == null:
		return
	for child in event_choice_panel.get_children():
		child.queue_free()
	event_choice_panel.visible = false


func _on_event_choice_pressed(choice: Dictionary) -> void:
	event_last_choice_id = str(choice.get("id", ""))
	var line: Dictionary = {}
	if event_line_index >= 0 and event_line_index < event_lines.size():
		line = event_lines[event_line_index]
	var branch_map: Dictionary = line.get("next_index_by_choice", {}) as Dictionary
	if not branch_map.is_empty() and branch_map.has(event_last_choice_id):
		event_line_index = int(branch_map.get(event_last_choice_id, event_line_index + 1)) - 1
	event_waiting_choice = false
	_hide_event_choices()
	event_line_timer = 0.05


func _set_event_speaker_highlight(speaker: String) -> void:
	var left_active: bool = speaker != "right"
	if event_left_face_panel:
		event_left_face_panel.modulate = Color(1, 1, 1, 1.0 if left_active else 0.45)
	if event_right_face_panel:
		event_right_face_panel.modulate = Color(1, 1, 1, 1.0 if not left_active else 0.45)


func _finish_event_dialog(result: Dictionary) -> void:
	if not is_event_mode:
		return
	event_finished.emit(result)
	_reset_event_mode_state()
	_play_close_effect()


func close_event_window_immediate() -> void:
	_reset_event_mode_state()
	queue_free()


func _reset_event_mode_state() -> void:
	is_event_mode = false
	_event_step_mode = false
	event_context.clear()
	event_lines.clear()
	event_line_index = -1
	event_line_timer = 0.0
	event_waiting_choice = false
	event_last_choice_id = ""
	if event_overlay_root and is_instance_valid(event_overlay_root):
		event_overlay_root.queue_free()
	event_overlay_root = null
	event_left_face_panel = null
	event_right_face_panel = null
	event_speaker_label = null
	event_text_label = null
	event_choice_panel = null
	event_left_bubble = null
	event_right_bubble = null
	event_left_bubble_label = null
	event_right_bubble_label = null


func _apply_event_bubble_style(panel: PanelContainer) -> void:
	if panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.72, 0.78, 0.94, 0.95)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)


func _show_event_speech_bubble(speaker: String, speaker_name: String, text: String) -> void:
	var left_active: bool = speaker != "right"
	var bubble_text: String = text
	if not speaker_name.is_empty():
		bubble_text = "%s: %s" % [speaker_name, text]

	if event_left_bubble and event_right_bubble:
		event_left_bubble.visible = left_active
		event_right_bubble.visible = not left_active
	if event_left_bubble_label and left_active:
		event_left_bubble_label.text = bubble_text
	if event_right_bubble_label and not left_active:
		event_right_bubble_label.text = bubble_text

func get_alive_enemies() -> Array:
	## 살아있는 적 목록 반환
	var alive: Array = []
	for enemy in enemies:
		if enemy != null and enemy.is_alive():
			alive.append(enemy)
	return alive


#region 행동 타이머
func _reset_enemy_timers() -> void:
	## 적 행동 타이머 초기화
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
			enemy.reset_action_timer()


#endregion


#region 실시간 행동 시스템
func set_battle_paused(paused: bool) -> void:
	## 전투 정지/재개
	is_battle_paused = paused
	if not paused:
		_pause_hover_focus = false
	_update_hover_highlight()
	_update_pause_visual(0.0)


func set_pause_hover_focus(focused: bool) -> void:
	_pause_hover_focus = focused
	_update_hover_highlight()


func _process_ready_unit() -> void:
	## 행동 타이머가 가득 찬 유닛을 찾아 즉시 행동
	if current_state != BattleState.RUNNING:
		return

	# 용사 체크
	for hero in _get_alive_heroes_in_battle():
		if hero != null and not hero.is_dead and hero.is_action_ready() and _has_ready_hero_action(hero):
			is_processing_action = true
			_execute_hero_action(hero)
			_check_battle_end()
			is_processing_action = false
			if is_inside_tree():
				ATBManager.action_executed.emit()
			return

	# 적 체크
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if enemy.is_action_ready():
			is_processing_action = true
			_execute_enemy_action(enemy)
			_check_battle_end()
			is_processing_action = false
			if is_inside_tree():
				ATBManager.action_executed.emit()
			return
#endregion






func _get_alive_heroes_in_battle(_require_face_chip: bool = true) -> Array:
	## 모든 살아있는 히어로가 모든 전투창에서 행동 가능
	var result: Array = []
	if PartyManager == null:
		return result
	var alive_heroes: Array = PartyManager.get_alive_heroes()
	for hero_any in alive_heroes:
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		result.append(hero)
	return result


func _prime_party_face_chips_and_locks() -> void:
	if not SHOW_HERO_FACE_CHIPS:
		return
	## 모든 히어로를 이 전투창에 표시 (락 무시)
	var heroes: Array = _get_alive_heroes_in_battle(false)
	for hero_any in heroes:
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		_show_hero_face_chip(hero.id, false, 0, false, 0.6)


func _has_face_chip_in_this_window(hero_id: String) -> bool:
	if hero_id.is_empty():
		return false
	var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
	return panel != null and is_instance_valid(panel)


func add_joined_hero_token(hero_id: String) -> bool:
	if not SHOW_HERO_FACE_CHIPS:
		return true
	if hero_id.is_empty():
		return false
	if not _can_accept_face_chip():
		return false
	var hero: Hero = PartyManager.get_hero_by_id(hero_id) if PartyManager else null
	if hero == null or hero.is_dead:
		return false
	if _has_face_chip_in_this_window(hero_id):
		return true
	_show_hero_face_chip(hero_id, false, 0, false, 0.6)
	_layout_persistent_face_chips(true)
	call_deferred("_emit_party_updated")
	return _has_face_chip_in_this_window(hero_id)


func on_enemy_defeated(enemy: BattleEnemy) -> void:
	_on_enemy_defeated(enemy)


func _execute_hero_action(hero: Hero) -> void:
	## 용사 즉시 행동 (동기, 대기 없음)
	if hero == null or hero.is_dead:
		return

	# 스킬 선택: 예약 스킬 우선, 없으면 기본공격
	var skill_id: String = _select_hero_skill(hero)
	if skill_id.is_empty():
		return

	# 예약 스킬 타겟 정보 저장 후 클리어
	var queued_enemy: Object = hero.queued_skill_enemy
	var queued_ally_id: String = hero.queued_skill_ally_id
	var is_queued: bool = not hero.queued_skill.is_empty()
	hero.queued_skill = ""
	hero.queued_skill_enemy = null
	hero.queued_skill_ally_id = ""

	var skill_data: Dictionary = DataManager.get_skill(skill_id)

	if skill_data.is_empty():
		if hero.is_action_ready():
			skill_id = "basic_attack"
			skill_data = DataManager.get_skill("basic_attack")
		else:
			return
	elif skill_id != "basic_attack":
		if not hero.is_skill_off_cooldown(skill_id):
			skill_id = "basic_attack"
			skill_data = DataManager.get_skill("basic_attack")
			is_queued = false
		elif _should_skip_skill_due_to_active_buff(hero, skill_data):
			skill_id = "basic_attack"
			skill_data = DataManager.get_skill("basic_attack")
			is_queued = false

	# 행동 타이머 리셋 (모든 행동에서 action_timer 리셋)
	hero.reset_action_timer()
	if skill_id != "basic_attack":
		hero.start_skill_cooldown(skill_id)

	# 합체 게이지 충전
	if skill_id == "basic_attack":
		BattleManager.on_hero_basic_attack()
	else:
		BattleManager.on_hero_skill_used()

	# 히어로 카드 공격 애니메이션
	BattleManager.hero_attacked.emit(hero.id)

	# 예약 스킬이면 저장된 타겟으로 실행
	if is_queued and skill_id != "basic_attack":
		var skill_type: String = skill_data.get("type", "physical")
		var target_type: String = skill_data.get("target", "single_enemy")
		# 버프/자기 버프 스킬 처리
		if skill_type == "buff" or skill_type == "resurrect":
			_execute_special_skill(hero, skill_id, skill_data)
		elif queued_enemy != null and is_instance_valid(queued_enemy):
			var enemy_target: BattleEnemy = queued_enemy as BattleEnemy
			if skill_type == "heal":
				_execute_heal_on_enemy(hero, skill_id, skill_data, enemy_target)
			else:
				_execute_single_attack(hero, skill_id, skill_data, enemy_target)
				_apply_post_attack_effects(hero, skill_id, skill_data, enemy_target)
		elif not queued_ally_id.is_empty():
			var ally: Hero = _find_hero_by_id(queued_ally_id)
			if skill_type == "heal":
				_execute_ally_skill(hero, skill_id, skill_data, "single_ally", ally)
			elif skill_type == "resurrect":
				_execute_special_skill(hero, skill_id, skill_data)
			else:
				_execute_attack_on_ally(hero, skill_id, skill_data, ally)
		else:
			match target_type:
				"self":
					_execute_special_skill(hero, skill_id, skill_data)
				"single_ally", "all_allies":
					if skill_type == "heal":
						_execute_ally_skill(hero, skill_id, skill_data, target_type)
					else:
						_execute_special_skill(hero, skill_id, skill_data)
				"all_enemies":
					_execute_aoe_attack(hero, skill_id, skill_data)
				_:
					_execute_single_attack(hero, skill_id, skill_data)
					_apply_post_attack_effects(hero, skill_id, skill_data)
		# 스킬 ATB는 이미 리셋됨 (행동 타이머 리셋 단계에서)
	else:
		# 기본공격
		var target_type: String = skill_data.get("target", "single_enemy")
		match target_type:
			"single_ally", "all_allies":
				_execute_ally_skill(hero, skill_id, skill_data, target_type)
			"all_enemies":
				_execute_aoe_attack(hero, skill_id, skill_data)
			_:
				_execute_single_attack(hero, skill_id, skill_data)


func _execute_enemy_action(enemy: BattleEnemy) -> void:
	## 적 즉시 행동 (동기, 대기 없음)
	if enemy == null or not enemy.is_alive():
		return

	# 행동 타이머 리셋
	enemy.reset_action_timer()

	_enemy_attack(enemy)


func _select_hero_skill(hero: Hero) -> String:
	## 용사의 스킬 선택 — 예약 스킬 우선, 없으면 쿨다운 끝난 스킬 자동 사용
	if not hero.queued_skill.is_empty():
		return hero.queued_skill
	# 해금 스킬 중 사용 가능한 것 자동 선택 (basic_attack 제외)
	var auto_skill: String = _pick_auto_skill(hero)
	if not auto_skill.is_empty():
		# 자동 선택된 스킬을 예약으로 설정 (타겟은 자동 결정)
		hero.queued_skill = auto_skill
		return auto_skill
	# 사용 가능한 스킬이 없으면 기본공격
	if hero.is_action_ready():
		return "basic_attack"
	return ""


func _pick_auto_skill(hero: Hero) -> String:
	## 우선순위 기반 자동 스킬 선택:
	## 1. 부활 — 죽은 아군 + 쿨다운 완료
	## 2. 힐 — HP ≤50% 아군 + 쿨다운 완료
	## 3. 버프 — 현재 미적용 + 쿨다운 완료
	## 4. 공격 스킬 — 쿨다운 완료 중 cooldown 값 큰 것 우선
	## 5. 빈 문자열 (basic_attack 폴백은 호출부에서)

	# --- 1. 부활 ---
	var has_dead: bool = false
	if PartyManager != null:
		for h in PartyManager.get_party():
			if h is Hero and h.is_dead:
				has_dead = true
				break
	if has_dead:
		for sid in hero.unlocked_skills:
			if sid == "basic_attack" or not hero.is_skill_enabled(sid):
				continue
			var sd: Dictionary = DataManager.get_skill(sid)
			if sd.get("type", "") == "resurrect" and hero.is_skill_off_cooldown(sid):
				return sid

	# --- 2. 힐 (임계치: 50%) ---
	var needs_heal: bool = false
	var self_needs_heal: bool = hero.get_hp_percent() < 0.5
	for h in _get_alive_heroes_in_battle():
		if h.get_hp_percent() < 0.5:
			needs_heal = true
			break
	if needs_heal or self_needs_heal:
		for sid in hero.unlocked_skills:
			if sid == "basic_attack" or not hero.is_skill_enabled(sid):
				continue
			var sd: Dictionary = DataManager.get_skill(sid)
			if sd.get("type", "") != "heal":
				continue
			if not hero.is_skill_off_cooldown(sid):
				continue
			if sd.get("target", "") == "self":
				if self_needs_heal:
					return sid
			else:
				if needs_heal:
					return sid

	# --- 3. 버프 (중복 안 걸림 + 쿨다운 완료) ---
	for sid in hero.unlocked_skills:
		if sid == "basic_attack" or not hero.is_skill_enabled(sid):
			continue
		var sd: Dictionary = DataManager.get_skill(sid)
		if sd.get("type", "") != "buff":
			continue
		if not hero.is_skill_off_cooldown(sid):
			continue
		if _should_skip_skill_due_to_active_buff(hero, sd):
			continue
		return sid

	# --- 4. 공격 스킬 (쿨다운 완료, cooldown 값 큰 것 우선) ---
	var attack_candidates: Array = []
	for sid in hero.unlocked_skills:
		if sid == "basic_attack" or not hero.is_skill_enabled(sid):
			continue
		var sd: Dictionary = DataManager.get_skill(sid)
		var stype: String = sd.get("type", "")
		if stype != "physical" and stype != "magic":
			continue
		if not hero.is_skill_off_cooldown(sid):
			continue
		attack_candidates.append({"id": sid, "cd": float(sd.get("cooldown", 0.0))})

	if not attack_candidates.is_empty():
		attack_candidates.sort_custom(func(a, b): return a["cd"] > b["cd"])
		return attack_candidates[0]["id"]

	# --- 5. 기본공격 폴백 ---
	return ""


func _has_ready_hero_action(hero: Hero) -> bool:
	## 기본 공격 또는 예약 스킬 가능 여부 확인
	if hero == null or hero.is_dead:
		return false
	return hero.is_action_ready()


func execute_skill(hero_id: String, skill_id: String, enemy_target: BattleEnemy = null, ally_target_id: String = "") -> void:
	## 스킬 예약: 다음 ATB 충전 완료 시 발동
	if current_state != BattleState.RUNNING:
		return
	var hero: Hero = _find_hero_by_id(hero_id)
	if hero == null or hero.is_dead:
		return

	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	if skill_data.is_empty():
		return
	if not hero.is_skill_off_cooldown(skill_id):
		return
	if _should_skip_skill_due_to_active_buff(hero, skill_data):
		return

	# 스킬 예약 (ATB는 리셋하지 않음 — 현재 게이지 유지)
	hero.queued_skill = skill_id
	hero.queued_skill_enemy = enemy_target
	hero.queued_skill_ally_id = ally_target_id


func _is_effect_already_active_on_target(target: Hero, effect: Dictionary) -> bool:
	if target == null:
		return true
	var eff_type: String = str(effect.get("type", ""))
	match eff_type:
		"atk_up", "def_up", "eva_up", "magic_amp":
			return target.has_buff(eff_type)
		"taunt":
			return target.has_taunt()
		_:
			return false


func _should_skip_skill_due_to_active_buff(hero: Hero, skill_data: Dictionary) -> bool:
	if hero == null or skill_data.is_empty():
		return false

	var effects: Array = skill_data.get("effects", [])
	if effects.is_empty():
		return false

	var buff_effects: Array = []
	for e in effects:
		var eff: Dictionary = e as Dictionary
		var eff_type: String = str(eff.get("type", ""))
		if eff_type in ["atk_up", "def_up", "eva_up", "magic_amp", "taunt"]:
			buff_effects.append(eff)
	if buff_effects.is_empty():
		return false

	var target_type: String = str(skill_data.get("target", "self"))
	var targets: Array[Hero] = []
	match target_type:
		"all_allies":
			for h in _get_alive_heroes_in_battle():
				if h is Hero:
					targets.append(h as Hero)
		"single_ally", "self":
			targets.append(hero)
		_:
			targets.append(hero)

	if targets.is_empty():
		return false

	for t in targets:
		for eff in buff_effects:
			if not _is_effect_already_active_on_target(t, eff):
				return false
	return true


func _execute_heal_on_enemy(hero: Hero, skill_id: String, skill_data: Dictionary, target: BattleEnemy) -> void:
	## 힐 스킬을 적에게 사용 → 적 체력 회복
	if target == null or not target.is_alive():
		return
	var sn: String = skill_data.get("name", "스킬")
	var heal_amount: int = _calc_heal_amount(hero, skill_data, skill_id)
	var actual_heal: int = target.heal(heal_amount)
	if SoundManager:
		SoundManager.play_heal()
	if target.has_method("show_heal_number"):
		target.show_heal_number(actual_heal)
	show_battle_text([hero.hero_name + "은(는) " + sn + "을(를) 사용!", target.enemy_name + "의 HP가 " + str(actual_heal) + " 회복되었다!"])


func _execute_attack_on_ally(hero: Hero, skill_id: String, skill_data: Dictionary, target: Hero) -> void:
	## 공격 스킬을 아군에게 사용 → 아군에게 데미지
	if target == null or target.is_dead:
		return
	var sn: String = skill_data.get("name", "스킬")
	# 간이 데미지 계산 (방어 무시, 순수 공격력 기반)
	var damage_base: int = int(skill_data.get("damage_base", 0))
	var scaling: Dictionary = skill_data.get("damage_scaling", {"stat": "str", "multiplier": 1.0})
	var multiplier: float = scaling.get("multiplier", 1.0)
	var damage: int = 0
	var skill_type: String = skill_data.get("type", "physical")
	if skill_id == "power_strike":
		damage = maxi(1, int(float(hero.get_atk()) * 2.0))
	elif skill_type == "magic":
		var int_stat: int = hero.get_base_stat("wis")
		damage = maxi(1, int(float(damage_base) + float(int_stat) * multiplier))
	else:
		damage = maxi(1, int(float(damage_base) + float(hero.get_atk()) * multiplier))
	# 스킬 레벨 보너스
	if skill_id != "basic_attack":
		var skill_lv: int = hero.get_skill_level(skill_id)
		if skill_lv > 1:
			damage = int(float(damage) * (1.0 + 0.1 * float(skill_lv - 1)))
	var actual: int = target.take_damage(damage)
	if SoundManager:
		SoundManager.play_attack(hero.class_id, false)
	show_battle_text([hero.hero_name + "은(는) " + sn + "을(를) 사용!", target.hero_name + "에게 " + str(damage) + "의 데미지!"])
	call_deferred("_emit_party_updated")


func get_enemy_at_position(screen_pos: Vector2) -> BattleEnemy:
	## 화면 좌표에서 살아있는 적을 찾아 반환
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var rect := Rect2(enemy.global_position, enemy.size)
		if rect.has_point(screen_pos):
			return enemy
	return null


func _find_finisher_skill(hero: Hero, skill_ids: Array) -> String:
	## 스킬로 적을 한 방에 처치할 수 있는지 확인, 가능한 스킬 ID 반환
	var alive: Array = get_alive_enemies()
	for skill_id in skill_ids:
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		var target_type: String = skill_data.get("target", "single_enemy")
		if target_type != "single_enemy":
			continue
		for enemy in alive:
			var estimated_dmg: int = _estimate_skill_damage(hero, enemy, skill_data, str(skill_id))
			if estimated_dmg >= enemy.current_hp:
				return skill_id
	return ""


func _estimate_skill_damage(hero: Hero, target: BattleEnemy, skill_data: Dictionary, skill_id: String = "") -> int:
	## 스킬 예상 데미지 (크리 제외, 방어 반영)
	var resolved_skill_id: String = skill_id if not skill_id.is_empty() else str(skill_data.get("id", ""))
	var damage: int = 0
	if resolved_skill_id == "power_strike":
		var basic_damage: int = _calc_physical_damage(float(hero.get_atk()), target.get_p_def())
		damage = maxi(1, basic_damage * 2)
	else:
		var damage_base: int = int(skill_data.get("damage_base", 0))
		var scaling: Dictionary = skill_data.get("damage_scaling", {"stat": "str", "multiplier": 1.0})
		var multiplier: float = scaling.get("multiplier", 1.0)
		var skill_type: String = skill_data.get("type", "physical")
		if skill_type == "magic":
			var int_stat: int = hero.get_base_stat("wis")
			var equip_matk_bonus: int = hero.get_magic_attack() - int_stat
			var matk: float = float(damage_base) + float(int_stat) * multiplier + float(equip_matk_bonus)
			damage = _calc_magic_damage(matk, target.get_m_def())
		else:
			var skill_mult: float = float(skill_data.get("skill_multiplier", multiplier))
			var skill_flat: int = int(skill_data.get("skill_flat_bonus", damage_base))
			var effective_atk: float = float(hero.get_atk()) * skill_mult + float(skill_flat)
			damage = _calc_physical_damage(effective_atk, target.get_p_def())

	# 스킬 레벨 보너스
	if resolved_skill_id != "basic_attack" and resolved_skill_id != "":
		var skill_lv: int = hero.get_skill_level(resolved_skill_id)
		if skill_lv > 1:
			var lv_bonus: float = float(DataManager.get_formula("damage").get("skill_level_bonus_per_level", 0.1))
			damage = int(float(damage) * (1.0 + lv_bonus * float(skill_lv - 1)))

	return maxi(1, damage)


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

	hero.reset_action_timer()
	if skill_id != "basic_attack":
		hero.start_skill_cooldown(skill_id)

	# 합체 게이지 충전
	if skill_id == "basic_attack":
		BattleManager.on_hero_basic_attack()
	else:
		BattleManager.on_hero_skill_used()

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
	## HP가 70% 미만인 아군 반환
	var result: Array = []
	for hero in _get_alive_heroes_in_battle():
		if hero.get_hp_percent() < 0.7:
			result.append(hero)
	return result


func _execute_special_skill(hero: Hero, skill_id: String, skill_data: Dictionary) -> void:
	## 버프/부활 등 특수 스킬 실행
	var skill_type: String = skill_data.get("type", "buff")
	var target_type: String = skill_data.get("target", "self")
	var effects: Array = skill_data.get("effects", [])
	var sn: String = skill_data.get("name", "스킬")

	_show_hero_face_chip(hero.id, false, 0, false, 1.0)

	if skill_type == "resurrect":
		# 죽은 아군 부활
		var hp_percent: float = 0.3
		for effect in effects:
			if effect.get("type", "") == "revive":
				hp_percent = float(effect.get("hp_percent", 0.3))
		var dead_hero: Hero = null
		if PartyManager != null:
			for h in PartyManager.get_party():
				var hero_h: Hero = h as Hero
				if hero_h != null and hero_h.is_dead:
					dead_hero = hero_h
					break
		if dead_hero != null:
			dead_hero.revive(hp_percent)
			show_battle_text([hero.hero_name + "은(는) " + sn + "을(를) 사용!", dead_hero.hero_name + "이(가) 되살아났다!"])
			if SoundManager != null:
				SoundManager.play_heal()
		else:
			show_battle_text([hero.hero_name + "은(는) " + sn + "을(를) 사용!", "그러나 효과가 없었다!"])
		call_deferred("_emit_party_updated")
		return

	# 버프 스킬 처리
	var buff_desc_lines: Array = [hero.hero_name + "은(는) " + sn + "을(를) 사용!"]
	for effect in effects:
		var eff_type: String = str(effect.get("type", ""))
		var eff_value: float = float(effect.get("value", 0.0))
		var eff_duration: float = float(effect.get("duration", 8.0))

		match eff_type:
			"atk_up", "def_up", "eva_up", "magic_amp":
				# 대상 결정
				var buff_targets: Array = []
				if target_type == "self":
					buff_targets.append(hero)
				elif target_type == "all_allies":
					buff_targets = _get_alive_heroes_in_battle()
				elif target_type == "single_ally":
					buff_targets.append(hero)
				for t in buff_targets:
					t.apply_buff(eff_type, eff_duration, eff_value)
				# 버프 종류별 설명
				var buff_name: String = ""
				match eff_type:
					"atk_up": buff_name = "공격력"
					"def_up": buff_name = "방어력"
					"eva_up": buff_name = "회피율"
					"magic_amp": buff_name = "마력"
				if target_type == "self":
					buff_desc_lines.append(hero.hero_name + "의 " + buff_name + "이(가) 올랐다!")
				else:
					buff_desc_lines.append("아군 전체의 " + buff_name + "이(가) 올랐다!")
			"taunt":
				var count: int = int(effect.get("count", 2))
				hero.apply_taunt(count)
				buff_desc_lines.append(hero.hero_name + "은(는) 적의 주의를 끌었다!")

	show_battle_text(buff_desc_lines)
	if SoundManager != null:
		SoundManager.play_heal()
	call_deferred("_emit_party_updated")


func _apply_post_attack_effects(hero: Hero, skill_id: String, skill_data: Dictionary, target: BattleEnemy = null) -> void:
	## 공격 후 특수 효과 적용 (ATB 초기화, 도트, ATB 슬로우, 즉사 등)
	var effects: Array = skill_data.get("effects", [])
	if target == null:
		# 단일 타겟 공격에서 타겟을 지정하지 않은 경우
		return
	for effect in effects:
		var eff_type: String = str(effect.get("type", ""))
		match eff_type:
			"reset_atb":
				target.reset_action_timer()
			"dot":
				var dps: int = int(effect.get("dps", 5))
				var duration: float = float(effect.get("duration", 5.0))
				target.apply_dot(dps, duration)
			"atb_slow":
				var value: float = float(effect.get("value", 0.5))
				var duration: float = float(effect.get("duration", 4.0))
				target.apply_atb_slow(value, duration)
			"instant_kill":
				if target.is_alive() and target.enemy_type != "boss":
					var chance: float = float(effect.get("chance", 15))
					if randf() * 100.0 < chance:
						target.take_damage(target.current_hp)
						target.show_damage_number(target.current_hp, true)
						if not target.is_alive():
							_on_enemy_defeated(target)


func _execute_single_attack(hero: Hero, skill_id: String, skill_data: Dictionary, forced_target: BattleEnemy = null) -> void:
	## 단일 대상 공격 실행
	if not has_alive_enemies():
		return

	var target: BattleEnemy = forced_target if (forced_target != null and forced_target.is_alive()) else _select_smart_target(hero)
	if target == null:
		return
	# 행동 선언 로그
	var action_line: String
	if skill_id == "basic_attack":
		action_line = hero.hero_name + "의 공격!"
	else:
		var sn: String = skill_data.get("name", "")
		action_line = hero.hero_name + "은(는) " + sn + "을(를) 사용!"

	_show_hero_face_chip(hero.id, false, 0, false, 0.95)
	if skill_id != "basic_attack":
		_show_skill_particle(target, skill_id, skill_data)

	var skill_name: String = skill_data.get("name", "공격")
	var skill_type: String = skill_data.get("type", "physical")

	# 다연사 (multi_hit) 처리
	var hit_count: int = _get_skill_effect_int(skill_data, "multi_hit", 1)
	var any_crit: bool = false
	var total_damage: int = 0
	var miss_count: int = 0

	for hit_i in hit_count:
		if not target.is_alive():
			break

		# 명중/회피 판정
		var hit_rate: float = hero.get_hit_rate()
		var eva_ignore: float = _get_skill_effect_value(skill_data, "ignore_eva", 0.0)
		var effective_eva: float = target.get_eva() * (1.0 - eva_ignore)
		var evade_roll: float = randf() * 100
		var hit_roll: float = randf() * 100
		var is_evaded: bool = (evade_roll < effective_eva) or (hit_roll > hit_rate)

		if is_evaded:
			miss_count += 1
			target.show_miss_text()
			target.play_evade_effect()
			continue

		# 크리티컬 판정
		var crit_bonus: float = _get_skill_effect_value(skill_data, "crit_bonus", 0.0)
		var crit_chance: float = hero.get_crit() + crit_bonus
		var is_crit: bool = randf() * 100 < crit_chance
		if is_crit:
			any_crit = true

		# 데미지 계산
		var damage: int = _calc_skill_damage(hero, target, skill_data, is_crit, skill_id)

		# 마력집중 버프 소모 (마법 스킬에만 적용)
		if skill_type == "magic" and hero.has_buff("magic_amp") and hit_i == 0:
			var amp: float = hero.get_buff_value("magic_amp")
			damage = int(float(damage) * amp)
			hero.consume_buff("magic_amp")

		# 클래스별 공격 사운드 (첫 타격만)
		if hit_i == 0 and SoundManager:
			SoundManager.play_attack(hero.class_id, is_crit)

		total_damage += damage
		target.take_damage(damage)
		target.play_hit_effect(is_crit)
		target.show_damage_number(damage, is_crit)

	_show_hero_face_chip(hero.id, false, 0, any_crit, 1.15)

	# 결과 로그 (고전 RPG 스타일: 한번에 2줄 표시)
	var log_lines: Array = [action_line]
	if miss_count > 0 and total_damage == 0:
		log_lines.append(target.enemy_name + "은(는) 공격을 피했다!")
	elif total_damage > 0:
		var result_line: String = target.enemy_name + "에게 " + str(total_damage) + "의 데미지!"
		if any_crit:
			result_line += " 회심의 일격!"
		log_lines.append(result_line)
	if not target.is_alive():
		log_lines.append(target.enemy_name + "을(를) 쓰러뜨렸다!")
	show_battle_text(log_lines)

	# 크리티컬 시 진동 효과
	if any_crit:
		play_critical_shake()

	# 도발 효과 적용 (방패 강타 등)
	var taunt_count: int = _get_skill_effect_int(skill_data, "taunt", 0)
	if taunt_count > 0:
		hero.apply_taunt(taunt_count)

	# 공격 후 특수 효과 (ATB 초기화, 도트, 슬로우, 즉사 등)
	if target.is_alive():
		_apply_post_attack_effects(hero, skill_id, skill_data, target)

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
	_show_hero_face_chip(hero.id, false, 0, false, 1.0)

	# 전체 공격 플래시 효과
	play_aoe_flash()

	# 클래스별 공격 사운드
	if SoundManager:
		SoundManager.play_attack(hero.class_id, false)

	# 마력집중 버프 소모 (AOE 마법에도 적용)
	var skill_type: String = skill_data.get("type", "physical")
	var has_magic_amp: bool = skill_type == "magic" and hero.has_buff("magic_amp")
	var magic_amp_val: float = hero.get_buff_value("magic_amp") if has_magic_amp else 1.0
	if has_magic_amp:
		hero.consume_buff("magic_amp")

	var any_crit: bool = false
	var aoe_total_damage: int = 0
	var aoe_defeated: Array[String] = []
	for target in alive_enemies:
		_show_skill_particle(target, skill_id, skill_data)
		var is_crit: bool = randf() * 100 < hero.get_crit()
		if is_crit:
			any_crit = true
		var damage: int = _calc_skill_damage(hero, target, skill_data, is_crit, skill_id)
		if has_magic_amp:
			damage = int(float(damage) * magic_amp_val)

		aoe_total_damage += damage
		target.take_damage(damage)
		target.play_hit_effect(is_crit)
		target.show_damage_number(damage, is_crit)

		if not target.is_alive():
			aoe_defeated.append(target.enemy_name)
			_on_enemy_defeated(target)

	# 고전 RPG 스타일 로그
	var log_lines: Array = [hero.hero_name + "은(는) " + skill_name + "을(를) 사용!"]
	log_lines.append("전체에 " + str(aoe_total_damage) + "의 데미지!")
	for defeated_name in aoe_defeated:
		log_lines.append(defeated_name + "을(를) 쓰러뜨렸다!")
	show_battle_text(log_lines)

	# 크리티컬이 하나라도 있으면 진동
	if any_crit:
		play_critical_shake()
	_show_hero_face_chip(hero.id, false, 0, any_crit, 1.2)


func _show_skill_particle(target: BattleEnemy, skill_id: String, skill_data: Dictionary) -> void:
	## 스킬별 임시 이모지 파티클
	if target == null:
		return

	var resolved_skill_id: String = skill_id.strip_edges()
	var skill_name: String = str(skill_data.get("name", "")).to_lower()
	var skill_type: String = str(skill_data.get("type", "physical"))
	var emoji: String = "👊"
	var burst_count: int = 1

	# ID 매핑 우선
	match resolved_skill_id:
		"fireball":
			emoji = "🔥"
			burst_count = 3
		"power_strike", "shield_bash":
			emoji = "👊"
			burst_count = 2
		"aimed_shot":
			emoji = "🏹"
		"backstab":
			emoji = "🗡️"
		"charge":
			emoji = "💨"
			burst_count = 2
		"multi_shot":
			emoji = "🏹"
			burst_count = 3
		"poison_arrow":
			emoji = "☠️"
		"vital_strike":
			emoji = "🗡️"
			burst_count = 2
		"ice_bolt":
			emoji = "❄️"
			burst_count = 2
		"basic_attack":
			return

	# ID가 기대와 다를 때 이름 기반 보조 매핑
	if emoji == "👊":
		if skill_name.find("파이어볼") >= 0 or skill_name.find("fireball") >= 0:
			emoji = "🔥"
			burst_count = maxi(burst_count, 3)
		elif skill_name.find("강타") >= 0 or skill_name.find("타격") >= 0 or skill_name.find("strike") >= 0 or skill_name.find("bash") >= 0:
			emoji = "👊"
			burst_count = maxi(burst_count, 2)
		elif skill_name.find("조준") >= 0 or skill_name.find("shot") >= 0:
			emoji = "🏹"
		elif skill_name.find("백스탭") >= 0 or skill_name.find("backstab") >= 0 or skill_name.find("stab") >= 0:
			emoji = "🗡️"

	# 기본 fallback: magic 타입은 ✨
	if emoji == "👊" and skill_type == "magic":
		emoji = "✨"

	target.show_attack_particle(emoji, burst_count)


func _execute_ally_skill(hero: Hero, skill_id: String, skill_data: Dictionary, target_type: String, forced_target: Hero = null) -> void:
	## 아군 대상 스킬 실행 (힐 등)
	var skill_name: String = skill_data.get("name", "스킬")
	var skill_type: String = skill_data.get("type", "utility")
	var action_line: String = hero.hero_name + "은(는) " + skill_name + "을(를) 사용!"

	if skill_type == "heal":
		var targets: Array = []
		if forced_target != null and not forced_target.is_dead:
			targets.append(forced_target)
		elif target_type == "self":
			# 자기 자신 회복 (치유의빛)
			if not hero.is_dead:
				targets.append(hero)
		elif target_type == "single_ally":
			# 가장 체력이 낮은 아군 선택
			var lowest_hp_hero: Hero = null
			var lowest_percent: float = 1.0
			for h_any in _get_alive_heroes_in_battle():
				var h: Hero = h_any as Hero
				if h == null:
					continue
				var hp_percent: float = h.get_hp_percent()
				if hp_percent < lowest_percent:
					lowest_percent = hp_percent
					lowest_hp_hero = h
			if lowest_hp_hero:
				targets.append(lowest_hp_hero)
		else:  # all_allies
			targets = _get_alive_heroes_in_battle()

		# 회복 사운드 재생
		if targets.size() > 0:
			if SoundManager != null:
				SoundManager.play_heal()

		var log_lines: Array = [action_line]
		for target in targets:
			var heal_amount: int = _calc_heal_amount(hero, skill_data, skill_id)
			var actual_heal: int = target.heal(heal_amount)
			log_lines.append(target.hero_name + "의 HP가 " + str(heal_amount) + " 회복되었다!")

		show_battle_text(log_lines)
		call_deferred("_emit_party_updated")
	else:
		show_battle_text([action_line])
		pass


func _calc_skill_damage(hero: Hero, target: BattleEnemy, skill_data: Dictionary, is_crit: bool, skill_id: String = "") -> int:
	## 스킬 데미지 계산
	var resolved_skill_id: String = skill_id if not skill_id.is_empty() else str(skill_data.get("id", ""))
	var damage_base: int = int(skill_data.get("damage_base", 0))
	var scaling: Dictionary = skill_data.get("damage_scaling", {"stat": "str", "multiplier": 1.0})
	var multiplier: float = scaling.get("multiplier", 1.0)
	var skill_type: String = skill_data.get("type", "physical")
	var damage: int = 1
	var hero_atk: int = hero.get_buffed_atk()  # ATK 버프 반영
	var crit_attack_base: float = float(hero_atk)
	if resolved_skill_id == "power_strike":
		# 강타: 평타 강화가 아니라 스킬, 최종 데미지 = 평타 데미지의 2배
		var basic_damage: int = _calc_physical_damage(float(hero_atk), target.get_p_def())
		damage = maxi(1, basic_damage * 2)
		crit_attack_base = float(hero_atk) * 2.0
	elif skill_type == "magic":
		var int_stat: int = hero.get_base_stat("wis")
		var equip_matk_bonus: int = hero.get_magic_attack() - int_stat
		var matk: float = float(damage_base) + float(int_stat) * multiplier + float(equip_matk_bonus)
		damage = _calc_magic_damage(matk, target.get_m_def())
		crit_attack_base = matk
	else:
		var skill_mult: float = float(skill_data.get("skill_multiplier", multiplier))
		var skill_flat: int = int(skill_data.get("skill_flat_bonus", damage_base))
		var effective_atk: float = float(hero_atk) * skill_mult + float(skill_flat)
		damage = _calc_physical_damage(effective_atk, target.get_p_def())
		crit_attack_base = effective_atk

	# 스킬 레벨 보너스 (레벨당 보너스, 기본공격 제외)
	if resolved_skill_id != "basic_attack" and resolved_skill_id != "":
		var skill_lv: int = hero.get_skill_level(resolved_skill_id)
		if skill_lv > 1:
			var lv_bonus: float = float(DataManager.get_formula("damage").get("skill_level_bonus_per_level", 0.1))
			damage = int(float(damage) * (1.0 + lv_bonus * float(skill_lv - 1)))
			crit_attack_base *= (1.0 + lv_bonus * float(skill_lv - 1))

	if is_crit:
		damage = _calc_critical_damage_from_attack(crit_attack_base)
	return maxi(1, damage)


func _calc_heal_amount(hero: Hero, skill_data: Dictionary, skill_id: String = "") -> int:
	## 힐량 계산
	var heal_base: float = float(skill_data.get("heal_base", skill_data.get("base_damage", 0)))
	var scaling: Dictionary = skill_data.get("heal_scaling", {"stat": "int", "multiplier": skill_data.get("scaling", 0.5)})
	var multiplier: float = float(scaling.get("multiplier", skill_data.get("scaling", 0.5)))
	var int_stat: int = hero.get_base_stat("wis")
	var base_heal: float = heal_base + float(int_stat) * multiplier

	# 스킬 레벨 보너스
	var resolved_id: String = skill_id if not skill_id.is_empty() else str(skill_data.get("id", ""))
	if resolved_id != "" and resolved_id != "basic_attack":
		var skill_lv: int = hero.get_skill_level(resolved_id)
		if skill_lv > 1:
			var lv_bonus: float = float(DataManager.get_formula("damage").get("skill_level_bonus_per_level", 0.1))
			base_heal *= (1.0 + lv_bonus * float(skill_lv - 1))

	return _round_half_up(base_heal)


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

	# 한 방에 죽일 수 있는 적 우선
	var atk := hero.get_atk()
	for enemy in alive:
		var expected := _calc_physical_damage(float(atk), enemy.get_p_def())
		if expected >= enemy.current_hp:
			return enemy

	# HP가 가장 낮은 적 우선
	alive.sort_custom(func(a, b): return a.current_hp < b.current_hp)
	return alive[0]


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

	# 도발 상태인 용사이 있으면 우선 타겟
	var target: Hero = _find_taunt_target(alive_heroes)
	if target == null:
		target = _pick_enemy_target(alive_heroes, enemy)

	enemy.play_attack_effect()

	# 적 공격 사운드
	if SoundManager:
		SoundManager.play_enemy_attack()

	var action_line: String = enemy.enemy_name + "의 공격!"

	# 블라인드 디버프 시 미스 확률 증가
	var blind_miss: bool = false
	if enemy.has_method("is_blinded") and enemy.is_blinded():
		var blind_penalty: float = absf(enemy.get_blind_penalty())
		blind_miss = randf() * 100 < blind_penalty
	if blind_miss:
		show_battle_text([action_line, "공격이 빗나갔다!"])
		return

	var is_evaded := randf() * 100 < target.get_buffed_eva()
	if is_evaded:
		show_battle_text([action_line, target.hero_name + "은(는) 공격을 피했다!"])
		return

	var is_crit := randf() * 100 < enemy.get_crit()
	var damage := _calc_enemy_damage(enemy, target, is_crit)

	# 도발 상태였으면 카운트 소모
	var was_taunting := target.consume_taunt()

	PartyManager.on_hero_damaged(target, damage)
	BattleManager.on_hero_hit()
	if target.is_dead:
		BattleManager.on_hero_died()
	_show_hero_face_chip(target.id, true, damage, is_crit, 1.25)
	BattleManager.hero_damaged.emit(target.id)
	call_deferred("_emit_party_updated")

	# 고전 RPG 스타일 로그
	var log_lines: Array = [action_line]
	var result_line: String = target.hero_name + "에게 " + str(damage) + "의 데미지!"
	if is_crit:
		result_line += " 회심의 일격!"
	log_lines.append(result_line)
	if target.is_dead:
		log_lines.append(target.hero_name + "은(는) 쓰러졌다!")
		call_deferred("_emit_party_updated")
	show_battle_text(log_lines)


func _calc_enemy_damage(enemy: BattleEnemy, target: Hero, is_crit: bool) -> int:
	var attack: int = enemy.get_atk()
	if enemy.damage_type == "magic":
		var magic_damage := _calc_magic_damage(float(attack), target.get_m_def())
		return _calc_critical_damage_from_attack(float(attack)) if is_crit else magic_damage
	else:
		var buffed_def: int = target.get_buffed_def()  # DEF 버프 반영
		var physical_damage := _calc_physical_damage(float(attack), buffed_def)
		return _calc_critical_damage_from_attack(float(attack)) if is_crit else physical_damage


func _calc_physical_damage(atk: float, def_val: float) -> int:
	var f: Dictionary = DataManager.get_formula("damage", "physical")
	var atk_m: float = float(f.get("atk_mult", 0.5))
	var def_m: float = float(f.get("def_mult", 0.25))
	return maxi(int(f.get("min", 1)), _round_half_up(atk * atk_m - def_val * def_m))


func _calc_magic_damage(matk: float, mdef: float) -> int:
	var f: Dictionary = DataManager.get_formula("damage", "magic")
	var matk_m: float = float(f.get("matk_mult", 0.5))
	var mdef_m: float = float(f.get("mdef_mult", 0.25))
	return maxi(int(f.get("min", 1)), _round_half_up(matk * matk_m - mdef * mdef_m))


func _calc_critical_damage_from_attack(attack_value: float) -> int:
	## 크리티컬: 방어 무시
	var f: Dictionary = DataManager.get_formula("damage", "critical")
	var atk_m: float = float(f.get("atk_mult", 0.5))
	return maxi(int(f.get("min", 1)), _round_half_up(attack_value * atk_m))


func _round_half_up(value: float) -> int:
	# Rules require 0.5 up.
	if value >= 0.0:
		return int(floor(value + 0.5))
	return int(ceil(value - 0.5))


func _find_taunt_target(alive_heroes: Array) -> Hero:
	## 도발 상태인 용사 찾기
	for hero in alive_heroes:
		if hero.has_taunt():
			return hero
	return null


func _pick_enemy_target(alive_heroes: Array, enemy: BattleEnemy) -> Hero:
	## 가중치 기반 타겟 선택 — 골고루 때리되, HP 낮은 용사이 약간 더 맞음
	## 보스: 완전 균등 랜덤
	if alive_heroes.size() == 1:
		return alive_heroes[0]

	if enemy.enemy_type == "boss":
		return alive_heroes[randi() % alive_heroes.size()]

	# 일반/엘리트: 가중치 랜덤
	# 기본 가중치 1.0 + HP% 낮을수록 보너스 (최대 +0.5)
	# → HP 100% 용사 = 1.0, HP 0% 용사 = 1.5
	# 4명 파티 기준: 25% vs 37.5% 정도 차이 (완전 집중은 아님)
	var weights: Array[float] = []
	var total: float = 0.0
	for hero in alive_heroes:
		var hp_pct: float = hero.get_hp_percent()
		var w: float = 1.0 + (1.0 - hp_pct) * 0.5
		weights.append(w)
		total += w

	var roll: float = randf() * total
	var acc: float = 0.0
	for i in range(alive_heroes.size()):
		acc += weights[i]
		if roll <= acc:
			return alive_heroes[i]

	return alive_heroes[alive_heroes.size() - 1]


func _show_hero_face_chip(
	hero_id: String,
	is_damaged: bool,
	damage_number: int = 0,
	is_crit: bool = false,
	_hold_time: float = 0.95
) -> void:
	if not SHOW_HERO_FACE_CHIPS:
		return
	if hero_id.is_empty():
		return
	if battle_area == null:
		return
	if SpriteManager == null or not SpriteManager.has_method("get_hero_face_sprite"):
		return

	var key: String = hero_id
	var now_ms: int = Time.get_ticks_msec()
	var prev_ms: int = int(_face_chip_last_ms.get(key, 0))
	var bypass_throttle: bool = is_damaged and damage_number > 0
	if not bypass_throttle and now_ms - prev_ms < 60:
		return
	_face_chip_last_ms[key] = now_ms
	_claim_global_face_chip_owner()

	var face_tex: Texture2D = SpriteManager.get_hero_face_sprite(hero_id)
	if face_tex == null:
		return

	var panel: PanelContainer = _face_chip_panels.get(key, null) as PanelContainer
	var is_new_panel: bool = panel == null or not is_instance_valid(panel)
	if is_new_panel:
		_ensure_face_chip_layer()
		var token_node: Node = BATTLE_WINDOW_UNIT_TOKEN_SCENE.instantiate()
		panel = token_node as PanelContainer
		if panel == null:
			return
		panel.name = "PersistentFaceChip_%s" % key
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.z_index = 70
		panel.custom_minimum_size = FACE_CHIP_SIZE
		_face_chip_layer.add_child(panel)
		panel.set_as_top_level(false)
		var face_node_new: TextureRect = panel.get_node_or_null("Face") as TextureRect
		if face_node_new != null:
			face_node_new.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.gui_input.connect(_on_face_chip_gui_input.bind(key))
		panel.mouse_entered.connect(_on_face_chip_mouse_entered.bind(key))
		panel.mouse_exited.connect(_on_face_chip_mouse_exited.bind(key))
		_face_chip_panels[key] = panel
		if not _face_chip_order.has(key):
			_face_chip_order.append(key)

	if panel.has_method("apply_state_style"):
		panel.call("apply_state_style", is_damaged)

	if panel.has_method("set_token_texture"):
		panel.call("set_token_texture", face_tex)
	else:
		var face_node: TextureRect = panel.get_node_or_null("Face") as TextureRect
		if face_node != null:
			face_node.texture = face_tex

	if is_new_panel:
		panel.modulate.a = 0.0
		panel.scale = Vector2(0.9, 0.9)
	else:
		panel.modulate.a = 1.0
		panel.scale = Vector2.ONE

	_layout_persistent_face_chips(is_new_panel)

	if is_new_panel:
		var show_tw := create_tween()
		show_tw.set_parallel(true)
		show_tw.tween_property(panel, "modulate:a", 1.0, 0.1)
		show_tw.tween_property(panel, "scale", Vector2.ONE, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		_play_face_chip_pulse(panel)
	if is_damaged and damage_number > 0:
		_play_face_chip_hit_effect(panel, is_crit)

	if _face_chip_order.size() >= 2:
		_play_face_chip_overlap_effect(panel)


func _layout_persistent_face_chips(animated: bool) -> void:
	if battle_area == null:
		return
	if _face_chip_dragging:
		return

	var valid_keys: Array[String] = []
	var panels: Array[PanelContainer] = []
	for key in _face_chip_order:
		var panel: PanelContainer = _face_chip_panels.get(key, null) as PanelContainer
		if panel == null or not is_instance_valid(panel):
			continue
		if panel.size.x <= 0.0 or panel.size.y <= 0.0:
			panel.size = panel.custom_minimum_size
		valid_keys.append(key)
		panels.append(panel)
	_face_chip_order = valid_keys
	if panels.is_empty():
		return

	var spacing: float = FACE_CHIP_SPACING
	var total_width: float = 0.0
	for i in range(panels.size()):
		total_width += panels[i].size.x
		if i > 0:
			total_width += spacing

	var area_size: Vector2 = battle_area.size
	var start_x: float = (area_size.x - total_width) * 0.5
	var max_h: float = 0.0
	for panel in panels:
		max_h = maxf(max_h, panel.size.y)
	var y: float = area_size.y - max_h - 6.0
	var cursor_x: float = start_x

	for panel in panels:
		var target_pos := Vector2(cursor_x, y)
		if animated:
			var tw := create_tween()
			tw.tween_property(panel, "position", target_pos, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			panel.position = target_pos
		cursor_x += panel.size.x + spacing


func _spawn_face_chip_damage_number(panel: PanelContainer, damage: int, is_crit: bool) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var label := Label.new()
	label.text = ("CRIT %d" % damage) if is_crit else str(damage)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12 if is_crit else 11)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0) if is_crit else Color(1.0, 0.78, 0.78, 1.0))
	label.z_index = 120
	panel.add_child(label)
	label.custom_minimum_size = Vector2(34, 14)
	label.position = Vector2(2, -6)
	label.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.08)
	tw.tween_property(label, "position:y", -12.0, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(label, "modulate:a", 0.0, 0.2)
	tw.tween_callback(label.queue_free)


func _claim_global_face_chip_owner() -> void:
	# 페이스칩은 전투창마다 독립 유지한다.
	_global_face_chip_owner_window_id = get_instance_id()


func _ensure_face_chip_layer() -> void:
	if _face_chip_layer != null and is_instance_valid(_face_chip_layer):
		return
	if battle_area == null:
		return
	_face_chip_layer = Control.new()
	_face_chip_layer.name = "FaceChipLayer"
	_face_chip_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face_chip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_chip_layer.z_index = 80
	battle_area.add_child(_face_chip_layer)


func _deactivate_persistent_face_chip() -> void:
	_face_chip_dragging = false
	_face_chip_drag_hero_id = ""
	_face_chip_drag_panel = null
	for key in _face_chip_panels.keys():
		var panel: PanelContainer = _face_chip_panels[key] as PanelContainer
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	_face_chip_panels.clear()
	_face_chip_order.clear()


func _on_face_chip_gui_input(event: InputEvent, hero_id: String) -> void:
	if hero_id.is_empty():
		return
	var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
	if panel == null or not is_instance_valid(panel):
		return

	if event is InputEventMouseButton:
		var btn: InputEventMouseButton = event as InputEventMouseButton
		if btn.button_index != MOUSE_BUTTON_LEFT:
			return
		if btn.pressed:
			_face_chip_dragging = true
			_face_chip_drag_hero_id = hero_id
			_face_chip_drag_panel = panel
			_face_chip_drag_offset = btn.global_position - panel.global_position
			panel.z_index = 220
			accept_event()
			return

		if _face_chip_dragging and _face_chip_drag_hero_id == hero_id:
			var drop_window: BattleWindow = _find_face_chip_drop_window(btn.global_position)
			if drop_window != null and is_instance_valid(drop_window):
				_transfer_face_chip_to_window(hero_id, drop_window)
			_finish_face_chip_drag()
			accept_event()
	elif event is InputEventMouseMotion:
		if _face_chip_dragging and _face_chip_drag_hero_id == hero_id:
			panel.global_position = event.global_position - _face_chip_drag_offset
			accept_event()


func _finish_face_chip_drag() -> void:
	if _face_chip_drag_panel != null and is_instance_valid(_face_chip_drag_panel):
		_face_chip_drag_panel.z_index = 70
	_face_chip_dragging = false
	_face_chip_drag_hero_id = ""
	_face_chip_drag_panel = null
	_layout_persistent_face_chips(false)


func _find_face_chip_drop_window(global_pos: Vector2) -> BattleWindow:
	var result: BattleWindow = null
	var best_index: int = -999999
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("battle_windows"):
		if node == null or not is_instance_valid(node):
			continue
		if not (node is BattleWindow):
			continue
		var window: BattleWindow = node as BattleWindow
		if window == null:
			continue
		if not window._can_accept_face_chip():
			continue
		var rect: Rect2 = Rect2(window.global_position, window.size)
		if not rect.has_point(global_pos):
			continue
		var idx: int = window.get_index()
		if idx >= best_index:
			best_index = idx
			result = window
	return result


func _can_accept_face_chip() -> bool:
	if is_event_mode:
		return false
	return current_state == BattleState.RUNNING or current_state == BattleState.STARTING


func transfer_all_face_chips_to_window(target_window: BattleWindow) -> Array[String]:
	var moved_hero_ids: Array[String] = []
	if target_window == null or not is_instance_valid(target_window):
		return moved_hero_ids
	if target_window == self:
		return moved_hero_ids
	var ordered_hero_ids: Array[String] = _face_chip_order.duplicate()
	for hero_id_any in ordered_hero_ids:
		var hero_id: String = str(hero_id_any)
		if hero_id.is_empty():
			continue
		var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
		if panel == null or not is_instance_valid(panel):
			continue
		_transfer_face_chip_to_window(hero_id, target_window)
		if not _face_chip_panels.has(hero_id):
			moved_hero_ids.append(hero_id)
	return moved_hero_ids


func _transfer_face_chip_to_window(hero_id: String, target_window: BattleWindow) -> void:
	if hero_id.is_empty() or target_window == null or not is_instance_valid(target_window):
		return
	if target_window == self:
		return
	var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
	if panel == null or not is_instance_valid(panel):
		return
	_face_chip_panels.erase(hero_id)
	_face_chip_order.erase(hero_id)
	panel.queue_free()
	target_window._show_hero_face_chip(hero_id, false, 0, false, 0.6)
	target_window._layout_persistent_face_chips(false)


func _play_face_chip_pulse(panel: PanelContainer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.08)
	tw.chain().tween_property(panel, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _play_face_chip_overlap_effect(panel: PanelContainer) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var style := panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var sb: StyleBoxFlat = style as StyleBoxFlat
		sb.border_color = Color(1.0, 1.0, 0.35, 1.0)
		panel.add_theme_stylebox_override("panel", sb)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "rotation_degrees", 4.0, 0.06)
	tw.chain().tween_property(panel, "rotation_degrees", -4.0, 0.09)
	tw.chain().tween_property(panel, "rotation_degrees", 0.0, 0.1)


func _play_face_chip_hit_effect(panel: PanelContainer, is_crit: bool) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var flash: ColorRect = panel.get_node_or_null("HitFlash") as ColorRect
	if flash == null:
		flash = ColorRect.new()
		flash.name = "HitFlash"
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.color = Color(1.0, 0.2, 0.2, 0.0)
		flash.z_index = 130
		panel.add_child(flash)

	flash.color = Color(1.0, 0.25, 0.25, 0.0) if is_crit else Color(1.0, 0.45, 0.45, 0.0)
	var base_pos: Vector2 = panel.global_position

	var flash_tw := create_tween()
	flash_tw.tween_property(flash, "color:a", 0.82 if is_crit else 0.62, 0.045)
	flash_tw.chain().tween_property(flash, "color:a", 0.0, 0.17)

	var hit_tw := create_tween()
	hit_tw.tween_property(panel, "global_position:x", base_pos.x + (5.0 if is_crit else 3.5), 0.045).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hit_tw.chain().tween_property(panel, "global_position:x", base_pos.x - (4.0 if is_crit else 2.8), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hit_tw.chain().tween_property(panel, "global_position:x", base_pos.x, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
#endregion


#region 메시지 박스 팝업
func _show_msg_box(text: String, color: Color = Color.WHITE, duration: float = 1.0) -> void:
	## 전투창 중앙에 메시지 박스 팝업 (검은 배경 + 흰 테두리, 컴팩트)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 1.0, 1.0, 0.85)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 50

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)

	# top_level로 컨테이너 레이아웃에서 분리
	add_child(panel)
	panel.set_as_top_level(true)

	# 1프레임 후 실제 크기 계산 → 중앙 배치
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var area_center: Vector2 = battle_area.global_position + battle_area.size / 2
	panel.global_position = area_center - panel.size / 2
	panel.pivot_offset = panel.size / 2

	# 팝업 등장 애니메이션
	panel.scale = Vector2(0.7, 0.7)
	panel.modulate.a = 0.0
	var pop := create_tween()
	pop.set_parallel(true)
	pop.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	pop.tween_property(panel, "modulate:a", 1.0, 0.08)

	# 표시 대기
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(panel):
		return

	# 페이드 아웃
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.25)
	tween.tween_callback(panel.queue_free)
	await tween.finished


func _build_encounter_message() -> String:
	## 전투 시작 메시지 생성 (적 이름 조합)
	var name_counts: Dictionary = {}
	for e in enemies:
		if e != null:
			var ename: String = e.enemy_name
			name_counts[ename] = name_counts.get(ename, 0) + 1

	var parts: Array = []
	for ename in name_counts:
		var count: int = name_counts[ename]
		if count > 1:
			parts.append("%s x%d" % [ename, count])
		else:
			parts.append(ename)

	return "%s이(가) 나타났다!" % ", ".join(parts)
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	if GameManager:
		GameManager.add_kill_count(1)
	BattleManager.on_enemy_killed()
	_on_local_grudge_kill()

	# 보상 계산 (특성 적용)
	var exp_trait_mult: float = 1.0 + _get_trait_effect_float("exp_mult")
	var gold_trait_mult: float = 1.0 + _get_trait_effect_float("gold_mult")
	var trinket_exp_mult: float = 1.0
	var trinket_gold_mult: float = 1.0
	if GameManager != null:
		if GameManager.has_method("get_trinket_reward_exp_multiplier"):
			trinket_exp_mult = float(GameManager.call("get_trinket_reward_exp_multiplier"))
		if GameManager.has_method("get_trinket_reward_gold_multiplier"):
			trinket_gold_mult = float(GameManager.call("get_trinket_reward_gold_multiplier"))

	var base_gold_mult: float = 1.0
	if DataManager != null:
		base_gold_mult = float(DataManager.get_formula("loot_gauge", "gold_multiplier"))
		if base_gold_mult <= 0.0:
			base_gold_mult = 1.0
	var exp_reward: int = int(enemy.get_exp_reward() * exp_trait_mult * trinket_exp_mult)
	var gold_reward: int = int(enemy.get_gold_reward() * gold_trait_mult * trinket_gold_mult * base_gold_mult)
	var items: Array = enemy.roll_drops()

	total_exp += exp_reward
	total_gold += gold_reward
	drop_items.append_array(items)
	_refresh_reward_preview_ui()

	# 경험치 분배 (골드 기반 간이 계산)
	var per_kill_exp: int = maxi(5, gold_reward / 2)
	for hero in _get_alive_heroes_in_battle():
		var old_lv: int = hero.level
		var exp_result: Dictionary = hero.gain_exp(per_kill_exp)
		_check_skill_select_on_levelup(hero, old_lv, exp_result)
		if exp_result.get("leveled_up", false):
			if SoundManager:
				SoundManager.play_level_up()
	call_deferred("_emit_party_updated")

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
	## 엘리트 처치 특수 연출: 떨림 → 폭발 → 해산 → 보상 버튼 노출 (비동기, 전투 차단 없음)
	var tween := create_tween()

	# 1) 엘리트 떨림
	if elite.sprite:
		for i in range(6):
			tween.tween_property(elite, "position:x", elite.position.x + 3, 0.08)
			tween.tween_property(elite, "position:x", elite.position.x - 3, 0.08)
		tween.tween_property(elite, "position:x", elite.position.x, 0.05)

	# 2) 엘리트 폭발 이펙트
	if elite.sprite:
		tween.tween_property(elite, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(elite, "modulate", Color(2.0, 1.0, 2.0, 1.0), 0.1)
		tween.tween_property(elite, "modulate:a", 0.0, 0.15)
		tween.tween_property(elite, "scale", Vector2(0.0, 0.0), 0.1)

	tween.tween_callback(func(): elite.visible = false)

	# 3) 남은 적 즉시 해산 (보상 없이 소멸)
	tween.tween_callback(func():
		for enemy in enemies:
			if enemy != null and enemy.is_alive() and enemy != elite:
				if enemy.sprite:
					var fade := create_tween()
					fade.tween_property(enemy, "modulate:a", 0.0, 0.3)
					fade.tween_callback(func(): enemy.visible = false)
				enemy.current_hp = 0
	)

	# 4) 짧은 대기 후 보상 버튼 표시
	tween.tween_interval(0.4)
	tween.tween_callback(_end_battle_victory)


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
	## 모든 적이 처치되었는지 확인
	# 종료 판정 로직을 _check_battle_end로 일원화해서 최소 표시시간 규칙을 동일 적용
	_check_battle_end()


func _check_battle_end() -> bool:
	if current_state != BattleState.RUNNING:
		return true
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)

	# 패배 판정은 전투창 로컬 페이스칩이 아니라 파티 전체 생존 기준으로 처리
	var alive_heroes: Array = PartyManager.get_alive_heroes()

	if alive_enemies.is_empty():
		if not _wave_clear_processed:
			_wave_clear_processed = true
			_on_wave_cleared()

		# 적이 모두 사라짐 - 너무 빠른 즉시 종료를 막고 최소 시간/사망 모션을 보장
		_update_buttons_for_enemies()
		var now_ms: int = Time.get_ticks_msec()
		var min_visible_ms: int = int(MIN_BATTLE_VISIBLE_TIME * 1000.0)
		var min_ready_ms: int = int(VICTORY_POST_KILL_DELAY * 1000.0)
		if pending_victory_ready_ms <= 0:
			pending_victory_ready_ms = now_ms + min_ready_ms
		var can_finish: bool = (now_ms - battle_started_ms) >= min_visible_ms and now_ms >= pending_victory_ready_ms
		if can_finish:
			_end_battle_victory()
			return true
		pending_victory = true
		pending_victory_ready_ms = maxi(pending_victory_ready_ms, now_ms + min_ready_ms)
		return false

	_wave_clear_processed = false
	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true

	return false


func _report_rewards_and_close() -> void:
	## 보상을 BattleManager에 누적하고 전투창 닫기
	BattleManager.add_accumulated_reward(total_exp, total_gold, drop_items)

	# 전투창 종료 (승리)
	current_state = BattleState.VICTORY
	set_process(false)
	battle_ended.emit(battle_id, true)

	_play_close_effect()


func _update_buttons_for_no_enemies() -> void:
	## 적이 없을 때 버튼 상태 업데이트
	pass


func _show_claim_reward_button() -> void:
	_end_battle_victory()


func is_waiting_reward_claim() -> bool:
	return false


func _on_reward_claim_pressed() -> void:
	return


func _clear_reward_claim_button() -> void:
	waiting_reward_claim = false


func _end_battle_victory() -> void:
	if current_state == BattleState.VICTORY:
		return
	waiting_reward_claim = false
	current_state = BattleState.VICTORY
	set_process(false)

	clear_battle_log()

	# 도주 버튼 숨기기
	if run_button:
		run_button.visible = false

	# 승리 사운드 재생
	if SoundManager != null:
		SoundManager.play_victory()

	# HUD 보상 알림 (비차단)
	_apply_heart_rewards(1.0)

	# 보상 처리
	_grant_exp_rewards()
	call_deferred("_emit_party_updated")

	# 스킬 선택 큐가 있으면 팝업 먼저 처리
	if not _skill_select_queue.is_empty():
		_skill_select_in_victory = true
		_show_next_skill_select()
		return

	_play_victory_text_then_close()


func _check_skill_select_on_levelup(hero: Hero, old_level: int, result: Dictionary, show_immediately: bool = true) -> void:
	## 레벨업할 때마다 스킬 선택 큐에 추가 (show_immediately=true이면 즉시 팝업 표시)
	var levels: Array = result.get("levels", [])
	for lv_data in levels:
		var lv: int = int(lv_data.get("level", 0))
		if lv >= 2:
			# 같은 용사가 이미 큐에 동일 레벨로 있으면 스킵
			var already_queued: bool = false
			for entry in _skill_select_queue:
				if entry.get("hero_id", "") == hero.id and entry.get("level", 0) == lv:
					already_queued = true
					break
			if already_queued:
				continue
			_skill_select_queue.append({
				"hero_id": hero.id,
				"hero_name": hero.hero_name,
				"level": lv,
			})
	# 즉시 표시 모드일 때만 팝업 열기 (전투 중 레벨업)
	if show_immediately and not _skill_select_queue.is_empty():
		if _skill_select_popup == null or not is_instance_valid(_skill_select_popup):
			_show_next_skill_select()


func _show_next_skill_select() -> void:
	## 큐에서 다음 용사의 스킬 선택 팝업 표시
	if _skill_select_queue.is_empty():
		if _skill_select_in_victory:
			_skill_select_in_victory = false
			_play_victory_text_then_close()
		return

	var entry: Dictionary = _skill_select_queue.pop_front()
	var hero_id: String = entry.get("hero_id", "")
	var hero_name: String = entry.get("hero_name", "")

	# 클래스 스킬에서 후보 생성 (기본 공격 제외, 배운 스킬도 포함 → 중복 선택 시 레벨업)
	var hero: Hero = _find_hero_by_id(hero_id)
	var class_skills: Array = DataManager.get_class_skills(hero.class_id) if hero else []

	var candidates: Array = []
	for sid in class_skills:
		var skill_id: String = str(sid)
		if skill_id != "basic_attack":
			candidates.append(skill_id)

	# 후보가 없으면 스킵
	if candidates.is_empty():
		_show_next_skill_select()
		return

	# 3지선다 구성: 후보가 충분하면 셔플 후 선택, 부족하면 반복하여 채움
	var choices: Array = []
	if candidates.size() >= SKILL_SELECT_CHOICE_COUNT:
		candidates.shuffle()
		choices = candidates.slice(0, SKILL_SELECT_CHOICE_COUNT)
	else:
		for i in range(SKILL_SELECT_CHOICE_COUNT):
			choices.append(candidates[i % candidates.size()])

	# 팝업 생성
	if _skill_select_popup != null and is_instance_valid(_skill_select_popup):
		_skill_select_popup.queue_free()

	# 말풍선(PartyChatterLayer) 숨기기
	_hide_party_chatter_layer(true)

	# CanvasLayer로 감싸 카메라 무관하게 화면 고정 (ChatterLayer=220보다 위)
	var layer := CanvasLayer.new()
	layer.name = "SkillSelectLayer"
	layer.layer = 300
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)

	_skill_select_popup = SKILL_SELECT_POPUP_SCENE.instantiate() as SkillSelectPopup
	_skill_select_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	_skill_select_popup.skill_selected.connect(_on_skill_selected)

	layer.add_child(_skill_select_popup)
	_skill_select_popup.open(hero_id, hero_name, choices, hero)

	# open 이후 크기가 결정되므로 deferred로 화면 중앙 배치
	_skill_select_popup.call_deferred("_center_on_screen")

	# 게임 일시정지
	get_tree().paused = true


func _on_skill_selected(hero_id: String, skill_id: String) -> void:
	## 스킬 선택 완료 콜백
	var hero: Hero = _find_hero_by_id(hero_id)
	var already_owned: bool = hero != null and hero.unlocked_skills.has(skill_id)

	if hero and not already_owned:
		hero.unlocked_skills.append(skill_id)
	elif hero and already_owned:
		hero.level_up_skill(skill_id)

	if BattleManager and BattleManager.has_method("push_hud_notice"):
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		var skill_name: String = skill_data.get("name", skill_id)
		var hero_name: String = hero.hero_name if hero else hero_id
		if already_owned:
			var new_lv: int = hero.get_skill_level(skill_id) if hero else 2
			BattleManager.push_hud_notice("%s: %s Lv.%d!" % [hero_name, skill_name, new_lv], 2.5, Color(0.6, 0.8, 1.0))
		else:
			BattleManager.push_hud_notice("%s: %s 습득!" % [hero_name, skill_name], 2.5, Color(0.4, 1.0, 0.6))

	# 팝업 + CanvasLayer 제거
	if _skill_select_popup != null and is_instance_valid(_skill_select_popup):
		var layer_node: Node = _skill_select_popup.get_parent()
		_skill_select_popup.queue_free()
		_skill_select_popup = null
		if layer_node and is_instance_valid(layer_node) and layer_node.name == "SkillSelectLayer":
			layer_node.queue_free()

	# 말풍선(PartyChatterLayer) 복원
	_hide_party_chatter_layer(false)

	# 일시정지 해제
	get_tree().paused = false

	# 다음 용사 처리 or 승리 연출
	_show_next_skill_select()


func _hide_party_chatter_layer(hide: bool) -> void:
	var chatter_layer: CanvasLayer = get_tree().root.find_child("PartyChatterLayer", true, false) as CanvasLayer
	if chatter_layer != null and is_instance_valid(chatter_layer):
		chatter_layer.visible = not hide


func _find_hero_by_id(hero_id: String) -> Hero:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for h in party:
		if h != null and h.id == hero_id:
			return h
	var bench: Array = PartyManager.get_bench_heroes() if PartyManager and PartyManager.has_method("get_bench_heroes") else []
	for h in bench:
		if h != null and h.id == hero_id:
			return h
	return null


func _finalize_victory_close() -> void:
	battle_ended.emit(battle_id, true)
	_play_close_effect()



func _play_victory_text_then_close() -> void:
	## 하단 로그 박스에 승리 메시지 표시 후 닫기
	show_battle_text(["승리했다!"])

	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(_finalize_victory_close)


func _check_trinket_loot_activation() -> void:
	## 현재 살아있는 적 수 기준으로 트링캣 전리품 배율 체크 (트링캣당 1회만)
	if GameManager == null or DataManager == null:
		return
	var alive: int = get_enemy_count()
	for tid in GameManager.obtained_trinkets:
		if _activated_trinket_ids.has(tid):
			continue
		var data: Dictionary = DataManager.get_trinket(tid)
		var min_enemies: int = int(data.get("loot_mult_min_enemies", 0))
		if min_enemies <= 0 or alive < min_enemies:
			continue
		var mv: float = float(data.get("loot_mult_value", 1.0))
		if mv <= 1.0:
			continue
		_activated_trinket_ids[tid] = true
		trinket_loot_mult *= mv
		_show_loot_mult_popup(mv)
		if BattleManager and BattleManager.has_signal("trinket_loot_activated"):
			BattleManager.trinket_loot_activated.emit(tid, mv, battle_id)


func _show_loot_mult_popup(mult: float) -> void:
	## 우측 상단에 "x2" 텍스트를 팍! 하고 표시
	var lbl := Label.new()
	lbl.text = "x%d" % int(mult)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.2))
	lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.position = Vector2(size.x - 52, 4)
	lbl.size = Vector2(48, 28)
	lbl.z_index = 200
	add_child(lbl)

	# 팍! 스케일 팝 연출
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2(2.2, 2.2)
	lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.1)


func _play_close_effect() -> void:
	## 전투창 닫힘 이펙트
	# top_level 버튼 숨기기
	if run_button:
		run_button.visible = false
	if block_entry_button and is_instance_valid(block_entry_button):
		block_entry_button.visible = false
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.3).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


func _start_loot_animations() -> void:
	# 먼저 모든 아이템을 즉시 처리 (자동 장착 또는 인벤토리 추가)
	for item_id in drop_items:
		if not InventoryManager.try_auto_equip(item_id):
			InventoryManager.add_item(item_id)

	# 그 후 애니메이션과 로그만 표시
	for item_id in drop_items:
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


func _end_battle_defeat() -> void:
	if current_state == BattleState.DEFEAT:
		return
	waiting_reward_claim = false
	_clear_reward_claim_button()
	current_state = BattleState.DEFEAT
	set_process(false)

	if run_button:
		run_button.visible = false
	if block_entry_button and is_instance_valid(block_entry_button):
		block_entry_button.visible = false

	# 패배 사운드 재생
	if SoundManager != null:
		SoundManager.play_defeat()

	_apply_partial_rewards(0.3, "전멸! 보상 30%%")

	battle_ended.emit(battle_id, false)
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
	total_exp += _exp
	total_gold += gold
	drop_items.append_array(items)
#endregion


func _grant_exp_rewards() -> void:
	## 파티원 EXP 지급 (복사 지급), 벤치 용사은 50%
	if total_exp <= 0:
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		if hero == null:
			continue
		var old_level: int = hero.level
		var result: Dictionary = hero.gain_exp(total_exp)
		_show_rebel_up_popups(hero, result)
		_check_skill_select_on_levelup(hero, old_level, result, false)

	var bench: Array = PartyManager.get_bench_heroes() if PartyManager and PartyManager.has_method("get_bench_heroes") else []
	var bench_exp: int = int(total_exp * Hero.BENCH_EXP_RATIO)
	if bench_exp <= 0:
		return

	for hero in bench:
		if hero == null:
			continue
		var old_level: int = hero.level
		var result: Dictionary = hero.gain_exp(bench_exp)
		_show_rebel_up_popups(hero, result)
		_check_skill_select_on_levelup(hero, old_level, result, false)


func _show_rebel_up_popups(hero: Hero, gain_result: Dictionary) -> void:
	var levels: Array = gain_result.get("levels", [])
	if levels.is_empty():
		return

	for lv_data in levels:
		var lv: int = int(lv_data.get("level", hero.level))
		if SoundManager:
			SoundManager.play_level_up()
		if BattleManager and BattleManager.has_method("push_hud_notice"):
			BattleManager.push_hud_notice("%s Lv.%d Rebel Up!" % [hero.hero_name, lv], 2.0, Color(0.6, 0.95, 1.0))


func _show_rebel_up_popup(text: String) -> void:
	## 0.5초 비차단 레벨업 연출
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.85, 1.0, 1.0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	panel.add_child(label)

	add_child(panel)
	panel.set_as_top_level(true)

	await get_tree().process_frame
	if not is_instance_valid(panel):
		return

	var area_center: Vector2 = battle_area.global_position + battle_area.size / 2
	panel.global_position = area_center + Vector2(0, -36) - panel.size / 2
	panel.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	tween.tween_property(panel, "global_position:y", panel.global_position.y - 10.0, 0.5)
	tween.chain().tween_property(panel, "modulate:a", 0.0, 0.18)
	tween.tween_callback(panel.queue_free)


#region 특성 시스템
func _collect_party_traits() -> void:
	## 파티원들의 특성 수집
	active_traits.clear()
	for hero in _get_alive_heroes_in_battle():
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
	_apply_partial_rewards(0.5, "도주! 보상 50%")

	call_deferred("_emit_party_updated")
	current_state = BattleState.ESCAPED
	set_process(false)
	battle_ended.emit(battle_id, false)

	await get_tree().create_timer(0.3).timeout
	queue_free()
#endregion


func _apply_partial_rewards(ratio: float, log_prefix: String) -> void:
	var r: float = clampf(ratio, 0.0, 1.0)
	var partial_gold: int = int(round(float(total_gold) * r))
	if partial_gold > 0 and GameManager:
		GameManager.add_gold(partial_gold)
		_send_log("%s: Gold +%d" % [log_prefix, partial_gold], Color.ORANGE)
	else:
		_send_log(log_prefix, Color.ORANGE)

	var partial_drops: Array = []
	for item in drop_items:
		if randf() < r:
			partial_drops.append(item)
	for item_id in partial_drops:
		if InventoryManager:
			if not InventoryManager.try_auto_equip(item_id):
				InventoryManager.add_item(item_id)

	_apply_heart_rewards(r)


func _apply_heart_rewards(ratio: float) -> void:
	if reward_hearts <= 0:
		return
	var hearts_to_apply: int = int(floor(float(reward_hearts) * clampf(ratio, 0.0, 1.0)))
	if ratio >= 1.0:
		hearts_to_apply = reward_hearts
	if hearts_to_apply <= 0:
		return

	var heal_per_heart: int = 12
	var healed_any: bool = false
	for hero in PartyManager.get_party():
		if hero == null or hero.is_dead:
			continue
		var heal_amount: int = hearts_to_apply * heal_per_heart
		if heal_amount > 0:
			var actual: int = hero.heal(heal_amount)
			healed_any = healed_any or actual > 0

	if healed_any and BattleManager and BattleManager.has_method("push_hud_notice"):
		BattleManager.push_hud_notice("♥ 회복 +%d" % (hearts_to_apply * heal_per_heart), 1.5, Color(1.0, 0.5, 0.6, 1.0))


#region 유틸리티
func _bring_to_front() -> void:
	var parent = get_parent()
	if parent:
		parent.move_child(self, -1)


func _exit_tree() -> void:
	if _global_face_chip_owner_window_id == get_instance_id():
		_global_face_chip_owner_window_id = -1
	_deactivate_persistent_face_chip()
	if BattleManager and BattleManager.has_method("release_hero_locks_for_battle"):
		BattleManager.release_hero_locks_for_battle(battle_id)
	if BattleManager and BattleManager.has_method("clear_battle_group_hover"):
		BattleManager.clear_battle_group_hover()


func _emit_party_updated() -> void:
	party_updated.emit()


func _send_log(_msg: String, _color: Color = Color.WHITE) -> void:
	if _msg.is_empty():
		return
	battle_log.emit(_msg, _color)
	_show_msg_box(_msg, _color, 0.65)


func _on_close_pressed() -> void:
	if is_event_mode:
		_finish_event_dialog({"choice_id": event_last_choice_id, "closed": true})
		return
	waiting_reward_claim = false
	_clear_reward_claim_button()
	current_state = BattleState.ENDED
	queue_free()


func _on_run_button_pressed() -> void:
	## 우측 버튼: 전투중 도주
	if current_state != BattleState.RUNNING:
		return
	_run_with_partial_rewards()
#endregion


#region Mother 2 스타일 배경 효과
var is_shaking: bool = false
var shake_time: float = 0.0
var shake_intensity: float = 0.0
var shake_original_pos: Vector2 = Vector2.ZERO

# === 도주 버튼 (전투 화면 우측 하단 오버레이) ===

func _create_run_button_overlay() -> void:
	if run_button != null and is_instance_valid(run_button):
		return
	if battle_area == null:
		return

	run_button = Button.new()
	run_button.text = "도주"
	run_button.custom_minimum_size = Vector2(52, 20)
	run_button.add_theme_font_size_override("font_size", 9)
	run_button.mouse_filter = Control.MOUSE_FILTER_STOP
	run_button.focus_mode = Control.FOCUS_NONE
	run_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run_button.top_level = true
	run_button.z_index = 10
	_apply_run_button_style()

	run_button.pressed.connect(_on_run_button_pressed)
	run_button.mouse_entered.connect(_on_run_button_mouse_entered)
	run_button.mouse_exited.connect(_on_run_button_mouse_exited)
	add_child(run_button)


func _update_run_button_position() -> void:
	if run_button == null or not is_instance_valid(run_button):
		return
	if battle_area == null:
		return
	var area_global: Vector2 = battle_area.global_position
	var area_size: Vector2 = battle_area.size
	var bx: float = area_global.x + area_size.x - run_button.size.x - 6.0
	var by: float = area_global.y + area_size.y - run_button.size.y - 6.0
	run_button.global_position = Vector2(bx, by)


# === 전투 로그 시스템 (고전 RPG 스타일 + 타이핑 연출) ===

func _setup_battle_log() -> void:
	if battle_log_label == null:
		battle_log_label = get_node_or_null("MainVBox/BattleLogPanel/BattleLogLabel")
	if battle_log_label != null:
		battle_log_label.add_theme_font_size_override("normal_font_size", BATTLE_LOG_FONT_SIZE)
		battle_log_label.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0, 1.0))
		battle_log_label.text = ""
	_tw_done = true


func start_typewriter(lines: Array, callback: Callable = Callable(), callback_after_line: int = -1) -> void:
	## 타이핑 연출 시작: lines를 한 글자씩 순차 표시
	_tw_lines.clear()
	for l in lines:
		_tw_lines.append(str(l))
	_tw_current_line = 0
	_tw_char_index = 0
	_tw_timer = 0.0
	_tw_done = false
	_tw_displayed.clear()
	_tw_callback = callback
	_tw_callback_after_line = callback_after_line
	_tw_callback_fired = false
	_tw_pause_timer = 0.0
	if battle_log_label != null:
		battle_log_label.text = ""


func _update_typewriter(delta: float) -> void:
	## _process에서 호출: 타이핑 애니메이션 진행
	if _tw_done:
		return
	if battle_log_label == null:
		_tw_done = true
		return

	# 줄 사이/콜백 대기 중
	if _tw_pause_timer > 0.0:
		_tw_pause_timer -= delta
		return

	# 모든 줄 완료 체크
	if _tw_current_line >= _tw_lines.size():
		_tw_done = true
		return

	# 콜백 실행 (해당 줄 타이핑 완료 후, 다음 줄 시작 전)
	if _tw_callback_after_line >= 0 and _tw_current_line == _tw_callback_after_line + 1 and not _tw_callback_fired:
		_tw_callback_fired = true
		if _tw_callback.is_valid():
			_tw_callback.call()
		_tw_pause_timer = TYPEWRITER_LINE_PAUSE
		return

	_tw_timer += delta
	if _tw_timer < TYPEWRITER_CHAR_DELAY:
		return
	_tw_timer -= TYPEWRITER_CHAR_DELAY

	var current_text: String = _tw_lines[_tw_current_line]
	_tw_char_index += 1

	# 현재 줄 표시 업데이트
	var partial: String = current_text.substr(0, _tw_char_index)
	var display_lines: Array[String] = _tw_displayed.duplicate()
	display_lines.append(partial)
	battle_log_label.text = "\n".join(display_lines)

	# 현재 줄 완료
	if _tw_char_index >= current_text.length():
		_tw_displayed.append(current_text)
		_tw_current_line += 1
		_tw_char_index = 0
		_tw_pause_timer = TYPEWRITER_LINE_PAUSE


func is_typewriter_done() -> bool:
	return _tw_done


func show_battle_text(lines: Array) -> void:
	## 즉시 표시 (타이핑 없이)
	if battle_log_label == null:
		battle_log_label = get_node_or_null("MainVBox/BattleLogPanel/BattleLogLabel")
	if battle_log_label == null:
		return
	battle_log_label.text = "\n".join(lines)
	_tw_done = true


func clear_battle_log() -> void:
	if battle_log_label != null:
		battle_log_label.text = ""
	_tw_done = true
	_tw_lines.clear()
	_tw_displayed.clear()


func show_skill_action_message(text: String) -> void:
	show_battle_text([text])


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
	## 크리티컬 공격 시 진동 효과 (아군 공격용 — 현재 비활성)
	pass


func play_skill_shake() -> void:
	## 강타 등 스킬 사용 시 진동 효과 (아군 공격용 — 현재 비활성)
	pass


func play_enemy_hit_shake(damage: int) -> void:
	## 적에게 맞았을 때 전투창 흔들림 — 데미지에 비례
	if not is_shaking:
		shake_original_pos = position
	is_shaking = true
	# 데미지 구간별 흔들림 강도
	if damage >= 80:
		shake_time = 0.40
		shake_intensity = 24.0
	elif damage >= 40:
		shake_time = 0.34
		shake_intensity = 18.0
	elif damage >= 15:
		shake_time = 0.28
		shake_intensity = 12.0
	else:
		shake_time = 0.22
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



#region 마우스 인터랙션
func _on_gui_input(event: InputEvent) -> void:
	## 마우스 드래그로 전투창 이동 + 머지
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_battle_is_dragging = true
				_battle_drag_offset = event.global_position - global_position
				_bring_to_front()
			else:
				if _battle_is_dragging and _merge_target != null:
					_execute_merge(_merge_target)
					return
				_battle_is_dragging = false
				_clear_merge_highlight()
	elif event is InputEventMouseMotion and _battle_is_dragging:
		global_position = event.global_position - _battle_drag_offset
		# 화면 밖으로 나가지 않도록 제한
		var vp_size := get_viewport().get_visible_rect().size
		global_position.x = clampf(global_position.x, -size.x + 40, vp_size.x - 40)
		global_position.y = clampf(global_position.y, 0, vp_size.y - 30)
		# 정지 중이면 머지 타겟 감지
		if is_battle_paused:
			_update_merge_target()


func _release_reward_pause_locks() -> void:
	if get_tree() == null:
		return
	for node in get_tree().get_nodes_in_group("reward_windows"):
		if node != null and is_instance_valid(node) and node.has_method("release_pause_lock"):
			node.call("release_pause_lock")


func _setup_enemy_tooltip() -> void:
	## 적 호버 시 표시할 툴팁 패널 생성
	var tooltip_node: Node = TOOLTIP_SCENE.instantiate()
	_enemy_tooltip = tooltip_node as PanelContainer
	if _enemy_tooltip == null:
		return
	_enemy_tooltip.name = "EnemyTooltip"
	_enemy_tooltip.visible = false
	_enemy_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_tooltip.z_index = 200
	add_child(_enemy_tooltip)
	_enemy_tooltip.set_as_top_level(true)


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
	_enemy_tooltip_hide_token += 1
	_hovered_enemy = enemy
	enemy.set_hover_highlight(true)
	_show_enemy_tooltip(enemy)


func _on_enemy_mouse_exited(enemy: BattleEnemy) -> void:
	if _hovered_enemy == enemy:
		if _is_pointer_inside_enemy(enemy):
			return
		_hovered_enemy = null
		enemy.set_hover_highlight(false)
		var token: int = _enemy_tooltip_hide_token + 1
		_enemy_tooltip_hide_token = token
		_defer_hide_enemy_tooltip(token)


func _defer_hide_enemy_tooltip(token: int) -> void:
	if get_tree() == null:
		_hide_enemy_tooltip()
		return
	await get_tree().create_timer(0.06).timeout
	if token != _enemy_tooltip_hide_token:
		return
	if _hovered_enemy != null:
		return
	_hide_enemy_tooltip()


func _is_pointer_inside_enemy(enemy: BattleEnemy) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var rect: Rect2 = Rect2(enemy.global_position, enemy.size)
	return rect.has_point(get_global_mouse_position())


func _show_enemy_tooltip(enemy: BattleEnemy) -> void:
	## 적 정보 툴팁 표시
	if _enemy_tooltip == null:
		return

	var name_color: Color = Color.WHITE
	if enemy.is_elite_version:
		name_color = Color.PURPLE
	elif enemy.enemy_type == "boss":
		name_color = Color.ORANGE

	var rows: Array = [
		{"text": enemy.enemy_name, "color": name_color, "size": 10},
		{"text": "HP: %d/%d" % [enemy.current_hp, enemy.max_hp], "color": Color(0.9, 0.35, 0.35, 1.0), "size": 9},
		{"text": "ATK:%d DEF:%d SPD:%d" % [enemy.get_atk(), enemy.get_p_def(), enemy.get_dex()], "color": Color(0.7, 0.7, 0.8, 1.0), "size": 8},
		{"text": "타입: %s" % enemy.damage_type, "color": Color(0.6, 0.6, 0.7, 1.0), "size": 8},
	]
	var enemy_icon: Texture2D = null
	var enemy_sprite: AnimatedSprite2D = enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if enemy_sprite != null and enemy_sprite.sprite_frames != null:
		var anim: StringName = enemy_sprite.animation
		var frame_idx: int = enemy_sprite.frame
		if enemy_sprite.sprite_frames.has_animation(anim):
			enemy_icon = enemy_sprite.sprite_frames.get_frame_texture(anim, frame_idx)
	var anchor_pos: Vector2 = enemy.global_position + Vector2(enemy.size.x * 0.5, 0.0)
	_show_shared_tooltip("enemy", rows, anchor_pos, enemy_icon)


func _hide_enemy_tooltip() -> void:
	if _enemy_tooltip:
		_enemy_tooltip.visible = false
	_tooltip_owner = ""


func _show_shared_tooltip(owner: String, rows: Array, anchor_pos: Vector2, icon_tex: Texture2D = null) -> void:
	if _enemy_tooltip == null:
		return
	_enemy_tooltip_hide_token += 1
	_tooltip_owner = owner
	if _enemy_tooltip.has_method("set_rows"):
		_enemy_tooltip.call("set_rows", rows, icon_tex)
	_enemy_tooltip.visible = true
	var clamp_rect: Rect2 = get_viewport().get_visible_rect()
	if _enemy_tooltip.has_method("place_near"):
		_enemy_tooltip.call("place_near", anchor_pos, clamp_rect, true, 4.0)
		return
	await get_tree().process_frame
	_enemy_tooltip.global_position = anchor_pos + Vector2(-_enemy_tooltip.size.x * 0.5, -_enemy_tooltip.size.y - 4.0)


func _on_face_chip_mouse_entered(hero_id: String) -> void:
	if _face_chip_dragging:
		return
	var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
	if panel == null or not is_instance_valid(panel):
		return
	var hero: Hero = PartyManager.get_hero_by_id(hero_id) if PartyManager else null
	if hero == null:
		return
	var rows: Array = [
		{"text": hero.hero_name, "color": Color(0.95, 0.96, 1.0, 1.0), "size": 10},
		{"text": "HP: %d/%d" % [hero.current_hp, hero.get_max_hp()], "color": Color(0.75, 1.0, 0.75, 1.0), "size": 9},
		{"text": "%s" % hero.hero_class_name, "color": Color(0.72, 0.76, 0.9, 1.0), "size": 8},
		{"text": "ATK:%d DEF:%d SPD:%d" % [hero.get_atk(), hero.get_p_def(), hero.get_dex()], "color": Color(0.7, 0.7, 0.8, 1.0), "size": 8},
	]
	var icon_tex: Texture2D = SpriteManager.get_hero_face_sprite(hero_id) if SpriteManager else null
	var anchor_pos: Vector2 = panel.global_position + panel.size * 0.5
	_show_shared_tooltip("token_%s" % hero_id, rows, anchor_pos, icon_tex)


func _on_face_chip_mouse_exited(hero_id: String) -> void:
	if _tooltip_owner != "token_%s" % hero_id:
		return
	var panel: PanelContainer = _face_chip_panels.get(hero_id, null) as PanelContainer
	if panel != null and is_instance_valid(panel):
		var rect: Rect2 = Rect2(panel.global_position, panel.size)
		if rect.has_point(get_global_mouse_position()):
			return
	_hide_enemy_tooltip()


func _on_run_button_mouse_entered() -> void:
	if run_button == null or not is_instance_valid(run_button):
		return
	var rows: Array = []
	if run_button.text.find("보상") >= 0:
		rows = [
			{"text": "보상받기", "color": Color(0.85, 1.0, 0.85, 1.0), "size": 10},
			{"text": "적 전멸 보상 100% 획득", "color": Color(0.78, 0.9, 0.78, 1.0), "size": 8},
		]
	else:
		rows = [
			{"text": "도주", "color": Color(1.0, 0.92, 0.62, 1.0), "size": 10},
			{"text": "적이 살아있을 때 보상 50%만 획득", "color": Color(0.88, 0.8, 0.56, 1.0), "size": 8},
		]
	var anchor_pos: Vector2 = run_button.global_position + run_button.size * 0.5
	_show_shared_tooltip("run_button", rows, anchor_pos, null)


func _on_run_button_mouse_exited() -> void:
	if _tooltip_owner != "run_button":
		return
	var rect: Rect2 = Rect2(run_button.global_position, run_button.size)
	if rect.has_point(get_global_mouse_position()):
		return
	_hide_enemy_tooltip()


func _setup_hover_highlight() -> void:
	## 전투창 호버 시 노란 테두리 스타일 준비
	_normal_panel_style = StyleBoxFlat.new()
	_normal_panel_style.bg_color = Color(0, 0, 0, 1)
	_normal_panel_style.border_width_left = 2
	_normal_panel_style.border_width_top = 2
	_normal_panel_style.border_width_right = 2
	_normal_panel_style.border_width_bottom = 2
	_normal_panel_style.border_color = Color(1, 1, 1, 1)

	_hover_panel_style = StyleBoxFlat.new()
	_hover_panel_style.bg_color = Color(0, 0, 0, 1)
	_hover_panel_style.border_width_left = 2
	_hover_panel_style.border_width_top = 2
	_hover_panel_style.border_width_right = 2
	_hover_panel_style.border_width_bottom = 2
	_hover_panel_style.border_color = Color(1.0, 0.9, 0.2, 1.0)

	mouse_entered.connect(_on_window_mouse_entered)
	mouse_exited.connect(_on_window_mouse_exited)


func _on_window_mouse_entered() -> void:
	_is_window_hovered = true
	if is_event_mode:
		_update_hover_highlight()
		_update_pause_visual(0.0)
		return
	_pause_hover_focus = true
	_update_hover_highlight()
	_update_pause_visual(0.0)


func _is_pointer_inside_window() -> bool:
	var rect: Rect2 = Rect2(global_position, size)
	return rect.has_point(get_global_mouse_position())


func _on_window_mouse_exited() -> void:
	# 자식 Control(에너미/토큰)으로 마우스가 이동할 때도 exited가 들어올 수 있다.
	# 포인터가 여전히 전투창 영역 안이면 hover를 유지한다.
	if _is_pointer_inside_window():
		return
	_is_window_hovered = false
	if is_event_mode:
		_update_hover_highlight()
		_update_pause_visual(0.0)
		return
	_pause_hover_focus = false
	_update_hover_highlight()
	_update_pause_visual(0.0)


func _update_hover_highlight() -> void:
	if _normal_panel_style == null:
		return
	# 머지 하이라이트가 활성이면 무시 (머지가 우선)
	if _merge_target != null:
		return
	var tree_paused: bool = false
	if get_tree():
		tree_paused = get_tree().paused
	var show_hover: bool = false
	if is_event_mode:
		show_hover = (tree_paused or _event_step_mode) and _is_window_hovered
	elif is_battle_paused:
		show_hover = _pause_hover_focus
	if show_hover:
		add_theme_stylebox_override("panel", _hover_panel_style)
	else:
		add_theme_stylebox_override("panel", _normal_panel_style)


func set_merge_highlight(show: bool) -> void:
	## 외부에서 호출: 머지 대상으로 노란 테두리 표시/해제
	if _hover_panel_style == null:
		return
	if show:
		add_theme_stylebox_override("panel", _hover_panel_style)
	else:
		add_theme_stylebox_override("panel", _normal_panel_style)


func _update_merge_target() -> void:
	## 드래그 중: 겹치는 다른 전투창 찾아서 하이라이트
	var new_target: BattleWindow = _find_merge_candidate()

	if new_target == _merge_target:
		return

	# 이전 타겟 하이라이트 해제
	if _merge_target != null and is_instance_valid(_merge_target):
		_merge_target.set_merge_highlight(false)

	_merge_target = new_target

	# 새 타겟 하이라이트
	if _merge_target != null:
		_merge_target.set_merge_highlight(true)
		add_theme_stylebox_override("panel", _hover_panel_style)
	else:
		add_theme_stylebox_override("panel", _normal_panel_style)


func _find_merge_candidate() -> BattleWindow:
	## 현재 드래그 위치에서 겹치는 다른 전투창 찾기
	var my_rect := Rect2(global_position, size)
	var parent_node := get_parent()
	if parent_node == null:
		return null

	for child in parent_node.get_children():
		if child == self:
			continue
		if child is BattleWindow and is_instance_valid(child):
			var other: BattleWindow = child as BattleWindow
			# 보스전은 머지 불가
			if other.is_boss_battle:
				continue
			if other.is_enemy_entry_blocked():
				continue
			if other.current_state != BattleState.RUNNING and other.current_state != BattleState.STARTING:
				continue
			var other_rect := Rect2(other.global_position, other.size)
			if my_rect.intersects(other_rect):
				var overlap := my_rect.intersection(other_rect)
				# 15% 이상 겹쳐야 머지 후보
				if overlap.get_area() > my_rect.get_area() * 0.15:
					return other
	return null


func _clear_merge_highlight() -> void:
	## 머지 하이라이트 전부 해제
	if _merge_target != null and is_instance_valid(_merge_target):
		_merge_target.set_merge_highlight(false)
	_merge_target = null
	_update_hover_highlight()


func _execute_merge(target: BattleWindow) -> void:
	## 드래그한 전투창의 적들을 타겟 전투창으로 이전
	if target == null or not is_instance_valid(target):
		_battle_is_dragging = false
		_clear_merge_highlight()
		return

	# 보스전은 머지 불가
	if is_boss_battle or target.is_boss_battle:
		_battle_is_dragging = false
		_clear_merge_highlight()
		return
	if target.is_enemy_entry_blocked():
		_battle_is_dragging = false
		_clear_merge_highlight()
		return

	# 살아있는 적 이전
	for enemy in enemies:
		if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
			enemy.get_parent().remove_child(enemy)
			target.enemy_container.add_child(enemy)
			target.enemies.append(enemy)
			target._connect_enemy_hover(enemy)

	# 보상 이전
	target.total_gold += total_gold
	target.drop_items.append_array(drop_items)

	# 타겟 전투 상태/UI 갱신
	target.pending_victory = false
	target.pending_victory_ready_ms = 0
	target._wave_clear_processed = false
	target._update_buttons_for_enemies()
	target._refresh_enemy_layout()
	_refresh_enemy_layout()

	# BattleManager에서 제거
	if BattleManager and BattleManager.has_method("reassign_hero_locks"):
		BattleManager.reassign_hero_locks(battle_id, target.battle_id)
	BattleManager.active_battles.erase(battle_id)

	# 하이라이트 정리
	target.set_merge_highlight(false)
	_merge_target = null
	_battle_is_dragging = false

	# 머지 효과음
	if SoundManager:
		SoundManager.play_encounter()

	# 닫기 효과
	_play_close_effect()
#endregion
