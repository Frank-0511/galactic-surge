# loot_drop_medallion.gd
# Weapon medallions (blaster, missile, laser) painted on any CanvasItem. Shared by
# the falling LootDrop and the HUD weapon icon, so both look the same (Etapa 20).
# Stateless: every function is static and receives the canvas to paint on.

extends RefCounted


## Paints the medallion of a weapon (0 blaster, 1 misil, 2 laser) on any CanvasItem.
static func paint_medallion(canvas: CanvasItem, weapon_type: int) -> void:
	match weapon_type:
		1:
			_paint_missile(canvas)
		2:
			_paint_laser(canvas)
		_:
			_paint_blaster(canvas)


## Dark badge with a colored ring; keeps every weapon readable on the drop and at HUD size.
static func _paint_badge(canvas: CanvasItem, color: Color) -> void:
	canvas.draw_circle(Vector2.ZERO, 9.0, Color(0.03, 0.05, 0.1, 0.92))
	canvas.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, color, 1.6, true)


## Blaster: a pistol silhouette (barrel, body and grip).
static func _paint_blaster(canvas: CanvasItem) -> void:
	var blue: Color = Color(0.3, 0.7, 1.0)
	_paint_badge(canvas, blue)
	var pistol: PackedVector2Array = PackedVector2Array([
		Vector2(-5, -3), Vector2(4, -3), Vector2(4, -1), Vector2(1, -1),
		Vector2(1, 1), Vector2(3, 1), Vector2(3, 5), Vector2(-1, 5),
		Vector2(-1, 1), Vector2(-5, 1)
	])
	canvas.draw_colored_polygon(pistol, blue)
	canvas.draw_circle(Vector2(5, -2), 1.2, Color.WHITE)


## Missile: a rocket with a nose cone, fins and a flame.
static func _paint_missile(canvas: CanvasItem) -> void:
	var orange: Color = Color(1.0, 0.6, 0.15)
	_paint_badge(canvas, orange)
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -6), Vector2(2.5, -2), Vector2(2.5, 3), Vector2(-2.5, 3), Vector2(-2.5, -2)
	])
	canvas.draw_colored_polygon(body, Color.WHITE)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-2.5, 0), Vector2(-5, 4), Vector2(-2.5, 3)]), orange)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(2.5, 0), Vector2(5, 4), Vector2(2.5, 3)]), orange)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-1.5, 3), Vector2(1.5, 3), Vector2(0, 7)]), Color(1.0, 0.9, 0.4))


## Laser: an energy bolt (lightning), the usual sign of an energy weapon.
static func _paint_laser(canvas: CanvasItem) -> void:
	var red: Color = Color(1.0, 0.25, 0.3)
	_paint_badge(canvas, red)
	var bolt: PackedVector2Array = PackedVector2Array([
		Vector2(1.5, -6), Vector2(-3, 0.5), Vector2(0, 0.5),
		Vector2(-1.5, 6), Vector2(3, -0.5), Vector2(0, -0.5)
	])
	canvas.draw_colored_polygon(bolt, red)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(0.8, -4.5), Vector2(-1.5, 0.2), Vector2(0.2, 0.2), Vector2(0.6, -2)
	]), Color(1.0, 0.9, 0.9))
