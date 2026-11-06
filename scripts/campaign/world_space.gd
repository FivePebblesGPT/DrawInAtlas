class_name AtlasWorldSpace
extends RefCounted
## Atlas-only signed map-world frame. All detail levels share 1024 ticks/unit;
## no unrebased, enormous Vector2 positions or floating-point raster addressing.

const TICKS_PER_UNIT: int = 1024
const MAX_TICKS: int = 4000000000000000
const MAX_PIXELS: int = 1152921504606846976
const MAX_DENSITY: int = 1048576
const TILES: Script = preload("res://addons/drawing/signed_tiles.gd")


static func valid_density(num: int, den: int) -> bool:
	return num > 0 and den > 0 and num <= MAX_DENSITY and den <= MAX_DENSITY


static func default_density(level: int) -> int:
	# Default progression is capped, not an implied 2^32-sized texture.
	return 1 << mini(maxi(level, 0), 10)


static func world_to_pixel(ticks: int, num: int, den: int) -> DrawingResult:
	if ticks < -MAX_TICKS or ticks > MAX_TICKS:
		return DrawingResult.failure("COORD_RANGE", "World coordinate out of range")
	if not valid_density(num, den):
		return DrawingResult.failure("DENSITY", "Invalid positive density fraction")
	var divisor: int = TICKS_PER_UNIT * den
	var q: int = TILES.floor_div(ticks, divisor)
	var r: int = ticks - q * divisor
	if q < -MAX_PIXELS / num or q > MAX_PIXELS / num:
		return DrawingResult.failure("COORD_RANGE", "Scaled coordinate out of range")
	var pixel: int = q * num + (r * num) / divisor
	if pixel < -MAX_PIXELS or pixel > MAX_PIXELS:
		return DrawingResult.failure("COORD_RANGE", "Scaled coordinate out of range")
	return DrawingResult.success(pixel)


static func point_to_pixels(x_ticks: int, y_ticks: int, num: int, den: int) -> DrawingResult:
	var x: DrawingResult = world_to_pixel(x_ticks, num, den)
	if not x.ok:
		return x
	var y: DrawingResult = world_to_pixel(y_ticks, num, den)
	if not y.ok:
		return y
	return DrawingResult.success({"x": x.value, "y": y.value})


static func snap_ticks(ticks: int, spacing: int, origin: int = 0) -> DrawingResult:
	if spacing <= 0 or spacing > MAX_TICKS or abs(ticks) > MAX_TICKS or abs(origin) > MAX_TICKS:
		return DrawingResult.failure("SNAP", "Invalid world-space grid")
	var relative: int = ticks - origin
	var cell: int = TILES.floor_div(relative, spacing)
	var rem: int = relative - cell * spacing
	if rem * 2 >= spacing:
		cell += 1
	var result: int = origin + cell * spacing
	if abs(result) > MAX_TICKS:
		return DrawingResult.failure("COORD_RANGE", "Snap exceeds supported world")
	return DrawingResult.success(result)


static func camera_relative(world_ticks: int, camera_ticks: int, zoom: float = 1.0) -> DrawingResult:
	if abs(world_ticks) > MAX_TICKS or abs(camera_ticks) > MAX_TICKS or not is_finite(zoom) or zoom <= 0.0:
		return DrawingResult.failure("COORD_RANGE", "Invalid camera anchor")
	var offset: float = float(world_ticks - camera_ticks) * zoom / float(TICKS_PER_UNIT)
	if not is_finite(offset) or absf(offset) > 100000000.0:
		return DrawingResult.failure("VIEW_RANGE", "Camera rebase required")
	return DrawingResult.success(offset)


static func placed_asset_relative(local: Vector2, transform: Transform2D,
		anchor_x: int, anchor_y: int, camera_x: int, camera_y: int) -> DrawingResult:
	if not local.is_finite() or not transform.x.is_finite() or not transform.y.is_finite() \
			or not transform.origin.is_finite() or not is_finite(transform.determinant()) \
			or absf(transform.determinant()) < 0.00000001:
		return DrawingResult.failure("TRANSFORM", "Invalid asset-local transform")
	var x: DrawingResult = camera_relative(anchor_x, camera_x)
	var y: DrawingResult = camera_relative(anchor_y, camera_y)
	if not x.ok:
		return x
	if not y.ok:
		return y
	var point: Vector2 = transform * local + Vector2(x.value, y.value)
	return DrawingResult.success(point) if point.is_finite() else DrawingResult.failure("TRANSFORM", "Invalid transformed point")
