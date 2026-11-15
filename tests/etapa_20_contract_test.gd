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
	_check_hud_p2_lives_bottom_right()
	_check_hud_p1_lives_bottom_left()
	_check_hud_weapon_level_bottom()
	_check_hud_p1_score_heat_top_left()
	_check_boss_bar_center_free()
	_check_kill_attribution()
	_check_bullet_propagates_shooter()
	_check_missile_propagates_shooter()
	_check_laser_declares_shooter()
	_check_legacy_bullet_kill_attribution()
	_check_hud_icons_and_wave_out()
	_check_eliminated_ship_stays_hidden()
	_check_weapon_icon_by_type()
	_check_active_weapon_text_hidden()
	_check_p2_panels_follow_session()
	_check_weapon_icon_is_drop_medallion()
	_check_weapon_icon_size()
	_check_camera_follow_pick()

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
		_expect(hud.call("is_lives_p2_visible") == true and hud.call("get_lives_p2_text") == "♥ 2", "Contrato 5c: J2 muestra \"♥ 2\" como J1")
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
	var heat_p1: Control = hud.get("_heat_container") as Control
	_expect(heat_p1.anchor_left == 0.0 and heat_p1.anchor_right == 0.0, "Contrato 13a: calor de J1 a la izquierda")
	hud.call("set_lives_p2", 2)
	hud.call("set_heat_p2", 10.0, 100.0, false)
	var panel: Control = hud.get_node_or_null("P2Panel") as Control
	_expect(panel != null and panel.anchor_left == 1.0 and panel.anchor_right == 1.0, "Contrato 13b: panel de J2 a la derecha")
	if panel != null:
		_expect(hud.call("get_heat_p2_parent") == panel and hud.call("get_lives_p2_parent") == hud.get_node_or_null("P2BottomPanel"), "Contrato 13c: calor de J2 arriba en su panel, vidas de J2 abajo (spec S7-S8)")
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
	var heat_container: Control = hud.get("_heat_container") as Control
	_expect(heat_container.get_parent() == hud.get_node_or_null("P1TopPanel"), "Contrato 13h: el calor de J1 vive en el panel superior izquierdo (spec S8)")
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
	hud.call("set_score_p2", 0)
	var wrappers: Array[String] = ["BossContainer", "Margin", "ComboContainer", "P2Panel", "P2BottomPanel", "P1TopPanel", "P1BottomPanel"]
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
	var lives_p1: Label = hud.get("_lives_label") as Label
	var score_p1: Label = hud.get("_score_label") as Label
	var lives_p2: Label = hud.get("_lives_p2_label") as Label
	var score_p2: Label = hud.get("_score_p2_label") as Label
	_expect(lives_p2 != null and lives_p2.get_theme_color("font_color") == lives_p1.get_theme_color("font_color"), "Contrato 17a: color de vidas de J2 igual al de J1")
	_expect(score_p2 != null and score_p2.get_theme_color("font_color") == score_p1.get_theme_color("font_color"), "Contrato 17b: color de score de J2 igual al de J1")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 18. HUD (spec S7): vidas de J2 abajo a la derecha
# ---------------------------------------------------------------------------
func _check_hud_p2_lives_bottom_right() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_lives_p2", 2)
	var lives_p2: Label = hud.get("_lives_p2_label") as Label
	var bottom: Control = hud.get_node_or_null("P2BottomPanel") as Control
	_expect(bottom != null and bottom.anchor_top == 1.0 and bottom.anchor_right == 1.0, "Contrato 18a: panel inferior de J2 anclado abajo a la derecha")
	_expect(lives_p2 != null and bottom != null and lives_p2.get_parent() == bottom, "Contrato 18b: vidas de J2 viven en el panel inferior")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 19. HUD (spec S7): vidas de J1 abajo a la izquierda
