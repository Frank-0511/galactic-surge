# combo_system.gd
# Tracks consecutive enemy eliminations within a decay time window to calculate
# score multipliers (1x to 4x) and drive combo UI feedback.

class_name ComboSystem
extends Node

## Emitted whenever the combo multiplier, kill count, or remaining time ratio updates.
signal combo_updated(multiplier: int, kills: int, time_ratio: float)

## Emitted when the combo streak decays to zero or is forcibly reset.
signal combo_reset

## Time window in seconds before the combo multiplier decays back to 1x.
const DECAY_DURATION: float = 3.0

## Minimum kill count required to reach each multiplier tier.
const MULTIPLIER_THRESHOLDS: Dictionary = {
	1: 0,
	2: 3,
	3: 6,
	4: 10,
}

## Total kills accumulated in current uninterrupted streak.
var combo_kills: int = 0

## Current score multiplier applied to defeated enemies (1 to 4).
var combo_multiplier: int = 1

## Remaining time in seconds before combo decays.
var time_remaining: float = 0.0


func _process(delta: float) -> void:
	if time_remaining > 0.0:
		time_remaining = maxf(0.0, time_remaining - delta)
		if time_remaining == 0.0:
			reset_combo()
		else:
			combo_updated.emit(combo_multiplier, combo_kills, time_remaining / DECAY_DURATION)


## Registers an enemy elimination, recalculates the multiplier tier,
## and restarts the decay timer. Returns the updated multiplier.
func register_kill() -> int:
	combo_kills += 1
	if combo_kills >= 10:
		combo_multiplier = 4
	elif combo_kills >= 6:
		combo_multiplier = 3
	elif combo_kills >= 3:
		combo_multiplier = 2
	else:
		combo_multiplier = 1

	time_remaining = DECAY_DURATION
	combo_updated.emit(combo_multiplier, combo_kills, 1.0)
	return combo_multiplier


## Immediately resets the streak, multiplier, and decay timer back to base state.
func reset_combo() -> void:
	combo_kills = 0
	combo_multiplier = 1
	time_remaining = 0.0
	combo_reset.emit()
	combo_updated.emit(1, 0, 0.0)


## Returns the currently active score multiplier.
func get_multiplier() -> int:
	return combo_multiplier


## Returns the total kills in the active combo chain.
func get_kills() -> int:
	return combo_kills


## Returns the normalized time ratio remaining (0.0 to 1.0).
func get_time_ratio() -> float:
	if DECAY_DURATION > 0.0:
		return clampf(time_remaining / DECAY_DURATION, 0.0, 1.0)
	return 0.0
