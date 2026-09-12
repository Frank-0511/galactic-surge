# Contract harness for the Etapa 4B audio, power-ups and wave transition.
# Tasks 1 and 2: verify approved audio assets and define the red contracts
# for AudioFeedback, PowerUp, WaveAnnouncement, Player and Main integration.
extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const AUDIO_FEEDBACK_SCENE_PATH := "res://scenes/audio/audio_feedback.tscn"
const POWER_UP_SCENE_PATH := "res://scenes/powerups/power_up.tscn"
const WAVE_ANNOUNCEMENT_SCENE_PATH := "res://scenes/ui/wave_announcement.tscn"
const PLAYER_SCENE_PATH := "res://scenes/entities/player/player.tscn"

const MUSIC_PATH := "res://assets/audio/music/combat_8bit_space_shooter.mp3"

const SFX_PATHS: Array[String] = [
	"res://assets/audio/sfx/player_shoot.wav",
	"res://assets/audio/sfx/player_double_shoot.wav",
	"res://assets/audio/sfx/enemy_explosion.wav",
	"res://assets/audio/sfx/player_damage.wav",
	"res://assets/audio/sfx/pickup_double_shot.wav",
	"res://assets/audio/sfx/pickup_shield.wav",
]

const SHIELD_DURATION := 10.0
const ENEMY_DROP_CHANCE := 0.04
const CLEAR_DROP_CHANCE := 0.50

const ALLOWED_PHRASES: Array[String] = [
	"SEÑAL HOSTIL DETECTADA",
	"FORMACIÓN ENTRANTE",
	"CONTACTO EN EL RADAR",
	"ENEMIGOS APROXIMÁNDOSE",
]


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_display_configuration_contract() and passed
	passed = _assert_audio_assets_contract() and passed
	passed = _assert_audio_feedback_interface_contract() and passed
	passed = await _assert_power_up_interface_contract() and passed
	passed = _assert_wave_announcement_full_rect_contract() and passed
	passed = await _assert_wave_announcement_interface_contract() and passed
	passed = await _assert_player_power_up_api_contract() and passed
	passed = await _assert_main_integration_contract() and passed
	passed = await _assert_wave_transition_contract() and passed
	quit(0 if passed else 1)


# ---------------------------------------------------------------------------
# Task 1: approved audio assets
# ---------------------------------------------------------------------------

func _assert_display_configuration_contract() -> bool:
	var passed: bool = true
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", -1)) < 720:
		push_error("Viewport width must be at least 720")
		passed = false
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", -1)) != 960:
		push_error("Viewport height must be 960")
		passed = false
	return passed

func _assert_audio_assets_contract() -> bool:
	var passed: bool = true
	for path: String in SFX_PATHS:
		if not ResourceLoader.exists(path):
			push_error("Missing approved SFX: %s" % path)
			passed = false
		elif not (load(path) is AudioStreamWAV):
			push_error("SFX must import as AudioStreamWAV: %s" % path)
			passed = false
	if not ResourceLoader.exists(MUSIC_PATH):
		push_error("Missing approved music: %s" % MUSIC_PATH)
		passed = false
	else:
		var music_stream: AudioStream = load(MUSIC_PATH) as AudioStream
		if music_stream == null:
			push_error("Music must import as AudioStream: %s" % MUSIC_PATH)
			passed = false
	return passed


# ---------------------------------------------------------------------------
# Task 2: red contracts for 4B interfaces
# ---------------------------------------------------------------------------

