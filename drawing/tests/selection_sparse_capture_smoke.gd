extends SceneTree
## T-088: independent dense readback oracle for sparse Copy/Move capture.
## A separate lazy-source fixture guards error propagation and masked no-fetch.

class CountingDocument:
	extends DrawingDocument
	var resolves: int = 0

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		resolves += 1
		return super._resolve_chunk(layer_id, key)

var checks: int = 0
var failures: int = 0
var loader_calls: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T088_SPARSE_CAPTURE_FAILED: " + label)


func oracle(document: DrawingDocument, layer: String, area: Rect2i,
		selection: DrawingSelection, ox: int, oy: int) -> Dictionary:
	var pixels: Dictionary[Vector2i, int] = {}
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var point: Vector2i = Vector2i(x, y)
			if selection != null and not selection.allows(point):
				continue
			var read: DrawingResult = document.read_pixel(layer, ox + x, oy + y)
			if not read.ok:
				printerr("T088_SPARSE_CAPTURE_FAILED: dense oracle read failed")
				failures += 1
				return {}
			if int(read.value) != 0:
				pixels[point - area.position] = int(read.value)
	return pixels


func broken_loader(_ref: String) -> PackedByteArray:
	loader_calls += 1
	return PackedByteArray([1, 2, 3])


func good_loader(_ref: String) -> PackedByteArray:
	loader_calls += 1
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(16 * 16 * 4)
	bytes[0] = 21
	bytes[1] = 43
	bytes[2] = 65
	bytes[3] = 0 # Hidden RGB is nonzero despite zero alpha.
	return bytes


