# enemy_spawner_pressure.gd
# Offensive pressure of the enemy formation: the dive countdown (1-on-1 and pairs), the dive
# launch and the rejoin grace period, and the wave enrage. Owned by EnemySpawner through _spawner.

extends RefCounted

var _spawner: Node2D


func _init(spawner: Node2D) -> void:
	_spawner = spawner


## Dive attack countdown: only ticks down when at least one candidate is in formation.
func tick_dives(delta: float, formation_enemies: Array[Area2D]) -> void:
	if formation_enemies.is_empty():
		return
	_spawner._dive_cooldown_timer -= delta
	if _spawner._dive_cooldown_timer <= 0.0:
		var dive_count: int = 1
		if _spawner._current_wave >= 2 or _spawner._is_enraged:
			dive_count = 2 if randf() < 0.65 else 1
		trigger_dive(dive_count)
		_spawner._dive_cooldown_timer = randf_range(1.6, 2.5) if _spawner._is_enraged else randf_range(3.2, 5.0)


func trigger_dive(count: int = 1) -> Array[Area2D]:
	var candidates: Array[Area2D] = []
	for enemy: Area2D in _spawner._get_valid_enemies():
		if enemy.has_method(&"is_in_formation") and enemy.is_in_formation():
			candidates.append(enemy)

	if candidates.is_empty():
		return []

	# Prioritize lower rows (higher Y)
	candidates.sort_custom(func(a: Area2D, b: Area2D) -> bool:
		return a.global_position.y > b.global_position.y
	)

	var target_pos: Vector2 = Vector2(540.0, 850.0)
	if _spawner.is_inside_tree():
		var players: Array[Node] = _spawner.get_tree().get_nodes_in_group(&"player")
		if not players.is_empty() and is_instance_valid(players[0]) and players[0] is Node2D:
			target_pos = (players[0] as Node2D).global_position

	var selected_count: int = mini(count, candidates.size())
	var attackers: Array[Area2D] = []

	for i: int in range(selected_count):
		var enemy: Area2D = candidates[i]
		var dive_dur: float = 1.6 if _spawner._is_enraged else 2.0
		var enemy_ref: Area2D = enemy
		var slot_getter: Callable = func() -> Vector2:
			return _spawner._slots.get_enemy_slot_position(enemy_ref)

		if enemy.has_method(&"start_dive"):
			enemy.start_dive(target_pos, dive_dur, "swoop", slot_getter)
		if enemy.has_method(&"set_slot_getter"):
			enemy.set_slot_getter(slot_getter)

		var bound_callback: Callable = _on_enemy_returned_to_formation.bind(enemy)
		if not enemy.returned_to_formation.is_connected(bound_callback):
			enemy.returned_to_formation.connect(bound_callback, CONNECT_ONE_SHOT)

		attackers.append(enemy)
		_spawner.enemy_dived.emit(enemy)

	return attackers


func _on_enemy_returned_to_formation(enemy: Area2D) -> void:
	var bound: Callable = _on_enemy_returned_to_formation.bind(enemy)
	if is_instance_valid(enemy):
		if enemy.returned_to_formation.is_connected(bound):
			enemy.returned_to_formation.disconnect(bound)
		elif enemy.returned_to_formation.is_connected(_on_enemy_returned_to_formation):
			enemy.returned_to_formation.disconnect(_on_enemy_returned_to_formation)
	_spawner.formation_rejoined.emit(enemy)
	# Grace period: ensure cooldown is at least 3.8s (or 2.2s if enraged) so player has ample time to shoot
	var min_grace: float = 2.2 if _spawner._is_enraged else 3.8
	_spawner._dive_cooldown_timer = maxf(_spawner._dive_cooldown_timer, min_grace)


func trigger_enrage() -> void:
	if _spawner._is_enraged:
		return
	_spawner._is_enraged = true
	_spawner.formation_speed *= 1.4
	_spawner.enrage_triggered.emit()
	for enemy: Area2D in _spawner._get_valid_enemies():
		if enemy.has_method(&"set_enraged"):
			enemy.set_enraged(true)
