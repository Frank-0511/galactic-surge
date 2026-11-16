# enemy_steering.gd
# Steering and charge of one Enemy: evasion of slow player shots, swarm cohesion, flee offset
# bounded over the formation slot, and the straight accelerating suicide charge.
# Owned by Enemy through _enemy.

extends RefCounted

const EnemyAI: Script = preload("res://scripts/components/enemy_ai.gd")

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


## Applies evasion, swarm and flee steering as a bounded offset over the formation slot.
func update_steering(delta: float) -> void:
	var old_offset: Vector2 = _enemy._ai_offset
	var offset: Vector2 = _enemy._ai_offset
	var steering_active: bool = false

	var evasion_speed: float = float(_enemy._variant_def.get("evasion_speed", 0.0))
	if evasion_speed > 0.0 and _enemy.is_inside_tree():
		var dodge: float = EnemyAI.compute_evasion_direction(_enemy.global_position, collect_slow_projectiles())
		if dodge != 0.0:
			offset.x += dodge * evasion_speed * delta
			steering_active = true

	if bool(_enemy._variant_def.get("swarm", false)) and _enemy.is_inside_tree():
		var steer: Vector2 = EnemyAI.compute_swarm_steering(_enemy.global_position, collect_swarm_neighbors())
		if steer != Vector2.ZERO:
			offset += steer * 70.0 * delta
			steering_active = true

	var fleeing: bool = _enemy._ai != null and _enemy._ai.is_fleeing()
	if fleeing:
		var threat: Variant = _enemy._tactics.get_target_position()
		var flee_dir: Vector2 = EnemyAI.compute_flee_direction(_enemy.global_position, threat if threat is Vector2 else _enemy.global_position + Vector2.DOWN)
		offset += flee_dir * 120.0 * delta
		steering_active = true

	if not steering_active:
		offset = offset.move_toward(Vector2.ZERO, 60.0 * delta)

	if fleeing:
		offset = offset.limit_length(_enemy.MAX_FLEE_OFFSET)
	else:
		offset.x = clampf(offset.x, -_enemy.MAX_AI_OFFSET_X, _enemy.MAX_AI_OFFSET_X)
		offset.y = clampf(offset.y, -_enemy.MAX_AI_OFFSET_Y, _enemy.MAX_AI_OFFSET_Y)

	_enemy._ai_offset = offset
	var applied: Vector2 = offset - old_offset
	if applied != Vector2.ZERO:
		_enemy.position += applied


func collect_slow_projectiles() -> Array:
	var projectiles: Array = []
	for node: Node in _enemy.get_tree().get_nodes_in_group(&"player_bullets"):
		if is_instance_valid(node) and node is Node2D and node.has_method(&"get_projectile_velocity"):
			projectiles.append({
				"position": (node as Node2D).global_position,
				"velocity": node.call(&"get_projectile_velocity"),
			})
	return projectiles


func collect_swarm_neighbors() -> Array:
	var neighbors: Array = []
	for node: Node in _enemy.get_tree().get_nodes_in_group(&"enemies"):
		if node == _enemy or not is_instance_valid(node) or not (node is Node2D):
			continue
		var other: Node2D = node as Node2D
		if other.has_method(&"get_variant_id") and other.call(&"get_variant_id") == _enemy.variant_id:
			neighbors.append(other.global_position)
	return neighbors


## Begins a straight, accelerating charge toward target_pos (suicide variants).
func start_charge(target_pos: Vector2) -> void:
	if _enemy._destroyed:
		return
	_enemy._state = _enemy.State.CHARGING
	_enemy._is_flying_in = false
	_enemy._ai_offset = Vector2.ZERO
	_enemy._charge_elapsed = 0.0
	var dir: Vector2 = target_pos - _enemy.global_position
	_enemy._charge_direction = dir.normalized() if dir.length_squared() > 1.0 else Vector2.DOWN
	if _enemy._shoot_cooldown != null:
		_enemy._shoot_cooldown.stop()
	_enemy.charge_started.emit()


func process_charging(delta: float) -> void:
	_enemy._charge_elapsed += delta
	var target: Variant = _enemy._tactics.get_target_position()
	if target is Vector2:
		var desired: Vector2 = ((target as Vector2) - _enemy.global_position).normalized()
		if desired != Vector2.ZERO:
			var angle: float = rotate_toward(_enemy._charge_direction.angle(), desired.angle(), 1.6 * delta)
			_enemy._charge_direction = Vector2.from_angle(angle)
	# Overloaded engines: ramp from 50% to 100% of charge speed over 0.6 s.
	var ramp: float = clampf(0.5 + _enemy._charge_elapsed / 1.2, 0.5, 1.0)
	var speed: float = float(_enemy._variant_def.get("charge_speed", 500.0)) * ramp
	_enemy.global_position += _enemy._charge_direction * speed * delta
	_enemy.rotation = Vector2.DOWN.angle_to(_enemy._charge_direction)

	var vp_rect: Rect2 = _enemy.get_viewport_rect() if _enemy.is_inside_tree() else Rect2(0, 0, 1080, 960)
	if _enemy.global_position.y > vp_rect.size.y + 40.0 or _enemy.global_position.x < -80.0 or _enemy.global_position.x > vp_rect.size.x + 80.0:
		_enemy.rotation = 0.0
		_enemy._charge_cooldown = randf_range(4.0, 6.0)
		if _enemy._slot_getter.is_valid():
			_enemy.global_position = Vector2(clampf(_enemy.global_position.x, 60.0, vp_rect.size.x - 60.0), -30.0)
			_enemy._motion.return_to_slot(_enemy._slot_getter, 1.8)
		else:
			_enemy.destroy()
