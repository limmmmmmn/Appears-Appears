extends Control
class_name HeroCard
## 히어로 박스 — 고전 RPG 스타일
## 레이아웃: 좌측 페이스칩 | 우측 이름+레벨, HP바, MP바, ATB바

#region 상수 / 인스펙터 조정 가능 레이아웃
# 레이아웃 치수 (인스펙터에서 조정 가능)
@export_group("Layout")
@export var name_row_h: int = 14           ## 이름/레벨 행 높이
@export var bar_row_h: int = 12            ## HP/MP/ATB 행 높이 (라벨+바 통합)
@export var bar_thickness: int = 8         ## 바 ColorRect 실제 높이
@export var row_gap: int = 2               ## 행 사이 간격
@export var inner_pad: int = 4             ## 내부 패딩
@export var border_width: int = 1          ## 테두리 두께

@export_group("Face Chip")
@export var face_size: int = 40            ## 페이스칩 크기 (정사각형)
@export var face_gap: int = 4              ## 페이스칩과 바 사이 간격

@export_group("Bar Labels")
@export var bar_label_w: int = 18          ## "HP"/"MP"/"ATB" 라벨 너비
@export var bar_num_min_w: int = 32        ## 숫자 표시 최소 너비

## 페이스칩 영역 폭 (inner_pad + face_size + face_gap)
var face_area_w: int:
	get: return inner_pad + face_size + face_gap

# 색상 — 고전 RPG 테두리 박스
const BG_COLOR := Color(0.06, 0.06, 0.1, 0.92)
const BORDER_COLOR := Color(0.55, 0.6, 0.75, 0.9)
const BORDER_COLOR_SELECTED := Color(1.0, 0.88, 0.28, 1.0)
const BORDER_COLOR_HOVER := Color(0.7, 0.75, 0.9, 1.0)

# HP 바 색상 (비율별)
const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW := Color(0.92, 0.22, 0.22)
const HP_BG_COLOR := Color(0.12, 0.12, 0.15, 0.9)

# MP 바 색상
const MP_COLOR := Color(0.3, 0.5, 0.95)
const MP_BG_COLOR := Color(0.1, 0.1, 0.18, 0.9)

# ATB 바 색상
const ATB_BG_COLOR := Color(0.1, 0.1, 0.14, 0.85)
const ATB_FILL_LOW := Color(0.2, 0.3, 0.5, 0.7)
const ATB_FILL_HIGH := Color(0.4, 0.75, 1.0, 0.95)
const ATB_FILL_READY := Color(0.25, 0.9, 0.35, 0.95)
const ATB_FILL_QUEUED_PHYS := Color(1.0, 0.55, 0.25, 0.95)
const ATB_FILL_QUEUED_MAG := Color(0.6, 0.5, 1.0, 0.95)
const ATB_FILL_QUEUED_HEAL := Color(0.4, 0.9, 0.8, 0.95)
const ATB_FILL_QUEUED_READY := Color(1.0, 0.85, 0.2, 0.95)

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

# 트윈
var _shake_tween: Tween

# 장비 관련 (호환성)
var equip_rows: Dictionary = {}
var equip_panel: PanelContainer
#endregion


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)


#region 리사이즈 — 카드 폭이 바뀔 때 바/라벨 재배치
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


func _relayout() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0:
		return

	# 우측 영역: 페이스칩 오른쪽부터 카드 끝까지
	var right_w: float = w - face_area_w - inner_pad
	var right_x: float = face_area_w

	# 페이스칩 세로 중앙 배치
	if _face_chip:
		var face_y: float = maxf(inner_pad, floorf((h - face_size) * 0.5))
		_face_chip.position = Vector2(inner_pad, face_y)
		_face_chip.size = Vector2(face_size, face_size)

	# 이름/레벨 라벨
	if _name_label:
		_name_label.position.x = right_x
		_name_label.size = Vector2(right_w * 0.6, name_row_h)
	if _level_label:
		_level_label.position.x = right_x
		_level_label.size = Vector2(right_w, name_row_h)

	# HP/MP/ATB 바 — 라벨 오른쪽
	var bar_x: float = right_x + bar_label_w + 2
	var bar_w: float = right_w - bar_label_w - 2
	if _hp_bar_bg:
		_hp_bar_bg.position.x = bar_x
		_hp_bar_bg.size.x = bar_w
	if _hp_bar_fill:
		_hp_bar_fill.position.x = bar_x
	if _hp_label_num:
		_hp_label_num.position.x = bar_x
		_hp_label_num.size.x = bar_w

	# MP 바
	if _mp_bar_bg:
		_mp_bar_bg.position.x = bar_x
		_mp_bar_bg.size.x = bar_w
	if _mp_bar_fill:
		_mp_bar_fill.position.x = bar_x
	if _mp_label_num:
		_mp_label_num.position.x = bar_x
		_mp_label_num.size.x = bar_w

	# ATB 바
	if _atb_bar_bg:
		_atb_bar_bg.position.x = bar_x
		_atb_bar_bg.size.x = bar_w
