extends Control
class_name HeroCard
## 히어로 카드 — 좌측 페이스칩(HP 오버레이) + 우측 HP바/ASP바
## 레이아웃 (가로):
##   [Face 40×40] ████████ HP바 (두꺼움)
##                ━━━━━  ASP바 (얇고 짧음, HP바 2/3)
##                이름 Lv.7

#region 상수 / 레이아웃
@export_group("Layout")
@export var inner_pad: int = 2
@export var border_width: int = 1

@export_group("Face Chip")
@export var face_size: int = 40

# 레이아웃
const FACE_X: int = 2
const FACE_Y: int = 2
const BAR_GAP: int = 2             # 바 사이 세로 간격
const HP_BAR_H: int = 6            # HP바 높이
const ASP_BAR_H: int = 2           # ASP바 높이 (얇음)
const ASP_BAR_RATIO: float = 0.7   # ASP바 길이 = HP바의 70%
const LV_FONT_SIZE: int = 7

# 색상 — 카드 배경/테두리 (투명)
const BG_COLOR := Color(0, 0, 0, 0)
const BORDER_COLOR := Color(0, 0, 0, 0)
const BORDER_COLOR_SELECTED := Color(1.0, 0.88, 0.28, 0.6)
const BORDER_COLOR_HOVER := Color(0.7, 0.75, 0.9, 0.4)

# 데미지 오버레이 (페이스칩 위 빨간색)
const DAMAGE_OVERLAY_COLOR := Color(0.85, 0.1, 0.1, 0.55)

# HP바 색상 (초록색 계열)
const HP_BAR_BG := Color(0.08, 0.12, 0.08, 0.9)
const HP_BAR_HIGH := Color(0.2, 0.8, 0.25, 0.9)
const HP_BAR_MID := Color(0.85, 0.75, 0.15, 0.9)
const HP_BAR_LOW := Color(0.8, 0.2, 0.15, 0.9)
const HP_BAR_GHOST := Color(0.9, 0.3, 0.25, 0.9)  # 잔상 HP바 (빨간색 — 깎인 HP 강조)

# 잔상 HP바 타이밍
const GHOST_HOLD: float = 0.3   # 피격 후 잔상 유지 시간
const GHOST_FADE: float = 0.5   # 잔상이 실제 HP까지 줄어드는 시간

# 액션스피드바 색상 (푸른색 계열)
const ACTION_BAR_BG := Color(0.06, 0.08, 0.15, 0.85)
const ACTION_BAR_FILL := Color(0.25, 0.5, 0.85, 0.8)
const ACTION_BAR_READY := Color(0.5, 0.8, 1.0, 0.95)

# 사망 오버레이
const DEATH_OVERLAY_COLOR := Color(0.08, 0.08, 0.08, 0.7)

# 애니메이션
const SHAKE_DURATION := 0.2
const SHAKE_STRENGTH := 3.0
#endregion


#region 시그널
signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)
signal card_selected(hero_index: int)
signal card_hovered(hero_index: int, is_hovered: bool)
signal face_chip_clicked(hero_index: int)
#endregion


#region 변수
var hero_index: int = -1
var hero_id: String = ""
var _hero_ref: Hero = null
var _is_selected: bool = false
var _is_hovered: bool = false

# UI 노드 (씬 참조)
@onready var _content: Control = %Content
@onready var _face_chip: TextureRect = %FaceChip
@onready var _name_label: Label = %NameLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar_bg: ColorRect = %HPBarBG
@onready var _hp_bar_fill: ColorRect = %HPBarFill
@onready var _hp_label_tag: Label = %HPLabelTag
@onready var _hp_label_num: Label = %HPLabelNum
@onready var _mp_bar_bg: ColorRect = %MPBarBG
@onready var _mp_bar_fill: ColorRect = %MPBarFill
@onready var _mp_label_tag: Label = %MPLabelTag
@onready var _mp_label_num: Label = %MPLabelNum
@onready var _atb_bar_bg: ColorRect = %ATBBarBG
@onready var _atb_bar_fill: ColorRect = %ATBBarFill
@onready var _atb_label_tag: Label = %ATBLabelTag
@onready var _death_overlay: ColorRect = %DeathOverlay
@onready var _skull_label: Label = %SkullLabel

