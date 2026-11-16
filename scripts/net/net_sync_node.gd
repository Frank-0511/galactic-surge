# net_sync_node.gd
# Replication node of a network match (Etapa 20 T1 to T4, S1 to S3). Lives at Main/NetSync on both peers.
# Host: simulates J1, J2, the enemies and the boss, sends their state to the client, applies the client's input
# (move and shoot intent) to J2, and broadcasts every volley as a shot event. Client: sends its own input (the J2
# keys) to the host and applies the state and shots the host sends; it never simulates ships, enemies or the boss,
# and never applies damage. Explicit RPCs, not MultiplayerSynchronizer (decision L5). Shot events live in
# net_sync_shots.gd; enemies and the boss in net_sync_enemies.gd and net_sync_boss.gd.
# Loot, asteroids, score, the end of the match and laser beams: net_sync_loot, _asteroids, _score, _laser.gd.
# Wave transitions and announcements: net_sync_waves.gd. Ship state: net_sync_ships.gd.

extends Node

const PlayerInput: GDScript = preload("res://features/player/player_input.gd")
const NetSyncShots: GDScript = preload("res://scripts/net/net_sync_shots.gd")
const NetSyncEnemies: GDScript = preload("res://scripts/net/net_sync_enemies.gd")
const NetSyncLoot: GDScript = preload("res://scripts/net/net_sync_loot.gd")
const NetSyncAsteroids: GDScript = preload("res://scripts/net/net_sync_asteroids.gd")
const NetSyncScore: GDScript = preload("res://scripts/net/net_sync_score.gd")
const NetSyncBullets: GDScript = preload("res://scripts/net/net_sync_bullets.gd")
const NetSyncLaser: GDScript = preload("res://scripts/net/net_sync_laser.gd")
const NetSyncDisconnect: GDScript = preload("res://scripts/net/net_sync_disconnect.gd")
const NetSyncWaves: GDScript = preload("res://scripts/net/net_sync_waves.gd")
const NetSyncShips: GDScript = preload("res://scripts/net/net_sync_ships.gd")
## Seconds between state packets (host) or input packets (client): 20 per second.
const SEND_INTERVAL: float = 0.05

var _main: Node2D = null
var _is_host: bool = false
var _remote_peer: int = 0
var _accumulator: float = 0.0
var _enemies: RefCounted = null
var _loot: RefCounted = null
var _asteroids: RefCounted = null
var _bullets: RefCounted = null
var _waves: RefCounted = null
## Reliable events the host sends on the next physics frame: [rpc method, payload] pairs.
var _outbox: Array = []


## Binds the node to Main and sets each ship's role. Call after J2 exists.
func setup(main: Node2D, is_host: bool) -> void:
	_main = main
	_is_host = is_host
	_remote_peer = 0
	_enemies = NetSyncEnemies.new(main)
	_loot = NetSyncLoot.new(main, self)
	_asteroids = NetSyncAsteroids.new(main, self)
	_bullets = NetSyncBullets.new(main, self)
	_waves = NetSyncWaves.new(main, self)
	_main._enemy_spawner.set("replica", not is_host)
	if _is_host:
		_main._player_two.set("remote_driven", true)
		multiplayer.peer_disconnected.connect(handle_peer_lost)
		_main._player.volley_fired.connect(_on_volley.bind(1))
		_main._player_two.volley_fired.connect(_on_volley.bind(2))
	else:
		_main._player.set("replica", true)
		_main._player_two.set("replica", true)


func _physics_process(delta: float) -> void:
	if _main == null:
		return
	if _is_host:
		_flush_outbox()
	if not _main._session_active or not _has_remote_peer():
		return
	if _is_host:
		_bullets.scan_host()
	_accumulator += delta
	if _accumulator < SEND_INTERVAL:
		return
	_accumulator = 0.0
	if _is_host:
		rpc("rpc_host_state", build_state())
		var removed: Array = _enemies.take_pending_removed()
		if not removed.is_empty():
			rpc("rpc_host_removed", removed)
	else:
		rpc_id(1, "rpc_client_input", local_input_direction(), local_shoot_intent())


