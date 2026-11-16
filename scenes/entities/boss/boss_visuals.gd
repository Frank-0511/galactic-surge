# boss_visuals.gd
# Drawing of the Nexus mothership (chapter 1 look) and the dive telegraph warning ring shared with the
# other variants. Called from Boss._draw() and owned by Boss through _boss; the drawing calls go to the
# Boss canvas item.

extends RefCounted

var _boss: Area2D


func _init(boss: Area2D) -> void:
	_boss = boss


## Nexus mothership: hull, armored wings, twin plasma cannons, central reactor and hit flash.
func draw_nexus() -> void:
	var pulse_speed: float = 9.0 if _boss.is_enraged else 4.0
	if _boss._state == _boss.MovementState.DIVE_TELEGRAPH:
		pulse_speed = 22.0
	var core_pulse: float = 0.5 + 0.5 * sin(_boss._time * pulse_speed)

	var neon_primary: Color = Color(1.0, 0.22, 0.48) if _boss.is_enraged else Color(0.22, 0.9, 1.0)
	var neon_secondary: Color = Color(1.0, 0.6, 0.1) if _boss.is_enraged else Color(0.68, 0.28, 1.0)
	var hull_color: Color = Color(0.08, 0.04, 0.16)

	# 0. Dive telegraph threat warning pulse
	if _boss._state == _boss.MovementState.DIVE_TELEGRAPH:
		var warn_color: Color = Color(1.0, 0.2, 0.35, 0.55 + 0.35 * sin(_boss._time * 24.0))
		_boss.draw_arc(Vector2.ZERO, 72.0 + 8.0 * sin(_boss._time * 16.0), 0.0, TAU, 32, warn_color, 3.5)
		_boss.draw_circle(Vector2.ZERO, 85.0, Color(1.0, 0.1, 0.2, 0.12))

	# 1. Soft atmospheric threat glow
	_boss.draw_circle(Vector2.ZERO, 65.0 + 8.0 * core_pulse, Color(neon_primary.r, neon_primary.g, neon_primary.b, 0.12 + 0.08 * core_pulse))

	# 2. Main mothership hull polygon (approx 140x70)
	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(0, -32),
		Vector2(28, -26),
		Vector2(55, -16),
		Vector2(70, 0),
		Vector2(65, 20),
		Vector2(45, 30),
		Vector2(32, 22),
		Vector2(20, 34),
		Vector2(0, 36),
		Vector2(-20, 34),
		Vector2(-32, 22),
		Vector2(-45, 30),
		Vector2(-65, 20),
		Vector2(-70, 0),
		Vector2(-55, -16),
		Vector2(-28, -26),
	])
	_boss.draw_colored_polygon(hull, hull_color)

	# Hull outline glow
	var hull_loop: PackedVector2Array = hull.duplicate()
	hull_loop.append(hull[0])
	_boss.draw_polyline(hull_loop, neon_primary, 2.0)

	# 3. Outer armored wing panels
	var wing_left: PackedVector2Array = PackedVector2Array([
		Vector2(-28, -12), Vector2(-58, -6), Vector2(-66, 12), Vector2(-36, 16),
	])
	var wing_right: PackedVector2Array = PackedVector2Array([
		Vector2(28, -12), Vector2(58, -6), Vector2(66, 12), Vector2(36, 16),
	])
	_boss.draw_colored_polygon(wing_left, Color(0.14, 0.08, 0.26))
	_boss.draw_colored_polygon(wing_right, Color(0.14, 0.08, 0.26))
	var wing_left_loop: PackedVector2Array = wing_left.duplicate()
	wing_left_loop.append(wing_left[0])
	var wing_right_loop: PackedVector2Array = wing_right.duplicate()
	wing_right_loop.append(wing_right[0])
	_boss.draw_polyline(wing_left_loop, neon_secondary, 1.4)
	_boss.draw_polyline(wing_right_loop, neon_secondary, 1.4)

	# 4. Twin heavy plasma cannons
	_boss.draw_line(Vector2(-36, 12), Vector2(-36, 32), neon_primary, 3.5)
	_boss.draw_line(Vector2(36, 12), Vector2(36, 32), neon_primary, 3.5)
	_boss.draw_circle(Vector2(-36, 32), 3.0, neon_primary)
	_boss.draw_circle(Vector2(36, 32), 3.0, neon_primary)

	# 5. Central Nexus reactor core
	var core_radius: float = 12.0 + 3.0 * core_pulse
	_boss.draw_circle(Vector2.ZERO, core_radius + 4.0, Color(neon_primary.r, neon_primary.g, neon_primary.b, 0.35))
	_boss.draw_circle(Vector2.ZERO, core_radius, neon_primary)
	_boss.draw_circle(Vector2.ZERO, core_radius * 0.55, Color(1.0, 1.0, 1.0, 0.95))

	# 6. Hit flash overlay
	if _boss._hit_flash_time > 0.0:
		var flash_alpha: float = clampf(_boss._hit_flash_time / 0.12, 0.0, 1.0) * 0.75
		_boss.draw_colored_polygon(hull, Color(1.0, 1.0, 1.0, flash_alpha))


## Dive telegraph warning ring shared by the Espectro and Núcleo Blindado looks.
func draw_dive_warning() -> void:
	if _boss._state != _boss.MovementState.DIVE_TELEGRAPH:
		return
	var warn_color: Color = Color(1.0, 0.2, 0.35, 0.55 + 0.35 * sin(_boss._time * 24.0))
	_boss.draw_arc(Vector2.ZERO, 72.0 + 8.0 * sin(_boss._time * 16.0), 0.0, TAU, 32, warn_color, 3.5)
	_boss.draw_circle(Vector2.ZERO, 85.0, Color(1.0, 0.1, 0.2, 0.12))
