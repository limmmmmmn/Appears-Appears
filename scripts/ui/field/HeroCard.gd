extends Control
class_name HeroCard
## 좌측 파티 카드: 평소 페이스칩+바 표시

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"
const FACE_SIZE := 48
const BAR_GAP := 2

const HP_BAR_HEIGHT := 9
const EXP_BAR_HEIGHT := 4
const BAR_SPACING := 2

const LONG_BAR_MAX_WIDTH := 120
const MIN_BAR_RATIO := 0.3
const SHORT_BAR_WIDTH := 55
const CARD_WIDTH := FACE_SIZE + BAR_GAP + LONG_BAR_MAX_WIDTH
const EXPANDED_EXTRA_HEIGHT := 152.0
const EXPAND_DURATION := 0.28
const COLLAPSE_DURATION := 0.22

const SLOT_ORDER: Array[String] = [
	"main_hand", "off_hand", "head", "body", "acc1", "acc2"
]
const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️", "off_hand": "🛡️", "head": "⛑️",
	"body": "🛡️", "acc1": "💍", "acc2": "💎"
}

const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW := Color(0.92, 0.22, 0.22)
const HP_GHOST_COLOR := Color(1.0, 0.35, 0.35, 0.8)
const EXP_BAR_COLOR := Color(0.3, 0.85, 0.75)
const BAR_BG_COLOR := Color(0.06, 0.06, 0.09, 0.9)
const DEATH_OVERLAY_COLOR := Color(0.1, 0.1, 0.1, 0.7)
const PLACEHOLDER_COLOR := Color(0.15, 0.12, 0.2)

const HP_TWEEN_DURATION := 0.35
const GHOST_DELAY := 0.4
const GHOST_DURATION := 0.5
const SHAKE_DURATION := 0.2
const SHAKE_STRENGTH := 3.0

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)
signal card_selected(hero_index: int)

var hero_index: int = -1
var hero_id: String = ""
var _hero_ref: Hero = null
var hp_reference: int = 100

var content: Control
var face_container: Control
var placeholder: ColorRect
var face_chip: TextureRect
var death_overlay: ColorRect
var skull_label: Label
var bars_container: Control
var hp_bar_bg: ColorRect
var hp_ghost: ColorRect
var hp_bar: ColorRect
var hp_tick_overlay: Control
var exp_bar_bg: ColorRect
var exp_bar: ColorRect
var level_label: Label

var equip_panel: PanelContainer
var equip_rows: Dictionary = {} # slot -> {panel, item}
var _row_style_normal: StyleBoxFlat
var _row_style_highlight: StyleBoxFlat
var _is_expanded: bool = false

var _hp_bar_width: float = LONG_BAR_MAX_WIDTH
var _cached_max_hp: int = 0
var _prev_hp: int = -1
var _hp_tween: Tween
var _ghost_tween: Tween
var _shake_tween: Tween
var _expand_tween: Tween
var _is_selected: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, FACE_SIZE)
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_build_ui()
	queue_redraw()


func _build_ui() -> void:
	content = Control.new()
	content.position = Vector2.ZERO
	content.size = Vector2(CARD_WIDTH, FACE_SIZE)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(content)

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
	death_overlay.visible = false
	death_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(death_overlay)

	skull_label = Label.new()
	skull_label.text = "☠"
	skull_label.size = Vector2(FACE_SIZE, FACE_SIZE)
	skull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skull_label.add_theme_font_size_override("font_size", 22)
	skull_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	skull_label.mouse_filter = MOUSE_FILTER_IGNORE
	death_overlay.add_child(skull_label)

	bars_container = Control.new()
	bars_container.position = Vector2(FACE_SIZE + BAR_GAP, 0)
	bars_container.size = Vector2(LONG_BAR_MAX_WIDTH, FACE_SIZE)
	bars_container.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(bars_container)

	var total_bar_height: float = HP_BAR_HEIGHT + BAR_SPACING + EXP_BAR_HEIGHT
	var start_y: float = floorf((FACE_SIZE - total_bar_height) / 2.0)

	var hp_y: float = start_y
	hp_bar_bg = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(hp_bar_bg)
	hp_ghost = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), HP_GHOST_COLOR)
	bars_container.add_child(hp_ghost)
	hp_bar = _make_rect(Vector2(0, hp_y), Vector2(LONG_BAR_MAX_WIDTH, HP_BAR_HEIGHT), HP_COLOR_HIGH)
	bars_container.add_child(hp_bar)
	hp_tick_overlay = _create_tick_overlay(Vector2(0, hp_y), HP_BAR_HEIGHT)
	bars_container.add_child(hp_tick_overlay)

	level_label = Label.new()
	level_label.position = Vector2(0, hp_y + HP_BAR_HEIGHT + BAR_SPACING)
	level_label.text = "Lv.1"
	level_label.add_theme_font_size_override("font_size", 9)
	level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	level_label.mouse_filter = MOUSE_FILTER_IGNORE
	bars_container.add_child(level_label)

	var exp_y: float = hp_y + HP_BAR_HEIGHT + BAR_SPACING
	exp_bar_bg = _make_rect(Vector2(0, exp_y), Vector2(SHORT_BAR_WIDTH, EXP_BAR_HEIGHT), BAR_BG_COLOR)
	bars_container.add_child(exp_bar_bg)
	exp_bar = _make_rect(Vector2(0, exp_y), Vector2(0, EXP_BAR_HEIGHT), EXP_BAR_COLOR)
	bars_container.add_child(exp_bar)

	# 아코디언 장비 패널 비활성화


