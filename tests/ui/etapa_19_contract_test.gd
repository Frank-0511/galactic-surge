# etapa_19_contract_test.gd
# Contract test harness for Etapa 19: Settings base (persistencia local).
# Verifies (odd/tasks/etapa-19-settings.md):
# 1. Defaults: master_db 0.0, music_db 0.0, sfx_db 0.0, fullscreen false, vsync true.
# 2. Missing file: load_settings() returns the defaults and does not create a file.
# 3. Round trip: save_settings() then load_settings() returns the same values.
# 4. Sections: values are written under [audio] and [display] in the ConfigFile.
# 12. Rebind Kit: addon classes, Controles button, InputRemap saving to user://rebind_kit.json.
# Uses an explicit temporary path so the user's real settings file is never touched.

extends SceneTree

const SETTINGS := preload("res://core/settings/settings.gd")
const TEST_PATH := "user://settings_test.cfg"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 19 ---")
	_cleanup()
	var passed: bool = true
	passed = _assert_defaults() and passed
	passed = _assert_missing_file_returns_defaults() and passed
	passed = _assert_round_trip() and passed
	passed = _assert_sections() and passed
	passed = _assert_audio_buses() and passed
	passed = _assert_display_mapping() and passed
	passed = _assert_apply_audio() and passed
	passed = _assert_settings_menu_scene() and passed
	passed = _assert_toggles_share_style() and passed
	passed = _assert_settings_focus_on_open() and passed
	passed = _assert_settings_layout() and passed
	passed = _assert_rebind_kit_contract() and passed
	_cleanup()

	if passed:
		print("ETAPA 19 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 19 CONTRACT TESTS: FAILURES DETECTED")
		print("ETAPA 19 CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if passed else 1)


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


# 1. Defaults
func _assert_defaults() -> bool:
	var d: Dictionary = SETTINGS.default_values()
	var ok: bool = is_equal_approx(d["master_db"], 0.0) \
		and is_equal_approx(d["music_db"], 0.0) \
		and is_equal_approx(d["sfx_db"], 0.0) \
		and d["fullscreen"] == false \
		and d["vsync"] == true
	if ok:
		print("✓ Contrato 1: Valores por defecto")
	else:
		push_error("Defaults incorrectos: %s" % str(d))
	return ok


# 2. Missing file
func _assert_missing_file_returns_defaults() -> bool:
	var loaded: Dictionary = SETTINGS.load_settings(TEST_PATH)
	var ok: bool = loaded == SETTINGS.default_values() and not FileAccess.file_exists(TEST_PATH)
	if ok:
		print("✓ Contrato 2: Archivo ausente devuelve defaults sin crear archivo")
	else:
		push_error("Archivo ausente: se esperaban defaults y ningún archivo")
	return ok


# 3. Round trip
func _assert_round_trip() -> bool:
	var values: Dictionary = {
		"master_db": -6.5,
		"music_db": -12.0,
		"sfx_db": -3.0,
		"fullscreen": true,
		"vsync": false,
	}
	SETTINGS.save_settings(values, TEST_PATH)
	var loaded: Dictionary = SETTINGS.load_settings(TEST_PATH)
	var ok: bool = is_equal_approx(loaded["master_db"], -6.5) \
		and is_equal_approx(loaded["music_db"], -12.0) \
		and is_equal_approx(loaded["sfx_db"], -3.0) \
		and loaded["fullscreen"] == true \
		and loaded["vsync"] == false
	if ok:
		print("✓ Contrato 3: Ida y vuelta de save/load")
	else:
		push_error("Round trip fallido: %s" % str(loaded))
	return ok


# 5. Audio buses: layout has Master, Music, SFX; music players route to Music, the rest to SFX
func _assert_audio_buses() -> bool:
	var layout: AudioBusLayout = load("res://default_bus_layout.tres") as AudioBusLayout
	if layout == null:
		push_error("default_bus_layout.tres must exist and load as AudioBusLayout")
		return false
	AudioServer.set_bus_layout(layout)
	var names: Array[String] = []
	for i: int in range(AudioServer.get_bus_count()):
		names.append(AudioServer.get_bus_name(i))
	if not ("Master" in names and "Music" in names and "SFX" in names):
		push_error("Bus layout must contain Master, Music and SFX, got %s" % str(names))
		return false
	var scene: Node = load("res://features/audio/audio_feedback.tscn").instantiate()
	var ok: bool = true
	for child: Node in scene.get_children():
		if not child is AudioStreamPlayer:
			continue
		var expected: String = "Music" if child.name in ["CombatMusic", "BossMusic"] else "SFX"
		if child.bus != expected:
			push_error("%s must route to %s, got %s" % [child.name, expected, child.bus])
			ok = false
	scene.free()
	if ok:
		print("✓ Contrato 5: Buses Master/Music/SFX y ruteo de reproductores")
	return ok


# 6. Display mapping: fullscreen and vsync booleans map to DisplayServer modes
func _assert_display_mapping() -> bool:
	var ok: bool = SETTINGS.window_mode_for(true) == DisplayServer.WINDOW_MODE_FULLSCREEN \
		and SETTINGS.window_mode_for(false) == DisplayServer.WINDOW_MODE_WINDOWED \
		and SETTINGS.vsync_mode_for(true) == DisplayServer.VSYNC_ENABLED \
		and SETTINGS.vsync_mode_for(false) == DisplayServer.VSYNC_DISABLED
	if ok:
		print("✓ Contrato 6: Mapeo fullscreen/vsync a DisplayServer")
	else:
		push_error("Mapeo de display incorrecto")
	return ok


# 7. Audio apply: apply_audio sets the dB of the Master, Music and SFX buses
func _assert_apply_audio() -> bool:
	SETTINGS.apply_audio({"master_db": -6.0, "music_db": -12.0, "sfx_db": -3.0})
	var ok: bool = is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), -6.0) \
		and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -12.0) \
		and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), -3.0)
	SETTINGS.apply_audio(SETTINGS.default_values())
	if ok:
		print("✓ Contrato 7: apply_audio fija volumen dB de Master, Music y SFX")
	else:
		push_error("apply_audio no fijó los dB esperados")
	return ok


