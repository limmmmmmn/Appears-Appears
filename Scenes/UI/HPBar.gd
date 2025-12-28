# res://Scenes/UI/HPBar.gd
extends ProgressBar

# 체력 갱신 함수 (부드럽게 움직이면 더 귀여움)
func update_health(current_hp: int, max_hp: int):
	max_value = max_hp
	value = current_hp
	
	# (선택사항) 체력이 낮으면 빨간색으로 변하게 할 수도 있음
	# var style = get("theme_override_styles/fill")
	# if style:
	# 	if float(current_hp) / max_hp < 0.3:
	# 		style.bg_color = Color.RED
	# 	else:
	# 		style.bg_color = Color.GREEN
