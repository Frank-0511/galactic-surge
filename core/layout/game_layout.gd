# Central viewport-derived geometry for the layout responsivo feature.
#
# GameLayout derives playfield bounds, spawn positions and formation origins from
# the real viewport size at session start. It does not scale sprites, collision
# shapes or physical speeds; it only computes rectangles, margins and reference
# positions so Main, Player, EnemySpawner, drops, backgrounds and UI share a
# single source of geometry.
#
# configure() and relayout() produce the same result for an equal viewport
# size. relayout() is prepared for a future live-resize stage but does not
# change physical constants nor emit gameplay signals.
class_name GameLayout
extends RefCounted

# Physical margins and reference offsets. These are layout constants, not scale
# factors; entity sizes, collision shapes and speeds remain in raw pixels.
const SIDE_MARGIN: float = 24.0
const TOP_MARGIN: float = 120.0
const BOTTOM_MARGIN: float = 96.0
const FALLBACK_DROP_Y: float = 160.0

# Fixed height of the playfield (Etapa 21, movil-banda-controles). On tall phones the viewport grows below
# this line; that extra band is reserved for the touch controls and never holds gameplay anchors.
const PLAYFIELD_HEIGHT: float = 960.0

var viewport_size: Vector2 = Vector2.ZERO
var viewport_rect: Rect2 = Rect2()
var playfield_rect: Rect2 = Rect2()


# Configure the layout from the effective viewport size. Equivalent to
# relayout(); kept as the primary entry point for session initialization.
func configure(next_viewport_size: Vector2) -> void:
	relayout(next_viewport_size)


# Recompute the cached geometry for a new viewport size without changing
# physical constants or emitting gameplay signals.
func relayout(next_viewport_size: Vector2) -> void:
	viewport_size = next_viewport_size
	viewport_rect = Rect2(Vector2.ZERO, viewport_size)
	var field: Rect2 = playfield_of(viewport_rect)
	playfield_rect = Rect2(
		Vector2(SIDE_MARGIN, TOP_MARGIN),
		Vector2(
			maxf(0.0, field.size.x - SIDE_MARGIN * 2.0),
			maxf(0.0, field.size.y - TOP_MARGIN - BOTTOM_MARGIN),
		),
	)


# Pure: the playfield inside a viewport. Anchored to the top; the viewport's extra height below
# PLAYFIELD_HEIGHT is the control band. Equal to the viewport when it is not taller than the playfield.
static func playfield_of(viewport: Rect2) -> Rect2:
	return Rect2(viewport.position, Vector2(viewport.size.x, minf(viewport.size.y, PLAYFIELD_HEIGHT)))


# Pure: the band below the playfield where touch controls go. Zero height when the viewport has no extra height.
static func control_band_of(viewport: Rect2) -> Rect2:
	var top: float = minf(viewport.end.y, PLAYFIELD_HEIGHT)
	return Rect2(Vector2(viewport.position.x, top), Vector2(viewport.size.x, maxf(0.0, viewport.end.y - top)))


# Player spawn: horizontally centered, sitting BOTTOM_MARGIN above the bottom
# edge of the playfield (not of the viewport, so the control band never covers the ship).
func get_player_spawn_position() -> Vector2:
	return Vector2(viewport_rect.get_center().x, playfield_of(viewport_rect).end.y - BOTTOM_MARGIN)


# Horizontal movement limits for the player: the full viewport width. Player
# applies its own collision-safe margin, so its hull can reach the visible edge.
func get_player_horizontal_limits() -> Vector2:
	return Vector2(viewport_rect.position.x, viewport_rect.end.x)


# Formation origin: horizontally centered, first row at TOP_MARGIN from the top
# of the viewport. Enemies are generated around this center.
func get_enemy_formation_origin() -> Vector2:
	return Vector2(viewport_rect.get_center().x, viewport_rect.position.y + TOP_MARGIN)


# Position of a single enemy row, centered horizontally, offset from the first
# row by row * vertical_spacing. The existing 64 px vertical spacing is passed
# by the caller and is not scaled here.
func get_enemy_row_position(row: int, vertical_spacing: float) -> Vector2:
	return Vector2(
		viewport_rect.get_center().x,
		viewport_rect.position.y + TOP_MARGIN + float(row) * vertical_spacing,
	)


# Power-up drop fallback position: horizontally centered, at FALLBACK_DROP_Y
# from the top of the viewport. Used when cleaning up wave drops.
func get_power_up_fallback_position() -> Vector2:
	return Vector2(viewport_rect.get_center().x, viewport_rect.position.y + FALLBACK_DROP_Y)


# Full viewport rectangle, from (0, 0) to the configured viewport size. Used by
# backgrounds and UI layers that must cover the whole visible area.
func get_full_viewport_rect() -> Rect2:
	return viewport_rect
