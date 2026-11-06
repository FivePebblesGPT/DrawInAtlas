extends SceneTree
## Run: godot --headless --path . --script res://tests/clipboard_smoke.gd

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	_test_ink()
	_test_raster()
	_test_tiles()
	_test_invalid_envelopes()
	_test_json_syntax()
	_test_invalid_ink()
	_test_invalid_raster()
	_test_invalid_tiles()
	_test_size_limits()
	if failures == 0:
		print("ATLAS_CLIPBOARD_PASSED (%d checks)" % checks)
	else:
		push_error("ATLAS_CLIPBOARD_FAILED: %d of %d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CLIPBOARD FAILED: " + description)


func _reject(data: Variant, description: String) -> void:
	_check(AtlasClipboard.decode(JSON.stringify(data, "", true, true)) == null, description)


func _ink() -> Array[AtlasStroke]:
	return [
		AtlasStroke.new(PackedVector2Array([Vector2(-2.125, 0.375), Vector2(0.125, -0.625)]),
			Color(0.125, 0.375, 0.625, 0.5), 0.375),
		AtlasStroke.new(PackedVector2Array([Vector2(7.25, -8.5)]), Color(0.75, 0.5, 0.25, 0.125), 13.125)
	]


func _ink_wire() -> Dictionary:
	return JSON.parse_string(AtlasClipboard.encode_ink(_ink(), [1, 0], Vector2(0.25, -0.125)))


func _pixels() -> Image:
	# Include alpha=0 with nonzero hidden RGB, fractional alpha, and opaque pixels.
	return Image.create_from_data(3, 2, false, Image.FORMAT_RGBA8, PackedByteArray([
		203, 17, 91, 0, 5, 101, 239, 127, 255, 1, 2, 255,
		12, 34, 56, 1, 87, 65, 43, 254, 9, 19, 29, 0
	]))


func _raster() -> AtlasRasterLayer:
	var layer: AtlasRasterLayer = AtlasRasterLayer.new("source", "Detached image α")
	layer.visible = false
	layer.locked = true
	layer.opacity = 0.375
	layer.pixels_per_unit = 2.5
	layer.transform = Transform2D(Vector2(1.25, 0.5), Vector2(-0.75, 2.0), Vector2(8.125, -6.5))
	layer.chunks["-3,2"] = AtlasRasterChunk.new(Vector2i(-3, 2), _pixels())
	layer.chunks["1,-4"] = AtlasRasterChunk.new(Vector2i(1, -4), _pixels())
	return layer


func _raster_wire() -> Dictionary:
	var text: String = AtlasClipboard.encode_raster(_raster(), Vector2(0.25, -0.125))
	_check(not text.is_empty(), "raster fixture encodes losslessly including hidden RGB")
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _grid() -> AtlasGrid:
	var grid: AtlasGrid = AtlasGrid.new(AtlasGrid.Kind.HEX_FLAT, 17.125)
	grid.origin = Vector2(-3.25, 7.875)
	grid.rotation = 0.325
	grid.distance_per_cell = 2.75
	grid.distance_unit = "km"
	grid.visible = false
	return grid


func _tiles_wire() -> Dictionary:
	return JSON.parse_string(AtlasClipboard.encode_tiles(_grid(), {"-4,2": 3, "1,-3": 5}, Vector2i(-3, 2)))


