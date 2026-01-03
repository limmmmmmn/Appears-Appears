extends Node2D

func _ready():
	# 게임 시작 위치(화면 중앙)에 파티 생성 요청
	PartyManager.setup_party(Vector2(600, 300), self)
