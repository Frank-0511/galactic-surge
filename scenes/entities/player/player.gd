# player.gd
# Player ship controller. Handles horizontal movement, modular arsenal switching
# (Blaster, Missile, Laser), thermal overheat regulation, power-ups, and respawns.

extends CharacterBody2D

## Emitted when the ship requests life loss from valid hostile contact.
signal damage_requested

## Emitted when the post-respawn invulnerability blink window expires.
signal invulnerability_ended

## Emitted upon firing any weapon; receives true if double shot is engaged.
signal shot_fired(is_double_shot: bool)

const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

## Emitted when active weapon changes (WeaponType enum value).
signal weapon_changed(new_weapon: int)

## Emitted when active weapon power level changes (1 to 15).
signal weapon_level_changed(new_level: int)

## Emitted when barrel heat changes.
signal heat_changed(current_heat: float, max_heat: float)

## Emitted when thermal lock activates or clears.
signal overheat_state_changed(is_overheated: bool)

## Available weapon systems in the modular arsenal.
enum WeaponType {
	BLASTER = 0,
	MISSILE = 1,
	LASER = 2,
}

const WEAPON_COUNT: int = 3
const MAX_WEAPON_LEVEL: int = 15
## Last level of the original calibration (heat curve, missile cooldown). Levels above it reuse its heat.
const LEGACY_MAX_LEVEL: int = 10

## Power level of the current weapon system (1 to 15).
@export_range(1, 15) var weapon_level: int = 1

## Horizontal movement speed in pixels per second.
@export var speed: float = 480.0

## Default blaster projectile scene.
@export var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

## Directional projectile used by the Ion Blaster.
@export var ion_bullet_scene: PackedScene = preload("res://scenes/entities/bullet/spread_bullet.tscn")

## Backward compatibility property alias for tests expecting spread_bullet_scene.
var spread_bullet_scene: PackedScene:
	get:
		return ion_bullet_scene
	set(value):
		ion_bullet_scene = value

## Homing missile projectile scene.
@export var missile_scene: PackedScene = preload("res://scenes/entities/bullet/missile.tscn")

## Continuous laser beam scene.
@export var laser_beam_scene: PackedScene = preload("res://scenes/entities/bullet/laser_beam.tscn")

## Duration in seconds after respawning during which damage is ignored.
@export var invulnerability_duration: float = 1.5

## Interval in seconds between Player visibility changes while invulnerable.
@export var blink_interval: float = 0.15

## Currently selected weapon in the arsenal.
var current_weapon: int = WeaponType.BLASTER

## Current barrel heat level (0.0 to 100.0).
var heat: float = 0.0

## Maximum barrel heat capacity.
var max_heat: float = 100.0

## True when firing is locked due to thermal overload.
var is_overheated: bool = false

## Passive cooling rate (% heat dissipated per second).
var cooling_rate: float = 35.0

## Session difficulty multiplier applied to passive cooling (Etapa 18). 1.0 keeps the base rate.
var cooling_scale: float = 1.0

## Delay in seconds before passive cooling begins after the last shot.
var cooling_delay: float = 0.25

## Duration in seconds of the thermal lock when 100% heat is reached.
var overheat_duration: float = 2.5

## Margin from the ship center to the screen edge.
const MARGIN: float = 16.0

## Horizontal offset (px) between the two bullets fired in double-shot mode.
const DOUBLE_SHOT_SPREAD: float = 12.0

@onready var _shoot_cooldown: Timer = $ShootCooldown
@onready var _invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var _blink_timer: Timer = $BlinkTimer
@onready var _shield_timer: Timer = $ShieldTimer
@onready var _shield_ring: Node2D = $ShieldRing
@onready var _laser_beam: Area2D = get_node_or_null("LaserBeam") as Area2D

var _cooling_delay_timer: float = 0.0
var _overheat_timer: float = 0.0
var _is_invulnerable: bool = false
var _gameplay_enabled: bool = true
var _double_shot_enabled: bool = false
const MAX_SHIELD_LEVEL: int = 3
## Extra duration (as a fraction of the base) added per level above 1: 10 s, 14 s, 18 s.
const SHIELD_LEVEL_DURATION_BONUS: float = 0.4
var _shield_active: bool = false
var _shield_level: int = 0
var _horizontal_limits: Vector2 = Vector2.ZERO