func _test_ink() -> void:
	var strokes: Array[AtlasStroke] = _ink()
	var before: Array[AtlasStroke] = AtlasStroke.clone_all(strokes)
	var anchor: Vector2 = Vector2(0.25, -0.125)
	var text: String = AtlasClipboard.encode_ink(strokes, [1, 0], anchor)
	_check(not text.is_empty(), "ink encodes")
	_check(AtlasStroke.same_artwork(strokes, before), "ink encoding leaves source unchanged")
	var decoded: AtlasClipboardData = AtlasClipboard.decode(text)
	_check(decoded != null, "ink decodes")
	if decoded == null:
		return
	_check(decoded.kind == "INK" and decoded.strokes.size() == 2 and decoded.raster == null
		and decoded.tiles.is_empty() and decoded.grid == null, "ink has typed isolated payload")
	for index: int in range(decoded.strokes.size()):
		var source: AtlasStroke = before[1 - index]
		var pasted: AtlasStroke = decoded.strokes[index]
		_check(pasted.color == source.color and pasted.width == source.width, "ink preserves RGBA and widths")
		for point: int in range(source.points.size()):
			_check(pasted.points[point] == source.points[point] - anchor, "ink retains negative/subcell relative points")
	decoded.strokes[0].points[0] = Vector2(999, 999)
	decoded.strokes[0].color = Color.WHITE
	decoded.strokes[0].width = 99.0
	_check(AtlasStroke.same_artwork(strokes, before), "decoded ink has independent editable geometry")
	strokes[0].points[0] = Vector2(100, 100)
	var again: AtlasClipboardData = AtlasClipboard.decode(text)
	_check(again != null and again.strokes[1].points[0] == before[0].points[0] - anchor,
		"clipboard text is an immutable source snapshot")
	var single: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_ink(_ink(), [1], anchor))
	_check(single != null and single.strokes.size() == 1, "only selected ink is copied")


func _test_raster() -> void:
	var layer: AtlasRasterLayer = _raster()
	var before: Dictionary = layer.to_dict()
	var pixels: PackedByteArray = layer.chunks["-3,2"].image.get_data()
	var anchor: Vector2 = Vector2(-2.125, 3.75)
	var text: String = AtlasClipboard.encode_raster(layer, anchor)
	var decoded: AtlasClipboardData = AtlasClipboard.decode(text)
	_check(decoded != null, "self-contained raster roundtrip")
	_check(layer.to_dict() == before and layer.chunks["-3,2"].image.get_data() == pixels,
		"raster encode never mutates metadata or pixels")
	if decoded == null:
		return
	var copy: AtlasRasterLayer = decoded.raster
	_check(decoded.kind == "RASTER" and copy != null and decoded.strokes.is_empty()
		and decoded.tiles.is_empty() and decoded.grid == null, "raster result has typed payload")
	_check(copy.visible and not copy.locked and copy.opacity == layer.opacity
		and copy.pixels_per_unit == layer.pixels_per_unit and copy.display_name == layer.display_name,
		"pasted raster is editable/visible and preserves opacity, scale, name")
	_check(copy.transform == Transform2D(0.0, -anchor) * layer.transform,
		"anchor translation left-multiplies rotated/sheared/scaled transform")
	_check(copy.chunks.has("-3,2") and copy.chunks.has("1,-4"), "negative raster chunk coordinates survive")
	for key: String in copy.chunks:
		var chunk: AtlasRasterChunk = copy.chunks[key]
		_check(chunk.image.get_data() == pixels and chunk.width == 3 and chunk.height == 2,
			"actual RGBA bytes including alpha and hidden RGB survive lossless WebP")
		_check(chunk.asset_id == layer.chunks[key].asset_id, "verified pixel content address survives")
	var wire: Dictionary = JSON.parse_string(text)
	_check(wire.assets.size() == 1, "shared content address has one embedded buffer")
	var asset: String = wire.assets.keys()[0]
	var bytes: PackedByteArray = Marshalls.base64_to_raw(wire.assets[asset])
	_check(bytes.slice(8, 12).get_string_from_ascii() == "WEBP", "embedded bytes are WebP")
	copy.chunks["-3,2"].image.set_pixel(0, 0, Color.WHITE)
	_check(copy.chunks["1,-4"].image.get_data() == pixels, "same-asset chunks own independent images")
	_check(layer.chunks["-3,2"].image.get_data() == pixels, "decoded raster pixels are detached from source")
	layer.chunks["1,-4"].image.fill(Color.BLACK)
	var again: AtlasClipboardData = AtlasClipboard.decode(text)
	_check(again != null and again.raster.chunks["1,-4"].image.get_data() == pixels,
		"raster text retains captured pixels after source edits")
	var reshaped: Image = Image.create_from_data(2, 3, false, Image.FORMAT_RGBA8, pixels)
	_check(AtlasRasterChunk.image_hash(reshaped) != AtlasRasterChunk.image_hash(_pixels()),
		"pixel identity includes dimensions")


