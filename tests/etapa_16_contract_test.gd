# etapa_16_contract_test.gd
# Contract test harness for Etapa 16: duración de la oleada del cinturón de asteroides.
# Verifies:
# 1. AsteroidSpawner scene instantiates and exposes spawn_interval == 2.25 s (tolerance 0.001).
# 2. wave_asteroid_count * spawn_interval == 54.0 s (tolerance 0.01): 24 asteroids at 2.25 s.
# 3. CameraShake follows a target on X during the belt, clamped to a max offset, and
#    returns to its home position when the follow ends. Y is never followed.
# No real-time dependencies: values are read from the instantiated scene and
# _process is driven manually.

extends SceneTree

const ASTEROID_SPAWNER_PATH := "res://scenes/systems/asteroid_spawner.tscn"
const CAMERA_SHAKE_PATH := "res://scenes/main/camera_shake.gd"
const CAMERA_HOME := Vector2(540.0, 480.0)
const CAMERA_MAX_OFFSET := 120.0
const POSITION_TOLERANCE := 0.01
const EXPECTED_SPAWN_INTERVAL := 2.25
const EXPECTED_WAVE_DURATION := 54.0
const SPAWN_INTERVAL_TOLERANCE := 0.001
const WAVE_DURATION_TOLERANCE := 0.01


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 16 ---")
	var t1: bool = _assert_wave_duration_contract()
	var t2: bool = _assert_camera_follow_contract()

	var all_passed: bool = t1 and t2

	if all_passed:
		print("ETAPA 16 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 16 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Wave duration: spawn_interval * wave_asteroid_count == 54 s (24 asteroids)
# ---------------------------------------------------------------------------
func _assert_wave_duration_contract() -> bool:
	if not ResourceLoader.exists(ASTEROID_SPAWNER_PATH):
		push_error("Missing AsteroidSpawner scene: %s" % ASTEROID_SPAWNER_PATH)
		return false

	var packed: PackedScene = load(ASTEROID_SPAWNER_PATH) as PackedScene
	var spawner: Node2D = packed.instantiate() as Node2D
	if spawner == null:
		push_error("AsteroidSpawner scene did not instantiate as Node2D")
		return false

	var spawn_interval: float = float(spawner.get("spawn_interval"))
	var wave_count: int = int(spawner.get("wave_asteroid_count"))
	spawner.free()

	if absf(spawn_interval - EXPECTED_SPAWN_INTERVAL) > SPAWN_INTERVAL_TOLERANCE:
		push_error("spawn_interval must be %.3f, got %.3f" % [EXPECTED_SPAWN_INTERVAL, spawn_interval])
		return false

	var wave_duration: float = float(wave_count) * spawn_interval
	if absf(wave_duration - EXPECTED_WAVE_DURATION) > WAVE_DURATION_TOLERANCE:
		push_error("wave_asteroid_count * spawn_interval must be %.2f, got %.3f" % [EXPECTED_WAVE_DURATION, wave_duration])
		return false

	print("✓ Contrato 1: Duración de oleada del cinturón (54 s, 24 asteroides) superado")
	return true


# ---------------------------------------------------------------------------
# 2. Camera follow: tracks X within the max offset, never Y, returns home
# ---------------------------------------------------------------------------
func _assert_camera_follow_contract() -> bool:
	var script: Script = load(CAMERA_SHAKE_PATH) as Script
	if script == null:
		push_error("Missing CameraShake script: %s" % CAMERA_SHAKE_PATH)
		return false

	var camera: Camera2D = script.new() as Camera2D
	var target: Node2D = Node2D.new()
	camera.position = CAMERA_HOME

	if not camera.has_method(&"begin_follow") or not camera.has_method(&"end_follow"):
		push_error("CameraShake must expose begin_follow() and end_follow()")
		camera.free()
		target.free()
		return false

	camera.call(&"begin_follow", target)

	# Target inside the limit: camera X follows exactly.
	target.position = Vector2(600.0, 700.0)
	camera._process(0.016)
	if absf(camera.position.x - 600.0) > POSITION_TOLERANCE:
		push_error("camera must follow X inside the limit, got %.2f" % camera.position.x)
		return _fail_camera_follow(camera, target)

	# Target beyond the limit: camera X clamps to home +/- max offset.
	target.position = Vector2(1000.0, 864.0)
	camera._process(0.016)
	if absf(camera.position.x - (CAMERA_HOME.x + CAMERA_MAX_OFFSET)) > POSITION_TOLERANCE:
		push_error("camera X must clamp to %.2f, got %.2f" % [CAMERA_HOME.x + CAMERA_MAX_OFFSET, camera.position.x])
		return _fail_camera_follow(camera, target)

	target.position = Vector2(20.0, 864.0)
	camera._process(0.016)
	if absf(camera.position.x - (CAMERA_HOME.x - CAMERA_MAX_OFFSET)) > POSITION_TOLERANCE:
		push_error("camera X must clamp to %.2f, got %.2f" % [CAMERA_HOME.x - CAMERA_MAX_OFFSET, camera.position.x])
		return _fail_camera_follow(camera, target)

	# Y is never followed.
	if absf(camera.position.y - CAMERA_HOME.y) > POSITION_TOLERANCE:
		push_error("camera Y must stay at home %.2f, got %.2f" % [CAMERA_HOME.y, camera.position.y])
		return _fail_camera_follow(camera, target)

	# Ending the follow returns the camera to its home position and stops tracking.
	camera.call(&"end_follow")
	if camera.position.distance_to(CAMERA_HOME) > POSITION_TOLERANCE:
		push_error("camera must return home %s after end_follow, got %s" % [CAMERA_HOME, camera.position])
		return _fail_camera_follow(camera, target)

	target.position = Vector2(900.0, 864.0)
	camera._process(0.016)
	if camera.position.distance_to(CAMERA_HOME) > POSITION_TOLERANCE:
		push_error("camera must not track after end_follow, got %s" % camera.position)
		return _fail_camera_follow(camera, target)

	camera.free()
	target.free()
	print("✓ Contrato 2: Seguimiento de cámara con límite y retorno superado")
	return true


func _fail_camera_follow(camera: Camera2D, target: Node2D) -> bool:
	camera.free()
	target.free()
	return false
