# net_sync_loot.gd
# Loot replication of a network match (Etapa 20 T4, S1/S3). Host: gives each drop a network id, queues a
# reliable spawn event (id, type, position) and, when a ship collects it, a reliable pickup event (id, collector
# 1 or 2). Client: shows each spawned drop as a visual replica (no pickup, no collision, no magnet) and removes
# it on the pickup event. Owned by NetSyncNode through _loot.

extends RefCounted

const DROP_SCENE_PATH: String = "res://features/loot/loot_drop.tscn"

var _main: Node2D
var _node: Node
var _next_id: int = 0
## Client: replica drops by net id.
var _replicas: Dictionary = {}


func _init(main: Node2D, node: Node) -> void:
	_main = main
	_node = node


## Host side: gives the configured drop a new id, queues its spawn event and reports its pickup.
func announce_spawn(loot: Node, loot_type: int, spawn_position: Vector2) -> void:
	_next_id += 1
	var id: int = _next_id
	loot.set("net_id", id)
	loot.connect(&"collected", _on_host_collected.bind(id))
	_node.call("queue_reliable", "rpc_host_loot_spawned", {"id": id, "type": loot_type, "x": spawn_position.x, "y": spawn_position.y})


## Host side: a ship collected the drop; the collector is 2 for J2 and 1 for J1 (the default, as in singleplayer).
func _on_host_collected(_loot_type: int, collector: Node2D, id: int) -> void:
	var ship: int = 2 if collector != null and collector == _main.get("_player_two") else 1
	_node.call("queue_reliable", "rpc_host_loot_picked", {"id": id, "collector": ship})


## Client side: shows the drop of a spawn event as a visual replica. Ignored outside a running session or for a malformed event.
func apply_spawn(event: Dictionary) -> void:
	if _main == null or not _main.get("_session_active") or not event.has_all(["id", "type", "x", "y"]):
		return
	var id: int = int(event["id"])
	if _replicas.has(id):
		return
	var scene: PackedScene = load(DROP_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var drop: Area2D = scene.instantiate() as Area2D
	if drop == null:
		return
	drop.set("net_id", id)
	drop.set("replica", true)
	drop.call("configure", int(event["type"]), Vector2(float(event["x"]), float(event["y"])))
	_main.add_child(drop)
	_replicas[id] = drop


## Client side: removes the replica the host picked up and records which ship (1 or 2) collected it.
func apply_pickup(event: Dictionary) -> void:
	if not event.has_all(["id", "collector"]):
		return
	var id: int = int(event["id"])
	var drop: Variant = _replicas.get(id)
	_replicas.erase(id)
	if not is_instance_valid(drop):
		return
	var node: Node = drop as Node
	node.set("collected_by", int(event["collector"]))
	_main.remove_child(node)
	node.queue_free()


## Client side: frees every replica (session end or leaving the match).
func clear() -> void:
	for drop: Variant in _replicas.values():
		if is_instance_valid(drop):
			(drop as Node).queue_free()
	_replicas.clear()
