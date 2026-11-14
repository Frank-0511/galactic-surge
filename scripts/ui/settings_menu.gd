# settings_menu.gd
# Settings screen (Etapa 19): audio levels and display toggles. Every change is
# applied immediately and persisted to user://settings.cfg via systems/settings.gd.
# Emits back_requested so the owner can return to the main menu.

extends CanvasLayer

const SETTINGS := preload("res://scripts/systems/settings.gd")

signal back_requested

const TOGGLE_FONT_SIZE := 18
const TOGGLE_FONT_COLOR := Color(0.72, 0.92, 1.0)

var _values: Dictionary = {}

@onready var _master_slider: HSlider = $Control/MasterSlider
@onready var _music_slider: HSlider = $Control/MusicSlider
@onready var _sfx_slider: HSlider = $Control/SfxSlider
@onready var _fullscreen_toggle: CheckButton = $Control/FullscreenToggle
@onready var _vsync_toggle: CheckButton = $Control/VsyncToggle
@onready var _back_button: Button = $Control/BackButton


func _ready() -> void:
	_values = SETTINGS.load_settings()
	_master_slider.value = _values["master_db"]
	_music_slider.value = _values["music_db"]
	_sfx_slider.value = _values["sfx_db"]
	_fullscreen_toggle.button_pressed = _values["fullscreen"]
	_vsync_toggle.button_pressed = _values["vsync"]
	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_vsync_toggle.toggled.connect(_on_vsync_toggled)
	_back_button.pressed.connect(_on_back_pressed)
	_style_toggle(_fullscreen_toggle)
	_style_toggle(_vsync_toggle)


# Both display toggles use the same theme overrides, so they always render alike.
func _style_toggle(toggle: CheckButton) -> void:
	toggle.add_theme_font_size_override("font_size", TOGGLE_FONT_SIZE)
	toggle.add_theme_color_override("font_color", TOGGLE_FONT_COLOR)


func _on_master_changed(value: float) -> void:
	_update("master_db", value)


func _on_music_changed(value: float) -> void:
	_update("music_db", value)


func _on_sfx_changed(value: float) -> void:
	_update("sfx_db", value)


func _on_fullscreen_toggled(on: bool) -> void:
	_update("fullscreen", on)


func _on_vsync_toggled(on: bool) -> void:
	_update("vsync", on)


func _on_back_pressed() -> void:
	back_requested.emit()


# Stores one change, applies it now and persists the whole set.
func _update(key: String, value: Variant) -> void:
	_values[key] = value
	SETTINGS.apply_audio(_values)
	SETTINGS.apply_display(_values)
	SETTINGS.save_settings(_values)
