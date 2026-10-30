class_name AtlasClipboard
extends RefCounted
## Versioned, self-contained clipboard text. No filesystem or OS clipboard access.

const FORMAT: String = "drawinatlas.clipboard"
const VERSION: int = 1
const MAX_TEXT_BYTES: int = 16 * 1024 * 1024
const MAX_RASTER_CHUNKS: int = 256
const GRID_KEYS: Array[String] = [
	"kind", "cell_size", "origin", "rotation", "distance_per_cell", "distance_unit", "visible"
]
const RASTER_KEYS: Array[String] = [
	"id", "name", "kind", "visible", "locked", "opacity", "pixels_per_unit", "transform", "chunks",
	"detail_level"
]
const LEGACY_RASTER_KEYS: Array[String] = [
	"id", "name", "kind", "visible", "locked", "opacity", "pixels_per_unit", "transform", "chunks"
]


## Invalid or empty selections return an empty string. Index order is preserved.
static func encode_ink(strokes: Array[AtlasStroke], indices: Array[int], anchor: Vector2) -> String:
	if indices.is_empty() or not anchor.is_finite():
		return ""
	var selected: Array[Dictionary] = []
	var seen: Dictionary[int, bool] = {}
	for index: int in indices:
		if index < 0 or index >= strokes.size() or seen.has(index):
			return ""
		seen[index] = true
		var source: AtlasStroke = strokes[index]
		if source == null or not source.is_valid():
			return ""
		var copy: AtlasStroke = source.copy()
		for point: int in range(copy.points.size()):
			copy.points[point] -= anchor
		if not copy.is_valid():
			return ""
		selected.append(copy.to_dict())
	var data: Dictionary = _envelope("INK")
	data["strokes"] = selected
	return _serialize(data)


static func encode_raster(layer: AtlasRasterLayer, anchor: Vector2) -> String:
	if layer == null or not anchor.is_finite() or layer.chunks.is_empty() \
			or layer.chunks.size() > MAX_RASTER_CHUNKS or layer.kind != "RASTER":
		return ""
	for key: String in layer.chunks:
		var chunk: AtlasRasterChunk = layer.chunks[key]
		if not _coordinate_key(key) or chunk == null or not chunk.is_valid(true) \
				or key != "%d,%d" % [chunk.coord.x, chunk.coord.y]:
			return ""
	var copy: AtlasRasterLayer = AtlasLayerCodec.clone(layer) as AtlasRasterLayer
	if copy == null:
		return ""
	copy.transform = copy.transform.translated(-anchor)
	copy.visible = true
	copy.locked = false
	var metadata: Dictionary = copy.to_dict()
	if AtlasLayerCodec.from_dict(metadata) == null:
		return ""
	var assets: Dictionary[String, String] = {}
	var encoded_size: int = 0
	for chunk: AtlasRasterChunk in copy.chunks.values():
		var ref: String = chunk.asset_id + ".webp"
		if assets.has(ref):
			continue
		var bytes: PackedByteArray = AtlasWebPStore.encode_lossless(chunk.image)
		if bytes.is_empty():
			return ""
		var base64: String = Marshalls.raw_to_base64(bytes)
		encoded_size += base64.length()
		if encoded_size > MAX_TEXT_BYTES:
			return ""
		assets[ref] = base64
	var data: Dictionary = _envelope("RASTER")
	data["raster"] = metadata
	data["assets"] = assets
	return _serialize(data)


static func encode_tiles(grid: AtlasGrid, cells: Dictionary, anchor: Vector2i) -> String:
	if grid == null or not grid.is_valid() or not _valid_cells(cells):
		return ""
	var relative: Dictionary[String, int] = {}
	for key: String in cells:
		var parts: PackedStringArray = key.split(",")
		# Subtract as 64-bit integers before checking Vector2i's bounds.
		var x: int = int(parts[0]) - anchor.x
		var y: int = int(parts[1]) - anchor.y
		if not AtlasData.integer(x) or not AtlasData.integer(y):
			return ""
		relative["%d,%d" % [x, y]] = int(cells[key])
	var data: Dictionary = _envelope("TILES")
	data["tiles"] = relative
	data["grid"] = grid.copy().to_dict()
	return _serialize(data)