## Client -> host: the client's move direction for J2 (-1, 0 or 1) and its shoot intent. Accepted from the first client only.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_client_input(direction: float, shoot: bool = false) -> void:
	if not _is_host or _main == null or _main._player_two == null:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0:
		if _remote_peer == 0:
			_remote_peer = sender
		if sender != _remote_peer:
			return
	_main._player_two.set("remote_direction", clampf(direction, -1.0, 1.0))
	_main._player_two.set("remote_shoot", shoot)


## Host -> client: the authoritative state of J1 and J2. Only the host (the authority) may send it.
@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_host_state(state: Dictionary) -> void:
	apply_host_state(state)


## Host -> client: the enemy and boss ids the host removed since the last state. Reliable: a freed replica must not linger.
@rpc("authority", "call_remote", "reliable")
func rpc_host_removed(ids: Array) -> void:
	if _is_host or _main == null or _enemies == null:
		return
	_enemies.remove_ids(ids)


## Host -> client: one volley the host fired (ship, weapon, level, origin, aim). Reliable: a lost shot is visible.
@rpc("authority", "call_remote", "reliable")
func rpc_host_shot(event: Dictionary) -> void:
	if _is_host or _main == null:
		return
	NetSyncShots.replay(_main, event)


## Host -> client: an enemy or boss bullet was spawned (id, kind, variant, origin, velocity, gravity). Reliable.
@rpc("authority", "call_remote", "reliable")
func rpc_host_bullet_spawned(event: Dictionary) -> void:
	if _is_host or _bullets == null:
		return
	_bullets.apply_spawn(event)


## Host -> client: the ids of enemy or boss bullets that died (hit, left, cleared or detonated). Reliable.
@rpc("authority", "call_remote", "reliable")
func rpc_host_bullets_removed(ids: Array) -> void:
	if _is_host or _bullets == null:
		return
	_bullets.remove_ids(ids)


## Host -> client: a loot drop appeared (id, type, position). Reliable: its pickup event must find the replica.
@rpc("authority", "call_remote", "reliable")
func rpc_host_loot_spawned(event: Dictionary) -> void:
	if _is_host or _loot == null:
		return
	_loot.apply_spawn(event)


## Host -> client: a loot drop was picked up (id, collector 1 or 2). Reliable.
@rpc("authority", "call_remote", "reliable")
func rpc_host_loot_picked(event: Dictionary) -> void:
	if _is_host or _loot == null:
		return
	_loot.apply_pickup(event)


## Host -> client: the asteroid ids that left since the last state. Reliable: a freed replica must not linger.
@rpc("authority", "call_remote", "reliable")
func rpc_host_asteroids_removed(ids: Array) -> void:
	if _is_host or _asteroids == null:
		return
	_asteroids.remove_ids(ids)


## Host -> client: the match ended (game over or mission complete) with the final scores. Reliable.
@rpc("authority", "call_remote", "reliable")
func rpc_host_session_end(event: Dictionary) -> void:
	if _is_host or _main == null:
		return
	NetSyncScore.apply_session_end(_main, event)


## Host -> client: a wave was cleared (or a chapter starts): the announcement text, the wave and the state. Reliable.
@rpc("authority", "call_remote", "reliable")
func rpc_host_wave_transition(event: Dictionary) -> void:
	if _is_host or _waves == null:
		return
	_waves.apply_transition(event)


## Host side: the state of both ships, as sent to the client.
func build_state() -> Dictionary:
	var state: Dictionary = {
		"j1": NetSyncShips.ship_state(_main._player, _main.lives),
		"j2": NetSyncShips.ship_state(_main._player_two, _main._player_two_lives),
	}
	if _is_host:
		if _enemies != null:
			_enemies.encode_into(state)
		if _asteroids != null:
			_asteroids.encode_into(state)
		NetSyncScore.encode_into(_main, state)
		NetSyncLaser.encode_into(_main, state)
		_waves.encode_into(state)
	return state


