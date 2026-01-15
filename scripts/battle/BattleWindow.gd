# scripts/battle/BattleWindow.gd
extends Panel

@onready var enemy_name_label = $VBoxContainer/EnemyName
@onready var enemy_hp_bar = $VBoxContainer/EnemyHP
@onready var party_list = $VBoxContainer/PartyList

var enemy_data: Dictionary = {}
var enemy_current_hp: int = 0
var enemy_max_hp: int = 0
var enemy_attack: int = 5
var enemy_defense: int = 2
var enemy_attack_speed: float = 1.0

var party_data: Array = []
var party_labels: Array = []

var hero_cooldowns: Array = []
var enemy_cooldown: float = 0.0

var battle_active: bool = true
var battle_id: String = ""

func _ready():
	print("[BattleWindow] Created")

func _process(delta):
	if not battle_active:
		return
	update_atb(delta)

func update_atb(delta):
	for i in range(hero_cooldowns.size()):
		if hero_cooldowns[i] > 0:
			hero_cooldowns[i] -= delta
			if hero_cooldowns[i] <= 0:
				hero_attack(i)
				hero_cooldowns[i] = get_hero_cooldown(i)
	
	if enemy_cooldown > 0:
		enemy_cooldown -= delta
	else:
		enemy_attack_party()
		enemy_cooldown = 1.0 / enemy_attack_speed
	
	update_ui()

func init_battle(enemy: Dictionary, uid: String):
	battle_id = uid
	enemy_data = enemy
	party_data = GameManager.party
	
	if enemy.has("base_stats"):
		var stats = enemy.base_stats
		enemy_max_hp = stats.get("hp", 30)
		enemy_current_hp = enemy_max_hp
		enemy_attack = stats.get("attack", 5)
		enemy_defense = stats.get("defense", 2)
		enemy_attack_speed = stats.get("attack_speed", 1.0)
	
	hero_cooldowns.clear()
	for i in range(party_data.size()):
		hero_cooldowns.append(randf_range(0.5, 1.5))
	
	enemy_cooldown = 1.0 / enemy_attack_speed
	
	create_party_ui()
	update_ui()
	
	print("[Battle] %s HP:%d" % [enemy_data.get("name"), enemy_max_hp])

func create_party_ui():
	for child in party_list.get_children():
		child.queue_free()
	party_labels.clear()
	
	for hero in party_data:
		var label = Label.new()
		party_list.add_child(label)
		party_labels.append(label)

func update_ui():
	if enemy_name_label:
		enemy_name_label.text = enemy_data.get("name", "Enemy")
	
	if enemy_hp_bar:
		enemy_hp_bar.max_value = enemy_max_hp
		enemy_hp_bar.value = enemy_current_hp
		
		var ratio = float(enemy_current_hp) / enemy_max_hp
		if ratio > 0.5:
			enemy_hp_bar.modulate = Color.GREEN
		elif ratio > 0.25:
			enemy_hp_bar.modulate = Color.YELLOW
		else:
			enemy_hp_bar.modulate = Color.RED
	
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

func hero_attack(idx: int):
	if idx >= party_data.size():
		return
	var hero = party_data[idx]
	var damage = max(1, hero.base_stats.get("attack", 10) - enemy_defense)
	enemy_current_hp -= damage
	print("  %s → %d dmg" % [hero.name, damage])
	
	if enemy_current_hp <= 0:
		enemy_dies()

func enemy_attack_party():
	if party_data.is_empty():
		return
	var idx = randi() % party_data.size()
	var target = party_data[idx]
	var damage = max(1, enemy_attack - target.base_stats.get("defense", 5))
	target.current_hp -= damage
	print("  %s ← %d dmg (HP:%d)" % [target.name, damage, target.current_hp])
	
	if target.current_hp <= 0:
		hero_dies(idx)

# ========================================
# 승리 처리 (아이템 드랍 추가!) ⭐
# ========================================

func enemy_dies():
	battle_active = false
	print("[Battle] VICTORY!")
	
	GameManager.on_enemy_killed()
	
	# 경험치
	var exp = 20
	GameManager.add_exp(exp)
	
	# 골드
	var gold = randi_range(
		enemy_data.drop_table.get("gold_min", 5),
		enemy_data.drop_table.get("gold_max", 15)
	)
	GameManager.add_gold(gold)
	
	# 아이템 드랍 체크 ⭐
	var drop_rate = enemy_data.drop_table.get("item_drop_rate", 0.1)
	
	if randf() < drop_rate:
		# 3지선다 UI 표시!
		show_item_choice()
	else:
		# 드랍 없음
		EventBus.battle_victory.emit()
		close_window()

func show_item_choice():
	print("[Battle] Item dropped! Showing choices...")
	
	# ItemChoiceUI 생성
	var choice_ui = preload("res://scenes/ui/ItemChoiceUI.tscn").instantiate()
	
	# Canvas에 추가
	var canvas = get_tree().root.get_node_or_null("BattleCanvas")
	if canvas:
		canvas.add_child(choice_ui)
	else:
		get_tree().root.add_child(choice_ui)
	
	# 중앙 배치
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	choice_ui.position = Vector2(
		viewport_size.x / 2 - 200,
		viewport_size.y / 2 - 150
	)
	
	# 랜덤 아이템 3개
	var items = choice_ui.get_weighted_random_items(3)
	choice_ui.show_choices(items)
	
	# 선택 완료 대기
	choice_ui.item_selected.connect(_on_item_choice_made)
	choice_ui.choice_skipped.connect(_on_item_choice_skipped)

func _on_item_choice_made(item_id: String):
	print("[Battle] Item chosen: %s" % item_id)
	EventBus.battle_victory.emit()
	close_window()

func _on_item_choice_skipped():
	print("[Battle] Item skipped")
	EventBus.battle_victory.emit()
	close_window()

# ========================================
# 패배 처리
# ========================================

func hero_dies(idx: int):
	if idx >= party_data.size():
		return
	var hero = party_data[idx]
	print("  %s defeated!" % hero.name)
	
	hero.current_hp = 0  # HP 0으로 (파티에서 제거 안함)
	hero_cooldowns[idx] = 999999  # 더 이상 공격 안함
	
	# 살아있는 영웅 체크
	var alive_count = 0
	for h in party_data:
		if h.current_hp > 0:
			alive_count += 1
	
	if alive_count == 0:
		party_defeated()

func party_defeated():
	battle_active = false
	print("[Battle] DEFEAT!")
	EventBus.battle_defeat.emit()
	close_window()

func close_window():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()
