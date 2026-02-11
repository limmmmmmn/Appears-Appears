extends Control
class_name MiniMap
## 미니맵 - 타일맵 기반 간략 지도
## 플레이어 위치(노랑 점), 적(빨강 점), 출구(초록 사각) 표시

const TILE_COLORS := {
	"grass": Color(0.25, 0.5, 0.2),
	"forest": Color(0.12, 0.32, 0.12),
	"mountain": Color(0.42, 0.36, 0.26),
	"water": Color(0.15, 0.3, 0.55),
	"cave": Color(0.22, 0.2, 0.28),
}
const EMPTY_COLOR := Color(0.03, 0.03, 0.06, 0.3)
const PLAYER_COLOR := Color(1.0, 1.0, 0.3)
const ENEMY_COLOR := Color(0.85, 0.2, 0.2)
const EXIT_COLOR := Color(0.3, 1.0, 0.5)
const BG_COLOR := Color(0.03, 0.03, 0.06, 0.9)
const BORDER_COLOR := Color(0.3, 0.35, 0.5, 0.7)

const TILE_SIZE := 16  # 게임 타일 크기

var tilemap: TileMapLayer
var tile_type_map := {0: "grass", 1: "forest", 2: "mountain", 3: "water", 4: "cave"}

var map_texture: ImageTexture
var map_bounds: Rect2i
var field_ref: WeakRef = weakref(null)

var is_setup := false
var _blink_timer := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	call_deferred("_find_and_setup")


func _find_and_setup() -> void:
	var field = _find_field()
	if field:
		field_ref = weakref(field)
		if field.tilemap:
			_setup_tilemap(field.tilemap)


func _find_field():
	# FieldHUD(CanvasLayer) → 부모가 Field
	var node = get_parent()
	while node:
		if node.has_method("get_party_leader"):
			return node
		node = node.get_parent()
	# 폴백: 현재 씬
	var root = get_tree().current_scene
	if root and root.has_method("get_party_leader"):
		return root
	return null


func _setup_tilemap(p_tilemap: TileMapLayer) -> void:
	tilemap = p_tilemap
	_build_map_texture()
	is_setup = true


func _build_map_texture() -> void:
	var used_rect := tilemap.get_used_rect()
	map_bounds = used_rect
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return

	var img := Image.create(used_rect.size.x, used_rect.size.y, false, Image.FORMAT_RGBA8)
	for y in range(used_rect.size.y):
		for x in range(used_rect.size.x):
			var cell := Vector2i(used_rect.position.x + x, used_rect.position.y + y)
			var source_id: int = tilemap.get_cell_source_id(cell)
			if source_id < 0:
				img.set_pixel(x, y, EMPTY_COLOR)
				continue
			var tile_type: String = str(tile_type_map.get(source_id, "grass"))
			img.set_pixel(x, y, TILE_COLORS.get(tile_type, EMPTY_COLOR))

	map_texture = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if is_setup:
		_blink_timer += delta
		queue_redraw()


func _draw() -> void:
	# 배경
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.0)

	if not is_setup or map_texture == null:
		return

	# 맵 텍스처 스케일링
	var pad := 3.0
	var draw_area := size - Vector2(pad * 2, pad * 2)
	var scale_x: float = draw_area.x / float(map_bounds.size.x)
	var scale_y: float = draw_area.y / float(map_bounds.size.y)
	var map_scale: float = min(scale_x, scale_y)
	var map_draw_size := Vector2(map_bounds.size) * map_scale
	var offset := Vector2(pad, pad) + (draw_area - map_draw_size) * 0.5

	draw_texture_rect(map_texture, Rect2(offset, map_draw_size), false)

	var field = field_ref.get()
	if field == null:
		return

	# 플레이어 (깜빡이는 노란 점)
	if field.party_leader and is_instance_valid(field.party_leader):
		var player_cell := tilemap.local_to_map(field.party_leader.global_position)
		var px: float = float(player_cell.x - map_bounds.position.x) * map_scale + offset.x
		var py: float = float(player_cell.y - map_bounds.position.y) * map_scale + offset.y
		var blink_alpha: float = 0.6 + 0.4 * sin(_blink_timer * 5.0)
		var c := PLAYER_COLOR
		c.a = blink_alpha
		draw_circle(Vector2(px, py), 2.5, c)

	# 적 (빨간 점)
	for enemy in field.field_enemies:
		if not is_instance_valid(enemy):
			continue
		var enemy_cell := tilemap.local_to_map(enemy.global_position)
		var ex: float = float(enemy_cell.x - map_bounds.position.x) * map_scale + offset.x
		var ey: float = float(enemy_cell.y - map_bounds.position.y) * map_scale + offset.y
		draw_circle(Vector2(ex, ey), 1.5, ENEMY_COLOR)

	# 출구 (초록 사각)
	if field.exit_area and is_instance_valid(field.exit_area):
		var exit_cell := tilemap.local_to_map(field.exit_area.global_position)
		var epx: float = float(exit_cell.x - map_bounds.position.x) * map_scale + offset.x
		var epy: float = float(exit_cell.y - map_bounds.position.y) * map_scale + offset.y
		draw_rect(Rect2(epx - 2, epy - 2, 4, 4), EXIT_COLOR)
