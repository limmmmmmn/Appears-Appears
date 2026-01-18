extends CharacterBody2D
class_name Player
## 드퀘 스타일 필드 이동을 담당하는 플레이어

@export var move_speed: float = 80.0

var party_members: Array[PartyMember] = []
var party_member_scene: PackedScene = preload("res://scenes/player/party_member.tscn")

var encountered_enemies: Array = []  # 이미 만난 적 추적


@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	# 적과 충돌 감지 연결
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# GameManager에 플레이어 등록 (레벨업 연출용)
	GameManager.register_player(self)
	
	# 리더 캐릭터 스프라이트 로드
	_load_leader_sprite()
	
	# 파티원 생성
	await get_tree().process_frame
	_spawn_party_members()


func _spawn_party_members() -> void:
	var party := GameManager.party
	if party.size() <= 1:
		return
	
	var prev_unit: Node2D = self
	var base_distance := 22.0
	
	# 1번 인덱스부터 (0번은 플레이어 자신)
	for i in range(1, party.size()):
		var hero_id: String = party[i]
		var member := party_member_scene.instantiate() as PartyMember
		
		member.setup(hero_id, prev_unit, base_distance)
		member.z_index = -i  # 뒤에 있는 멤버일수록 뒤로
		get_parent().add_child(member)
		
		party_members.append(member)
		prev_unit = member


func _load_leader_sprite() -> void:
	if GameManager.party.is_empty():
		return
	
	var leader_id: String = GameManager.party[0]
	var hero_data := DataManager.get_hero(leader_id)
	if hero_data.is_empty():
		return
	
	var sprite_path: String = hero_data.get("visuals", {}).get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)


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
	# 왼쪽이 기본, 오른쪽 갈 때 뒤집기
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
