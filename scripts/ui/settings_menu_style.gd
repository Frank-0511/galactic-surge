# settings_menu_style.gd
# Theme of the Ajustes screen (Etapa 19): one Theme built in code for the whole screen,
# assigned to the root Control, plus the Theme of the Rebind Kit panel and the StyleBoxFlat
# helper. Buttons use the ToggleButton and PrimaryButton variations; hover and focus share
# a solid cyan fill with dark text. Owned by SettingsMenu through _menu; the palette and
# sizes stay as constants on SettingsMenu.

extends RefCounted

var _menu: CanvasLayer


func _init(menu: CanvasLayer) -> void:
	_menu = menu


# Theme: one Theme for the whole screen, assigned to the root Control.
# Buttons: ToggleButton (display options) and PrimaryButton (Volver). Hover and focus
# share a solid cyan fill with dark text, so the selection is the highest-contrast item.
# Sliders: cyan grabber and cyan focus ring. Title: TitleLabel. Spacing is theme constants.
func build_theme() -> Theme:
	var settings_theme := Theme.new()
	settings_theme.set_constant(&"separation", &"VBoxContainer", _menu.COLUMN_SEPARATION)
	settings_theme.set_type_variation(_menu.FIELD_VARIATION, &"VBoxContainer")
	settings_theme.set_constant(&"separation", _menu.FIELD_VARIATION, _menu.FIELD_SEPARATION)
	settings_theme.set_type_variation(_menu.TOGGLE_COLUMN_VARIATION, &"VBoxContainer")
	settings_theme.set_constant(&"separation", _menu.TOGGLE_COLUMN_VARIATION, _menu.TOGGLE_SEPARATION)
	settings_theme.set_color(&"font_color", &"Label", _menu.TEXT_SOFT)
	settings_theme.set_type_variation(_menu.TITLE_VARIATION, &"Label")
	settings_theme.set_font_size(&"font_size", _menu.TITLE_VARIATION, _menu.TITLE_FONT_SIZE)
	settings_theme.set_color(&"font_color", _menu.TITLE_VARIATION, _menu.TITLE_FILL)
	_theme_button_variation(settings_theme, _menu.TOGGLE_VARIATION, _menu.TOGGLE_FONT_SIZE)
	_theme_button_variation(settings_theme, _menu.PRIMARY_VARIATION, _menu.PRIMARY_FONT_SIZE)
	# Rebind Kit's panel: its listening and save buttons, and its small captions.
	_theme_button_variation(settings_theme, &"ActionButton", _menu.TOGGLE_FONT_SIZE)
	settings_theme.set_type_variation(&"CaptionLabel", &"Label")
	settings_theme.set_font_size(&"font_size", &"CaptionLabel", 16)
	# Plain Buttons and the scheme OptionButton of the panel share the same cyan look.
	_theme_plain_control(settings_theme, &"Button")
	_theme_plain_control(settings_theme, &"OptionButton")
	_theme_slider(settings_theme)
	return settings_theme


# Theme only for the Rebind Kit panel (its host): the focused key cell is a dark fill with a
# thick cyan border, so the key text stays readable. The rest of the menu keeps the solid cyan focus.
func build_remap_theme() -> Theme:
	var remap_theme: Theme = _menu._root.theme.duplicate()
	var focus_box: StyleBoxFlat = make_box(_menu.REMAP_FOCUS_FILL, _menu.FOCUS_FILL, _menu.REMAP_FOCUS_BORDER)
	remap_theme.set_stylebox(&"hover", &"Button", focus_box)
	remap_theme.set_stylebox(&"focus", &"Button", focus_box)
	remap_theme.set_color(&"font_hover_color", &"Button", _menu.TEXT_SOFT)
	remap_theme.set_color(&"font_focus_color", &"Button", _menu.TEXT_SOFT)
	return remap_theme


func make_box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(_menu.CORNER_RADIUS)
	box.content_margin_left = _menu.BUTTON_PADDING_X
	box.content_margin_right = _menu.BUTTON_PADDING_X
	box.content_margin_top = _menu.BUTTON_PADDING_Y
	box.content_margin_bottom = _menu.BUTTON_PADDING_Y
	box.anti_aliasing = true
	return box


