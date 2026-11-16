# enemy_damage.gd
# Damage and destruction of one Enemy: the frontal deflector multiplier, projectile and fractional
# damage, death, and the area/body contact handlers (player bullets and player contact).
# Owned by Enemy through _enemy.

extends RefCounted

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


## Damage multiplier for a projectile travelling along travel_direction.
## Frontal hits are attenuated by the deflector; flank hits are not.
func get_deflector_multiplier(travel_direction: Vector2) -> float:
	if not _enemy.has_deflector() or travel_direction == Vector2.ZERO:
		return 1.0
	var facing: Vector2 = Vector2.DOWN.rotated(_enemy.rotation)
	var incoming_from: Vector2 = -travel_direction.normalized()
	var half_cone: float = deg_to_rad(float(_enemy._variant_def.get("deflector_cone_deg", 60.0)) * 0.5)
	if absf(facing.angle_to(incoming_from)) <= half_cone:
		return float(_enemy._variant_def.get("deflector_multiplier", 0.25))
	return 1.0


## Applies projectile damage honoring the frontal deflector.
func take_damage_from(amount: float, travel_direction: Vector2) -> void:
	if _enemy._destroyed or _enemy.replica or amount <= 0.0:
		return
	var multiplier: float = get_deflector_multiplier(travel_direction)
	if multiplier < 1.0:
		_enemy.deflected.emit(amount * (1.0 - multiplier))
	take_damage(amount * multiplier)


## Applies damage (fractional values allowed, used by the continuous laser).
func take_damage(amount: float = 1.0) -> void:
	if _enemy._destroyed or _enemy.replica or amount <= 0.0:
		return
	_enemy.health = maxf(0.0, _enemy.health - amount)
	_enemy._hit_flash_timer = _enemy.HIT_FLASH_DURATION
	_enemy.damaged.emit(_enemy.health, _enemy.max_health)
	_enemy.queue_redraw()
	if is_zero_approx(_enemy.health) or _enemy.health <= 0.0:
		_enemy.health = 0.0
		destroy()


func destroy() -> void:
	if _enemy._destroyed:
		return
	_enemy._destroyed = true
	_enemy._is_flying_in = false
	_enemy.destroyed.emit(_enemy)
	_enemy.queue_free()


func on_area_entered(area: Area2D) -> void:
	# Player bullets occupy collision layer 2, which is part of this Area2D mask.
	if _enemy._destroyed or _enemy.replica or (area.collision_layer & 2) == 0:
		return
	# Continuous beams apply their own damage over time.
	if area.has_method(&"is_beam"):
		return
	# Projectiles that apply their own damage (ion bullet, missile) handle it themselves.
	if "damage_applied" in area or "damage" in area:
		return
	# Legacy linear bullet: one hit (travels along its direction, upward by default).
	var travel: Vector2 = area.get("direction") if "direction" in area else Vector2.UP
	if "shooter" in area and area.get("shooter") != null:
		_enemy.last_attacker = area.get("shooter")
	take_damage_from(1.0, travel)


func on_body_entered(body: Node2D) -> void:
	if _enemy._destroyed or _enemy.replica or not body.is_in_group("player"):
		return
	_enemy.player_contacted.emit(body)
	destroy()
