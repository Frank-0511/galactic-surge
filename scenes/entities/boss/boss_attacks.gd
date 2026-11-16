# boss_attacks.gd
# Attack patterns of the Boss: Nexus phase 1 and phase 2 volleys, the Espectro fan and ring volleys,
# bullet spawning, the first-alive-ship lookup and shoot-timer scheduling. Owned by Boss through _boss;
# the shoot timer, the cycle counters and the Espectro/Nexus constants stay on Boss.

extends RefCounted

const PlayerShip: Script = preload("res://scenes/entities/player/player.gd")

var _boss: Area2D


func _init(boss: Area2D) -> void:
	_boss = boss


## Shoot timer callback: fires the volley of the current variant and phase.
func on_shoot_timer_timeout() -> void:
	if _boss._is_defeated or _boss._is_entering or _boss.boss_bullet_scene == null:
		return

	if _boss.boss_variant == &"espectro":
		fire_spectre_volley()
		return

	if not _boss.is_enraged:
		# Phase 1: Alternate between dual heavy cannons and aimed shot
		if (_boss._shoot_cycle_phase1 % 2) == 0:
			# Pattern A: Dual heavy shot
			spawn_bullet(Vector2(-36, 32), Vector2.DOWN, 360.0)
			spawn_bullet(Vector2(36, 32), Vector2.DOWN, 360.0)
		else:
			# Pattern B: Aimed shot from central cannon
			var player: Node2D = get_player_node()
			var aim_dir: Vector2 = Vector2.DOWN
			if player != null:
				var to_player: Vector2 = _boss.global_position.direction_to(player.global_position)
				if to_player.length_squared() > 0.0001:
					aim_dir = to_player.normalized()
			spawn_bullet(Vector2(0, 36), aim_dir, 370.0, true)
		_boss._shoot_cycle_phase1 += 1
		schedule_shoot(0.75)
	else:
		# Phase 2: Alternate between 5-bullet fan spread and dual fast aimed shots
		if (_boss._shoot_cycle_phase2 % 2) == 0:
			# Pattern A: 5-bullet fan spread (-30°, -15°, 0°, +15°, +30°)
			var angles: Array[float] = [-30.0, -15.0, 0.0, 15.0, 30.0]
			for angle_deg: float in angles:
				var spread_dir: Vector2 = Vector2.DOWN.rotated(deg_to_rad(angle_deg))
				spawn_bullet(Vector2(0, 36), spread_dir, 400.0)
		else:
			# Pattern B: Fast dual aimed shots from lateral turrets
			var player: Node2D = get_player_node()
			var aim_dir: Vector2 = Vector2.DOWN
			if player != null:
				var to_player: Vector2 = _boss.global_position.direction_to(player.global_position)
				if to_player.length_squared() > 0.0001:
					aim_dir = to_player.normalized()
			spawn_bullet(Vector2(-36, 32), aim_dir, 420.0, true)
			spawn_bullet(Vector2(36, 32), aim_dir, 420.0, true)
		_boss._shoot_cycle_phase2 += 1
		schedule_shoot(0.5)


# Espectro attack: fan of 5 aimed at the player, then a radial ring of 8, alternating.
func fire_spectre_volley() -> void:
	if (_boss._shoot_cycle_spectre % 2) == 0:
		var player: Node2D = get_player_node()
		var aim_dir: Vector2 = Vector2.DOWN
		if player != null:
			var to_player: Vector2 = _boss.global_position.direction_to(player.global_position)
			if to_player.length_squared() > 0.0001:
				aim_dir = to_player.normalized()
		for fan_index: int in _boss.SPECTRE_FAN_BULLET_COUNT:
			var fan_angle: float = lerpf(-30.0, 30.0, float(fan_index) / float(_boss.SPECTRE_FAN_BULLET_COUNT - 1))
			spawn_bullet(Vector2(0, 36), aim_dir.rotated(deg_to_rad(fan_angle)), _boss.SPECTRE_FAN_BULLET_SPEED, true)
	else:
		for ring_index: int in _boss.SPECTRE_RING_BULLET_COUNT:
			var ring_angle: float = TAU * float(ring_index) / float(_boss.SPECTRE_RING_BULLET_COUNT)
			spawn_bullet(Vector2.ZERO, Vector2.RIGHT.rotated(ring_angle), _boss.SPECTRE_RING_BULLET_SPEED, true)
	_boss._shoot_cycle_spectre += 1
	schedule_shoot(_boss.SPECTRE_ENRAGED_VOLLEY_INTERVAL if _boss.is_enraged else _boss.SPECTRE_VOLLEY_INTERVAL)


## First living ship of the player group, or null when the boss is outside the tree or none is alive.
func get_player_node() -> Node2D:
	if _boss.is_inside_tree():
		var player: Node2D = PlayerShip.first_alive_ship(_boss.get_tree())
		if player != null and is_instance_valid(player):
			return player
	return null


func spawn_bullet(offset: Vector2, dir: Vector2, bullet_speed: float, is_world_dir: bool = false) -> void:
	var bullet: Area2D = _boss.boss_bullet_scene.instantiate() as Area2D
	if bullet == null:
		return
	bullet.global_position = _boss.global_position + offset.rotated(_boss.rotation)
	var final_dir: Vector2 = dir if is_world_dir else dir.rotated(_boss.rotation)
	if "direction" in bullet:
		bullet.set("direction", final_dir)
	if "speed" in bullet:
		bullet.set("speed", bullet_speed)
	var parent_node: Node = _boss.get_parent()
	if parent_node != null:
		parent_node.add_child(bullet)
	else:
		_boss.get_tree().current_scene.add_child(bullet)


func schedule_shoot(delay: float) -> void:
	if _boss._shoot_timer != null and not _boss._is_defeated:
		_boss._shoot_timer.start(delay)
