# hud_status.gd
# Status readouts of the HUD: J1 score, lives and wave labels, and the coop J2
# lives and score labels (Etapa 20). Owned by HUD through _hud; the labels and the
# J2 state stay on HUD because the tests read them there.

extends RefCounted

const HudIcons: Script = preload("res://features/ui/hud_icons.gd")

var _hud: CanvasLayer


func _init(hud: CanvasLayer) -> void:
	_hud = hud


func set_lives(lives: int) -> void:
	_hud._lives_label.text = str(lives)
	_hud.lives_changed.emit(lives)


func set_score(score: int) -> void:
	_hud._score_label.text = "Score: %d" % score
	_hud.score_changed.emit(score)


func set_wave(wave: int) -> void:
	_hud._wave_label.text = "Oleada %d" % wave
	# The wave number is shown by the between-waves announcement, not in the HUD (Etapa 20).
	_hud._wave_label.visible = false
	_hud.wave_changed.emit(wave)


## Coop local (Etapa 20): J2 lives indicator, hidden until set (singleplayer never sets it).
func set_lives_p2(lives: int) -> void:
	if _hud._lives_p2_label == null:
		_hud._lives_p2_label = Label.new()
		_hud._lives_p2_label.name = "LivesP2Label"
		_hud._lives_p2_label.custom_minimum_size = Vector2(0.0, 28.0)
		_hud._lives_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud._lives_p2_label.add_theme_font_size_override("font_size", 20)
		_hud._lives_p2_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42, 1.0))
		var row_p2: HBoxContainer = HBoxContainer.new()
		row_p2.name = "LivesRowP2"
		row_p2.alignment = BoxContainer.ALIGNMENT_END
		_hud._layout.ensure_p2_bottom_panel().add_child(row_p2)
		row_p2.add_child(HudIcons.HeartIcon.new())
		row_p2.add_child(_hud._lives_p2_label)
	_hud._lives_p2_label.text = str(lives)
	_hud._lives_p2_label.visible = true


func is_lives_p2_visible() -> bool:
	return _hud._lives_p2_label != null and _hud._lives_p2_label.visible


func get_lives_p2_text() -> String:
	return _hud._lives_p2_label.text if _hud._lives_p2_label != null else ""


func get_lives_p2_parent() -> Node:
	return _hud._lives_p2_label.get_parent() if _hud._lives_p2_label != null else null


## Coop local (Etapa 20): J2 score label, in J2's panel with the same style as its lives.
func set_score_p2(points: int) -> void:
	if _hud._score_p2_label == null:
		_hud._score_p2_label = Label.new()
		_hud._score_p2_label.name = "ScoreP2Label"
		_hud._score_p2_label.custom_minimum_size = Vector2(0.0, 28.0)
		_hud._score_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud._score_p2_label.add_theme_font_size_override("font_size", 20)
		_hud._score_p2_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25, 1.0))
		_hud._layout.ensure_p2_panel().add_child(_hud._score_p2_label)
	_hud._score_p2_label.text = "Score: %d" % points
	_hud._score_p2_label.visible = true
