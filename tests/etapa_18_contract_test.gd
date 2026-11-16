# etapa_18_contract_test.gd
# Contract test harness for Etapa 18: selección de dificultad.
# Verifies the difficulty table used by the main-menu selector:
# 1. Three tiers exist: CADET, COMMANDER, ELITE.
# 2. Each tier exposes the agreed multipliers:
#    - speed:   CADET 0.85, COMMANDER 1.00, ELITE 1.20 (global formation speed)
#    - density: CADET -1, COMMANDER 0, ELITE +1 (extra formation columns)
#    - cooling: CADET 1.25, COMMANDER 1.00, ELITE 0.80 (weapon cooling rate)
#    - score:   CADET 0.75, COMMANDER 1.00, ELITE 1.50 (final score multiplier)
# 3. Main-menu selector: DificultadButton cycles CADET -> COMMANDER -> ELITE -> CADET,
#    shows the current tier name and play_requested carries the selected tier.
# 4. Enemy destruction feedback: HullFragment configures lifetime from velocity/lifetime/color,
#    and VisualFeedback.play_hull_fragments spawns the requested fragments in its effects layer.
# 5. Post-session stats: accuracy helper (pure math) and the game-over StatsLabel
#    that lists accuracy and kills per enemy type.
# 6. Shot accuracy counter: SessionStats holds shots and hits (register_shot,
#    register_hit, reset) and get_accuracy() derives the percentage from them.
# Contracts 1 and 2 are pure data through DS; contract 3 instantiates the menu scene;
# contract 4 instantiates the fragment script and the visual feedback scene;
# contract 5 uses the static stats helper and instantiates the game-over scene;
# contract 6 is pure static state (no scene instancing).

extends SceneTree

