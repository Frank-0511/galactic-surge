# player_weapon_patterns.gd
# Shot layouts and damage tables of the arsenal: the Ion Blaster pattern per level, the
# missile spread offsets per level, and the Ion Blaster damage per level. Pure data.

extends RefCounted

## Ion Blaster pattern per level (index 0 = level 1). Each shot is [offset_x, angle_deg].
## Coverage metric: x300 = offset_x + 300 * tan(angle_deg), the horizontal landing spot after 300 px.
## L6 and L8-L15 keep at most 35% of shots with |x300| <= 40 and mirror-symmetric pairs. L5 and L7
## keep their legacy layout: etapa 12.5 time-to-kill windows need 3+ central hits there.
const ION_PATTERNS: Array = [
	[[0.0, 0.0]],                                                                  # L1: 1 recto
	[[-8.0, 0.0], [8.0, 0.0]],                                                     # L2: 2 rectos
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0]],                                       # L3: 3 rectos
	[[-8.0, 0.0], [8.0, 0.0], [-14.0, -8.0], [14.0, 8.0]],                         # L4: 2 rectos + 2 diagonales
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0], [-16.0, -10.0], [16.0, 10.0]],         # L5: 3 rectos + 2 diagonales
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-24.0, -24.0], [24.0, 24.0]],  # L6: 2 central + 2 diagonal pairs
	[[-12.0, 0.0], [0.0, 0.0], [12.0, 0.0], [-16.0, -9.0], [16.0, 9.0], [-20.0, -18.0], [20.0, 18.0]],  # L7: 3 rectos + 4 diag
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -34.0], [24.0, 34.0]],  # L8: 1 central pair + 3 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-26.0, -34.0], [26.0, 34.0]],  # L9: 3 central + 3 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-22.0, -22.0], [22.0, 22.0], [-26.0, -34.0], [26.0, 34.0], [-30.0, -40.0], [30.0, 40.0]],  # L10: 1 central pair + 4 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -24.0], [22.0, 24.0], [-26.0, -33.0], [26.0, 33.0], [-28.0, -40.0], [28.0, 40.0]],  # L11: 3 central + 4 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -28.0], [24.0, 28.0], [-26.0, -34.0], [26.0, 34.0], [-28.0, -40.0], [28.0, 40.0]],  # L12: 1 central pair + 5 diagonal pairs
	[[0.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-20.0, -14.0], [20.0, 14.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -28.0], [24.0, 28.0], [-26.0, -34.0], [26.0, 34.0], [-28.0, -40.0], [28.0, 40.0]],  # L13: 3 central + 5 diagonal pairs
	[[-12.0, 0.0], [12.0, 0.0], [-18.0, -12.0], [18.0, 12.0], [-20.0, -18.0], [20.0, 18.0], [-22.0, -22.0], [22.0, 22.0], [-24.0, -30.0], [24.0, 30.0], [-26.0, -36.0], [26.0, 36.0], [-28.0, -40.0], [28.0, 40.0]],  # L14: 1 central pair + 6 diagonal pairs
	[[0.0, 0.0], [-6.0, 0.0], [6.0, 0.0], [-12.0, 0.0], [12.0, 0.0], [-18.0, -10.0], [18.0, 10.0], [-22.0, -18.0], [22.0, 18.0], [-24.0, -24.0], [24.0, 24.0], [-26.0, -30.0], [26.0, 30.0], [-30.0, -40.0], [30.0, 40.0]],  # L15: 5 central + 5 diagonal pairs
]

## Damage per Ion Blaster projectile by level (index 0 = level 1): 1 up to L4, 2 up to L8, 3 at L9-L10, 3-4 at L11-L15.
const BLASTER_DAMAGE: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4]

## Missile spread x offsets per level (index 0 = level 1).
const MISSILE_OFFSETS: Array = [
	[0.0],                                    # L1
	[-14.0, 14.0],                            # L2
	[-14.0, 14.0],                            # L3 (misma cantidad, menor cooldown)
	[-16.0, 0.0, 16.0],                       # L4
	[-16.0, 0.0, 16.0],                       # L5
	[-20.0, -8.0, 8.0, 20.0],                 # L6
	[-20.0, -8.0, 8.0, 20.0],                 # L7
	[-24.0, -12.0, 0.0, 12.0, 24.0],          # L8
	[-24.0, -12.0, 0.0, 12.0, 24.0],          # L9
	[-30.0, -18.0, -6.0, 6.0, 18.0, 30.0],    # L10
	[-30.0, -18.0, -6.0, 6.0, 18.0, 30.0],    # L11 (mismo que L10)
	[-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0],    # L12
	[-36.0, -24.0, -12.0, 0.0, 12.0, 24.0, 36.0],    # L13
	[-42.0, -30.0, -18.0, -6.0, 6.0, 18.0, 30.0, 42.0],    # L14
	[-42.0, -30.0, -18.0, -6.0, 6.0, 18.0, 30.0, 42.0],    # L15
]


## Returns the damage of one Ion Blaster projectile at the given level (clamped to 1..15).
static func blaster_damage(level: int) -> int:
	return BLASTER_DAMAGE[clampi(level, 1, BLASTER_DAMAGE.size()) - 1]
