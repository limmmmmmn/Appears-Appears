extends Control
class_name HeroCard
## 개별 영웅 카드 (페이스칩 + 가로 HP/MP 바)
## 레이아웃: [페이스칩][HP바/MP바] - 페이스칩 좌측, 바 우측 상단 정렬

const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID  := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW  := Color(0.92, 0.22, 0.22)
const HP_GHOST_COLOR := Color(1.0, 0.2, 0.2)
const MP_COLOR := Color(0.3, 0.5, 1.0)
const MP_COLOR_LOW := Color(0.6, 0.4, 0.9)
const MP_GHOST_COLOR := Color(1.0, 0.4, 0.8)
const BAR_BG_COLOR := Color(0.05, 0.05, 0.07, 0.9)

# 잔상 타이밍
const GHOST_DELAY := 0.3
const GHOST_DURATION := 0.5
const BLINK_INTERVAL := 0.3
const BLINK_ALPHA_LOW := 0.3
const BLINK_HP_THRESHOLD := 0.25

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)

@onready var panel: PanelContainer = %Panel
@onready var hp_bar: ProgressBar = %HPBar
@onready var hp_bar_ghost: ProgressBar = %HPBarGhost
@onready var mp_bar: ProgressBar = %MPBar
@onready var mp_bar_ghost: ProgressBar = %MPBarGhost
@onready var face_chip: TextureRect = %FaceChip

var hero_index: int = -1
var hero_id: String = ""
var is_hovered: bool = false

var _anim_tween: Tween = null
var _stat_popup: PanelContainer = null

# 잔상 관련 상태
var _prev_hp: int = -1
var _prev_mp: int = -1
var _hp_ghost_tween: Tween = null
var _mp_ghost_tween: Tween = null
var _blink_tween: Tween = null
var _is_blinking: bool = false


func _ready() -> void:
	panel.mouse_entered.connect(_on_mouse_entered)
	panel.mouse_exited.connect(_on_mouse_exited)
	panel.gui_input.connect(_on_gui_input)
	_style_bar(hp_bar, HP_COLOR_HIGH)
	_style_bar(hp_bar_ghost, HP_GHOST_COLOR, true)
	_style_bar(mp_bar, MP_COLOR)
	_style_bar(mp_bar_ghost, MP_GHOST_COLOR, true)
	call_deferred("_update_min_size")


func _update_min_size() -> void:
	if panel:
		custom_minimum_size.y = panel.get_combined_minimum_size().y


#region 초기화
func init(p_hero_index: int) -> void:
	hero_index = p_hero_index
#endregion


#region 호버
func _on_mouse_entered() -> void:
	is_hovered = true
	_kill_anim()

func _on_mouse_exited() -> void:
	is_hovered = false
#endregion


#region 데이터 갱신
func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	hero_id = hero.id
	_update_bars(hero)
	_update_face_chip(hero)


func _update_face_chip(hero: Hero) -> void:
	if face_chip == null:
		return
	# 페이스칩 로드: sprite_face → field_sprite → 빈 상태
	var face_path: String = ""
	if not hero.portrait.is_empty():
		face_path = FACE_CHIP_PATH % hero.portrait
	elif not hero.field_sprite.is_empty():
		face_path = FACE_CHIP_PATH % hero.field_sprite

	if not face_path.is_empty() and ResourceLoader.exists(face_path):
		face_chip.texture = load(face_path)
	else:
		face_chip.texture = null


func _update_bars(hero: Hero) -> void:
	var max_hp := hero.get_max_hp()
	var cur_hp := hero.current_hp

	# HP 바 max_value 동기화
	hp_bar.max_value = max_hp
	hp_bar_ghost.max_value = max_hp

	# HP 변화 감지
	if _prev_hp < 0:
		hp_bar.value = cur_hp
		hp_bar_ghost.value = cur_hp
	elif cur_hp < _prev_hp:
		hp_bar.value = cur_hp
		_animate_ghost(hp_bar_ghost, cur_hp, true)
	elif cur_hp > _prev_hp:
		_kill_ghost_tween(true)
		hp_bar.value = cur_hp
		hp_bar_ghost.value = cur_hp
	else:
		hp_bar.value = cur_hp

	_prev_hp = cur_hp

	# HP 색상
	var hp_pct: float = float(cur_hp) / float(max_hp) if max_hp > 0 else 1.0
	var hp_color: Color
	if hp_pct <= 0.25:
		hp_color = HP_COLOR_LOW
	elif hp_pct <= 0.5:
		hp_color = HP_COLOR_MID
	else:
		hp_color = HP_COLOR_HIGH
	_update_bar_color(hp_bar, hp_color)

	# 25% 이하 깜빡임
	if hp_pct <= BLINK_HP_THRESHOLD and not hero.is_dead:
		_start_blink()
	else:
		_stop_blink()

	# MP 바
	var max_mp := hero.get_max_mp()
	var cur_mp := hero.current_mp
	mp_bar.max_value = max_mp if max_mp > 0 else 1
	mp_bar_ghost.max_value = max_mp if max_mp > 0 else 1

	if _prev_mp < 0:
		mp_bar.value = cur_mp
		mp_bar_ghost.value = cur_mp
	elif cur_mp < _prev_mp:
		mp_bar.value = cur_mp
		_animate_ghost(mp_bar_ghost, cur_mp, false)
	elif cur_mp > _prev_mp:
		_kill_ghost_tween(false)
		mp_bar.value = cur_mp
		mp_bar_ghost.value = cur_mp
	else:
		mp_bar.value = cur_mp

	_prev_mp = cur_mp

	var mp_pct: float = float(cur_mp) / float(max_mp) if max_mp > 0 else 1.0
	var mp_color: Color = MP_COLOR_LOW if mp_pct <= 0.25 else MP_COLOR
	_update_bar_color(mp_bar, mp_color)
