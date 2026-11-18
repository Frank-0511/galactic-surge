# player_visuals.gd
# Rendering of the player ship for one Player: the hull, delta wings, canopy in the weapon color,
# thermal muzzle glow, overheat warning pulse, engine flame and nav lights. Draw calls go through
# _player, so they run inside Player's _draw callback. Owned by Player through _player.

extends RefCounted

const MAX_TILT: float = 0.3141593  # 18 degrees: middle of the 15-20 degree banking range (Etapa 23)
const TILT_RESPONSE: float = 8.0   # how fast the ship leans toward its target tilt (1/s)

var _player: CharacterBody2D
## Current banking angle in radians, positive when leaning right. Visual only: the body never rotates.
var tilt: float = 0.0


func _init(player: CharacterBody2D) -> void:
	_player = player


## Eases the banking angle toward the lean that matches the horizontal speed.
func update_tilt(delta: float) -> void:
	var ratio: float = 0.0
	if _player.speed > 0.0:
		ratio = clampf(_player.velocity.x / _player.speed, -1.0, 1.0)
	var blend: float = 1.0 - exp(-TILT_RESPONSE * delta)
	tilt = lerpf(tilt, ratio * MAX_TILT, blend)


## Hull outline color per slot: J1 Azul Neón (default), J2 Naranja Neón (coop local).
static func hull_outline_color(player_index: int) -> Color:
	return Color(1.0, 0.6, 0.15) if player_index == 2 else Color(0.45, 0.95, 1.0)


## Accent color of the active weapon (canopy, muzzles).
func weapon_color() -> Color:
	var weapon: int = _player.current_weapon
	if weapon == _player.WeaponType.BLASTER:
		return Color(0.2, 0.6, 1.0)
	if weapon == _player.WeaponType.MISSILE:
		return Color(1.0, 0.55, 0.1)
	if weapon == _player.WeaponType.LASER:
		return Color(1.0, 0.2, 0.25)
	return Color(0.28, 0.85, 1.0)


