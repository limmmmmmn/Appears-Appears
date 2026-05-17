class_name LevelUpPanel
extends Control

signal modifier_chosen(member_index: int, modifier: ModifierData)

const CARD_SCENE: PackedScene = preload("res://scenes/ui/town_card.tscn")

const STAT_CARD_BG: Color = Color(1.0, 1.0, 1.0, 0.86)
const STAT_CARD_BORDER: Color = Color(0.16, 0.24, 0.34, 0.95)
const STAT_NAME_COLOR: Color = Color(0.11, 0.2, 0.31, 1.0)
const STAT_TEXT_COLOR: Color = Color(0.06, 0.08, 0.1, 1.0)
const STAT_ACCENT_COLOR: Color = Color(0.64, 0.23, 0.14, 1.0)

@onready var _title_label: Label = %TitleLabel
@onready var _party_stats: HBoxContainer = %PartyStats
@onready var _cards: HBoxContainer = %Cards

var _member_index: int = -1
var _member_name: String = ""
var _offers: Array[ModifierData] = []
var _pending_setup: bool = false


func setup(member_index: int, member_name: String, offers: Array[ModifierData]) -> void:
	_member_index = member_index
	_member_name = member_name
	_offers = offers.duplicate()
	if is_inside_tree():
		_apply()
	else:
		_pending_setup = true


func _ready() -> void:
	if _pending_setup:
		_pending_setup = false
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _apply() -> void:
	_title_label.text = "%s 레벨업 — 카드를 고르세요" % _member_name
	_rebuild_party_stats()
	for child in _cards.get_children():
		child.queue_free()
	for mod: ModifierData in _offers:
		var card: TownCard = CARD_SCENE.instantiate()
		card.custom_minimum_size = Vector2(108, 138)
		_cards.add_child(card)
		card.setup(mod, true)
		card.purchase_requested.connect(_on_card_pressed)
	if _cards.get_child_count() > 0:
		(_cards.get_child(0) as Control).call_deferred("grab_focus")


func _on_card_pressed(_card: TownCard, mod: ModifierData) -> void:
	modifier_chosen.emit(_member_index, mod)
	queue_free()


func _rebuild_party_stats() -> void:
	for child in _party_stats.get_children():
		child.queue_free()
	for i in GameState.party_size():
		_party_stats.add_child(_build_party_stat_card(i))


func _build_party_stat_card(index: int) -> Control:
	var member: CharacterData = GameState.party[index]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(140, 74)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = STAT_CARD_BG
	style.border_color = STAT_CARD_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "%s  Lv %d" % [member.display_name, GameState.party_level(index)]
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", STAT_NAME_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	vbox.add_child(title)

	var hp: int = GameState.party_hp[index] if index < GameState.party_hp.size() else 0
	var mp: int = GameState.party_mp[index] if index < GameState.party_mp.size() else 0
	var damage: String = GameState.damage_range_text(GameState.effective_attack(index))
	_add_stat_line(vbox, "HP %d/%d   MP %d/%d" % [
		hp,
		GameState.effective_max_hp(index),
		mp,
		GameState.effective_max_mp(index),
	])
	_add_stat_line(vbox, "DMG %s   ATK %d" % [damage, GameState.effective_attack(index)], true)
	_add_stat_line(vbox, "DEF %d   AGI %d" % [
		GameState.effective_defense(index),
		GameState.effective_agility(index),
	])
	_add_stat_line(vbox, "CRIT %d%%   CDMG %d%%" % [
		int(round(GameState.effective_crit_chance(index) * 100.0)),
		int(round(GameState.effective_crit_damage_mult(index) * 100.0)),
	])
	return card


func _add_stat_line(parent: VBoxContainer, text: String, accent: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", STAT_ACCENT_COLOR if accent else STAT_TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
