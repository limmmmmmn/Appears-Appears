extends Control
class_name HeroCard
## 히어로 카드 — 페이스칩 + 스킬별 ATB 바
## 레이아웃: 좌측 페이스칩(+HP 오버레이) + 이름/레벨 | 우측 스킬 ATB 바 ×3

#region 상수 / 레이아웃
@export_group("Layout")
@export var name_row_h: int = 14
@export var bar_row_h: int = 12
@export var bar_thickness: int = 8
@export var row_gap: int = 2
@export var inner_pad: int = 4
@export var border_width: int = 1

@export_group("Face Chip")
@export var face_size: int = 40
@export var face_gap: int = 4

@export_group("Bar Labels")
@export var bar_label_w: int = 18
@export var bar_num_min_w: int = 32

var face_area_w: int:
	get: return inner_pad + face_size + face_gap

# 새 레이아웃 상수
const FACE_TOP_Y: int = 2
const NAME_LABEL_Y: int = 42
const LEVEL_LABEL_Y: int = 51
const LABEL_H: int = 9

# 색상 — 카드 배경/테두리
const BG_COLOR := Color(0.06, 0.06, 0.1, 0.92)
const BORDER_COLOR := Color(0.55, 0.6, 0.75, 0.9)
const BORDER_COLOR_SELECTED := Color(1.0, 0.88, 0.28, 1.0)
const BORDER_COLOR_HOVER := Color(0.7, 0.75, 0.9, 1.0)

# HP 바 색상 (레거시 — 숨김 상태이지만 호환용 유지)
const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW := Color(0.92, 0.22, 0.22)
const HP_BG_COLOR := Color(0.12, 0.12, 0.15, 0.9)

# 데미지 오버레이 (페이스칩 위 빨간색)
const DAMAGE_OVERLAY_COLOR := Color(0.85, 0.1, 0.1, 0.55)

# 스킬 ATB 바 (기본공격 1줄 + 클래스 스킬 3줄 = 4줄)
const SKILL_BAR_X: int = 48
const SKILL_BAR_W: int = 108
const SKILL_BAR_H: int = 13
const SKILL_BAR_GAP: int = 1
const SKILL_BAR_TOP_Y: int = 2
const SKILL_BAR_COUNT: int = 4  # 기본공격 + 스킬 3개
const ATB_BG_COLOR := Color(0.1, 0.1, 0.14, 0.85)

# 기본공격 ATB 바 색상
const BASIC_ATK_COLOR := Color(0.7, 0.7, 0.7, 0.8)
const BASIC_ATK_READY := Color(1.0, 1.0, 0.9, 0.95)

# 스킬 타입별 색상 (충전 중)
const SKILL_COLOR_PHYSICAL := Color(0.9, 0.45, 0.2, 0.85)
const SKILL_COLOR_MAGIC := Color(0.45, 0.35, 0.9, 0.85)
const SKILL_COLOR_HEAL := Color(0.25, 0.8, 0.5, 0.85)
const SKILL_COLOR_BUFF := Color(0.8, 0.7, 0.2, 0.85)
const SKILL_COLOR_RESURRECT := Color(0.8, 0.8, 0.2, 0.85)

# 스킬 타입별 색상 (준비 완료)
const SKILL_READY_PHYSICAL := Color(1.0, 0.7, 0.3, 0.95)
const SKILL_READY_MAGIC := Color(0.7, 0.6, 1.0, 0.95)
const SKILL_READY_HEAL := Color(0.4, 1.0, 0.7, 0.95)
const SKILL_READY_BUFF := Color(1.0, 0.9, 0.3, 0.95)
const SKILL_READY_RESURRECT := Color(1.0, 1.0, 0.5, 0.95)

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

# 트윈
var _shake_tween: Tween

# 데미지 오버레이
var _damage_overlay: ColorRect = null