func draw_ship() -> void:
	var heat_ratio: float = clampf(_player.heat / _player.max_heat, 0.0, 1.0)
	# Banking: rotate only the drawing, so the collision shape stays upright.
	_player.draw_set_transform(Vector2.ZERO, tilt)

	# Wide ambient glow announces silhouette.
	var glow_color: Color = Color(0.35, 0.55, 1.0, 0.14).lerp(Color(1.0, 0.3, 0.1, 0.25), heat_ratio)
	var glow: PackedVector2Array = PackedVector2Array([
		Vector2(0, -22), Vector2(-23, 12), Vector2(23, 12),
	])
	_player.draw_colored_polygon(glow, glow_color)

	# Fuselage
	var fuselage: PackedVector2Array = PackedVector2Array([
		Vector2(0, -20), Vector2(-4, -9), Vector2(-3, 3),
		Vector2(-5, 13), Vector2(0, 16), Vector2(5, 13),
		Vector2(3, 3), Vector2(4, -9),
	])
	_player.draw_colored_polygon(fuselage, Color(0.08, 0.10, 0.19))
	var fuselage_outline: PackedVector2Array = fuselage.duplicate()
	fuselage_outline.append(fuselage[0])
	var outline_color: Color = hull_outline_color(_player.player_index).lerp(Color(1.0, 0.4, 0.2), heat_ratio * 0.7)
	_player.draw_polyline(fuselage_outline, outline_color, 1.5)

	# Delta wings
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-3, -1), Vector2(-21, 9), Vector2(-15, 14), Vector2(-4, 9),
	])
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(3, -1), Vector2(21, 9), Vector2(15, 14), Vector2(4, 9),
	])
	_player.draw_colored_polygon(wing_l, Color(0.27, 0.08, 0.48))
	_player.draw_colored_polygon(wing_r, Color(0.27, 0.08, 0.48))
	var wing_l_outline: PackedVector2Array = wing_l.duplicate()
	wing_l_outline.append(wing_l[0])
	var wing_r_outline: PackedVector2Array = wing_r.duplicate()
	wing_r_outline.append(wing_r[0])
	_player.draw_polyline(wing_l_outline, Color(0.85, 0.45, 1.0), 1.25)
	_player.draw_polyline(wing_r_outline, Color(0.85, 0.45, 1.0), 1.25)

	# Wingtip fins
	_player.draw_colored_polygon(PackedVector2Array([
		Vector2(-21, 9), Vector2(-25, 15), Vector2(-17, 12),
	]), Color(0.85, 0.45, 1.0, 0.8))
	_player.draw_colored_polygon(PackedVector2Array([
		Vector2(21, 9), Vector2(25, 15), Vector2(17, 12),
	]), Color(0.85, 0.45, 1.0, 0.8))

	# Glowing canopy
	var w_color: Color = weapon_color()
	var canopy: PackedVector2Array = PackedVector2Array([
		Vector2(0, -14), Vector2(-3.5, -4), Vector2(0, 2), Vector2(3.5, -4),
	])
	_player.draw_colored_polygon(canopy, w_color)
	_player.draw_polyline(PackedVector2Array([Vector2(0, -13), Vector2(0, 1)]), w_color.lerp(Color.WHITE, 0.5), 1.0)

	# Wing-mounted cannons
	_player.draw_rect(Rect2(-22, 4, 6, 2.4), Color(0.55, 0.6, 0.68))
	_player.draw_rect(Rect2(16, 4, 6, 2.4), Color(0.55, 0.6, 0.68))

	# Cannon thermal muzzle glow
	var muzzle_color: Color = w_color.lerp(Color(1.0, 0.35, 0.1, 0.95), heat_ratio)
	_player.draw_circle(Vector2(-22, 5.2), 1.1 + 1.2 * heat_ratio, muzzle_color)
	_player.draw_circle(Vector2(22, 5.2), 1.1 + 1.2 * heat_ratio, muzzle_color)

	# Overheat warning pulse
	if _player.is_overheated:
		var warning_pulse: float = 0.5 + 0.5 * sin(_player._time * 16.0)
		_player.draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 28, Color(1.0, 0.2, 0.15, 0.65 * warning_pulse), 1.8)

	# Engines
	_player.draw_rect(Rect2(-9, 9, 4, 6), Color(0.95, 0.35, 0.12))
	_player.draw_rect(Rect2(5, 9, 4, 6), Color(0.95, 0.35, 0.12))
	_player.draw_rect(Rect2(-2.5, 12, 5, 5), Color(0.95, 0.35, 0.12))
	_player.draw_rect(Rect2(-8, 13, 2.5, 3), Color(1.0, 0.8, 0.25))
	_player.draw_rect(Rect2(5.5, 13, 2.5, 3), Color(1.0, 0.8, 0.25))
	_player.draw_rect(Rect2(-1.7, 15, 3.4, 2.5), Color(1.0, 0.8, 0.25))

	# Flickering exhaust glow
	var flicker: float = 0.7 + 0.3 * absf(sin(_player._time * 14.0)) * absf(cos(_player._time * 5.0))
	var flame_h: float = 5.0 * flicker
	_player.draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 17), Vector2(-6.5, 17 + flame_h), Vector2(-5, 17),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))
	_player.draw_colored_polygon(PackedVector2Array([
		Vector2(5, 17), Vector2(6.5, 17 + flame_h), Vector2(8, 17),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))
	_player.draw_colored_polygon(PackedVector2Array([
		Vector2(-1, 18), Vector2(0, 18 + flame_h * 1.1), Vector2(1, 18),
	]), Color(1.0, 0.85, 0.3, 0.85 * flicker))

	# Nav lights
	var blink: float = 1.0 if fmod(_player._time, 1.0) < 0.6 else 0.2
	_player.draw_circle(Vector2(-23, 12), 1.4, Color(1.0, 0.25, 0.25, blink))
	_player.draw_circle(Vector2(23, 12), 1.4, Color(0.3, 1.0, 0.4, blink))
	_player.draw_set_transform(Vector2.ZERO, 0.0)
