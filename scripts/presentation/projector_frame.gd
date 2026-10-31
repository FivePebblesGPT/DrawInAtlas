class_name AtlasProjectorFrame
extends RefCounted
## T-013: GM-only, session-scoped framing geometry. This is not artwork,
## calibration, a privacy grant, or a player rendering surface.

const MIN_WIDTH: float = 4.0
const MAX_WIDTH: float = 100000.0

var center: Vector2 = Vector2.ZERO
var width: float = 400.0
var output_size: Vector2i = Vector2i(1920, 1080)


func aspect_ratio() -> float:
	return float(output_size.x) / float(output_size.y)


func bounds() -> Rect2:
	var dimensions: Vector2 = Vector2(width, width / aspect_ratio())
	return Rect2(center - dimensions * 0.5, dimensions)


## Changing the physical output resolution only changes the frame aspect;
## it never changes document pixels, layer transforms or a GM camera.
func set_output_size(candidate: Vector2i) -> bool:
	if candidate.x < 1 or candidate.y < 1 or candidate.x > 16384 or candidate.y > 16384:
		return false
	output_size = candidate
	return true


func set_view(position: Vector2, horizontal_span: float) -> bool:
	if not is_finite(position.x) or not is_finite(position.y) \
			or not is_finite(horizontal_span) or horizontal_span < MIN_WIDTH or horizontal_span > MAX_WIDTH:
		return false
	center = position
	width = horizontal_span
	return true


## Opposite corner remains fixed; both pointer axes influence the drag while
## the rectangle stays constrained to its output aspect ratio.
func resize_from_top_left(anchor: Vector2, pointer: Vector2) -> bool:
	if not is_finite(pointer.x) or not is_finite(pointer.y):
		return false
	var direction: Vector2 = Vector2(1.0, 1.0 / aspect_ratio())
	var horizontal_span: float = clampf((pointer - anchor).dot(direction) / direction.length_squared(),
		MIN_WIDTH, MAX_WIDTH)
	return set_view(anchor + Vector2(horizontal_span, horizontal_span / aspect_ratio()) * 0.5, horizontal_span)


## A future authorized player viewport may use these two numbers to display
## the board rectangle. Do not call this with an unsanitized GM campaign.
func output_camera_center() -> Vector2:
	return center


func output_camera_zoom() -> float:
	return float(output_size.x) / width
