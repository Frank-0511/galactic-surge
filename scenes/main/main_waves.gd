# main_waves.gd
# Wave flow of the session: wave-cleared rewards and feedback, the announcement that
# opens each wave, the asteroid belt wave and its camera follow (Etapa 16), the
# peaceful bonus wave, the hyperspace jump between chapters and the chapter getters.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


## Wave number within the current chapter (1-based, 1-10) from the global wave number.
func local_wave(global_wave: int) -> int:
	return (global_wave - 1) % _main.TOTAL_WAVES + 1


## Wave index within the current chapter (0-based, 0-9) from a global 0-based index.
func local_index(global_index: int) -> int:
	return global_index % _main.TOTAL_WAVES


func on_wave_cleared(_wave_index: int) -> void:
	# Etapa 20 T4: a network client never scores or starts a wave; the host sends them.
	if not _main._session_active or _main._player.get("replica") == true:
		return
	if _main._starfield != null and _main._starfield.has_method(&"trigger_warp_boost"):
		_main._starfield.trigger_warp_boost(3.0, 10.0)
	if _main._wave_is_clean:
		_main._add_score(_main.CLEAN_WAVE_BONUS)
		_main._hud.set_score(_main.score)
		_main._visual_feedback.play_score_popup(_main._player.global_position + Vector2(0, -50), _main.CLEAN_WAVE_BONUS, true)
	if local_wave(_main.wave) >= _main.TOTAL_WAVES:
		# Transition to Boss encounter instead of completing mission directly
		_main._session_state = _main.SessionState.WAVE_TRANSITION
		_main._enemy_spawner.stop()
		_main._boss_pending = true
		_main._audio_feedback.stop_combat_music()
		_main._wave_announcement.show_announcement(_main.wave + 1, "¡AMENAZA COLOSAL DETECTADA!")
		return
	show_wave_cleared_feedback()
	# Enter wave transition instead of starting the next wave immediately.
	_main._session_state = _main.SessionState.WAVE_TRANSITION
	_main._enemy_spawner.stop()
	_main._pending_wave_index = _main.wave
	var phrase: String = pick_radar_phrase()
	if local_index(_main._pending_wave_index) == _main.ASTEROID_WAVE_INDEX and _main._asteroid_spawner != null and _main._asteroid_spawner.has_method(&"start_asteroid_wave"):
		phrase = "¡ALERTA: CINTURÓN DE ASTEROIDES INMINENTE!"
		if _main._audio_feedback != null and _main._audio_feedback.has_method(&"play_asteroid_warning"):
			_main._audio_feedback.play_asteroid_warning()
		if _main._visual_feedback != null and _main._visual_feedback.has_method(&"play_asteroid_warning"):
			_main._visual_feedback.play_asteroid_warning()
		if _main._camera != null and _main._camera.has_method(&"add_trauma"):
			_main._camera.add_trauma(0.20)
	_main._wave_announcement.show_announcement(_main.wave + 1, phrase)


