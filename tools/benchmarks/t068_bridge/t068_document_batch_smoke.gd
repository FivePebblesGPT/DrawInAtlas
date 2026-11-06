extends SceneTree

# Isolated T-068: several checked native tiles, one canonical history event.
const ADAPTER = preload("res://batch_adapter.gd")
var checks: int = 0
var failures: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var lazy_bytes: PackedByteArray
var lazy_state: int = 0

func _fetch(_id: String) -> Variant:
	if lazy_state == 0:
		return null
	if lazy_state == 1:
		return PackedByteArray([12, 34])
	return lazy_bytes

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T068_BATCH_FAIL: ", label)

static func _make_doc(stride: int = 8) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("native-batch", stride)
	var layer: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	return {"doc": doc, "layer": String(layer.value)}

static func _job(cx: int, cy: int, points: PackedInt32Array, rgba: int,
		operation: int = 2, mask: PackedByteArray = PackedByteArray()) -> Dictionary:
	return {"cx": cx, "cy": cy, "points": points, "rgba": rgba,
		"operation": operation, "mask": mask}

static func _read(doc: DrawingDocument, layer: String, x: int, y: int) -> int:
	var result: DrawingResult = doc.read_pixel(layer, x, y)
	return int(result.value) if result.ok else -1

static func _contains_dirty(output: Dictionary, cx: int, cy: int, rect: Rect2i) -> bool:
	for row: Dictionary in output.get("dirty_tiles", []):
		if row["cx"] == cx and row["cy"] == cy and row["rect"] == rect:
			return true
	return false

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in extension load")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null, "native checked bridge available")
	if bridge == null:
		quit(1)
		return
	var fixture: Dictionary = _make_doc()
	var doc: DrawingDocument = fixture.doc
	var layer: String = fixture.layer
	var start: int = doc.revision
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(64)
	mask[3 * 8 + 2] = 1
	var first: Dictionary = _job(0, 0, PackedInt32Array([2, 3, 2, 3, 7, 0]),
		0x00123456, 2, mask)
	var second: Dictionary = _job(1, 0, PackedInt32Array([0, 0, 3, 4]),
		0x80A0B0C0, 0)
	var result: Dictionary = ADAPTER.apply(bridge, doc, layer, start, [first, second])
	_check(result.ok and result.changed == 3 and doc.revision == start + 1,
		"two tiles committed in one revision")
	_check(doc.history_length() == 1, "two native tiles use one history event")
	_check(_read(doc, layer, 2, 3) == 0x00123456 and _read(doc, layer, 7, 0) == 0,
		"masked replacement retains hidden RGB and rejects masked point")
	_check(_read(doc, layer, 8, 0) == DrawingEditSession._blend(0x80A0B0C0, 0)
		and _read(doc, layer, 11, 4) == DrawingEditSession._blend(0x80A0B0C0, 0),
		"adjacent tile exact source-over semantics")
	_check(result.dirty_tiles.size() == 2 and
		_contains_dirty(result, 0, 0, Rect2i(2, 3, 1, 1)) and
		_contains_dirty(result, 1, 0, Rect2i(0, 0, 4, 5)),
		"independent per-tile dirty bounds, no fake subtexture upload")
	_check(doc.undo().ok and _read(doc, layer, 2, 3) == 0 and
		_read(doc, layer, 8, 0) == 0, "one undo removes all tiles")
	_check(doc.redo().ok and _read(doc, layer, 2, 3) == 0x00123456 and
		_read(doc, layer, 8, 0) == DrawingEditSession._blend(0x80A0B0C0, 0),
		"one redo restores all tiles")
	var committed_revision: int = doc.revision
	result = ADAPTER.apply(bridge, doc, layer, start, [first, second])
	_check(not result.ok and result.code == "STALE_REVISION" and
		doc.revision == committed_revision, "stale batch rejected")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision,
		[_job(0, 0, PackedInt32Array([2, 3]), 0x00123456)])
	_check(result.ok and result.changed == 0 and
		doc.revision == committed_revision and doc.history_length() == 1,
		"all-no-op batch creates no history")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision, [])
	_check(not result.ok and result.code == "BATCH_LIMIT", "empty batch refused")
	var repeated: Array[Dictionary] = [first, first]
	result = ADAPTER.apply(bridge, doc, layer, committed_revision, repeated)
	_check(not result.ok and result.code == "DUPLICATE_TILE", "duplicate target refused")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 4),
		 _job(1, 0, PackedInt32Array([9, 0]), 5)])
	_check(not result.ok and result.code == "NATIVE" and
		_read(doc, layer, 1, 1) == 0, "invalid second native result is atomic")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 4),
		 _job(1, 0, PackedInt32Array([0, 0]), 5, 2, PackedByteArray([1]))])
	_check(not result.ok and result.code == "NATIVE" and
		_read(doc, layer, 1, 1) == 0, "short second mask is atomic")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 4),
		 _job(1000000000, 0, PackedInt32Array([0, 0]), 5)])
	_check(not result.ok and result.code == "VIEW_RANGE", "distant tiles refused")
	result = ADAPTER.apply(bridge, doc, layer, committed_revision,
		[_job(200000000000000000, 0, PackedInt32Array([0, 0]), 5)])
	_check(not result.ok and result.code == "COORD_RANGE", "oversized signed tile anchor refused")
	var many: Array[Dictionary] = []
	for i: int in range(17):
		many.append(_job(i, 0, PackedInt32Array([0, 0]), 4))
	result = ADAPTER.apply(bridge, doc, layer, committed_revision, many)
	_check(not result.ok and result.code == "BATCH_LIMIT", "tile-count limit enforced: %s, %d" % [result.get("code"), many.size()])
	var giant: Dictionary = _make_doc(512)
	var big_jobs: Array[Dictionary] = []
	for i: int in range(5):
		big_jobs.append(_job(i, 0, PackedInt32Array([0, 0]), 4))
	result = ADAPTER.apply(bridge, giant.doc, giant.layer, giant.doc.revision, big_jobs)
	_check(not result.ok and result.code == "BATCH_LIMIT", "total pixel budget enforced")

	# The second tile is lazy: no first-tile partial commit on missing/corrupt data.
	var lazy: Dictionary = _make_doc()
	var lazy_doc: DrawingDocument = lazy.doc
	var lazy_layer: String = lazy.layer
	lazy_bytes.resize(8 * 8 * 4)
	lazy_bytes[0] = 54
	var digest: String = DrawingRasterTile.digest_rgba8(lazy_bytes, 8)
	_check(lazy_doc.register_lazy_chunk(lazy_layer, 1, 0, "sha-source", digest,
		Callable(self, "_fetch")).ok, "lazy tile registered")
	var lazy_start: int = lazy_doc.revision
	var lazy_jobs: Array[Dictionary] = [
		_job(0, 0, PackedInt32Array([1, 1]), 0xFF445566),
		_job(1, 0, PackedInt32Array([0, 0]), 0x00112233),
	]
	result = ADAPTER.apply(bridge, lazy_doc, lazy_layer, lazy_start, lazy_jobs)
	_check(not result.ok and result.code == "MISSING_TILE" and
		lazy_doc.revision == lazy_start and _read(lazy_doc, lazy_layer, 1, 1) == 0,
		"missing second tile aborts whole batch")
	lazy_state = 1
	result = ADAPTER.apply(bridge, lazy_doc, lazy_layer, lazy_start, lazy_jobs)
	_check(not result.ok and result.code == "CORRUPT_TILE" and
		lazy_doc.revision == lazy_start, "corrupt second tile aborts whole batch")
	lazy_state = 2
	result = ADAPTER.apply(bridge, lazy_doc, lazy_layer, lazy_start, lazy_jobs)
	_check(result.ok and result.changed == 2 and
		_read(lazy_doc, lazy_layer, 1, 1) == 0xFF445566 and
		_read(lazy_doc, lazy_layer, 8, 0) == 0x00112233,
		"recovered source commits both tiles atomically")
	_check(lazy_doc.undo().ok and _read(lazy_doc, lazy_layer, 1, 1) == 0
		and _read(lazy_doc, lazy_layer, 8, 0) == 54,
		"undo restores original lazy bytes and first tile")

	# A reentrant writer wins. A staged native batch must not overwrite it.
	var racing: Dictionary = _make_doc()
	var race_doc: DrawingDocument = racing.doc
	var race_layer: String = racing.layer
	var race_revision: int = race_doc.revision
	var winner: Callable = func() -> void:
		var edit: DrawingEditSession = race_doc.begin_edit(race_layer, race_doc.revision).value
		edit.fill_rect(Rect2i(3, 3, 1, 1), 0xFF123456)
		edit.commit()
	result = ADAPTER.apply(bridge, race_doc, race_layer, race_revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 12),
		 _job(1, 0, PackedInt32Array([2, 2]), 22)], winner)
	_check(not result.ok and result.code == "STALE_REVISION" and
		_read(race_doc, race_layer, 3, 3) == 0xFF123456 and
		_read(race_doc, race_layer, 1, 1) == 0 and
		_read(race_doc, race_layer, 10, 2) == 0,
		"competing commit rejects staged multi-tile gesture")
	_check(race_doc.history_length() == 1 and race_doc.undo().ok,
		"only winner entered history")
	_check(race_doc.set_locked(race_layer, true).ok, "layer can be locked")
	var locked_rev: int = race_doc.revision
	result = ADAPTER.apply(bridge, race_doc, race_layer, locked_rev,
		[_job(0, 0, PackedInt32Array([1, 1]), 1),
		 _job(1, 0, PackedInt32Array([2, 2]), 2)])
	_check(not result.ok and result.code == "LOCKED" and race_doc.revision == locked_rev,
		"locked layer refuses batch before publication")

	var far: Dictionary = _make_doc(16)
	var far_doc: DrawingDocument = far.doc
	var far_layer: String = far.layer
	var cx: int = 562949953421312 # 2^53/16, exact signed 64-bit anchor
	var cy: int = -cx
	result = ADAPTER.apply(bridge, far_doc, far_layer, far_doc.revision,
		[_job(cx, cy, PackedInt32Array([3, 4]), 0x00112233),
		 _job(cx + 1, cy, PackedInt32Array([0, 5]), 0x00665544)])
	_check(result.ok and result.changed == 2 and result.dirty_tiles.size() == 2,
		"high signed coordinates commit together")
	_check(_contains_dirty(result, cx, cy, Rect2i(3, 4, 1, 1)) and
		_contains_dirty(result, cx + 1, cy, Rect2i(0, 5, 1, 1)),
		"far dirty bounds do not round through floats")
	_check(_read(far_doc, far_layer, cx * 16 + 3, cy * 16 + 4) == 0x00112233
		and _read(far_doc, far_layer, (cx + 1) * 16, cy * 16 + 5) == 0x00665544,
		"far tile pixels are exact")
	_check(far_doc.undo().ok and _read(far_doc, far_layer, cx * 16 + 3, cy * 16 + 4) == 0
		and _read(far_doc, far_layer, (cx + 1) * 16, cy * 16 + 5) == 0,
		"one undo restores two far tiles")

	# Deterministic randomized multi-tile oracle from canonical blending.
	rng.seed = 68006843
	for case: int in range(32):
		var tested: Dictionary = _make_doc(8)
		var td: DrawingDocument = tested.doc
		var tl: String = tested.layer
		var jobs: Array[Dictionary] = []
		var expected_values: Array[int] = []
		for tile_index: int in range(3):
			var px: int = rng.randi_range(0, 7)
			var py: int = rng.randi_range(0, 7)
			var rgba: int = rng.randi() | 0x40000000
			var op: int = 2 if case % 2 == 0 else 0
			var selection: PackedByteArray = PackedByteArray()
			if case % 2 == 0:
				selection.resize(64)
				selection[py * 8 + px] = 1
			jobs.append(_job(tile_index, 0, PackedInt32Array([px, py, px, py]),
				rgba, op, selection))
			expected_values.append(0 if op == 1 else rgba if op == 2 else
				DrawingEditSession._blend(rgba, 0))
		var before: int = td.revision
		result = ADAPTER.apply(bridge, td, tl, before, jobs)
		_check(result.ok and result.changed == 3 and td.revision == before + 1,
			"random 3-tile one-commit batch %d" % case)
		var exact: bool = true
		for i: int in range(3):
			var loc: PackedInt32Array = jobs[i]["points"]
			if _read(td, tl, i * 8 + loc[0], loc[1]) != expected_values[i]:
				exact = false
		_check(exact, "random native pixel oracle %d" % case)
		_check(td.history_length() == 1 and td.undo().ok and td.redo().ok,
			"random atomic undo/redo %d" % case)

	bridge.free()
	print("T068_BATCH_PASSED: ", checks, " checks") if failures == 0 else \
		print("T068_BATCH_FAILED: ", failures, "/", checks)
	quit(0 if failures == 0 else 1)
