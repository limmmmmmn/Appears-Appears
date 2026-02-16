extends Area2D
class_name FieldDrop
## 필드 드롭 오브젝트: 전투 종료 후 필드에 떨어지는 보상
## 플레이어가 위를 지나가면 수집

enum DropType { GOLD, ITEM, HP_ORB }

const DROP_ICONS := {
	DropType.GOLD: "🪙",
	DropType.ITEM: "📦",
	DropType.HP_ORB: "💗",
}
const DROP_COLORS := {
	DropType.GOLD: Color(1.0, 0.9, 0.3),
	DropType.ITEM: Color(0.9, 0.6, 1.0),
	DropType.HP_ORB: Color(1.0, 0.4, 0.6),
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
const HP_PER_ORB := 10

var drop_type: DropType = DropType.GOLD
var gold_amount: int = 0
var item_id: String = ""
var item_type: String = ""
var item_rarity: String = ""
var heal_amount: int = HP_PER_ORB
var spawn_delay: float = 0.0

var _collected: bool = false
var _icon_sprite: Sprite2D
var _shadow_sprite: Sprite2D


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

	# 즉시 활성화 (스폰 애니메이션 없음)
	monitoring = true
	_start_float_anim()
	# 스폰 직후 이미 위에 서 있는 경우 체크
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _start_float_anim() -> void:
	if _icon_sprite == null:
		return
	var base_y := _icon_sprite.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(_icon_sprite, "position:y", base_y - 3, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_icon_sprite, "position:y", base_y, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if body.is_in_group("party_leader") or body.is_in_group("party"):
		collect()


func collect() -> void:
	_collected = true
	monitoring = false

	match drop_type:
		DropType.GOLD:
			_collect_gold()
		DropType.ITEM:
			_collect_item()
		DropType.HP_ORB:
			_collect_hp()

	_play_collect_anim()


func _collect_gold() -> void:
	if GameManager:
		GameManager.add_gold(gold_amount)
	if BattleManager:
		BattleManager.battle_log_received.emit(
			"💰 Gold +%d" % gold_amount, Color(1.0, 0.9, 0.3)
		)


func _collect_item() -> void:
	var auto_equipped: bool = false

	if InventoryManager:
		auto_equipped = InventoryManager.try_auto_equip(item_id)
		if not auto_equipped:
			InventoryManager.add_item(item_id)

	var edata: Dictionary = DataManager.get_equipment(item_id) if DataManager else {}
	var item_name: String = edata.get("name", item_id)
	if BattleManager:
		BattleManager.battle_log_received.emit(
			"🎁 %s 획득!" % item_name, Color(0.9, 0.6, 1.0)
		)


func _collect_hp() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	var actual_total := 0
	for hero in party:
		if hero == null or hero.is_dead:
			continue
		if hero.current_hp >= hero.get_max_hp():
			continue
		var actual: int = hero.heal(heal_amount)
		actual_total += actual
	if PartyManager:
		PartyManager.party_changed.emit()
	# 항상 팝업 표시 (만피여도 연출)
	_spawn_heal_popups()
	if actual_total > 0 and BattleManager:
		BattleManager.battle_log_received.emit(
			"💗 파티 전체 HP +%d" % actual_total, Color(0.4, 1.0, 0.4)
		)


func _spawn_heal_popups() -> void:
	## 필드 파티원 머리 위에 "+10" 초록색 팝업 연출
	_spawn_restore_popups("+%d" % heal_amount, Color(0.3, 1.0, 0.3))


func _spawn_restore_popups(text: String, color: Color) -> void:
	## 필드 파티원 머리 위에 팝업 연출
	var field_members: Array = get_tree().get_nodes_in_group("party")

	for member in field_members:
		if not is_instance_valid(member) or not member is Node2D:
			continue
		var member_2d: Node2D = member as Node2D
		var popup := Label.new()
		popup.text = text
		popup.add_theme_font_size_override("font_size", 10)
		popup.add_theme_color_override("font_color", color)
		popup.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		popup.add_theme_constant_override("outline_size", 3)
		popup.z_index = 100
		popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup.position = member_2d.global_position + Vector2(-10, -20)
		get_tree().current_scene.add_child(popup)

		var start_y: float = popup.position.y
		var tween := popup.create_tween()
		tween.set_parallel(true)
		tween.tween_property(popup, "position:y", start_y - 20.0, 0.6) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(popup, "modulate:a", 0.0, 0.6) \
			.set_ease(Tween.EASE_IN).set_delay(0.3)
		tween.chain().tween_callback(popup.queue_free)


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

	var img := Image.create(OBJECT_SIZE, OBJECT_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in range(OBJECT_SIZE):
		for x in range(OBJECT_SIZE):
			var px: int = x - OBJECT_SIZE / 2
			var py: int = y - OBJECT_SIZE / 2
			var inside: bool = false
			match drop_type:
				DropType.GOLD, DropType.HP_ORB:
					inside = float(px * px + py * py) <= 36.0
				DropType.ITEM:
					inside = x >= 3 and x <= 12 and y >= 3 and y <= 12
				_:
					inside = x >= 4 and x <= 11 and y >= 4 and y <= 11

			if not inside:
				continue

			var edge: bool = false
			match drop_type:
				DropType.GOLD, DropType.HP_ORB:
					edge = float(px * px + py * py) >= 28.0
				DropType.ITEM:
					edge = x == 3 or x == 12 or y == 3 or y == 12
				_:
					edge = false

			img.set_pixel(x, y, color.darkened(0.25) if edge else color)

	return ImageTexture.create_from_image(img)


func _make_rect_texture(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
