# Contract harness for Etapa 15 (T1): campaign structure in 3 chapters.
# Chapter 1 is the current 10-wave campaign plus boss. Defeating the boss of
# chapters 1 and 2 starts the next chapter (waves restart at 1); defeating the
# boss of chapter 3 completes the mission.
extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const BOSS_DEFEAT_CHAPTER_SCORE: int = 3000
const TOTAL_WAVES: int = 10
const TOTAL_CHAPTERS: int = 3


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = await _assert_chapter_structure_contract() and passed
	quit(0 if passed else 1)


func _assert_chapter_structure_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true

	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	if "clear_wave_drop_chance" in main:
		main.set("clear_wave_drop_chance", 0.0)

	if not main.has_method("get_chapter") or not main.has_method("get_total_chapters"):
		push_error("Main must expose get_chapter() and get_total_chapters()")
		root.remove_child(main)
		main.free()
		return false

	if int(main.call("get_total_chapters")) != TOTAL_CHAPTERS:
		push_error("Main must report %d total chapters" % TOTAL_CHAPTERS)
		passed = false

	if int(main.call("get_chapter")) != 1:
		push_error("A new session must start at chapter 1")
		passed = false

	for chapter_index: int in range(1, TOTAL_CHAPTERS + 1):
		if int(main.call("get_chapter")) != chapter_index:
			push_error("Expected chapter %d before its boss, got %d" % [chapter_index, int(main.call("get_chapter"))])
			passed = false
			break
		for wave_index: int in TOTAL_WAVES:
			await _clear_current_wave(main)
			await _finish_wave_transition(main)
		var boss: Area2D = _find_boss(main)
		if boss == null:
			push_error("Chapter %d must spawn its boss after wave %d" % [chapter_index, TOTAL_WAVES])
			passed = false
			break
		boss.call("take_damage", int(boss.get("max_health")))
		await process_frame
		await process_frame
		if chapter_index < TOTAL_CHAPTERS:
			if main.is_mission_complete():
				push_error("Defeating the boss of chapter %d must NOT complete the mission" % chapter_index)
				passed = false
				break
			await _finish_wave_transition(main)
		else:
			if not main.is_mission_complete():
				push_error("Defeating the boss of chapter %d must complete the mission" % chapter_index)
				passed = false

	root.remove_child(main)
	main.free()
	return passed


func _find_boss(main: Node2D) -> Area2D:
	for child: Node in main.get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			return child as Area2D
	return null


func _clear_current_wave(main: Node2D) -> void:
	if main.has_method("is_asteroid_wave_active") and main.call("is_asteroid_wave_active"):
		var asteroid_spawner: Node2D = main.call("get_asteroid_spawner") as Node2D
		for _attempt: int in range(500):
			if asteroid_spawner == null or not asteroid_spawner.call("is_wave_active"):
				break
			asteroid_spawner.set("_spawn_timer", 0.0)
			for child: Node in asteroid_spawner.get_children():
				if is_instance_valid(child) and child is Area2D and child.has_method("destroy"):
					child.call("destroy")
			await process_frame
		return
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	for child: Node in spawner.get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			var enemy: Area2D = child as Area2D
			if enemy.has_method("destroy"):
				enemy.destroy()
	await create_timer(0.0).timeout


func _finish_wave_transition(main: Node2D) -> void:
	await process_frame
	await process_frame
	await process_frame
