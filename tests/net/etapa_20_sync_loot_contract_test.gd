extends SceneTree
# Contract test for Etapa 20 T17a to T21a and T27: host-owned loot drops and their client replicas (S1, S3, S5).
# Two peers are simulated in one process: RPC handlers are called directly with an arity check, and the host's
# reliable events are read from the sync node's outbox (the payloads it would send). Asteroids, score, lives and the
# end of the match are checked in etapa_20_sync_session_contract_test.gd.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_I: int = 7802
const HOST_PORT_K: int = 7804
const HOST_PORT_L: int = 7805
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const PLAY_BUTTON := "Control/Menu/PlayButton"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_assigns_drop_ids()
	await _check_host_spawn_events()
	await _check_host_pickup_events_name_collector()
	await _check_client_replica_drop_and_pickup()
	await _check_client_never_spawns_loot()
	await _check_singleplayer_loot_unchanged()

	if _failures == 0:
		print("ETAPA 20 SYNC LOOT CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC LOOT CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T17a (S1, task T4): the host gives every loot drop it spawns a unique, positive network id.
func _check_host_assigns_drop_ids() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_I)
	var main: Node = await _new_main()
	await _start_network_session(main)
	main.call("_spawn_loot", LootDrop.Type.SCORE, Vector2(200.0, 100.0))
	main.call("_spawn_loot", LootDrop.Type.SHIELD, Vector2(300.0, 100.0))
	var drops: Array = _loot_nodes(main)
	var ids: Dictionary = {}
	var valid: bool = drops.size() == 2
	for drop: Node in drops:
		var id: int = _net_id(drop)
		if id <= 0 or ids.has(id):
			valid = false
		ids[id] = true
	_expect(valid, "Contrato T17a: el host asigna un id de red unico y positivo a cada gota")
	_close_session(main, peer)


# T18 (S1, task T4): the host queues a reliable spawn event (id, type, position) for each drop, the recovery capsule included.
func _check_host_spawn_events() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_K)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.call("_spawn_loot", LootDrop.Type.SHIELD, Vector2(300.0, 150.0))
	var spawned: Array = _outbox(sync, "rpc_host_loot_spawned")
	var drops: Array = _loot_nodes(main)
	var event: Dictionary = {}
	if spawned.size() == 1:
		event = spawned[0] as Dictionary
	var same_id: bool = not drops.is_empty() and int(event.get("id", -1)) == _net_id(drops[0])
	var same_place: bool = Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))).is_equal_approx(Vector2(300.0, 150.0))
	_expect(spawned.size() == 1 and same_id and int(event.get("type", -1)) == LootDrop.Type.SHIELD and same_place, "Contrato T18a: el host envia un evento de aparicion fiable con id, tipo y posicion de la gota")
	var ships: RefCounted = main.get("_ships") as RefCounted
	if ships != null:
		ships.call("spawn_recovery_capsule", Vector2(150.0, 150.0))
	var capsules: Array = _outbox(sync, "rpc_host_loot_spawned")
	var capsule_ok: bool = capsules.size() == 1 and int((capsules[0] as Dictionary).get("type", -1)) == LootDrop.Type.RECOVERY_CAPSULE
	_expect(capsule_ok, "Contrato T18b: la capsula de recuperacion del host tambien envia su evento de aparicion")
	_close_session(main, peer)


# T19 (S3, task T4): a drop picked up on the host sends a reliable pickup event with its id and the collector (1 or 2).
func _check_host_pickup_events_name_collector() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_L)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.call("_spawn_loot", LootDrop.Type.SCORE, Vector2(200.0, 100.0))
	main.call("_spawn_loot", LootDrop.Type.SCORE, Vector2(260.0, 100.0))
	var drops: Array = _loot_nodes(main)
	_outbox(sync, "rpc_host_loot_spawned")
	var valid: bool = drops.size() == 2
	if valid:
		(drops[0] as Node).emit_signal("collected", LootDrop.Type.SCORE, main.get("_player_two"))
		(drops[1] as Node).emit_signal("collected", LootDrop.Type.SCORE, main.get("_player"))
	var picked: Array = _outbox(sync, "rpc_host_loot_picked")
	valid = valid and picked.size() == 2
	if valid:
		var first: Dictionary = picked[0] as Dictionary
		var second: Dictionary = picked[1] as Dictionary
		valid = int(first.get("id", -1)) == _net_id(drops[0]) and int(first.get("collector", -1)) == 2
		valid = valid and int(second.get("id", -1)) == _net_id(drops[1]) and int(second.get("collector", -1)) == 1
	_expect(valid, "Contrato T19a: la recogida en el host envia un evento fiable con el id de la gota y el colector (J2=2, J1=1)")
	_close_session(main, peer)


