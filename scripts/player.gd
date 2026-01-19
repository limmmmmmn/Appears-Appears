extends CharacterBody2D
class_name Player
## 드퀘 스타일 필드 이동을 담당하는 플레이어
## 리더 사망 시 자동으로 다음 멤버가 리더가 됨

@export var move_speed: float = 80.0

var party_members: Array[PartyMember] = []
var party_member_scene: PackedScene = preload("res://scenes/player/party_member.tscn")

var encountered_enemies: Array = []
var current_leader_id: String = ""


@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox

var is_dead: bool = false


func _ready() -> void:
	# 그룹 추가 (적이 찾을 수 있도록)
	add_to_group("player")
	
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# GameManager에 플레이어 등록
	GameManager.register_player(self)
	
	# 파티 순서 변경 시그널 연결
	GameManager.party_order_changed.connect(_on_party_order_changed)
	
	# 리더 사망 시그널 연결
	GameManager.hero_died.connect(_on_hero_died)
	
	# 초기 리더 설정
	if not GameManager.party.is_empty():
		current_leader_id = GameManager.party[0]
	
	_load_leader_sprite()
	
	await get_tree().process_frame
	_spawn_party_members()


func _spawn_party_members() -> void:
	for member in party_members:
		if is_instance_valid(member):
			member.queue_free()
	party_members.clear()
	
	var party := GameManager.party
	if party.size() <= 1:
		return
	
	var prev_unit: Node2D = self
	var base_distance := 22.0
	
	for i in range(1, party.size()):
		var hero_id: String = party[i]
		var member := party_member_scene.instantiate() as PartyMember
		
		member.setup(hero_id, prev_unit, base_distance)
		member.z_index = -i
		get_parent().add_child(member)
		
		party_members.append(member)
		prev_unit = member


func _load_leader_sprite() -> void:
	if current_leader_id.is_empty():
		return
	
	var hero_data := DataManager.get_hero(current_leader_id)
	if hero_data.is_empty():
		return
	
	var sprite_path: String = hero_data.get("visuals", {}).get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	
	# 리더는 항상 살아있으므로 정상 상태로
	sprite.modulate = Color.WHITE
	sprite.rotation_degrees = 0


func _physics_process(_delta: float) -> void:
	if is_dead:
		return
	
	var input_dir := _get_input_direction()
	
	velocity = input_dir * move_speed
	
	move_and_slide()
	
	_update_sprite_direction(input_dir)


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	
	return dir.normalized()


func _update_sprite_direction(dir: Vector2) -> void:
	if dir.x > 0:
		sprite.flip_h = true
	elif dir.x < 0:
		sprite.flip_h = false


func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy_hitbox"):
		var enemy = area.get_parent()
		if enemy and enemy.is_active and not encountered_enemies.has(enemy):
			encountered_enemies.append(enemy)
			_encounter_enemy(enemy)


func _encounter_enemy(enemy) -> void:
	if not enemy.is_active:
		return
	
	var enemy_id = enemy.enemy_id
	enemy.on_encountered()
	GameManager.start_battle(enemy_id)


func _on_party_order_changed(new_order: Array) -> void:
	print("[Player] 파티 순서 변경 감지: ", new_order)
	
	var new_leader = GameManager.get_current_leader()
	
	if new_leader != current_leader_id and not new_leader.is_empty():
		current_leader_id = new_leader
		_load_leader_sprite()
		print("[Player] 새 리더: ", current_leader_id)
	
	_rebuild_party_chain()


func _rebuild_party_chain() -> void:
	var party := GameManager.party
	
	# 현재 파티원들의 위치와 플립 상태 저장
	var positions: Dictionary = {}
	var flips: Dictionary = {}
	for member in party_members:
		if is_instance_valid(member):
			positions[member.hero_id] = member.global_position
			flips[member.hero_id] = member.sprite.flip_h
	
	# 기존 파티원 제거
	for member in party_members:
		if is_instance_valid(member):
			member.queue_free()
	party_members.clear()
	
	if party.size() <= 1:
		return
	
	var prev_unit: Node2D = self
	var base_distance := 22.0
	
	for i in range(1, party.size()):
		var hero_id: String = party[i]
		var member := party_member_scene.instantiate() as PartyMember
		
		member.setup(hero_id, prev_unit, base_distance)
		member.z_index = -i
		
		# 이전 위치/플립 복원
		if positions.has(hero_id):
			member.global_position = positions[hero_id]
		
		get_parent().add_child(member)
		
		# 플립 상태는 노드 추가 후 적용 (sprite가 준비된 후)
		if flips.has(hero_id):
			await get_tree().process_frame
			if is_instance_valid(member) and member.sprite:
				member.sprite.flip_h = flips[hero_id]
				if member.is_dead:
					member._update_dead_rotation()
		
		party_members.append(member)
		prev_unit = member
	
	print("[Player] 파티 체인 재구성 완료, 멤버 수: ", party_members.size())


func get_party_member_by_id(hero_id: String) -> PartyMember:
	for member in party_members:
		if is_instance_valid(member) and member.hero_id == hero_id:
			return member
	return null


## 리더 유닛 반환 (적 추적용)
func get_leader_unit() -> Node2D:
	return self


func _on_hero_died(hero_id: String) -> void:
	# 현재 리더가 죽었고, 전멸이면 리더도 쓰러짐
	if hero_id == current_leader_id and GameManager.is_party_dead():
		_apply_leader_dead_visual()


func _apply_leader_dead_visual() -> void:
	if is_dead:
		return
	
	is_dead = true
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	
	tween.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.3)
	
	var target_rotation = 90.0 if not sprite.flip_h else -90.0
	tween.tween_property(sprite, "rotation_degrees", target_rotation, 0.3)
