# player_arsenal.gd
# Weapon selection and power for one Player: switching between Blaster, Missile and Laser,
# power-level changes (clamped, synced to the laser beam), medallion and power-atom upgrades,
# the level penalty on death, and the laser beam node (created on demand). Owned by Player through _player.

extends RefCounted

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


## Selects an active weapon from WeaponType.
func set_weapon(type: int) -> void:
	if type < 0 or type >= _player.WEAPON_COUNT:
		return
	if _player.current_weapon == type:
		return
	if _player.current_weapon == _player.WeaponType.LASER:
		set_laser_active(false)
	_player._double_shot_enabled = false
	_player.current_weapon = type
	_player.weapon_changed.emit(_player.current_weapon)
	_player.queue_redraw()


## Cycles through weapons forward or backward.
func cycle_weapon(forward: bool = true) -> void:
	var delta_dir: int = 1 if forward else -1
	var next_type: int = (_player.current_weapon + delta_dir) % _player.WEAPON_COUNT
	if next_type < 0:
		next_type += _player.WEAPON_COUNT
	set_weapon(next_type)


## Sets weapon power level clamped between 1 and 15, emitting weapon_level_changed.
func set_weapon_level(level: int) -> void:
	var clamped: int = clampi(level, 1, _player.MAX_WEAPON_LEVEL)
	_player.weapon_level = clamped
	if _player._laser_beam != null and _player._laser_beam.has_method(&"set_power_level"):
		_player._laser_beam.call(&"set_power_level", _player.weapon_level)
	_player.weapon_level_changed.emit(_player.weapon_level)


## Applies a medallion drop. If it matches current weapon, upgrades level (+1).
## If it differs, switches weapon and preserves the accumulated weapon level (Chicken Invaders model).
func apply_medallion(weapon_type: int) -> void:
	if weapon_type == _player.current_weapon:
		set_weapon_level(_player.weapon_level + 1)
	else:
		set_weapon(weapon_type)
		set_weapon_level(_player.weapon_level)


## Applies a power atom drop. Upgrades weapon level (+1) without changing current weapon.
func apply_power_atom() -> void:
	set_weapon_level(_player.weapon_level + 1)


## Decrements weapon level by 1 on player death (if > 1) and returns lost levels (1 or 0).
func penalize_weapon_on_death() -> int:
	if _player.weapon_level > 1:
		set_weapon_level(_player.weapon_level - 1)
		return 1
	return 0


func ensure_laser_beam() -> Area2D:
	if is_instance_valid(_player._laser_beam):
		if _player._laser_beam.has_method(&"set_power_level"):
			_player._laser_beam.call(&"set_power_level", _player.weapon_level)
		return _player._laser_beam
	var existing: Area2D = _player.get_node_or_null("LaserBeam") as Area2D
	if is_instance_valid(existing):
		_player._laser_beam = existing
		if _player._laser_beam.has_method(&"set_power_level"):
			_player._laser_beam.call(&"set_power_level", _player.weapon_level)
		return _player._laser_beam
	if _player.laser_beam_scene == null:
		_player.laser_beam_scene = load("res://features/bullet/laser_beam.tscn") as PackedScene
	if _player.laser_beam_scene != null:
		_player._laser_beam = _player.laser_beam_scene.instantiate() as Area2D
		_player._laser_beam.set("shooter", _player)
		_player._laser_beam.position = Vector2(0.0, -20.0)
		_player.add_child(_player._laser_beam)
		if _player._laser_beam.has_method(&"set_power_level"):
			_player._laser_beam.call(&"set_power_level", _player.weapon_level)
		if _player._laser_beam.has_method(&"set_firing"):
			_player._laser_beam.call(&"set_firing", false)
		else:
			_player._laser_beam.visible = false
	return _player._laser_beam


func set_laser_active(active: bool) -> void:
	var beam: Area2D = ensure_laser_beam()
	if beam != null and is_instance_valid(beam):
		if beam.has_method(&"set_firing"):
			beam.call(&"set_firing", active)
		else:
			beam.visible = active
