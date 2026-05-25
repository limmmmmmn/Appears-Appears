class_name SettlementReport
extends CanvasLayer

signal continue_requested
signal town_requested

@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _report_label: Label = %ReportLabel
@onready var _inventory_label: Label = %InventoryLabel
@onready var _sell_all_button: Button = %SellAllButton
@onready var _continue_button: Button = %ContinueButton
@onready var _town_button: Button = %TownButton

var _title: String = "정산"
var _lines: PackedStringArray = []
var _gold: int = 0
var _selling_inventory: bool = false


func setup(title: String, lines: PackedStringArray, gold: int) -> void:
	_title = title
	_lines = lines.duplicate()
	_gold = gold


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_title_label.text = _title
	_refresh_gold_label()
	_report_label.text = "\n".join(_lines)
	_refresh_inventory()
	_sell_all_button.pressed.connect(_on_sell_all_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_town_button.pressed.connect(_on_town_pressed)
	_town_button.grab_focus()


func _on_continue_pressed() -> void:
	if _selling_inventory:
		return
	continue_requested.emit()
	queue_free()


func _on_town_pressed() -> void:
	if _selling_inventory:
		return
	town_requested.emit()
	queue_free()


func _on_sell_all_pressed() -> void:
	if _selling_inventory or GameState.inventory_items().is_empty():
		return
	_selling_inventory = true
	_continue_button.disabled = true
	_town_button.disabled = true
	_sell_all_button.disabled = true
	var sold_total: int = 0
	while not GameState.inventory_items().is_empty() and is_inside_tree():
		var value: int = GameState.sell_inventory_entry_at(0)
		if value <= 0:
			break
		sold_total += value
		_sell_all_button.text = "판매중 +%dG" % sold_total
		_refresh_gold_label()
		_refresh_inventory()
		_pop_gold_label()
		await get_tree().create_timer(0.055).timeout
	_selling_inventory = false
	_continue_button.disabled = false
	_town_button.disabled = false
	_refresh_inventory()
	_sell_all_button.text = "판매 완료" if sold_total > 0 else "일괄판매"
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	_refresh_sell_button()


func _refresh_gold_label() -> void:
	_gold = GameState.gold
	_gold_label.text = "%d G" % _gold


func _refresh_inventory() -> void:
	var items: Array = GameState.inventory_items()
	if items.is_empty():
		_inventory_label.text = "비어 있음"
	else:
		_inventory_label.text = _inventory_text(items)
	_refresh_sell_button()


func _refresh_sell_button() -> void:
	if _selling_inventory:
		return
	var total: int = GameState.inventory_sell_total()
	_sell_all_button.disabled = total <= 0
	_sell_all_button.text = "일괄판매 +%dG" % total if total > 0 else "일괄판매"


func _inventory_text(items: Array) -> String:
	var counts: Dictionary = {}
	var labels: Dictionary = {}
	for entry in items:
		var item: ItemData = GameState.item_entry_data(entry)
		if item == null:
			continue
		var level: int = GameState.item_entry_level(entry)
		var key: String = "%s:%d" % [str(item.id), level]
		counts[key] = int(counts.get(key, 0)) + 1
		labels[key] = "%s Lv %d" % [item.display_name, level]
	var lines: PackedStringArray = []
	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		var count: int = int(counts[key])
		var label: String = str(labels[key])
		lines.append("%s x%d" % [label, count] if count > 1 else label)
	return "\n".join(lines) if not lines.is_empty() else "비어 있음"


func _pop_gold_label() -> void:
	_gold_label.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(_gold_label, "scale", Vector2(1.16, 1.16), 0.04)
	tween.tween_property(_gold_label, "scale", Vector2.ONE, 0.08)
