# enemy.gd
# Enemy ship: the public API (signals, exports, state, delegates) used by the spawner, Main and the
# tests. Behavior lives in the enemy_*.gd modules, owned through _enemy: motion (fly-in, dive,
# return), weapons (cooldown and burst), tactics and steering (variants and AI), ballistics
# (bullet configuration), damage (deflector, death, contacts) and visuals (drawing).

extends Area2D

const MotionModule: GDScript = preload("res://features/enemy/enemy_motion.gd")
const WeaponsModule: GDScript = preload("res://features/enemy/enemy_weapons.gd")
const DamageModule: GDScript = preload("res://features/enemy/enemy_damage.gd")
const TacticsModule: GDScript = preload("res://features/enemy/enemy_tactics.gd")
const SteeringModule: GDScript = preload("res://features/enemy/enemy_steering.gd")
const BallisticsModule: GDScript = preload("res://features/enemy/enemy_ballistics.gd")
const VisualsModule: GDScript = preload("res://features/enemy/enemy_visuals.gd")

## Maximum displacement (px) applied on top of the formation slot by AI steering.
const MAX_AI_OFFSET_X: float = 48.0
const MAX_AI_OFFSET_Y: float = 30.0
const MAX_FLEE_OFFSET: float = 70.0
const HIT_FLASH_DURATION: float = 0.08

## High-level tactical lifecycle states of the enemy.
enum State { FORMATION, FLY_IN, DIVING, RETURNING, CHARGING }

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

## Emitted when the frontal deflector absorbs part of a hit (absorbed damage).
signal deflected(absorbed_damage: float)

## Emitted when the AI state machine changes state (EnemyAI.State values).
signal ai_state_changed(previous_state: int, new_state: int)

## Emitted when a suicide unit starts its high-speed charge.
signal charge_started

## Tactical variant id (see enemy_variants.gd). "standard" keeps the base enemy.
@export var variant_id: StringName = &"standard"

## Maximum hit points. Basic formation enemies die to one projectile hit.
@export var max_health: float = 1.0

## Minimum delay in seconds before a shot.
@export var min_shoot_cooldown: float = 1.25

## Maximum delay in seconds before a shot.
@export var max_shoot_cooldown: float = 2.5

## Projectile scene instantiated by this enemy.
@export var enemy_bullet_scene: PackedScene

## Last ship that damaged this enemy; kill points go to it (Etapa 20, kill attribution).
var last_attacker: Node = null

## Host-given network id (Etapa 20 T3); 0 when not networked.
var net_id: int = 0
## Client replica (T3): no AI, fire, motion, damage or collision; the host decides all of it.
var replica: bool = false:
	set(value):
		replica = value
		monitoring = not value
		monitorable = not value

@onready var _shoot_cooldown: Timer = $ShootCooldown

var health: float = 1.0
var _hit_flash_timer: float = 0.0
var _destroyed: bool = false

## Local clock and per-instance offset used only to animate a subtle idle
## breathing pulse, so a whole formation doesn't blink in perfect unison.
var _time: float = 0.0
var _pulse_offset: float = 0.0

## Active behavioral state.
var _state: State = State.FORMATION
var _is_flying_in: bool = false
var _is_enraged: bool = false

## Slot the enemy returns to (set by the spawner; motion lives in enemy_motion.gd).
var _slot_getter: Callable = Callable()

## Tactical variant / AI (Stage 12)
var _variant_applied: bool = false
var _variant_def: Dictionary = {}
var _ai: RefCounted = null
var _ai_offset: Vector2 = Vector2.ZERO
var _charge_direction: Vector2 = Vector2.DOWN
var _charge_elapsed: float = 0.0
var _charge_cooldown: float = 0.0
var _target_override: Variant = null

var _motion: RefCounted = MotionModule.new(self)
var _weapons: RefCounted = WeaponsModule.new(self)
var _damage: RefCounted = DamageModule.new(self)
var _tactics: RefCounted = TacticsModule.new(self)
var _steering: RefCounted = SteeringModule.new(self)
var _ballistics: RefCounted = BallisticsModule.new(self)
var _visuals: RefCounted = VisualsModule.new(self)


func _ready() -> void:
	_tactics.init_variant()
	health = max_health
	_pulse_offset = randf_range(0.0, TAU)
	if _state == State.FORMATION and not replica:
		_weapons.schedule_next_shot()


func _process(delta: float) -> void:
	if replica:
		_time += delta
		queue_redraw()
		return
	if not _destroyed:
		_tactics.process_ai(delta)
		_weapons.process_burst(delta)

	match _state:
		State.FLY_IN:
			_motion.process_fly_in(delta)
		State.DIVING:
			_motion.process_diving(delta)
		State.RETURNING:
			_motion.process_returning(delta)
		State.CHARGING:
			_steering.process_charging(delta)
		State.FORMATION:
			pass

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)

	_time += delta
	queue_redraw()


