# boss_bullet.gd
# Projectile fired by the Boss. Moves along a configurable direction vector
# and notifies when it hits the player. Belongs to enemy_bullets and combat_transients.

extends Area2D

## Emitted once when this projectile hits the player.
signal player_hit(player: Node2D)

## Movement speed in pixels per second.
@export var speed: float = 350.0

## Movement direction vector (normalized before use).
@export var direction: Vector2 = Vector2.DOWN

var _has_hit: bool = false


func _process(delta: float) -> void:
	global_position += direction.normalized() * speed * delta
	var viewport_rect: Rect2 = get_viewport_rect()
	if global_position.y > viewport_rect.end.y + 60.0 \
			or global_position.y < -60.0 \
			or global_position.x < -60.0 \
			or global_position.x > viewport_rect.end.x + 60.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _has_hit or not body.is_in_group(&"player"):
		return
	_has_hit = true
	player_hit.emit(body)
	queue_free()


func _draw() -> void:
	# Outer plasma glow
	draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.15, 0.55, 0.35))
	# Inner glowing bullet core
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.3, 0.7, 0.85))
	draw_circle(Vector2.ZERO, 1.8, Color(1.0, 0.9, 0.95, 1.0))
