# hud.gd
# Displays player lives, score, wave, boss health bar,
# barrel overheat status, and active combo multipliers.
# Emits semantic signals for player retries and menu navigation.

extends CanvasLayer

signal lives_changed(lives: int)
signal score_changed(score: int)
signal wave_changed(wave: int)
signal retry_mission_requested
signal main_menu_requested
signal weapon_selected_by_user(weapon_index: int)

@onready var _lives_label: Label = $Margin/LivesLabel
@onready var _score_label: Label = $Margin/ScoreLabel
@onready var _wave_label: Label = $Margin/WaveLabel
@onready var _active_weapon_label: Label = get_node_or_null("Margin/ActiveWeaponLabel") as Label

@onready var _boss_container: Control = $BossContainer
@onready var _boss_name_label: Label = $BossContainer/BossNameLabel
@onready var _boss_progress_bar: ProgressBar = $BossContainer/BossProgressBar

@onready var _heat_container: Control = get_node_or_null("HeatContainer") as Control
@onready var _heat_label: Label = get_node_or_null("HeatContainer/HeatLabel") as Label
@onready var _overheat_warning_label: Label = get_node_or_null("HeatContainer/OverheatWarningLabel") as Label
@onready var _heat_progress_bar: ProgressBar = get_node_or_null("HeatContainer/HeatProgressBar") as ProgressBar

@onready var _combo_container: Control = get_node_or_null("ComboContainer") as Control
@onready var _combo_label: Label = get_node_or_null("ComboContainer/ComboLabel") as Label
@onready var _combo_progress_bar: ProgressBar = get_node_or_null("ComboContainer/ComboProgressBar") as ProgressBar

@onready var _victory_label: Label = $VictoryLabel
@onready var _victory_score_label: Label = $VictoryScoreLabel
@onready var _new_record_label: Label = $NewRecordLabel
@onready var _retry_button: Button = $RetryButton
@onready var _main_menu_button: Button = $MainMenuButton

## Wave-cleared banner (Etapa 15 T6): text, display time, and fade-out length.
const WAVE_CLEARED_BANNER_TEXT: String = "¡OLEADA SUPERADA!"
const WAVE_CLEARED_BANNER_DURATION: float = 2.5
const WAVE_CLEARED_BANNER_FADE: float = 0.35

var _current_weapon_level: int = 1
var _current_weapon_type: int = 0
var _heat_fill_style: StyleBoxFlat = null
var _overheat_pulse_time: float = 0.0
var _wave_cleared_label: Label = null
var _wave_cleared_tween: Tween = null


func _ready() -> void:
	_init_styles()
	_init_wave_cleared_banner()
	set_active_weapon(_current_weapon_type)
	set_weapon_level(1, 0)
	set_heat(0.0, 100.0, false)
	set_combo(1, 0, 0.0)


func _process(delta: float) -> void:
	if _overheat_warning_label != null and _overheat_warning_label.visible:
		_overheat_pulse_time += delta * 12.0
		var alpha: float = 0.5 + 0.5 * sin(_overheat_pulse_time)
		_overheat_warning_label.modulate = Color(1.0, 1.0, 1.0, 0.4 + 0.6 * alpha)


## Creates the hidden "¡OLEADA SUPERADA!" label centered near the top of the screen.
func _init_wave_cleared_banner() -> void:
	_wave_cleared_label = Label.new()
	_wave_cleared_label.name = "WaveClearedLabel"
	_wave_cleared_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wave_cleared_label.offset_left = -300.0
	_wave_cleared_label.offset_right = 300.0
	_wave_cleared_label.offset_top = 96.0
	_wave_cleared_label.offset_bottom = 150.0
	_wave_cleared_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_cleared_label.add_theme_font_size_override(&"font_size", 36)
	_wave_cleared_label.add_theme_color_override(&"font_color", Color(0.45, 1.0, 0.6, 1.0))
	_wave_cleared_label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.05, 0.09, 0.95))
	_wave_cleared_label.add_theme_constant_override(&"outline_size", 6)
	_wave_cleared_label.visible = false
	add_child(_wave_cleared_label)


