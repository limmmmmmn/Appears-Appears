class_name OSWindow

## Shared "app window" chrome for the OS-desktop UI. Every panel (field, 강화, 마을,
## 인벤, 도구 dock, narration) wears the SAME clothes via these helpers:
##   • white border (1px)
##   • only the CORNERS slightly curved (retro OS window — not a full pill)
##   • a titlebar showing the app name
##
## LOOK SOURCE = assets/themes/ui_theme.tres (the master Theme). The "window" and
## "titlebar" styleboxes + the window colors/fonts live there — edit them in the
## Godot Theme editor; this script only reads them.

const THEME: Theme = preload("res://assets/themes/ui_theme.tres")

static var FONT: Font = THEME.default_font
static var BORDER: Color = THEME.get_color("window_border", "Palette")  ## white window edge
static var BODY: Color = THEME.get_color("window_body", "Palette")      ## dark interior
static var TITLE_TEXT: Color = THEME.get_color("title_text", "Palette")
static var CORNER: int = THEME.get_constant("corner", "Palette")        ## 끝만 살짝
static var TITLE_FONT: int = THEME.get_font_size("title", "Palette")


## Window body: dark fill, white border, lightly-rounded corners, soft shadow.
## Pass a bg to override the theme's interior fill.
static func body_style(bg = null) -> StyleBoxFlat:
	var s := THEME.get_stylebox("window", "Palette").duplicate() as StyleBoxFlat
	if bg != null:
		s.bg_color = bg
	return s


## Titlebar: colored accent strip, rounded only on the TOP corners, white-bordered
## sides/top to merge with the body border.
static func titlebar_style(accent: Color) -> StyleBoxFlat:
	var s := THEME.get_stylebox("titlebar", "Palette").duplicate() as StyleBoxFlat
	s.bg_color = accent
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
