# boss.gd
# Final boss entity ("Nave Nodriza Nexus") for Etapa 5.
# Autonomous Area2D in group "enemies" with vector neon art, phase-based attack patterns,
# dynamic banking tilt, sinusoidal cruise oscillation, dive maneuvers, and health-based defeat signaling.

extends Area2D

## Emitted when current health changes.
signal health_changed(current: int, max_health: int)

## Emitted once when the boss reaches 0 health.
signal boss_defeated(boss: Area2D)

## Emitted when the boss makes direct physical contact with the player ship.
signal boss_contacted_player(player: Node2D)

## Emitted when the Núcleo Blindado moves to another armor phase (multi-phase mode only).
signal armor_phase_changed(phase: int)

## Movement states for autonomous flight navigation.
enum MovementState {
	ENTERING,
	CRUISE,
	DIVE_TELEGRAPH,
	DIVE_DESCENT,
	DIVE_ASCENT,
}

## Núcleo Blindado armor phases, ordered from outer shell to exposed core.
enum ArmorPhase {
	EXTERIOR_ARMOR = 1,
	SUBCORE = 2,
	EXPOSED_CORE = 3,
}

## Subcore phase starts at or below this health percentage.
const SUBCORE_THRESHOLD_PERCENT: int = 66
## Exposed core phase starts at or below this health percentage.
const EXPOSED_CORE_THRESHOLD_PERCENT: int = 33
## Damage multiplier applied to every hit while the exposed core is vulnerable.
const EXPOSED_CORE_DAMAGE_MULTIPLIER: float = 1.5

## Maximum health points.
@export var max_health: int = 150

## Projectile scene used for boss attacks.
@export var boss_bullet_scene: PackedScene = preload("res://scenes/entities/boss/boss_bullet.tscn")

## Base hover elevation in cruise mode.
@export var base_y: float = 140.0

## Enables the three-phase Núcleo Blindado mode. Set by main.gd for chapter 3 only.
var multi_phase_enabled: bool = false

## Current health points.
var health: int = 150
var current_health: int = 150

## Whether the boss has entered Phase 2 (enraged).
var is_enraged: bool = false

@onready var _shoot_timer: Timer = $ShootTimer

var _state: MovementState = MovementState.ENTERING
var _is_defeated: bool = false
var _is_entering: bool = true
var _target_y: float = 140.0
var _base_y: float = 140.0
var _time: float = 0.0
var _hit_flash_time: float = 0.0
var _move_direction: float = 1.0
var _left_margin: float = 110.0
var _right_margin: float = 610.0

var _dive_cooldown: float = 5.0
var _telegraph_timer: float = 0.0
var _dive_target: Vector2 = Vector2.ZERO
var _shoot_cycle_phase1: int = 0
var _shoot_cycle_phase2: int = 0
var _armor_phase: ArmorPhase = ArmorPhase.EXTERIOR_ARMOR


func _ready() -> void:
	health = max_health
	current_health = max_health
	_base_y = base_y
	_target_y = _base_y
	var vp_width: float = get_viewport_rect().size.x
	if vp_width > 0.0:
		_right_margin = vp_width - _left_margin
	if _shoot_timer != null:
		_shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	_dive_cooldown = 3.0 if is_enraged else 5.0


func _process(delta: float) -> void:
	_time += delta
	if _hit_flash_time > 0.0:
		_hit_flash_time = maxf(0.0, _hit_flash_time - delta)

	_update_movement(delta)
	queue_redraw()


