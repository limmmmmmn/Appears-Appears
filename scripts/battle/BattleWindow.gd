extends PanelContainer
class_name BattleWindow
## BattleWindow: ATB 전투창
## - 적 ATB만 관리 (영웅 ATB는 BattleManager에서 전역 관리)
## - BattleManager로부터 영웅 공격 명령 수신

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated

enum BattleState { STARTING, RUNNING, VICTORY, DEFEAT, ESCAPED, ENDED }

# === 전투 식별 ===
var battle_id: int = -1
var is_boss_battle: bool = false
var is_elite_battle: bool = false

# === 전투 상태 ===
var current_state: BattleState = BattleState.STARTING

# === 전투 참가자 ===
var enemies: Array = []
var enemy_data_list: Array = []

# === 적 ATB 시스템 ===
var enemy_atb: Dictionary = {}  # enemy_index -> atb_value

# === 보상 ===
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []

# === UI 참조 ===
@onready var enemy_container: HBoxContainer = $MainVBox/BattleArea/EnemyContainer
@onready var run_button: Button = $MainVBox/BottomBar/RunButton
@onready var close_button: Button = $MainVBox/TopBar/CloseButton

# === ATB 설정 ===
const ATB_BASE_SPEED: float = 0.08  # 적 기본 ATB 충전 속도
const ATB_SPD_FACTOR: float = 0.008
const ATB_MAX: float = 1.0
const BASE_ESCAPE_RATE: float = 40.0


func _ready() -> void:
	visible = false
	set_process(false)
	
	if run_button:
		run_button.pressed.connect(_on_run_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)


func _process(delta: float) -> void:
	if current_state != BattleState.RUNNING:
		return
	
	# 적 ATB만 업데이트
	_update_enemy_atb(delta)


#region 전투 초기화
func setup(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	
	is_boss_battle = _check_is_boss_battle(enemy_ids)
	run_button.disabled = is_boss_battle
	
	_spawn_enemies(enemy_ids)
	_init_enemy_atb()
	
	if is_elite_battle:
		var bg: Panel = get_node_or_null("Panel")
		if bg:
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.1, 0.3, 0.95)
			bg.add_theme_stylebox_override("panel", style)
	
	visible = true
	current_state = BattleState.STARTING
	
	await get_tree().create_timer(0.3).timeout
	_start_battle()


func _check_is_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var data: Dictionary = DataManager.get_enemy(str(enemy_id))
		if data.get("type", "") == "boss":
			return true
	return false


const BATTLE_ENEMY_SCENE = preload("res://scenes/battle/BattleEnemy.tscn")

func _spawn_enemies(enemy_ids: Array) -> void:
	for child in enemy_container.get_children():
		child.queue_free()
	enemies.clear()
	
	var spawned_elite: bool = false
	
	for enemy_id in enemy_ids:
		var battle_enemy: BattleEnemy = BATTLE_ENEMY_SCENE.instantiate()
		enemy_container.add_child(battle_enemy)
		
		if is_elite_battle and not spawned_elite:
			battle_enemy.setup(str(enemy_id), true)
			spawned_elite = true
		else:
			battle_enemy.setup(str(enemy_id), false)
		
		enemies.append(battle_enemy)


func _init_enemy_atb() -> void:
	## 적 ATB 초기화 - 랜덤 시작 (동시 공격 방지)
	enemy_atb.clear()
	
	for i in range(enemies.size()):
		if enemies[i].is_alive():
			enemy_atb[i] = randf() * 0.6  # 0~60% 랜덤 시작


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


#region 적 ATB 시스템
func _update_enemy_atb(delta: float) -> void:
	## 적 ATB 업데이트 및 공격 처리 (배속 적용)
	var speed_delta: float = delta * BattleManager.get_battle_speed()
	
	for i in range(enemies.size()):
		var enemy: BattleEnemy = enemies[i]
		if not enemy.is_alive():
			continue
		
		if not enemy_atb.has(i):
			enemy_atb[i] = randf() * 0.4
		
		var charge_rate: float = ATB_BASE_SPEED + (enemy.get_spd() * ATB_SPD_FACTOR)
		enemy_atb[i] = minf(enemy_atb[i] + charge_rate * speed_delta, ATB_MAX)
		
		# ATB 게이지 UI 업데이트
		enemy.update_atb_bar(enemy_atb[i])
		
		# ATB 풀 차면 공격
		if enemy_atb[i] >= ATB_MAX:
			_enemy_attack(enemy)
			enemy_atb[i] = 0.0
			
			if _check_battle_end():
				return
#endregion


#region 외부 공격 인터페이스
func has_alive_enemies() -> bool:
	## BattleManager가 호출 - 살아있는 적이 있는지
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false


func execute_hero_attack(hero: Hero) -> void:
	## BattleManager에서 호출 - 영웅이 이 전투창의 적을 공격
	if current_state != BattleState.RUNNING:
		return
	
	if hero == null or hero.is_dead:
		return
	
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)
	
	if alive_enemies.is_empty():
		return
	
	# 스마트 타겟팅
	var target: BattleEnemy = _select_smart_target(hero, alive_enemies)
	_do_hero_attack(hero, target)
	
	# 전투 종료 체크
	_check_battle_end()
#endregion


