extends SceneTree
# Contract test for Etapa 20 T17b and T22 to T26: replicated asteroids, the host's score and lives on the client HUD,
# the end of a network match and the host-only RPC authority (S1, S3, S5). Two peers are simulated in one process:
# RPC handlers are called directly with an arity check, and the host's reliable events are read from the sync node's
# outbox (the payloads it would send). Drops are checked in etapa_20_sync_loot_contract_test.gd.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const NET_SYNC_PATH := "res://scripts/net/net_sync_node.gd"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_I: int = 7802
const HOST_PORT_J: int = 7803
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const NET_ERROR_LABEL := "Control/NetPanel/NetErrorLabel"
const SESSION_MAIN_MENU: int = 0 # SessionState.MAIN_MENU in main.gd

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_assigns_asteroid_ids()
	await _check_asteroid_replicas_follow_host()
	await _check_host_score_and_lives_reach_client_hud()
	await _check_host_session_end_event()
	await _check_session_end_returns_client_to_menu()
	await _check_new_rpcs_are_host_authority()

	if _failures == 0:
		print("ETAPA 20 SYNC SESSION CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC SESSION CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T17b (S1, task T4): the host gives every asteroid (initial and fragment) a unique, positive network id.
func _check_host_assigns_asteroid_ids() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_J)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var spawner: Node = main.get_node_or_null("AsteroidSpawner")
	if spawner != null:
		spawner.call("spawn_asteroid", 0, Vector2(300.0, 200.0), Vector2(0.0, 90.0))
		spawner.call("spawn_asteroid", 1, Vector2(500.0, 200.0), Vector2(0.0, 90.0))
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	if sync != null:
		sync.call("build_state")
	var rocks: Array = _asteroid_nodes(main)
	var ids: Dictionary = {}
	var valid: bool = rocks.size() == 2
	for rock: Node in rocks:
		var id: int = _net_id(rock)
		if id <= 0 or ids.has(id):
			valid = false
		ids[id] = true
	_expect(valid, "Contrato T17b: el host asigna un id de red unico y positivo a cada asteroide")
	_close_session(main, peer)


# T22a-T22d (S1, task T4): asteroid replicas follow the host state, have no collision, and the removal event frees them.
func _check_asteroid_replicas_follow_host() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var first: Dictionary = {"asteroids": [{"id": 4, "x": 300.0, "y": 200.0, "size": 0, "rot": 0.5}, {"id": 5, "x": 500.0, "y": 220.0, "size": 1, "rot": 0.0}]}
	_call_checked(sync, "rpc_host_state", 1, [first])
	var rock: Node = _asteroid_replica(main, 4)
	var placed: bool = rock != null and rock.get("replica") == true and (rock as Node2D).global_position.is_equal_approx(Vector2(300.0, 200.0))
	_expect(placed and is_equal_approx(float(rock.get("rotation")), 0.5) and _asteroid_replica(main, 5) != null, "Contrato T22a: el cliente crea replicas de asteroide con la posicion y rotacion del host")
	_call_checked(sync, "rpc_host_state", 1, [{"asteroids": [{"id": 4, "x": 310.0, "y": 260.0, "size": 0, "rot": 1.0}]}])
	var moved: bool = rock != null and _asteroid_replica(main, 4) == rock and (rock as Node2D).global_position.is_equal_approx(Vector2(310.0, 260.0))
	_expect(moved, "Contrato T22b: la replica sigue al asteroide del host en cada estado (la misma instancia)")
	if rock == null:
		_expect(false, "Contrato T22c: la replica de asteroide no colisiona ni dana al jugador (falta la replica)")
	else:
		var contacts: Array = [0]
		rock.connect("player_contacted", func(_p: Node2D) -> void: contacts[0] += 1)
		var player := Node2D.new()
		player.add_to_group(&"player")
		rock.call("_on_body_entered", player)
		_expect(rock.monitoring == false and rock.monitorable == false and contacts[0] == 0 and not rock.is_queued_for_deletion(), "Contrato T22c: la replica de asteroide no colisiona ni dana al jugador")
		player.free()
	_call_checked(sync, "rpc_host_asteroids_removed", 1, [[4]])
	_expect(_asteroid_replica(main, 4) == null and _asteroid_replica(main, 5) != null, "Contrato T22d: la baja de asteroide del host libera su replica y deja las demas")
	_close_session(main, peer)


