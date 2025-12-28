extends Control

@onready var container = $Panel/HBoxContainer
@onready var log_label = $LogPanel/LogLabel # 방금 만든 텍스트 라벨

# BattleUnit 클래스 수정
class BattleUnit:
	var name: String
	var hp: int
	var max_hp: int
	var attack: int
	var speed: int
	var cooldown: float = 0.0
	var is_enemy: bool
	var texture_node: TextureRect = null
	var hp_bar_node: Control = null # [추가] 내 HP바가 뭔지 기억해야 갱신 가능

# 아군과 적군 명단
var allies: Array[BattleUnit] = []
var enemies: Array[BattleUnit] = []
var battle_active: bool = false # 전투 중인가?

# [추가] HP바 씬을 미리 로드합니다.
var hp_bar_scene = preload("res://Scenes/UI/HPBar.tscn")

# [추가] 로그를 출력해달라고 요청하는 신호
signal log_requested(text_message)

# [수정] setup에서 파티 데이터(party_jobs)도 받습니다.
func setup(enemy_data: EnemyData, history: Array[Rect2], party_jobs: Array[Resource]) -> Rect2:
	pick_best_position(history)
	
	# 1. 아군 데이터 등록 (Resource -> BattleUnit 변환)
	for job in party_jobs:
		var unit = BattleUnit.new()
		unit.name = job.job_name # 직업 이름
		unit.hp = job.base_hp
		unit.max_hp = job.base_hp
		unit.attack = job.base_attack
		unit.speed = job.base_speed
		unit.is_enemy = false
		# 아군은 속도에 따라 랜덤 쿨타임 시작 (0~1초)
		unit.cooldown = randf_range(0.5, 2.0)
		allies.append(unit)

	# 2. 적군 데이터 등록 (1~3마리) 
	var enemy_count = randi_range(1, 3)
	for i in range(enemy_count):
		var unit = BattleUnit.new()
		unit.name = enemy_data.enemy_name
		unit.hp = enemy_data.hp
		unit.max_hp = enemy_data.hp
		unit.attack = enemy_data.attack
		unit.speed = enemy_data.speed
		unit.is_enemy = true
		unit.cooldown = randf_range(1.0, 3.0) # 적은 조금 더 늦게 공격 시작
		
# [수정] create_enemy_ui가 이제 (Texture, HPBar) 두 개를 건드릴 수 있게 객체를 넘깁니다.
		create_enemy_ui_for_unit(unit, enemy_data) # 함수 이름 살짝 변경 추천
		enemies.append(unit)

	# 전투 시작!
	battle_active = true
	log_message("몬스터가 나타났다!")
	
	return Rect2(position, size)

func _process(delta):
	if not battle_active:
		return
		
	# --- 자동 전투 로직 ---
	
	# 1. 아군 턴 계산
	for unit in allies:
		if unit.hp > 0:
			unit.cooldown -= delta * (unit.speed * 0.5) # 속도가 빠를수록 쿨타임 빨리 짐
			if unit.cooldown <= 0:
				execute_attack(unit, enemies)
				unit.cooldown = 3.0 # 공격 후 3초 쿨타임 (기본)

	# 2. 적군 턴 계산
	for unit in enemies:
		if unit.hp > 0:
			unit.cooldown -= delta * (unit.speed * 0.5)
			if unit.cooldown <= 0:
				execute_attack(unit, allies)
				unit.cooldown = 4.0 # 적은 조금 더 느리게

# 공격 실행 함수
func execute_attack(attacker: BattleUnit, targets: Array[BattleUnit]):
	# 살아있는 타겟 중 하나 랜덤 선택
	var valid_targets = targets.filter(func(u): return u.hp > 0)
	if valid_targets.is_empty():
		return # 때릴 대상이 없음 (이미 승리/패배 판정 났을 것임)
		
	var target = valid_targets.pick_random()
	
	# 데미지 계산 (단순 공격력 - 0)
	var damage = attacker.attack
	# 크리티컬 확률 (10%)
	if randf() < 0.1:
		damage *= 2
		log_message("%s의 치명적 공격! %s에게 %d 피해!" % [attacker.name, target.name, damage])
	else:
		log_message("%s의 공격! %s에게 %d 피해." % [attacker.name, target.name, damage])
		
		# 크리티컬! (빨간색, 굵게)
	if randf() < 0.1:
		damage *= 2
		log_message("[color=red][b]%s의 치명타![/b][/color] %s에게 %d 피해!" % [attacker.name, target.name, damage])
	else:
		# 일반 공격 (아군은 초록색, 적은 흰색 등)
		var color = "green" if not attacker.is_enemy else "white"
		log_message("[color=%s]%s[/color]의 공격! %s에게 %d 피해." % [color, attacker.name, target.name, damage])
	# 체력 깎기
	target.hp -= damage
	
	# [추가] HP바 즉시 갱신!
	if target.hp_bar_node:
		target.hp_bar_node.update_health(target.hp, target.max_hp)
	
	# 적군이 맞았을 때 깜빡거리는 효과 (피드백)
	if target.is_enemy and target.texture_node:
		var tween = create_tween()
		tween.tween_property(target.texture_node, "modulate", Color.RED, 0.1)
		tween.tween_property(target.texture_node, "modulate", Color.WHITE, 0.1)

	# 사망 처리
	if target.hp <= 0:
		log_message("%s 처치!" % target.name)
		if target.is_enemy:
			# 적 이미지 흐려지게 하기
			target.texture_node.modulate = Color(0.5, 0.5, 0.5, 0.5)
			
		check_battle_end()