# 8. Settings menu scene exposes its controls and emits back_requested
func _assert_settings_menu_scene() -> bool:
	var scene: Node = load("res://features/ui/settings_menu.tscn").instantiate()
	var ok: bool = true
	for path: String in ["Control/Center/Content/MasterBlock/MasterSlider", "Control/Center/Content/MusicBlock/MusicSlider", "Control/Center/Content/SfxBlock/SfxSlider", "Control/Center/Content/DisplayOptions/FullscreenToggle", "Control/Center/Content/DisplayOptions/VsyncToggle", "Control/Center/Content/BackButton"]:
		if scene.get_node_or_null(path) == null:
			push_error("settings_menu.tscn missing %s" % path)
			ok = false
	if not scene.has_signal("back_requested"):
		push_error("settings_menu must declare back_requested")
		ok = false
	scene.free()
	if ok:
		print("✓ Contrato 8: Escena de Settings con controles y back_requested")
	return ok


# 9. Both display toggles share the same theme overrides (font size and color)
func _assert_toggles_share_style() -> bool:
	var menu: CanvasLayer = load("res://features/ui/settings_menu.tscn").instantiate()
	root.add_child(menu)
	var fullscreen: Button = menu.get_node("Control/Center/Content/DisplayOptions/FullscreenToggle")
	var vsync: Button = menu.get_node("Control/Center/Content/DisplayOptions/VsyncToggle")
	var ok: bool = fullscreen.get_theme_font_size("font_size") == vsync.get_theme_font_size("font_size") \
		and fullscreen.get_theme_color("font_color") == vsync.get_theme_color("font_color") \
		and fullscreen.theme_type_variation == &"ToggleButton" and vsync.theme_type_variation == &"ToggleButton"
	# VSync se oculta del menu (decision del usuario): el ajuste sigue guardado con su valor por defecto.
	ok = ok and not vsync.visible
	root.remove_child(menu)
	menu.free()
	if ok:
		print("✓ Contrato 9: Toggles de pantalla completa y VSync con el mismo estilo")
	else:
		push_error("Pantalla completa y VSync deben compartir font_size y font_color")
	return ok


# 10. Focus on open: show_menu() gives focus to the first control so gamepad navigation works
func _assert_settings_focus_on_open() -> bool:
	var menu: CanvasLayer = load("res://features/ui/settings_menu.tscn").instantiate()
	root.add_child(menu)
	menu.show_menu()
	var owner: Control = root.get_viewport().gui_get_focus_owner()
	var ok: bool = owner != null and owner == menu.get_node("Control/Center/Content/MasterBlock/MasterSlider")
	root.remove_child(menu)
	menu.free()
	if ok:
		print("✓ Contrato 10: Ajustes toma foco al abrirse")
	else:
		push_error("show_menu() debe dar foco a MasterSlider")
	return ok