func median(samples: Array[int]) -> int:
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var document: CountingDocument = CountingDocument.new("t088-sparse-capture", 32)
	var layer: String = String(document.create_layer(DrawingLayerNode.RASTER, "Sparse").value)
	var area: Rect2i = Rect2i(-73, -51, 176, 140)
	var ox: int = 1027
	var oy: int = -2094
	var pixels: Dictionary[Vector2i, int] = {
		Vector2i(-73, -51): 0x00fedcba, Vector2i(-65, -32): 0xff112233,
		Vector2i(-1, -1): 0x00887766, Vector2i(0, 0): 0xff332211,
		Vector2i(31, 31): 0xffaabbcc, Vector2i(32, 32): 0xffabcdef,
		Vector2i(102, 88): 0xff122334, Vector2i(150, 10): 0xff556677,
	}
	var seed: DrawingEditSession = document.begin_edit(layer, document.revision,
		Transform2D.IDENTITY, ox, oy).value as DrawingEditSession
	for point: Vector2i in pixels:
		check(seed._stage(point.x, point.y, pixels[point]).ok, "seed %s" % point)
	check(seed.commit().ok, "seed committed")
	var selections: Array[DrawingSelection] = [null]
	var rectangle: DrawingSelection = DrawingSelection.new(area, true)
	selections.append(rectangle)
	var holes: DrawingSelection = rectangle.detached_copy()
	check(holes.combine_rectangle(Rect2i(-9, -9, 46, 46), "Subtract") and
		holes.combine_rectangle(Rect2i(75, -20, 22, 18), "Subtract"), "boolean holes")
	selections.append(holes)
	var islands: DrawingSelection = DrawingSelection.new(Rect2i(-70, -48, 10, 20), true)
	check(islands.combine_rectangle(Rect2i(30, 28, 10, 12), "Add"), "detached island")
	selections.append(islands)
	var mask: DrawingSelection = rectangle.detached_copy()
	var flags: Dictionary[Vector2i, bool] = {}
	for point: Vector2i in pixels:
		if point.x % 2 != 0:
			flags[point] = true
	mask.set_mask(flags)
	selections.append(mask)
	selections.append(DrawingSelection.new(Rect2i(), true)) # Enabled empty denies all.
	for idx: int in range(selections.size()):
		var selected: DrawingSelection = selections[idx]
		var expected: Dictionary = oracle(document, layer, area, selected, ox, oy)
		var revision: int = document.revision
		var copied: DrawingResult = DrawingClipboard.capture(document, layer, area,
			selected, ox, oy)
		check(copied.ok, "capture case %d succeeds" % idx)
		if copied.ok:
			var payload: DrawingClipboard = copied.value as DrawingClipboard
			check(payload._pixels == expected and payload.width == area.size.x and
				payload.height == area.size.y and payload.source_position == area.position,
				"capture case %d matches dense byte-exact oracle" % idx)
			check((payload.source_selection == null and selected == null) or
				(payload.source_selection != null and payload.source_selection.same_as(selected)),
				"capture case %d freezes selection" % idx)
		check(document.revision == revision, "capture case %d is read-only" % idx)

	var sparse_area: Rect2i = Rect2i(-96, -96, 512, 512)
	var all_sparse: DrawingResult = DrawingClipboard.capture(document, layer, sparse_area,
		null, ox, oy)
	check(all_sparse.ok and (all_sparse.value as DrawingClipboard)._pixels.size() == pixels.size(),
		"large sparse copy contains all nonzero values")
	# The old implementation resolved every one of the 17*17 empty/source
	# chunks; the sparse one must resolve only actual stored source chunks.
	document.resolves = 0
	var bounded: DrawingResult = DrawingClipboard.capture(document, layer, sparse_area,
		null, ox, oy)
	check(bounded.ok and document.resolves < 25,
		"large sparse capture resolves fewer than 25 occupied chunks (got %d)" % document.resolves)
	var samples_us: Array[int] = []
	for trial: int in range(7):
		var start: int = Time.get_ticks_usec()
		var result: DrawingResult = DrawingClipboard.capture(document, layer, sparse_area,
			null, ox, oy)
		samples_us.append(Time.get_ticks_usec() - start)
		check(result.ok and (result.value as DrawingClipboard)._pixels.size() == pixels.size(),
			"CPU timing trial %d retains canonical bytes" % trial)
	print("T088_SPARSE_CAPTURE_BENCH: 512x512, %d stored, seven CPU-only samples, median %d us, samples=%s" % [
		pixels.size(), median(samples_us), samples_us])

	# Atlas can anchor a small Drawing far outside Vector2i range; tile
	# lookups must stay in signed 64-bit space until offset into the payload.
	var far: CountingDocument = CountingDocument.new("t088-signed64", 32)
	var far_layer: String = String(far.create_layer(DrawingLayerNode.RASTER, "Far").value)
	var far_x: int = 5000000009
	var far_y: int = -5000000071
	var far_edit: DrawingEditSession = far.begin_edit(far_layer, far.revision,
		Transform2D.IDENTITY, far_x, far_y).value as DrawingEditSession
	check(far_edit._stage(-3, -4, 0x00abcdef).ok and far_edit.commit().ok,
		"signed-64 source stage/commit")
	var far_copy: DrawingResult = DrawingClipboard.capture(far, far_layer,
		Rect2i(-8, -8, 16, 16), null, far_x, far_y)
	check(far_copy.ok and (far_copy.value as DrawingClipboard)._pixels == {
		Vector2i(5, 4): 0x00abcdef}, "signed-64 sparse capture avoids Vector2i global truncation")

	var lazy: CountingDocument = CountingDocument.new("t088-sparse-lazy", 16)
	var lazy_layer: String = String(lazy.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	var expected_bytes: PackedByteArray = good_loader("")
	loader_calls = 0
	var digest: String = DrawingRasterTile.digest_rgba8(expected_bytes, 16)
	check(lazy.register_lazy_chunk(lazy_layer, 0, 0, "corrupt", digest,
		Callable(self, "broken_loader")).ok, "register corrupt lazy chunk")
	var exclude: DrawingSelection = DrawingSelection.new(Rect2i(16, 0, 16, 16), true)
	var excluded: DrawingResult = DrawingClipboard.capture(lazy, lazy_layer,
		Rect2i(0, 0, 32, 16), exclude)
	check(excluded.ok and loader_calls == 0 and
		(excluded.value as DrawingClipboard)._pixels.is_empty(),
		"entirely masked-out pending corruption is not fetched")
	var damaged: DrawingResult = DrawingClipboard.capture(lazy, lazy_layer,
		Rect2i(0, 0, 32, 16))
	check(not damaged.ok and damaged.code == "CORRUPT_TILE" and loader_calls == 1,
		"selected corrupt lazy source fails closed")
	var valid: CountingDocument = CountingDocument.new("t088-valid-lazy", 16)
	var valid_layer: String = String(valid.create_layer(DrawingLayerNode.RASTER, "Lazy").value)
	check(valid.register_lazy_chunk(valid_layer, -1, 0, "valid", digest,
		Callable(self, "good_loader")).ok, "register signed valid lazy chunk")
	loader_calls = 0
	var valid_copy: DrawingResult = DrawingClipboard.capture(valid, valid_layer,
		Rect2i(-16, 0, 32, 16))
	check(valid_copy.ok and loader_calls == 1 and
		(valid_copy.value as DrawingClipboard)._pixels.get(Vector2i(0, 0), -1) == 0x00412b15,
		"signed lazy capture preserves hidden RGBA and fetches exactly once")
	var repeat_copy: DrawingResult = DrawingClipboard.capture(valid, valid_layer,
		Rect2i(-16, 0, 32, 16))
	check(repeat_copy.ok and loader_calls == 1 and
		(repeat_copy.value as DrawingClipboard)._pixels == (valid_copy.value as DrawingClipboard)._pixels,
		"resolved lazy source is reused with byte parity")
	check(not DrawingClipboard.capture(valid, "missing", area).ok,
		"missing raster layer is rejected")
	check(not DrawingClipboard.capture(valid, valid_layer, Rect2i(0, 0, 2048, 1024)).ok,
		"oversize clipboard remains rejected")

	print("T088_SPARSE_CAPTURE: %d checks; %d failed" % [checks, failures])
	if failures == 0 and checks >= 50:
		print("T088_SPARSE_CAPTURE_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
