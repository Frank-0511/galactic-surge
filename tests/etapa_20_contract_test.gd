extends SceneTree
# Contract test harness for Etapa 20 (slice 1): cooperativo local 2P.
# Verifies:
# 1. J1 keeps the existing action names (move_left, move_right, shoot), so singleplayer is unchanged.
# 2. J2 uses its own action names (p2_move_left, p2_move_right, p2_shoot), never J1's.
# No real-time dependencies: pure static function on the player script.

const PLAYER_SCRIPT := preload("res://scenes/entities/player/player.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	_check_player_one_keeps_actions()
	_check_player_two_uses_own_actions()

	if _failures == 0:
		print("ETAPA 20 CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ " + message)
	else:
		_failures += 1
		push_error("✗ " + message)


# ---------------------------------------------------------------------------
# 1. J1 keeps the current action names
# ---------------------------------------------------------------------------
func _check_player_one_keeps_actions() -> void:
	_expect(PLAYER_SCRIPT.input_action_name("move_left", 1) == "move_left", "Contrato 1a: J1 mantiene move_left")
	_expect(PLAYER_SCRIPT.input_action_name("move_right", 1) == "move_right", "Contrato 1b: J1 mantiene move_right")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 1) == "shoot", "Contrato 1c: J1 mantiene shoot")


# ---------------------------------------------------------------------------
# 2. J2 uses its own action names
# ---------------------------------------------------------------------------
func _check_player_two_uses_own_actions() -> void:
	_expect(PLAYER_SCRIPT.input_action_name("move_left", 2) == "p2_move_left", "Contrato 2a: J2 usa p2_move_left")
	_expect(PLAYER_SCRIPT.input_action_name("move_right", 2) == "p2_move_right", "Contrato 2b: J2 usa p2_move_right")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) == "p2_shoot", "Contrato 2c: J2 usa p2_shoot")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) != PLAYER_SCRIPT.input_action_name("shoot", 1), "Contrato 2d: J2 nunca comparte acción con J1")
