# enemy.gd
# Enemy ship that shoots downward, executes formation movement, fly-in entrances,
# dynamic dive swoops toward the player, and returns to its formation slot.
# Features health system, hit flash, visual health bar, visual enrage escalation,
# and configurable ballistic bullet mix per wave.

extends Area2D

const VectorMath: Script = preload("res://scripts/math/vector_math.gd")

## High-level tactical lifecycle states of the enemy.
enum State { FORMATION, FLY_IN, DIVING, RETURNING }

## Emitted once when the enemy has been destroyed.
signal destroyed(enemy: Area2D)

## Emitted whenever the enemy receives damage (current and max health).
signal damaged(current_health: float, max_health: float)

## Emitted when this enemy makes direct contact with the player.
signal player_contacted(player: Node2D)

## Emitted when the enemy completes its fly-in entrance curve.
signal fly_in_completed

## Emitted when this enemy begins an offensive dive.
signal dive_started

## Emitted when this enemy finishes its return journey and locks into formation.
signal returned_to_formation

## Maximum hit points. Basic formation enemies die to one projectile hit.
@export var max_health: float = 1.0

## Minimum delay in seconds before a shot.
@export var min_shoot_cooldown: float = 1.25

## Maximum delay in seconds before a shot.
@export var max_shoot_cooldown: float = 2.5

## Projectile scene instantiated by this enemy.
@export var enemy_bullet_scene: PackedScene

@onready var _shoot_cooldown: Timer = $ShootCooldown

var health: float = 1.0
var _hit_flash_timer: float = 0.0
const HIT_FLASH_DURATION: float = 0.08

var _destroyed: bool = false

## Local clock and per-instance offset used only to animate a subtle idle
## breathing pulse, so a whole formation doesn't blink in perfect unison.
var _time: float = 0.0
var _pulse_offset: float = 0.0

## Active behavioral state.
var _state: State = State.FORMATION
var _is_flying_in: bool = false
var _is_enraged: bool = false

## Fly-in entrance curve parameters (Stage 8)
var _fly_in_p0: Vector2 = Vector2.ZERO
var _fly_in_p1: Vector2 = Vector2.ZERO
var _fly_in_p2: Vector2 = Vector2.ZERO
var _fly_in_p3: Vector2 = Vector2.ZERO
var _fly_in_duration: float = 1.0
var _fly_in_elapsed: float = 0.0
var _fly_in_delay: float = 0.0

## Dynamic dive parameters (Stage 9)
var _dive_p0: Vector2 = Vector2.ZERO
var _dive_p1: Vector2 = Vector2.ZERO
var _dive_p2: Vector2 = Vector2.ZERO
var _dive_p3: Vector2 = Vector2.ZERO
var _dive_duration: float = 2.0
var _dive_elapsed: float = 0.0

## Return to formation parameters (Stage 9)
var _return_start_pos: Vector2 = Vector2.ZERO
var _slot_getter: Callable = Callable()
var _return_duration: float = 1.6
var _return_elapsed: float = 0.0


func _ready() -> void:
	health = max_health
	_pulse_offset = randf_range(0.0, TAU)
	if _state == State.FORMATION:
		_schedule_next_shot()


func _process(delta: float) -> void:
	match _state:
		State.FLY_IN:
			_process_fly_in(delta)
		State.DIVING:
			_process_diving(delta)
		State.RETURNING:
			_process_returning(delta)
		State.FORMATION:
			pass

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)

	_time += delta
	queue_redraw()


func _process_fly_in(delta: float) -> void:
	_fly_in_elapsed += delta
	if _fly_in_elapsed >= _fly_in_delay:
		var effective_t: float = (_fly_in_elapsed - _fly_in_delay) / _fly_in_duration
		var t: float = clampf(effective_t, 0.0, 1.0)
		global_position = VectorMath.cubic_bezier(_fly_in_p0, _fly_in_p1, _fly_in_p2, _fly_in_p3, t)
		var deriv: Vector2 = VectorMath.cubic_bezier_derivative(_fly_in_p0, _fly_in_p1, _fly_in_p2, _fly_in_p3, t)
		rotation = clampf(deriv.x * 0.0015, -0.45, 0.45) * (1.0 - t)
		if t >= 1.0:
			_state = State.FORMATION
			_is_flying_in = false
			rotation = 0.0
			global_position = _fly_in_p3
			_schedule_next_shot()
			fly_in_completed.emit()


