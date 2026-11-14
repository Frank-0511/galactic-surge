# main_menu.gd
# Presents the initial navigation options and emits user intent to Main.
# Lets the player pick the session difficulty (Etapa 18) before play.
# Layout lives in main_menu.tscn; all visual styling (buttons, title, chip,
# vignette, entrance fade, title pulse) is applied here in code.
# REDUCED_MOTION is a switch to flip: true skips the title pulse and the entrance fade.

extends CanvasLayer

const DS := preload("res://scripts/systems/difficulty_settings.gd")

## Switch to true to disable the title pulse and the entrance fade (reduced motion).
const REDUCED_MOTION := false
const ENTRANCE_DURATION := 0.35
const PULSE_HALF_PERIOD := 1.6
const CORNER_RADIUS := 10
const BUTTON_PADDING_X := 14.0
const BUTTON_PADDING_Y := 6.0
const BORDER_WIDTH := 2
const FOCUS_BORDER_WIDTH := 3
const CYAN := Color(0.22, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.24, 0.72)
const TITLE_FILL := Color(0.72, 0.97, 1.0)
const TEXT_SOFT := Color(0.72, 0.92, 1.0)

signal play_requested
signal quit_requested
signal settings_requested

## Tier chosen in the menu; read by Main when play_requested fires and fixed for the session.
var selected_difficulty: int = DS.Tier.COMMANDER

@onready var _content: Control = $Control
@onready var _vignette: TextureRect = $Control/Vignette
@onready var _high_score_label: Label = $Control/HighScoreLabel
@onready var _title_label: Label = $Control/TitleLabel
@onready var _difficulty_button: Button = $Control/DificultadButton
@onready var _play_button: Button = $Control/PlayButton
@onready var _quit_button: Button = $Control/QuitButton
@onready var _ajustes_button: Button = $Control/AjustesButton

var _entrance_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	_apply_vignette()
	_apply_title_style()
	_apply_chip_style()
	_style_buttons()
	_start_title_pulse()
	_refresh_difficulty_text()


func show_menu() -> void:
	visible = true
	_play_entrance()
	$Control/PlayButton.grab_focus()


func set_high_score(value: int) -> void:
	_high_score_label.text = "Mejor puntaje: %d" % value


func _on_play_button_pressed() -> void:
	play_requested.emit()


# Cycles CADET -> COMMANDER -> ELITE -> CADET.
func _on_dificultad_button_pressed() -> void:
	selected_difficulty = (selected_difficulty + 1) % DS.Tier.size()
	_refresh_difficulty_text()


func _refresh_difficulty_text() -> void:
	_difficulty_button.text = DS.get_tier_name(selected_difficulty).to_upper()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()


func _on_ajustes_button_pressed() -> void:
	settings_requested.emit()


# ---------------------------------------------------------------------------
# Background: radial vignette generated in code (no external textures).
# ---------------------------------------------------------------------------
func _apply_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0.0, 0.0, 0.02, 0.0), Color(0.0, 0.0, 0.02, 0.7)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_vignette.texture = texture


# ---------------------------------------------------------------------------
# Title: larger, cyan outline and dark drop shadow.
# ---------------------------------------------------------------------------
func _apply_title_style() -> void:
	_title_label.add_theme_font_size_override("font_size", 46)
	_title_label.add_theme_color_override("font_color", TITLE_FILL)
	_title_label.add_theme_color_override("font_outline_color", Color(CYAN, 0.9))
	_title_label.add_theme_constant_override("outline_size", 6)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.01, 0.04, 0.85))
	_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_title_label.add_theme_constant_override("shadow_offset_y", 5)


