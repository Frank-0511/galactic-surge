extends SceneTree
# Contract test for Etapa 20 T10 to T16: enemy ids, replicated enemies, waves and boss replication (S2, S5).
# Two peers are simulated in one process: RPC handlers are called directly, and RPC wiring is
# checked through the node's RPC configuration.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_D: int = 7797
const HOST_PORT_E: int = 7798
const HOST_PORT_F: int = 7799
const HOST_PORT_G: int = 7800
const HOST_PORT_H: int = 7801
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const COOP_BUTTON := "Control/Menu/CoopButton"
const PLAY_BUTTON := "Control/Menu/PlayButton"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_assigns_enemy_ids()
	await _check_replica_created_on_client()
	await _check_host_removal_frees_replica()
	await _check_replica_has_no_collision_or_damage()
	await _check_client_spawner_off_in_network()
	await _check_boss_replica_follows_host()
	await _check_local_modes_spawn_enemies()

	if _failures == 0:
		print("ETAPA 20 SYNC CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T10 (S2, task T3): the host gives every enemy it spawns a unique replicated id (0 is reserved for the boss).
func _check_host_assigns_enemy_ids() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_D)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var ids: Dictionary = {}
	var nodes: Array = _enemy_nodes(main)
	var valid: bool = not nodes.is_empty()
	for node: Node in nodes:
		var id: int = _net_id(node)
		if id <= 0 or ids.has(id):
			valid = false
		ids[id] = true
	_expect(valid, "Contrato T10a: el host asigna un id de red unico a cada enemigo que crea")
	_close_session(main, peer)


# T11 (S2, task T3): the host's replicated state reaches the client and creates one replica per enemy, with the same position and variant.
func _check_replica_created_on_client() -> void:
	var host: Dictionary = await _host_session(HOST_PORT_E, 1)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	_call_checked(main.get_node_or_null(SYNC_NODE_NAME), "rpc_host_state", 1, [host["state"]])
	var replicas: Dictionary = _replica_by_id(main)
	var truth: Dictionary = host["truth"]
	_expect(not truth.is_empty() and replicas.size() == truth.size(), "Contrato T11a: el cliente crea un replica por cada enemigo del host")
	var same: bool = not truth.is_empty()
	for id: int in truth:
		if not replicas.has(id):
			same = false
			continue
		var replica: Node2D = replicas[id] as Node2D
		if not replica.position.is_equal_approx(truth[id]["pos"]) or String(replica.call("get_variant_id")) != truth[id]["variant"]:
			same = false
	_expect(same, "Contrato T11b: cada replica tiene la posicion y la variante del enemigo del host")
	_close_session(main, peer)


# T12 (S2, task T3): a removal event from the host frees the replica with that id on the client; the others stay.
func _check_host_removal_frees_replica() -> void:
	var host: Dictionary = await _host_session(HOST_PORT_F, 1)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(sync, "rpc_host_state", 1, [host["state"]])
	var before: Dictionary = _replica_by_id(main)
	var gone_id: int = int(before.keys()[0]) if not before.is_empty() else -1
	_call_checked(sync, "rpc_host_removed", 1, [[gone_id]])
	var after: Dictionary = _replica_by_id(main)
	_expect(not before.is_empty() and not after.has(gone_id) and after.size() == before.size() - 1, "Contrato T12a: una baja del host libera el replica del cliente y deja los demas")
	_close_session(main, peer)


# T13 (S2, task T3): a replica has no collision and never takes damage or touches the player.
func _check_replica_has_no_collision_or_damage() -> void:
	var host: Dictionary = await _host_session(HOST_PORT_G, 1)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	_call_checked(main.get_node_or_null(SYNC_NODE_NAME), "rpc_host_state", 1, [host["state"]])
	var replicas: Dictionary = _replica_by_id(main)
	if replicas.is_empty():
		_expect(false, "Contrato T13a: el replica no colisiona (faltan replicas)")
		_close_session(main, peer)
		return
	var replica: Area2D = replicas[replicas.keys()[0]] as Area2D
	var contacts: Array = [0]
	replica.player_contacted.connect(func(_p: Node2D) -> void: contacts[0] += 1)
	var player := Node2D.new()
	player.add_to_group(&"player")
	var health_before: float = float(replica.get("health"))
	replica.call("take_damage", 1.0)
	replica.call("_on_body_entered", player)
	_expect(replica.monitoring == false and replica.monitorable == false, "Contrato T13a: el replica no colisiona (monitoring y monitorable apagados)")
	_expect(is_equal_approx(float(replica.get("health")), health_before), "Contrato T13b: el dano no altera la vida del replica")
	_expect(contacts[0] == 0 and not replica.is_queued_for_deletion(), "Contrato T13c: el contacto con el jugador no dana ni destruye el replica")
	player.free()
	_close_session(main, peer)


