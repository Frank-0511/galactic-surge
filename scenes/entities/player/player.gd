# player.gd
# Player ship controller. Handles horizontal movement and shooting.

extends CharacterBody2D

## Movement speed in pixels per second.
@export var speed: float = 400.0

## Scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Margin from the ship center to the screen edge.
const MARGIN: float = 16.0

@onready var _shoot_cooldown: Timer = $ShootCooldown


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	# --- Movement ---
	var direction: float = Input.get_axis("move_left", "move_right")
	velocity = Vector2(direction * speed, 0.0)
	move_and_slide()

	# Clamp to viewport bounds.
	var viewport_rect: Rect2 = get_viewport_rect()
	position.x = clampf(position.x, viewport_rect.position.x + MARGIN, viewport_rect.end.x - MARGIN)

	# --- Shooting ---
	if Input.is_action_pressed("shoot") and _shoot_cooldown.is_stopped():
		_shoot()
		_shoot_cooldown.start()


func _shoot() -> void:
	if bullet_scene == null:
		return
	var bullet: Node = bullet_scene.instantiate()
	bullet.position = global_position + Vector2(0, -20)
	get_tree().current_scene.add_child(bullet)


func _draw() -> void:
	# Draw a simple triangle as a placeholder ship visual.
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0, -16),    # Top (nose)
		Vector2(-14, 16),   # Bottom-left
		Vector2(14, 16),    # Bottom-right
	])
	draw_polygon(points, PackedColorArray([Color(0.2, 0.6, 1.0)]))

	# Draw engine glow.
	draw_rect(Rect2(-4, 12, 8, 8), Color(1.0, 0.5, 0.1))