# High score as a small rounded chip with a faint cyan border.
func _apply_chip_style() -> void:
	var chip: StyleBoxFlat = _make_box(Color(0.03, 0.06, 0.14, 0.75), Color(CYAN, 0.35), 1)
	chip.corner_radius_top_left = 8
	chip.corner_radius_top_right = 8
	chip.corner_radius_bottom_left = 8
	chip.corner_radius_bottom_right = 8
	chip.content_margin_left = 14.0
	chip.content_margin_right = 14.0
	chip.content_margin_top = 4.0
	chip.content_margin_bottom = 4.0
	_high_score_label.add_theme_stylebox_override("normal", chip)
	_high_score_label.add_theme_font_size_override("font_size", 15)


# ---------------------------------------------------------------------------
# Buttons: one StyleBoxFlat per state. Jugar is the primary action (magenta
# tinted fill); Salir and the difficulty control stay cyan-outlined.
# Focus is a 3 px magenta border with a transparent fill, so it stays distinct
# from hover (brighter fill, 2 px cyan border).
# ---------------------------------------------------------------------------
func _style_buttons() -> void:
	_style_button(_play_button, 26, true)
	_style_button(_quit_button, 20, false)
	_style_button(_ajustes_button, 20, false)
	_style_button(_difficulty_button, 16, false)


func _style_button(button: Button, font_size: int, primary: bool) -> void:
	var normal_box: StyleBoxFlat
	var hover_box: StyleBoxFlat
	var pressed_box: StyleBoxFlat
	if primary:
		normal_box = _make_box(Color(0.2, 0.04, 0.19, 0.95), Color(CYAN, 0.8), BORDER_WIDTH)
		hover_box = _make_box(Color(0.34, 0.08, 0.3, 1.0), Color(CYAN, 1.0), BORDER_WIDTH)
		pressed_box = _make_box(Color(0.1, 0.02, 0.1, 1.0), Color(CYAN, 0.6), BORDER_WIDTH)
	else:
		normal_box = _make_box(Color(0.04, 0.07, 0.16, 0.92), Color(CYAN, 0.8), BORDER_WIDTH)
		hover_box = _make_box(Color(0.1, 0.2, 0.3, 0.98), Color(CYAN, 1.0), BORDER_WIDTH)
		pressed_box = _make_box(Color(0.02, 0.04, 0.1, 1.0), Color(CYAN, 0.5), BORDER_WIDTH)
	var focus_box: StyleBoxFlat = _make_box(Color(0.0, 0.0, 0.0, 0.0), MAGENTA, FOCUS_BORDER_WIDTH)

	button.add_theme_stylebox_override("normal", normal_box)
	button.add_theme_stylebox_override("hover", hover_box)
	button.add_theme_stylebox_override("pressed", pressed_box)
	button.add_theme_stylebox_override("focus", focus_box)
	button.add_theme_font_size_override("font_size", font_size)

	var text_normal: Color = Color(1.0, 0.93, 0.98) if primary else TEXT_SOFT
	var text_pressed: Color = Color(0.85, 0.75, 0.82) if primary else Color(0.6, 0.8, 0.9)
	button.add_theme_color_override("font_color", text_normal)
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", text_pressed)
	button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))


func _make_box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(CORNER_RADIUS)
	box.content_margin_left = BUTTON_PADDING_X
	box.content_margin_right = BUTTON_PADDING_X
	box.content_margin_top = BUTTON_PADDING_Y
	box.content_margin_bottom = BUTTON_PADDING_Y
	box.anti_aliasing = true
	return box


# ---------------------------------------------------------------------------
# Motion (cosmetic only; never delays input, never changes layout).
# ---------------------------------------------------------------------------
# Fades the menu content in over ENTRANCE_DURATION each time show_menu() runs.
func _play_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	if REDUCED_MOTION:
		_content.modulate.a = 1.0
		return
	_content.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.tween_property(_content, "modulate:a", 1.0, ENTRANCE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Slow, low-amplitude breathing on the title's alpha. Does not affect layout or state.
func _start_title_pulse() -> void:
	if REDUCED_MOTION:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_title_label, "modulate:a", 0.9, PULSE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_title_label, "modulate:a", 1.0, PULSE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