func _test_tiles() -> void:
	var grid: AtlasGrid = _grid()
	var cells: Dictionary = {"-4,2": 3, "1,-3": 5, "-3,2": 0}
	var before: Dictionary = cells.duplicate(true)
	var decoded: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_tiles(grid, cells, Vector2i(-3, 2)))
	_check(decoded != null, "tiles roundtrip")
	_check(cells == before and grid.same_as(_grid()), "tile encoding preserves source cells/grid")
	if decoded == null:
		return
	_check(decoded.kind == "TILES" and decoded.tiles == {"-1,0": 3, "4,-5": 5, "0,0": 0},
		"tile coordinates normalized around anchor, palette IDs preserved")
	_check(decoded.tiles["-1,0"] is int, "decoded palettes are integers")
	_check(decoded.grid != grid and decoded.grid.same_as(grid), "all explicit grid metadata preserved for compatibility")
	_check(decoded.strokes.is_empty() and decoded.raster == null, "tile payload excludes other artwork")
	decoded.tiles["-1,0"] = 1
	decoded.grid.origin = Vector2.ZERO
	_check(cells == before and grid.same_as(_grid()), "decoded cells and grid detached from source")
	for kind: int in AtlasGrid.Kind.values():
		var example: AtlasGrid = _grid()
		example.kind = kind
		var result: AtlasClipboardData = AtlasClipboard.decode(AtlasClipboard.encode_tiles(example, cells, Vector2i.ZERO))
		_check(result != null and result.grid.same_as(example), "grid kind %d preserved" % kind)


