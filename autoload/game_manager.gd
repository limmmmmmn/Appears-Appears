extends Node
## 게임 전역 상태를 관리하는 오토로드

signal battle_started(enemy_id: String)
signal battle_ended(enemy_id: String, victory: bool)
signal party_status_changed()
signal hero_died(hero_id: String)

# 현재 파티 구성 (영웅 id 배열)
var party: Array[String] = ["warrior", "mage", "cleric", "thief"]

# 파티 상태 (전역으로 관리)
var party_hp: Dictionary = {}
var party_max_hp: Dictionary = {}
var party_cooldowns: Dictionary = {}
var party_max_cooldowns: Dictionary = {}

# 활성 전투 목록
var active_battles: Array = []

# 배틀 매니저 참조 (전투창 직접 관리용)
var battle_manager: Node = null

# 게임 상태
var is_paused: bool = false


func _ready() -> void:
	_init_party_status()
	print("[GameManager] 초기화 완료")


func _init_party_status() -> void:
	for hero_id in party:
		var hero_data = DataManager.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var max_hp = int(hero_data.get("stats", {}).get("max_hp", 100))
		var base_cd = float(hero_data.get("combat", {}).get("base_cooldown", 2.0))
		
		party_hp[hero_id] = max_hp
		party_max_hp[hero_id] = max_hp
		party_cooldowns[hero_id] = 0.0
		party_max_cooldowns[hero_id] = base_cd


func register_battle_manager(manager: Node) -> void:
	## BattleManager 등록 (전투창 직접 접근용)
	battle_manager = manager
	print("[GameManager] BattleManager 등록됨")


func _process(delta: float) -> void:
	if is_paused:
		return
	
	_process_party_cooldowns(delta)


func _process_party_cooldowns(delta: float) -> void:
	for hero_id in party_cooldowns:
		if int(party_hp.get(hero_id, 0)) <= 0:
			continue
		
		var current_cd = float(party_cooldowns[hero_id])
		
		if current_cd > 0:
			party_cooldowns[hero_id] = maxf(0, current_cd - delta)
		
		if float(party_cooldowns[hero_id]) <= 0:
			if active_battles.size() > 0:
				_execute_hero_attack(hero_id)
			party_cooldowns[hero_id] = float(party_max_cooldowns[hero_id])


func _execute_hero_attack(hero_id: String) -> void:
	## 영웅 공격 실행 - 스킬 타입에 따라 분기
	if battle_manager == null:
		return
	
	var hero_data = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var skill_ids = hero_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return
	
	var skill_id = skill_ids[0]
	var skill_data = DataManager.get_skill(skill_id)
	
	# 스킬 타겟 타입 확인 (기본: single)
	var target_type = str(skill_data.get("target_type", "single"))
	
	match target_type:
		"single":
			_attack_single(hero_id, skill_data)
		"multi":
			_attack_multi(hero_id, skill_data)
		"all":
			_attack_all(hero_id, skill_data)
		_:
			_attack_single(hero_id, skill_data)


func _attack_single(hero_id: String, skill_data: Dictionary) -> void:
	## 단일 공격: 전투창 하나의 적 하나
	var windows = _get_active_windows()
	if windows.is_empty():
		return
	
	var target_window = windows[randi() % windows.size()]
	target_window.receive_hero_attack(hero_id, skill_data, "single")


func _attack_multi(hero_id: String, skill_data: Dictionary) -> void:
	## 범위 공격: 전투창 하나의 모든 적
	var windows = _get_active_windows()
	if windows.is_empty():
		return
	
	var target_window = windows[randi() % windows.size()]
	target_window.receive_hero_attack(hero_id, skill_data, "multi")


func _attack_all(hero_id: String, skill_data: Dictionary) -> void:
	## 전체 공격: 모든 전투창의 모든 적
	var windows = _get_active_windows()
	for window in windows:
		window.receive_hero_attack(hero_id, skill_data, "multi")


func _get_active_windows() -> Array:
	## 활성화된 전투창 목록 반환
	if battle_manager == null:
		return []
	
	var valid_windows = []
	for w in battle_manager.active_windows:
		if is_instance_valid(w) and w.is_battle_active:
			valid_windows.append(w)
	return valid_windows


func start_battle(enemy_id: String) -> void:
	active_battles.append(enemy_id)
	battle_started.emit(enemy_id)
	print("[GameManager] 전투 시작: " + enemy_id + " (활성 전투: %d)" % active_battles.size())


func end_battle(enemy_id: String, victory: bool) -> void:
	active_battles.erase(enemy_id)
	battle_ended.emit(enemy_id, victory)
	print("[GameManager] 전투 종료: " + enemy_id + " (승리: %s)" % str(victory))


func get_active_battle_count() -> int:
	return active_battles.size()


func damage_hero(hero_id: String, damage: int) -> void:
	if party_hp.has(hero_id):
		var was_alive = int(party_hp[hero_id]) > 0
		party_hp[hero_id] = maxi(0, int(party_hp[hero_id]) - damage)
		party_status_changed.emit()
		
		if was_alive and int(party_hp[hero_id]) <= 0:
			hero_died.emit(hero_id)
			_show_dead_popup(hero_id)


func _show_dead_popup(hero_id: String) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	var hero_name = str(hero_data.get("name", hero_id))
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	get_tree().root.add_child(canvas)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = hero_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var dead_label = Label.new()
	dead_label.text = "DEAD"
	dead_label.add_theme_font_size_override("font_size", 32)
	dead_label.add_theme_color_override("font_color", Color.RED)
	dead_label.add_theme_color_override("font_outline_color", Color.BLACK)
	dead_label.add_theme_constant_override("outline_size", 4)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dead_label)
	
	vbox.modulate.a = 0.0
	vbox.scale = Vector2(0.5, 0.5)
	vbox.pivot_offset = vbox.size / 2
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(vbox, "modulate:a", 1.0, 0.15)
	tween.tween_property(vbox, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	tween.set_parallel(false)
	tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(0.8)
	tween.tween_property(vbox, "modulate:a", 0.0, 0.3)
	tween.tween_callback(canvas.queue_free)


func heal_hero(hero_id: String, amount: int) -> void:
	if party_hp.has(hero_id):
		var max_hp = int(party_max_hp.get(hero_id, 100))
		party_hp[hero_id] = mini(max_hp, int(party_hp[hero_id]) + amount)
		party_status_changed.emit()


func is_hero_alive(hero_id: String) -> bool:
	return int(party_hp.get(hero_id, 0)) > 0


func get_alive_heroes() -> Array:
	var alive = []
	for hero_id in party:
		if is_hero_alive(hero_id):
			alive.append(hero_id)
	return alive


func is_party_dead() -> bool:
	return get_alive_heroes().is_empty()


func get_cooldown_percent(hero_id: String) -> float:
	var current = float(party_cooldowns.get(hero_id, 0))
	var max_cd = float(party_max_cooldowns.get(hero_id, 1))
	return (max_cd - current) / max_cd
