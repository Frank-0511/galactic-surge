# net_sync_ships.gd
# Ship replication of a network match (Etapa 20 T1, S3): the host's state of J1 and J2 (position, facing, lives,
# shield and weapon level) and the client's copy of it onto its own ships and HUD lives. Moved out of
# net_sync_node.gd to keep that file under 300 lines. Stateless: static.

extends RefCounted


## Host side: the state of one ship, as sent to the client; empty when the ship does not exist.
static func ship_state(ship: CharacterBody2D, lives: int) -> Dictionary:
	if ship == null:
		return {}
	return {
		"x": ship.position.x,
		"y": ship.position.y,
		"facing": int(signf(ship.velocity.x)),
		"lives": lives,
		"shield": ship.get_shield_level(),
		"weapon_level": ship.get_weapon_level(),
	}


## Client side: copies one ship's state onto the ship and its lives onto the HUD. index is 1 for J1, 2 for J2.
static func apply_ship(main: Node2D, ship: CharacterBody2D, data: Dictionary, index: int) -> void:
	if ship == null or data.is_empty():
		return
	ship.position = Vector2(float(data["x"]), float(data["y"]))
	ship.set("facing", int(data["facing"]))
	ship.set_weapon_level(int(data["weapon_level"]))
	ship.apply_replicated_shield(int(data["shield"]))
	var lives: int = int(data["lives"])
	if index == 1:
		main.lives = lives
		main._hud.set_lives(lives)
	else:
		main._player_two_lives = lives
		main._hud.set_lives_p2(lives)
