# boss.gd
# Final boss entity ("Nave Nodriza Nexus") for Etapa 5.
# Autonomous Area2D in group "enemies" with vector neon art, phase-based attack patterns,
# hit flash feedback, dynamic core pulse, and health-based defeat signaling.

extends Area2D

## Emitted when current health changes.
signal health_changed(current: int, max_health: int)

## Emitted once when the boss reaches 0 health.
signal boss_defeated(boss: Area2D)

## Emitted when the boss makes direct physical contact with the player ship.
signal boss_contacted_player(player: Node2D)

## Maximum health points.
@export var max_health: int = 30

## Projectile scene used for boss attacks.
@export var boss_bullet_scene: PackedScene = preload("res://scenes/entities/boss/boss_bullet.tscn")

## Current health points.
var health: int = 30
var current_health: int = 30

## Whether the boss has entered Phase 2 (enraged).
var is_enraged: bool = false

@onready var _shoot_timer: Timer = $ShootTimer

var _is_defeated: bool = false
var _is_entering: bool = true
var _target_y: float = 140.0
var _time: float = 0.0
var _hit_flash_time: float = 0.0
var _move_direction: float = 1.0
var _left_margin: float = 110.0
var _right_margin: float = 610.0


func _ready() -> void:
	health = max_health
	current_health = max_health
	if _shoot_timer != null:
		_shoot_timer.timeout.connect(_on_shoot_timer_timeout)


func _process(delta: float) -> void:
	_time += delta
	if _hit_flash_time > 0.0:
		_hit_flash_time = maxf(0.0, _hit_flash_time - delta)

	if _is_entering:
		global_position.y += 150.0 * delta
		if global_position.y >= _target_y:
			global_position.y = _target_y
			_is_entering = false
			_schedule_shoot(1.1)
	else:
		var speed: float = 160.0 if is_enraged else 110.0
		global_position.x += _move_direction * speed * delta
		if global_position.x <= _left_margin:
			global_position.x = _left_margin
			_move_direction = 1.0
		elif global_position.x >= _right_margin:
			global_position.x = _right_margin
			_move_direction = -1.0

	queue_redraw()


func take_damage(amount: int = 1) -> void:
	if _is_defeated:
		return
	health = maxi(0, health - amount)
	current_health = health
	_hit_flash_time = 0.12

	if health <= 15 and not is_enraged:
		is_enraged = true
		if _shoot_timer != null:
			_shoot_timer.wait_time = 0.85

	health_changed.emit(health, max_health)
	queue_redraw()

	if health == 0:
		_is_defeated = true
		if _shoot_timer != null:
			_shoot_timer.stop()
		boss_defeated.emit(self)
		queue_free()


func _on_shoot_timer_timeout() -> void:
	if _is_defeated or _is_entering or boss_bullet_scene == null:
		return

	if not is_enraged:
		# Phase 1: dual straight cannons
		_spawn_bullet(Vector2(-36, 32), Vector2.DOWN, 340.0)
		_spawn_bullet(Vector2(36, 32), Vector2.DOWN, 340.0)
		_schedule_shoot(1.1)
	else:
		# Phase 2: triple spread (center, -20 deg, +20 deg)
		var angle_rad: float = deg_to_rad(20.0)
		var left_dir: Vector2 = Vector2(-sin(angle_rad), cos(angle_rad))
		var right_dir: Vector2 = Vector2(sin(angle_rad), cos(angle_rad))
		_spawn_bullet(Vector2(0, 36), Vector2.DOWN, 380.0)
		_spawn_bullet(Vector2(-36, 32), left_dir, 380.0)
		_spawn_bullet(Vector2(36, 32), right_dir, 380.0)
		_schedule_shoot(0.85)


func _spawn_bullet(offset: Vector2, dir: Vector2, bullet_speed: float) -> void:
	var bullet: Area2D = boss_bullet_scene.instantiate() as Area2D
	if bullet == null:
		return
	bullet.global_position = global_position + offset
	if "direction" in bullet:
		bullet.set("direction", dir)
	if "speed" in bullet:
		bullet.set("speed", bullet_speed)
	var parent_node: Node = get_parent()
	if parent_node != null:
		parent_node.add_child(bullet)
	else:
		get_tree().current_scene.add_child(bullet)


