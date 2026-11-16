extends SceneTree
# Two-process probe, CLIENT side (Etapa 20, gap item 6). Run only by etapa_20_two_process_test.gd.
# Starts the real main scene, joins 127.0.0.1:PORT_TEXT with Join, starts Coop en red (NETWORK mode, as the lobby does)
# and checks over the real ENet socket: the connection is up, the host state moves J2 here, and the host's session end
# returns this client to the menu. Holds the J2 left key so the host has input to apply.
# Prints one "PROBE client ok|fail: <name>" line per check; exits 0 when all pass, 1 otherwise.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const PLAYER_INPUT: GDScript = preload("res://features/player/player_input.gd")
const PORT_TEXT := "7791"
const HOST_ADDRESS := "127.0.0.1"
const IP_FIELD := "Control/NetPanel/AddressRow/IpField"
const PORT_FIELD := "Control/NetPanel/AddressRow/PortField"
const JOIN_BUTTON := "Control/NetPanel/ButtonRow/JoinButton"
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const NET_ERROR_LABEL := "Control/NetPanel/NetErrorLabel"
const NOTICE_GAME_OVER: String = "La partida termino en el host: fin del juego."
const ROLE := "client"
const MIN_MOVE_PX: float = 10.0
const WAIT_CONNECT_SECONDS: float = 30.0
const RETRY_MS: int = 1000
const WAIT_INPUT_SECONDS: float = 20.0
const WAIT_END_SECONDS: float = 40.0
const SESSION_STATE_MAIN_MENU: int = 0
const LEAVE_FLUSH_SECONDS: float = 1.0

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = await _open_main()
	var menu: CanvasLayer = main.get_node("MainMenu") as CanvasLayer
	(menu.get_node(IP_FIELD) as LineEdit).text = HOST_ADDRESS
	(menu.get_node(PORT_FIELD) as LineEdit).text = PORT_TEXT
	var connected: bool = await _connect(menu)
	_check(connected, "client connects to the host over ENet", "connection status %d after the retries" % _status())
	if not connected:
		_finish()
		return
	(menu.get_node(NET_COOP_BUTTON) as Button).pressed.emit()
	var sync: Node = main.get_node_or_null("NetSync")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	var network: bool = main.get("_session_active") == true and sync != null and sync.get("_is_host") == false and p2 != null and p2.get("replica") == true
	_check(network, "client session starts in NETWORK mode (J2 is a replica)", "active=%s NetSync=%s J2=%s" % [main.get("_session_active"), sync != null, p2 != null])
	if not network:
		_finish()
		return
	var left: String = PLAYER_INPUT.input_action_name("move_left", 2)
	var start_x: float = p2.position.x
	Input.action_press(left)
	var moved: bool = await _wait_for(func() -> bool: return p2.position.x <= start_x - MIN_MOVE_PX, WAIT_INPUT_SECONDS)
	Input.action_release(left)
	_check(moved, "host state reaches client: J2 moves on the client", "J2 x %.1f -> %.1f (need %.1f px left)" % [start_x, p2.position.x, MIN_MOVE_PX])
	if not moved:
		_finish()
		return
	var ended: bool = await _wait_for(func() -> bool: return main.get("_session_active") == false, WAIT_END_SECONDS)
	_check(ended, "host session end reaches client", "client session still active after %d s" % int(WAIT_END_SECONDS))
	if not ended:
		_finish()
		return
	var label: Label = menu.get_node(NET_ERROR_LABEL) as Label
	var in_menu: bool = main.get("_session_state") == SESSION_STATE_MAIN_MENU and menu.visible and label.text == NOTICE_GAME_OVER
	_check(in_menu, "host session end returns client to the menu with a notice", "state=%s menu_visible=%s notice=\"%s\"" % [main.get("_session_state"), menu.visible, label.text])
	await _run_leave_match(main, menu)
	_finish()


## Second network match on the same connection; then this client leaves mid-match (its peer closes while the host plays on).
func _run_leave_match(main: Node, menu: CanvasLayer) -> void:
	(menu.get_node(NET_COOP_BUTTON) as Button).pressed.emit()
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	var again: bool = main.get("_session_active") == true and p2 != null and p2.get("replica") == true
	_check(again, "client starts a second network match (J2 is a replica)", "active=%s J2=%s" % [main.get("_session_active"), p2 != null])
	if not again:
		return
	var left: String = PLAYER_INPUT.input_action_name("move_left", 2)
	var start_x: float = p2.position.x
	Input.action_press(left)
	var moved: bool = await _wait_for(func() -> bool: return p2.position.x <= start_x - MIN_MOVE_PX, WAIT_INPUT_SECONDS)
	Input.action_release(left)
	_check(moved, "host state reaches client again: J2 moves on the client", "J2 x %.1f -> %.1f (need %.1f px left)" % [start_x, p2.position.x, MIN_MOVE_PX])
	if not moved:
		return
	menu.call("close_network")
	await _wait_seconds(LEAVE_FLUSH_SECONDS)
	_check(root.multiplayer.multiplayer_peer == null and main.get("_session_active") == true, "client leaves mid-match: its peer closes while the match runs", "peer=%s active=%s" % [root.multiplayer.multiplayer_peer, main.get("_session_active")])


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func _open_main() -> Node:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	return main


## Presses Join and retries while the ENet client is disconnected (the host may not be listening yet).
func _connect(menu: CanvasLayer) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(WAIT_CONNECT_SECONDS * 1000.0)
	var next_try: int = 0
	while Time.get_ticks_msec() < deadline:
		if _status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return true
		if _status() == MultiplayerPeer.CONNECTION_DISCONNECTED and Time.get_ticks_msec() >= next_try:
			(menu.get_node(JOIN_BUTTON) as Button).pressed.emit()
			next_try = Time.get_ticks_msec() + RETRY_MS
		await process_frame
	return _status() == MultiplayerPeer.CONNECTION_CONNECTED


## Connection status of the ENet client peer. The offline peer (no Join yet) reports CONNECTED, so it counts as disconnected.
func _status() -> int:
	var peer: MultiplayerPeer = root.multiplayer.multiplayer_peer
	if not peer is ENetMultiplayerPeer:
		return MultiplayerPeer.CONNECTION_DISCONNECTED
	return peer.get_connection_status()


## Polls cond once per frame until it is true or the seconds run out. Returns the last result.
func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _check(ok: bool, name: String, reason: String) -> void:
	if ok:
		print("PROBE %s ok: %s" % [ROLE, name])
	else:
		_failures += 1
		print("PROBE %s fail: %s %s" % [ROLE, name, reason])


func _finish() -> void:
	quit(0 if _failures == 0 else 1)