# 캐시
var _cached_max_hp: int = 0
var _prev_hp: int = -1
var _cached_hp_ratio: float = 1.0

# 트윈
var _shake_tween: Tween

# 데미지 오버레이
var _damage_overlay: ColorRect = null

# 우측 바 (동적 생성)
var _right_hp_bar_bg: ColorRect = null
var _right_hp_bar_ghost: ColorRect = null  # 잔상 HP바 (뒤 레이어)
var _right_hp_bar_fill: ColorRect = null   # 실제 HP바 (앞 레이어)
var _action_bar_bg: ColorRect = null
var _action_bar_fill: ColorRect = null
var _lv_label: Label = null
var _ghost_tween: Tween = null
var _ghost_ratio: float = 1.0  # 잔상 HP바 비율

# 장비 관련 (호환성)
var equip_rows: Dictionary = {}
var equip_panel: PanelContainer

# 레거시 호환 (PartyPanel에서 아직 참조)
signal hp_potion_requested(hero_index: int)
signal mp_potion_requested(hero_index: int)
#endregion


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_hide_legacy_bars()
	_create_right_bars()


#region 레거시 바 숨기기
func _hide_legacy_bars() -> void:
	for node in [_hp_bar_bg, _hp_bar_fill, _hp_label_tag, _hp_label_num,
				 _mp_bar_bg, _mp_bar_fill, _mp_label_tag, _mp_label_num,
				 _atb_bar_bg, _atb_bar_fill, _atb_label_tag,
				 _name_label, _level_label]:
		if node:
			node.visible = false
#endregion


#region 데미지 오버레이 (페이스칩 위 빨간색 채움)
func _create_damage_overlay() -> void:
	_damage_overlay = ColorRect.new()
	_damage_overlay.color = DAMAGE_OVERLAY_COLOR
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_overlay.size = Vector2(face_size, 0)
	_damage_overlay.position = Vector2(FACE_X, FACE_Y + face_size)
	if _content:
		_content.add_child(_damage_overlay)


func _update_damage_overlay(hp_ratio: float) -> void:
	if _damage_overlay == null:
		return
	var loss: float = 1.0 - clampf(hp_ratio, 0.0, 1.0)
	var overlay_h: float = float(face_size) * loss
	_damage_overlay.size = Vector2(face_size, overlay_h)
	_damage_overlay.position = Vector2(FACE_X, float(FACE_Y) + float(face_size) - overlay_h)
#endregion


