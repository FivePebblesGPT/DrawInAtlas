class_name AtlasTextLayout
extends RefCounted
## Text uses board-space font sizes and anchors. Culling is presentation only.

const MIN_SIZE: float = 6.0
const MAX_SIZE: float = 256.0
const MAX_CHARS: int = 2048
## Determined against native 960x660/800x600 visual probes: below 9 px
## lowercase characters become indistinct at normal monitor scaling.
const MIN_READABLE_SCREEN_PX: float = 9.0
const FAMILIES: Array[String] = ["Sans", "Serif", "Monospace"]
static var _fonts: Dictionary[String, Font] = {}


static func font_for(stroke: AtlasStroke) -> Font:
	var key: String = "%s:%s:%s" % [stroke.font_family, stroke.text_bold, stroke.text_italic]
	if not _fonts.has(key):
		var face: SystemFont = SystemFont.new()
		match stroke.font_family:
			"Serif": face.font_names = PackedStringArray(["DejaVu Serif", "Liberation Serif", "Times New Roman"])
			"Monospace": face.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New"])
			_: face.font_names = PackedStringArray(["DejaVu Sans", "Liberation Sans", "Arial"])
		face.font_weight = 700 if stroke.text_bold else 400
		face.font_italic = stroke.text_italic
		_fonts[key] = face
	return _fonts[key]


static func bounds(stroke: AtlasStroke) -> Rect2:
	var font: Font = font_for(stroke)
	var size: int = maxi(1, roundi(stroke.width))
	var max_width: float = 1.0
	var lines: PackedStringArray = stroke.text.split("\n", true)
	for line: String in lines:
		max_width = maxf(max_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var local_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(max_width, maxf(1.0, font.get_height(size)) * lines.size()))
	var transform: Transform2D = Transform2D(stroke.text_rotation, stroke.points[0])
	var result: Rect2 = Rect2(transform * local_rect.position, Vector2.ZERO)
	for corner: Vector2 in [Vector2(local_rect.end.x, 0), local_rect.end, Vector2(0, local_rect.end.y)]:
		result = result.expand(transform * corner)
	return result


static func readable(stroke: AtlasStroke, zoom: float) -> bool:
	return stroke.width * zoom >= MIN_READABLE_SCREEN_PX


static func make(anchor: Vector2, content: String, family: String, size: float,
		color: Color, bold: bool = false, italic: bool = false) -> AtlasStroke:
	var result: AtlasStroke = AtlasStroke.new(PackedVector2Array([anchor]), color, size)
	result.text = content
	result.font_family = family
	result.text_bold = bold
	result.text_italic = italic
	return result if result.is_valid() else null
