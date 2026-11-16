extends RefCounted
## Shared, dependency-free signed tile arithmetic for the Drawing package.
## Stride is supplied by the caller; T-067 must benchmark the production value.


static func floor_div(value: int, positive_divisor: int) -> int:
	assert(positive_divisor > 0, "Tile stride must be positive")
	@warning_ignore("integer_division")
	var quotient: int = value / positive_divisor
	if value < 0 and value % positive_divisor != 0:
		quotient -= 1
	return quotient


## Godot display/manifest coordinates use a stricter 2^52 pixel bound than
## the Rust input ABI. Compare rather than abs(): abs(INT64_MIN) overflows
## signed 64-bit and must never accidentally pass the bound.
const MAX_PROJECTION_PIXEL_COORD: int = 4503599627370496


## Legacy-compatible public gesture, image-import and viewport anchor limit.
## Compare both signed halves: abs(INT64_MIN) wraps to a negative value.
const MAX_DOCUMENT_ANCHOR_COORD: int = 1152921504606846976


static func document_anchor_in_range(x: int, y: int) -> bool:
	return x >= -MAX_DOCUMENT_ANCHOR_COORD and x <= MAX_DOCUMENT_ANCHOR_COORD \
		and y >= -MAX_DOCUMENT_ANCHOR_COORD and y <= MAX_DOCUMENT_ANCHOR_COORD


## Pixel-based history has the same signed projection budget as storage tiles.
## Never use abs() here: abs(INT64_MIN) wraps back to a negative number.
static func pixel_coordinates_in_projection_range(x: int, y: int) -> bool:
	return x >= -MAX_PROJECTION_PIXEL_COORD and x <= MAX_PROJECTION_PIXEL_COORD \
		and y >= -MAX_PROJECTION_PIXEL_COORD and y <= MAX_PROJECTION_PIXEL_COORD


static func tile_coordinates_in_projection_range(cx: int, cy: int, stride: int) -> bool:
	if stride <= 0:
		return false
	@warning_ignore("integer_division")
	var limit: int = MAX_PROJECTION_PIXEL_COORD / stride
	return cx >= -limit and cx <= limit and cy >= -limit and cy <= limit


static func tile_for_pixel(pixel: Vector2i, stride: int) -> Vector2i:
	return Vector2i(floor_div(pixel.x, stride), floor_div(pixel.y, stride))


static func offset_in_tile(pixel: Vector2i, stride: int) -> Vector2i:
	assert(stride > 0, "Tile stride must be positive")
	return Vector2i(posmod(pixel.x, stride), posmod(pixel.y, stride))


## 64-bit document addressing must not pass through Vector2i or float division.
static func tile_key64(x: int, y: int, stride: int) -> String:
	return "%d,%d" % [floor_div(x, stride), floor_div(y, stride)]


static func pixel_key64(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


static func local_offset64(x: int, y: int, stride: int) -> Vector2i:
	return Vector2i(posmod(x, stride), posmod(y, stride))