# 스킬 ATB 바: Array of { bg: ColorRect, fill: ColorRect, label: Label, skill_id: String, skill_type: String }
var _skill_bars: Array[Dictionary] = []
var _skill_bar_container: Control = null
var _skill_bar_skill_ids: Array = []

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
	_create_damage_overlay()


#region 레거시 바 숨기기
func _hide_legacy_bars() -> void:
	for node in [_hp_bar_bg, _hp_bar_fill, _hp_label_tag, _hp_label_num,
				 _mp_bar_bg, _mp_bar_fill, _mp_label_tag, _mp_label_num,
				 _atb_bar_bg, _atb_bar_fill, _atb_label_tag]:
		if node:
			node.visible = false
#endregion


#region 데미지 오버레이 (페이스칩 위 빨간색 채움)
func _create_damage_overlay() -> void:
	_damage_overlay = ColorRect.new()
	_damage_overlay.color = DAMAGE_OVERLAY_COLOR
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_overlay.size = Vector2(face_size, 0)
	_damage_overlay.position = Vector2(inner_pad, FACE_TOP_Y + face_size)
	if _content:
		_content.add_child(_damage_overlay)


func _update_damage_overlay(hp_ratio: float) -> void:
	if _damage_overlay == null:
		return
	var loss: float = 1.0 - clampf(hp_ratio, 0.0, 1.0)
	var overlay_h: float = float(face_size) * loss
	_damage_overlay.size = Vector2(face_size, overlay_h)
	_damage_overlay.position = Vector2(inner_pad, float(FACE_TOP_Y) + float(face_size) - overlay_h)
#endregion


#region 스킬 ATB 바
func _create_skill_atb_bars(hero: Hero) -> void:
	if _skill_bar_container != null and is_instance_valid(_skill_bar_container):
		_skill_bar_container.queue_free()
	_skill_bars.clear()
	_skill_bar_skill_ids.clear()

	_skill_bar_container = Control.new()
	_skill_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_bar_container.position = Vector2.ZERO
	_skill_bar_container.size = size
	if _content:
		_content.add_child(_skill_bar_container)

	var skill_ids: Array = _get_display_skill_ids(hero)
	_skill_bar_skill_ids = skill_ids.duplicate()

	for i in range(mini(skill_ids.size(), SKILL_BAR_COUNT)):
		var skill_id: String = skill_ids[i]
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		var skill_type: String = str(skill_data.get("type", "physical"))
		var skill_name: String = str(skill_data.get("name", skill_id))
		var is_basic: bool = (skill_id == "basic_attack")

		var bar_y: int = SKILL_BAR_TOP_Y + i * (SKILL_BAR_H + SKILL_BAR_GAP)

		# 배경
		var bg := ColorRect.new()
		bg.position = Vector2(SKILL_BAR_X, bar_y)
		bg.size = Vector2(SKILL_BAR_W, SKILL_BAR_H)
		bg.color = ATB_BG_COLOR
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skill_bar_container.add_child(bg)

		# 채움
		var fill := ColorRect.new()
		fill.position = Vector2(SKILL_BAR_X, bar_y)
		fill.size = Vector2(0, SKILL_BAR_H)
		fill.color = BASIC_ATK_COLOR if is_basic else _get_skill_type_color(skill_type, false)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skill_bar_container.add_child(fill)

		# 스킬 이름 라벨
		var lbl := Label.new()
		lbl.position = Vector2(SKILL_BAR_X + 2, bar_y)
		lbl.size = Vector2(SKILL_BAR_W - 4, SKILL_BAR_H)
		lbl.text = skill_name
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.7))
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.clip_text = true
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skill_bar_container.add_child(lbl)

		_skill_bars.append({
			"bg": bg,
			"fill": fill,
			"label": lbl,
			"skill_id": skill_id,
			"skill_type": skill_type,
			"is_basic": is_basic,
		})


