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
	_check_p2_input_actions()
	_check_loot_nearest_ship()
	_check_loot_collector_routing()
	_check_j1_ignores_arrows_in_coop()
	_check_p2_overheat_wiring()
	_check_hud_two_player_layout()
	_check_score_per_player()
	_check_hud_score_p2()
	_check_hud_is_passive()
	_check_hud_p2_matches_p1_style()

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
		_expect(hud.call("is_lives_p2_visible") == true and hud.call("get_lives_p2_text") == "Vidas: 2", "Contrato 5c: J2 muestra \"Vidas: 2\" como J1")
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
# 8. Controles de J2: flechas + Shift, o gamepad (Etapa 20, S3)
# ---------------------------------------------------------------------------
func _check_p2_input_actions() -> void:
	PLAYER_SCRIPT.ensure_p2_input_actions()
	PLAYER_SCRIPT.ensure_p2_input_actions()
	_expect(InputMap.has_action("p2_move_left") and InputMap.has_action("p2_move_right") and InputMap.has_action("p2_shoot"), "Contrato 8a: existen las acciones p2_ de J2")
	_expect(_has_key("p2_move_left", KEY_LEFT), "Contrato 8b: p2_move_left con flecha izquierda")
	_expect(_has_key("p2_move_right", KEY_RIGHT), "Contrato 8c: p2_move_right con flecha derecha")
	_expect(_has_key("p2_shoot", KEY_SHIFT), "Contrato 8d: p2_shoot con Shift")
	_expect(_has_axis("p2_move_left", JOY_AXIS_LEFT_X, -1.0) and _has_axis("p2_move_right", JOY_AXIS_LEFT_X, 1.0), "Contrato 8e: movimiento de J2 con stick izquierdo del gamepad")
	_expect(_has_button("p2_shoot", JOY_BUTTON_A), "Contrato 8f: disparo de J2 con el botón A del gamepad")
	_expect(InputMap.action_get_events("p2_shoot").size() == 2, "Contrato 8g: registrar dos veces no duplica eventos")


func _has_key(action: String, keycode: Key) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).keycode == keycode:
			return true
	return false


func _has_axis(action: String, axis: JoyAxis, value: float) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == axis and signf((ev as InputEventJoypadMotion).axis_value) == signf(value):
			return true
	return false


func _has_button(action: String, button: JoyButton) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


# ---------------------------------------------------------------------------
# 9. Drops: el magnetismo va a la nave visible más cercana (Etapa 20, opción 1)
# ---------------------------------------------------------------------------
func _check_loot_nearest_ship() -> void:
	var loot_script: Script = load("res://scenes/loot/loot_drop.gd")
	_expect(loot_script.has_method("nearest_ship"), "Contrato 9d: LootDrop expone nearest_ship()")
	if not loot_script.has_method("nearest_ship"):
		return
	var near: Node2D = Node2D.new()
	var far: Node2D = Node2D.new()
	get_root().add_child(near)
	get_root().add_child(far)
	near.global_position = Vector2(100.0, 0.0)
	far.global_position = Vector2(500.0, 0.0)
	var origin: Vector2 = Vector2(400.0, 0.0)
	_expect(loot_script.nearest_ship(origin, [near, far]) == far, "Contrato 9a: el drop se engancha a la nave más cercana")
	far.visible = false
	_expect(loot_script.nearest_ship(origin, [near, far]) == near, "Contrato 9b: una nave oculta no atrae drops")
	_expect(loot_script.nearest_ship(origin, []) == null, "Contrato 9c: sin naves visibles no hay objetivo")
	near.queue_free()
	far.queue_free()


# ---------------------------------------------------------------------------
# 10. Recogida: el efecto se aplica a la nave que recogió el drop (Etapa 20)
# ---------------------------------------------------------------------------
func _check_loot_collector_routing() -> void:
	var loot_script: Script = load("res://scenes/loot/loot_drop.gd")
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	main.set("_session_active", true)
	main.call("enable_coop_local")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	main.call("_set_player_two_active", true)
	main.set("lives", 1)
	main.set("_player_two_lives", 1)
	main.call("_on_loot_collected", loot_script.Type.EXTRA_LIFE, p2)
	_expect(main.get("_player_two_lives") == 2, "Contrato 10a: vida extra recogida por J2 suma a J2")
	_expect(main.get("lives") == 1, "Contrato 10b: vida extra recogida por J2 no suma a J1")
	main.call("_on_loot_collected", loot_script.Type.EXTRA_LIFE)
	_expect(main.get("lives") == 2, "Contrato 10c: sin recolector, la vida extra es de J1 (singleplayer)")
	main.queue_free()


