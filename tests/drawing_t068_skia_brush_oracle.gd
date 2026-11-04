extends SceneTree
## T-068: generate pinned hard-brush/selection fixtures from the *real*
## DrawingEditSession, not an approximation of its geometry or RGBA8 blending.
##
## Run after Godot's resource import with:
##   godot --headless --path . --script res://tests/drawing_t068_skia_brush_oracle.gd -- /tmp/oracle.json

const SIDE: int = 32
const ANCHOR_X: int = 9007199254740993
const ANCHOR_Y: int = -9007199254740993


func _initialize() -> void:
	call_deferred("_generate")


func _source_bytes() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(SIDE * SIDE * 4)
	for y: int in range(SIDE):
		for x: int in range(SIDE):
			var offset: int = (y * SIDE + x) * 4
			data[offset] = (x * 19 + y * 11 + 31) & 255
			data[offset + 1] = (x * 7 + y * 23 + 53) & 255
			data[offset + 2] = (x * 3 + y * 17 + 79) & 255
			data[offset + 3] = [0, 1, 64, 128, 254, 255][(x + y * 3) % 6]
	return data


func _cases() -> Array[Dictionary]:
	return [
		{"id": "stationary_dab", "path": [[16.0, 16.0]], "width": 5.0,
			"paint": [219, 41, 87, 255], "erase": false, "selection": "none"},
		{"id": "horizontal_fractional", "path": [[5.25, 12.5], [27.5, 12.5]],
			"width": 5.0, "paint": [219, 41, 87, 129], "erase": false, "selection": "none"},
		{"id": "vertical_reverse", "path": [[12.5, 29.0], [12.5, 3.0]],
			"width": 3.5, "paint": [91, 237, 13, 64], "erase": false, "selection": "none"},
		{"id": "diagonal", "path": [[4.5, 3.0], [27.0, 23.5]],
			"width": 4.0, "paint": [219, 41, 87, 129], "erase": false, "selection": "none"},
		{"id": "self_crossing", "path": [[5.0, 6.0], [28.0, 27.0],
			[5.0, 27.0], [28.0, 6.0]], "width": 3.5,
			"paint": [219, 41, 87, 129], "erase": false, "selection": "none"},
		{"id": "self_crossing_batched", "path": [[5.0, 6.0], [28.0, 27.0],
			[5.0, 27.0], [28.0, 6.0]], "width": 3.5,
			"paint": [219, 41, 87, 129], "erase": false, "selection": "none", "batches": 2},
		{"id": "rect_selection", "path": [[6.5, 7.0], [25.5, 24.5]],
			"width": 7.0, "paint": [39, 190, 111, 200], "erase": false, "selection": "rect"},
		{"id": "sparse_selection", "path": [[6.5, 7.0], [25.5, 24.5]],
			"width": 7.0, "paint": [39, 190, 111, 200], "erase": false, "selection": "sparse"},
		{"id": "inverted_selection", "path": [[6.5, 7.0], [25.5, 24.5]],
			"width": 7.0, "paint": [39, 190, 111, 200], "erase": false, "selection": "inverted"},
		{"id": "erase_hidden_rgb", "path": [[4.5, 3.0], [27.0, 23.5]],
			"width": 4.0, "paint": [0, 0, 0, 0], "erase": true, "selection": "none"},
		{"id": "zero_alpha_noop", "path": [[5.0, 6.0], [28.0, 27.0],
			[5.0, 27.0], [28.0, 6.0]], "width": 3.5,
			"paint": [101, 223, 52, 0], "erase": false, "selection": "none"},
	]


func _selection(kind: String) -> DrawingSelection:
	if kind == "none":
		return null
	var mask: DrawingSelection = DrawingSelection.new(Rect2i(8, 8, 16, 16), true)
	if kind == "sparse":
		var pixels: Dictionary[Vector2i, bool] = {}
		for y: int in range(8, 24):
			for x: int in range(8, 24):
				if (x + y) % 3 == 0:
					pixels[Vector2i(x, y)] = true
		mask.set_mask(pixels)
	elif kind == "inverted":
		mask.inverted = true
	return mask