func _process_diving(delta: float) -> void:
	_dive_elapsed += delta
	var t: float = clampf(_dive_elapsed / _dive_duration, 0.0, 1.0)
	global_position = VectorMath.cubic_bezier(_dive_p0, _dive_p1, _dive_p2, _dive_p3, t)
	var deriv: Vector2 = VectorMath.cubic_bezier_derivative(_dive_p0, _dive_p1, _dive_p2, _dive_p3, t)

	# Banking tilt ~15-20 deg (+/- 0.2618 to 0.3491 rad) based on lateral derivative
	var max_tilt: float = deg_to_rad(20.0)
	var min_tilt: float = deg_to_rad(15.0)
	if absf(deriv.x) > 30.0:
		var factor: float = clampf(absf(deriv.x) / 350.0, 0.0, 1.0)
		rotation = signf(deriv.x) * lerpf(min_tilt, max_tilt, factor)
	else:
		rotation = signf(deriv.x) * min_tilt * (absf(deriv.x) / 30.0)

	if t >= 1.0:
		if _slot_getter.is_valid():
			var vp_rect: Rect2 = get_viewport_rect() if is_inside_tree() else Rect2(0, 0, 1080, 960)
			if global_position.y > vp_rect.size.y * 0.9:
				global_position.y = -30.0
				global_position.x = clampf(global_position.x, 60.0, vp_rect.size.x - 60.0)
			return_to_slot(_slot_getter, 2.0 if not _is_enraged else 1.5)
		else:
			_state = State.FORMATION
			rotation = 0.0
			_schedule_next_shot()
			returned_to_formation.emit()


func _process_returning(delta: float) -> void:
	_return_elapsed += delta
	var t: float = clampf(_return_elapsed / _return_duration, 0.0, 1.0)
	var target_slot: Vector2 = _slot_getter.call() if _slot_getter.is_valid() else _return_start_pos
	var smooth_t: float = smoothstep(0.0, 1.0, t)
	global_position = _return_start_pos.lerp(target_slot, smooth_t)

	var return_dx: float = (target_slot.x - _return_start_pos.x)
	var max_tilt: float = deg_to_rad(20.0)
	var min_tilt: float = deg_to_rad(15.0)
	if absf(return_dx) > 30.0:
		var factor: float = clampf(absf(return_dx) / 300.0, 0.0, 1.0)
		rotation = signf(return_dx) * lerpf(min_tilt, max_tilt, factor) * (1.0 - smooth_t)
	else:
		rotation = 0.0

	if t >= 1.0 or (t > 0.8 and global_position.distance_to(target_slot) < 6.0):
		global_position = target_slot
		rotation = 0.0
		_state = State.FORMATION
		_schedule_next_shot()
		returned_to_formation.emit()


func get_state() -> State:
	return _state


func is_in_formation() -> bool:
	return _state == State.FORMATION


func is_diving() -> bool:
	return _state == State.DIVING


func is_returning() -> bool:
	return _state == State.RETURNING


func is_flying_in() -> bool:
	return _state == State.FLY_IN or _is_flying_in


func set_slot_getter(getter: Callable) -> void:
	_slot_getter = getter


func start_dive(target_pos: Vector2, duration: float = 2.0, _dive_type: String = "swoop", slot_getter: Callable = Callable()) -> void:
	if slot_getter.is_valid():
		_slot_getter = slot_getter
	_state = State.DIVING
	_is_flying_in = false
	_dive_duration = maxf(duration, 0.001)
	_dive_elapsed = 0.0

	var p0: Vector2 = global_position
	# Determine swoop lateral curvature
	var side: float = 1.0 if target_pos.x >= p0.x else -1.0
	if absf(target_pos.x - p0.x) < 40.0:
		side = 1.0 if p0.x <= 540.0 else -1.0

	var p1: Vector2 = p0 + Vector2(side * 220.0, 160.0)
	var p2: Vector2 = Vector2(target_pos.x + side * 140.0, target_pos.y - 120.0)
	var p3: Vector2 = Vector2(target_pos.x - side * 80.0, 1040.0)

	_dive_p0 = p0
	_dive_p1 = p1
	_dive_p2 = p2
	_dive_p3 = p3

	dive_started.emit()


