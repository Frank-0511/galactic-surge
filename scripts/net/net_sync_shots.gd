# net_sync_shots.gd
# Shot replication of a network match (Etapa 20 T2, S2). The host turns each volley of J1 or J2 into a
# small event dictionary; the client replays it as visual-only bullets. Damage, kills and score stay on
# the host: a replayed bullet never collides, and the client never simulates a volley's effects.

extends RefCounted

const WeaponsModule: GDScript = preload("res://features/player/player_weapons.gd")
const EVENT_KEYS: Array = ["ship", "weapon", "level", "x", "y", "dx", "dy", "double"]
const WEAPON_COUNT: int = 3


## Event sent host -> client for one volley: ship slot (1 or 2), weapon kind and level, origin and aim.
static func make_event(ship_index: int, weapon: int, level: int, origin: Vector2, aim: Vector2, double_shot: bool) -> Dictionary:
	return {"ship": ship_index, "weapon": weapon, "level": level, "x": origin.x, "y": origin.y, "dx": aim.x, "dy": aim.y, "double": double_shot}


## Client side: shows the volley of the ship named in the event as visual bullets.
## Returns false (and shows nothing) for a malformed event or a ship that is not in the scene.
static func replay(main: Node2D, event: Dictionary) -> bool:
	if not event.has_all(EVENT_KEYS) or int(event["weapon"]) < 0 or int(event["weapon"]) >= WEAPON_COUNT:
		return false
	var ship: CharacterBody2D = main.get("_player") if int(event["ship"]) == 1 else main.get("_player_two")
	if ship == null:
		return false
	var shots: RefCounted = WeaponsModule.new(ship)
	shots.replay_volley(int(event["weapon"]), int(event["level"]), Vector2(float(event["x"]), float(event["y"])), Vector2(float(event["dx"]), float(event["dy"])), bool(event["double"]))
	return true
