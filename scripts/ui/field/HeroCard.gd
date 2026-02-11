extends Control
class_name HeroCard
## 좌측 파티 초상화 유닛
## 페이스칩(48x48) + 가변 길이 HP/MP 바 (잔상, Tween, 색상 전환)

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"
const FACE_SIZE := 48
const BAR_GAP := 2  # 페이스칩 ↔ 바 사이 간격

# 바 크기
const HP_BAR_HEIGHT := 7
const MP_BAR_HEIGHT := 5
const BAR_SPACING := 2  # HP바 ↔ MP바 사이 간격
const MAX_BAR_WIDTH := 120  # 바 최대 픽셀 너비
const MIN_BAR_RATIO := 0.3  # 바 최소 비율 (= 36px)

# 바 길이 기준값 (가변 시스템) — 외부에서 변경 가능
var hp_reference: int = 500
var mp_reference: int = 200

# HP 색상 (잔량 기반 자동 전환)
const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)   # 60% 이상
const HP_COLOR_MID  := Color(0.92, 0.72, 0.2)    # 30~60%
const HP_COLOR_LOW  := Color(0.92, 0.22, 0.22)   # 30% 미만
const HP_GHOST_COLOR := Color(1.0, 0.35, 0.35, 0.8)
const MP_BAR_COLOR := Color(0.25, 0.45, 0.95)
const BAR_BG_COLOR := Color(0.06, 0.06, 0.09, 0.9)

const DEATH_OVERLAY_COLOR := Color(0.1, 0.1, 0.1, 0.7)
const PLACEHOLDER_COLOR := Color(0.15, 0.12, 0.2)

# 타이밍
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
var hp_bar_bg: ColorRect
var hp_ghost: ColorRect
var hp_bar: ColorRect
var mp_bar_bg: ColorRect
var mp_bar: ColorRect

# 바 길이 캐시
var _hp_bar_width: float = MAX_BAR_WIDTH
var _mp_bar_width: float = MAX_BAR_WIDTH

# 상태 추적
var _prev_hp: int = -1
var _prev_mp: int = -1

# 트윈
var _hp_tween: Tween
var _mp_tween: Tween
var _ghost_tween: Tween
var _shake_tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(FACE_SIZE + BAR_GAP + MAX_BAR_WIDTH, FACE_SIZE)
	_build_ui()


func _build_ui() -> void:
	# --- 콘텐츠 래퍼 (셰이크 대상) ---
	content = Control.new()
	content.position = Vector2.ZERO
	content.size = Vector2(FACE_SIZE + BAR_GAP + MAX_BAR_WIDTH, FACE_SIZE)
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
	bars_container.size = Vector2(MAX_BAR_WIDTH, FACE_SIZE)
	bars_container.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(bars_container)

	# HP: bg → ghost → fill
	var hp_y: float = 0.0
	hp_bar_bg = _make_rect(Vector2(0, hp_y), Vector2(MAX_BAR_WIDTH, HP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(hp_bar_bg)
	hp_ghost = _make_rect(Vector2(0, hp_y), Vector2(MAX_BAR_WIDTH, HP_BAR_HEIGHT), HP_GHOST_COLOR)
	bars_container.add_child(hp_ghost)
	hp_bar = _make_rect(Vector2(0, hp_y), Vector2(MAX_BAR_WIDTH, HP_BAR_HEIGHT), HP_COLOR_HIGH)
	bars_container.add_child(hp_bar)

	# MP: bg → fill
	var mp_y: float = HP_BAR_HEIGHT + BAR_SPACING
	mp_bar_bg = _make_rect(Vector2(0, mp_y), Vector2(MAX_BAR_WIDTH, MP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(mp_bar_bg)
	mp_bar = _make_rect(Vector2(0, mp_y), Vector2(MAX_BAR_WIDTH, MP_BAR_HEIGHT), MP_BAR_COLOR)
	bars_container.add_child(mp_bar)


func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


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
	_recalc_bar_widths(hero.get_max_hp(), hero.get_max_mp())
	update_hp(hero.current_hp, hero.get_max_hp())
	update_mp(hero.current_mp, hero.get_max_mp())
	set_dead(hero.is_dead)
#endregion


#region 바 길이 가변 시스템
func _recalc_bar_widths(max_hp: int, max_mp: int) -> void:
	_hp_bar_width = _calc_bar_length(max_hp, hp_reference)
	_mp_bar_width = _calc_bar_length(max_mp, mp_reference)

	# 배경 바 크기
	if hp_bar_bg:
		hp_bar_bg.size.x = _hp_bar_width
	if mp_bar_bg:
		mp_bar_bg.size.x = _mp_bar_width

	# 카드 최소 너비 = 페이스칩 + 갭 + 더 긴 바
	var wider: float = maxf(_hp_bar_width, _mp_bar_width)
	custom_minimum_size.x = FACE_SIZE + BAR_GAP + wider


func _calc_bar_length(max_value: int, reference: int) -> float:
	var ratio: float = clampf(float(max_value) / float(reference), MIN_BAR_RATIO, 1.0)
	return ratio * MAX_BAR_WIDTH
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


#region MP 바 (Tween)
func update_mp(current: int, max_mp: int) -> void:
	if mp_bar == null:
		return
	var ratio: float = clampf(float(current) / float(max_mp), 0.0, 1.0) if max_mp > 0 else 1.0
	var target_w: float = _mp_bar_width * ratio

	if _prev_mp < 0:
		mp_bar.size.x = target_w
		_prev_mp = current
		return

	_kill_tween(_mp_tween)
	_mp_tween = create_tween()
	_mp_tween.tween_property(mp_bar, "size:x", target_w, MP_TWEEN_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_prev_mp = current
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
	if item_slot in ["acc", "ring", "necklace", "shoes", "ring1", "ring2"]:
		return ["acc1", "acc2"]
	return [item_slot]
#endregion
