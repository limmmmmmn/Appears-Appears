extends Control
class_name HeroCard
## 파티 카드: 세로 레이아웃 (하단 중앙 가로 배열용)
## 상단: 이름+레벨 / 중앙: 초상화(HP 오버레이) / 하단: ATB 바 + EXP 바

const FACE_CHIP_PATH := "res://assets/sprites/heroes/%s.png"

const FACE_SIZE := 56
const CARD_WIDTH := FACE_SIZE
const NAME_HEIGHT := 14
const ATB_AREA_HEIGHT := 12
const EXP_BAR_HEIGHT := 3
const ATB_BAR_HEIGHT := 5
const ATB_BAR_SPACING := 2
const CARD_PADDING := 4

const CARD_TOTAL_HEIGHT := NAME_HEIGHT + FACE_SIZE + CARD_PADDING + ATB_AREA_HEIGHT + 2 + EXP_BAR_HEIGHT + CARD_PADDING

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
const HP_OVERLAY_COLOR := Color(0.85, 0.12, 0.12, 0.55)
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

const EXPANDED_EXTRA_HEIGHT := 152.0
const EXPAND_DURATION := 0.28
const COLLAPSE_DURATION := 0.22

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)
signal card_selected(hero_index: int)

var hero_index: int = -1
var hero_id: String = ""
var _hero_ref: Hero = null
var hp_reference: int = 100

var content: Control
var name_label: Label
var level_label: Label
var face_container: Control
var placeholder: ColorRect
var face_chip: TextureRect
var hp_overlay: ColorRect
var death_overlay: ColorRect
var skull_label: Label
var atb_container: Control
var skill_bar_bgs: Array[ColorRect] = []
var skill_bar_fills: Array[ColorRect] = []
var skill_bar_skill_ids: Array[String] = []
var exp_bar_bg: ColorRect
var exp_bar: ColorRect

var equip_panel: PanelContainer
var equip_rows: Dictionary = {}
var _row_style_normal: StyleBoxFlat
var _row_style_highlight: StyleBoxFlat
var _is_expanded: bool = false

var _cached_max_hp: int = 0
var _prev_hp: int = -1
var _prev_hp_ratio: float = 1.0
var _hp_tween: Tween
var _ghost_tween: Tween
var _shake_tween: Tween
var _expand_tween: Tween
var _is_selected: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_TOTAL_HEIGHT)
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_build_ui()
	queue_redraw()


func _build_ui() -> void:
	content = Control.new()
	content.position = Vector2.ZERO
	content.size = Vector2(CARD_WIDTH, CARD_TOTAL_HEIGHT)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(content)

	_build_face_area()
	_build_name_row()
	_build_atb_area()
	_build_exp_bar()


func _build_name_row() -> void:
	var name_y: float = FACE_SIZE - 3
	var name_row := Control.new()
	name_row.position = Vector2(0, name_y)
	name_row.size = Vector2(CARD_WIDTH, NAME_HEIGHT)
	name_row.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(name_row)

	name_label = Label.new()
	name_label.position = Vector2(1, 0)
	name_label.size = Vector2(CARD_WIDTH - 2, NAME_HEIGHT)
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	name_row.add_child(name_label)

	level_label = Label.new()
	level_label.position = Vector2(0, 0)
	level_label.size = Vector2(CARD_WIDTH - 1, NAME_HEIGHT)
	level_label.add_theme_font_size_override("font_size", 7)
	level_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.65, 0.8))
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.text = "Lv.1"
	level_label.mouse_filter = MOUSE_FILTER_IGNORE
	name_row.add_child(level_label)


func _build_face_area() -> void:
	var face_y: float = 0

	face_container = Control.new()
	face_container.position = Vector2(0, face_y)
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

	hp_overlay = ColorRect.new()
	hp_overlay.position = Vector2(0, 0)
	hp_overlay.size = Vector2(FACE_SIZE, 0)
	hp_overlay.color = HP_OVERLAY_COLOR
	hp_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	face_container.add_child(hp_overlay)

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


