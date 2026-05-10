class_name Town2Card
extends Button

## Upgrade box for the town2 grid. Two visual flavors:
##   • Stat card (atk_flat / hp_flat)  — simplified red/green panel, no name,
##                                        big "+N" number, no icon. The slot
##                                        stats panel below verifies the buff,
##                                        so the card doesn't need to spell it
##                                        out beyond "ATK" or "HP".
##   • Full card (skills, recruits, monster cards) — cream parchment with
##                                        icon + name + description + cost.
## A "▶" arrow appears on focus, Zelda 2 style.

signal purchase_requested(card: Town2Card, mod: ModifierData)

@onready var _name_label: Label = %CardName
@onready var _desc_label: Label = %CardDesc
@onready var _cost_label: Label = %CardCost
@onready var _arrow: Label = %FocusArrow
@onready var _icon: TextureRect = %CardIcon
## Defaults captured from the .tscn so we can swap to a stat-flavor LabelSettings
## set and back without losing the parchment look.
@onready var _default_name_settings: LabelSettings = _name_label.label_settings
@onready var _default_desc_settings: LabelSettings = _desc_label.label_settings
@onready var _default_cost_settings: LabelSettings = _cost_label.label_settings

## Last-resort icon mapping for non-class modifiers that don't have their own
## .icon set. Class-tagged modifiers fall back to the owner's attack_effect.
const ICON_FALLBACK_BY_ID: Dictionary = {
	&"monster_lure": "res://assets/sprites/enemies/slime.png",
	&"reinforcements": "res://assets/sprites/enemies/slime.png",
	&"recruit": "res://assets/sprites/objects/village.png",
	&"forest_tile": "res://assets/sprites/objects/forest 2.png",
}

## effect_data key → label shown on stat cards.
const STAT_LABEL_BY_KEY: Dictionary = {
	"atk_flat": "ATK",
	"hp_flat": "HP",
	"agi_flat": "AGI",
}

## effect_data key → solid panel color for stat cards. Vibrant on purpose so
## the three stat flavors read instantly against the bright town background.
const STAT_COLOR_BY_KEY: Dictionary = {
	"atk_flat": Color(0.82, 0.2, 0.18),
	"hp_flat": Color(0.22, 0.66, 0.32),
	"agi_flat": Color(0.16, 0.45, 0.85),
}

var data: ModifierData
var purchased: bool = false

var _stat_name_settings: LabelSettings
var _stat_desc_settings: LabelSettings
var _stat_cost_settings: LabelSettings


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	_arrow.visible = false
	_build_stat_settings()
	if data:
		_apply_data()


## Inject the modifier this slot represents. Pass null to render an empty slot
## (pool exhausted) — the box is then disabled and dimmed.
func setup(mod: ModifierData) -> void:
	data = mod
	purchased = false
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data == null:
		_render_empty()
		return
	disabled = false
	focus_mode = Control.FOCUS_ALL
	modulate = Color.WHITE
	var stat_key: String = _stat_card_key()
	if not stat_key.is_empty():
		_apply_stat_layout(stat_key)
	else:
		_apply_default_layout()


func _render_empty() -> void:
	disabled = true
	focus_mode = Control.FOCUS_NONE
	modulate = Color(0.55, 0.55, 0.6, 1)
	_apply_default_layout_chrome()
	_name_label.text = "—"
	_desc_label.text = ""
	_cost_label.text = ""
	_cost_label.visible = false
	_icon.texture = null
	_icon.visible = false


# ─── Stat-flavor layout ───────────────────────────────────────────────
## Returns the effect_data key that drives stat-card styling, or "" if the
## modifier doesn't qualify (i.e. it's a skill, recruit, or world-modifying
## card that needs the full description).
func _stat_card_key() -> String:
	if data == null:
		return ""
	for key in STAT_LABEL_BY_KEY:
		if data.effect_data.has(key):
			return key
	return ""


func _apply_stat_layout(key: String) -> void:
	var amount: int = GameState.modifier_next_int_effect(data, key)
	var stat_name: String = STAT_LABEL_BY_KEY[key]
	var name_text: String = stat_name
	if data.max_level > 1:
		var next_level: int = mini(GameState.modifier_level(data.id) + 1, data.max_level)
		name_text = "%s  %d/%d" % [stat_name, next_level, data.max_level]
	_icon.visible = false
	_name_label.label_settings = _stat_name_settings
	_desc_label.label_settings = _stat_desc_settings
	_cost_label.label_settings = _stat_cost_settings
	_name_label.text = name_text
	_desc_label.text = "+%d" % amount
	_cost_label.text = "%d G" % GameState.modifier_purchase_cost(data)
	_cost_label.visible = true
	_apply_panel_color(STAT_COLOR_BY_KEY[key])