func _theme_plain_control(settings_theme: Theme, type: StringName) -> void:
	settings_theme.set_stylebox(&"normal", type, make_box(Color(0.04, 0.07, 0.16, 0.92), Color(_menu.CYAN, 0.8), _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"hover", type, make_box(_menu.FOCUS_FILL, _menu.FOCUS_FILL, _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"pressed", type, make_box(Color(0.02, 0.04, 0.1, 1.0), Color(_menu.CYAN, 0.5), _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"focus", type, make_box(_menu.FOCUS_FILL, _menu.FOCUS_FILL, _menu.BORDER_WIDTH))
	settings_theme.set_font_size(&"font_size", type, 16)
	settings_theme.set_color(&"font_color", type, _menu.TEXT_SOFT)
	settings_theme.set_color(&"font_hover_color", type, _menu.FOCUS_TEXT)
	settings_theme.set_color(&"font_focus_color", type, _menu.FOCUS_TEXT)


func _theme_button_variation(settings_theme: Theme, variation: StringName, font_size: int) -> void:
	settings_theme.set_type_variation(variation, &"Button")
	settings_theme.set_stylebox(&"normal", variation, make_box(Color(0.04, 0.07, 0.16, 0.92), Color(_menu.CYAN, 0.8), _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"hover", variation, make_box(_menu.FOCUS_FILL, _menu.FOCUS_FILL, _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"pressed", variation, make_box(Color(0.02, 0.04, 0.1, 1.0), Color(_menu.CYAN, 0.5), _menu.BORDER_WIDTH))
	settings_theme.set_stylebox(&"focus", variation, make_box(_menu.FOCUS_FILL, _menu.FOCUS_FILL, _menu.BORDER_WIDTH))
	settings_theme.set_font_size(&"font_size", variation, font_size)
	settings_theme.set_color(&"font_color", variation, _menu.TEXT_SOFT)
	settings_theme.set_color(&"font_pressed_color", variation, Color(0.6, 0.8, 0.9))
	settings_theme.set_color(&"font_hover_color", variation, _menu.FOCUS_TEXT)
	settings_theme.set_color(&"font_hover_pressed_color", variation, _menu.FOCUS_TEXT)
	settings_theme.set_color(&"font_focus_color", variation, _menu.FOCUS_TEXT)


func _theme_slider(settings_theme: Theme) -> void:
	var track: StyleBoxFlat = make_box(Color(0.04, 0.07, 0.16, 0.92), Color(_menu.CYAN, 0.6), 1)
	track.content_margin_left = 0.0
	track.content_margin_right = 0.0
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	settings_theme.set_stylebox(&"slider", &"HSlider", track)
	var filled: StyleBoxFlat = make_box(Color(_menu.CYAN, 0.45), Color(_menu.CYAN, 0.45), 0)
	settings_theme.set_stylebox(&"grabber_area", &"HSlider", filled)
	settings_theme.set_stylebox(&"grabber_area_highlight", &"HSlider", make_box(_menu.FOCUS_FILL, _menu.FOCUS_FILL, 0))
	# Focus ring on the whole slider: solid cyan border, no fill.
	var ring: StyleBoxFlat = make_box(Color(0.0, 0.0, 0.0, 0.0), _menu.FOCUS_FILL, _menu.BORDER_WIDTH)
	ring.content_margin_left = 0.0
	ring.content_margin_right = 0.0
	ring.content_margin_top = 0.0
	ring.content_margin_bottom = 0.0
	settings_theme.set_stylebox(&"focus", &"HSlider", ring)
	settings_theme.set_icon(&"grabber", &"HSlider", _circle_icon(Color(_menu.CYAN, 0.6)))
	settings_theme.set_icon(&"grabber_highlight", &"HSlider", _circle_icon(_menu.FOCUS_FILL))


func _circle_icon(color: Color) -> ImageTexture:
	var size: int = _menu.GRABBER_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center := Vector2(size, size) * 0.5
	for x: int in range(size):
		for y: int in range(size):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= size * 0.5:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
