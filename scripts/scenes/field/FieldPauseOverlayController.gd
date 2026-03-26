extends RefCounted
class_name FieldPauseOverlayController

var host: Node = null
var pause_dim_layer: CanvasLayer = null
var pause_dim_rect: ColorRect = null


func setup(p_host: Node) -> void:
	host = p_host


func ensure_overlay() -> void:
	if host == null:
		return
	if pause_dim_layer != null and is_instance_valid(pause_dim_layer):
		return

	pause_dim_layer = CanvasLayer.new()
	pause_dim_layer.name = "PauseDimLayer"
	pause_dim_layer.layer = 9
	pause_dim_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(pause_dim_layer)

	pause_dim_rect = ColorRect.new()
	pause_dim_rect.name = "PauseDimRect"
	pause_dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim_rect.color = Color(0.0, 0.0, 0.0, 0.28)
	pause_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_dim_rect.visible = false
	pause_dim_layer.add_child(pause_dim_rect)


func update_overlay(is_paused: bool, party_chatter_root: Control) -> void:
	if pause_dim_rect == null or not is_instance_valid(pause_dim_rect):
		return
	pause_dim_rect.visible = is_paused
	if party_chatter_root != null and is_instance_valid(party_chatter_root):
		party_chatter_root.modulate = Color(0.62, 0.62, 0.62, 1.0) if is_paused else Color(1, 1, 1, 1)
