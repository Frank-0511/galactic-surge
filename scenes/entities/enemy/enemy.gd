# enemy.gd
# Enemy ship that shoots downward and reports collisions to its formation spawner.

extends Area2D

## Emitted once when the enemy has been destroyed.
signal destroyed(enemy: Area2D)

## Emitted when this enemy makes direct contact with the player.
signal player_contacted(player: Node2D)

## Minimum delay in seconds before a shot.
@export var min_shoot_cooldown: float = 1.25

## Maximum delay in seconds before a shot.
@export var max_shoot_cooldown: float = 2.5

## Projectile scene instantiated by this enemy.
@export var enemy_bullet_scene: PackedScene

@onready var _shoot_cooldown: Timer = $ShootCooldown

var _destroyed: bool = false


func _ready() -> void:
	_schedule_next_shot()


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit(self)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Player bullets occupy collision layer 2, which is part of this Area2D mask.
	if _destroyed or (area.collision_layer & 2) == 0:
		return
	destroy()


func _on_body_entered(body: Node2D) -> void:
	if _destroyed or not body.is_in_group("player"):
		return
	player_contacted.emit(body)
	destroy()


func _on_shoot_cooldown_timeout() -> void:
	if _destroyed:
		return
	if enemy_bullet_scene != null:
		var enemy_bullet: Node2D = enemy_bullet_scene.instantiate() as Node2D
		if enemy_bullet != null:
			get_tree().current_scene.add_child(enemy_bullet)
			enemy_bullet.global_position = global_position + Vector2(0, 20)
	_schedule_next_shot()


func _schedule_next_shot() -> void:
	_shoot_cooldown.start(randf_range(min_shoot_cooldown, max_shoot_cooldown))


func _draw() -> void:
	# Subtle glow separates the enemy from the starfield.
	draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.2, 0.3, 0.12))

	# Compact hull and swept wings preserve the existing 36x28 silhouette.
	var wings: PackedVector2Array = PackedVector2Array([
		Vector2(-17, -7), Vector2(-8, -10), Vector2(-4, -4),
		Vector2(4, -4), Vector2(8, -10), Vector2(17, -7),
		Vector2(13, 8), Vector2(6, 5), Vector2(-6, 5), Vector2(-13, 8),
	])
	draw_colored_polygon(wings, Color(0.55, 0.08, 0.18))
	var wing_outline: PackedVector2Array = wings.duplicate()
	wing_outline.append(wings[0])
	draw_polyline(wing_outline, Color(1.0, 0.35, 0.45), 1.25)

	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(-9, -10), Vector2(9, -10), Vector2(12, 3),
		Vector2(7, 12), Vector2(-7, 12), Vector2(-12, 3),
	])
	draw_colored_polygon(hull, Color(0.72, 0.1, 0.2))
	var hull_outline: PackedVector2Array = hull.duplicate()
	hull_outline.append(hull[0])
	draw_polyline(hull_outline, Color(1.0, 0.55, 0.55), 1.5)

	# A restrained bright core gives the enemy a readable focal point.
	draw_circle(Vector2(0, -1), 4.0, Color(1.0, 0.3, 0.35, 0.35))
	draw_circle(Vector2(0, -1), 2.0, Color(1.0, 0.85, 0.55))
	draw_rect(Rect2(-9, 11, 18, 4), Color(0.35, 0.03, 0.1))
