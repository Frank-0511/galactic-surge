# spread_bullet.gd
# Player spread-shot projectile. Moves along a directed trajectory, deals damage
# to enemies, and self-destructs off-screen.

extends Area2D

const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

## Emitted once when this projectile hits an enemy.
signal enemy_hit(enemy: Area2D)

## Movement speed in pixels per second.
@export var speed: float = 550.0

## Travel direction vector (normalized when moving).
@export var direction: Vector2 = Vector2.UP

## Damage dealt to enemies or bosses.
@export var damage: int = 1

## Ship that fired this bullet; the hit target records it for kill attribution (Etapa 20).
var shooter: Node = null

## True for a client-side replica of a host shot (Etapa 20 T2): it shows the shot and never hits.
var visual_only: bool = false

var _has_hit: bool = false
var damage_applied: bool = false


func _ready() -> void:
	if direction != Vector2.ZERO:
		rotation = Vector2.UP.angle_to(direction)


func _process(delta: float) -> void:
	var move_dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.UP
	global_position += move_dir * speed * delta

	# Self-destruct when off-screen (dynamic viewport bounds with safe margin).
	var max_x: float = 1180.0
	var max_y: float = 1060.0
	if is_inside_tree():
		var vp: Rect2 = get_viewport_rect()
		if vp.size.x > 0.0:
			max_x = vp.end.x + 80.0
			max_y = vp.end.y + 80.0
	if global_position.y < -80.0 or global_position.y > max_y or global_position.x < -80.0 or global_position.x > max_x:
		queue_free()



func _on_area_entered(area: Area2D) -> void:
	if visual_only or _has_hit or not area.is_in_group(&"enemies"):
		return
	_has_hit = true
	enemy_hit.emit(area)

	if not damage_applied:
		damage_applied = true
		if shooter != null:
			area.set("last_attacker", shooter)
		if area.has_method(&"take_damage_from"):
			area.call(&"take_damage_from", float(damage), direction)
			SESSION_STATS.register_hit()
		elif area.has_method(&"take_damage"):
			area.call(&"take_damage", damage)
			SESSION_STATS.register_hit()
		elif area.has_method(&"destroy"):
			area.call(&"destroy")
			SESSION_STATS.register_hit()

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
