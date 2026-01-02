# res://Scenes/Battle/DamagePopup.gd
extends Label

func setup(amount: int, color: Color = Color.WHITE):
	text = str(amount)
	label_settings = label_settings.duplicate() # 고유 설정 사용
	label_settings.font_color = color
	
	# 중앙 정렬을 위해 피벗 조정 (글자 길이에 따라 다를 수 있어 생략 가능하나 권장)
	# pivot_offset = size / 2 

	animate()

func animate():
	# 위치 보정 (살짝 위에서 시작하거나 랜덤성 부여)
	position += Vector2(randf_range(-10, 10), -20)
	
	var tween = create_tween()
	tween.set_parallel(true) # 동시에 실행
	
	# 1. 위로 둥실 떠오르기 (Y축 이동)
	tween.tween_property(self, "position:y", position.y - 50, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 2. 투명해지기 (Alpha)
	tween.tween_property(self, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	
	# 3. 톡 튀어오르는 크기 변화 (커졌다가 작아짐) - 쥬시함 추가!
	var scale_tween = create_tween()
	scale = Vector2(0.5, 0.5) # 작게 시작
	scale_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# 애니메이션 끝나면 삭제
	await tween.finished
	queue_free()