func _build_equip_panel() -> void:
	equip_panel = PanelContainer.new()
	equip_panel.position = Vector2(0, FACE_SIZE + 2.0)
	equip_panel.custom_minimum_size = Vector2(CARD_WIDTH, EXPANDED_EXTRA_HEIGHT)
	equip_panel.visible = false
	equip_panel.mouse_filter = MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.03, 0.03, 0.06, 0.96)
	pstyle.border_color = Color(0.45, 0.39, 0.2, 0.9)
	pstyle.set_border_width_all(1)
	pstyle.set_corner_radius_all(5)
	pstyle.content_margin_left = 6
	pstyle.content_margin_right = 6
	pstyle.content_margin_top = 5
	pstyle.content_margin_bottom = 5
	equip_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(equip_panel)

	_row_style_normal = StyleBoxFlat.new()
	_row_style_normal.bg_color = Color(0.05, 0.06, 0.09, 0.95)
	_row_style_normal.border_color = Color(0.36, 0.34, 0.22, 0.7)
	_row_style_normal.set_border_width_all(1)
	_row_style_normal.set_corner_radius_all(4)
	_row_style_normal.content_margin_left = 4
	_row_style_normal.content_margin_right = 4
	_row_style_normal.content_margin_top = 2
	_row_style_normal.content_margin_bottom = 2

	_row_style_highlight = _row_style_normal.duplicate()
	_row_style_highlight.bg_color = Color(0.1, 0.09, 0.03, 0.98)
	_row_style_highlight.border_color = Color(1.0, 0.9, 0.35, 1.0)
	_row_style_highlight.set_border_width_all(2)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	equip_panel.add_child(vbox)

	equip_rows.clear()
	for slot in SLOT_ORDER:
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", _row_style_normal)
		vbox.add_child(row_panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row_panel.add_child(row)

		var icon := Label.new()
		icon.text = str(SLOT_ICONS.get(slot, "📦"))
		icon.custom_minimum_size.x = 16
		icon.add_theme_font_size_override("font_size", 9)
		row.add_child(icon)

		var item := Label.new()
		item.text = "— 비어있음 —"
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.add_theme_font_size_override("font_size", 9)
		item.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		row.add_child(item)

		equip_rows[slot] = {"panel": row_panel, "item": item}


func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


class TickOverlay extends Control:
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


func init(p_hero_index: int) -> void:
	hero_index = p_hero_index


func _draw() -> void:
	if not _is_selected:
		return
	var border_rect := Rect2(Vector2.ZERO, Vector2(FACE_SIZE, FACE_SIZE))
	draw_rect(border_rect, Color(1.0, 0.88, 0.28, 1.0), false, 2.0)


func set_selected(selected: bool) -> void:
	_is_selected = selected
	queue_redraw()


func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	_hero_ref = hero
	hero_id = hero.id
	_load_face_chip(hero)
	_recalc_bar_widths(hero.get_max_hp())
	update_hp(hero.current_hp, hero.get_max_hp())
	update_exp(hero.get_exp_ratio())
	update_level(hero.level)
	set_dead(hero.is_dead)
	_refresh_equip_rows()


func _refresh_equip_rows() -> void:
	if _hero_ref == null:
		return
	for slot in SLOT_ORDER:
		var row: Dictionary = equip_rows.get(slot, {})
		if row.is_empty():
			continue
		var item_label: Label = row.get("item")
		var panel: PanelContainer = row.get("panel")
		var equip_id: String = str(_hero_ref.equipment.get(slot, ""))
		if equip_id.is_empty():
			item_label.text = "— 비어있음 —"
			item_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		else:
			var data: Dictionary = DataManager.get_equipment(equip_id)
			item_label.text = str(data.get("name", equip_id))
			item_label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.82))
		panel.add_theme_stylebox_override("panel", _row_style_normal)
		panel.modulate = Color.WHITE