func return_to_slot(slot_getter: Callable, duration: float = 1.6) -> void:
	_state = State.RETURNING
	_is_flying_in = false
	_slot_getter = slot_getter
	_return_start_pos = global_position
	_return_duration = maxf(duration, 0.001)
	_return_elapsed = 0.0


func set_enraged(enraged: bool) -> void:
	if _is_enraged == enraged:
		return
	_is_enraged = enraged
	if _is_enraged:
		min_shoot_cooldown *= 0.5
		max_shoot_cooldown *= 0.5
	else:
		min_shoot_cooldown *= 2.0
		max_shoot_cooldown *= 2.0


func is_enraged() -> bool:
	return _is_enraged


func start_fly_in(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, duration: float, delay: float = 0.0) -> void:
	_fly_in_p0 = p0
	_fly_in_p1 = p1
	_fly_in_p2 = p2
	_fly_in_p3 = p3
	_fly_in_duration = maxf(duration, 0.001)
	_fly_in_delay = maxf(delay, 0.0)
	_fly_in_elapsed = 0.0
	_is_flying_in = true
	_state = State.FLY_IN
	global_position = p0
	if _shoot_cooldown != null:
		_shoot_cooldown.stop()


func cancel_fly_in() -> void:
	if _state != State.FLY_IN and not _is_flying_in:
		return
	_is_flying_in = false
	_state = State.FORMATION
	global_position = _fly_in_p3
	rotation = 0.0
	_schedule_next_shot()


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	_is_flying_in = false
	destroyed.emit(self)
	queue_free()


## Applies damage (fractional values allowed, used by the continuous laser).
func take_damage(amount: float = 1.0) -> void:
	if _destroyed or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hit_flash_timer = HIT_FLASH_DURATION
	damaged.emit(health, max_health)
	queue_redraw()
	if is_zero_approx(health) or health <= 0.0:
		health = 0.0
		destroy()


## Signals to damage dealers that this target accepts fractional damage.
func supports_fractional_damage() -> bool:
	return true


func _on_area_entered(area: Area2D) -> void:
	# Player bullets occupy collision layer 2, which is part of this Area2D mask.
	if _destroyed or (area.collision_layer & 2) == 0:
		return
	# Continuous beams apply their own damage over time.
	if area.has_method(&"is_beam"):
		return
	# Projectiles that apply their own damage (ion bullet, missile) handle it themselves.
	if "damage_applied" in area or "damage" in area:
		return
	# Legacy linear bullet: one hit.
	take_damage(1.0)


func _on_body_entered(body: Node2D) -> void:
	if _destroyed or not body.is_in_group("player"):
		return
	player_contacted.emit(body)
	destroy()


## Optional forced bullet variant for testing/scripting (-1 for standard probability).
var _forced_bullet_variant: int = -1

## Probabilities [direct, parabolic, cluster] for normal state. Empty = legacy defaults.
var _bullet_mix: Array = []

## Probabilities [direct, parabolic, cluster] when enraged. Empty = legacy defaults.
var _enraged_bullet_mix: Array = []


func set_bullet_mix(normal_mix: Array, enraged_mix: Array) -> void:
	_bullet_mix = normal_mix.duplicate()
	_enraged_bullet_mix = enraged_mix.duplicate()


## Multiplies the shoot cooldown range (>1.0 = slower fire).
func set_fire_rate_scale(scale: float) -> void:
	min_shoot_cooldown *= scale
	max_shoot_cooldown *= scale


func set_forced_bullet_variant(variant: int) -> void:
	_forced_bullet_variant = variant


func get_forced_bullet_variant() -> int:
	return _forced_bullet_variant


