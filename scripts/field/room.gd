class_name Room
extends Node2D
## Room: 20x20 타일 하나의 방. 필드 생성 결과를 setup으로 주입받음.

const ROOM_SIZE := Vector2(640, 640)

@onready var floor_rect: ColorRect = $Floor
@onready var type_label: Label = $TypeLabel
@onready var north_marker: Marker2D = $EntryPoints/North
@onready var south_marker: Marker2D = $EntryPoints/South
@onready var east_marker: Marker2D = $EntryPoints/East
@onready var west_marker: Marker2D = $EntryPoints/West
@onready var objects_node: Node2D = $Objects

var room_type: String = "normal"
var grid_position: Vector2i = Vector2i.ZERO
var neighbors: Array = []
var field_type: String = "plains"
var visited: bool = false

func setup(room_data: Dictionary, field_type_str: String = "plains") -> void:
	grid_position = room_data.get("grid_pos", Vector2i.ZERO)
	room_type = String(room_data.get("type", "normal"))
	neighbors = room_data.get("neighbors", [])
	field_type = field_type_str
	call_deferred("_apply_visuals")

func _apply_visuals() -> void:
	if floor_rect:
		floor_rect.color = _floor_color_for(field_type, room_type)
	if type_label:
		type_label.text = _label_for(room_type)
	_spawn_decorations()

func _floor_color_for(ft: String, rt: String) -> Color:
	var base: Color
	match ft:
		"plains": base = Color(0.30, 0.58, 0.25)
		"forest": base = Color(0.12, 0.38, 0.18)
		"dungeon": base = Color(0.22, 0.18, 0.24)
		"mountain": base = Color(0.46, 0.40, 0.32)
		"cave": base = Color(0.18, 0.22, 0.26)
		_: base = Color(0.30, 0.50, 0.25)
	match rt:
		"start": base = base.lightened(0.15)
		"exit": base = base.lightened(0.05)
		"treasure": base = Color(0.42, 0.38, 0.12).lerp(base, 0.4)
		"event": base = Color(0.18, 0.22, 0.48).lerp(base, 0.6)
		"fork": base = Color(0.52, 0.18, 0.18).lerp(base, 0.5)
	return base

func _label_for(rt: String) -> String:
	match rt:
		"start": return "★ 시작"
		"exit": return "▷ 출구"
		"treasure": return "◆ 보물"
		"event": return "? 이벤트"
		"fork": return "⟡ 분기"
		_: return ""

func _spawn_decorations() -> void:
	# 방 안에 배경 장식 점 찍기 (필드 타입별 색)
	var count := 12
	var deco_color := Color(0.08, 0.08, 0.08, 0.7)
	match field_type:
		"plains": deco_color = Color(1, 1, 1, 0.15)  # 꽃
		"forest": deco_color = Color(0.05, 0.2, 0.1, 0.8)  # 짙은 덤불
		"dungeon": deco_color = Color(0.6, 0.5, 0.2, 0.4)  # 횃불
		"mountain": deco_color = Color(0.3, 0.3, 0.3, 0.8)  # 바위
	for i in count:
		var dot := ColorRect.new()
		dot.size = Vector2(8, 8)
		dot.color = deco_color
		dot.position = Vector2(
			randf_range(40, ROOM_SIZE.x - 48),
			randf_range(40, ROOM_SIZE.y - 48)
		)
		objects_node.add_child(dot)

## 특정 이웃 방향으로 가는 진입점 반환 (방의 중앙 → 방향 경계 중간)
func entry_point_for_direction(dir: Vector2i) -> Vector2:
	match dir:
		Vector2i(0, -1): return position + north_marker.position
		Vector2i(1, 0): return position + east_marker.position
		Vector2i(0, 1): return position + south_marker.position
		Vector2i(-1, 0): return position + west_marker.position
		_: return position + Vector2(ROOM_SIZE.x * 0.5, ROOM_SIZE.y * 0.5)

func center() -> Vector2:
	return position + ROOM_SIZE * 0.5
