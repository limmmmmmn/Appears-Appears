class_name DOS

## DOS-game UI kit: flat single-tone boxes, one border color, one font size, tidy
## rows. No per-card colors, no gradients/shadows — only the item SPRITES keep
## their color (for identification). Centralized so every list looks identical.

const FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const BG: Color = Color(0.094, 0.106, 0.137, 0.98)   ## panel fill
const ROW_BG: Color = Color(0.149, 0.165, 0.204, 1.0)## row fill
const ROW_HOVER: Color = Color(0.216, 0.235, 0.286, 1.0)
const BORDER: Color = Color(0.557, 0.576, 0.624, 1.0)## single border tone
const TEXT: Color = Color(0.866, 0.882, 0.910, 1.0)
const DIM: Color = Color(0.42, 0.44, 0.49, 1.0)      ## unaffordable / disabled
const SECTION: Color = Color(0.62, 0.67, 0.74, 1.0)
const FONT_SIZE: int = 8
const SECTION_SIZE: int = 8
const ROW_H: float = 18.0
const ICON: float = 16.0


static func box_style(bg: Color = BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = BORDER
	s.set_corner_radius_all(0)  # DOS = sharp rectangles
	s.set_content_margin_all(4)
	s.anti_aliasing = false
	return s


static func row_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = BORDER.darkened(0.25)
	s.set_corner_radius_all(0)
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	s.anti_aliasing = false
	return s


static func label(text: String, color: Color = TEXT, size: int = FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## "── 적 ──" style section header.
static func section(text: String) -> Label:
	var l := label("── %s ──" % text, SECTION, SECTION_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## A 12px colored sprite cell (sprite keeps its color; null → empty spacer).
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
