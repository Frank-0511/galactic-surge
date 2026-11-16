# net_sync_boss.gd
# Boss replication of a network match (Etapa 20 T3, S2). Host: encodes the live boss (id, position, tilt,
# health, armor phase, movement state, enraged flag). Client: creates one replica boss from that state,
# keeps it at the host's position and phase, and frees it when the host reports its removal. A replica
# never moves, shoots, collides or takes damage. Owned by NetSyncEnemies through _boss_sync.

extends RefCounted

const BossScene: PackedScene = preload("res://features/boss/boss.tscn")

var _main: Node2D
var _replica: Node2D = null
var _replica_id: int = 0


func _init(main: Node2D) -> void:
	_main = main


## Stable id of the boss of chapter N: -N. Enemy ids are positive, so the two never collide.
static func boss_id_for_chapter(chapter: int) -> int:
	return -chapter


## Host side: the live boss as a dictionary, or {} when no boss is alive.
func encode() -> Dictionary:
	var boss: Node2D = _main.get("_active_boss") as Node2D
	if boss == null or boss.is_queued_for_deletion():
		return {}
	return {
		"id": boss_id_for_chapter(int(_main.get("_chapter"))),
		"variant": String(boss.get("boss_variant")),
		"x": boss.position.x,
		"y": boss.position.y,
		"rot": boss.rotation,
		"health": int(boss.get("health")),
		"max_health": int(boss.get("max_health")),
		"phase": int(boss.call("get_armor_phase")),
		"state": int(boss.call("get_movement_state")),
		"enraged": bool(boss.get("is_enraged")),
		"multi_phase": bool(boss.get("multi_phase_enabled")),
	}


## Client side: creates or updates the replica boss from the host's boss dictionary ({} = nothing to show).
func apply(data: Dictionary) -> void:
	if data.is_empty():
		return
	var id: int = int(data["id"])
	if _replica != null and _replica_id != id:
		remove(_replica_id)
	if _replica == null:
		_replica = _create(data, id)
		_replica_id = id
	if _replica == null:
		return
	_replica.call("apply_replica_state", data)
	_main._hud.update_boss_health(int(data["health"]), int(data["max_health"]))


## Client side: frees the replica when the host reports the boss with this id as removed.
func remove(id: int) -> void:
	if _replica == null or _replica_id != id:
		return
	_main.remove_child(_replica)
	_replica.queue_free()
	_replica = null
	_main._active_boss = null
	_main._hud.hide_boss_health_bar()


func _create(data: Dictionary, id: int) -> Node2D:
	var boss: Node2D = BossScene.instantiate() as Node2D
	if boss == null:
		return null
	boss.set("replica", true)
	boss.set("boss_variant", StringName(String(data["variant"])))
	boss.set("multi_phase_enabled", bool(data["multi_phase"]))
	boss.set("max_health", int(data["max_health"]))
	_main.add_child(boss)
	_main._active_boss = boss
	var chapter_index: int = clampi(-id - 1, 0, _main.BOSS_NAMES_BY_CHAPTER.size() - 1)
	_main._hud.show_boss_health_bar(_main.BOSS_NAMES_BY_CHAPTER[chapter_index], int(data["max_health"]))
	return boss