## Local clock used only to animate engine flicker, lights, and heat pulsation.
var _time: float = 0.0


func _ready() -> void:
	if bullet_scene == null:
		bullet_scene = load("res://scenes/entities/bullet/bullet.tscn") as PackedScene
	if ion_bullet_scene == null:
		ion_bullet_scene = load("res://scenes/entities/bullet/spread_bullet.tscn") as PackedScene
	if missile_scene == null:
		missile_scene = load("res://scenes/entities/bullet/missile.tscn") as PackedScene
	if laser_beam_scene == null:
		laser_beam_scene = load("res://scenes/entities/bullet/laser_beam.tscn") as PackedScene

	if _laser_beam == null and laser_beam_scene != null:
		_laser_beam = laser_beam_scene.instantiate() as Area2D
		if _laser_beam != null:
			_laser_beam.position = Vector2(0.0, -20.0)
			add_child(_laser_beam)

	if _laser_beam != null:
		if _laser_beam.has_method(&"set_power_level"):
			_laser_beam.call(&"set_power_level", weapon_level)
		if _laser_beam.has_method(&"set_firing"):
			_laser_beam.call(&"set_firing", false)
		else:
			_laser_beam.visible = false

	if _invulnerability_timer != null:
		_invulnerability_timer.timeout.connect(_on_invulnerability_timer_timeout)
	if _blink_timer != null:
		_blink_timer.timeout.connect(_on_blink_timer_timeout)
	if _shield_timer != null:
		_shield_timer.timeout.connect(_on_shield_timer_timeout)


func _process(delta: float) -> void:
	_time += delta
	_process_overheat_and_cooling(delta)
	queue_redraw()

	if not _gameplay_enabled:
		velocity = Vector2.ZERO
		_set_laser_active(false)
		return

	# Horizontal movement
	var direction: float = Input.get_axis("move_left", "move_right")
	velocity = Vector2(direction * speed, 0.0)
	move_and_slide()

	# Clamp to horizontal limits from GameLayout when provided, else viewport bounds.
	if _horizontal_limits != Vector2.ZERO:
		position.x = clampf(position.x, _horizontal_limits.x + MARGIN, _horizontal_limits.y - MARGIN)
	else:
		var viewport_rect: Rect2 = get_viewport_rect()
		position.x = clampf(position.x, viewport_rect.position.x + MARGIN, viewport_rect.end.x - MARGIN)

	# Firing handling
	_handle_shooting(delta)


# ---------------------------------------------------------------------------
# Arsenal management API
# ---------------------------------------------------------------------------

## Selects an active weapon from WeaponType.
func set_weapon(type: int) -> void:
	if type < 0 or type >= WEAPON_COUNT:
		return
	if current_weapon == type:
		return
	if current_weapon == WeaponType.LASER:
		_set_laser_active(false)
	_double_shot_enabled = false
	current_weapon = type
	weapon_changed.emit(current_weapon)
	queue_redraw()


func _get_weapon_color() -> Color:
	match current_weapon:
		WeaponType.BLASTER: return Color(0.2, 0.6, 1.0)
		WeaponType.MISSILE: return Color(1.0, 0.55, 0.1)
		WeaponType.LASER: return Color(1.0, 0.2, 0.25)
		_: return Color(0.28, 0.85, 1.0)


## Returns the currently active weapon type.
func get_weapon() -> int:
	return current_weapon


## Cycles through weapons forward or backward.
func cycle_weapon(forward: bool = true) -> void:
	var delta_dir: int = 1 if forward else -1
	var next_type: int = (current_weapon + delta_dir) % WEAPON_COUNT
	if next_type < 0:
		next_type += WEAPON_COUNT
	set_weapon(next_type)


## Returns current weapon level (1 to 15).
func get_weapon_level() -> int:
	return weapon_level


