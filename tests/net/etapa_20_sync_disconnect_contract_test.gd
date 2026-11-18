extends SceneTree
# Contract test for Etapa 20 T5 (S4): a disconnect in the middle of a network match.
# Host: a client that leaves drops J2 from the match (no remote ship, no lives, HUD panel hidden), the match
# keeps running and the host shows a notice. Client: a lost host (server_disconnected) returns to the menu with
# the notice, frees the NetSync node, the peer and every replica, and raises no errors. Two peers are simulated
# in one process; RPC handlers are called with an arity check, never a silent pass.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const NET_SYNC_PATH := "res://features/net/net_sync_node.gd"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT: int = 7804
const CLIENT_TARGET_PORT: int = 7805
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const NET_ERROR_LABEL := "Control/NetPanel/NetErrorLabel"
const HUD_NOTICE_NAME := "NetNoticeLabel"
const HOST_LEFT_NOTICE: String = "El otro jugador se desconecto."
const HOST_LOST_NOTICE: String = "Se perdio la conexion con el host."
const SESSION_STATE_PLAYING: int = 1 # SessionState.PLAYING in main.gd
const SESSION_STATE_MAIN_MENU: int = 0 # SessionState.MAIN_MENU in main.gd
const CLIENT_PEER_ID: int = 2

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_clears_j2_when_client_leaves()
	await _check_host_ignores_other_peers()
	await _check_host_loss_is_idempotent()
	await _check_client_returns_to_menu_on_lost_host()
	await _check_notice_clears_when_returning_to_menu()
	await _check_host_frees_j2_slot_and_targets()

	if _failures == 0:
		print("ETAPA 20 SYNC DISCONNECT CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC DISCONNECT CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T47a-T47f (S4, task T5): the client leaves mid-match; the host keeps the match, clears J2 and shows the notice.
func _check_host_clears_j2_when_client_leaves() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	_expect(p2 != null and p2.get("remote_driven") == true and sync != null, "Contrato T47 (precondicion): el host tiene J2 remoto en una partida de red")
	main.set("_player_two_lives", 2)
	if _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]):
		_expect(main.get("_session_active") == true and int(main.get("_session_state")) == SESSION_STATE_PLAYING, "Contrato T47a: el host sigue en partida cuando el cliente se desconecta")
		_expect(int(main.get("_player_two_lives")) == 0 and p2.get("remote_driven") == false, "Contrato T47b: J2 deja de ser nave remota y pierde sus vidas")
		_expect(p2.visible == false and p2.get("_gameplay_enabled") == false, "Contrato T47c: J2 queda oculta y sin juego")
		var panel: Control = _p2_panel(main)
		_expect(panel != null and panel.visible == false, "Contrato T47d: el panel de J2 del HUD queda oculto")
		_expect(_hud_notice_text(main) == HOST_LEFT_NOTICE, "Contrato T47e: el host muestra el aviso \"El otro jugador se desconecto.\"")
		_expect(main.get("_player") != null and (main.get("_player") as Node).get("replica") == false and int(main.get("lives")) > 0, "Contrato T47f: J1 sigue vivo y jugable en el host")
	_close_session(main, peer)


# T48a-T48b (S4, task T5): a peer that is not the J2 client never clears J2 or the match.
func _check_host_ignores_other_peers() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.set("_player_two_lives", 2)
	sync.set("_remote_peer", 9)
	if _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]):
		_expect(int(main.get("_player_two_lives")) == 2 and p2.get("remote_driven") == true, "Contrato T48a: un peer distinto del cliente de J2 no toca a J2")
		_expect(_hud_notice_text(main) == "", "Contrato T48b: un peer distinto del cliente no muestra aviso")
	_close_session(main, peer)


# T49a-T49b (S4, task T5): a second report of the same loss changes nothing and raises no error.
func _check_host_loss_is_idempotent() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	if _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]) and _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]):
		_expect(main.get("_session_active") == true and int(main.get("_player_two_lives")) == 0, "Contrato T49a: una segunda perdida del mismo cliente no cambia la partida")
		_expect(_hud_notice_text(main) == HOST_LEFT_NOTICE, "Contrato T49b: la segunda perdida conserva el aviso")
	_close_session(main, peer)


