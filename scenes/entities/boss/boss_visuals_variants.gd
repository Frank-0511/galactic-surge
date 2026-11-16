# boss_visuals_variants.gd
# Drawing of the two non-Nexus Boss looks: the Crucero Espectro (chapter 2, swept diamond hull with
# blade wings) and the Núcleo Blindado (chapter 3, armor plates that come off with each phase).
# Called from Boss._draw() and owned by Boss through _boss.

extends RefCounted

var _boss: Area2D


func _init(boss: Area2D) -> void:
	_boss = boss


## Crucero Espectro (chapter 2): swept diamond hull with blade wings, green-violet palette.
func draw_espectro() -> void:
	var pulse_speed: float = 9.0 if _boss.is_enraged else 4.0
	if _boss._state == _boss.MovementState.DIVE_TELEGRAPH:
		pulse_speed = 22.0
	var core_pulse: float = 0.5 + 0.5 * sin(_boss._time * pulse_speed)
	var neon_primary: Color = Color(0.85, 1.0, 0.2) if _boss.is_enraged else Color(0.35, 1.0, 0.55)
	var neon_secondary: Color = Color(1.0, 0.25, 0.75) if _boss.is_enraged else Color(0.62, 0.3, 1.0)
	var hull_color: Color = Color(0.06, 0.04, 0.14)

	_boss._visuals.draw_dive_warning()
	_boss.draw_circle(Vector2.ZERO, 60.0 + 8.0 * core_pulse, Color(neon_primary.r, neon_primary.g, neon_primary.b, 0.1 + 0.08 * core_pulse))

	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(0, -40),
		Vector2(22, -14),
		Vector2(40, -10),
		Vector2(40, 10),
		Vector2(22, 34),
		Vector2(0, 24),
		Vector2(-22, 34),
		Vector2(-40, 10),
		Vector2(-40, -10),
		Vector2(-22, -14),
	])
	_boss.draw_colored_polygon(hull, hull_color)
	var hull_loop: PackedVector2Array = hull.duplicate()
	hull_loop.append(hull[0])
	_boss.draw_polyline(hull_loop, neon_primary, 2.0)

	# Swept blade wings
	for side: float in [-1.0, 1.0]:
		var wing: PackedVector2Array = PackedVector2Array([
			Vector2(side * 36, -6), Vector2(side * 80, -18), Vector2(side * 66, 6), Vector2(side * 36, 12),
		])
		_boss.draw_colored_polygon(wing, Color(0.14, 0.08, 0.26))
		var wing_loop: PackedVector2Array = wing.duplicate()
		wing_loop.append(wing[0])
		_boss.draw_polyline(wing_loop, neon_secondary, 1.4)

	# Forward emitter and diamond reactor core
	_boss.draw_circle(Vector2(0, 24), 3.0, neon_primary)
	var core_size: float = 8.0 + 3.0 * core_pulse
	var core: PackedVector2Array = PackedVector2Array([
		Vector2(0, -core_size), Vector2(core_size, 0), Vector2(0, core_size), Vector2(-core_size, 0),
	])
	_boss.draw_colored_polygon(core, neon_primary)
	_boss.draw_circle(Vector2.ZERO, core_size * 0.45, Color(1.0, 1.0, 1.0, 0.95))

	if _boss._hit_flash_time > 0.0:
		var flash_alpha: float = clampf(_boss._hit_flash_time / 0.12, 0.0, 1.0) * 0.75
		_boss.draw_colored_polygon(hull, Color(1.0, 1.0, 1.0, flash_alpha))


