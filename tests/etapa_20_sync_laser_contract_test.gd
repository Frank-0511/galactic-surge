extends SceneTree
# Contract test for Etapa 20 T36 onward: the host's laser (firing, power level, origin, length) is replicated in the
# state path, and the client shows a visual-only laser replica that never monitors, collides or damages (S2, S5).
# Two peers are simulated in one process, one after the other: the host session, then the client session.

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const SYNC_NODE_NAME := "NetSync"
const REPLICA_NAME := "LaserReplica"
const NET_COOP_BUTTON := "Control/NetPanel/ButtonRow/NetCoopButton"
const HOST_PORT_A: int = 7801
const CLIENT_TARGET_PORT: int = 7802
const WEAPON_LASER: int = 2
const LASER_BEAM_PATH: String = "res://features/bullet/laser_beam.tscn"
const DUMMY_ENEMY_SOURCE := "extends Area2D\nvar hits := 0\nfunc supports_fractional_damage() -> void: pass\nfunc take_damage(_amount) -> void: hits += 1\n"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	await _check_host_laser()
	await _check_client_laser_replica()
	_check_beam_width_curve_unchanged()

	if _failures == 0:
		print("ETAPA 20 SYNC LASER CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 SYNC LASER CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T36, T39a, T40a (host): the host's state carries each ship's laser while it fires, the host's laser damages
# an enemy on the host, and the state reports the laser off once the host stops firing.
func _check_host_laser() -> void:
	var peer: ENetMultiplayerPeer = _open_server(HOST_PORT_A)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var beam: Area2D = p2.get("_laser_beam") as Area2D if p2 != null else null
	var dummy: Area2D = _add_dummy_enemy(main, Vector2(p2.global_position.x if p2 != null else 0.0, 400.0))
	if sync != null and p2 != null and _has_arity(sync, "rpc_client_input", 2):
		p2.call("set_weapon", WEAPON_LASER)
		sync.call("rpc_client_input", 0.0, true)
		for i: int in 30:
			await physics_frame
	var entry: Dictionary = _laser_entry(sync, 2)
	_expect(entry.get("firing") == true, "Contrato T36a: el estado del host lleva el laser de J2 con firing=true mientras dispara")
	_expect(p2 != null and int(entry.get("level", -1)) == p2.get_weapon_level(), "Contrato T36b: el laser replicado lleva el nivel de potencia de J2")
	_expect(beam != null and Vector2(float(entry.get("x", -1.0)), float(entry.get("y", -1.0))).distance_to(beam.global_position) < 0.5, "Contrato T36c: el laser replicado lleva el origen del laser del host")
	_expect(float(entry.get("length", 0.0)) > 0.0, "Contrato T36d: el laser replicado lleva su largo")
	_expect(_laser_entry(sync, 1).get("firing") == false, "Contrato T36e: J1 aparece en el estado del host sin disparar")
	_expect(dummy != null and int(dummy.get("hits")) > 0, "Contrato T40a: el laser del host dania al enemigo en el host")
	if sync != null and _has_arity(sync, "rpc_client_input", 2):
		sync.call("rpc_client_input", 0.0, false)
		for i: int in 5:
			await physics_frame
	_expect(_laser_entry(sync, 2).get("firing") == false, "Contrato T39a: el estado del host marca el laser de J2 apagado al soltar el disparo")
	_close_session(main, peer)


# T37, T38, T39b, T40b (client): the host's laser shows as a replica at the host origin with the host length;
# the replica never monitors, collides or damages, and it hides when the host stops firing.
func _check_client_laser_replica() -> void:
	var peer: ENetMultiplayerPeer = _open_client(CLIENT_TARGET_PORT)
	var main: Node = await _new_main()
	var p2: CharacterBody2D = await _start_network_session(main)
	var sync: Node = main.get_node_or_null(SYNC_NODE_NAME)
	var dummy: Area2D = _add_dummy_enemy(main, Vector2(300.0, 100.0))
	if sync != null and p2 != null and _has_arity(sync, "rpc_host_state", 1):
		sync.call("rpc_host_state", _laser_state(300.0, 300.0, 250.0, true))
	var replica: Area2D = _replica_of(p2)
	_expect(replica != null and replica.visible, "Contrato T37a: el cliente muestra el laser replicado de J2 mientras el host dispara")
	_expect(replica != null and replica.global_position.distance_to(Vector2(300.0, 300.0)) < 0.5, "Contrato T37b: la replica del laser nace en el origen que envio el host")
	_expect(replica != null and absf(float(replica.get("length")) - 250.0) < 0.01, "Contrato T37c: la replica del laser usa el largo que envio el host")
	_expect(replica != null and replica.monitoring == false and replica.monitorable == false, "Contrato T38a: la replica del laser no monitorea ni es detectable")
	_expect(replica != null and replica.collision_layer == 0 and replica.collision_mask == 0 and replica.find_children("*", "CollisionShape2D", false, false).is_empty(), "Contrato T38b: la replica del laser no tiene colision")
	for i: int in 30:
		await physics_frame
	_expect(dummy != null and int(dummy.get("hits")) == 0, "Contrato T38c: la replica del laser no dania al enemigo que cruza su haz")
	if sync != null and p2 != null and _has_arity(sync, "rpc_host_state", 1):
		sync.call("rpc_host_state", _laser_state(300.0, 300.0, 250.0, false))
	replica = _replica_of(p2)
	_expect(replica == null or not replica.visible, "Contrato T39b: el laser replicado se oculta cuando el host deja de disparar")
	_close_session(main, peer)


# T41 (PRESERVE, singleplayer and coop share LaserBeam.set_power_level): the beam width curve keeps its values.
# Levels 1-10: 4 + 2.2 * (level - 1); above 10: plus 3 per level over 10.
func _check_beam_width_curve_unchanged() -> void:
	var beam: Area2D = (load(LASER_BEAM_PATH) as PackedScene).instantiate() as Area2D
	root.add_child(beam)
	var expected: Dictionary = {1: 4.0, 5: 12.8, 10: 23.8, 11: 26.8, 15: 38.8}
	for level: int in expected:
		beam.call("set_power_level", level)
		var width: float = float(beam.get("beam_width"))
		_expect(absf(width - float(expected[level])) < 0.0001, "Contrato T41: el ancho del laser en nivel %d sigue igual (%.1f)" % [level, float(expected[level])])
	root.remove_child(beam)
	beam.free()


# The host's state entry for one ship (ship 1 or 2) from build_state(); empty when missing.
func _laser_entry(sync: Node, ship: int) -> Dictionary:
	if sync == null or not sync.has_method("build_state"):
		return {}
	var state: Dictionary = sync.call("build_state")
	for entry: Variant in state.get("lasers", []):
		if entry is Dictionary and int((entry as Dictionary).get("ship", 0)) == ship:
			return entry as Dictionary
	return {}


# A host state packet with only the laser of J2 (the other keys are optional on the client).
func _laser_state(x: float, y: float, length: float, firing: bool) -> Dictionary:
	return {"lasers": [{"ship": 2, "firing": firing, "level": 3, "x": x, "y": y, "length": length}]}


# The laser replica the client keeps for a ship (a child named LaserReplica); null when missing.
func _replica_of(ship: Node) -> Area2D:
	if ship == null:
		return null
	return ship.get_node_or_null(REPLICA_NAME) as Area2D


# An enemy stand-in in the group the laser targets: it counts the damage it takes.
func _add_dummy_enemy(main: Node, at: Vector2) -> Area2D:
	var script := GDScript.new()
	script.source_code = DUMMY_ENEMY_SOURCE
	script.reload()
	var dummy: Area2D = script.new() as Area2D
	dummy.add_to_group(&"enemies")
	main.add_child(dummy)
	dummy.global_position = at
	return dummy


# True when obj's script has the method with that arity (a wrong RPC call would abort the check).
func _has_arity(obj: Object, method: String, arity: int) -> bool:
	return obj.get_script().get_script_method_list().any(func(e: Dictionary) -> bool: return e["name"] == method and (e["args"] as Array).size() == arity)


# Opens a Host on port: the scene multiplayer peer is the server (authority, peer id 1).
func _open_server(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port)
	_expect(err == OK, "Contrato T36 (precondicion): el host abre el puerto %d" % port)
	root.multiplayer.multiplayer_peer = peer
	return peer


# Joins a Host on port: the scene multiplayer peer is a client (not the authority).
func _open_client(port: int) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	root.multiplayer.multiplayer_peer = peer
	return peer


# Presses Coop en red in a fresh main and returns J2 (null when the session did not start).
func _start_network_session(main: Node) -> CharacterBody2D:
	var menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var net_button: Button = menu.get_node_or_null(NET_COOP_BUTTON) as Button if menu != null else null
	if net_button != null:
		net_button.pressed.emit()
	return main.get("_player_two") as CharacterBody2D


func _close_session(main: Node, peer: MultiplayerPeer) -> void:
	root.multiplayer.multiplayer_peer = null
	peer.close()
	_free_main(main)


func _new_main() -> Node:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	return main


func _free_main(main: Node) -> void:
	root.remove_child(main)
	main.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		_failures += 1
		push_error("✗ %s" % message)