# 11. Layout: centered container, constant separations, label above slider, Theme variations
# and no per-node style or font overrides on the buttons and labels.
func _assert_settings_layout() -> bool:
	var menu: CanvasLayer = load("res://features/ui/settings_menu.tscn").instantiate()
	root.add_child(menu)
	var ok: bool = true
	var control: Control = menu.get_node_or_null("Control") as Control
	if control == null or control.theme == null:
		push_error("Root Control must have a Theme assigned")
		ok = false
	if menu.get_node_or_null("Control/Center") is not CenterContainer:
		push_error("Control/Center must be a CenterContainer")
		ok = false
	var content: VBoxContainer = menu.get_node_or_null("Control/Center/Content") as VBoxContainer
	var display: VBoxContainer = menu.get_node_or_null("Control/Center/Content/DisplayOptions") as VBoxContainer
	if content == null or display == null:
		push_error("Content and DisplayOptions must be VBoxContainer")
		ok = false
	else:
		if content.get_theme_constant("separation") != 18:
			push_error("Blocks of sliders must be separated by 18 px")
			ok = false
		if display.get_theme_constant("separation") != 24:
			push_error("Display toggles must be separated by 24 px")
			ok = false
	for pair: Array in [["MasterBlock/MasterLabel", "MasterBlock/MasterSlider"], ["MusicBlock/MusicLabel", "MusicBlock/MusicSlider"], ["SfxBlock/SfxLabel", "SfxBlock/SfxSlider"]]:
		var label: Node = menu.get_node_or_null("Control/Center/Content/" + pair[0])
		var slider: Node = menu.get_node_or_null("Control/Center/Content/" + pair[1])
		if label == null or slider == null or label.get_index() > slider.get_index():
			push_error("%s must sit above %s" % [pair[0], pair[1]])
			ok = false
	var variations: Dictionary = {
		"Control/Center/Content/DisplayOptions/FullscreenToggle": "ToggleButton",
		"Control/Center/Content/DisplayOptions/VsyncToggle": "ToggleButton",
		"Control/Center/Content/BackButton": "PrimaryButton",
	}
	for path: String in variations.keys():
		var button: Button = menu.get_node_or_null(path) as Button
		if button == null or String(button.theme_type_variation) != variations[path]:
			push_error("%s must use theme variation %s" % [path, variations[path]])
			ok = false
			continue
		for state: String in ["normal", "hover", "pressed", "focus"]:
			if button.has_theme_stylebox_override(state):
				push_error("%s must not override StyleBox '%s' per node" % [path, state])
				ok = false
		if button.has_theme_font_size_override("font_size") or button.has_theme_color_override("font_color"):
			push_error("%s must take font size and color from the Theme" % path)
			ok = false
	for path: String in ["Control/Center/Content/Title", "Control/Center/Content/MasterBlock/MasterLabel", "Control/Center/Content/MusicBlock/MusicLabel", "Control/Center/Content/SfxBlock/SfxLabel"]:
		var label: Label = menu.get_node_or_null(path) as Label
		if label == null or label.has_theme_font_size_override("font_size") or label.has_theme_color_override("font_color"):
			push_error("%s must take font size and color from the Theme" % path)
			ok = false
	if menu.get_node_or_null("Control/Center/Content/Title") is Label and String(menu.get_node("Control/Center/Content/Title").theme_type_variation) != "TitleLabel":
		push_error("Title must use theme variation TitleLabel")
		ok = false
	root.remove_child(menu)
	menu.free()
	if ok:
		print("✓ Contrato 11: Contenedor centrado, separaciones 18/24 px, variaciones de Theme sin overrides")
	else:
		push_error("Layout de Ajustes fuera del contrato")
	return ok


# 12. Rebind Kit: the addon's classes load, the menu has a Controles button, and the menu owns an InputRemap that
# saves to user://rebind_kit.json.
const REBIND_DIR := "res://addons/rebind_kit/"
const REBIND_SAVE_PATH := "user://rebind_kit.json"

func _assert_rebind_kit_contract() -> bool:
	var ok: bool = true
	for class_file: String in ["InputRemap", "RemapPanel"]:
		var script: Script = load(REBIND_DIR + class_file + ".gd") as Script
		if script == null or script.get_global_name() != StringName(class_file):
			push_error("Falta la clase %s de Rebind Kit en %s" % [class_file, REBIND_DIR])
			ok = false
	var menu: CanvasLayer = load("res://features/ui/settings_menu.tscn").instantiate()
	if menu.get_node_or_null("Control/Center/Content/ControlsButton") == null:
		push_error("settings_menu.tscn debe tener Control/Center/Content/ControlsButton")
		ok = false
	root.add_child(menu)
	var remap = menu.get("remap")
	if remap == null or not remap.is_inside_tree():
		push_error("El menu de Ajustes debe tener un InputRemap en su arbol (propiedad remap)")
		ok = false
	elif remap.adapter.save_path != REBIND_SAVE_PATH:
		push_error("El InputRemap debe guardar en %s, guarda en %s" % [REBIND_SAVE_PATH, remap.adapter.save_path])
		ok = false
	root.remove_child(menu)
	menu.free()
	if ok:
		print("✓ Contrato 12: Rebind Kit cargado, botón Controles e InputRemap guardando en user://rebind_kit.json")
	else:
		push_error("Contrato Rebind Kit fuera de contrato")
	return ok


# 4. Sections
func _assert_sections() -> bool:
	var config := ConfigFile.new()
	var err: int = config.load(TEST_PATH)
	var ok: bool = err == OK \
		and config.has_section_key("audio", "master_db") \
		and config.has_section_key("audio", "music_db") \
		and config.has_section_key("audio", "sfx_db") \
		and config.has_section_key("display", "fullscreen") \
		and config.has_section_key("display", "vsync")
	if ok:
		print("✓ Contrato 4: Secciones [audio] y [display]")
	else:
		push_error("Secciones o claves ausentes en settings.cfg")
	return ok
