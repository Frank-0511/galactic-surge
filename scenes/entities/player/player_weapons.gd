# player_weapons.gd
# Firing for one Player: the trigger gate per weapon (laser held versus timed shots), the Ion
# Blaster, missile and laser-pulse volleys with their heat and cooldowns, and placement of the
# projectiles under the combat container. Layouts come from player_weapon_patterns.gd.
# Network (Etapa 20 T2): a remote_driven ship fires from the client's shoot intent and announces each
# volley; replay_volley() shows a host volley on a client as visual-only bullets (no hit, no score, no heat).
# Owned by Player through _player.

extends RefCounted

const InputModule: GDScript = preload("res://scenes/entities/player/player_input.gd")
const WeaponPatterns: GDScript = preload("res://scenes/entities/player/player_weapon_patterns.gd")
const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

var _player: CharacterBody2D
## Remote trigger of the previous frame (remote_driven ships only), to detect a new press.
var _was_held: bool = false
## Replay state: true only while replay_volley() spawns a host volley on this client.
var _replaying: bool = false
var _replay_origin: Vector2 = Vector2.ZERO
var _replay_aim: Vector2 = Vector2.UP
var _replay_level: int = 1
var _replay_double: bool = false


func _init(player: CharacterBody2D) -> void:
	_player = player


## Fires according to the trigger: the laser holds a beam while held, other weapons fire on cooldown.
## A network J2 (remote_driven) takes its trigger from the client's shoot intent, not from local keys.
func handle_shooting(delta: float) -> void:
	var shoot_action: String = InputModule.input_action_name("shoot", _player.player_index)
	var held: bool = _player.remote_shoot if _player.remote_driven else Input.is_action_pressed(shoot_action)
	var just_pressed: bool = (held and not _was_held) if _player.remote_driven else Input.is_action_just_pressed(shoot_action)
	_was_held = held
	if _player.current_weapon == _player.WeaponType.LASER:
		if held and not _player.is_overheated:
			if just_pressed:
				_player.shot_fired.emit(false)
			_player._set_laser_active(true)
			_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.LASER) * delta)
		else:
			_player._set_laser_active(false)
	else:
		_player._set_laser_active(false)
		if held and _player._shoot_cooldown.is_stopped() and not _player.is_overheated:
			shoot()


## Fires the current weapon once, unless the barrel is locked by overheat.
func shoot() -> void:
	if _player.is_overheated:
		return
	_fire(_player.current_weapon)


## Client only (Etapa 20 T2): shows a volley the host fired. The bullets are visual only: they never
## collide, damage, score or change this ship's heat or cooldown.
func replay_volley(weapon: int, level: int, origin: Vector2, aim: Vector2, double_shot: bool) -> void:
	_replaying = true
	_replay_origin = origin
	_replay_aim = aim
	_replay_level = clampi(level, 1, _player.MAX_WEAPON_LEVEL)
	_replay_double = double_shot
	_fire(weapon)
	_replaying = false


func _fire(weapon: int) -> void:
	if weapon == _player.WeaponType.BLASTER:
		shoot_blaster()
	elif weapon == _player.WeaponType.MISSILE:
		shoot_missile()
	elif weapon == _player.WeaponType.LASER:
		shoot_laser_pulse()


