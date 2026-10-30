class_name AtlasGridSnap
extends RefCounted

## Snap artwork in continuous board units, never in screen pixels.
## Selection moves use cell-to-cell displacement to avoid jumping an existing
## unsnapped object onto a grid point when the drag first begins.


static func available(grid: AtlasGrid) -> bool:
	return grid != null and grid.is_valid() and grid.kind != AtlasGrid.Kind.GRIDLESS


static func point(grid: AtlasGrid, position: Vector2) -> Vector2:
	if not available(grid) or not position.is_finite():
		return position
	return grid.cell_to_document(grid.document_to_cell(position))


static func move_delta(grid: AtlasGrid, start: Vector2, finish: Vector2) -> Vector2:
	if not available(grid) or not start.is_finite() or not finish.is_finite():
		return finish - start
	return point(grid, finish) - point(grid, start)
