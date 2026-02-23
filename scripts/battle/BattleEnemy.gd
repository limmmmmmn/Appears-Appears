extends Control
class_name BattleEnemy
## BattleEnemy: 전투창 내 적 표시 및 상태 관리
## 씬 구조: Sprite(Sprite2D), NameLabel, HPBar

signal defeated(enemy: BattleEnemy)

const HP_MULTIPLIER: float = 1.0  # HP 배율 (1/4로 축소)

var enemy_id: String = ""
var enemy_name: String = ""
var enemy_type: String = "normal"  # normal, elite, boss

const DROP_RATE_MULTIPLIER: float = 3.0
const BONUS_EQUIP_DROP_BASE: float = 0.35
const ELITE_BONUS_DROP_CHANCE: float = 0.9

# 고유 식별자 (전투창 간 구분용)
static var _uid_counter: int = 0
var battle_uid: int = -1

# 스탯
var max_hp: int = 1
var current_hp: int = 1
var action_timer: float = 0.0  # 행동 타이머 (내부)
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_dex: int = 0
var base_luk: int = 0
var damage_type: String = "physical"  # physical or magic
var _origin_max_hp: int = 1
var _origin_atk: int = 1
var _grudge_atk_mult: float = 1.0
var _grudge_hp_mult: float = 1.0

# 보상
var exp_reward: int = 0
var gold_min: int = 0
var gold_max: int = 0
var drop_table: Array = []

# UI 노드 참조 (씬에서 가져옴)
@onready var sprite: Sprite2D = $Sprite
@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar

# 이펙트
var original_modulate: Color = Color.WHITE

# 호버 선택 이펙트
var _hover_tween: Tween = null
var _hover_glow: Panel = null
var _is_hovered: bool = false


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
	base_str = int(stats.get("atk", 5))
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

	# 트링켓 난이도 배율 적용 (적 스탯 강화)
	if GameManager != null and GameManager.has_method("get_trinket_enemy_stat_multiplier"):
		var trinket_mult: float = float(GameManager.call("get_trinket_enemy_stat_multiplier"))
		max_hp = maxi(1, int(round(float(max_hp) * trinket_mult)))
		base_str = maxi(1, int(round(float(base_str) * trinket_mult)))
		base_def = maxi(0, int(round(float(base_def) * trinket_mult)))
		base_int = maxi(0, int(round(float(base_int) * trinket_mult)))
		base_dex = maxi(1, int(round(float(base_dex) * trinket_mult)))

	_origin_max_hp = maxi(1, max_hp)
	_origin_atk = maxi(1, base_str)

	current_hp = max_hp
	action_timer = 0.0
	
	# 보상 (엘리트는 3배 + 최소 보장)
	var rewards: Dictionary = data.get("rewards", {})
	var reward_mult: float = 3.0 if is_elite_version else 1.0
	exp_reward = int(int(rewards.get("exp", 0)) * reward_mult)
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
		# 보스는 일반 슬라임 대비 3배 크기로 표시 (기본 scale=2 => 6)
		if sprite:
			sprite.scale = Vector2(6, 6)
		if name_label:
			name_label.add_theme_color_override("font_color", Color.ORANGE)
	elif enemy_type == "elite":
		if name_label:
			name_label.add_theme_color_override("font_color", Color.PURPLE)


func set_grudge_scaling(atk_mult: float, hp_mult: float) -> void:
	## 전투창 로컬 원념 배율 적용
	_grudge_atk_mult = maxf(1.0, atk_mult)
	_grudge_hp_mult = maxf(1.0, hp_mult)

	var old_max: int = maxi(1, max_hp)
	var hp_ratio: float = float(current_hp) / float(old_max)

	base_str = maxi(1, int(round(float(_origin_atk) * _grudge_atk_mult)))
	max_hp = maxi(1, int(round(float(_origin_max_hp) * _grudge_hp_mult)))
	current_hp = clampi(int(round(float(max_hp) * hp_ratio)), 1 if is_alive() else 0, max_hp)
	_update_hp_display()


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
	return int(round(float(base_int) * 0.5))

