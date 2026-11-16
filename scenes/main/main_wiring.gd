# main_wiring.gd
# Scene wiring of the session: connects the player, HUD, spawners, menus, game-over
# and feedback signals to their handlers, and routes menu, settings, input and
# child-node events to the session lifecycle and the coop ships.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

const NetSyncMode: GDScript = preload("res://features/net/net_sync_mode.gd")
const NetSyncNode: GDScript = preload("res://features/net/net_sync_node.gd")
const NetSyncDisconnect: GDScript = preload("res://features/net/net_sync_disconnect.gd")
const NET_NODE_NAME: String = "NetSync"

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


## Called from Main._ready: creates the combo system when missing and connects every signal.
func setup() -> void:
	if _main._combo_system == null:
		var combo_script: Script = load("res://core/session/combo_system.gd") as Script
		if combo_script != null:
			_main._combo_system = combo_script.new() as Node
			_main._combo_system.name = "ComboSystem"
			_main.add_child(_main._combo_system)

	_main._player.bullet_scene = _main.bullet_scene
	_main._player.damage_requested.connect(_main._on_player_damage_requested)
	if _main._player.has_signal(&"shot_fired"):
		_main._player.shot_fired.connect(_main._scoring.on_player_shot_fired)

	if _main._player.has_signal(&"weapon_changed") and _main._hud.has_method(&"set_active_weapon"):
		_main._player.weapon_changed.connect(func(w: int) -> void:
			_main._hud.set_active_weapon(w)
			if _main._hud.has_method(&"set_weapon_level"):
				_main._hud.set_weapon_level(_main._player.get_weapon_level() if _main._player.has_method(&"get_weapon_level") else 1, w)
		)

	if _main._player.has_signal(&"weapon_level_changed") and _main._hud.has_method(&"set_weapon_level"):
		_main._player.weapon_level_changed.connect(func(lvl: int) -> void:
			_main._hud.set_weapon_level(lvl, _main._player.get_weapon() if _main._player.has_method(&"get_weapon") else 0)
		)

	if _main._player.has_signal(&"heat_changed") and _main._hud.has_method(&"set_heat"):
		_main._player.heat_changed.connect(func(cur: float, m: float) -> void:
			_main._hud.set_heat(cur, m, _main._player.is_weapon_overheated() if _main._player.has_method(&"is_weapon_overheated") else false)
		)

	if _main._player.has_signal(&"overheat_state_changed"):
		_main._player.overheat_state_changed.connect(func(overheated: bool) -> void:
			if _main._hud.has_method(&"set_heat"):
				_main._hud.set_heat(_main._player.heat if "heat" in _main._player else 0.0, _main._player.max_heat if "max_heat" in _main._player else 100.0, overheated)
			if overheated and _main._session_active and _main._audio_feedback != null and _main._audio_feedback.has_method(&"play_overheat_warning"):
				_main._audio_feedback.play_overheat_warning()
		)

	if _main._hud.has_signal(&"weapon_selected_by_user") and _main._player.has_method(&"set_weapon"):
		_main._hud.weapon_selected_by_user.connect(_main._player.set_weapon)

	if _main._combo_system != null:
		if _main._combo_system.has_signal(&"combo_updated") and _main._hud.has_method(&"set_combo"):
			_main._combo_system.combo_updated.connect(_main._hud.set_combo)
		if _main._combo_system.has_signal(&"combo_reset") and _main._hud.has_method(&"set_combo"):
			_main._combo_system.combo_reset.connect(func() -> void: _main._hud.set_combo(1, 0, 0.0))

	_main._enemy_spawner.enemy_contacted_player.connect(on_enemy_contacted_player)
	_main._enemy_spawner.enemy_destroyed.connect(_main._on_enemy_destroyed)
	_main._enemy_spawner.wave_cleared.connect(_main._on_wave_cleared)
	if _main._enemy_spawner.has_signal(&"enrage_triggered"):
		_main._enemy_spawner.enrage_triggered.connect(_main._scoring.on_enrage_triggered)

	if _main._asteroid_spawner == null:
		_main._asteroid_spawner = _main.get_node_or_null("AsteroidSpawner") as Node2D
	if _main._asteroid_spawner != null:
		if _main._asteroid_spawner.has_signal(&"asteroid_spawned"):
			_main._asteroid_spawner.asteroid_spawned.connect(_main._scoring.on_asteroid_spawned)
		if _main._asteroid_spawner.has_signal(&"asteroid_wave_completed"):
			_main._asteroid_spawner.asteroid_wave_completed.connect(_main._scoring.on_asteroid_wave_completed)
	_main._game_over.retry_requested.connect(on_game_over_retry_requested)
	_main._game_over.main_menu_requested.connect(_main.return_to_main_menu)
	_main._hud.retry_mission_requested.connect(on_hud_retry_mission_requested)
	_main._hud.main_menu_requested.connect(_main.return_to_main_menu)
	_main._main_menu.play_requested.connect(on_main_menu_play_requested)
	_main._main_menu.quit_requested.connect(on_main_menu_quit_requested)
	_main._main_menu.settings_requested.connect(on_main_menu_settings_requested)
	_main._settings_menu = _main.SETTINGS_MENU_SCENE.instantiate()
	_main.add_child(_main._settings_menu)
	_main._settings_menu.visible = false
	_main._settings_menu.back_requested.connect(on_settings_back_requested)
	_main._pause_menu.resume_requested.connect(_main._session.resume_session)
	_main._pause_menu.main_menu_requested.connect(_main.return_to_main_menu)
	_main._wave_announcement.announcement_finished.connect(_main._waves.on_wave_announcement_finished)
	_main.child_entered_tree.connect(on_child_entered_tree)
	_main._high_score = _main.HighScore.load_value()
	_main.Settings.apply_display(_main.Settings.load_settings())
	_main._hud_layout.configure_game_layout()
	_main._hud_layout.update_hud()


