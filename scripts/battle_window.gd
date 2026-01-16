extends Control
class_name BattleWindow
## 드퀘 스타일 전투창 - 1~3마리 적 표시

signal battle_finished(victory: bool)
signal log_message(text: String)
signal party_updated(party_hp: Dictionary, party_cooldowns: Dictionary, max_cooldowns: Dictionary)

# 전투에 참여한 적들
var enemies: Array = []  # [{id, data, hp, max_hp, cooldown, max_cooldown, ui}]

var party_hp: Dictionary = {}
var party_cooldowns: Dictionary = {}
var max_cooldowns: Dictionary = {}

var is_battle_active: bool = false

@onready var panel: Panel = $Panel
@onready var enemies_container: HBoxContainer = $Panel/EnemiesContainer


func _ready() -> void:
	visible = false


func start_battle(enemy_id: String) -> void:
	if not is_node_ready():
		await ready
	
	_init_party_state()
	_create_enemies(enemy_id)
	
	visible = true
	is_battle_active = true
	
	# 출현 로그
	if enemies.size() == 1:
		log_message.emit("[ %s 출현! ]" % str(enemies[0]["data"].get("name", enemy_id)))
	else:
		log_message.emit("[ %s x%d 출현! ]" % [str(enemies[0]["data"].get("name", enemy_id)), enemies.size()])


func _init_party_state() -> void:
	party_hp.clear()
	party_cooldowns.clear()
	max_cooldowns.clear()
	
	for hero_id in GameManager.party:
		var hero_data = DataManager.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var max_hp = int(hero_data.get("stats", {}).get("max_hp", 100))
		var base_cd = float(hero_data.get("combat", {}).get("base_cooldown", 2.0))
		
		party_hp[hero_id] = max_hp
		party_cooldowns[hero_id] = base_cd
		max_cooldowns[hero_id] = base_cd


func _create_enemies(base_enemy_id: String) -> void:
	# 1~3마리 랜덤
	var count = randi_range(1, 3)
	
	for i in range(count):
		var enemy_data = DataManager.get_enemy(base_enemy_id)
		if enemy_data.is_empty():
			continue
		
		var max_hp = int(enemy_data.get("stats", {}).get("max_hp", 30))
		var max_cd = float(enemy_data.get("combat", {}).get("base_cooldown", 3.0))
		
		var enemy = {
			"id": base_enemy_id,
			"data": enemy_data,
			"hp": max_hp,
			"max_hp": max_hp,
			"cooldown": max_cd + randf_range(0, 1.0),  # 약간의 랜덤 딜레이
			"max_cooldown": max_cd,
			"ui": null
		}
		
		enemies.append(enemy)
		_create_enemy_ui(enemy)


func _create_enemy_ui(enemy: Dictionary) -> void:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(50, 70)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 스프라이트
	var sprite = TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE  # 원본 크기 유지
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED  # 중앙 정렬

	var sprite_path = str(enemy["data"].get("battle", {}).get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	container.add_child(sprite)
	
	# 이름
	var name_label = Label.new()
	name_label.text = str(enemy["data"].get("name", "???"))
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)
	
	# HP 바
	var hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(40, 5)
	hp_bar.max_value = enemy["max_hp"]
	hp_bar.value = enemy["hp"]
	hp_bar.show_percentage = false
	container.add_child(hp_bar)
	
	# 쿨다운 바
	var cd_bar = ProgressBar.new()
	cd_bar.custom_minimum_size = Vector2(40, 3)
	cd_bar.max_value = 100
	cd_bar.value = 0
	cd_bar.show_percentage = false
	container.add_child(cd_bar)
	
	enemies_container.add_child(container)
	
	enemy["ui"] = {
		"container": container,
		"sprite": sprite,
		"name": name_label,
		"hp_bar": hp_bar,
		"cooldown_bar": cd_bar
	}


func _process(delta: float) -> void:
	if not is_battle_active:
		return
	
	_process_enemy_cooldowns(delta)
	_process_party_cooldowns(delta)
	_update_ui()
	_check_battle_end()
	
	party_updated.emit(party_hp, party_cooldowns, max_cooldowns)


