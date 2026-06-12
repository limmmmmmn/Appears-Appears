class_name GoldChip
extends PanelContainer

## Top-left gold readout, split out of the HUD into its own scene so it can be placed
## directly in main.tscn. Self-contained: listens to EventBus for gold changes, samples
## income/sec each second, and grants +1000 on click (debug). The chrome (panel/coin/
## label) is authored in gold_chip.tscn — this only drives the number + the click pop.

@onready var _label: Label = %GoldLabel
@onready var _unlock_bar: ProgressBar = %UnlockBar  # legacy 누적-해금 게이지 (이제 숨김)

var _income_timer: float = 0.0
var _income_marker: int = 0
var _income_per_sec: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	EventBus.gold_changed.connect(_on_gold_changed)
	_income_marker = GameState.total_gold_earned
	_refresh()


func _process(delta: float) -> void:
	_income_timer += delta
	if _income_timer >= 1.0:
		_income_per_sec = maxi(0, GameState.total_gold_earned - _income_marker)
		_income_marker = GameState.total_gold_earned
		_income_timer = 0.0
		_refresh()


func _on_gold_changed(_new_gold: int) -> void:
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	# Coin icon already signals "gold" → show just the number (+ income).
	if _income_per_sec > 0:
		_label.text = "%d  +%d/s" % [GameState.gold, _income_per_sec]
	else:
		_label.text = "%d" % GameState.gold
	# 누적 골드 해금 게이지 제거 — 모든 해금은 이제 노드트리에서. 바는 항상 숨김.
	if _unlock_bar != null:
		_unlock_bar.visible = false


## Click the chip → +1000 gold AND every placement tile surfaces in the dock
## (debug shortcut for testing flows). A quick pop sells the action.
func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.add_gold(1000)
		GameState.debug_unlock_all_tiles()
		pivot_offset = size * 0.5
		var t := create_tween()
		t.tween_property(self, "scale", Vector2(1.18, 1.18), 0.07).set_trans(Tween.TRANS_QUAD)
		t.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