#endregion


#region 잔상 애니메이션
func _animate_ghost(ghost_bar: ProgressBar, target_value: int, is_hp: bool) -> void:
	_kill_ghost_tween(is_hp)

	var tween := create_tween()
	tween.tween_interval(GHOST_DELAY)
	tween.tween_property(ghost_bar, "value", float(target_value), GHOST_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	if is_hp:
		_hp_ghost_tween = tween
	else:
		_mp_ghost_tween = tween


func _kill_ghost_tween(is_hp: bool) -> void:
	if is_hp:
		if _hp_ghost_tween and _hp_ghost_tween.is_valid():
			_hp_ghost_tween.kill()
			_hp_ghost_tween = null
	else:
		if _mp_ghost_tween and _mp_ghost_tween.is_valid():
			_mp_ghost_tween.kill()
			_mp_ghost_tween = null
#endregion


#region 깜빡임 (HP 25% 이하)
func _start_blink() -> void:
	if _is_blinking:
		return
	_is_blinking = true
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_property(hp_bar, "modulate:a", BLINK_ALPHA_LOW, BLINK_INTERVAL)
	_blink_tween.tween_property(hp_bar, "modulate:a", 1.0, BLINK_INTERVAL)


func _stop_blink() -> void:
	if not _is_blinking:
		return
	_is_blinking = false
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
		_blink_tween = null
	if hp_bar:
		hp_bar.modulate.a = 1.0
#endregion


#region 바 스타일
func _style_bar(bar: ProgressBar, fill_color: Color, is_ghost: bool = false) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG_COLOR if is_ghost else Color.TRANSPARENT
	bg.corner_radius_top_left = 1
	bg.corner_radius_top_right = 1
	bg.corner_radius_bottom_left = 1
	bg.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.corner_radius_top_left = 1
	fill.corner_radius_top_right = 1
	fill.corner_radius_bottom_left = 1
	fill.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("fill", fill)


func _update_bar_color(bar: ProgressBar, color: Color) -> void:
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fill:
		var new_fill := fill.duplicate()
		new_fill.bg_color = color
		bar.add_theme_stylebox_override("fill", new_fill)
#endregion


#region 애니메이션
func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
		_anim_tween = null
	if panel:
		panel.position = Vector2.ZERO


func play_attack_anim() -> void:
	if is_hovered or not panel:
		return
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.tween_property(panel, "position:x", 8.0, 0.1).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(panel, "position:x", 0.0, 0.15).set_ease(Tween.EASE_IN)


func play_damage_anim() -> void:
	if is_hovered or not panel:
		return
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.tween_property(panel, "position:x", -4.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 4.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", -3.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 3.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", -2.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 0.0, 0.03)
#endregion


#region 필드 힐 (클릭)
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			field_heal_requested.emit(hero_index)
#endregion


#region 능력치 팝업
func show_item_info(_item_id: String) -> void:
	pass

func show_stat_compare(_item_id: String) -> void:
	pass

func hide_stat_compare() -> void:
	if _stat_popup and is_instance_valid(_stat_popup):
		_stat_popup.queue_free()
		_stat_popup = null
#endregion


#region 슬롯 하이라이트 (호환용 stub)
func highlight_slot(_slot_name: String, _equip_id: String = "") -> void:
	pass

func clear_slot_highlights() -> void:
	pass

func expand_equips() -> void:
	pass

func collapse_equips() -> void:
	pass

static func get_target_slots(item_slot: String) -> Array:
	if item_slot in ["acc", "ring", "necklace", "shoes", "ring1", "ring2"]:
		return ["acc1", "acc2"]
	return [item_slot]
#endregion
