extends PanelContainer
## BattleWindow: DQ식 1인칭 자동 전투창.
## 생성 시 setup(enemy_data) 호출. 전투가 끝나면 battle_finished(result) 시그널.

signal battle_finished(result: String)

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

const MACRO_BASIC := "기본 공격"
const MACRO_AOE := "광역 공격"
const MACRO_FOCUS := "보스 집중"
const MACRO_DEFEND := "방어/회복"

@export var turn_interval: float = 2.0

@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var macro_label: Label = $Margin/VBox/Header/MacroLabel
@onready var gold_label: Label = $Margin/VBox/GoldLabel
@onready var enemy_name: Label = $Margin/VBox/EnemyArea/EnemyName
@onready var enemy_hp_label: Label = $Margin/VBox/EnemyArea/EnemyHP
@onready var hp_value: Label = $Margin/VBox/PartyStatus/HPBox/HPValue
@onready var mp_value: Label = $Margin/VBox/PartyStatus/MPBox/MPValue
@onready var log_label: Label = $Margin/VBox/LogPanel/LogLabel
@onready var turn_timer: Timer = $TurnTimer

var enemy: Dictionary = {}
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var ally_turn: bool = true
var finished: bool = false
var macro: String = MACRO_BASIC
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _log_lines: Array[String] = []

func _ready() -> void:
	custom_minimum_size = Vector2(440, 380)
	DQThemeScript.apply_full(self)
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	turn_timer.timeout.connect(_on_turn)
	turn_timer.wait_time = turn_interval
	turn_timer.start()
	GameManager.party_hp_changed.connect(_refresh_party_status)
	GameManager.party_mp_changed.connect(_refresh_party_status)
	GameManager.game_over.connect(_on_party_dead)
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(enemy_data: Dictionary) -> void:
	enemy = enemy_data.duplicate(true)
	enemy_max_hp = int(enemy.get("hp", 1))
	enemy_hp = enemy_max_hp
	# Node tree is not yet ready here when called pre-add, so defer
	call_deferred("_apply_enemy_visuals")

func _apply_enemy_visuals() -> void:
	if title_label:
		title_label.text = "전투 — %s" % enemy.get("name", "???")
	if macro_label:
		macro_label.text = macro
	if enemy_name:
		enemy_name.text = String(enemy.get("name", "???"))
	if gold_label:
		gold_label.text = "보상: %dG" % int(enemy.get("reward_gold", 0))
	_update_enemy_hp_display()
	_refresh_party_status()
	_push_log("%s 이(가) 나타났다!" % enemy.get("name", "적"))

func _refresh_party_status(_a: int = 0, _b: int = 0) -> void:
	if hp_value:
		hp_value.text = "%d/%d" % [GameManager.party_hp, GameManager.party_max_hp]
	if mp_value:
		mp_value.text = "%d/%d" % [GameManager.party_mp, GameManager.party_max_mp]

func _update_enemy_hp_display() -> void:
	if enemy_hp_label:
		enemy_hp_label.text = "HP %d/%d" % [enemy_hp, enemy_max_hp]

func _push_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > 4:
		_log_lines.pop_front()
	if log_label:
		log_label.text = "\n".join(_log_lines)

func _on_turn() -> void:
	if finished:
		return
	if GameManager.party_hp <= 0:
		_on_party_dead()
		return
	if ally_turn:
		_ally_act()
	else:
		_enemy_act()
	ally_turn = not ally_turn

# ── 아군 행동 ────────────────────────────────
func _ally_act() -> void:
	match macro:
		MACRO_BASIC: _macro_basic()
		MACRO_AOE: _macro_aoe()
		MACRO_FOCUS: _macro_focus()
		MACRO_DEFEND: _macro_defend()

func _macro_basic() -> void:
	var dmg := _roll_physical_damage(_party_power())
	_apply_damage_to_enemy(dmg, "아군의 공격")
	# 힐러가 있고 HP가 낮으면 힐
	if GameManager.party_hp < GameManager.party_max_hp * 0.5 and GameManager.use_mp(3):
		var heal_amt := 8 + randi() % 6
		GameManager.heal(heal_amt)
		_push_log("승려의 회복! HP +%d" % heal_amt)

func _macro_aoe() -> void:
	if not GameManager.use_mp(6):
		_macro_basic()
		return
	var dmg := int(_roll_magic_damage(_party_magic()) * 1.2)
	_apply_damage_to_enemy(dmg, "광역 마법")