static func decode(text: String) -> AtlasClipboardData:
	if text.is_empty() or text.length() > MAX_TEXT_BYTES \
			or text.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		return null
	if not _valid_json_tokens(text):
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	var data: Dictionary = json.data
	if not data.get("format") is String or data.get("format") != FORMAT \
			or not AtlasData.integer(data.get("version")) or data.get("version") != VERSION \
			or not data.get("kind") is String:
		return null
	match data["kind"]:
		"INK":
			return _decode_ink(data)
		"RASTER":
			return _decode_raster(data)
		"TILES":
			return _decode_tiles(data)
	return null


static func _decode_ink(data: Dictionary) -> AtlasClipboardData:
	if not _has_keys(data, ["format", "version", "kind", "strokes"]):
		return null
	var strokes: Variant = data["strokes"]
	if not strokes is Array or strokes.is_empty():
		return null
	var result: AtlasClipboardData = AtlasClipboardData.new()
	result.kind = "INK"
	for raw: Variant in strokes:
		if not raw is Dictionary or not raw.has("points") or not raw.has("color") or not raw.has("width"):
			return null
		for key: Variant in raw:
			if key not in ["points", "color", "width", "filled", "editable_path", "closed_path", "text", "font_family", "text_bold", "text_italic", "text_rotation"]:
				return null
		var stroke: AtlasStroke = AtlasStroke.from_dict(raw)
		if stroke == null:
			return null
		result.strokes.append(stroke)
	return result


static func _decode_raster(data: Dictionary) -> AtlasClipboardData:
	# 1. Validate the closed clipboard envelope and the layer metadata before
	#    touching any binary buffer. The layer codec rejects malformed transforms,
	#    chunk coordinates, dimensions, duplicate coordinates and asset names.
	if not _has_keys(data, ["format", "version", "kind", "raster", "assets"]):
		return null
	var metadata: Variant = data["raster"]
	var assets: Variant = data["assets"]
	if not metadata is Dictionary or not assets is Dictionary \
			or (not _has_keys(metadata, RASTER_KEYS) and not _has_keys(metadata, LEGACY_RASTER_KEYS)) \
			or not metadata["kind"] is String \
			or metadata["kind"] != "RASTER":
		return null
	var chunks: Variant = metadata["chunks"]
	if not chunks is Array or chunks.is_empty() or chunks.size() > MAX_RASTER_CHUNKS:
		return null
	for raw: Variant in chunks:
		if not raw is Dictionary or not _has_keys(raw, ["coord", "width", "height", "asset"]):
			return null
	var layer: AtlasRasterLayer = AtlasLayerCodec.from_dict(metadata) as AtlasRasterLayer
	if layer == null:
		return null

	# 2. Check the exact set of content-addressed assets, then verify their
	#    canonical base64, lossless WebP dimensions and pixel-derived hashes.
	var dimensions_by_asset: Dictionary[String, Vector2i] = _raster_asset_dimensions(layer)
	if dimensions_by_asset.is_empty() or assets.size() != dimensions_by_asset.size():
		return null
	var images_by_asset: Dictionary[String, Image] = _decode_raster_assets(assets, dimensions_by_asset)
	if images_by_asset.size() != dimensions_by_asset.size():
		return null

	# 3. Install detached pixel buffers, one per chunk even when several chunks
	#    share an asset hash, and normalize clipboard content for editing.
	for chunk: AtlasRasterChunk in layer.chunks.values():
		chunk.image = images_by_asset[chunk.asset_id + ".webp"].duplicate() as Image
	layer.visible = true
	layer.locked = false
	var result: AtlasClipboardData = AtlasClipboardData.new()
	result.kind = "RASTER"
	result.raster = layer
	return result


