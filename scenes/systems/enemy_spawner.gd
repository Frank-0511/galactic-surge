# enemy_spawner.gd
# Creates and moves the enemy formation as one synchronized group.
# Owns the exports, signals and state used by Main and the tests, plus the per-frame movement
# (edge bounce and descent). Logic lives in sibling modules that read and write this node through
# _spawner: enemy_spawner_waves.gd (wave table and difficulty), enemy_spawner_formation.gd (spawn
# and teardown), enemy_spawner_slots.gd (variants, slot positions, fly-in paths) and
# enemy_spawner_pressure.gd (dives and enrage).

extends Node2D

const WavesModule: Script = preload("res://scenes/systems/enemy_spawner_waves.gd")
const FormationModule: Script = preload("res://scenes/systems/enemy_spawner_formation.gd")
const SlotsModule: Script = preload("res://scenes/systems/enemy_spawner_slots.gd")
const PressureModule: Script = preload("res://scenes/systems/enemy_spawner_pressure.gd")
const DS := preload("res://scripts/systems/difficulty_settings.gd")

## Master switch for the tactical enemy AI (Stage 12, ADR 009). When false, the
## "variants" key of every wave config is ignored at spawn time and all enemies
## spawn as standard. The variant catalog and enemy_ai.gd stay intact; set to
## true to re-enable the tactical variants.
const ENEMY_AI_ENABLED: bool = true

## Emitted when an enemy directly collides with the player.
signal enemy_contacted_player(player: Node2D)

## Emitted once for every enemy destruction signal received.
signal enemy_destroyed(enemy: Area2D)

## Emitted exactly once when the last enemy of a wave is destroyed.
## wave_index is 0-based.
signal wave_cleared(wave_index: int)

## Emitted after the final wave (index 9) is cleared.
signal all_waves_cleared

## Emitted when all flying-in enemies of the current wave have settled into formation.
signal fly_in_completed_all

## Emitted when the formation enrage threshold is reached.
signal enrage_triggered

## Emitted when an enemy begins an offensive dive toward the player.
signal enemy_dived(enemy: Area2D)

## Emitted when an enemy returns from a dive and re-enters formation.
signal formation_rejoined(enemy: Area2D)

## Scene used for every member of the formation.
@export var enemy_scene: PackedScene = preload("res://scenes/entities/enemy/enemy.tscn")

## Number of horizontal formation rows.
@export var rows: int = 3

## Number of enemies per row.
@export var columns: int = 6

## Rotation of the formation in radians around its origin (Etapa 17). 0 keeps the layout.
@export var formation_rotation: float = 0.0

## Horizontal distance between enemy centers.
@export var horizontal_spacing: float = 72.0

## Vertical distance between enemy centers.
@export var vertical_spacing: float = 64.0

## Shared horizontal speed in pixels per second.
@export var formation_speed: float = 80.0

## Vertical step applied after reaching a viewport edge.
@export var descent_distance: float = 32.0

## Maximum vertical descent accumulated for the formation.
@export var max_formation_descent_y: float = 380.0

## Maximum Y position allowed for the lowest enemy in formation.
@export var max_formation_bottom_y: float = 480.0

## Whether enemies enter using Bézier curve fly-in.
@export var fly_in_enabled: bool = true

## Duration in seconds of each enemy's Bézier fly-in entrance.
@export var fly_in_duration: float = 1.2

## Wave elapsed seconds before enemies enter enrage state.
@export var enrage_time: float = 35.0

## Base interval in seconds between offensive dives.
@export var base_dive_interval: float = 4.2

## Half of the 36 px Enemy collision shape width.
const ENEMY_HALF_WIDTH: float = 18.0

## Waves past the first chapter (global index >= 10) start from the wave-10 configuration and
## get one extra difficulty step per wave: faster formation and fire, capped columns.
const GLOBAL_STEP_SPEED: float = 0.04
const GLOBAL_STEP_FIRE: float = 0.02
const MIN_FIRE_RATE_SCALE: float = 0.5
const DIFFICULTY_SPEED_STEP: float = 0.15
const MAX_FORMATION_COLUMNS: int = 8

## Campaign chapter (1-based). Later chapters speed up formations and add one column per level above 1.
var difficulty_level: int = 1

## Session difficulty tier (Etapa 18). Scales formation speed and density; COMMANDER keeps the base values.
var session_difficulty: int = DS.Tier.COMMANDER

var _direction: float = 1.0
var _is_running: bool = false
var _is_flying_in: bool = false
var _flying_in_count: int = 0
var _current_wave: int = 0
## Config in effect for the running wave (scaled for waves past chapter 1).
var _current_config: Dictionary = {}
var _alive_count: int = 0
var _wave_cleared_emitted: bool = false
var _formation_origin: Vector2 = Vector2.ZERO
var _first_row_y: float = 120.0
var _current_pattern_type: String = "grid"
var _current_trajectory: String = "swoop_left"

