class_name DesktopFrame
extends Control

## Frames the FIELD as an "app window" floating on the desktop wallpaper. The field
## (a camera world) fills the viewport, so we overlay opaque wallpaper-colored bands
## around an inset rectangle + a window titlebar — visually the field becomes a
## window with the desktop showing around it. It's the MAIN app: the close pip is
## present but disabled (the field never closes).
##   Sits just above the field (layer 1) and below all the toggleable app windows.

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const WALLPAPER: Color = Color(0.07, 0.08, 0.11, 1.0)    ## dark void (matches WallpaperLayer)
const TITLEBAR: Color = Color(0.18, 0.133, 0.184, 1.0)   ## #2e222f window chrome
const BORDER: Color = Color(0.96, 0.97, 0.99, 1.0)       ## shared white window edge (OSWindow.BORDER)
const TITLE_TEXT: Color = Color(0.96, 0.97, 0.99, 1.0)

## Field "window" — WIDE again: it fills the central area between the side panels
## (the dynamic hero/enemy movement needs room). Cards float on top, screen-fixed.
const FIELD_RECT: Rect2 = Rect2(126.0, 17.0, 396.0, 341.0)
const TITLEBAR_H: float = 12.0
const VIEWPORT: Vector2 = Vector2(640.0, 360.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var fr: Rect2 = FIELD_RECT
	# Four opaque wallpaper bands cover the field's overflow → only the inset shows.
	_band(0.0, 0.0, VIEWPORT.x, fr.position.y)                                  # top
	_band(0.0, fr.end.y, VIEWPORT.x, VIEWPORT.y - fr.end.y)                     # bottom
	_band(0.0, fr.position.y, fr.position.x, fr.size.y)                         # left
	_band(fr.end.x, fr.position.y, VIEWPORT.x - fr.end.x, fr.size.y)            # right
	_window_border(fr)
	# (Field titlebar / traffic lights removed — no OS chrome on the stage.)


func _band(x: float, y: float, w: float, h: float) -> void:
	var r := ColorRect.new()
	r.color = WALLPAPER
	r.position = Vector2(x, y)
	r.size = Vector2(maxf(0.0, w), maxf(0.0, h))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _window_border(fr: Rect2) -> void:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)        # transparent center → field shows through
	s.set_border_width_all(1)
	s.border_color = BORDER
	s.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", s)
	p.position = fr.position
	p.size = fr.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)


func _titlebar(fr: Rect2) -> void:
	var bar := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = TITLEBAR
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	bar.add_theme_stylebox_override("panel", s)
	bar.position = fr.position
	bar.size = Vector2(fr.size.x, TITLEBAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	# Traffic-light pips (left). The close (red) is DISABLED — the field never closes.
	var pips := [Color(0.45, 0.4, 0.45, 1.0), Color(0.96, 0.74, 0.28, 1.0), Color(0.31, 0.78, 0.35, 1.0)]
	for i in pips.size():
		var dot := Panel.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = pips[i]
		ds.set_corner_radius_all(3)
		dot.add_theme_stylebox_override("panel", ds)
		dot.size = Vector2(5.0, 5.0)
		dot.position = Vector2(fr.position.x + 5.0 + float(i) * 8.0, fr.position.y + (TITLEBAR_H - 5.0) * 0.5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)

	var title := Label.new()
	title.text = "필드.app"
	title.add_theme_font_override("font", PANEL_FONT)
	title.add_theme_font_size_override("font_size", 8)
	title.add_theme_color_override("font_color", TITLE_TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(fr.position.x, fr.position.y)
	title.size = Vector2(fr.size.x, TITLEBAR_H)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
