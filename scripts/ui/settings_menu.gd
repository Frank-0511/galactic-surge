# settings_menu.gd
# Settings screen (Etapa 19): audio levels and display options. Every change is
# applied immediately and persisted to user://settings.cfg via systems/settings.gd.
# The display options are text buttons ("Pantalla completa: Sí/No", "VSync: Sí/No")
# that share one style, so their on/off state is shown in the label.
# Emits back_requested so the owner can return to the main menu.

extends CanvasLayer

const SETTINGS := preload("res://scripts/systems/settings.gd")
const TOGGLE_FONT_SIZE := 18
const TOGGLE_FONT_COLOR := Color(0.72, 0.92, 1.0)
const TOGGLE_CORNER_RADIUS := 10
const TOGGLE_BORDER_WIDTH := 2
const CYAN := Color(0.22, 0.9, 1.0)

signal back_requested

var _values: Dictionary = {}

@onready var _master_slider: HSlider = $Control/MasterSlider
@onready var _music_slider: HSlider = $Control/MusicSlider
@onready var _sfx_slider: HSlider = $Control/SfxSlider
@onready var _fullscreen_toggle: Button = $Control/FullscreenToggle
@onready var _vsync_toggle: Button = $Control/VsyncToggle
@onready var _back_button: Button = $Control/BackButton


func _ready() -> void:
	_values = SETTINGS.load_settings()
	_master_slider.value = _values["master_db"]
	_music_slider.value = _values["music_db"]
	_sfx_slider.value = _values["sfx_db"]
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_toggle.pressed.connect(_on_fullscreen_pressed)
	_vsync_toggle.pressed.connect(_on_vsync_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_style_toggle(_fullscreen_toggle)
	_style_toggle(_vsync_toggle)
	_refresh_toggle_texts()


# Shows the screen and gives focus to the first control, so pad and keyboard work at once.
func show_menu() -> void:
	visible = true
	_master_slider.grab_focus()


func _on_master_changed(value: float) -> void:
	_update("master_db", value)


func _on_music_changed(value: float) -> void:
	_update("music_db", value)


func _on_sfx_changed(value: float) -> void:
	_update("sfx_db", value)


func _on_fullscreen_pressed() -> void:
	_update("fullscreen", not _values["fullscreen"])
	_refresh_toggle_texts()


func _on_vsync_pressed() -> void:
	_update("vsync", not _values["vsync"])
	_refresh_toggle_texts()


func _on_back_pressed() -> void:
	back_requested.emit()


# Stores one change, applies it now and persists the whole set.
func _update(key: String, value: Variant) -> void:
	_values[key] = value
	SETTINGS.apply_audio(_values)
	SETTINGS.apply_display(_values)
	SETTINGS.save_settings(_values)


func _refresh_toggle_texts() -> void:
	_fullscreen_toggle.text = "Pantalla completa: %s" % _yes_no(_values["fullscreen"])
	_vsync_toggle.text = "VSync: %s" % _yes_no(_values["vsync"])


func _yes_no(on: bool) -> String:
	return "Sí" if on else "No"


# One shared look for both display buttons: same font, color and StyleBox per state.
func _style_toggle(button: Button) -> void:
	var normal_box: StyleBoxFlat = _make_box(Color(0.04, 0.07, 0.16, 0.92), Color(CYAN, 0.8))
	var hover_box: StyleBoxFlat = _make_box(Color(0.1, 0.2, 0.3, 0.98), Color(CYAN, 1.0))
	var pressed_box: StyleBoxFlat = _make_box(Color(0.02, 0.04, 0.1, 1.0), Color(CYAN, 0.5))
	var focus_box: StyleBoxFlat = _make_box(Color(0.0, 0.0, 0.0, 0.0), Color(1.0, 0.24, 0.72), 3)
	button.add_theme_stylebox_override("normal", normal_box)
	button.add_theme_stylebox_override("hover", hover_box)
	button.add_theme_stylebox_override("pressed", pressed_box)
	button.add_theme_stylebox_override("focus", focus_box)
	button.add_theme_font_size_override("font_size", TOGGLE_FONT_SIZE)
	button.add_theme_color_override("font_color", TOGGLE_FONT_COLOR)


func _make_box(fill: Color, border: Color, border_width: int = TOGGLE_BORDER_WIDTH) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(TOGGLE_CORNER_RADIUS)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.anti_aliasing = true
	return box
