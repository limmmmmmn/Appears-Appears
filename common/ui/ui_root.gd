extends CanvasLayer
class_name UIRoot

@onready var popup_layer: Control = $PopupLayer
@onready var hud_layer: Control = $HudLayer
@onready var toast_layer: Control = $ToastLayer

func _ready() -> void:
	# M0: 로직 없음 (부팅 안정성만)
	pass