func _assert_audio_feedback_interface_contract() -> bool:
	var packed_scene: PackedScene = load(AUDIO_FEEDBACK_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % AUDIO_FEEDBACK_SCENE_PATH)
		return false
	var audio_feedback: Node = packed_scene.instantiate()
	if audio_feedback == null:
		push_error("AudioFeedback scene root must be Node")
		return false
	# process_mode = 3 (always) so audio keeps running while Main is paused.
	if audio_feedback.process_mode != Node.PROCESS_MODE_ALWAYS:
		push_error("AudioFeedback process_mode must be PROCESS_MODE_ALWAYS (3)")
		audio_feedback.free()
		return false
	root.add_child(audio_feedback)
	var passed: bool = true
	# AudioFeedback must expose exactly the seven specified methods.
	for method_name: StringName in [
		&"start_combat_music",
		&"stop_combat_music",
		&"set_session_paused",
		&"play_player_shot",
		&"play_enemy_explosion",
		&"play_player_damage",
		&"play_power_up_collected",
	]:
		if not audio_feedback.has_method(method_name):
			push_error("AudioFeedback missing method: %s" % method_name)
			passed = false
	# The seven required AudioStreamPlayer children with their exact assets.
	var player_assets: Dictionary = {
		&"CombatMusic": MUSIC_PATH,
		&"PlayerShot": SFX_PATHS[0],
		&"PlayerDoubleShot": SFX_PATHS[1],
		&"EnemyExplosion": SFX_PATHS[2],
		&"PlayerDamage": SFX_PATHS[3],
		&"PickupDoubleShot": SFX_PATHS[4],
		&"PickupShield": SFX_PATHS[5],
	}
	for node_name: StringName in player_assets:
		var player: AudioStreamPlayer = audio_feedback.get_node_or_null(NodePath(node_name)) as AudioStreamPlayer
		if player == null:
			push_error("AudioFeedback missing AudioStreamPlayer: %s" % node_name)
			passed = false
			continue
		if player.stream == null or player.stream.resource_path != String(player_assets[node_name]):
			push_error("AudioFeedback %s must reference asset %s" % [node_name, player_assets[node_name]])
			passed = false
	# Combat music must loop for the whole session.
	var combat_music: AudioStreamPlayer = audio_feedback.get_node_or_null("CombatMusic") as AudioStreamPlayer
	if combat_music != null and combat_music.stream != null:
		if absf(combat_music.volume_db - (-10.89)) > 0.01:
			push_error("CombatMusic.volume_db must be -10.89 dB (got %.2f)" % combat_music.volume_db)
			passed = false
		var loop_value: Variant = combat_music.stream.get(&"loop")
		if loop_value != null and not bool(loop_value):
			push_error("CombatMusic.stream.loop must be true")
			passed = false
		if combat_music.autoplay:
			push_error("CombatMusic.autoplay must be false")
			passed = false
	# Behavioral checks: each API must drive the corresponding player.
	if combat_music != null:
		audio_feedback.call("start_combat_music")
		if not combat_music.playing:
			push_error("start_combat_music() must play CombatMusic")
			passed = false
		audio_feedback.call("set_session_paused", true)
		if not combat_music.stream_paused:
			push_error("set_session_paused(true) must pause CombatMusic stream")
			passed = false
		audio_feedback.call("set_session_paused", false)
		if combat_music.stream_paused:
			push_error("set_session_paused(false) must unpause CombatMusic stream")
			passed = false
		audio_feedback.call("stop_combat_music")
		if combat_music.playing:
			push_error("stop_combat_music() must stop CombatMusic")
			passed = false
	# Single-shot SFX behavior. PowerUp.Type does not exist yet (Task 5); the
	# enum values DOUBLE_SHOT = 0 / SHIELD = 1 are passed as ints for now.
	audio_feedback.call("play_player_shot", false)
	if not _assert_player_playing(audio_feedback, &"PlayerShot"):
		push_error("play_player_shot(false) must play PlayerShot")
		passed = false
	audio_feedback.call("play_player_shot", true)
	if not _assert_player_playing(audio_feedback, &"PlayerDoubleShot"):
		push_error("play_player_shot(true) must play PlayerDoubleShot")
		passed = false
	audio_feedback.call("play_enemy_explosion")
	if not _assert_player_playing(audio_feedback, &"EnemyExplosion"):
		push_error("play_enemy_explosion() must play EnemyExplosion")
		passed = false
	audio_feedback.call("play_player_damage")
	if not _assert_player_playing(audio_feedback, &"PlayerDamage"):
		push_error("play_player_damage() must play PlayerDamage")
		passed = false
	# PowerUp.Type values: DOUBLE_SHOT = 0, SHIELD = 1 (created in Task 5).
	audio_feedback.call("play_power_up_collected", 0)
	if not _assert_player_playing(audio_feedback, &"PickupDoubleShot"):
		push_error("play_power_up_collected(DOUBLE_SHOT) must play PickupDoubleShot")
		passed = false
	audio_feedback.call("play_power_up_collected", 1)
	if not _assert_player_playing(audio_feedback, &"PickupShield"):
		push_error("play_power_up_collected(SHIELD) must play PickupShield")
		passed = false
	root.remove_child(audio_feedback)
	audio_feedback.free()
	return passed