# ---------------------------------------------------------------------------
# 11. Flechas: en coop J1 usa solo A/D; singleplayer conserva las flechas
# ---------------------------------------------------------------------------
func _check_j1_ignores_arrows_in_coop() -> void:
	_expect(PLAYER_SCRIPT.ignores_arrow_keys(1, true), "Contrato 11a: en coop J1 ignora las flechas")
	_expect(not PLAYER_SCRIPT.ignores_arrow_keys(1, false), "Contrato 11b: singleplayer conserva las flechas de J1")
	_expect(not PLAYER_SCRIPT.ignores_arrow_keys(2, true), "Contrato 11c: J2 siempre usa sus flechas")


# ---------------------------------------------------------------------------
# 12. Sobrecarga de J2: HUD propio, mismo enfriamiento que J1, reset al cerrar la sesión
# ---------------------------------------------------------------------------
func _check_p2_overheat_wiring() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	main.set("_session_active", true)
	main.call("enable_coop_local")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	var hud: Node = main.get("_hud")
	_expect(hud != null and hud.has_method("set_heat_p2"), "Contrato 12a: HUD tiene barra de calor de J2 (set_heat_p2)")
	if p2 != null:
		main.get("_player").set("cooling_scale", 0.8)
		p2.cooling_scale = 1.0
		main.call("_set_player_two_active", true)
		_expect(p2.cooling_scale == 0.8, "Contrato 12b: J2 usa el mismo enfriamiento que J1 al empezar")
		p2.heat_changed.emit(60.0, 100.0)
		_expect(hud != null and hud.has_method("get_heat_p2_text") and str(hud.call("get_heat_p2_text")).contains("60"), "Contrato 12c: el calor de J2 llega al HUD propio")
		p2.set("heat", 50.0)
		main.call("_set_player_two_active", false)
		_expect(p2.get("heat") == 0.0, "Contrato 12d: al cerrar la sesión se resetea el calor de J2")
	main.queue_free()


# ---------------------------------------------------------------------------
# 13. HUD de dos naves: J1 a la izquierda, J2 a la derecha, sin superponerse
# ---------------------------------------------------------------------------
func _check_hud_two_player_layout() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	var heat_p1: Control = hud.get_node("HeatContainer") as Control
	_expect(heat_p1.anchor_left == 0.0 and heat_p1.anchor_right == 0.0, "Contrato 13a: calor de J1 a la izquierda")
	hud.call("set_lives_p2", 2)
	hud.call("set_heat_p2", 10.0, 100.0, false)
	var panel: Control = hud.get_node_or_null("P2Panel") as Control
	_expect(panel != null and panel.anchor_left == 1.0 and panel.anchor_right == 1.0, "Contrato 13b: panel de J2 a la derecha")
	if panel != null:
		_expect(hud.call("get_lives_p2_parent") == panel and hud.call("get_heat_p2_parent") == panel, "Contrato 13c: vidas y calor de J2 viven en el panel de J2")
		var view_w: float = get_root().get_visible_rect().size.x
		var boss_right: float = view_w * 0.5 + 200.0
		var panel_left: float = view_w - 260.0
		_expect(panel.offset_top == 16.0 and panel_left > boss_right, "Contrato 13d: el panel de J2 sube a la altura de J1 (top 16) sin pisar la barra del jefe (x 340-740)")
		var lives_p2: Label = hud.get("_lives_p2_label") as Label
		_expect(lives_p2 != null and lives_p2.has_theme_font_size_override("font_size") and lives_p2.get_theme_font_size("font_size") == 20, "Contrato 13e: etiqueta de vidas de J2 con override de tamaño 20 (como J1)")
		_expect(lives_p2 != null and lives_p2.has_theme_color_override("font_color"), "Contrato 13f: etiqueta de vidas de J2 con color propio (como J1)")
		hud.call("set_heat_p2", 60.0, 100.0, false)
		var bar_p2: ProgressBar = panel.get_node_or_null("HeatP2Bar") as ProgressBar
		_expect(bar_p2 != null and bar_p2.value == 60.0, "Contrato 13g: J2 tiene barra de calor propia, como J1")
		var bar_p1: ProgressBar = hud.get("_heat_progress_bar") as ProgressBar
		_expect(bar_p2 != null and bar_p1 != null and bar_p2.get_theme_stylebox("background") == bar_p1.get_theme_stylebox("background") and bar_p2.get_theme_stylebox("fill") == bar_p1.get_theme_stylebox("fill"), "Contrato 13j: la barra de J2 usa el mismo estilo que la de J1")
		var heat_p2: Label = hud.get("_heat_p2_label") as Label
		_expect(heat_p2 != null and heat_p2.get_theme_font_size("font_size") == 12, "Contrato 13i: etiqueta de calor de J2 con tamaño 12 (como J1)")
	var heat_container: Control = hud.get_node("HeatContainer") as Control
	_expect(heat_container.offset_top >= 140.0, "Contrato 13h: el calor de J1 queda debajo de la línea de ARMA (no se pisan)")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 14. Score por jugador (Etapa 20, decisión: "Score por jugador")
