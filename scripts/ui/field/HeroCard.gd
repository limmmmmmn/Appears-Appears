extends Control
class_name HeroCard
## 발더스게이트 스타일 초상화 유닛
## 페이스칩(48x48) + HP 오버레이(빨간 반투명) + MP 바(우측 세로 3px) + 사망 오버레이

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"
const FACE_SIZE := 48
const MP_BAR_WIDTH := 3

const HP_OVERLAY_COLOR := Color(0.8, 0, 0, 0.5)
const MP_BAR_COLOR := Color(0.25, 0.45, 0.95)
const MP_BAR_BG_COLOR := Color(0.05, 0.05, 0.1, 0.8)
const DEATH_OVERLAY_COLOR := Color(0.1, 0.1, 0.1, 0.7)
const PLACEHOLDER_COLOR := Color(0.15, 0.12, 0.2)
const BORDER_COLOR := Color(0.3, 0.3, 0.35, 0.6)

const HP_TWEEN_DURATION := 0.35
const SHAKE_DURATION := 0.2
const SHAKE_STRENGTH := 3.0

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)

var hero_index: int = -1
var hero_id: String = ""

# 노드 참조 (코드에서 생성)
var face_container: Control
var placeholder: ColorRect
var face_chip: TextureRect
var hp_overlay: ColorRect
var death_overlay: ColorRect
var skull_label: Label
var mp_bar_bg: ColorRect
var mp_bar_fill: ColorRect
var border_rect: ColorRect

var _hp_tween: Tween
var _shake_tween: Tween
var _prev_hp_ratio: float = 1.0


func _ready() -> void:
	custom_minimum_size = Vector2(FACE_SIZE + MP_BAR_WIDTH + 1, FACE_SIZE)
	_build_ui()


func _build_ui() -> void:
	# --- 페이스칩 컨테이너 (클리핑 영역) ---
	face_container = Control.new()
	face_container.position = Vector2.ZERO
	face_container.size = Vector2(FACE_SIZE, FACE_SIZE)
	face_container.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	face_container.mouse_filter = MOUSE_FILTER_STOP
	face_container.gui_input.connect(_on_gui_input)
	add_child(face_container)

	# 플레이스홀더 배경
	placeholder = ColorRect.new()
	placeholder.position = Vector2.ZERO
	placeholder.size = Vector2(FACE_SIZE, FACE_SIZE)
	placeholder.color = PLACEHOLDER_COLOR
	placeholder.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(placeholder)

	# 페이스칩 텍스처
	face_chip = TextureRect.new()
	face_chip.position = Vector2.ZERO
	face_chip.size = Vector2(FACE_SIZE, FACE_SIZE)
	face_chip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_chip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_chip.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(face_chip)

	# HP 오버레이 (아래에서 위로 차오름)
	hp_overlay = ColorRect.new()
	hp_overlay.color = HP_OVERLAY_COLOR
	hp_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	hp_overlay.position = Vector2(0, FACE_SIZE)
	hp_overlay.size = Vector2(FACE_SIZE, 0)
	face_container.add_child(hp_overlay)

	# 사망 오버레이
	death_overlay = ColorRect.new()
	death_overlay.position = Vector2.ZERO
	death_overlay.size = Vector2(FACE_SIZE, FACE_SIZE)
	death_overlay.color = DEATH_OVERLAY_COLOR
	death_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	face_container.add_child(death_overlay)

	skull_label = Label.new()
	skull_label.text = "☠"
	skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skull_label.position = Vector2.ZERO
	skull_label.size = Vector2(FACE_SIZE, FACE_SIZE)
	skull_label.add_theme_font_size_override("font_size", 22)
	skull_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	skull_label.mouse_filter = MOUSE_FILTER_IGNORE
	death_overlay.add_child(skull_label)

	# 테두리
	border_rect = ColorRect.new()
	border_rect.position = Vector2.ZERO
	border_rect.size = Vector2(FACE_SIZE, FACE_SIZE)
	border_rect.color = Color.TRANSPARENT
	border_rect.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(border_rect)

	# --- MP 바 (페이스칩 우측, 위에서 아래로 줄어듦) ---
	mp_bar_bg = ColorRect.new()
	mp_bar_bg.position = Vector2(FACE_SIZE + 1, 0)
	mp_bar_bg.size = Vector2(MP_BAR_WIDTH, FACE_SIZE)
	mp_bar_bg.color = MP_BAR_BG_COLOR
	mp_bar_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(mp_bar_bg)

	mp_bar_fill = ColorRect.new()
	mp_bar_fill.position = Vector2(FACE_SIZE + 1, 0)
	mp_bar_fill.size = Vector2(MP_BAR_WIDTH, FACE_SIZE)
	mp_bar_fill.color = MP_BAR_COLOR
	mp_bar_fill.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(mp_bar_fill)


#region 초기화
func init(p_hero_index: int) -> void:
	hero_index = p_hero_index
#endregion


#region 데이터 갱신 (BottomPartyCards에서 호출)
func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	hero_id = hero.id
	_load_face_chip(hero)
	update_hp(hero.current_hp, hero.get_max_hp())
	update_mp(hero.current_mp, hero.get_max_mp())
	set_dead(hero.is_dead)
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


#region HP 오버레이 (Tween 보간)
func update_hp(current: int, max_hp: int) -> void:
	if hp_overlay == null:
		return
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0
	var overlay_h: float = FACE_SIZE * (1.0 - ratio)
	var overlay_y: float = FACE_SIZE - overlay_h

	if _hp_tween and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween().set_parallel(true)
	_hp_tween.tween_property(hp_overlay, "position:y", overlay_y, HP_TWEEN_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_hp_tween.tween_property(hp_overlay, "size:y", overlay_h, HP_TWEEN_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_prev_hp_ratio = ratio
#endregion


#region MP 바
func update_mp(current: int, max_mp: int) -> void:
	if mp_bar_fill == null:
		return
	var ratio: float = clampf(float(current) / float(max_mp), 0.0, 1.0) if max_mp > 0 else 1.0
	mp_bar_fill.size.y = FACE_SIZE * ratio
#endregion


#region 사망 오버레이
func set_dead(is_dead: bool) -> void:
	if death_overlay:
		death_overlay.visible = is_dead
#endregion


#region 피격 셰이크
func shake() -> void:
	if face_container == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_property(face_container, "position:x", -SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(face_container, "position:x", SHAKE_STRENGTH, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(face_container, "position:x", -SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(face_container, "position:x", SHAKE_STRENGTH * 0.6, SHAKE_DURATION * 0.15)
	_shake_tween.tween_property(face_container, "position:x", 0.0, SHAKE_DURATION * 0.1)


func play_damage_anim() -> void:
	shake()


func play_attack_anim() -> void:
	if face_container == null:
		return
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_property(face_container, "position:y", -5.0, 0.08) \
		.set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(face_container, "position:y", 0.0, 0.12) \
		.set_ease(Tween.EASE_IN)
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
