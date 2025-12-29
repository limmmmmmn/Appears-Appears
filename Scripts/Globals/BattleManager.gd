extends Node

func process_attack(attacker: BattleUnit, target: BattleUnit):
	var damage = attacker.attack
	var is_crit = randf() < 0.1
	if is_crit: damage *= 2
	
	var is_dead = target.take_damage(damage)
	
	# [New] 로그만 찍지 말고, "진짜 신호"를 쏘세요!
	# 첫 번째 인자로 '맞은 대상(데이터)'을 보냅니다.
	SignalBus.unit_damaged.emit(target, damage, is_crit)
	
	# 로그는 로그대로
	var log_msg = "⚔️ %s -> %s (%d)" % [attacker.unit_name, target.unit_name, damage]
	SignalBus.log_message.emit(log_msg)