func _update_movement(delta: float) -> void:
	match _state:
		MovementState.ENTERING:
			_is_entering = true
			global_position.y += 150.0 * delta
			rotation = lerpf(rotation, 0.0, delta * 5.0)
			if global_position.y >= _base_y:
				global_position.y = _base_y
				_is_entering = false
				_state = MovementState.CRUISE
				_dive_cooldown = 3.0 if is_enraged else 5.0
				_schedule_shoot(0.5 if is_enraged else 0.75)

		MovementState.CRUISE:
			_is_entering = false
			# 1. Horizontal movement with boundary bounce
			var speed: float = 190.0 if is_enraged else 140.0
			global_position.x += _move_direction * speed * delta
			if global_position.x <= _left_margin:
				global_position.x = _left_margin
				_move_direction = 1.0
			elif global_position.x >= _right_margin:
				global_position.x = _right_margin
				_move_direction = -1.0

			# 2. Sinusoidal vertical oscillation around base_y
			var vertical_amp: float = 90.0 if is_enraged else 60.0
			var vertical_freq: float = 2.4 if is_enraged else 1.8
			global_position.y = _base_y + sin(_time * vertical_freq) * vertical_amp

			# 3. Dynamic banking tilt based on horizontal direction
			var target_tilt: float = clampf(_move_direction * 0.25, -0.3, 0.3)
			rotation = lerpf(rotation, target_tilt, delta * 5.0)

			# 4. Dive maneuver cooldown
			_dive_cooldown -= delta
			if _dive_cooldown <= 0.0:
				trigger_dive()

		MovementState.DIVE_TELEGRAPH:
			_is_entering = false
			_telegraph_timer -= delta
			rotation = lerpf(rotation, 0.0, delta * 8.0)
			if _telegraph_timer <= 0.0:
				_state = MovementState.DIVE_DESCENT

		MovementState.DIVE_DESCENT:
			_is_entering = false
			var descent_speed: float = 540.0 if is_enraged else 420.0
			global_position.y += descent_speed * delta

			var diff_x: float = _dive_target.x - global_position.x
			var steer_speed: float = clampf(diff_x * 3.5, -descent_speed * 0.75, descent_speed * 0.75)
			global_position.x += steer_speed * delta
			global_position.x = clampf(global_position.x, _left_margin, _right_margin)

			var dive_tilt: float = clampf((steer_speed / descent_speed) * 0.5, -0.4, 0.4)
			rotation = lerpf(rotation, dive_tilt, delta * 6.0)

			if global_position.y >= _dive_target.y or global_position.y >= 740.0:
				_state = MovementState.DIVE_ASCENT

		MovementState.DIVE_ASCENT:
			_is_entering = false
			var ascent_speed: float = 320.0 if is_enraged else 260.0
			global_position.y -= ascent_speed * delta

			var speed_x: float = 140.0 if is_enraged else 100.0
			global_position.x += _move_direction * speed_x * delta
			if global_position.x <= _left_margin:
				global_position.x = _left_margin
				_move_direction = 1.0
			elif global_position.x >= _right_margin:
				global_position.x = _right_margin
				_move_direction = -1.0

			var ascent_tilt: float = clampf(_move_direction * 0.2, -0.3, 0.3)
			rotation = lerpf(rotation, ascent_tilt, delta * 5.0)

			if global_position.y <= _base_y:
				global_position.y = _base_y
				_state = MovementState.CRUISE
				_dive_cooldown = 3.0 if is_enraged else 5.0


## Triggers a dive maneuver telegraph towards player position or current X.
func trigger_dive() -> void:
	if _state != MovementState.CRUISE and _state != MovementState.ENTERING:
		return
	_state = MovementState.DIVE_TELEGRAPH
	_telegraph_timer = 0.4 if is_enraged else 0.5
	var target_x: float = global_position.x
	if is_inside_tree():
		var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null and is_instance_valid(player):
			target_x = player.global_position.x
	_dive_target = Vector2(clampf(target_x, _left_margin, _right_margin), 760.0)


## Returns the current movement state.
func get_movement_state() -> MovementState:
	return _state


## Returns the Núcleo Blindado phase. Without multi-phase mode the boss stays in the exterior phase.
func get_armor_phase() -> ArmorPhase:
	if not multi_phase_enabled:
		return ArmorPhase.EXTERIOR_ARMOR
	return _armor_phase_for_health(health)


func _armor_phase_for_health(current: int) -> ArmorPhase:
	# Integer comparison avoids float rounding at the exact thresholds.
	if current * 100 <= max_health * EXPOSED_CORE_THRESHOLD_PERCENT:
		return ArmorPhase.EXPOSED_CORE
	if current * 100 <= max_health * SUBCORE_THRESHOLD_PERCENT:
		return ArmorPhase.SUBCORE
	return ArmorPhase.EXTERIOR_ARMOR


