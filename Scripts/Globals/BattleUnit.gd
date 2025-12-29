# res://Scripts/Globals/BattleUnit.gd
class_name BattleUnit extends RefCounted

# 실제 전투에서 쓸 변수들
var unit_name: String
var max_hp: int
var current_hp: int
var attack: int
var speed: int
var is_enemy: bool

# 쿨타임 (턴제 시스템용)
var cooldown: float = 0.0

var sprite: Texture2D # [New] 내 사진

# 생성자 (데이터를 넣으면 전투 유닛으로 변환)
func _init(data, _is_enemy: bool):
	is_enemy = _is_enemy
	
	if is_enemy:
		# EnemyData에서 가져오기
		unit_name = data.enemy_name
		max_hp = data.max_hp
		attack = data.attack
		speed = data.speed
		sprite = data.sprite # [추가] 사진 저장
	else:
		# JobData에서 가져오기
		unit_name = data.job_name
		max_hp = data.base_hp
		attack = data.base_attack
		speed = data.base_speed
		sprite = data.sprite # [추가] 사진 저장
	
	current_hp = max_hp
	# 속도가 빠를수록 시작 쿨타임이 짧게 (랜덤성 추가)
	cooldown = randf_range(0.5, 2.0)

# 기능: 데미지 받기
func take_damage(amount: int):
	current_hp = max(0, current_hp - amount)
	# 죽었는지 살았는지 반환
	return current_hp == 0 

# 기능: 힐 받기
func heal(amount: int):
	current_hp = min(max_hp, current_hp + amount)
