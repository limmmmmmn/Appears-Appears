extends Control
class_name BattleWindow
## 드퀘 스타일 전투창 - 1~3마리 적 표시

signal battle_finished(victory: bool)
signal log_message(text: String)

# 전투에 참여한 적들
var enemies: Array = []  # [{id, data, hp, max_hp, cooldown, max_cooldown, ui}]

var is_battle_active: bool = false

@onready var panel: Panel = $Panel
@onready var enemies_container: HBoxContainer = $Panel/EnemiesContainer


func _ready() -> void:
	visible = false
	# GameManager의 공격 준비 시그널 연결
	GameManager.hero_ready_to_attack.connect(_on_hero_ready_to_attack)


func start_battle(enemy_id: String) -> void:
	if not is_node_ready():
		await ready
	
	_create_enemies(enemy_id)
	
	visible = true
	is_battle_active = true
	
	# 출현 로그
	if enemies.size() == 1:
		log_message.emit("[ %s 출현! ]" % str(enemies[0]["data"].get("name", enemy_id)))
	else:
		log_message.emit("[ %s x%d 출현! ]" % [str(enemies[0]["data"].get("name", enemy_id)), enemies.size()])


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
			"cooldown": max_cd + randf_range(0, 1.0),
			"max_cooldown": max_cd,
			"ui": null
		}
		
		enemies.append(enemy)
		_create_enemy_ui(enemy)


func _create_enemy_ui(enemy: Dictionary) -> void:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 스프라이트
	var sprite = TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	
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
	_update_ui()
	_check_battle_end()


func _process_enemy_cooldowns(delta: float) -> void:
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		
		enemy["cooldown"] = float(enemy["cooldown"]) - delta
		if float(enemy["cooldown"]) <= 0:
			_enemy_attack(enemy)
			enemy["cooldown"] = float(enemy["max_cooldown"])


func _on_hero_ready_to_attack(hero_id: String) -> void:
	# 이 전투창이 활성화 상태일 때만 공격
	if not is_battle_active:
		return
	
	# 살아있는 적이 있는지 확인
	var alive_enemies = []
	for i in range(enemies.size()):
		if int(enemies[i]["hp"]) > 0:
			alive_enemies.append(i)
	
	if alive_enemies.is_empty():
		return
	
	_hero_attack(hero_id, alive_enemies)


func _enemy_attack(enemy: Dictionary) -> void:
	var enemy_data = enemy["data"]
	
	var alive_heroes = GameManager.get_alive_heroes()
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
	
	# 공격 이펙트 재생
	_play_attack_effect(enemy)
	
	GameManager.damage_hero(target_id, damage)
	
	log_message.emit("%s → %s %d!" % [
		str(enemy_data.get("name", "적")),
		str(target_data.get("name", target_id)),
		damage
	])


func _hero_attack(hero_id: String, alive_enemies: Array) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	
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
	
	# 피격 이펙트 재생
	_play_hit_effect(target)
	
	log_message.emit("%s → %s %d!" % [
		str(hero_data.get("name", hero_id)),
		str(target["data"].get("name", "적")),
		damage
	])
	
	if int(target["hp"]) <= 0:
		log_message.emit("[ %s 격파! ]" % str(target["data"].get("name", "적")))
		_on_enemy_defeated(target_idx)


#region 이펙트
func _play_hit_effect(enemy: Dictionary) -> void:
	## 피격 이펙트: 흰색 플래시 + 깜빡임 (클래식 RPG 스타일)
	if enemy["ui"] == null:
		return
	
	var sprite: TextureRect = enemy["ui"]["sprite"]
	if sprite == null or not is_instance_valid(sprite):
		return
	
	var tween = create_tween()
	var original_modulate = sprite.modulate
	
	# 흰색 플래시 + 깜빡임 3회
	for i in range(3):
		# 흰색으로 (피격 순간)
		tween.tween_property(sprite, "modulate", Color.WHITE * 2.0, 0.03)
		# 투명하게 (깜빡)
		tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0.3), 0.03)
		# 원래대로
		tween.tween_property(sprite, "modulate", original_modulate, 0.03)
	
	# 최종 원래 색으로 복귀 보장
	tween.tween_property(sprite, "modulate", original_modulate, 0.01)


func _play_attack_effect(enemy: Dictionary) -> void:
	## 공격 이펙트: 앞으로 튀어나왔다 돌아오기
	if enemy["ui"] == null:
		return
	
	var container: VBoxContainer = enemy["ui"]["container"]
	if container == null or not is_instance_valid(container):
		return
	
	var original_pos = container.position
	var attack_offset = Vector2(0, 8)  # 아래로 튀어나옴 (플레이어 쪽)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	# 빠르게 앞으로
	tween.tween_property(container, "position", original_pos + attack_offset, 0.1)
	# 잠깐 대기
	tween.tween_interval(0.05)
	# 부드럽게 돌아오기
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(container, "position", original_pos, 0.15)
#endregion


func _on_enemy_defeated(idx: int) -> void:
	var enemy = enemies[idx]
	if enemy["ui"] != null:
		# 사망 이펙트: 페이드아웃
		var container = enemy["ui"]["container"]
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 0.0, 0.3)
		tween.tween_callback(container.queue_free)
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
	
	if GameManager.is_party_dead():
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