## Shows the wave-cleared banner, then fades and hides it after its display time.
func show_wave_cleared_banner() -> void:
	if _wave_cleared_label == null:
		return
	if _wave_cleared_tween != null and _wave_cleared_tween.is_valid():
		_wave_cleared_tween.kill()
	_wave_cleared_label.text = WAVE_CLEARED_BANNER_TEXT
	_wave_cleared_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_wave_cleared_label.visible = true
	_wave_cleared_tween = create_tween()
	_wave_cleared_tween.tween_interval(WAVE_CLEARED_BANNER_DURATION - WAVE_CLEARED_BANNER_FADE)
	_wave_cleared_tween.tween_property(_wave_cleared_label, "modulate:a", 0.0, WAVE_CLEARED_BANNER_FADE)
	_wave_cleared_tween.tween_callback(hide_wave_cleared_banner)


## Hides the wave-cleared banner immediately.
func hide_wave_cleared_banner() -> void:
	if _wave_cleared_tween != null and _wave_cleared_tween.is_valid():
		_wave_cleared_tween.kill()
	if _wave_cleared_label != null:
		_wave_cleared_label.visible = false
		_wave_cleared_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Returns the banner text while it is visible, or an empty string otherwise.
func get_wave_cleared_banner_text() -> String:
	if _wave_cleared_label == null or not _wave_cleared_label.visible:
		return ""
	return _wave_cleared_label.text


func _init_styles() -> void:
	if _heat_progress_bar != null:
		var base_fill: StyleBox = _heat_progress_bar.get_theme_stylebox(&"fill")
		if base_fill is StyleBoxFlat:
			_heat_fill_style = (base_fill as StyleBoxFlat).duplicate() as StyleBoxFlat
		else:
			_heat_fill_style = StyleBoxFlat.new()
			_heat_fill_style.set_border_width_all(1)
			_heat_fill_style.set_corner_radius_all(2)
		_heat_progress_bar.add_theme_stylebox_override(&"fill", _heat_fill_style)


## Updates active weapon text and neon color theme in the HUD.
func set_active_weapon(weapon_index: int) -> void:
	_current_weapon_type = weapon_index
	if _active_weapon_label != null:
		var weapon_names: Array[String] = ["BLASTER", "MISIL", "LÁSER"]
		var weapon_colors: Array[Color] = [
			Color(0.2, 0.6, 1.0),
			Color(1.0, 0.55, 0.1),
			Color(1.0, 0.2, 0.25)
		]
		var idx: int = clampi(weapon_index, 0, 2)
		_active_weapon_label.text = "ARMA: %s" % weapon_names[idx]
		_active_weapon_label.modulate = weapon_colors[idx]


## Maintained for backwards compatibility; weapon power is displayed diegetically through projectiles.
func set_weapon_level(level: int, weapon_type: int = -1) -> void:
	if weapon_type >= 0:
		_current_weapon_type = weapon_type
	_current_weapon_level = clampi(level, 1, 15)



## Updates heat level indicator, text label, and thermal overload warning.
func set_heat(current_heat: float, max_heat: float, is_overheated: bool) -> void:
	var ratio: float = clampf(current_heat / max_heat, 0.0, 1.0) if max_heat > 0.0 else 0.0
	var percentage: float = ratio * 100.0

	if _heat_progress_bar != null:
		_heat_progress_bar.max_value = 100.0
		_heat_progress_bar.value = percentage
		if _heat_fill_style != null:
			if is_overheated or percentage > 85.0:
				_heat_fill_style.bg_color = Color(1.0, 0.22, 0.22, 1.0)
				_heat_fill_style.border_color = Color(1.0, 0.6, 0.6, 1.0)
			elif percentage >= 50.0:
				_heat_fill_style.bg_color = Color(1.0, 0.62, 0.12, 1.0)
				_heat_fill_style.border_color = Color(1.0, 0.8, 0.35, 1.0)
			else:
				_heat_fill_style.bg_color = Color(0.2, 0.85, 1.0, 1.0)
				_heat_fill_style.border_color = Color(0.5, 0.95, 1.0, 1.0)

	if _heat_label != null:
		_heat_label.text = "CALOR: %d%%" % int(round(percentage))

	if _overheat_warning_label != null:
		_overheat_warning_label.visible = is_overheated
		if not is_overheated:
			_overheat_warning_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Updates combo multiplier banner and remaining decay time progress.
