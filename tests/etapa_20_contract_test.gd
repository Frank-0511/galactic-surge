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
	_check_hull_colors_per_player()
	_check_second_ship_lives()
	_check_hud_lives_p2()
	_check_coop_menu_button()
	_check_menu_does_not_cover_high_score()

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
# 3. Hull outline color: J1 Azul Neón, J2 Naranja Neón (Etapa 20, S2)
# ---------------------------------------------------------------------------
func _check_hull_colors_per_player() -> void:
	var p1: Color = PLAYER_SCRIPT.hull_outline_color(1)
	var p2: Color = PLAYER_SCRIPT.hull_outline_color(2)
	_expect(p1.b > p1.r and p1.b > 0.9, "Contrato 3a: J1 contorno azul neón")
	_expect(p2.r > 0.9 and p2.g > 0.4 and p2.g < 0.7 and p2.b < 0.3, "Contrato 3b: J2 contorno naranja neón")
	_expect(p1 != p2, "Contrato 3c: J1 y J2 tienen colores distintos")


# ---------------------------------------------------------------------------
# 4. Vidas por nave (Etapa 20, decisión: "Vidas por nave")
# ---------------------------------------------------------------------------
func _check_second_ship_lives() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	main.set("_session_active", true)

	var starting: int = main.get("lives") as int
	var stranger: Node2D = Node2D.new()
	main.call("_request_player_damage", stranger)
	_expect(main.get("lives") == starting, "Contrato 4a: singleplayer ignora daño de una nave que no es J1")

	_expect(main.has_method("enable_coop_local"), "Contrato 4b0: main expone enable_coop_local()")
	if main.has_method("enable_coop_local"):
		main.call("enable_coop_local")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	_expect(p2 != null and p2.player_index == 2, "Contrato 4b: coop local crea J2 con player_index 2")
	if p2 != null:
		_expect(not p2.visible, "Contrato 4b1: J2 oculta hasta empezar la sesión coop")
	if p2 == null:
		_failures += 1
		main.queue_free()
		return

	main.call("_set_player_two_active", true)
	# Activation respawns J2 with invulnerability, as J1 has at session start; clear it to test damage.
	p2.set("_is_invulnerable", false)
	main.call("_request_player_damage", p2)
	_expect(main.get("_player_two_lives") == starting - 1, "Contrato 4c: daño a J2 le resta una vida a J2")
	_expect(main.get("lives") == starting, "Contrato 4d: daño a J2 no toca las vidas de J1")
	main.queue_free()


# ---------------------------------------------------------------------------
# 5. HUD: indicador de vidas de J2, oculto en singleplayer
# ---------------------------------------------------------------------------
func _check_hud_lives_p2() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	_expect(hud.has_method("set_lives_p2"), "Contrato 5a: HUD expone set_lives_p2()")
	_expect(not hud.call("is_lives_p2_visible") if hud.has_method("is_lives_p2_visible") else false, "Contrato 5b: indicador de J2 oculto en singleplayer")
	if hud.has_method("set_lives_p2"):
		hud.call("set_lives_p2", 2)
		_expect(hud.call("is_lives_p2_visible") == true and hud.call("get_lives_p2_text") == "Vidas J2: 2", "Contrato 5c: J2 muestra \"Vidas J2: 2\" al activarse")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 6. Menú: botón "Coop local" entre Jugar y Dificultad (Etapa 20, T3)
# ---------------------------------------------------------------------------
func _check_coop_menu_button() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	var coop: Button = menu.get_node_or_null("Control/Menu/CoopButton") as Button
	_expect(coop != null and coop.text == "Coop local", "Contrato 6a: menú tiene botón \"Coop local\"")
	if coop != null:
		var play_idx: int = (menu.get_node("Control/Menu/PlayButton") as Control).get_index()
		var dif_idx: int = (menu.get_node("Control/Menu/DificultadButton") as Control).get_index()
		_expect(coop.get_index() > play_idx and coop.get_index() < dif_idx, "Contrato 6b: Coop local entre Jugar y Dificultad")
	menu.free()


# ---------------------------------------------------------------------------
# 7. Menú principal: el menú no tapa "Mejor puntaje" (crece solo hacia abajo y su alto cubre el contenido)
# ---------------------------------------------------------------------------
func _check_menu_does_not_cover_high_score() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	var box: Control = menu.get_node("Control/Menu") as Control
	_expect(box.grow_vertical == Control.GROW_DIRECTION_END, "Contrato 7a: el menú crece solo hacia abajo (no tapa el puntaje)")
	var height: float = box.offset_bottom - box.offset_top
	_expect(height >= box.get_combined_minimum_size().y, "Contrato 7b: el alto del menú cubre su contenido mínimo")
	menu.free()


# ---------------------------------------------------------------------------
# 2. J2 uses its own action names
# ---------------------------------------------------------------------------
func _check_player_two_uses_own_actions() -> void:
	_expect(PLAYER_SCRIPT.input_action_name("move_left", 2) == "p2_move_left", "Contrato 2a: J2 usa p2_move_left")
	_expect(PLAYER_SCRIPT.input_action_name("move_right", 2) == "p2_move_right", "Contrato 2b: J2 usa p2_move_right")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) == "p2_shoot", "Contrato 2c: J2 usa p2_shoot")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) != PLAYER_SCRIPT.input_action_name("shoot", 1), "Contrato 2d: J2 nunca comparte acción con J1")
