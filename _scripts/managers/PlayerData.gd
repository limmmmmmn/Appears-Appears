# _scripts/managers/PlayerData.gd
extends Node

signal stats_changed 
signal player_died # 죽었을 때 신호

# --- [기본 스탯] ---
var gold: int = 0
var level: int = 1
var attack_power: int = 35

# --- [경험치] ---
var current_xp: int = 0
var max_xp: int = 100

# --- [체력] ---
var max_hp: int = 100
var current_hp: int = 100

func _ready():
	current_hp = max_hp # 시작할 때 체력 꽉 채우기

# 돈 획득
func add_gold(amount: int):
	gold += amount
	stats_changed.emit()

# 경험치 획득 (레벨업 포함)
func add_xp(amount: int):
	current_xp += amount
	
	# 경험치가 꽉 차면 레벨업!
	while current_xp >= max_xp:
		level_up()
		
	stats_changed.emit()

# 레벨업 처리
func level_up():
	current_xp -= max_xp
	level += 1
	attack_power += 5   # 공격력 5 증가
	max_hp += 10        # 최대 체력 10 증가
	current_hp = max_hp # 체력 완전 회복!
	max_xp = int(max_xp * 1.2) # 다음 경험치통 20% 증가
	print("Level Up! Lv:", level)

# [핵심] 데미지 입는 함수
func take_damage(amount: int):
	current_hp -= amount
	if current_hp < 0: current_hp = 0
	
	stats_changed.emit() # UI 갱신해!
	
	if current_hp <= 0:
		player_died.emit() # 으악 죽음 신호 발사!

# 부활용 (체력 만땅)
func heal_hp_full():
	current_hp = max_hp
	stats_changed.emit()