func set_combo(multiplier: int, kills: int, time_ratio: float) -> void:
	if multiplier >= 2:
		if _combo_container != null:
			_combo_container.visible = true
		if _combo_progress_bar != null:
			_combo_progress_bar.max_value = 1.0
			_combo_progress_bar.value = clampf(time_ratio, 0.0, 1.0)
		if _combo_label != null:
			if multiplier >= 4:
				_combo_label.text = "COMBO x%d MAX!" % multiplier
			else:
				_combo_label.text = "COMBO x%d!" % multiplier
	else:
		if _combo_container != null:
			_combo_container.visible = false
		if _combo_progress_bar != null:
			_combo_progress_bar.value = 0.0
		if _combo_label != null:
			_combo_label.text = ""


func show_boss_health_bar(boss_name: String, max_health: int) -> void:
	_boss_name_label.text = "BOSS: %s" % boss_name
	_boss_progress_bar.max_value = max_health
	_boss_progress_bar.value = max_health
	_boss_container.visible = true


func update_boss_health(current: int, max_health: int) -> void:
	_boss_progress_bar.max_value = max_health
	_boss_progress_bar.value = current


func hide_boss_health_bar() -> void:
	_boss_container.visible = false


func set_lives(lives: int) -> void:
	_lives_label.text = "Vidas: %d" % lives
	lives_changed.emit(lives)


## Coop local (Etapa 20): J2 lives indicator, hidden until set (singleplayer never sets it).
var _lives_p2_label: Label = null


## Right-side panel for J2 (Etapa 20): stacks its labels so they never overlap J1's.
var _p2_panel: VBoxContainer = null


func _ensure_p2_panel() -> VBoxContainer:
	if _p2_panel == null:
		_p2_panel = VBoxContainer.new()
		_p2_panel.name = "P2Panel"
		_p2_panel.anchor_left = 1.0
		_p2_panel.anchor_right = 1.0
		_p2_panel.offset_left = -260.0
		_p2_panel.offset_right = -16.0
		_p2_panel.offset_top = 16.0
		_p2_panel.grow_horizontal = 0
		add_child(_p2_panel)
	return _p2_panel


func get_lives_p2_parent() -> Node:
	return _lives_p2_label.get_parent() if _lives_p2_label != null else null


func get_heat_p2_parent() -> Node:
	return _heat_p2_label.get_parent() if _heat_p2_label != null else null


func set_lives_p2(lives: int) -> void:
	if _lives_p2_label == null:
		_lives_p2_label = Label.new()
		_lives_p2_label.name = "LivesP2Label"
		_lives_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ensure_p2_panel().add_child(_lives_p2_label)
	_lives_p2_label.text = "Vidas J2: %d" % lives
	_lives_p2_label.visible = true


func is_lives_p2_visible() -> bool:
	return _lives_p2_label != null and _lives_p2_label.visible


func get_lives_p2_text() -> String:
	return _lives_p2_label.text if _lives_p2_label != null else ""


## Coop local (Etapa 20): J2 heat indicator, separate from J1's HeatContainer.
var _heat_p2_label: Label = null


func set_heat_p2(current: float, maximum: float, overheated: bool) -> void:
	if _heat_p2_label == null:
		_heat_p2_label = Label.new()
		_heat_p2_label.name = "HeatP2Label"
		_heat_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ensure_p2_panel().add_child(_heat_p2_label)
	var percent: int = int(round(current / maximum * 100.0)) if maximum > 0.0 else 0
	_heat_p2_label.text = "Calor J2: %d%%" % percent
	if overheated:
		_heat_p2_label.text += " SOBRECARGA"
	_heat_p2_label.visible = true


func get_heat_p2_text() -> String:
	return _heat_p2_label.text if _heat_p2_label != null else ""


func set_score(score: int) -> void:
	_score_label.text = "Score: %d" % score
	score_changed.emit(score)


func set_wave(wave: int) -> void:
	_wave_label.text = "Oleada %d" % wave
	wave_changed.emit(wave)


func show_mission_complete(final_score: int, is_new_record: bool = false) -> void:
	_victory_label.text = "¡Victoria!"
	_victory_score_label.text = "Score final: %d" % final_score
	_victory_label.visible = true
	_victory_score_label.visible = true
	_new_record_label.visible = is_new_record
	_retry_button.visible = true
	_main_menu_button.visible = true
	_retry_button.grab_focus()


func hide_mission_complete() -> void:
	_victory_label.visible = false
	_victory_score_label.visible = false
	_new_record_label.visible = false
	_retry_button.visible = false
	_main_menu_button.visible = false
	hide_boss_health_bar()


func _on_retry_button_pressed() -> void:
	retry_mission_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
