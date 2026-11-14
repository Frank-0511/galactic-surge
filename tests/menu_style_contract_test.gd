# menu_style_contract_test.gd
# Contract test for the main menu visual upgrade.
# Verifies:
# 1. Each menu button gets normal, hover, pressed and focus StyleBoxes from the Theme
#    assigned to the root Control (type variations), with no per-node StyleBox overrides.
#    The focus StyleBox has a solid, opaque fill and dark text.
# 2. TitleLabel has an outline size > 0 and a non-zero drop shadow.
# 3. Node names and public texts of the menu still exist (no structural renames).
# 4. Order (laid out on screen): high score above Jugar, Dificultad, Ajustes above Salir.
#    KickerLabel stays removed.
# 5. The four buttons live in a centered VBoxContainer with a 14 px theme separation and
#    a minimum height of 34 px.
# Uses the instantiated scene only; no real-time dependencies.

extends SceneTree

const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const MENU_CONTAINER_PATH := "Control/Menu"
const EXPECTED_SEPARATION := 14
const MIN_BUTTON_HEIGHT := 34.0
## Button path -> theme type variation it must use.
const BUTTON_VARIATIONS: Dictionary = {
	"Control/Menu/PlayButton": "PrimaryButton",
	"Control/Menu/DificultadButton": "SecondaryButton",
	"Control/Menu/AjustesButton": "SecondaryButton",
	"Control/Menu/QuitButton": "SecondaryButton",
}
const STATES: Array[String] = ["normal", "hover", "pressed", "focus"]
const REQUIRED_NODES: Array[String] = [
	"Control/Panel",
	"Control/TitleLabel",
	"Control/Divider",
	"Control/HighScoreLabel",
	"Control/Menu",
	"Control/Menu/DifficultyCaption",
	"Control/Menu/DificultadButton",
	"Control/Menu/PlayButton",
	"Control/Menu/QuitButton",
	"Control/Menu/AjustesButton",
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
	# Containers lay children out on the next frame; positions are read after that.
	await process_frame
	var t1: bool = _assert_button_theme_styles(menu)
	var t2: bool = _assert_title_outline_and_shadow(menu)
	var t3: bool = _assert_node_names_kept(menu)
	var t4: bool = _assert_menu_order(menu)
	var t5: bool = _assert_menu_container(menu)
	root.remove_child(menu)
	menu.free()

	var all_passed: bool = t1 and t2 and t3 and t4 and t5
	if all_passed:
		print("MENU STYLE CONTRACT TESTS: ALL PASSED")
	else:
		push_error("MENU STYLE CONTRACT TESTS: FAILURES DETECTED")
		print("MENU STYLE CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Buttons: StyleBoxes come from the Theme; focus is a solid fill
# ---------------------------------------------------------------------------
func _assert_button_theme_styles(menu: CanvasLayer) -> bool:
	var control: Control = menu.get_node_or_null("Control") as Control
	if control == null or control.theme == null:
		push_error("Root Control must have a Theme assigned")
		return false
	var passed: bool = true
	for path: String in BUTTON_VARIATIONS.keys():
		var button: Button = menu.get_node_or_null(path) as Button
		if button == null:
			push_error("Missing Button at %s" % path)
			passed = false
			continue
		var variation: String = BUTTON_VARIATIONS[path]
		if String(button.theme_type_variation) != variation:
			push_error("%s must use theme type variation %s" % [path, variation])
			passed = false
		if button.has_theme_font_size_override("font_size"):
			push_error("%s must take its font size from the Theme, not an override" % path)
			passed = false
		for state: String in STATES:
			if button.has_theme_stylebox_override(state):
				push_error("%s must not override StyleBox '%s' per node" % [path, state])
				passed = false
			if not control.theme.has_stylebox(state, variation):
				push_error("Theme must define StyleBox '%s' for %s" % [state, variation])
				passed = false
			if not (button.get_theme_stylebox(state) is StyleBoxFlat):
				push_error("%s must resolve StyleBoxFlat '%s' from the Theme" % [path, state])
				passed = false
		var focus_box: StyleBoxFlat = button.get_theme_stylebox("focus") as StyleBoxFlat
		if focus_box != null and focus_box.bg_color.a < 1.0:
			push_error("%s focus must have a solid, opaque fill" % path)
			passed = false
		var focus_text: Color = button.get_theme_color("font_focus_color")
		if focus_text.get_luminance() > 0.1:
			push_error("%s focus text must be dark on the solid fill" % path)
			passed = false
	if passed:
		print("✓ Contrato 1: Botones con StyleBox normal, hover, pressed y focus desde el Theme")
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
# 4. Vertical order on screen: high score, Jugar, Dificultad, Ajustes, Salir
# ---------------------------------------------------------------------------
func _assert_menu_order(menu: CanvasLayer) -> bool:
	var order: Array[String] = [
		"Control/HighScoreLabel",
		"Control/Menu/PlayButton",
		"Control/Menu/DificultadButton",
		"Control/Menu/AjustesButton",
		"Control/Menu/QuitButton",
	]
	var previous_center_y: float = -INF
	for path: String in order:
		var node: Control = menu.get_node_or_null(path) as Control
		if node == null:
			push_error("Missing %s for order check" % path)
			return false
		var center_y: float = node.get_global_rect().get_center().y
		if center_y <= previous_center_y:
			push_error("%s must sit below the previous entry of the menu order" % path)
			return false
		previous_center_y = center_y
	if menu.get_node_or_null("Control/KickerLabel") != null:
		push_error("KickerLabel must be removed from the menu")
		return false
	print("✓ Contrato 4: Orden del menú (puntaje, Jugar, Dificultad, Ajustes, Salir)")
	return true


# ---------------------------------------------------------------------------
# 5. Menu container: centered VBoxContainer, separation and minimum height
# ---------------------------------------------------------------------------
func _assert_menu_container(menu: CanvasLayer) -> bool:
	var container: VBoxContainer = menu.get_node_or_null(MENU_CONTAINER_PATH) as VBoxContainer
	if container == null:
		push_error("Missing VBoxContainer %s" % MENU_CONTAINER_PATH)
		return false
	var passed: bool = true
	var separation: int = container.get_theme_constant("separation")
	if separation != EXPECTED_SEPARATION:
		push_error("Menu separation must be %d from the Theme, got %d" % [EXPECTED_SEPARATION, separation])
		passed = false
	var viewport_center_x: float = menu.get_viewport().get_visible_rect().size.x * 0.5
	var container_center_x: float = container.get_global_rect().get_center().x
	if absf(container_center_x - viewport_center_x) > 1.0:
		push_error("Menu container must be horizontally centered (center %f, viewport %f)" % [container_center_x, viewport_center_x])
		passed = false
	for path: String in BUTTON_VARIATIONS.keys():
		var button: Button = menu.get_node_or_null(path) as Button
		if button == null:
			push_error("Missing Button at %s" % path)
			passed = false
			continue
		if button.get_parent() != container:
			push_error("%s must be a child of %s" % [path, MENU_CONTAINER_PATH])
			passed = false
		if button.custom_minimum_size.y < MIN_BUTTON_HEIGHT:
			push_error("%s minimum height must be at least %d px" % [path, int(MIN_BUTTON_HEIGHT)])
			passed = false
	if passed:
		print("✓ Contrato 5: Contenedor centrado, separación 14 px y alto mínimo 34 px")
	return passed


# ---------------------------------------------------------------------------
# 3. Node names and texts kept
# ---------------------------------------------------------------------------
func _assert_node_names_kept(menu: CanvasLayer) -> bool:
	var passed: bool = true
	for path: String in REQUIRED_NODES:
		if menu.get_node_or_null(path) == null:
			push_error("Missing node %s" % path)
			passed = false
	var play: Button = menu.get_node_or_null("Control/Menu/PlayButton") as Button
	if play != null and play.text != "Jugar":
		push_error("PlayButton must display Jugar, got '%s'" % play.text)
		passed = false
	var quit_button: Button = menu.get_node_or_null("Control/Menu/QuitButton") as Button
	if quit_button != null and quit_button.text != "Salir":
		push_error("QuitButton must display Salir, got '%s'" % quit_button.text)
		passed = false
	if passed:
		print("✓ Contrato 3: Nombres de nodos y textos del menú conservados")
	return passed
