extends Area2D
# [Blueprint v1.4] 8. 맵 시스템 - 마을행 포탈

# 이동할 마을 씬 경로 (인스펙터에서 수정 가능)
@export_file("*.tscn") var target_scene: String = "res://scenes/ui/village/village_menu.tscn"

func _ready() -> void:
	# 플레이어가 들어왔을 때 실행될 시그널 연결
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		print("마을로 이동합니다...")
		
		# --- 추가: 마을 가기 전 전투창 모두 끄기 ---
		if BattleManager.has_method("clear_all_battles"):
			BattleManager.clear_all_battles()
		
		get_tree().change_scene_to_file(target_scene)