## Configures physical ballistic properties and plasma variant for spawned bullets.
func _configure_bullet(bullet: Node2D) -> void:
	if not ("plasma_variant" in bullet):
		return

	var variant: int = _forced_bullet_variant
	if variant < 0:
		var roll: float = randf()
		var mix: Array = _enraged_bullet_mix if _is_enraged else _bullet_mix
		if mix.size() >= 3:
			var cluster_p: float = float(mix[2])
			var parabolic_p: float = float(mix[1])
			if roll < cluster_p:
				variant = 2 # CLUSTER
			elif roll < (cluster_p + parabolic_p):
				variant = 1 # PARABOLIC
			else:
				variant = 0 # DIRECT
		else:
			if _is_enraged:
				# Enraged enemies favor complex ballistic artillery
				if roll < 0.35:
					variant = 2 # CLUSTER
				elif roll < 0.80:
					variant = 1 # PARABOLIC
				else:
					variant = 0 # DIRECT
			else:
				# Standard formation enemies
				if roll < 0.15:
					variant = 2 # CLUSTER
				elif roll < 0.50:
					variant = 1 # PARABOLIC
				else:
					variant = 0 # DIRECT

	bullet.set("plasma_variant", variant)

	match variant:
		0: # DIRECT
			bullet.set("ballistic_gravity", 0.0)
			bullet.set("gravity", 0.0)
			bullet.set("velocity", Vector2(0.0, bullet.get("speed") if "speed" in bullet else 350.0))
		1: # PARABOLIC
			bullet.set("ballistic_gravity", 380.0)
			bullet.set("gravity", 380.0)
			var target_pos: Vector2 = Vector2.ZERO
			var has_target: bool = false
			if is_inside_tree():
				var player: Node2D = get_tree().get_first_node_in_group(&"player") as Node2D
				if player != null and is_instance_valid(player):
					target_pos = player.global_position
					has_target = true
			if has_target:
				var spawn_pos: Vector2 = global_position + Vector2(0, 20)
				var flight_time: float = randf_range(1.1, 1.5)
				var launch_vel: Vector2 = VectorMath.calculate_ballistic_launch_velocity(
					spawn_pos, target_pos, 380.0, flight_time
				)
				launch_vel.x = clampf(launch_vel.x, -220.0, 220.0)
				bullet.set("velocity", launch_vel)
				bullet.set("initial_velocity", launch_vel)
			else:
				var lateral_vx: float = randf_range(-140.0, 140.0)
				var launch_vel: Vector2 = Vector2(lateral_vx, randf_range(40.0, 100.0))
				bullet.set("velocity", launch_vel)
				bullet.set("initial_velocity", launch_vel)
		2: # CLUSTER
			bullet.set("ballistic_gravity", 320.0)
			bullet.set("gravity", 320.0)
			var lateral_vx: float = randf_range(-90.0, 90.0)
			var launch_vel: Vector2 = Vector2(lateral_vx, randf_range(80.0, 140.0))
			bullet.set("velocity", launch_vel)
			bullet.set("initial_velocity", launch_vel)
			bullet.set("cluster_fuse_time", randf_range(0.5, 0.65))



func _on_shoot_cooldown_timeout() -> void:
	if _destroyed:
		return
	if enemy_bullet_scene != null:
		var enemy_bullet: Node2D = enemy_bullet_scene.instantiate() as Node2D
		if enemy_bullet != null:
			_configure_bullet(enemy_bullet)
			get_tree().current_scene.add_child(enemy_bullet)
			enemy_bullet.global_position = global_position + Vector2(0, 20)
	_schedule_next_shot()



func _schedule_next_shot() -> void:
	_shoot_cooldown.start(randf_range(min_shoot_cooldown, max_shoot_cooldown))