#endregion


#region _draw — 테두리
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# 배경
	draw_rect(rect, BG_COLOR)
	# 테두리
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
	# 페이스칩
	if _face_chip and SpriteManager:
		_face_chip.texture = SpriteManager.get_hero_face_sprite(hero.id)
	update_name(hero.hero_name)
	update_level(hero.level)
	update_hp(hero.current_hp, hero.get_max_hp())
	update_mp(hero)
	update_atb(hero)
	set_dead(hero.is_dead)


func update_name(hero_name: String) -> void:
	if _name_label:
		_name_label.text = hero_name


func update_level(lv: int) -> void:
	if _level_label:
		_level_label.text = "Lv.%d" % lv


func update_hp(current: int, max_hp: int) -> void:
	_cached_max_hp = max_hp
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0

	# 바 너비
	if _hp_bar_fill and _hp_bar_bg:
		var bar_w: float = _hp_bar_bg.size.x
		_hp_bar_fill.size.x = bar_w * ratio

	# 바 색상 (비율별)
	if _hp_bar_fill:
		if ratio > 0.6:
			_hp_bar_fill.color = HP_COLOR_HIGH
		elif ratio > 0.3:
			_hp_bar_fill.color = HP_COLOR_MID
		else:
			_hp_bar_fill.color = HP_COLOR_LOW

	# 숫자 텍스트
	if _hp_label_num:
		_hp_label_num.text = "%d/%d" % [current, max_hp]

	_prev_hp = current


func update_mp(hero: Hero) -> void:
	## MP 바 갱신 — Hero에 MP 시스템이 없으면 빈 바 표시
	if _mp_bar_fill == null or _mp_bar_bg == null:
		return
	var current_mp: int = 0
	var max_mp: int = 0
	if hero != null:
		if "current_mp" in hero:
			current_mp = int(hero.get("current_mp"))
		if hero.has_method("get_max_mp"):
			max_mp = int(hero.get_max_mp())
		elif "max_mp" in hero:
			max_mp = int(hero.get("max_mp"))

	var bar_w: float = _mp_bar_bg.size.x
	if max_mp > 0:
		var ratio: float = clampf(float(current_mp) / float(max_mp), 0.0, 1.0)
		_mp_bar_fill.size.x = bar_w * ratio
	else:
		_mp_bar_fill.size.x = 0

	if _mp_label_num:
		if max_mp > 0:
			_mp_label_num.text = "%d/%d" % [current_mp, max_mp]
		else:
			_mp_label_num.text = ""


func update_atb(hero: Hero) -> void:
	if hero == null or _atb_bar_fill == null or _atb_bar_bg == null:
		return
	var action_delay: float = maxf(0.001, hero.get_action_delay())
	var ratio: float = clampf(hero.action_timer / action_delay, 0.0, 1.0)
	var bar_w: float = _atb_bar_bg.size.x
	_atb_bar_fill.size.x = bar_w * ratio
	_atb_bar_fill.color = _calc_atb_color(hero, ratio)


func _calc_atb_color(hero: Hero, ratio: float) -> Color:
	# 예약 스킬이 있으면 스킬 타입별 색상
	if not hero.queued_skill.is_empty():
		if ratio >= 0.999:
			return ATB_FILL_QUEUED_READY
		var queued_data: Dictionary = DataManager.get_skill(hero.queued_skill)
		var queued_type: String = str(queued_data.get("type", "physical"))
		if queued_type == "magic":
			return ATB_FILL_QUEUED_MAG
		if queued_type == "heal":
			return ATB_FILL_QUEUED_HEAL
		return ATB_FILL_QUEUED_PHYS
	if ratio >= 0.999:
		return ATB_FILL_READY
	# 점점 밝아지는 효과
	return ATB_FILL_LOW.lerp(ATB_FILL_HIGH, ratio)


func update_exp(_percent: float) -> void:
	# EXP 바는 새 디자인에서 제거 (레벨업 버튼 사용)
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
	if _atb_bar_bg:
		_atb_bar_bg.visible = not is_dead
	if _atb_label_tag:
		_atb_label_tag.visible = not is_dead
	if _atb_bar_fill:
		_atb_bar_fill.visible = not is_dead
	if _face_chip:
		_face_chip.modulate = Color(0.3, 0.3, 0.3) if is_dead else Color.WHITE
#endregion


#region 기존 하위 호환 API (PartyPanel에서 사용)
func update_skill_atb_bars(hero: Hero) -> void:
	update_atb(hero)

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