func _assert_player_playing(audio_feedback: Node, player_name: StringName) -> bool:
	var player: AudioStreamPlayer = audio_feedback.get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	return player != null and player.playing


func _assert_power_up_interface_contract() -> bool:
	var packed_scene: PackedScene = load(POWER_UP_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % POWER_UP_SCENE_PATH)
		return false
	var power_up: Area2D = packed_scene.instantiate() as Area2D
	if power_up == null:
		push_error("PowerUp scene root must be Area2D")
		return false
	root.add_child(power_up)
	var passed: bool = true
	# PowerUp must be a class_name'd Area2D in the combat_transients group.
	if not power_up.is_in_group(&"combat_transients"):
		push_error("PowerUp must be in the combat_transients group")
		passed = false
	if power_up.get_script() == null or not power_up.get_script().is_class("GDScript"):
		passed = false
	# PowerUp must declare the enum Type and the signal collected.
	if not power_up.has_signal(&"collected"):
		push_error("PowerUp missing signal: collected")
		passed = false
	# PowerUp must expose configure and get_type.
	for method_name: StringName in [&"configure", &"get_type"]:
		if not power_up.has_method(method_name):
			push_error("PowerUp missing method: %s" % method_name)
			passed = false
	# PowerUp must have a CollisionShape2D child.
	if power_up.get_node_or_null("CollisionShape2D") == null:
		push_error("PowerUp must have a CollisionShape2D child")
		passed = false

	# --- Behavioural contracts (Step 1 of Task 5) ---

	# configure() must place the pickup at the requested position.
	if power_up.has_method(&"configure") and power_up.has_method(&"get_type"):
		power_up.call("configure", 0, Vector2(300, 100))
		if power_up.global_position.distance_to(Vector2(300, 100)) > 0.5:
			push_error("PowerUp.configure() must set global_position")
			passed = false

		# After 0.5s of processing the y position must increase (fall downward).
		var y_before: float = power_up.global_position.y
		var fall_timer: SceneTreeTimer = create_timer(0.5)
		await fall_timer.timeout
		if power_up.global_position.y <= y_before:
			push_error("PowerUp must fall downward over time")
			passed = false

		# Must auto-free when it falls below the viewport.
		power_up.global_position = Vector2(300, 5000)
		await create_timer(0.1).timeout
		if is_instance_valid(power_up):
			push_error("PowerUp must free itself when below the viewport")
			passed = false

	# collected signal must fire exactly once on player contact.
	var pu2: Area2D = packed_scene.instantiate() as Area2D
	if pu2 != null:
		root.add_child(pu2)
		if pu2.has_method(&"configure"):
			pu2.call("configure", 0, Vector2(300, 400))
		var collect_count: Array[int] = [0]
		if pu2.has_signal(&"collected"):
			pu2.collected.connect(func(_t: int) -> void: collect_count[0] += 1)
		# Create a player-grouped body and drive body_entered directly.
		var fake_player: CharacterBody2D = CharacterBody2D.new()
		fake_player.add_to_group(&"player", true)
		root.add_child(fake_player)
		pu2.set("fall_speed", 0.0)
		await physics_frame
		# Call the handler directly; physics overlap is unreliable headless.
		pu2.call("_on_body_entered", fake_player)
		await physics_frame
		fake_player.queue_free()
		if is_instance_valid(pu2):
			pu2.queue_free()
		if collect_count[0] != 1:
			push_error("PowerUp must emit collected exactly once, got %d" % collect_count[0])
			passed = false
	else:
		root.remove_child(power_up)
		power_up.free()
		return passed

	if is_instance_valid(power_up):
		root.remove_child(power_up)
		power_up.free()
	return passed


func _assert_wave_announcement_full_rect_contract() -> bool:
	# Task 3 red contract: the WaveAnnouncement Control layer must cover the
	# whole viewport with full anchors and zero offsets, so the announcement
	# no longer depends on the historical 600x800 rect.
	var packed_scene: PackedScene = load(WAVE_ANNOUNCEMENT_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % WAVE_ANNOUNCEMENT_SCENE_PATH)
		return false
	var announcement: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if announcement == null:
		push_error("WaveAnnouncement scene root must be CanvasLayer")
		return false
	root.add_child(announcement)
	var passed: bool = true
	var control: Control = announcement.get_node_or_null("Control") as Control
	if control == null:
		push_error("WaveAnnouncement missing Control layer")
		passed = false
	else:
		if control.anchor_right != 1.0 or control.anchor_bottom != 1.0:
			push_error("WaveAnnouncement Control must fill the viewport with full anchors")
			passed = false
		if control.offset_left != 0.0 or control.offset_top != 0.0 \
				or control.offset_right != 0.0 or control.offset_bottom != 0.0:
			push_error("WaveAnnouncement Control must not retain 600x800 offsets")
			passed = false
	root.remove_child(announcement)
	announcement.free()
	return passed


