# player_heat.gd
# Barrel heat for one Player: heat added by firing, passive cooling after a delay, the
# overheat lock that drains back to zero, and the heat-per-second curve per weapon and level.
# Owned by Player through _player; the heat state itself stays on Player (HUD and tests read it).

extends RefCounted

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


## Adds heat to the ship's barrel. Automatically engages overheat lock at max_heat.
func add_heat(amount: float) -> void:
	if _player.is_overheated:
		return
	_player._cooling_delay_timer = _player.cooling_delay
	var prev_heat: float = _player.heat
	_player.heat = minf(_player.max_heat, _player.heat + amount)
	if _player.heat >= _player.max_heat:
		_player.heat = _player.max_heat
		_player.is_overheated = true
		_player._overheat_timer = _player.overheat_duration
		_player._set_laser_active(false)
		_player.heat_changed.emit(_player.heat, _player.max_heat)
		_player.overheat_state_changed.emit(true)
	elif _player.heat != prev_heat:
		_player.heat_changed.emit(_player.heat, _player.max_heat)


## Dissipates an explicit amount of heat.
func cool_down(amount: float) -> void:
	var prev_heat: float = _player.heat
	_player.heat = maxf(0.0, _player.heat - amount)
	if _player.is_overheated and _player.heat <= 0.0:
		_player.heat = 0.0
		_player.is_overheated = false
		_player._overheat_timer = 0.0
		_player.heat_changed.emit(_player.heat, _player.max_heat)
		_player.overheat_state_changed.emit(false)
	elif _player.heat != prev_heat:
		_player.heat_changed.emit(_player.heat, _player.max_heat)


## Immediately resets heat to 0 and clears overheat lock.
func reset_heat() -> void:
	var was_overheated: bool = _player.is_overheated
	_player.heat = 0.0
	_player._cooling_delay_timer = 0.0
	_player._overheat_timer = 0.0
	_player.is_overheated = false
	if was_overheated:
		_player.overheat_state_changed.emit(false)
	_player.heat_changed.emit(_player.heat, _player.max_heat)


## Advances the overheat drain (while locked) or the passive cooling by delta seconds.
func tick(delta: float) -> void:
	if _player.is_overheated:
		_player._overheat_timer = maxf(0.0, _player._overheat_timer - delta)
		var decay_rate: float = _player.max_heat / _player.overheat_duration
		var prev_heat: float = _player.heat
		_player.heat = maxf(0.0, _player.heat - decay_rate * delta)
		if _player._overheat_timer <= 0.0 or _player.heat <= 0.0:
			_player.heat = 0.0
			_player.is_overheated = false
			_player._overheat_timer = 0.0
			_player.overheat_state_changed.emit(false)
		if _player.heat != prev_heat:
			_player.heat_changed.emit(_player.heat, _player.max_heat)
	else:
		if _player._cooling_delay_timer > 0.0:
			_player._cooling_delay_timer = maxf(0.0, _player._cooling_delay_timer - delta)
		elif _player.heat > 0.0:
			var prev_heat: float = _player.heat
			_player.heat = maxf(0.0, _player.heat - _player.cooling_rate * _player.cooling_scale * delta)
			if _player.heat != prev_heat:
				_player.heat_changed.emit(_player.heat, _player.max_heat)


## Heat per second needed so sustained fire overheats in the target time for the current level.
func heat_per_second(weapon: int) -> float:
	var range_s: Vector2 = _player.OVERHEAT_SECONDS.get(weapon, Vector2(8.0, 8.0))
	var t: float = float(clampi(_player.weapon_level, 1, _player.LEGACY_MAX_LEVEL) - 1) / float(_player.LEGACY_MAX_LEVEL - 1)
	var seconds: float = lerpf(range_s.x, range_s.y, t)
	return _player.max_heat / maxf(seconds, 0.1)