const DS := preload("res://core/settings/difficulty_settings.gd")
const SESSION_STATS := preload("res://core/session/session_stats.gd")
const GAME_OVER_SCENE := preload("res://scenes/ui/game_over.tscn")
const SPAWNER_SCENE := preload("res://scenes/systems/enemy_spawner.tscn")
const PLAYER_SCENE := preload("res://scenes/entities/player/player.tscn")
const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const HULL_FRAGMENT_SCRIPT := preload("res://features/effects/hull_fragment.gd")
const VISUAL_FEEDBACK_SCENE := preload("res://features/effects/visual_feedback.tscn")
const FLOAT_TOLERANCE := 0.0001
const SPEED_TOLERANCE := 0.001


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 18 ---")
	var t1: bool = _assert_tier_table_contract()
	var t2: bool = _assert_session_difficulty_contract()
	var t3: bool = _assert_menu_difficulty_selector_contract()
	var t4: bool = _assert_hull_fragment_feedback_contract()
	var t5: bool = _assert_session_stats_contract()
	var t6: bool = _assert_shot_accuracy_counter_contract()

	var all_passed: bool = t1 and t2 and t3 and t4 and t5 and t6

	if all_passed:
		print("ETAPA 18 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 18 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Difficulty table: tiers and multipliers
# ---------------------------------------------------------------------------
func _assert_tier_table_contract() -> bool:
	var cases: Array[Dictionary] = [
		{"tier": DS.Tier.CADET, "name": "Cadete", "speed": 0.85, "density": -1, "cooling": 1.25, "score": 0.75},
		{"tier": DS.Tier.COMMANDER, "name": "Comandante", "speed": 1.0, "density": 0, "cooling": 1.0, "score": 1.0},
		{"tier": DS.Tier.ELITE, "name": "Élite Galáctica", "speed": 1.2, "density": 1, "cooling": 0.8, "score": 1.5},
	]

	if DS.Tier.size() != cases.size():
		push_error("expected %d tiers, got %d" % [cases.size(), DS.Tier.size()])
		return false

	for c: Dictionary in cases:
		var tier: int = c["tier"]
		if DS.get_tier_name(tier) != c["name"]:
			push_error("tier %d name must be %s, got %s" % [tier, c["name"], DS.get_tier_name(tier)])
			return false
		if absf(DS.speed_multiplier(tier) - c["speed"]) > FLOAT_TOLERANCE:
			push_error("%s speed multiplier must be %.2f" % [c["name"], c["speed"]])
			return false
		if DS.density_offset(tier) != c["density"]:
			push_error("%s density offset must be %d" % [c["name"], c["density"]])
			return false
		if absf(DS.cooling_multiplier(tier) - c["cooling"]) > FLOAT_TOLERANCE:
			push_error("%s cooling multiplier must be %.2f" % [c["name"], c["cooling"]])
			return false
		if absf(DS.score_multiplier(tier) - c["score"]) > FLOAT_TOLERANCE:
			push_error("%s score multiplier must be %.2f" % [c["name"], c["score"]])
			return false

	print("✓ Contrato 1: Tabla de dificultad (3 niveles y multiplicadores) superada")
	return true


# ---------------------------------------------------------------------------
# 2. Session difficulty applied to spawner (speed, density) and player (cooling)
# ---------------------------------------------------------------------------
func _assert_session_difficulty_contract() -> bool:
	var commander_spawner: Node2D = _start_spawner_wave(DS.Tier.COMMANDER)
	var elite_spawner: Node2D = _start_spawner_wave(DS.Tier.ELITE)
	if commander_spawner == null or elite_spawner == null:
		if commander_spawner != null:
			commander_spawner.free()
		if elite_spawner != null:
			elite_spawner.free()
		return false

	var speed_ratio: float = DS.speed_multiplier(DS.Tier.ELITE) / DS.speed_multiplier(DS.Tier.COMMANDER)
	var expected_speed: float = commander_spawner.formation_speed * speed_ratio
	var expected_columns: int = commander_spawner.columns + DS.density_offset(DS.Tier.ELITE) - DS.density_offset(DS.Tier.COMMANDER)
	var spawner_ok: bool = true
	if absf(elite_spawner.formation_speed - expected_speed) > SPEED_TOLERANCE:
		push_error("ELITE formation_speed must be %.3f (COMMANDER %.3f x 1.2), got %.3f" % [expected_speed, commander_spawner.formation_speed, elite_spawner.formation_speed])
		spawner_ok = false
	if elite_spawner.rows != commander_spawner.rows:
		push_error("ELITE rows must equal COMMANDER rows (%d), got %d" % [commander_spawner.rows, elite_spawner.rows])
		spawner_ok = false
	if elite_spawner.columns != expected_columns:
		push_error("ELITE columns must be %d (COMMANDER %d, density +1), got %d" % [expected_columns, commander_spawner.columns, elite_spawner.columns])
		spawner_ok = false

	commander_spawner.free()
	elite_spawner.free()
	if not spawner_ok:
		return false

	var player: CharacterBody2D = PLAYER_SCENE.instantiate() as CharacterBody2D
	if player == null or not ("cooling_scale" in player):
		push_error("player.tscn must expose cooling_scale")
		if player != null:
			player.free()
		return false
	# Shallow check (no tree, no frames simulated): the property is stored and reads back.
	player.set("cooling_scale", DS.cooling_multiplier(DS.Tier.CADET))
	var readback: float = float(player.get("cooling_scale"))
	player.free()
	if absf(readback - 1.25) > FLOAT_TOLERANCE:
		push_error("CADET cooling_scale must read back 1.25, got %.4f" % readback)
		return false

	print("✓ Contrato 2: Dificultad de sesión aplicada a spawner (ELITE) y jugador (CADET cooling)")
	return true


# ---------------------------------------------------------------------------
# 3. Main-menu selector: DificultadButton cycles tiers and feeds play_requested
# ---------------------------------------------------------------------------
func _assert_menu_difficulty_selector_contract() -> bool:
	var menu: CanvasLayer = MENU_SCENE.instantiate() as CanvasLayer
	if menu == null:
		push_error("main_menu.tscn must instantiate as CanvasLayer")
		return false
	get_root().add_child(menu)

	var ok: bool = _check_menu_selector(menu)

	get_root().remove_child(menu)
	menu.free()
	if not ok:
		return false

	print("✓ Contrato 3: Selector de dificultad del menú (ciclo de niveles y play_requested) superado")
	return true


func _check_menu_selector(menu: CanvasLayer) -> bool:
	var button: Button = menu.find_child("DificultadButton", true, false) as Button
	if button == null:
		push_error("main_menu.tscn must contain a Button named DificultadButton")
		return false
	if not ("selected_difficulty" in menu):
		push_error("main_menu must expose selected_difficulty")
		return false
	if int(menu.get("selected_difficulty")) != DS.Tier.COMMANDER:
		push_error("main_menu selected_difficulty must start at COMMANDER")
		return false

	# Full cycle from the default COMMANDER: ELITE, CADET, COMMANDER.
	var expected_cycle: Array[int] = [DS.Tier.ELITE, DS.Tier.CADET, DS.Tier.COMMANDER]
	for expected: int in expected_cycle:
		button.pressed.emit()
		var selected: int = int(menu.get("selected_difficulty"))
		if selected != expected:
			push_error("DificultadButton press must select tier %d, got %d" % [expected, selected])
			return false
		if not button.text.to_upper().contains(DS.get_tier_name(expected).to_upper()):
			push_error("DificultadButton text must contain %s, got '%s'" % [DS.get_tier_name(expected), button.text])
			return false

	# Play must carry the selected tier.
	var emitted: Array[int] = []
	menu.play_requested.connect(func() -> void: emitted.append(int(menu.get("selected_difficulty"))))
	menu.call("_on_play_button_pressed")
	if emitted.size() != 1 or emitted[0] != DS.Tier.COMMANDER:
		push_error("play_requested must emit selected difficulty COMMANDER once")
		return false

	return true


# ---------------------------------------------------------------------------
# 4. Enemy destruction feedback: hull fragments
# ---------------------------------------------------------------------------
func _assert_hull_fragment_feedback_contract() -> bool:
	var fragment: Node2D = HULL_FRAGMENT_SCRIPT.new() as Node2D
	if fragment == null:
		push_error("hull_fragment.gd must instantiate as Node2D")
		return false
	fragment.call("configure", Vector2(100, 0), 0.5, Color.WHITE)
	if not ("lifetime" in fragment):
		push_error("hull_fragment must expose lifetime")
		fragment.free()
		return false
	var fragment_lifetime: float = float(fragment.get("lifetime"))
	fragment.free()
	if absf(fragment_lifetime - 0.5) > FLOAT_TOLERANCE:
		push_error("hull_fragment lifetime must be 0.5 after configure, got %.4f" % fragment_lifetime)
		return false

	var feedback: Node2D = VISUAL_FEEDBACK_SCENE.instantiate() as Node2D
	if feedback == null:
		push_error("visual_feedback.tscn must instantiate as Node2D")
		return false
	get_root().add_child(feedback)
	if not feedback.has_method("play_hull_fragments"):
		push_error("visual_feedback must expose play_hull_fragments")
		get_root().remove_child(feedback)
		feedback.free()
		return false
	feedback.call("play_hull_fragments", Vector2(300, 300), 4)
	var layer: Node = feedback.get_node("ExplosionLayer")
	var fragment_count: int = 0
	for child: Node in layer.get_children():
		if child.get_script() == HULL_FRAGMENT_SCRIPT:
			fragment_count += 1

	get_root().remove_child(feedback)
	feedback.free()
	if fragment_count != 4:
		push_error("play_hull_fragments(pos, 4) must add 4 hull fragments to ExplosionLayer, got %d" % fragment_count)
		return false

	print("✓ Contrato 4: Fragmentos de casco al destruir enemigo (configure y play_hull_fragments) superado")
	return true


# ---------------------------------------------------------------------------
# 5. Post-session stats: accuracy math and game-over stats block
# ---------------------------------------------------------------------------
func _assert_session_stats_contract() -> bool:
	if SESSION_STATS.accuracy_percent(0, 0) != 0.0:
		push_error("accuracy_percent(0 hits, 0 shots) must be 0.0, got %.4f" % SESSION_STATS.accuracy_percent(0, 0))
		return false
	if absf(SESSION_STATS.accuracy_percent(3, 4) - 75.0) > FLOAT_TOLERANCE:
		push_error("accuracy_percent(3 hits, 4 shots) must be 75.0, got %.4f" % SESSION_STATS.accuracy_percent(3, 4))
		return false

	var game_over: CanvasLayer = GAME_OVER_SCENE.instantiate() as CanvasLayer
	if game_over == null:
		push_error("game_over.tscn must instantiate as CanvasLayer")
		return false
	get_root().add_child(game_over)
	game_over.call("show_session_stats", 75.0, {&"standard": 2, &"assault_frigate": 1})
	var kills_grid: GridContainer = game_over.get_node_or_null("Control/Content/StatsCard/StatsMargin/StatsBox/KillsGrid") as GridContainer
	var accuracy_label: Label = game_over.get_node_or_null("Control/Content/StatsCard/StatsMargin/StatsBox/AccuracyLabel") as Label
	var found: bool = kills_grid != null and accuracy_label != null
	var text: String = accuracy_label.text if found else ""
	if found:
		for child: Node in kills_grid.get_children():
			text += " | " + (child as Label).text
	get_root().remove_child(game_over)
	game_over.free()

	if not found:
		push_error("game_over.tscn must contain the stats card with AccuracyLabel and KillsGrid")
		return false
	for expected: String in ["75%", "Caza | 2", "Fragata de asalto | 1", "Interceptor suicida | 0"]:
		if not text.contains(expected):
			push_error("Stats card must contain '%s', got '%s'" % [expected, text])
			return false

	print("✓ Contrato 5: Estadísticas de sesión (precisión y bajas por tipo) superadas")
	return true


# ---------------------------------------------------------------------------
# 6. Shot accuracy counter: SessionStats shots/hits and derived accuracy
# ---------------------------------------------------------------------------
func _assert_shot_accuracy_counter_contract() -> bool:
	SESSION_STATS.reset()
	if SESSION_STATS.get_accuracy() != 0.0:
		push_error("get_accuracy() with no shots must be 0.0, got %.4f" % SESSION_STATS.get_accuracy())
		return false

	for i: int in range(4):
		SESSION_STATS.register_shot()
	for i: int in range(3):
		SESSION_STATS.register_hit()
	if absf(SESSION_STATS.get_accuracy() - 75.0) > FLOAT_TOLERANCE:
		push_error("4 shots and 3 hits must give accuracy 75.0, got %.4f" % SESSION_STATS.get_accuracy())
		SESSION_STATS.reset()
		return false
	if SESSION_STATS.shots != 4 or SESSION_STATS.hits != 3:
		push_error("counters must read shots=4 hits=3, got shots=%d hits=%d" % [SESSION_STATS.shots, SESSION_STATS.hits])
		SESSION_STATS.reset()
		return false

	SESSION_STATS.reset()
	if SESSION_STATS.shots != 0 or SESSION_STATS.hits != 0:
		push_error("reset() must zero shots and hits, got shots=%d hits=%d" % [SESSION_STATS.shots, SESSION_STATS.hits])
		return false
	if SESSION_STATS.get_accuracy() != 0.0:
		push_error("accuracy after reset() must be 0.0, got %.4f" % SESSION_STATS.get_accuracy())
		return false

	print("✓ Contrato 6: Contador de precisión (shots/hits, reset y precisión derivada) superado")
	return true


## Instantiates the spawner, sets the session tier and starts wave 0 at chapter 1.
func _start_spawner_wave(tier: int) -> Node2D:
	var spawner: Node2D = SPAWNER_SCENE.instantiate() as Node2D
	if spawner == null:
		return null
	if not ("session_difficulty" in spawner):
		push_error("enemy_spawner.tscn must expose session_difficulty")
		spawner.free()
		return null
	spawner.set("session_difficulty", tier)
	spawner.difficulty_level = 1
	spawner.start_wave(0)
	return spawner
