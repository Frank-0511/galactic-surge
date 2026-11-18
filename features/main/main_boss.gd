# main_boss.gd
# Boss battles of the session (Etapa 8 onward): spawns the chapter boss, reacts to
# its health and armor phases, rewards the defeat and moves to the next chapter.
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


func start_battle() -> void:
	_main._session_state = _main.SessionState.BOSS_BATTLE
	clear_boss()
	var boss: Area2D = _main.BOSS_SCENE.instantiate() as Area2D
	if boss == null:
		return
	_main._active_boss = boss
	boss.global_position = Vector2(_main.get_viewport().get_visible_rect().size.x * 0.5, -100.0)
	boss.max_health = int(_main.BOSS_HEALTH_BY_CHAPTER[clampi(_main._chapter - 1, 0, _main.BOSS_HEALTH_BY_CHAPTER.size() - 1)])
	var chapter_index: int = clampi(_main._chapter - 1, 0, _main.TOTAL_CHAPTERS - 1)
	boss.boss_variant = _main.BOSS_VARIANTS_BY_CHAPTER[chapter_index]
	# Núcleo Blindado three-phase fight is reserved for the final chapter.
	boss.multi_phase_enabled = _main._chapter == _main.TOTAL_CHAPTERS
	boss.armor_phase_changed.connect(on_armor_phase_changed)
	boss.health_changed.connect(on_health_changed)
	boss.boss_defeated.connect(on_defeated)
	boss.boss_contacted_player.connect(on_contacted_player)
	_main.add_child(boss)
	var max_hp: int = int(boss.get("max_health")) if "max_health" in boss else 150
	_main._hud.show_boss_health_bar(_main.BOSS_NAMES_BY_CHAPTER[chapter_index], max_hp)
	_main._audio_feedback.stop_combat_music()
	_main._audio_feedback.start_boss_music()


func on_health_changed(current: int, max_hp: int) -> void:
	_main._hud.update_boss_health(current, max_hp)
	_main._camera.shake(4.0, 0.15)


## Núcleo Blindado armor phase change: camera shake and a short on-screen message.
func on_armor_phase_changed(phase: int) -> void:
	if not _main._session_active:
		return
	if phase != _main.ARMOR_PHASE_SUBCORE and phase != _main.ARMOR_PHASE_EXPOSED_CORE:
		return
	var text: String = _main.ARMOR_BROKEN_TEXT if phase == _main.ARMOR_PHASE_SUBCORE else _main.CORE_EXPOSED_TEXT
	if _main._camera != null and _main._camera.has_method(&"add_trauma"):
		_main._camera.add_trauma(_main.ARMOR_PHASE_CHANGE_TRAUMA)
	if _main._visual_feedback != null and _main._active_boss != null:
		_main._visual_feedback.play_text_popup(_main._active_boss.global_position + Vector2(0, -60), text, Color(1.0, 0.75, 0.25))


func on_contacted_player(player: Node2D) -> void:
	_main._request_player_damage(player)


func on_defeated(boss: Area2D) -> void:
	if not _main._session_active:
		return
	var explosion_pos: Vector2 = boss.global_position
	_main._visual_feedback.play_enemy_explosion(explosion_pos)
	_main._visual_feedback.play_enemy_explosion(explosion_pos + Vector2(-35, 15))
	_main._visual_feedback.play_enemy_explosion(explosion_pos + Vector2(35, -15))
	_main._visual_feedback.play_score_popup(explosion_pos, _main.BOSS_POINTS, true)
	_main._camera.shake(8.0, 0.35)
	_main._audio_feedback.play_enemy_explosion()
	_main._add_score(_main.BOSS_POINTS)
	_main._hud.set_score(_main.score)

	# Guaranteed alternative weapon medallion reward post-boss with high magnetism
	var player: Node = _main._player
	var active_w: int = player.get_weapon() if (player != null and player.has_method(&"get_weapon")) else 0
	var alt_weapons: Array[int] = []
	for w_idx: int in range(4):
		if w_idx != active_w:
			alt_weapons.append(w_idx)
	var chosen_alt: int = alt_weapons[randi() % alt_weapons.size()]
	var loot: Area2D = _main.LOOT_DROP_SCENE.instantiate() as Area2D
	if loot != null:
		if loot.has_signal(&"collected"):
			loot.collected.connect(_main._on_loot_collected)
		if loot.has_method(&"configure"):
			loot.configure(LootDrop.Type.MEDALLION_BLASTER + chosen_alt, explosion_pos, _main._player)
		loot.set("magnet_radius", 2000.0)
		loot.set("magnet_acceleration", 1500.0)
		_main.add_child(loot)

	_main._audio_feedback.stop_boss_music()
	_main._hud.hide_boss_health_bar()
	_main._active_boss = null
	if _main._chapter < _main.TOTAL_CHAPTERS:
		begin_next_chapter()
	else:
		_main._session.complete_mission()


## Starts the next chapter: waves restart at 1 after the chapter announcement.
func begin_next_chapter() -> void:
	_main._chapter += 1
	_main._waves.perform_hyperspace_jump()
	_main._session_state = _main.SessionState.WAVE_TRANSITION
	_main._enemy_spawner.stop()
	_main._enemy_spawner.clear_formation()
	# Wave numbering is global: the next chapter continues after the boss wave.
	_main._pending_wave_index = _main.wave
	_main._wave_is_clean = true
	_main._waves.show_transition("¡CAPÍTULO %d INICIADO!" % _main._chapter)


func clear_boss() -> void:
	if is_instance_valid(_main._active_boss):
		_main._active_boss.queue_free()
	_main._active_boss = null
	for child: Node in _main.get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			child.queue_free()
