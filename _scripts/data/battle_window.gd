# _scripts/ui/battle_window.gd
extends Control

# --- [1. 노드 연결] ---
@onready var enemy_group = $Panel/EnemyGroup
@onready var action_bar = $ActionBar

# --- [2. 데이터/설정] ---
var popup_text_scene = preload("res://scenes/ui/floating_text.tscn")

var attack_speed = 300.0 
var damage = 80         

func _ready():
	action_bar.max_value = 100
	action_bar.value = 0
	
	var monster_count = randi_range(1, 3)
	for i in range(monster_count):
		spawn_enemy()

func _process(delta):
	action_bar.value += attack_speed * delta
	
	if action_bar.value >= action_bar.max_value:
		perform_attack()
		action_bar.value = 0

# --- [3. 몬스터 생성] ---
func spawn_enemy():
	var enemy_slot = VBoxContainer.new()
	enemy_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# A. 체력바
	var hp = ProgressBar.new()
	hp.max_value = 100
	hp.value = 100
	hp.custom_minimum_size = Vector2(40, 10)
	hp.show_percentage = false
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(1, 0.3, 0.3)
	hp.add_theme_stylebox_override("fill", style_box)
	
	# B. 이미지
	var tex_rect = TextureRect.new()
	# (본인 프로젝트 이미지 경로로 수정하세요!)
	tex_rect.texture = load("res://sprites/monsters/aqua_slime.png") 
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(20, 20)

	
	# C. 조립
	enemy_slot.add_child(hp)       
	enemy_slot.add_child(tex_rect) 
	
	# D. 그룹에 추가
	enemy_group.add_child(enemy_slot)

# --- [4. 공격 로직] ---
func perform_attack():
	# enemy_group에는 이제 진짜 '몬스터 슬롯'만 들어있음!
	var live_enemies = enemy_group.get_children()
	
	if live_enemies.size() > 0:
		var target_slot = live_enemies.pick_random()
		var target_hp_bar = target_slot.get_child(0) 
		
		target_hp_bar.value -= damage
		
		# [수정 포인트 1] 데미지 함수 호출
		show_damage(damage, target_slot)
		
		var tween = create_tween()
		tween.tween_property(self, "position", position + Vector2(3, 0), 0.05)
		tween.tween_property(self, "position", position, 0.05)
		
		if target_hp_bar.value <= 0:
			target_slot.queue_free()
			
			# (주의: 방금 죽인 1마리가 포함된 상태라 개수가 1개 이하면 전멸로 침)
			if enemy_group.get_child_count() <= 1: 
				win_battle()
	else:
		win_battle()

# --- [5. 데미지 텍스트 띄우기 (여기가 중요!)] ---
func show_damage(amount, target_node):
	var popup = popup_text_scene.instantiate()
	popup.set_text_value(amount, Color(1, 0.3, 0.3))
	
	# [수정 포인트 2] 
	# 팝업을 'EnemyGroup'에 넣지 말고, 'BattleWindow(self)'에 넣어야 함!
	# 그래야 공격 로직이 팝업을 몬스터로 착각하지 않음.
	add_child(popup)
	
	# [수정 포인트 3]
	# 위치는 '절대 좌표(global_position)'를 기준으로 잡으면 아주 편함.
	# 몬스터 머리 위(Y - 20)에 띄우기
	popup.global_position = target_node.global_position + Vector2(10, -20)

# --- [6. 승리] ---
func win_battle():
	var popup = popup_text_scene.instantiate()
	popup.set_text_value("GOLD +50", Color(1, 0.8, 0.2))
	
	# 승리 메시지도 윈도우 중앙에
	popup.position = size / 2 - Vector2(30, 10)
	popup.scale = Vector2(1.5, 1.5)
	add_child(popup)
	
	var timer = get_tree().create_timer(0.8)
	await timer.timeout
	
	queue_free()
