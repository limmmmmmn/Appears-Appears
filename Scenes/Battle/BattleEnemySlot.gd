# res://Scenes/Battle/BattleEnemySlot.gd
extends TextureRect

# [NEW] 데미지 팝업 씬 미리 불러오기
var popup_scene = preload("res://Scenes/Battle/DamagePopup.tscn")

@onready var hp_bar = $HPBar

var enemy_data: EnemyData
var current_hp: int
var current_cooldown: float = 0.0
var max_cooldown: float = 2.0

func setup(data: EnemyData):
	enemy_data = data
	current_hp = data.max_hp
	
	if data.texture:
		texture = data.texture
	else:
		texture = load("res://icon.svg")
	
	hp_bar.max_value = data.max_hp
	hp_bar.value = current_hp
	
	# [중요] 애니메이션을 위해 중심점을 이미지 가운데로 설정
	# 이게 없으면 확대/회전할 때 좌상단 기준으로 움직여서 이상해짐
	pivot_offset = size / 2
	
	max_cooldown = max(0.5, 20.0 / float(max(1, data.agility)))
	current_cooldown = randf_range(0, max_cooldown)

# [NEW] 공격 애니메이션 (플레이어 쪽으로 줌인)
func animate_attack():
	var tween = create_tween()
	# 1. 커지면서 앞으로 튀어나옴 (0.1초)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2. 다시 원래 크기로 복귀 (0.1초)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

# [NEW] 피격 애니메이션 (빨갛게 번쩍 + 부르르 떨기)
func animate_damage():
	var tween = create_tween()
	
	# 1. 색상 번쩍임 (빨강 -> 원래대로)
	tween.tween_property(self, "modulate", Color(2.0, 0.2, 0.2), 0.05) # 강렬한 빨강 (밝기 부스트)
	tween.tween_property(self, "modulate", Color.WHITE, 0.05)
	
	# 2. 쉐이크 효과 (좌우 회전으로 충격 표현)
	# 동시에 진행하기 위해 set_parallel(true) 사용 가능하지만, 간단히 순차적으로 떪
	var shake_tween = create_tween()
	for i in range(3):
		shake_tween.tween_property(self, "rotation_degrees", 5, 0.03)
		shake_tween.tween_property(self, "rotation_degrees", -5, 0.03)
	shake_tween.tween_property(self, "rotation_degrees", 0, 0.03)

func take_damage(amount: int):
	current_hp -= amount
	hp_bar.value = current_hp
	
	animate_damage() # 기존 피격 모션
	
	# [NEW] 데미지 숫자 띄우기
	if popup_scene:
		var popup = popup_scene.instantiate()
		# 슬롯의 자식으로 넣으면 슬롯이 움직일 때 같이 움직임
		# 혹은 부모(BattleScene)에 넣어도 됨. 여기선 간단히 자식으로 추가.
		add_child(popup)
		
		# 위치: 이미지의 정중앙 혹은 머리 위
		popup.position = size / 2 
		
		# 실행 (흰색 or 치명타면 빨강 등 색상 지정 가능)
		popup.setup(amount, Color.WHITE)

func is_dead() -> bool:
	return current_hp <= 0
