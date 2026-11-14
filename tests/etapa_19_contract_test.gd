# etapa_19_contract_test.gd
# Contract test harness for Etapa 19: Settings base (persistencia local).
# Verifies (odd/tasks/etapa-19-settings.md):
# 1. Defaults: master_db 0.0, music_db 0.0, sfx_db 0.0, fullscreen false, vsync true.
# 2. Missing file: load_settings() returns the defaults and does not create a file.
# 3. Round trip: save_settings() then load_settings() returns the same values.
# 4. Sections: values are written under [audio] and [display] in the ConfigFile.
# Uses an explicit temporary path so the user's real settings file is never touched.

extends SceneTree

const SETTINGS := preload("res://scripts/systems/settings.gd")
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