## Stage 9 temporal escalation and slot tracking
var _wave_timer: float = 0.0
var _is_enraged: bool = false
var _dive_cooldown_timer: float = 3.5
var _enemy_base_slots: Dictionary = {} # Area2D -> Vector2
var _formation_shift: Vector2 = Vector2.ZERO

var _waves: RefCounted = WavesModule.new(self)
var _formation: RefCounted = FormationModule.new(self)
var _slots: RefCounted = SlotsModule.new(self)
var _pressure: RefCounted = PressureModule.new(self)


## Sets the formation origin (center_x, first_row_y) from GameLayout.
func set_formation_layout(origin: Vector2, first_row_y: float) -> void:
	_formation_origin = origin
	_first_row_y = first_row_y


func _process(delta: float) -> void:
	if not _is_running or _is_flying_in:
		return

	# Temporal escalation (enrage countdown)
	if not _is_enraged:
		_wave_timer += delta
		if _wave_timer >= enrage_time:
			_pressure.trigger_enrage()

	var all_enemies: Array[Area2D] = _get_valid_enemies()
	if all_enemies.is_empty():
		return

	# Formation movement: only considers and displaces enemies actively IN FORMATION
	var formation_enemies: Array[Area2D] = []
	for enemy: Area2D in all_enemies:
		if enemy.has_method(&"is_in_formation") and not enemy.is_in_formation():
			continue
		formation_enemies.append(enemy)

	_pressure.tick_dives(delta, formation_enemies)

	# If no enemies are currently in formation, freeze formation shift to prevent off-screen drift
	if formation_enemies.is_empty():
		return

	var horizontal_delta: float = _direction * formation_speed * delta
	var viewport_rect: Rect2 = get_viewport_rect()
	var left_edge: float = formation_enemies[0].global_position.x - ENEMY_HALF_WIDTH
	var right_edge: float = formation_enemies[0].global_position.x + ENEMY_HALF_WIDTH
	for enemy: Area2D in formation_enemies:
		left_edge = minf(left_edge, enemy.global_position.x - ENEMY_HALF_WIDTH)
		right_edge = maxf(right_edge, enemy.global_position.x + ENEMY_HALF_WIDTH)

	# Strict edge bounce: only reverse direction if moving toward that wall
	var hit_right: bool = (_direction > 0.0 and right_edge + horizontal_delta >= viewport_rect.end.x)
	var hit_left: bool = (_direction < 0.0 and left_edge + horizontal_delta <= viewport_rect.position.x)

	if hit_right or hit_left:
		_direction = -1.0 if hit_right else 1.0

		# Clamp positions to prevent formation from remaining outside viewport bounds
		var clamp_x: float = 0.0
		if hit_right and right_edge > viewport_rect.end.x:
			clamp_x = viewport_rect.end.x - right_edge
		elif hit_left and left_edge < viewport_rect.position.x:
			clamp_x = viewport_rect.position.x - left_edge

		if absf(clamp_x) > 0.001:
			_formation_shift.x += clamp_x
			for enemy: Area2D in formation_enemies:
				enemy.position.x += clamp_x

		# Check descent ceiling: only descend if formation bottom remains within safe limits
		var can_descend: bool = (_formation_shift.y + descent_distance <= max_formation_descent_y)
		if can_descend:
			var lowest_y: float = -INF
			for enemy: Area2D in formation_enemies:
				lowest_y = maxf(lowest_y, enemy.global_position.y)
			if lowest_y + descent_distance > max_formation_bottom_y:
				can_descend = false

		if can_descend:
			_formation_shift.y += descent_distance
			for enemy: Area2D in formation_enemies:
				enemy.position.y += descent_distance
		return

	_formation_shift.x += horizontal_delta
	for enemy: Area2D in formation_enemies:
		enemy.position.x += horizontal_delta


func spawn_formation() -> void:
	_formation.spawn_formation()


func clear_formation() -> void:
	_formation.clear_formation()


func stop() -> void:
	_formation.stop()


func get_total_waves() -> int:
	return _waves.get_total_waves()


func get_current_wave() -> int:
	return _current_wave


func is_flying_in() -> bool:
	return _is_flying_in


func is_enraged() -> bool:
	return _is_enraged


func get_wave_config(wave_index: int) -> Dictionary:
	return _waves.get_wave_config(wave_index)


## Returns the wave config for a local index (0-9) at a global wave index (0-29).
func get_scaled_wave_config(local_index: int, global_index: int) -> Dictionary:
	return _waves.get_scaled_wave_config(local_index, global_index)


## wave_index is the local index (0-9); global_index (0-29, -1 = same as local) drives the
## difficulty ramp across chapters.
func start_wave(wave_index: int, global_index: int = -1) -> void:
	_waves.start_wave(wave_index, global_index)


func assign_variant_slots(variants: Dictionary, slot_count: int) -> Dictionary:
	return _slots.assign_variant_slots(variants, slot_count)


func trigger_dive(count: int = 1) -> Array[Area2D]:
	return _pressure.trigger_dive(count)


func _get_valid_enemies() -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies
