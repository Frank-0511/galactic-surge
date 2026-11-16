# enemy_visuals.gd
# Drawing of one Enemy: the beetle carapace, claws, antennae, legs, pulsing glow, the enraged and
# tactical-variant palettes, the deflector arc, the charge flame, the hit flash and the mini health
# bar. Called from Enemy._draw() and owned by Enemy through _enemy.

extends RefCounted

const EnemyVariants: Script = preload("res://scripts/systems/enemy_variants.gd")

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


func draw_enemy() -> void:
	var pulse_speed: float = 6.0 if _enemy._is_enraged else 3.0
	var pulse: float = 0.5 + 0.5 * sin(_enemy._time * pulse_speed + _enemy._pulse_offset)

	# Glow colors: toxic green normally, reacting amber/crimson when enraged
	var ambient_glow_color: Color = Color(1.0, 0.35, 0.15, 0.12 + 0.08 * pulse) if _enemy._is_enraged else Color(0.45, 1.0, 0.35, 0.07 + 0.05 * pulse)
	var shadow_color: Color = Color(1.0, 0.20, 0.05, 0.14 + 0.08 * pulse) if _enemy._is_enraged else Color(0.35, 0.95, 0.3, 0.10 + 0.06 * pulse)
	var carapace_color: Color = Color(0.38, 0.06, 0.12) if _enemy._is_enraged else Color(0.22, 0.05, 0.32)
	var carapace_outline_color: Color = Color(1.0, 0.40, 0.15) if _enemy._is_enraged else Color(0.55, 1.0, 0.4)
	var claw_color: Color = Color(0.44, 0.08, 0.16) if _enemy._is_enraged else Color(0.28, 0.06, 0.4)
	var claw_outline_color: Color = Color(1.0, 0.45, 0.20) if _enemy._is_enraged else Color(0.6, 1.0, 0.45)
	var antenna_color: Color = Color(1.0, 0.55, 0.22) if _enemy._is_enraged else Color(0.65, 1.0, 0.5)
	var eye_outer_color: Color = Color(1.0, 0.35, 0.15, 0.4 + 0.3 * pulse) if _enemy._is_enraged else Color(0.55, 1.0, 0.35, 0.3 + 0.2 * pulse)
	var eye_inner_color: Color = Color(1.0, 0.85, 0.25, 0.9 + 0.1 * pulse) if _enemy._is_enraged else Color(0.9, 1.0, 0.55, 0.8 + 0.2 * pulse)
	var leg_color: Color = Color(1.0, 0.45, 0.20, 0.9) if _enemy._is_enraged else Color(0.5, 0.95, 0.4, 0.8)

	# Tactical variant palette (Stage 12)
	if _enemy.variant_id != EnemyVariants.STANDARD and not _enemy._is_enraged:
		var accent: Color = _get_variant_accent()
		carapace_outline_color = accent
		claw_outline_color = accent
		antenna_color = accent
		eye_inner_color = accent.lightened(0.4)
		leg_color = accent
		ambient_glow_color = Color(accent.r, accent.g, accent.b, 0.08 + 0.06 * pulse)

	# Ambient glow
	_enemy.draw_circle(Vector2.ZERO, 16.0 + 2.0 * pulse, ambient_glow_color)

	# Soft hover shadow beneath carapace
	_enemy.draw_circle(Vector2(0, 13), 8.0, shadow_color)

	# Compact beetle-like carapace
	var carapace: PackedVector2Array = PackedVector2Array([
		Vector2(-8, -10), Vector2(0, -12), Vector2(8, -10),
		Vector2(10, 1), Vector2(6, 9), Vector2(0, 11), Vector2(-6, 9), Vector2(-10, 1),
	])
	_enemy.draw_colored_polygon(carapace, carapace_color)
	var carapace_outline: PackedVector2Array = carapace.duplicate()
	carapace_outline.append(carapace[0])
	_enemy.draw_polyline(carapace_outline, carapace_outline_color, 1.5)

	# Crab-like pincer claws
	var claw_l: PackedVector2Array = PackedVector2Array([
		Vector2(-9, -3), Vector2(-17, -6), Vector2(-21, -9),
		Vector2(-16, -1), Vector2(-21, 4), Vector2(-16, 5), Vector2(-10, 2),
	])
	var claw_r: PackedVector2Array = PackedVector2Array([
		Vector2(9, -3), Vector2(17, -6), Vector2(21, -9),
		Vector2(16, -1), Vector2(21, 4), Vector2(16, 5), Vector2(10, 2),
	])
	_enemy.draw_colored_polygon(claw_l, claw_color)
	_enemy.draw_colored_polygon(claw_r, claw_color)
	var claw_l_outline: PackedVector2Array = claw_l.duplicate()
	claw_l_outline.append(claw_l[0])
	var claw_r_outline: PackedVector2Array = claw_r.duplicate()
	claw_r_outline.append(claw_r[0])
	_enemy.draw_polyline(claw_l_outline, claw_outline_color, 1.25)
	_enemy.draw_polyline(claw_r_outline, claw_outline_color, 1.25)

	# Twin antennae
	_enemy.draw_line(Vector2(-3, -11), Vector2(-4.5, -17), antenna_color, 1.2)
	_enemy.draw_line(Vector2(3, -11), Vector2(4.5, -17), antenna_color, 1.2)
	_enemy.draw_circle(Vector2(-4.5, -17), 1.2, antenna_color)
	_enemy.draw_circle(Vector2(4.5, -17), 1.2, antenna_color)

	# Pulsing central eye
	_enemy.draw_circle(Vector2(0, -1), 4.0, eye_outer_color)
	_enemy.draw_circle(Vector2(0, -1), 2.0, eye_inner_color)

	# Three thin wriggling legs
	for i in range(3):
		var leg_x: float = (i - 1) * 4.0
		var wag: float = sin(_enemy._time * 6.0 + _enemy._pulse_offset + i) * 1.5
		_enemy.draw_line(Vector2(leg_x, 9), Vector2(leg_x + wag, 15), leg_color, 1.1)

	# Frontal deflector arc (armored fighter) and overloaded engine flame (interceptor)
	if _enemy.has_deflector():
		var arc_alpha: float = 0.6 + 0.3 * pulse
		_enemy.draw_arc(Vector2(0, 2), 19.0, deg_to_rad(60.0), deg_to_rad(120.0), 16, Color(0.4, 0.85, 1.0, arc_alpha), 3.0)
	if _enemy._state == _enemy.State.CHARGING:
		_enemy.draw_colored_polygon(PackedVector2Array([Vector2(-5, -12), Vector2(0, -26 - 6.0 * pulse), Vector2(5, -12)]), Color(1.0, 0.55, 0.15, 0.85))

	# Impact hit flash overlay
	if _enemy._hit_flash_timer > 0.0:
		_enemy.draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.9, 0.7, 0.45))

	# Mini health bar when damaged
	if _enemy.health < _enemy.max_health and _enemy.health > 0.0:
		_enemy.draw_rect(Rect2(-15.0, -22.0, 30.0, 3.0), Color(0.1, 0.1, 0.15, 0.8))
		var hp_ratio: float = clampf(_enemy.health / _enemy.max_health, 0.0, 1.0)
		var bar_color: Color = Color.RED.lerp(Color.GREEN, hp_ratio)
		_enemy.draw_rect(Rect2(-15.0, -22.0, 30.0 * hp_ratio, 3.0), bar_color)


func _get_variant_accent() -> Color:
	match _enemy.variant_id:
		EnemyVariants.ARMORED_FIGHTER:
			return Color(0.45, 0.8, 1.0)
		EnemyVariants.ASSAULT_FRIGATE:
			return Color(1.0, 0.7, 0.25)
		EnemyVariants.SCOUT_DRONE:
			return Color(0.3, 1.0, 0.9)
		EnemyVariants.SUICIDE_INTERCEPTOR:
			return Color(1.0, 0.3, 0.45)
		_:
			return Color(0.55, 1.0, 0.4)
