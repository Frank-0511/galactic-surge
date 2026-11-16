# hud_wave_banner.gd
# Wave-cleared banner ("¡OLEADA SUPERADA!", Etapa 15 T6): builds the hidden label,
# shows it with a fade-out and hides it again. Owned by HUD through _hud.

extends RefCounted

var _hud: CanvasLayer
var _label: Label = null
var _tween: Tween = null


func _init(hud: CanvasLayer) -> void:
	_hud = hud


## Creates the hidden "¡OLEADA SUPERADA!" label centered near the top of the screen.
func build() -> void:
	_label = Label.new()
	_label.name = "WaveClearedLabel"
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = 96.0
	_label.offset_bottom = 150.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 36)
	_label.add_theme_color_override(&"font_color", Color(0.45, 1.0, 0.6, 1.0))
	_label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.05, 0.09, 0.95))
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.visible = false
	_hud.add_child(_label)


## Shows the wave-cleared banner, then fades and hides it after its display time.
func show_banner() -> void:
	if _label == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.text = _hud.WAVE_CLEARED_BANNER_TEXT
	_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_label.visible = true
	_tween = _hud.create_tween()
	_tween.tween_interval(_hud.WAVE_CLEARED_BANNER_DURATION - _hud.WAVE_CLEARED_BANNER_FADE)
	_tween.tween_property(_label, "modulate:a", 0.0, _hud.WAVE_CLEARED_BANNER_FADE)
	_tween.tween_callback(hide_banner)


## Hides the wave-cleared banner immediately.
func hide_banner() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _label != null:
		_label.visible = false
		_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Returns the banner text while it is visible, or an empty string otherwise.
func get_text() -> String:
	if _label == null or not _label.visible:
		return ""
	return _label.text
