# main_session.gd
# Session lifecycle of Main: menu state, start, pause and resume, reset, game over,
# mission complete, the session high score and the clean-up of combat transients.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

const NET_SYNC_NAME: String = "NetSync"
const NetSyncDisconnect: GDScript = preload("res://features/net/net_sync_disconnect.gd")

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


func start_session() -> void:
	if _main._session_state != _main.SessionState.MAIN_MENU:
		return
	reset_session()


func pause_session() -> void:
	if _main._session_state != _main.SessionState.PLAYING and _main._session_state != _main.SessionState.BOSS_BATTLE:
		return
	_main._state_before_pause = _main._session_state
	_main._session_state = _main.SessionState.PAUSED
	_main._pause_menu.show_menu()
	_main._audio_feedback.set_session_paused(true)
	_main.get_tree().paused = true


func resume_session() -> void:
	if _main._session_state != _main.SessionState.PAUSED:
		return
	_main.get_tree().paused = false
	_main._pause_menu.visible = false
	_main._audio_feedback.set_session_paused(false)
	_main._session_state = _main._state_before_pause


func is_mission_complete() -> bool:
	return _main._mission_complete


func is_session_active() -> bool:
	return _main._session_active


func enter_main_menu() -> void:
	_main.get_tree().paused = false
	_clear_net_replicas()
	NetSyncDisconnect.clear_notice(_main)
	_main._waves.end_belt_camera_follow()
	_main._enemy_spawner.stop()
	_main._enemy_spawner.clear_formation()
	_main._boss.clear_boss()
	clear_combat_transients()
	_main._waves.reset_wave_cleared_feedback()
	_main._boss_pending = false
	_main._visual_feedback.clear_effects()
	_main._wave_announcement.cancel_announcement()
	_main._pending_wave_index = 0
	_main._audio_feedback.stop_combat_music()
	_main._audio_feedback.stop_boss_music()
	_main._hud.hide_boss_health_bar()
	_main._player.clear_power_ups()
	if _main._combo_system != null and _main._combo_system.has_method(&"reset_combo"):
		_main._combo_system.reset_combo()
	if _main._player != null:
		if _main._player.has_method(&"reset_heat"):
			_main._player.reset_heat()
		if _main._player.has_method(&"set_weapon"):
			_main._player.set_weapon(0)
		if _main._player.has_method(&"set_weapon_level"):
			_main._player.set_weapon_level(1)
	if _main._hud != null:
		if _main._hud.has_method(&"set_active_weapon"):
			_main._hud.set_active_weapon(0)
		if _main._hud.has_method(&"set_heat"):
			_main._hud.set_heat(0.0, _main._player.max_heat if _main._player != null and "max_heat" in _main._player else 100.0, false)
		if _main._hud.has_method(&"set_combo"):
			_main._hud.set_combo(1, 0, 0.0)
	_main.lives = _main.STARTING_LIVES
	_main.score = 0
	_main.wave = 1
	_main._chapter = 1
	_main._bonus_active = false
	_main._hyperspace_jumps = 0
	_main._session_active = false
	_main._mission_complete = false
	_main._wave_is_clean = true
	_main._session_state = _main.SessionState.MAIN_MENU
	_main._game_over.visible = false
	_main._pause_menu.visible = false
	_main._hud.visible = false
	_main._player.set_gameplay_enabled(false)
	_main._player.visible = false
	_main._ships.set_player_two_active(false)
	_main._hud_layout.hide_mission_complete_message()
	_main._hud_layout.update_hud()
	_main._main_menu.set_high_score(_main._high_score)
	_main._main_menu.show_menu()


func reset_session() -> void:
	_main.get_tree().paused = false
	_clear_net_replicas()
	NetSyncDisconnect.clear_notice(_main)
	_main.SESSION_STATS.reset()
	_main.kills_by_type.clear()
	_main._enemy_spawner.stop()
	_main._enemy_spawner.clear_formation()
	if _main._asteroid_spawner != null:
		_main._asteroid_spawner.stop()
		_main._asteroid_spawner.clear_asteroids()
	_main._waves.end_belt_camera_follow()
	if _main._camera != null and _main._camera.has_method(&"reset_shake"):
		_main._camera.reset_shake()
	_main._waves.reset_wave_cleared_feedback()
	_main._boss.clear_boss()
	_main._boss_pending = false
	clear_combat_transients()
	_main._visual_feedback.clear_effects()
	_main._wave_announcement.cancel_announcement()
	_main._pending_wave_index = 0
	_main._audio_feedback.stop_combat_music()
	_main._audio_feedback.stop_boss_music()
	_main._hud.hide_boss_health_bar()
	_main._player.clear_power_ups()
	if _main._combo_system != null and _main._combo_system.has_method(&"reset_combo"):
		_main._combo_system.reset_combo()
	if _main._player != null:
		if _main._player.has_method(&"reset_heat"):
			_main._player.reset_heat()
		if _main._player.has_method(&"set_weapon"):
			_main._player.set_weapon(0)
	if _main._hud != null:
		if _main._hud.has_method(&"set_active_weapon"):
			_main._hud.set_active_weapon(0)
		if _main._hud.has_method(&"set_heat"):
			_main._hud.set_heat(0.0, _main._player.max_heat if _main._player != null and "max_heat" in _main._player else 100.0, false)
		if _main._hud.has_method(&"set_combo"):
			_main._hud.set_combo(1, 0, 0.0)
	_main.lives = _main.STARTING_LIVES
	_main.score = 0
	_main.wave = 1
	_main._chapter = 1
	_main._bonus_active = false
	_main._hyperspace_jumps = 0
	_main._last_extra_life_threshold = 0
	if _main._player != null and _main._player.has_method(&"set_weapon_level"):
		_main._player.set_weapon_level(1)
	_main._session_active = true
	_main._mission_complete = false
	_main._wave_is_clean = true
	_main._session_state = _main.SessionState.PLAYING
	_main._enemy_spawner.session_difficulty = _main.session_difficulty
	_main._player.cooling_scale = _main.DS.cooling_multiplier(_main.session_difficulty)
	_main._main_menu.visible = false
	_main._game_over.visible = false
	_main._pause_menu.visible = false
	_main._hud.visible = true
	_main._hud_layout.configure_game_layout()
	_main._player.set_gameplay_enabled(true)
	_main._player.respawn(_main._game_layout.get_player_spawn_position())
	_main._hud_layout.hide_mission_complete_message()
	_main._starfield.reset_scroll()
	_main._hud_layout.update_hud()
	_main._audio_feedback.start_combat_music()
	_main._enemy_spawner.difficulty_level = _main._chapter
	_main._enemy_spawner.start_wave(0)


