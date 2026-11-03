extends SceneTree

# Exercise the real canonical Document/EditSession publication and history path
# with bytes produced by the opt-in C++ kernel. No Atlas or app UI is loaded.
const ADAPTER = preload("res://document_adapter.gd")
var checks: int = 0
var failed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lazy_available: bool = false
var _lazy_corrupt: bool = false
var _lazy_data: PackedByteArray

func _lazy_fetch(_ref: String) -> Variant:
	if not _lazy_available:
		return null
	if _lazy_corrupt:
		return PackedByteArray([1, 2, 3, 4])
	return _lazy_data


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("T068_DOCUMENT_FAIL: ", label)

static func _rgba(bytes: PackedByteArray, index: int) -> int:
	var at: int = index * 4
	return int(bytes[at]) | (int(bytes[at + 1]) << 8) | \
		(int(bytes[at + 2]) << 16) | (int(bytes[at + 3]) << 24)

static func _put(bytes: PackedByteArray, index: int, color: int) -> void:
	for channel: int in range(4):
		bytes[index * 4 + channel] = (color >> (8 * channel)) & 255

static func _source(stride: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(stride * stride * 4)
	for i: int in range(stride * stride):
		_put(data, i, (i * 431 + 0x00112233) & 0xFFFFFFFF)
	return data

static func _oracle(input: PackedByteArray, stride: int, points: PackedInt32Array,
		mask: PackedByteArray, color: int, operation: int) -> PackedByteArray:
	var output: PackedByteArray = input.duplicate()
	var visited: Dictionary[int, bool] = {}
	for n: int in range(0, points.size(), 2):
		var pixel: int = points[n + 1] * stride + points[n]
		if visited.has(pixel) or (not mask.is_empty() and mask[pixel] == 0):
			continue
		visited[pixel] = true
		var original: int = _rgba(input, pixel)
		var next: int = 0 if operation == 1 else \
			color if operation == 2 else DrawingEditSession._blend(color, original)
		_put(output, pixel, next)
	return output

static func _document(name: String, stride: int) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, stride)
	var layer: DrawingResult = document.create_layer(DrawingLayerNode.RASTER, "Pixels")
	return {"document": document, "layer": String(layer.value)}

