class_name DrawingTextRaster
extends RefCounted
## Shared CPU compositor for editable text and its irreversible pixel conversion.
## Uses Godot's real shaped OpenType glyph atlas, no screen-capture timing.

const FONT_PATH: String = "res://addons/drawing/fonts/Lato-Regular.ttf"
const FONT_ID: String = DrawingTextElement.DEFAULT_FONT
const FONT_FILES: Dictionary = {
	"lato-regular-v1": "res://addons/drawing/fonts/Lato-Regular.ttf",
	"lato-bold-v1": "res://addons/drawing/fonts/Lato-Bold.ttf",
	"lato-italic-v1": "res://addons/drawing/fonts/Lato-Italic.ttf",
}
static var _fonts: Dictionary[String, FontFile] = {}


static func font_path(font_id: String) -> String:
	return String(FONT_FILES.get(font_id, ""))


static func font_status(font_id: String) -> DrawingResult:
	var path: String = font_path(font_id)
	if path.is_empty():
		return DrawingResult.failure("FONT_MISSING", "Font '" + font_id + "' is not bundled; no silent substitution")
	if not _fonts.has(font_id):
		# Godot exports imported FontFile resources, not their original .ttf files.
		# Resource data retains the exact licensed OpenType bytes in both builds.
		var loaded: FontFile = load(path) as FontFile
		if loaded == null or loaded.get_data().is_empty():
			return DrawingResult.failure("FONT_MISSING", "Required bundled font unavailable: " + path)
		_fonts[font_id] = loaded
	return DrawingResult.success(_fonts[font_id])


static func _layout(item: DrawingTextElement) -> DrawingResult:
	var status: DrawingResult = font_status(item.font_id)
	if not status.ok:
		return status
	var font: FontFile = status.value as FontFile
	var server: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var lines: PackedStringArray = item.content.split("\n", true)
	var glyphs: Array[Dictionary] = []
	var missing: Dictionary[int, bool] = {}
	var ascent: float = font.get_ascent(item.font_size)
	var line_advance: float = ceilf(font.get_height(item.font_size) * 1.2)
	for line_number: int in range(lines.size()):
		var text: String = lines[line_number]
		var display_text: String = ""
		for codepoint_index: int in range(text.length()):
			var codepoint: int = text.unicode_at(codepoint_index)
			if codepoint > 32 and not server.font_has_char(rid, codepoint):
				missing[codepoint] = true
				display_text += "?"  # Visible placeholder; original semantic text is never changed.
			else:
				display_text += text.substr(codepoint_index, 1)
		var shaped: RID = server.create_shaped_text()
		var added: bool = server.shaped_text_add_string(shaped, display_text, [rid], item.font_size)
		if not added or not server.shaped_text_shape(shaped):
			server.free_rid(shaped)
			return DrawingResult.failure("TEXT_SHAPE", "Font layout failed")
		var width: float = server.shaped_text_get_width(shaped)
		var indent: float = 0.0 if item.alignment == "left" else -width * (0.5 if item.alignment == "center" else 1.0)
		var pen: float = indent
		for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
			var gl_index: int = glyph["index"]
			var font_size: int = glyph["font_size"]
			var dim: Vector2i = Vector2i(font_size, 0)
			var uv: Rect2 = font.get_glyph_uv_rect(0, dim, gl_index)
			var tex: int = font.get_glyph_texture_idx(0, dim, gl_index)
			if tex >= 0 and uv.has_area():
				glyphs.append({"uv": uv, "texture": tex, "size": dim,
					"baseline": Vector2(pen, ascent + line_advance * line_number) + \
					Vector2(glyph["offset"]) + font.get_glyph_offset(0, dim, gl_index)})
			pen += float(glyph["advance"]) * int(glyph["repeat"])
		server.free_rid(shaped)
	var result: DrawingResult = DrawingResult.success(glyphs)
	if not missing.is_empty():
		result.code = "GLYPH_FALLBACK"
		var report: Array[String] = []
		for codepoint: int in missing:
			report.append("U+%04X" % codepoint)
		result.message = "Bundled font substituted visible '?' for unsupported " + ", ".join(report)
	return result


static func _transform(item: DrawingTextElement) -> Transform2D:
	return Transform2D(item.angle, item.scale, 0.0, Vector2(item.position))