# ---------------------------------------------------------------------------
func _check_score_per_player() -> void:
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	main.set("_session_active", true)
	main.call("enable_coop_local")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	main.set("score", 0)
	main.set("score_p2", 0)
	_expect(main.get("score_p2") != null and main.has_method("_ship_for"), "Contrato 14d: main expone score_p2 y _ship_for()")
	if main.get("score_p2") == null or not main.has_method("_ship_for"):
		main.queue_free()
		return
	main.call("_add_score", 100, p2)
	_expect(main.get("score_p2") == 100 and main.get("score") == 0, "Contrato 14a: puntos de J2 suman a J2, no a J1")
	main.call("_add_score", 50)
	_expect(main.get("score") == 50, "Contrato 14b: sin nave indicada, los puntos son de J1")
	_expect(main.call("_ship_for", p2) == p2 and main.call("_ship_for", null) == main.get("_player"), "Contrato 14c: _ship_for resuelve la nave del atacante")
	main.queue_free()


# ---------------------------------------------------------------------------
# 15. HUD: score de J2 en su panel, con el mismo estilo que las vidas de J2
# ---------------------------------------------------------------------------
func _check_hud_score_p2() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	_expect(hud.has_method("set_score_p2"), "Contrato 15a: HUD expone set_score_p2()")
	if hud.has_method("set_score_p2"):
		hud.call("set_score_p2", 300)
		var label: Label = hud.get("_score_p2_label") as Label
		_expect(label != null and label.text == "Score: 300", "Contrato 15b: J2 muestra \"Score: 300\" como J1")
		_expect(label != null and label.get_parent() == hud.get("_p2_panel"), "Contrato 15c: score de J2 vive en el panel de J2")
		_expect(label != null and label.has_theme_font_size_override("font_size") and label.get_theme_font_size("font_size") == 20, "Contrato 15d: score de J2 con tamaño 20 (como J1)")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 16. HUD pasivo: los wrappers no capturan el mouse (skill scenario-godot-ui, regla 7)
# ---------------------------------------------------------------------------
func _check_hud_is_passive() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_lives_p2", 2)
	var wrappers: Array[String] = ["BossContainer", "Margin", "HeatContainer", "ComboContainer", "P2Panel"]
	for path: String in wrappers:
		var node: Control = hud.get_node_or_null(path) as Control
		_expect(node != null and node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Contrato 16: %s no captura el mouse" % path)
	hud.queue_free()


# ---------------------------------------------------------------------------
# 17. Estilo: las etiquetas de J2 usan los mismos colores que las de J1
# ---------------------------------------------------------------------------
func _check_hud_p2_matches_p1_style() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_lives_p2", 2)
	hud.call("set_score_p2", 10)
	hud.call("set_heat_p2", 10.0, 100.0, false)
	var lives_p1: Label = hud.get_node("Margin/LivesLabel") as Label
	var score_p1: Label = hud.get_node("Margin/ScoreLabel") as Label
	var lives_p2: Label = hud.get("_lives_p2_label") as Label
	var score_p2: Label = hud.get("_score_p2_label") as Label
	_expect(lives_p2 != null and lives_p2.get_theme_color("font_color") == lives_p1.get_theme_color("font_color"), "Contrato 17a: color de vidas de J2 igual al de J1")
	_expect(score_p2 != null and score_p2.get_theme_color("font_color") == score_p1.get_theme_color("font_color"), "Contrato 17b: color de score de J2 igual al de J1")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 2. J2 uses its own action names
# ---------------------------------------------------------------------------
func _check_player_two_uses_own_actions() -> void:
	_expect(PLAYER_SCRIPT.input_action_name("move_left", 2) == "p2_move_left", "Contrato 2a: J2 usa p2_move_left")
	_expect(PLAYER_SCRIPT.input_action_name("move_right", 2) == "p2_move_right", "Contrato 2b: J2 usa p2_move_right")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) == "p2_shoot", "Contrato 2c: J2 usa p2_shoot")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) != PLAYER_SCRIPT.input_action_name("shoot", 1), "Contrato 2d: J2 nunca comparte acción con J1")
