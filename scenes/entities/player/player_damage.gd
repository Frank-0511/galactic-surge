# player_damage.gd
# Damage and availability of one Player: damage requests, respawn with the post-respawn
# invulnerability blink, timed invulnerability grants, the eliminated-ship state (gameplay off,
# collision layers off, Etapa 20) and the first-alive-ship lookup used by enemies and the boss.
# Owned by Player through _player.

extends RefCounted

## Collision values of the ship in player.tscn (layer 1, mask 12).
const PLAYER_COLLISION_LAYER: int = 1
const PLAYER_COLLISION_MASK: int = 12

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


func take_damage() -> bool:
	if _player._is_invulnerable or not _player._gameplay_enabled:
		return false
	if _player._shield_active:
		return false
	_player.damage_requested.emit(_player)
	return true


func respawn(respawn_position: Vector2) -> void:
	_player.position = respawn_position
	set_body_collision(true)
	_player._is_invulnerable = true
	_player.visible = true
	_player._set_laser_active(false)
	_player._heat.reset_heat()
	if _player._invulnerability_timer != null:
		_player._invulnerability_timer.start(_player.invulnerability_duration)
	if _player._blink_timer != null:
		_player._blink_timer.start(_player.blink_interval)


## Grants a timed invulnerability window (e.g. after clearing a wave). Reuses the
## respawn invulnerability state, so enemy hits are ignored until it expires.
func grant_invulnerability(duration: float) -> void:
	_player._is_invulnerable = true
	if _player._invulnerability_timer != null:
		_player._invulnerability_timer.start(duration)


## Seconds left of the current invulnerability window, or 0.0 when vulnerable.
func get_invulnerability_time_left() -> float:
	if not _player._is_invulnerable or _player._invulnerability_timer == null:
		return 0.0
	return _player._invulnerability_timer.time_left


func set_gameplay_enabled(enabled: bool) -> void:
	_player._gameplay_enabled = enabled
	set_body_collision(enabled)
	if not _player._gameplay_enabled:
		_player.velocity = Vector2.ZERO
		_player._set_laser_active(false)


## Puts the ship on or off the collision layers. An eliminated ship is in layer 0 and
## detects nothing, so enemies and bullets do not hit an invisible ship (Etapa 20 fix).
func set_body_collision(active: bool) -> void:
	_player.collision_layer = PLAYER_COLLISION_LAYER if active else 0
	_player.collision_mask = PLAYER_COLLISION_MASK if active else 0


func on_invulnerability_timeout() -> void:
	_player._is_invulnerable = false
	if _player._blink_timer != null:
		_player._blink_timer.stop()
	# An eliminated ship (gameplay off) must stay hidden when its window ends (Etapa 20).
	if _player._gameplay_enabled:
		_player.visible = true
	_player.invulnerability_ended.emit()


func on_blink_timeout() -> void:
	if _player._is_invulnerable and _player._gameplay_enabled:
		_player.visible = not _player.visible


## First ship of the "player" group that is alive (collision layer on). Enemies and the boss
## aim with it, so an eliminated ship is never a target (Etapa 20 fix).
static func first_alive_ship(tree: SceneTree) -> Node2D:
	for node: Node in tree.get_nodes_in_group(&"player"):
		var ship: CharacterBody2D = node as CharacterBody2D
		if ship != null and is_instance_valid(ship) and ship.collision_layer != 0:
			return ship
	return null