func _assert_wave_announcement_interface_contract() -> bool:
	var packed_scene: PackedScene = load(WAVE_ANNOUNCEMENT_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % WAVE_ANNOUNCEMENT_SCENE_PATH)
		return false
	var announcement: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if announcement == null:
		push_error("WaveAnnouncement scene root must be CanvasLayer")
		return false
	root.add_child(announcement)
	var passed: bool = true
	# WaveAnnouncement must use process_mode = 3 (always) so it can finish while paused.
	if announcement.process_mode != Node.PROCESS_MODE_ALWAYS:
		push_error("WaveAnnouncement process_mode must be PROCESS_MODE_ALWAYS (3)")
		passed = false
	# Required signal and methods.
	if not announcement.has_signal(&"announcement_finished"):
		push_error("WaveAnnouncement missing signal: announcement_finished")
		passed = false
	for method_name: StringName in [&"show_announcement", &"cancel_announcement"]:
		if not announcement.has_method(method_name):
			push_error("WaveAnnouncement missing method: %s" % method_name)
			passed = false
	# Required node structure.
	for node_path: String in ["Control/WaveLabel", "Control/RadarLabel", "Control/ReadyLabel"]:
		if announcement.get_node_or_null(node_path) == null:
			push_error("WaveAnnouncement missing node: %s" % node_path)
			passed = false
	# Must accept display_duration property.
	if "display_duration" not in announcement:
		push_error("WaveAnnouncement missing property: display_duration")
		passed = false

	# --- Behavioural contracts (Step 1 of Task 6) ---

	# After show_announcement(2, "CONTACTO EN EL RADAR"), the panel must be visible
	# and the three labels must show exact texts.
	if announcement.has_method(&"show_announcement"):
		announcement.call("show_announcement", 2, "CONTACTO EN EL RADAR")
		if not announcement.visible:
			push_error("WaveAnnouncement must be visible after show_announcement()")
			passed = false
		var wave_label: Label = announcement.get_node_or_null("Control/WaveLabel") as Label
		var radar_label: Label = announcement.get_node_or_null("Control/RadarLabel") as Label
		var ready_label: Label = announcement.get_node_or_null("Control/ReadyLabel") as Label
		if wave_label != null and wave_label.text != "OLEADA 2":
			push_error("WaveLabel must show 'OLEADA 2', got '%s'" % wave_label.text)
			passed = false
		if radar_label != null and radar_label.text != "CONTACTO EN EL RADAR":
			push_error("RadarLabel must show the phrase, got '%s'" % radar_label.text)
			passed = false
		if ready_label != null and ready_label.text != "¡PREPÁRATE!":
			push_error("ReadyLabel must show '¡PREPÁRATE!', got '%s'" % ready_label.text)
			passed = false

		# With display_duration = 0.0, the next frame must emit announcement_finished once.
		var finish_count: Array[int] = [0]
		if announcement.has_signal(&"announcement_finished"):
			announcement.announcement_finished.connect(func() -> void: finish_count[0] += 1)
		announcement.set("display_duration", 0.0)
		announcement.call("show_announcement", 3, "FORMACIÓN ENTRANTE")
		await process_frame
		await process_frame
		if finish_count[0] != 1:
			push_error("WaveAnnouncement must emit announcement_finished exactly once, got %d" % finish_count[0])
			passed = false

		# cancel_announcement() must hide the panel and prevent late emission.
		var late_count: Array[int] = [0]
		if announcement.has_signal(&"announcement_finished"):
			announcement.announcement_finished.connect(func() -> void: late_count[0] += 1)
		announcement.set("display_duration", 1.0)
		announcement.call("show_announcement", 4, "ENEMIGOS APROXIMÁNDOSE")
		announcement.call("cancel_announcement")
		if announcement.visible:
			push_error("WaveAnnouncement must be invisible after cancel_announcement()")
			passed = false
		await create_timer(0.2).timeout
		if late_count[0] != 0:
			push_error("cancel_announcement() must prevent late announcement_finished emission, got %d" % late_count[0])
			passed = false

	root.remove_child(announcement)
	announcement.free()
	return passed


