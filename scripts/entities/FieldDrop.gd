extends Area2D
class_name FieldDrop
## 필드 드롭 오브젝트: 전투 종료 후 필드에 떨어지는 보상
## LOOT_ORB: 초록 오브 — 바닥에 닿자마자 흡수 → 루트 점수 증가
## ITEM / BATTLE_CHEST: 기존 아이템/보물상자 유지

enum DropType { LOOT_ORB, ITEM, BATTLE_CHEST }

const DROP_COLORS := {
	DropType.LOOT_ORB: Color(0.3, 0.9, 0.4),
	DropType.ITEM: Color(0.9, 0.6, 1.0),
	DropType.BATTLE_CHEST: Color(0.95, 0.8, 0.32),
}

const ITEM_TYPE_ICONS: Dictionary = {
	"sword": "🗡️", "dagger": "🔪", "axe": "🪓", "staff": "🪄", "bow": "🏹",
	"shield": "🛡️", "helmet": "⛑️", "light_armor": "👘", "medium_armor": "🦺",
	"heavy_armor": "🛡️", "robe": "👗", "ring": "💍", "necklace": "💍", "shoes": "💍",
	"acc": "💍", "weapon": "⚔️", "head": "👑", "body": "👕"
}

const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.4, 0.8, 0.4),
	"magic": Color(0.4, 0.6, 1.0),
	"rare": Color(0.8, 0.5, 1.0),
	"epic": Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.8, 0.2),
}

const OBJECT_SIZE := 16
const PICKUP_RADIUS := 8.0
const ORB_DROP_HEIGHT_MIN: float = 20.0
const ORB_DROP_HEIGHT_MAX: float = 42.0
const ORB_DROP_TIME: float = 0.24
const ORB_LAND_BOUNCE: float = 4.0
const ORB_LAND_BOUNCE_TIME: float = 0.09
const ORB_HOMING_MAX_SPEED: float = 360.0
const ORB_HOMING_ACCEL: float = 980.0
const ORB_HOMING_COLLECT_DISTANCE: float = 10.0
const ORB_HOMING_MIN_SCALE: float = 0.36

var drop_type: DropType = DropType.LOOT_ORB
var loot_score: int = 0
var gold_amount: int = 0
var item_id: String = ""
var item_type: String = ""
var item_rarity: String = ""
var spawn_delay: float = 0.0
var chest_gold_amount: int = 0
var chest_hp_orbs: int = 0
var chest_item_ids: Array[String] = []

var _collected: bool = false
var _icon_sprite: Sprite2D
var _shadow_sprite: Sprite2D
var _emoji_label: Label = null
var _is_homing: bool = false
var _homing_speed: float = 0.0
var _homing_target: Node2D = null
var _homing_start_distance: float = 1.0
var _homing_start_scale: Vector2 = Vector2.ONE
var _float_tween: Tween = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # party layer
	monitoring = false  # 스폰 애니메이션 후 활성화

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	add_child(shape)

	_shadow_sprite = Sprite2D.new()
	_shadow_sprite.texture = _make_rect_texture(10, 3, Color(0.0, 0.0, 0.0, 0.28))
	_shadow_sprite.centered = true
	_shadow_sprite.position = Vector2(0, 5)
	_shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_shadow_sprite)

	_icon_sprite = Sprite2D.new()
	_icon_sprite.texture = _build_drop_texture()
	_icon_sprite.centered = true
	_icon_sprite.position = Vector2.ZERO
	_icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_icon_sprite)

	body_entered.connect(_on_body_entered)
	call_deferred("_start_drop_sequence")


func _physics_process(_delta: float) -> void:
	if _collected or not _is_homing:
		return
	var target_pos: Vector2 = _get_homing_target_position()
	var to_target: Vector2 = target_pos - global_position
	var dist: float = to_target.length()
	if dist <= ORB_HOMING_COLLECT_DISTANCE:
		collect()
		return
	if dist <= 0.001:
		return
	var homing_t: float = 1.0 - (dist / maxf(1.0, _homing_start_distance))
	var shrink_t: float = clampf(homing_t, 0.0, 1.0)
	var scale_factor: float = lerpf(1.0, ORB_HOMING_MIN_SCALE, shrink_t)
	scale = _homing_start_scale * scale_factor
	_homing_speed = minf(ORB_HOMING_MAX_SPEED, _homing_speed + ORB_HOMING_ACCEL * _delta)
	global_position += to_target.normalized() * _homing_speed * _delta


