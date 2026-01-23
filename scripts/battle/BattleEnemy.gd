extends VBoxContainer
class_name BattleEnemy
## BattleEnemy: 전투창 내 적 표시 및 상태 관리

signal defeated(enemy: BattleEnemy)

var enemy_id: String = ""
var enemy_name: String = ""
var enemy_type: String = "normal"  # normal, elite, boss

# 스탯
var max_hp: int = 1
var current_hp: int = 1
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_spd: int = 0
var base_luk: int = 0

# 보상
var exp_reward: int = 0
var gold_min: int = 0
var gold_max: int = 0
var drop_table: Array = []

# UI
var sprite: TextureRect
var name_label: Label
var hp_bar: ProgressBar
var hp_label: Label

# 이펙트
var original_modulate: Color = Color.WHITE


var _ui_built: bool = false


func _ready() -> void:
	if not _ui_built:
		_build_ui()


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	# 세로 정렬
	alignment = BoxContainer.ALIGNMENT_CENTER
	custom_minimum_size = Vector2(64, 100)
	
	# 스프라이트
	sprite = TextureRect.new()
	sprite.custom_minimum_size = Vector2(48, 48)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	add_child(sprite)
	
	# 이름
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	add_child(name_label)
	
	# HP 바
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(50, 8)
	hp_bar.show_percentage = false
	hp_bar.value = 100
	add_child(hp_bar)
	
	# HP 수치
	hp_label = Label.new()
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 9)
	add_child(hp_label)


var is_elite_version: bool = false  # 엘리트 버전 여부

func setup(p_enemy_id: String, p_is_elite: bool = false) -> void:
	# UI가 아직 생성되지 않았으면 먼저 생성
	if not _ui_built:
		_build_ui()
	
	enemy_id = p_enemy_id
	is_elite_version = p_is_elite
	
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		push_error("[BattleEnemy] 데이터 없음: " + enemy_id)
		return
	
	enemy_name = str(data.get("name", enemy_id))
	enemy_type = str(data.get("type", "normal"))
	
	# 기본 스탯
	var stats: Dictionary = data.get("base_stats", {})
	max_hp = int(stats.get("hp", 10))
	base_str = int(stats.get("str", 5))
	base_def = int(stats.get("def", 2))
	base_int = int(stats.get("int", 1))
	base_spd = int(stats.get("spd", 5))
	base_luk = int(stats.get("luk", 2))
	
	# 엘리트 버전이면 스탯 강화!
	if is_elite_version:
		enemy_name = "⭐ " + enemy_name
		enemy_type = "elite"
		max_hp = int(max_hp * 2.0)  # HP 2배
		base_str = int(base_str * 1.5)  # 공격력 1.5배
		base_def = int(base_def * 1.5)  # 방어력 1.5배
	
	current_hp = max_hp
	
	# 보상 (엘리트는 2배)
	var rewards: Dictionary = data.get("rewards", {})
	var reward_mult: float = 2.0 if is_elite_version else 1.0
	exp_reward = int(int(rewards.get("exp", 5)) * reward_mult)
	gold_min = int(int(rewards.get("gold_min", 1)) * reward_mult)
	gold_max = int(int(rewards.get("gold_max", 5)) * reward_mult)
	
	# 드랍 테이블
	drop_table = data.get("drop_table", [])
	
	# UI 업데이트
	name_label.text = enemy_name
	_update_hp_display()
	
	# 스프라이트 로드
	if SpriteManager:
		var tex: Texture2D = SpriteManager.get_enemy_sprite(enemy_id)
		if tex:
			sprite.texture = tex
	
	# 엘리트 버전 시각적 표시
	if is_elite_version:
		name_label.add_theme_color_override("font_color", Color.PURPLE)
		sprite.scale = Vector2(1.3, 1.3)  # 크기 증가
		modulate = Color(1.2, 0.9, 1.3)  # 보라빛 틴트
	elif enemy_type == "boss":
		name_label.add_theme_color_override("font_color", Color.ORANGE)
	elif enemy_type == "elite":
		name_label.add_theme_color_override("font_color", Color.PURPLE)


#region 스탯 계산
func get_atk() -> int:
	return base_str

func get_p_def() -> int:
	return base_def

func get_m_def() -> int:
	return base_int

func get_spd() -> int:
	return base_spd

func get_luk() -> int:
	return base_luk

func get_eva() -> float:
	return base_spd * 0.3 + base_luk * 0.1

func get_crit() -> float:
	return base_luk * 0.3
#endregion


#region 전투 상태
func is_alive() -> bool:
	return current_hp > 0


func take_damage(amount: int) -> int:
	var actual := maxi(1, amount)
	current_hp = maxi(0, current_hp - actual)
	_update_hp_display()
	
	if current_hp <= 0:
		defeated.emit(self)
	
	return actual


func heal(amount: int) -> int:
	var actual := mini(amount, max_hp - current_hp)
	current_hp += actual
	_update_hp_display()
	return actual


func _update_hp_display() -> void:
	if hp_bar:
		hp_bar.value = (float(current_hp) / float(max_hp)) * 100.0
	if hp_label:
		hp_label.text = "%d/%d" % [current_hp, max_hp]
#endregion


#region 보상
func get_gold_reward() -> int:
	return randi_range(gold_min, gold_max)


func roll_drops() -> Array:
	## 드랍 판정 - LUK 보정 적용
	var drops: Array = []
	var party_luk := PartyManager.get_party_average_luk()
	var luk_multiplier := 1.0 + (party_luk / 100.0)
	
	for drop in drop_table:
		var drop_dict: Dictionary = drop as Dictionary
		var item_id: String = str(drop_dict.get("item_id", ""))
		var base_chance: float = float(drop_dict.get("chance", 0.0))
		var final_chance: float = base_chance * luk_multiplier
		
		if randf() < final_chance:
			drops.append(item_id)
	
	return drops
#endregion


#region 이펙트
func play_hit_effect(is_crit: bool = false) -> void:
	original_modulate = modulate
	
	# 깜빡임 + 흔들림
	var tween := create_tween()
	
	if is_crit:
		modulate = Color.ORANGE
		tween.tween_property(self, "position:x", position.x + 8, 0.05)
		tween.tween_property(self, "position:x", position.x - 8, 0.05)
		tween.tween_property(self, "position:x", position.x + 4, 0.05)
		tween.tween_property(self, "position:x", position.x, 0.05)
	else:
		modulate = Color.RED
		tween.tween_property(self, "position:x", position.x + 4, 0.05)
		tween.tween_property(self, "position:x", position.x - 4, 0.05)
		tween.tween_property(self, "position:x", position.x, 0.05)
	
	tween.tween_property(self, "modulate", original_modulate, 0.1)


func play_evade_effect() -> void:
	# 옆으로 슬쩍 이동
	var tween := create_tween()
	var orig_pos := position.x
	tween.tween_property(self, "position:x", orig_pos + 20, 0.1)
	tween.tween_property(self, "position:x", orig_pos, 0.15)


func play_death_effect() -> void:
	# 페이드아웃 + 아래로 떨어짐 (fire and forget)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "position:y", position.y + 30, 0.5)
	
	# tween 완료 후 숨김 처리 (await 대신 콜백 사용)
	tween.finished.connect(func(): visible = false)
#endregion