## Núcleo Blindado (chapter 3): steel armor plates that come off with each armor phase.
## Phase 1 full plating, phase 2 only centre plates left, phase 3 bare bright core.
func draw_blindado() -> void:
	var pulse_speed: float = 9.0 if _boss.is_enraged else 4.0
	if _boss._state == _boss.MovementState.DIVE_TELEGRAPH:
		pulse_speed = 22.0
	var core_pulse: float = 0.5 + 0.5 * sin(_boss._time * pulse_speed)
	var accent: Color = Color(1.0, 0.3, 0.2) if _boss.is_enraged else Color(1.0, 0.72, 0.22)
	var steel: Color = Color(0.5, 0.56, 0.66)
	var seam: Color = Color(0.16, 0.19, 0.25)
	var hull_color: Color = Color(0.09, 0.1, 0.13)
	var phase: int = _boss._armor_phase

	_boss._visuals.draw_dive_warning()

	var hull: PackedVector2Array = PackedVector2Array([
		Vector2(-72, -22), Vector2(72, -22), Vector2(74, 0), Vector2(64, 24),
		Vector2(-64, 24), Vector2(-74, 0),
	])
	_boss.draw_colored_polygon(hull, hull_color)

	# Exposed reactor: visible from the subcore phase on, bright and pulsing once the armor is gone.
	if phase == _boss.ArmorPhase.EXTERIOR_ARMOR:
		_boss.draw_circle(Vector2.ZERO, 7.0, Color(accent.r, accent.g, accent.b, 0.35))
	elif phase == _boss.ArmorPhase.SUBCORE:
		_boss.draw_circle(Vector2.ZERO, 11.0, Color(accent.r, accent.g, accent.b, 0.6))
	else:
		var core_radius: float = 16.0 + 4.0 * core_pulse
		_boss.draw_circle(Vector2.ZERO, core_radius + 6.0, Color(accent.r, accent.g, accent.b, 0.3))
		_boss.draw_circle(Vector2.ZERO, core_radius, accent)
		_boss.draw_circle(Vector2.ZERO, core_radius * 0.5, Color(1.0, 1.0, 1.0, 0.95))

	# Armor plates: six in phase 1, only the centre pair in phase 2, none in phase 3.
	if phase != _boss.ArmorPhase.EXPOSED_CORE:
		var plates: Array[PackedVector2Array] = []
		if phase == _boss.ArmorPhase.EXTERIOR_ARMOR:
			plates.append(PackedVector2Array([Vector2(-70, -22), Vector2(-26, -22), Vector2(-30, -8), Vector2(-70, -6)]))
			plates.append(PackedVector2Array([Vector2(-70, -4), Vector2(-30, -4), Vector2(-34, 12), Vector2(-64, 22), Vector2(-72, 6)]))
			plates.append(PackedVector2Array([Vector2(70, -22), Vector2(26, -22), Vector2(30, -8), Vector2(70, -6)]))
			plates.append(PackedVector2Array([Vector2(70, -4), Vector2(30, -4), Vector2(34, 12), Vector2(64, 22), Vector2(72, 6)]))
		plates.append(PackedVector2Array([Vector2(-22, -22), Vector2(22, -22), Vector2(16, -8), Vector2(-16, -8)]))
		plates.append(PackedVector2Array([Vector2(-22, 6), Vector2(22, 6), Vector2(14, 22), Vector2(-14, 22)]))
		for plate: PackedVector2Array in plates:
			_boss.draw_colored_polygon(plate, steel)
			var plate_loop: PackedVector2Array = plate.duplicate()
			plate_loop.append(plate[0])
			_boss.draw_polyline(plate_loop, seam, 1.5)

	# Hull outline: accent colour when the armor is gone, steel while plated.
	var outline_color: Color = accent if phase != _boss.ArmorPhase.EXTERIOR_ARMOR else steel
	var hull_loop: PackedVector2Array = hull.duplicate()
	hull_loop.append(hull[0])
	_boss.draw_polyline(hull_loop, outline_color, 2.0)

	if _boss._hit_flash_time > 0.0:
		var flash_alpha: float = clampf(_boss._hit_flash_time / 0.12, 0.0, 1.0) * 0.75
		_boss.draw_colored_polygon(hull, Color(1.0, 1.0, 1.0, flash_alpha))
