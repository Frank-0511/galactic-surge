# enemy_spawner_formation.gd
# Spawn, teardown and stop of the enemy formation: builds the slot grid, instantiates one enemy
# per slot with its variant, bullet mix and fire rate, wires the enemy signals, and starts each
# fly-in or places the enemy directly. Owned by EnemySpawner through _spawner.

extends RefCounted

const FormationPatterns: Script = preload("res://scripts/systems/formation_patterns.gd")

var _spawner: Node2D


func _init(spawner: Node2D) -> void:
	_spawner = spawner


func spawn_formation() -> void:
	clear_formation()
	if _spawner.enemy_scene == null:
		return

	var vp_rect: Rect2 = _spawner.get_viewport_rect() if _spawner.is_inside_tree() else Rect2(0, 0, 1080, 960)
	if vp_rect.size == Vector2.ZERO:
		vp_rect = Rect2(0, 0, 1080, 960)

	var origin: Vector2 = _spawner._formation_origin
	if origin == Vector2.ZERO:
		origin = Vector2(vp_rect.get_center().x, _spawner._first_row_y)

	var pattern: int = FormationPatterns.pattern_from_string(_spawner._current_pattern_type)
	var slots: Array[Vector2] = FormationPatterns.calculate_slots(
		pattern, _spawner.rows, _spawner.columns, _spawner.horizontal_spacing, _spawner.vertical_spacing,
		origin, _spawner.formation_rotation
	)

	var should_fly_in: bool = _spawner.fly_in_enabled and _spawner.fly_in_duration > 0.0
	_spawner._is_flying_in = should_fly_in
	_spawner._flying_in_count = 0
	_spawner._enemy_base_slots.clear()
	_spawner._formation_shift = Vector2.ZERO
	_spawner._wave_timer = 0.0
	_spawner._is_enraged = false
	_spawner._dive_cooldown_timer = 3.5

	var wave_config: Dictionary = _spawner._current_config if not _spawner._current_config.is_empty() else _spawner.get_wave_config(_spawner._current_wave)
	var wave_variants: Dictionary = wave_config.get("variants", {}) if _spawner.ENEMY_AI_ENABLED else {}
	var variant_slots: Dictionary = _spawner._slots.assign_variant_slots(wave_variants, slots.size())
	for i: int in range(slots.size()):
		var slot_pos: Vector2 = slots[i]
		var enemy: Area2D = _spawner.enemy_scene.instantiate() as Area2D
		if enemy == null:
			continue
		if variant_slots.has(i) and enemy.has_method(&"apply_variant"):
			enemy.call(&"apply_variant", variant_slots[i])
		if enemy.has_method(&"set_bullet_mix"):
			enemy.call(&"set_bullet_mix", wave_config.get("bullet_mix", []), wave_config.get("enraged_bullet_mix", []))
		if enemy.has_method(&"set_fire_rate_scale"):
			enemy.call(&"set_fire_rate_scale", float(wave_config.get("fire_rate_scale", 1.0)))
		_spawner.add_child(enemy)
		enemy.player_contacted.connect(_on_enemy_player_contacted)
		enemy.destroyed.connect(_on_enemy_destroyed)
		_spawner._alive_count += 1
		_spawner._enemy_base_slots[enemy] = slot_pos
		if variant_slots.has(i) and enemy.has_method(&"set_slot_getter"):
			var variant_enemy: Area2D = enemy
			enemy.call(&"set_slot_getter", func() -> Vector2:
				return _spawner._slots.get_enemy_slot_position(variant_enemy))

		if should_fly_in:
			_spawner._flying_in_count += 1
			var points: Array[Vector2] = _spawner._slots.generate_bezier_points(_spawner._current_trajectory, slot_pos, i, vp_rect)
			var delay: float = 0.06 * float(i)
			enemy.global_position = points[0]
			if enemy.has_signal(&"fly_in_completed"):
				enemy.fly_in_completed.connect(_on_enemy_fly_in_completed)
			if enemy.has_method(&"start_fly_in"):
				enemy.start_fly_in(points[0], points[1], points[2], points[3], _spawner.fly_in_duration, delay)
		else:
			enemy.global_position = slot_pos

	_spawner._direction = 1.0
	_spawner._is_running = true
	_spawner.set_process(true)


func clear_formation() -> void:
	for enemy: Area2D in _spawner._get_valid_enemies():
		_spawner.remove_child(enemy)
		enemy.queue_free()
	_spawner._alive_count = 0
	_spawner._flying_in_count = 0
	_spawner._is_flying_in = false
	_spawner._wave_cleared_emitted = false
	_spawner._enemy_base_slots.clear()
	_spawner._formation_shift = Vector2.ZERO
	_spawner._wave_timer = 0.0
	_spawner._is_enraged = false
	_spawner._dive_cooldown_timer = 3.5


func stop() -> void:
	_spawner._is_running = false
	_spawner._is_flying_in = false
	_spawner.set_process(false)
	for enemy: Area2D in _spawner._get_valid_enemies():
		if enemy.has_method(&"cancel_fly_in"):
			enemy.cancel_fly_in()
		var shoot_cooldown: Timer = enemy.get_node_or_null("ShootCooldown") as Timer
		if shoot_cooldown != null:
			shoot_cooldown.stop()


func _on_enemy_player_contacted(player: Node2D) -> void:
	_spawner.enemy_contacted_player.emit(player)


func _on_enemy_fly_in_completed() -> void:
	_spawner._flying_in_count -= 1
	if _spawner._flying_in_count <= 0 and _spawner._is_flying_in:
		_spawner._is_flying_in = false
		_spawner.fly_in_completed_all.emit()


func _on_enemy_destroyed(enemy: Area2D) -> void:
	_spawner._enemy_base_slots.erase(enemy)
	if _spawner._is_flying_in:
		_spawner._flying_in_count -= 1
		if _spawner._flying_in_count <= 0:
			_spawner._is_flying_in = false
			_spawner.fly_in_completed_all.emit()
	_spawner.enemy_destroyed.emit(enemy)
	_spawner._alive_count -= 1
	if _spawner._alive_count <= 0 and not _spawner._wave_cleared_emitted:
		_spawner._wave_cleared_emitted = true
		_spawner.wave_cleared.emit(_spawner._current_wave)
		if _spawner._current_wave == _spawner.get_total_waves() - 1:
			_spawner.all_waves_cleared.emit()
