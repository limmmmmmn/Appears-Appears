# _scripts/ui/battle_window.gd
extends Control

@onready var enemy_group = $Panel/EnemyGroup
@onready var action_bar = $ActionBar

var attack_speed = 300.0 
var damage = 35

func _ready():
	# 1. 내 액션바 초기화
	action_bar.max_value = 100
	action_bar.value = 0
	
	# 2. 몬스터 랜덤 생성 (1마리 ~ 3마리)
	var monster_count = randi_range(1, 3)
	
	for i in range(monster_count):
		spawn_enemy()

func _process(delta):
	# 3. 오토 배틀: 게이지 차오름
	action_bar.value += attack_speed * delta
	
	if action_bar.value >= action_bar.max_value:
		perform_attack()
		action_bar.value = 0

# --- 몬스터 생성 함수 ---
func spawn_enemy():
	# 몬스터 한 마리를 위한 세트(VBox) 만들기
	var enemy_slot = VBoxContainer.new()
	
	# 1. 이미지 만들기
	var tex_rect = TextureRect.new()
	# (임시) 아이콘 이미지를 씀. 나중엔 monster_data에서 가져오면 됨
	tex_rect.texture = load("res://sprites/monsters/aqua_slime.png") 
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(20, 20) # 크기 지정
	tex_rect.modulate = Color(randf(), randf(), randf()) # 색깔 랜덤
	
	# 2. 체력바 만들기
	var hp = ProgressBar.new()
	hp.max_value = 100
	hp.value = 100
	hp.custom_minimum_size = Vector2(40, 10)
	hp.show_percentage = false # 숫자 끄기
	
	# 3. 조립하기 (슬롯에 이미지+체력바 넣기)
	enemy_slot.add_child(hp)       # 위에 체력바
	enemy_slot.add_child(tex_rect) # 아래에 몬스터
	
	# 4. 그룹(화면)에 추가
	enemy_group.add_child(enemy_slot)

# --- 공격 함수 ---
func perform_attack():
	# 살아있는 몬스터 찾기
	var live_enemies = enemy_group.get_children()
	
	if live_enemies.size() > 0:
		# 랜덤하게 한 놈 골라서 때리기
		var target_slot = live_enemies.pick_random()
		var target_hp_bar = target_slot.get_child(0) # 0번이 체력바였지?
		
		target_hp_bar.value -= damage
		
		# 때리는 연출 (창 흔들기)
		var tween = create_tween()
		tween.tween_property(self, "position", position + Vector2(3, 0), 0.05)
		tween.tween_property(self, "position", position, 0.05)
		
		print("공격! 남은 체력:", target_hp_bar.value)

		# 죽었는지 확인
		if target_hp_bar.value <= 0:
			target_slot.queue_free() # 그 몬스터만 삭제
			
			# 다 죽었는지 확인 (방금 죽인 놈 빼고 남은 게 없으면)
			if enemy_group.get_child_count() <= 1: 
				win_battle()
	else:
		win_battle()

func win_battle():
	print("전원 처치! 승리!")
	queue_free() # 창 닫기
