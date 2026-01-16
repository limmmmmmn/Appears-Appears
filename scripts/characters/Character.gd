extends CharacterBody2D
class_name Character
## Character.gd
## 캐릭터 기본 클래스 - 플레이어, 파티원, 적 공통

# ===== 캐릭터 정보 =====
@export var char_id: String = ""
@export var char_name: String = ""
@export var char_class: String = ""

# ===== 스탯 =====
var level: int = 1
var max_hp: int = 100
var current_hp: int = 100
var max_mp: int = 50
var current_mp: int = 50
var attack: int = 10
var defense: int = 5
var magic: int = 5
var magic_defense: int = 5
var speed: int = 10
var critical: float = 5.0
var evasion: float = 3.0

# ===== 이동 =====
@export var move_speed: float = 80.0
var move_direction: Vector2 = Vector2.ZERO
var is_moving: bool = false
var facing_left: bool = true  # 기본 스프라이트가 왼쪽을 봄

# ===== 상태 =====
var is_alive: bool = true
var is_in_battle: bool = false
var status_effects: Array[Dictionary] = []

# ===== 노드 참조 =====
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

# ===== 시그널 =====
signal hp_changed(current: int, maximum: int)
signal mp_changed(current: int, maximum: int)
signal died


func _ready() -> void:
	_setup_character()


func _setup_character() -> void:
	# 자식 클래스에서 오버라이드
	pass


# ===== 스탯 초기화 =====
func init_from_data(data: Dictionary) -> void:
	char_id = data.get("id", char_id)
	char_name = data.get("name", char_name)
	char_class = data.get("class", char_class)
	
	var base_stats = data.get("base_stats", {})
	level = base_stats.get("level", 1)
	max_hp = base_stats.get("max_hp", 100)
	current_hp = max_hp
	max_mp = base_stats.get("max_mp", 50)
	current_mp = max_mp
	attack = base_stats.get("attack", 10)
	defense = base_stats.get("defense", 5)
	magic = base_stats.get("magic", 5)
	magic_defense = base_stats.get("magic_defense", 5)
	speed = base_stats.get("speed", 10)
	critical = base_stats.get("critical", 5.0)
	evasion = base_stats.get("evasion", 3.0)
	
	# 스프라이트 로드
	_load_sprite_from_data(data)


func init_from_saved_data(data: Dictionary) -> void:
	init_from_data(data)
	current_hp = data.get("current_hp", max_hp)
	current_mp = data.get("current_mp", max_mp)
	level = data.get("level", level)


# ===== 이동 =====
func _physics_process(delta: float) -> void:
	if is_in_battle:
		return
	
	if move_direction != Vector2.ZERO:
		velocity = move_direction.normalized() * move_speed
		is_moving = true
		_update_facing()
	else:
		velocity = Vector2.ZERO
		is_moving = false
	
	move_and_slide()


func set_move_direction(direction: Vector2) -> void:
	move_direction = direction


func stop_movement() -> void:
	move_direction = Vector2.ZERO
	velocity = Vector2.ZERO
	is_moving = false


func _update_facing() -> void:
	if sprite == null:
		return
	
	# 기본 스프라이트가 왼쪽을 보고 있음
	# 오른쪽으로 이동하면 flip_h = true
	if move_direction.x > 0:
		sprite.flip_h = true
		facing_left = false
	elif move_direction.x < 0:
		sprite.flip_h = false
		facing_left = true


func face_direction(dir: Vector2) -> void:
	if dir.x > 0:
		sprite.flip_h = true
		facing_left = false
	elif dir.x < 0:
		sprite.flip_h = false
		facing_left = true


func face_left() -> void:
	if sprite:
		sprite.flip_h = false
	facing_left = true


func face_right() -> void:
	if sprite:
		sprite.flip_h = true
	facing_left = false


# ===== HP/MP 관리 =====
func take_damage(amount: int) -> bool:
	if not is_alive:
		return false
	
	var actual_damage = maxi(1, amount - defense / 2)
	current_hp = maxi(0, current_hp - actual_damage)
	hp_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0:
		_on_death()
		return true
	
	return false


func take_magic_damage(amount: int) -> bool:
	if not is_alive:
		return false
	
	var actual_damage = maxi(1, amount - magic_defense / 2)
	current_hp = maxi(0, current_hp - actual_damage)
	hp_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0:
		_on_death()
		return true
	
	return false