static func bounds(item: DrawingTextElement) -> DrawingResult:
	var layout: DrawingResult = _layout(item)
	if not layout.ok:
		return layout
	var mapping: Transform2D = _transform(item)
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for glyph: Dictionary in layout.value:
		var uv: Rect2 = glyph["uv"]
		var origin: Vector2 = glyph["baseline"]
		for corner: Vector2 in [Vector2.ZERO, Vector2(uv.size.x, 0), uv.size, Vector2(0, uv.size.y)]:
			var transformed: Vector2 = mapping * (origin + corner)
			low = low.min(transformed)
			high = high.max(transformed)
	if low.x == INF:
		return DrawingResult.success(Rect2i(item.position, Vector2i.ZERO))
	var result: DrawingResult = DrawingResult.success(Rect2i(Vector2i(floori(low.x), floori(low.y)),
		Vector2i(ceili(high.x) - floori(low.x), ceili(high.y) - floori(low.y))))
	result.code = layout.code
	result.message = layout.message
	return result


## Draw into a bounded straight-RGBA8 buffer, preserving hidden RGB of untouched pixels.
## Area is in signed world pixels. Source-over alpha uses Drawing's one compositor.
static func composite(item: DrawingTextElement, area: Rect2i,
		bytes: PackedByteArray) -> DrawingResult:
	if bytes.size() != area.size.x * area.size.y * 4:
		return DrawingResult.failure("BUFFER", "Invalid text target size")
	# Conservatively reject far-off labels BEFORE shaping glyphs. This square
	# overestimates every supported affine text size, including 360° rotation.
	var lines: PackedStringArray = item.content.split("\n", true)
	var longest: int = 0
	for line: String in lines:
		longest = maxi(longest, line.length())
	var reach: float = float(maxi(longest, lines.size()) + 2) * float(item.font_size) * \
		maxf(item.scale.x, item.scale.y) * 4.0
	if float(area.end.x) < float(item.position.x) - reach or \
			float(area.position.x) > float(item.position.x) + reach or \
			float(area.end.y) < float(item.position.y) - reach or \
			float(area.position.y) > float(item.position.y) + reach:
		return DrawingResult.success()
	var layout: DrawingResult = _layout(item)
	if not layout.ok:
		return layout
	var mapping: Transform2D = _transform(item)
	var inverse: Transform2D = mapping.affine_inverse()
	var font: FontFile = _fonts[item.font_id]
	var foreground: int = item.color_rgba & 0x00ffffff
	var opacity: int = (item.color_rgba >> 24) & 255
	var atlases: Dictionary[int, Image] = {}
	for glyph: Dictionary in layout.value:
		var uv: Rect2 = glyph["uv"]
		var uv_rect: Rect2i = Rect2i(Vector2i(uv.position), Vector2i(uv.size))
		var local: Vector2 = glyph["baseline"]
		var aabb_min: Vector2 = Vector2(INF, INF)
		var aabb_max: Vector2 = Vector2(-INF, -INF)
		for corner: Vector2 in [Vector2.ZERO, Vector2(uv.size.x, 0), uv.size, Vector2(0, uv.size.y)]:
			var point: Vector2 = mapping * (local + corner)
			aabb_min = aabb_min.min(point)
			aabb_max = aabb_max.max(point)
		var intersection: Rect2i = Rect2i(Vector2i(floori(aabb_min.x), floori(aabb_min.y)),
			Vector2i(ceili(aabb_max.x) - floori(aabb_min.x), ceili(aabb_max.y) - floori(aabb_min.y))).intersection(area)
		if not intersection.has_area():
			continue
		var tex: int = glyph["texture"]
		if not atlases.has(tex):
			atlases[tex] = font.get_texture_image(0, glyph["size"], tex)
		var atlas: Image = atlases[tex]
		if atlas == null or atlas.is_empty():
			return DrawingResult.failure("FONT_ATLAS", "Font glyph bitmap unavailable")
		for y: int in range(intersection.position.y, intersection.end.y):
			for x: int in range(intersection.position.x, intersection.end.x):
				var point: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - local
				var local_x: int = floori(point.x)
				var local_y: int = floori(point.y)
				if local_x < 0 or local_y < 0 or local_x >= uv_rect.size.x or local_y >= uv_rect.size.y:
					continue
				var coverage: int = roundi(atlas.get_pixel(uv_rect.position.x + local_x,
						uv_rect.position.y + local_y).a * float(opacity))
				if coverage <= 0:
					continue
				var index: int = ((y - area.position.y) * area.size.x + (x - area.position.x)) * 4
				var background: int = 0
				for channel: int in range(4):
					background |= int(bytes[index + channel]) << (channel * 8)
				var blended: int = DrawingEditSession._blend(foreground | (coverage << 24), background)
				for channel: int in range(4):
					bytes[index + channel] = (blended >> (channel * 8)) & 255
	var result: DrawingResult = DrawingResult.success()
	result.code = layout.code
	result.message = layout.message
	return result
