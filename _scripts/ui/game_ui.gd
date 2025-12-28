# _scripts/ui/game_ui.gd
extends CanvasLayer

@onready var gold_label = $GoldLabel
@onready var level_label = $LevelLabel
@onready var xp_bar = $XPBar
@onready var hp_bar = $HPBar # [필수] HPBar 노드가 있어야 함!

func _ready():
	update_ui()
	PlayerData.stats_changed.connect(update_ui)

func update_ui():
	# 1. 텍스트 갱신
	gold_label.text = "GOLD: %d" % PlayerData.gold
	level_label.text = "LV: %d" % PlayerData.level
	
	# 2. 경험치 바 갱신
	xp_bar.max_value = PlayerData.max_xp
	xp_bar.value = PlayerData.current_xp
	
	# 3. 체력 바 갱신
	hp_bar.max_value = PlayerData.max_hp
	hp_bar.value = PlayerData.current_hp
