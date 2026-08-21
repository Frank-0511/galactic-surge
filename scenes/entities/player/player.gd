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
	# Draw a simple triangle as a placeholder ship visual.
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0, -16),    # Top (nose)
		Vector2(-14, 16),   # Bottom-left
		Vector2(14, 16),    # Bottom-right
	])
	draw_polygon(points, PackedColorArray([Color(0.2, 0.6, 1.0)]))

	# Draw engine glow.
	draw_rect(Rect2(-4, 12, 8, 8), Color(1.0, 0.5, 0.1))
