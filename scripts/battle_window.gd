extends Control
class_name BattleWindow
## 드퀘 스타일 전투창 - 여러 적을 한 창에서 표시

signal battle_finished(victory: bool)
signal log_message(text: String)
signal party_updated(party_hp: Dictionary, party_cooldowns: Dictionary, max_cooldowns: Dictionary)

# 전투에 참여한 적들 {enemy_uid: {id, data, hp, max_hp, cooldown, max_cooldown}}
var enemies: Dictionary = {}
var enemy_ui_nodes: Dictionary = {}  # enemy_uid: {sprite, name, hp_bar, cooldown_bar}

var party_hp: Dictionary = {}
var party_cooldowns: Dictionary = {}
var max_cooldowns: Dictionary = {}

var is_battle_active: bool = false
var enemy_uid_counter: int = 0

@onready var panel: Panel = $Panel
@onready var enemies_container: HBoxContainer = $Panel/EnemiesContainer
@onready var battle_title: Label = $Panel/BattleTitle


func _ready() -> void:
	visible = false
	_init_party_state()


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


func add_enemy(enemy_id: String) -> void:
	## 전투에 적 추가
	var enemy_data = DataManager.get_enemy(enemy_id)
	if enemy_data.is_empty():
		return
	
	enemy_uid_counter += 1
	var uid = enemy_uid_counter
	
	var max_hp = int(enemy_data.get("stats", {}).get("max_hp", 30))
	var max_cd = float(enemy_data.get("combat", {}).get("base_cooldown", 3.0))
	
	enemies[uid] = {
		"id": enemy_id,
		"data": enemy_data,
		"hp": max_hp,
		"max_hp": max_hp,
		"cooldown": max_cd,
		"max_cooldown": max_cd
	}
	
	# UI 생성
	_create_enemy_ui(uid, enemy_data)
	
	# 첫 적이면 전투 시작
	if not is_battle_active:
		_start_battle()
	
	log_message.emit("[ %s 출현! ]" % str(enemy_data.get("name", enemy_id)))
	_update_title()


func _create_enemy_ui(uid: int, enemy_data: Dictionary) -> void:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(60, 80)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 스프라이트
	var sprite = TextureRect.new()
	sprite.custom_minimum_size = Vector2(48, 48)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var sprite_path = str(enemy_data.get("battle", {}).get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	
	container.add_child(sprite)
	
	# 이름
	var name_label = Label.new()
	name_label.text = str(enemy_data.get("name", "???"))
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)
	
	# HP 바
	var hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(50, 6)
	hp_bar.max_value = int(enemy_data.get("stats", {}).get("max_hp", 30))
	hp_bar.value = hp_bar.max_value
	hp_bar.show_percentage = false
	container.add_child(hp_bar)
	
	# 쿨다운 바
	var cd_bar = ProgressBar.new()
	cd_bar.custom_minimum_size = Vector2(50, 4)
	cd_bar.max_value = 100
	cd_bar.value = 0
	cd_bar.show_percentage = false
	container.add_child(cd_bar)
	
	enemies_container.add_child(container)
	
	enemy_ui_nodes[uid] = {
		"container": container,
		"sprite": sprite,
		"name": name_label,
		"hp_bar": hp_bar,
		"cooldown_bar": cd_bar
	}


func _start_battle() -> void:
	visible = true
	is_battle_active = true


func _process(delta: float) -> void:
	if not is_battle_active:
		return
	
	_process_enemy_cooldowns(delta)
	_process_party_cooldowns(delta)
	_update_ui()
	_check_battle_end()
	
	party_updated.emit(party_hp, party_cooldowns, max_cooldowns)


func _process_enemy_cooldowns(delta: float) -> void:
	for uid in enemies:
		var enemy = enemies[uid]
		if int(enemy["hp"]) <= 0:
			continue
		
		enemy["cooldown"] = float(enemy["cooldown"]) - delta
		if float(enemy["cooldown"]) <= 0:
			_enemy_attack(uid)
			enemy["cooldown"] = float(enemy["max_cooldown"])


