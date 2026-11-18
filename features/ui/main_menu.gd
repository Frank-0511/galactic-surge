# main_menu.gd
# Presents the initial navigation options and emits user intent to Main.
# Lets the player pick the session difficulty (Etapa 18) before play.
# Layout lives in main_menu.tscn: title, divider and high score are anchored to
# the center; the four buttons sit in the Menu VBoxContainer.
# All button styling comes from one Theme built in code (_build_menu_theme) and
# assigned to the root Control; buttons pick PrimaryButton or SecondaryButton variations.
# REDUCED_MOTION is a switch to flip: true skips the title pulse and the entrance fade.

extends CanvasLayer

const DS := preload("res://core/settings/difficulty_settings.gd")
## Session modes (Etapa 20, S6): LOCAL_COOP (J2 on this PC) or NETWORK (J2 is the remote peer).
const NetSyncMode := preload("res://features/net/net_sync_mode.gd")
## Red section (Etapa 20, S2/T1): Host, Join and Coop en red, with IP/port validation.
const LobbyMenu := preload("res://features/net/lobby_menu.gd")

## Switch to true to disable the title pulse and the entrance fade (reduced motion).
const REDUCED_MOTION := false
const ENTRANCE_DURATION := 0.35
const PULSE_HALF_PERIOD := 1.6
const CORNER_RADIUS := 10
const BUTTON_PADDING_X := 14.0
const BUTTON_PADDING_Y := 6.0
const BORDER_WIDTH := 2
const MENU_SEPARATION := 14
const PRIMARY_VARIATION := &"PrimaryButton"
## "MenuButton" is a built-in Godot class name and cannot be a theme variation.
const SECONDARY_VARIATION := &"SecondaryButton"
const PRIMARY_FONT_SIZE := 26
const MENU_FONT_SIZE := 20
const CYAN := Color(0.22, 0.9, 1.0)
## Solid focus/hover fill (#38E6FF) and its dark text (#050A14).
const FOCUS_FILL := Color(0.22, 0.9, 1.0)
const FOCUS_TEXT := Color(0.02, 0.04, 0.08)
const TITLE_FILL := Color(0.72, 0.97, 1.0)
const TEXT_SOFT := Color(0.72, 0.92, 1.0)

signal play_requested
signal quit_requested
signal settings_requested

## Tier chosen in the menu; read by Main when play_requested fires and fixed for the session.
var selected_difficulty: int = DS.Tier.COMMANDER

## True when the player pressed a coop button instead of "Jugar" (Etapa 20).
var coop_selected: bool = false

## Mode of the coop session (Etapa 20 T1); read by Main with coop_selected. Only the network button sets NETWORK.
var session_mode: int = NetSyncMode.DEFAULT_MODE

## Red section logic (Host, Join, Coop en red); created in _ready once the Red nodes exist.
var _lobby_menu: RefCounted

@onready var _content: Control = $Control
@onready var _vignette: TextureRect = $Control/Vignette
@onready var _high_score_label: Label = $Control/HighScoreLabel
@onready var _title_label: Label = $Control/TitleLabel
@onready var _difficulty_button: Button = $Control/Menu/DificultadButton
@onready var _play_button: Button = $Control/Menu/PlayButton
@onready var _quit_button: Button = $Control/Menu/QuitButton
@onready var _ajustes_button: Button = $Control/Menu/AjustesButton

var _entrance_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	_lobby_menu = LobbyMenu.new(self)
	_content.theme = _build_menu_theme()
	_apply_vignette()
	_apply_title_style()
	apply_network_availability(OS.has_feature("web"))
	apply_platform_availability(OS.has_feature("web"), DisplayServer.is_touchscreen_available())
	_apply_chip_style()
	_start_title_pulse()
	_refresh_difficulty_text()


func show_menu() -> void:
	visible = true
	_play_entrance()
	_play_button.grab_focus()


func set_high_score(value: int) -> void:
	_high_score_label.text = "Mejor puntaje: %d" % value


func _on_play_button_pressed() -> void:
	coop_selected = false
	play_requested.emit()


func _on_coop_button_pressed() -> void:
	coop_selected = true
	session_mode = NetSyncMode.LOCAL_COOP
	play_requested.emit()


