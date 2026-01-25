extends PanelContainer
class_name BattleWindow
## BattleWindow: ATB 전투창
## - 각 전투창이 독립적인 영웅 ATB + 적 ATB 관리
## - 전투창마다 영웅의 ATB가 따로 진행

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)
signal party_updated
signal hero_atb_changed(battle_id: int, hero_id: String, value: float)

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

# === ATB 시스템 (전투창별 독립) ===
var enemy_atb: Dictionary = {}  # enemy_index -> atb_value
var hero_atb: Dictionary = {}   # hero_id -> atb_value (0.0 ~ 1.0)

# === 보상 ===
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []

# === UI 참조 ===
@onready var enemy_container: HBoxContainer = $MainVBox/BattleArea/EnemyContainer
@onready var run_button: Button = $MainVBox/BottomBar/RunButton
@onready var close_button: Button = $MainVBox/TopBar/CloseButton

# === ATB 설정 ===
const ENEMY_ATB_BASE: float = 0.08
const ENEMY_ATB_SPD_FACTOR: float = 0.008
const HERO_ATB_BASE: float = 0.15
const HERO_ATB_SPD_FACTOR: float = 0.012
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
	
	_update_hero_atb(delta)
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
	enemy_atb.clear()
	for i in range(enemies.size()):
		if enemies[i].is_alive():
			enemy_atb[i] = randf() * 0.6


func _init_hero_atb() -> void:
	hero_atb.clear()
	for hero in PartyManager.get_alive_heroes():
		hero_atb[hero.id] = randf() * 0.4


func _start_battle() -> void:
	current_state = BattleState.RUNNING
	_init_hero_atb()
	set_process(true)
	_send_log("전투 시작!", Color.WHITE)
#endregion


#region 영웅 ATB 시스템
func _update_hero_atb(delta: float) -> void:
	var speed_delta: float = delta * BattleManager.get_battle_speed()
	
	for hero in PartyManager.get_alive_heroes():
		if not hero_atb.has(hero.id):
			hero_atb[hero.id] = 0.0
		
		var charge_rate: float = HERO_ATB_BASE + (hero.get_spd() * HERO_ATB_SPD_FACTOR)
		hero_atb[hero.id] = minf(hero_atb[hero.id] + charge_rate * speed_delta, ATB_MAX)
		
		hero_atb_changed.emit(battle_id, hero.id, hero_atb[hero.id])
		
		if hero_atb[hero.id] >= ATB_MAX:
			_hero_attack(hero)
			hero_atb[hero.id] = 0.0
			hero_atb_changed.emit(battle_id, hero.id, 0.0)
			
			if _check_battle_end():
				return


func _hero_attack(hero: Hero) -> void:
	if hero == null or hero.is_dead:
		return
	
	if not has_alive_enemies():
		return
	
	BattleManager.hero_attacked.emit(hero.id)
	
	var target: BattleEnemy = _select_smart_target(hero)
	if target == null:
		return
	
	var is_evaded: bool = randf() * 100 < target.get_eva()
	if is_evaded:
		target.show_miss_text()
		target.play_evade_effect()
		_send_log("%s의 공격을 %s이(가) 회피!" % [hero.hero_name, target.enemy_name], Color.GRAY)
		return
	
	var is_crit: bool = randf() * 100 < hero.get_crit()
	var damage: int = _calc_hero_damage(hero, target, is_crit)
	
	target.take_damage(damage)
	target.play_hit_effect(is_crit)
	target.show_damage_number(damage, is_crit)
	
	var log_color: Color = Color.ORANGE if is_crit else Color.WHITE
	var crit_text: String = " (크리티컬!)" if is_crit else ""
	_send_log("%s → %s에게 %d%s" % [hero.hero_name, target.enemy_name, damage, crit_text], log_color)
	
	if not target.is_alive():
		_on_enemy_defeated(target)


func _select_smart_target(hero: Hero) -> BattleEnemy:
	var alive: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive.append(e)
	
	if alive.is_empty():
		return null
	
	var atk := hero.get_atk()
	for enemy in alive:
		var expected := maxi(1, atk - int(enemy.get_p_def() / 2))
		if expected >= enemy.current_hp:
			return enemy
	
	return alive[randi() % alive.size()]


func _calc_hero_damage(hero: Hero, target: BattleEnemy, is_crit: bool) -> int:
	var atk := hero.get_atk()
	var p_def := target.get_p_def()
	if is_crit:
		return maxi(1, atk)
	return maxi(1, atk - int(p_def / 2))


func get_hero_atb_value(hero_id: String) -> float:
	return hero_atb.get(hero_id, 0.0)


func has_alive_enemies() -> bool:
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false
#endregion


#region 적 ATB 시스템
func _update_enemy_atb(delta: float) -> void:
	var speed_delta: float = delta * BattleManager.get_battle_speed()
	
	for i in range(enemies.size()):
		var enemy: BattleEnemy = enemies[i]
		if not enemy.is_alive():
			continue
		
		if not enemy_atb.has(i):
			enemy_atb[i] = randf() * 0.4
		
		var charge_rate: float = ENEMY_ATB_BASE + (enemy.get_spd() * ENEMY_ATB_SPD_FACTOR)
		enemy_atb[i] = minf(enemy_atb[i] + charge_rate * speed_delta, ATB_MAX)
		
		enemy.update_atb_bar(enemy_atb[i])
		
		if enemy_atb[i] >= ATB_MAX:
			_enemy_attack(enemy)
			enemy_atb[i] = 0.0
			
			if _check_battle_end():
				return


func _enemy_attack(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		return
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	
	enemy.play_attack_effect()
	
	var is_evaded := randf() * 100 < target.get_eva()
	if is_evaded:
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
		return
	
	var is_crit := randf() * 100 < enemy.get_crit()
	var damage := _calc_enemy_damage(enemy, target, is_crit)
	
	PartyManager.on_hero_damaged(target, damage)
	call_deferred("_emit_party_updated")
	
	var log_color: Color = Color.RED if is_crit else Color.YELLOW
	var crit_text: String = " (강타!)" if is_crit else ""
	_send_log("%s → %s에게 %d%s" % [enemy.enemy_name, target.hero_name, damage, crit_text], log_color)
	
	if target.is_dead:
		_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
		call_deferred("_emit_party_updated")


func _calc_enemy_damage(enemy: BattleEnemy, target: Hero, is_crit: bool) -> int:
	var atk := enemy.get_atk()
	var p_def := target.get_p_def()
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