# T20a/T20b/T20c (S3, task T4): the client shows a drop as a visual replica from the spawn event (no pickup, no
# collision) and removes it on the pickup event; the client gains no points for that pickup (the host decides).
func _check_client_replica_drop_and_pickup() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var score_before: int = int(main.get("score"))
	_call_checked(sync, "rpc_host_loot_spawned", 1, [{"id": 9, "type": LootDrop.Type.SCORE, "x": 240.0, "y": 120.0}])
	var replica: Node = _replica_loot(main, 9)
	var shows: bool = replica != null and replica.get("replica") == true and replica.monitoring == false
	shows = shows and (replica as Node2D).position.is_equal_approx(Vector2(240.0, 120.0)) and int(replica.call("get_type")) == LootDrop.Type.SCORE
	_expect(shows, "Contrato T20a: el cliente crea una gota replica con el id, tipo y posicion del host, sin colision")
	_call_checked(sync, "rpc_host_loot_picked", 1, [{"id": 9, "collector": 2}])
	var gone: bool = replica != null and replica.is_queued_for_deletion() and replica.get("collected_by") == 2 and _replica_loot(main, 9) == null
	_expect(gone, "Contrato T20b: el evento de recogida quita la replica y registra que J2 la recogio")
	_expect(int(main.get("score")) == score_before, "Contrato T20c: el cliente no suma puntos por recoger una gota (los decide el host)")
	_close_session(main, peer)


# T21a (S1, task T4): a client never creates loot on its own: a spawn call on the client adds no drop.
func _check_client_never_spawns_loot() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var before: int = _loot_nodes(main).size()
	main.call("_spawn_loot", LootDrop.Type.SCORE, Vector2(200.0, 100.0))
	_expect(_loot_nodes(main).size() == before, "Contrato T21a: el cliente no crea gotas por su cuenta (solo las del host)")
	_close_session(main, peer)


# T27 (S5): singleplayer keeps its local drops: no network node, no net id, not a replica.
func _check_singleplayer_loot_unchanged() -> void:
	root.multiplayer.multiplayer_peer = null
	var solo: Node = await _new_main()
	var menu: CanvasLayer = solo.get_node_or_null("MainMenu") as CanvasLayer
	var play: Button = menu.get_node_or_null(PLAY_BUTTON) as Button if menu != null else null
	if play != null:
		play.pressed.emit()
	var before: int = _loot_nodes(solo).size()
	solo.call("_spawn_loot", LootDrop.Type.SCORE, Vector2(200.0, 100.0))
	var drops: Array = _loot_nodes(solo)
	var local_drop: bool = drops.size() == before + 1 and _net_id(drops.back()) == 0 and drops.back().get("replica") != true
	_expect(local_drop and solo.get_node_or_null(SYNC_NODE_NAME) == null, "Contrato T27: singleplayer sigue creando gotas locales, sin red ni replicas")
	_free_main(solo)


# Loot drops (LootDrop children of main) that are alive.
func _loot_nodes(main: Node) -> Array:
	return main.get_children().filter(func(c: Node) -> bool: return c is LootDrop and not c.is_queued_for_deletion())


# Replica drop with this net id on the client, or null.
func _replica_loot(main: Node, id: int) -> Node:
	for drop: Node in _loot_nodes(main):
		if _net_id(drop) == id and drop.get("replica") == true:
			return drop
	return null


# Payloads of the reliable events of one method that the host queued (the outbox is drained by this call).
func _outbox(sync: Node, method: String) -> Array:
	if sync == null or not sync.has_method("take_outbox"):
		return []
	var out: Array = []
	for entry: Variant in sync.call("take_outbox"):
		if String((entry as Array)[0]) == method:
			out.append((entry as Array)[1])
	return out


# net_id of a node as an int (0 when the node carries no id).
func _net_id(node: Node) -> int:
	var value: Variant = node.get("net_id")
	return int(value) if value != null else 0


# Calls an RPC only when the method exists with the expected arity; a wrong signature is a failure, never a silent pass.
func _call_checked(obj: Object, method: String, arity: int, args: Array) -> bool:
	if obj == null or obj.get_script() == null or not _has_arity(obj, method, arity):
		_expect(false, "RPC %s con aridad %d no existe en el nodo de sincronizacion" % [method, arity])
		return false
	obj.callv(method, args)
	return true


# True when obj's script has the method with that arity (a wrong RPC call would abort the check).
func _has_arity(obj: Object, method: String, arity: int) -> bool:
	return obj.get_script().get_script_method_list().any(func(e: Dictionary) -> bool: return e["name"] == method and (e["args"] as Array).size() == arity)


# Opens a Host on port: the scene multiplayer peer is the server (authority, peer id 1).
func _open_server(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port)
	_expect(err == OK, "Contrato T3 (precondicion): el host abre el puerto %d" % port)
	root.multiplayer.multiplayer_peer = peer
	return peer


# Joins a Host on port: the scene multiplayer peer is a client (not the authority).
func _open_client(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	root.multiplayer.multiplayer_peer = peer
	return peer


# Presses Coop en red in a fresh main and returns J2 (null when the session did not start).
func _start_network_session(main: Node) -> CharacterBody2D:
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var net_button: Button = menu.get_node_or_null(NET_COOP_BUTTON) as Button if menu != null else null
	if net_button != null:
		net_button.pressed.emit()
	return main.get("_player_two") as CharacterBody2D


func _close_session(main: Node, peer: MultiplayerPeer) -> void:
	root.multiplayer.multiplayer_peer = null
	peer.close()
	_free_main(main)


func _new_main() -> Node:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	return main


func _free_main(main: Node) -> void:
	root.remove_child(main)
	main.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		_failures += 1
		push_error("✗ %s" % message)
