# res://Components/WindowPositionComponent.gd
class_name WindowPositionComponent extends Node

# 움직일 대상 (인스펙터에서 BattleContainer를 넣어줄 겁니다)
@export var target_control: Control
@export var padding: float = 20.0 # 화면 끝에서 얼마나 띄울지

# 1. 랜덤 위치로 이동시키는 기능
func apply_random_position():
	if not target_control:
		push_error("이동할 타겟(Target Control)이 연결되지 않았습니다!")
		return
		
	# 앵커를 안전하게 'Top-Left'로 강제 초기화 (혹시 모르니까)
	target_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	
	var screen_size = get_viewport().get_visible_rect().size
	var window_size = target_control.size
	
	# 안전 구역 계산
	var safe_x = screen_size.x - window_size.x - padding
	var safe_y = screen_size.y - window_size.y - padding
	
	# 랜덤 좌표
	var rand_x = randf_range(padding, safe_x)
	var rand_y = randf_range(padding, safe_y)
	
	target_control.position = Vector2(rand_x, rand_y)

# (나중에 추가 가능한 기능들)
# func apply_center_position(): ...
# func apply_grid_position(index): ...
