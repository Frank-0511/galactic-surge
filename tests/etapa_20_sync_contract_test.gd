extends SceneTree
# Contract test for Etapa 20 T1: host-authoritative ship sync (S1, S3, S5, S6).
# Covers session mode selection, where J2 comes from in each mode, client input reaching the host,
# host state reaching the client, client damage being ignored, and LOCAL_COOP staying unchanged.
# Two peers are simulated in one process: RPC handlers are called directly, and RPC wiring is
# checked through the node's RPC configuration.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const MODE_SCRIPT_PATH := "res://scripts/net/net_sync_mode.gd"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_A: int = 7793
const HOST_PORT_B: int = 7794
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const COOP_BUTTON := "Control/Menu/CoopButton"
const PLAY_BUTTON := "Control/Menu/PlayButton"
const NET_ERROR_LABEL := "Control/NetPanel/NetErrorLabel"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_mode_selection()
	await _check_network_requires_peer()
	await _check_network_j2_not_driven_by_local_keys()
	await _check_client_input_moves_j2_on_host()
	await _check_host_state_sets_j2_on_client()
	await _check_client_applies_no_damage()
	await _check_local_coop_unchanged()
	await _check_singleplayer_has_no_j2()

	if _failures == 0:
		print("ETAPA 20 SYNC CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T1: the mode lives in one module with LOCAL_COOP and NETWORK; the menu starts in LOCAL_COOP and has a network coop button.
func _check_mode_selection() -> void:
	var mode_script: Script = load(MODE_SCRIPT_PATH) as Script
	_expect(mode_script != null, "Contrato T1a: existe el modulo de modo de sesion %s" % MODE_SCRIPT_PATH)
	var local_mode: Variant = null
	if mode_script != null:
		var consts: Dictionary = mode_script.get_script_constant_map()
		_expect(consts.has("LOCAL_COOP") and consts.has("NETWORK"), "Contrato T1a2: el modo define LOCAL_COOP y NETWORK")
		local_mode = consts.get("LOCAL_COOP")
	var main: Node = await _new_main()
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	_expect(menu != null and local_mode != null and menu.get("session_mode") == local_mode, "Contrato T1b: el menu arranca en modo LOCAL_COOP")
	_expect(menu != null and menu.get_node_or_null(NET_COOP_BUTTON) != null, "Contrato T1c: el menu tiene el boton Coop en red")
	_free_main(main)


# T2: the network coop button needs a Host or Join peer; without one it starts nothing and shows a notice.
func _check_network_requires_peer() -> void:
	root.multiplayer.multiplayer_peer = null
	var main: Node = await _new_main()
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var net_button: Button = menu.get_node_or_null(NET_COOP_BUTTON) as Button if menu != null else null
	var error_label: Label = menu.get_node_or_null(NET_ERROR_LABEL) as Label if menu != null else null
	if net_button != null and error_label != null:
		net_button.pressed.emit()
		_expect(main.get("_session_active") == false, "Contrato T2a: Coop en red sin Host/Join no inicia la sesion")
		_expect(error_label.text != "", "Contrato T2b: Coop en red sin Host/Join muestra un aviso en el menu")
	else:
		_expect(false, "Contrato T2a: Coop en red sin Host/Join no inicia la sesion (faltan nodos)")
	_free_main(main)


# T3: in NETWORK mode J2 is the remote peer: local keys do not move it on the host.
func _check_network_j2_not_driven_by_local_keys() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_A)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	_expect(p2 != null and p2.get("remote_driven") == true, "Contrato T3a: en red J2 es el jugador remoto (no lo maneja el teclado)")
	var start_x: float = p2.position.x if p2 != null else 0.0
	_ensure_p2_actions()
	Input.action_press("p2_move_right")
	for i: int in 10:
		await physics_frame
	Input.action_release("p2_move_right")
	_expect(p2 != null and absf(p2.position.x - start_x) < 0.01, "Contrato T3b: en red una tecla local no mueve J2 en el host")
	_close_session(main, peer)


# T4: the client's input RPC reaches the host and moves J2 there; the RPCs are declared with the right authority.
func _check_client_input_moves_j2_on_host() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_B)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var start_x: float = p2.position.x if p2 != null else 0.0
	if sync != null and sync.has_method("rpc_client_input") and p2 != null:
		sync.call("rpc_client_input", -1.0)
		for i: int in 10:
			await physics_frame
		_expect(p2.position.x < start_x - 1.0, "Contrato T4a: el input del cliente llega al host y mueve J2 hacia la izquierda")
	else:
		_expect(false, "Contrato T4a: el input del cliente llega al host y mueve J2 (faltan nodos o RPC)")
	var config: Dictionary = {}
	if sync != null and sync.get_script() != null:
		config = sync.get_script().get_rpc_config()
	_expect(config.has(&"rpc_client_input") and config[&"rpc_client_input"]["rpc_mode"] == MultiplayerAPI.RPC_MODE_ANY_PEER, "Contrato T4b: rpc_client_input acepta input de cualquier peer (el cliente)")
	_expect(config.has(&"rpc_host_state") and config[&"rpc_host_state"]["rpc_mode"] == MultiplayerAPI.RPC_MODE_AUTHORITY, "Contrato T4c: rpc_host_state solo acepta al host como autoridad")
	_close_session(main, peer)


