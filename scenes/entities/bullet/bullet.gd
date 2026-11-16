# bullet.gd
# Projectile fired by the player. Moves upward and self-destructs off-screen.

extends Area2D

const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

## Emitted once when this projectile hits an enemy.
signal enemy_hit(enemy: Area2D)

## Movement speed in pixels per second.
@export var speed: float = 600.0

## Ship that fired this bullet; the enemy records it for kill attribution (Etapa 20).
var shooter: Node = null

## True for a client-side replica of a host shot (Etapa 20 T2): it shows the shot and never hits.
var visual_only: bool = false

var _has_hit: bool = false


func _process(delta: float) -> void:
	position.y -= speed * delta
	# Self-destruct when off-screen (above viewport).
	if position.y < -50.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if visual_only or _has_hit or not area.is_in_group("enemies"):
		return
	_has_hit = true
	if area.get("_destroyed") != true:
		SESSION_STATS.register_hit()
	enemy_hit.emit(area)
	queue_free()


func _draw() -> void:
	# Draw a bright rectangle as a placeholder bullet visual.
	draw_rect(Rect2(-2, -6, 4, 12), Color.CYAN)