# ---------------------------------------------------------------------------
func _check_hud_p1_lives_bottom_left() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	var lives_p1: Label = hud.get("_lives_label") as Label
	var bottom: Control = hud.get_node_or_null("P1BottomPanel") as Control
	_expect(bottom != null and bottom.anchor_top == 1.0 and bottom.anchor_left == 0.0, "Contrato 19a: panel inferior de J1 anclado abajo a la izquierda")
	_expect(lives_p1 != null and bottom != null and lives_p1.get_parent() == bottom, "Contrato 19b: vidas de J1 viven en el panel inferior izquierdo")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 20. HUD (spec S7): nivel del arma abajo en la esquina de cada jugador
# ---------------------------------------------------------------------------
func _check_hud_weapon_level_bottom() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_weapon_level", 3, 0)
	_expect(hud.has_method("set_weapon_level_p2"), "Contrato 20c: HUD expone set_weapon_level_p2()")
	if not hud.has_method("set_weapon_level_p2"):
		hud.queue_free()
		return
	hud.call("set_weapon_level_p2", 2)
	var bottom_p1: Control = hud.get_node_or_null("P1BottomPanel") as Control
	var bottom_p2: Control = hud.get_node_or_null("P2BottomPanel") as Control
	var level_p1: Label = hud.get("_weapon_level_label") as Label
	var level_p2: Label = hud.get("_weapon_level_p2_label") as Label
	_expect(level_p1 != null and bottom_p1 != null and level_p1.get_parent().get_parent() == bottom_p1 and level_p1.text == "3", "Contrato 20a: nivel del arma de J1 abajo a la izquierda (\"3\")")
	_expect(level_p2 != null and bottom_p2 != null and level_p2.get_parent().get_parent() == bottom_p2 and level_p2.text == "2", "Contrato 20b: nivel del arma de J2 abajo a la derecha (\"2\")")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 21. HUD (spec S8): score y calor de J1 arriba a la izquierda
# ---------------------------------------------------------------------------
func _check_hud_p1_score_heat_top_left() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	var top: Control = hud.get_node_or_null("P1TopPanel") as Control
	var score_p1: Label = hud.get("_score_label") as Label
	var heat_p1: Control = hud.get("_heat_container") as Control
	_expect(top != null and top.anchor_left == 0.0 and top.anchor_top == 0.0, "Contrato 21a: panel superior de J1 anclado arriba a la izquierda")
	_expect(score_p1 != null and top != null and score_p1.get_parent() == top, "Contrato 21b: score de J1 en el panel superior izquierdo")
	_expect(heat_p1 != null and top != null and heat_p1.get_parent() == top, "Contrato 21c: calor de J1 en el panel superior izquierdo")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 22. HUD (spec S9): la barra del jefe queda centrada y ningún panel la pisa
# ---------------------------------------------------------------------------
func _check_boss_bar_center_free() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_lives_p2", 2)
	hud.call("set_score_p2", 0)
	var w: float = get_root().get_visible_rect().size.x
	var boss_left: float = w * 0.5 - 200.0
	var boss_right: float = w * 0.5 + 200.0
	var top_p1: Control = hud.get_node_or_null("P1TopPanel") as Control
	var panel_p2: Control = hud.get_node_or_null("P2Panel") as Control
	var boss: Control = hud.get_node_or_null("BossContainer") as Control
	_expect(boss != null and boss.anchor_left == 0.5 and boss.anchor_right == 0.5, "Contrato 22a: barra del jefe centrada")
	_expect(top_p1 != null and top_p1.offset_right <= boss_left, "Contrato 22b: panel de J1 no pisa la barra del jefe")
	_expect(panel_p2 != null and w + panel_p2.offset_left >= boss_right, "Contrato 22c: panel de J2 no pisa la barra del jefe")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 23. Kills: el score de un enemigo destruido va a la nave que lo atacó (feature L13)
# ---------------------------------------------------------------------------
func _check_kill_attribution() -> void:
	var enemy_packed: PackedScene = load("res://scenes/entities/enemy/enemy.tscn") as PackedScene
	var enemy: Node = enemy_packed.instantiate()
	_expect("last_attacker" in enemy, "Contrato 23a: el enemigo registra su último atacante (last_attacker)")
	if not ("last_attacker" in enemy):
		enemy.free()
		return
	var packed: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	var main: Node = packed.instantiate()
	get_root().add_child(main)
	main.set("_session_active", true)
	main.call("enable_coop_local")
	var p2: CharacterBody2D = main.get("_player_two") as CharacterBody2D
	main.set("score", 0)
	main.set("score_p2", 0)
	get_root().add_child(enemy)
	enemy.set("last_attacker", p2)
	main.call("_on_enemy_destroyed", enemy)
	_expect(main.get("score_p2") > 0 and main.get("score") == 0, "Contrato 23b: kill de J2 suma a J2, no a J1")
	main.queue_free()