func _test_invalid_envelopes() -> void:
	for text: String in ["", "plain user text", "{", "[]", "null", "true", "42", "\"hello\"", "{}"]:
		_check(AtlasClipboard.decode(text) == null, "invalid/nonclipboard text rejected: " + text)
	var valid: Dictionary = _ink_wire()
	for key: String in ["format", "version", "kind", "strokes"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(key)
		_reject(missing, "missing envelope field " + key)
	for key: String in ["format", "version", "kind"]:
		for bad: Variant in [null, false, [], {}, "", "UNKNOWN", -1, 0, 2, 1.5]:
			var data: Dictionary = valid.duplicate(true)
			data[key] = bad
			_reject(data, "wrong envelope type/value " + key)
	var extra: Dictionary = valid.duplicate(true)
	extra["path"] = "res://external.webp"
	_reject(extra, "unknown external reference field rejected")
	var reordered: Dictionary = {"strokes": valid.strokes, "kind": "INK", "version": 1, "format": AtlasClipboard.FORMAT}
	_check(AtlasClipboard.decode(JSON.stringify(reordered, "", false, true)) != null,
		"top marker recognition independent of JSON key ordering")
	var canonical: String = JSON.stringify(valid)
	for malformed: String in [canonical + " trailing", canonical + "{}", canonical.left(-1) + ",}"]:
		_check(AtlasClipboard.decode(malformed) == null, "malformed JSON document rejected")


func _test_invalid_ink() -> void:
	for raw: Array in [[], [-1], [2], [0, 0], [0, 2]]:
		var indices: Array[int] = []
		indices.assign(raw)
		_check(AtlasClipboard.encode_ink(_ink(), indices, Vector2.ZERO).is_empty(), "invalid selection rejected")
	_check(AtlasClipboard.encode_ink([null], [0], Vector2.ZERO).is_empty(), "null selected stroke rejected")
	_check(AtlasClipboard.encode_ink([AtlasStroke.new()], [0], Vector2.ZERO).is_empty(), "invalid selected stroke rejected")
	for bad: float in [INF, -INF, NAN]:
		_check(AtlasClipboard.encode_ink(_ink(), [0], Vector2(bad, 0)).is_empty(), "nonfinite ink anchor rejected")
	var valid: Dictionary = _ink_wire()
	for bad: Variant in [null, true, 7, "ink", {}, [], [null], [true], [7], [[]], [{}]]:
		var data: Dictionary = valid.duplicate(true)
		data["strokes"] = bad
		_reject(data, "wrong/empty stroke collection rejected")
	for key: String in ["points", "color", "width"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.strokes[0].erase(key)
		_reject(missing, "missing stroke primitive " + key)
		for bad: Variant in [null, true, "bad", {}, [], -1, 0, [["x", 0]], [1, 2, 3]]:
			var data: Dictionary = valid.duplicate(true)
			data.strokes[0][key] = bad
			_reject(data, "wrong stroke primitive " + key)
	_check(AtlasClipboard.decode('{"format":"drawinatlas.clipboard","version":1,"kind":"INK",'
		+ '"strokes":[{"points":[[1e999,0]],"color":[0,0,0,1],"width":1}]}') == null,
		"nonfinite JSON numeric overflow rejected")
	var extra: Dictionary = valid.duplicate(true)
	extra.strokes[0]["file"] = "../stroke"
	_reject(extra, "stroke external references rejected")


func _test_json_syntax() -> void:
	var valid: String = JSON.stringify(_ink_wire())
	for bad: String in ["+1", "01", "1.", ".1", "1e", "1e+", "NaN", "Infinity", "1e999"]:
		_check(AtlasClipboard.decode(valid.replace("13.125", bad)) == null, "invalid/nonfinite numeric token rejected: " + bad)
	for good: String in ["1", "1.0", "1e0", "1E+0", "1.125e-3"]:
		_check(AtlasClipboard.decode(valid.replace("13.125", good)) != null, "standard JSON number accepted: " + good)
	var tiles: String = JSON.stringify(_tiles_wire())
	for escaped: String in ["\\\"", "\\\\", "\\/", "\\b", "\\f", "\\n", "\\r", "\\t", "\\u03b1", "\\ud83d\\uddfa"]:
		var text: String = tiles.replace('"km"', '"unit' + escaped + '"')
		_check(AtlasClipboard.decode(text) != null, "valid JSON string escape accepted: " + escaped)
	for escaped: String in ["\\q", "\\x41", "\\u123", "\\uZZZZ", "\\u+123", "\\u-123", "\\ud800", "\\udc00", "\\ud800\\u0061", "\\u0000", "\n", "\t", String.chr(1)]:
		var text: String = tiles.replace('"km"', '"unit' + escaped + '"')
		_check(AtlasClipboard.decode(text) == null, "malformed string/control/surrogate rejected")
	var punctuation: String = tiles.replace('"km"', JSON.stringify('Escaped "quote", \\slash },] and emoji 🗺'))
	_check(AtlasClipboard.decode(punctuation) != null, "punctuation inside strings does not affect syntax precheck")
	_check(AtlasClipboard.decode(valid.replace('"points":[[', '"points":[,[')) == null,
		"leading array comma rejected")
	_check(AtlasClipboard.decode(valid.replace('"width":13.125}', '"width":13.125,}')) == null,
		"nested trailing comma rejected")


func _test_invalid_raster() -> void:
	_check(AtlasClipboard.encode_raster(null, Vector2.ZERO).is_empty(), "null raster rejected")
	_check(AtlasClipboard.encode_raster(AtlasRasterLayer.new(), Vector2.ZERO).is_empty(), "empty raster rejected")
	var source: AtlasRasterLayer = _raster()
	source.chunks["0,0"] = null
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "null chunk rejected without script error")
	source = _raster()
	source.chunks["wrong"] = source.chunks["-3,2"]
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "noncanonical source chunk key rejected")
	source = _raster()
	source.chunks["-3,2"].image = null
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "unresolved external-only chunk rejected")
	for bad: float in [INF, -INF, NAN]:
		_check(AtlasClipboard.encode_raster(_raster(), Vector2(bad, 0)).is_empty(), "nonfinite raster anchor rejected")
	source = _raster()
	source.transform = Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "singular source raster transform rejected")
	source = _raster()
	source.chunks["-3,2"].width = 257
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "oversized source raster chunk rejected")
	var valid: Dictionary = _raster_wire()
	if valid.is_empty():
		return
	for key: String in ["raster", "assets"]:
		for bad: Variant in [null, true, 3, "path.webp", [], {}]:
			var data: Dictionary = valid.duplicate(true)
			data[key] = bad
			_reject(data, "wrong raster envelope field " + key)
	for key: String in AtlasClipboard.RASTER_KEYS:
		var missing: Dictionary = valid.duplicate(true)
		missing.raster.erase(key)
		_reject(missing, "missing raster metadata " + key)
		for bad: Variant in [null, [], {}]:
			var data: Dictionary = valid.duplicate(true)
			data.raster[key] = bad
			_reject(data, "wrong raster metadata type " + key)
	for key: String in ["coord", "width", "height", "asset"]:
		var missing: Dictionary = valid.duplicate(true)
		missing.raster.chunks[0].erase(key)
		_reject(missing, "missing chunk field " + key)
		for bad: Variant in [null, true, [], {}, "bad", -1, 0, 257, 1.5]:
			var data: Dictionary = valid.duplicate(true)
			data.raster.chunks[0][key] = bad
			_reject(data, "invalid chunk field " + key)
	for bad: Variant in [[], [0, 0], [1, 0, 0, 0, 0, 0], [1, 0, 0, 1, "x", 0], [1e100, 0, 0, 1, 0, 0]]:
		var data: Dictionary = valid.duplicate(true)
		data.raster["transform"] = bad
		_reject(data, "invalid/singular/overflowed transform rejected")
	for key: String in ["opacity", "pixels_per_unit"]:
		var data: Dictionary = valid.duplicate(true)
		data.raster[key] = -0.5
		_reject(data, "out-of-range raster number " + key)
	for patch: Dictionary in [{"opacity": 1.01}, {"visible": 1}, {"locked": "false"}, {"pixels_per_unit": 0},
			{"id": true}, {"id": " "}, {"name": false}, {"name": ""}, {"kind": "INK"}, {"path": "../asset"}]:
		var data: Dictionary = valid.duplicate(true)
		data.raster.merge(patch, true)
		_reject(data, "wrong raster primitive/range/extra reference rejected")
	var duplicate: Dictionary = valid.duplicate(true)
	duplicate.raster.chunks.append(duplicate.raster.chunks[0].duplicate(true))
	_reject(duplicate, "duplicate raster coordinate rejected")
	for coord: Variant in [[2147483648, 0], [-2147483649, 0], [0.5, 0], [0, "0"]]:
		var data: Dictionary = valid.duplicate(true)
		data.raster.chunks[0]["coord"] = coord
		_reject(data, "out-of-range/wrong-type chunk coordinate rejected")
	var ref: String = valid.assets.keys()[0]
	for bad: String in ["../" + ref, "/tmp/" + ref, "res://" + ref, "user://" + ref, ref.to_upper(), ref.trim_suffix(".webp") + ".png"]:
		var data: Dictionary = valid.duplicate(true)
		data.raster.chunks[0]["asset"] = bad
		_reject(data, "external/traversal/noncanonical asset reference rejected")
	var unreferenced: Dictionary = valid.duplicate(true)
	unreferenced.assets["../external.webp"] = valid.assets[ref]
	_reject(unreferenced, "unreferenced embedded asset rejected")
	var mismatch: Dictionary = valid.duplicate(true)
	mismatch.raster.chunks[0]["width"] = 2
	_reject(mismatch, "same ID with mismatched dimensions rejected before decoding")
	for bad: Variant in [null, 7, true, [], {}, "", "x", "====", "AA=A", "AA==AAAA", "!!!!", "A A=", "AB==", "AAA\n"]:
		var data: Dictionary = valid.duplicate(true)
		data.assets[ref] = bad
		_reject(data, "invalid/noncanonical base64 rejected")
	for bytes: PackedByteArray in [PackedByteArray([1, 2, 3, 4]), _pixels().save_png_to_buffer(), _pixels().save_webp_to_buffer(true)]:
		var data: Dictionary = valid.duplicate(true)
		data.assets[ref] = Marshalls.raw_to_base64(bytes)
		_reject(data, "corrupt/PNG/lossy WebP rejected")
	var truncated: PackedByteArray = Marshalls.base64_to_raw(valid.assets[ref])
	truncated.resize(truncated.size() - 1)
	var corrupt: Dictionary = valid.duplicate(true)
	corrupt.assets[ref] = Marshalls.raw_to_base64(truncated)
	_reject(corrupt, "truncated WebP rejected")
	var different: Image = _pixels()
	different.set_pixel(1, 0, Color.WHITE)
	var hash_mismatch: Dictionary = valid.duplicate(true)
	hash_mismatch.assets[ref] = Marshalls.raw_to_base64(AtlasWebPStore.encode_lossless(different))
	_reject(hash_mismatch, "valid lossless buffer with wrong pixel hash rejected")
	var dimension_mismatch: Dictionary = valid.duplicate(true)
	for raw: Dictionary in dimension_mismatch.raster.chunks:
		raw["width"] = 2
	_reject(dimension_mismatch, "buffer dimensions must match all valid metadata refs")
	var reshape: Image = Image.create_from_data(2, 3, false, Image.FORMAT_RGBA8, _pixels().get_data())
	var shape_attack: Dictionary = valid.duplicate(true)
	for raw: Dictionary in shape_attack.raster.chunks:
		raw["width"] = 2
		raw["height"] = 3
	shape_attack.assets[ref] = Marshalls.raw_to_base64(AtlasWebPStore.encode_lossless(reshape))
	_reject(shape_attack, "same pixel bytes reshaped cannot impersonate dimension-sensitive asset ID")
	var flags: Dictionary = valid.duplicate(true)
	flags.raster["visible"] = false
	flags.raster["locked"] = true
	var normalized: AtlasClipboardData = AtlasClipboard.decode(JSON.stringify(flags))
	_check(normalized != null and normalized.raster.visible and not normalized.raster.locked,
		"decode also normalizes pasted visibility and locking")