## Client side: copies the host state onto J1 and J2 (position, facing, lives, shield, weapon level).
func apply_host_state(state: Dictionary) -> void:
	if _is_host or _main == null:
		return
	NetSyncShips.apply_ship(_main, _main._player, state.get("j1", {}) as Dictionary, 1)
	NetSyncShips.apply_ship(_main, _main._player_two, state.get("j2", {}) as Dictionary, 2)
	if _enemies != null:
		_enemies.apply_state(state)
	if _asteroids != null:
		_asteroids.apply_state(state)
	if _waves != null:
		_waves.apply_state(state)
	NetSyncLaser.apply(_main, state)
	if _main.get("_session_active") == true:
		NetSyncScore.apply(_main, state)


## Queues a reliable event for the client; the host sends it on the next physics frame.
func queue_reliable(method: String, payload: Variant) -> void:
	_outbox.append([method, payload])


## Returns the queued reliable events as [method, payload] pairs and empties the queue.
func take_outbox() -> Array:
	var pending: Array = _outbox
	_outbox = []
	return pending


## Host side: a loot drop was created and configured on the host; queues its spawn event and reports its pickup.
func announce_loot_spawn(loot: Node, loot_type: int, spawn_position: Vector2) -> void:
	if _is_host and _loot != null:
		_loot.announce_spawn(loot, loot_type, spawn_position)


## Host side: the match ended (kind "game_over" or "mission_complete"); queues the reliable event for the client.
func announce_session_end(kind: String) -> void:
	if _is_host and _main != null:
		queue_reliable("rpc_host_session_end", NetSyncScore.session_end_event(_main, kind))


## Host side: a wave was cleared and the host shows `phrase`; queues the transition for the client.
func announce_wave_transition(phrase: String) -> void:
	if _is_host and _waves != null:
		_waves.announce_transition(phrase)


## Host side: scans the enemy and boss bullets now (the physics path does this each frame with a client connected).
func announce_bullets() -> void:
	if _is_host and _bullets != null:
		_bullets.scan_host()


## Frees the client replicas of loot, asteroids and bullets (session end, new session or leaving the match).
func clear_replicas() -> void:
	if _loot != null:
		_loot.clear()
	if _asteroids != null:
		_asteroids.clear()
	if _bullets != null:
		_bullets.clear()
	NetSyncLaser.hide_all(_main)


## The client's own move direction, read from the J2 actions (arrows or left stick).
func local_input_direction() -> float:
	return Input.get_axis(PlayerInput.input_action_name("move_left", 2), PlayerInput.input_action_name("move_right", 2))


## The client's own shoot intent, read from the J2 shoot action (Shift or gamepad A).
func local_shoot_intent() -> bool:
	return Input.is_action_pressed(PlayerInput.input_action_name("shoot", 2))


## Host side: sends one volley of ship_index (1 or 2) to the client when a client is connected.
func _on_volley(weapon: int, level: int, origin: Vector2, aim: Vector2, double_shot: bool, ship_index: int) -> void:
	if _has_remote_peer():
		rpc("rpc_host_shot", NetSyncShots.make_event(ship_index, weapon, level, origin, aim, double_shot))


## Sends the queued reliable events in order. The queue is emptied even when no client is connected.
func _flush_outbox() -> void:
	var pending: Array = take_outbox()
	if not _has_remote_peer():
		return
	for entry: Variant in pending:
		rpc(String((entry as Array)[0]), (entry as Array)[1])

## Host side: a peer left the match. Only the J2 client counts (Etapa 20 T5); see net_sync_disconnect.gd.
func handle_peer_lost(peer_id: int) -> void:
	NetSyncDisconnect.host_peer_left(_main, _is_host, _remote_peer, peer_id)


func _exit_tree() -> void:
	clear_replicas()


func _has_remote_peer() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.get_peers().is_empty()
