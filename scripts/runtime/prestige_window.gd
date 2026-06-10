class_name PrestigeWindow
extends Control

## 프레스티지 창 — "세계 다시 쓰기". Shows banked 별조각, the permanent perks,
## and the fold button (two-step confirm). Folding banks shards from lifetime
## gold, resets the run, and reloads the scene so everything wakes up fresh.
## Minimal RPG frame, same freeze contract as the 방문 창.

const PERK_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _shard_label: Label = %ShardLabel
@onready var _perks: VBoxContainer = %Perks
@onready var _fold_button: Button = %FoldButton
@onready var _close_button: Button = %CloseButton

var _confirming: bool = false


func _ready() -> void:
	add_to_group("prestige_window")
	visible = false
	_close_button.pressed.connect(close)
	_fold_button.pressed.connect(_on_fold_pressed)
	_dim.gui_input.connect(_on_dim_input)
	EventBus.prestige_changed.connect(_on_state_changed)
	EventBus.gold_changed.connect(_on_state_changed.unbind(1))


func open() -> void:
	if visible:
		return
	_confirming = false
	GameState.open_object_window()  # hold the hero while the world is on the table
	visible = true
	_render()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_dim.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	_confirming = false
	GameState.close_object_window()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_state_changed() -> void:
	if visible:
		_render()


func _render() -> void:
	_shard_label.text = "보유 별조각  ★%d" % GameState.star_shards
	for c in _perks.get_children():
		c.queue_free()
	for perk: Dictionary in Balance.PRESTIGE_PERKS:
		_perks.add_child(_make_perk_row(perk))
	var pending: int = GameState.prestige_shards_on_reset()
	_fold_button.disabled = not GameState.can_prestige()
	if _confirming:
		_fold_button.text = "정말로? 세계가 접힌다 ▸"
	elif pending > 0:
		_fold_button.text = "세계 다시 쓰기  +%d★" % pending
	else:
		_fold_button.text = "세계 다시 쓰기  (골드를 더 모으자)"


func _make_perk_row(perk: Dictionary) -> Control:
	var id: StringName = StringName(perk.get("id", &""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	row.add_child(text_col)
	var name_label := Label.new()
	name_label.text = str(perk.get("name", ""))
	name_label.add_theme_font_override("font", PERK_FONT)
	name_label.add_theme_font_size_override("font_size", 9)
	text_col.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(perk.get("desc", ""))
	desc_label.add_theme_font_override("font", PERK_FONT)
	desc_label.add_theme_font_size_override("font_size", 7)
	desc_label.add_theme_color_override("font_color", Color(0.478, 0.427, 0.36, 1.0))
	text_col.add_child(desc_label)

	var level: int = GameState.perk_level(id)
	var max_level: int = int(perk.get("max_level", 1))
	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(58.0, 16.0)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.add_theme_font_size_override("font_size", 7)
	if level >= max_level:
		buy.text = "MAX Lv%d" % level
		buy.disabled = true
	else:
		buy.text = "%d★  Lv%d" % [GameState.perk_cost(id), level + 1]
		buy.disabled = not GameState.can_buy_perk(id)
		buy.pressed.connect(GameState.buy_perk.bind(id))
	row.add_child(buy)
	return row


func _on_fold_pressed() -> void:
	if not GameState.can_prestige():
		return
	if not _confirming:
		# Two-step confirm: folding wipes the run — make the player mean it.
		_confirming = true
		_render()
		return
	GameState.do_prestige()
	close()
	# Fresh world: reload the whole scene; autoloads (and the shards) survive.
	get_tree().call_deferred("reload_current_scene")