func _build_atb_area() -> void:
	var atb_y: float = FACE_SIZE + NAME_HEIGHT + CARD_PADDING
	atb_container = Control.new()
	atb_container.position = Vector2(0, atb_y)
	atb_container.size = Vector2(CARD_WIDTH, ATB_AREA_HEIGHT)
	atb_container.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(atb_container)


func _build_exp_bar() -> void:
	var exp_y: float = FACE_SIZE + NAME_HEIGHT + CARD_PADDING + ATB_AREA_HEIGHT + 2
	exp_bar_bg = _make_rect(Vector2(0, exp_y), Vector2(CARD_WIDTH, EXP_BAR_HEIGHT), BAR_BG_COLOR)
	content.add_child(exp_bar_bg)
	exp_bar = _make_rect(Vector2(0, exp_y), Vector2(0, EXP_BAR_HEIGHT), EXP_BAR_COLOR)
	content.add_child(exp_bar)


func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


func init(p_hero_index: int) -> void:
	hero_index = p_hero_index


func _draw() -> void:
	if not _is_selected:
		return
	var border_rect := Rect2(
		Vector2(-1, -1),
		Vector2(FACE_SIZE + 2, FACE_SIZE + 2)
	)
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
	_rebuild_skill_atb_rows(hero)
	update_hp(hero.current_hp, hero.get_max_hp())
	update_skill_atb_bars(hero)
	update_exp(hero.get_exp_ratio())
	update_level(hero.level)
	update_name(hero.hero_name)
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


func update_name(hero_name: String) -> void:
	if name_label:
		name_label.text = hero_name


func update_hp(current: int, max_hp: int) -> void:
	if hp_overlay == null:
		return
	_cached_max_hp = max_hp
	var ratio: float = clampf(float(current) / float(max_hp), 0.0, 1.0) if max_hp > 0 else 1.0
	var damage_ratio: float = 1.0 - ratio
	var overlay_height: float = FACE_SIZE * damage_ratio
	var target_y: float = FACE_SIZE - overlay_height

	if _prev_hp < 0:
		hp_overlay.position.y = target_y
		hp_overlay.size = Vector2(FACE_SIZE, overlay_height)
		_prev_hp = current
		_prev_hp_ratio = ratio
		return

	if damage_ratio > 0.001:
		if ratio > 0.6:
			hp_overlay.color = Color(HP_OVERLAY_COLOR.r, HP_OVERLAY_COLOR.g, HP_OVERLAY_COLOR.b, 0.3)
		elif ratio > 0.3:
			hp_overlay.color = Color(HP_OVERLAY_COLOR.r, HP_OVERLAY_COLOR.g * 0.5, HP_OVERLAY_COLOR.b, 0.45)
		else:
			hp_overlay.color = HP_OVERLAY_COLOR
	else:
		hp_overlay.color = Color(HP_OVERLAY_COLOR.r, HP_OVERLAY_COLOR.g, HP_OVERLAY_COLOR.b, 0.0)

	_kill_tween(_hp_tween)
	_hp_tween = create_tween()
	_hp_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hp_tween.set_parallel(true)
	_hp_tween.tween_property(hp_overlay, "position:y", target_y, HP_TWEEN_DURATION)
	_hp_tween.tween_property(hp_overlay, "size:y", overlay_height, HP_TWEEN_DURATION)

	_prev_hp = current
	_prev_hp_ratio = ratio


func update_exp(percent: float) -> void:
	if exp_bar == null:
		return
	exp_bar.size.x = CARD_WIDTH * clampf(percent, 0.0, 1.0)


func update_level(lv: int) -> void:
	if level_label:
		level_label.text = "Lv.%d" % lv


