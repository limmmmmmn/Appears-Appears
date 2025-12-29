# res://Scenes/Field/Player.gd
extends CharacterBody2D

# 1. 데이터 (기획자가 만지는 부분)
@export var job_data: JobData 

# 2. 컴포넌트 가져오기 (기능 담당)
@onready var health_comp = $HealthComponent
@onready var move_comp = $MoveComponent

func _ready():
	# 데이터가 있으면 체력 블록을 초기화
	if job_data:
		health_comp.init(job_data.base_hp)
		# 이미지도 여기서 설정 가능
		if $Sprite2D and job_data.sprite:
			$Sprite2D.texture = job_data.sprite

func _physics_process(delta):
	# 3. 입력은 내가 받지만, 이동은 'MoveComponent' 야, 네가 해!
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	move_comp.handle_move(direction)

# 테스트용: 스페이스바 누르면 자해(?)해서 피 깎이는지 확인
func _input(event):
	if event.is_action_pressed("ui_accept"): # SpaceBar
		health_comp.take_damage(10)
		print("현재 체력: ", health_comp.current_hp)