#region 우측 바: 이름Lv + HP바 + ASP바 (페이스칩 하단 정렬)
func _create_right_bars() -> void:
	if _content == null:
		return

	var bar_x: int = FACE_X + face_size + 3
	var bar_w: float = size.x - float(bar_x) - float(inner_pad)
	if bar_w < 4.0:
		bar_w = 30.0  # 최소 폭

	# 하단 정렬 기준: 페이스칩 바닥 = FACE_Y + face_size
	var face_bottom: int = FACE_Y + face_size
	# 총 높이: 이름Lv(10) + gap(1) + HP바(6) + gap(2) + ASP바(2)
	var lv_h: int = 10
	var total_h: int = lv_h + 1 + HP_BAR_H + BAR_GAP + ASP_BAR_H
	var start_y: int = face_bottom - total_h

	# --- 이름+Lv 라벨 (맨 위) ---
	_lv_label = Label.new()
	_lv_label.text = "Lv.1"
	_lv_label.add_theme_font_size_override("font_size", LV_FONT_SIZE)
	_lv_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.85, 1.0))
	_lv_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_lv_label.add_theme_constant_override("outline_size", 3)
	_lv_label.position = Vector2(bar_x, start_y)
	_lv_label.size = Vector2(bar_w, lv_h)
	_lv_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lv_label.clip_text = true
	_lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_lv_label)

	# --- HP 바 (3층: BG → Ghost → Fill) ---
	var hp_y: int = start_y + lv_h + 1
	_right_hp_bar_bg = ColorRect.new()
	_right_hp_bar_bg.position = Vector2(bar_x, hp_y)
	_right_hp_bar_bg.size = Vector2(bar_w, HP_BAR_H)
	_right_hp_bar_bg.color = HP_BAR_BG
	_right_hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_right_hp_bar_bg)

	_right_hp_bar_ghost = ColorRect.new()
	_right_hp_bar_ghost.position = Vector2(bar_x, hp_y)
	_right_hp_bar_ghost.size = Vector2(bar_w, HP_BAR_H)
	_right_hp_bar_ghost.color = HP_BAR_GHOST
	_right_hp_bar_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_right_hp_bar_ghost)

	_right_hp_bar_fill = ColorRect.new()
	_right_hp_bar_fill.position = Vector2(bar_x, hp_y)
	_right_hp_bar_fill.size = Vector2(bar_w, HP_BAR_H)
	_right_hp_bar_fill.color = HP_BAR_HIGH
	_right_hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_right_hp_bar_fill)

	# --- ASP 바 (얇고 짧음) ---
	var asp_y: int = hp_y + HP_BAR_H + BAR_GAP
	var asp_w: float = bar_w * ASP_BAR_RATIO
	_action_bar_bg = ColorRect.new()
	_action_bar_bg.position = Vector2(bar_x, asp_y)
	_action_bar_bg.size = Vector2(asp_w, ASP_BAR_H)
	_action_bar_bg.color = ACTION_BAR_BG
	_action_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_action_bar_bg)

	_action_bar_fill = ColorRect.new()
	_action_bar_fill.position = Vector2(bar_x, asp_y)
	_action_bar_fill.size = Vector2(0, ASP_BAR_H)
	_action_bar_fill.color = ACTION_BAR_FILL
	_action_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_action_bar_fill)
#endregion


#region 리사이즈
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


func _relayout() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0:
		return

	# 페이스칩: 좌측 고정
	if _face_chip:
		_face_chip.position = Vector2(FACE_X, FACE_Y)
		_face_chip.size = Vector2(face_size, face_size)

	# 우측 바 위치/크기 조정 (하단 정렬)
	var bar_x: int = FACE_X + face_size + 3
	var bar_w: float = w - float(bar_x) - float(inner_pad)
	if bar_w < 4.0:
		bar_w = 4.0

	var face_bottom: int = FACE_Y + face_size
	var lv_h: int = 10
	var total_h: int = lv_h + 1 + HP_BAR_H + BAR_GAP + ASP_BAR_H
	var start_y: int = face_bottom - total_h

	# 이름+Lv (맨 위)
	if _lv_label:
		_lv_label.position = Vector2(bar_x, start_y)
		_lv_label.size = Vector2(bar_w, lv_h)

	# HP바
	var hp_y: int = start_y + lv_h + 1
	if _right_hp_bar_bg:
		_right_hp_bar_bg.position = Vector2(bar_x, hp_y)
		_right_hp_bar_bg.size = Vector2(bar_w, HP_BAR_H)
	if _right_hp_bar_ghost:
		_right_hp_bar_ghost.position = Vector2(bar_x, hp_y)
		_right_hp_bar_ghost.size.x = bar_w * _ghost_ratio
		_right_hp_bar_ghost.size.y = HP_BAR_H
	if _right_hp_bar_fill:
		_right_hp_bar_fill.position = Vector2(bar_x, hp_y)
		_right_hp_bar_fill.size.x = bar_w * _cached_hp_ratio
		_right_hp_bar_fill.size.y = HP_BAR_H

	# ASP바
	var asp_y: int = hp_y + HP_BAR_H + BAR_GAP
	var asp_w: float = bar_w * ASP_BAR_RATIO
	if _action_bar_bg:
		_action_bar_bg.position = Vector2(bar_x, asp_y)
		_action_bar_bg.size = Vector2(asp_w, ASP_BAR_H)
	if _action_bar_fill:
		_action_bar_fill.position = Vector2(bar_x, asp_y)
		_action_bar_fill.size.y = ASP_BAR_H

	# 사망 오버레이
	if _death_overlay:
		_death_overlay.size = size
#endregion


