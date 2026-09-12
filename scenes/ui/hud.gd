# hud.gd
# Displays player lives, score, wave, boss health bar, arsenal selection,
# barrel overheat status, and active combo multipliers.
# Emits semantic signals for player weapon choice, retries, and menu navigation.

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

@onready var _boss_container: Control = $BossContainer
@onready var _boss_name_label: Label = $BossContainer/BossNameLabel
@onready var _boss_progress_bar: ProgressBar = $BossContainer/BossProgressBar

@onready var _weapon_selector_container: Control = get_node_or_null("WeaponSelectorContainer") as Control
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

var _weapon_buttons: Array[Button] = []
var _active_weapon_style: StyleBoxFlat = null
var _inactive_weapon_style: StyleBoxFlat = null
var _heat_fill_style: StyleBoxFlat = null
var _overheat_pulse_time: float = 0.0


func _ready() -> void:
	_init_weapon_buttons()
	_init_styles()
	set_active_weapon(0)
	set_heat(0.0, 100.0, false)
	set_combo(1, 0, 0.0)


func _process(delta: float) -> void:
	if _overheat_warning_label != null and _overheat_warning_label.visible:
		_overheat_pulse_time += delta * 12.0
		var alpha: float = 0.5 + 0.5 * sin(_overheat_pulse_time)
		_overheat_warning_label.modulate = Color(1.0, 1.0, 1.0, 0.4 + 0.6 * alpha)


func _init_weapon_buttons() -> void:
	_weapon_buttons.clear()
	for i: int in range(4):
		var btn: Button = get_node_or_null("WeaponSelectorContainer/WeaponButton%d" % i) as Button
		if btn != null:
			_weapon_buttons.append(btn)
			var idx: int = i
			btn.pressed.connect(func() -> void: weapon_selected_by_user.emit(idx))


func _init_styles() -> void:
	_active_weapon_style = StyleBoxFlat.new()
	_active_weapon_style.bg_color = Color(0.12, 0.25, 0.45, 0.95)
	_active_weapon_style.border_color = Color(0.22, 0.9, 1.0, 1.0)
	_active_weapon_style.set_border_width_all(2)
	_active_weapon_style.set_corner_radius_all(3)

	_inactive_weapon_style = StyleBoxFlat.new()
	_inactive_weapon_style.bg_color = Color(0.06, 0.08, 0.16, 0.8)
	_inactive_weapon_style.border_color = Color(0.25, 0.35, 0.5, 0.5)
	_inactive_weapon_style.set_border_width_all(1)
	_inactive_weapon_style.set_corner_radius_all(3)

	if _heat_progress_bar != null:
		var base_fill: StyleBox = _heat_progress_bar.get_theme_stylebox(&"fill")
		if base_fill is StyleBoxFlat:
			_heat_fill_style = (base_fill as StyleBoxFlat).duplicate() as StyleBoxFlat
		else:
			_heat_fill_style = StyleBoxFlat.new()
			_heat_fill_style.set_border_width_all(1)
			_heat_fill_style.set_corner_radius_all(2)
		_heat_progress_bar.add_theme_stylebox_override(&"fill", _heat_fill_style)


## Updates visual button styles to highlight the currently equipped weapon.
func set_active_weapon(weapon_index: int) -> void:
	for i: int in range(_weapon_buttons.size()):
		var btn: Button = _weapon_buttons[i]
		if btn == null:
			continue
		if i == weapon_index:
			btn.add_theme_color_override(&"font_color", Color(0.2, 0.95, 1.0, 1.0))
			btn.add_theme_color_override(&"font_hover_color", Color(0.5, 1.0, 1.0, 1.0))
			btn.add_theme_color_override(&"font_pressed_color", Color(0.2, 0.95, 1.0, 1.0))
			if _active_weapon_style != null:
				btn.add_theme_stylebox_override(&"normal", _active_weapon_style)
				btn.add_theme_stylebox_override(&"hover", _active_weapon_style)
				btn.add_theme_stylebox_override(&"pressed", _active_weapon_style)
		else:
			btn.add_theme_color_override(&"font_color", Color(0.7, 0.75, 0.85, 0.8))
			btn.add_theme_color_override(&"font_hover_color", Color(0.9, 0.95, 1.0, 1.0))
			btn.add_theme_color_override(&"font_pressed_color", Color(0.7, 0.75, 0.85, 0.8))
			if _inactive_weapon_style != null:
				btn.add_theme_stylebox_override(&"normal", _inactive_weapon_style)
				btn.add_theme_stylebox_override(&"hover", _inactive_weapon_style)
				btn.add_theme_stylebox_override(&"pressed", _inactive_weapon_style)


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
