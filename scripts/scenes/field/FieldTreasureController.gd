extends RefCounted
class_name FieldTreasureController

const FIELD_OBJECT_SIZE := 16
const TREASURE_KEY_ITEM_ID: String = "treasure_key"
const TREASURE_REWARD_RARITIES: Array[String] = ["uncommon", "magic", "rare"]

var host: Node2D = null
var reward_window_scene: PackedScene = null
var close_blocking_ui: Callable = Callable()
var show_notice: Callable = Callable()

var field_treasure_chests: Array[Dictionary] = []
var reward_window_layer: CanvasLayer = null
var reward_window = null
var pending_treasure_chest_index: int = -1
var treasure_interact_cooldown: float = 0.0
var sanctuary_root: Node2D = null
var sanctuary_tick_timer: float = 0.0


func setup(
	p_host: Node2D,
	p_reward_window_scene: PackedScene,
	p_close_blocking_ui: Callable,
	p_show_notice: Callable
) -> void:
	host = p_host
	reward_window_scene = p_reward_window_scene
	close_blocking_ui = p_close_blocking_ui
	show_notice = p_show_notice


func spawn_field_treasure_chests(
	is_test_field: bool,
	is_boss_field: bool,
	bounds: Rect2,
	chest_ratios: Array[Vector2],
	locked_chest_index: int,
	world_object_z: int
) -> void:
	field_treasure_chests.clear()
	if not is_test_field or is_boss_field:
		return
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	_ensure_reward_window()
	for i in range(chest_ratios.size()):
		var ratio: Vector2 = chest_ratios[i]
		var locked: bool = (i == locked_chest_index)
		var pos := bounds.position + bounds.size * ratio
		_create_treasure_chest(i, pos, locked, world_object_z)

	_show_notice("보물상자 1개가 배치되었습니다.", 1.6, Color(0.98, 0.9, 0.65))


func spawn_sanctuary(
	is_test_field: bool,
	bounds: Rect2,
	spawn_ratio: Vector2,
	world_object_z: int,
	heal_interval: float,
	heal_radius: float
) -> void:
	if not is_test_field:
		return
	if sanctuary_root != null and is_instance_valid(sanctuary_root):
		return
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	sanctuary_root = Node2D.new()
	sanctuary_root.name = "Sanctuary"
	sanctuary_root.position = bounds.position + bounds.size * spawn_ratio
	sanctuary_root.z_index = world_object_z
	host.add_child(sanctuary_root)

	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = _build_field_object_texture("sanctuary")
	sanctuary_root.add_child(sprite)

	var sanctuary_area := Area2D.new()
	sanctuary_area.name = "SanctuaryArea"
	sanctuary_area.monitoring = true
	sanctuary_area.monitorable = true
	sanctuary_area.collision_layer = 1
	sanctuary_area.collision_mask = 2
	sanctuary_root.add_child(sanctuary_area)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = heal_radius
	shape.shape = circle
	sanctuary_area.add_child(shape)

	sanctuary_tick_timer = heal_interval
	_show_notice("성소를 발견했다. 가까이 가면 HP/MP가 회복된다.", 1.5, Color(0.64, 0.9, 1.0))


func update(
	delta: float,
	party_leader: Node2D,
	heal_radius: float,
	heal_interval: float,
	hp_per_tick: int,
	world_effect_z: int
) -> void:
	treasure_interact_cooldown = maxf(0.0, treasure_interact_cooldown - delta)
	_poll_treasure_chest_interaction(party_leader)
	_update_sanctuary(delta, party_leader, heal_radius, heal_interval, hp_per_tick, world_effect_z)


func get_treasure_chests() -> Array[Dictionary]:
	return field_treasure_chests


func get_sanctuary_root() -> Node2D:
	return sanctuary_root


func is_reward_window_visible() -> bool:
	return reward_window != null and is_instance_valid(reward_window) and bool(reward_window.visible)


