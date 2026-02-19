extends PanelContainer
class_name TrinketBadge

@onready var emoji_label: Label = $EmojiLabel


func configure(data: Dictionary) -> void:
	var emoji: String = str(data.get("emoji", "🧿"))
	var name: String = str(data.get("name", "Trinket"))
	var desc: String = str(data.get("description", ""))
	if emoji_label != null:
		emoji_label.text = emoji
	tooltip_text = "%s\n%s" % [name, desc]
