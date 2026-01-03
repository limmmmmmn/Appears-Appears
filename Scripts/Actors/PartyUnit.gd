class_name PartyUnit extends CharacterBody2D

# [핵심 변수]
@export var unit_data: UnitData # 인스펙터에서 데이터를 넣을 수 있게 함
var is_leader: bool = false # 리더 여부 [cite: 20]
var target_unit: Node2D = null # 나중에 스네이크 이동에 쓸 변수

@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready():
	# 데이터가 있으면 초기화 및 이미지 적용 [cite: 22]
	if unit_data:
		unit_data.initialize()
		if unit_data.sprite_texture:
			sprite_2d.texture = unit_data.sprite_texture

func _physics_process(delta):
	if is_leader:
		_leader_movement()
	else:
		_follower_movement()

# [리더 로직] WASD 이동 처리 [cite: 21]
func _leader_movement():
	var input_vector = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vector * 200 # 이동 속도 200 (조절 가능)
	move_and_slide()

# [동료 로직] Phase 4에서 구현 예정 (지금은 비워둠)
func _follower_movement():
	pass
