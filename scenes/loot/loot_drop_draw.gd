# loot_drop_draw.gd
# Procedural vector drawing of a LootDrop: the pulsing halo and neon rim shared by
# every type, the per-type glyphs, and the glow color of each type. Owned by
# LootDrop through _drop; it reads _drop._type and _drop._elapsed and paints on the drop.

extends RefCounted

const MedallionModule: GDScript = preload("res://scenes/loot/loot_drop_medallion.gd")

var _drop: LootDrop


func _init(drop: LootDrop) -> void:
	_drop = drop


## Draws the whole drop: halo, backing disc, neon rim and the glyph of its type.
func draw_all() -> void:
	var canvas: CanvasItem = _drop
	# Subtle pulsing background halo for visibility against dark space
	var halo_pulse: float = 0.5 + 0.5 * sin(_drop._elapsed * 4.0)
	var glow_color: Color = glow_color_for(_drop._type)
	canvas.draw_circle(Vector2.ZERO, 15.0 + 2.5 * halo_pulse, Color(glow_color.r, glow_color.g, glow_color.b, 0.16 + 0.08 * halo_pulse))

	# High contrast backing disc and outer neon rim
	canvas.draw_circle(Vector2.ZERO, 12.0, Color(0.04, 0.06, 0.12, 0.85))
	canvas.draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, glow_color, 1.5, true)

	match _drop._type:
		LootDrop.Type.SCORE:
			_draw_score(canvas)
		LootDrop.Type.DOUBLE_SHOT:
			_draw_double_shot(canvas)
		LootDrop.Type.SHIELD:
			_draw_shield(canvas)
		LootDrop.Type.EXTRA_LIFE:
			_draw_extra_life(canvas)
		LootDrop.Type.BOMB:
			_draw_bomb(canvas)
		LootDrop.Type.MEDALLION_BLASTER:
			MedallionModule.paint_medallion(canvas, 0)
		LootDrop.Type.MEDALLION_MISSILE:
			MedallionModule.paint_medallion(canvas, 1)
		LootDrop.Type.MEDALLION_LASER:
			MedallionModule.paint_medallion(canvas, 2)
		LootDrop.Type.POWER_ATOM:
			_draw_power_atom(canvas)
		LootDrop.Type.RECOVERY_CAPSULE:
			_draw_recovery_capsule(canvas)


## Glow color (rim and halo) of each loot type.
static func glow_color_for(loot_type: int) -> Color:
	match loot_type:
		LootDrop.Type.SCORE:
			return Color(1.0, 0.84, 0.0) # Yellow / Gold
		LootDrop.Type.DOUBLE_SHOT:
			return Color(0.0, 0.9, 1.0) # Cyan
		LootDrop.Type.SHIELD:
			return Color(0.0, 0.9, 0.46) # Emerald Green
		LootDrop.Type.EXTRA_LIFE:
			return Color(1.0, 0.09, 0.27) # Red / Magenta
		LootDrop.Type.BOMB:
			return Color(1.0, 0.57, 0.0) # Orange / Amber
		LootDrop.Type.MEDALLION_BLASTER:
			return Color(0.2, 0.6, 1.0) # Neon Blue
		LootDrop.Type.MEDALLION_MISSILE:
			return Color(1.0, 0.55, 0.1) # Neon Orange
		LootDrop.Type.MEDALLION_LASER:
			return Color(1.0, 0.2, 0.25) # Neon Crimson
		LootDrop.Type.POWER_ATOM:
			return Color(1.0, 0.85, 0.2) # Neon Golden
		LootDrop.Type.RECOVERY_CAPSULE:
			return Color(0.1, 0.95, 1.0) # Radiant Cyan
		_:
			return Color.WHITE


func _draw_score(canvas: CanvasItem) -> void:
	# Golden diamond star with glistening inner gleams
	var outer_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)
	])
	var inner_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -4.5), Vector2(3.5, 0), Vector2(0, 4.5), Vector2(-3.5, 0)
	])
	canvas.draw_colored_polygon(outer_diamond, Color(1.0, 0.84, 0.0))
	canvas.draw_colored_polygon(inner_diamond, Color(1.0, 0.98, 0.7))
	# Subtle sparkle axes
	canvas.draw_line(Vector2(-9, 0), Vector2(9, 0), Color(1.0, 1.0, 0.85, 0.8), 1.0, true)
	canvas.draw_line(Vector2(0, -9), Vector2(0, 9), Color(1.0, 1.0, 0.85, 0.8), 1.0, true)


func _draw_double_shot(canvas: CanvasItem) -> void:
	# Twin cyan chevrons representing dual blaster power
	var cyan: Color = Color(0.0, 0.9, 1.0)
	var left_chevron: PackedVector2Array = PackedVector2Array([
		Vector2(-7, 4), Vector2(-4, -5), Vector2(-1, 4)
	])
	var right_chevron: PackedVector2Array = PackedVector2Array([
		Vector2(1, 4), Vector2(4, -5), Vector2(7, 4)
	])
	canvas.draw_polyline(left_chevron, cyan, 2.2, true)
	canvas.draw_polyline(right_chevron, cyan, 2.2, true)
	canvas.draw_line(Vector2(-4, -4), Vector2(-4, 2), Color.WHITE, 1.2, true)
	canvas.draw_line(Vector2(4, -4), Vector2(4, 2), Color.WHITE, 1.2, true)