# ---------------------------------------------------------------------------
# 24. Balas: el impacto marca al enemigo con la nave que disparó (feature L13)
# ---------------------------------------------------------------------------
func _check_bullet_propagates_shooter() -> void:
	var bullet_packed: PackedScene = load("res://scenes/entities/bullet/spread_bullet.tscn") as PackedScene
	var bullet: Node = bullet_packed.instantiate()
	var enemy: Node = (load("res://scenes/entities/enemy/enemy.tscn") as PackedScene).instantiate()
	var shooter: Node2D = Node2D.new()
	get_root().add_child(enemy)
	get_root().add_child(shooter)
	enemy.add_to_group("enemies")
	_expect("shooter" in bullet, "Contrato 24a: las balas declaran su nave (shooter)")
	if not ("shooter" in bullet):
		bullet.free()
		enemy.queue_free()
		shooter.queue_free()
		return
	bullet.set("shooter", shooter)
	bullet.call("_on_area_entered", enemy)
	_expect(enemy.get("last_attacker") == shooter, "Contrato 24b: el impacto deja al enemigo marcado con la nave que disparó")
	bullet.free()
	enemy.queue_free()
	shooter.queue_free()


# ---------------------------------------------------------------------------
# 25. Misiles: el impacto marca al enemigo con la nave que disparó
# ---------------------------------------------------------------------------
func _check_missile_propagates_shooter() -> void:
	var missile_packed: PackedScene = load("res://scenes/entities/bullet/missile.tscn") as PackedScene
	var missile: Node = missile_packed.instantiate()
	var enemy: Node = (load("res://scenes/entities/enemy/enemy.tscn") as PackedScene).instantiate()
	var shooter: Node2D = Node2D.new()
	get_root().add_child(enemy)
	get_root().add_child(shooter)
	enemy.add_to_group("enemies")
	_expect("shooter" in missile, "Contrato 25a: los misiles declaran su nave (shooter)")
	if not ("shooter" in missile):
		missile.free()
		enemy.queue_free()
		shooter.queue_free()
		return
	missile.set("shooter", shooter)
	missile.call("_on_area_entered", enemy)
	_expect(enemy.get("last_attacker") == shooter, "Contrato 25b: el misil marca al enemigo con su nave")
	missile.free()
	enemy.queue_free()
	shooter.queue_free()


# ---------------------------------------------------------------------------
# 26. Láser: el haz declara su nave y el daño marca al objetivo (feature L13)
# ---------------------------------------------------------------------------
func _check_laser_declares_shooter() -> void:
	var beam: Node = (load("res://scenes/entities/bullet/laser_beam.tscn") as PackedScene).instantiate()
	_expect("shooter" in beam, "Contrato 26a: el láser declara su nave (shooter)")
	beam.free()


# ---------------------------------------------------------------------------
# 27. Blaster base (bala legacy): el impacto marca al enemigo con la nave que disparó
# ---------------------------------------------------------------------------
func _check_legacy_bullet_kill_attribution() -> void:
	var bullet: Area2D = (load("res://scenes/entities/bullet/bullet.tscn") as PackedScene).instantiate() as Area2D
	var enemy: Node = (load("res://scenes/entities/enemy/enemy.tscn") as PackedScene).instantiate()
	var shooter: Node2D = Node2D.new()
	get_root().add_child(enemy)
	get_root().add_child(shooter)
	bullet.collision_layer = 2
	_expect("shooter" in bullet, "Contrato 27a: la bala legacy declara su nave (shooter)")
	if not ("shooter" in bullet):
		bullet.free()
		enemy.queue_free()
		shooter.queue_free()
		return
	bullet.set("shooter", shooter)
	enemy.call("_on_area_entered", bullet)
	_expect(enemy.get("last_attacker") == shooter, "Contrato 27b: el impacto del blaster base marca al enemigo con su nave")
	bullet.free()
	enemy.queue_free()
	shooter.queue_free()


