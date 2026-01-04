extends Control
class_name BattleWindow

# --- UI 참조 ---
@onready var enemy_name_lbl: Label = $Background/MarginContainer/VBoxContainer/EnemyName
@onready var enemy_visual: TextureRect = $Background/MarginContainer/VBoxContainer/EnemyVisual
@onready var enemy_hp_bar: ProgressBar = $Background/MarginContainer/VBoxContainer/EnemyHP
@onready var battle_timer: Timer = $BattleTimer

# --- 데이터 ---
var enemy_data: UnitData
var player_data: UnitData # [설계도 154] 공격자 정보 필요

# --- [설계도 151] 의존성 주입 (Setup) ---
func setup(p_data: UnitData, e_data: UnitData) -> void:
	player_data = p_data
	enemy_data = e_data
	
	# UI 초기화
	enemy_name_lbl.text = enemy_data.name
	enemy_visual.texture = enemy_data.sprite
	
	_update_hp_bar()
	
	# 시그널 연결 (적의 체력 변화 감지)
	if not enemy_data.hp_changed.is_connected(_on_hp_changed):
		enemy_data.hp_changed.connect(_on_hp_changed)
	if not enemy_data.dead.is_connected(_on_enemy_dead):
		enemy_data.dead.connect(_on_enemy_dead)
		
	# 전투 루프 시작 [설계도 152]
	battle_timer.start()

# --- [설계도 152] 전투 루프 (Timer 기반) ---
func _on_battle_timer_timeout() -> void:
	# 1. 플레이어 턴: 적 공격
	_perform_attack(player_data, enemy_data)
	
	# 적이 죽었으면 루프 중단
	if enemy_data.current_hp <= 0:
		battle_timer.stop()
		return
		
	# 2. 적 턴: 플레이어 공격 (단순화를 위해 동시 공격 처리 혹은 0.5초 딜레이 가능)
	# 여기서는 플레이어가 때리고 0.5초 뒤 적이 반격하는 느낌으로 타이머 하나로 처리하거나
	# 별도 코루틴을 쓸 수 있습니다. 간단하게 "서로 한 대씩 주고받음"으로 구현합니다.
	
	await get_tree().create_timer(0.5).timeout
	if enemy_data.current_hp > 0: # 적이 살아있다면 반격
		_perform_attack(enemy_data, player_data)

# --- 공격 로직 [설계도 154-156] ---
func _perform_attack(attacker: UnitData, defender: UnitData) -> void:
	# 1. 스킬 선택 (지금은 기본 공격 = skills[0] 혹은 기본 스탯)
	var damage = attacker.get_total_stat("atk")
	var skill_name = "평타"
	
	# 스킬 데이터가 있다면 활용
	if attacker.skills.size() > 0:
		var skill: SkillData = attacker.skills[0]
		damage = int(damage * skill.damage_multiplier) # [설계도 155] 계수 적용
		skill_name = skill.skill_name
		
	# 2. 데미지 적용 [설계도 156]
	defender.take_damage(damage)
	
	# 3. 로그 출력
	var color = Color.RED if attacker == player_data else Color.WHITE
	SignalBus.on_log_message.emit("%s의 %s! %d 피해." % [attacker.name, skill_name, damage], color)
	
	# 4. 시각 효과 (Shake) [설계도 157]
	if defender == enemy_data:
		_shake_window()

# --- 시각화 및 유틸 ---
func _update_hp_bar() -> void:
	enemy_hp_bar.max_value = enemy_data.get_total_stat("hp")
	enemy_hp_bar.value = enemy_data.current_hp

func _on_hp_changed(_cur, _max) -> void:
	_update_hp_bar()

func _on_enemy_dead() -> void:
	SignalBus.on_log_message.emit("%s 처치! 승리!" % enemy_data.name, Color.GOLD)
	battle_timer.stop()
	
	# 보상 지급 (간략 구현)
	# ... 추후 LootTable 구현 ...
	
	await get_tree().create_timer(1.5).timeout
	queue_free() # 창 닫기

func _shake_window() -> void:
	var tween = create_tween()
	var original_pos = position
	for i in range(5):
		var offset = Vector2(randf_range(-5, 5), randf_range(-5, 5))
		tween.tween_property(self, "position", original_pos + offset, 0.05)
	tween.tween_property(self, "position", original_pos, 0.05)
