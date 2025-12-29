extends Node2D

# 전투 씬 미리 불러오기
var battle_scene_packed = preload("res://Scenes/Battle/BattleScene.tscn")
@onready var player = $Player # 플레이어 데이터 접근용

func _ready():
	SignalBus.battle_requested.connect(_on_battle_requested)

func _on_battle_requested(enemy_data: EnemyData):
	print("맵: 전투 요청 수신! 전투 씬으로 전환합니다.")
	
	# 1. 전투 씬 생성
	var battle_scene = battle_scene_packed.instantiate()
	
	# 2. 화면에 붙이기 (지금은 UI가 없어서 투명하지만 로직은 돌아감)
	add_child(battle_scene)
	
	# 3. 데이터 넘겨주고 시작!
	# (주의: Player 스크립트에 job_data가 있어야 합니다)
	if player.job_data:
		battle_scene.start_battle(player.job_data, enemy_data)
	else:
		print("오류: 플레이어 직업 데이터가 없습니다!")
