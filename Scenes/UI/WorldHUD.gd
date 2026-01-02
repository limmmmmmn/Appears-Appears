# res://Scenes/UI/WorldHUD.gd
extends CanvasLayer

@export var slot_scene: PackedScene # PartyMemberSlot.tscn 연결

@onready var party_container = $PartyContainer
@onready var log_text = $LogPanel/LogText

func _ready():
	# 1. 파티원 슬롯 생성
	create_party_slots()
	
	# 2. 시그널 연결
	SignalBus.party_updated.connect(_on_party_updated)
	SignalBus.game_log.connect(add_log)
	
	# 테스트 로그
	add_log("[color=yellow]모험이 시작되었습니다![/color]")

func create_party_slots():
	# 기존 슬롯 초기화 (재시작 등의 경우 대비)
	for child in party_container.get_children():
		child.queue_free()
	
	# 파티 매니저에서 명단을 가져와 슬롯 생성
	for member in PartyManager.party_members:
		if not slot_scene: return
		
		var slot = slot_scene.instantiate()
		party_container.add_child(slot)
		slot.setup(member)

func _on_party_updated():
	# 파티원 체력이 변했을 때 호출됨 (나중에 전투 시스템에서 emit 해야 함)
	for slot in party_container.get_children():
		slot.update_hp()

func add_log(text: String, color: Color = Color.WHITE):
	# 색상 코드로 변환하여 BBCode 적용
	var color_code = color.to_html()
	var final_text = "[color=#%s]%s[/color]" % [color_code, text]
	
	# 텍스트 추가 및 줄바꿈
	log_text.append_text(final_text + "\n")
	
	# 스크롤을 항상 맨 아래로 유지하지 않아도 append_text는 보통 아래에 붙음.
