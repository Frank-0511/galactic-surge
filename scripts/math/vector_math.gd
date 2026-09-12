# vector_math.gd
# Mathematical utility module for vector interpolation, Bézier curves, and derivatives.

class_name VectorMath
extends RefCounted


## Computes a point on a cubic Bézier curve defined by p0, p1, p2, and p3 at parameter t in [0.0, 1.0].
## Formula: B(t) = (1-t)^3 * P0 + 3(1-t)^2 * t * P1 + 3(1-t) * t^2 * P2 + t^3 * P3
static func cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	var u: float = 1.0 - clamped_t
	var u2: float = u * u
	var u3: float = u2 * u
	var t2: float = clamped_t * clamped_t
	var t3: float = t2 * clamped_t

	return (u3 * p0) + (3.0 * u2 * clamped_t * p1) + (3.0 * u * t2 * p2) + (t3 * p3)


## Computes a point on a quadratic Bézier curve defined by p0, p1, and p2 at parameter t in [0.0, 1.0].
## Formula: B(t) = (1-t)^2 * P0 + 2(1-t) * t * P1 + t^2 * P2
static func quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	var u: float = 1.0 - clamped_t
	var u2: float = u * u
	var t2: float = clamped_t * clamped_t

	return (u2 * p0) + (2.0 * u * clamped_t * p1) + (t2 * p2)


## Computes the first derivative (tangent velocity vector) of a cubic Bézier curve at parameter t.
## Formula: B'(t) = 3(1-t)^2 * (P1 - P0) + 6(1-t) * t * (P2 - P1) + 3t^2 * (P3 - P2)
static func cubic_bezier_derivative(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	var u: float = 1.0 - clamped_t
	var u2: float = u * u
	var t2: float = clamped_t * clamped_t

	var term1: Vector2 = 3.0 * u2 * (p1 - p0)
	var term2: Vector2 = 6.0 * u * clamped_t * (p2 - p1)
	var term3: Vector2 = 3.0 * t2 * (p3 - p2)

	return term1 + term2 + term3


## Returns the tangent angle (in radians) along a cubic Bézier curve at parameter t.
static func get_tangent_angle(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> float:
	var deriv: Vector2 = cubic_bezier_derivative(p0, p1, p2, p3, t)
	if deriv.is_zero_approx():
		var delta_t: float = 0.01 if t < 0.5 else -0.01
		deriv = cubic_bezier_derivative(p0, p1, p2, p3, t + delta_t)
	return deriv.angle()


## Samples points along a cubic Bézier curve into a PackedVector2Array of (segments + 1) points.
static func sample_cubic_path(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, segments: int) -> PackedVector2Array:
	var count: int = maxi(segments, 1)
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(count + 1)
	for i: int in range(count + 1):
		var t: float = float(i) / float(count)
		points[i] = cubic_bezier(p0, p1, p2, p3, t)
	return points