func _test_invalid_tiles() -> void:
	_check(AtlasClipboard.encode_tiles(null, {"0,0": 1}, Vector2i.ZERO).is_empty(), "null grid rejected")
	_check(AtlasClipboard.encode_tiles(_grid(), {}, Vector2i.ZERO).is_empty(), "empty tile selection rejected")
	var invalid: Array[Dictionary] = [
		{Vector2i.ZERO: 1}, {"01,0": 1}, {"-0,0": 1}, {"+1,0": 1}, {"1, 0": 1},
		{"1": 1}, {"1,2,3": 1}, {"2147483648,0": 1}, {"-2147483649,0": 1},
		{"999999999999999999999999999999,0": 1}, {"0,0": -1}, {"0,0": 1.5},
		{"0,0": true}, {"0,0": "1"}, {"0,0": null}, {"0,0": []}, {"0,0": {}}, {"0,0": 2147483648}
	]
	var valid: Dictionary = _tiles_wire()
	for cells: Dictionary in invalid:
		_check(AtlasClipboard.encode_tiles(_grid(), cells, Vector2i.ZERO).is_empty(), "invalid source tile key/palette rejected")
		if cells.keys()[0] is String:
			var data: Dictionary = valid.duplicate(true)
			data["tiles"] = cells
			_reject(data, "invalid decoded tile key/palette rejected")
	_check(AtlasClipboard.encode_tiles(_grid(), {"2147483647,0": 1}, Vector2i(-1, 0)).is_empty(),
		"relative tile coordinate overflow rejected before Vector2i conversion")
	for key: String in ["tiles", "grid"]:
		for bad: Variant in [null, true, 7, "bad", [], {}]:
			var data: Dictionary = valid.duplicate(true)
			data[key] = bad
			_reject(data, "wrong tile envelope type " + key)
	for key: String in AtlasClipboard.GRID_KEYS:
		var missing: Dictionary = valid.duplicate(true)
		missing.grid.erase(key)
		_reject(missing, "grid metadata must be explicit: " + key)
		for bad: Variant in [null, [], {}]:
			var data: Dictionary = valid.duplicate(true)
			data.grid[key] = bad
			_reject(data, "wrong grid metadata type " + key)
	for patch: Dictionary in [
		{"kind": 99}, {"kind": true}, {"kind": 1.5}, {"cell_size": 0}, {"cell_size": -1},
		{"origin": [1e100, 0]}, {"origin": [0, "0"]}, {"distance_per_cell": 0},
		{"distance_unit": " "}, {"visible": 1}, {"rotation": "0"}, {"path": "../grid"}
	]:
		var data: Dictionary = valid.duplicate(true)
		data.grid.merge(patch, true)
		_reject(data, "invalid grid primitive/range/extra reference rejected")
	for bad: float in [INF, -INF, NAN]:
		var grid: AtlasGrid = _grid()
		grid.rotation = bad
		_check(AtlasClipboard.encode_tiles(grid, {"0,0": 1}, Vector2i.ZERO).is_empty(), "nonfinite source grid rejected")