# T5: the host state RPC sets J1 and J2 position, lives, shield, weapon level and facing on the client.
func _check_host_state_sets_j2_on_client() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var state: Dictionary = {
		"j1": {"x": 100.0, "y": 600.0, "facing": 0, "lives": 2, "shield": 0, "weapon_level": 3},
		"j2": {"x": 300.0, "y": 600.0, "facing": -1, "lives": 1, "shield": 2, "weapon_level": 5},
	}
	if sync != null and sync.has_method("rpc_host_state") and p2 != null:
		sync.call("rpc_host_state", state)
		_expect(p2.position.x == 300.0, "Contrato T5a: el estado del host fija la posicion de J2 en el cliente")
		_expect(main.get("_player_two_lives") == 1, "Contrato T5b: el estado del host fija las vidas de J2 en el cliente")
		_expect(main.get("lives") == 2, "Contrato T5c: el estado del host fija las vidas de J1 en el cliente")
		_expect(p2.call("get_weapon_level") == 5, "Contrato T5d: el estado del host fija el nivel de arma de J2")
		_expect(p2.call("get_shield_level") == 2, "Contrato T5e: el estado del host fija el escudo de J2")
		_expect(p2.get("facing") == -1, "Contrato T5f: el estado del host fija la orientacion de J2")
	else:
		_expect(false, "Contrato T5a: el estado del host fija la posicion de J2 en el cliente (faltan nodos o RPC)")
	_close_session(main, peer)


# T6: the client never applies damage or score: a hit on J1 or J2 changes no lives on the client.
func _check_client_applies_no_damage() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	_expect(main.get("_session_active") == true, "Contrato T6 (precondicion): la sesion de red esta activa")
	var lives_j1: int = main.get("lives")
	var lives_j2: int = main.get("_player_two_lives")
	main.call("_on_player_damage_requested", p2)
	main.call("_on_player_damage_requested")
	_expect(main.get("_player_two_lives") == lives_j2 and main.get("lives") == lives_j1, "Contrato T6a: el cliente no aplica dano a J1 ni a J2")
	_close_session(main, peer)


# T7 (S5): LOCAL_COOP is unchanged: J2 is local, moves with its own keys, and no network node exists.
func _check_local_coop_unchanged() -> void:
	root.multiplayer.multiplayer_peer = null
	var main: Node = await _new_main()
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var coop_button: Button = menu.get_node_or_null(COOP_BUTTON) as Button if menu != null else null
	if coop_button != null:
		coop_button.pressed.emit()
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	_expect(p2 != null and p2.get("remote_driven") == false and p2.get("replica") == false, "Contrato T7a: en coop local J2 es local (no remoto)")
	var start_x: float = p2.position.x if p2 != null else 0.0
	Input.action_press("p2_move_right")
	for i: int in 10:
		await physics_frame
	Input.action_release("p2_move_right")
	_expect(p2 != null and p2.position.x > start_x, "Contrato T7b: en coop local J2 se mueve con sus propias teclas")
	_expect(main.get_node_or_null(SYNC_NODE_NAME) == null, "Contrato T7c: coop local no crea el nodo de sincronizacion de red")
	_free_main(main)


# T8 (S5): singleplayer is unchanged: no J2 and no network node.
func _check_singleplayer_has_no_j2() -> void:
	root.multiplayer.multiplayer_peer = null
	var main: Node = await _new_main()
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var play_button: Button = menu.get_node_or_null(PLAY_BUTTON) as Button if menu != null else null
	if play_button != null:
		play_button.pressed.emit()
	_expect(main.get("_session_active") == true and main.get("_player_two") == null, "Contrato T8a: singleplayer inicia sin J2")
	_expect(main.get_node_or_null(SYNC_NODE_NAME) == null, "Contrato T8b: singleplayer no crea el nodo de sincronizacion de red")
	_free_main(main)


# Precondition: J2 actions are registered as the game does when a coop ship is created.
func _ensure_p2_actions() -> void:
	var player_script: Script = load("res://scenes/entities/player/player.gd") as Script
	player_script.call("ensure_p2_input_actions")


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