## Wave-cleared feedback (Etapa 15 T6): banner, camera zoom pulse, and a short
## invulnerability grace period for the player.
func show_wave_cleared_feedback() -> void:
	_main._hud.show_wave_cleared_banner()
	_main._player.grant_invulnerability(_main.WAVE_CLEARED_INVULNERABILITY)
	if _main._camera == null:
		return
	if _main._zoom_tween != null and _main._zoom_tween.is_valid():
		_main._zoom_tween.kill()
	_main._camera.zoom = Vector2.ONE
	_main._zoom_tween = _main.create_tween()
	_main._zoom_tween.tween_property(_main._camera, "zoom", Vector2.ONE * _main.CAMERA_ZOOM_PULSE, _main.CAMERA_ZOOM_IN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_main._zoom_tween.tween_property(_main._camera, "zoom", Vector2.ONE, _main.CAMERA_ZOOM_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Stops the zoom pulse, returns the camera to its base zoom, and hides the banner.
func reset_wave_cleared_feedback() -> void:
	if _main._zoom_tween != null and _main._zoom_tween.is_valid():
		_main._zoom_tween.kill()
	_main._zoom_tween = null
	if _main._camera != null:
		_main._camera.zoom = Vector2.ONE
	_main._hud.hide_wave_cleared_banner()


func on_wave_announcement_finished() -> void:
	if _main._session_state != _main.SessionState.WAVE_TRANSITION or not _main._session_active:
		return
	if _main._boss_pending:
		_main._boss_pending = false
		_main._boss.start_battle()
		return
	_main.wave = _main._pending_wave_index + 1
	_main._wave_is_clean = true
	_main._hud.set_wave(_main.wave)
	_main._hud_layout.update_hud()
	_main._session_state = _main.SessionState.PLAYING
	_main._enemy_spawner.difficulty_level = _main._chapter
	if local_wave(_main.wave) == _main.BONUS_WAVE_NUMBER:
		start_bonus_wave()
		return
	if local_index(_main._pending_wave_index) == _main.ASTEROID_WAVE_INDEX and _main._asteroid_spawner != null and _main._asteroid_spawner.has_method(&"start_asteroid_wave"):
		_main._enemy_spawner.stop()
		_main._enemy_spawner.clear_formation()
		_main._asteroid_spawner.start_asteroid_wave(24)
		begin_belt_camera_follow()
	else:
		_main._enemy_spawner.start_wave(local_index(_main._pending_wave_index), _main._pending_wave_index)


func is_bonus_wave_active() -> bool:
	return _main._bonus_active


func get_bonus_drops_spawned() -> int:
	return _main._bonus_drops_spawned


## Peaceful wave: no fighters, loot rains down, then the wave is cleared.
func start_bonus_wave() -> void:
	_main._enemy_spawner.stop()
	_main._enemy_spawner.clear_formation()
	_main._bonus_active = true
	_main._bonus_drops_spawned = 0
	_main._session_state = _main.SessionState.BONUS_WAVE
	run_bonus_wave()


func run_bonus_wave() -> void:
	var vp_width: float = _main.get_viewport().get_visible_rect().size.x
	for _i: int in range(_main.BONUS_DROP_COUNT):
		await _main.get_tree().create_timer(_main.bonus_drop_interval).timeout
		if not _main._session_active or not _main._bonus_active:
			return
		var loot_types: Array[int] = [LootDrop.Type.MEDALLION_BLASTER, LootDrop.Type.MEDALLION_MISSILE, LootDrop.Type.MEDALLION_LASER, LootDrop.Type.POWER_ATOM]
		_main._spawn_loot(loot_types[randi() % loot_types.size()], Vector2(randf_range(60.0, vp_width - 60.0), -20.0))
		_main._bonus_drops_spawned += 1
	await _main.get_tree().create_timer(_main.bonus_drop_interval).timeout
	if not _main._session_active or not _main._bonus_active:
		return
	_main._bonus_active = false
	on_wave_cleared(_main.BONUS_WAVE_NUMBER - 1)


## Cinematic jump between chapters: strong starfield warp plus camera trauma.
func perform_hyperspace_jump() -> void:
	_main._hyperspace_jumps += 1
	if _main._starfield != null and _main._starfield.has_method(&"trigger_warp_boost"):
		_main._starfield.trigger_warp_boost(2.5, 18.0)
	if _main._camera != null and _main._camera.has_method(&"add_trauma"):
		_main._camera.add_trauma(0.5)


func get_hyperspace_jump_count() -> int:
	return _main._hyperspace_jumps


func get_chapter() -> int:
	return _main._chapter


func get_total_chapters() -> int:
	return _main.TOTAL_CHAPTERS


func pick_radar_phrase() -> String:
	var index: int = randi() % _main._RADAR_PHRASES.size()
	if index == _main._last_phrase_index and _main._RADAR_PHRASES.size() > 1:
		index = (index + 1) % _main._RADAR_PHRASES.size()
	_main._last_phrase_index = index
	return _main._RADAR_PHRASES[index]


## Etapa 16: the camera follows the ship only while the asteroid belt runs.
func begin_belt_camera_follow() -> void:
	if _main._camera != null and _main._player != null and _main._camera.has_method(&"begin_follow"):
		_main._camera.begin_follow(_main._player)
		# Coop: follow the living ship, or the one moving sideways when both live (Etapa 20).
		if _main._camera.has_method(&"set_follow_candidates"):
			_main._camera.set_follow_candidates([_main._player, _main._player_two])


func end_belt_camera_follow() -> void:
	if _main._camera != null and _main._camera.has_method(&"end_follow"):
		_main._camera.end_follow()


func get_asteroid_spawner() -> Node2D:
	return _main._asteroid_spawner


func is_asteroid_wave_active() -> bool:
	return _main._asteroid_spawner != null and _main._asteroid_spawner.has_method(&"is_wave_active") and _main._asteroid_spawner.is_wave_active()


func start_asteroid_wave_direct(count: int = 4) -> void:
	_main._session_state = _main.SessionState.PLAYING
	_main._enemy_spawner.stop()
	_main._enemy_spawner.clear_formation()
	if _main._asteroid_spawner != null and _main._asteroid_spawner.has_method(&"start_asteroid_wave"):
		_main._asteroid_spawner.start_asteroid_wave(count)