func _test_size_limits() -> void:
	_check(AtlasClipboard.MAX_TEXT_BYTES == 16 * 1024 * 1024, "clipboard text limit is 16 MiB")
	_check(AtlasClipboard.decode(" ".repeat(AtlasClipboard.MAX_TEXT_BYTES + 1)) == null, "oversized ASCII payload rejected")
	_check(AtlasClipboard.decode("α".repeat(AtlasClipboard.MAX_TEXT_BYTES / 2 + 1)) == null, "limit counts UTF-8 bytes")
	var boundary: Dictionary = _tiles_wire()
	boundary.grid["distance_unit"] = ""
	var overhead: int = JSON.stringify(boundary).to_utf8_buffer().size()
	boundary.grid["distance_unit"] = "x".repeat(AtlasClipboard.MAX_TEXT_BYTES - overhead)
	var exact: String = JSON.stringify(boundary)
	_check(exact.to_utf8_buffer().size() == AtlasClipboard.MAX_TEXT_BYTES, "exact text boundary fixture")
	_check(AtlasClipboard.decode(exact) != null, "exactly 16 MiB valid payload accepted")
	_check(AtlasClipboard.decode(exact + " ") == null, "valid JSON one byte above limit rejected")
	var source: AtlasRasterLayer = _raster()
	var valid: Dictionary = _raster_wire()
	if valid.is_empty():
		return
	var template: Dictionary = valid.raster.chunks[0].duplicate(true)
	valid.raster.chunks.clear()
	source.chunks.clear()
	for index: int in range(AtlasClipboard.MAX_RASTER_CHUNKS):
		var raw: Dictionary = template.duplicate(true)
		raw["coord"] = [index, -1]
		valid.raster.chunks.append(raw)
		source.chunks["%d,-1" % index] = AtlasRasterChunk.new(Vector2i(index, -1), _pixels())
	_check(AtlasClipboard.decode(JSON.stringify(valid)) != null, "exactly 256 raster chunks accepted")
	_check(not AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "encoder accepts exactly 256 chunks")
	var excess: Dictionary = template.duplicate(true)
	excess["coord"] = [256, -1]
	valid.raster.chunks.append(excess)
	_reject(valid, "257 chunks rejected before decoding")
	source.chunks["256,-1"] = AtlasRasterChunk.new(Vector2i(256, -1), _pixels())
	_check(AtlasClipboard.encode_raster(source, Vector2.ZERO).is_empty(), "encoder rejects 257 chunks")
	var large: AtlasGrid = _grid()
	large.distance_unit = "α".repeat(AtlasClipboard.MAX_TEXT_BYTES / 2)
	_check(AtlasClipboard.encode_tiles(large, {"0,0": 1}, Vector2i.ZERO).is_empty(), "encoder bounds serialized UTF-8 size")
