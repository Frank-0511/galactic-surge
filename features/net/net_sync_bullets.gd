# net_sync_bullets.gd
# Enemy and boss bullet replication of a network match (Etapa 20 T5, S1/S2). Host: every physics frame it gives
# each new enemy or boss bullet a network id and queues a reliable spawn event (id, kind, plasma variant, origin,
# velocity, gravity). A bullet that hits, leaves the screen, is cleared or detonates queues one reliable removal.
# Client: shows each spawned bullet as a visual replica that flies the host's path; replicas never collide,
# damage or score. Owned by NetSyncNode through _bullets.

extends RefCounted

const ENEMY_BULLET_PATH: String = "res://features/enemy/enemy_bullet.tscn"
const BOSS_BULLET_PATH: String = "res://features/boss/boss_bullet.tscn"
const ENEMY_REPLICA: GDScript = preload("res://features/enemy/enemy_bullet_replica.gd")
const GROUP: StringName = &"enemy_bullets"
const KIND_ENEMY: int = 0
const KIND_BOSS: int = 1
const SPAWN_KEYS: Array = ["id", "kind", "variant", "x", "y", "vx", "vy", "g"]

var _main: Node2D
var _node: Node
var _next_id: int = 0
## Host: tracked bullets by net id.
var _live: Dictionary = {}
## Client: replicas by net id.
var _replicas: Dictionary = {}


func _init(main: Node2D, node: Node) -> void:
	_main = main
	_node = node


## Host side: gives each new bullet an id and queues its spawn event; queues one removal for each bullet that died.
func scan_host() -> void:
	if _main == null or not _main.is_inside_tree():
		return
	var gone: Array = []
	for id: Variant in _live.keys():
		if not _is_alive(_live[id]):
			gone.append(id)
			_live.erase(id)
	for node: Node in _main.get_tree().get_nodes_in_group(GROUP):
		if _id_of(node) > 0 or not _is_alive(node):
			continue
		_next_id += 1
		node.set("net_id", _next_id)
		_live[_next_id] = node
		_node.call("queue_reliable", "rpc_host_bullet_spawned", _spawn_event(node, _next_id))
	if not gone.is_empty():
		_node.call("queue_reliable", "rpc_host_bullets_removed", gone)


## Client side: shows a spawn event as a visual replica at the host's origin with the host's launch state.
## Ignored outside a running session or for a malformed event.
func apply_spawn(event: Dictionary) -> void:
	if _main == null or not _main.get("_session_active") or not event.has_all(SPAWN_KEYS):
		return
	var id: int = int(event["id"])
	if is_instance_valid(_replicas.get(id)):
		return
	var kind: int = int(event["kind"])
	var scene: PackedScene = load(BOSS_BULLET_PATH if kind == KIND_BOSS else ENEMY_BULLET_PATH) as PackedScene
	var visual: Node2D = scene.instantiate() as Node2D if scene != null else null
	if visual == null:
		return
	var origin := Vector2(float(event["x"]), float(event["y"]))
	var launch := Vector2(float(event["vx"]), float(event["vy"]))
	visual.set("net_id", id)
	visual.set("replica", true)
	_main.add_child(visual)
	if kind == KIND_BOSS:
		visual.set("direction", launch.normalized())
		visual.set("speed", launch.length())
		visual.global_position = origin
	else:
		ENEMY_REPLICA.configure(visual as Area2D, int(event["variant"]), origin, launch, float(event["g"]))
	_replicas[id] = visual


## Client side: frees the replicas the host reported as gone.
func remove_ids(ids: Array) -> void:
	for raw: Variant in ids:
		var node: Variant = _replicas.get(int(raw))
		_replicas.erase(int(raw))
		if is_instance_valid(node):
			_detach(node as Node)


## Client side: frees every bullet replica (session end or leaving the match).
func clear() -> void:
	for node: Variant in _replicas.values():
		if is_instance_valid(node):
			_detach(node as Node)
	_replicas.clear()


static func _spawn_event(node: Node, id: int) -> Dictionary:
	var origin: Vector2 = (node as Node2D).global_position
	if "plasma_variant" in node:
		var launch: Vector2 = node.get("velocity")
		return {"id": id, "kind": KIND_ENEMY, "variant": int(node.get("plasma_variant")), "x": origin.x, "y": origin.y,
			"vx": launch.x, "vy": launch.y, "g": float(node.call("get_effective_gravity"))}
	var boss_velocity: Vector2 = (node.get("direction") as Vector2).normalized() * float(node.get("speed"))
	return {"id": id, "kind": KIND_BOSS, "variant": 0, "x": origin.x, "y": origin.y,
		"vx": boss_velocity.x, "vy": boss_velocity.y, "g": 0.0}


static func _is_alive(value: Variant) -> bool:
	if not is_instance_valid(value):
		return false
	var node: Node = value as Node
	if node.is_queued_for_deletion() or not node.is_inside_tree():
		return false
	return not (node.has_method("is_detonating") and bool(node.call("is_detonating")))


static func _id_of(node: Node) -> int:
	var value: Variant = node.get("net_id")
	return int(value) if value != null else 0


static func _detach(node: Node) -> void:
	node.queue_free()
