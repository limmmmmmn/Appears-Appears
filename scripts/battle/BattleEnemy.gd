extends Control
class_name BattleEnemy
## BattleEnemy: 전투창 내 적 표시 및 상태 관리
## 씬 구조: Sprite(Sprite2D), NameLabel, HPBar

signal defeated(enemy: BattleEnemy)

const HP_MULTIPLIER: float = 1.0  # HP 배율 (1/4로 축소)

var enemy_id: String = ""
var enemy_name: String = ""
var enemy_type: String = "normal"  # normal, elite, boss

# 고유 식별자 (전투창 간 구분용)
static var _uid_counter: int = 0
var battle_uid: int = -1

# 스탯
var max_hp: int = 1
var current_hp: int = 1
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_dex: int = 0
var base_luk: int = 0
var damage_type: String = "physical"  # physical or magic

# 보상
var gold_min: int = 0
var gold_max: int = 0
var drop_table: Array = []

# UI 노드 참조 (씬에서 가져옴)
@onready var sprite: Sprite2D = $Sprite
@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar

# 이펙트
var original_modulate: Color = Color.WHITE


var is_elite_version: bool = false  # 엘리트 버전 여부

func setup(p_enemy_id: String, p_is_elite: bool = false) -> void:
	enemy_id = p_enemy_id
	is_elite_version = p_is_elite

	# 고유 ID 할당
	_uid_counter += 1
	battle_uid = _uid_counter

	var data: Dictionary = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		push_error("[BattleEnemy] 데이터 없음: " + enemy_id)
		return

	enemy_name = str(data.get("name", enemy_id))
	enemy_type = str(data.get("type", "normal"))

	# 기본 스탯
	var stats: Dictionary = data.get("stats", {})
	max_hp = int(int(stats.get("hp", 10)) * HP_MULTIPLIER)
	base_str = int(stats.get("atk", 5))  # enemies.json uses "atk" not "str"
	base_def = int(stats.get("def", 2))
	base_int = int(stats.get("int", 1))
	base_dex = int(stats.get("dex", 5))
	base_luk = int(stats.get("luk", 2))
	damage_type = str(data.get("damage_type", "physical"))

	# 엘리트 버전이면 스탯 강화!
	if is_elite_version:
		enemy_name = "⭐ " + enemy_name
		enemy_type = "elite"
		max_hp = int(max_hp * 2.0)  # HP 2배
		base_str = int(base_str * 1.5)  # 공격력 1.5배
		base_def = int(base_def * 1.5)  # 방어력 1.5배

	current_hp = max_hp
	
	# 보상 (엘리트는 3배 + 최소 보장)
	var rewards: Dictionary = data.get("rewards", {})
	var reward_mult: float = 3.0 if is_elite_version else 1.0
	gold_min = int(int(rewards.get("gold_min", 1)) * reward_mult)
	gold_max = int(int(rewards.get("gold_max", 5)) * reward_mult)
	if is_elite_version:
		gold_min = maxi(gold_min, 20)  # 엘리트 최소 골드 보장
	
	# 드랍 테이블
	drop_table = data.get("drop_table", [])
	
	# UI 업데이트
	if name_label:
		name_label.text = enemy_name
	_update_hp_display()
	
	# 스프라이트 로드
	if SpriteManager and sprite:
		var tex: Texture2D = SpriteManager.get_enemy_sprite(enemy_id)
		if tex:
			sprite.texture = tex
	
	# 엘리트 버전 시각적 표시 (크기는 동일, 색상만 변경)
	if is_elite_version:
		if name_label:
			name_label.add_theme_color_override("font_color", Color.PURPLE)
		modulate = Color(1.2, 0.9, 1.3)  # 보라빛 틴트
		_add_elite_star()
	elif enemy_type == "boss":
		if name_label:
			name_label.add_theme_color_override("font_color", Color.ORANGE)
	elif enemy_type == "elite":
		if name_label:
			name_label.add_theme_color_override("font_color", Color.PURPLE)


func _add_elite_star() -> void:
	## 엘리트 머리 위에 ⭐ 표시
	var star := Label.new()
	star.text = "⭐"
	star.add_theme_font_size_override("font_size", 14)
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.z_index = 10
	add_child(star)
	# 스프라이트 위 중앙에 배치
	await get_tree().process_frame
	if is_instance_valid(star) and is_instance_valid(sprite):
		star.position = Vector2(
			sprite.position.x - star.size.x / 2,
			sprite.position.y - sprite.texture.get_height() / 2 - star.size.y
		)


