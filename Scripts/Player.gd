extends CharacterBody2D

# 스네이크 무브먼트 구현
# 3명의 동료를 위한 변수
@export var follower_scene: PackedScene # PartyMember 씬을 여기에 드래그해서 넣으세요
@export var jobs: Array[Resource] # 직업 데이터(JobData) 3개를 여기에 넣으세요

const SPEED = 150.0
const HISTORY_GAP = 9 # 앞사람과의 간격 (프레임 수 or 거리)

# 이동 기록을 저장할 배열
var position_history: Array[Vector2] = []
var followers: Array[Node2D] = []

@onready var sprite = $Sprite2D

func _ready():
	# 동료 3명 생성 및 배치
	for i in range(3): 
		if i < jobs.size():
			var new_follower = follower_scene.instantiate()
			
			# 1. 텍스처 먼저 설정 (이제 PartyMember 코드를 고쳐서 에러 안 남)
			new_follower.setup(jobs[i].sprite)
			
			# 2. 월드(Scene)에 추가
			get_parent().call_deferred("add_child", new_follower)
			
			# 3. 내 관리 목록에 추가
			followers.append(new_follower)

func _physics_process(delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# 1. 플레이어 이동
	if direction:
		velocity = direction * SPEED
		
		# 왼쪽을 바라보는 스프라이트, 움직임에 따라 좌우 반전
		if direction.x < 0:
			sprite.flip_h = false # 원본이 왼쪽
		elif direction.x > 0:
			sprite.flip_h = true
			
		move_and_slide()
		
		# 2. 이동 기록 저장 (움직일 때만)
		position_history.push_front(global_position)
		
		# 메모리 관리를 위해 너무 긴 기록은 삭제 (동료 수 * 간격 + 여유분)
		if position_history.size() > 500:
			position_history.pop_back()
			
	# 3. 동료 이동 (스네이크)
	# 움직이지 않아도 동료는 제자리에 있어야 하므로 여기는 if direction 밖에서도 처리 가능하지만
	# 드퀘 스타일은 멈추면 딱 멈추므로 움직일 때만 갱신하는 게 자연스러움.
	if direction:
		for i in range(followers.size()):
			var target_index = (i + 1) * HISTORY_GAP
			if target_index < position_history.size():
				followers[i].move_to(position_history[target_index])