# ─── Default (parchment) layout ───────────────────────────────────────
func _apply_default_layout() -> void:
	_apply_default_layout_chrome()
	_name_label.text = _display_name_with_level()
	_desc_label.text = data.description
	_cost_label.text = "%d G" % GameState.modifier_purchase_cost(data)
	_cost_label.visible = true
	_apply_icon()


## Reset the visual chrome (label settings + panel styleboxes + icon visibility)
## back to the parchment defaults from the .tscn. Called when transitioning
## from a stat layout to a regular card or to the empty state.
func _apply_default_layout_chrome() -> void:
	_icon.visible = true
	_name_label.label_settings = _default_name_settings
	_desc_label.label_settings = _default_desc_settings
	_cost_label.label_settings = _default_cost_settings
	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
	remove_theme_stylebox_override("pressed")
	remove_theme_stylebox_override("focus")


func _build_stat_settings() -> void:
	_stat_name_settings = LabelSettings.new()
	_stat_name_settings.font_size = 14
	_stat_name_settings.font_color = Color.WHITE
	_stat_desc_settings = LabelSettings.new()
	_stat_desc_settings.font_size = 30
	_stat_desc_settings.font_color = Color.WHITE
	_stat_cost_settings = LabelSettings.new()
	_stat_cost_settings.font_size = 11
	_stat_cost_settings.font_color = Color.WHITE


func _apply_panel_color(bg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color.BLACK
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = bg.lightened(0.12)
	var focus: StyleBoxFlat = normal.duplicate()
	focus.bg_color = bg.lightened(0.18)
	focus.border_width_left = 3
	focus.border_width_top = 3
	focus.border_width_right = 3
	focus.border_width_bottom = 3
	focus.border_color = Color(1, 0.78, 0.22, 1)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("focus", focus)


# ─── Icon resolution (default-layout cards only) ──────────────────────
## Surface a small pixel sprite that hints at what the card does. Class-tagged
## modifiers (Heavy Strike, Pilfer, etc.) reuse the owner's attack_effect so
## the icon and the in-battle effect read as the same thing. Non-class cards
## fall back to a hand-curated id→path map. If nothing matches we leave the
## TextureRect visible-but-blank so all four cards stay vertically aligned.
func _apply_icon() -> void:
	_icon.texture = _resolve_icon()
	_icon.visible = true


func _resolve_icon() -> Texture2D:
	if data.icon:
		return data.icon
	if data.required_party_member_id != &"":
		var character: CharacterData = _load_character(data.required_party_member_id)
		if character and character.attack_effect:
			return character.attack_effect
	if data.category == ModifierData.Category.COMPANION:
		var portrait: Texture2D = _build_recruit_portrait(data)
		if portrait:
			return portrait
	var path: String = ICON_FALLBACK_BY_ID.get(data.id, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return null


## Pre-resolved single-companion recruit cards (recruit_mage etc.) carry the
## character directly; older random-pool recruit cards fall back to the first
## still-available pool entry so the offer at least previews someone. Crops a
## head+shoulders square from the idle-down frame so the icon scales 2× cleanly
## to 32×32 instead of fractional-stretching the full 16×24 sprite.
func _build_recruit_portrait(mod: ModifierData) -> Texture2D:
	var character: CharacterData = mod.companion_data
	if character == null and not mod.companion_pool.is_empty():
		for c in mod.companion_pool:
			if c and not GameState.has_party_member(c.id):
				character = c
				break
	if character == null or character.sprite_sheet == null:
		return null
	var fw: int = character.frame_size.x
	var idle_col: int = clampi(1, 0, maxi(0, character.frames_per_direction - 1))
	var atlas := AtlasTexture.new()
	atlas.atlas = character.sprite_sheet
	atlas.region = Rect2(idle_col * fw, 0, fw, fw)
	atlas.filter_clip = true
	return atlas


func _load_character(id: StringName) -> CharacterData:
	var path := "res://data/characters/%s.tres" % id
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as CharacterData


func _display_name_with_level() -> String:
	if data.category == ModifierData.Category.COMPANION or data.max_level <= 1:
		return data.display_name
	var next_level: int = mini(GameState.modifier_level(data.id) + 1, data.max_level)
	return "%s Lv %d/%d" % [data.display_name, next_level, data.max_level]


# ─── Input / state ────────────────────────────────────────────────────
func _on_pressed() -> void:
	if purchased or data == null:
		return
	purchase_requested.emit(self, data)


func _on_focus_entered() -> void:
	_arrow.visible = true


func _on_focus_exited() -> void:
	_arrow.visible = false


func mark_purchased() -> void:
	purchased = true
	disabled = true
	modulate = Color(0.45, 0.45, 0.45, 1)
	_cost_label.text = "OWNED"


func mark_unaffordable_flash() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_cost_label, "modulate", Color(1, 0.3, 0.3, 1), 0.1)
	tween.tween_property(_cost_label, "modulate", Color.WHITE, 0.2)
