extends CanvasLayer
class_name BattleHUD
## 전투 로그와 파티 상태를 표시하는 HUD

@onready var party_container: HBoxContainer = $PartyPanel/PartyContainer
@onready var battle_log: Label = $LogPanel/BattleLog

var party_labels: Dictionary = {}  # hero_id: {name_label, hp_bar, cooldown_bar}

var log_lines: Array[String] = []
const MAX_LOG_LINES := 6


func _ready() -> void:
	_setup_party_ui()


func _setup_party_ui() -> void:
	# 파티원 UI 생성
	for hero_id in GameManager.party:
		var hero_data := DataManager.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var panel := _create_hero_panel(hero_id, hero_data)
		party_container.add_child(panel)


func _create_hero_panel(hero_id: String, hero_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(70, 50)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	
	# 이름
	var name_label := Label.new()
	name_label.text = str(hero_data.get("name", hero_id))
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	# HP 바
	var hp_bar := ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(60, 8)
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	vbox.add_child(hp_bar)
	
	# HP 라벨
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", 6)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hp_label)
	
	# 쿨다운 바
	var cooldown_bar := ProgressBar.new()
	cooldown_bar.custom_minimum_size = Vector2(60, 4)
	cooldown_bar.max_value = 100
	cooldown_bar.value = 0
	cooldown_bar.show_percentage = false
	vbox.add_child(cooldown_bar)
	
	party_labels[hero_id] = {
		"hp_bar": hp_bar,
		"hp_label": hp_label,
		"cooldown_bar": cooldown_bar
	}
	
	return panel


func update_party_status(party_hp: Dictionary, party_cooldowns: Dictionary, max_cooldowns: Dictionary) -> void:
	for hero_id in party_labels:
		var ui: Dictionary = party_labels[hero_id]
		var hero_data := DataManager.get_hero(hero_id)
		
		var current_hp := int(party_hp.get(hero_id, 0))
		var max_hp := int(hero_data.get("stats", {}).get("max_hp", 100))
		
		# HP 바 업데이트
		var hp_bar: ProgressBar = ui["hp_bar"]
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
		
		# HP 라벨
		var hp_label: Label = ui["hp_label"]
		hp_label.text = "%d/%d" % [current_hp, max_hp]
		
		# 쿨다운 바 업데이트
		var cooldown_bar: ProgressBar = ui["cooldown_bar"]
		var current_cd := float(party_cooldowns.get(hero_id, 0))
		var max_cd := float(max_cooldowns.get(hero_id, 1))
		cooldown_bar.max_value = max_cd
		cooldown_bar.value = max_cd - current_cd  # 차오르는 방식


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()
	
	battle_log.text = "\n".join(log_lines)


func clear_log() -> void:
	log_lines.clear()
	battle_log.text = ""
