extends SceneTree
## T-068: compares the pre-optimization per-pixel read loop to the canonical
## tile-run compositor, while exercising real DrawingEditSession transactions.

const STRIDES: Array[int] = [512, 1024, 2048]
const ROUNDS: int = 5
var checks: int = 0
var failures: int = 0
var measurements: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, name: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("T068_FAILED: " + name)


func _elapsed(start_us: int) -> float:
	return float(Time.get_ticks_usec() - start_us) / 1000.0


func _statistics(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median_ms": snappedf(values[values.size() / 2], 0.001),
		"p95_ms": snappedf(values[ceili(float(values.size()) * 0.95) - 1], 0.001)}


## Deliberately retain the original per-pixel renderer only as a benchmark oracle.
## No editor or application calls this function.
func _reference_frame(document: DrawingDocument, layers: Array[String],
		width: int, height: int, origin_x: int, origin_y: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(width * height * 4)
	for layer_id: String in layers:
		for y: int in range(height):
			for x: int in range(width):
				var source: DrawingResult = document.read_pixel(layer_id, origin_x + x, origin_y + y)
				if not source.ok:
					return PackedByteArray()
				var index: int = (y * width + x) * 4
				var destination: int = int(bytes[index]) | (int(bytes[index + 1]) << 8) \
					| (int(bytes[index + 2]) << 16) | (int(bytes[index + 3]) << 24)
				var result: int = DrawingEditSession._blend(int(source.value), destination)
				bytes[index] = result & 255
				bytes[index + 1] = (result >> 8) & 255
				bytes[index + 2] = (result >> 16) & 255
				bytes[index + 3] = (result >> 24) & 255
	return bytes


func _single_edit(document: DrawingDocument, layer: String, rgba: int,
		a: Vector2, b: Vector2, width: float, erase: bool = false,
		selection: DrawingSelection = null, anchor_x: int = 0, anchor_y: int = 0) -> Dictionary:
	var begun: DrawingResult = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, anchor_x, anchor_y)
	_check(begun.ok, "start stroke transaction")
	if not begun.ok:
		return {"success": false, "time_ms": 0.0}
	var edit: DrawingEditSession = begun.value as DrawingEditSession
	var start: int = Time.get_ticks_usec()
	var touched: DrawingResult = edit.paint_path(PackedVector2Array([a, b]), rgba,
		width, erase, selection)
	var result: DrawingResult = edit.commit() if touched.ok and edit.change_count() > 0 else touched
	_check(result.ok, "atomic stroke commit " + result.code + " " + result.message)
	if not result.ok:
		return {"success": false, "time_ms": _elapsed(start)}
	_check(result.regions.size() > 0 and result.delta != null, "bounded dirty rectangles and delta")
	var history_bytes: int = var_to_bytes([result.delta.before, result.delta.after]).size()
	var amount: int = result.delta.after.size()
	var undo: DrawingResult = document.undo()
	var redo: DrawingResult = document.redo()
	_check(undo.ok and redo.ok, "same gesture undo and redo")
	return {"success": true, "time_ms": _elapsed(start), "changed": amount,
		"undo_wire_bytes": history_bytes, "dirty_regions": result.regions.size()}