func _process_party_cooldowns(delta: float) -> void:
	for hero_id in party_cooldowns:
		if int(party_hp.get(hero_id, 0)) <= 0:
			continue
		
		party_cooldowns[hero_id] = float(party_cooldowns[hero_id]) - delta
		if float(party_cooldowns[hero_id]) <= 0:
			_hero_attack(hero_id)
			party_cooldowns[hero_id] = float(max_cooldowns[hero_id])


func _enemy_attack(uid: int) -> void:
	var enemy = enemies[uid]
	var enemy_data = enemy["data"]
	
	# 살아있는 영웅 중 랜덤 타겟
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
	
	var skill_id = skill_ids[0]
	var skill_data = DataManager.get_skill(skill_id)
	var effects = skill_data.get("effects", [])
	var damage = 10
	if effects.size() > 0:
		damage = int(effects[0].get("base_value", 10))
	
	party_hp[target_id] = maxi(0, int(party_hp[target_id]) - damage)
	
	log_message.emit("%s → %s에게 %d!" % [
		str(enemy_data.get("name", "적")),
		str(target_data.get("name", target_id)),
		damage
	])


func _hero_attack(hero_id: String) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	
	# 살아있는 적 중 랜덤 타겟
	var alive_enemies = []
	for uid in enemies:
		if int(enemies[uid]["hp"]) > 0:
			alive_enemies.append(uid)
	
	if alive_enemies.is_empty():
		return
	
	var target_uid = alive_enemies[randi() % alive_enemies.size()]
	var target = enemies[target_uid]
	
	var skill_ids = hero_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return
	
	var skill_id = skill_ids[0]
	var skill_data = DataManager.get_skill(skill_id)
	var effects = skill_data.get("effects", [])
	var damage = 10
	if effects.size() > 0:
		damage = int(effects[0].get("base_value", 10))
	
	target["hp"] = maxi(0, int(target["hp"]) - damage)
	
	log_message.emit("%s → %s에게 %d!" % [
		str(hero_data.get("name", hero_id)),
		str(target["data"].get("name", "적")),
		damage
	])
	
	# 적 처치 시
	if int(target["hp"]) <= 0:
		log_message.emit("[ %s 격파! ]" % str(target["data"].get("name", "적")))
		_on_enemy_defeated(target_uid)


func _on_enemy_defeated(uid: int) -> void:
	# UI 어둡게 처리
	if enemy_ui_nodes.has(uid):
		var ui = enemy_ui_nodes[uid]
		ui["container"].modulate = Color(0.3, 0.3, 0.3, 1)
	
	_update_title()


func _check_battle_end() -> void:
	# 모든 적 처치 확인
	var all_enemies_dead = true
	for uid in enemies:
		if int(enemies[uid]["hp"]) > 0:
			all_enemies_dead = false
			break
	
	if all_enemies_dead:
		_end_battle(true)
		return
	
	# 파티 전멸 확인
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
		log_message.emit("[ 전투 승리! ]")
	else:
		log_message.emit("[ 전멸... ]")
	
	await get_tree().create_timer(1.5).timeout
	
	# 모든 적의 전투 종료 알림
	for uid in enemies:
		GameManager.end_battle(str(enemies[uid]["id"]), victory)
	
	battle_finished.emit(victory)
	queue_free()


func _update_ui() -> void:
	for uid in enemies:
		if not enemy_ui_nodes.has(uid):
			continue
		
		var enemy = enemies[uid]
		var ui = enemy_ui_nodes[uid]
		
		# HP 바
		var hp_bar: ProgressBar = ui["hp_bar"]
		hp_bar.max_value = int(enemy["max_hp"])
		hp_bar.value = int(enemy["hp"])
		
		# 쿨다운 바
		var cd_bar: ProgressBar = ui["cooldown_bar"]
		var max_cd = float(enemy["max_cooldown"])
		var current_cd = float(enemy["cooldown"])
		cd_bar.value = ((max_cd - current_cd) / max_cd) * 100


func _update_title() -> void:
	if battle_title == null:
		return
	
	var alive_count = 0
	for uid in enemies:
		if int(enemies[uid]["hp"]) > 0:
			alive_count += 1
	
	battle_title.text = "전투 중... (적 %d마리)" % alive_count


func get_enemy_count() -> int:
	return enemies.size()


func has_active_enemies() -> bool:
	for uid in enemies:
		if int(enemies[uid]["hp"]) > 0:
			return true
	return false
