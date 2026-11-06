extends SceneTree
## T-068: actual DrawingEditSession hard-brush coverage at 512/1024/2048.
## Compress a bounded coverage bitmask, not a multi-megabyte JSON index list.
## An empty canonical source is intentional: this oracle tests geometry only;
## the separate native scale evidence checks source-over and hidden RGBA8.
## Run after Godot import:
##   godot --headless --path . --script res://tests/drawing_t068_blend2d_large_oracle.gd -- /tmp/t068-large-oracle.json

const SIDES: Array[int] = [512, 1024, 2048]
const ANCHOR_X: int = 9007199254740993
const ANCHOR_Y: int = -9007199254740993


func _initialize() -> void:
	call_deferred("_generate")


func _cases() -> Array[Dictionary]:
	return [
		{"id": "hard4_long", "width": 4.0, "path": [[-56.0, -4.0], [56.0, 4.0]],
			"selection": "rect128", "paint": [243, 51, 119, 193], "erase": false,
			"transform": [2.0, 0.0, 0.0, 2.0, 5.0, -3.0]},
		{"id": "round256", "width": 256.0, "path": [[0.0, 0.0]],
			"selection": "rect256", "paint": [29, 207, 15, 128], "erase": false,
			"transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]},
		{"id": "cross64_sparse_erase", "width": 64.0,
			"path": [[-90.0, -90.0], [90.0, 90.0], [-90.0, 90.0], [90.0, -90.0]],
			"selection": "sparse256", "paint": [13, 99, 183, 0], "erase": true,
			"transform": [0.0, 1.0, -1.0, 0.0, 20.0, -4.0]},
		{"id": "transparent_noop", "width": 64.0,
			"path": [[-30.0, 0.0], [30.0, 0.0]],
			"selection": "rect128", "paint": [255, 127, 17, 0], "erase": false,
			"transform": [1.0, 0.0, 0.5, 1.0, -5.0, 2.0]},
	]


func _selection(side: int, kind: String) -> DrawingSelection:
	var span: int = 128 if kind == "rect128" else 256
	var low: int = (side - span) / 2
	var selection: DrawingSelection = DrawingSelection.new(Rect2i(low, low, span, span), true)
	if kind == "sparse256":
		var pixels: Dictionary[Vector2i, bool] = {}
		for y: int in range(low, low + span):
			for x: int in range(low, low + span):
				if (x + y) % 3 != 0:
					pixels[Vector2i(x, y)] = true
		selection.set_mask(pixels)
	return selection


func _index(key: String, side: int) -> int:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return -1
	var x: int = int(parts[0]) - ANCHOR_X
	var y: int = int(parts[1]) - ANCHOR_Y
	if x < 0 or x >= side or y < 0 or y >= side:
		return -1
	return y * side + x


func _coverage_blob(covered: Dictionary[String, bool], side: int) -> String:
	var bitmap: PackedByteArray = PackedByteArray()
	bitmap.resize(side * side)
	bitmap.fill(0)
	for key: String in covered:
		var index: int = _index(key, side)
		if index < 0:
			return ""
		bitmap[index] = 1
	return Marshalls.raw_to_base64(bitmap.compress(FileAccess.COMPRESSION_DEFLATE))


func _case(side: int, spec: Dictionary) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("t068-large-geometry", side)
	var layer: String = String(doc.create_layer(DrawingLayerNode.RASTER, "Raster").value)
	var coeff: Array = spec["transform"]
	var transform: Transform2D = Transform2D(
		Vector2(float(coeff[0]), float(coeff[1])),
		Vector2(float(coeff[2]), float(coeff[3])),
		Vector2(float(coeff[4]), float(coeff[5])))
	var session: DrawingEditSession = doc.begin_edit(layer, doc.revision,
		transform, ANCHOR_X, ANCHOR_Y).value as DrawingEditSession
	if session == null:
		return {}
	var path: PackedVector2Array = PackedVector2Array()
	var local_path: Array[Array] = []
	var view_path: Array[Array] = []
	for relative: Array in spec["path"]:
		var local: Vector2 = Vector2(side / 2.0 + float(relative[0]),
			side / 2.0 + float(relative[1]))
		var view: Vector2 = transform * local
		local_path.append([local.x, local.y])
		view_path.append([view.x, view.y])
		path.append(view)
	var rgba: int = 0
	for channel: int in range(4):
		rgba |= int(spec["paint"][channel]) << (8 * channel)
	var painted: DrawingResult = session.paint_path(path, rgba,
		float(spec["width"]), bool(spec["erase"]), _selection(side, String(spec["selection"])))
	if not painted.ok:
		push_error("T068_LARGE_ORACLE_FAILED: %s/%s: %s" % [side, spec["id"], painted.code])
		return {}
	var coverage: String = _coverage_blob(session._covered, side)
	var count: int = session._covered.size()
	if coverage.is_empty() or count == 0:
		return {}
	var changed: int = session.change_count()
	if changed != (0 if bool(spec["erase"]) or int(spec["paint"][3]) == 0 else count):
		return {}
	# The source stays blank and detached; no side-sized pixel buffer is seeded
	# or published. Erase/no-op coverage is still included in _covered.
	session.cancel()
	return {"side": side, "id": spec["id"], "width": spec["width"],
		"relative_path": spec["path"], "local_path": local_path,
		"view_path": view_path, "transform": spec["transform"],
		"paint": spec["paint"], "erase": spec["erase"],
		"selection": spec["selection"], "coverage_deflate_base64": coverage,
		"coverage_count": count, "blank_source_changed_pixels": changed}


func _generate() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected one output path after --")
		quit(1)
		return
	var cases: Array[Dictionary] = []
	for side: int in SIDES:
		for spec: Dictionary in _cases():
			var result: Dictionary = _case(side, spec)
			if result.is_empty():
				push_error("T068_LARGE_ORACLE_FAILED: %s/%s" % [side, spec["id"]])
				quit(1)
				return
			cases.append(result)
	var payload: Dictionary = {"schema": 1, "generator":
		"tests/drawing_t068_blend2d_large_oracle.gd", "sides": SIDES,
		"anchor_x": str(ANCHOR_X), "anchor_y": str(ANCHOR_Y),
		"godot_version": Engine.get_version_info().get("string", ""), "cases": cases}
	var file: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write large oracle JSON")
		quit(1)
		return
	file.store_string(JSON.stringify(payload, "  ") + "\n")
	file.close()
	print("T068_LARGE_ORACLE_PASSED: ", cases.size(), " cases")
	quit(0)
