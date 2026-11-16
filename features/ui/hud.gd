# hud.gd
# Displays player lives, score, wave, boss health bar,
# barrel overheat status, and active combo multipliers.
# Emits semantic signals for player retries and menu navigation.
# Owns the nodes and state read by tests; logic lives in the hud_*.gd modules.

extends CanvasLayer

const HudWaveBanner: Script = preload("res://features/ui/hud_wave_banner.gd")
const HudBossBar: Script = preload("res://features/ui/hud_boss_bar.gd")
const HudLayout: Script = preload("res://features/ui/hud_layout.gd")
const HudWeapons: Script = preload("res://features/ui/hud_weapons.gd")
const HudHeat: Script = preload("res://features/ui/hud_heat.gd")
const HudStatus: Script = preload("res://features/ui/hud_status.gd")

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

var _banner: RefCounted = HudWaveBanner.new(self)
var _boss_bar: RefCounted = HudBossBar.new(self)
var _layout: RefCounted = HudLayout.new(self)
var _weapons: RefCounted = HudWeapons.new(self)
var _heat: RefCounted = HudHeat.new(self)
var _status: RefCounted = HudStatus.new(self)



func _ready() -> void:
	_layout.make_passive()
	_layout.move_p1_lives_bottom_left()
	_layout.move_p1_top_left()
	_weapons.update_level_label()
	_heat.init_styles()
	_banner.build()
	_weapons.set_active(_weapons.current_type)
	_weapons.set_level(1, 0)
	set_heat(0.0, 100.0, false)
	set_combo(1, 0, 0.0)


func _process(delta: float) -> void:
	_heat.pulse(delta)


## Shows the wave-cleared banner, then fades and hides it after its display time.
func show_wave_cleared_banner() -> void:
	_banner.show_banner()


## Hides the wave-cleared banner immediately.
func hide_wave_cleared_banner() -> void:
	_banner.hide_banner()


## Returns the banner text while it is visible, or an empty string otherwise.
func get_wave_cleared_banner_text() -> String:
	return _banner.get_text()


## Updates active weapon text and neon color theme in the HUD.
func set_active_weapon(weapon_index: int) -> void:
	_weapons.set_active(weapon_index)


## Maintained for backwards compatibility; weapon power is displayed diegetically through projectiles.
func set_weapon_level(level: int, weapon_type: int = -1) -> void:
	_weapons.set_level(level, weapon_type)


var _weapon_icon: Control = null
var _weapon_icon_p2: Control = null
var _weapon_level_label: Label = null
## Weapon level of J2, shown in the bottom-right corner (spec S7, Etapa 20).
var _weapon_level_p2_label: Label = null


## Icon per weapon type (0 blaster, 1 misil, 2 laser); the icon follows the weapon (Etapa 20).
func weapon_glyph(weapon_type: int) -> String:
	return _weapons.glyph(weapon_type)


func set_weapon_level_p2(level: int, weapon_type: int = -1) -> void:
	_weapons.set_level_p2(level, weapon_type)



## Updates heat level indicator, text label, and thermal overload warning.
func set_heat(current_heat: float, max_heat: float, is_overheated: bool) -> void:
	_heat.set_heat(current_heat, max_heat, is_overheated)


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
	_boss_bar.show_bar(boss_name, max_health)


func update_boss_health(current: int, max_health: int) -> void:
	_boss_bar.update_bar(current, max_health)


func hide_boss_health_bar() -> void:
	_boss_bar.hide_bar()


func set_lives(lives: int) -> void:
	_status.set_lives(lives)


## Coop local (Etapa 20): J2 lives indicator, hidden until set (singleplayer never sets it).
var _lives_p2_label: Label = null


## Right-side panel for J2 (Etapa 20); created and owned by _layout, read by the tests here.
var _p2_panel: VBoxContainer = null


func set_p2_visible(on: bool) -> void:
	_layout.set_p2_visible(on)


func get_lives_p2_parent() -> Node:
	return _status.get_lives_p2_parent()


func set_lives_p2(lives: int) -> void:
	_status.set_lives_p2(lives)


func is_lives_p2_visible() -> bool:
	return _status.is_lives_p2_visible()


func get_lives_p2_text() -> String:
	return _status.get_lives_p2_text()


## Coop local (Etapa 20): J2 score label, in J2's panel with the same style as its lives.
var _score_p2_label: Label = null


func set_score_p2(points: int) -> void:
	_status.set_score_p2(points)


## Coop local (Etapa 20): J2 heat indicator, separate from J1's HeatContainer.
var _heat_p2_label: Label = null


func set_heat_p2(current: float, maximum: float, overheated: bool) -> void:
	_heat.set_heat_p2(current, maximum, overheated)


func get_heat_p2_parent() -> Node:
	return _heat.get_heat_p2_parent()


func get_heat_p2_text() -> String:
	return _heat.get_heat_p2_text()


func set_score(score: int) -> void:
	_status.set_score(score)


func set_wave(wave: int) -> void:
	_status.set_wave(wave)


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