func _run() -> void:
	var output: String = ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--output":
			output = args[index + 1]
	for stride: int in STRIDES:
		var document: DrawingDocument = DrawingDocument.new("t068-%d" % stride, stride)
		var layers: Array[String] = []
		for name: String in ["Ink", "Glass"]:
			var created: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, name)
			_check(created.ok, "create independent raster layer")
			layers.append(str(created.value))
		var anchor_x: int = 9007199254740993 + stride * 2
		var anchor_y: int = -(9007199254740993 + stride * 2)
		# Seed both layers with differently transparent values including hidden RGB.
		for index: int in range(layers.size()):
			var opened: DrawingResult = document.begin_edit(layers[index], document.revision,
				Transform2D.IDENTITY, anchor_x, anchor_y)
			_check(opened.ok, "begin seed")
			var editor: DrawingEditSession = opened.value as DrawingEditSession
			var seed: PackedByteArray = PackedByteArray()
			seed.resize(16 * 16 * 4)
			for pixel: int in range(16 * 16):
				seed[pixel * 4] = (pixel + index * 17) % 256
				seed[pixel * 4 + 1] = (pixel * 5) % 256
				seed[pixel * 4 + 2] = (pixel * 11) % 256
				seed[pixel * 4 + 3] = (pixel % 3) * 127
			_check(editor.apply_region(Rect2i(0, 0, 16, 16), seed).ok and editor.commit().ok,
				"seed exact RGBA8")
			_check(int(document.read_pixel(layers[index], anchor_x, anchor_y).value) & 0xff000000 == 0,
				"hidden RGB source survives exact save")
		var baseline_ms: Array[float] = []
		var tiled_ms: Array[float] = []
		for repeat: int in range(ROUNDS):
			var x: int = anchor_x - 8 if repeat % 2 == 0 else anchor_x + stride - 32
			var y: int = anchor_y - 8 if repeat % 2 == 0 else anchor_y + stride - 32
			var start: int = Time.get_ticks_usec()
			var baseline: PackedByteArray = _reference_frame(document, layers, 96, 96, x, y)
			baseline_ms.append(_elapsed(start))
			start = Time.get_ticks_usec()
			var optimized: DrawingResult = DrawingRenderer.render(document, Rect2i(0, 0, 96, 96), x, y)
			tiled_ms.append(_elapsed(start))
			_check(optimized.ok and optimized.value is Image
				and (optimized.value as Image).get_data() == baseline,
				"byte-identical raster composition around signed tile seams")
		var strokes: Array[Dictionary] = []
		var selection: DrawingSelection = DrawingSelection.new(Rect2i(0, 0, 32, 32), true)
		for workload: String in ["short_4px", "round_64px", "long_fast", "self_cross", "eraser", "masked"]:
			var samples: Array[float] = []
			var histories: Array[int] = []
			var pixel_counts: Array[int] = []
			for repeat: int in range(ROUNDS):
				var a: Vector2 = Vector2(8.5 + repeat, 8.5)
				var b: Vector2 = Vector2(16.5 + repeat, 9.5)
				var width: float = 4.0
				if workload == "round_64px":
					a = Vector2(90.5 + repeat, 90.5)
					b = a
					width = 64.0
				elif workload == "long_fast":
					b = Vector2(224.5 + repeat, 8.5)
				elif workload == "self_cross":
					b = Vector2(8.5, 8.5 + repeat)
				elif workload == "masked":
					b = Vector2(48.5, 8.5)
				var result: Dictionary = _single_edit(document, layers[0], 0x88774422,
					a, b, width, workload == "eraser", selection if workload == "masked" else null,
					anchor_x + repeat * (stride + 1000), anchor_y)
				if result.get("success", false):
					samples.append(float(result["time_ms"]))
					histories.append(int(result["undo_wire_bytes"]))
					pixel_counts.append(int(result["changed"]))
			_check(not samples.is_empty(), "workload had a committed gesture")
			if samples.is_empty():
				continue
			strokes.append({"name": workload, "latency": _statistics(samples),
				"max_undo_wire_bytes": histories.max(), "max_changed": pixel_counts.max()})
		# Cancel and revision conflicts must not mutate either source or history.
		var revision: int = document.revision
		var cancelled: DrawingEditSession = document.begin_edit(layers[0], revision).value
		_check(cancelled.paint_path(PackedVector2Array([Vector2(50, 50)]),
			0x88998877, 3).ok, "stage cancelled brush")
		cancelled.cancel()
		_check(not cancelled.commit().ok and document.revision == revision,
			"cancellation is non-destructive")
		var stale: DrawingEditSession = document.begin_edit(layers[0], revision).value
		_check(stale.paint_path(PackedVector2Array([Vector2(80, 80)]),
			0x88998877, 3).ok, "stage conflicting brush")
		var interfering: DrawingEditSession = document.begin_edit(layers[0], revision).value
		_check(interfering.paint_path(PackedVector2Array([Vector2(100, 100)]),
			0xff123456, 3).ok and interfering.commit().ok, "interfering commit")
		_check(not stale.commit().ok, "stale edit rejected")
		measurements.append({"stride": stride, "view_size": [96, 96],
			"baseline_composite": _statistics(baseline_ms),
			"tiled_composite": _statistics(tiled_ms), "workloads": strokes})
		print("T068_CASE stride=%d baseline=%s tile_run=%s" % [stride,
			JSON.stringify(_statistics(baseline_ms)), JSON.stringify(_statistics(tiled_ms))])
	# Canonical straight-RGBA8 parity vectors for the C++ prototype.
	var blend_vectors: Array[Dictionary] = []
	for alpha: int in [0, 1, 2, 63, 127, 128, 254, 255]:
		for dst_alpha: int in [0, 1, 127, 255]:
			for value: int in range(4):
				var source: int = (alpha << 24) | ((value * 53) << 16) | (value * 17 << 8) | (255 - value * 19)
				var destination: int = (dst_alpha << 24) | ((value * 29) << 16) | ((255 - value * 31) << 8) | (value * 59)
				blend_vectors.append({"src": source, "dst": destination,
					"result": DrawingEditSession._blend(source, destination)})
	# Real Godot-covered pixels become the native batch comparison fixture.
	# No 64-bit world anchor is narrowed into Vector2i or a JSON number.
	var fixture_document: DrawingDocument = DrawingDocument.new("t068-parity", 16)
	var fixture_layer: String = str(fixture_document.create_layer(DrawingLayerNode.RASTER, "Parity").value)
	var fixture_seed: PackedByteArray = PackedByteArray()
	fixture_seed.resize(16 * 16 * 4)
	for index: int in range(16 * 16):
		fixture_seed[index * 4] = (index * 17) % 256
		fixture_seed[index * 4 + 1] = (index * 3) % 256
		fixture_seed[index * 4 + 2] = (index * 29) % 256
		fixture_seed[index * 4 + 3] = (index % 6) * 42
	var fixture_anchor: int = 9007199254740993
	var fixture_seed_edit: DrawingEditSession = fixture_document.begin_edit(fixture_layer,
		fixture_document.revision, Transform2D.IDENTITY, fixture_anchor, -fixture_anchor).value
	_check(fixture_seed_edit.apply_region(Rect2i(0, 0, 16, 16), fixture_seed).ok
		and fixture_seed_edit.commit().ok, "seed native parity fixture")
	var fixture_selection: DrawingSelection = DrawingSelection.new(Rect2i(2, 1, 10, 10), true)
	var fixture_edit: DrawingEditSession = fixture_document.begin_edit(fixture_layer,
		fixture_document.revision, Transform2D.IDENTITY, fixture_anchor, -fixture_anchor).value
	_check(fixture_edit.paint_path(PackedVector2Array([
		Vector2(2.5, 3.5), Vector2(8.5, 3.5), Vector2(2.5, 3.5)]),
		0x88776655, 3.0, false, fixture_selection).ok, "stage fixture self-overlap")
	var fixture_result: DrawingResult = fixture_edit.commit()
	_check(fixture_result.ok, "commit parity fixture")
	var fixture_points: Array[Array] = []
	if fixture_result.ok and fixture_result.delta != null:
		for key: String in fixture_result.delta.after:
			var components: PackedStringArray = key.split(",")
			fixture_points.append([int(components[0]) - fixture_anchor,
				int(components[1]) + fixture_anchor])
	fixture_points.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[1]) < int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))
	var fixture_after: PackedByteArray = PackedByteArray()
	fixture_after.resize(16 * 16 * 4)
	for y: int in range(16):
		for x: int in range(16):
			var result: DrawingResult = fixture_document.read_pixel(fixture_layer,
				fixture_anchor + x, -fixture_anchor + y)
			_check(result.ok, "read signed fixture pixel")
			var rgba: int = int(result.value) if result.ok else 0
			var offset: int = (y * 16 + x) * 4
			for channel: int in range(4):
				fixture_after[offset + channel] = (rgba >> (channel * 8)) & 255
	var kernel_fixture: Dictionary = {"width": 16, "height": 16,
		"rgba": 0x88776655, "before_hex": fixture_seed.hex_encode(),
		"after_hex": fixture_after.hex_encode(), "changed": fixture_points.size(),
		"covered_xy": fixture_points}
	if not output.is_empty():
		var error: Error = DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		_check(error == OK, "output directory")
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "report file")
		if file != null:
			file.store_string(JSON.stringify({"schema": "t068-godot-v1", "engine": Engine.get_version_info(),
				"rounds": ROUNDS, "cases": measurements,
				"blend_vectors": blend_vectors, "kernel_fixture": kernel_fixture,
				"checks": checks, "failures": failures}, "  ") + "\n")
			file.close()
	print("T068_GODOT_%s (%d checks, %d failures)" % [
		"PASSED" if failures == 0 else "FAILED", checks, failures])
	quit(0 if failures == 0 else 1)
