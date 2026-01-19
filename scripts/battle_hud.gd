extends CanvasLayer
class_name BattleHUD
## 전투 로그와 파티 상태를 표시하는 HUD
## 레이아웃은 씬에서 직접 조정

@onready var party_container: VBoxContainer = $UIRoot/PartyPanel
@onready var battle_log: Label = $UIRoot/LogPanel/BattleLog

# 파티원 UI 데이터
var hero_panels: Array = []

var log_lines: Array[String] = []
const MAX_LOG_LINES := 6


func _ready() -> void:
	_setup_party_ui()
	GameManager.party_status_changed.connect(_on_party_status_changed)


func _process(_delta: float) -> void:
	_update_party_ui()


func _setup_party_ui() -> void:
	var hero_index := 0
	
	for i in range(party_container.get_child_count()):
		var child = party_container.get_child(i)
		
		# HSeparator는 스킵
		if child is HSeparator:
			continue
		
		# 파티원 수 초과하면 숨기고 스킵
		if hero_index >= GameManager.party.size():
			child.visible = false
			continue
		
		var hero_id = GameManager.party[hero_index]
		var hero_data = DataManager.get_hero(hero_id)
		
		# InfoBox 찾기 (HBoxContainer 안에 있음)
		var info_box = child.get_node_or_null("InfoBox")
		
		# 패널 데이터 저장
		var panel_data = {
			"hero_id": hero_id,
			"panel": child,
			"portrait": child.get_node_or_null("Portrait"),
			"name_label": info_box.get_node_or_null("NameLabel") if info_box else null,
			"hp_bar": info_box.get_node_or_null("HPBar") if info_box else null,
			"hp_label": info_box.get_node_or_null("HPLabel") if info_box else null,
			"cooldown_bar": info_box.get_node_or_null("CooldownBar") if info_box else null
		}
		
		# 포트레이트 로드
		if panel_data["portrait"] != null:
			var portrait_path = str(hero_data.get("visuals", {}).get("portrait", ""))
			if portrait_path != "" and ResourceLoader.exists(portrait_path):
				panel_data["portrait"].texture = load(portrait_path)
		
		# 이름 설정
		if panel_data["name_label"] != null:
			panel_data["name_label"].text = str(hero_data.get("name", hero_id))
		
		hero_panels.append(panel_data)
		child.visible = true
		hero_index += 1

func _update_party_ui() -> void:
	for panel_data in hero_panels:
		var hero_id = panel_data["hero_id"]
		
		var current_hp = int(GameManager.party_hp.get(hero_id, 0))
		var max_hp = int(GameManager.party_max_hp.get(hero_id, 100))
		
		# HP 바 - 퍼센트 기반으로 변경
		if panel_data["hp_bar"] != null:
			panel_data["hp_bar"].max_value = 100  # 항상 100으로 고정
			panel_data["hp_bar"].value = (float(current_hp) / float(max_hp)) * 100
		
		# HP 라벨
		if panel_data["hp_label"] != null:
			panel_data["hp_label"].text = "%d/%d" % [current_hp, max_hp]
		
		# 쿨다운 바
		if panel_data["cooldown_bar"] != null:
			panel_data["cooldown_bar"].value = GameManager.get_cooldown_percent(hero_id) * 100
			
			
func _on_party_status_changed() -> void:
	_update_party_ui()


func add_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > MAX_LOG_LINES:
		log_lines.pop_front()
	
	battle_log.text = "\n".join(log_lines)


func clear_log() -> void:
	log_lines.clear()
	battle_log.text = ""