## Configures this enemy from the variant catalog. Safe before or after _ready().
func apply_variant(id: StringName) -> void:
	_tactics.apply_variant(id)


func get_variant_id() -> StringName: return variant_id
func get_variant_definition() -> Dictionary: return _variant_def.duplicate(true)
func get_ai() -> RefCounted: return _ai
func get_ai_offset() -> Vector2: return _ai_offset
func is_charging() -> bool: return _state == State.CHARGING
func has_deflector() -> bool: return bool(_variant_def.get("deflector", false))


## Overrides the AI target (Vector2) for testing; null restores the player lookup.
func set_target_override(target: Variant) -> void:
	_target_override = target


## Damage multiplier for a projectile travelling along travel_direction.
func get_deflector_multiplier(travel_direction: Vector2) -> float:
	return _damage.get_deflector_multiplier(travel_direction)


## Applies projectile damage honoring the frontal deflector.
func take_damage_from(amount: float, travel_direction: Vector2) -> void:
	_damage.take_damage_from(amount, travel_direction)


func _process_ai(delta: float) -> void:
	_tactics.process_ai(delta)


func _update_steering(delta: float) -> void:
	_steering.update_steering(delta)


func start_charge(target_pos: Vector2) -> void:
	_steering.start_charge(target_pos)


func _process_charging(delta: float) -> void:
	_steering.process_charging(delta)


func get_state() -> State: return _state
func is_in_formation() -> bool: return _state == State.FORMATION
func is_diving() -> bool: return _state == State.DIVING
func is_returning() -> bool: return _state == State.RETURNING
func is_flying_in() -> bool: return _state == State.FLY_IN or _is_flying_in


func set_slot_getter(getter: Callable) -> void:
	_slot_getter = getter


func start_dive(target_pos: Vector2, duration: float = 2.0, _dive_type: String = "swoop", slot_getter: Callable = Callable()) -> void:
	_motion.start_dive(target_pos, duration, _dive_type, slot_getter)


func return_to_slot(slot_getter: Callable, duration: float = 1.6) -> void:
	_motion.return_to_slot(slot_getter, duration)


func set_enraged(enraged: bool) -> void:
	_weapons.set_enraged(enraged)


func is_enraged() -> bool:
	return _is_enraged

## Client replica: copies the host's movement state, health and enraged flag (position is set by the caller).
func apply_replica_state(state: int, hp: float, enraged: bool) -> void:
	_motion.apply_replica_state(state, hp, enraged)


func start_fly_in(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, duration: float, delay: float = 0.0) -> void:
	_motion.start_fly_in(p0, p1, p2, p3, duration, delay)


func cancel_fly_in() -> void:
	_motion.cancel_fly_in()


func destroy() -> void:
	_damage.destroy()


## Applies damage (fractional values allowed, used by the continuous laser).
func take_damage(amount: float = 1.0) -> void:
	_damage.take_damage(amount)


## Signals to damage dealers that this target accepts fractional damage.
func supports_fractional_damage() -> bool:
	return true


func _on_area_entered(area: Area2D) -> void:
	PhysicsSafe.begin_callback()
	_damage.on_area_entered(area)
	PhysicsSafe.end_callback()


func _on_body_entered(body: Node2D) -> void:
	PhysicsSafe.begin_callback()
	_damage.on_body_entered(body)
	PhysicsSafe.end_callback()


func set_bullet_mix(normal_mix: Array, enraged_mix: Array) -> void:
	_ballistics.set_bullet_mix(normal_mix, enraged_mix)


## Multiplies the shoot cooldown range (>1.0 = slower fire).
func set_fire_rate_scale(scale: float) -> void:
	min_shoot_cooldown *= scale
	max_shoot_cooldown *= scale


func set_forced_bullet_variant(variant: int) -> void:
	_ballistics.set_forced_variant(variant)


func get_forced_bullet_variant() -> int:
	return _ballistics.get_forced_variant()


## Configures physical ballistic properties and plasma variant for spawned bullets.
func _configure_bullet(bullet: Node2D) -> void:
	_ballistics.configure_bullet(bullet)


func _on_shoot_cooldown_timeout() -> void:
	if not replica:
		_weapons.on_shoot_cooldown_timeout()


func _fire_bullet(lateral_offset: float = 0.0) -> void:
	if enemy_bullet_scene == null or not is_inside_tree():
		return
	var enemy_bullet: Node2D = enemy_bullet_scene.instantiate() as Node2D
	if enemy_bullet != null:
		_ballistics.configure_bullet(enemy_bullet)
		get_tree().current_scene.add_child(enemy_bullet)
		enemy_bullet.global_position = global_position + Vector2(0, 20)
		enemy_bullet.global_position.x += lateral_offset


func _draw() -> void:
	_visuals.draw_enemy()
