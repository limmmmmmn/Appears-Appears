class_name OSWindow

## Shared "app window" chrome for the OS-desktop UI. Every panel (field, 강화, 마을,
## 인벤, 도구 dock, narration) wears the SAME clothes via these helpers:
##   • white border (1px)
##   • only the CORNERS slightly curved (retro OS window — not a full pill)
##   • a titlebar showing the app name
## Centralized so a future "retro game skin" can restyle every window in one place.

const FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const BORDER: Color = Color(0.96, 0.97, 0.99, 1.0)   ## white window edge
const BODY: Color = Color(0.18, 0.133, 0.184, 0.98)  ## #2e222f dark interior
const TITLE_TEXT: Color = Color(0.96, 0.97, 0.99, 1.0)
const CORNER: int = 3                                ## 끝만 살짝 — small radius
const TITLE_FONT: int = 8


## Window body: dark fill, white border, lightly-rounded corners, soft shadow.
static func body_style(bg: Color = BODY) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(CORNER)
	s.set_border_width_all(1)
	s.border_color = BORDER
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 4
	return s


## Titlebar: colored accent strip, rounded only on the TOP corners, white-bordered
## sides/top to merge with the body border.
static func titlebar_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = accent
	s.corner_radius_top_left = CORNER
	s.corner_radius_top_right = CORNER
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_color = BORDER
	s.content_margin_left = 5
	s.content_margin_right = 4
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


## A titlebar label (the app name shown like "필드.app").
static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", TITLE_FONT)
	l.add_theme_color_override("font_color", TITLE_TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