func _process_enemy_cooldowns(delta: float) -> void:
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		
		enemy["cooldown"] = float(enemy["cooldown"]) - delta
		if float(enemy["cooldown"]) <= 0:
			_enemy_attack(enemy)
			enemy["cooldown"] = float(enemy["max_cooldown"])


func _process_party_cooldowns(delta: float) -> void:
	for hero_id in party_cooldowns:
		if int(party_hp.get(hero_id, 0)) <= 0:
			continue
		
		party_cooldowns[hero_id] = float(party_cooldowns[hero_id]) - delta
		if float(party_cooldowns[hero_id]) <= 0:
			_hero_attack(hero_id)
			party_cooldowns[hero_id] = float(max_cooldowns[hero_id])


func _enemy_attack(enemy: Dictionary) -> void:
	var enemy_data = enemy["data"]
	
	var alive_heroes = []
	for id in party_hp:
		if int(party_hp[id]) > 0:
			alive_heroes.append(id)
	
	if alive_heroes.is_empty():
		return
	
	var target_id = alive_heroes[randi() % alive_heroes.size()]
	var target_data = DataManager.get_hero(target_id)
	
	var skill_ids = enemy_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return
	
	var skill_data = DataManager.get_skill(skill_ids[0])
	var effects = skill_data.get("effects", [])
	var damage = 10
	if effects.size() > 0:
		damage = int(effects[0].get("base_value", 10))
	
	party_hp[target_id] = maxi(0, int(party_hp[target_id]) - damage)
	
	log_message.emit("%s → %s %d!" % [
		str(enemy_data.get("name", "적")),
		str(target_data.get("name", target_id)),
		damage
	])


func _hero_attack(hero_id: String) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	
	var alive_enemies = []
	for i in range(enemies.size()):
		if int(enemies[i]["hp"]) > 0:
			alive_enemies.append(i)
	
	if alive_enemies.is_empty():
		return
	
	var target_idx = alive_enemies[randi() % alive_enemies.size()]
	var target = enemies[target_idx]
	
	var skill_ids = hero_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return
	
	var skill_data = DataManager.get_skill(skill_ids[0])
	var effects = skill_data.get("effects", [])
	var damage = 10
	if effects.size() > 0:
		damage = int(effects[0].get("base_value", 10))
	
	target["hp"] = maxi(0, int(target["hp"]) - damage)
	
	log_message.emit("%s → %s %d!" % [
		str(hero_data.get("name", hero_id)),
		str(target["data"].get("name", "적")),
		damage
	])
	
	if int(target["hp"]) <= 0:
		log_message.emit("[ %s 격파! ]" % str(target["data"].get("name", "적")))
		_on_enemy_defeated(target_idx)


func _on_enemy_defeated(idx: int) -> void:
	var enemy = enemies[idx]
	if enemy["ui"] != null:
		enemy["ui"]["container"].queue_free()
		enemy["ui"] = null


func _check_battle_end() -> void:
	var all_enemies_dead = true
	for enemy in enemies:
		if int(enemy["hp"]) > 0:
			all_enemies_dead = false
			break
	
	if all_enemies_dead:
		_end_battle(true)
		return
	
	var all_party_dead = true
	for hp in party_hp.values():
		if int(hp) > 0:
			all_party_dead = false
			break
	
	if all_party_dead:
		_end_battle(false)


func _end_battle(victory: bool) -> void:
	is_battle_active = false
	
	if victory:
		log_message.emit("[ 승리! ]")
	else:
		log_message.emit("[ 전멸... ]")
	
	await get_tree().create_timer(1.0).timeout
	
	battle_finished.emit(victory)
	GameManager.end_battle(enemies[0]["id"], victory)
	queue_free()


func _update_ui() -> void:
	for enemy in enemies:
		if enemy["ui"] == null:
			continue
		
		var ui = enemy["ui"]
		
		ui["hp_bar"].value = int(enemy["hp"])
		
		var max_cd = float(enemy["max_cooldown"])
		var current_cd = float(enemy["cooldown"])
		ui["cooldown_bar"].value = ((max_cd - current_cd) / max_cd) * 100
