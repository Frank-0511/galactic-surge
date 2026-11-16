# net_sync_asteroids.gd
# Asteroid replication of a network match (Etapa 20 T4, S1/S3). Host: gives each live asteroid a network id on its
# first send, encodes every live rock (id, position, size, rotation) into the state at 20 Hz, and queues a reliable
# removal event for the ids that left. Client: creates, moves and frees asteroid replicas from that state; replicas
# never move on their own, collide or damage. Ids the host removed are remembered so a late state cannot bring them
# back. Owned by NetSyncNode through _asteroids.

extends RefCounted

var _main: Node2D
var _node: Node
var _next_id: int = 0
## Host: ids present in the last encoded state.
var _known_ids: Dictionary = {}
## Client: replicas by net id, and the ids the host removed (never reused within a match).
var _replicas: Dictionary = {}
var _removed_ids: Dictionary = {}


func _init(main: Node2D, node: Node) -> void:
	_main = main
	_node = node


## Host side: adds every live asteroid to state and queues one reliable removal event for the ids that left.
func encode_into(state: Dictionary) -> void:
	var spawner: Node = _main.get_node_or_null("AsteroidSpawner")
	var entries: Array = []
	var live: Dictionary = {}
	if spawner != null:
		for rock: Node2D in _live_rocks(spawner):
			var id: int = _ensure_id(rock)
			entries.append({
				"id": id,
				"x": rock.global_position.x,
				"y": rock.global_position.y,
				"size": int(rock.get("asteroid_size")),
				"rot": rock.rotation,
			})
			live[id] = true
	var gone: Array = []
	for id: Variant in _known_ids:
		if not live.has(id):
			gone.append(id)
	if not gone.is_empty():
		_node.call("queue_reliable", "rpc_host_asteroids_removed", gone)
	_known_ids = live
	state["asteroids"] = entries


## Client side: creates, moves and frees the asteroid replicas of the host state. Ignored outside a running session.
func apply_state(state: Dictionary) -> void:
	if _main == null or not _main.get("_session_active") or not state.has("asteroids"):
		return
	var spawner: Node = _main.get_node_or_null("AsteroidSpawner")
	if spawner == null:
		return
	for entry: Variant in state["asteroids"]:
		_apply_rock(spawner, entry as Dictionary)


## Client side: frees the replicas the host reported as removed; their ids are remembered.
func remove_ids(ids: Array) -> void:
	for raw: Variant in ids:
		var id: int = int(raw)
		_removed_ids[id] = true
		var rock: Variant = _replicas.get(id)
		_replicas.erase(id)
		if is_instance_valid(rock):
			_detach(rock as Node)


## Client side: frees every replica (session end or leaving the match).
func clear() -> void:
	for rock: Variant in _replicas.values():
		if is_instance_valid(rock):
			(rock as Node).queue_free()
	_replicas.clear()
	_removed_ids.clear()


func _apply_rock(spawner: Node, entry: Dictionary) -> void:
	var id: int = int(entry["id"])
	if _removed_ids.has(id):
		return
	var rock_value: Variant = _replicas.get(id)
	if not is_instance_valid(rock_value):
		rock_value = _create(spawner, id, int(entry["size"]))
		if rock_value == null:
			return
	var rock: Node2D = rock_value as Node2D
	rock.global_position = Vector2(float(entry["x"]), float(entry["y"]))
	rock.rotation = float(entry["rot"])


func _create(spawner: Node, id: int, size: int) -> Node2D:
	var scene: PackedScene = spawner.get("asteroid_scene") as PackedScene
	if scene == null:
		return null
	var rock: Node2D = scene.instantiate() as Node2D
	if rock == null:
		return null
	rock.set("net_id", id)
	rock.set("replica", true)
	rock.call("set_size", size)
	spawner.add_child(rock)
	_replicas[id] = rock
	return rock


func _detach(rock: Node) -> void:
	var parent: Node = rock.get_parent()
	if parent != null:
		parent.remove_child(rock)
	rock.queue_free()


func _ensure_id(rock: Node) -> int:
	var id: int = int(rock.get("net_id"))
	if id <= 0:
		_next_id += 1
		id = _next_id
		rock.set("net_id", id)
	return id


func _live_rocks(spawner: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child: Node in spawner.get_children():
		if child is Node2D and child.is_in_group(&"asteroids") and not child.is_queued_for_deletion() and child.get("replica") != true:
			out.append(child as Node2D)
	return out