func get_dex() -> int:
	return base_dex

func get_int() -> int:
	return base_int

func get_luk() -> int:
	return base_luk

func get_eva() -> float:
	return base_dex * 0.3 + base_luk * 0.1

func get_crit() -> float:
	return clampf(base_luk * 0.5, 0.0, 95.0)
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


func is_action_ready() -> bool:
	return action_timer >= get_action_delay()


func reset_action_timer() -> void:
	action_timer = 0.0


func get_action_delay() -> float:
	# 보스는 고정 2.5초, 일반/엘리트는 DEX 기반
	var base_delay: float
	if enemy_type == "boss":
		base_delay = 2.5
	else:
		base_delay = maxf(0.5, 2.0 - get_dex() * 0.05)
	# ATB 슬로우 디버프 적용
	if _atb_slow_remaining > 0.0:
		base_delay *= (1.0 + _atb_slow_value)
	return base_delay
#endregion


# === 디버프 시스템 ===
var _dot_remaining: float = 0.0
var _dot_dps: int = 0
var _dot_tick_timer: float = 0.0
var _atb_slow_remaining: float = 0.0
var _atb_slow_value: float = 0.0  # 0.5 = ATB 50% 느려짐


func apply_dot(dps: int, duration: float) -> void:
	_dot_dps = dps
	_dot_remaining = duration
	_dot_tick_timer = 0.0


func apply_atb_slow(value: float, duration: float) -> void:
	_atb_slow_value = value
	_atb_slow_remaining = duration


func tick_debuffs(delta: float) -> void:
	# 도트 처리
	if _dot_remaining > 0.0:
		_dot_remaining -= delta
		_dot_tick_timer += delta
		if _dot_tick_timer >= 1.0:
			_dot_tick_timer -= 1.0
			take_damage(_dot_dps)
			show_damage_number(_dot_dps, false)
		if _dot_remaining <= 0.0:
			_dot_dps = 0
	# ATB 슬로우 처리
	if _atb_slow_remaining > 0.0:
		_atb_slow_remaining -= delta
		if _atb_slow_remaining <= 0.0:
			_atb_slow_value = 0.0


#region 보상
func get_gold_reward() -> int:
	return randi_range(gold_min, gold_max)


