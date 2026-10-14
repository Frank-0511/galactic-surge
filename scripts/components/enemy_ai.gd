# enemy_ai.gd
# Reusable enemy AI component (Stage 12): finite state machine PATROL -> DETECT ->
# ATTACK -> FLEE plus pure steering helpers (projectile evasion, swarm
# separation/cohesion, flee direction). It owns no nodes and moves nothing: the
# host enemy reads the state and the steering vectors, which keeps it testable.

extends RefCounted

enum State { PATROL, DETECT, ATTACK, FLEE }

## Emitted after every state transition.
signal state_changed(previous_state: State, new_state: State)

## Distance at which a target is noticed (PATROL -> DETECT).
var detect_range: float = 520.0

## Distance within which the attack is sustained; beyond it the target is lost.
var attack_range: float = 420.0

## Seconds spent in DETECT before committing to ATTACK.
var detect_time: float = 0.6

## Seconds an ATTACK lasts before returning to PATROL.
var attack_duration: float = 3.0

## Health ratio at or below which the unit flees (0.0 disables fleeing).
var flee_health_ratio: float = 0.0

## Seconds spent fleeing.
var flee_duration: float = 2.0

var _state: State = State.PATROL
var _state_time: float = 0.0
var _has_fled: bool = false


## Applies a configuration dictionary (keys match the property names).
func configure(config: Dictionary) -> void:
	detect_range = float(config.get("detect_range", detect_range))
	attack_range = float(config.get("attack_range", attack_range))
	detect_time = float(config.get("detect_time", detect_time))
	attack_duration = float(config.get("attack_duration", attack_duration))
	flee_health_ratio = float(config.get("flee_health_ratio", flee_health_ratio))
	flee_duration = float(config.get("flee_duration", flee_duration))


func get_state() -> State:
	return _state


func get_state_time() -> float:
	return _state_time


func is_attacking() -> bool:
	return _state == State.ATTACK


func is_fleeing() -> bool:
	return _state == State.FLEE


## Forces a transition (no-op when already in that state).
func set_state(new_state: State) -> void:
	if new_state == _state:
		return
	var previous: State = _state
	_state = new_state
	_state_time = 0.0
	if new_state == State.FLEE:
		_has_fled = true
	state_changed.emit(previous, new_state)


## Advances the FSM. target_position may be null when no target exists.
func update(delta: float, self_position: Vector2, target_position: Variant, health_ratio: float = 1.0) -> void:
	_state_time += delta
	var has_target: bool = target_position is Vector2
	var distance: float = INF
	if has_target:
		distance = self_position.distance_to(target_position as Vector2)

	var should_flee: bool = flee_health_ratio > 0.0 and health_ratio <= flee_health_ratio and not _has_fled

	match _state:
		State.PATROL:
			if should_flee:
				set_state(State.FLEE)
			elif distance <= detect_range:
				set_state(State.DETECT)
		State.DETECT:
			if should_flee:
				set_state(State.FLEE)
			elif distance > detect_range * 1.25:
				set_state(State.PATROL)
			elif _state_time >= detect_time:
				set_state(State.ATTACK)
		State.ATTACK:
			if should_flee:
				set_state(State.FLEE)
			elif distance > attack_range * 1.25 or _state_time >= attack_duration:
				set_state(State.PATROL)
		State.FLEE:
			if _state_time >= flee_duration:
				set_state(State.PATROL)


## Lateral dodge direction (-1, 0, 1) against slow projectiles heading toward us.
## projectiles: Array of Dictionary {"position": Vector2, "velocity": Vector2}.
## Only projectiles slower than max_evadable_speed are considered dodgeable.
static func compute_evasion_direction(
	self_position: Vector2,
	projectiles: Array,
	max_evadable_speed: float = 650.0,
	lateral_threat_width: float = 38.0,
	max_threat_distance: float = 260.0
) -> float:
	var best_time: float = INF
	var direction: float = 0.0
	for entry: Variant in projectiles:
		var proj: Dictionary = entry
		var pos: Vector2 = proj.get("position", Vector2.ZERO)
		var vel: Vector2 = proj.get("velocity", Vector2.ZERO)
		var speed: float = vel.length()
		if speed < 1.0 or speed > max_evadable_speed:
			continue
		var rel: Vector2 = self_position - pos
		var dist: float = rel.length()
		if dist > max_threat_distance:
			continue
		# Must be approaching.
		var closing: float = vel.normalized().dot(rel.normalized())
		if closing < 0.3:
			continue
		# Predicted lateral miss distance at closest approach.
		var time_to_reach: float = dist / speed
		var predicted: Vector2 = pos + vel * time_to_reach
		var lateral_miss: float = predicted.x - self_position.x
		if absf(lateral_miss) > lateral_threat_width:
			continue
		if time_to_reach < best_time:
			best_time = time_to_reach
			# Dodge away from the projectile's predicted line; tie -> away from its current x.
			var side: float = signf(self_position.x - predicted.x)
			if is_zero_approx(side):
				side = signf(self_position.x - pos.x)
			if is_zero_approx(side):
				side = 1.0
			direction = side
	return direction


## Boids-like steering: separation from close neighbors plus cohesion toward their centroid.
## Returns a unit-or-shorter vector (length <= 1).
static func compute_swarm_steering(
	self_position: Vector2,
	neighbor_positions: Array,
	separation_radius: float = 60.0,
	cohesion_radius: float = 220.0,
	separation_weight: float = 1.4,
	cohesion_weight: float = 0.6
) -> Vector2:
	var separation: Vector2 = Vector2.ZERO
	var centroid: Vector2 = Vector2.ZERO
	var cohesion_count: int = 0
	for entry: Variant in neighbor_positions:
		var pos: Vector2 = entry
		var offset: Vector2 = self_position - pos
		var dist: float = offset.length()
		if dist < 0.001 or dist > cohesion_radius:
			continue
		centroid += pos
		cohesion_count += 1
		if dist < separation_radius:
			separation += offset.normalized() * (1.0 - dist / separation_radius)
	var cohesion: Vector2 = Vector2.ZERO
	if cohesion_count > 0:
		centroid /= float(cohesion_count)
		var to_centroid: Vector2 = centroid - self_position
		if to_centroid.length() > separation_radius:
			cohesion = to_centroid.normalized()
	var steering: Vector2 = separation * separation_weight + cohesion * cohesion_weight
	if steering.length() > 1.0:
		steering = steering.normalized()
	return steering


## Unit vector pointing away from the threat, biased upward (retreat toward the top).
static func compute_flee_direction(self_position: Vector2, threat_position: Vector2) -> Vector2:
	var away: Vector2 = self_position - threat_position
	if away.length_squared() < 0.0001:
		return Vector2.UP
	var flee: Vector2 = Vector2(away.normalized().x, -0.6)
	return flee.normalized()
