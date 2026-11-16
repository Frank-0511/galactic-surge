# player_power_ups.gd
# Power-up state of one Player: the double-shot flag and the stacking shield (levels, duration
# bonus, ring visibility and expiry), plus clearing every power-up on elimination.
# Power-up state stays on Player; this module reads and writes it through _player.

extends RefCounted

const MAX_SHIELD_LEVEL: int = 3
## Extra duration (as a fraction of the base) added per level above 1: 10 s, 14 s, 18 s.
const SHIELD_LEVEL_DURATION_BONUS: float = 0.4

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


func enable_double_shot() -> void:
	_player._double_shot_enabled = true


func disable_double_shot() -> void:
	_player._double_shot_enabled = false


func has_double_shot() -> bool:
	return _player._double_shot_enabled


## Activates the shield. Picking one up while another is still active raises its level
## (up to MAX_SHIELD_LEVEL); each level lasts SHIELD_LEVEL_DURATION_BONUS longer.
func activate_shield(duration: float) -> void:
	_player._shield_level = mini(_player._shield_level + 1, MAX_SHIELD_LEVEL) if _player._shield_active else 1
	_player._shield_active = true
	if _player._shield_ring != null:
		_player._shield_ring.visible = true
		if _player._shield_ring.has_method(&"set_level"):
			_player._shield_ring.call(&"set_level", _player._shield_level)
	if _player._shield_timer != null:
		_player._shield_timer.wait_time = duration * (1.0 + SHIELD_LEVEL_DURATION_BONUS * float(_player._shield_level - 1))
		_player._shield_timer.start()


func has_shield() -> bool:
	return _player._shield_active


## Current shield level: 0 when there is no shield, otherwise 1 to MAX_SHIELD_LEVEL.
func get_shield_level() -> int:
	return _player._shield_level if _player._shield_active else 0


## Client side of the replicated shield (Etapa 20 T1): sets the level and ring without timers; 0 clears it.
func apply_replicated_shield(level: int) -> void:
	_player._shield_active = level > 0
	_player._shield_level = clampi(level, 0, MAX_SHIELD_LEVEL)
	if _player._shield_ring != null:
		_player._shield_ring.visible = level > 0
		if level > 0 and _player._shield_ring.has_method(&"set_level"):
			_player._shield_ring.call(&"set_level", level)


func clear_power_ups() -> void:
	_player._double_shot_enabled = false
	_player._shield_active = false
	_player._shield_level = 0
	if _player._shield_timer != null:
		_player._shield_timer.stop()
	if _player._shield_ring != null:
		_player._shield_ring.visible = false
	_player._set_laser_active(false)


func on_shield_timeout() -> void:
	_player._shield_active = false
	_player._shield_level = 0
	if _player._shield_ring != null:
		_player._shield_ring.visible = false
