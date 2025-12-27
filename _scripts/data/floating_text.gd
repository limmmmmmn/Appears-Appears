# _scripts/ui/floating_text.gd
extends Label

func _ready():
	# 등장하자마자 위로 둥실 떠오르면서 사라지는 연출 (Tween)
	var tween = create_tween()
	tween.set_parallel(true) # 동시에 실행
	
	# 1. 위로 30px 이동
	tween.tween_property(self, "position", position + Vector2(0, -30), 0.5)
	# 2. 투명해지기 (Alpha 0)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	
	# 3. 끝나면 삭제 (메모리 청소)
	tween.chain().tween_callback(queue_free)

# 외부에서 숫자랑 색깔을 정해주는 함수
func set_text_value(value, color: Color):
	text = str(value)
	modulate = color # 글자 색 변경 (데미지는 빨강, 회복은 초록 등)
