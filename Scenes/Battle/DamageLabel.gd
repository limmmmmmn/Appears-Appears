extends Label

# [수정] 색상과 크기를 인스펙터에서 조절 가능하게 변경
@export_group("Settings")
@export var normal_color: Color = Color.WHITE
@export var crit_color: Color = Color.YELLOW
@export var crit_scale: Vector2 = Vector2(1.5, 1.5)
@export var float_distance: float = 50.0 # 위로 뜨는 거리
@export var duration: float = 0.5 # 사라지는 시간

func setup(amount: int, is_crit: bool):
	text = str(amount)
	
	if is_crit:
		modulate = crit_color # 변수 사용
		scale = crit_scale    # 변수 사용
		text += "!"
	else:
		modulate = normal_color
		scale = Vector2.ONE

	# 애니메이션 설정 (변수 사용)
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 변수로 설정한 거리와 시간 사용
	tween.tween_property(self, "position:y", position.y - float_distance, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
	tween.tween_property(self, "modulate:a", 0.0, duration).set_delay(duration * 0.4)
	
	await tween.finished
	queue_free()
