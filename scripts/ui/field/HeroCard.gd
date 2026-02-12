extends Control
class_name HeroCard
## 좌측 파티 초상화 유닛
## 페이스칩(48x48) + HP (롱, 10단위 눈금) + Will (5칸) + EXP (숏) + 레벨

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"
const FACE_SIZE := 48
const BAR_GAP := 2  # 페이스칩 ↔ 바 영역 간격

# === 바 높이 ===
const HP_BAR_HEIGHT := 9
const WILL_BAR_HEIGHT := 7
const EXP_BAR_HEIGHT := 4
const BAR_SPACING := 2  # 바 간 간격

# === 롱 바 (HP) ===
const LONG_BAR_MAX_WIDTH := 120  # HP 최대 너비
const MIN_BAR_RATIO := 0.3  # 최소 비율

# === Will 바 ===
const WILL_BAR_WIDTH := 75  # Will 바 전체 너비
const WILL_SLOTS := 5       # Will 칸 수

# === 숏 바 (EXP) ===
const SHORT_BAR_WIDTH := 55  # EXP 고정 너비

# === 기준값 (가변 길이) ===
var hp_reference: int = 100

# === 색상 ===
const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID  := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW  := Color(0.92, 0.22, 0.22)
const HP_GHOST_COLOR := Color(1.0, 0.35, 0.35, 0.8)
const WILL_BAR_COLOR := Color(0.95, 0.75, 0.2)
const WILL_BAR_FULL_COLOR := Color(1.0, 0.9, 0.3)
const EXP_BAR_COLOR := Color(0.3, 0.85, 0.75)
const BAR_BG_COLOR := Color(0.06, 0.06, 0.09, 0.9)
const TICK_COLOR := Color(0.0, 0.0, 0.0, 0.3)
const WILL_DIVIDER_COLOR := Color(0.15, 0.15, 0.2, 0.9)

const DEATH_OVERLAY_COLOR := Color(0.1, 0.1, 0.1, 0.7)
const PLACEHOLDER_COLOR := Color(0.15, 0.12, 0.2)

# === 타이밍 ===
const HP_TWEEN_DURATION := 0.35
const MP_TWEEN_DURATION := 0.3
const GHOST_DELAY := 0.4
const GHOST_DURATION := 0.5
const SHAKE_DURATION := 0.2
const SHAKE_STRENGTH := 3.0

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)

var hero_index: int = -1
var hero_id: String = ""

# 래퍼 (셰이크 대상)
var content: Control

# 페이스칩 노드
var face_container: Control
var placeholder: ColorRect
var face_chip: TextureRect
var death_overlay: ColorRect
var skull_label: Label

# 바 노드
var bars_container: Control
# HP 바
var hp_bar_bg: ColorRect
var hp_ghost: ColorRect
var hp_bar: ColorRect
var hp_tick_overlay: Control
# Will 바
var will_bar_bg: ColorRect
var will_bar: ColorRect
var will_divider_overlay: Control
# EXP 바
var exp_bar_bg: ColorRect
var exp_bar: ColorRect
# 레벨 라벨
var level_label: Label

# 바 길이 캐시
var _hp_bar_width: float = LONG_BAR_MAX_WIDTH
var _cached_max_hp: int = 0

# 상태 추적
var _prev_hp: int = -1

# 트윈
var _hp_tween: Tween
var _ghost_tween: Tween
var _shake_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(FACE_SIZE + BAR_GAP + LONG_BAR_MAX_WIDTH, FACE_SIZE)
	_build_ui()


