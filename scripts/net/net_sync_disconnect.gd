# net_sync_disconnect.gd
# Disconnects in the middle of a network match (Etapa 20 T5, S4). Host: when the J2 client leaves, J2 leaves the
# match (no remote ship, no lives, HUD panel hidden) and the session goes on solo, with a notice. Client: when the
# host is lost, the NetSync node (and with it every replica and the sync state) is freed and the ships and the
# spawner stop being replicas before the menu shows its notice. Used by NetSyncNode and MainWiring.

extends RefCounted

const NET_NODE_NAME: String = "NetSync"
const NOTICE_NAME: String = "NetNoticeLabel"
const HOST_LEFT_TEXT: String = "El otro jugador se desconecto."
const NOTICE_POSITION: Vector2 = Vector2(24.0, 120.0)


## Host side: J2 leaves the match when its client is the peer that left. Other peers, a match that is not running,
## or a second report of the same loss change nothing (J2 is no longer remote after the first one).
static func host_peer_left(main: Node2D, is_host: bool, remote_peer: int, peer_id: int) -> void:
	if not is_host or main == null or not main._session_active:
		return
	if remote_peer != 0 and peer_id != remote_peer:
		return
	var p2: CharacterBody2D = main._player_two
	if p2 == null or p2.get("remote_driven") != true:
		return
	main._ships.set_player_two_active(false)
	p2.set("remote_driven", false)
	main._player_two_lives = 0
	main._hud.set_lives_p2(0)
	show_notice(main, HOST_LEFT_TEXT)


## Client side: a lost host. Frees the NetSync node (its replicas leave with it) and drops the replica roles.
## Safe without a match: it only finds nothing to free.
static func clean_client(main: Node2D) -> void:
	var sync: Node = main.get_node_or_null(NET_NODE_NAME)
	if sync != null:
		main.remove_child(sync)
		sync.queue_free()
	for ship: Variant in [main._player, main._player_two]:
		if ship != null:
			ship.set("replica", false)
	main._enemy_spawner.set("replica", false)


## Shows a notice on the HUD (created on first use). The notice belongs to the match and is hidden by clear_notice.
static func show_notice(main: Node2D, text: String) -> void:
	var hud: Node = main._hud
	var label: Label = hud.get_node_or_null(NOTICE_NAME) as Label
	if label == null:
		label = Label.new()
		label.name = NOTICE_NAME
		label.position = NOTICE_POSITION
		hud.add_child(label)
	label.text = text
	label.visible = true


## Hides the notice. Called when a match starts or the menu returns, so it never leaks into the next match.
static func clear_notice(main: Node2D) -> void:
	if main._hud == null:
		return
	var label: Label = main._hud.get_node_or_null(NOTICE_NAME) as Label
	if label != null:
		label.visible = false
		label.text = ""
