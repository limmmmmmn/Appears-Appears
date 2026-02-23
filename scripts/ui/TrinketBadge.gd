extends PanelContainer
class_name TrinketBadge

@onready var emoji_label: Label = $EmojiLabel

var _pending_data: Dictionary = {}


func configure(data: Dictionary) -> void:
	_pending_data = data
	# 아직 트리에 추가되지 않았으면 _ready에서 적용
	if is_inside_tree() and emoji_label != null:
		_apply_data()


func _ready() -> void:
	if not _pending_data.is_empty():
		_apply_data()


func _apply_data() -> void:
	var emoji: String = str(_pending_data.get("emoji", "🧿"))
	var trinket_name: String = str(_pending_data.get("name", "Trinket"))
	var desc: String = str(_pending_data.get("description", ""))
	if emoji_label != null:
		emoji_label.text = emoji
	tooltip_text = "%s\n%s" % [trinket_name, desc]
