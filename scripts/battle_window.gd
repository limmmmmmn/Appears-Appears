extends Control
class_name BattleWindow
## 드퀘 스타일 전투창 - 1~3마리 적 표시

signal battle_finished(victory: bool)
signal log_message(text: String)

# 전투에 참여한 적들
var enemies: Array = []  # [{id, data, hp, max_hp, cooldown, max_cooldown, ui}]

var is_battle_active: bool = false

# 이펙트 텍스처
var slash_texture: Texture2D = null

@onready var panel: Panel = $Panel
@onready var enemies_container: HBoxContainer = $Panel/EnemiesContainer


func _ready() -> void:
	visible = false
<<<<<<< HEAD
	_load_fx_textures()


func _load_fx_textures() -> void:
	var slash_path = "res://assets/FX/slash.png"  # ← 이 경로 확인!
	if ResourceLoader.exists(slash_path):
		slash_texture = load(slash_path)
		print("[BattleWindow] 슬래시 텍스처 로드됨")  # 디버그용
	else:
		print("[BattleWindow] 슬래시 텍스처 없음: ", slash_path)  # 디버그용
=======
	# 시그널 연결 제거됨 - 이제 GameManager가 직접 호출
>>>>>>> parent of 1e03c52 (HUD)


func start_battle(enemy_id: String) -> void:
	if not is_node_ready():
		await ready
	
	_create_enemies(enemy_id)
	
	visible = true
	is_battle_active = true
	
	if enemies.size() == 1:
		log_message.emit("[ %s 출현! ]" % str(enemies[0]["data"].get("name", enemy_id)))
	else:
		log_message.emit("[ %s x%d 출현! ]" % [str(enemies[0]["data"].get("name", enemy_id)), enemies.size()])


func _create_enemies(base_enemy_id: String) -> void:
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
<<<<<<< HEAD
			"cooldown": max_cd * randf_range(0.25, 1.0) ,
=======
			"cooldown": max_cd + randf_range(0, 1.0),
>>>>>>> parent of 1e03c52 (HUD)
			"max_cooldown": max_cd,
			"ui": null
		}
		
		enemies.append(enemy)
		_create_enemy_ui(enemy)


func _create_enemy_ui(enemy: Dictionary) -> void:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 스프라이트 컨테이너 (이펙트 표시용)
	var sprite_container = Control.new()
	sprite_container.custom_minimum_size = Vector2(48, 48)
	
	var sprite = TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	sprite.set_anchors_preset(Control.PRESET_CENTER)
	
	var sprite_path = str(enemy["data"].get("battle", {}).get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	
	sprite_container.add_child(sprite)
	container.add_child(sprite_container)
	
	var name_label = Label.new()
	name_label.text = str(enemy["data"].get("name", "???"))
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)
	
	var hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(40, 5)
	hp_bar.max_value = enemy["max_hp"]
	hp_bar.value = enemy["hp"]
	hp_bar.show_percentage = false
	container.add_child(hp_bar)
	
	var cd_bar = ProgressBar.new()
	cd_bar.custom_minimum_size = Vector2(40, 3)
	cd_bar.max_value = 100
	cd_bar.value = 0
	cd_bar.show_percentage = false
	container.add_child(cd_bar)
	
	enemies_container.add_child(container)
	
	enemy["ui"] = {
		"container": container,
		"sprite_container": sprite_container,
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


func receive_hero_attack(hero_id: String, skill_data: Dictionary, attack_type: String) -> void:
	## GameManager가 직접 호출하는 공격 수신 함수
	if not is_battle_active:
		return
	
	var alive_enemies = _get_alive_enemy_indices()
	if alive_enemies.is_empty():
		return
	
	# 필드 아이콘 이펙트 요청
	var skill_type = str(skill_data.get("type", "physical"))
	GameManager.show_attack_icon(hero_id, skill_type)
	
	match attack_type:
		"single":
			_hero_attack_single(hero_id, skill_data, alive_enemies)
		"multi":
			_hero_attack_multi(hero_id, skill_data, alive_enemies)


func _get_alive_enemy_indices() -> Array:
	var alive = []
	for i in range(enemies.size()):
		if int(enemies[i]["hp"]) > 0:
			alive.append(i)
	return alive


func _hero_attack_single(hero_id: String, skill_data: Dictionary, alive_enemies: Array) -> void:
	## 단일 공격: 적 하나만
	var hero_data = DataManager.get_hero(hero_id)
	
	var target_idx = alive_enemies[randi() % alive_enemies.size()]
	var target = enemies[target_idx]
	
	var damage = _calculate_damage(skill_data)
	target["hp"] = maxi(0, int(target["hp"]) - damage)
	
	_play_hit_effect(target)
	_play_slash_effect(target)
	
	log_message.emit("%s → %s %d!" % [
		str(hero_data.get("name", hero_id)),
		str(target["data"].get("name", "적")),
		damage
	])
	
	if int(target["hp"]) <= 0:
		log_message.emit("[ %s 격파! ]" % str(target["data"].get("name", "적")))
		_on_enemy_defeated(target_idx)


func _hero_attack_multi(hero_id: String, skill_data: Dictionary, alive_enemies: Array) -> void:
	## 범위 공격: 모든 살아있는 적
	var hero_data = DataManager.get_hero(hero_id)
	var damage = _calculate_damage(skill_data)
	
	log_message.emit("%s의 전체 공격!" % str(hero_data.get("name", hero_id)))
	
	for idx in alive_enemies:
		var target = enemies[idx]
		target["hp"] = maxi(0, int(target["hp"]) - damage)
		
		_play_hit_effect(target)
		_play_slash_effect(target)
		
		log_message.emit("→ %s %d!" % [
			str(target["data"].get("name", "적")),
			damage
		])
		
		if int(target["hp"]) <= 0:
			log_message.emit("[ %s 격파! ]" % str(target["data"].get("name", "적")))
			_on_enemy_defeated(idx)


func _calculate_damage(skill_data: Dictionary) -> int:
	var effects = skill_data.get("effects", [])
	var damage = 10
	if effects.size() > 0:
		damage = int(effects[0].get("base_value", 10))
	return damage


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
	
	_play_attack_effect(enemy)
	
	GameManager.damage_hero(target_id, damage)
	
	log_message.emit("%s → %s %d!" % [
		str(enemy_data.get("name", "적")),
		str(target_data.get("name", target_id)),
		damage
	])


#region 이펙트
func _play_hit_effect(enemy: Dictionary) -> void:
	## 피격 시 깜빡임 효과
	if enemy["ui"] == null:
		return
	
	var sprite: TextureRect = enemy["ui"]["sprite"]
	if sprite == null or not is_instance_valid(sprite):
		return
	
	var tween = create_tween()
	var original_modulate = sprite.modulate
	
	for i in range(3):
		tween.tween_property(sprite, "modulate", Color.WHITE * 2.0, 0.03)
		tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0.3), 0.03)
		tween.tween_property(sprite, "modulate", original_modulate, 0.03)
	
	tween.tween_property(sprite, "modulate", original_modulate, 0.01)


