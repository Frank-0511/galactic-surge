# net_sync_node.gd
# Replication node of a network match (Etapa 20 T1, S1/S3). Lives at Main/NetSync on both peers.
# Host: simulates J1 and J2, sends their state to the client and applies the client's input to J2.
# Client: sends its own input (the J2 keys) to the host and applies the state the host sends; it never
# simulates the ships and never applies damage. Explicit RPCs, not MultiplayerSynchronizer (decision L5).

extends Node

const PlayerInput: GDScript = preload("res://scenes/entities/player/player_input.gd")
## Seconds between state packets (host) or input packets (client): 20 per second.
const SEND_INTERVAL: float = 0.05

var _main: Node2D = null
var _is_host: bool = false
var _remote_peer: int = 0
var _accumulator: float = 0.0


## Binds the node to Main and sets each ship's role. Call after J2 exists.
func setup(main: Node2D, is_host: bool) -> void:
	_main = main
	_is_host = is_host
	_remote_peer = 0
	if _is_host:
		_main._player_two.set("remote_driven", true)
	else:
		_main._player.set("replica", true)
		_main._player_two.set("replica", true)


func _physics_process(delta: float) -> void:
	if _main == null or not _main._session_active or not _has_remote_peer():
		return
	_accumulator += delta
	if _accumulator < SEND_INTERVAL:
		return
	_accumulator = 0.0
	if _is_host:
		rpc("rpc_host_state", build_state())
	else:
		rpc_id(1, "rpc_client_input", local_input_direction())


## Client -> host: the client's move direction for J2 (-1, 0 or 1). Accepted from the first client only.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_client_input(direction: float) -> void:
	if not _is_host or _main == null or _main._player_two == null:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		if _remote_peer == 0:
			_remote_peer = sender
		if sender != _remote_peer:
			return
	_main._player_two.set("remote_direction", clampf(direction, -1.0, 1.0))


## Host -> client: the authoritative state of J1 and J2. Only the host (the authority) may send it.
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_host_state(state: Dictionary) -> void:
	apply_host_state(state)


## Host side: the state of both ships, as sent to the client.
func build_state() -> Dictionary:
	return {
		"j1": _ship_state(_main._player, _main.lives),
		"j2": _ship_state(_main._player_two, _main._player_two_lives),
	}


## Client side: copies the host state onto J1 and J2 (position, facing, lives, shield, weapon level).
func apply_host_state(state: Dictionary) -> void:
	if _is_host or _main == null:
		return
	_apply_ship(_main._player, state.get("j1", {}) as Dictionary, 1)
	_apply_ship(_main._player_two, state.get("j2", {}) as Dictionary, 2)


## The client's own move direction, read from the J2 actions (arrows or left stick).
func local_input_direction() -> float:
	return Input.get_axis(PlayerInput.input_action_name("move_left", 2), PlayerInput.input_action_name("move_right", 2))


static func _ship_state(ship: CharacterBody2D, lives: int) -> Dictionary:
	if ship == null:
		return {}
	return {
		"x": ship.position.x,
		"y": ship.position.y,
		"facing": int(signf(ship.velocity.x)),
		"lives": lives,
		"shield": ship.get_shield_level(),
		"weapon_level": ship.get_weapon_level(),
	}


func _apply_ship(ship: CharacterBody2D, data: Dictionary, index: int) -> void:
	if ship == null or data.is_empty():
		return
	ship.position = Vector2(float(data["x"]), float(data["y"]))
	ship.set("facing", int(data["facing"]))
	ship.set_weapon_level(int(data["weapon_level"]))
	ship.apply_replicated_shield(int(data["shield"]))
	var lives: int = int(data["lives"])
	if index == 1:
		_main.lives = lives
		_main._hud.set_lives(lives)
	else:
		_main._player_two_lives = lives
		_main._hud.set_lives_p2(lives)


func _has_remote_peer() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.get_peers().is_empty()
