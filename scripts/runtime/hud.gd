class_name HUD
extends CanvasLayer

## macOS-dock-styled bottom bar.
## Each party member is one app-icon-style box (rounded square + face crop +
## per-character background color), with a thin HP bar floating above.
## A vertical divider separates party from gold readout, like Dock vs Trash.

const SLOT_COUNT: int = 4

# Width budget — every part of the dock has a fixed slot here so the panel
# can resize itself smoothly as the party grows.
const SIDE_PADDING: float = 8.0
const SECTION_GAP: float = 6.0      ## space between slots / divider / gold
const FIELD_WIDTH: float = 38.0
const SLOT_WIDTH: float = 20.0
const SLOT_GAP: float = 4.0
const DIVIDER_WIDTH: float = 1.0
const GOLD_WIDTH: float = 36.0

const PANEL_HEIGHT: float = 26.0
const PANEL_BOTTOM_MARGIN: float = 8.0

# How many pixels of the sprite frame's top to keep for the icon's "face".
# 24-tall sprites cleanly show head + shoulders in the top ~14px.
const FACE_CROP_HEIGHT: int = 14

@onready var _party_panel: Panel = $BottomBar
@onready var _field_label: Label = %FieldLabel
@onready var _slots_container: HBoxContainer = %SlotsContainer
@onready var _gold_label: Label = %GoldLabel

var _slots: Array[Control] = []
var _icon_boxes: Array[Panel] = []
var _portraits: Array[TextureRect] = []
var _hp_bars: Array[ProgressBar] = []


func _ready() -> void:
	_collect_slot_refs()
	# Child _ready() runs before Main._ready() in Godot, so the party may not
	# be set up yet at this point. Listen for party_changed and (re)populate
	# whenever the roster lands.
	EventBus.party_changed.connect(_populate_from_game_state)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.stage_started.connect(_on_stage_started)
	_populate_from_game_state()
	_refresh_field_label()
	_gold_label.text = "%d G" % GameState.gold


func _collect_slot_refs() -> void:
	for i in SLOT_COUNT:
		var slot: Control = _slots_container.get_child(i)
		_slots.append(slot)
		_hp_bars.append(slot.get_node("HPBar") as ProgressBar)
		var icon_box: Panel = slot.get_node("IconBox") as Panel
		_icon_boxes.append(icon_box)
		_portraits.append(icon_box.get_node("Portrait") as TextureRect)


func _populate_from_game_state() -> void:
	var visible_count: int = mini(GameState.party_size(), SLOT_COUNT)
	_resize_dock(visible_count)
	for i in SLOT_COUNT:
		var has_member: bool = i < visible_count
		_slots[i].visible = has_member
		if not has_member:
			continue
		var member: CharacterData = GameState.party[i]
		_portraits[i].texture = _build_face_portrait(member)
		_apply_icon_color(i, member)
		_set_hp_ratio(i, GameState.party_hp[i], GameState.effective_max_hp(i))
		_slots[i].modulate = Color.WHITE


## Recompute the dock width so it hugs the visible slots — no empty padding
## when only the leader is alive, but room for all four when fully recruited.
func _resize_dock(member_count: int) -> void:
	var slot_count: int = maxi(1, member_count)
	var slots_width: float = slot_count * SLOT_WIDTH + maxi(0, slot_count - 1) * SLOT_GAP
	var content_width: float = (
		FIELD_WIDTH
		+ SECTION_GAP + DIVIDER_WIDTH
		+ SECTION_GAP + slots_width
		+ SECTION_GAP + DIVIDER_WIDTH
		+ SECTION_GAP + GOLD_WIDTH
	)
	var total_width: float = SIDE_PADDING * 2.0 + content_width
	_party_panel.offset_left = -total_width * 0.5
	_party_panel.offset_right = total_width * 0.5
	_party_panel.offset_top = -PANEL_HEIGHT - PANEL_BOTTOM_MARGIN
	_party_panel.offset_bottom = -PANEL_BOTTOM_MARGIN


## Crop the top portion of the idle frame (col 1, row 0 = facing down) so
## only head + shoulders show in the icon — like an avatar crop.
func _build_face_portrait(member: CharacterData) -> AtlasTexture:
	if member.sprite_sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = member.sprite_sheet
	var fw: int = member.frame_size.x
	var fh: int = member.frame_size.y
	var crop_h: int = mini(fh, FACE_CROP_HEIGHT)
	atlas.region = Rect2(fw, 0, fw, crop_h)
	return atlas


## Stable random color per character (hash of id). Same character = same
## color across runs, so the player learns "blue square = mage" intuitively.
func _apply_icon_color(index: int, member: CharacterData) -> void:
	var hash_value: int = abs(int(member.id.hash()))
	var hue: float = float(hash_value % 360) / 360.0
	var color: Color = Color.from_hsv(hue, 0.55, 0.78, 1.0)
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = color
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	stylebox.anti_aliasing = false
	_icon_boxes[index].add_theme_stylebox_override("panel", stylebox)


func _set_hp_ratio(index: int, current: int, max_hp: int) -> void:
	if index < 0 or index >= _hp_bars.size():
		return
	if max_hp <= 0:
		_hp_bars[index].value = 0.0
		return
	_hp_bars[index].value = clampf(float(current) / float(max_hp), 0.0, 1.0)


# ─── Signal handlers ──────────────────────────────────────────────────
func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= SLOT_COUNT or index >= _hp_bars.size():
		return
	_set_hp_ratio(index, new_hp, max_hp)
	if new_hp <= 0:
		_slots[index].modulate = Color(0.4, 0.4, 0.4, 1.0)
	else:
		_slots[index].modulate = Color.WHITE


func _on_gold_changed(new_gold: int) -> void:
	_gold_label.text = "%d G" % new_gold


func _on_stage_started(_stage_num: int) -> void:
	_refresh_field_label()


func _refresh_field_label() -> void:
	_field_label.text = "Field %d" % maxi(1, GameState.current_stage)
