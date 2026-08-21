# enemy_bullet.gd
# Projectile fired by enemies. Moves downward and notifies when it hits the player.

extends Area2D

## Emitted once when this projectile hits the player.
signal player_hit(player: Node2D)

## Movement speed in pixels per second.
@export var speed: float = 350.0

var _has_hit: bool = false


func _process(delta: float) -> void:
	position.y += speed * delta
	if position.y > get_viewport_rect().end.y + 50.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _has_hit or not body.is_in_group("player"):
		return
	_has_hit = true
	player_hit.emit(body)
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(-2, -6, 4, 12), Color.ORANGE_RED)
