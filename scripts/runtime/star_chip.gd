class_name StarChip
extends PanelContainer

## 별조각 chip (top strip, beside the gold chip). Hidden until prestige becomes
## relevant; then it shows the banked shards and — the carrot — how many a fold
## would pay RIGHT NOW ("★2 +3"). Click → the 프레스티지 창.

@onready var _label: Label = %StarLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	EventBus.gold_changed.connect(_refresh.unbind(1))
	EventBus.prestige_changed.connect(_refresh)
	EventBus.world_started.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var pending: int = GameState.prestige_shards_on_reset()
	var relevant: bool = GameState.star_shards > 0 or GameState.prestige_count > 0 \
		or GameState.can_prestige()
	if visible != relevant and relevant:
		# First reveal — pop in so the new system announces itself.
		visible = true
		pivot_offset = size * 0.5
		scale = Vector2(0.2, 0.2)
		var t := create_tween()
		t.tween_property(self, "scale", Vector2(1.2, 1.2), 0.16)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "scale", Vector2.ONE, 0.1)
	visible = relevant
	if pending > 0:
		_label.text = "★%d  +%d" % [GameState.star_shards, pending]
	else:
		_label.text = "★%d" % GameState.star_shards
	tooltip_text = "세계를 다시 쓰면 +%d 별조각" % pending if pending > 0 else "별조각 — 세계 다시 쓰기"


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var window := get_tree().get_first_node_in_group("prestige_window")
		if window != null and window.has_method("open"):
			window.open()