func _recalc_bar_widths(max_hp: int) -> void:
	_hp_bar_width = _calc_bar_length(max_hp, hp_reference, LONG_BAR_MAX_WIDTH)
	if hp_bar_bg:
		hp_bar_bg.size.x = _hp_bar_width
	if max_hp != _cached_max_hp:
		_cached_max_hp = max_hp
		if hp_tick_overlay and hp_tick_overlay is TickOverlay:
			(hp_tick_overlay as TickOverlay).setup(max_hp, _hp_bar_width, HP_BAR_HEIGHT)
	custom_minimum_size.x = FACE_SIZE + BAR_GAP + _hp_bar_width


func _calc_bar_length(max_value: int, reference: int, max_width: float) -> float:
	var ratio: float = clampf(float(max_value) / float(reference), MIN_BAR_RATIO, 1.0)
	return ratio * max_width


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


func update_hp(current: int, max_hp: int) -> void:
	if hp_bar == null:
		return
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0
	var target_w: float = _hp_bar_width * ratio

	if ratio > 0.6:
		hp_bar.color = HP_COLOR_HIGH
	elif ratio > 0.3:
		hp_bar.color = HP_COLOR_MID
	else:
		hp_bar.color = HP_COLOR_LOW

	if _prev_hp < 0:
		hp_bar.size.x = target_w
		hp_ghost.size.x = target_w
		_prev_hp = current
		return

	if current < _prev_hp:
		hp_bar.size.x = target_w
		_kill_tween(_ghost_tween)
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(GHOST_DELAY)
		_ghost_tween.tween_property(hp_ghost, "size:x", target_w, GHOST_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	elif current > _prev_hp:
		_kill_tween(_ghost_tween)
		hp_ghost.size.x = target_w
		_kill_tween(_hp_tween)
		_hp_tween = create_tween()
		_hp_tween.tween_property(hp_bar, "size:x", target_w, HP_TWEEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_prev_hp = current


func update_exp(percent: float) -> void:
	if exp_bar == null:
		return
	exp_bar.size.x = SHORT_BAR_WIDTH * clampf(percent, 0.0, 1.0)


func update_level(lv: int) -> void:
	if level_label:
		level_label.text = "Lv.%d" % lv


func set_dead(is_dead: bool) -> void:
	if death_overlay:
		death_overlay.visible = is_dead
	if bars_container:
		bars_container.visible = not is_dead


func is_expanded() -> bool:
	return false


func toggle_equips() -> void:
	pass


func expand_equips() -> void:
	pass


func play_equip_sequence(slot: String, id: String = "") -> void:
	pass


func collapse_equips() -> void:
	pass


func highlight_slot(slot: String, _id: String = "") -> void:
	pass


func clear_slot_highlights() -> void:
	pass


func show_item_info(_item_id: String) -> void:
	pass


func show_stat_compare(_item_id: String) -> void:
	pass


func hide_stat_compare() -> void:
	pass


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
	_shake_tween.tween_property(content, "position:y", oy - 5.0, 0.08).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_property(content, "position:y", oy, 0.12).set_ease(Tween.EASE_IN)


func _kill_tween(tw: Tween) -> void:
	if tw and tw.is_valid():
		tw.kill()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			card_selected.emit(hero_index)


static func get_target_slots(item_slot: String) -> Array:
	var normalized: String = Hero.normalize_equipment_slot(item_slot)
	if normalized == "acc":
		return ["acc1", "acc2"]
	return [normalized]


func get_slot_global_center(slot: String) -> Vector2:
	var row: Dictionary = equip_rows.get(slot, {})
	if row.is_empty():
		return global_position + size * 0.5
	var panel: PanelContainer = row.get("panel")
	if panel == null:
		return global_position + size * 0.5
	return panel.global_position + panel.size * 0.5
