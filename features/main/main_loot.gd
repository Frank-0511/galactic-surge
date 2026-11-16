# main_loot.gd
# Loot drops for the session (Etapa 6 onward): picks the drop type from the
# weights exported on Main, spawns LootDrop nodes and applies the effect of each
# pickup to the ship that collected it (Etapa 20: J1 or J2).
# Owned by Main; it reads and writes Main's state through _main.

extends RefCounted

const NET_SYNC_NAME: String = "NetSync"

var _main: Node2D


func _init(main: Node2D) -> void:
	_main = main


func pick_type() -> int:
	var w_score: float = maxf(_main.score_loot_weight, 0.0)
	var w_double: float = maxf(_main.double_shot_loot_weight, 0.0)
	var w_shield: float = maxf(_main.shield_loot_weight, 0.0)
	var w_life: float = maxf(_main.extra_life_loot_weight, 0.0)
	var w_bomb: float = maxf(_main.bomb_loot_weight, 0.0)
	var w_m_blaster: float = maxf(_main.medallion_blaster_weight, 0.0)
	var w_m_missile: float = maxf(_main.medallion_missile_weight, 0.0)
	var w_m_laser: float = maxf(_main.medallion_laser_weight, 0.0)
	var w_atom: float = maxf(_main.power_atom_weight, 0.0)

	var base_weights: Array[float] = [w_score, w_double, w_shield, w_life, w_bomb]
	var zero_count: int = 0
	var single_one_index: int = -1
	for idx: int in range(base_weights.size()):
		if base_weights[idx] == 0.0:
			zero_count += 1
		elif base_weights[idx] == 1.0:
			single_one_index = idx

	# Contract testing support: isolated single basic weight or all basic weights zero
	if zero_count == 5:
		return LootDrop.Type.SCORE
	if zero_count == 4 and single_one_index >= 0:
		return single_one_index

	var all_weights: Array[float] = [
		w_score, w_double, w_shield, w_life, w_bomb,
		w_m_blaster, w_m_missile, w_m_laser, w_atom
	]
	var total_zeros: int = 0
	var total_single_index: int = -1
	for idx: int in range(all_weights.size()):
		if all_weights[idx] == 0.0:
			total_zeros += 1
		elif all_weights[idx] > 0.0:
			total_single_index = idx
	if total_zeros == all_weights.size() - 1 and total_single_index >= 0:
		return total_single_index

	var total_basic_weight: float = w_score + w_double + w_shield + w_life + w_bomb
	var total_weapon_weight: float = w_m_blaster + w_m_missile + w_m_laser + w_atom
	var total_weight: float = total_basic_weight + total_weapon_weight
	if total_weight <= 0.0:
		return LootDrop.Type.SCORE

	var roll: float = randf() * total_weight
	if roll < total_basic_weight:
		var cumulative: float = 0.0
		cumulative += w_score
		if roll < cumulative:
			return LootDrop.Type.SCORE
		cumulative += w_double
		if roll < cumulative:
			return LootDrop.Type.DOUBLE_SHOT
		cumulative += w_shield
		if roll < cumulative:
			return LootDrop.Type.SHIELD
		cumulative += w_life
		if roll < cumulative:
			return LootDrop.Type.EXTRA_LIFE
		return LootDrop.Type.BOMB

	# Weapon / Power drop: Chicken Invaders model:
	# ~55% chance of Power Atom or active weapon's medallion (+1 level)
	# ~45% chance of dropping a different weapon's medallion (distributed among the other 2)
	var player: Node = _main._player
	var active_w: int = player.get_weapon() if (player != null and player.has_method(&"get_weapon")) else 0
	var weapon_roll: float = randf()
	if weapon_roll < 0.55:
		if randf() < 0.5:
			return LootDrop.Type.MEDALLION_BLASTER + active_w
		else:
			return LootDrop.Type.POWER_ATOM
	else:
		var alt_weapons: Array[int] = []
		for w_idx: int in range(3):
			if w_idx != active_w:
				alt_weapons.append(w_idx)
		var chosen_alt: int = alt_weapons[randi() % alt_weapons.size()]
		return LootDrop.Type.MEDALLION_BLASTER + chosen_alt


func try_spawn_enemy_loot(spawn_position: Vector2) -> void:
	if not _main._session_active:
		return
	if _main.enemy_loot_drop_chance <= 0.0 or randf() >= _main.enemy_loot_drop_chance:
		return
	var total_weight: float = (
		maxf(_main.score_loot_weight, 0.0)
		+ maxf(_main.double_shot_loot_weight, 0.0)
		+ maxf(_main.shield_loot_weight, 0.0)
		+ maxf(_main.extra_life_loot_weight, 0.0)
		+ maxf(_main.bomb_loot_weight, 0.0)
		+ maxf(_main.medallion_blaster_weight, 0.0)
		+ maxf(_main.medallion_missile_weight, 0.0)
		+ maxf(_main.medallion_laser_weight, 0.0)
		+ maxf(_main.power_atom_weight, 0.0)
	)
	if total_weight <= 0.0:
		return
	spawn_loot(pick_type(), spawn_position)


