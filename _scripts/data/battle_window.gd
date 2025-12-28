# _scripts/ui/battle_window.gd
extends Control

# --- 노드 연결 ---
@onready var enemy_group = $Panel/EnemyGroup
@onready var action_bar = $ActionBar

# --- 설정값 ---
var popup_text_scene = preload("res://scenes/ui/floating_text.tscn")
var attack_speed = 200.0

# [추가] 몬스터 공격 타이머
var enemy_timer: float = 0.0
var enemy_attack_delay: float = 1.0 # 1초마다 때림
var enemy_damage: int = 5           # 몬스터 공격력

func _ready():
	action_bar.max_value = 100
	action_bar.value = 0
	
	# 몬스터 생성 (1~3마리)
	var monster_count = randi_range(1, 3)
	for i in range(monster_count):
		spawn_enemy()
		
	# [추가] 플레이어가 죽었을 때 신호 연결
	PlayerData.player_died.connect(_on_player_died)

func _process(delta):
	# 1. 내 턴 (게이지 차오름)
	action_bar.value += attack_speed * delta
	if action_bar.value >= action_bar.max_value:
		perform_attack()
		action_bar.value = 0
		
	# [추가] 2. 몬스터 턴 (시간 체크)
	enemy_timer += delta
	if enemy_timer >= enemy_attack_delay:
		enemy_timer = 0
		perform_enemy_attack() # 몬스터가 때림!

# 몬스터 생성
func spawn_enemy():
	var enemy_slot = VBoxContainer.new()
	enemy_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var hp = ProgressBar.new()
	hp.max_value = 100
	hp.value = 100
	hp.custom_minimum_size = Vector2(10, 2)
	hp.show_percentage = false
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(1, 0.3, 0.3)
	hp.add_theme_stylebox_override("fill", style_box)
	
	var tex_rect = TextureRect.new()
	tex_rect.texture = load("res://sprites/monsters/aqua_slime.png") # 이미지 경로 확인!
	tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(10, 10)
	tex_rect.modulate = Color(randf(), randf(), randf())
	
	enemy_slot.add_child(hp)       
	enemy_slot.add_child(tex_rect) 
	enemy_group.add_child(enemy_slot)

# 내 공격
func perform_attack():
	var live_enemies = enemy_group.get_children()
	
	if live_enemies.size() > 0:
		var target_slot = live_enemies.pick_random()
		var target_hp_bar = target_slot.get_child(0) 
		
		# PlayerData 공격력 사용
		var dmg = PlayerData.attack_power
		target_hp_bar.value -= dmg
		
		show_damage(dmg, target_slot, Color(1, 0.3, 0.3)) # 빨간색
		
		# 타격감 연출
		var tween = create_tween()
		tween.tween_property(self, "position", position + Vector2(3, 0), 0.05)
		tween.tween_property(self, "position", position, 0.05)
		
		if target_hp_bar.value <= 0:
			target_slot.queue_free()
			if enemy_group.get_child_count() <= 1: 
				win_battle()
	else:
		win_battle()

# [추가] 몬스터 공격
func perform_enemy_attack():
	if enemy_group.get_child_count() > 0:
		# 내 체력 깎기
		PlayerData.take_damage(enemy_damage)
		
		# 화면 빨갛게 깜빡!
		var tween = create_tween()
		modulate = Color(1, 0.5, 0.5)
		tween.tween_property(self, "modulate", Color.WHITE, 0.1)
		
		# 데미지 숫자 띄우기 (화면 중앙)
		var popup = popup_text_scene.instantiate()
		popup.set_text_value("-%d" % enemy_damage, Color(1, 0, 0)) # 새빨강
		popup.position = size / 2 
		add_child(popup)

# 데미지 텍스트 띄우기 (공통 함수)
func show_damage(amount, target_node, color):
	var popup = popup_text_scene.instantiate()
	popup.set_text_value(amount, color)
	add_child(popup)
	if target_node:
		popup.global_position = target_node.global_position + Vector2(10, -20)

# 승리
func win_battle():
	PlayerData.add_gold(50)
	PlayerData.add_xp(40) # 경험치도 줌!
	
	var popup = popup_text_scene.instantiate()
	popup.set_text_value("VICTORY!", Color(1, 0.8, 0.2))
	popup.position = size / 2 - Vector2(30, 10)
	popup.scale = Vector2(1.5, 1.5)
	add_child(popup)
	
	var timer = get_tree().create_timer(0.8)
	await timer.timeout
	queue_free()

# [추가] 사망
func _on_player_died():
	print("사망!")
	PlayerData.heal_hp_full() # 임시 부활
	queue_free()
