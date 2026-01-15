# scripts/battle/BossBattleWindow.gd
# 보스 전용 전투창! 더 크고 화려함!
extends Panel

@onready var boss_name_label = $VBoxContainer/BossName
@onready var boss_hp_bar = $VBoxContainer/BossHP
@onready var boss_hp_text = $VBoxContainer/BossHPText
@onready var party_list = $VBoxContainer/PartyList
@onready var battle_log = $VBoxContainer/BattleLog

var boss_data: Dictionary = {}
var boss_current_hp: int = 0
var boss_max_hp: int = 0
var boss_attack: int = 25
var boss_defense: int = 10
var boss_attack_speed: float = 0.8

var party_data: Array = []
var party_labels: Array = []

var hero_cooldowns: Array = []
var boss_cooldown: float = 0.0

# 보스 특수 공격
var special_cooldown: float = 0.0
var special_interval: float = 8.0

var battle_active: bool = true
var battle_id: String = ""

func _ready():
	print("[BossBattle] Created")

func _process(delta):
	if not battle_active:
		return
	
	update_atb(delta)
	update_special(delta)

func update_atb(delta):
	# 영웅 쿨다운
	for i in range(hero_cooldowns.size()):
		if hero_cooldowns[i] > 0:
			hero_cooldowns[i] -= delta
			if hero_cooldowns[i] <= 0:
				hero_attack(i)
				hero_cooldowns[i] = get_hero_cooldown(i)
	
	# 보스 쿨다운
	if boss_cooldown > 0:
		boss_cooldown -= delta
	else:
		boss_attack_party()
		boss_cooldown = 1.0 / boss_attack_speed
	
	update_ui()

func update_special(delta):
	special_cooldown += delta
	
	if special_cooldown >= special_interval:
		special_cooldown = 0.0
		boss_special_attack()

# ========================================
# 초기화
# ========================================

func init_boss_battle(boss: Dictionary, uid: String):
	battle_id = uid
	boss_data = boss
	party_data = GameManager.party
	
	if boss.has("base_stats"):
		var stats = boss.base_stats
		boss_max_hp = stats.get("hp", 500)
		boss_current_hp = boss_max_hp
		boss_attack = stats.get("attack", 25)
		boss_defense = stats.get("defense", 10)
		boss_attack_speed = stats.get("attack_speed", 0.8)
	
	# 스테이지 배율
	var mult = StageManager.get_enemy_stats_multiplier()
	boss_max_hp = int(boss_max_hp * mult)
	boss_current_hp = boss_max_hp
	boss_attack = int(boss_attack * mult)
	
	# 쿨다운 초기화
	hero_cooldowns.clear()
	for i in range(party_data.size()):
		hero_cooldowns.append(randf_range(0.3, 1.0))
	
	boss_cooldown = 1.0 / boss_attack_speed
	
	create_party_ui()
	update_ui()
	
	log_message("=== BOSS BATTLE START! ===")
	log_message("%s HP: %d" % [boss_data.get("name"), boss_max_hp])

func create_party_ui():
	for child in party_list.get_children():
		child.queue_free()
	party_labels.clear()
	
	for hero in party_data:
		var label = Label.new()
		party_list.add_child(label)
		party_labels.append(label)

func update_ui():
	# 보스 이름
	if boss_name_label:
		boss_name_label.text = "👹 %s 👹" % boss_data.get("name", "BOSS")
	
	# 보스 HP 바
	if boss_hp_bar:
		boss_hp_bar.max_value = boss_max_hp
		boss_hp_bar.value = boss_current_hp
		
		var ratio = float(boss_current_hp) / boss_max_hp
		if ratio > 0.5:
			boss_hp_bar.modulate = Color.RED
		elif ratio > 0.25:
			boss_hp_bar.modulate = Color.ORANGE
		else:
			boss_hp_bar.modulate = Color.DARK_RED
	
	# HP 텍스트
	if boss_hp_text:
		boss_hp_text.text = "%d / %d" % [boss_current_hp, boss_max_hp]
	
	# 파티 업데이트
	for i in range(party_data.size()):
		if i >= party_labels.size():
			continue
		var hero = party_data[i]
		var label = party_labels[i]
		var hp = hero.get("current_hp", hero.base_stats.hp)
		var max_hp = hero.base_stats.hp
		var cd = hero_cooldowns[i] if i < hero_cooldowns.size() else 0.0
		var cd_text = " (%.1f)" % cd if cd > 0 else " ⚔"
		label.text = "%s %d/%d%s" % [hero.name, hp, max_hp, cd_text]

func get_hero_cooldown(idx: int) -> float:
	if idx >= party_data.size():
		return 1.0
	return 1.0 / party_data[idx].base_stats.get("attack_speed", 1.0)

