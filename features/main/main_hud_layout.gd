# main_hud_layout.gd
# Layout and HUD of the session: sizes the game layout to the viewport, keeps the
# HUD in sync with lives, score, wave, weapon, heat and combo, and hides the
# mission-complete message.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


func configure_game_layout() -> void:
	var vp_size: Vector2 = _main.get_viewport().get_visible_rect().size
	_main._game_layout.configure(vp_size)
	if _main._camera != null:
		_main._camera.position = vp_size * 0.5
	_main._player.set_horizontal_limits(_main._game_layout.get_player_horizontal_limits())
	var formation_origin: Vector2 = _main._game_layout.get_enemy_formation_origin()
	_main._enemy_spawner.set_formation_layout(formation_origin, formation_origin.y)


func update_hud() -> void:
	_main._hud.set_lives(_main.lives)
	_main._hud.set_score(_main.score)
	_main._hud.set_wave(_main.wave)
	if _main._hud != null:
		if _main._hud.has_method(&"set_active_weapon"):
			_main._hud.set_active_weapon(_main._player.get_weapon() if (_main._player != null and _main._player.has_method(&"get_weapon")) else 0)
		if _main._hud.has_method(&"set_weapon_level"):
			var cur_w: int = _main._player.get_weapon() if (_main._player != null and _main._player.has_method(&"get_weapon")) else 0
			var cur_lvl: int = _main._player.get_weapon_level() if (_main._player != null and _main._player.has_method(&"get_weapon_level")) else 1
			_main._hud.set_weapon_level(cur_lvl, cur_w)
		if _main._hud.has_method(&"set_heat"):
			var cur_h: float = _main._player.heat if (_main._player != null and "heat" in _main._player) else 0.0
			var max_h: float = _main._player.max_heat if (_main._player != null and "max_heat" in _main._player) else 100.0
			var is_oh: bool = _main._player.is_weapon_overheated() if (_main._player != null and _main._player.has_method(&"is_weapon_overheated")) else false
			_main._hud.set_heat(cur_h, max_h, is_oh)
		if _main._hud.has_method(&"set_combo"):
			var mult: int = _main._combo_system.get_multiplier() if (_main._combo_system != null and _main._combo_system.has_method(&"get_multiplier")) else 1
			var kills: int = _main._combo_system.get_kills() if (_main._combo_system != null and _main._combo_system.has_method(&"get_kills")) else 0
			var ratio: float = _main._combo_system.get_time_ratio() if (_main._combo_system != null and _main._combo_system.has_method(&"get_time_ratio")) else 0.0
			_main._hud.set_combo(mult, kills, ratio)


func hide_mission_complete_message() -> void:
	_main._hud.hide_mission_complete()
