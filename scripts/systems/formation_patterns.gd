# formation_patterns.gd
# Spatial pattern generator for enemy formations (Grid, V-Shape, Arc, Diagonal).

class_name FormationPatterns
extends RefCounted

enum PatternType {
	GRID,
	V_SHAPE,
	ARC,
	DIAGONAL,
}


## Converts a pattern name string (e.g. "grid", "v_shape", "arc", "diagonal") to PatternType.
static func pattern_from_string(name: String) -> PatternType:
	match name.to_lower():
		"v_shape", "v", "chevron":
			return PatternType.V_SHAPE
		"arc", "curve", "parabola":
			return PatternType.ARC
		"diagonal", "diag", "stairs":
			return PatternType.DIAGONAL
		_:
			return PatternType.GRID


## Calculates formation slot positions for given geometry parameters.
## Slots are built in local space (origin at zero) and placed with a Transform2D
## that rotates them by `rotation` radians around `origin`. Rotation 0 is identity.
## Returns an array of Vector2 positions of size (rows * columns).
static func calculate_slots(
	pattern: PatternType,
	rows: int,
	columns: int,
	h_spacing: float,
	v_spacing: float,
	origin: Vector2,
	rotation: float = 0.0
) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	if rows <= 0 or columns <= 0:
		return slots

	slots.resize(rows * columns)
	var center_col: float = (float(columns) - 1.0) / 2.0
	var placement: Transform2D = Transform2D(rotation, origin)

	for row: int in range(rows):
		var row_f: float = float(row)
		var base_y: float = row_f * v_spacing

		for col: int in range(columns):
			var col_f: float = float(col)
			var col_delta: float = col_f - center_col
			var x: float = col_delta * h_spacing
			var y: float = base_y

			match pattern:
				PatternType.GRID:
					pass
				PatternType.V_SHAPE:
					# Center column is foremost; flanks descend downwards.
					y += absf(col_delta) * (v_spacing * 0.45)
				PatternType.ARC:
					# Parabolic curved arc symmetric around center.
					var norm_delta: float = col_delta / maxf(center_col, 1.0)
					y += (norm_delta * norm_delta) * (v_spacing * 0.5)
				PatternType.DIAGONAL:
					# Stepped linear tilt across columns.
					y += col_delta * (v_spacing * 0.25)

			var index: int = row * columns + col
			slots[index] = placement * Vector2(x, y)

	return slots