## Clipboard assets are keyed by pixel content address, not chunk coordinate.
## A reused address must describe the same dimensions in every chunk.
static func _raster_asset_dimensions(layer: AtlasRasterLayer) -> Dictionary[String, Vector2i]:
	var dimensions_by_asset: Dictionary[String, Vector2i] = {}
	for chunk: AtlasRasterChunk in layer.chunks.values():
		var asset_name: String = chunk.asset_id + ".webp"
		var size: Vector2i = Vector2i(chunk.width, chunk.height)
		if dimensions_by_asset.has(asset_name) and dimensions_by_asset[asset_name] != size:
			return {}
		dimensions_by_asset[asset_name] = size
	return dimensions_by_asset


## Return an empty table if *any* referenced asset fails verification; no
## caller-visible layer receives partially decoded or untrusted pixel content.
static func _decode_raster_assets(assets: Dictionary,
		dimensions_by_asset: Dictionary[String, Vector2i]) -> Dictionary[String, Image]:
	var images_by_asset: Dictionary[String, Image] = {}
	# Check every reference before decoding any bytes. An extra asset is
	# rejected by the caller's count check and a missing one fails here.
	for asset_name: String in dimensions_by_asset:
		if not assets.has(asset_name) or not assets[asset_name] is String \
				or not _valid_base64(assets[asset_name]):
			return {}
	for asset_name: String in dimensions_by_asset:
		var encoded: String = assets[asset_name]
		var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
		var padding: int = 2 if encoded.ends_with("==") else (1 if encoded.ends_with("=") else 0)
		if bytes.size() != (encoded.length() >> 2) * 3 - padding \
				or Marshalls.raw_to_base64(bytes) != encoded:
			return {}
		var dimensions: Vector2i = dimensions_by_asset[asset_name]
		var image: Image = AtlasWebPStore.decode_lossless(bytes, dimensions.x, dimensions.y)
		if image == null or image.get_width() != dimensions.x or image.get_height() != dimensions.y \
				or AtlasRasterChunk.image_hash(image) != asset_name.trim_suffix(".webp"):
			return {}
		images_by_asset[asset_name] = image
	return images_by_asset


static func _decode_tiles(data: Dictionary) -> AtlasClipboardData:
	if not _has_keys(data, ["format", "version", "kind", "tiles", "grid"]):
		return null
	var cells: Variant = data["tiles"]
	var raw_grid: Variant = data["grid"]
	if not cells is Dictionary or not _valid_cells(cells) or not raw_grid is Dictionary \
			or not _has_keys(raw_grid, GRID_KEYS):
		return null
	var grid: AtlasGrid = AtlasGrid.from_dict(raw_grid)
	if grid == null:
		return null
	var result: AtlasClipboardData = AtlasClipboardData.new()
	result.kind = "TILES"
	for key: String in cells:
		result.tiles[key] = int(cells[key])
	result.grid = grid
	return result


static func _valid_cells(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	for key: Variant in cells:
		if not _coordinate_key(key) or not AtlasData.integer(cells[key]) or int(cells[key]) < 0:
			return false
	return true


static func _coordinate_key(key: Variant) -> bool:
	if not key is String or key.length() > 23 or not AtlasData.coordinate_key(key):
		return false
	var parts: PackedStringArray = key.split(",")
	return AtlasData.integer(int(parts[0])) and AtlasData.integer(int(parts[1]))


static func _valid_base64(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_TEXT_BYTES or value.length() % 4 != 0:
		return false
	var padding: int = 2 if value.ends_with("==") else (1 if value.ends_with("=") else 0)
	for index: int in range(value.length() - padding):
		var code: int = value.unicode_at(index)
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) or code == 43 or code == 47):
			return false
	return true


