# settings_menu.gd
# Settings screen (Etapa 19): audio levels and display options. Every change is
# applied immediately and persisted to user://settings.cfg via systems/settings.gd.
# Layout lives in settings_menu.tscn: a centered VBoxContainer (Center/Content) holds
# the title, three slider blocks (label above slider), the two display toggles, Controles and Volver.
# Controles hides that content and shows the Rebind Kit RemapPanel in a dark host (Center/RemapHost),
# built here; closing it brings Ajustes back with focus on Controles. The InputRemap is created in _ready,
# so saved bindings reach the InputMap at game start, not only when Ajustes opens.
# All styling comes from one Theme built in code (_build_settings_theme) and assigned
# to the root Control; buttons use the ToggleButton and PrimaryButton variations and the
# title uses TitleLabel. Focus and hover share the solid cyan fill, as in the main menu.
# Emits back_requested so the owner can return to the main menu.

extends CanvasLayer

const SETTINGS := preload("res://scripts/systems/settings.gd")
const TOGGLE_VARIATION := &"ToggleButton"
const PRIMARY_VARIATION := &"PrimaryButton"
const TITLE_VARIATION := &"TitleLabel"
const FIELD_VARIATION := &"FieldBlock"
const TOGGLE_COLUMN_VARIATION := &"ToggleColumn"
## Spacing: 18 px between blocks, 6 px label-to-slider, 24 px between the two toggles.
const COLUMN_SEPARATION := 18
const FIELD_SEPARATION := 6
const TOGGLE_SEPARATION := 24
const TOGGLE_FONT_SIZE := 18
const PRIMARY_FONT_SIZE := 20
const TITLE_FONT_SIZE := 32
const CORNER_RADIUS := 10
const BORDER_WIDTH := 2
const BUTTON_PADDING_X := 14.0
const BUTTON_PADDING_Y := 6.0
const GRABBER_SIZE := 20
const CYAN := Color(0.22, 0.9, 1.0)
## Solid focus/hover fill (#38E6FF) and its dark text (#050A14).
const FOCUS_FILL := Color(0.22, 0.9, 1.0)
const FOCUS_TEXT := Color(0.02, 0.04, 0.08)
const TITLE_FILL := Color(0.72, 0.97, 1.0)
const TEXT_SOFT := Color(0.72, 0.92, 1.0)
const REMAP_SAVE_PATH := "user://rebind_kit.json"
const REMAP_PANEL_FILL := Color(0.02, 0.03, 0.08, 0.96)
## Colors of the Rebind Kit panel, from this menu's palette: light text, cyan accent, dark background.
const REMAP_COLORS := {
	"text": Color(0.72, 0.97, 1.0), "dim": Color(0.72, 0.92, 1.0, 0.65), "off": Color(0.72, 0.92, 1.0, 0.35),
	"accent": Color(0.22, 0.9, 1.0), "warn": Color(1.0, 0.8, 0.35), "stripe": Color(0.22, 0.9, 1.0, 0.05),
	"line": Color(0.22, 0.9, 1.0, 0.25),
}
## Rebindable actions from project.godot [input]. Godot's ui_* actions are left out on purpose: menus keep them.
## Gameplay actions share the scope "juego" (one key can't do two of them); "pausa" is global (clashes with all).
const CATALOG := {"groups": [
	{"id": "movimiento", "title": "Movimiento", "scope": "juego", "actions": [
		{"id": "move_left", "title": "Mover a la izquierda"}, {"id": "move_right", "title": "Mover a la derecha"}]},
	{"id": "combate", "title": "Combate", "scope": "juego", "actions": [{"id": "shoot", "title": "Disparar"}]},
	{"id": "armas", "title": "Armas", "scope": "juego", "actions": [
		{"id": "weapon_1", "title": "Arma 1"}, {"id": "weapon_2", "title": "Arma 2"},
		{"id": "weapon_3", "title": "Arma 3"}, {"id": "weapon_4", "title": "Arma 4"},
		{"id": "weapon_prev", "title": "Arma anterior"}, {"id": "weapon_next", "title": "Arma siguiente"}]},
	{"id": "pausa", "title": "Pausa", "scope": "global", "actions": [{"id": "pause", "title": "Pausar"}]},
]}

signal back_requested

var _values: Dictionary = {}
## The rebinding of the game's commands, alive for the whole game (applies the saved choices at start).
var remap: InputRemap
var _remap_panel: RemapPanel
var _remap_host: PanelContainer