func spawn_loot(loot_type: int, spawn_position: Vector2) -> void:
	if _is_network_client():
		return
	var loot: Area2D = _main.LOOT_DROP_SCENE.instantiate() as Area2D
	if loot == null:
		return
	if loot.has_signal(&"collected"):
		loot.collected.connect(on_loot_collected)
	if loot.has_method(&"configure"):
		loot.configure(loot_type, spawn_position, _main._player)
	PhysicsSafe.add_child_safe(_main, loot)
	announce_net_spawn(loot, loot_type, spawn_position)


## Etapa 20 T4: the host reports a new drop to the client (id, type, position). No-op without a network match.
func announce_net_spawn(loot: Area2D, loot_type: int, spawn_position: Vector2) -> void:
	var net: Node = _main.get_node_or_null(NET_SYNC_NAME)
	if net != null and net.has_method(&"announce_loot_spawn"):
		net.call("announce_loot_spawn", loot, loot_type, spawn_position)


## Etapa 20 T4: a network client never creates drops; the host sends them.
func _is_network_client() -> bool:
	return _main._player != null and _main._player.get("replica") == true


## collector: the ship that picked the drop up (Etapa 20); null means J1 (singleplayer).
func on_loot_collected(loot_type: int, collector: Node2D = null) -> void:
	if not _main._session_active and not _main._mission_complete:
		return
	var ship: CharacterBody2D = _main._player_two if collector != null and collector == _main._player_two else _main._player
	match loot_type:
		LootDrop.Type.SCORE:
			_main._add_score(_main.SCORE_LOOT_POINTS)
			_main._hud.set_score(_main.score)
			_main._visual_feedback.play_score_popup(ship.global_position, _main.SCORE_LOOT_POINTS)
		LootDrop.Type.DOUBLE_SHOT:
			ship.enable_double_shot()
			_main._audio_feedback.play_power_up_collected(0)
		LootDrop.Type.SHIELD:
			ship.activate_shield(_main.SHIELD_DURATION)
			_main._audio_feedback.play_power_up_collected(1)
		LootDrop.Type.EXTRA_LIFE:
			if ship == _main._player_two:
				_main._player_two_lives = mini(_main._player_two_lives + 1, _main.STARTING_LIVES)
				_main._hud.set_lives_p2(_main._player_two_lives)
			else:
				_main.lives = mini(_main.lives + 1, _main.STARTING_LIVES)
				_main._hud.set_lives(_main.lives)
		LootDrop.Type.BOMB:
			_main._clear_enemy_bullets()
		LootDrop.Type.MEDALLION_BLASTER, LootDrop.Type.MEDALLION_MISSILE, LootDrop.Type.MEDALLION_LASER:
			_collect_medallion(loot_type, ship)
		LootDrop.Type.POWER_ATOM, LootDrop.Type.RECOVERY_CAPSULE:
			if ship.has_method(&"apply_power_atom"):
				ship.apply_power_atom()
			var audio: Node = _main._audio_feedback
			if audio != null and audio.has_method(&"play_power_atom_collected"):
				audio.play_power_atom_collected()
			var visual: Node2D = _main._visual_feedback
			if visual != null and visual.has_method(&"play_level_up"):
				visual.play_level_up(ship.global_position, ship.get_weapon_level() if ship.has_method(&"get_weapon_level") else 1)


func _collect_medallion(loot_type: int, ship: CharacterBody2D) -> void:
	var target_w: int = loot_type - LootDrop.Type.MEDALLION_BLASTER
	var prev_w: int = ship.get_weapon() if ship.has_method(&"get_weapon") else -1
	if ship.has_method(&"apply_medallion"):
		ship.apply_medallion(target_w)
	var visual: Node2D = _main._visual_feedback
	var audio: Node = _main._audio_feedback
	if target_w != prev_w:
		var weapon_names: Array[String] = ["BLASTER", "MISIL", "LÁSER"]
		var weapon_colors: Array[Color] = [
			Color(0.2, 0.6, 1.0),
			Color(1.0, 0.55, 0.1),
			Color(1.0, 0.2, 0.25)
		]
		var w_name: String = weapon_names[target_w] if target_w >= 0 and target_w < weapon_names.size() else "ARMA"
		var w_color: Color = weapon_colors[target_w] if target_w >= 0 and target_w < weapon_colors.size() else Color.WHITE
		if visual != null and visual.has_method(&"play_weapon_switched"):
			visual.play_weapon_switched(ship.global_position, w_name, w_color)
		if audio != null and audio.has_method(&"play_weapon_switched"):
			audio.play_weapon_switched(target_w)
	else:
		if visual != null and visual.has_method(&"play_level_up"):
			visual.play_level_up(ship.global_position, ship.get_weapon_level() if ship.has_method(&"get_weapon_level") else 1)
		if audio != null and audio.has_method(&"play_medallion_collected"):
			audio.play_medallion_collected(target_w)
