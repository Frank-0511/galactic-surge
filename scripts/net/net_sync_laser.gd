# net_sync_laser.gd
# Laser replication of a network match (Etapa 20 T36, S2). The host decides each ship's laser (firing, power level,
# origin and length) and sends one entry per ship inside every state packet (20 Hz). The client shows a visual-only
# LaserReplica child of the remote ship while the host reports it firing, and hides it when the host stops.
# Damage, heat and score stay on the host: the replica never monitors, collides or damages.

extends RefCounted

const LaserReplicaScript: GDScript = preload("res://scenes/entities/bullet/laser_replica.gd")
const REPLICA_NAME: String = "LaserReplica"
const ENTRY_KEYS: Array = ["ship", "firing", "level", "x", "y", "length"]


## Host side: adds one laser entry for J1 and J2 to the state packet (key "lasers").
static func encode_into(main: Node2D, state: Dictionary) -> void:
	state["lasers"] = [_encode_ship(main, 1), _encode_ship(main, 2)]


## Client side: shows or hides each ship's laser replica from the host's entries. Ignored outside a running session.
static func apply(main: Node2D, state: Dictionary) -> void:
	if not is_instance_valid(main) or main.get("_session_active") != true:
		return
	for entry: Variant in state.get("lasers", []):
		if entry is Dictionary and (entry as Dictionary).has_all(ENTRY_KEYS):
			_apply_entry(main, entry as Dictionary)


## Client side: hides every laser replica (session end, new session or leaving the match).
static func hide_all(main: Node2D) -> void:
	if not is_instance_valid(main):
		return
	for slot: int in [1, 2]:
		var ship: Node2D = _ship_of(main, slot)
		var replica: Node = ship.get_node_or_null(REPLICA_NAME) if ship != null else null
		if replica != null:
			replica.call("hide_beam")


static func _encode_ship(main: Node2D, slot: int) -> Dictionary:
	var ship: Node = _ship_of(main, slot)
	var beam: Node = ship.get("_laser_beam") as Node if ship != null else null
	var live: bool = is_instance_valid(beam)
	var origin: Vector2 = (beam as Node2D).global_position if live else Vector2.ZERO
	return {
		"ship": slot,
		"firing": live and beam.get("is_firing") == true,
		"level": ship.call("get_weapon_level") if ship != null else 1,
		"x": origin.x,
		"y": origin.y,
		"length": float(beam.call("get_active_length")) if live else 0.0,
	}


static func _apply_entry(main: Node2D, entry: Dictionary) -> void:
	var ship: Node2D = _ship_of(main, int(entry["ship"]))
	if ship == null:
		return
	if not bool(entry["firing"]):
		var idle: Node = ship.get_node_or_null(REPLICA_NAME)
		if idle != null:
			idle.call("hide_beam")
		return
	var replica: Node = _replica_for(ship)
	replica.call("show_beam", Vector2(float(entry["x"]), float(entry["y"])), float(entry["length"]), int(entry["level"]))


## The laser replica of a ship; created on first use as a top-level child so it keeps the host's origin.
static func _replica_for(ship: Node2D) -> Node:
	var existing: Node = ship.get_node_or_null(REPLICA_NAME)
	if existing != null:
		return existing
	var replica: Area2D = LaserReplicaScript.new() as Area2D
	replica.name = REPLICA_NAME
	replica.top_level = true
	ship.add_child(replica)
	return replica


static func _ship_of(main: Node2D, slot: int) -> Node2D:
	return main.get("_player") as Node2D if slot == 1 else main.get("_player_two") as Node2D