static func _has_keys(data: Dictionary, keys: Array[String]) -> bool:
	if data.size() != keys.size():
		return false
	for key: String in keys:
		if not data.has(key):
			return false
	return true


static func _valid_json_tokens(text: String) -> bool:
	# Godot's JSON parser accepts trailing commas, raw controls in strings and
	# lax numeric tokens. Check those lexemes first; JSON still owns the grammar.
	var number: RegEx = RegEx.new()
	number.compile("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$")
	var controls: RegEx = RegEx.new()
	controls.compile("[\\x00-\\x1f]")
	var index: int = 0
	var previous: String = ""
	while index < text.length():
		var character: String = text[index]
		if character in [" ", "\t", "\r", "\n"]:
			index += 1
			continue
		if character in ["}", "]"] and previous == ",":
			return false
		if character == '"':
			var end: int = _json_string_end(text, index)
			if end < 0 or controls.search(text.substr(index + 1, end - index - 1)) != null:
				return false
			index = end + 1
			previous = '"'
		elif character in ["{", "}", "[", "]", ":", ","]:
			previous = character
			index += 1
		else:
			var end: int = index
			while end < text.length() and not text[end] in [" ", "\t", "\r", "\n", "{", "}", "[", "]", ":", ",", '"']:
				end += 1
			var token: String = text.substr(index, end - index)
			if token not in ["true", "false", "null"]:
				if number.search(token) == null:
					return false
				# Extreme exponents can make the native parser log warnings.
				# They cannot occur in this service's finite numeric output.
				var exponent_at: int = token.to_lower().find("e")
				if exponent_at >= 0:
					var exponent: String = token.substr(exponent_at + 1).trim_prefix("+").trim_prefix("-")
					var first_digit: int = 0
					while first_digit < exponent.length() and exponent[first_digit] == "0":
						first_digit += 1
					exponent = exponent.substr(first_digit)
					if exponent.length() > 3 or (not exponent.is_empty() and int(exponent) > 324):
						return false
			previous = token
			index = end
	return true


static func _json_string_end(text: String, start: int) -> int:
	var search_from: int = start + 1
	var end: int = -1
	while true:
		end = text.find('"', search_from)
		if end < 0:
			return -1
		var slash: int = end - 1
		while slash > start and text[slash] == "\\":
			slash -= 1
		if (end - slash - 1) % 2 == 0:
			break
		search_from = end + 1
	var token: String = text.substr(start + 1, end - start - 1)
	var index: int = token.find("\\")
	while index >= 0:
		if index + 1 >= token.length():
			return -1
		var escaped: String = token[index + 1]
		if escaped == "u":
			var hex: String = token.substr(index + 2, 4)
			if not _unicode_hex(hex):
				return -1
			var code: int = hex.hex_to_int()
			index += 6
			if code == 0:
				return -1
			if code >= 0xdc00 and code <= 0xdfff:
				return -1
			if code >= 0xd800 and code <= 0xdbff:
				if token.substr(index, 2) != "\\u":
					return -1
				var low: String = token.substr(index + 2, 4)
				if not _unicode_hex(low) \
						or low.hex_to_int() < 0xdc00 or low.hex_to_int() > 0xdfff:
					return -1
				index += 6
		elif escaped in ['"', "\\", "/", "b", "f", "n", "r", "t"]:
			index += 2
		else:
			return -1
		index = token.find("\\", index)
	return end


static func _unicode_hex(value: String) -> bool:
	return value.length() == 4 and value.is_valid_hex_number(false) \
		and not value.begins_with("+") and not value.begins_with("-")


static func _envelope(kind: String) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "kind": kind}


static func _serialize(data: Dictionary) -> String:
	var text: String = JSON.stringify(data, "", true, true)
	return text if text.length() <= MAX_TEXT_BYTES and text.to_utf8_buffer().size() <= MAX_TEXT_BYTES else ""
