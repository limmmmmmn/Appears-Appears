# _scripts/characters/party_member.gd
extends Node2D

@export var leader: PlayerHead
@export var follow_offset: int = 10 # 간격을 조금 넉넉하게 (10~20 추천)

func _process(delta):
	if not leader: return
	
	if leader.position_history.size() > follow_offset:
		var target_pos = leader.position_history[follow_offset]
		
		# [수정] 0.2(느림) -> 0.5(빠름) ~ 0.8(아주 빠름)
		# 0.5 정도면 고무줄 느낌 없이 지렁이처럼 부드럽게 쫓아옴!
		global_position = global_position.lerp(target_pos, 0.2)
		
		# 방향 전환 코드는 그대로 유지
		if global_position.x > target_pos.x:
			$Sprite2D.flip_h = true
		elif global_position.x < target_pos.x:
			$Sprite2D.flip_h = false