func _build_field_object_texture(kind: String) -> Texture2D:
	var img := Image.create(FIELD_OBJECT_SIZE, FIELD_OBJECT_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match kind:
		"treasure", "treasure_locked", "treasure_opened":
			for y in range(5, 14):
				for x in range(2, 14):
					var c := Color(0.62, 0.38, 0.12, 1.0)
					if y <= 7:
						c = Color(0.74, 0.46, 0.16, 1.0)
					if x == 2 or x == 13 or y == 5 or y == 13:
						c = c.darkened(0.22)
					img.set_pixel(x, y, c)
			if kind == "treasure_locked":
				for y in range(8, 11):
					for x in range(7, 9):
						img.set_pixel(x, y, Color(1.0, 0.86, 0.3, 1.0))
			elif kind == "treasure_opened":
				for y in range(3, 6):
					for x in range(2, 14):
						var oc := Color(0.72, 0.44, 0.16, 1.0)
						if x == 2 or x == 13 or y == 3 or y == 5:
							oc = oc.darkened(0.25)
						img.set_pixel(x, y, oc)
				for y in range(8, 12):
					for x in range(6, 10):
						img.set_pixel(x, y, Color(0.67, 1.0, 0.78, 1.0))
		"sanctuary":
			for y in range(3, 14):
				for x in range(6, 10):
					var c := Color(0.56, 0.78, 0.88, 1.0)
					if x == 6 or x == 9 or y == 3 or y == 13:
						c = c.darkened(0.22)
					img.set_pixel(x, y, c)
			for y in range(12, 15):
				for x in range(3, 13):
					var b := Color(0.45, 0.6, 0.68, 1.0)
					if x == 3 or x == 12 or y == 12 or y == 14:
						b = b.darkened(0.25)
					img.set_pixel(x, y, b)
			for y in range(1, 4):
				for x in range(6, 10):
					img.set_pixel(x, y, Color(0.35, 0.9, 1.0, 1.0))
		_:
			for y in range(2, 14):
				for x in range(2, 14):
					img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0))

	return ImageTexture.create_from_image(img)