func _assert_player_power_up_api_contract() -> bool:
	var packed_scene: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % PLAYER_SCENE_PATH)
		return false
	var player: Node2D = packed_scene.instantiate() as Node2D
	if player == null:
		push_error("Player scene root must be Node2D")
		return false
	root.add_child(player)
	await process_frame
	var passed: bool = true
	# Player must expose the six power-up APIs.
	for method_name: StringName in [
		&"enable_double_shot",
		&"disable_double_shot",
		&"has_double_shot",
		&"activate_shield",
		&"has_shield",
		&"clear_power_ups",
	]:
		if not player.has_method(method_name):
			push_error("Player missing 4B API: %s" % method_name)
			passed = false
	# Player must emit shot_fired when shooting.
	if not player.has_signal(&"shot_fired"):
		push_error("Player missing 4B signal: shot_fired")
		passed = false
	root.remove_child(player)
	player.free()
	return passed


# ---------------------------------------------------------------------------
# Task 2: red contracts for Main integration
# ---------------------------------------------------------------------------

func _assert_main_integration_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	await process_frame
	var passed: bool = true

	# Main must own the new 4B drop-chance properties (legacy 4B).
	# In Etapa 6+, power-up drops are superseded by the LootDrop system (enemy_loot_drop_chance).
	if "enemy_loot_drop_chance" not in main:
		if "enemy_drop_chance" not in main:
			push_error("Main missing property: enemy_drop_chance")
			passed = false
		else:
			if absf(float(main.get("enemy_drop_chance")) - ENEMY_DROP_CHANCE) > 0.001:
				push_error("Main enemy_drop_chance must default to %f" % ENEMY_DROP_CHANCE)
				passed = false
		if "clear_wave_drop_chance" not in main:
			push_error("Main missing property: clear_wave_drop_chance")
			passed = false
		else:
			if absf(float(main.get("clear_wave_drop_chance")) - CLEAR_DROP_CHANCE) > 0.001:
				push_error("Main clear_wave_drop_chance must default to %f" % CLEAR_DROP_CHANCE)
				passed = false

	# Main must instantiate AudioFeedback and WaveAnnouncement.
	if main.get_node_or_null("AudioFeedback") == null:
		push_error("Main must have an AudioFeedback child")
		passed = false
	if main.get_node_or_null("WaveAnnouncement") == null:
		push_error("Main must have a WaveAnnouncement child")
		passed = false

	# Session integration: requires Main.start_session() and the 4B APIs to exist.
	if main.has_method("start_session"):
		main.call("start_session")
		await process_frame

		# Combat music must be active after starting a session.
		var audio_feedback: Node = main.get_node_or_null("AudioFeedback")
		if audio_feedback != null:
			var combat_music: AudioStreamPlayer = audio_feedback.get_node_or_null("CombatMusic") as AudioStreamPlayer
			if combat_music != null and not combat_music.playing:
				push_error("CombatMusic must be playing after start_session()")
				passed = false

		# A single shot must create exactly one bullet.
		var player: Node2D = main.get_node_or_null("Player") as Node2D
		if player != null and player.has_method(&"enable_double_shot"):
			var transient_before: int = _count_combat_transients(main)
			# Trigger a single shot through the player's shot mechanism.
			if player.has_method(&"simulate_shot"):
				player.call("simulate_shot")
			await process_frame
			var transient_after_single: int = _count_combat_transients(main)
			if transient_after_single - transient_before != 1:
				push_error("Single shot must create exactly one bullet, got %d" % (transient_after_single - transient_before))
				passed = false

			# Double shot must create exactly two bullets.
			player.call("enable_double_shot")
			var transient_before_double: int = _count_combat_transients(main)
			if player.has_method(&"simulate_shot"):
				player.call("simulate_shot")
			await process_frame
			var transient_after_double: int = _count_combat_transients(main)
			if transient_after_double - transient_before_double != 2:
				push_error("Double shot must create exactly two bullets, got %d" % (transient_after_double - transient_before_double))
				passed = false

		# Shield must block damage and then expire.
		if player != null and player.has_method(&"activate_shield"):
			# End any respawn invulnerability so take_damage() depends only on the shield.
			var invuln_timer: Timer = player.get_node_or_null("InvulnerabilityTimer") as Timer
			if invuln_timer != null and not invuln_timer.is_stopped():
				invuln_timer.wait_time = 0.01
				invuln_timer.start()
				await create_timer(0.02).timeout
			player.call("activate_shield", SHIELD_DURATION)
			if player.has_method(&"has_shield") and not bool(player.call("has_shield")):
				push_error("Player must report shield active after activate_shield()")
				passed = false
			if player.has_method(&"take_damage"):
				var damage_result: bool = bool(player.call("take_damage"))
				if damage_result:
					push_error("take_damage() must return false while shield is active")
					passed = false
			# Fast-forward the shield timer to expiry.
			var shield_timer: Timer = player.get_node_or_null("ShieldTimer") as Timer
			if shield_timer != null:
				shield_timer.wait_time = 0.05
				shield_timer.start()
				await create_timer(0.06).timeout
				if player.has_method(&"has_shield") and bool(player.call("has_shield")):
					push_error("Shield must expire after its duration")
					passed = false
				if player.has_method(&"take_damage"):
					var damage_after_expire: bool = bool(player.call("take_damage"))
					if not damage_after_expire:
						push_error("take_damage() must return true after shield expires")
						passed = false

		# Legacy 4B power-up drop assertions (superseded in Etapa 6+ by LootDrop).
		if "enemy_loot_drop_chance" not in main:
			# Enemy drop at 100% chance must create exactly one pickup.
			if "enemy_drop_chance" in main:
				main.set("enemy_drop_chance", 1.0)
				var pickups_before: int = _count_power_ups(main)
				_destroy_one_enemy(main)
				await process_frame
				await process_frame
				var pickups_after_enemy: int = _count_power_ups(main)
				if pickups_after_enemy - pickups_before != 1:
					push_error("enemy_drop_chance = 1.0 must create exactly one pickup, got %d" % (pickups_after_enemy - pickups_before))
					passed = false
				# A second enemy destroyed in the same wave must NOT create a second pickup.
				var pickups_before_second: int = _count_power_ups(main)
				_destroy_one_enemy(main)
				await process_frame
				await process_frame
				var pickups_after_second: int = _count_power_ups(main)
				if pickups_after_second - pickups_before_second != 0:
					push_error("Only one power-up may drop per wave")
					passed = false

			# Clear-wave fallback drop at 100% with no prior drop must create exactly one.
			if main.has_method("reset_session"):
				main.call("reset_session")
				await process_frame
			if "enemy_drop_chance" in main and "clear_wave_drop_chance" in main:
				main.set("enemy_drop_chance", 0.0)
				main.set("clear_wave_drop_chance", 1.0)
				var pickups_before_clear: int = _count_power_ups(main)
				_clear_current_wave(main)
				await process_frame
				await process_frame
				var pickups_after_clear: int = _count_power_ups(main)
				if pickups_after_clear - pickups_before_clear != 1:
					push_error("clear_wave_drop_chance = 1.0 must create exactly one pickup, got %d" % (pickups_after_clear - pickups_before_clear))
					passed = false

				# The clear-wave fallback must use GameLayout, not the historical Vector2(300, 160).
				var main_source: String = FileAccess.get_file_as_string("res://scenes/main/main.gd")
				if main_source.contains("Vector2(300, 160)"):
					push_error("Main must not use the historical Vector2(300, 160) for the fallback drop")
					passed = false
				if not main_source.contains("get_power_up_fallback_position()"):
					push_error("Main must use GameLayout.get_power_up_fallback_position() for the fallback drop")
					passed = false

		# return_to_main_menu must clean up everything.
		if main.has_method("return_to_main_menu"):
			main.call("return_to_main_menu")
			await process_frame
			if _count_combat_transients(main) != 0:
				push_error("return_to_main_menu() must clear all combat_transients")
				passed = false
			if _count_power_ups(main) != 0:
				push_error("return_to_main_menu() must clear all power-ups")
				passed = false
			var audio_after_menu: Node = main.get_node_or_null("AudioFeedback")
			if audio_after_menu != null:
				var combat_music_after: AudioStreamPlayer = audio_after_menu.get_node_or_null("CombatMusic") as AudioStreamPlayer
				if combat_music_after != null and combat_music_after.playing:
					push_error("return_to_main_menu() must stop combat music")
					passed = false
			var announcement_after_menu: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
			if announcement_after_menu != null and announcement_after_menu.visible:
				push_error("return_to_main_menu() must hide the wave announcement")
				passed = false
			if player != null and player.has_method(&"has_double_shot") and bool(player.call("has_double_shot")):
				push_error("return_to_main_menu() must clear double shot")
				passed = false
			if player != null and player.has_method(&"has_shield") and bool(player.call("has_shield")):
				push_error("return_to_main_menu() must clear shield")
				passed = false

	if paused:
		paused = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_wave_transition_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	await process_frame
	var passed: bool = true

	if main.has_method("start_session"):
		main.call("start_session")
		await process_frame

		var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
		if announcement == null:
			push_error("Main missing WaveAnnouncement for transition test")
			passed = false
		else:
			# Use zero-duration announcement so it finishes on the next frame.
			if "display_duration" in announcement:
				announcement.set("display_duration", 0.0)
			if "enemy_loot_drop_chance" in main:
				main.set("enemy_loot_drop_chance", 0.0)
			# Observation 1: after clearing wave 1 and one frame, the transition is
			# still active: wave 1, visible announcement, and no enemies.
			_clear_current_wave(main)
			await process_frame
			if int(main.get("wave")) != 1:
				push_error("Wave must remain 1 during transition, got %d" % int(main.get("wave")))
				passed = false
			var spawner: Node = main.get_node_or_null("EnemySpawner")
			if spawner != null and _count_enemies(spawner) != 0:
				push_error("No enemies must exist during the wave transition")
				passed = false
			if not announcement.visible:
				push_error("WaveAnnouncement must be visible during the transition")
				passed = false
			# Observation 2: one additional frame must complete the announcement,
			# advance to wave 2, and create its enemies before this assertion.
			await process_frame
			if int(main.get("wave")) != 2:
				push_error("Wave must advance to 2 after announcement_finished, got %d" % int(main.get("wave")))
				passed = false
			if spawner != null and _count_enemies(spawner) <= 0:
				push_error("Wave 2 enemies must appear after the announcement finishes")
				passed = false
			# The radar phrase must be one of the four allowed phrases.
			var radar_label: Label = announcement.get_node_or_null("Control/RadarLabel") as Label
			if radar_label != null and not ALLOWED_PHRASES.has(radar_label.text):
				push_error("Radar phrase must be one of the allowed set, got: %s" % radar_label.text)
				passed = false

			# Repeat: clear wave 2 and cancel the announcement via return_to_main_menu.
			_clear_current_wave(main)
			await process_frame
			if int(main.get("wave")) != 2:
				push_error("Wave must remain 2 during second transition")
				passed = false
			if main.has_method("return_to_main_menu"):
				main.call("return_to_main_menu")
				await process_frame
				await process_frame
				if spawner != null and _count_enemies(spawner) != 0:
					push_error("return_to_main_menu() during announcement must not spawn enemies")
					passed = false
				if announcement.visible:
					push_error("return_to_main_menu() during announcement must hide it")
					passed = false

	if paused:
		paused = false
	root.remove_child(main)
	main.free()
	return passed


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _count_combat_transients(root_node: Node) -> int:
	return root_node.get_tree().get_nodes_in_group("combat_transients").size()


func _count_power_ups(root_node: Node) -> int:
	var count: int = 0
	for node: Node in root_node.get_tree().get_nodes_in_group("combat_transients"):
		if is_instance_valid(node) and node is Area2D and node.get_script() != null:
			if node.get_script().get_global_name() == "PowerUp":
				count += 1
	return count


func _count_enemies(spawner: Node) -> int:
	var enemy_count: int = 0
	for child: Node in spawner.get_children():
		if child.is_in_group("enemies"):
			enemy_count += 1
	return enemy_count


func _destroy_one_enemy(main: Node2D) -> void:
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	var enemies: Array[Area2D] = _get_formation_enemies(spawner)
	if enemies.is_empty():
		return
	var first_enemy: Area2D = enemies[0]
	if is_instance_valid(first_enemy) and first_enemy.has_method("destroy"):
		first_enemy.destroy()


func _clear_current_wave(main: Node2D) -> void:
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	var enemies: Array[Area2D] = _get_formation_enemies(spawner)
	for enemy: Area2D in enemies:
		if is_instance_valid(enemy) and enemy.has_method("destroy"):
			enemy.destroy()
	await create_timer(0.0).timeout


func _get_formation_enemies(spawner: Node2D) -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in spawner.get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies
