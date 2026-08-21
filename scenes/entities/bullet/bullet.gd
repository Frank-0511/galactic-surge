# bullet.gd
# Projectile fired by the player. Moves upward and self-destructs off-screen.

extends Area2D

## Movement speed in pixels per second.
@export var speed: float = 600.0


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	position.y -= speed * delta
	# Self-destruct when off-screen (above viewport).
	if position.y < -50.0:
		queue_free()


func _draw() -> void:
	# Draw a bright rectangle as a placeholder bullet visual.
	draw_rect(Rect2(-2, -6, 4, 12), Color.CYAN)
