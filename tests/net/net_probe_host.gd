extends SceneTree
# Two-process probe, HOST side (Etapa 20, gap item 6). Run only by etapa_20_two_process_test.gd.
# Starts the real main scene, opens a Host on PORT_TEXT and starts Coop en red (NETWORK mode, as the lobby does).
# Checks over the real ENet socket: the client connects, the client's input moves J2 here, and the host's
# session end is sent. Prints one "PROBE host ok|fail: <name>" line per check; exits 0 when all pass, 1 otherwise.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const PORT_TEXT := "7791"
const HOST_BUTTON := "Control/NetPanel/ButtonRow/HostButton"
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const PORT_FIELD := "Control/NetPanel/AddressRow/PortField"
const ROLE := "host"
const MIN_MOVE_PX: float = 10.0
const WAIT_CLIENT_SECONDS: float = 30.0
const WAIT_INPUT_SECONDS: float = 20.0
## Seconds the host keeps sending state after the input check, so the client reads J2 before the session ends.
const SETTLE_SECONDS: float = 2.0
## Seconds the host keeps running after the session end, so the reliable packet leaves the socket.
const FLUSH_SECONDS: float = 1.0
const SESSION_STATE_GAME_OVER: int = 5
const SESSION_STATE_PLAYING: int = 1
const NOTICE_NAME := "NetNoticeLabel"
const LEAVE_NOTICE: String = "El otro jugador se desconecto."
## Seconds the host waits for the client to leave mid-match (second match, Etapa 20 T5).
const WAIT_LEAVE_SECONDS: float = 20.0

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = await _open_main()
	var menu: CanvasLayer = main.get_node("MainMenu") as CanvasLayer
	(menu.get_node(PORT_FIELD) as LineEdit).text = PORT_TEXT
	(menu.get_node(HOST_BUTTON) as Button).pressed.emit()
	var hosting: bool = root.multiplayer.multiplayer_peer is ENetMultiplayerPeer and root.multiplayer.is_server()
	_check(hosting, "host opens server on port %s" % PORT_TEXT, "Host button did not open an ENet server")
	if not hosting:
		_finish()
		return
	(menu.get_node(NET_COOP_BUTTON) as Button).pressed.emit()
	var sync: Node = main.get_node_or_null("NetSync")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	var network: bool = main.get("_session_active") == true and sync != null and sync.get("_is_host") == true and p2 != null
	_check(network, "host session starts in NETWORK mode", "active=%s NetSync=%s J2=%s" % [main.get("_session_active"), sync != null, p2 != null])
	if not network:
		_finish()
		return
	var start_x: float = p2.position.x
	var connected: bool = await _wait_for(func() -> bool: return not root.multiplayer.get_peers().is_empty(), WAIT_CLIENT_SECONDS)
	_check(connected, "client connects to the host", "no client connected within %d s" % int(WAIT_CLIENT_SECONDS))
	if not connected:
		_finish()
		return
	var moved: bool = await _wait_for(func() -> bool: return p2.position.x <= start_x - MIN_MOVE_PX, WAIT_INPUT_SECONDS)
	_check(moved, "client input reaches host: J2 moves on the host", "J2 x %.1f -> %.1f (need %.1f px left)" % [start_x, p2.position.x, MIN_MOVE_PX])
	if not moved:
		_finish()
		return
	await _wait_seconds(SETTLE_SECONDS)
	(main.get("_session") as Object).call("end_session")
	var ended: bool = main.get("_session_state") == SESSION_STATE_GAME_OVER and main.get("_session_active") == false
	_check(ended, "host session end is sent: game over on the host", "state=%s active=%s" % [main.get("_session_state"), main.get("_session_active")])
	await _wait_seconds(FLUSH_SECONDS)
	await _run_client_leaves(main)
	_finish()


## Second network match on the same connection: the client leaves mid-match and the host keeps playing with J2 cleared.
func _run_client_leaves(main: Node) -> void:
	main.call("return_to_main_menu")
	var menu: CanvasLayer = main.get_node("MainMenu") as CanvasLayer
	(menu.get_node(NET_COOP_BUTTON) as Button).pressed.emit()
	var sync: Node = main.get_node_or_null("NetSync")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	var again: bool = main.get("_session_active") == true and sync != null and sync.get("_is_host") == true and p2 != null
	_check(again, "host starts a second network match", "active=%s NetSync=%s J2=%s" % [main.get("_session_active"), sync != null, p2 != null])
	if not again:
		return
	var start_x: float = p2.position.x
	var moved: bool = await _wait_for(func() -> bool: return p2.position.x <= start_x - MIN_MOVE_PX, WAIT_INPUT_SECONDS)
	_check(moved, "client input reaches host again before it leaves", "J2 x %.1f -> %.1f (need %.1f px left)" % [start_x, p2.position.x, MIN_MOVE_PX])
	if not moved:
		return
	var left: bool = await _wait_for(func() -> bool: return p2.get("remote_driven") == false, WAIT_LEAVE_SECONDS)
	_check(left, "client leaves mid-match: host notices the lost peer", "J2 still remote %d s after the client left" % int(WAIT_LEAVE_SECONDS))
	if not left:
		return
	await _wait_seconds(SETTLE_SECONDS)
	var active: bool = main.get("_session_active") == true and main.get("_session_state") == SESSION_STATE_PLAYING
	_check(active, "client leaves mid-match: host keeps the match active", "state=%s active=%s" % [main.get("_session_state"), main.get("_session_active")])
	var cleared: bool = int(main.get("_player_two_lives")) == 0 and p2.visible == false
	_check(cleared, "client leaves mid-match: host clears J2 (no lives, hidden)", "J2 lives=%s visible=%s" % [main.get("_player_two_lives"), p2.visible])
	var notice: Label = (main.get("_hud") as Node).get_node_or_null(NOTICE_NAME) as Label
	var shown: bool = notice != null and notice.visible and notice.text == LEAVE_NOTICE
	_check(shown, "client leaves mid-match: host shows the disconnect notice", "notice=\"%s\"" % (notice.text if notice != null else ""))


func _open_main() -> Node:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	return main


## Polls cond once per frame until it is true or the seconds run out. Returns the last result.
func _wait_for(cond: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(ok: bool, name: String, reason: String) -> void:
	if ok:
		print("PROBE %s ok: %s" % [ROLE, name])
	else:
		_failures += 1
		print("PROBE %s fail: %s %s" % [ROLE, name, reason])


func _finish() -> void:
	quit(0 if _failures == 0 else 1)
