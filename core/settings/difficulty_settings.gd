# difficulty_settings.gd
# Difficulty tiers for a session (Etapa 18). Pure static data: the main-menu selector
# picks a tier once, and the spawner, player and score read its multipliers.

class_name DifficultySettings
extends RefCounted

enum Tier {
	CADET,
	COMMANDER,
	ELITE,
}

const _NAMES: Dictionary = {
	Tier.CADET: "Cadete",
	Tier.COMMANDER: "Comandante",
	Tier.ELITE: "Élite Galáctica",
}


## Display name of a tier, for the menu and stats panel.
static func get_tier_name(tier: int) -> String:
	return _NAMES.get(tier, "Comandante")


## Global formation speed multiplier.
static func speed_multiplier(tier: int) -> float:
	match tier:
		Tier.CADET:
			return 0.85
		Tier.ELITE:
			return 1.2
		_:
			return 1.0


## Extra formation columns added (negative removes columns).
static func density_offset(tier: int) -> int:
	match tier:
		Tier.CADET:
			return -1
		Tier.ELITE:
			return 1
		_:
			return 0


## Weapon cooling rate multiplier (above 1 cools faster).
static func cooling_multiplier(tier: int) -> float:
	match tier:
		Tier.CADET:
			return 1.25
		Tier.ELITE:
			return 0.8
		_:
			return 1.0


## Final score multiplier applied to every score gain.
static func score_multiplier(tier: int) -> float:
	match tier:
		Tier.CADET:
			return 0.75
		Tier.ELITE:
			return 1.5
		_:
			return 1.0