func take_damage(amount: int = 1) -> void:
	if _is_defeated:
		return
	var applied: int = amount
	if get_armor_phase() == ArmorPhase.EXPOSED_CORE:
		applied = int(round(float(amount) * EXPOSED_CORE_DAMAGE_MULTIPLIER))
	health = maxi(0, health - applied)
	current_health = health
	_hit_flash_time = 0.12

	var new_phase: ArmorPhase = get_armor_phase()
	if new_phase != _armor_phase:
		_armor_phase = new_phase
		armor_phase_changed.emit(int(new_phase))

	if health <= (max_health / 2) and not is_enraged:
		is_enraged = true
		if _shoot_timer != null:
			_shoot_timer.wait_time = 0.5
		_dive_cooldown = minf(_dive_cooldown, 3.0)

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
		# Phase 1: Alternate between dual heavy cannons and aimed shot
		if (_shoot_cycle_phase1 % 2) == 0:
			# Pattern A: Dual heavy shot
			_spawn_bullet(Vector2(-36, 32), Vector2.DOWN, 360.0)
			_spawn_bullet(Vector2(36, 32), Vector2.DOWN, 360.0)
		else:
			# Pattern B: Aimed shot from central cannon
			var player: Node2D = _get_player_node()
			var aim_dir: Vector2 = Vector2.DOWN
			if player != null:
				var to_player: Vector2 = global_position.direction_to(player.global_position)
				if to_player.length_squared() > 0.0001:
					aim_dir = to_player.normalized()
			_spawn_bullet(Vector2(0, 36), aim_dir, 370.0, true)
		_shoot_cycle_phase1 += 1
		_schedule_shoot(0.75)
	else:
		# Phase 2: Alternate between 5-bullet fan spread and dual fast aimed shots
		if (_shoot_cycle_phase2 % 2) == 0:
			# Pattern A: 5-bullet fan spread (-30°, -15°, 0°, +15°, +30°)
			var angles: Array[float] = [-30.0, -15.0, 0.0, 15.0, 30.0]
			for angle_deg: float in angles:
				var spread_dir: Vector2 = Vector2.DOWN.rotated(deg_to_rad(angle_deg))
				_spawn_bullet(Vector2(0, 36), spread_dir, 400.0)
		else:
			# Pattern B: Fast dual aimed shots from lateral turrets
			var player: Node2D = _get_player_node()
			var aim_dir: Vector2 = Vector2.DOWN
			if player != null:
				var to_player: Vector2 = global_position.direction_to(player.global_position)
				if to_player.length_squared() > 0.0001:
					aim_dir = to_player.normalized()
			_spawn_bullet(Vector2(-36, 32), aim_dir, 420.0, true)
			_spawn_bullet(Vector2(36, 32), aim_dir, 420.0, true)
		_shoot_cycle_phase2 += 1
		_schedule_shoot(0.5)


func _get_player_node() -> Node2D:
	if is_inside_tree():
		var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
		if player != null and is_instance_valid(player) and player.visible:
			return player
	return null


func _spawn_bullet(offset: Vector2, dir: Vector2, bullet_speed: float, is_world_dir: bool = false) -> void:
	var bullet: Area2D = boss_bullet_scene.instantiate() as Area2D
	if bullet == null:
		return
	bullet.global_position = global_position + offset.rotated(rotation)
	var final_dir: Vector2 = dir if is_world_dir else dir.rotated(rotation)
	if "direction" in bullet:
		bullet.set("direction", final_dir)
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
	if area.has_method(&"is_beam") and area.call(&"is_beam"):
		return
	# Player bullet layer is 2
	if (area.collision_layer & 2) != 0 or area.is_in_group(&"player_bullets"):
		if area.get("damage_applied") == true:
			return
		if "damage_applied" in area:
			area.set("damage_applied", true)
		var damage_amount: int = 1
		if "damage" in area and area.damage != null:
			damage_amount = int(area.damage)
		elif area.get("damage") != null:
			damage_amount = int(area.get("damage"))
		elif area.has_meta(&"damage"):
			damage_amount = int(area.get_meta(&"damage"))
		take_damage(damage_amount)


func _on_body_entered(body: Node2D) -> void:
	if _is_defeated:
		return
	if body.is_in_group(&"player"):
		boss_contacted_player.emit(body)


func _draw() -> void:
	var pulse_speed: float = 9.0 if is_enraged else 4.0
	if _state == MovementState.DIVE_TELEGRAPH:
		pulse_speed = 22.0
	var core_pulse: float = 0.5 + 0.5 * sin(_time * pulse_speed)

	var neon_primary: Color = Color(1.0, 0.22, 0.48) if is_enraged else Color(0.22, 0.9, 1.0)
	var neon_secondary: Color = Color(1.0, 0.6, 0.1) if is_enraged else Color(0.68, 0.28, 1.0)
	var hull_color: Color = Color(0.08, 0.04, 0.16)

	# 0. Dive telegraph threat warning pulse
	if _state == MovementState.DIVE_TELEGRAPH:
		var warn_color: Color = Color(1.0, 0.2, 0.35, 0.55 + 0.35 * sin(_time * 24.0))
		draw_arc(Vector2.ZERO, 72.0 + 8.0 * sin(_time * 16.0), 0.0, TAU, 32, warn_color, 3.5)
		draw_circle(Vector2.ZERO, 85.0, Color(1.0, 0.1, 0.2, 0.12))

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