#region 전투 행동
func _enemy_attack(enemy: BattleEnemy) -> void:
	## 적 기본 공격
	if not enemy.is_alive():
		return
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	
	enemy.play_attack_effect()
	
	var atk := enemy.get_atk()
	var is_crit := randf() * 100 < enemy.get_crit()
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
	else:
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		PartyManager.on_hero_damaged(target, damage)
		call_deferred("_emit_party_updated")
		
		if is_crit:
			_send_log("%s → %s에게 %d! (강타)" % [enemy.enemy_name, target.hero_name, damage], Color.RED)
		else:
			_send_log("%s → %s에게 %d" % [enemy.enemy_name, target.hero_name, damage], Color.YELLOW)
		
		if target.is_dead:
			_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
			call_deferred("_emit_party_updated")


func _select_smart_target(hero: Hero, alive_enemies: Array) -> BattleEnemy:
	## 스마트 타겟팅 - 처치 가능한 적 우선
	var atk := hero.get_atk()
	
	for enemy in alive_enemies:
		if enemy == null:
			continue
		var expected_damage := _calculate_damage(atk, enemy.get_p_def())
		if expected_damage >= enemy.current_hp:
			return enemy
	
	return alive_enemies[randi() % alive_enemies.size()]


func _do_hero_attack(hero: Hero, target: BattleEnemy) -> void:
	## 영웅 공격 실행
	if hero == null or target == null:
		return
	
	var atk := hero.get_atk()
	var is_crit := randf() * 100 < hero.get_crit()
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_send_log("%s → %s 회피!" % [hero.hero_name, target.enemy_name], Color.GRAY)
		target.play_evade_effect()
		target.show_miss_text()
	else:
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		target.take_damage(damage)
		target.show_damage_number(damage, is_crit)
		
		if is_crit:
			_send_log("%s → %s에게 %d! (크리티컬)" % [hero.hero_name, target.enemy_name, damage], Color.ORANGE)
			target.play_hit_effect(true)
		else:
			_send_log("%s → %s에게 %d" % [hero.hero_name, target.enemy_name, damage], Color.WHITE)
			target.play_hit_effect(false)
		
		if not target.is_alive():
			_on_enemy_defeated(target)


func _calculate_damage(atk: int, p_def: int, is_crit: bool = false) -> int:
	if is_crit:
		return maxi(1, atk)
	return maxi(1, atk - int(p_def / 2))
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	_send_log("%s 처치!" % enemy.enemy_name, Color.LIME)
	
	total_exp += enemy.exp_reward
	total_gold += enemy.get_gold_reward()
	drop_items.append_array(enemy.roll_drops())
	
	var idx := enemies.find(enemy)
	if idx >= 0:
		enemy_atb.erase(idx)
	
	enemy.play_death_effect()


func _check_battle_end() -> bool:
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)
	
	var alive_heroes := PartyManager.get_alive_heroes()
	
	if alive_enemies.is_empty():
		_end_battle_victory()
		return true
	
	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true
	
	return false


func _end_battle_victory() -> void:
	current_state = BattleState.VICTORY
	set_process(false)
	
	_send_log("승리! EXP +%d, Gold +%d" % [total_exp, total_gold], Color.CYAN)
	
	for item_id in drop_items:
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if not equip_data.is_empty():
			var rarity: String = str(equip_data.get("rarity", "common"))
			var item_name: String = str(equip_data.get("name", item_id))
			var color: Color = Color.WHITE
			match rarity:
				"magic": color = Color(0.4, 0.6, 1.0)
				"legendary": color = Color(1.0, 0.7, 0.2)
			_send_log("⚔️ %s 획득!" % item_name, color)
		else:
			var item_data: Dictionary = DataManager.get_item(item_id)
			_send_log("%s 획득!" % str(item_data.get("name", item_id)), Color.YELLOW)
	
	PartyManager.distribute_exp(total_exp)
	GameManager.add_gold(total_gold)
	for item_id in drop_items:
		InventoryManager.add_item(item_id)
	
	call_deferred("_emit_party_updated")
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, true)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	set_process(false)
	
	_send_log("전멸...", Color.DARK_RED)
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, false)
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	if is_boss_battle or current_state != BattleState.RUNNING:
		return
	
	run_button.disabled = true
	
	var escape_chance := _calculate_escape_chance()
	var roll := randf() * 100
	
	if roll < escape_chance:
		current_state = BattleState.ESCAPED
		set_process(false)
		_send_log("도주 성공!", Color.CYAN)
		run_button.visible = false
		close_button.visible = true
		battle_ended.emit(battle_id, false)
	else:
		_send_log("도주 실패!", Color.GRAY)
		run_button.disabled = false


func _calculate_escape_chance() -> float:
	var party_avg_spd := PartyManager.get_party_average_spd()
	
	var enemy_total_spd: float = 0.0
	var alive_count: int = 0
	for enemy in enemies:
		if enemy.is_alive():
			enemy_total_spd += enemy.get_spd()
			alive_count += 1
	var enemy_avg_spd: float = enemy_total_spd / maxf(1.0, float(alive_count))
	
	var chance := BASE_ESCAPE_RATE + (party_avg_spd - enemy_avg_spd) * 2.0
	return clampf(chance, 5.0, 95.0)
#endregion


#region 유틸리티
func _emit_party_updated() -> void:
	party_updated.emit()


func _send_log(msg: String, color: Color = Color.WHITE) -> void:
	battle_log.emit(msg, color)


func _on_close_pressed() -> void:
	current_state = BattleState.ENDED
	queue_free()
#endregion
