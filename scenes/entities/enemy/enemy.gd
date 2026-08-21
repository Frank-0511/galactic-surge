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
	draw_rect(Rect2(-18, -12, 36, 24), Color.CRIMSON)
	draw_rect(Rect2(-10, 12, 20, 4), Color.DARK_RED)