#region 스탯 계산
func get_atk() -> int:
	return base_str

func get_p_def() -> int:
	return base_def

func get_m_def() -> int:
	return base_int

func get_dex() -> int:
	return base_dex

func get_int() -> int:
	return base_int

func get_luk() -> int:
	return base_luk

func get_eva() -> float:
	return base_dex * 0.3 + base_luk * 0.1

func get_atb_speed() -> int:
	## ATB 속도: 물리형은 DEX, 마법형은 INT
	if damage_type == "magic":
		return base_int
	return base_dex

func get_crit() -> float:
	return base_luk * 0.3
#endregion


#region 비트 시스템 (ATB 제거됨)
# ATB 바 제거됨 - 비트 시스템으로 대체
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
	# HP바가 visible일 때만 업데이트
	if hp_bar and hp_bar.visible:
		hp_bar.value = (float(current_hp) / float(max_hp)) * 100.0
#endregion


#region 보상
func get_gold_reward() -> int:
	return randi_range(gold_min, gold_max)


func roll_drops() -> Array:
	## 드랍 판정 - LUK 보정 적용
	var drops: Array = []
	var party_luk: int = PartyManager.get_party_average_luk()
	var luk_multiplier: float = 1.0 + (party_luk / 100.0)
	
	# 1. 기존 드랍 테이블 판정
	for drop in drop_table:
		var drop_dict: Dictionary = drop as Dictionary
		var item_id: String = str(drop_dict.get("item_id", ""))
		var base_chance: float = float(drop_dict.get("chance", 0.0))
		var final_chance: float = base_chance * luk_multiplier
		
		if randf() < final_chance:
			drops.append(item_id)
	
	# 2. 일반몹 추가 장비 드랍 (common 등급만)
	if enemy_type == "normal" and not is_elite_version:
		var equip_drop_chance: float = 0.08 * luk_multiplier  # 기본 8% 확률
		if randf() < equip_drop_chance:
			var common_equip: String = _roll_random_common_equipment()
			if not common_equip.is_empty():
				drops.append(common_equip)

	# 3. 엘리트 확정 보상 (반드시 장비 1개 + 추가 장비 50%)
	if is_elite_version:
		var elite_equip: String = _roll_random_elite_equipment()
		if not elite_equip.is_empty():
			drops.append(elite_equip)
		# 50% 확률로 추가 장비 1개 더
		if randf() < 0.5:
			var bonus_equip: String = _roll_random_elite_equipment()
			if not bonus_equip.is_empty():
				drops.append(bonus_equip)

	return drops


func _roll_random_elite_equipment() -> String:
	## 엘리트 확정 보상: uncommon~rare 등급 장비
	var elite_equipment: Array[String] = [
		"sword_uncommon", "dagger_uncommon", "staff_uncommon", "bow_uncommon",
		"shield_uncommon", "iron_helmet", "chainmail",
		"ring_hp", "boots_speed", "ring_str", "ring_def",
	]
	# rare 장비도 30% 확률로
	var rare_pool: Array[String] = [
		"sword_rare", "dagger_rare", "staff_rare", "bow_rare",
		"shield_rare", "plate_helmet", "plate_armor",
	]
	if randf() < 0.3 and not rare_pool.is_empty():
		return rare_pool[randi() % rare_pool.size()]
	if elite_equipment.is_empty():
		return ""
	return elite_equipment[randi() % elite_equipment.size()]


func _roll_random_common_equipment() -> String:
	## 랜덤 커먼 장비 선택
	var common_equipment: Array[String] = [
		"sword_common", "dagger_common", "staff_common", "bow_common",
		"shield_common", "leather_helmet", "iron_helmet",
		"leather_armor", "chainmail", "robe_common",
		"ring_hp", "boots_speed"
	]
	
	if common_equipment.is_empty():
		return ""
	
	return common_equipment[randi() % common_equipment.size()]
#endregion


#region 이펙트
var _hit_tween: Tween = null

# 슬래시 이펙트 스프라이트 경로
const SLASH_SPRITE_PATH := "res://assets/sprites/effects/slash.png"
const SLASH_CRIT_SPRITE_PATH := "res://assets/sprites/effects/slash_crit.png"


