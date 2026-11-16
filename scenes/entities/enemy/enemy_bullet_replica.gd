# enemy_bullet_replica.gd
# Visual-only flight of an enemy bullet replica (Etapa 20 T5). The host's spawn event gives the variant, origin,
# launch velocity and gravity; step() integrates them like the host bullet and keeps its trail. No fuse, split,
# detonation or hit: the host's removal event ends the replica. Used by NetSyncBullets; no node owns it.

extends RefCounted


## Sets the replica's variant, origin and launch state. Call after the bullet is in the tree.
static func configure(bullet: Area2D, variant: int, origin: Vector2, launch: Vector2, gravity_value: float) -> void:
	bullet.set("plasma_variant", variant)
	bullet.set("ballistic_gravity", gravity_value)
	bullet.set("velocity", launch)
	bullet.set("initial_velocity", launch)
	bullet.global_position = origin
	var trail: Array[Vector2] = [origin]
	bullet.set("_trail_points", trail)


## One frame of the replica: the host's integration, the trail, and off-screen cleanup.
static func step(bullet: Area2D, delta: float) -> void:
	var velocity: Vector2 = bullet.get("velocity")
	velocity.y += float(bullet.call("get_effective_gravity")) * delta
	bullet.set("velocity", velocity)
	bullet.position += velocity * delta
	bullet.call("update_trail", delta)
	var rect: Rect2 = bullet.get_viewport_rect() if bullet.is_inside_tree() else Rect2(0, 0, 1080, 960)
	if bullet.position.x < -150.0 or bullet.position.x > rect.size.x + 150.0 or bullet.position.y < -200.0:
		bullet.queue_free()
		return
	bullet.queue_redraw()