static func _tile(document: DrawingDocument, layer: String,
		cx: int = 0, cy: int = 0) -> PackedByteArray:
	var result: DrawingResult = document.request_chunk_at(layer, cx, cy)
	var chunk: DrawingRasterTile = result.value as DrawingRasterTile if result.ok else null
	if chunk != null:
		return chunk.to_rgba8()
	var zeros: PackedByteArray = PackedByteArray()
	zeros.resize(document.tile_stride * document.tile_stride * 4)
	return zeros

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "load explicit extension")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null, "native class available")
	if bridge == null:
		quit(1)
		return
	var setup: Dictionary = _document("document-native", 16)
	var doc: DrawingDocument = setup.document
	var layer: String = setup.layer
	var original: PackedByteArray = _source(16)
	var seed: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
	_check(seed.apply_region(Rect2i(0, 0, 16, 16), original).ok and seed.commit().ok,
		"seed real DrawingDocument")
	var original_revision: int = doc.revision
	var coords: PackedInt32Array = PackedInt32Array([2, 3, 3, 3, 2, 3, 5, 4])
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(256)
	mask[3 * 16 + 2] = 1
	mask[4 * 16 + 5] = 1
	var target: int = 0x00332211
	var expected: PackedByteArray = _oracle(original, 16, coords, mask, target, 2)
	var outcome: Dictionary = ADAPTER.apply(bridge, doc, layer, 0, 0,
		original_revision, coords, mask, target, 2)
	_check(outcome.ok and outcome.changed == 2 and doc.revision == original_revision + 1,
		"one real document transaction and revision")
	_check(outcome.dirty_rect == Rect2i(2, 3, 4, 2), "exact local dirty bounds")
	_check(_tile(doc, layer) == expected and original == _source(16),
		"straight RGBA including hidden RGB; detached caller bytes")
	_check(outcome.result.delta.after.size() == 2 and outcome.result.regions.size() == 1,
		"real delta and dirty region returned")
	_check(doc.undo().ok and _tile(doc, layer) == original,
		"actual DrawingDocument undo restores source")
	_check(doc.redo().ok and _tile(doc, layer) == expected,
		"actual DrawingDocument redo restores native edit")
	var revision: int = doc.revision
	outcome = ADAPTER.apply(bridge, doc, layer, 0, 0, original_revision,
		coords, mask, target, 2)
	_check(not outcome.ok and outcome.code == "STALE_REVISION" and doc.revision == revision,
		"stale revision fails before any native edit")
	outcome = ADAPTER.apply(bridge, doc, layer, 0, 0, revision,
		coords, mask, target, 2)
	_check(outcome.ok and outcome.changed == 0 and doc.revision == revision,
		"native no-op does not advance history")
	outcome = ADAPTER.apply(bridge, doc, layer, 0, 0, revision,
		PackedInt32Array([18, 0]), mask, target, 2)
	_check(not outcome.ok and outcome.code == "NATIVE" and _tile(doc, layer) == expected,
		"out-of-bounds native coordinate leaves source unchanged")
	outcome = ADAPTER.apply(bridge, doc, layer, 0, 0, revision,
		coords, PackedByteArray([1]), target, 2)
	_check(not outcome.ok and outcome.code == "NATIVE" and doc.revision == revision,
		"short mask rejected atomically")

	var concurrent: Dictionary = _document("concurrent", 8)
	var other: DrawingDocument = concurrent.document
	var other_layer: String = concurrent.layer
	var expected_rev: int = other.revision
	var winner_color: int = 0xFF554433
	var winner: Callable = func() -> void:
		var session: DrawingEditSession = other.begin_edit(other_layer, other.revision).value
		session.fill_rect(Rect2i(0, 0, 1, 1), winner_color)
		session.commit()
	outcome = ADAPTER.apply(bridge, other, other_layer, 0, 0, expected_rev,
		PackedInt32Array([1, 1]), PackedByteArray(), 0xFF112233, 2, winner)
	_check(not outcome.ok and outcome.code == "STALE_REVISION" and
		other.revision == expected_rev + 1, "reentrant edit wins over native candidate")
	_check(int(other.read_pixel(other_layer, 0, 0).value) == winner_color and
		int(other.read_pixel(other_layer, 1, 1).value) == 0,
		"stale native candidate cannot partially install")
	_check(other.undo().ok and int(other.read_pixel(other_layer, 0, 0).value) == 0,
		"concurrent source remains undoable")

	# Tile origin is kept as a signed-64-bit anchor; native points are small.
	var far: Dictionary = _document("far", 16)
	var far_doc: DrawingDocument = far.document
	var far_layer: String = far.layer
	var cx: int = 562949953421312 # 2^53 / 16
	var cy: int = -cx
	outcome = ADAPTER.apply(bridge, far_doc, far_layer, cx, cy, far_doc.revision,
		PackedInt32Array([1, 2, 1, 2]), PackedByteArray(), 0x00CCBBAA, 2)
	_check(outcome.ok and outcome.changed == 1 and outcome.dirty_rect == Rect2i(1, 2, 1, 1),
		"exact signed-64-bit tile dirty rectangle")
	_check(int(far_doc.read_pixel(far_layer, cx * 16 + 1, cy * 16 + 2).value) == 0x00CCBBAA,
		"high signed coordinate remains exact")
	_check(far_doc.undo().ok and int(far_doc.read_pixel(
		far_layer, cx * 16 + 1, cy * 16 + 2).value) == 0,
		"high-coordinate native edit undo")
	outcome = ADAPTER.apply(bridge, far_doc, far_layer, 72057594037927937, 0,
		far_doc.revision, PackedInt32Array([0, 0]), PackedByteArray(), 4, 2)
	_check(not outcome.ok and outcome.code == "COORD_RANGE", "reject oversized origin")

	# The real storage model can contain digest-checked references to tiles that
	# have not been hydrated. Never interpret failed loading as blank pixels.
	var lazy: Dictionary = _document("lazy-real-document", 8)
	var lazy_doc: DrawingDocument = lazy.document
	var lazy_layer: String = lazy.layer
	_lazy_data = _source(8)
	var digest: String = DrawingRasterTile.digest_rgba8(_lazy_data, 8)
	_check(lazy_doc.register_lazy_chunk(lazy_layer, -1, -1, "sealed", digest,
		Callable(self, "_lazy_fetch")).ok, "register digest-verified lazy tile")
	var lazy_revision: int = lazy_doc.revision
	var lazy_points: PackedInt32Array = PackedInt32Array([1, 2])
	outcome = ADAPTER.apply(bridge, lazy_doc, lazy_layer, -1, -1, lazy_revision,
		lazy_points, PackedByteArray(), 0x00887766, 2)
	_check(not outcome.ok and outcome.code == "MISSING_TILE" and
		lazy_doc.revision == lazy_revision, "missing lazy source is never blank")
	_lazy_available = true
	_lazy_corrupt = true
	outcome = ADAPTER.apply(bridge, lazy_doc, lazy_layer, -1, -1, lazy_revision,
		lazy_points, PackedByteArray(), 0x00887766, 2)
	_check(not outcome.ok and outcome.code == "CORRUPT_TILE" and
		lazy_doc.revision == lazy_revision, "corrupt lazy tile rejected before native")
	_lazy_corrupt = false
	outcome = ADAPTER.apply(bridge, lazy_doc, lazy_layer, -1, -1, lazy_revision,
		lazy_points, PackedByteArray(), 0x00887766, 2)
	_check(outcome.ok and outcome.changed == 1 and
		int(lazy_doc.read_pixel(lazy_layer, -7, -6).value) == 0x00887766,
		"verified lazy source can be edited and published")
	_check(lazy_doc.undo().ok and _tile(lazy_doc, lazy_layer, -1, -1) == _lazy_data,
		"undo restores exact original lazy tile")

	var locked: Dictionary = _document("locked", 8)
	var locked_doc: DrawingDocument = locked.document
	var locked_layer: String = locked.layer
	_check(locked_doc.set_locked(locked_layer, true).ok, "lock raster source")
	var locked_revision: int = locked_doc.revision
	outcome = ADAPTER.apply(bridge, locked_doc, locked_layer, 0, 0,
		locked_revision, PackedInt32Array([0, 0]), PackedByteArray(), 0xFFFFFFFF, 2)
	_check(not outcome.ok and outcome.code == "LOCKED" and
		locked_doc.revision == locked_revision and int(locked_doc.read_pixel(locked_layer, 0, 0).value) == 0,
		"native output cannot bypass DrawingDocument layer lock")

	rng.seed = 68006842
	for n: int in range(48):
		var stride: int = [4, 8, 16][n % 3]
		var fixture: Dictionary = _document("seed-%d" % n, stride)
		var sample_doc: DrawingDocument = fixture.document
		var sample_layer: String = fixture.layer
		var bytes: PackedByteArray = _source(stride)
		var sample_seed: DrawingEditSession = sample_doc.begin_edit(
			sample_layer, sample_doc.revision).value
		sample_seed.apply_region(Rect2i(0, 0, stride, stride), bytes)
		var seeded: DrawingResult = sample_seed.commit()
		_check(seeded.ok, "random case seeded %d" % n)
		var points: PackedInt32Array = PackedInt32Array()
		for index: int in range(rng.randi_range(1, stride * stride * 2)):
			points.append(rng.randi_range(0, stride - 1))
			points.append(rng.randi_range(0, stride - 1))
		var selection: PackedByteArray = PackedByteArray()
		if n % 3 == 0:
			selection.resize(stride * stride)
			for index: int in range(selection.size()):
				selection[index] = 0 if index % 5 == 0 else 1
		var mode: int = n % 3
		var color: int = rng.randi()
		var expected_bytes: PackedByteArray = _oracle(bytes, stride, points, selection, color, mode)
		var source_rev: int = sample_doc.revision
		var actual: Dictionary = ADAPTER.apply(bridge, sample_doc, sample_layer, 0, 0,
			source_rev, points, selection, color, mode)
		_check(actual.ok and _tile(sample_doc, sample_layer) == expected_bytes,
			"native batch published via canonical document %d" % n)
		_check(sample_doc.revision == source_rev + (1 if expected_bytes != bytes else 0),
			"correct no-op/commit revision %d" % n)
		if expected_bytes != bytes:
			_check(sample_doc.undo().ok and _tile(sample_doc, sample_layer) == bytes and
				sample_doc.redo().ok and _tile(sample_doc, sample_layer) == expected_bytes,
				"real history parity %d" % n)

	bridge.free()
	print("T068_DOCUMENT_PASSED: ", checks, " checks") if failed == 0 else \
		print("T068_DOCUMENT_FAILED: ", failed, "/", checks)
	quit(0 if failed == 0 else 1)
