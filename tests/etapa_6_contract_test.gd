# Contract harness for Etapa 6: Drops and Loot.
# Verifies LootDrop scene, physics layers, wave motion, player magnetism,
# bomb scope restricted to enemy_bullets, and Main loot weights and collection effects.
extends SceneTree

const LOOT_SCENE_PATH := "res://features/loot/loot_drop.tscn"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const ENEMY_BULLET_SCENE_PATH := "res://scenes/entities/enemy/enemy_bullet.tscn"
const BOSS_BULLET_SCENE_PATH := "res://scenes/entities/boss/boss_bullet.tscn"
const PLAYER_BULLET_SCENE_PATH := "res://features/bullet/bullet.tscn"

const STARTING_LIVES: int = 3
const SCORE_LOOT_POINTS: int = 250


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var loot_drop_passed: bool = await _assert_loot_drop_contract()
	var bomb_scope_passed: bool = await _assert_bomb_scope_contract()
	var main_loot_passed: bool = await _assert_main_loot_contract()
	var passed: bool = loot_drop_passed and bomb_scope_passed and main_loot_passed
	quit(0 if passed else 1)


# ---------------------------------------------------------------------------
# 1. LootDrop entity and behavior contract
# ---------------------------------------------------------------------------

func _assert_loot_drop_contract() -> bool:
	if not ResourceLoader.exists(LOOT_SCENE_PATH):
		push_error("Missing scene: %s" % LOOT_SCENE_PATH)
		return false
	var packed_scene: PackedScene = load(LOOT_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % LOOT_SCENE_PATH)
		return false
	var loot: Area2D = packed_scene.instantiate() as Area2D
	if loot == null:
		push_error("LootDrop scene root must be Area2D")
		return false
	root.add_child(loot)
	var passed: bool = true

	# 1. Group membership
	if not loot.is_in_group(&"combat_transients"):
		push_error("LootDrop must belong to group 'combat_transients'")
		passed = false

	# 2. Collision layers (layer 8 = items/drops, mask 1 = player)
	if loot.collision_layer != 8:
		push_error("LootDrop collision_layer must be 8, got %d" % loot.collision_layer)
		passed = false
	if loot.collision_mask != 1:
		push_error("LootDrop collision_mask must be 1, got %d" % loot.collision_mask)
		passed = false

	# 3. Signals and methods
	if not loot.has_signal(&"collected"):
		push_error("LootDrop missing signal: collected")
		passed = false
	for method_name: StringName in [&"configure", &"get_type"]:
		if not loot.has_method(method_name):
			push_error("LootDrop missing method: %s" % method_name)
			passed = false

	# 4. Collision shape child
	if loot.get_node_or_null("CollisionShape2D") == null:
		push_error("LootDrop must have CollisionShape2D child")
		passed = false

	# 5. Type enum validation
	var script: Script = loot.get_script() as Script
	if script == null:
		push_error("LootDrop missing script")
		passed = false
	else:
		var const_map: Dictionary = script.get_script_constant_map()
		if not const_map.has("Type"):
			push_error("LootDrop script must declare enum Type")
			passed = false
		else:
			var type_dict: Dictionary = const_map["Type"] as Dictionary
			var expected_types: Dictionary = {
				"SCORE": 0,
				"DOUBLE_SHOT": 1,
				"SHIELD": 2,
				"EXTRA_LIFE": 3,
				"BOMB": 4
			}
			for type_name: String in expected_types:
				if not type_dict.has(type_name):
					push_error("LootDrop enum Type missing: %s" % type_name)
					passed = false
				elif int(type_dict[type_name]) != expected_types[type_name]:
					push_error("LootDrop enum Type.%s must be %d, got %s" % [type_name, expected_types[type_name], str(type_dict[type_name])])
					passed = false

	# 6. Movement properties
	for prop: String in ["fall_speed", "wave_amplitude", "wave_frequency", "magnet_radius", "magnet_acceleration"]:
		if not prop in loot:
			push_error("LootDrop missing property: %s" % prop)
			passed = false

	# 7. Motion & Magnetism behavioral tests
	var fake_player: CharacterBody2D = CharacterBody2D.new()
	fake_player.add_to_group(&"player", true)
	root.add_child(fake_player)
	fake_player.global_position = Vector2(220, 180)

	if loot.has_method(&"configure"):
		loot.call("configure", 0, Vector2(200, 100), fake_player)
		loot.set("fall_speed", 100.0)
		loot.set("wave_amplitude", 26.0)
		loot.set("wave_frequency", 3.0)
		loot.set("magnet_radius", 200.0)
		loot.set("magnet_acceleration", 900.0)

		var before: Vector2 = loot.global_position
		await create_timer(0.25).timeout
		if loot.global_position.y <= before.y:
			push_error("LootDrop must fall downward over time")
			passed = false
		if is_equal_approx(loot.global_position.x, before.x):
			push_error("LootDrop must drift horizontally")
			passed = false

	# Test magnetic acceleration towards player when within magnet_radius
	var loot_magnet: Area2D = packed_scene.instantiate() as Area2D
	if loot_magnet != null:
		root.add_child(loot_magnet)
		fake_player.global_position = Vector2(300, 100)
		if loot_magnet.has_method(&"configure"):
			# Spawn within magnet_radius: loot at (220, 100), player at (300, 100), dist 80 <= 150
			loot_magnet.call("configure", 0, Vector2(220, 100), fake_player)
			loot_magnet.set("fall_speed", 0.0)
			loot_magnet.set("wave_amplitude", 0.0)
			loot_magnet.set("magnet_radius", 150.0)
			loot_magnet.set("magnet_acceleration", 1000.0)
			var x_start: float = loot_magnet.global_position.x
			await create_timer(0.15).timeout
			if loot_magnet.global_position.x <= x_start:
				push_error("LootDrop must accelerate toward player when inside magnet_radius")
				passed = false
		if is_instance_valid(loot_magnet):
			root.remove_child(loot_magnet)
			loot_magnet.free()

	# 8. Viewport despawn
	loot.global_position = Vector2(200, 5000)
	await create_timer(0.1).timeout
	if is_instance_valid(loot):
		push_error("LootDrop must free itself when below the viewport")
		passed = false

	# 9. Collection signal & single emission
	var loot_collect: Area2D = packed_scene.instantiate() as Area2D
	if loot_collect != null:
		root.add_child(loot_collect)
		if loot_collect.has_method(&"configure"):
			loot_collect.call("configure", 0, Vector2(200, 200), fake_player)
		var collect_count: Array[int] = [0]
		var collected_type: Array[int] = [-1]
		if loot_collect.has_signal(&"collected"):
			loot_collect.connect(&"collected", func(t: int, _collector: Node2D) -> void:
				collect_count[0] += 1
				collected_type[0] = t
			)
		if loot_collect.has_method(&"_on_body_entered"):
			loot_collect.call("_on_body_entered", fake_player)
			# Second invocation to test single emission guard
			loot_collect.call("_on_body_entered", fake_player)
			await process_frame
			if collect_count[0] != 1:
				push_error("LootDrop must emit collected signal exactly once, got %d" % collect_count[0])
				passed = false
			if collected_type[0] != 0:
				push_error("LootDrop must emit configured type 0 (SCORE), got %d" % collected_type[0])
				passed = false
			if is_instance_valid(loot_collect):
				push_error("LootDrop must queue_free() upon collection")
				passed = false
		if is_instance_valid(loot_collect):
			root.remove_child(loot_collect)
			loot_collect.free()

	if is_instance_valid(fake_player):
		root.remove_child(fake_player)
		fake_player.free()
	if is_instance_valid(loot):
		root.remove_child(loot)
		loot.free()
	return passed


