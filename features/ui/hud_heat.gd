# hud_heat.gd
# Heat readouts of the HUD: J1 heat bar, label and overheat warning pulse, and the
# coop J2 heat label and bar (Etapa 20). Owned by HUD through _hud; the nodes and
# the J2 label stay on HUD because the tests read them there.

extends RefCounted

var _hud: CanvasLayer
var _fill_style: StyleBoxFlat = null
var _pulse_time: float = 0.0


func _init(hud: CanvasLayer) -> void:
	_hud = hud


## Gives the J1 heat bar its own fill style so its color can change with the heat.
func init_styles() -> void:
	if _hud._heat_progress_bar != null:
		var base_fill: StyleBox = _hud._heat_progress_bar.get_theme_stylebox(&"fill")
		if base_fill is StyleBoxFlat:
			_fill_style = (base_fill as StyleBoxFlat).duplicate() as StyleBoxFlat
		else:
			_fill_style = StyleBoxFlat.new()
			_fill_style.set_border_width_all(1)
			_fill_style.set_corner_radius_all(2)
		_hud._heat_progress_bar.add_theme_stylebox_override(&"fill", _fill_style)


## Pulses the overheat warning label while it is visible.
func pulse(delta: float) -> void:
	if _hud._overheat_warning_label != null and _hud._overheat_warning_label.visible:
		_pulse_time += delta * 12.0
		var alpha: float = 0.5 + 0.5 * sin(_pulse_time)
		_hud._overheat_warning_label.modulate = Color(1.0, 1.0, 1.0, 0.4 + 0.6 * alpha)


## Updates heat level indicator, text label, and thermal overload warning.
func set_heat(current_heat: float, max_heat: float, is_overheated: bool) -> void:
	var ratio: float = clampf(current_heat / max_heat, 0.0, 1.0) if max_heat > 0.0 else 0.0
	var percentage: float = ratio * 100.0

	if _hud._heat_progress_bar != null:
		_hud._heat_progress_bar.max_value = 100.0
		_hud._heat_progress_bar.value = percentage
		if _fill_style != null:
			if is_overheated or percentage > 85.0:
				_fill_style.bg_color = Color(1.0, 0.22, 0.22, 1.0)
				_fill_style.border_color = Color(1.0, 0.6, 0.6, 1.0)
			elif percentage >= 50.0:
				_fill_style.bg_color = Color(1.0, 0.62, 0.12, 1.0)
				_fill_style.border_color = Color(1.0, 0.8, 0.35, 1.0)
			else:
				_fill_style.bg_color = Color(0.2, 0.85, 1.0, 1.0)
				_fill_style.border_color = Color(0.5, 0.95, 1.0, 1.0)

	if _hud._heat_label != null:
		_hud._heat_label.text = "CALOR: %d%%" % int(round(percentage))

	if _hud._overheat_warning_label != null:
		_hud._overheat_warning_label.visible = is_overheated
		if not is_overheated:
			_hud._overheat_warning_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Coop local (Etapa 20): J2 heat label and bar in the J2 panel, separate from J1's bar.
func set_heat_p2(current: float, maximum: float, overheated: bool) -> void:
	if _hud._heat_p2_label == null:
		_hud._heat_p2_label = Label.new()
		_hud._heat_p2_label.name = "HeatP2Label"
		_hud._heat_p2_label.custom_minimum_size = Vector2(0.0, 28.0)
		_hud._heat_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud._heat_p2_label.add_theme_font_size_override("font_size", 12)
		_hud._heat_p2_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
		_hud._layout.ensure_p2_panel().add_child(_hud._heat_p2_label)
	var percent: int = int(round(current / maximum * 100.0)) if maximum > 0.0 else 0
	_hud._heat_p2_label.text = "CALOR: %d%%" % percent
	if overheated:
		_hud._heat_p2_label.text += " SOBRECARGA"
	_hud._heat_p2_label.visible = true
	var bar: ProgressBar = _hud._layout.ensure_p2_panel().get_node_or_null("HeatP2Bar") as ProgressBar
	if bar == null:
		bar = ProgressBar.new()
		bar.name = "HeatP2Bar"
		bar.custom_minimum_size = Vector2(240.0, 14.0)
		bar.max_value = 100.0
		bar.show_percentage = false
		if _hud._heat_progress_bar != null:
			bar.add_theme_stylebox_override("background", _hud._heat_progress_bar.get_theme_stylebox("background"))
			bar.add_theme_stylebox_override("fill", _hud._heat_progress_bar.get_theme_stylebox("fill"))
		_hud._layout.ensure_p2_panel().add_child(bar)
	bar.value = percent


func get_heat_p2_parent() -> Node:
	return _hud._heat_p2_label.get_parent() if _hud._heat_p2_label != null else null


func get_heat_p2_text() -> String:
	return _hud._heat_p2_label.text if _hud._heat_p2_label != null else ""