func _play_slash_effect(enemy: Dictionary) -> void:
	## 슬래시 이펙트 표시
	if enemy["ui"] == null or slash_texture == null:
		return
	
	var sprite: TextureRect = enemy["ui"]["sprite"]
	if sprite == null or not is_instance_valid(sprite):
		return
	
	# Sprite2D로 생성
	var slash = Sprite2D.new()
	slash.texture = slash_texture
	slash.z_index = 10
	slash.modulate.a = 0.0
	slash.rotation_degrees = randf_range(-30, 30)
	
	# 스프라이트 중앙에 위치
	slash.position = sprite.size / 2
	
	sprite.add_child(slash)
	
	# 애니메이션
	var tween = create_tween()
	slash.scale = Vector2(0.5, 0.5)
	
	tween.tween_property(slash, "modulate:a", 1.0, 0.05)
	tween.set_parallel(true)
	tween.tween_property(slash, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(0.1)
	tween.tween_property(slash, "modulate:a", 0.0, 0.1)
	tween.tween_callback(slash.queue_free)

func _play_attack_effect(enemy: Dictionary) -> void:
	## 적 공격 시 앞으로 이동 효과
	if enemy["ui"] == null:
		return
	
	var container: VBoxContainer = enemy["ui"]["container"]
	if container == null or not is_instance_valid(container):
		return
	
	var original_pos = container.position
	var attack_offset = Vector2(0, 8)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(container, "position", original_pos + attack_offset, 0.1)
	tween.tween_interval(0.05)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(container, "position", original_pos, 0.15)
#endregion


func _on_enemy_defeated(idx: int) -> void:
	var enemy = enemies[idx]
	if enemy["ui"] != null:
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
		# 경험치 계산 및 분배
		var total_exp = _calculate_total_exp()
		log_message.emit("[ 승리! ]")
		log_message.emit("+ %d EXP" % total_exp)
		GameManager.add_exp_to_party(total_exp)
	else:
		log_message.emit("[ 전멸... ]")
	
	await get_tree().create_timer(1.0).timeout
	
	battle_finished.emit(victory)
	GameManager.end_battle(enemies[0]["id"], victory)
	queue_free()


func _calculate_total_exp() -> int:
	## 처치한 모든 적의 경험치 합산
	var total = 0
	for enemy in enemies:
		var rewards = enemy["data"].get("rewards", {})
		var exp = int(rewards.get("exp", 0))
		total += exp
	return total


func _update_ui() -> void:
	for enemy in enemies:
		if enemy["ui"] == null:
			continue
		
		var ui = enemy["ui"]
		
		ui["hp_bar"].value = int(enemy["hp"])
		
		var max_cd = float(enemy["max_cooldown"])
		var current_cd = float(enemy["cooldown"])
		ui["cooldown_bar"].value = ((max_cd - current_cd) / max_cd) * 100
