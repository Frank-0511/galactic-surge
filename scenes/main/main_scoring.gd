# main_scoring.gd
# Scoring of the session: points for kills and asteroids, score milestones (extra
# lives), attribution of points to the ship that earned them (Etapa 20) and the
# feedback of kills, asteroid breaks and enrage warnings.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


## Adds points scaled by the session difficulty score multiplier, then checks extra-life milestones.
## ship: the ship that earned the points; null means J1 (singleplayer and unattributed bonuses).
func add_score(points: int, ship: Node2D = null) -> void:
	var gained: int = int(round(points * _main.DS.score_multiplier(_main.session_difficulty)))
	if ship_for(ship) == _main._player_two and _main._player_two != null:
		_main.score_p2 += gained
		_main._hud.set_score_p2(_main.score_p2)
	else:
		_main.score += gained
	check_score_milestones()


## Nave que corresponde a un atacante: J2 si es _player_two, si no J1.
func ship_for(attacker: Node) -> Node:
	return _main._player_two if attacker != null and attacker == _main._player_two else _main._player


func check_score_milestones() -> void:
	if _main.EXTRA_LIFE_SCORE_THRESHOLD <= 0:
		return
	var current_threshold: int = _main.score / _main.EXTRA_LIFE_SCORE_THRESHOLD
	if current_threshold > _main._last_extra_life_threshold:
		var bonus_lives: int = current_threshold - _main._last_extra_life_threshold
		_main._last_extra_life_threshold = current_threshold
		_main.lives += bonus_lives
		_main._hud.set_lives(_main.lives)
		if _main._visual_feedback != null and _main._visual_feedback.has_method(&"play_extra_life_alert"):
			_main._visual_feedback.play_extra_life_alert(_main._player.global_position)
		if _main._audio_feedback != null and _main._audio_feedback.has_method(&"play_extra_life"):
			_main._audio_feedback.play_extra_life()


func on_player_shot_fired(is_double_shot: bool) -> void:
	if _main._session_active:
		if _main._player != null and _main._audio_feedback != null and _main._audio_feedback.has_method(&"play_weapon_shot"):
			_main._audio_feedback.play_weapon_shot(_main._player.get_weapon() if _main._player.has_method(&"get_weapon") else 0)
		elif _main._audio_feedback != null:
			_main._audio_feedback.play_player_shot(is_double_shot)


func on_enemy_destroyed(enemy: Area2D) -> void:
	if not _main._session_active:
		return
	if enemy.has_method(&"get_variant_id"):
		var variant_id: StringName = enemy.call(&"get_variant_id")
		_main.kills_by_type[variant_id] = int(_main.kills_by_type.get(variant_id, 0)) + 1
	var explosion_position: Vector2 = enemy.global_position
	_main._visual_feedback.play_enemy_explosion(explosion_position)
	if _main._visual_feedback.has_method(&"play_hull_fragments"):
		_main._visual_feedback.play_hull_fragments(explosion_position)
	var multiplier: int = _main._combo_system.register_kill() if (_main._combo_system != null and _main._combo_system.has_method(&"register_kill")) else 1
	var points_earned: int = _main.POINTS_PER_ENEMY * multiplier
	add_score(points_earned, enemy.get("last_attacker") as Node2D if enemy != null else null)
	_main._hud.set_score(_main.score)
	_main._visual_feedback.play_score_popup(explosion_position, points_earned, multiplier > 1)
	_main._audio_feedback.play_enemy_explosion()
	if explosion_position.distance_to(_main._player.global_position) < _main.NEARBY_SHAKE_RADIUS:
		_main._camera.shake(3.0, 0.12)
	_main._try_spawn_enemy_loot(explosion_position)


func on_asteroid_spawned(asteroid: Area2D) -> void:
	if asteroid == null:
		return
	if not asteroid.destroyed.is_connected(on_asteroid_destroyed):
		asteroid.destroyed.connect(on_asteroid_destroyed)
	if not asteroid.player_contacted.is_connected(on_asteroid_player_contacted):
		asteroid.player_contacted.connect(on_asteroid_player_contacted)


func on_asteroid_destroyed(asteroid: Area2D, size_idx: int, pos: Vector2, _vel: Vector2) -> void:
	if not _main._session_active:
		return
	var base_pts: int = _main.ASTEROID_LARGE_POINTS
	var trauma_add: float = 0.35
	match size_idx:
		0: # LARGE
			base_pts = _main.ASTEROID_LARGE_POINTS
			trauma_add = 0.35
		1: # MEDIUM
			base_pts = _main.ASTEROID_MEDIUM_POINTS
			trauma_add = 0.20
		2: # SMALL
			base_pts = _main.ASTEROID_SMALL_POINTS
			trauma_add = 0.10

	var mult: int = _main._combo_system.register_kill() if (_main._combo_system != null and _main._combo_system.has_method(&"register_kill")) else 1
	var points_earned: int = base_pts * mult
	add_score(points_earned, asteroid.get("last_attacker") as Node2D if asteroid != null else null)
	_main._hud.set_score(_main.score)
	_main._visual_feedback.play_score_popup(pos, points_earned, mult > 1)
	_main._visual_feedback.play_enemy_explosion(pos)
	_main._audio_feedback.play_enemy_explosion()
	if _main._camera != null and _main._camera.has_method(&"add_trauma"):
		_main._camera.add_trauma(trauma_add)
	elif _main._camera != null:
		_main._camera.shake(4.0, 0.15)

	# High-HP large asteroids drop resources or power-ups
	if size_idx == 0:
		var has_loot: bool = (asteroid != null and asteroid.get("contains_loot") == true)
		if has_loot or randf() < 0.60:
			_main._spawn_loot(_main._pick_loot_type(), pos)


func on_asteroid_player_contacted(player: Node2D) -> void:
	_main._request_player_damage(player)
	if _main._camera != null and _main._camera.has_method(&"add_trauma"):
		_main._camera.add_trauma(0.50)


func on_asteroid_wave_completed() -> void:
	_main._end_belt_camera_follow()
	if not _main._session_active:
		return
	_main._on_wave_cleared(_main.ASTEROID_WAVE_INDEX)


func on_enrage_triggered() -> void:
	if not _main._session_active:
		return
	if _main._camera != null:
		_main._camera.shake(5.0, 0.25)
	if _main._audio_feedback != null:
		if _main._audio_feedback.has_method(&"play_enrage_warning"):
			_main._audio_feedback.play_enrage_warning()
		elif _main._audio_feedback.has_method(&"play_overheat_warning"):
			_main._audio_feedback.play_overheat_warning()
	if _main._visual_feedback != null:
		if _main._visual_feedback.has_method(&"play_enrage_alert"):
			_main._visual_feedback.play_enrage_alert()
		elif _main._visual_feedback.has_method(&"play_damage_flash"):
			_main._visual_feedback.play_damage_flash()
