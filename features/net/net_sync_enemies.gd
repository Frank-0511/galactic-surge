# net_sync_enemies.gd
# Enemy and wave replication of a network match (Etapa 20 T3, S1/S2). Host: encodes every live enemy of
# the formation (id, variant, position, tilt, health, movement state, enraged flag), the boss and the
# spawner phase, and collects the ids that left since the last send. Client: creates, updates and frees
# replica enemies from that state; replicas never simulate, collide or damage. Ids the host removed are
# remembered so a late state packet cannot bring them back. The boss lives in net_sync_boss.gd.
# Owned by NetSyncNode through _enemies.

extends RefCounted

const NetSyncBoss: GDScript = preload("res://features/net/net_sync_boss.gd")

## Spawner phases sent in the state.
const PHASE_STOPPED: int = 0
const PHASE_FORMATION: int = 1
const PHASE_FLYING_IN: int = 2

var _main: Node2D
var _boss_sync: RefCounted
## Host: ids present in the last encoded state, and ids that left and are not reported yet.
var _known_ids: Dictionary = {}
var _pending_removed: Dictionary = {}
## Client: ids the host removed. Ids are never reused within a session, so they stay removed.
var _removed_ids: Dictionary = {}
## Client: last spawner phase received from the host.
var _phase: int = PHASE_STOPPED


func _init(main: Node2D) -> void:
	_main = main
	_boss_sync = NetSyncBoss.new(main)


## Host side: adds the enemies, the boss, the wave and the spawner phase to state, and records the ids that left.
func encode_into(state: Dictionary) -> void:
	var spawner: Node = _main.get_node_or_null("EnemySpawner")
	var entries: Array = []
	var live: Dictionary = {}
	if spawner != null:
		for node: Node2D in _live_enemies(spawner):
			var id: int = _net_id(node)
			entries.append({
				"id": id,
				"variant": String(node.call("get_variant_id")),
				"x": node.position.x,
				"y": node.position.y,
				"rot": node.rotation,
				"health": float(node.get("health")),
				"state": int(node.call("get_state")),
				"enraged": bool(node.call("is_enraged")),
			})
			live[id] = true
	var boss: Dictionary = _boss_sync.encode()
	if not boss.is_empty():
		live[int(boss["id"])] = true
	for id: Variant in _known_ids:
		if not live.has(id):
			_pending_removed[id] = true
	_known_ids = live
	state["enemies"] = entries
	state["boss"] = boss
	state["wave"] = int(_main.get("wave"))
	state["spawn_wave"] = int(spawner.call("get_current_wave")) if spawner != null else 0
	state["phase"] = _host_phase(spawner)
	state["enraged"] = bool(spawner.call("is_enraged")) if spawner != null else false


## Host side: the ids that left since the last call, cleared by the call (sent on the reliable channel).
func take_pending_removed() -> Array:
	var ids: Array = _pending_removed.keys()
	_pending_removed.clear()
	return ids


## Client side: the spawner phase last received from the host (PHASE_* value).
func get_phase() -> int:
	return _phase


## Client side: creates, updates and frees replicas from the host's state. Ignored outside a running session.
func apply_state(state: Dictionary) -> void:
	if _main == null or not _main.get("_session_active") or not state.has("enemies"):
		return
	var spawner: Node = _main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	_phase = int(state.get("phase", PHASE_STOPPED))
	_main.set("wave", int(state.get("wave", 1)))
	_main._hud.set_wave(int(state.get("wave", 1)))
	spawner.call("apply_replica_phase", int(state.get("spawn_wave", 0)), _phase == PHASE_FLYING_IN, bool(state.get("enraged", false)))
	for entry: Variant in state["enemies"]:
		_apply_enemy(spawner, entry as Dictionary)
	_boss_sync.apply(state.get("boss", {}) as Dictionary)


## Client side: frees the replicas (and the boss) the host reported as removed.
func remove_ids(ids: Array) -> void:
	var spawner: Node = _main.get_node_or_null("EnemySpawner") if _main != null else null
	for raw: Variant in ids:
		var id: int = int(raw)
		_removed_ids[id] = true
		if id < 0:
			_boss_sync.remove(id)
		elif spawner != null:
			var node: Node = _replica_node(spawner, id)
			if node != null:
				spawner.remove_child(node)
				node.queue_free()


func _apply_enemy(spawner: Node, entry: Dictionary) -> void:
	var id: int = int(entry["id"])
	if _removed_ids.has(id):
		return
	var node: Node2D = _replica_node(spawner, id)
	if node == null:
		node = _create_replica(spawner, id, String(entry["variant"]))
		if node == null:
			return
	node.position = Vector2(float(entry["x"]), float(entry["y"]))
	node.rotation = float(entry["rot"])
	node.call("apply_replica_state", int(entry["state"]), float(entry["health"]), bool(entry["enraged"]))


func _create_replica(spawner: Node, id: int, variant: String) -> Node2D:
	var scene: PackedScene = spawner.get("enemy_scene") as PackedScene
	if scene == null:
		return null
	var enemy: Node2D = scene.instantiate() as Node2D
	if enemy == null:
		return null
	enemy.set("net_id", id)
	enemy.set("replica", true)
	enemy.call("apply_variant", StringName(variant))
	spawner.add_child(enemy)
	return enemy


func _replica_node(spawner: Node, id: int) -> Node2D:
	for node: Node2D in _live_enemies(spawner):
		if _net_id(node) == id:
			return node
	return null


func _live_enemies(spawner: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child: Node in spawner.get_children():
		if child is Node2D and child.is_in_group(&"enemies") and not child.is_queued_for_deletion():
			out.append(child as Node2D)
	return out


func _host_phase(spawner: Node) -> int:
	if spawner == null or not bool(spawner.call("is_running")):
		return PHASE_STOPPED
	return PHASE_FLYING_IN if bool(spawner.call("is_flying_in")) else PHASE_FORMATION


static func _net_id(node: Node) -> int:
	var value: Variant = node.get("net_id")
	return int(value) if value != null else 0