func _schedule_shoot(delay: float) -> void:
	if _shoot_timer != null and not _is_defeated:
		_shoot_timer.start(delay)


func _on_area_entered(area: Area2D) -> void:
	if _is_defeated:
		return
	# Player bullet layer is 2
	if (area.collision_layer & 2) != 0 or area.is_in_group(&"player_bullets"):
		take_damage(1)


func _on_body_entered(body: Node2D) -> void:
	if _is_defeated:
		return
	if body.is_in_group(&"player"):
		boss_contacted_player.emit(body)


func _draw() -> void:
	var pulse_speed: float = 9.0 if is_enraged else 4.0
	var core_pulse: float = 0.5 + 0.5 * sin(_time * pulse_speed)

	var neon_primary: Color = Color(1.0, 0.22, 0.48) if is_enraged else Color(0.22, 0.9, 1.0)
	var neon_secondary: Color = Color(1.0, 0.6, 0.1) if is_enraged else Color(0.68, 0.28, 1.0)
	var hull_color: Color = Color(0.08, 0.04, 0.16)

	# 1. Soft atmospheric threat glow
	draw_circle(Vector2.ZERO, 65.0 + 8.0 * core_pulse, Color(neon_primary.r, neon_primary.g, neon_primary.b, 0.12 + 0.08 * core_pulse))

	# 2. Main mothership hull polygon (approx 140x70)
	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(0, -32),
		Vector2(28, -26),
		Vector2(55, -16),
		Vector2(70, 0),
		Vector2(65, 20),
		Vector2(45, 30),
		Vector2(32, 22),
		Vector2(20, 34),
		Vector2(0, 36),
		Vector2(-20, 34),
		Vector2(-32, 22),
		Vector2(-45, 30),
		Vector2(-65, 20),
		Vector2(-70, 0),
		Vector2(-55, -16),
		Vector2(-28, -26),
	])
	draw_colored_polygon(hull, hull_color)

	# Hull outline glow
	var hull_loop: PackedVector2Array = hull.duplicate()
	hull_loop.append(hull[0])
	draw_polyline(hull_loop, neon_primary, 2.0)

	# 3. Outer armored wing panels
	var wing_left: PackedVector2Array = PackedVector2Array([
		Vector2(-28, -12), Vector2(-58, -6), Vector2(-66, 12), Vector2(-36, 16),
	])
	var wing_right: PackedVector2Array = PackedVector2Array([
		Vector2(28, -12), Vector2(58, -6), Vector2(66, 12), Vector2(36, 16),
	])
	draw_colored_polygon(wing_left, Color(0.14, 0.08, 0.26))
	draw_colored_polygon(wing_right, Color(0.14, 0.08, 0.26))
	var wing_left_loop: PackedVector2Array = wing_left.duplicate()
	wing_left_loop.append(wing_left[0])
	var wing_right_loop: PackedVector2Array = wing_right.duplicate()
	wing_right_loop.append(wing_right[0])
	draw_polyline(wing_left_loop, neon_secondary, 1.4)
	draw_polyline(wing_right_loop, neon_secondary, 1.4)

	# 4. Twin heavy plasma cannons
	draw_line(Vector2(-36, 12), Vector2(-36, 32), neon_primary, 3.5)
	draw_line(Vector2(36, 12), Vector2(36, 32), neon_primary, 3.5)
	draw_circle(Vector2(-36, 32), 3.0, neon_primary)
	draw_circle(Vector2(36, 32), 3.0, neon_primary)

	# 5. Central Nexus reactor core
	var core_radius: float = 12.0 + 3.0 * core_pulse
	draw_circle(Vector2.ZERO, core_radius + 4.0, Color(neon_primary.r, neon_primary.g, neon_primary.b, 0.35))
	draw_circle(Vector2.ZERO, core_radius, neon_primary)
	draw_circle(Vector2.ZERO, core_radius * 0.55, Color(1.0, 1.0, 1.0, 0.95))

	# 6. Hit flash overlay
	if _hit_flash_time > 0.0:
		var flash_alpha: float = clampf(_hit_flash_time / 0.12, 0.0, 1.0) * 0.75
		draw_colored_polygon(hull, Color(1.0, 1.0, 1.0, flash_alpha))
