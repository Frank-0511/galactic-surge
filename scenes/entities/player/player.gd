# player.gd
# Player ship controller: the public API (signals, exports, state, delegates) used by Main, the
# tests and other scripts. Behavior lives in the player_*.gd modules, owned through _player:
# input (movement), heat (overheat), arsenal (weapon selection and laser), weapons (firing),
# damage (respawn and invulnerability), power-ups (double shot, shield) and visuals (drawing).

extends CharacterBody2D

## Emitted when the ship requests life loss from valid hostile contact; carries the requesting ship.
signal damage_requested(ship: Node2D)

## Emitted when the post-respawn invulnerability blink window expires.
signal invulnerability_ended

## Emitted upon firing any weapon; receives true if double shot is engaged.
signal shot_fired(is_double_shot: bool)

## Emitted when active weapon changes (WeaponType enum value).
signal weapon_changed(new_weapon: int)

## Emitted when active weapon power level changes (1 to 15).
signal weapon_level_changed(new_level: int)

## Emitted for each volley this ship fires (Etapa 20 T2): weapon, level, origin, aim, double shot.
signal volley_fired(weapon: int, level: int, origin: Vector2, aim: Vector2, double_shot: bool)

## Emitted when barrel heat changes.
signal heat_changed(current_heat: float, max_heat: float)

## Emitted when thermal lock activates or clears.
signal overheat_state_changed(is_overheated: bool)

const InputModule: GDScript = preload("res://scenes/entities/player/player_input.gd")
const HeatModule: GDScript = preload("res://scenes/entities/player/player_heat.gd")
const ArsenalModule: GDScript = preload("res://scenes/entities/player/player_arsenal.gd")
const WeaponsModule: GDScript = preload("res://scenes/entities/player/player_weapons.gd")
const WeaponPatternsModule: GDScript = preload("res://scenes/entities/player/player_weapon_patterns.gd")
const DamageModule: GDScript = preload("res://scenes/entities/player/player_damage.gd")
const PowerUpsModule: GDScript = preload("res://scenes/entities/player/player_power_ups.gd")
const VisualsModule: GDScript = preload("res://scenes/entities/player/player_visuals.gd")

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
## Horizontal offset (px) between the two bullets fired in double-shot mode.
const DOUBLE_SHOT_SPREAD: float = 12.0
## Seconds of sustained fire before overheating, per weapon, at level 1 and level 10.
const OVERHEAT_SECONDS: Dictionary = {
	WeaponType.BLASTER: Vector2(10.0, 8.0),
	WeaponType.MISSILE: Vector2(9.0, 7.5),
	WeaponType.LASER: Vector2(8.0, 10.0),
}

## Power level of the current weapon system (1 to 15).
@export_range(1, 15) var weapon_level: int = 1

## Player slot: 1 uses the default actions, 2 uses the p2_ actions (coop local).
@export_range(1, 2) var player_index: int = 1

## Horizontal movement speed in pixels per second.
@export var speed: float = 480.0

## Default blaster projectile scene.
@export var bullet_scene: PackedScene = preload("res://features/bullet/bullet.tscn")

## Directional projectile used by the Ion Blaster.
@export var ion_bullet_scene: PackedScene = preload("res://features/bullet/spread_bullet.tscn")

## Backward compatibility property alias for tests expecting spread_bullet_scene.
var spread_bullet_scene: PackedScene:
	get:
		return ion_bullet_scene
	set(value):
		ion_bullet_scene = value

## Homing missile projectile scene.
@export var missile_scene: PackedScene = preload("res://features/bullet/missile.tscn")

## Continuous laser beam scene.
@export var laser_beam_scene: PackedScene = preload("res://features/bullet/laser_beam.tscn")

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

## Set by Main while a coop local session runs (J1 then reads A/D only).
var coop_active: bool = false

## Network roles (Etapa 20 T1). remote_driven: the host moves this ship from the client's input, not local keys.
## replica: the client only shows the host's state (no simulation, no damage).
var remote_driven: bool = false
var replica: bool = false
## Move direction (-1, 0 or 1) and shoot intent received from the client while remote_driven.
var remote_direction: float = 0.0
var remote_shoot: bool = false
## Horizontal facing from the last replicated state (-1, 0 or 1).
var facing: int = 0

## Local clock used only to animate engine flicker, lights, and heat pulsation.
var _time: float = 0.0

@onready var _shoot_cooldown: Timer = $ShootCooldown
@onready var _invulnerability_timer: Timer = $InvulnerabilityTimer
@onready var _blink_timer: Timer = $BlinkTimer
@onready var _shield_timer: Timer = $ShieldTimer
@onready var _shield_ring: Node2D = $ShieldRing
@onready var _laser_beam: Area2D = get_node_or_null("LaserBeam") as Area2D