## Sets weapon power level clamped between 1 and 15, emitting weapon_level_changed.
func set_weapon_level(level: int) -> void:
	var clamped: int = clampi(level, 1, MAX_WEAPON_LEVEL)
	weapon_level = clamped
	if _laser_beam != null and _laser_beam.has_method(&"set_power_level"):
		_laser_beam.call(&"set_power_level", weapon_level)
	weapon_level_changed.emit(weapon_level)


## Applies a medallion drop. If it matches current weapon, upgrades level (+1).
## If it differs, switches weapon and preserves the accumulated weapon level (Chicken Invaders model).
func apply_medallion(weapon_type: int) -> void:
	if weapon_type == current_weapon:
		set_weapon_level(weapon_level + 1)
	else:
		set_weapon(weapon_type)
		set_weapon_level(weapon_level)


## Applies a power atom drop. Upgrades weapon level (+1) without changing current weapon.
func apply_power_atom() -> void:
	set_weapon_level(weapon_level + 1)


## Decrements weapon level by 1 on player death (if > 1) and returns lost levels (1 or 0).
func penalize_weapon_on_death() -> int:
	if weapon_level > 1:
		set_weapon_level(weapon_level - 1)
		return 1
	return 0


# ---------------------------------------------------------------------------
# Overheat and thermal regulation API
# ---------------------------------------------------------------------------

## Adds heat to the ship's barrel. Automatically engages overheat lock at max_heat.
func add_heat(amount: float) -> void:
	if is_overheated:
		return
	_cooling_delay_timer = cooling_delay
	var prev_heat: float = heat
	heat = minf(max_heat, heat + amount)
	if heat >= max_heat:
		heat = max_heat
		is_overheated = true
		_overheat_timer = overheat_duration
		_set_laser_active(false)
		heat_changed.emit(heat, max_heat)
		overheat_state_changed.emit(true)
	elif heat != prev_heat:
		heat_changed.emit(heat, max_heat)


## Dissipates an explicit amount of heat.
func cool_down(amount: float) -> void:
	var prev_heat: float = heat
	heat = maxf(0.0, heat - amount)
	if is_overheated and heat <= 0.0:
		heat = 0.0
		is_overheated = false
		_overheat_timer = 0.0
		heat_changed.emit(heat, max_heat)
		overheat_state_changed.emit(false)
	elif heat != prev_heat:
		heat_changed.emit(heat, max_heat)


## Immediately resets heat to 0 and clears overheat lock.
func reset_heat() -> void:
	var was_overheated: bool = is_overheated
	heat = 0.0
	_cooling_delay_timer = 0.0
	_overheat_timer = 0.0
	is_overheated = false
	if was_overheated:
		overheat_state_changed.emit(false)
	heat_changed.emit(heat, max_heat)


## Returns true if the weapon system is currently locked due to overheat.
func is_weapon_overheated() -> bool:
	return is_overheated


func _process_overheat_and_cooling(delta: float) -> void:
	if is_overheated:
		_overheat_timer = maxf(0.0, _overheat_timer - delta)
		var decay_rate: float = max_heat / overheat_duration
		var prev_heat: float = heat
		heat = maxf(0.0, heat - decay_rate * delta)
		if _overheat_timer <= 0.0 or heat <= 0.0:
			heat = 0.0
			is_overheated = false
			_overheat_timer = 0.0
			overheat_state_changed.emit(false)
		if heat != prev_heat:
			heat_changed.emit(heat, max_heat)
	else:
		if _cooling_delay_timer > 0.0:
			_cooling_delay_timer = maxf(0.0, _cooling_delay_timer - delta)
		elif heat > 0.0:
			var prev_heat: float = heat
			heat = maxf(0.0, heat - cooling_rate * cooling_scale * delta)
			if heat != prev_heat:
				heat_changed.emit(heat, max_heat)


## Seconds of sustained fire before overheating, per weapon, at level 1 and level 10.
const OVERHEAT_SECONDS: Dictionary = {
	WeaponType.BLASTER: Vector2(10.0, 8.0),
	WeaponType.MISSILE: Vector2(9.0, 7.5),
	WeaponType.LASER: Vector2(8.0, 10.0),
}