# ========================================
# 전투 로직
# ========================================

func hero_attack(idx: int):
	if idx >= party_data.size():
		return
	var hero = party_data[idx]
	
	if hero.current_hp <= 0:
		return
	
	var damage = max(1, hero.base_stats.get("attack", 10) - boss_defense)
	boss_current_hp -= damage
	
	log_message("%s → %d dmg" % [hero.name, damage])
	
	if boss_current_hp <= 0:
		boss_dies()

func boss_attack_party():
	if party_data.is_empty():
		return
	
	# 살아있는 영웅만
	var alive = []
	for i in range(party_data.size()):
		if party_data[i].current_hp > 0:
			alive.append(i)
	
	if alive.is_empty():
		party_defeated()
		return
	
	var idx = alive[randi() % alive.size()]
	var target = party_data[idx]
	
	var damage = max(1, boss_attack - target.base_stats.get("defense", 5))
	target.current_hp -= damage
	
	log_message("👹 → %s %d dmg (HP:%d)" % [target.name, damage, target.current_hp])
	
	if target.current_hp <= 0:
		hero_dies(idx)

func boss_special_attack():
	log_message("⚠️ BOSS SPECIAL ATTACK! ⚠️")
	
	# 전체 공격!
	for hero in party_data:
		if hero.current_hp <= 0:
			continue
		
		var damage = max(1, int(boss_attack * 0.5) - hero.base_stats.get("defense", 5))
		hero.current_hp -= damage
		
		log_message("  → %s %d dmg" % [hero.name, damage])
		
		if hero.current_hp <= 0:
			var idx = party_data.find(hero)
			hero_dies(idx)

# ========================================
# 승리/패배
# ========================================

func boss_dies():
	battle_active = false
	
	log_message("")
	log_message("=== BOSS DEFEATED! ===")
	
	# 보스 보상 (일반 적의 5배!)
	var exp = 100
	var gold = randi_range(100, 200)
	
	GameManager.add_exp(exp)
	GameManager.add_gold(gold)
	GameManager.on_enemy_killed()
	
	log_message("+%d EXP" % exp)
	log_message("+%d Gold" % gold)
	
	# 무조건 아이템 드랍!
	show_item_choice()

func show_item_choice():
	var choice_ui = preload("res://scenes/ui/ItemChoiceUI.tscn").instantiate()
	
	var canvas = get_tree().root.get_node_or_null("BattleCanvas")
	if canvas:
		canvas.add_child(choice_ui)
	
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	choice_ui.position = Vector2(
		viewport_size.x / 2 - 200,
		viewport_size.y / 2 - 150
	)
	
	# 보스는 더 좋은 아이템!
	var items = get_boss_drop_items()
	choice_ui.show_choices(items)
	
	choice_ui.item_selected.connect(_on_item_choice_made)
	choice_ui.choice_skipped.connect(_on_item_choice_skipped)

func get_boss_drop_items() -> Array:
	# 보스는 Magic 이상 아이템만!
	var all_items = []
	
	if DataManager.items.has("items"):
		for item_id in DataManager.items.items:
			var item = DataManager.items.items[item_id]
			if not item.get("enabled", true):
				continue
			var rarity = item.get("rarity", "common")
			if rarity in ["magic", "unique", "legendary"]:
				all_items.append(item)
	
	all_items.shuffle()
	
	var result = []
	var selected_ids = []
	for item in all_items:
		if result.size() >= 3:
			break
		if item.id not in selected_ids:
			result.append(item)
			selected_ids.append(item.id)
	
	return result

func _on_item_choice_made(item_id: String):
	EventBus.battle_victory.emit()
	close_window()

func _on_item_choice_skipped():
	EventBus.battle_victory.emit()
	close_window()

func hero_dies(idx: int):
	if idx >= party_data.size():
		return
	var hero = party_data[idx]
	log_message("💀 %s defeated!" % hero.name)
	
	hero.current_hp = 0
	hero_cooldowns[idx] = 999999
	
	var alive_count = 0
	for h in party_data:
		if h.current_hp > 0:
			alive_count += 1
	
	if alive_count == 0:
		party_defeated()

func party_defeated():
	battle_active = false
	log_message("")
	log_message("=== DEFEAT ===")
	EventBus.battle_defeat.emit()
	StageManager.trigger_game_over()
	close_window()

func close_window():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()

# ========================================
# 로그
# ========================================

func log_message(msg: String):
	print("[BossBattle] %s" % msg)
	if battle_log:
		battle_log.text += msg + "\n"
		# 스크롤 아래로
		await get_tree().process_frame
		battle_log.scroll_vertical = battle_log.get_line_count()
