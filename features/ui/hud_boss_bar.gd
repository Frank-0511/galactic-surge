# hud_boss_bar.gd
# Boss health bar of the HUD: shows the boss name and its health, updates the bar
# and hides it. Owned by HUD through _hud; the nodes stay on HUD.

extends RefCounted

var _hud: CanvasLayer


func _init(hud: CanvasLayer) -> void:
	_hud = hud


func show_bar(boss_name: String, max_health: int) -> void:
	_hud._boss_name_label.text = "BOSS: %s" % boss_name
	_hud._boss_progress_bar.max_value = max_health
	_hud._boss_progress_bar.value = max_health
	_hud._boss_container.visible = true


func update_bar(current: int, max_health: int) -> void:
	_hud._boss_progress_bar.max_value = max_health
	_hud._boss_progress_bar.value = current


func hide_bar() -> void:
	_hud._boss_container.visible = false
