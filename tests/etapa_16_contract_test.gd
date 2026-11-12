# etapa_16_contract_test.gd
# Contract test harness for Etapa 16: duración de la oleada del cinturón de asteroides.
# Verifies:
# 1. AsteroidSpawner scene instantiates and exposes spawn_interval == 2.25 s (tolerance 0.001).
# 2. wave_asteroid_count * spawn_interval == 18.0 s (tolerance 0.01), i.e. +50% over the previous 12 s.
# No real-time dependencies: values are read from the instantiated scene only.

extends SceneTree

const ASTEROID_SPAWNER_PATH := "res://scenes/systems/asteroid_spawner.tscn"
const EXPECTED_SPAWN_INTERVAL := 2.25
const EXPECTED_WAVE_DURATION := 18.0
const SPAWN_INTERVAL_TOLERANCE := 0.001
const WAVE_DURATION_TOLERANCE := 0.01


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 16 ---")
	var t1: bool = _assert_wave_duration_contract()

	var all_passed: bool = t1

	if all_passed:
		print("ETAPA 16 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 16 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Wave duration: spawn_interval * wave_asteroid_count == 18 s (+50%)
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

	print("✓ Contrato 1: Duración de oleada del cinturón (18 s, +50%) superado")
	return true