func get_exp_reward() -> int:
	return maxi(0, exp_reward)


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
		var final_chance: float = clampf(base_chance * luk_multiplier * DROP_RATE_MULTIPLIER, 0.0, 0.95)
		
		if randf() < final_chance:
			# 트링켓은 일반 드랍에서 제외 (보스/상점/이벤트 획득 전용)
			if DataManager != null and DataManager.has_method("get_trinket"):
				var trinket_data: Dictionary = DataManager.get_trinket(item_id)
				if not trinket_data.is_empty():
					continue
			drops.append(item_id)
	
	# 2. 일반몹 추가 장비 드랍 (common 등급만)
	if enemy_type == "normal" and not is_elite_version:
		var equip_drop_chance: float = clampf(BONUS_EQUIP_DROP_BASE * luk_multiplier, 0.0, 0.95)
		if randf() < equip_drop_chance:
			var common_equip: String = _roll_random_common_equipment()
			if not common_equip.is_empty():
				drops.append(common_equip)

	# 3. 엘리트 확정 보상 (반드시 장비 1개 + 추가 장비 50%)
	if is_elite_version:
		var elite_equip: String = _roll_random_elite_equipment()
		if not elite_equip.is_empty():
			drops.append(elite_equip)
		# 높은 확률로 추가 장비 1개 더
		if randf() < ELITE_BONUS_DROP_CHANCE:
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
	tween.tween_property(slash, "modulate:a", 1.0, 0.06)
	tween.tween_property(slash, "position", Vector2(20, 0), 0.22).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash, "rotation_degrees", 45.0, 0.22).set_ease(Tween.EASE_OUT)

	# 크리티컬이면 스케일 커짐
	if is_crit:
		tween.tween_property(slash, "scale", Vector2(1.0, 1.0), 0.16)

	# 잠깐 유지 후 페이드아웃
	tween.chain().tween_interval(0.08)
	tween.chain().tween_property(slash, "modulate:a", 0.0, 0.15)
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
		_hit_tween.tween_property(sprite, "modulate", Color(3, 0.5, 0.5), 0.07)
		_hit_tween.chain().tween_property(sprite, "modulate", Color(3, 3, 3), 0.07)
		_hit_tween.chain().tween_property(sprite, "modulate", Color(3, 0.5, 0.5), 0.07)
		_hit_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.12)

		# 강한 흔들림 (스프라이트)
		var shake_tween := create_tween()
		for i in range(4):
			var offset := Vector2(randf_range(-6, 6), randf_range(-4, 4))
			shake_tween.tween_property(sprite, "position", original_pos + offset, 0.06)
		shake_tween.tween_property(sprite, "position", original_pos, 0.08)
	else:
		# 일반: 깜빡임 + 약한 흔들림
		_hit_tween.set_parallel(true)
		
		# 흰색 플래시
		_hit_tween.tween_property(sprite, "modulate", Color(2.5, 2.5, 2.5), 0.08)
		_hit_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.14)

		# 약한 흔들림 (스프라이트)
		var shake_tween := create_tween()
		for i in range(2):
			var offset := Vector2(randf_range(-3, 3), randf_range(-2, 2))
			shake_tween.tween_property(sprite, "position", original_pos + offset, 0.06)
		shake_tween.tween_property(sprite, "position", original_pos, 0.08)


