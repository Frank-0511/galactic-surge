# etapa_17_contract_test.gd
# Contract test harness for Etapa 17: formation slots computed with Transform2D.
# Verifies:
# 1. With rotation PI/2, a 1x3 GRID rotates around the formation origin
#    (540,120): slots become (540,48), (540,120), (540,192).
# 2. With rotation 0 (default), slots match the previous origin-based layout
#    (slot 0 of a 1x3 GRID at origin (540,120) with h_spacing 72 is (468,120)).
# No real-time dependencies: pure calculation through FormationPatterns.

extends SceneTree

const ORIGIN := Vector2(540.0, 120.0)
const H_SPACING := 72.0
const V_SPACING := 64.0
const POSITION_TOLERANCE := 0.01


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 17 ---")
	var t1: bool = _assert_rotated_grid_contract()
	var t2: bool = _assert_default_rotation_contract()

	var all_passed: bool = t1 and t2

	if all_passed:
		print("ETAPA 17 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 17 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Rotation PI/2 around origin via Transform2D
# ---------------------------------------------------------------------------
func _assert_rotated_grid_contract() -> bool:
	var slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.GRID, 1, 3, H_SPACING, V_SPACING, ORIGIN, PI / 2.0
	)
	var expected: Array[Vector2] = [
		Vector2(540.0, 48.0),
		Vector2(540.0, 120.0),
		Vector2(540.0, 192.0),
	]
	if slots.size() != expected.size():
		push_error("rotated grid must have %d slots, got %d" % [expected.size(), slots.size()])
		return false
	for i: int in range(expected.size()):
		if slots[i].distance_to(expected[i]) > POSITION_TOLERANCE:
			push_error("rotated slot %d must be %s, got %s" % [i, expected[i], slots[i]])
			return false

	print("✓ Contrato 1: Slots rotados alrededor del origen con Transform2D superado")
	return true


# ---------------------------------------------------------------------------
# 2. Default rotation keeps the previous layout
# ---------------------------------------------------------------------------
func _assert_default_rotation_contract() -> bool:
	var slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.GRID, 1, 3, H_SPACING, V_SPACING, ORIGIN
	)
	if slots.size() != 3:
		push_error("default grid must have 3 slots, got %d" % slots.size())
		return false
	if slots[0].distance_to(Vector2(468.0, 120.0)) > POSITION_TOLERANCE:
		push_error("default slot 0 must be (468,120), got %s" % slots[0])
		return false

	print("✓ Contrato 2: Rotación por defecto mantiene el layout anterior superado")
	return true
