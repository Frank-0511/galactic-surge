# etapa_14_contract_test.gd
# Contract test harness for Etapa 14: Células de Plasma y Cargas de Antimateria.
# Verifies:
# 1. LootDrop exposes the PLASMA_CELL type and picks one of three visual variants.
# 2. The "antimatter" input action is bound to the X key.
# 3. Plasma meter: 50 cells store one charge, the meter stays below full when the
#    charge stock is full, and every 100 cells in total grant an extra life.
# 4. Antimatter detonation: spends one charge, destroys enemies on screen with
#    score (no drops), and is refused when no charge is stored.
# 5. HUD: the plasma meter reflects the current cell count and charges.

extends SceneTree

const LOOT_DROP_SCENE_PATH := "res://scenes/loot/loot_drop.tscn"
const ASTEROID_SCENE_PATH := "res://scenes/entities/asteroid/asteroid.tscn"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"

const LootDropScript: Script = preload("res://scenes/loot/loot_drop.gd")


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 14 ---")
	var t1: bool = await _assert_plasma_cell_loot_contract()
	var t2: bool = _assert_antimatter_input_contract()
	var t3: bool = await _assert_plasma_meter_contract()
	var t4: bool = await _assert_antimatter_detonation_contract()
	var t5: bool = await _assert_hud_plasma_meter_contract()

	var all_passed: bool = t1 and t2 and t3 and t4 and t5

	if all_passed:
		print("ETAPA 14 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 14 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Plasma cell loot type and variants
# ---------------------------------------------------------------------------
func _assert_plasma_cell_loot_contract() -> bool:
	if not ResourceLoader.exists(LOOT_DROP_SCENE_PATH):
		push_error("Missing loot drop scene: %s" % LOOT_DROP_SCENE_PATH)
		return false

	var packed: PackedScene = load(LOOT_DROP_SCENE_PATH) as PackedScene
	var loot: Area2D = packed.instantiate() as Area2D
	root.add_child(loot)
	await process_frame

	loot.call("configure", LootDropScript.Type.PLASMA_CELL, Vector2(200, 200))
	await process_frame

	if loot.call("get_type") != LootDropScript.Type.PLASMA_CELL:
		push_error("LootDrop must keep the PLASMA_CELL type after configure()")
		loot.queue_free()
		return false

	var variant: int = loot.get("_variant")
	if variant < 0 or variant >= LootDropScript.PLASMA_CELL_VARIANT_COUNT:
		push_error("Plasma cell variant must be in [0, %d)" % LootDropScript.PLASMA_CELL_VARIANT_COUNT)
		loot.queue_free()
		return false

	loot.queue_free()
	await process_frame
	return true


# ---------------------------------------------------------------------------
# 2. Input binding
# ---------------------------------------------------------------------------
func _assert_antimatter_input_contract() -> bool:
	if not InputMap.has_action(&"antimatter"):
		push_error("Input action 'antimatter' must exist in project.godot")
		return false

	for event: InputEvent in InputMap.action_get_events(&"antimatter"):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == KEY_X:
			return true

	push_error("Input action 'antimatter' must be bound to the X key")
	return false


# ---------------------------------------------------------------------------
# 3. Plasma meter conversion, cap, and extra life
# ---------------------------------------------------------------------------
func _assert_plasma_meter_contract() -> bool:
	var main: Node2D = await _spawn_main()
	if main == null:
		return false

	main.call("reset_session")
	await process_frame

	for i: int in range(49):
		main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)
	if main.get("antimatter_charges") != 0 or main.get("plasma_cells") != 49:
		push_error("49 plasma cells must fill the meter without storing a charge")
		main.queue_free()
		return false

	main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)
	if main.get("antimatter_charges") != 1 or main.get("plasma_cells") != 0:
		push_error("50 plasma cells must store one antimatter charge and reset the meter")
		main.queue_free()
		return false

	# Fill the stock to its cap; the meter must then stay below full
	for i: int in range(50 * 2):
		main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)
	if main.get("antimatter_charges") != 3:
		push_error("Antimatter charges must reach the cap of 3")
		main.queue_free()
		return false

	for i: int in range(50):
		main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)
	if main.get("antimatter_charges") != 3 or main.get("plasma_cells") != 49:
		push_error("At the charge cap the meter must stay at 49 and never store more charges")
		main.queue_free()
		return false

	# Extra life every 100 cells in total (lives are capped by STARTING_LIVES)
	main.call("reset_session")
	await process_frame
	main.set("lives", 1)
	for i: int in range(100):
		main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)
	if main.get("lives") != 2:
		push_error("100 total plasma cells must grant one extra life")
		main.queue_free()
		return false

	main.queue_free()
	await process_frame
	return true


# ---------------------------------------------------------------------------
# 4. Antimatter detonation
# ---------------------------------------------------------------------------
func _assert_antimatter_detonation_contract() -> bool:
	var main: Node2D = await _spawn_main()
	if main == null:
		return false

	main.call("reset_session")
	await process_frame

	if main.call("activate_antimatter"):
		push_error("Antimatter must be refused when no charge is stored")
		main.queue_free()
		return false

	if not ResourceLoader.exists(ASTEROID_SCENE_PATH):
		push_error("Missing asteroid scene: %s" % ASTEROID_SCENE_PATH)
		main.queue_free()
		return false

	var asteroid: Area2D = (load(ASTEROID_SCENE_PATH) as PackedScene).instantiate() as Area2D
	main.add_child(asteroid)
	asteroid.global_position = Vector2(300, 200)
	main.call("_on_asteroid_spawned", asteroid)
	await process_frame

	var score_before: int = main.get("score")
	main.set("antimatter_charges", 1)
	if not main.call("activate_antimatter"):
		push_error("Antimatter must detonate when a charge is stored")
		main.queue_free()
		return false

	await process_frame
	if main.get("antimatter_charges") != 0:
		push_error("Detonation must spend the stored charge")
		main.queue_free()
		return false
	if is_instance_valid(asteroid) and not asteroid.is_queued_for_deletion():
		push_error("Detonation must destroy enemies and asteroids on screen")
		main.queue_free()
		return false
	if main.get("score") <= score_before:
		push_error("Enemies destroyed by antimatter must still award score")
		main.queue_free()
		return false

	main.queue_free()
	await process_frame
	return true


# ---------------------------------------------------------------------------
# 5. HUD plasma meter
# ---------------------------------------------------------------------------
func _assert_hud_plasma_meter_contract() -> bool:
	var main: Node2D = await _spawn_main()
	if main == null:
		return false

	main.call("reset_session")
	await process_frame

	for i: int in range(12):
		main.call("_on_loot_collected", LootDropScript.Type.PLASMA_CELL)

	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	var bar: ProgressBar = hud.find_child("PlasmaBar", true, false) as ProgressBar if hud != null else null
	if bar == null:
		push_error("HUD must contain the PlasmaBar meter")
		main.queue_free()
		return false
	if int(bar.value) != 12 or int(bar.max_value) != 50:
		push_error("HUD plasma meter must show 12/50 after 12 cells, got %d/%d" % [int(bar.value), int(bar.max_value)])
		main.queue_free()
		return false

	main.queue_free()
	await process_frame
	return true


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _spawn_main() -> Node2D:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		push_error("Missing Main scene: %s" % MAIN_SCENE_PATH)
		return null
	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame
	return main