@onready var _root: Control = $Control
@onready var _content: VBoxContainer = $Control/Center/Content
@onready var _master_slider: HSlider = $Control/Center/Content/MasterBlock/MasterSlider
@onready var _music_slider: HSlider = $Control/Center/Content/MusicBlock/MusicSlider
@onready var _sfx_slider: HSlider = $Control/Center/Content/SfxBlock/SfxSlider
@onready var _fullscreen_toggle: Button = $Control/Center/Content/DisplayOptions/FullscreenToggle
@onready var _vsync_toggle: Button = $Control/Center/Content/DisplayOptions/VsyncToggle
@onready var _controls_button: Button = $Control/Center/Content/ControlsButton
@onready var _back_button: Button = $Control/Center/Content/BackButton


func _ready() -> void:
	_root.theme = _build_settings_theme()
	remap = InputRemap.new(RebindAdapter.new(CATALOG, REMAP_SAVE_PATH))
	remap.name = "InputRemap"
	add_child(remap)
	_remap_host = PanelContainer.new()
	var host_style := _make_box(REMAP_PANEL_FILL, Color(CYAN, 0.6), BORDER_WIDTH)
	host_style.content_margin_left = 16.0
	host_style.content_margin_right = 16.0
	host_style.content_margin_top = 16.0
	host_style.content_margin_bottom = 16.0
	_remap_host.add_theme_stylebox_override("panel", host_style)
	_remap_host.visible = false
	_content.get_parent().add_child(_remap_host)
	_controls_button.pressed.connect(_on_controls_pressed)
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


# Controles: the Ajustes content gives way to the rebinding panel, which takes focus on its first command.
func _on_controls_pressed() -> void:
	_content.visible = false
	_remap_host.visible = true
	_remap_panel = RemapPanel.new(remap, REMAP_COLORS)
	_remap_panel.closed.connect(_on_remap_closed)
	_remap_host.add_child(_remap_panel)
	_remap_panel.focus_first()


# The panel saved and closed: back to Ajustes, focus on the Controles button.
func _on_remap_closed() -> void:
	_remap_panel.queue_free()
	_remap_panel = null
	_remap_host.visible = false
	_content.visible = true
	_controls_button.grab_focus()


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


# ---------------------------------------------------------------------------
# Theme: one Theme for the whole screen, assigned to the root Control.
# Buttons: ToggleButton (display options) and PrimaryButton (Volver). Hover and focus
# share a solid cyan fill with dark text, so the selection is the highest-contrast item.
# Sliders: cyan grabber and cyan focus ring. Title: TitleLabel. Spacing is theme constants.
# ---------------------------------------------------------------------------
func _build_settings_theme() -> Theme:
	var settings_theme := Theme.new()
	settings_theme.set_constant(&"separation", &"VBoxContainer", COLUMN_SEPARATION)
	settings_theme.set_type_variation(FIELD_VARIATION, &"VBoxContainer")
	settings_theme.set_constant(&"separation", FIELD_VARIATION, FIELD_SEPARATION)
	settings_theme.set_type_variation(TOGGLE_COLUMN_VARIATION, &"VBoxContainer")
	settings_theme.set_constant(&"separation", TOGGLE_COLUMN_VARIATION, TOGGLE_SEPARATION)
	settings_theme.set_color(&"font_color", &"Label", TEXT_SOFT)
	settings_theme.set_type_variation(TITLE_VARIATION, &"Label")
	settings_theme.set_font_size(&"font_size", TITLE_VARIATION, TITLE_FONT_SIZE)
	settings_theme.set_color(&"font_color", TITLE_VARIATION, TITLE_FILL)
	_theme_button_variation(settings_theme, TOGGLE_VARIATION, TOGGLE_FONT_SIZE)
	_theme_button_variation(settings_theme, PRIMARY_VARIATION, PRIMARY_FONT_SIZE)
	# Rebind Kit's panel: its listening and save buttons, and its small captions.
	_theme_button_variation(settings_theme, &"ActionButton", TOGGLE_FONT_SIZE)
	settings_theme.set_type_variation(&"CaptionLabel", &"Label")
	settings_theme.set_font_size(&"font_size", &"CaptionLabel", 14)
	_theme_slider(settings_theme)
	return settings_theme