func _rebuild_skill_atb_rows(hero: Hero) -> void:
	if atb_container == null or hero == null:
		return
	var skills: Array[String] = []
	for skill_any in hero.get_available_skills():
		skills.append(str(skill_any))
	if skills.is_empty():
		skills.append("basic_attack")

	if skills == skill_bar_skill_ids:
		return

	skill_bar_skill_ids = skills
	for child in atb_container.get_children():
		child.queue_free()
	skill_bar_bgs.clear()
	skill_bar_fills.clear()

	var bar_count: int = mini(skill_bar_skill_ids.size(), 2)
	var total_h: float = bar_count * ATB_BAR_HEIGHT + maxi(0, bar_count - 1) * ATB_BAR_SPACING
	var start_y: float = maxf(0.0, floorf((ATB_AREA_HEIGHT - total_h) * 0.5))

	for i in range(bar_count):
		var skill_id: String = skill_bar_skill_ids[i]
		var y: float = start_y + i * (ATB_BAR_HEIGHT + ATB_BAR_SPACING)
		var bg := _make_rect(Vector2(0, y), Vector2(CARD_WIDTH, ATB_BAR_HEIGHT), BAR_BG_COLOR)
		bg.tooltip_text = _get_skill_atb_tooltip(skill_id)
		atb_container.add_child(bg)
		skill_bar_bgs.append(bg)

		var fill := _make_rect(Vector2(0, y), Vector2(0, ATB_BAR_HEIGHT), Color(0.35, 0.65, 1.0))
		fill.tooltip_text = _get_skill_atb_tooltip(skill_id)
		atb_container.add_child(fill)
		skill_bar_fills.append(fill)


func update_skill_atb_bars(hero: Hero) -> void:
	if hero == null:
		return
	_rebuild_skill_atb_rows(hero)
	for i in range(mini(skill_bar_skill_ids.size(), skill_bar_fills.size())):
		var skill_id: String = skill_bar_skill_ids[i]
		var ratio: float = _get_skill_atb_ratio(hero, skill_id)
		var fill: ColorRect = skill_bar_fills[i]
		fill.size.x = CARD_WIDTH * clampf(ratio, 0.0, 1.0)
		fill.color = _get_skill_atb_color(hero, skill_id, ratio)


func _get_skill_atb_ratio(hero: Hero, skill_id: String) -> float:
	var action_delay: float = maxf(0.001, hero.get_action_delay())
	var loop_ratio: float = clampf(hero.action_timer / action_delay, 0.0, 1.0)
	var has_active_battle: bool = BattleManager != null and BattleManager.get_active_battle_count() > 0
	if skill_id == "basic_attack":
		return loop_ratio

	var skill_delay: float = maxf(0.001, hero.get_skill_action_delay())
	var skill_ratio: float = clampf(hero.skill_action_timer / skill_delay, 0.0, 1.0)
	if CooldownManager == null:
		return skill_ratio
	var cd_ratio: float = clampf(1.0 - CooldownManager.get_cooldown_percent(hero.id, skill_id), 0.0, 1.0)
	if not has_active_battle and cd_ratio >= 0.999:
		return skill_ratio
	return minf(skill_ratio, cd_ratio)


func _get_skill_atb_color(hero: Hero, skill_id: String, ratio: float) -> Color:
	if skill_id != "basic_attack" and hero.has_method("is_skill_enabled") and not hero.is_skill_enabled(skill_id):
		return Color(0.35, 0.35, 0.4, 0.9)
	if ratio >= 0.999:
		return Color(0.25, 0.9, 0.35, 0.95)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_type: String = str(skill_data.get("type", "physical"))
	if skill_type == "magic":
		return Color(0.45, 0.65, 1.0, 0.95)
	if skill_type == "heal":
		return Color(0.35, 0.9, 0.75, 0.95)
	return Color(0.95, 0.65, 0.35, 0.95)


func _get_skill_atb_tooltip(skill_id: String) -> String:
	var data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = str(data.get("name", skill_id))
	return "%s ATB" % skill_name


func set_dead(is_dead: bool) -> void:
	if death_overlay:
		death_overlay.visible = is_dead
	if atb_container:
		atb_container.visible = not is_dead
	if exp_bar_bg:
		exp_bar_bg.visible = not is_dead
	if exp_bar:
		exp_bar.visible = not is_dead


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
