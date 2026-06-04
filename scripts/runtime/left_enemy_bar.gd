class_name LeftEnemyBar
extends Control

## Left placement panel — DOS-style list. Gold lives in the HUD chip above; this is
## the sectioned placement list below it:
##     ── 적 ──        [sprite] name  price   (click → place / claim)
##     ── 이벤트 ──     [sprite] 모닥불 price   (click → place on map)
## A free "rescue slime" row appears at the top when the run is deadlocked.

const BONFIRE_TEX: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const SHRINE_TEX: Texture2D = preload("res://assets/sprites/objects/shrine.png")

const PANEL_X: float = 4.0
const PANEL_TOP: float = 36.0     ## below the menu bar + gold chip (floats over the field now)
const PANEL_W: float = UITheme.LEFT_PANEL_WIDTH   ## smaller floating dock

var _box: PanelContainer
var _list: VBoxContainer
var _rows: Array[Dictionary] = []          ## {button, kind, id}
var _built_signature: String = ""
var _was_deadlocked: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	custom_minimum_size = Vector2(PANEL_W + PANEL_X * 2.0, 360.0)
	offset_right = PANEL_W + PANEL_X * 2.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("placement_panel")
	_rebuild()
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.tier_unlocked.connect(_on_changed.unbind(1))
	EventBus.campfire_placed.connect(_on_changed)
	EventBus.building_built.connect(_on_changed.unbind(1))
	EventBus.world_started.connect(_on_changed)
	EventBus.player_named.connect(_on_changed.unbind(1))
	set_process(true)


func _on_changed() -> void:
	_refresh()


func _process(_delta: float) -> void:
	# Cheap deadlock poll (queries the field for live enemies / fights / loot).
	var dl: bool = _is_deadlocked()
	if dl != _was_deadlocked:
		_was_deadlocked = dl
		if dl:
			EventBus.rescue_offered.emit()
		_rebuild()


# ─── Build ─────────────────────────────────────────────────────────────
func _refresh() -> void:
	if _signature() != _built_signature:
		_rebuild()
	else:
		_refresh_affordability()


func _rebuild() -> void:
	if _box != null:
		_box.queue_free()
	_rows.clear()
	_built_signature = _signature()

	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", DOS.box_style())
	_box.position = Vector2(PANEL_X, PANEL_TOP)
	_box.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_box.size = Vector2(PANEL_W, 0.0)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_box.add_child(_list)

	# Opening: just the "초원 깔기" row until the world starts.
	if not GameState.world_started:
		if GameState.name_entered:
			_list.add_child(DOS.section("시작"))
			_add_row(&"grass", &"grass", "초원 깔기", "", null, true)
		return

	if _was_deadlocked:
		_list.add_child(DOS.section("구제"))
		_add_row(&"rescue", &"slime", "구제 슬라임", "무료", _tier_sprite(&"slime"), true)

	# ── 적 ── (TOGGLE auto-spawn — hands stay free for flipping reward cards)
	_list.add_child(DOS.section("적"))
	var any_enemy: bool = false
	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		var id: StringName = tier["id"]
		if not GameState.is_tier_visible(id):
			continue
		any_enemy = true
		if GameState.is_tier_unlock_available(id):
			_add_row(&"enemy", id, str(tier.get("name", "?")), "해금!", _tier_sprite(id), true, Color(1.0, 0.85, 0.35, 1.0))
		else:
			var on: bool = GameState.is_tier_active(id)
			_add_row(&"enemy", id, str(tier.get("name", "?")), ("● ON" if on else "○ OFF"), _tier_sprite(id), true,
				Color(0.45, 0.85, 0.45, 1.0) if on else DOS.DIM)
	if not any_enemy:
		_list.add_child(DOS.label("(잠김)", DOS.DIM))

	# ── 이벤트 ──
	_list.add_child(DOS.section("이벤트"))
	var fire_cost: int = GameState.campfire_upgrade_cost() if GameState.campfire_placed else GameState.campfire_place_cost()
	var fire_label: String = "모닥불↑" if GameState.campfire_placed else "모닥불"
	_add_row(&"campfire", &"campfire", fire_label, "%dG" % fire_cost, BONFIRE_TEX, GameState.gold >= fire_cost)
	if GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary"):
		var s_cost: int = GameState.building_cost(&"sanctuary")
		_add_row(&"sanctuary", &"sanctuary", "성소", "%dG" % s_cost, SHRINE_TEX, GameState.gold >= s_cost)


