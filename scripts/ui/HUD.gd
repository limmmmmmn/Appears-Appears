# scripts/ui/HUD.gd
# 화면 상단에 항상 표시되는 HUD
extends CanvasLayer

# UI 참조
@onready var gold_label = $TopBar/GoldLabel
@onready var exp_bar = $TopBar/ExpBar
@onready var level_label = $TopBar/LevelLabel
@onready var kill_label = $TopBar/KillLabel
@onready var stage_label = $TopBar/StageLabel
@onready var party_hp_container = $PartyHP
@onready var synergy_container = $SynergyPanel
@onready var timer_label = $TopBar/TimerLabel

# 게임 시간
var game_time: float = 0.0
var game_paused: bool = false

func _ready():
	print("[HUD] Created")
	layer = 50
	
	# 시그널 연결
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.level_up.connect(_on_level_up)
	GameManager.party_changed.connect(_on_party_changed)
	
	# 초기 업데이트
	await get_tree().create_timer(0.5).timeout
	update_all()

func _process(delta):
	if not game_paused:
		game_time += delta
		update_timer()
	
	# 파티 HP 실시간 업데이트
	update_party_hp()

# ========================================
# 전체 업데이트
# ========================================

func update_all():
	update_gold()
	update_exp()
	update_level()
	update_kills()
	update_stage()
	update_party_hp()
	update_synergies()

# ========================================
# 개별 업데이트
# ========================================

func update_gold():
	if gold_label:
		gold_label.text = "💰 %d" % GameManager.gold

func update_exp():
	if exp_bar:
		exp_bar.max_value = GameManager.exp_to_next_level
		exp_bar.value = GameManager.current_exp

func update_level():
	if level_label:
		level_label.text = "Lv.%d" % GameManager.party_level

func update_kills():
	if kill_label:
		kill_label.text = "💀 %d" % GameManager.total_kills

func update_stage():
	if stage_label:
		stage_label.text = "Stage %d" % GameManager.current_stage

func update_timer():
	if timer_label:
		var minutes = int(game_time) / 60
		var seconds = int(game_time) % 60
		timer_label.text = "%02d:%02d" % [minutes, seconds]

# ========================================
# 파티 HP 바
# ========================================

func update_party_hp():
	if not party_hp_container:
		return
	
	# 기존 HP 바 제거
	for child in party_hp_container.get_children():
		child.queue_free()
	
	# 파티원별 HP 바 생성
	for hero in GameManager.party:
		var hp_bar = create_hero_hp_bar(hero)
		party_hp_container.add_child(hp_bar)

func create_hero_hp_bar(hero: Dictionary) -> HBoxContainer:
	var container = HBoxContainer.new()
	
	# 이름
	var name_label = Label.new()
	name_label.text = hero.name.substr(0, 3)  # 첫 3글자
	name_label.custom_minimum_size = Vector2(40, 0)
	name_label.add_theme_font_size_override("font_size", 12)
	container.add_child(name_label)
	
	# HP 바
	var hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(80, 15)
	hp_bar.max_value = hero.base_stats.hp
	hp_bar.value = hero.current_hp
	hp_bar.show_percentage = false
	
	# HP 색상
	var hp_ratio = float(hero.current_hp) / hero.base_stats.hp
	if hp_ratio > 0.5:
		hp_bar.modulate = Color.GREEN
	elif hp_ratio > 0.25:
		hp_bar.modulate = Color.YELLOW
	else:
		hp_bar.modulate = Color.RED
	
	# 죽은 영웅
	if hero.current_hp <= 0:
		hp_bar.modulate = Color.GRAY
		name_label.add_theme_color_override("font_color", Color.GRAY)
	
	container.add_child(hp_bar)
	
	# HP 숫자
	var hp_text = Label.new()
	hp_text.text = "%d" % hero.current_hp
	hp_text.add_theme_font_size_override("font_size", 10)
	container.add_child(hp_text)
	
	return container

# ========================================
# 시너지 표시
# ========================================

func update_synergies():
	if not synergy_container:
		return
	
	# 기존 제거
	for child in synergy_container.get_children():
		child.queue_free()
	
	# 활성 시너지 확인
	var active_synergies = check_active_synergies()
	
	for synergy in active_synergies:
		var label = Label.new()
		label.text = "✨ %s" % synergy.name
		label.add_theme_color_override("font_color", Color.GOLD)
		label.add_theme_font_size_override("font_size", 12)
		synergy_container.add_child(label)

func check_active_synergies() -> Array:
	var result = []
	
	if not DataManager.synergies.has("synergies"):
		return result
	
	# 파티 태그 수집
	var tag_count = {}
	for hero in GameManager.party:
		if hero.has("tags"):
			for tag in hero.tags:
				if not tag_count.has(tag):
					tag_count[tag] = 0
				tag_count[tag] += 1
	
	# 시너지 조건 체크
	for synergy_id in DataManager.synergies.synergies:
		var synergy = DataManager.synergies.synergies[synergy_id]
		var required_tags = synergy.get("required_tags", [])
		var required_count = synergy.get("required_count", 2)
		
		var matched = 0
		for tag in required_tags:
			if tag_count.has(tag) and tag_count[tag] >= 1:
				matched += 1
		
		if matched >= required_count:
			result.append(synergy)
	
	return result

# ========================================
# 시그널 핸들러
# ========================================

func _on_gold_changed(new_gold: int):
	update_gold()

func _on_level_up(_hero_id):
	update_level()
	update_exp()
	
	# 레벨업 이펙트
	show_level_up_effect()

func _on_party_changed():
	update_party_hp()
	update_synergies()

func show_level_up_effect():
	if level_label:
		var tween = create_tween()
		tween.tween_property(level_label, "scale", Vector2(1.5, 1.5), 0.2)
		tween.tween_property(level_label, "scale", Vector2(1, 1), 0.2)

# ========================================
# 일시정지
# ========================================

func pause_game():
	game_paused = true
	get_tree().paused = true

func resume_game():
	game_paused = false
	get_tree().paused = false
