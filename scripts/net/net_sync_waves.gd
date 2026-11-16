# net_sync_waves.gd
# Wave transitions and announcements of a network match (Etapa 20, gap 5 of T3). Host: when a wave is cleared
# (main_waves.gd show_transition), queues one reliable event with the global wave, its local wave, the announcement
# text and the session state. Client: shows the same announcement on its own WaveAnnouncement and takes the wave
# number and the session state from the host; it never starts or advances a wave. The host's 20 Hz state carries
# the session state too, so the client follows the host even when an event arrives late. Owned by NetSyncNode.

extends RefCounted

var _main: Node2D
var _node: Node


func _init(main: Node2D, node: Node) -> void:
	_main = main
	_node = node


## Host side: adds the session state to the 20 Hz state.
func encode_into(state: Dictionary) -> void:
	state["session_state"] = int(_main.get("_session_state"))


## Host side: the host shows the announcement `phrase` for the next wave; queues the event for the client.
func announce_transition(phrase: String) -> void:
	var wave: int = int(_main.get("wave"))
	_node.queue_reliable("rpc_host_wave_transition", {
		"wave": wave,
		"local_wave": _main._waves.local_wave(wave),
		"text": phrase,
		"state": int(_main.get("_session_state")),
	})


## Client side: shows the host's announcement and takes the host's wave number and session state. Ignored outside a session.
func apply_transition(event: Dictionary) -> void:
	if not _main.get("_session_active") or not event.has("wave"):
		return
	var wave: int = int(event["wave"])
	_main.set("wave", wave)
	_main._hud.set_wave(wave)
	_follow(int(event.get("state", -1)))
	_main._wave_announcement.show_announcement(wave + 1, String(event.get("text", "")))


## Client side: takes the host's session state from the 20 Hz state. Ignored outside a session.
func apply_state(state: Dictionary) -> void:
	if not _main.get("_session_active") or not state.has("session_state"):
		return
	_follow(int(state["session_state"]))


## Copies a host session state the client shows (PLAYING, WAVE_TRANSITION, BOSS_BATTLE); other states stay local.
func _follow(host_state: int) -> void:
	if host_state == _main.SessionState.PLAYING or host_state == _main.SessionState.WAVE_TRANSITION or host_state == _main.SessionState.BOSS_BATTLE:
		_main.set("_session_state", host_state)