func _get_display_skill_ids(hero: Hero) -> Array:
	var result: Array = ["basic_attack"]  # 기본공격 항상 맨 위
	for sid in hero.get_skill_priority_list():
		if sid != "basic_attack":
			result.append(sid)
	if result.size() <= 1:
		for sid in hero.unlocked_skills:
			if sid != "basic_attack" and not result.has(sid):
				result.append(sid)
	return result


func _get_skill_type_color(skill_type: String, is_ready: bool) -> Color:
	match skill_type:
		"physical":
			return SKILL_READY_PHYSICAL if is_ready else SKILL_COLOR_PHYSICAL
		"magic":
			return SKILL_READY_MAGIC if is_ready else SKILL_COLOR_MAGIC
		"heal":
			return SKILL_READY_HEAL if is_ready else SKILL_COLOR_HEAL
		"buff":
			return SKILL_READY_BUFF if is_ready else SKILL_COLOR_BUFF
		"resurrect":
			return SKILL_READY_RESURRECT if is_ready else SKILL_COLOR_RESURRECT
		_:
			return SKILL_READY_PHYSICAL if is_ready else SKILL_COLOR_PHYSICAL
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

	# 페이스칩: 좌상단
	if _face_chip:
		_face_chip.position = Vector2(inner_pad, FACE_TOP_Y)
		_face_chip.size = Vector2(face_size, face_size)

	# 이름 라벨: 페이스칩 아래
	if _name_label:
		_name_label.position = Vector2(inner_pad, NAME_LABEL_Y)
		_name_label.size = Vector2(face_size, LABEL_H)
		_name_label.add_theme_font_size_override("font_size", 7)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.clip_text = true

	# 레벨 라벨: 이름 아래
	if _level_label:
		_level_label.position = Vector2(inner_pad, LEVEL_LABEL_Y)
		_level_label.size = Vector2(face_size, LABEL_H)
		_level_label.add_theme_font_size_override("font_size", 7)
		_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 데미지 오버레이
	if _damage_overlay and _hero_ref:
		_update_damage_overlay(_hero_ref.get_hp_percent())
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
	update_name(hero.hero_name)
	update_level(hero.level)
	update_hp(hero.current_hp, hero.get_max_hp())
	update_skill_atb_bars(hero)
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
	_update_damage_overlay(ratio)
	_prev_hp = current


func update_mp(_hero: Hero) -> void:
	pass


func update_atb(hero: Hero) -> void:
	update_skill_atb_bars(hero)


func update_skill_atb_bars(hero: Hero) -> void:
	if hero == null:
		return
	var current_ids: Array = _get_display_skill_ids(hero)
	# 바가 아직 없거나 스킬 구성이 바뀌면 재생성
	if _skill_bars.is_empty() and not current_ids.is_empty():
		_create_skill_atb_bars(hero)
	elif not _skill_bars.is_empty() and current_ids != _skill_bar_skill_ids:
		_create_skill_atb_bars(hero)

	for bar_data in _skill_bars:
		var skill_id: String = bar_data["skill_id"]
		var skill_type: String = bar_data["skill_type"]
		var is_basic: bool = bar_data.get("is_basic", false)
		var fill: ColorRect = bar_data["fill"]
		var lbl: Label = bar_data["label"]

		var percent: float = hero.get_skill_cooldown_percent(skill_id)
		var is_ready: bool = hero.is_skill_off_cooldown(skill_id)

		fill.size.x = float(SKILL_BAR_W) * percent
		if is_basic:
			fill.color = BASIC_ATK_READY if is_ready else BASIC_ATK_COLOR
		else:
			fill.color = _get_skill_type_color(skill_type, is_ready)

		if is_ready:
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8, 1.0))
		else:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.7))


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
	if _skill_bar_container:
		_skill_bar_container.visible = not is_dead
	if _face_chip:
		_face_chip.modulate = Color(0.3, 0.3, 0.3) if is_dead else Color.WHITE
	if _damage_overlay:
		_damage_overlay.visible = not is_dead

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
			var face_rect := Rect2(Vector2(inner_pad, FACE_TOP_Y), Vector2(face_size, face_size))
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