func _macro_focus() -> void:
	var dmg := _roll_physical_damage(_party_power() + 3)
	dmg = int(dmg * 1.25)
	_apply_damage_to_enemy(dmg, "집중 공격")

func _macro_defend() -> void:
	var dmg := int(_roll_physical_damage(_party_power()) * 0.5)
	_apply_damage_to_enemy(dmg, "방어 자세 반격")
	if GameManager.use_mp(2):
		var heal_amt := 6
		GameManager.heal(heal_amt)
		_push_log("방어 회복 +%d" % heal_amt)

func _apply_damage_to_enemy(dmg: int, label: String) -> void:
	dmg = maxi(1, dmg - int(enemy.get("vit", 0)) / 2)
	var crit_roll := randi() % 100
	var luk := _party_luck()
	if crit_roll < 5 + luk / 2:
		dmg = int(dmg * 1.5)
		_push_log("%s! 회심의 일격! %d 데미지" % [label, dmg])
	else:
		_push_log("%s! %d 데미지" % [label, dmg])
	enemy_hp = maxi(0, enemy_hp - dmg)
	_update_enemy_hp_display()
	if enemy_hp <= 0:
		_on_enemy_dead()

# ── 적 행동 ──────────────────────────────────
func _enemy_act() -> void:
	var spells: Array = enemy.get("spells", [])
	if spells.size() > 0 and enemy.get("mp", 0) >= 4 and randi() % 3 == 0:
		enemy["mp"] = int(enemy.get("mp", 0)) - 4
		var spell := String(spells[randi() % spells.size()])
		if spell == "heal":
			var h := 10 + randi() % 8
			enemy_hp = mini(enemy_max_hp, enemy_hp + h)
			_update_enemy_hp_display()
			_push_log("%s 의 회복 주문! +%d" % [enemy.get("name"), h])
			return
		# fire 등 공격 주문
		var mdmg := int(_roll_magic_damage(int(enemy.get("int", 5))) * 1.1)
		mdmg = maxi(1, mdmg - _party_defense() / 3)
		GameManager.take_damage(mdmg)
		_push_log("%s 의 %s! 아군 %d 데미지" % [enemy.get("name"), spell, mdmg])
		return
	var dmg := _roll_physical_damage(int(enemy.get("str", 3)))
	dmg = maxi(1, dmg - _party_defense() / 2)
	GameManager.take_damage(dmg)
	_push_log("%s 의 공격! 아군 %d 데미지" % [enemy.get("name"), dmg])

# ── 파티 스탯 합계 ─────────────────────────
func _party_power() -> int:
	var total := 0
	for m in GameManager.party_members:
		total += int(m.get("base_str", 0))
	return maxi(5, total / 2)

func _party_magic() -> int:
	var total := 0
	for m in GameManager.party_members:
		total += int(m.get("base_int", 0))
	return maxi(3, total / 2)

func _party_defense() -> int:
	var total := 0
	for m in GameManager.party_members:
		total += int(m.get("base_vit", 0))
	return maxi(3, total / 2)

func _party_luck() -> int:
	var total := 0
	for m in GameManager.party_members:
		total += int(m.get("base_luk", 0))
	return total / 2

func _roll_physical_damage(power: int) -> int:
	return maxi(1, power + randi() % maxi(1, power / 2 + 1))

func _roll_magic_damage(magic: int) -> int:
	return maxi(1, magic + randi() % maxi(1, magic / 2 + 1))

# ── 종료 처리 ────────────────────────────────
func _on_enemy_dead() -> void:
	if finished:
		return
	finished = true
	turn_timer.stop()
	var reward := int(enemy.get("reward_gold", 0))
	GameManager.add_gold(reward)
	_push_log("%s 을(를) 물리쳤다! %dG" % [enemy.get("name"), reward])
	await get_tree().create_timer(0.8).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		battle_finished.emit("victory")
		queue_free()
	)

func _on_party_dead() -> void:
	if finished:
		return
	finished = true
	turn_timer.stop()
	battle_finished.emit("defeat")
	# Main이 게임오버 처리 — 창은 닫히지 않아도 무방

# ── 드래그 이동 ──────────────────────────────
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_offset = get_global_mouse_position() - position
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = get_global_mouse_position() - _drag_offset
