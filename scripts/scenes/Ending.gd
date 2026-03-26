extends Control
## Ending: 게임 클리어 엔딩 화면
class_name EndingScreen

signal title_pressed
signal quit_pressed

var stats: Dictionary = {}  # 플레이 통계
var tween: Tween = null


func _ready() -> void:
	# 통계 수집
	_collect_stats()
	
	# UI 구성
	_build_ui()
	
	# 페이드인 애니메이션
	modulate.a = 0
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.5)


func _collect_stats() -> void:
	## 플레이 통계 수집
	stats = {
		"gold": GameManager.gold,
		"act": GameManager.get_act_display(),
		"party_size": PartyManager.get_party().size(),
		"legendaries": GameManager.obtained_legendaries.size()
	}
	
	# 파티 정보
	var hero_names: Array[String] = []
	for hero in PartyManager.get_party():
		hero_names.append(hero.hero_name)

	stats["party_size"] = hero_names.size()
	stats["hero_names"] = hero_names


func _build_ui() -> void:
	# 전체 화면 배경
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.05, 1.0)
	add_child(bg)
	
	# 별 효과 배경
	_add_star_background()
	
	# 중앙 컨테이너
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	# 🎉 축하 타이틀
	var title := Label.new()
	title.text = "🎉 CONGRATULATIONS! 🎉"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 서브 타이틀
	var subtitle := Label.new()
	subtitle.text = "고블린 킹을 물리치고 평화를 되찾았다!"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color.WHITE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# 구분선
	var sep := HSeparator.new()
	sep.custom_minimum_size.x = 400
	vbox.add_child(sep)
	
	# 통계 패널
	var stats_panel := PanelContainer.new()
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	stats_style.set_border_width_all(2)
	stats_style.border_color = Color.GOLD
	stats_style.set_corner_radius_all(10)
	stats_panel.add_theme_stylebox_override("panel", stats_style)
	vbox.add_child(stats_panel)
	
	var stats_margin := MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 30)
	stats_margin.add_theme_constant_override("margin_right", 30)
	stats_margin.add_theme_constant_override("margin_top", 20)
	stats_margin.add_theme_constant_override("margin_bottom", 20)
	stats_panel.add_child(stats_margin)
	
	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 12)
	stats_margin.add_child(stats_vbox)
	
	# 통계 제목
	var stats_title := Label.new()
	stats_title.text = "〈 모험의 기록 〉"
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.add_theme_color_override("font_color", Color.GOLD)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_vbox.add_child(stats_title)
	
	# 파티 멤버
	var party_label := Label.new()
	var hero_names: Array = stats.get("hero_names", [])
	party_label.text = "🗡️ 영웅들: %s" % ", ".join(hero_names)
	party_label.add_theme_color_override("font_color", Color.LIGHT_CYAN)
	stats_vbox.add_child(party_label)
	
	
	# 획득 골드
	var gold_label := Label.new()
	gold_label.text = "💰 보유 골드: %d G" % stats.get("gold", 0)
	gold_label.add_theme_color_override("font_color", Color.YELLOW)
	stats_vbox.add_child(gold_label)
	
	# 레전더리 아이템
	var legendary_label := Label.new()
	legendary_label.text = "👑 레전더리 획득: %d개" % stats.get("legendaries", 0)
	legendary_label.add_theme_color_override("font_color", Color.ORANGE)
	stats_vbox.add_child(legendary_label)
	
	# 구분선 2
	var sep2 := HSeparator.new()
	sep2.custom_minimum_size.x = 400
	vbox.add_child(sep2)
	
	# 감사 메시지
	var thanks := Label.new()
	thanks.text = "플레이해 주셔서 감사합니다!"
	thanks.add_theme_font_size_override("font_size", 14)
	thanks.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(thanks)
	
	# 버튼 컨테이너
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 20)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)
	
	# 타이틀로 버튼
	var title_btn := Button.new()
	title_btn.text = "🏠 타이틀로"
	title_btn.custom_minimum_size = Vector2(150, 45)
	title_btn.pressed.connect(_on_title_pressed)
	btn_hbox.add_child(title_btn)
	
	# 게임 종료 버튼
	var quit_btn := Button.new()
	quit_btn.text = "🚪 게임 종료"
	quit_btn.custom_minimum_size = Vector2(150, 45)
	quit_btn.pressed.connect(_on_quit_pressed)
	btn_hbox.add_child(quit_btn)
	
	# 지연 후 버튼 포커스
	await get_tree().create_timer(1.0).timeout
	title_btn.grab_focus()


func _add_star_background() -> void:
	## 반짝이는 별 배경 추가
	for i in range(50):
		var star := ColorRect.new()
		star.size = Vector2(2, 2)
		star.position = Vector2(randf() * 640, randf() * 360)
		star.color = Color(1, 1, 1, randf_range(0.3, 0.8))
		add_child(star)
		
		# 반짝임 애니메이션
		var star_tween := create_tween()
		star_tween.set_loops()
		star_tween.tween_property(star, "modulate:a", randf_range(0.2, 0.5), randf_range(0.5, 2.0))
		star_tween.tween_property(star, "modulate:a", 1.0, randf_range(0.5, 2.0))


func _on_title_pressed() -> void:
	# 세이브 삭제 (클리어했으므로)
	SaveManager.delete_save()
	
	title_pressed.emit()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_pressed() -> void:
	quit_pressed.emit()
	get_tree().quit()


func _input(event: InputEvent) -> void:
	# 아무 키나 누르면 타이틀로 (일정 시간 후)
	if event is InputEventKey and event.pressed:
		if tween and tween.is_running():
			return  # 페이드인 중에는 무시