func play_attack_effect() -> void:
	## 공격 이펙트 - 스프라이트를 앞으로 (아래로)
	if not sprite:
		return
	var original_pos := sprite.position
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", sprite.position.y + 10, 0.13)
	tween.tween_property(sprite, "position:y", original_pos.y, 0.16)


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
	## MOTHER 2/3 스타일 데미지 숫자: 랜덤 방향으로 포물선 튕김
	if not sprite:
		return

	# 데미지 규모에 따른 설정
	var font_size: int
	var color: Color
	var text_suffix: String = ""
	var pop_height: float  # 튀어오르는 높이
	var pop_speed: float   # 포물선 총 시간

	if damage >= 100:
		font_size = 42
		color = Color(1.0, 0.3, 0.3)
		text_suffix = "!!"
		pop_height = 55.0
		pop_speed = 0.5
	elif damage >= 61:
		font_size = 34
		color = Color(1.0, 0.6, 0.2)
		text_suffix = "!"
		pop_height = 45.0
		pop_speed = 0.45
	elif damage >= 36:
		font_size = 28
		color = Color(1.0, 0.9, 0.3)
		text_suffix = "!"
		pop_height = 38.0
		pop_speed = 0.42
	elif damage >= 16:
		font_size = 22
		color = Color.WHITE
		pop_height = 30.0
		pop_speed = 0.38
	else:
		font_size = 16
		color = Color(0.9, 0.9, 0.9)
		pop_height = 22.0
		pop_speed = 0.35

	# 크리티컬 보너스
	if is_crit:
		font_size = int(font_size * 1.3)
		color = Color(1.0, 1.0, 0.4)
		text_suffix = " CRIT!"
		pop_height *= 1.4
		pop_speed += 0.08

	# 라벨 생성
	var label := Label.new()
	label.text = str(damage) + text_suffix
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)

	# 검정 테두리 (모든 데미지)
	var outline_size: int = 3 if damage >= 36 or is_crit else 2
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))

	# 스프라이트 중앙 위에 배치
	sprite.add_child(label)
	var start_pos := Vector2(-10, -20)
	label.position = start_pos
	label.z_index = 100
	label.pivot_offset = label.size / 2

	# 랜덤 수평 방향 (-1 또는 +1) + 랜덤 세기
	var dir_x: float = randf_range(15.0, 35.0) * (1.0 if randf() > 0.5 else -1.0)
	var ground_y: float = start_pos.y  # 바닥 기준선

	# 팝 스케일
	var bounce_scale: float = 1.3 if is_crit else 1.15
	label.scale = Vector2(bounce_scale, bounce_scale)
	label.modulate.a = 0.0

	# Phase 1: 팝 등장 (즉시 나타남)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.06)

	# Phase 2: 포물선 — 위로 튕김 (X: 선형, Y: 위로 갔다 내려옴)
	tween.tween_property(label, "position:x", start_pos.x + dir_x, pop_speed).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", start_pos.y - pop_height, pop_speed * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Phase 2b: 낙하 (중력)
	tween.set_parallel(false)
	tween.tween_property(label, "position:y", ground_y, pop_speed * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Phase 3: 바닥 바운스 (작게 한번 더 튕김)
	var bounce_h: float = pop_height * 0.2
	var bounce_dir_x: float = dir_x * 0.15
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", ground_y - bounce_h, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:x", label.position.x + dir_x + bounce_dir_x, 0.3).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(label, "position:y", ground_y, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Phase 4: 잠깐 머무른 후 페이드아웃
	tween.tween_interval(0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)

	tween.finished.connect(func(): label.queue_free())


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


func show_attack_particle(emoji: String, burst_count: int = 1) -> void:
	## 이모지 파티클 표시 (스킬 타입별 임시 연출)
	if not sprite or emoji.is_empty():
		return

	var count: int = maxi(1, burst_count)
	for i in range(count):
		var particle := Label.new()
		particle.text = emoji
		particle.add_theme_font_size_override("font_size", 18)
		particle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		particle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE

		sprite.add_child(particle)
		particle.z_index = 90
		particle.position = Vector2(randf_range(-12, 12), randf_range(-18, 2))
		particle.scale = Vector2(0.6, 0.6)
		particle.modulate.a = 0.0

		var move_offset := Vector2(randf_range(-18, 18), randf_range(-36, -16))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "modulate:a", 1.0, 0.06)
		tween.tween_property(particle, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "position", particle.position + move_offset, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(particle, "modulate:a", 0.0, 0.26)
		tween.finished.connect(func(): particle.queue_free())


func set_hover_highlight(show: bool) -> void:
	## 마우스 호버 선택 이펙트 표시/숨기기
	if _is_hovered == show:
		return
	_is_hovered = show

	if show:
		_start_hover_effect()
	else:
		_stop_hover_effect()


func _start_hover_effect() -> void:
	## 호버 시 스프라이트 위에 선택 테두리 + 밝기 표시
	if not sprite or not sprite.texture:
		return

	# 선택 테두리 패널 생성 (최초 1회)
	if _hover_glow == null:
		_hover_glow = Panel.new()
		_hover_glow.name = "HoverGlow"
		_hover_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_glow.z_index = 5

		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 1.0, 1.0, 0.1)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 0.95, 0.5, 0.9)
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_left = 2
		style.corner_radius_bottom_right = 2
		_hover_glow.add_theme_stylebox_override("panel", style)
		add_child(_hover_glow)

	# 스프라이트 크기에 맞춰 위치/크기 설정
	var tex_size := sprite.texture.get_size() * sprite.scale
	var padding := Vector2(4, 4)
	_hover_glow.size = tex_size + padding * 2
	_hover_glow.position = sprite.position - tex_size / 2 - padding
	_hover_glow.visible = true
	_hover_glow.modulate.a = 0.0

	# 펄스 애니메이션 (무한 반복)
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_loops()
	_hover_tween.tween_property(_hover_glow, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_hover_tween.tween_property(_hover_glow, "modulate:a", 0.4, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_hover_effect() -> void:
	## 호버 해제 시 글로우 숨기기
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null

	if _hover_glow:
		_hover_glow.visible = false
#endregion
