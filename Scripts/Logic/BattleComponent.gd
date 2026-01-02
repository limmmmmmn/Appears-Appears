extends Node
class_name BattleComponent

# 공격 준비 완료 신호
signal attack_ready 

# 데이터 연결
var stats: BattleStats
var cooldown_timer: float = 0.0
var is_active: bool = false

# 초기화 함수 (부모가 데이터를 넣어줘야 함)
func initialize(_stats: BattleStats):
	stats = _stats
	if stats:
		is_active = true
		
		# [팁] 전투 시작 시 모두가 동시에 때리는 걸 막기 위해
		# 첫 공격은 랜덤하게 0초 ~ 최종쿨타임 사이에서 시작!
		var first_cooldown = stats.get_final_cooldown()
		cooldown_timer = randf_range(0.0, first_cooldown)

func _process(delta):
	if not is_active or not stats: return

	# 1. 시간 깎기
	cooldown_timer -= delta
	
	# 2. 시간이 0이 되면 공격!
	if cooldown_timer <= 0.0:
		_perform_attack()

func _perform_attack():
	# 부모에게 "공격해!" 신호 보냄
	attack_ready.emit()
	
	# 3. 쿨타임 리셋 (공식 적용)
	# 약간의 랜덤(-0.1 ~ +0.1초)을 섞어주면 기계적인 느낌이 사라짐
	var final_cd = stats.get_final_cooldown()
	var jitter = randf_range(-0.1, 0.1)
	
	cooldown_timer = final_cd + jitter
	
	# (디버깅용) 로그 찍어보기
	# print("공격! 다음 쿨타임: ", cooldown_timer)
