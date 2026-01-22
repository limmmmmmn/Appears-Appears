extends CharacterBody2D
class_name PartyFollower
## 파티 팔로워: 리더의 이동 경로를 Snake처럼 따라감

@export var follow_index: int = 1
@export var follow_speed: float = 90.0

var leader: PartyLeader = null
var target_position: Vector2 = Vector2.ZERO
var facing_right: bool = false
var hero_id: String = ""
var hero_data: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("party_follower")
	add_to_group("party")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(leader):
		return
	
	target_position = leader.get_position_at_offset(follow_index)
	var distance := global_position.distance_to(target_position)
	
	if distance > 4.0:
		var direction := (target_position - global_position).normalized()
		velocity = direction * follow_speed
		_update_facing(direction.x)
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func _update_facing(x_direction: float) -> void:
	if x_direction > 0.1:
		facing_right = true
		sprite.flip_h = true
	elif x_direction < -0.1:
		facing_right = false
		sprite.flip_h = false


func setup(p_leader: PartyLeader, p_index: int, hero: RefCounted = null) -> void:
	leader = p_leader
	follow_index = p_index
	global_position = leader.get_position_at_offset(follow_index)
	facing_right = leader.get_facing_right()
	sprite.flip_h = facing_right
	
	if hero:
		hero_id = hero.id
		hero_data = {
			"id": hero.id,
			"name": hero.hero_name,
			"class_id": hero.class_id
		}
		
		# SpriteManager에서 스프라이트 로드
		if SpriteManager:
			var tex: Texture2D = SpriteManager.get_hero_field_sprite(hero_id)
			if tex:
				sprite.texture = tex
				sprite.scale = Vector2(1, 1)