func _draw_shield(canvas: CanvasItem) -> void:
	# Emerald concentric shield with rotating orbital arc
	var emerald: Color = Color(0.0, 0.9, 0.46)
	canvas.draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 24, Color(0.0, 0.9, 0.46, 0.6), 1.5, true)
	var sweep: float = fmod(_drop._elapsed * 3.2, TAU)
	canvas.draw_arc(Vector2.ZERO, 7.5, sweep, sweep + 1.5, 12, Color(0.6, 1.0, 0.8), 2.5, true)
	var crest: PackedVector2Array = PackedVector2Array([
		Vector2(0, -4.5), Vector2(3.5, -2.5), Vector2(2.5, 2.5),
		Vector2(0, 4.5), Vector2(-2.5, 2.5), Vector2(-3.5, -2.5)
	])
	canvas.draw_colored_polygon(crest, emerald)
	canvas.draw_circle(Vector2.ZERO, 1.5, Color.WHITE)


func _draw_extra_life(canvas: CanvasItem) -> void:
	# Vibrant red / magenta medical cross with white core
	var red: Color = Color(1.0, 0.09, 0.27)
	canvas.draw_rect(Rect2(-6.5, -2.5, 13.0, 5.0), red)
	canvas.draw_rect(Rect2(-2.5, -6.5, 5.0, 13.0), red)
	canvas.draw_rect(Rect2(-4.5, -1.2, 9.0, 2.4), Color(1.0, 0.92, 0.95))
	canvas.draw_rect(Rect2(-1.2, -4.5, 2.4, 9.0), Color(1.0, 0.92, 0.95))


func _draw_bomb(canvas: CanvasItem) -> void:
	# Radiant orange detonator with radial spikes and bright core
	var orange: Color = Color(1.0, 0.57, 0.0)
	var base_angle: float = _drop._elapsed * 1.8
	for i in range(8):
		var a: float = base_angle + i * (TAU / 8.0)
		var dir_v: Vector2 = Vector2(cos(a), sin(a))
		canvas.draw_line(dir_v * 5.5, dir_v * 9.5, orange, 1.8, true)
	canvas.draw_circle(Vector2.ZERO, 5.0, orange)
	canvas.draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.95, 0.8))


func _draw_power_atom(canvas: CanvasItem) -> void:
	var gold: Color = Color(1.0, 0.85, 0.2)
	var pulse: float = 0.8 + 0.2 * sin(_drop._elapsed * 6.0)
	canvas.draw_circle(Vector2.ZERO, 3.8 * pulse, gold)
	canvas.draw_circle(Vector2.ZERO, 2.0 * pulse, Color.WHITE)
	# Orbit 1
	var a1: float = _drop._elapsed * 3.0
	var pts1: PackedVector2Array = PackedVector2Array()
	for i in range(16):
		var t: float = float(i) / 16.0 * TAU
		var p: Vector2 = Vector2(cos(t) * 8.0, sin(t) * 3.5).rotated(a1)
		pts1.append(p)
	pts1.append(pts1[0])
	canvas.draw_polyline(pts1, Color(1.0, 0.9, 0.4, 0.75), 1.2, true)
	# Orbit 2
	var a2: float = -_drop._elapsed * 2.5 + PI / 3.0
	var pts2: PackedVector2Array = PackedVector2Array()
	for i in range(16):
		var t: float = float(i) / 16.0 * TAU
		var p: Vector2 = Vector2(cos(t) * 8.0, sin(t) * 3.5).rotated(a2)
		pts2.append(p)
	pts2.append(pts2[0])
	canvas.draw_polyline(pts2, Color(1.0, 0.9, 0.4, 0.75), 1.2, true)


func _draw_recovery_capsule(canvas: CanvasItem) -> void:
	var cyan: Color = Color(0.1, 0.95, 1.0)
	var pulse: float = 0.85 + 0.15 * sin(_drop._elapsed * 8.0)
	var diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -9 * pulse), Vector2(7 * pulse, 0), Vector2(0, 9 * pulse), Vector2(-7 * pulse, 0)
	])
	canvas.draw_colored_polygon(diamond, Color(0.08, 0.18, 0.32, 0.9))
	canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), cyan, 2.0, true)
	# Glowing core chevron
	canvas.draw_line(Vector2(-3.5, 2), Vector2(0, -4), Color.WHITE, 1.8, true)
	canvas.draw_line(Vector2(0, -4), Vector2(3.5, 2), Color.WHITE, 1.8, true)
	canvas.draw_circle(Vector2(0, -4), 1.5, Color.WHITE)
