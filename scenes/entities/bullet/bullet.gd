# bullet.gd
# Projectile fired by the player. Moves upward and self-destructs off-screen.

extends Area2D

## Emitted once when this projectile hits an enemy.
signal enemy_hit(enemy: Area2D)

## Movement speed in pixels per second.
@export var speed: float = 600.0

var _has_hit: bool = false


func _process(delta: float) -> void:
	position.y -= speed * delta
	# Self-destruct when off-screen (above viewport).
	if position.y < -50.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _has_hit or not area.is_in_group("enemies"):
		return
	_has_hit = true
	enemy_hit.emit(area)
	queue_free()


func _draw() -> void:
	# Draw a bright rectangle as a placeholder bullet visual.
	draw_rect(Rect2(-2, -6, 4, 12), Color.CYAN)
