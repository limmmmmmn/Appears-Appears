extends CanvasLayer

@export var slot_scene: PackedScene # PartyMemberSlot.tscn 연결

@onready var party_container = $PartyContainer
@onready var log_text = $LogPanel/LogText
@onready var gold_label = $GoldLabel # (노드 경로 확인!)

func _ready():
	# 1. 파티원 슬롯 생성 (가장 먼저 해야 함!)
	create_party_slots()
	
	# 2. 시그널 연결
	SignalBus.game_log.connect(add_log)
	
	# [수정] 신호 연결 (함수 이름 update_ui로 통일)
	SignalBus.party_updated.connect(update_ui)
	SignalBus.gold_updated.connect(update_gold)
	
	# 3. 초기화 (화면 갱신)
	update_ui()
	
	# GameSettings가 있다면 초기 골드 표시
	if GameSettings:
		update_gold(GameSettings.current_gold)
		
	# 시작 로그 출력
	add_log("모험이 시작되었습니다!", Color.YELLOW)

# --- 골드 UI 업데이트 ---
func update_gold(amount: int):
	if gold_label:
		gold_label.text = "GOLD: " + str(amount)

# --- 파티 슬롯 생성 (게임 시작 시 1회) ---
func create_party_slots():
	# 기존 슬롯 초기화 (안전장치)
	for child in party_container.get_children():
		child.queue_free()
	
	# 파티 매니저에서 명단을 가져와 슬롯 생성
	for member in PartyManager.party_members:
		if not slot_scene: 
			push_error("WorldHUD: slot_scene이 연결되지 않았습니다!")
			return
		
		var slot = slot_scene.instantiate()
		party_container.add_child(slot)
		
		# 슬롯 데이터 주입
		if slot.has_method("setup"):
			slot.setup(member)

# --- [핵심 수정] UI 전체 갱신 함수 ---
# (이 함수 이름이 없어서 에러가 났었습니다!)
func update_ui():
	# 모든 파티원 슬롯을 돌면서 화면(체력, 레벨 등)을 새로고침
	for slot in party_container.get_children():
		# PartyMemberSlot에 'refresh' 함수가 있다면 실행
		if slot.has_method("refresh"):
			slot.refresh()
		# 혹시 옛날 버전이라 refresh가 없다면 hp만이라도 업데이트
		elif slot.has_method("update_hp"):
			slot.update_hp()

# --- 로그 출력 ---
func add_log(text: String, color: Color = Color.WHITE):
	# 색상 코드로 변환하여 BBCode 적용
	var color_code = color.to_html()
	var final_text = "[color=#%s]%s[/color]" % [color_code, text]
	
	# 텍스트 추가 및 줄바꿈
	if log_text:
		log_text.append_text(final_text + "\n")
