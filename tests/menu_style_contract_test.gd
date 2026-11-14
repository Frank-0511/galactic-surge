# menu_style_contract_test.gd
# Contract test for the main menu visual upgrade.
# Verifies:
# 1. PlayButton, QuitButton and DificultadButton each define StyleBox overrides for
#    normal, hover, pressed and focus states.
# 2. TitleLabel has an outline size > 0 and a non-zero drop shadow.
# 3. Node names and public texts of the menu still exist (no structural renames).
# Uses the instantiated scene only; no real-time dependencies.

extends SceneTree

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const BUTTON_PATHS: Array[String] = [
	"Control/PlayButton",
	"Control/QuitButton",
	"Control/DificultadButton",
]
const STATES: Array[String] = ["normal", "hover", "pressed", "focus"]
const REQUIRED_NODES: Array[String] = [
	"Control/Panel",
	"Control/KickerLabel",
	"Control/TitleLabel",
	"Control/Divider",
	"Control/DifficultyCaption",
	"Control/DificultadButton",
	"Control/PlayButton",
	"Control/QuitButton",
	"Control/HighScoreLabel",
]


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS MENU STYLE ---")
	var menu: CanvasLayer = MAIN_MENU_SCENE.instantiate() as CanvasLayer
	if menu == null:
		push_error("main_menu.tscn must instantiate as CanvasLayer")
		print("MENU STYLE CONTRACT TESTS: FAILURES DETECTED")
		quit(1)
		return

	root.add_child(menu)
	var t1: bool = _assert_button_stylebox_overrides(menu)
	var t2: bool = _assert_title_outline_and_shadow(menu)
	var t3: bool = _assert_node_names_kept(menu)
	root.remove_child(menu)
	menu.free()

	var all_passed: bool = t1 and t2 and t3
	if all_passed:
		print("MENU STYLE CONTRACT TESTS: ALL PASSED")
	else:
		push_error("MENU STYLE CONTRACT TESTS: FAILURES DETECTED")
		print("MENU STYLE CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Buttons: normal, hover, pressed and focus StyleBox overrides
# ---------------------------------------------------------------------------
func _assert_button_stylebox_overrides(menu: CanvasLayer) -> bool:
	var passed: bool = true
	for path: String in BUTTON_PATHS:
		var button: Button = menu.get_node_or_null(path) as Button
		if button == null:
			push_error("Missing Button at %s" % path)
			passed = false
			continue
		for state: String in STATES:
			if not button.has_theme_stylebox_override(state):
				push_error("%s must override StyleBox '%s'" % [path, state])
				passed = false
	if passed:
		print("✓ Contrato 1: Botones con StyleBox normal, hover, pressed y focus")
	return passed


# ---------------------------------------------------------------------------
# 2. Title: outline and drop shadow
# ---------------------------------------------------------------------------
func _assert_title_outline_and_shadow(menu: CanvasLayer) -> bool:
	var title: Label = menu.get_node_or_null("Control/TitleLabel") as Label
	if title == null:
		push_error("Missing Label Control/TitleLabel")
		return false
	if title.text != "GALACTIC SURGE":
		push_error("TitleLabel text must stay GALACTIC SURGE, got '%s'" % title.text)
		return false
	if title.get_theme_constant("outline_size") <= 0:
		push_error("TitleLabel outline_size must be > 0")
		return false
	# Explicit overrides only: Godot's default Label theme already ships a 1 px shadow.
	var has_explicit_shadow: bool = title.has_theme_constant_override("shadow_offset_x") or title.has_theme_constant_override("shadow_outline_size")
	var shadow_offset: int = absi(title.get_theme_constant("shadow_offset_x")) + absi(title.get_theme_constant("shadow_offset_y"))
	var shadow_size: int = title.get_theme_constant("shadow_outline_size")
	if not has_explicit_shadow or (shadow_offset == 0 and shadow_size == 0):
		push_error("TitleLabel must declare an explicit non-zero drop shadow")
		return false
	print("✓ Contrato 2: Título con outline y sombra")
	return true


# ---------------------------------------------------------------------------
# 3. Node names and texts kept
# ---------------------------------------------------------------------------
func _assert_node_names_kept(menu: CanvasLayer) -> bool:
	var passed: bool = true
	for path: String in REQUIRED_NODES:
		if menu.get_node_or_null(path) == null:
			push_error("Missing node %s" % path)
			passed = false
	var play: Button = menu.get_node_or_null("Control/PlayButton") as Button
	if play != null and play.text != "Jugar":
		push_error("PlayButton must display Jugar, got '%s'" % play.text)
		passed = false
	var quit_button: Button = menu.get_node_or_null("Control/QuitButton") as Button
	if quit_button != null and quit_button.text != "Salir":
		push_error("QuitButton must display Salir, got '%s'" % quit_button.text)
		passed = false
	if passed:
		print("✓ Contrato 3: Nombres de nodos y textos del menú conservados")
	return passed
