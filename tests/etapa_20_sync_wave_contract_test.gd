extends SceneTree
# Contract test for Etapa 20 gap 5 (T52 to T56): the host decides wave transitions and announcements; the client shows
# the same announcement, follows the host's wave and session state, and never starts a wave on its own (S1, S5).
# Two peers are simulated in one process: the host's reliable event is read from the sync node's outbox, and the
# client's RPC handler is called directly with an arity check.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const NET_SYNC_PATH := "res://features/net/net_sync_node.gd"
const SYNC_NODE_NAME := "NetSync"
const HOST_PORT_K: int = 7830
const HOST_PORT_L: int = 7831
const HOST_PORT_M: int = 7832
const CLIENT_TARGET_PORT: int = 7795
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const PLAY_BUTTON := "Control/Menu/PlayButton"
const SESSION_PLAYING: int = 1 # SessionState.PLAYING in main.gd
const SESSION_WAVE_TRANSITION: int = 3 # SessionState.WAVE_TRANSITION in main.gd

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_queues_transition_on_clear()
	await _check_client_shows_same_announcement()
	await _check_client_hud_wave_matches_host()
	await _check_client_never_starts_wave()
	await _check_host_behavior_unchanged()

	if _failures == 0:
		print("ETAPA 20 SYNC WAVE CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC WAVE CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T52 (gap 5, task T3-b): a cleared wave on the host queues one reliable transition event (global wave, local wave,
# the announcement text shown on the host, and the state), and the event's RPC is reliable and host-authority.
func _check_host_queues_transition_on_clear() -> void:
	var sent: Dictionary = await _host_transition(HOST_PORT_K)
	var events: Array = sent["events"]
	var event: Dictionary = sent["event"]
	var script: Script = load(NET_SYNC_PATH) as Script
	var config: Dictionary = script.get_rpc_config() if script != null else {}
	var reliable: bool = config.has(&"rpc_host_wave_transition") and config[&"rpc_host_wave_transition"]["transfer_mode"] == MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var authority: bool = config.has(&"rpc_host_wave_transition") and config[&"rpc_host_wave_transition"]["rpc_mode"] == MultiplayerAPI.RPC_MODE_AUTHORITY
	_expect(events.size() == 1 and int(event.get("wave", -1)) == 2 and int(event.get("local_wave", -1)) == 2 and String(event.get("text", "")) == String(sent["text"]) and not String(sent["text"]).is_empty(), "Contrato T52a: al limpiar una oleada el host encola un evento de transicion con la oleada global, la local y el texto del aviso")
	_expect(int(event.get("state", -1)) == SESSION_WAVE_TRANSITION, "Contrato T52b: el evento de transicion lleva el estado WAVE_TRANSITION del host")
	_expect(reliable and authority, "Contrato T52c: el RPC de transicion de oleada es fiable y solo acepta al host como autoridad")


# T53 (gap 5): the client shows the same announcement text as the host, through its own WaveAnnouncement.
func _check_client_shows_same_announcement() -> void:
	var sent: Dictionary = await _host_transition(HOST_PORT_L)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	_call_checked(sync, "rpc_host_wave_transition", 1, [sent["event"]])
	_expect(announcement != null and announcement.visible and _radar_text(main) == String(sent["text"]) and not String(sent["text"]).is_empty(), "Contrato T53a: el cliente muestra el mismo texto de aviso que el host")
	_expect(announcement != null and _wave_banner_text(main) == "OLEADA 3", "Contrato T53b: el cliente muestra el encabezado OLEADA 3, igual que el host")
	_close_session(main, peer)


# T54 (gap 5): the client's HUD wave number matches the host's, and the client's session state follows the host's
# WAVE_TRANSITION and PLAYING states.
func _check_client_hud_wave_matches_host() -> void:
	var sent: Dictionary = await _host_transition(HOST_PORT_L)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(sync, "rpc_host_wave_transition", 1, [sent["event"]])
	_expect(int(main.get("wave")) == 2 and _hud_wave_text(main) == "Oleada 2", "Contrato T54a: el HUD del cliente muestra la oleada del host (Oleada 2) al recibir la transicion")
	_call_checked(sync, "rpc_host_state", 1, [sent["state_packet"]])
	_expect(int(main.get("_session_state")) == SESSION_WAVE_TRANSITION, "Contrato T54b: el estado de sesion del cliente sigue al host (WAVE_TRANSITION) en el estado de 20 Hz")
	var playing: Dictionary = (sent["state_packet"] as Dictionary).duplicate()
	playing["session_state"] = SESSION_PLAYING
	playing["wave"] = 3
	_call_checked(sync, "rpc_host_state", 1, [playing])
	_expect(int(main.get("_session_state")) == SESSION_PLAYING and int(main.get("wave")) == 3 and _hud_wave_text(main) == "Oleada 3", "Contrato T54c: al empezar la oleada del host el cliente pasa a PLAYING y el HUD muestra Oleada 3")
	_close_session(main, peer)


# T55 (gap 5, S5 guard): the client never starts or advances a wave on its own: when its announcement finishes its
# spawner stays off, creates no enemies, keeps its wave number and keeps the state the host sent.
func _check_client_never_starts_wave() -> void:
	var sent: Dictionary = await _host_transition(HOST_PORT_L)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	_call_checked(sync, "rpc_host_wave_transition", 1, [sent["event"]])
	if announcement != null:
		announcement.emit_signal("announcement_finished")
	_expect(spawner != null and spawner.get("replica") == true and spawner.call("is_running") == false and _enemy_nodes(main).is_empty(), "Contrato T55a: al terminar el aviso el spawner del cliente sigue apagado y no crea enemigos")
	_expect(int(main.get("wave")) == 2 and int(main.get("_session_state")) == SESSION_WAVE_TRANSITION, "Contrato T55b: el cliente no avanza la oleada ni cambia de estado por si mismo al terminar el aviso")
	_close_session(main, peer)


# T56 (S5): the host's own flow is unchanged (WAVE_TRANSITION, then the next wave after its announcement), and a
# singleplayer clear shows its announcement with no NetSync node.
func _check_host_behavior_unchanged() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_M)
	var host: Node = await _new_main()
	await _start_network_session(host)
	var spawner: Node = host.get_node_or_null("EnemySpawner")
	host.set("wave", 2)
	host.get("_waves").call("on_wave_cleared", 1)
	var waiting: bool = int(host.get("_session_state")) == SESSION_WAVE_TRANSITION and int(host.get("wave")) == 2 and spawner.call("is_running") == false
	host.get("_wave_announcement").emit_signal("announcement_finished")
	_expect(waiting, "Contrato T56a: el host entra en WAVE_TRANSITION al limpiar la oleada y espera al aviso")
	_expect(int(host.get("wave")) == 3 and int(host.get("_session_state")) == SESSION_PLAYING and _enemy_nodes(host).size() > 0, "Contrato T56b: al terminar el aviso el host pasa a la oleada 3 y la arranca")
	_close_session(host, peer)

	root.multiplayer.multiplayer_peer = null
	var solo: Node = await _new_main()
	var play_button: Button = (solo.get_node_or_null("MainMenu/" + PLAY_BUTTON) as Button) if solo.get_node_or_null("MainMenu") != null else null
	if play_button != null:
		play_button.pressed.emit()
	solo.set("wave", 2)
	solo.get("_waves").call("on_wave_cleared", 1)
	_expect(solo.get_node_or_null(SYNC_NODE_NAME) == null and _radar_text(solo) != "" and (solo.get_node_or_null("WaveAnnouncement") as CanvasLayer).visible, "Contrato T56c: singleplayer muestra su aviso de oleada sin crear red")
	_free_main(solo)


