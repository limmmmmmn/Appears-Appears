extends Control

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var hp_value: Label = $TopBar/HPBox/HPValue
@onready var mp_value: Label = $TopBar/MPBox/MPValue
@onready var gold_value: Label = $TopBar/GoldBox/GoldValue
@onready var battle_value: Label = $TopBar/BattleBox/BattleValue
@onready var node_label: Label = $TopBar/NodeBox/NodeValue
@onready var pause_indicator: Label = $PauseIndicator

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameManager.party_hp_changed.connect(_on_hp_changed)
	GameManager.party_mp_changed.connect(_on_mp_changed)
	GameManager.gold_changed.connect(_on_gold_changed)
	GameManager.encounter_count_changed.connect(_on_encounter_changed)
	GameManager.journey_node_changed.connect(_on_node_changed)
	DQThemeScript.apply_full(self)
	_refresh()
	pause_indicator.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		GameManager.toggle_movement()
		pause_indicator.visible = not GameManager.is_moving

func _refresh() -> void:
	_on_hp_changed(GameManager.party_hp, GameManager.party_max_hp)
	_on_mp_changed(GameManager.party_mp, GameManager.party_max_mp)
	_on_gold_changed(GameManager.gold)
	_on_encounter_changed(GameManager.encounter_count)
	_on_node_changed(GameManager.current_node_index)

func _on_hp_changed(cur: int, mx: int) -> void:
	hp_value.text = "%d/%d" % [cur, mx]

func _on_mp_changed(cur: int, mx: int) -> void:
	mp_value.text = "%d/%d" % [cur, mx]

func _on_gold_changed(amount: int) -> void:
	gold_value.text = "%dG" % amount

func _on_encounter_changed(count: int) -> void:
	battle_value.text = "%d" % count

func _on_node_changed(idx: int) -> void:
	var nodes := GameManager.get_journey_nodes()
	if nodes.is_empty():
		node_label.text = "-"
		return
	var name_str := ""
	if idx >= 0 and idx < nodes.size():
		name_str = String(nodes[idx].get("name", ""))
	node_label.text = "%d/%d %s" % [idx + 1, nodes.size(), name_str]
