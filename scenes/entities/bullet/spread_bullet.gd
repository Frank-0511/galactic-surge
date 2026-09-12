# spread_bullet.gd
# Player spread-shot projectile. Moves along a directed trajectory, deals damage
# to enemies, and self-destructs off-screen.

extends Area2D

## Emitted once when this projectile hits an enemy.
signal enemy_hit(enemy: Area2D)

## Movement speed in pixels per second.
@export var speed: float = 550.0

## Travel direction vector (normalized when moving).
@export var direction: Vector2 = Vector2.UP

## Damage dealt to enemies or bosses.
@export var damage: int = 1

var _has_hit: bool = false
var damage_applied: bool = false


func _ready() -> void:
	if direction != Vector2.ZERO:
		rotation = Vector2.UP.angle_to(direction)


func _process(delta: float) -> void:
	var move_dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.UP
	position += move_dir * speed * delta

	# Self-destruct when off-screen (bounds with safe margin around 720x960 viewport).
	if position.y < -50.0 or position.y > 1020.0 or position.x < -50.0 or position.x > 770.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _has_hit or not area.is_in_group(&"enemies"):
		return
	_has_hit = true
	enemy_hit.emit(area)

	if not damage_applied:
		damage_applied = true
		if area.has_method(&"take_damage"):
			area.call(&"take_damage", damage)
		elif area.has_method(&"destroy"):
			area.call(&"destroy")

	queue_free()


func _draw() -> void:
	# Glowing neon amber/yellow diamond projectile.
	var outer_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0, -9), Vector2(5, 0), Vector2(0, 9), Vector2(-5, 0)
	])
	draw_colored_polygon(outer_poly, Color(1.0, 0.75, 0.15, 0.35))

	var body_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0, -7), Vector2(3.5, 0), Vector2(0, 7), Vector2(-3.5, 0)
	])
	draw_colored_polygon(body_poly, Color(1.0, 0.85, 0.2, 0.95))

	var core_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0, -4), Vector2(1.5, 0), Vector2(0, 4), Vector2(-1.5, 0)
	])
	draw_colored_polygon(core_poly, Color(1.0, 1.0, 0.85, 1.0))