# Coop en red (Etapa 20 T1): needs a Host or Join peer first; otherwise the Red section shows a notice.
func _on_net_coop_button_pressed() -> void:
	if _lobby_menu.can_start_network():
		coop_selected = true
		session_mode = NetSyncMode.NETWORK
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
# Red (Etapa 20, S2/S4): Host, Join and Coop en red are handled by lobby_menu.gd; these are the signal entry points.
# ---------------------------------------------------------------------------
func _on_host_button_pressed() -> void:
	_lobby_menu.host_pressed()


func _on_join_button_pressed() -> void:
	_lobby_menu.join_pressed()


## Public: shows a network notice (for example, a lost host) in the Red section.
func show_network_message(text: String) -> void:
	_lobby_menu.show_message(text)


## Etapa 21 (S7): web builds have no ENet networking and no way to close the browser tab, so in web the Red
## panel and the Salir button are hidden; outside web they are visible again.
func apply_network_availability(is_web: bool) -> void:
	$Control/NetPanel.visible = not is_web
	$Control/Menu/QuitButton.visible = not is_web


## Public: the local coop button needs a shared keyboard, so it is hidden only in a browser on a touch device.
func apply_platform_availability(is_web: bool, is_touch: bool) -> void:
	$Control/Menu/CoopButton.visible = not (is_web and is_touch)


## Public: closes the lobby and clears the scene multiplayer peer. Safe when nothing is open.
func close_network() -> void:
	_lobby_menu.close()


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
# Theme: one Theme for the whole menu, assigned to the root Control.
# PrimaryButton (Jugar) and SecondaryButton (Dificultad, Ajustes, Salir) carry the
# button looks. Hover and focus share a solid cyan fill with dark text, so the
# focused button is the highest-contrast element on screen. Pressed keeps the
# dark fill. The Menu VBoxContainer separation is a theme constant too.
# ---------------------------------------------------------------------------
func _build_menu_theme() -> Theme:
	var menu_theme := Theme.new()
	menu_theme.set_type_variation(PRIMARY_VARIATION, &"Button")
	menu_theme.set_type_variation(SECONDARY_VARIATION, &"Button")
	menu_theme.set_constant(&"separation", &"VBoxContainer", MENU_SEPARATION)
	_theme_button_variation(menu_theme, PRIMARY_VARIATION, PRIMARY_FONT_SIZE, true)
	_theme_button_variation(menu_theme, SECONDARY_VARIATION, MENU_FONT_SIZE, false)
	return menu_theme


func _theme_button_variation(menu_theme: Theme, variation: StringName, font_size: int, primary: bool) -> void:
	var normal_box: StyleBoxFlat
	var pressed_box: StyleBoxFlat
	var text_normal: Color
	var text_pressed: Color
	if primary:
		normal_box = _make_box(Color(0.2, 0.04, 0.19, 0.95), Color(CYAN, 0.8), BORDER_WIDTH)
		pressed_box = _make_box(Color(0.1, 0.02, 0.1, 1.0), Color(CYAN, 0.6), BORDER_WIDTH)
		text_normal = Color(1.0, 0.93, 0.98)
		text_pressed = Color(0.85, 0.75, 0.82)
	else:
		normal_box = _make_box(Color(0.04, 0.07, 0.16, 0.92), Color(CYAN, 0.8), BORDER_WIDTH)
		pressed_box = _make_box(Color(0.02, 0.04, 0.1, 1.0), Color(CYAN, 0.5), BORDER_WIDTH)
		text_normal = TEXT_SOFT
		text_pressed = Color(0.6, 0.8, 0.9)

	menu_theme.set_stylebox(&"normal", variation, normal_box)
	menu_theme.set_stylebox(&"hover", variation, _make_box(FOCUS_FILL, FOCUS_FILL, BORDER_WIDTH))
	menu_theme.set_stylebox(&"pressed", variation, pressed_box)
	menu_theme.set_stylebox(&"focus", variation, _make_box(FOCUS_FILL, FOCUS_FILL, BORDER_WIDTH))
	menu_theme.set_font_size(&"font_size", variation, font_size)
	menu_theme.set_color(&"font_color", variation, text_normal)
	menu_theme.set_color(&"font_pressed_color", variation, text_pressed)
	menu_theme.set_color(&"font_hover_color", variation, FOCUS_TEXT)
	menu_theme.set_color(&"font_focus_color", variation, FOCUS_TEXT)


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