# ---------------------------------------------------------------------------
# 2. Bomb scope contract (enemy_bullets group only)
# ---------------------------------------------------------------------------

func _assert_bomb_scope_contract() -> bool:
	var passed: bool = true

	# 1. Instantiate Main first so its startup _enter_main_menu doesn't purge test bullets
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	if main == null:
		push_error("Main root must be Node2D")
		return false
	root.add_child(main)
	await process_frame

	# 2. Verify EnemyBullet belongs to enemy_bullets group
	if not ResourceLoader.exists(ENEMY_BULLET_SCENE_PATH):
		push_error("Missing scene: %s" % ENEMY_BULLET_SCENE_PATH)
		root.remove_child(main)
		main.free()
		return false
	var enemy_bullet_scene: PackedScene = load(ENEMY_BULLET_SCENE_PATH) as PackedScene
	var enemy_bullet: Area2D = enemy_bullet_scene.instantiate() as Area2D
	if enemy_bullet == null:
		push_error("EnemyBullet root must be Area2D")
		root.remove_child(main)
		main.free()
		return false
	enemy_bullet.global_position = Vector2(200, 200)
	root.add_child(enemy_bullet)
	if not enemy_bullet.is_in_group(&"enemy_bullets"):
		push_error("EnemyBullet must be in group 'enemy_bullets'")
		passed = false

	# 3. Verify BossBullet belongs to enemy_bullets group
	if not ResourceLoader.exists(BOSS_BULLET_SCENE_PATH):
		push_error("Missing scene: %s" % BOSS_BULLET_SCENE_PATH)
		if is_instance_valid(enemy_bullet):
			enemy_bullet.free()
		root.remove_child(main)
		main.free()
		return false
	var boss_bullet_scene: PackedScene = load(BOSS_BULLET_SCENE_PATH) as PackedScene
	var boss_bullet: Area2D = boss_bullet_scene.instantiate() as Area2D
	if boss_bullet == null:
		push_error("BossBullet root must be Area2D")
		if is_instance_valid(enemy_bullet):
			enemy_bullet.free()
		root.remove_child(main)
		main.free()
		return false
	boss_bullet.global_position = Vector2(280, 200)
	root.add_child(boss_bullet)
	if not boss_bullet.is_in_group(&"enemy_bullets"):
		push_error("BossBullet must be in group 'enemy_bullets'")
		passed = false

	# 4. Verify PlayerBullet does NOT belong to enemy_bullets group
	if not ResourceLoader.exists(PLAYER_BULLET_SCENE_PATH):
		push_error("Missing scene: %s" % PLAYER_BULLET_SCENE_PATH)
		if is_instance_valid(enemy_bullet):
			enemy_bullet.free()
		if is_instance_valid(boss_bullet):
			boss_bullet.free()
		root.remove_child(main)
		main.free()
		return false
	var player_bullet_scene: PackedScene = load(PLAYER_BULLET_SCENE_PATH) as PackedScene
	var player_bullet: Area2D = player_bullet_scene.instantiate() as Area2D
	if player_bullet == null:
		push_error("Player bullet root must be Area2D")
		if is_instance_valid(enemy_bullet):
			enemy_bullet.free()
		if is_instance_valid(boss_bullet):
			boss_bullet.free()
		root.remove_child(main)
		main.free()
		return false
	player_bullet.global_position = Vector2(240, 300)
	root.add_child(player_bullet)
	if player_bullet.is_in_group(&"enemy_bullets"):
		push_error("Player bullet must NOT be in group 'enemy_bullets'")
		passed = false

	# 5. Test _clear_enemy_bullets
	if not main.has_method(&"_clear_enemy_bullets"):
		push_error("Main missing method: _clear_enemy_bullets")
		passed = false
	else:
		main.call("_clear_enemy_bullets")
		await process_frame
		await process_frame
		if is_instance_valid(enemy_bullet):
			push_error("Bomb (_clear_enemy_bullets) must remove EnemyBullet")
			passed = false
		if is_instance_valid(boss_bullet):
			push_error("Bomb (_clear_enemy_bullets) must remove BossBullet")
			passed = false
		if not is_instance_valid(player_bullet):
			push_error("Bomb (_clear_enemy_bullets) must NOT remove PlayerBullet")
			passed = false

	# Cleanup
	if is_instance_valid(enemy_bullet):
		root.remove_child(enemy_bullet)
		enemy_bullet.free()
	if is_instance_valid(boss_bullet):
		root.remove_child(boss_bullet)
		boss_bullet.free()
	if is_instance_valid(player_bullet):
		root.remove_child(player_bullet)
		player_bullet.free()
	if is_instance_valid(main):
		root.remove_child(main)
		main.free()

	return passed



