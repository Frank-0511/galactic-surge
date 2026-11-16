# enemy_weapons.gd
# Firing cadence of one Enemy: the shoot-cooldown timeout, the burst fire of multi-shot variants,
# the next-shot scheduling (halved while attacking) and the enraged cooldown scaling.
# Owned by Enemy through _enemy.

extends RefCounted

var _burst_remaining: int = 0
var _burst_timer: float = 0.0

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


func schedule_next_shot() -> void:
	var attack_scale: float = 0.5 if (_enemy._ai != null and _enemy._ai.is_attacking()) else 1.0
	_enemy._shoot_cooldown.start(randf_range(_enemy.min_shoot_cooldown, _enemy.max_shoot_cooldown) * attack_scale)


func on_shoot_cooldown_timeout() -> void:
	if _enemy._destroyed:
		return
	var burst_count: int = int(_enemy._variant_def.get("burst_count", 1))
	_enemy._fire_bullet(-10.0 if burst_count > 1 else 0.0)
	schedule_next_shot()
	if burst_count > 1:
		_burst_remaining = burst_count - 1
		_burst_timer = float(_enemy._variant_def.get("burst_interval", 0.1))


func process_burst(delta: float) -> void:
	if _burst_remaining <= 0:
		return
	if _enemy._shoot_cooldown == null or _enemy._shoot_cooldown.is_stopped():
		_burst_remaining = 0
		return
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		var index: int = int(_enemy._variant_def.get("burst_count", 1)) - _burst_remaining
		_burst_remaining -= 1
		_burst_timer = float(_enemy._variant_def.get("burst_interval", 0.1))
		_enemy._fire_bullet(float(index - 1) * 10.0)


## Enraged enemies fire at half the cooldown; leaving the rage restores it.
func set_enraged(enraged: bool) -> void:
	if _enemy._is_enraged == enraged:
		return
	_enemy._is_enraged = enraged
	var factor: float = 0.5 if _enemy._is_enraged else 2.0
	_enemy.min_shoot_cooldown *= factor
	_enemy.max_shoot_cooldown *= factor