# T14 (S2, task T3): in NETWORK mode the client's local spawner creates no formation; only replicas exist.
func _check_client_spawner_off_in_network() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	var at_start: int = _enemy_nodes(main).size()
	if spawner != null:
		spawner.call("start_wave", 0)
		spawner.call("start_wave", 1)
	_expect(at_start == 0 and _enemy_nodes(main).size() == 0, "Contrato T14a: en red el spawner del cliente no crea enemigos locales")
	_expect(spawner != null and spawner.has_method("is_running") and spawner.call("is_running") == false, "Contrato T14b: en red el spawner del cliente no corre la formacion")
	_close_session(main, peer)


# T15 (S2, task T3): the host's boss is replicated: the client shows a replica with the host's position, health and armor phase; its removal frees it.
func _check_boss_replica_follows_host() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_H)
	var host: Node = await _new_main()
	await _start_network_session(host)
	host.set("_chapter", 3)
	(host.get("_boss") as RefCounted).call("start_battle")
	var boss: Node = host.get("_active_boss") as Node
	if boss != null:
		boss.call("take_damage", int(boss.get("max_health")) / 2)
	var host_state: Dictionary = host.get_node(SYNC_NODE_NAME).call("build_state")
	var truth_pos: Vector2 = (boss as Node2D).position if boss != null else Vector2.ZERO
	var truth_health: int = int(boss.get("health")) if boss != null else -1
	var truth_phase: int = int(boss.call("get_armor_phase")) if boss != null else -1
	_close_session(host, peer)

	peer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	var sync: Node = client.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(sync, "rpc_host_state", 1, [host_state])
	var replica: Node2D = client.get("_active_boss") as Node2D
	var had_replica: bool = replica != null
	_expect(replica != null and replica.get("replica") == true, "Contrato T15a: el jefe del host aparece como replica en el cliente")
	_expect(replica != null and replica.position.is_equal_approx(truth_pos) and int(replica.get("health")) == truth_health, "Contrato T15b: la replica del jefe sigue la posicion y la vida del host")
	_expect(replica != null and truth_phase == 2 and int(replica.call("get_armor_phase")) == truth_phase, "Contrato T15c: la replica del jefe muestra la misma fase de blindaje del host")
	_call_checked(sync, "rpc_host_removed", 1, [[int((host_state.get("boss", {}) as Dictionary).get("id", 0))]])
	_expect(had_replica and (not is_instance_valid(replica) or not replica.is_inside_tree()), "Contrato T15d: la baja del jefe en el host libera su replica en el cliente")
	_close_session(client, peer)


# T16 (S5): LOCAL_COOP and singleplayer still spawn their formation on this PC, with no replicas.
func _check_local_modes_spawn_enemies() -> void:
	root.multiplayer.multiplayer_peer = null
	var coop: Node = await _new_main()
	var coop_button: Button = (coop.get_node_or_null("MainMenu/" + COOP_BUTTON) as Button) if coop.get_node_or_null("MainMenu") != null else null
	if coop_button != null:
		coop_button.pressed.emit()
	_expect(_enemy_nodes(coop).size() > 0 and coop.get_node_or_null(SYNC_NODE_NAME) == null, "Contrato T16a: coop local crea su formacion en este PC y no crea red")
	_free_main(coop)
	var solo: Node = await _new_main()
	var play_button: Button = (solo.get_node_or_null("MainMenu/" + PLAY_BUTTON) as Button) if solo.get_node_or_null("MainMenu") != null else null
	if play_button != null:
		play_button.pressed.emit()
	_expect(_enemy_nodes(solo).size() > 0, "Contrato T16b: singleplayer crea su formacion en este PC")
	_free_main(solo)


# Enemy children of the spawner of main that are alive (in group "enemies", not being freed).
func _enemy_nodes(main: Node) -> Array:
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return []
	return spawner.get_children().filter(func(c: Node) -> bool: return c.is_in_group(&"enemies") and not c.is_queued_for_deletion())


# net_id of an enemy node as an int (0 when the node carries no id).
func _net_id(node: Node) -> int:
	var value: Variant = node.get("net_id")
	return int(value) if value != null else 0


# Replicas on a peer keyed by net_id (only nodes that carry an id).
func _replica_by_id(main: Node) -> Dictionary:
	var out: Dictionary = {}
	for node: Node in _enemy_nodes(main):
		var id: int = _net_id(node)
		if id > 0:
			out[id] = node
	return out


# Host side of a formation: starts the host session, starts wave_index, and returns the state the host would send
# plus the truth per enemy id (position and variant) that a client must reproduce.
func _host_session(port: int, wave_index: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = _open_server(port)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.call("start_wave", wave_index)
	var state: Dictionary = main.get_node_or_null(SYNC_NODE_NAME).call("build_state") if main.get_node_or_null(SYNC_NODE_NAME) != null else {}
	var truth: Dictionary = {}
	for node: Node in _enemy_nodes(main):
		truth[_net_id(node)] = {"pos": (node as Node2D).position, "variant": String(node.call("get_variant_id"))}
	_close_session(main, peer)
	return {"state": state, "truth": truth}


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


# Precondition: J2 actions are registered as the game does when a coop ship is created.
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
