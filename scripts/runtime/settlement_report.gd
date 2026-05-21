class_name SettlementReport
extends CanvasLayer

signal continue_requested
signal town_requested

@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _report_label: Label = %ReportLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _town_button: Button = %TownButton

var _title: String = "정산"
var _lines: PackedStringArray = []
var _gold: int = 0


func setup(title: String, lines: PackedStringArray, gold: int) -> void:
	_title = title
	_lines = lines.duplicate()
	_gold = gold


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_title_label.text = _title
	_gold_label.text = "%d G" % _gold
	_report_label.text = "\n".join(_lines)
	_continue_button.pressed.connect(_on_continue_pressed)
	_town_button.pressed.connect(_on_town_pressed)
	_town_button.grab_focus()


func _on_continue_pressed() -> void:
	continue_requested.emit()
	queue_free()


func _on_town_pressed() -> void:
	town_requested.emit()
	queue_free()