func _start_drop_sequence() -> void:
	if not is_inside_tree() or _collected:
		return
	var landing_pos: Vector2 = global_position
	var start_pos: Vector2 = landing_pos + Vector2(
		randf_range(-12.0, 12.0),
		-randf_range(ORB_DROP_HEIGHT_MIN, ORB_DROP_HEIGHT_MAX)
	)
	var drop_time: float = ORB_DROP_TIME
	var bounce_height: float = ORB_LAND_BOUNCE
	var bounce_time: float = ORB_LAND_BOUNCE_TIME
	if drop_type == DropType.BATTLE_CHEST:
		start_pos = landing_pos + Vector2(randf_range(-8.0, 8.0), -52.0)
		drop_time = 0.32
		bounce_height = 6.5
		bounce_time = 0.11
	global_position = start_pos
	scale = Vector2(1.18, 1.18) if drop_type == DropType.BATTLE_CHEST else Vector2(0.88, 0.88)
	if _icon_sprite != null:
		_icon_sprite.modulate.a = 0.85

	if spawn_delay > 0.0:
		await get_tree().create_timer(spawn_delay).timeout
		if not is_inside_tree() or _collected:
			return

	var drop_tw := create_tween()
	drop_tw.set_parallel(true)
	drop_tw.tween_property(self, "global_position", landing_pos, drop_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop_tw.tween_property(self, "scale", Vector2.ONE, drop_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _shadow_sprite != null:
		_shadow_sprite.modulate.a = 0.38
		drop_tw.tween_property(_shadow_sprite, "scale", Vector2(1.0, 1.0), drop_time) \
			.from(Vector2(0.65, 0.65))
	await drop_tw.finished
	if not is_inside_tree() or _collected:
		return

	var bounce_tw := create_tween()
	bounce_tw.tween_property(self, "global_position:y", landing_pos.y - bounce_height, bounce_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	bounce_tw.chain().tween_property(self, "global_position:y", landing_pos.y, bounce_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await bounce_tw.finished
	if not is_inside_tree() or _collected:
		return

	# === LOOT_ORB: 바닥에 닿으면 플레이어 쪽으로 호밍 시작 (뱀서 스타일) ===
	if drop_type == DropType.LOOT_ORB:
		_begin_homing_to_party()
		return

	# 아이템/보물상자는 기존 방식 (플레이어가 걸어서 줍기)
	monitoring = true
	_setup_drop_emoji()
	if drop_type == DropType.BATTLE_CHEST:
		_spawn_chest_land_effect()
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _begin_homing_to_party() -> void:
	if _is_homing:
		return
	_homing_target = _resolve_homing_target()
	if _homing_target == null:
		return
	_is_homing = true
	_homing_speed = 90.0
	_homing_start_scale = scale
	_homing_start_distance = maxf(1.0, global_position.distance_to(_get_homing_target_position()))
	if _float_tween != null and is_instance_valid(_float_tween):
		_float_tween.kill()
	if _icon_sprite != null:
		_icon_sprite.position = Vector2.ZERO


func _resolve_homing_target() -> Node2D:
	var leader_nodes: Array = get_tree().get_nodes_in_group("party_leader")
	for node in leader_nodes:
		if node is Node2D and is_instance_valid(node):
			return node as Node2D
	var party_nodes: Array = get_tree().get_nodes_in_group("party")
	for node in party_nodes:
		if node is Node2D and is_instance_valid(node):
			return node as Node2D
	return null


func _get_homing_target_position() -> Vector2:
	if _homing_target == null or not is_instance_valid(_homing_target):
		_homing_target = _resolve_homing_target()
		if _homing_target == null:
			return global_position
	return _homing_target.global_position + Vector2(0.0, -8.0)


func _start_float_anim() -> void:
	if _icon_sprite == null:
		return
	var base_y := _icon_sprite.position.y
	if _float_tween != null and is_instance_valid(_float_tween):
		_float_tween.kill()
	_float_tween = create_tween().set_loops()
	_float_tween.tween_property(_icon_sprite, "position:y", base_y - 3, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_float_tween.tween_property(_icon_sprite, "position:y", base_y, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _setup_drop_emoji() -> void:
	if _emoji_label != null and is_instance_valid(_emoji_label):
		_emoji_label.queue_free()
	_emoji_label = null
	if drop_type != DropType.ITEM:
		_apply_default_shadow_style()
		return

	_apply_item_shadow_style()
	_emoji_label = Label.new()
	_emoji_label.text = _resolve_drop_emoji()
	_emoji_label.add_theme_font_size_override("font_size", 10)
	_emoji_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_emoji_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	_emoji_label.add_theme_constant_override("outline_size", 2)
	_emoji_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emoji_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_emoji_label.position = Vector2(-8.0, -8.0)
	_emoji_label.size = Vector2(16.0, 16.0)
	add_child(_emoji_label)


func _apply_default_shadow_style() -> void:
	if _shadow_sprite == null:
		return
	if drop_type == DropType.BATTLE_CHEST:
		_shadow_sprite.texture = _make_ellipse_texture(20, 8, Color(0.0, 0.0, 0.0, 0.32), Color(0.0, 0.0, 0.0, 0.5))
		_shadow_sprite.position = Vector2(0, 6)
	else:
		_shadow_sprite.texture = _make_rect_texture(10, 3, Color(0.0, 0.0, 0.0, 0.28))
		_shadow_sprite.position = Vector2(0, 5)
	_shadow_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _apply_item_shadow_style() -> void:
	if _shadow_sprite == null:
		return
	var rarity_color: Color = RARITY_COLORS.get(item_rarity, DROP_COLORS[DropType.ITEM])
	var base_color: Color = rarity_color.darkened(0.45)
	var edge_color: Color = rarity_color.lightened(0.05)
	_shadow_sprite.texture = _make_ellipse_texture(18, 7, base_color, edge_color)
	_shadow_sprite.position = Vector2(0, 4)
	_shadow_sprite.modulate = Color(1.0, 1.0, 1.0, 0.95)


func _resolve_drop_emoji() -> String:
	if drop_type == DropType.ITEM:
		if not item_type.is_empty() and ITEM_TYPE_ICONS.has(item_type):
			return str(ITEM_TYPE_ICONS[item_type])
		return "📦"
	return "•"


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if body.is_in_group("party_leader") or body.is_in_group("party"):
		if drop_type == DropType.BATTLE_CHEST:
			_open_battle_chest()
			return
		collect()


func collect() -> void:
	_collected = true
	monitoring = false
	_is_homing = false
	if _float_tween != null and is_instance_valid(_float_tween):
		_float_tween.kill()

	match drop_type:
		DropType.LOOT_ORB:
			_collect_loot_orb()
		DropType.ITEM:
			_collect_item()

	_play_collect_anim()


func _collect_loot_orb() -> void:
	## 루트 오브 흡수 → 골드 획득 + 루트 게이지 점수 증가
	_collected = true
	if gold_amount > 0 and GameManager:
		GameManager.add_gold(gold_amount)
	if loot_score > 0 and BattleManager:
		BattleManager.add_loot_gauge(loot_score)
	if BattleManager:
		var parts: Array[String] = []
		if loot_score > 0:
			parts.append("✦ Loot +%d" % loot_score)
		if gold_amount > 0:
			parts.append("💰 +%d G" % gold_amount)
		if not parts.is_empty():
			BattleManager.battle_log_received.emit(
				" ".join(parts), Color(0.3, 0.9, 0.4)
			)


func _collect_item() -> void:
	var auto_equipped: bool = false

	if InventoryManager:
		auto_equipped = InventoryManager.try_auto_equip(item_id)
		if not auto_equipped:
			InventoryManager.add_item(item_id)


func _open_battle_chest() -> void:
	_collect_battle_chest()
	_play_collect_anim()


func _collect_battle_chest() -> void:
	if _collected:
		return
	_collected = true
	monitoring = false
	_is_homing = false
	if _float_tween != null and is_instance_valid(_float_tween):
		_float_tween.kill()

	if chest_gold_amount > 0 and GameManager:
		GameManager.add_gold(chest_gold_amount)

	var granted_items: Array[String] = []
	for cid in chest_item_ids:
		if cid.is_empty():
			continue
		granted_items.append(cid)
		if InventoryManager:
			var equipped: bool = InventoryManager.try_auto_equip(cid)
			if not equipped:
				InventoryManager.add_item(cid)

	_show_battle_chest_loot_list(granted_items, chest_gold_amount)


func _play_collect_anim() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 20, 0.25) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.25)
	tween.chain().tween_callback(queue_free)


func _build_drop_texture() -> Texture2D:
	var color: Color = DROP_COLORS.get(drop_type, Color.WHITE)
	if drop_type == DropType.ITEM and not item_rarity.is_empty():
		color = RARITY_COLORS.get(item_rarity, color)
	if drop_type == DropType.ITEM:
		return _make_rect_texture(OBJECT_SIZE, OBJECT_SIZE, Color(0, 0, 0, 0))
	if drop_type == DropType.BATTLE_CHEST:
		return _make_chest_texture()

	# LOOT_ORB: 원형 초록 오브
	var img := Image.create(OBJECT_SIZE, OBJECT_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in range(OBJECT_SIZE):
		for x in range(OBJECT_SIZE):
			var px: int = x - OBJECT_SIZE / 2
			var py: int = y - OBJECT_SIZE / 2
			var inside: bool = float(px * px + py * py) <= 36.0
			if not inside:
				continue
			var edge: bool = float(px * px + py * py) >= 28.0
			img.set_pixel(x, y, color.darkened(0.25) if edge else color)

	return ImageTexture.create_from_image(img)


func _make_rect_texture(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _make_ellipse_texture(w: int, h: int, fill: Color, border: Color) -> Texture2D:
	var width: int = maxi(2, w)
	var height: int = maxi(2, h)
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = (float(width) - 1.0) * 0.5
	var cy: float = (float(height) - 1.0) * 0.5
	var rx: float = maxf(1.0, float(width) * 0.5 - 1.0)
	var ry: float = maxf(1.0, float(height) * 0.5 - 1.0)
	for yp in range(height):
		for xp in range(width):
			var nx: float = (float(xp) - cx) / rx
			var ny: float = (float(yp) - cy) / ry
			var d: float = nx * nx + ny * ny
			if d > 1.0:
				continue
			var is_edge: bool = d >= 0.78
			img.set_pixel(xp, yp, border if is_edge else fill)
	return ImageTexture.create_from_image(img)


func _make_chest_texture() -> Texture2D:
	var w: int = 22
	var h: int = 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(6, 17):
		for x in range(2, 20):
			var c := Color(0.69, 0.44, 0.17, 1.0)
			if y <= 9:
				c = Color(0.84, 0.58, 0.23, 1.0)
			if x == 2 or x == 19 or y == 6 or y == 16:
				c = c.darkened(0.24)
			img.set_pixel(x, y, c)
	for y in range(10, 13):
		for x in range(10, 12):
			img.set_pixel(x, y, Color(0.96, 0.86, 0.37, 1.0))
	return ImageTexture.create_from_image(img)


func _spawn_chest_land_effect() -> void:
	var pulse := Sprite2D.new()
	pulse.texture = _make_ellipse_texture(26, 9, Color(1.0, 0.84, 0.35, 0.22), Color(1.0, 0.9, 0.45, 0.42))
	pulse.centered = true
	pulse.position = Vector2(0, 8)
	pulse.z_index = -1
	add_child(pulse)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(pulse, "scale", Vector2(1.45, 1.25), 0.22).from(Vector2(0.75, 0.65))
	tw.tween_property(pulse, "modulate:a", 0.0, 0.22).from(0.9)
	tw.chain().tween_callback(pulse.queue_free)


func _show_battle_chest_loot_list(items: Array[String], gold: int) -> void:
	var lines: Array[String] = []
	if gold > 0:
		lines.append("💰 골드 +%d" % gold)
	for cid in items:
		var cname: String = cid
		if DataManager != null:
			var equip_data: Dictionary = DataManager.get_equipment(cid)
			if not equip_data.is_empty():
				cname = str(equip_data.get("name", cid))
			else:
				var item_data: Dictionary = DataManager.get_item(cid)
				if not item_data.is_empty():
					cname = str(item_data.get("name", cid))
		lines.append("• %s" % cname)
	if lines.is_empty():
		lines.append("획득한 보상이 없습니다.")

	var popup := PanelContainer.new()
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.z_index = 210
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.95, 0.82, 0.42, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = "보물상자 보상\n" + "\n".join(lines)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
	popup.add_child(label)

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(popup)
	popup.global_position = global_position + Vector2(12, -22)
	var tw := popup.create_tween()
	tw.tween_property(popup, "modulate:a", 1.0, 0.08).from(0.0)
	tw.tween_interval(2.1)
	tw.tween_property(popup, "modulate:a", 0.0, 0.22)
	tw.tween_callback(popup.queue_free)
