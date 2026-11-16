# main_ships.gd
# Player ships of the session: local co-op (J2) activation and the damage and lives
# of each ship (Etapa 20: lives per ship, the session ends when both are out).
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


func enable_coop_local() -> void:
	if _main._player_two != null:
		return
	_main.PlayerScript.ensure_p2_input_actions()
	var packed: PackedScene = load("res://scenes/entities/player/player.tscn") as PackedScene
	_main._player_two = packed.instantiate() as CharacterBody2D
	_main._player_two.player_index = 2
	_main._player_two.bullet_scene = _main.bullet_scene
	_main._player_two.position = _main._game_layout.get_player_spawn_position() + Vector2(80.0, 0.0)
	_main.add_child(_main._player_two)
	_main._player_two.damage_requested.connect(_main._on_player_damage_requested)
	_main._player_two.weapon_level_changed.connect(func(lvl: int) -> void:
		_main._hud.set_weapon_level_p2(lvl, _main._player_two.get_weapon()))
	_main._player_two.heat_changed.connect(func(cur: float, m: float) -> void:
		_main._hud.set_heat_p2(cur, m, _main._player_two.is_weapon_overheated()))
	_main._player_two.visible = false
	_main._player_two.set_gameplay_enabled(false)
	_main._player_two_lives = _main.STARTING_LIVES


## Shows or hides J2 for a session; activating gives J2 fresh lives and a respawn.
func set_player_two_active(active: bool) -> void:
	_main._player.coop_active = active and _main._player_two != null
	if _main._player_two == null:
		return
	_main._hud.set_p2_visible(active)
	if active:
		_main.score_p2 = 0
		_main._player_two_lives = _main.STARTING_LIVES
		_main._hud.set_lives_p2(_main._player_two_lives)
		_main._hud.set_score_p2(_main.score_p2)
		_main._hud.set_weapon_level_p2(_main._player_two.get_weapon_level(), _main._player_two.get_weapon())
		_main._player_two.cooling_scale = _main._player.cooling_scale
		_main._hud.set_heat_p2(0.0, _main._player_two.max_heat, false)
		_main._player_two.respawn(_main._game_layout.get_player_spawn_position() + Vector2(80.0, 0.0))
		_main._player_two.set_gameplay_enabled(true)
	else:
		_main._player_two.reset_heat()
		_main._hud.set_heat_p2(0.0, _main._player_two.max_heat, false)
		_main._player_two.set_gameplay_enabled(false)
		_main._player_two.visible = false


func request_player_damage(player: Node2D) -> void:
	if not _main._session_active:
		return
	if player == _main._player or (player != null and player == _main._player_two):
		player.take_damage()


## ship: the ship that requested damage; null means J1 (keeps the singleplayer path).
func on_player_damage_requested(ship: Node2D = null) -> void:
	if not _main._session_active:
		return
	if ship != null and ship == _main._player_two:
		on_player_two_damage_requested()
		return
	if _main._combo_system != null and _main._combo_system.has_method(&"reset_combo"):
		_main._combo_system.reset_combo()
	_main._visual_feedback.play_damage_flash()
	_main._camera.shake(6.0, 0.2)
	if _main._camera != null and _main._camera.has_method(&"add_trauma"):
		_main._camera.add_trauma(0.55)
	_main._audio_feedback.play_player_damage()
	_main._wave_is_clean = false
	var death_pos: Vector2 = _main._player.global_position
	var lost_level: int = _main._player.penalize_weapon_on_death() if _main._player.has_method(&"penalize_weapon_on_death") else 0
	if lost_level > 0:
		spawn_recovery_capsule(death_pos)
	_main.lives -= 1
	_main._hud.set_lives(_main.lives)
	if _main.lives > 0:
		_main._player.respawn(_main._game_layout.get_player_spawn_position())
		return
	if _main._player_two != null and _main._player_two_lives > 0:
		# J1 sin vidas: sale de la partida, J2 sigue (vidas por nave).
		_main._player.set_gameplay_enabled(false)
		_main._player.visible = false
		return
	_main._session.end_session()


## J2 loses a life; the session ends only when both ships are out of lives.
func on_player_two_damage_requested() -> void:
	_main._player_two_lives -= 1
	_main._hud.set_lives_p2(_main._player_two_lives)
	if _main._player_two_lives > 0:
		_main._player_two.respawn(_main._game_layout.get_player_spawn_position() + Vector2(80.0, 0.0))
		return
	_main._player_two.set_gameplay_enabled(false)
	_main._player_two.visible = false
	if _main.lives <= 0:
		_main._session.end_session()


func spawn_recovery_capsule(spawn_pos: Vector2) -> void:
	var loot: Area2D = _main.LOOT_DROP_SCENE.instantiate() as Area2D
	if loot == null:
		return
	if loot.has_signal(&"collected"):
		loot.collected.connect(_main._on_loot_collected)
	if loot.has_method(&"configure"):
		loot.configure(LootDrop.Type.RECOVERY_CAPSULE, spawn_pos, _main._player, 3.0)
	_main.add_child(loot)