## Heat per second needed so sustained fire overheats in the target time for the current level.
func _get_heat_per_second(weapon: int) -> float:
	var range_s: Vector2 = OVERHEAT_SECONDS.get(weapon, Vector2(8.0, 8.0))
	var t: float = float(clampi(weapon_level, 1, LEGACY_MAX_LEVEL) - 1) / float(LEGACY_MAX_LEVEL - 1)
	var seconds: float = lerpf(range_s.x, range_s.y, t)
	return max_heat / maxf(seconds, 0.1)


## Public accessor for heat per second calculation.
func get_heat_per_second(weapon: int) -> float:
	return _get_heat_per_second(weapon)


# ---------------------------------------------------------------------------
# Shooting mechanics
# ---------------------------------------------------------------------------

func _handle_shooting(delta: float) -> void:
	if current_weapon == WeaponType.LASER:
		if Input.is_action_pressed("shoot") and not is_overheated:
			if Input.is_action_just_pressed("shoot"):
				shot_fired.emit(false)
			_set_laser_active(true)
			add_heat(_get_heat_per_second(WeaponType.LASER) * delta)
		else:
			_set_laser_active(false)
	else:
		_set_laser_active(false)
		if Input.is_action_pressed("shoot") and _shoot_cooldown.is_stopped() and not is_overheated:
			_shoot()


func _shoot() -> void:
	if is_overheated:
		return
	match current_weapon:
		WeaponType.BLASTER:
			_shoot_blaster()
		WeaponType.MISSILE:
			_shoot_missile()
		WeaponType.LASER:
			_shoot_laser_pulse()


## Ion Blaster pattern per level (index 0 = level 1). Each shot is [offset_x, angle_deg].
## Coverage metric: x300 = offset_x + 300 * tan(angle_deg), the horizontal landing spot after 300 px.
## L6 and L8-L15 keep at most 35% of shots with |x300| <= 40 and mirror-symmetric pairs. L5 and L7
## keep their legacy layout: etapa 12.5 time-to-kill windows need 3+ central hits there.
const ION_PATTERNS: Array = [
	[[0.0, 0.0]],                                                                  # L1: 1 recto
	[[-8.0, 0.0], [8.0, 0.0]],                                                     # L2: 2 rectos
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0]],                                       # L3: 3 rectos
	[[-8.0, 0.0], [8.0, 0.0], [-14.0, -8.0], [14.0, 8.0]],                         # L4: 2 rectos + 2 diagonales
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0], [-16.0, -10.0], [16.0, 10.0]],         # L5: 3 rectos + 2 diagonales
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-24.0, -24.0], [24.0, 24.0]],  # L6: 2 central + 2 diagonal pairs
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0], [-16.0, -9.0], [16.0, 9.0], [-20.0, -18.0], [20.0, 18.0]],  # L7: 3 rectos + 4 diag
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -34.0], [24.0, 34.0]],  # L8: 1 central pair + 3 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-26.0, -34.0], [26.0, 34.0]],  # L9: 3 central + 3 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-26.0, -34.0], [26.0, 34.0], [-30.0, -40.0], [30.0, 40.0]],  # L10: 1 central pair + 4 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -24.0], [22.0, 24.0], [-26.0, -33.0], [26.0, 33.0], [-28.0, -40.0], [28.0, 40.0]],  # L11: 3 central + 4 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -28.0], [24.0, 28.0], [-26.0, -34.0], [26.0, 34.0], [-28.0, -40.0], [28.0, 40.0]],  # L12: 1 central pair + 5 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -28.0], [24.0, 28.0], [-26.0, -34.0], [26.0, 34.0], [-28.0, -40.0], [28.0, 40.0]],  # L13: 3 central + 5 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-20.0, -18.0], [20.0, 18.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -30.0], [24.0, 30.0], [-26.0, -36.0], [26.0, 36.0], [-28.0, -40.0], [28.0, 40.0]],  # L14: 1 central pair + 6 diagonal pairs
	[[0.0, 0.0], [-6.0, 0.0], [6.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-18.0, -10.0], [18.0, 10.0], [-22.0, -18.0], [22.0, 18.0], [-24.0, -24.0], [24.0, 24.0], [-26.0, -30.0], [26.0, 30.0], [-30.0, -40.0], [30.0, 40.0]],  # L15: 5 central + 5 diagonal pairs
]

## Damage per Ion Blaster projectile by level (index 0 = level 1): 1 up to L4, 2 up to L8, 3 at L9-L10, 3-4 at L11-L15.
const BLASTER_DAMAGE: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4]


## Returns the damage of one Ion Blaster projectile at the given level.
static func get_blaster_damage(level: int) -> int:
	return BLASTER_DAMAGE[clampi(level, 1, MAX_WEAPON_LEVEL) - 1]


func _shoot_blaster() -> void:
	var scene: PackedScene = ion_bullet_scene if ion_bullet_scene != null else bullet_scene
	if scene == null:
		return
	var level_index: int = clampi(weapon_level, 1, MAX_WEAPON_LEVEL) - 1
	var pattern: Array = ION_PATTERNS[level_index]
	# Double-shot power-up only affects level 1 (keeps legacy behaviour).
	if weapon_level == 1 and _double_shot_enabled:
		pattern = ION_PATTERNS[1]
	for shot: Variant in pattern:
		var shot_arr: Array = shot as Array
		var offset_x: float = float(shot_arr[0])
		var rad: float = deg_to_rad(float(shot_arr[1]))
		var dir: Vector2 = Vector2(sin(rad), -cos(rad))
		var bullet: Area2D = scene.instantiate() as Area2D
		if bullet != null:
			bullet.global_position = global_position + Vector2(offset_x, -20.0)
			if "direction" in bullet:
				bullet.set("direction", dir)
			if "damage" in bullet:
				bullet.set("damage", get_blaster_damage(weapon_level))
			SESSION_STATS.register_shot()
			_add_combat_transient(bullet)
	add_heat(_get_heat_per_second(WeaponType.BLASTER) * 0.25)
	_shoot_cooldown.start(0.25)
	shot_fired.emit(_double_shot_enabled or weapon_level >= 2)


const MISSILE_OFFSETS: Array = [
	[0.0],                                    # L1
	[-14.0, 14.0],                            # L2
	[-14.0, 14.0],                            # L3 (misma cantidad, menor cooldown)
	[-16.0, 0.0, 16.0],                       # L4
	[-16.0, 0.0, 16.0],                       # L5
	[-20.0, -8.0, 8.0, 20.0],                 # L6
	[-20.0, -8.0, 8.0, 20.0],                 # L7
	[-24.0, -12.0, 0.0, 12.0, 24.0],          # L8
	[-24.0, -12.0, 0.0, 12.0, 24.0],          # L9
	[-30.0, -18.0, -6.0, 6.0, 18.0, 30.0],    # L10
	[-30.0, -18.0, -6.0, 6.0, 18.0, 30.0],    # L11 (mismo que L10)
	[-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0],    # L12
	[-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0],    # L13
	[-42.0, -30.0, -18.0, -6.0, 6.0, 18.0, 30.0, 42.0],    # L14
	[-42.0, -30.0, -18.0, -6.0, 6.0, 18.0, 30.0, 42.0],    # L15
]

func _shoot_missile() -> void:
	var scene: PackedScene = missile_scene if missile_scene != null else bullet_scene
	if scene == null:
		return
	var level_index: int = clampi(weapon_level, 1, MAX_WEAPON_LEVEL) - 1
	var offsets: Array = MISSILE_OFFSETS[level_index]

	var candidate_enemies: Array[Node2D] = []
	if get_tree() != null:
		var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
		for node: Node in enemies:
			if is_instance_valid(node) and (node is Node2D):
				var enemy_node: Node2D = node as Node2D
				if enemy_node.is_inside_tree() and not enemy_node.is_queued_for_deletion() and enemy_node.get("_destroyed") != true:
					candidate_enemies.append(enemy_node)

		candidate_enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)
		)

	for i in range(offsets.size()):
		var ox: float = float(offsets[i])
		var missile: Area2D = scene.instantiate() as Area2D
		if missile != null:
			missile.global_position = global_position + Vector2(ox, -20.0)
			if missile.has_method(&"set_power_level"):
				missile.call(&"set_power_level", weapon_level)
			if candidate_enemies.size() > 0:
				var target_assigned: Node2D = candidate_enemies[i % candidate_enemies.size()]
				if missile.has_method(&"set_target"):
					missile.call(&"set_target", target_assigned)
			SESSION_STATS.register_shot()
			_add_combat_transient(missile)

	var cooldown: float = lerpf(0.55, 0.35, float(mini(weapon_level, LEGACY_MAX_LEVEL) - 1) / float(LEGACY_MAX_LEVEL - 1))
	if weapon_level > LEGACY_MAX_LEVEL:
		cooldown = lerpf(0.35, 0.28, float(weapon_level - LEGACY_MAX_LEVEL) / 5.0)
	add_heat(_get_heat_per_second(WeaponType.MISSILE) * cooldown)
	_shoot_cooldown.start(cooldown)
	shot_fired.emit(false)


func _shoot_laser_pulse() -> void:
	_set_laser_active(true)
	add_heat(_get_heat_per_second(WeaponType.LASER) * 0.25)
	_shoot_cooldown.start(0.25)
	shot_fired.emit(false)


func _ensure_laser_beam() -> Area2D:
	if is_instance_valid(_laser_beam):
		if _laser_beam.has_method(&"set_power_level"):
			_laser_beam.call(&"set_power_level", weapon_level)
		return _laser_beam
	var existing: Area2D = get_node_or_null("LaserBeam") as Area2D
	if is_instance_valid(existing):
		_laser_beam = existing
		if _laser_beam.has_method(&"set_power_level"):
			_laser_beam.call(&"set_power_level", weapon_level)
		return _laser_beam
	if laser_beam_scene == null:
		laser_beam_scene = load("res://scenes/entities/bullet/laser_beam.tscn") as PackedScene
	if laser_beam_scene != null:
		_laser_beam = laser_beam_scene.instantiate() as Area2D
		_laser_beam.position = Vector2(0.0, -20.0)
		add_child(_laser_beam)
		if _laser_beam.has_method(&"set_power_level"):
			_laser_beam.call(&"set_power_level", weapon_level)
		if _laser_beam.has_method(&"set_firing"):
			_laser_beam.call(&"set_firing", false)
		else:
			_laser_beam.visible = false
	return _laser_beam


func _set_laser_active(active: bool) -> void:
	var beam: Area2D = _ensure_laser_beam()
	if beam != null and is_instance_valid(beam):
		if beam.has_method(&"set_firing"):
			beam.call(&"set_firing", active)
		else:
			beam.visible = active


func _spawn_bullet(offset_x: float) -> void:
	var bullet: Node2D = bullet_scene.instantiate() as Node2D
	bullet.global_position = global_position + Vector2(offset_x, -20.0)
	_add_combat_transient(bullet)


func _add_combat_transient(node: Node) -> void:
	var container: Node = get_tree().current_scene if get_tree() != null else null
	if container == null:
		container = get_parent()
	if container != null:
		container.add_child(node)
	else:
		add_child(node)


# ---------------------------------------------------------------------------
# Damage and respawn
# ---------------------------------------------------------------------------

func take_damage() -> bool:
	if _is_invulnerable or not _gameplay_enabled:
		return false
	if _shield_active:
		return false
	damage_requested.emit()
	return true


func respawn(respawn_position: Vector2) -> void:
	position = respawn_position
	_is_invulnerable = true
	visible = true
	_set_laser_active(false)
	reset_heat()
	if _invulnerability_timer != null:
		_invulnerability_timer.start(invulnerability_duration)
	if _blink_timer != null:
		_blink_timer.start(blink_interval)


## Grants a timed invulnerability window (e.g. after clearing a wave). Reuses the
## respawn invulnerability state, so enemy hits are ignored until it expires.
func grant_invulnerability(duration: float) -> void:
	_is_invulnerable = true
	if _invulnerability_timer != null:
		_invulnerability_timer.start(duration)


## Seconds left of the current invulnerability window, or 0.0 when vulnerable.
func get_invulnerability_time_left() -> float:
	if not _is_invulnerable or _invulnerability_timer == null:
		return 0.0
	return _invulnerability_timer.time_left


func set_gameplay_enabled(enabled: bool) -> void:
	_gameplay_enabled = enabled
	if not _gameplay_enabled:
		velocity = Vector2.ZERO
		_set_laser_active(false)


## Sets the horizontal movement limits (min_x, max_x) from GameLayout.
func set_horizontal_limits(limits: Vector2) -> void:
	_horizontal_limits = limits


# ---------------------------------------------------------------------------
# Power-up APIs (4B compatible)
# ---------------------------------------------------------------------------

func enable_double_shot() -> void:
	_double_shot_enabled = true


func disable_double_shot() -> void:
	_double_shot_enabled = false


func has_double_shot() -> bool:
	return _double_shot_enabled


## Activates the shield. Picking one up while another is still active raises its level
## (up to MAX_SHIELD_LEVEL); each level lasts SHIELD_LEVEL_DURATION_BONUS longer.
func activate_shield(duration: float) -> void:
	_shield_level = mini(_shield_level + 1, MAX_SHIELD_LEVEL) if _shield_active else 1
	_shield_active = true
	if _shield_ring != null:
		_shield_ring.visible = true
		if _shield_ring.has_method(&"set_level"):
			_shield_ring.call(&"set_level", _shield_level)
	if _shield_timer != null:
		_shield_timer.wait_time = duration * (1.0 + SHIELD_LEVEL_DURATION_BONUS * float(_shield_level - 1))
		_shield_timer.start()


func has_shield() -> bool:
	return _shield_active


## Current shield level: 0 when there is no shield, otherwise 1 to MAX_SHIELD_LEVEL.
func get_shield_level() -> int:
	return _shield_level if _shield_active else 0


func clear_power_ups() -> void:
	_double_shot_enabled = false
	_shield_active = false
	_shield_level = 0
	if _shield_timer != null:
		_shield_timer.stop()
	if _shield_ring != null:
		_shield_ring.visible = false
	_set_laser_active(false)


# ---------------------------------------------------------------------------
# Test-only helpers
# ---------------------------------------------------------------------------

## Simulates a single shot bypassing input and cooldown. Used by contract tests.
func simulate_shot() -> void:
	reset_heat()
	_shoot()



func _on_invulnerability_timer_timeout() -> void:
	_is_invulnerable = false
	if _blink_timer != null:
		_blink_timer.stop()
	visible = true
	invulnerability_ended.emit()


func _on_blink_timer_timeout() -> void:
	if _is_invulnerable:
		visible = not visible


func _on_shield_timer_timeout() -> void:
	_shield_active = false
	_shield_level = 0
	if _shield_ring != null:
		_shield_ring.visible = false


# ---------------------------------------------------------------------------
# Visual rendering
# ---------------------------------------------------------------------------

