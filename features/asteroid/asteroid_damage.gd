# asteroid_damage.gd
# Health, damage and destruction of one Asteroid: applies integer and fractional damage, emits
# damaged/destroyed, and resolves the collision rules for player contact and bullet hits.
# Owned by Asteroid through _asteroid; state, signals and exports stay on Asteroid.

extends RefCounted

var _asteroid: Asteroid


func _init(asteroid: Asteroid) -> void:
	_asteroid = asteroid


## Accepts damage, reducing current_health. Triggers destroy() if depleted.
func take_damage(amount: int) -> bool:
	if _asteroid._destroyed or amount <= 0:
		return false

	_asteroid.current_health = maxi(0, _asteroid.current_health - amount)
	_asteroid._hit_flash_timer = 0.08
	_asteroid.damaged.emit(_asteroid.current_health, _asteroid.max_health)
	_asteroid.queue_redraw()

	if _asteroid.current_health <= 0:
		destroy()
		return true
	return false


## Rounds fractional damage (laser ticks, splash) to at least one point and applies it.
func take_damage_from(amount: float) -> bool:
	var rounded_damage: int = maxi(1, int(round(amount)))
	return take_damage(rounded_damage)


## Destroys the asteroid once: emits destroyed, spawns fragments and frees the node.
func destroy() -> void:
	if _asteroid._destroyed:
		return
	_asteroid._destroyed = true

	_asteroid.destroyed.emit(_asteroid, int(_asteroid.asteroid_size), _asteroid.global_position, _asteroid.linear_velocity)
	_asteroid.split()
	_asteroid.queue_free()


## Player contact destroys the rock and emits player_contacted for the listener.
func on_body_entered(body: Node2D) -> void:
	if _asteroid._destroyed:
		return
	if body.is_in_group(&"player"):
		# Damage is applied by the listener (Main) through player_contacted,
		# so the player is hit exactly once per collision.
		_asteroid.player_contacted.emit(body)
		destroy()


## Bullet contact deals one point; beams and self-damaging projectiles are ignored here.
func on_area_entered(area: Area2D) -> void:
	if _asteroid._destroyed:
		return
	# Beams handle their own tick rate and damage application
	if area.has_method(&"is_beam"):
		return
	# Projectiles that apply their own damage handle it themselves
	if "damage_applied" in area or "damage" in area:
		return
	# Generic bullet contact
	if area.collision_layer & 2 != 0 or area.is_in_group(&"bullets"):
		take_damage(1)
