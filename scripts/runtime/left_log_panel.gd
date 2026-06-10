class_name LeftLogPanel
extends Control

## Dark-Room-style running log on the lower-left. Game events (placing enemies /
## structures, milestones, narration) print a line here. Lines ACCUMULATE — newest at
## the BOTTOM, older ones pushed up and scrolling off the top. Achromatic + minimal so
## it reads as ambient narration, distinct from the colored placement dock above it.
##
## Fiction: a being arranges this world to wring power out of the hero — these lines
## are that being noting what it just set in motion.
##
## To add a new logged event: connect its EventBus signal in _connect_events() and
## call add_line("..."). The catalog below is intentionally tiny + easy to grow.

const MAX_LINES: int = 200                              ## safety cap (oldest pruned)
const FADE_LINES: int = 9                               ## newest N fade IN toward bottom
const FADE_FLOOR: float = 0.55                          ## oldest visible line alpha (still readable)
const LINE_COLOR: Color = Color(0.09, 0.13, 0.19, 1.0)  ## dark ink (reads on the bright desktop wallpaper)

## A RichTextLabel handles wrap + auto-scroll natively (a ScrollContainer+VBox of
## autowrap Labels collapses to ~1 char wide). It's authored in the scene now (edit
## its font/position in the editor); lines are kept here for dedup/fade and the bbcode
## is rebuilt on each change.
@onready var _log: RichTextLabel = %Log
var _lines: PackedStringArray = []  ## oldest → newest; every line kept (no merging)


func _ready() -> void:
	add_to_group("game_log")
	# Position/size are AUTHORED in the scene (move/resize it in the editor → it sticks).
	# Code no longer computes the rect, so editor and game match and edits don't get
	# overridden.
	_log.text = ""  # clear the authored preview text at runtime
	_connect_events()


func _connect_events() -> void:
	EventBus.world_started.connect(func() -> void: add_line("세계가 깨어난다."))
	EventBus.enemy_place_requested.connect(_on_enemy_placed)
	EventBus.structure_placed.connect(_on_structure_placed)
	EventBus.building_built.connect(_on_building_built)
	EventBus.tier_available.connect(_on_tier_available)
	EventBus.objet_acquired.connect(_on_objet_acquired)
	EventBus.companion_recruited.connect(_on_companion_recruited)
	EventBus.party_member_leveled_up.connect(_on_member_leveled)
	EventBus.party_split_learned.connect(func() -> void: add_line("따로 다니기를 배웠다."))
	EventBus.party_group_limit_changed.connect(_on_group_limit_changed)
	EventBus.member_group_changed.connect(_on_member_group_changed)
	# Mirror one-off narration into the running log so story beats accumulate too.
	EventBus.narration.connect(add_line)


# ─── Event → line ──────────────────────────────────────────────────────
func _on_enemy_placed(tier_id: StringName) -> void:
	var nm: String = _tier_name(tier_id)
	add_line("%s%s 풀어놓았다." % [nm, _eul(nm)])


func _on_structure_placed(tile_id: StringName) -> void:
	var nm: String = _tile_name(tile_id)
	add_line("%s%s 세웠다." % [nm, _eul(nm)])


func _on_building_built(id: StringName) -> void:
	var nm: String = _building_name(id)
	add_line("%s%s 세웠다." % [nm, _eul(nm)])


func _on_tier_available(tier_id: StringName) -> void:
	var nm: String = _tier_name(tier_id)
	add_line("%s%s 이 세계에 나타날 수 있게 되었다." % [nm, _i(nm)])


func _on_objet_acquired(id: StringName) -> void:
	var nm: String = _tile_name(id)
	add_line("%s%s 손에 넣었다." % [nm, _eul(nm)])


func _on_companion_recruited(id: StringName) -> void:
	var nm: String = _companion_name(id)
	add_line("%s%s 합류했다." % [nm, _i(nm)])


func _on_member_leveled(index: int, new_level: int) -> void:
	add_line("%s, 레벨 %d." % [_member_name(index), new_level])


func _on_member_group_changed(index: int, group: int) -> void:
	var nm: String = _member_name(index)
	if group == 0:
		add_line("%s%s 대열로 돌아왔다." % [nm, _i(nm)])
	else:
		add_line("%s%s 제%d파티로 갈라져 나왔다." % [nm, _i(nm), group + 1])


func _on_group_limit_changed(new_limit: int) -> void:
	add_line("이제 파티를 %d개까지 나눌 수 있다." % new_limit)


# ─── Log buffer ────────────────────────────────────────────────────────
## Every line is kept and stacked — repeats are NOT merged (they just pile up).
func add_line(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_lines.append(text)
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	_render()


## Rebuild the bbcode: newest line (bottom) full opacity, older lines fade up toward
## FADE_FLOOR — the Dark-Room "fading history" look, flipped so new prints at the bottom.
func _render() -> void:
	var n: int = _lines.size()
	var parts: PackedStringArray = []
	for i in n:
		var from_bottom: int = n - 1 - i  # 0 = newest
		var a: float = FADE_FLOOR
		if from_bottom < FADE_LINES:
			a = lerpf(1.0, FADE_FLOOR, float(from_bottom) / float(FADE_LINES))
		var col: Color = LINE_COLOR
		col.a = a
		parts.append("[color=#%s]%s[/color]" % [col.to_html(true), _lines[i]])
	_log.text = "\n".join(parts)
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	# scroll_following keeps us pinned, but nudge the bar after layout to be safe.
	await get_tree().process_frame
	if is_instance_valid(_log):
		var bar := _log.get_v_scroll_bar()
		if bar != null:
			bar.value = bar.max_value


# ─── Name lookups + Korean particle helpers ────────────────────────────
func _tier_name(id: StringName) -> String:
	return str(Balance.tier_by_id(id).get("name", id))


func _tile_name(id: StringName) -> String:
	var d: Dictionary = Balance.tile_by_id(id)
	if d.is_empty():
		d = Balance.building_by_id(id)
	return str(d.get("name", id))


func _building_name(id: StringName) -> String:
	return str(Balance.building_by_id(id).get("name", id))


func _companion_name(id: StringName) -> String:
	return str(Balance.companion_by_id(id).get("name", id))


func _member_name(index: int) -> String:
	if index >= 0 and index < GameState.party_size() and GameState.party[index] != null:
		return GameState.party[index].display_name
	return "용사"


## Has a final consonant (받침)? Drives the 을/를, 이/가 choice for natural lines.
func _has_batchim(word: String) -> bool:
	if word.is_empty():
		return false
	var c: int = word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return false  # not a Korean syllable → default to no-batchim form
	return (c - 0xAC00) % 28 != 0


func _eul(word: String) -> String:
	return "을" if _has_batchim(word) else "를"


func _i(word: String) -> String:
	return "이" if _has_batchim(word) else "가"
