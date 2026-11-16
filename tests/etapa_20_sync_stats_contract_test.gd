extends SceneTree
# Contract test for Etapa 20 T42 to T46: the host's final session stats (kills by type and accuracy) travel in the
# reliable session-end event and fill the client's game-over panel instead of the client's own counters (S1, S5), and
# a client never starts an asteroid wave on its own (S1). Two peers are simulated in one process: RPC handlers are
# called directly with an arity check, and the host's session-end event is read from the sync node's outbox.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_K: int = 7804
const HOST_PORT_L: int = 7805
const HOST_PORT_M: int = 7806
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const SESSION_PLAYING: int = 1 # SessionState.PLAYING in main.gd
const SESSION_WAVE_TRANSITION: int = 3 # SessionState.WAVE_TRANSITION in main.gd
const EXPECTED_ACCURACY: float = 75.0

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_session_end_carries_kills_and_accuracy()
	await _check_client_panel_shows_host_stats()
	await _check_client_does_not_count_own_kills()
	await _check_client_cannot_start_asteroid_wave()
	await _check_host_still_starts_asteroid_wave()

	if _failures == 0:
		print("ETAPA 20 SYNC STATS CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC STATS CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T42a-T42b (S1, task T4 gap 3): the host's session-end event carries the kills by type and the session accuracy.
func _check_host_session_end_carries_kills_and_accuracy() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_K)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.set("kills_by_type", {&"standard": 2, &"assault_frigate": 1})
	SESSION_STATS.reset()
	for _i: int in range(4):
		SESSION_STATS.register_shot()
	for _i: int in range(3):
		SESSION_STATS.register_hit()
	(main.get("_session") as RefCounted).call("end_session")
	var ended: Array = _outbox(sync, "rpc_host_session_end")
	var event: Dictionary = ended[0] as Dictionary if ended.size() == 1 else {}
	var kills: Dictionary = event.get("kills", {}) as Dictionary
	_expect(int(kills.get(&"standard", 0)) == 2 and int(kills.get(&"assault_frigate", 0)) == 1, "Contrato T42a: el evento de fin de partida del host lleva las bajas por tipo")
	_expect(event.has("accuracy") and is_equal_approx(float(event["accuracy"]), EXPECTED_ACCURACY), "Contrato T42b: el evento de fin de partida del host lleva la precision de la sesion (75%)")
	SESSION_STATS.reset()
	_close_session(main, peer)


# T43a-T43b (S1, task T4 gap 3): the client shows the host's accuracy and kills in its game-over panel.
func _check_client_panel_shows_host_stats() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var event: Dictionary = {"kind": "game_over", "score": 640, "score_p2": 0, "kills": {&"standard": 2, &"assault_frigate": 1}, "accuracy": EXPECTED_ACCURACY}
	_call_checked(sync, "rpc_host_session_end", 1, [event])
	_expect(_panel_accuracy(main) == "Precisión: 75%", "Contrato T43a: el cliente muestra la precision del host en su panel de fin de partida")
	_expect(_panel_kill_count(main, "Caza") == "2" and _panel_kill_count(main, "Fragata de asalto") == "1", "Contrato T43b: el cliente muestra las bajas por tipo del host en su panel de fin de partida")
	_close_session(main, peer)


# T44 (S1, task T4 gap 3): the client's own kills and shots never reach its game-over panel; only the host's stats do.
func _check_client_does_not_count_own_kills() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.set("kills_by_type", {&"standard": 9})
	SESSION_STATS.reset()
	for _i: int in range(10):
		SESSION_STATS.register_shot()
	SESSION_STATS.register_hit()
	var event: Dictionary = {"kind": "game_over", "score": 640, "score_p2": 0, "kills": {&"standard": 2}, "accuracy": EXPECTED_ACCURACY}
	_call_checked(sync, "rpc_host_session_end", 1, [event])
	_expect(_panel_kill_count(main, "Caza") == "2" and _panel_accuracy(main) == "Precisión: 75%", "Contrato T44: el panel del cliente no suma sus bajas ni sus disparos locales")
	SESSION_STATS.reset()
	_close_session(main, peer)


# T45 (S1, task T4 gap 4): start_asteroid_wave_direct on a client does nothing: no wave, no asteroids, same state.
func _check_client_cannot_start_asteroid_wave() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	main.set("_session_state", SESSION_WAVE_TRANSITION)
	main.call("start_asteroid_wave_direct", 3)
	var spawner: Node = main.get_node_or_null("AsteroidSpawner")
	var started: bool = spawner != null and bool(spawner.call("is_wave_active"))
	_expect(not started and _asteroid_nodes(main).is_empty() and int(main.get("_session_state")) == SESSION_WAVE_TRANSITION, "Contrato T45: start_asteroid_wave_direct en un cliente no inicia oleada, no crea asteroides ni cambia el estado")
	_close_session(main, peer)


# T46 (S1, task T4 gap 4): the host still starts the asteroid wave through start_asteroid_wave_direct.
func _check_host_still_starts_asteroid_wave() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_M)
	var main: Node = await _new_main()
	await _start_network_session(main)
	main.call("start_asteroid_wave_direct", 3)
	var spawner: Node = main.get_node_or_null("AsteroidSpawner")
	var started: bool = spawner != null and bool(spawner.call("is_wave_active"))
	_expect(started and int(main.get("_session_state")) == SESSION_PLAYING, "Contrato T46: el host sigue iniciando la oleada de asteroides con start_asteroid_wave_direct")
	_close_session(main, peer)


# Text of the accuracy label of the game-over panel.
func _panel_accuracy(main: Node) -> String:
	var panel: Node = main.get("_game_over") as Node
	var label: Label = panel.get("_accuracy_label") as Label if panel != null else null
	return label.text if label != null else ""


# Count shown next to a kill name in the game-over panel ("" when the name is not listed).
func _panel_kill_count(main: Node, display_name: String) -> String:
	var panel: Node = main.get("_game_over") as Node
	var grid: GridContainer = panel.get("_kills_grid") as GridContainer if panel != null else null
	if grid == null:
		return ""
	var cells: Array = grid.get_children()
	for i: int in range(0, cells.size() - 1, 2):
		if (cells[i] as Label).text == display_name:
			return (cells[i + 1] as Label).text
	return ""


# Asteroids of the AsteroidSpawner that are alive.
func _asteroid_nodes(main: Node) -> Array:
	var spawner: Node = main.get_node_or_null("AsteroidSpawner")
	if spawner == null:
		return []
	return spawner.get_children().filter(func(c: Node) -> bool: return c.is_in_group(&"asteroids") and not c.is_queued_for_deletion())


# Payloads of the reliable events of one method that the host queued (the outbox is drained by this call).
func _outbox(sync: Node, method: String) -> Array:
	if sync == null or not sync.has_method("take_outbox"):
		return []
	var out: Array = []
	for entry: Variant in sync.call("take_outbox"):
		if String((entry as Array)[0]) == method:
			out.append((entry as Array)[1])
	return out


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
	_expect(err == OK, "Contrato T42 (precondicion): el host abre el puerto %d" % port)
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