# Host side of one transition: starts a network session, clears wave 2 (global) and returns the event the host queued,
# the announcement text it shows, and the state packet it would send right after.
func _host_transition(port: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = _open_server(port)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	main.set("wave", 2)
	main.get("_waves").call("on_wave_cleared", 1)
	var events: Array = _outbox(sync, "rpc_host_wave_transition")
	var text: String = _radar_text(main)
	var state_packet: Dictionary = sync.call("build_state") if sync != null else {}
	_close_session(main, peer)
	return {
		"events": events,
		"event": events[0] as Dictionary if events.size() == 1 else {},
		"text": text,
		"state_packet": state_packet,
	}


# Payloads of the reliable events of one method that the host queued (the outbox is drained by this call).
func _outbox(sync: Node, method: String) -> Array:
	if sync == null or not sync.has_method("take_outbox"):
		return []
	var out: Array = []
	for entry: Variant in sync.call("take_outbox"):
		if String((entry as Array)[0]) == method:
			out.append((entry as Array)[1])
	return out


# Text of the announcement's radar line ("" when the announcement is missing).
func _radar_text(main: Node) -> String:
	var announcement: Node = main.get_node_or_null("WaveAnnouncement")
	var label: Variant = announcement.get("_radar_label") if announcement != null else null
	return (label as Label).text if label is Label else ""


# Text of the announcement's wave header ("OLEADA n").
func _wave_banner_text(main: Node) -> String:
	var announcement: Node = main.get_node_or_null("WaveAnnouncement")
	var label: Variant = announcement.get("_wave_label") if announcement != null else null
	return (label as Label).text if label is Label else ""


# Text of the HUD wave label ("Oleada n").
func _hud_wave_text(main: Node) -> String:
	var hud: Variant = main.get("_hud")
	var label: Variant = hud.get("_wave_label") if hud != null else null
	return (label as Label).text if label is Label else ""


# Enemy children of the spawner of main that are alive.
func _enemy_nodes(main: Node) -> Array:
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return []
	return spawner.get_children().filter(func(c: Node) -> bool: return c.is_in_group(&"enemies") and not c.is_queued_for_deletion())


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