# ---------------------------------------------------------------------------
# 28. HUD: iconos para vidas y arma, y la oleada sale del HUD (la muestra el anuncio)
# ---------------------------------------------------------------------------
func _check_hud_icons_and_wave_out() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_lives", 3)
	_expect(hud.get("_lives_label").text == "♥ 3", "Contrato 28a: vidas de J1 con icono \"♥ 3\"")
	hud.call("set_lives_p2", 2)
	_expect(hud.call("get_lives_p2_text") == "♥ 2", "Contrato 28b: vidas de J2 con icono \"♥ 2\"")
	hud.call("set_weapon_level", 3, 0)
	_expect(hud.get("_weapon_level_label").text == "3", "Contrato 28c: nivel del arma de J1 como numero")
	hud.call("set_weapon_level_p2", 2)
	_expect(hud.get("_weapon_level_p2_label").text == "2", "Contrato 28d: nivel del arma de J2 como numero")
	hud.call("set_wave", 4)
	_expect(not hud.get("_wave_label").visible, "Contrato 28e: la oleada no se muestra en el HUD (la muestra el anuncio)")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 29. Nave eliminada: un timer de invulnerabilidad no la hace visible (bug: J1 sin vidas reaparecia)
# ---------------------------------------------------------------------------
func _check_eliminated_ship_stays_hidden() -> void:
	var ship: CharacterBody2D = (load("res://scenes/entities/player/player.tscn") as PackedScene).instantiate() as CharacterBody2D
	get_root().add_child(ship)
	ship.set_gameplay_enabled(false)
	ship.visible = false
	ship.grant_invulnerability(0.1)
	ship.call("_on_invulnerability_timer_timeout")
	_expect(not ship.visible, "Contrato 29a: una nave eliminada no vuelve a verse cuando vence su invulnerabilidad")
	ship.call("_on_blink_timer_timeout")
	_expect(not ship.visible, "Contrato 29b: el parpadeo no muestra una nave eliminada")
	ship.queue_free()


# ---------------------------------------------------------------------------
# 30. Icono del arma: cambia segun el tipo de arma (0 blaster, 1 misil, 2 laser)
# ---------------------------------------------------------------------------
func _check_weapon_icon_by_type() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_weapon_level", 3, 1)
	_expect(hud.get("_weapon_icon").get("weapon_type") == 1, "Contrato 30a: arma misil de J1 con medallon de misil")
	hud.call("set_weapon_level", 2, 2)
	_expect(hud.get("_weapon_icon").get("weapon_type") == 2, "Contrato 30b: arma laser de J1 con medallon de laser")
	hud.call("set_weapon_level_p2", 2, 1)
	_expect(hud.get("_weapon_icon_p2").get("weapon_type") == 1, "Contrato 30c: arma misil de J2 con medallon de misil")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 31. HUD: la linea "ARMA: ..." no se muestra; el icono del arma la reemplaza
# ---------------------------------------------------------------------------
func _check_active_weapon_text_hidden() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_active_weapon", 2)
	var label: Label = hud.get("_active_weapon_label") as Label
	_expect(label != null and not label.visible, "Contrato 31a: la linea \"ARMA: ...\" queda oculta (el icono la reemplaza)")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 32. HUD: los paneles de J2 se ocultan fuera de la sesion coop (bug: quedaban visibles en singleplayer)
# ---------------------------------------------------------------------------
func _check_p2_panels_follow_session() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_score_p2", 500)
	hud.call("set_lives_p2", 2)
	var panel: Control = hud.get_node_or_null("P2Panel") as Control
	var bottom: Control = hud.get_node_or_null("P2BottomPanel") as Control
	_expect(hud.has_method("set_p2_visible"), "Contrato 32a: HUD expone set_p2_visible()")
	if hud.has_method("set_p2_visible") and panel != null and bottom != null:
		hud.call("set_p2_visible", false)
		_expect(not panel.visible and not bottom.visible, "Contrato 32b: fuera de coop los paneles de J2 no se ven")
		hud.call("set_p2_visible", true)
		_expect(panel.visible and bottom.visible, "Contrato 32c: en coop los paneles de J2 se ven")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 33. Icono del arma: el mismo dibujo del medallon que cae (LootDrop.paint_medallion)
