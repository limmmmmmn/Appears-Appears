@tool
class_name RightPropertyInspector
extends PanelContainer

## Right-side property inspector (v1). Click a field ally / enemy / objet on the map
## and it shows here. Vertical + extensible:
##   ① 헤더 : 정사각 스프라이트(가운데) + 이름   ← 모든 대상 공통
##   ② 정보 : 역할 한 줄
##   ③ 액션 : 업그레이드 버튼(골드 부족 시 비활성 + 가격 표시)
## Nothing selected → "클릭해서 선택". ②③ are one each for now; the section builders
## below take arrays so more rows can be added later without touching the layout.
##
## Each selectable target implements `get_inspector_data() -> Dictionary`:
##   { "name": String, "info": String, "sprite": Texture2D,
##     "actions": Array[ { "label": String, "cost": int, "enabled": bool,
##                         "on_press": Callable } ] }

const HEADER_ICON: float = 44.0
const UPGRADE_SHOP_SCRIPT = preload("res://scripts/runtime/upgrade_shop.gd")

var _selected: Node = null
var _vbox: VBoxContainer


func _ready() -> void:
	add_to_group("property_inspector")
	# Size/position/look are authored in the scene/theme now (drag/resize in the
	# editor -> it sticks in-game). Code only fills the dynamic content.
	# The panel is anchored to a FIXED on-screen rect (see the scene: top → near the
	# bottom edge). A long selection (마을 상점 with many rows) used to grow the panel
	# straight off the bottom of the screen — now the content lives in a ScrollContainer
	# so it scrolls inside those fixed bounds instead of overflowing.
	_ensure_content()
	# Editor preview: show the empty state at the real panel size so the scene matches
	# the game (the panel sizes itself in code, so without this it collapses to a thin
	# strip in the editor). No GameState / signals in the editor.
	if Engine.is_editor_hint():
		if _vbox.get_child_count() == 0:
			_build_empty()
		return
	EventBus.inspector_target_selected.connect(_on_target_selected)
	# Live refresh of affordability / stats while a target is shown. The 마을 shop
	# below also reacts to buys / equips / sells, so mirror those signals too.
	EventBus.gold_changed.connect(_on_state_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_state_changed.unbind(1))
	EventBus.inventory_changed.connect(_on_state_changed)
	EventBus.party_equipment_changed.connect(_on_state_changed.unbind(1))
	EventBus.weapon_equipped.connect(_on_state_changed.unbind(1))
	EventBus.armor_equipped.connect(_on_state_changed.unbind(1))
	_render()


func _ensure_content() -> void:
	# The scene wraps the scroll in a titlebar'd window layout; fall back to the old
	# flat path (or building one in code) so the script stays scene-shape tolerant.
	var scroll := get_node_or_null(^"Layout/Body/Scroll") as ScrollContainer
	if scroll == null:
		scroll = get_node_or_null(^"Scroll") as ScrollContainer
	if scroll == null:
		scroll = ScrollContainer.new()
		scroll.name = "Scroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(scroll)
	else:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox = scroll.get_node_or_null(^"Content") as VBoxContainer
	if _vbox == null:
		_vbox = VBoxContainer.new()
		_vbox.name = "Content"
		scroll.add_child(_vbox)
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 4)


func _on_target_selected(target: Node) -> void:
	if is_instance_valid(_selected) and _selected.tree_exited.is_connected(_on_selected_freed):
		_selected.tree_exited.disconnect(_on_selected_freed)
	_selected = target
	# A selected enemy can die / despawn — drop back to the empty state when it does.
	if is_instance_valid(_selected):
		_selected.tree_exited.connect(_on_selected_freed)
	_render()


func _on_selected_freed() -> void:
	_selected = null
	_render()


func _on_state_changed() -> void:
	if is_instance_valid(_selected):
		_render()


func _render() -> void:
	for c in _vbox.get_children():
		c.queue_free()
	if not is_instance_valid(_selected) or not _selected.has_method("get_inspector_data"):
		_set_title("속성")
		_build_empty()
		return
	var data: Dictionary = _selected.get_inspector_data()
	_set_title(str(data.get("name", "속성")))
	_build_header(data)
	_build_info(data)
	_build_actions(data)
	# 마을: the inn + gear shop live here now (was a floating popup above the village),
	# pinned right below the 강화 slot.
	if bool(data.get("shop", false)):
		GearShop.build(_vbox)
	if bool(data.get("upgrade_shop", false)):
		UPGRADE_SHOP_SCRIPT.build(_vbox)


## Window titlebar text mirrors the selection ("속성" when nothing is picked).
func _set_title(text: String) -> void:
	var title := get_node_or_null(^"Layout/TitleBar/TitleRow/TitleLabel") as Label
	if title != null:
		title.text = text


func _build_empty() -> void:
	var label := Label.new()
	label.text = "클릭해서 선택"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0.0, 56.0)
	label.add_theme_color_override("font_color", DOS.DIM)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SECTION)
	_vbox.add_child(label)


# ─── ① 헤더: 정사각 스프라이트 + 이름 ──────────────────────────────────
func _build_header(data: Dictionary) -> void:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(0.0, HEADER_ICON + 2.0)
	var tex := TextureRect.new()
	tex.texture = data.get("sprite", null)
	tex.custom_minimum_size = Vector2(HEADER_ICON, HEADER_ICON)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(tex)
	_vbox.add_child(box)
	var name_label := Label.new()
	name_label.text = str(data.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", DOS.TEXT)
	name_label.add_theme_font_size_override("font_size", UITheme.FONT_CARD_NAME)
	_vbox.add_child(name_label)


# ─── ② 정보: 역할 한 줄 (확장 가능 — 여러 줄도 OK) ─────────────────────
func _build_info(data: Dictionary) -> void:
	var info: String = str(data.get("info", ""))
	if info.is_empty():
		return
	var label := Label.new()
	label.text = info
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", DOS.DIM)
	label.add_theme_font_size_override("font_size", UITheme.FONT_CARD_VALUE)
	_vbox.add_child(label)


# ─── ③ 액션: 업그레이드 버튼들 (지금은 0~1개, 나중에 늘릴 수 있음) ──────
func _build_actions(data: Dictionary) -> void:
	var actions: Array = data.get("actions", [])
	if actions.is_empty():
		# Targets without an upgrade yet still show the ③ slot (준비 중) for structure.
		var placeholder := Button.new()
		placeholder.text = "강화 (준비 중)"
		placeholder.disabled = true
		placeholder.focus_mode = Control.FOCUS_NONE
		placeholder.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
		placeholder.add_theme_color_override("font_disabled_color", DOS.DIM)
		_vbox.add_child(placeholder)
		return
	for action: Dictionary in actions:
		_vbox.add_child(_make_action_button(action))


func _make_action_button(action: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
	var label: String = str(action.get("label", "강화"))
	var cost: int = int(action.get("cost", 0))
	var enabled: bool = bool(action.get("enabled", false))
	b.text = "%s  %dG" % [label, cost] if cost > 0 else label
	b.disabled = not enabled
	b.add_theme_color_override("font_disabled_color", DOS.DIM)
	var cb: Callable = action.get("on_press", Callable())
	if enabled and cb.is_valid():
		b.pressed.connect(cb)
	return b


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = DOS.BG
	s.border_color = DOS.BORDER
	s.set_border_width_all(1)
	s.set_content_margin_all(float(UITheme.PANEL_CONTENT_MARGIN))
	s.anti_aliasing = false
	return s
