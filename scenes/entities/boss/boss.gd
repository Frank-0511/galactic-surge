# boss.gd
# Boss entity for Etapa 5 and Etapa 15: "Nave Nodriza Nexus" (default), "Crucero Espectro"
# and "Núcleo Blindado", selected per chapter through boss_variant.
# Autonomous Area2D in group "enemies" with vector neon art, phase-based attack patterns,
# dynamic banking tilt, sinusoidal cruise oscillation, dive maneuvers, and health-based defeat signaling.
# Behavior lives in the boss_*.gd modules, owned through _boss: movement (flight and dive), attacks
# (volleys and bullets), damage (armor phases, enrage, defeat), and visuals (drawing). This file keeps
# the public API (signals, exports, state, delegates) used by main, the HUD and the tests.

extends Area2D
const MovementModule: GDScript = preload("res://scenes/entities/boss/boss_movement.gd")
const AttacksModule: GDScript = preload("res://scenes/entities/boss/boss_attacks.gd")
const DamageModule: GDScript = preload("res://scenes/entities/boss/boss_damage.gd")
const VisualsModule: GDScript = preload("res://scenes/entities/boss/boss_visuals.gd")
const VariantVisualsModule: GDScript = preload("res://scenes/entities/boss/boss_visuals_variants.gd")

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
## Espectro volley sizes: a fan of 5 aimed at the player alternates with a ring of 8.
const SPECTRE_FAN_BULLET_COUNT: int = 5
const SPECTRE_RING_BULLET_COUNT: int = 8
const SPECTRE_FAN_BULLET_SPEED: float = 340.0
const SPECTRE_RING_BULLET_SPEED: float = 280.0
## Seconds between Espectro volleys. 13 bullets per two volleys every 3.25 s is the same
## average rate as the Nexus phase 1 (2 bullets per second), so damage pressure does not rise.
const SPECTRE_VOLLEY_INTERVAL: float = 3.25
## Enraged Espectro matches the Nexus phase 2 rate (about 7 bullets per second).
const SPECTRE_ENRAGED_VOLLEY_INTERVAL: float = 0.95

## Maximum health points.
@export var max_health: int = 150

## Projectile scene used for boss attacks.
@export var boss_bullet_scene: PackedScene = preload("res://scenes/entities/boss/boss_bullet.tscn")

## Base hover elevation in cruise mode.
@export var base_y: float = 140.0

## Boss variant: "nexus" (chapter 1, default), "espectro" (chapter 2) or "blindado" (chapter 3).
@export var boss_variant: StringName = &"nexus"

## Enables the three-phase Núcleo Blindado mode. Set by main.gd for chapter 3 only.
var multi_phase_enabled: bool = false

## True on a client replica (Etapa 20 T3): the host moves, shoots and takes damage; the replica only shows its state.
## A replica has no collision either: its area monitoring and detection are off.
var replica: bool = false:
	set(value):
		replica = value
		monitoring = not value
		monitorable = not value

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
var _shoot_cycle_spectre: int = 0
var _armor_phase: ArmorPhase = ArmorPhase.EXTERIOR_ARMOR

var _movement: RefCounted = MovementModule.new(self)
var _attacks: RefCounted = AttacksModule.new(self)
var _damage: RefCounted = DamageModule.new(self)
var _visuals: RefCounted = VisualsModule.new(self)
var _variant_visuals: RefCounted = VariantVisualsModule.new(self)


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

	if not replica:
		_movement.update(delta)
	queue_redraw()


## Triggers a dive maneuver telegraph towards player position or current X.
func trigger_dive() -> void:
	_movement.trigger_dive()


## Returns the current movement state.
func get_movement_state() -> MovementState:
	return _state


## Returns the Núcleo Blindado phase. Without multi-phase mode the boss stays in the exterior phase.
func get_armor_phase() -> ArmorPhase:
	return _damage.get_armor_phase()


func take_damage(amount: int = 1) -> void:
	_damage.take_damage(amount)


func _on_shoot_timer_timeout() -> void:
	if not replica:
		_attacks.on_shoot_timer_timeout()


## Client replica (Etapa 20 T3): copies the host's position, tilt, health, armor phase, movement state and enraged flag.
func apply_replica_state(data: Dictionary) -> void:
	position = Vector2(float(data["x"]), float(data["y"]))
	rotation = float(data["rot"])
	max_health = int(data["max_health"])
	health = int(data["health"])
	current_health = health
	is_enraged = bool(data["enraged"])
	_state = int(data["state"]) as MovementState
	_armor_phase = int(data["phase"]) as ArmorPhase
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	_damage.on_area_entered(area)


func _on_body_entered(body: Node2D) -> void:
	if _is_defeated or replica:
		return
	if body.is_in_group(&"player"):
		boss_contacted_player.emit(body)


func _draw() -> void:
	if boss_variant == &"espectro":
		_variant_visuals.draw_espectro()
	elif boss_variant == &"blindado":
		_variant_visuals.draw_blindado()
	else:
		_visuals.draw_nexus()