func _build_ui() -> void:
	# --- 콘텐츠 래퍼 (셰이크 대상) ---
	content = Control.new()
	content.position = Vector2.ZERO
	content.size = Vector2(FACE_SIZE + BAR_GAP + LONG_BAR_MAX_WIDTH, FACE_SIZE)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(content)

	# --- 페이스칩 영역 ---
	face_container = Control.new()
	face_container.position = Vector2.ZERO
	face_container.size = Vector2(FACE_SIZE, FACE_SIZE)
	face_container.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	face_container.mouse_filter = MOUSE_FILTER_STOP
	face_container.gui_input.connect(_on_gui_input)
	content.add_child(face_container)

	placeholder = ColorRect.new()
	placeholder.size = Vector2(FACE_SIZE, FACE_SIZE)
	placeholder.color = PLACEHOLDER_COLOR
	placeholder.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(placeholder)

	face_chip = TextureRect.new()
	face_chip.size = Vector2(FACE_SIZE, FACE_SIZE)
	face_chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_chip.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(face_chip)

	death_overlay = ColorRect.new()
	death_overlay.size = Vector2(FACE_SIZE, FACE_SIZE)
	death_overlay.color = DEATH_OVERLAY_COLOR
	death_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	face_container.add_child(death_overlay)

	skull_label = Label.new()
	skull_label.text = "☠"
	skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skull_label.size = Vector2(FACE_SIZE, FACE_SIZE)
	skull_label.add_theme_font_size_override("font_size", 22)
	skull_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	skull_label.mouse_filter = MOUSE_FILTER_IGNORE
	death_overlay.add_child(skull_label)

	# --- 바 영역 ---
	bars_container = Control.new()
	bars_container.position = Vector2(FACE_SIZE + BAR_GAP, 0)
	bars_container.size = Vector2(LONG_BAR_MAX_WIDTH, FACE_SIZE)
	bars_container.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(bars_container)

	# 수직 중앙 정렬 계산
	var total_bar_height: float = HP_BAR_HEIGHT + BAR_SPACING + WILL_BAR_HEIGHT + BAR_SPACING + EXP_BAR_HEIGHT
	var start_y: float = floorf((FACE_SIZE - total_bar_height) / 2.0)

	# === HP 바 (롱) ===
	var hp_y: float = start_y
	hp_bar_bg = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(hp_bar_bg)
	hp_ghost = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), HP_GHOST_COLOR)
	bars_container.add_child(hp_ghost)
	hp_bar = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), HP_COLOR_HIGH)
	bars_container.add_child(hp_bar)
	hp_tick_overlay = _create_tick_overlay(Vector2(0, hp_y), HP_BAR_HEIGHT)
	bars_container.add_child(hp_tick_overlay)

	# === Will 바 (5칸) + 레벨 ===
	var will_y: float = hp_y + HP_BAR_HEIGHT + BAR_SPACING
	will_bar_bg = _make_rect(Vector2(0, will_y), Vector2(WILL_BAR_WIDTH, WILL_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(will_bar_bg)
	will_bar = _make_rect(Vector2(0, will_y), Vector2(0, WILL_BAR_HEIGHT), WILL_BAR_COLOR)
	bars_container.add_child(will_bar)
	will_divider_overlay = _create_will_divider_overlay(Vector2(0, will_y), WILL_BAR_HEIGHT)
	bars_container.add_child(will_divider_overlay)

	# 레벨 라벨 (Will 바 우측)
	level_label = Label.new()
	level_label.position = Vector2(WILL_BAR_WIDTH + 3, will_y - 2)
	level_label.text = "Lv.1"
	level_label.add_theme_font_size_override("font_size", 9)
	level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	level_label.mouse_filter = MOUSE_FILTER_IGNORE
	bars_container.add_child(level_label)

	# === EXP 바 (숏) ===
	var exp_y: float = will_y + WILL_BAR_HEIGHT + BAR_SPACING
	exp_bar_bg = _make_rect(Vector2(0, exp_y), Vector2(SHORT_BAR_WIDTH, EXP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(exp_bar_bg)
	exp_bar = _make_rect(Vector2(0, exp_y), Vector2(0, EXP_BAR_HEIGHT), EXP_BAR_COLOR)
	bars_container.add_child(exp_bar)


func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


#region 눈금 오버레이
class TickOverlay extends Control:
	## HP/MP 바 위에 10단위 눈금 표시
	var max_value: int = 0
	var bar_height: float = 0.0

	func setup(p_max: int, bar_width: float, p_height: float) -> void:
		max_value = p_max
		bar_height = p_height
		size = Vector2(bar_width, p_height)
		queue_redraw()

	func _draw() -> void:
		if max_value <= 10:
			return
		var tick_val: int = 10
		while tick_val < max_value:
			var x: float = (float(tick_val) / float(max_value)) * size.x
			draw_line(Vector2(x, 0), Vector2(x, bar_height), Color(0.0, 0.0, 0.0, 0.3), 1.0)
			tick_val += 10


func _create_tick_overlay(pos: Vector2, height: float) -> Control:
	var overlay := TickOverlay.new()
	overlay.position = pos
	overlay.size = Vector2(LONG_BAR_MAX_WIDTH, height)
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	return overlay


class WillDividerOverlay extends Control:
	## Will 바 위에 5칸 구분선 표시
	var bar_height: float = 0.0
	var slot_count: int = 5

	func setup(p_width: float, p_height: float, p_slots: int = 5) -> void:
		bar_height = p_height
		slot_count = p_slots
		size = Vector2(p_width, p_height)
		queue_redraw()

	func _draw() -> void:
		if slot_count <= 1:
			return
		var slot_width: float = size.x / float(slot_count)
		for i in range(1, slot_count):
			var x: float = slot_width * float(i)
			draw_line(Vector2(x, 0), Vector2(x, bar_height), Color(0.15, 0.15, 0.2, 0.9), 1.0)


func _create_will_divider_overlay(pos: Vector2, height: float) -> Control:
	var overlay := WillDividerOverlay.new()
	overlay.position = pos
	overlay.size = Vector2(WILL_BAR_WIDTH, height)
	overlay.mouse_filter = MOUSE_FILTER_IGNORE
	overlay.setup(WILL_BAR_WIDTH, height, WILL_SLOTS)
	return overlay
#endregion


#region 초기화
func init(p_hero_index: int) -> void:
	hero_index = p_hero_index
#endregion


#region 데이터 갱신
func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	hero_id = hero.id
	_load_face_chip(hero)
	_recalc_bar_widths(hero.get_max_hp())
	update_hp(hero.current_hp, hero.get_max_hp())
	update_will(hero.get_will_ratio())
	update_exp(hero.get_exp_ratio())
	update_level(hero.level)
	set_dead(hero.is_dead)
#endregion


#region 바 길이 가변 시스템 (비율 기반 통일)
func _recalc_bar_widths(max_hp: int) -> void:
	_hp_bar_width = _calc_bar_length(max_hp, hp_reference, LONG_BAR_MAX_WIDTH)

	# 배경 바 크기 적용
	if hp_bar_bg:
		hp_bar_bg.size.x = _hp_bar_width

	# 눈금 갱신 (max_value가 변경되었을 때만)
	if max_hp != _cached_max_hp:
		_cached_max_hp = max_hp
		if hp_tick_overlay and hp_tick_overlay is TickOverlay:
			(hp_tick_overlay as TickOverlay).setup(max_hp, _hp_bar_width, HP_BAR_HEIGHT)

	# 카드 최소 너비
	custom_minimum_size.x = FACE_SIZE + BAR_GAP + maxf(_hp_bar_width, WILL_BAR_WIDTH)


func _calc_bar_length(max_value: int, reference: int, max_width: float) -> float:
	var ratio: float = clampf(float(max_value) / float(reference), MIN_BAR_RATIO, 1.0)
	return ratio * max_width
#endregion


#region 페이스칩
func _load_face_chip(hero: Hero) -> void:
	var face_path := ""
	if not hero.portrait.is_empty():
		face_path = FACE_CHIP_PATH % hero.portrait
	elif not hero.field_sprite.is_empty():
		face_path = FACE_CHIP_PATH % hero.field_sprite
	if not face_path.is_empty() and ResourceLoader.exists(face_path):
		set_portrait(load(face_path))
	else:
		set_portrait(null)


func set_portrait(tex: Texture2D) -> void:
	if face_chip:
		face_chip.texture = tex
	if placeholder:
		placeholder.visible = (tex == null)
#endregion


#region HP 바 (Tween + 잔상)
func update_hp(current: int, max_hp: int) -> void:
	if hp_bar == null:
		return
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0
	var target_w: float = _hp_bar_width * ratio

	# HP 색상 자동 전환
	if ratio > 0.6:
		hp_bar.color = HP_COLOR_HIGH
	elif ratio > 0.3:
		hp_bar.color = HP_COLOR_MID
	else:
		hp_bar.color = HP_COLOR_LOW

	# 첫 호출 (초기화 — 애니메이션 없음)
	if _prev_hp < 0:
		hp_bar.size.x = target_w
		hp_ghost.size.x = target_w
		_prev_hp = current
		return

	# HP 감소 → 바 즉시 줄고, 잔상이 지연 후 따라옴
	if current < _prev_hp:
		hp_bar.size.x = target_w
		_kill_tween(_ghost_tween)
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(GHOST_DELAY)
		_ghost_tween.tween_property(hp_ghost, "size:x", target_w, GHOST_DURATION) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# HP 증가 → 바 부드럽게 늘어남
	elif current > _prev_hp:
		_kill_tween(_ghost_tween)
		hp_ghost.size.x = target_w
		_kill_tween(_hp_tween)
		_hp_tween = create_tween()
		_hp_tween.tween_property(hp_bar, "size:x", target_w, HP_TWEEN_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_prev_hp = current
#endregion


#region Will 바
func update_will(ratio: float) -> void:
	## Will 게이지 갱신 (0.0 ~ 1.0)
	if will_bar == null:
		return
	var clamped: float = clampf(ratio, 0.0, 1.0)
	var target_w: float = WILL_BAR_WIDTH * clamped
	will_bar.size.x = target_w
	# 가득 차면 색상 변경
	if clamped >= 1.0:
		will_bar.color = WILL_BAR_FULL_COLOR
	else:
		will_bar.color = WILL_BAR_COLOR
#endregion


#region EXP 바
func update_exp(percent: float) -> void:
	## 경험치 바 갱신 (0.0 ~ 1.0)
	if exp_bar == null:
		return
	var target_w: float = SHORT_BAR_WIDTH * clampf(percent, 0.0, 1.0)
	exp_bar.size.x = target_w
#endregion


#region 레벨 표시
func update_level(lv: int) -> void:
	if level_label:
		level_label.text = "Lv.%d" % lv
#endregion


#region 사망 처리
func set_dead(is_dead: bool) -> void:
	if death_overlay:
		death_overlay.visible = is_dead
	if bars_container:
		bars_container.visible = not is_dead
#endregion


#region 피격 셰이크
func shake() -> void:
	if content == null:
		return
	_kill_tween(_shake_tween)
	var ox: float = 0.0
	_shake_tween = create_tween()
	_shake_tween.tween_property(content, "position:x", ox - SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(content, "position:x", ox + SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(content, "position:x", ox - SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(content, "position:x", ox + SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(content, "position:x", ox, SHAKE_DURATION * 0.1)


func play_damage_anim() -> void:
	shake()


func play_attack_anim() -> void:
	if content == null:
		return
	_kill_tween(_shake_tween)
	var oy: float = 0.0
	_shake_tween = create_tween()
	_shake_tween.tween_property(content, "position:y", oy - 5.0, 0.08) \
		.set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(content, "position:y", oy, 0.12) \
		.set_ease(Tween.EASE_IN)
#endregion


#region 유틸
func _kill_tween(tw: Tween) -> void:
	if tw and tw.is_valid():
		tw.kill()
#endregion



#region 필드 힐 (클릭)
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			field_heal_requested.emit(hero_index)
#endregion


#region 호환 스텁
func expand_equips() -> void: pass
func collapse_equips() -> void: pass
func highlight_slot(_slot: String, _id: String = "") -> void: pass
func clear_slot_highlights() -> void: pass
func show_item_info(_item_id: String) -> void: pass
func show_stat_compare(_item_id: String) -> void: pass
func hide_stat_compare() -> void: pass

static func get_target_slots(item_slot: String) -> Array:
	if item_slot in ["ring", "acc"]:
		return ["ring1", "ring2"]
	return [item_slot]
#endregion