## One DOS row: [sprite] name … tag. `affordable` dims the row when false; the
## right-hand tag (price / ON·OFF) can take its own color.
func _add_row(kind: StringName, id: StringName, name_text: String, price_text: String, sprite: Texture2D, affordable: bool, price_color: Color = DOS.TEXT) -> void:
	var b := Button.new()
	DOS.style_button(b)
	b.custom_minimum_size = Vector2(0.0, DOS.ROW_H)
	b.pressed.connect(_on_row_pressed.bind(kind, id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(DOS.icon(sprite))
	var name_lbl := DOS.label(name_text)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	row.add_child(name_lbl)
	row.add_child(DOS.label(price_text, price_color if affordable else DOS.DIM))
	b.modulate = Color(1, 1, 1, 1) if affordable else Color(0.6, 0.62, 0.66, 1.0)
	_list.add_child(b)
	_rows.append({"button": b, "kind": kind, "id": id})


func _refresh_affordability() -> void:
	for row: Dictionary in _rows:
		var b: Button = row["button"]
		if not is_instance_valid(b):
			continue
		b.modulate = Color(1, 1, 1, 1) if _row_affordable(row["kind"], row["id"]) else Color(0.6, 0.62, 0.66, 1.0)


func _row_affordable(kind: StringName, id: StringName) -> bool:
	match kind:
		&"grass", &"rescue": return true
		&"enemy": return true  # toggle / claim — always clickable (no per-spawn cost)
		&"campfire":
			var c: int = GameState.campfire_upgrade_cost() if GameState.campfire_placed else GameState.campfire_place_cost()
			return GameState.gold >= c
		&"sanctuary": return GameState.gold >= GameState.building_cost(&"sanctuary")
	return true


# ─── Click handlers (unchanged placement logic) ────────────────────────
func _on_row_pressed(kind: StringName, id: StringName) -> void:
	match kind:
		&"grass": GameState.start_world()
		&"rescue": GameState.place_rescue_slime()
		&"enemy":
			if GameState.is_tier_unlocked(id):
				GameState.toggle_tier(id)   # ON/OFF auto-spawn (no per-spawn cost)
			else:
				GameState.unlock_tier(id)
		&"campfire":
			if GameState.campfire_placed:
				GameState.upgrade_campfire()
			else:
				GameState.place_campfire()
		&"sanctuary":
			if GameState.can_purchase_building(&"sanctuary"):
				GameState.purchase_building(&"sanctuary")


# ─── Deadlock detection (gold 0, nothing in progress) ──────────────────
func _is_deadlocked() -> bool:
	if not GameState.world_started:
		return false
	if GameState.gold >= GameState.tier_place_cost(&"slime"):
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if not tree.get_nodes_in_group("field_enemy").is_empty():
		return false
	if not tree.get_nodes_in_group("field_pickup").is_empty():
		return false
	var bm: Node = tree.get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("pending_window_count") and int(bm.pending_window_count()) > 0:
		return false  # a live fight OR an unflipped reward card → not stuck
	return true


# ─── Helpers ───────────────────────────────────────────────────────────
## A signature of everything that changes the LIST STRUCTURE (not just prices), so
## we only rebuild when rows appear/disappear; otherwise just re-tint affordability.
func _signature() -> String:
	var parts: PackedStringArray = []
	parts.append("w%d" % (1 if GameState.world_started else 0))
	parts.append("n%d" % (1 if GameState.name_entered else 0))
	parts.append("d%d" % (1 if _was_deadlocked else 0))
	parts.append("f%d" % (1 if GameState.campfire_placed else 0))
	parts.append("s%d" % (1 if (GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary")) else 0))
	for i in Balance.tier_count():
		var id: StringName = Balance.tier_at(i)["id"]
		if GameState.is_tier_visible(id):
			parts.append("%s%d%d" % [id, 1 if GameState.is_tier_unlock_available(id) else 0, 1 if GameState.is_tier_active(id) else 0])
	return "|".join(parts)


func _tier_sprite(id: StringName) -> Texture2D:
	var data: EnemyData = GameState.tier_enemy_data(id)
	return data.sprite if data != null else null
