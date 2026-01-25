extends CharacterBody2D
class_name PartyFollower
## 파티 팔로워: 리더의 이동 경로를 Snake처럼 따라감
## 스프라이트 위에 HP바 + ATB바 표시 (씬에서 참조)

@export var follow_index: int = 1
@export var follow_speed: float = 90.0

var leader: PartyLeader = null
var target_position: Vector2 = Vector2.ZERO
var facing_right: bool = false
var hero_id: String = ""
var hero_data: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $StatusBars/HPBar
@onready var atb_bar: ProgressBar = $StatusBars/ATBBar


func _ready() -> void:
	add_to_group("party_follower")
	add_to_group("party")
	
	# BattleManager ATB 시그널 연결
	if BattleManager:
		BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)


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
	
	# HP 바 업데이트
	_update_hp_bar()


func _update_hp_bar() -> void:
	if not hp_bar or hero_id.is_empty():
		return
	
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero:
		var percent: float = float(hero.current_hp) / float(hero.get_max_hp()) * 100.0
		hp_bar.value = percent
		
		# HP 낮으면 색상 변경
		var fill_style: StyleBoxFlat = hp_bar.get_theme_stylebox("fill").duplicate()
		if percent <= 25:
			fill_style.bg_color = Color(0.9, 0.2, 0.2)
		elif percent <= 50:
			fill_style.bg_color = Color(0.9, 0.7, 0.2)
		else:
			fill_style.bg_color = Color(0.2, 0.8, 0.2)
		hp_bar.add_theme_stylebox_override("fill", fill_style)


func _on_hero_atb_changed(changed_hero_id: String, value: float) -> void:
	if changed_hero_id == hero_id and atb_bar:
		atb_bar.value = value * 100.0
		
		# ATB가 거의 찼을 때 색상 변경
		var fill_style: StyleBoxFlat = atb_bar.get_theme_stylebox("fill").duplicate()
		if value >= 0.9:
			fill_style.bg_color = Color(1.0, 1.0, 0.5)
		else:
			fill_style.bg_color = Color(1.0, 0.8, 0.2)
		atb_bar.add_theme_stylebox_override("fill", fill_style)


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
		
		if SpriteManager:
			var tex: Texture2D = SpriteManager.get_hero_field_sprite(hero_id)
			if tex:
				sprite.texture = tex
				sprite.scale = Vector2(1, 1)
	
	# 초기 HP 업데이트
	_update_hp_bar()