func _make_colored_rect_texture(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _ensure_reward_window() -> void:
	if reward_window != null and is_instance_valid(reward_window):
		return
	if reward_window_scene == null or host == null:
		return

	if reward_window_layer == null or not is_instance_valid(reward_window_layer):
		reward_window_layer = CanvasLayer.new()
		reward_window_layer.layer = 170
		reward_window_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		host.add_child(reward_window_layer)

	reward_window = reward_window_scene.instantiate()
	if reward_window == null:
		return
	reward_window.name = "RewardWindow"
	if not reward_window.item_selected.is_connected(_on_treasure_loot_selected):
		reward_window.item_selected.connect(_on_treasure_loot_selected)
	reward_window_layer.add_child(reward_window)


func _create_treasure_chest(chest_index: int, world_pos: Vector2, is_locked: bool, world_object_z: int) -> void:
	if host == null:
		return
	var root := Node2D.new()
	root.name = "TreasureChest_%d" % chest_index
	root.position = world_pos
	root.z_index = world_object_z
	host.add_child(root)

	var icon := Sprite2D.new()
	icon.name = "Icon"
	icon.centered = true
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _build_field_object_texture("treasure_locked" if is_locked else "treasure")
	root.add_child(icon)

	var area := Area2D.new()
	area.name = "ContactArea"
	area.monitoring = true
	area.monitorable = true
	area.collision_layer = 1
	area.collision_mask = 2
	root.add_child(area)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	shape.position = Vector2.ZERO
	area.add_child(shape)

	if not area.body_entered.is_connected(_on_treasure_chest_body_entered.bind(chest_index)):
		area.body_entered.connect(_on_treasure_chest_body_entered.bind(chest_index))

	field_treasure_chests.append({
		"index": chest_index,
		"root": root,
		"icon": icon,
		"area": area,
		"locked": is_locked,
		"opened": false,
	})


func _on_treasure_chest_body_entered(body: Node2D, chest_index: int) -> void:
	if body == null or not body.is_in_group("party_leader"):
		return
	if chest_index < 0 or chest_index >= field_treasure_chests.size():
		return
	if pending_treasure_chest_index >= 0:
		return
	if is_reward_window_visible():
		return

	var chest: Dictionary = field_treasure_chests[chest_index]
	if bool(chest.get("opened", false)):
		return

	if bool(chest.get("locked", false)):
		if InventoryManager == null or not InventoryManager.has_item(TREASURE_KEY_ITEM_ID, 1):
			_show_notice("잠겨 있다. 보물상자 열쇠가 필요하다.", 1.5, Color(1.0, 0.72, 0.72))
			return
		InventoryManager.remove_item(TREASURE_KEY_ITEM_ID, 1)
		_show_notice("열쇠를 사용해 잠긴 상자를 열었다.", 1.4, Color(0.82, 1.0, 0.86))

	_open_treasure_chest(chest_index)


func _poll_treasure_chest_interaction(party_leader: Node2D) -> void:
	if party_leader == null:
		return
	if treasure_interact_cooldown > 0.0:
		return
	if field_treasure_chests.is_empty():
		return

	for i in range(field_treasure_chests.size()):
		var chest: Dictionary = field_treasure_chests[i]
		if bool(chest.get("opened", false)):
			continue
		var root: Node2D = chest.get("root") as Node2D
		if root == null:
			continue
		if party_leader.global_position.distance_to(root.global_position) <= 24.0:
			treasure_interact_cooldown = 0.25
			_on_treasure_chest_body_entered(party_leader, i)
			return


func _open_treasure_chest(chest_index: int) -> void:
	if chest_index < 0 or chest_index >= field_treasure_chests.size():
		return
	if close_blocking_ui.is_valid():
		close_blocking_ui.call()

	var chest: Dictionary = field_treasure_chests[chest_index]
	if bool(chest.get("opened", false)):
		return

	chest["opened"] = true
	field_treasure_chests[chest_index] = chest

	var icon: Sprite2D = chest.get("icon") as Sprite2D
	if icon:
		icon.texture = _build_field_object_texture("treasure_opened")
	var area: Area2D = chest.get("area") as Area2D
	if area:
		area.set_deferred("monitoring", false)

	var choices: Array[String] = _roll_treasure_reward_choices(3)
	if choices.is_empty():
		_show_notice("보상 풀이 비어 있다.", 1.2, Color(1.0, 0.75, 0.75))
		return

	pending_treasure_chest_index = chest_index
	_ensure_reward_window()
	if reward_window and is_instance_valid(reward_window):
		reward_window.set_title("Reward")
		reward_window.call_deferred("show_loot_selection", choices)
	else:
		_grant_treasure_reward(choices[0])
		pending_treasure_chest_index = -1


func _roll_treasure_reward_choices(count: int) -> Array[String]:
	var pool: Array[String] = DataManager.get_equipment_by_rarities(TREASURE_REWARD_RARITIES)
	if pool.is_empty():
		return []

	pool.shuffle()
	var result: Array[String] = []
	for equip_id in pool:
		result.append(str(equip_id))
		if result.size() >= count:
			break

	while result.size() < count:
		result.append(str(pool[randi() % pool.size()]))

	return result


func _on_treasure_loot_selected(item_id: String) -> void:
	var target_hero_id: String = ""
	if reward_window != null and is_instance_valid(reward_window) and reward_window.has_method("get_selected_hero_id"):
		target_hero_id = str(reward_window.call("get_selected_hero_id"))
	_grant_treasure_reward(item_id, target_hero_id)
	pending_treasure_chest_index = -1

	if _are_all_treasure_chests_opened():
		_show_notice("필드의 보물상자를 모두 열었다.", 1.6, Color(1.0, 0.9, 0.65))


func _grant_treasure_reward(item_id: String, target_hero_id: String = "") -> void:
	if item_id.is_empty():
		return
	if InventoryManager == null:
		return

	var added: bool = InventoryManager.add_item(item_id, 1)
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	if not added:
		_show_notice("보상을 획득하지 못했다. 인벤토리 확인 필요", 1.4, Color(1.0, 0.75, 0.75))
		return

	var equipped: bool = false
	var hero_name: String = ""
	if not target_hero_id.is_empty() and PartyManager:
		var hero: Hero = PartyManager.get_hero_by_id(target_hero_id)
		if hero != null and InventoryManager:
			hero_name = hero.hero_name
			equipped = InventoryManager.equip_item(hero, item_id, "")

	if not equipped and InventoryManager:
		equipped = InventoryManager.try_auto_equip(item_id)
		if equipped and PartyManager:
			var equipped_hero: Hero = _find_hero_equipped_item(item_id)
			if equipped_hero != null:
				hero_name = equipped_hero.hero_name

	if equipped:
		if hero_name.is_empty():
			_show_notice("획득: %s + 자동 장착 완료" % item_name, 1.5, Color(0.82, 1.0, 0.86))
		else:
			_show_notice("획득: %s + %s 자동 장착" % [item_name, hero_name], 1.5, Color(0.82, 1.0, 0.86))
	else:
		_show_notice("획득: %s" % item_name, 1.4, Color(0.88, 0.96, 1.0))
	if SaveManager:
		SaveManager.auto_save("보물상자 개봉")


func _find_hero_equipped_item(item_id: String) -> Hero:
	if item_id.is_empty() or not PartyManager:
		return null
	for hero_any in PartyManager.get_party():
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		for slot in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
			if str(hero.equipment.get(slot, "")) == item_id:
				return hero
	return null


func _are_all_treasure_chests_opened() -> bool:
	if field_treasure_chests.is_empty():
		return false
	for chest in field_treasure_chests:
		var chest_dict: Dictionary = chest as Dictionary
		if not bool(chest_dict.get("opened", false)):
			return false
	return true


func _update_sanctuary(
	delta: float,
	party_leader: Node2D,
	heal_radius: float,
	heal_interval: float,
	hp_per_tick: int,
	world_effect_z: int
) -> void:
	if sanctuary_root == null or not is_instance_valid(sanctuary_root):
		return
	if party_leader == null:
		return

	var dist: float = party_leader.global_position.distance_to(sanctuary_root.global_position)
	if dist > heal_radius:
		sanctuary_tick_timer = heal_interval
		return

	sanctuary_tick_timer -= delta
	if sanctuary_tick_timer > 0.0:
		return
	sanctuary_tick_timer = heal_interval

	var healed_total: int = 0
	if PartyManager:
		var party: Array = PartyManager.get_party()
		for hero_any in party:
			var hero: Hero = hero_any as Hero
			if hero == null or hero.is_dead:
				continue
			healed_total += hero.heal(hp_per_tick)
		PartyManager.party_changed.emit()

	_spawn_sanctuary_particle(Color(1.0, 0.45, 0.65, 0.95), world_effect_z)
	_spawn_sanctuary_particle(Color(0.35, 0.75, 1.0, 0.95), world_effect_z)

	if healed_total > 0 and BattleManager:
		BattleManager.party_hp_changed.emit()


func _spawn_sanctuary_particle(color: Color, world_effect_z: int) -> void:
	if sanctuary_root == null or not is_instance_valid(sanctuary_root) or host == null:
		return
	var particle := Sprite2D.new()
	particle.centered = true
	particle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particle.texture = _make_colored_rect_texture(4, 4, color)
	particle.global_position = sanctuary_root.global_position + Vector2(
		randf_range(-6.0, 6.0),
		randf_range(-6.0, 2.0)
	)
	particle.z_index = world_effect_z
	host.add_child(particle)

	var start_pos: Vector2 = particle.global_position
	var tween := particle.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		particle,
		"global_position",
		start_pos + Vector2(randf_range(-4.0, 4.0), -12.0),
		0.45
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(particle, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(particle.queue_free)


func _show_notice(message: String, duration: float, color: Color) -> void:
	if show_notice.is_valid():
		show_notice.call(message, duration, color)