# T50a-T50f (S4, task T5): the lost host returns the client to the menu, frees the sync node, peer and replicas.
func _check_client_returns_to_menu_on_lost_host() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var host_state: Dictionary = {
		"j1": {"x": 200.0, "y": 300.0, "facing": 0, "lives": 3, "shield": 0, "weapon_level": 1},
		"j2": {"x": 260.0, "y": 300.0, "facing": 0, "lives": 3, "shield": 0, "weapon_level": 1},
		"asteroids": [{"id": 4, "x": 300.0, "y": 200.0, "size": 0, "rot": 0.5}],
		"enemies": [{"id": 7, "variant": "standard", "x": 400.0, "y": 150.0, "rot": 0.0, "health": 1.0, "state": 0, "enraged": false}],
	}
	if _call_checked(sync, "rpc_host_state", 1, [host_state]):
		_expect(_replica_count(main, "asteroids") == 1 and _replica_count(main, "enemies") == 1, "Contrato T50 (precondicion): el cliente tiene replicas de asteroide y enemigo")
		root.multiplayer.server_disconnected.emit()
		_expect(main.get("_session_active") == false and int(main.get("_session_state")) == SESSION_STATE_MAIN_MENU, "Contrato T50a: la perdida del host devuelve al cliente al menu")
		var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
		var notice: Label = menu.get_node_or_null(NET_ERROR_LABEL) as Label if menu != null else null
		_expect(notice != null and notice.text == HOST_LOST_NOTICE, "Contrato T50b: el menu muestra \"Se perdio la conexion con el host.\"")
		_expect(main.get_node_or_null(SYNC_NODE_NAME) == null, "Contrato T50c: el nodo NetSync del cliente se elimina")
		_expect(root.multiplayer.multiplayer_peer == null, "Contrato T50d: el peer del cliente queda cerrado (null)")
		_expect(_replica_count(main, "asteroids") == 0 and _replica_count(main, "enemies") == 0, "Contrato T50e: no quedan replicas de asteroides ni enemigos")
		_expect((main.get("_player") as Node).get("replica") == false and (main.get("_player_two") as Node).get("replica") == false, "Contrato T50f: las naves vuelven a no ser replicas")
	peer.close()
	root.multiplayer.multiplayer_peer = null
	_free_main(main)


# T51 (S4, task T5): the host's notice does not survive into the next match or the menu.
func _check_notice_clears_when_returning_to_menu() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	if _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]):
		_expect(_hud_notice_text(main) == HOST_LEFT_NOTICE, "Contrato T51 (precondicion): el aviso del host esta visible en la partida")
		main.call("return_to_main_menu")
		_expect(_hud_notice_text(main) == "", "Contrato T51a: volver al menu oculta el aviso de desconexion")
	_close_session(main, peer)


# T52-T53 (S4, task T5, L16): after the J2 client leaves, a new client can take J2 (the remembered peer is
# cleared) and enemy dives never aim at the hidden J2 or at an eliminated ship (they fall back to the screen center).
func _check_host_frees_j2_slot_and_targets() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	sync.set("_remote_peer", CLIENT_PEER_ID)
	if _call_checked(sync, "handle_peer_lost", 1, [CLIENT_PEER_ID]):
		_expect(int(sync.get("_remote_peer")) == 0, "Contrato T52: tras la desconexion de J2 el host olvida el peer remoto para aceptar un cliente nuevo")
		var pressure: Object = main.get("_enemy_spawner").get("_pressure") as Object
		if pressure != null and pressure.has_method("dive_target_position"):
			var p1: CharacterBody2D = main.get("_player") as CharacterBody2D
			p1.global_position = Vector2(100.0, 100.0)
			p1.collision_layer = 0
			# Anchored to the playfield bottom (movil-banda-controles): the control band below never receives dives.
			var playfield: Rect2 = GameLayout.playfield_of(main.get_viewport().get_visible_rect())
			var fallback_point := Vector2(playfield.size.x * 0.5, playfield.end.y - 110.0)
			_expect(pressure.call("dive_target_position") == fallback_point, "Contrato T53: sin naves vivas (J1 eliminada, J2 oculta) la picada cae al centro inferior del area de juego")
			p1.collision_layer = 1
			_expect((pressure.call("dive_target_position") as Vector2).distance_to(Vector2(100.0, 100.0)) < 0.5, "Contrato T53b: con J1 viva la picada apunta a J1, no a J2 oculta")
		else:
			_expect(false, "Contrato T53: el modulo de presion expone dive_target_position()")
	_close_session(main, peer)


# Text of the host's notice label in the HUD ("" when it is hidden or missing).
func _hud_notice_text(main: Node) -> String:
	var hud: Node = main.get("_hud") as Node
	var label: Label = hud.get_node_or_null(HUD_NOTICE_NAME) as Label if hud != null else null
	return label.text if label != null and label.visible else ""


# The J2 side panel of the HUD (null when the layout has not built it).
func _p2_panel(main: Node) -> Control:
	var hud: Node = main.get("_hud") as Node
	return hud.get("_p2_panel") as Control if hud != null else null


# Replica nodes of one kind (asteroids or enemies) that are alive on the client.
func _replica_count(main: Node, kind: String) -> int:
	var count: int = 0
	var parent: Node = main.get_node_or_null("AsteroidSpawner") if kind == "asteroids" else main.get_node_or_null("EnemySpawner")
	if parent == null:
		return 0
	for child: Node in parent.get_children():
		if child.get("replica") == true and not child.is_queued_for_deletion():
			count += 1
	return count


# Calls an RPC or handler only when the method exists with the expected arity; a wrong signature is a failure.
func _call_checked(obj: Object, method: String, arity: int, args: Array) -> bool:
	if obj == null or obj.get_script() == null or not _has_arity(obj, method, arity):
		_expect(false, "%s con aridad %d no existe en el nodo de sincronizacion" % [method, arity])
		return false
	obj.callv(method, args)
	return true


# True when obj's script has the method with that arity (a wrong call would abort the check).
func _has_arity(obj: Object, method: String, arity: int) -> bool:
	return obj.get_script().get_script_method_list().any(func(e: Dictionary) -> bool: return e["name"] == method and (e["args"] as Array).size() == arity)


# Opens a Host on port: the scene multiplayer peer is the server (authority, peer id 1).
func _open_server(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port)
	_expect(err == OK, "Contrato T47 (precondicion): el host abre el puerto %d" % port)
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
