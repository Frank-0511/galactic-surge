# session_stats.gd
# Post-session shot accuracy: single source of truth for shots and hits, plus pure math helpers.

extends RefCounted

## Player projectiles created this session (one per projectile instance).
static var shots: int = 0

## Player projectiles that damaged an enemy this session (one per projectile).
static var hits: int = 0


## Counts one player projectile created.
static func register_shot() -> void:
	shots += 1


## Counts one player projectile that damaged an enemy.
static func register_hit() -> void:
	hits += 1


## Clears the shot and hit counters for a new session.
static func reset() -> void:
	shots = 0
	hits = 0


## Accuracy percentage derived from the session counters.
static func get_accuracy() -> float:
	return accuracy_percent(hits, shots)


## Returns hits as a percentage of shots, clamped to [0, 100].
## Returns 0.0 when no shots were fired.
static func accuracy_percent(hits: int, shots: int) -> float:
	if shots <= 0:
		return 0.0
	return clampf(float(hits) / float(shots) * 100.0, 0.0, 100.0)