func play_slash_effect(is_crit: bool = false) -> void:
	## 검 휘두르는 슬래시 이펙트 (스프라이트 기반)
	if not sprite:
		return
	
	var slash := Sprite2D.new()
	
	# 크리티컬/일반에 따라 다른 스프라이트
	var path := SLASH_CRIT_SPRITE_PATH if is_crit else SLASH_SPRITE_PATH
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	
	if tex:
		slash.texture = tex
	else:
		# 스프라이트 없으면 플레이스홀더 (흰색 사각형)
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		slash.texture = ImageTexture.create_from_image(img)
	
	# 스프라이트에 자식으로 추가
	sprite.add_child(slash)
	slash.z_index = 50
	slash.position = Vector2(-20, 0)  # 왼쪽에서 시작
	slash.rotation_degrees = -45  # 대각선
	slash.scale = Vector2(0.5, 0.5) if not is_crit else Vector2(0.7, 0.7)
	slash.modulate = Color.WHITE if not is_crit else Color(1.0, 0.9, 0.3)
	slash.modulate.a = 0.0
	
	# 애니메이션: 왼쪽에서 오른쪽으로 휘두르기
	var tween := create_tween()
	tween.set_parallel(true)
	
	# 나타나면서 회전하며 이동
	tween.tween_property(slash, "modulate:a", 1.0, 0.03)
	tween.tween_property(slash, "position", Vector2(20, 0), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash, "rotation_degrees", 45.0, 0.12).set_ease(Tween.EASE_OUT)
	
	# 크리티컬이면 스케일 커짐
	if is_crit:
		tween.tween_property(slash, "scale", Vector2(1.0, 1.0), 0.08)
	
	# 페이드아웃
	tween.chain().tween_property(slash, "modulate:a", 0.0, 0.08)
	tween.chain().tween_callback(func(): slash.queue_free())


func play_hit_effect(is_crit: bool = false) -> void:
	## 피격 이펙트 - 슬래시 + 깜빡임 + 흔들림 + 사운드
	if not sprite:
		return
	
	# 사운드 재생
	if SoundManager:
		SoundManager.play_hit(is_crit)
	
	# 슬래시 이펙트 먼저!
	play_slash_effect(is_crit)
	
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	
	var original_pos: Vector2 = sprite.position
	_hit_tween = create_tween()
	
	if is_crit:
		# 크리티컬: 강한 깜빡임 + 강한 흔들림 + 빨간 틴트
		_hit_tween.set_parallel(true)
		
		# 빨간색 플래시
		_hit_tween.tween_property(sprite, "modulate", Color(3, 0.5, 0.5), 0.03)
		_hit_tween.chain().tween_property(sprite, "modulate", Color(3, 3, 3), 0.03)
		_hit_tween.chain().tween_property(sprite, "modulate", Color(3, 0.5, 0.5), 0.03)
		_hit_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.05)
		
		# 강한 흔들림 (스프라이트)
		var shake_tween := create_tween()
		for i in range(4):
			var offset := Vector2(randf_range(-6, 6), randf_range(-4, 4))
			shake_tween.tween_property(sprite, "position", original_pos + offset, 0.03)
		shake_tween.tween_property(sprite, "position", original_pos, 0.04)
	else:
		# 일반: 깜빡임 + 약한 흔들림
		_hit_tween.set_parallel(true)
		
		# 흰색 플래시
		_hit_tween.tween_property(sprite, "modulate", Color(2.5, 2.5, 2.5), 0.04)
		_hit_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.06)
		
		# 약한 흔들림 (스프라이트)
		var shake_tween := create_tween()
		for i in range(2):
			var offset := Vector2(randf_range(-3, 3), randf_range(-2, 2))
			shake_tween.tween_property(sprite, "position", original_pos + offset, 0.03)
		shake_tween.tween_property(sprite, "position", original_pos, 0.04)


func play_attack_effect() -> void:
	## 공격 이펙트 - 스프라이트를 앞으로 (아래로)
	if not sprite:
		return
	var original_pos := sprite.position
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", sprite.position.y + 10, 0.08)
	tween.tween_property(sprite, "position:y", original_pos.y, 0.1)


func play_evade_effect() -> void:
	## 회피 이펙트 - 스프라이트를 옆으로 + 사운드
	if not sprite:
		return
	
	# 사운드 재생
	if SoundManager:
		SoundManager.play_miss()
	
	var original_pos := sprite.position
	var tween := create_tween()
	tween.tween_property(sprite, "position:x", sprite.position.x + 12, 0.08)
	tween.tween_property(sprite, "position:x", original_pos.x, 0.12)


func play_death_effect() -> void:
	## 사망 이펙트 - 스프라이트 페이드아웃 + 사운드
	if not sprite:
		return
	
	# 사운드 재생
	if SoundManager:
		SoundManager.play_death()
	
	var tween := create_tween()
	
	# 깜빡임 3회
	for i in range(3):
		tween.tween_property(sprite, "modulate:a", 0.3, 0.06)
		tween.tween_property(sprite, "modulate:a", 1.0, 0.06)
	
	# 페이드아웃
	tween.tween_property(sprite, "modulate:a", 0.0, 0.2)
	tween.finished.connect(func(): visible = false)


func show_damage_number(damage: int, is_crit: bool = false) -> void:
	## 발라트로 스타일 데미지 숫자 표시
	if not sprite:
		return
	
	# 데미지 규모에 따른 설정
	var font_size: int
	var color: Color
	var duration: float
	var bounce_scale: float
	var text_suffix: String = ""
	
	if damage >= 100:
		font_size = 42
		color = Color(1.0, 0.3, 0.3)  # 빨간색
		duration = 1.5
		bounce_scale = 1.8
		text_suffix = "!!"
	elif damage >= 61:
		font_size = 34
		color = Color(1.0, 0.6, 0.2)  # 주황색
		duration = 1.2
		bounce_scale = 1.6
		text_suffix = "!"
	elif damage >= 36:
		font_size = 28
		color = Color(1.0, 0.9, 0.3)  # 노란색
		duration = 1.0
		bounce_scale = 1.4
		text_suffix = "!"
	elif damage >= 16:
		font_size = 22
		color = Color.WHITE
		duration = 0.8
		bounce_scale = 1.2
	else:
		font_size = 16
		color = Color(0.9, 0.9, 0.9)
		duration = 0.6
		bounce_scale = 1.1
	
	# 크리티컬 보너스
	if is_crit:
		font_size = int(font_size * 1.3)
		color = Color(1.0, 1.0, 0.4)  # 밝은 노란색
		duration += 0.3
		bounce_scale += 0.3
		text_suffix = " CRIT!"
	
	# 라벨 생성
	var label := Label.new()
	label.text = str(damage) + text_suffix
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	
	# 테두리 효과 (큰 데미지용)
	if damage >= 36 or is_crit:
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	
	# 스프라이트 중앙 위에 배치
	sprite.add_child(label)
	label.position = Vector2(-10, -20)
	label.z_index = 100
	label.pivot_offset = label.size / 2
	
	# 시작 시 크게 (bounce_scale), 투명
	label.scale = Vector2(bounce_scale, bounce_scale)
	label.modulate.a = 0.0
	
	# 애니메이션
	var tween := create_tween()
	
	# Phase 1: 펑! 하고 나타남 (0.1초)
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "position:y", label.position.y - 8, 0.12)
	
	# Phase 2: 잠깐 머무름 + 살짝 위로
	tween.set_parallel(false)
	tween.tween_interval(duration * 0.5)
	
	# Phase 3: 천천히 위로 올라가며 페이드아웃
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30, duration * 0.4)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.35)
	
	# 큰 데미지면 살짝 흔들림 추가
	if damage >= 61 or is_crit:
		_shake_label(label, 0.15)
	
	tween.finished.connect(func(): label.queue_free())


func _shake_label(label: Label, duration: float) -> void:
	## 라벨 흔들림 효과
	var shake_tween := create_tween()
	var original_x: float = label.position.x
	var shake_amount := 3.0
	
	for i in range(4):
		shake_tween.tween_property(label, "position:x", original_x + randf_range(-shake_amount, shake_amount), duration / 4)
	shake_tween.tween_property(label, "position:x", original_x, 0.05)


func show_heal_number(amount: int) -> void:
	## 회복 숫자 표시 (녹색)
	if not sprite:
		return
	
	var label := Label.new()
	label.text = "+" + str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0.3, 0, 0.8))
	
	sprite.add_child(label)
	label.position = Vector2(-5, -15)
	label.z_index = 100
	label.scale = Vector2(1.3, 1.3)
	label.modulate.a = 0.0
	
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(label, "modulate:a", 1.0, 0.08)
	tween.tween_property(label, "position:y", label.position.y - 20, 0.8)
	tween.set_parallel(false)
	tween.tween_interval(0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	
	tween.finished.connect(func(): label.queue_free())


func show_miss_text() -> void:
	## MISS 표시
	if not sprite:
		return
	
	var label := Label.new()
	label.text = "MISS"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	
	sprite.add_child(label)
	label.position = Vector2(0, -10)
	label.z_index = 100
	label.modulate.a = 0.0
	
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.1)
	tween.tween_property(label, "position:x", label.position.x + 15, 0.3)
	tween.tween_property(label, "modulate:a", 0.0, 0.2)
	
	tween.finished.connect(func(): label.queue_free())
#endregion
