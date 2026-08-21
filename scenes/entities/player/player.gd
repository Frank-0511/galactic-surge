# player.gd
# Player ship controller. Handles horizontal movement and shooting.

extends CharacterBody2D

signal damage_requested
signal invulnerability_ended

## Movement speed in pixels per second.
@export var speed: float = 400.0

## Scene to instantiate when shooting.
@export var bullet_scene: PackedScene

## Duration in seconds after respawning during which damage is ignored.
@export var invulnerability_duration: float = 1.5

## Interval in seconds between Player visibility changes while invulnerable.
@export var blink_interval: float = 0.15

## Margin from the ship center to the screen edge.
const MARGIN: float = 16.0

@onready var _shoot_cooldown: Timer = $ShootCooldown
@onready var _invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var _blink_timer: Timer = $BlinkTimer

var _is_invulnerable: bool = false
var _gameplay_enabled: bool = true


func _ready() -> void:
	_invulnerability_timer.timeout.connect(_on_invulnerability_timer_timeout)
	_blink_timer.timeout.connect(_on_blink_timer_timeout)


func _process(_delta: float) -> void:
	if not _gameplay_enabled:
		velocity = Vector2.ZERO
		return

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


func take_damage() -> bool:
	if _is_invulnerable or not _gameplay_enabled:
		return false
	damage_requested.emit()
	return true


func respawn(respawn_position: Vector2) -> void:
	position = respawn_position
	_is_invulnerable = true
	visible = true
	_invulnerability_timer.start(invulnerability_duration)
	_blink_timer.start(blink_interval)


func set_gameplay_enabled(enabled: bool) -> void:
	_gameplay_enabled = enabled
	if not _gameplay_enabled:
		velocity = Vector2.ZERO


func _on_invulnerability_timer_timeout() -> void:
	_is_invulnerable = false
	_blink_timer.stop()
	visible = true
	invulnerability_ended.emit()


func _on_blink_timer_timeout() -> void:
	if _is_invulnerable:
		visible = not visible


func _shoot() -> void:
	if bullet_scene == null:
		return
	var bullet: Node = bullet_scene.instantiate()
	bullet.position = global_position + Vector2(0, -20)
	get_tree().current_scene.add_child(bullet)


func _draw() -> void:
	# Soft glow keeps the silhouette readable without changing its footprint.
	var glow: PackedVector2Array = PackedVector2Array([
		Vector2(0, -18), Vector2(-17, 16), Vector2(17, 16),
	])
	draw_colored_polygon(glow, Color(0.15, 0.75, 1.0, 0.16))

	# Dark hull with a crisp retro-neon outline.
	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(0, -16), Vector2(-6, -5), Vector2(-14, 15),
		Vector2(-5, 12), Vector2(0, 16), Vector2(5, 12),
		Vector2(14, 15), Vector2(6, -5),
	])
	draw_colored_polygon(hull, Color(0.08, 0.22, 0.42))
	var hull_outline: PackedVector2Array = hull.duplicate()
	hull_outline.append(hull[0])
	draw_polyline(hull_outline, Color(0.35, 0.9, 1.0), 1.5)

	# Canopy and center seam add a small amount of depth.
	var canopy: PackedVector2Array = PackedVector2Array([
		Vector2(0, -11), Vector2(-4, -3), Vector2(0, 5), Vector2(4, -3),
	])
	draw_colored_polygon(canopy, Color(0.22, 0.75, 0.95))
	draw_polyline(PackedVector2Array([Vector2(0, -10), Vector2(0, 10)]), Color(0.55, 0.95, 1.0, 0.8), 1.0)

	# Twin thrusters remain inside the original visual bounds.
	draw_rect(Rect2(-10, 10, 5, 6), Color(0.95, 0.35, 0.12))
	draw_rect(Rect2(5, 10, 5, 6), Color(0.95, 0.35, 0.12))
	draw_rect(Rect2(-9, 14, 3, 4), Color(1.0, 0.8, 0.25))
	draw_rect(Rect2(6, 14, 3, 4), Color(1.0, 0.8, 0.25))
