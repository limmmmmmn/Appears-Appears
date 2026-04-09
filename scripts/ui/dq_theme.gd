class_name DQTheme
extends RefCounted
## 클래식 드퀘 스타일 유틸리티. 검정 배경 + 흰색 이중 테두리 + 흰색 텍스트.

const BG_COLOR := Color(0.0, 0.0, 0.0, 0.95)
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const DIM_TEXT_COLOR := Color(0.55, 0.55, 0.55, 1.0)

## 검정 배경 + 흰색 이중선 스타일박스
static func make_window_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.expand_margin_left = 2
	sb.expand_margin_right = 2
	sb.expand_margin_top = 2
	sb.expand_margin_bottom = 2
	sb.anti_aliasing = false
	return sb

## 흰색 이중선 표현을 위한 얇은 내부 스타일 (ouptside wrap 용)
static func make_inner_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.anti_aliasing = false
	return sb

## 패널 전용: 배경 검정, 테두리 흰색
static func make_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = false
	return sb

## 버튼 스타일박스
static func make_button_stylebox(hovered: bool = false, pressed: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR if not pressed else Color(0.15, 0.15, 0.15, 0.95)
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(2 if not hovered else 3)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = false
	return sb

## Control에 DQ 윈도우 스타일을 적용. PanelContainer 같은 배경 override가 가능한 노드면 설정.
static func apply_window_style(target: Control) -> void:
	if target == null:
		return
	if target is PanelContainer:
		target.add_theme_stylebox_override("panel", make_window_stylebox())
	elif target is Panel:
		target.add_theme_stylebox_override("panel", make_window_stylebox())

## 모든 Label 자식에 흰 텍스트 색 적용
static func apply_label_color(target: Control) -> void:
	if target == null:
		return
	_apply_label_recursive(target)

static func _apply_label_recursive(node: Node) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", TEXT_COLOR)
	elif node is RichTextLabel:
		(node as RichTextLabel).add_theme_color_override("default_color", TEXT_COLOR)
	elif node is Button:
		var btn := node as Button
		btn.add_theme_color_override("font_color", TEXT_COLOR)
		btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
		btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)
		btn.add_theme_color_override("font_focus_color", TEXT_COLOR)
		btn.add_theme_stylebox_override("normal", make_button_stylebox(false, false))
		btn.add_theme_stylebox_override("hover", make_button_stylebox(true, false))
		btn.add_theme_stylebox_override("pressed", make_button_stylebox(false, true))
		btn.add_theme_stylebox_override("focus", make_button_stylebox(true, false))
	for child in node.get_children():
		_apply_label_recursive(child)

## 전체 적용 (윈도우 + 내부 라벨들)
static func apply_full(target: Control) -> void:
	apply_window_style(target)
	apply_label_color(target)
