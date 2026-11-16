extends SceneTree
# Contract test for Etapa 20 T28 to T35: replicated enemy and boss bullets (S1, S2, S5).
# Two peers are simulated in one process: the host scans its bullets, the RPC handlers are called
# directly on the client, and RPC wiring is checked through the node's RPC configuration.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const BOSS_BULLET_SCENE_PATH := "res://features/boss/boss_bullet.tscn"
const ENEMY_BULLET_SCENE_PATH := "res://features/enemy/enemy_bullet.tscn"
const SYNC_NODE_NAME := "NetSync"
const CLIENT_TARGET_PORT: int = 7809
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const STEP: float = 1.0 / 60.0

var _failures: int = 0

func _init() -> void:
	call_deferred("_run_contracts")

func _run_contracts() -> void:
	await _check_host_assigns_enemy_bullet_id()
	await _check_replica_lifecycle()
	await _check_host_bullet_hit_damages_host_only()
	await _check_boss_bullet_replica_follows_host()
	await _check_ballistic_and_cluster_replicas_follow_host()
	await _check_bullet_rpcs_are_host_authority_and_guarded()

	if _failures == 0:
		print("ETAPA 20 SYNC BULLETS CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC BULLETS CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)

# T28a (S2, task T5): the host gives every enemy bullet a network id and queues its reliable spawn event.
func _check_host_assigns_enemy_bullet_id() -> void:
	var peer: ENetMultiplayerPeer = _open_server(7810)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var bullet: Node2D = _fire_from_first_enemy(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	_announce(sync)
	var id: int = _id_of(bullet) if bullet != null else 0
	var found: bool = _event_with_id(_outbox(sync, "rpc_host_bullet_spawned"), id).get("id", 0) == id and id > 0
	_expect(found, "Contrato T28a: el host asigna un id de red a cada bala enemiga y la anuncia en un evento fiable")
	_close_session(main, peer)

# T29-T31 (S1/S2, task T5): one spawn event creates a replica at the host's origin that never monitors, collides or
# damages; the removal event frees it.
func _check_replica_lifecycle() -> void:
	var host: Dictionary = await _host_bullet_event(7811)
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	var sync: Node = client.get_node_or_null(SYNC_NODE_NAME)
	var id: int = int(host["event"]["id"])
	_call_checked(sync, "rpc_host_bullet_spawned", 1, [host["event"]])
	var replica: Area2D = _replica_bullet(client, id) as Area2D
	_expect(replica != null and replica.get("replica") == true and replica.global_position.is_equal_approx(host["origin"]), "Contrato T29: el evento de aparicion crea en el cliente un replica visual en el origen del host")
	if replica != null:
		var hits: Array = [0]
		replica.player_hit.connect(func(_p: Node2D) -> void: hits[0] += 1)
		var player := Node2D.new()
		player.add_to_group(&"player")
		replica.call("_on_body_entered", player)
		_expect(replica.monitoring == false and replica.monitorable == false, "Contrato T30a: el replica de bala no monitoriza ni es monitoreable")
		_expect(hits[0] == 0 and not replica.is_queued_for_deletion(), "Contrato T30b: el contacto con el jugador no dana ni destruye el replica de bala")
		player.free()
	_call_checked(sync, "rpc_host_bullets_removed", 1, [[id]])
	_expect(replica != null and replica.is_queued_for_deletion() and _replica_bullet(client, id) == null, "Contrato T31: el evento de baja del host libera el replica de bala")
	_close_session(client, peer)

# T32 (S1, task T5): the host's own bullet still damages through player_hit; the host's bullet is not a replica.
func _check_host_bullet_hit_damages_host_only() -> void:
	var peer: ENetMultiplayerPeer = _open_server(7814)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var bullet: Node2D = _fire_from_first_enemy(main)
	var hits: Array = [0]
	if bullet != null:
		bullet.connect(&"player_hit", func(_p: Node2D) -> void: hits[0] += 1)
		bullet.call("_on_body_entered", main.get("_player"))
	_expect(bullet != null and hits[0] == 1 and bullet.get("replica") == false, "Contrato T32: el impacto de una bala del host dana solo en el host")
	_close_session(main, peer)

# T33 (S2, task T5): a boss bullet is replicated with the host's origin and direction; its removal frees it.
func _check_boss_bullet_replica_follows_host() -> void:
	var peer: ENetMultiplayerPeer = _open_server(7815)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var boss_bullet: Area2D = (load(BOSS_BULLET_SCENE_PATH) as PackedScene).instantiate() as Area2D
	boss_bullet.set("direction", Vector2(0.0, 1.0))
	boss_bullet.set("speed", 300.0)
	main.add_child(boss_bullet)
	boss_bullet.global_position = Vector2(400.0, 200.0)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	_announce(sync)
	var event: Dictionary = _event_with_id(_outbox(sync, "rpc_host_bullet_spawned"), _id_of(boss_bullet))
	var origin: Vector2 = boss_bullet.global_position
	_close_session(main, peer)

	peer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	var client_sync: Node = client.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(client_sync, "rpc_host_bullet_spawned", 1, [event])
	var replica: Area2D = _replica_bullet(client, int(event.get("id", 0))) as Area2D
	var ok: bool = replica != null and replica.monitoring == false and replica.global_position.is_equal_approx(origin)
	ok = ok and replica != null and replica.get("direction").is_equal_approx(Vector2(0.0, 1.0)) and is_equal_approx(float(replica.get("speed")), 300.0)
	_expect(ok, "Contrato T33a: la bala del jefe se replica con el origen y la direccion del host, sin colision")
	_call_checked(client_sync, "rpc_host_bullets_removed", 1, [[int(event.get("id", 0))]])
	_expect(replica != null and replica.is_queued_for_deletion(), "Contrato T33b: la baja de la bala del jefe libera su replica")
	_close_session(client, peer)

# T34 (S2, task T5): the replicas of a parabolic and of a cluster bullet follow the host's path frame by frame.
func _check_ballistic_and_cluster_replicas_follow_host() -> void:
	var peer: ENetMultiplayerPeer = _open_server(7816)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var hosts: Array = [_ballistic_host_bullet(main, 1, Vector2(120.0, 90.0), Vector2(-60.0, 60.0)), _ballistic_host_bullet(main, 2, Vector2(-200.0, 150.0), Vector2(80.0, 100.0))]
	_announce(sync)
	var events: Array = _outbox(sync, "rpc_host_bullet_spawned")
	# The host's path, recorded while its bullets are alive (20 frames of 1/60 s).
	var paths: Array = []
	for host: Variant in hosts:
		var path: Array[Vector2] = []
		for _step: int in 20:
			(host as Node).call("_process", STEP)
			path.append((host as Node2D).global_position)
		paths.append(path)
	_close_session(main, peer)

	peer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	var client_sync: Node = client.get_node_or_null(SYNC_NODE_NAME)
	for event: Variant in events:
		_call_checked(client_sync, "rpc_host_bullet_spawned", 1, [event])
	var worst: float = 0.0
	var pairs: int = 0
	for i: int in mini(paths.size(), events.size()):
		var replica: Node2D = _replica_bullet(client, int((events[i] as Dictionary)["id"]))
		if replica == null:
			worst = 999.0
			continue
		pairs += 1
		for step_index: int in 20:
			replica.call("_process", STEP)
			worst = maxf(worst, replica.global_position.distance_to(paths[i][step_index]))
	_expect(pairs == 2 and worst < 0.5, "Contrato T34: los replicas parabolico y cluster siguen la trayectoria del host (desvio max %.3f px)" % worst)
	_close_session(client, peer)

# T35 (S2, task T5): the bullet RPCs are host-authority; a malformed payload creates no replica and does not fail.
func _check_bullet_rpcs_are_host_authority_and_guarded() -> void:
	var config: Dictionary = (load("res://scripts/net/net_sync_node.gd") as Script).get_rpc_config()
	var authority: bool = true
	for rpc_name: StringName in [&"rpc_host_bullet_spawned", &"rpc_host_bullets_removed"]:
		authority = authority and config.has(rpc_name) and config[rpc_name]["rpc_mode"] == MultiplayerAPI.RPC_MODE_AUTHORITY
	_expect(authority, "Contrato T35a: los eventos de bala son RPC de autoridad del host")
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var client: Node = await _new_main()
	await _start_network_session(client)
	var sync: Node = client.get_node_or_null(SYNC_NODE_NAME)
	_call_checked(sync, "rpc_host_bullet_spawned", 1, [{"id": 9}])
	_call_checked(sync, "rpc_host_bullets_removed", 1, [[]])
	var stray: int = 0
	for child: Node in client.get_children():
		stray += 1 if child.get("replica") == true and child.is_in_group(&"enemy_bullets") else 0
	_expect(stray == 0, "Contrato T35b: un evento de bala malformado no crea replicas ni falla")
	_close_session(client, peer)

# One volley from the first enemy of a host session (real enemy path); returns the first bullet without an id.
func _fire_from_first_enemy(main: Node) -> Node2D:
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.call("start_wave", 1)
	var enemies: Array = spawner.get_children().filter(func(c: Node) -> bool: return c.is_in_group(&"enemies")) if spawner != null else []
	if enemies.is_empty():
		return null
	(enemies[0] as Node).call("_fire_bullet")
	for node: Node in main.get_tree().get_nodes_in_group(&"enemy_bullets"):
		if _id_of(node) == 0:
			return node as Node2D
	return null

# Host session with one enemy bullet announced; returns its spawn event and the origin the bullet had at the announce.
func _host_bullet_event(port: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = _open_server(port)
	var main: Node = await _new_main()
	await _start_network_session(main)
	var bullet: Node2D = _fire_from_first_enemy(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var origin: Vector2 = bullet.global_position if bullet != null else Vector2.ZERO
	_announce(sync)
	var events: Array = _outbox(sync, "rpc_host_bullet_spawned")
	_close_session(main, peer)
	return {"event": events[0] as Dictionary if not events.is_empty() else {"id": 0}, "origin": origin}

# A host enemy bullet of a plasma variant (1 parabolic, 2 cluster) with a launch velocity, added to main.
func _ballistic_host_bullet(main: Node, variant: int, origin: Vector2, launch: Vector2) -> Node2D:
	var bullet: Area2D = (load(ENEMY_BULLET_SCENE_PATH) as PackedScene).instantiate() as Area2D
	bullet.set("plasma_variant", variant)
	bullet.set("ballistic_gravity", 380.0 if variant == 1 else 320.0)
	bullet.set("velocity", launch)
	bullet.set("initial_velocity", launch)
	bullet.set("cluster_fuse_time", 0.55)
	main.add_child(bullet)
	bullet.global_position = origin
	return bullet

# The spawn payload with the id among the events ({"id": 0} when absent).
func _event_with_id(events: Array, id: int) -> Dictionary:
	for event: Variant in events:
		if int((event as Dictionary).get("id", -1)) == id:
			return event as Dictionary
	return {"id": 0}

# Replica of an enemy or boss bullet with the id on a peer (only nodes flagged replica count).
func _replica_bullet(main: Node, id: int) -> Node2D:
	for node: Node in main.get_tree().get_nodes_in_group(&"enemy_bullets"):
		if node.get("replica") == true and _id_of(node) == id and not node.is_queued_for_deletion():
			return node as Node2D
	return null

# net_id of a node as an int (0 when the node carries no id yet).
func _id_of(node: Node) -> int:
	var value: Variant = node.get("net_id")
	return int(value) if value != null else 0

# Runs the host's bullet scan now (the physics path does the same each frame with a client connected).
func _announce(sync: Node) -> void:
	if sync != null and sync.has_method("announce_bullets"):
		sync.call("announce_bullets")
	else:
		_expect(false, "Contrato T28 (precondicion): el nodo de sincronizacion expone announce_bullets")

# Payloads of the reliable events of one method that the host queued (the outbox is drained by this call).
func _outbox(sync: Node, method: String) -> Array:
	var out: Array = []
	if sync == null or not sync.has_method("take_outbox"):
		return out
	for entry: Variant in sync.call("take_outbox"):
		if String((entry as Array)[0]) == method:
			out.append((entry as Array)[1])
	return out

# Calls an RPC only when the method exists with the expected arity; a wrong signature is a failure, never a silent pass.
func _call_checked(obj: Object, method: String, arity: int, args: Array) -> void:
	var exists: bool = obj != null and obj.get_script() != null and obj.get_script().get_script_method_list().any(func(e: Dictionary) -> bool: return e["name"] == method and (e["args"] as Array).size() == arity)
	if exists:
		obj.callv(method, args)
	else:
		_expect(false, "RPC %s con aridad %d no existe en el nodo de sincronizacion" % [method, arity])

func _open_server(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	_expect(peer.create_server(port) == OK, "Contrato T28 (precondicion): el host abre el puerto %d" % port)
	root.multiplayer.multiplayer_peer = peer
	return peer

func _open_client(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	root.multiplayer.multiplayer_peer = peer
	return peer

# Presses Coop en red in a fresh main; the session starts with J2 as the remote peer.
func _start_network_session(main: Node) -> void:
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var net_button: Button = menu.get_node_or_null(NET_COOP_BUTTON) as Button if menu != null else null
	if net_button != null:
		net_button.pressed.emit()

func _close_session(main: Node, peer: MultiplayerPeer) -> void:
	root.multiplayer.multiplayer_peer = null
	peer.close()
	root.remove_child(main)
	main.free()

func _new_main() -> Node:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	return main

func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		_failures += 1
		push_error("✗ %s" % message)