# ---------------------------------------------------------------------------
func _check_weapon_icon_is_drop_medallion() -> void:
	var loot_script: Script = load("res://scenes/loot/loot_drop.gd")
	_expect(loot_script.has_method("paint_medallion"), "Contrato 33a: LootDrop expone paint_medallion() para reutilizar el dibujo")
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_weapon_level", 3, 1)
	var icon_p1: Control = hud.get("_weapon_icon") as Control
	_expect(icon_p1 != null and icon_p1.get("weapon_type") == 1, "Contrato 33b: el icono de J1 muestra el medallon del arma (misil)")
	hud.call("set_weapon_level_p2", 2, 2)
	var icon_p2: Control = hud.get("_weapon_icon_p2") as Control
	_expect(icon_p2 != null and icon_p2.get("weapon_type") == 2, "Contrato 33c: el icono de J2 muestra el medallon del arma (laser)")
	_expect(hud.get("_weapon_level_label").text == "3", "Contrato 33d: el label del arma muestra solo el nivel")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 34. Icono del arma: tamano acorde al texto del nivel (no mas alto que una linea de 20 px)
# ---------------------------------------------------------------------------
func _check_weapon_icon_size() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	get_root().add_child(hud)
	hud.call("set_weapon_level", 3, 0)
	var icon: Control = hud.get("_weapon_icon") as Control
	_expect(icon != null and icon.custom_minimum_size.y <= 22.0, "Contrato 34a: el icono del arma mide como maximo 22 px (acorde al texto de 20 px)")
	hud.queue_free()


# ---------------------------------------------------------------------------
# 35. Camara del cinturon: sigue a la nave viva; si ambas viven, a la que se mueve de costado
# ---------------------------------------------------------------------------
func _check_camera_follow_pick() -> void:
	var cam_script: Script = load("res://scenes/main/camera_shake.gd")
	_expect(cam_script.has_method("pick_follow_target"), "Contrato 35a: la camara expone pick_follow_target()")
	if not cam_script.has_method("pick_follow_target"):
		return
	var p1: CharacterBody2D = CharacterBody2D.new()
	var p2: CharacterBody2D = CharacterBody2D.new()
	p1.visible = false
	p2.visible = true
	_expect(cam_script.pick_follow_target([p1, p2]) == p2, "Contrato 35b: si J1 muere la camara sigue a J2")
	p1.visible = true
	p1.velocity = Vector2(0.0, 0.0)
	p2.velocity = Vector2(300.0, 0.0)
	_expect(cam_script.pick_follow_target([p1, p2]) == p2, "Contrato 35c: con ambas vivas sigue a la que se mueve de costado")
	p1.velocity = Vector2(-400.0, 0.0)
	_expect(cam_script.pick_follow_target([p1, p2]) == p1, "Contrato 35d: cambia a la otra si esa se mueve mas de costado")
	p1.free()
	p2.free()


# ---------------------------------------------------------------------------
# 2. J2 uses its own action names
# ---------------------------------------------------------------------------
func _check_player_two_uses_own_actions() -> void:
	_expect(PLAYER_SCRIPT.input_action_name("move_left", 2) == "p2_move_left", "Contrato 2a: J2 usa p2_move_left")
	_expect(PLAYER_SCRIPT.input_action_name("move_right", 2) == "p2_move_right", "Contrato 2b: J2 usa p2_move_right")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) == "p2_shoot", "Contrato 2c: J2 usa p2_shoot")
	_expect(PLAYER_SCRIPT.input_action_name("shoot", 2) != PLAYER_SCRIPT.input_action_name("shoot", 1), "Contrato 2d: J2 nunca comparte acción con J1")
