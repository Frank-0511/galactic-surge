# player_weapons.gd
# Firing for one Player: the trigger gate per weapon (laser held versus timed shots), the Ion
# Blaster, missile and laser-pulse volleys with their heat and cooldowns, and placement of the
# projectiles under the combat container. Layouts come from player_weapon_patterns.gd.
# Owned by Player through _player.

extends RefCounted

const InputModule: GDScript = preload("res://scenes/entities/player/player_input.gd")
const WeaponPatterns: GDScript = preload("res://scenes/entities/player/player_weapon_patterns.gd")
const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


## Fires according to the trigger: the laser holds a beam while held, other weapons fire on cooldown.
func handle_shooting(delta: float) -> void:
	var shoot_action: String = InputModule.input_action_name("shoot", _player.player_index)
	if _player.current_weapon == _player.WeaponType.LASER:
		if Input.is_action_pressed(shoot_action) and not _player.is_overheated:
			if Input.is_action_just_pressed(shoot_action):
				_player.shot_fired.emit(false)
			_player._set_laser_active(true)
			_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.LASER) * delta)
		else:
			_player._set_laser_active(false)
	else:
		_player._set_laser_active(false)
		if Input.is_action_pressed(shoot_action) and _player._shoot_cooldown.is_stopped() and not _player.is_overheated:
			shoot()


## Fires the current weapon once, unless the barrel is locked by overheat.
func shoot() -> void:
	if _player.is_overheated:
		return
	if _player.current_weapon == _player.WeaponType.BLASTER:
		shoot_blaster()
	elif _player.current_weapon == _player.WeaponType.MISSILE:
		shoot_missile()
	elif _player.current_weapon == _player.WeaponType.LASER:
		shoot_laser_pulse()


func shoot_blaster() -> void:
	var scene: PackedScene = _player.ion_bullet_scene if _player.ion_bullet_scene != null else _player.bullet_scene
	if scene == null:
		return
	var level_index: int = clampi(_player.weapon_level, 1, _player.MAX_WEAPON_LEVEL) - 1
	var pattern: Array = WeaponPatterns.ION_PATTERNS[level_index]
	# Double-shot power-up only affects level 1 (keeps legacy behaviour).
	if _player.weapon_level == 1 and _player._double_shot_enabled:
		pattern = WeaponPatterns.ION_PATTERNS[1]
	for shot: Variant in pattern:
		var shot_arr: Array = shot as Array
		var offset_x: float = float(shot_arr[0])
		var rad: float = deg_to_rad(float(shot_arr[1]))
		var dir: Vector2 = Vector2(sin(rad), -cos(rad))
		var bullet: Area2D = scene.instantiate() as Area2D
		if bullet != null:
			bullet.global_position = _player.global_position + Vector2(offset_x, -20.0)
			bullet.set("shooter", _player)
			if "direction" in bullet:
				bullet.set("direction", dir)
			if "damage" in bullet:
				bullet.set("damage", WeaponPatterns.blaster_damage(_player.weapon_level))
			SESSION_STATS.register_shot()
			add_combat_transient(bullet)
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.BLASTER) * 0.25)
	_player._shoot_cooldown.start(0.25)
	_player.shot_fired.emit(_player._double_shot_enabled or _player.weapon_level >= 2)


func shoot_missile() -> void:
	var scene: PackedScene = _player.missile_scene if _player.missile_scene != null else _player.bullet_scene
	if scene == null:
		return
	var level_index: int = clampi(_player.weapon_level, 1, _player.MAX_WEAPON_LEVEL) - 1
	var offsets: Array = WeaponPatterns.MISSILE_OFFSETS[level_index]

	var candidate_enemies: Array[Node2D] = []
	if _player.get_tree() != null:
		var enemies: Array[Node] = _player.get_tree().get_nodes_in_group(&"enemies")
		for node: Node in enemies:
			if is_instance_valid(node) and (node is Node2D):
				var enemy_node: Node2D = node as Node2D
				if enemy_node.is_inside_tree() and not enemy_node.is_queued_for_deletion() and enemy_node.get("_destroyed") != true:
					candidate_enemies.append(enemy_node)

		candidate_enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return _player.global_position.distance_squared_to(a.global_position) < _player.global_position.distance_squared_to(b.global_position)
		)

	for i in range(offsets.size()):
		var ox: float = float(offsets[i])
		var missile: Area2D = scene.instantiate() as Area2D
		if missile != null:
			missile.global_position = _player.global_position + Vector2(ox, -20.0)
			missile.set("shooter", _player)
			if missile.has_method(&"set_power_level"):
				missile.call(&"set_power_level", _player.weapon_level)
			if candidate_enemies.size() > 0:
				var target_assigned: Node2D = candidate_enemies[i % candidate_enemies.size()]
				if missile.has_method(&"set_target"):
					missile.call(&"set_target", target_assigned)
			SESSION_STATS.register_shot()
			add_combat_transient(missile)

	var legacy_max: int = _player.LEGACY_MAX_LEVEL
	var cooldown: float = lerpf(0.55, 0.35, float(mini(_player.weapon_level, legacy_max) - 1) / float(legacy_max - 1))
	if _player.weapon_level > legacy_max:
		cooldown = lerpf(0.35, 0.28, float(_player.weapon_level - legacy_max) / 5.0)
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.MISSILE) * cooldown)
	_player._shoot_cooldown.start(cooldown)
	_player.shot_fired.emit(false)


func shoot_laser_pulse() -> void:
	_player._set_laser_active(true)
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.LASER) * 0.25)
	_player._shoot_cooldown.start(0.25)
	_player.shot_fired.emit(false)


func spawn_bullet(offset_x: float) -> void:
	var bullet: Node2D = _player.bullet_scene.instantiate() as Node2D
	bullet.global_position = _player.global_position + Vector2(offset_x, -20.0)
	bullet.set("shooter", _player)
	add_combat_transient(bullet)


## Adds a projectile under the current scene (or the parent when there is no tree).
func add_combat_transient(node: Node) -> void:
	var container: Node = _player.get_tree().current_scene if _player.get_tree() != null else null
	if container == null:
		container = _player.get_parent()
	if container != null:
		container.add_child(node)
	else:
		_player.add_child(node)
