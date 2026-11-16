# net_sync_score.gd
# Score and end of a network match (Etapa 20 T4, S1). Host: adds the score of J1 and J2 to the state (20 Hz) and
# builds the reliable session-end event (game over or mission complete) with the final scores. Client: shows the
# host's scores on its HUD and ends its own session through the existing session path, back to the menu with a
# notice. Lives travel with each ship in the state (net_sync_node.gd). Stateless: every function is static.

extends RefCounted

const NOTICE_GAME_OVER: String = "La partida termino en el host: fin del juego."
const NOTICE_MISSION_COMPLETE: String = "La partida termino en el host: mision completada."


## Host side: adds the score of J1 and J2 to state.
static func encode_into(main: Node2D, state: Dictionary) -> void:
	state["score"] = int(main.get("score"))
	state["score_p2"] = int(main.get("score_p2"))


## Client side: keeps the host's scores of J1 and J2 and shows them on the HUD.
static func apply(main: Node2D, state: Dictionary) -> void:
	if not state.has("score") or not state.has("score_p2"):
		return
	main.set("score", int(state["score"]))
	main.set("score_p2", int(state["score_p2"]))
	main._hud.set_score(int(state["score"]))
	main._hud.set_score_p2(int(state["score_p2"]))


## Host side: the event that ends the match on the client: kind ("game_over" or "mission_complete") and final scores.
static func session_end_event(main: Node2D, kind: String) -> Dictionary:
	return {"kind": kind, "score": int(main.get("score")), "score_p2": int(main.get("score_p2"))}


## Client side: takes the host's final scores, ends the local session through the existing session path and goes
## back to the menu with a notice. Ignored when no session is running here.
static func apply_session_end(main: Node2D, event: Dictionary) -> void:
	if not main.get("_session_active") or not event.has("kind"):
		return
	main.set("score", int(event.get("score", main.get("score"))))
	main.set("score_p2", int(event.get("score_p2", main.get("score_p2"))))
	var mission: bool = String(event["kind"]) == "mission_complete"
	if mission:
		main._session.complete_mission()
	else:
		main._session.end_session()
	main._enter_main_menu()
	if main._main_menu.has_method(&"show_network_message"):
		main._main_menu.show_network_message(NOTICE_MISSION_COMPLETE if mission else NOTICE_GAME_OVER)
