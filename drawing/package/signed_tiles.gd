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


static func tile_for_pixel(pixel: Vector2i, stride: int) -> Vector2i:
	return Vector2i(floor_div(pixel.x, stride), floor_div(pixel.y, stride))


static func offset_in_tile(pixel: Vector2i, stride: int) -> Vector2i:
	assert(stride > 0, "Tile stride must be positive")
	return Vector2i(posmod(pixel.x, stride), posmod(pixel.y, stride))
