class_name DOS

## DOS-game UI kit: flat single-tone boxes, one border color, one font size, tidy
## rows. No per-card colors, no gradients/shadows — only the item SPRITES keep
## their color (for identification). Centralized so every list looks identical.
##
## LOOK SOURCE = assets/themes/ui_theme.tres (the master Theme). Edit colors,
## fonts, font sizes, and styleboxes THERE in Godot's Theme editor — this script
## only READS them, so the whole UI restyles without touching code. (Logic stays
## in code; only the look lives in the theme.)

const THEME: Theme = preload("res://assets/themes/ui_theme.tres")

# Palette mirrors — pulled from the editable theme at load. Keep the old names so
# every caller (DOS.TEXT, DOS.ROW_H, …) keeps working unchanged.
static var FONT: Font = THEME.default_font
static var FONT_SIZE: int = THEME.get_font_size("body", "Palette")
static var SECTION_SIZE: int = THEME.get_font_size("section", "Palette")
static var BG: Color = THEME.get_color("bg", "Palette")
static var ROW_BG: Color = THEME.get_color("row_bg", "Palette")
static var ROW_HOVER: Color = THEME.get_color("row_hover", "Palette")
static var BORDER: Color = THEME.get_color("border", "Palette")
static var TEXT: Color = THEME.get_color("text", "Palette")
static var DIM: Color = THEME.get_color("dim", "Palette")
static var SECTION: Color = THEME.get_color("section", "Palette")
static var ROW_H: float = float(THEME.get_constant("row_h", "Palette"))
static var ICON: float = float(THEME.get_constant("icon", "Palette"))


## Panel box. Pass a bg to override the theme's fill (else uses the theme's).
static func box_style(bg = null) -> StyleBoxFlat:
	var s := THEME.get_stylebox("box", "Palette").duplicate() as StyleBoxFlat
	if bg != null:
		s.bg_color = bg
	return s


## Row fill at the given bg (border/corner/margins come from the theme's row box).
static func row_style(bg: Color) -> StyleBoxFlat:
	var s := THEME.get_stylebox("row", "Palette").duplicate() as StyleBoxFlat
	s.bg_color = bg
	return s


static func label(text: String, color = null, size: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size if size > 0 else FONT_SIZE)
	l.add_theme_color_override("font_color", color if color != null else TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## "── 적 ──" style section header.
static func section(text: String) -> Label:
	var l := label("── %s ──" % text, SECTION, SECTION_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A colored sprite cell (sprite keeps its color; null → empty spacer).
static func icon(texture: Texture2D) -> Control:
	var tr := TextureRect.new()
	tr.texture = texture
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# IGNORE_SIZE so big source sprites are forced down to ICON×ICON (else the
	# texture's native size wins and they render huge).
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(ICON, ICON)
	tr.size = Vector2(ICON, ICON)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Styles a Button as a flat DOS row (normal/hover/pressed/disabled).
static func style_button(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", row_style(ROW_BG))
	b.add_theme_stylebox_override("hover", row_style(ROW_HOVER))
	b.add_theme_stylebox_override("pressed", row_style(ROW_HOVER))
	b.add_theme_stylebox_override("disabled", row_style(ROW_BG))