## Etapa 20 (S4): a lost connection closes the network, returns to the menu and shows a notice.
## Safe without an active session: it only closes the lobby and shows the menu.
func on_network_lost() -> void:
	NetSyncDisconnect.clean_client(_main)
	if _main._main_menu.has_method(&"close_network"):
		_main._main_menu.close_network()
	_main._enter_main_menu()
	if _main._main_menu.has_method(&"show_network_message"):
		_main._main_menu.show_network_message("Se perdio la conexion con el host.")


func unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"pause"):
		return
	if _main._session_state == _main.SessionState.PLAYING or _main._session_state == _main.SessionState.BOSS_BATTLE:
		_main._session.pause_session()
	elif _main._session_state == _main.SessionState.PAUSED:
		_main._session.resume_session()
	else:
		return
	_main.get_viewport().set_input_as_handled()


## Receives the difficulty picked in the main menu; only the menu sets session_difficulty.
func on_main_menu_play_requested() -> void:
	if _main._session_state != _main.SessionState.MAIN_MENU:
		return
	_main.session_difficulty = _main._main_menu.selected_difficulty
	_main.session_coop = _main._main_menu.coop_selected
	if _main.session_coop:
		_main._ships.enable_coop_local()
	_begin_net_sync(_main.session_coop and NetSyncMode.is_network(_main._main_menu.session_mode))
	_main._session.start_session()
	_main._ships.set_player_two_active(_main.session_coop)


## Etapa 20 T1: every session starts from clean roles; only a NETWORK coop session adds the NetSync node.
## J2 persists between sessions, so its remote/replica flags are reset here, not only set.
func _begin_net_sync(network: bool) -> void:
	var old: Node = _main.get_node_or_null(NET_NODE_NAME)
	if old != null:
		_main.remove_child(old)
		old.queue_free()
	for ship: Variant in [_main._player, _main._player_two]:
		if ship != null:
			ship.set("remote_driven", false)
			ship.set("replica", false)
	_main._enemy_spawner.set("replica", false)
	if not network:
		return
	var sync: Node = NetSyncNode.new()
	sync.name = NET_NODE_NAME
	_main.add_child(sync)
	sync.setup(_main, _main.multiplayer.is_server())


func on_main_menu_quit_requested() -> void:
	_main.return_to_main_menu()
	_main.get_tree().quit()


func on_main_menu_settings_requested() -> void:
	_main._main_menu.visible = false
	_main._settings_menu.show_menu()


func on_settings_back_requested() -> void:
	_main._settings_menu.visible = false
	_main._main_menu.show_menu()


func on_game_over_retry_requested() -> void:
	_main._session.reset_session()


func on_hud_retry_mission_requested() -> void:
	_main._session.reset_session()


func on_child_entered_tree(child: Node) -> void:
	if child is Area2D and child.has_signal(&"player_hit"):
		child.connect(&"player_hit", on_enemy_bullet_player_hit)


func on_enemy_contacted_player(player: Node2D) -> void:
	_main._request_player_damage(player)


func on_enemy_bullet_player_hit(player: Node2D) -> void:
	_main._request_player_damage(player)