#region _draw — 테두리
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BG_COLOR)
	var border_col := BORDER_COLOR
	if _is_selected:
		border_col = BORDER_COLOR_SELECTED
	elif _is_hovered:
		border_col = BORDER_COLOR_HOVER
	draw_rect(rect, border_col, false, float(border_width))
#endregion


#region 초기화
func init(p_hero_index: int) -> void:
	hero_index = p_hero_index
#endregion


#region 히어로 데이터 갱신
func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	_hero_ref = hero
	hero_id = hero.id
	if _face_chip and SpriteManager:
		_face_chip.texture = SpriteManager.get_hero_face_sprite(hero.id)
	update_name_and_level(hero.hero_name, hero.level)
	update_hp(hero.current_hp, hero.get_max_hp())
	update_action_bar(hero)
	set_dead(hero.is_dead)


func update_name(hero_name: String) -> void:
	# 이름만 갱신할 때 — 레벨은 유지
	if _lv_label and _hero_ref:
		_lv_label.text = "%s Lv.%d" % [hero_name, _hero_ref.level]


func update_level(lv: int) -> void:
	# 레벨만 갱신할 때 — 이름은 유지
	if _lv_label and _hero_ref:
		_lv_label.text = "%s Lv.%d" % [_hero_ref.hero_name, lv]
	elif _lv_label:
		_lv_label.text = "Lv.%d" % lv


func update_name_and_level(hero_name: String, lv: int) -> void:
	if _lv_label:
		_lv_label.text = "%s Lv.%d" % [hero_name, lv]


func update_hp(current: int, max_hp: int) -> void:
	_cached_max_hp = max_hp
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0
	var hp_changed: bool = (current != _prev_hp)

	# 우측 HP바 갱신 (실제 HP = 즉시 반영)
	if _right_hp_bar_fill and _right_hp_bar_bg:
		_right_hp_bar_fill.size.x = _right_hp_bar_bg.size.x * ratio
		if ratio > 0.5:
			_right_hp_bar_fill.color = HP_BAR_HIGH
		elif ratio > 0.25:
			_right_hp_bar_fill.color = HP_BAR_MID
		else:
			_right_hp_bar_fill.color = HP_BAR_LOW

	# 잔상 HP바 처리 — HP가 실제로 변했을 때만 (매 프레임 호출 대응)
	if hp_changed and _right_hp_bar_ghost and _right_hp_bar_bg:
		if ratio < _cached_hp_ratio:
			# 피격: 잔상은 이전 비율에 머물다가 스르륵 줄어듦
			_ghost_ratio = _cached_hp_ratio
			_right_hp_bar_ghost.size.x = _right_hp_bar_bg.size.x * _ghost_ratio
			_start_ghost_tween(ratio)
		elif ratio > _cached_hp_ratio:
			# 회복: 잔상 즉시 실제 HP로 맞춤 (잔상 불필요)
			_ghost_ratio = ratio
			_right_hp_bar_ghost.size.x = _right_hp_bar_bg.size.x * ratio
			if _ghost_tween and _ghost_tween.is_valid():
				_ghost_tween.kill()

	_cached_hp_ratio = ratio
	_prev_hp = current


