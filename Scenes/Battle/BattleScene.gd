extends Node

@onready var turn_system = $TurnSystem
@onready var ui_container = $UI/BattleContainer

# 화가(UnitDisplay) 연결 정보
var unit_visuals: Dictionary = {}
var unit_display_scene = preload("res://Scenes/Battle/UnitDisplay.tscn")

var allies: Array[BattleUnit] = []
var enemies: Array[BattleUnit] = []
var all_units: Array[BattleUnit] = []

func _ready():
	SignalBus.unit_damaged.connect(_on_unit_damaged)
	SignalBus.log_message.connect(func(msg): print(msg))

func start_battle(player_data: JobData, enemy_data: EnemyData):
	# 1. 유닛 데이터 생성 (로직은 그대로)
	var player_unit = BattleUnit.new(player_data, false)
	var enemy_unit = BattleUnit.new(enemy_data, true)
	
	allies.append(player_unit)
	enemies.append(enemy_unit)
	all_units = [player_unit, enemy_unit]
	
	# 2. [변경] 드래곤 퀘스트 스타일: 적만 보여줍니다!
	# 플레이어 디스플레이 생성 코드는 삭제했습니다.
	
	# 적을 창 한가운데 배치 (창 크기가 300x150이라고 가정할 때 중앙)
	# ui_container.size / 2 로 중앙을 잡고, 유닛 크기 절반을 빼면 정중앙
	var center_pos = Vector2(150, 75) - Vector2(32, 40) 
	create_display(enemy_unit, enemy_data.sprite, center_pos)
	
	# 3. [변경] 창 위치 랜덤 설정 (화면 여기저기!)
	set_random_window_position()
	
	# 4. 전투 시작! (자동)
	turn_system.turn_ready.connect(_on_turn_ready)
	turn_system.initialize(all_units)

# [New] 랜덤 위치 잡기 함수
func set_random_window_position():
	var screen_size = get_viewport().get_visible_rect().size
	var window_size = ui_container.size
	
	# 화면 밖으로 나가지 않게 안전 범위 계산
	var safe_x = screen_size.x - window_size.x
	var safe_y = screen_size.y - window_size.y
	
	# 랜덤 좌표 생성
	var random_x = randf_range(0, safe_x)
	var random_y = randf_range(0, safe_y)
	
	ui_container.position = Vector2(random_x, random_y)

func create_display(unit: BattleUnit, texture: Texture2D, pos: Vector2):
	var display = unit_display_scene.instantiate()
	ui_container.add_child(display)
	display.position = pos # 위에서 계산한 중앙 위치
	display.setup(texture, unit.unit_name, unit.max_hp)
	unit_visuals[unit] = display

# [자동 전투 로직]
func _on_turn_ready(unit: BattleUnit):
	await get_tree().create_timer(0.3).timeout
	
	var targets = []
	if unit.is_enemy:
		targets = allies.filter(func(u): return u.current_hp > 0)
	else:
		targets = enemies.filter(func(u): return u.current_hp > 0)
	
	if targets.is_empty(): return
	var target = targets.pick_random()
	_execute_attack(unit, target)

func _execute_attack(attacker: BattleUnit, target: BattleUnit):
	# 시각 효과: 공격자가 '보이는 녀석(적)'일 때만 애니메이션 재생
	if attacker in unit_visuals:
		unit_visuals[attacker].play_attack_animation()
	
	# 플레이어가 공격할 땐, 적이 '맞는 효과'만 나오면 됨 (드퀘 스타일)
	# 약간의 딜레이
	await get_tree().create_timer(0.3).timeout
	
	BattleManager.process_attack(attacker, target)
	
	await get_tree().create_timer(0.3).timeout
	
	if target.current_hp <= 0:
		_finish_battle(target.is_enemy)

func _finish_battle(is_victory: bool):
	turn_system.stop()
	await get_tree().create_timer(1.0).timeout
	
	if is_victory:
		print("🎉 몬스터 처치!")
		queue_free()
	else:
		print("💀 도망쳐!")
		queue_free()

func _on_unit_damaged(target, amount, is_crit):
	# [중요] 타겟이 '보이는 녀석(적)'일 때만 HP바 갱신
	# 플레이어가 맞을 땐 전투창에 아무 변화 없음 (드퀘처럼!)
	if target in unit_visuals:
		var display = unit_visuals[target]
		display.update_hp(target.current_hp)
		display.play_damage_effect()
		if target.current_hp <= 0:
			display.play_death()
	else:
		# (선택) 플레이어가 맞았을 땐 화면 전체가 번쩍이거나, 
		# 필드 위의 캐릭터 위로 데미지 폰트가 뜨게 하면 좋습니다.
		# 지금은 일단 로그만 찍힙니다.
		pass