func _index(key: String) -> int:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return -1
	var x: int = int(parts[0]) - ANCHOR_X
	var y: int = int(parts[1]) - ANCHOR_Y
	if x < 0 or x >= SIDE or y < 0 or y >= SIDE:
		return -1
	return y * SIDE + x


func _sha256(data: PackedByteArray) -> String:
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(data)
	return digest.finish().hex_encode()


func _witness(spec: Dictionary, source: PackedByteArray) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new("skia-oracle", 16)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Raster").value)
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	if seed == null or not seed.apply_region(Rect2i(0, 0, SIDE, SIDE), source).ok:
		return {}
	if not seed.commit().ok:
		return {}
	var session: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	if session == null:
		return {}
	var path: PackedVector2Array = PackedVector2Array()
	for point: Array in spec["path"]:
		path.append(Vector2(float(point[0]), float(point[1])))
	var channels: Array = spec["paint"]
	var rgba: int = int(channels[0]) | (int(channels[1]) << 8) | (int(channels[2]) << 16) | (int(channels[3]) << 24)
	var selection: DrawingSelection = _selection(String(spec["selection"]))
	var batches: int = int(spec.get("batches", 1))
	var painted: DrawingResult
	if batches == 2:
		painted = session.paint_path(path.slice(0, 2), rgba, float(spec["width"]), bool(spec["erase"]), selection)
		if painted.ok:
			painted = session.paint_path(path.slice(2), rgba, float(spec["width"]), bool(spec["erase"]), selection)
	else:
		painted = session.paint_path(path, rgba, float(spec["width"]), bool(spec["erase"]), selection)
	if not painted.ok:
		return {}
	var coverage: Array[int] = []
	for key: String in session._covered:
		var index: int = _index(key)
		if index < 0:
			return {}
		coverage.append(index)
	coverage.sort()
	var committed: DrawingResult
	if session.change_count() == 0:
		# A zero-alpha brush still reports coverage, but has no publication.
		session.cancel()
	else:
		committed = session.commit()
		if not committed.ok:
			return {}
	var after: PackedByteArray = source.duplicate()
	var changed: Array[int] = []
	for key: String in (committed.delta.after if committed != null and committed.delta != null else {}):
		var index: int = _index(key)
		if index < 0:
			return {}
		changed.append(index)
		var value: int = int(committed.delta.after[key])
		for channel: int in range(4):
			after[index * 4 + channel] = (value >> (channel * 8)) & 255
	changed.sort()
	var output: Dictionary = spec.duplicate(true)
	output["coverage_indices"] = coverage
	output["changed_indices"] = changed
	output["after_sha256"] = _sha256(after)
	return output


func _generate() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected one JSON output path after --")
		quit(1)
		return
	var source: PackedByteArray = _source_bytes()
	var cases: Array[Dictionary] = []
	for spec: Dictionary in _cases():
		var witness: Dictionary = _witness(spec, source)
		if witness.is_empty():
			push_error("T068_SKIA_BRUSH_ORACLE_FAILED: " + String(spec["id"]))
			quit(1)
			return
		cases.append(witness)
	var payload: Dictionary = {
		"schema": 1, "side": SIDE, "source": "t068_cairo_cpu.fixture(side, False)",
		"source_sha256": _sha256(source),
		"anchor_x": str(ANCHOR_X), "anchor_y": str(ANCHOR_Y),
		"generator": "tests/drawing_t068_skia_brush_oracle.gd",
		"godot_version": Engine.get_version_info().get("string", ""),
		"cases": cases,
	}
	var output: FileAccess = FileAccess.open(arguments[0], FileAccess.WRITE)
	if output == null:
		push_error("Cannot write oracle JSON")
		quit(1)
		return
	output.store_string(JSON.stringify(payload, "  ") + "\n")
	output.close()
	print("T068_SKIA_BRUSH_ORACLE_PASSED: ", cases.size(), " cases")
	quit(0)