func _start_ghost_tween(target_ratio: float) -> void:
	if _ghost_tween and _ghost_tween.is_valid():
		_ghost_tween.kill()
	_ghost_tween = create_tween()
	# 0.3초 대기 후 0.5초에 걸쳐 실제 HP 위치까지 줄어듦
	_ghost_tween.tween_interval(GHOST_HOLD)
	_ghost_tween.tween_method(_update_ghost_bar, _ghost_ratio, target_ratio, GHOST_FADE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _update_ghost_bar(ratio: float) -> void:
	_ghost_ratio = ratio
	if _right_hp_bar_ghost and _right_hp_bar_bg:
		_right_hp_bar_ghost.size.x = _right_hp_bar_bg.size.x * ratio


func update_mp(_hero: Hero) -> void:
	pass


func update_atb(hero: Hero) -> void:
	update_action_bar(hero)


func update_action_bar(hero: Hero) -> void:
	## 기본공격 액션 스피드바만 갱신
	if hero == null or _action_bar_fill == null or _action_bar_bg == null:
		return
	var percent: float = hero.get_skill_cooldown_percent("basic_attack")
	var is_ready: bool = hero.is_skill_off_cooldown("basic_attack")
	var bar_max_w: float = _action_bar_bg.size.x
	_action_bar_fill.size.x = bar_max_w * percent
	_action_bar_fill.color = ACTION_BAR_READY if is_ready else ACTION_BAR_FILL


# 하위 호환: update_skill_atb_bars → update_action_bar
func update_skill_atb_bars(hero: Hero) -> void:
	update_action_bar(hero)


func update_exp(_percent: float) -> void:
	pass
#endregion


#region 스킬 (하위 호환 스텁)
func update_skill_cooldowns() -> void:
	pass

func refresh_skill_buttons(_hero: Hero) -> void:
	pass
#endregion


#region 상태
func set_selected(selected: bool) -> void:
	_is_selected = selected
	queue_redraw()


func set_dead(is_dead: bool) -> void:
	if _death_overlay:
		_death_overlay.visible = is_dead
	if _face_chip:
		_face_chip.modulate = Color(0.3, 0.3, 0.3) if is_dead else Color.WHITE
	if _right_hp_bar_bg:
		_right_hp_bar_bg.visible = not is_dead
	if _right_hp_bar_ghost:
		_right_hp_bar_ghost.visible = not is_dead
	if _right_hp_bar_fill:
		_right_hp_bar_fill.visible = not is_dead
	if _lv_label:
		_lv_label.visible = not is_dead
	if _action_bar_bg:
		_action_bar_bg.visible = not is_dead
	if _action_bar_fill:
		_action_bar_fill.visible = not is_dead

func set_potion_enabled(_hp_enabled: bool, _mp_enabled: bool) -> void:
	pass
#endregion


#region 기존 하위 호환 API (PartyPanel에서 사용)
var hp_reference: int = 100

func is_expanded() -> bool:
	return false

func toggle_equips() -> void:
	pass

func expand_equips() -> void:
	pass

func play_equip_sequence(_slot: String, _id: String = "") -> void:
	pass

func collapse_equips() -> void:
	pass

func highlight_slot(_slot: String, _id: String = "") -> void:
	pass

func clear_slot_highlights() -> void:
	pass

func show_item_info(_item_id: String) -> void:
	pass

func show_stat_compare(_item_id: String) -> void:
	pass

func hide_stat_compare() -> void:
	pass

func set_portrait(tex: Texture2D) -> void:
	if _face_chip:
		_face_chip.texture = tex

static func get_target_slots(item_slot: String) -> Array:
	var normalized: String = Hero.normalize_equipment_slot(item_slot)
	if normalized == "acc":
		return ["acc1", "acc2"]
	return [normalized]

func get_slot_global_center(slot: String) -> Vector2:
	return global_position + size * 0.5
#endregion


#region 애니메이션
func shake() -> void:
	if _content == null:
		return
	_kill_tween(_shake_tween)
	_shake_tween = create_tween()
	_shake_tween.tween_property(_content, "position:x", -SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(_content, "position:x", SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(_content, "position:x", -SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(_content, "position:x", SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(_content, "position:x", 0.0, SHAKE_DURATION * 0.1)


func play_damage_anim() -> void:
	shake()


func play_attack_anim() -> void:
	if _content == null:
		return
	_kill_tween(_shake_tween)
	_shake_tween = create_tween()
	_shake_tween.tween_property(_content, "position:y", -5.0, 0.08).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(_content, "position:y", 0.0, 0.12).set_ease(Tween.EASE_IN)


func _kill_tween(tw: Tween) -> void:
	if tw and tw.is_valid():
		tw.kill()
#endregion


#region 입력
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var face_rect := Rect2(
				Vector2(FACE_X, FACE_Y),
				Vector2(face_size, face_size)
			)
			if face_rect.has_point(mb.position):
				face_chip_clicked.emit(hero_index)
			else:
				card_selected.emit(hero_index)


func _on_mouse_entered() -> void:
	_is_hovered = true
	queue_redraw()
	card_hovered.emit(hero_index, true)


func _on_mouse_exited() -> void:
	_is_hovered = false
	queue_redraw()
	card_hovered.emit(hero_index, false)
#endregion