func shoot_blaster() -> void:
	var scene: PackedScene = _player.ion_bullet_scene if _player.ion_bullet_scene != null else _player.bullet_scene
	if scene == null:
		return
	var level: int = _level()
	var level_index: int = clampi(level, 1, _player.MAX_WEAPON_LEVEL) - 1
	var pattern: Array = WeaponPatterns.ION_PATTERNS[level_index]
	# Double-shot power-up only affects level 1 (keeps legacy behaviour).
	if level == 1 and _double_shot():
		pattern = WeaponPatterns.ION_PATTERNS[1]
	for shot: Variant in pattern:
		var shot_arr: Array = shot as Array
		var offset_x: float = float(shot_arr[0])
		var rad: float = deg_to_rad(float(shot_arr[1]))
		var dir: Vector2 = _aim().rotated(rad)
		var bullet: Area2D = scene.instantiate() as Area2D
		if bullet != null:
			bullet.global_position = _muzzle() + Vector2(offset_x, -20.0)
			bullet.set("shooter", _player)
			if "direction" in bullet:
				bullet.set("direction", dir)
			if "damage" in bullet:
				bullet.set("damage", WeaponPatterns.blaster_damage(level))
			_add_shot(bullet)
	if _replaying:
		return
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.BLASTER) * 0.25)
	_player._shoot_cooldown.start(0.25)
	_player.shot_fired.emit(_player._double_shot_enabled or _player.weapon_level >= 2)
	_announce(_player.WeaponType.BLASTER, level, _player._double_shot_enabled)


func shoot_missile() -> void:
	var scene: PackedScene = _player.missile_scene if _player.missile_scene != null else _player.bullet_scene
	if scene == null:
		return
	var level: int = _level()
	var level_index: int = clampi(level, 1, _player.MAX_WEAPON_LEVEL) - 1
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
			return _muzzle().distance_squared_to(a.global_position) < _muzzle().distance_squared_to(b.global_position)
		)

	for i in range(offsets.size()):
		var ox: float = float(offsets[i])
		var missile: Area2D = scene.instantiate() as Area2D
		if missile != null:
			missile.global_position = _muzzle() + Vector2(ox, -20.0)
			missile.set("shooter", _player)
			if missile.has_method(&"set_power_level"):
				missile.call(&"set_power_level", level)
			if candidate_enemies.size() > 0:
				var target_assigned: Node2D = candidate_enemies[i % candidate_enemies.size()]
				if missile.has_method(&"set_target"):
					missile.call(&"set_target", target_assigned)
			_add_shot(missile)
	if _replaying:
		return

	var legacy_max: int = _player.LEGACY_MAX_LEVEL
	var cooldown: float = lerpf(0.55, 0.35, float(mini(_player.weapon_level, legacy_max) - 1) / float(legacy_max - 1))
	if _player.weapon_level > legacy_max:
		cooldown = lerpf(0.35, 0.28, float(_player.weapon_level - legacy_max) / 5.0)
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.MISSILE) * cooldown)
	_player._shoot_cooldown.start(cooldown)
	_player.shot_fired.emit(false)
	_announce(_player.WeaponType.MISSILE, level, false)


func shoot_laser_pulse() -> void:
	if _replaying:
		return # The client shows no laser pulse; the held beam is replicated by net_sync_laser.gd (Etapa 20 T36).
	_player._set_laser_active(true)
	_player._heat.add_heat(_player._heat.heat_per_second(_player.WeaponType.LASER) * 0.25)
	_player._shoot_cooldown.start(0.25)
	_player.shot_fired.emit(false)
	_announce(_player.WeaponType.LASER, _player.weapon_level, false)


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


## Adds one projectile. A replayed projectile is visual only: it does not monitor, collide or count as a shot.
func _add_shot(node: Area2D) -> void:
	if _replaying:
		node.set("visual_only", true)
		node.monitoring = false
		node.monitorable = false
	else:
		SESSION_STATS.register_shot()
	add_combat_transient(node)


## Host (not replaying): tells the network sync node about this volley so the client can show it.
func _announce(weapon: int, level: int, double_shot: bool) -> void:
	_player.volley_fired.emit(weapon, level, _player.global_position, Vector2.UP, double_shot)


func _level() -> int:
	return _replay_level if _replaying else _player.weapon_level


func _double_shot() -> bool:
	return _replay_double if _replaying else _player._double_shot_enabled


func _muzzle() -> Vector2:
	return _replay_origin if _replaying else _player.global_position


func _aim() -> Vector2:
	return _replay_aim if _replaying else Vector2.UP