func _draw() -> void:
	var heat_ratio: float = clampf(heat / max_heat, 0.0, 1.0)

	# Wide ambient glow announces silhouette.
	var glow_color: Color = Color(0.35, 0.55, 1.0, 0.14).lerp(Color(1.0, 0.3, 0.1, 0.25), heat_ratio)
	var glow: PackedVector2Array = PackedVector2Array([
		Vector2(0, -22), Vector2(-23, 12), Vector2(23, 12),
	])
	draw_colored_polygon(glow, glow_color)

	# Fuselage
	var fuselage: PackedVector2Array = PackedVector2Array([
		Vector2(0, -20), Vector2(-4, -9), Vector2(-3, 3),
		Vector2(-5, 13), Vector2(0, 16), Vector2(5, 13),
		Vector2(3, 3), Vector2(4, -9),
	])
	draw_colored_polygon(fuselage, Color(0.08, 0.10, 0.19))
	var fuselage_outline: PackedVector2Array = fuselage.duplicate()
	fuselage_outline.append(fuselage[0])
	var outline_color: Color = Color(0.45, 0.95, 1.0).lerp(Color(1.0, 0.4, 0.2), heat_ratio * 0.7)
	draw_polyline(fuselage_outline, outline_color, 1.5)

	# Delta wings
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-3, -1), Vector2(-21, 9), Vector2(-15, 14), Vector2(-4, 9),
	])
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(3, -1), Vector2(21, 9), Vector2(15, 14), Vector2(4, 9),
	])
	draw_colored_polygon(wing_l, Color(0.27, 0.08, 0.48))
	draw_colored_polygon(wing_r, Color(0.27, 0.08, 0.48))
	var wing_l_outline: PackedVector2Array = wing_l.duplicate()
	wing_l_outline.append(wing_l[0])
	var wing_r_outline: PackedVector2Array = wing_r.duplicate()
	wing_r_outline.append(wing_r[0])
	draw_polyline(wing_l_outline, Color(0.85, 0.45, 1.0), 1.25)
	draw_polyline(wing_r_outline, Color(0.85, 0.45, 1.0), 1.25)

	# Wingtip fins
	draw_colored_polygon(PackedVector2Array([
		Vector2(-21, 9), Vector2(-25, 15), Vector2(-17, 12),
	]), Color(0.85, 0.45, 1.0, 0.8))
	draw_colored_polygon(PackedVector2Array([
		Vector2(21, 9), Vector2(25, 15), Vector2(17, 12),
	]), Color(0.85, 0.45, 1.0, 0.8))

	# Glowing canopy
	var w_color: Color = _get_weapon_color()
	var canopy: PackedVector2Array = PackedVector2Array([
		Vector2(0, -14), Vector2(-3.5, -4), Vector2(0, 2), Vector2(3.5, -4),
	])
	draw_colored_polygon(canopy, w_color)
	draw_polyline(PackedVector2Array([Vector2(0, -13), Vector2(0, 1)]), w_color.lerp(Color.WHITE, 0.5), 1.0)

	# Wing-mounted cannons
	draw_rect(Rect2(-22, 4, 6, 2.4), Color(0.55, 0.6, 0.68))
	draw_rect(Rect2(16, 4, 6, 2.4), Color(0.55, 0.6, 0.68))

	# Cannon thermal muzzle glow
	var muzzle_color: Color = w_color.lerp(Color(1.0, 0.35, 0.1, 0.95), heat_ratio)
	draw_circle(Vector2(-22, 5.2), 1.1 + 1.2 * heat_ratio, muzzle_color)
	draw_circle(Vector2(22, 5.2), 1.1 + 1.2 * heat_ratio, muzzle_color)

	# Overheat warning pulse
	if is_overheated:
		var warning_pulse: float = 0.5 + 0.5 * sin(_time * 16.0)
		draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 28, Color(1.0, 0.2, 0.15, 0.65 * warning_pulse), 1.8)

	# Engines
	draw_rect(Rect2(-9, 9, 4, 6), Color(0.95, 0.35, 0.12))
	draw_rect(Rect2(5, 9, 4, 6), Color(0.95, 0.35, 0.12))
	draw_rect(Rect2(-2.5, 12, 5, 5), Color(0.95, 0.35, 0.12))
	draw_rect(Rect2(-8, 13, 2.5, 3), Color(1.0, 0.8, 0.25))
	draw_rect(Rect2(5.5, 13, 2.5, 3), Color(1.0, 0.8, 0.25))
	draw_rect(Rect2(-1.7, 15, 3.4, 2.5), Color(1.0, 0.8, 0.25))

	# Flickering exhaust glow
	var flicker: float = 0.7 + 0.3 * absf(sin(_time * 14.0)) * absf(cos(_time * 5.0))
	var flame_h: float = 5.0 * flicker
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 17), Vector2(-6.5, 17 + flame_h), Vector2(-5, 17),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))
	draw_colored_polygon(PackedVector2Array([
		Vector2(5, 17), Vector2(6.5, 17 + flame_h), Vector2(8, 17),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1, 18), Vector2(0, 18 + flame_h * 1.1), Vector2(1, 18),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))

	# Nav lights
	var blink: float = 1.0 if fmod(_time, 1.0) < 0.6 else 0.2
	draw_circle(Vector2(-23, 12), 1.4, Color(1.0, 0.25, 0.25, blink))
	draw_circle(Vector2(23, 12), 1.4, Color(0.3, 1.0, 0.4, blink))