# ---------------------------------------------------------------------------
# 3. Main loot configuration, weights, and collection effects contract
# ---------------------------------------------------------------------------

func _assert_main_loot_contract() -> bool:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	var main: Node2D = main_scene.instantiate() as Node2D
	if main == null:
		push_error("Main root must be Node2D")
		return false
	root.add_child(main)
	var passed: bool = true

	# 1. Exported loot properties
	var required_props: Array[String] = [
		"enemy_loot_drop_chance",
		"score_loot_weight",
		"double_shot_loot_weight",
		"shield_loot_weight",
		"extra_life_loot_weight",
		"bomb_loot_weight"
	]
	for prop: String in required_props:
		if not prop in main:
			push_error("Main missing exported loot property: %s" % prop)
			passed = false

	# 2. Required methods
	var required_methods: Array[StringName] = [
		&"_pick_loot_type",
		&"_try_spawn_enemy_loot",
		&"_spawn_loot",
		&"_on_loot_collected"
	]
	for method_name: StringName in required_methods:
		if not main.has_method(method_name):
			push_error("Main missing method: %s" % method_name)
			passed = false

	# 3. Weighted selection test
	if main.has_method(&"_pick_loot_type"):
		var weight_keys: Array[String] = [
			"score_loot_weight",
			"double_shot_loot_weight",
			"shield_loot_weight",
			"extra_life_loot_weight",
			"bomb_loot_weight"
		]
		for expected_type: int in range(weight_keys.size()):
			for i: int in range(weight_keys.size()):
				main.set(weight_keys[i], 1.0 if i == expected_type else 0.0)
			var picked: int = int(main.call("_pick_loot_type"))
			if picked != expected_type:
				push_error("Weighted selection for %s expected %d, got %d" % [weight_keys[expected_type], expected_type, picked])
				passed = false

		# Fallback when all weights are zero (must return 0 / SCORE)
		for key: String in weight_keys:
			main.set(key, 0.0)
		var fallback_type: int = int(main.call("_pick_loot_type"))
		if fallback_type != 0:
			push_error("All weights zero must fallback to 0 (SCORE), got %d" % fallback_type)
			passed = false

	# 4. Spawning tests
	if main.has_method(&"_try_spawn_enemy_loot"):
		# Inactive session: must not spawn
		main.set("enemy_loot_drop_chance", 1.0)
		main.set("score_loot_weight", 1.0)
		main.call("_try_spawn_enemy_loot", Vector2(240, 180))
		var inactive_loot: Area2D = _find_loot(main)
		if inactive_loot != null:
			push_error("Main must NOT spawn loot when session is inactive")
			passed = false
			inactive_loot.queue_free()

		# Start session for active tests
		main.start_session()
		await process_frame
		var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
		if announcement != null and "display_duration" in announcement:
			announcement.set("display_duration", 0.0)
		var spawner: Node2D = main.get_node_or_null("EnemySpawner") as Node2D
		if spawner != null and spawner.has_method("stop"):
			spawner.stop()

		# Chance = 0.0: must not spawn
		main.set("enemy_loot_drop_chance", 0.0)
		main.call("_try_spawn_enemy_loot", Vector2(240, 180))
		var zero_loot: Area2D = _find_loot(main)
		if zero_loot != null:
			push_error("Main must NOT spawn loot when drop chance is 0.0")
			passed = false
			zero_loot.queue_free()

		# Chance = 1.0, score weight = 1.0: must spawn SCORE loot
		main.set("enemy_loot_drop_chance", 1.0)
		main.set("score_loot_weight", 1.0)
		main.set("double_shot_loot_weight", 0.0)
		main.set("shield_loot_weight", 0.0)
		main.set("extra_life_loot_weight", 0.0)
		main.set("bomb_loot_weight", 0.0)
		main.call("_try_spawn_enemy_loot", Vector2(240, 180))
		var spawned_loot: Area2D = _find_loot(main)
		if spawned_loot == null:
			push_error("Main._try_spawn_enemy_loot must spawn a loot drop when chance is 1.0")
			passed = false
		else:
			if spawned_loot.has_method(&"get_type") and int(spawned_loot.call("get_type")) != 0:
				push_error("Spawned loot drop must be Type.SCORE (0)")
				passed = false
			spawned_loot.queue_free()

	# 5. Effects tests via _on_loot_collected
	if main.has_method(&"_on_loot_collected"):
		if not main.call("is_session_active"):
			main.start_session()
			await process_frame

		# Effect 0: SCORE (250 points and HUD updated)
		var score_before: int = main.score
		main.call("_on_loot_collected", 0)
		if main.score != score_before + SCORE_LOOT_POINTS:
			push_error("SCORE loot must award %d points, got %d" % [SCORE_LOOT_POINTS, main.score - score_before])
			passed = false
		var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			var score_label: Label = hud.find_child("ScoreLabel", true, false) as Label
			if score_label == null or not score_label.text.contains(str(main.score)):
				push_error("HUD ScoreLabel must reflect updated score after SCORE loot")
				passed = false

		# Effect 1: DOUBLE_SHOT
		var player: CharacterBody2D = main.get_node_or_null("Player") as CharacterBody2D
		if player != null:
			player.call("clear_power_ups")
			main.call("_on_loot_collected", 1)
			if not player.call("has_double_shot"):
				push_error("DOUBLE_SHOT loot must activate double shot on player")
				passed = false

		# Effect 2: SHIELD
		if player != null:
			player.call("clear_power_ups")
			main.call("_on_loot_collected", 2)
			if not player.call("has_shield"):
				push_error("SHIELD loot must activate shield on player")
				passed = false

		# Effect 3: EXTRA_LIFE
		main.lives = 2
		main.call("_on_loot_collected", 3)
		if main.lives != 3:
			push_error("EXTRA_LIFE loot must increase lives from 2 to 3, got %d" % main.lives)
			passed = false
		if hud != null:
			var lives_label: Label = hud.find_child("LivesLabel", true, false) as Label
			if lives_label == null or not lives_label.text.contains("3"):
				push_error("HUD LivesLabel must reflect updated lives after EXTRA_LIFE loot")
				passed = false
		main.lives = STARTING_LIVES
		main.call("_on_loot_collected", 3)
		if main.lives != STARTING_LIVES:
			push_error("EXTRA_LIFE loot must cap lives at STARTING_LIVES (%d), got %d" % [STARTING_LIVES, main.lives])
			passed = false

		# Effect 4: BOMB
		var test_bullet: Node2D = Node2D.new()
		test_bullet.add_to_group(&"enemy_bullets", true)
		root.add_child(test_bullet)
		main.call("_on_loot_collected", 4)
		await process_frame
		await process_frame
		if is_instance_valid(test_bullet):
			push_error("BOMB loot must clear enemy_bullets")
			passed = false
			test_bullet.queue_free()

	root.remove_child(main)
	main.free()
	return passed


func _find_loot(main: Node2D) -> Area2D:
	for child: Node in main.get_children():
		if child is Area2D and child.is_in_group(&"combat_transients") and child.has_signal(&"collected") and "wave_amplitude" in child:
			return child as Area2D
	return null