func take_raw_damage(amount: int) -> bool:
	if not is_alive:
		return false
	
	current_hp = maxi(0, current_hp - amount)
	hp_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0:
		_on_death()
		return true
	
	return false


func heal(amount: int) -> int:
	if not is_alive:
		return 0
	
	var old_hp = current_hp
	current_hp = mini(current_hp + amount, max_hp)
	var healed = current_hp - old_hp
	hp_changed.emit(current_hp, max_hp)
	return healed


func use_mp(amount: int) -> bool:
	if current_mp >= amount:
		current_mp -= amount
		mp_changed.emit(current_mp, max_mp)
		return true
	return false


func restore_mp(amount: int) -> int:
	var old_mp = current_mp
	current_mp = mini(current_mp + amount, max_mp)
	var restored = current_mp - old_mp
	mp_changed.emit(current_mp, max_mp)
	return restored


func heal_full() -> void:
	current_hp = max_hp
	current_mp = max_mp
	hp_changed.emit(current_hp, max_hp)
	mp_changed.emit(current_mp, max_mp)


func revive(hp_percent: float = 0.25) -> void:
	if is_alive:
		return
	
	is_alive = true
	current_hp = int(max_hp * hp_percent)
	hp_changed.emit(current_hp, max_hp)


func _on_death() -> void:
	is_alive = false
	died.emit()


# ===== 상태이상 =====
func add_status_effect(effect: Dictionary) -> void:
	status_effects.append(effect)


func remove_status_effect(effect_name: String) -> void:
	status_effects = status_effects.filter(func(e): return e.get("name") != effect_name)


func has_status_effect(effect_name: String) -> bool:
	for effect in status_effects:
		if effect.get("name") == effect_name:
			return true
	return false


func process_status_effects() -> void:
	var effects_to_remove: Array[String] = []
	
	for effect in status_effects:
		var effect_type = effect.get("type", "")
		
		match effect_type:
			"dot":  # Damage over time (poison 등)
				var damage_percent = effect.get("damage_percent", 5)
				var damage = int(max_hp * damage_percent / 100.0)
				take_raw_damage(damage)
		
		# 지속시간 감소
		effect["duration"] = effect.get("duration", 1) - 1
		if effect["duration"] <= 0:
			effects_to_remove.append(effect.get("name", ""))
	
	for effect_name in effects_to_remove:
		remove_status_effect(effect_name)


# ===== 전투용 =====
func calculate_damage(target: Character) -> Dictionary:
	var base_damage = attack
	var is_crit = randf() * 100 < critical
	
	if is_crit:
		base_damage = int(base_damage * 2.0)
	
	var final_damage = maxi(1, base_damage - target.defense / 2)
	
	return {
		"damage": final_damage,
		"is_critical": is_crit
	}


func calculate_magic_damage(target: Character, power: int = 100) -> Dictionary:
	var base_damage = int(magic * power / 100.0)
	var is_crit = randf() * 100 < critical
	
	if is_crit:
		base_damage = int(base_damage * 2.0)
	
	var final_damage = maxi(1, base_damage - target.magic_defense / 2)
	
	return {
		"damage": final_damage,
		"is_critical": is_crit
	}


func check_evasion() -> bool:
	return randf() * 100 < evasion


# ===== 저장용 =====
func get_save_data() -> Dictionary:
	return {
		"id": char_id,
		"name": char_name,
		"class": char_class,
		"level": level,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"max_mp": max_mp,
		"current_mp": current_mp,
		"attack": attack,
		"defense": defense,
		"magic": magic,
		"magic_defense": magic_defense,
		"speed": speed,
		"critical": critical,
		"evasion": evasion
	}


# ===== 스프라이트 로딩 =====
func _load_sprite_from_data(data: Dictionary) -> void:
	if sprite == null:
		await ready
	
	var sprite_file = data.get("sprite", "")
	
	if sprite_file != "":
		_apply_sprite(sprite_file, "characters")


func _apply_sprite(sprite_file: String, folder: String = "characters") -> void:
	if sprite == null:
		return
	
	var full_path = "res://assets/sprites/" + folder + "/" + sprite_file
	
	if ResourceLoader.exists(full_path):
		sprite.texture = load(full_path)
	else:
		push_warning("Sprite not found: " + full_path)


func load_sprite(sprite_file: String, folder: String = "characters") -> void:
	_apply_sprite(sprite_file, folder)