func _theme_button_variation(settings_theme: Theme, variation: StringName, font_size: int) -> void:
	settings_theme.set_type_variation(variation, &"Button")
	settings_theme.set_stylebox(&"normal", variation, _make_box(Color(0.04, 0.07, 0.16, 0.92), Color(CYAN, 0.8), BORDER_WIDTH))
	settings_theme.set_stylebox(&"hover", variation, _make_box(FOCUS_FILL, FOCUS_FILL, BORDER_WIDTH))
	settings_theme.set_stylebox(&"pressed", variation, _make_box(Color(0.02, 0.04, 0.1, 1.0), Color(CYAN, 0.5), BORDER_WIDTH))
	settings_theme.set_stylebox(&"focus", variation, _make_box(FOCUS_FILL, FOCUS_FILL, BORDER_WIDTH))
	settings_theme.set_font_size(&"font_size", variation, font_size)
	settings_theme.set_color(&"font_color", variation, TEXT_SOFT)
	settings_theme.set_color(&"font_pressed_color", variation, Color(0.6, 0.8, 0.9))
	settings_theme.set_color(&"font_hover_color", variation, FOCUS_TEXT)
	settings_theme.set_color(&"font_hover_pressed_color", variation, FOCUS_TEXT)
	settings_theme.set_color(&"font_focus_color", variation, FOCUS_TEXT)


func _theme_slider(settings_theme: Theme) -> void:
	var track: StyleBoxFlat = _make_box(Color(0.04, 0.07, 0.16, 0.92), Color(CYAN, 0.6), 1)
	track.content_margin_left = 0.0
	track.content_margin_right = 0.0
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	settings_theme.set_stylebox(&"slider", &"HSlider", track)
	var filled: StyleBoxFlat = _make_box(Color(CYAN, 0.45), Color(CYAN, 0.45), 0)
	settings_theme.set_stylebox(&"grabber_area", &"HSlider", filled)
	settings_theme.set_stylebox(&"grabber_area_highlight", &"HSlider", _make_box(FOCUS_FILL, FOCUS_FILL, 0))
	# Focus ring on the whole slider: solid cyan border, no fill.
	var ring: StyleBoxFlat = _make_box(Color(0.0, 0.0, 0.0, 0.0), FOCUS_FILL, BORDER_WIDTH)
	ring.content_margin_left = 0.0
	ring.content_margin_right = 0.0
	ring.content_margin_top = 0.0
	ring.content_margin_bottom = 0.0
	settings_theme.set_stylebox(&"focus", &"HSlider", ring)
	settings_theme.set_icon(&"grabber", &"HSlider", _circle_icon(Color(CYAN, 0.6)))
	settings_theme.set_icon(&"grabber_highlight", &"HSlider", _circle_icon(FOCUS_FILL))


func _circle_icon(color: Color) -> ImageTexture:
	var image := Image.create(GRABBER_SIZE, GRABBER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(GRABBER_SIZE, GRABBER_SIZE) * 0.5
	for x: int in range(GRABBER_SIZE):
		for y: int in range(GRABBER_SIZE):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= GRABBER_SIZE * 0.5:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


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
# RebindAdapter: the Rebind Kit's FileRemapAdapter with the panel's texts in Spanish. The addon's TEXTS are constants
# in English; text() is the documented place to translate them. Unknown ids (catalog titles) pass through.
# ---------------------------------------------------------------------------
class RebindAdapter extends FileRemapAdapter:
	const TEXTS_ES := {
		"tab_keyboard": "TECLADO Y RATÓN", "tab_pad": "MANDO", "scheme": "ESQUEMA", "command": "ACCIÓN",
		"primary": "PRINCIPAL", "alternative": "ALTERNATIVA", "listening": "PULSA UNA TECLA...", "empty": "—",
		"custom": "Personalizado", "custom_of": "Personalizado (%s)", "swapped": "intercambiada: confirma",
		"pending": "%d por confirmar antes de guardar", "defaults": "PREDETERMINADO",
		"defaults_confirm": "¿Volver a las teclas predeterminadas de esta pestaña?", "save": "GUARDAR Y CERRAR",
		"form_title": "Acciones intercambiadas por confirmar",
		"form_body": "Una tecla nueva movió otra acción. Conserva la tecla que tiene ahora o elige otra.",
		"keep": "CONSERVAR", "reassign": "REASIGNAR", "back": "VOLVER A LA TABLA", "discard": "DESCARTAR CAMBIOS",
		"hint_keyboard": "Haz clic o ENTER en una acción y pulsa la tecla nueva",
		"hint_pad": "A sobre una acción y luego pulsa el botón nuevo",
		"hint_chord_keyboard": "Haz clic o ENTER en una acción y mantén hasta 4 teclas en orden",
		"hint_chord_pad": "A sobre una acción y mantén hasta 4 botones en orden",
		"pad_connected": "mando: %s", "no_pad": "ningún mando conectado",
		"pad_layout": "DISPOSICIÓN", "layout_auto": "Automática", "player": "JUGADOR %d",
		"listening_chord": "MANTÉN LAS TECLAS...", "moved_to_player": "Movida al jugador %d: %s",
	}

	func text(id: String) -> String:
		return str(TEXTS_ES.get(id, id))
