# etapa_23_banking_tilt_contract_test.gd
# Contract test for Etapa 23: banking tilt of the player ship (visual only).
# Verifies:
# 1. Moving right tilts the ship clockwise between 15 and 20 degrees once settled.
# 2. Moving left tilts it the opposite way with the same magnitude.
# 3. Standing still returns the tilt to 0.
# 4. The tilt is visual only: the physics body keeps rotation 0 (hitbox does not turn).
# Uses the public Player API only (update_visual_tilt, get_visual_tilt).

extends SceneTree

const PLAYER_SCENE := preload("res://features/player/player.tscn")
const MIN_TILT: float = 0.2617994  # 15 degrees in radians
const MAX_TILT: float = 0.3490659  # 20 degrees in radians
const FRAME: float = 1.0 / 60.0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 23 (BANKING TILT) ---")
	var player: Node = PLAYER_SCENE.instantiate()
	root.add_child(player)
	await process_frame

	var passed: bool = true
	passed = _assert_right_tilt(player) and passed
	passed = _assert_left_tilt(player) and passed
	passed = _assert_returns_to_zero(player) and passed
	passed = _assert_physics_rotation_untouched(player) and passed

	if passed:
		print("ETAPA 23 BANKING TILT CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 23 BANKING TILT CONTRACT TESTS: FAILURES DETECTED")
		print("ETAPA 23 BANKING TILT CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if passed else 1)


func _settle(player: Node, vx: float) -> void:
	player.velocity = Vector2(vx, 0.0)
	for i: int in 120:
		player.update_visual_tilt(FRAME)


# 1. Moving right
func _assert_right_tilt(player: Node) -> bool:
	_settle(player, player.speed)
	var tilt: float = player.get_visual_tilt()
	var ok: bool = tilt >= MIN_TILT and tilt <= MAX_TILT
	if ok:
		print("OK 1: tilt a la derecha dentro de 15 a 20 grados (%.4f rad)" % tilt)
	else:
		push_error("FAIL 1: tilt derecho esperado entre %.4f y %.4f, obtenido %.4f" % [MIN_TILT, MAX_TILT, tilt])
	return ok


# 2. Moving left
func _assert_left_tilt(player: Node) -> bool:
	_settle(player, -player.speed)
	var tilt: float = player.get_visual_tilt()
	var ok: bool = tilt <= -MIN_TILT and tilt >= -MAX_TILT
	if ok:
		print("OK 2: tilt a la izquierda simétrico (%.4f rad)" % tilt)
	else:
		push_error("FAIL 2: tilt izquierdo esperado entre %.4f y %.4f, obtenido %.4f" % [-MAX_TILT, -MIN_TILT, tilt])
	return ok


# 3. Standing still
func _assert_returns_to_zero(player: Node) -> bool:
	_settle(player, 0.0)
	var tilt: float = player.get_visual_tilt()
	var ok: bool = absf(tilt) < 0.001
	if ok:
		print("OK 3: sin movimiento el tilt vuelve a 0")
	else:
		push_error("FAIL 3: tilt sin movimiento debe ser 0, obtenido %.4f" % tilt)
	return ok


# 4. Physics body untouched
func _assert_physics_rotation_untouched(player: Node) -> bool:
	_settle(player, player.speed)
	var ok: bool = is_zero_approx(player.rotation)
	if ok:
		print("OK 4: el cuerpo físico no rota (hitbox intacto)")
	else:
		push_error("FAIL 4: rotation del cuerpo debe ser 0, obtenido %.4f" % player.rotation)
	return ok
