extends PanelContainer
class_name TrinketBadge

@onready var emoji_label: Label = $EmojiLabel
var _emoji_font: Font = null


func configure(data: Dictionary) -> void:
	var emoji: String = str(data.get("emoji", "🧿"))
	var name: String = str(data.get("name", "Trinket"))
	var desc: String = str(data.get("description", ""))
	if emoji_label != null:
		if _emoji_font == null:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray([
				"Apple Color Emoji",
				"Segoe UI Emoji",
				"Noto Color Emoji"
			])
			_emoji_font = sf
		emoji_label.add_theme_font_override("font", _emoji_font)
		emoji_label.text = emoji
	tooltip_text = "%s\n%s" % [name, desc]
