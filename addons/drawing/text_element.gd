class_name DrawingTextElement
extends RefCounted
## A text layer contains exactly one such value; no Node or OS font resources.
## Position is the top-left world pixel, independent of zoom and camera.

const DEFAULT_FONT: String = "lato-regular-v1"
const MAX_CHARS: int = 16384

var content: String = ""
var font_id: String = DEFAULT_FONT
var font_size: int = 24
var color_rgba: int = 0xff202020
var position: Vector2i = Vector2i.ZERO
var angle: float = 0.0
var scale: Vector2 = Vector2.ONE
var alignment: String = "left"


func detached_copy() -> DrawingTextElement:
	var clone: DrawingTextElement = DrawingTextElement.new()
	clone.content = content
	clone.font_id = font_id
	clone.font_size = font_size
	clone.color_rgba = color_rgba
	clone.position = position
	clone.angle = angle
	clone.scale = scale
	clone.alignment = alignment
	return clone


func validated() -> DrawingResult:
	if content.length() > MAX_CHARS or content.strip_edges().is_empty():
		return DrawingResult.failure("EMPTY_TEXT", "Commit nonempty text of at most 16384 characters")
	if font_id.is_empty() or font_id.length() > 128 or font_size < 6 or font_size > 256:
		return DrawingResult.failure("FONT", "Invalid font identity or size")
	if alignment not in ["left", "center", "right"]:
		return DrawingResult.failure("ALIGNMENT", "Unknown text alignment")
	if not is_finite(angle) or absf(angle) > TAU * 16.0 or not scale.is_finite() \
			or scale.x < 0.125 or scale.y < 0.125 or scale.x > 16.0 or scale.y > 16.0:
		return DrawingResult.failure("TRANSFORM", "Invalid text rotation or scale")
	return DrawingResult.success()


func to_record() -> Dictionary:
	return {"content": content, "font_id": font_id, "font_size": font_size,
		"rgba": color_rgba, "position": [str(position.x), str(position.y)],
		"angle": angle, "scale": [scale.x, scale.y], "alignment": alignment}


static func from_record(record: Dictionary) -> DrawingResult:
	var item: DrawingTextElement = DrawingTextElement.new()
	for key: String in ["content", "font_id", "alignment"]:
		if not record.get(key) is String:
			return DrawingResult.failure("TEXT_RECORD", "Malformed text field: " + key)
	item.content = record["content"]
	item.font_id = record["font_id"]
	item.alignment = record["alignment"]
	for key: String in ["font_size", "rgba"]:
		if not record.get(key) is int:
			return DrawingResult.failure("TEXT_RECORD", "Malformed integer text field: " + key)
	item.font_size = record["font_size"]
	item.color_rgba = record["rgba"]
	if item.color_rgba < 0 or item.color_rgba > 0xffffffff:
		return DrawingResult.failure("TEXT_RECORD", "Invalid RGBA8 color")
	var coords: Variant = record.get("position")
	if not coords is Array or coords.size() != 2:
		return DrawingResult.failure("TEXT_RECORD", "Invalid world position")
	for coord: Variant in coords:
		if not coord is String or not coord.is_valid_int() or coord.length() > 19 or str(int(coord)) != coord:
			return DrawingResult.failure("TEXT_RECORD", "Invalid signed coordinate")
	item.position = Vector2i(int(coords[0]), int(coords[1]))
	var axis: Variant = record.get("scale")
	if not axis is Array or axis.size() != 2:
		return DrawingResult.failure("TEXT_RECORD", "Invalid text scale")
	for val: Variant in axis:
		if not val is float and not val is int:
			return DrawingResult.failure("TEXT_RECORD", "Invalid text scale")
	item.scale = Vector2(float(axis[0]), float(axis[1]))
	var radians: Variant = record.get("angle")
	if not radians is float and not radians is int:
		return DrawingResult.failure("TEXT_RECORD", "Invalid text angle")
	item.angle = float(radians)
	var checked: DrawingResult = item.validated()
	return DrawingResult.success(item) if checked.ok else checked
