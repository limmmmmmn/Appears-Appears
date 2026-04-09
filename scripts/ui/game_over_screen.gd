extends CanvasLayer

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var retry_button: Button = $CenterContainer/Panel/VBox/RetryButton
@onready var quit_button: Button = $CenterContainer/Panel/VBox/QuitButton

func _ready() -> void:
	DQThemeScript.apply_full(panel)
	retry_button.pressed.connect(_on_retry)
	quit_button.pressed.connect(_on_quit)

func _on_retry() -> void:
	get_tree().reload_current_scene()

func _on_quit() -> void:
	get_tree().quit()