# 전투 종료 체크
func check_battle_end():
	# 1. 적 전멸? (승리) 
	var enemies_alive = enemies.filter(func(e): return e.hp > 0).size()
	if enemies_alive == 0:
		battle_active = false
		log_message("전투 승리! 경험치와 골드 획득!")
		await get_tree().create_timer(0.1).timeout # 1.5초 뒤 닫힘
		queue_free() # 창 닫기
		return

	# 2. 아군 전멸? (패배 - 일단 로그만 띄움)
	var allies_alive = allies.filter(func(a): return a.hp > 0).size()
	if allies_alive == 0:
		battle_active = false
		log_message("전멸했습니다...")
		# 나중에는 마을로 귀환 로직 필요

# [수정] 로그 메시지 함수: 이제 직접 표시하지 않고 신호를 쏘아 보냅니다.
func log_message(text: String):
	# 월드(World)에게 이 메시지를 띄워달라고 전달!
	log_requested.emit(text)

# [수정] 복잡한 계산 없이, 가운데만 피하고 자유롭게 뜹니다.
func pick_best_position(_history): # _history 앞에 _를 붙여서 안 쓴다고 표시
	var viewport_size = get_viewport_rect().size
	
	# 1. 안전구역 (화면 중앙 플레이어 주변)
	# 여기는 절대 침범하지 않게 합니다.
	var center_pos = viewport_size / 2
	var safe_area = Rect2(center_pos - Vector2(30, 30), Vector2(30, 30))
	
	# 2. 랜덤 시도 (그냥 막 던져봅니다)
	for i in range(30):
		# [핵심] 화면 밖으로 삐져나가도 됩니다! (여유분 50픽셀)
		# -50 부터 시작하므로 왼쪽이나 위로 삐져나갈 수 있음
		var margin = 10.0 
		var x = randf_range(-margin, viewport_size.x - size.x + margin)
		var y = randf_range(-margin, viewport_size.y - size.y + margin)
		
		var candidate_rect = Rect2(Vector2(x, y), size)
		
		# 3. 플레이어(가운데)만 안 가리면 합격!
		# 이전 창들과 겹치든 말든 신경 안 씁니다.
		if not candidate_rect.intersects(safe_area):
			position = Vector2(x, y)
			return # 바로 위치 확정하고 끝!

	# 운 나쁘게 30번 다 실패하면? 그냥 왼쪽 구석 어딘가에 배치
	position = Vector2(-20, randf_range(0, 200))

# [함수 변경] 데이터를 받아서 UI를 만들고 unit에 연결하는 함수
func create_enemy_ui_for_unit(unit: BattleUnit, data: EnemyData):
	# 1. 이미지 생성
	var enemy_texture = TextureRect.new()
	enemy_texture.texture = data.sprite
	enemy_texture.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	enemy_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(enemy_texture)
	
	# 2. HP바 생성 및 부착
	var hp_bar = hp_bar_scene.instantiate()
	enemy_texture.add_child(hp_bar) # 이미지의 자식으로 붙임
	
# [수정된 위치 잡기 코드]
	# 1. 앵커를 이용해 '중앙 상단'으로 기준점을 잡습니다.
	hp_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	
	# 2. 위치 미세 조정 (x는 0이면 정중앙, y는 음수면 위로 올라감)
	# y를 -10 ~ -20 정도로 설정해서 머리 바로 위에 띄웁니다.
	hp_bar.position = Vector2(0, -8)
	
	# 초기값 설정
	hp_bar.update_health(unit.hp, unit.max_hp)
	
	# 3. Unit에 정보 저장
	unit.texture_node = enemy_texture
	unit.hp_bar_node = hp_bar