func _draw() -> void:
	var pulse_speed: float = 6.0 if _is_enraged else 3.0
	var pulse: float = 0.5 + 0.5 * sin(_time * pulse_speed + _pulse_offset)

	# Glow colors: toxic green normally, reacting amber/crimson when enraged
	var ambient_glow_color: Color = Color(1.0, 0.35, 0.15, 0.12 + 0.08 * pulse) if _is_enraged else Color(0.45, 1.0, 0.35, 0.07 + 0.05 * pulse)
	var shadow_color: Color = Color(1.0, 0.20, 0.05, 0.14 + 0.08 * pulse) if _is_enraged else Color(0.35, 0.95, 0.3, 0.10 + 0.06 * pulse)
	var carapace_color: Color = Color(0.38, 0.06, 0.12) if _is_enraged else Color(0.22, 0.05, 0.32)
	var carapace_outline_color: Color = Color(1.0, 0.40, 0.15) if _is_enraged else Color(0.55, 1.0, 0.4)
	var claw_color: Color = Color(0.44, 0.08, 0.16) if _is_enraged else Color(0.28, 0.06, 0.4)
	var claw_outline_color: Color = Color(1.0, 0.45, 0.20) if _is_enraged else Color(0.6, 1.0, 0.45)
	var antenna_color: Color = Color(1.0, 0.55, 0.22) if _is_enraged else Color(0.65, 1.0, 0.5)
	var eye_outer_color: Color = Color(1.0, 0.35, 0.15, 0.4 + 0.3 * pulse) if _is_enraged else Color(0.55, 1.0, 0.35, 0.3 + 0.2 * pulse)
	var eye_inner_color: Color = Color(1.0, 0.85, 0.25, 0.9 + 0.1 * pulse) if _is_enraged else Color(0.9, 1.0, 0.55, 0.8 + 0.2 * pulse)
	var leg_color: Color = Color(1.0, 0.45, 0.20, 0.9) if _is_enraged else Color(0.5, 0.95, 0.4, 0.8)

	# Ambient glow
	draw_circle(Vector2.ZERO, 16.0 + 2.0 * pulse, ambient_glow_color)

	# Soft hover shadow beneath carapace
	draw_circle(Vector2(0, 13), 8.0, shadow_color)

	# Compact beetle-like carapace
	var carapace: PackedVector2Array = PackedVector2Array([
		Vector2(-8, -10), Vector2(0, -12), Vector2(8, -10),
		Vector2(10, 1), Vector2(6, 9), Vector2(0, 11), Vector2(-6, 9), Vector2(-10, 1),
	])
	draw_colored_polygon(carapace, carapace_color)
	var carapace_outline: PackedVector2Array = carapace.duplicate()
	carapace_outline.append(carapace[0])
	draw_polyline(carapace_outline, carapace_outline_color, 1.5)

	# Crab-like pincer claws
	var claw_l: PackedVector2Array = PackedVector2Array([
		Vector2(-9, -3), Vector2(-17, -6), Vector2(-21, -9),
		Vector2(-16, -1), Vector2(-21, 4), Vector2(-16, 5), Vector2(-10, 2),
	])
	var claw_r: PackedVector2Array = PackedVector2Array([
		Vector2(9, -3), Vector2(17, -6), Vector2(21, -9),
		Vector2(16, -1), Vector2(21, 4), Vector2(16, 5), Vector2(10, 2),
	])
	draw_colored_polygon(claw_l, claw_color)
	draw_colored_polygon(claw_r, claw_color)
	var claw_l_outline: PackedVector2Array = claw_l.duplicate()
	claw_l_outline.append(claw_l[0])
	var claw_r_outline: PackedVector2Array = claw_r.duplicate()
	claw_r_outline.append(claw_r[0])
	draw_polyline(claw_l_outline, claw_outline_color, 1.25)
	draw_polyline(claw_r_outline, claw_outline_color, 1.25)

	# Twin antennae
	draw_line(Vector2(-3, -11), Vector2(-4.5, -17), antenna_color, 1.2)
	draw_line(Vector2(3, -11), Vector2(4.5, -17), antenna_color, 1.2)
	draw_circle(Vector2(-4.5, -17), 1.2, antenna_color)
	draw_circle(Vector2(4.5, -17), 1.2, antenna_color)

	# Pulsing central eye
	draw_circle(Vector2(0, -1), 4.0, eye_outer_color)
	draw_circle(Vector2(0, -1), 2.0, eye_inner_color)

	# Three thin wriggling legs
	for i in range(3):
		var leg_x: float = (i - 1) * 4.0
		var wag: float = sin(_time * 6.0 + _pulse_offset + i) * 1.5
		draw_line(Vector2(leg_x, 9), Vector2(leg_x + wag, 15), leg_color, 1.1)

	# Impact hit flash overlay
	if _hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.9, 0.7, 0.45))

	# Mini health bar when damaged
	if health < max_health and health > 0.0:
		draw_rect(Rect2(-15.0, -22.0, 30.0, 3.0), Color(0.1, 0.1, 0.15, 0.8))
		var hp_ratio: float = clampf(health / max_health, 0.0, 1.0)
		var bar_color: Color = Color.RED.lerp(Color.GREEN, hp_ratio)
		draw_rect(Rect2(-15.0, -22.0, 30.0 * hp_ratio, 3.0), bar_color)
