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


func _ready() -> void:
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# GameManager에 플레이어 등록
	GameManager.register_player(self)
	
	# 파티 순서 변경 시그널 연결
	GameManager.party_order_changed.connect(_on_party_order_changed)
	
	# 초기 리더 설정
	if not GameManager.party.is_empty():
		current_leader_id = GameManager.party[0]
	
	_load_leader_sprite()
	
	await get_tree().process_frame
	_spawn_party_members()


func _spawn_party_members() -> void:
	# 기존 파티원 정리
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
	## 파티 순서가 바뀌면 전체 재구성
	print("[Player] 파티 순서 변경 감지: ", new_order)
	
	var new_leader = GameManager.get_current_leader()
	
	if new_leader != current_leader_id and not new_leader.is_empty():
		# 리더 변경!
		current_leader_id = new_leader
		_load_leader_sprite()
		print("[Player] 새 리더: ", current_leader_id)
	
	# 파티원 체인 재구성
	_rebuild_party_chain()


func _rebuild_party_chain() -> void:
	## 파티원 체인 완전 재구성
	var party := GameManager.party
	
	# 현재 파티원들의 위치 저장
	var positions: Dictionary = {}
	for member in party_members:
		if is_instance_valid(member):
			positions[member.hero_id] = member.global_position
	
	# 기존 파티원 제거
	for member in party_members:
		if is_instance_valid(member):
			member.queue_free()
	party_members.clear()
	
	if party.size() <= 1:
		return
	
	var prev_unit: Node2D = self
	var base_distance := 22.0
	
	# 1번 인덱스부터 (0번은 리더 = Player)
	for i in range(1, party.size()):
		var hero_id: String = party[i]
		var member := party_member_scene.instantiate() as PartyMember
		
		member.setup(hero_id, prev_unit, base_distance)
		member.z_index = -i
		
		# 이전 위치가 있으면 그 위치에서 시작
		if positions.has(hero_id):
			member.global_position = positions[hero_id]
		
		get_parent().add_child(member)
		
		party_members.append(member)
		prev_unit = member
	
	print("[Player] 파티 체인 재구성 완료, 멤버 수: ", party_members.size())


func get_party_member_by_id(hero_id: String) -> PartyMember:
	## hero_id로 파티원 찾기
	for member in party_members:
		if is_instance_valid(member) and member.hero_id == hero_id:
			return member
	return null
