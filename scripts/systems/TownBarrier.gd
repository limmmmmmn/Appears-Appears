extends RefCounted
class_name TownBarrier
## 마을 결계 시스템 - 전투 중 마을 진입 차단

var town_area: Area2D
var barrier: StaticBody2D
var barrier_visual: ColorRect
var speech_bubble: Control
var speech_timer: Timer
var tween: Tween
var parent: Node


func setup(p_parent: Node, p_town_area: Area2D) -> void:
	parent = p_parent
	town_area = p_town_area
	
	if not town_area:
		return
	
	_create_barrier()
	_create_speech_bubble()
	_connect_signals()
	
	# 초기 상태
	if BattleManager and BattleManager.get_active_battle_count() == 0:
		deactivate()
	else:
		activate()


func cleanup() -> void:
	if barrier:
		barrier.queue_free()
	if speech_timer and is_instance_valid(speech_timer):
		speech_timer.queue_free()


#=============================================================================
# 결계 활성화/비활성화
#=============================================================================
func activate() -> void:
	## 결계 활성화 (전투 시작 시)
	if not barrier:
		return
	
	barrier.visible = true
	barrier.process_mode = Node.PROCESS_MODE_INHERIT
	
	if barrier_visual:
		barrier_visual.modulate.a = 0
		_kill_tween()
		tween = parent.create_tween()
		tween.tween_property(barrier_visual, "modulate:a", 1.0, 0.3)
		tween.tween_property(barrier_visual, "modulate:a", 0.6, 0.8)
		tween.tween_property(barrier_visual, "modulate:a", 1.0, 0.8)
		tween.set_loops()


func deactivate() -> void:
	## 결계 비활성화 (전투 종료 시)
	if not barrier:
		return
	
	_hide_speech_bubble()
	_kill_tween()
	
	if barrier_visual:
		tween = parent.create_tween()
		tween.tween_property(barrier_visual, "modulate:a", 0.0, 0.5)
		tween.tween_callback(_finish_deactivate)
	else:
		_finish_deactivate()


func _finish_deactivate() -> void:
	if barrier:
		barrier.visible = false
		barrier.process_mode = Node.PROCESS_MODE_DISABLED


func _kill_tween() -> void:
	if tween and tween.is_valid():
		tween.kill()


#=============================================================================
# 결계 생성
#=============================================================================
func _create_barrier() -> void:
	barrier = StaticBody2D.new()
	barrier.name = "TownBarrier"
	barrier.collision_layer = 4
	barrier.collision_mask = 0
	town_area.add_child(barrier)
	
	# 충돌 shape
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(60, 60)
	shape.shape = rect
	barrier.add_child(shape)
	
	# 시각 효과 (보라색 반투명)
	barrier_visual = ColorRect.new()
	barrier_visual.size = Vector2(64, 64)
	barrier_visual.position = Vector2(-32, -32)
	barrier_visual.color = Color(0.6, 0.3, 0.8, 0.5)
	barrier.add_child(barrier_visual)
	
	# 테두리
	var border := ColorRect.new()
	border.size = Vector2(68, 68)
	border.position = Vector2(-34, -34)
	border.color = Color(0.8, 0.4, 1.0, 0.3)
	border.z_index = -1
	barrier.add_child(border)
	
	# 충돌 감지 Area
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	barrier.add_child(area)
	
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = Vector2(70, 70)
	area_shape.shape = area_rect
	area.add_child(area_shape)
	area.body_entered.connect(_on_barrier_touched)


func _create_speech_bubble() -> void:
	speech_bubble = Control.new()
	speech_bubble.z_index = 100
	town_area.add_child(speech_bubble)
	
	var panel := PanelContainer.new()
	panel.size = Vector2(180, 70)
	panel.position = Vector2(-90, -100)
	speech_bubble.add_child(panel)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.6, 0.4, 0.8, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	var label := Label.new()
	label.text = "몬스터를 데려올 셈인가?\n먼저 처치하고 오게나."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
	label.add_theme_font_size_override("font_size", 11)
	panel.add_child(label)
	
	# 말풍선 꼬리
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(0, 12)])
	tail.position = Vector2(0, -30)
	tail.color = Color(0.1, 0.1, 0.15, 0.95)
	speech_bubble.add_child(tail)
	
	speech_bubble.visible = false


func _connect_signals() -> void:
	if BattleManager:
		BattleManager.battle_started.connect(func(_id): activate())
		BattleManager.all_battles_ended.connect(func(): deactivate())


#=============================================================================
# 말풍선
#=============================================================================
func _on_barrier_touched(body: Node2D) -> void:
	if not body.is_in_group("party_leader"):
		return
	if not barrier or not barrier.visible:
		return
	_show_speech_bubble()


func _show_speech_bubble() -> void:
	if not speech_bubble:
		return
	
	speech_bubble.visible = true
	
	if speech_timer and is_instance_valid(speech_timer):
		speech_timer.queue_free()
	
	speech_timer = Timer.new()
	speech_timer.wait_time = 2.5
	speech_timer.one_shot = true
	speech_timer.timeout.connect(_hide_speech_bubble)
	parent.add_child(speech_timer)
	speech_timer.start()


func _hide_speech_bubble() -> void:
	if speech_bubble:
		speech_bubble.visible = false