## host_stats: the host's final kills and accuracy (Etapa 20 T42) on a client; empty on the host, which shows its own.
func end_session(host_stats: Dictionary = {}) -> void:
	if not _main._session_active:
		return
	_main._session_active = false
	_main._waves.end_belt_camera_follow()
	_main._session_state = _main.SessionState.GAME_OVER
	_main._player.set_gameplay_enabled(false)
	_main._ships.set_player_two_active(false)
	_main._enemy_spawner.stop()
	if _main._asteroid_spawner != null:
		_main._asteroid_spawner.stop()
	_main._boss.clear_boss()
	_main._wave_announcement.cancel_announcement()
	_main._audio_feedback.stop_combat_music()
	_main._audio_feedback.stop_boss_music()
	_main._hud.hide_boss_health_bar()
	var is_new_record: bool = update_high_score_if_needed()
	if host_stats.is_empty():
		_main._game_over.show_session_stats(get_session_accuracy(), _main.kills_by_type)
	else:
		_main._game_over.show_session_stats(float(host_stats["accuracy"]), host_stats["kills"] as Dictionary)
	_main._game_over.show_game_over(_main.score, is_new_record)
	_announce_session_end("game_over")


func complete_mission() -> void:
	_main._session_active = false
	_main._waves.end_belt_camera_follow()
	_main._mission_complete = true
	_main._session_state = _main.SessionState.MISSION_COMPLETE
	_main._player.set_gameplay_enabled(false)
	_main._enemy_spawner.stop()
	if _main._asteroid_spawner != null:
		_main._asteroid_spawner.stop()
	_main._boss.clear_boss()
	_main._wave_announcement.cancel_announcement()
	_main._audio_feedback.stop_combat_music()
	_main._audio_feedback.stop_boss_music()
	_main._hud.hide_boss_health_bar()
	var is_new_record: bool = update_high_score_if_needed()
	_main._hud.show_mission_complete(_main.score, is_new_record)
	_announce_session_end("mission_complete")


## Etapa 20 T4: the host tells the client how the match ended (game over or mission complete).
func _announce_session_end(kind: String) -> void:
	var net: Node = _main.get_node_or_null(NET_SYNC_NAME)
	if net != null and net.has_method(&"announce_session_end"):
		net.call("announce_session_end", kind)


## Etapa 20 T4: frees the client replicas of drops and asteroids when a match starts, ends or is left.
func _clear_net_replicas() -> void:
	var net: Node = _main.get_node_or_null(NET_SYNC_NAME)
	if net != null and net.has_method(&"clear_replicas"):
		net.call("clear_replicas")


func clear_combat_transients() -> void:
	for transient: Node in _main.get_tree().get_nodes_in_group(&"combat_transients"):
		if is_instance_valid(transient) and transient.get_parent() != _main._player and (_main._player == null or not _main._player.is_ancestor_of(transient)):
			transient.queue_free()


func clear_enemy_bullets() -> void:
	for bullet: Node in _main.get_tree().get_nodes_in_group(&"enemy_bullets"):
		if is_instance_valid(bullet):
			bullet.queue_free()


## Shot accuracy of the current session as a percentage (0.0 to 100.0).
func get_session_accuracy() -> float:
	return _main.SESSION_STATS.accuracy_percent(_main.SESSION_STATS.hits, _main.SESSION_STATS.shots)


## Returns true and persists the new best if this session's score beats
## the previous record; returns false otherwise.
func update_high_score_if_needed() -> bool:
	if _main.score <= _main._high_score:
		return false
	_main._high_score = _main.score
	_main.HighScore.save_value(_main._high_score)
	return true
