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
	"heavy_armor": "🛡️", "robe": "👗", "ring": "💍", "necklace": "📿", "shoes": "👟",
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

const PICKUP_RADIUS := 12.0
const HP_PER_ORB := 10

var drop_type: DropType = DropType.GOLD
var gold_amount: int = 0
var item_id: String = ""
var item_type: String = ""
var item_rarity: String = ""
var heal_amount: int = HP_PER_ORB
var spawn_delay: float = 0.0

var _collected: bool = false
var _label: Label
var _shadow: Label


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # party layer
	monitoring = false  # 스폰 애니메이션 후 활성화

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	add_child(shape)

	# 그림자
	_shadow = Label.new()
	_shadow.text = "●"
	_shadow.add_theme_font_size_override("font_size", 6)
	_shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.3))
	_shadow.position = Vector2(-3, -2)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	# 아이콘
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.position = Vector2(-8, -18)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 드롭 타입별 아이콘 및 색상 설정
	match drop_type:
		DropType.GOLD:
			_label.text = "🪙"
		DropType.ITEM:
			if not item_type.is_empty():
				_label.text = ITEM_TYPE_ICONS.get(item_type, "📦")
			else:
				_label.text = "📦"
			if not item_rarity.is_empty():
				_label.self_modulate = RARITY_COLORS.get(item_rarity, Color.WHITE)
		DropType.HP_ORB:
			_label.text = "💗"
		_:
			_label.text = "?"

	add_child(_label)

	body_entered.connect(_on_body_entered)

	# 즉시 활성화 (스폰 애니메이션 없음)
	monitoring = true
	_start_float_anim()
	# 스폰 직후 이미 위에 서 있는 경우 체크
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _start_float_anim() -> void:
	var base_y := _label.position.y
	var tween := create_tween().set_loops()
	tween.tween_property(_label, "position:y", base_y - 3, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_label, "position:y", base_y, 0.5) \
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
	# 골드 → HUD 골드 표시로 날아가는 연출
	var target: Vector2 = _get_gold_label_screen_pos()
	if target != Vector2.ZERO:
		_spawn_fly_icon("🪙", Color(1.0, 0.9, 0.3), target)
	if BattleManager:
		BattleManager.battle_log_received.emit(
			"💰 Gold +%d" % gold_amount, Color(1.0, 0.9, 0.3)
		)


func _collect_item() -> void:
	var auto_equipped: bool = false
	var equipped_hero_idx: int = -1

	if InventoryManager:
		auto_equipped = InventoryManager.try_auto_equip(item_id)
		if auto_equipped:
			equipped_hero_idx = _find_equipped_hero_index(item_id)
		else:
			InventoryManager.add_item(item_id)

	# 아이콘/색상
	var icon: String = ITEM_TYPE_ICONS.get(item_type, "📦")
	var color: Color = RARITY_COLORS.get(item_rarity, Color.WHITE)

	# 날아가는 연출
	if auto_equipped and equipped_hero_idx >= 0:
		# 자동 장착 → 해당 히어로 카드로 날아감
		var target: Vector2 = _get_hero_card_screen_pos(equipped_hero_idx)
		if target != Vector2.ZERO:
			_spawn_fly_icon(icon, color, target)
	else:
		# 인벤토리로 → 인벤토리 카드로 날아감
		var target: Vector2 = _get_inventory_card_screen_pos()
		if target != Vector2.ZERO:
			_spawn_fly_icon(icon, color, target)

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
	var field_members: Array = get_tree().get_nodes_in_group("party")

	for member in field_members:
		if not is_instance_valid(member) or not member is Node2D:
			continue
		var member_2d: Node2D = member as Node2D
		# 부모(Field)에 직접 추가하여 캐릭터 이동 영향 안 받게
		var popup := Label.new()
		popup.text = "+%d" % heal_amount
		popup.add_theme_font_size_override("font_size", 10)
		popup.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
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


#region 날아가는 아이콘 연출
func _spawn_fly_icon(icon_text: String, icon_color: Color, target_screen_pos: Vector2) -> void:
	## 드롭 위치에서 UI 대상으로 날아가는 아이콘 연출
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * global_position

	var hud_nodes: Array = get_tree().get_nodes_in_group("field_hud")
	if hud_nodes.is_empty():
		return
	var hud: Node = hud_nodes[0]

	var fly := Label.new()
	fly.text = icon_text
	fly.add_theme_font_size_override("font_size", 14)
	fly.add_theme_color_override("font_color", icon_color)
	fly.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fly.add_theme_constant_override("outline_size", 2)
	fly.z_index = 200
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.position = screen_pos
	fly.pivot_offset = Vector2(8, 8)
	hud.add_child(fly)

	# 위로 팝 → 포물선으로 목표 도달
	fly.scale = Vector2(1.5, 1.5)
	var tween := fly.create_tween()

	# Phase 1: 위로 떠오름 (0.15초)
	tween.set_parallel(true)
	tween.tween_property(fly, "position:y", screen_pos.y - 30.0, 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(fly, "scale", Vector2(1.0, 1.0), 0.15) \
		.set_ease(Tween.EASE_OUT)

	# Phase 2: 포물선으로 목표 (0.35초)
	tween.chain()
	tween.set_parallel(true)
	tween.tween_property(fly, "position:x", target_screen_pos.x, 0.35) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(fly, "position:y", target_screen_pos.y, 0.35) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(fly, "scale", Vector2(0.5, 0.5), 0.35) \
		.set_ease(Tween.EASE_IN)

	tween.chain().tween_callback(fly.queue_free)


func _get_gold_label_screen_pos() -> Vector2:
	var hud_nodes: Array = get_tree().get_nodes_in_group("field_hud")
	if hud_nodes.is_empty():
		return Vector2.ZERO
	var hud: FieldHUD = hud_nodes[0] as FieldHUD
	if hud == null:
		return Vector2.ZERO
	if hud.gold_label and is_instance_valid(hud.gold_label):
		return hud.gold_label.get_global_rect().get_center()
	return Vector2.ZERO


func _get_hero_card_screen_pos(hero_idx: int) -> Vector2:
	var hud_nodes: Array = get_tree().get_nodes_in_group("field_hud")
	if hud_nodes.is_empty():
		return Vector2.ZERO
	var hud: FieldHUD = hud_nodes[0] as FieldHUD
	if hud == null or hud.bottom_party_cards == null:
		return Vector2.ZERO
	var bpc: BottomPartyCards = hud.bottom_party_cards
	if hero_idx < bpc.cards.size():
		var card: HeroCard = bpc.cards[hero_idx]
		if card and is_instance_valid(card):
			return card.get_global_rect().get_center()
	return Vector2.ZERO


func _get_inventory_card_screen_pos() -> Vector2:
	var hud_nodes: Array = get_tree().get_nodes_in_group("field_hud")
	if hud_nodes.is_empty():
		return Vector2.ZERO
	var hud: FieldHUD = hud_nodes[0] as FieldHUD
	if hud == null or hud.bottom_party_cards == null:
		return Vector2.ZERO
	var inv_card = hud.bottom_party_cards.inventory_card
	if inv_card and is_instance_valid(inv_card):
		return inv_card.get_global_rect().get_center()
	return Vector2.ZERO


func _find_equipped_hero_index(p_item_id: String) -> int:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		var hero = party[i]
		if hero == null:
			continue
		for slot in hero.equipment:
			if hero.equipment[slot] == p_item_id:
				return i
	return -1
#endregion