var _input: RefCounted = InputModule.new(self)
var _heat: RefCounted = HeatModule.new(self)
var _arsenal: RefCounted = ArsenalModule.new(self)
var _weapons: RefCounted = WeaponsModule.new(self)
var _damage: RefCounted = DamageModule.new(self)
var _power_ups: RefCounted = PowerUpsModule.new(self)
var _visuals: RefCounted = VisualsModule.new(self)
var _cooling_delay_timer: float = 0.0
var _overheat_timer: float = 0.0
var _is_invulnerable: bool = false
var _gameplay_enabled: bool = true
var _double_shot_enabled: bool = false
var _shield_active: bool = false
var _shield_level: int = 0
var _horizontal_limits: Vector2 = Vector2.ZERO


func _ready() -> void:
	if bullet_scene == null:
		bullet_scene = load("res://features/bullet/bullet.tscn") as PackedScene
	if ion_bullet_scene == null:
		ion_bullet_scene = load("res://features/bullet/spread_bullet.tscn") as PackedScene
	if missile_scene == null:
		missile_scene = load("res://features/bullet/missile.tscn") as PackedScene
	if laser_beam_scene == null:
		laser_beam_scene = load("res://features/bullet/laser_beam.tscn") as PackedScene

	if _laser_beam == null and laser_beam_scene != null:
		_laser_beam = laser_beam_scene.instantiate() as Area2D
		if _laser_beam != null:
			_laser_beam.set("shooter", self)
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
	_heat.tick(delta)
	queue_redraw()

	if not _gameplay_enabled or replica:
		velocity = Vector2.ZERO
		_set_laser_active(false)
		return

	_input.move_and_clamp()
	_weapons.handle_shooting(delta)


func _draw() -> void:
	_visuals.draw_ship()


# Static helpers (input, colors, tables and the alive-ship lookup) delegate to their modules.
static func input_action_name(base: String, player_index: int) -> String:
	return InputModule.input_action_name(base, player_index)
static func ensure_p2_input_actions() -> void:
	InputModule.ensure_p2_input_actions()
static func ignores_arrow_keys(player_index: int, coop_active: bool) -> bool:
	return InputModule.ignores_arrow_keys(player_index, coop_active)
static func hull_outline_color(player_index: int) -> Color:
	return VisualsModule.hull_outline_color(player_index)
static func get_blaster_damage(level: int) -> int:
	return WeaponPatternsModule.blaster_damage(level)
static func first_alive_ship(tree: SceneTree) -> Node2D:
	return DamageModule.first_alive_ship(tree)

# Arsenal, weapons and heat.
func get_weapon() -> int:
	return current_weapon
func get_weapon_level() -> int:
	return weapon_level
func set_weapon(type: int) -> void:
	_arsenal.set_weapon(type)
func cycle_weapon(forward: bool = true) -> void:
	_arsenal.cycle_weapon(forward)
func set_weapon_level(level: int) -> void:
	_arsenal.set_weapon_level(level)
func apply_medallion(weapon_type: int) -> void:
	_arsenal.apply_medallion(weapon_type)
func apply_power_atom() -> void:
	_arsenal.apply_power_atom()
func penalize_weapon_on_death() -> int:
	return _arsenal.penalize_weapon_on_death()
func _ensure_laser_beam() -> Area2D:
	return _arsenal.ensure_laser_beam()
func _set_laser_active(active: bool) -> void:
	_arsenal.set_laser_active(active)
func simulate_shot() -> void:
	_heat.reset_heat()
	_weapons.shoot()
func add_heat(amount: float) -> void:
	_heat.add_heat(amount)
func cool_down(amount: float) -> void:
	_heat.cool_down(amount)
func reset_heat() -> void:
	_heat.reset_heat()
func is_weapon_overheated() -> bool:
	return is_overheated
func _get_heat_per_second(weapon: int) -> float:
	return _heat.heat_per_second(weapon)
func get_heat_per_second(weapon: int) -> float:
	return _heat.heat_per_second(weapon)

# Damage, respawn and invulnerability.
func take_damage() -> bool:
	return _damage.take_damage()
func respawn(respawn_position: Vector2) -> void:
	_damage.respawn(respawn_position)
func grant_invulnerability(duration: float) -> void:
	_damage.grant_invulnerability(duration)
func get_invulnerability_time_left() -> float:
	return _damage.get_invulnerability_time_left()
func set_gameplay_enabled(enabled: bool) -> void:
	_damage.set_gameplay_enabled(enabled)
func set_horizontal_limits(limits: Vector2) -> void:
	_horizontal_limits = limits
func _on_invulnerability_timer_timeout() -> void:
	_damage.on_invulnerability_timeout()
func _on_blink_timer_timeout() -> void:
	_damage.on_blink_timeout()

# Power-ups.
func enable_double_shot() -> void:
	_power_ups.enable_double_shot()
func disable_double_shot() -> void:
	_power_ups.disable_double_shot()
func has_double_shot() -> bool:
	return _power_ups.has_double_shot()
func activate_shield(duration: float) -> void:
	_power_ups.activate_shield(duration)
func has_shield() -> bool:
	return _power_ups.has_shield()
func get_shield_level() -> int:
	return _power_ups.get_shield_level()
func apply_replicated_shield(level: int) -> void:
	_power_ups.apply_replicated_shield(level)
func clear_power_ups() -> void:
	_power_ups.clear_power_ups()
func _on_shield_timer_timeout() -> void:
	_power_ups.on_shield_timeout()