# T23a-T23d (S3, task T4): the host's score and lives reach the client HUD values through the state.
func _check_host_score_and_lives_reach_client_hud() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_I)
	var host: Node = await _new_main()
	await _start_network_session(host)
	host.set("score", 1234)
	host.set("score_p2", 567)
	host.set("lives", 2)
	host.set("_player_two_lives", 1)
	var state: Dictionary = host.get_node(SYNC_NODE_NAME).call("build_state")
	_close_session(host, peer)

	peer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	_call_checked(client.get_node_or_null(SYNC_NODE_NAME), "rpc_host_state", 1, [state])
	var hud: Node = client.get("_hud") as Node
	_expect(int(client.get("score")) == 1234 and int(client.get("score_p2")) == 567, "Contrato T23a: el puntaje de J1 y J2 del host llega al cliente")
	_expect(_label_text(hud, "_score_label") == "Score: 1234" and _label_text(hud, "_score_p2_label") == "Score: 567", "Contrato T23b: el HUD del cliente muestra el puntaje del host")
	_expect(int(client.get("lives")) == 2 and int(client.get("_player_two_lives")) == 1, "Contrato T23c: las vidas de J1 y J2 del host llegan al cliente")
	_expect(_label_text(hud, "_lives_label") == "2" and _label_text(hud, "_lives_p2_label") == "1", "Contrato T23d: el HUD del cliente muestra las vidas del host")
	_close_session(client, peer)


# T24a (S1, task T4): the host queues one reliable session-end event with its kind and final score when a match ends.
func _check_host_session_end_event() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_J)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.set("score", 800)
	(main.get("_session") as RefCounted).call("end_session")
	var ended: Array = _outbox(sync, "rpc_host_session_end")
	var event: Dictionary = ended[0] as Dictionary if ended.size() == 1 else {}
	_expect(ended.size() == 1 and event.get("kind") == "game_over" and int(event.get("score", -1)) == 800, "Contrato T24a: el host envia un evento de fin de partida con el tipo y el puntaje final")
	_close_session(main, peer)


# T25a-T25c (S1, task T4): a game over or mission complete event returns the client to the menu with a notice.
func _check_session_end_returns_client_to_menu() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var notice: Label = menu.get_node_or_null(NET_ERROR_LABEL) as Label if menu != null else null
	if notice != null:
		notice.text = ""
	_call_checked(sync, "rpc_host_session_end", 1, [{"kind": "game_over", "score": 640, "score_p2": 0}])
	_expect(main.get("_session_active") == false and int(main.get("_session_state")) == SESSION_MAIN_MENU, "Contrato T25a: el fin de partida del host devuelve al cliente al menu")
	_expect(notice != null and notice.text != "", "Contrato T25b: el cliente muestra un aviso en el menu al terminar la partida del host")
	await _start_network_session(main)
	sync = main.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(sync, "rpc_host_session_end", 1, [{"kind": "mission_complete", "score": 9000, "score_p2": 100}])
	_expect(main.get("_session_active") == false and int(main.get("_session_state")) == SESSION_MAIN_MENU, "Contrato T25c: la mision completada del host tambien devuelve al cliente al menu")
	_close_session(main, peer)


# T26a (S1, task T4): the new replication RPCs are declared with host authority, so only the host can send them.
func _check_new_rpcs_are_host_authority() -> void:
	var script: Script = load(NET_SYNC_PATH) as Script
	var config: Dictionary = script.get_rpc_config() if script != null else {}
	var names: Array[StringName] = [&"rpc_host_loot_spawned", &"rpc_host_loot_picked", &"rpc_host_asteroids_removed", &"rpc_host_session_end"]
	var all_authority: bool = true
	for rpc_name: StringName in names:
		if not config.has(rpc_name) or config[rpc_name]["rpc_mode"] != MultiplayerAPI.RPC_MODE_AUTHORITY:
			all_authority = false
	_expect(all_authority, "Contrato T26a: los RPC de loot, asteroides y fin de partida solo acepta al host como autoridad")


# Asteroids of the AsteroidSpawner that are alive.
func _asteroid_nodes(main: Node) -> Array:
	var spawner: Node = main.get_node_or_null("AsteroidSpawner")
	if spawner == null:
		return []
	return spawner.get_children().filter(func(c: Node) -> bool: return c.is_in_group(&"asteroids") and not c.is_queued_for_deletion())


# Asteroid replica with this net id on the client, or null.
func _asteroid_replica(main: Node, id: int) -> Node:
	for rock: Node in _asteroid_nodes(main):
		if _net_id(rock) == id and rock.get("replica") == true:
			return rock
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


# Text of a HUD label by its member name ("" when the label does not exist yet).
func _label_text(hud: Node, member: String) -> String:
	var label: Variant = hud.get(member) if hud != null else null
	return (label as Label).text if label is Label else ""


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
