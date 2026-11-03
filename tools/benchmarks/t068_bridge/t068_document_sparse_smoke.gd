extends SceneTree

# T-068: compare the isolated checked sparse bridge with the old whole-tile
# adapter, with malformed native payloads and one-transaction history checks.
const SPARSE = preload("res://sparse_adapter.gd")
const FULL = preload("res://batch_adapter.gd")
var checks: int = 0
var failures: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var lazy_state: int = 0
var lazy_bytes: PackedByteArray

class ForgedBridge:
	extends RefCounted
	var payload: PackedByteArray
	func apply_sparse_checked(_source: PackedByteArray, _points: PackedInt32Array,
			_mask: PackedByteArray, _width: int, _height: int,
			_rgba: int, _operation: int) -> PackedByteArray:
		return payload

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T068_SPARSE_FAIL: ", description)

static func _fixture(stride: int = 8) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("sparse-delta", stride)
	var created: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	return {"doc": doc, "layer": String(created.value)}

static func _job(cx: int, cy: int, points: PackedInt32Array, color: int,
		operation: int = 2, mask: PackedByteArray = PackedByteArray()) -> Dictionary:
	return {"cx": cx, "cy": cy, "points": points, "rgba": color,
		"operation": operation, "mask": mask}

static func _pixel(doc: DrawingDocument, layer: String, x: int, y: int) -> int:
	var result: DrawingResult = doc.read_pixel(layer, x, y)
	return int(result.value) if result.ok else -1

static func _encoded(index: int, before: int, after: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(16)
	data.encode_u32(0, 1)
	data.encode_u32(4, index)
	data.encode_u32(8, before)
	data.encode_u32(12, after)
	return data

func _fetch(_id: String) -> Variant:
	if lazy_state == 0:
		return null
	if lazy_state == 1:
		return PackedByteArray([1, 2, 3])
	return lazy_bytes

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "opt-in sparse extension descriptor")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_sparse_checked"),
		"checked sparse native entrypoint registered")
	if bridge == null:
		quit(1)
		return

	var original: PackedByteArray = PackedByteArray()
	original.resize(8 * 8 * 4)
	var samples: PackedInt32Array = PackedInt32Array([2, 3, 2, 3, 7, 7])
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(64)
	mask[3 * 8 + 2] = 1
	var out: PackedByteArray = bridge.apply_sparse_checked(original, samples,
		mask, 8, 8, 0x00123456, 2)
	_check(out.size() == 16 and out.decode_u32(0) == 1,
		"sparse wire returns only one changed record")
	_check(out.decode_u32(4) == 26 and out.decode_u32(8) == 0 and
		out.decode_u32(12) == 0x00123456, "index, before and hidden RGB are byte exact")
	_check(original.decode_u32(26 * 4) == 0, "native output never mutates source")
	var no_op: PackedByteArray = bridge.apply_sparse_checked(original,
		PackedInt32Array(), PackedByteArray(), 8, 8, 123, 2)
	_check(no_op.size() == 4 and no_op.decode_u32(0) == 0,
		"valid empty delta list is distinguishable from native rejection")
	_check(bridge.apply_sparse_checked(original,
		PackedInt32Array([8, 0]), PackedByteArray(), 8, 8, 123, 2).is_empty(),
		"native rejects out-of-tile coordinates without a valid no-op marker")
	_check(bridge.apply_sparse_checked(original,
		PackedInt32Array([0]), PackedByteArray(), 8, 8, 123, 2).is_empty(),
		"native rejects odd coordinate vector")
	_check(bridge.apply_sparse_checked(original,
		PackedInt32Array([0, 0]), PackedByteArray([1]), 8, 8, 123, 2).is_empty(),
		"native rejects undersized mask")
	_check(bridge.apply_sparse_checked(original,
		PackedInt32Array([0, 0]), PackedByteArray(), 8, 8, 123, 5).is_empty(),
		"native rejects invalid operation")

	var old_case: Dictionary = _fixture()
	var new_case: Dictionary = _fixture()
	var first: Dictionary = _job(0, 0, samples, 0x00123456, 2, mask)
	var second: Dictionary = _job(1, 0, PackedInt32Array([0, 0, 3, 4, 3, 4]),
		0x80A0B0C0, 0)
	var jobs: Array[Dictionary] = [first, second]
	var whole: Dictionary = FULL.apply(bridge, old_case.doc, old_case.layer,
		old_case.doc.revision, jobs)
	var sparse: Dictionary = SPARSE.apply(bridge, new_case.doc, new_case.layer,
		new_case.doc.revision, jobs)
	_check(whole.ok and sparse.ok and whole.changed == sparse.changed and
		sparse.changed == 3, "multi-tile sparse and whole-tile commits have equal changes")
	_check(new_case.doc.history_length() == 1 and old_case.doc.history_length() == 1,
		"both publish one canonical history event")
	_check(sparse.native_return_bytes == 2 * 4 + sparse.changed * 12 and
		sparse.full_return_bytes == 2 * 8 * 8 * 4 and
		sparse.native_return_bytes < sparse.full_return_bytes,
		"reported native output bytes exclude full-tile return")
	_check(sparse.dirty_tiles == whole.dirty_tiles,
		"dirty rectangles and tile identities match whole-tile adapter")
	_check(_pixel(new_case.doc, new_case.layer, 2, 3) == 0x00123456 and
		_pixel(new_case.doc, new_case.layer, 8, 0) ==
		DrawingEditSession._blend(0x80A0B0C0, 0),
		"correct exact and source-over changed pixels")
	_check(_pixel(new_case.doc, new_case.layer, 7, 7) == 0,
		"masked-out pixel unchanged")
	_check(new_case.doc.undo().ok and old_case.doc.undo().ok and
		_pixel(new_case.doc, new_case.layer, 8, 0) == 0,
		"both adapters undo multi-tile transaction")
	_check(new_case.doc.redo().ok and old_case.doc.redo().ok and
		_pixel(new_case.doc, new_case.layer, 2, 3) ==
		_pixel(old_case.doc, old_case.layer, 2, 3),
		"both adapters redo multi-tile transaction")
	var revision: int = new_case.doc.revision
	sparse = SPARSE.apply(bridge, new_case.doc, new_case.layer, revision,
		[_job(0, 0, PackedInt32Array([2, 3]), 0x00123456)])
	_check(sparse.ok and sparse.changed == 0 and sparse.code == "NO_CHANGE" and
		new_case.doc.revision == revision, "sparse no-op does not publish")

	# Malformed/forged native deltas must not be installed or enter history.
	var forged: ForgedBridge = ForgedBridge.new()
	var guarded: Dictionary = _fixture()
	var gd: DrawingDocument = guarded.doc
	var gl: String = guarded.layer
	var target: Array[Dictionary] = [_job(0, 0, PackedInt32Array([1, 1]), 0xFF112233)]
	var bad_payloads: Array[PackedByteArray] = []
	bad_payloads.append(PackedByteArray([0, 1, 2])) # no count header
	var wrong_count: PackedByteArray = _encoded(9, 0, 0xFF112233)
	wrong_count.encode_u32(0, 2)
	bad_payloads.append(wrong_count)
	bad_payloads.append(_encoded(64, 0, 0xFF112233)) # out of range
	bad_payloads.append(_encoded(9, 5, 0xFF112233)) # source mismatch
	bad_payloads.append(_encoded(9, 0, 0xFF556677)) # wrong operation output
	bad_payloads.append(_encoded(9, 0, 0)) # fabricated no-change
	bad_payloads.append(_encoded(8, 0, 0xFF112233)) # outside requested points
	var duplicated: PackedByteArray = PackedByteArray()
	duplicated.resize(28)
	duplicated.encode_u32(0, 2)
	for k: int in range(2):
		duplicated.encode_u32(4 + k * 12, 9)
		duplicated.encode_u32(8 + k * 12, 0)
		duplicated.encode_u32(12 + k * 12, 0xFF112233)
	bad_payloads.append(duplicated)
	for i: int in range(bad_payloads.size()):
		forged.payload = bad_payloads[i]
		var rejected: Dictionary = SPARSE.apply(forged, gd, gl, gd.revision, target)
		_check(not rejected.ok and rejected.code == "NATIVE_DELTA" and
			gd.history_length() == 0 and _pixel(gd, gl, 1, 1) == 0,
			"malformed native payload refused without mutation %d" % i)
	var guarded_mask: PackedByteArray = PackedByteArray()
	guarded_mask.resize(64)
	forged.payload = _encoded(9, 0, 0xFF112233)
	var masked: Dictionary = SPARSE.apply(forged, gd, gl, gd.revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 0xFF112233, 2, guarded_mask)])
	_check(not masked.ok and masked.code == "NATIVE_DELTA",
		"native cannot write a pixel outside the selection mask")
	forged.payload = PackedByteArray([0, 0, 0, 0])
	var empty: Dictionary = SPARSE.apply(forged, gd, gl, gd.revision, target)
	_check(empty.ok and empty.changed == 0 and gd.history_length() == 0,
		"explicit native no-op token is benign")

	var late: Dictionary = _fixture()
	var ld: DrawingDocument = late.doc
	var ll: String = late.layer
	var stale_revision: int = ld.revision
	var competitor: Callable = func() -> void:
		var e: DrawingEditSession = ld.begin_edit(ll, ld.revision).value
		e.fill_rect(Rect2i(4, 4, 1, 1), 0xFF778899)
		e.commit()
	var losing: Dictionary = SPARSE.apply(bridge, ld, ll, stale_revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 0xFF010203),
		 _job(1, 0, PackedInt32Array([1, 1]), 0xFF040506)], competitor)
	_check(not losing.ok and losing.code == "STALE_REVISION" and
		_pixel(ld, ll, 1, 1) == 0 and _pixel(ld, ll, 9, 1) == 0 and
		_pixel(ld, ll, 4, 4) == 0xFF778899,
		"competing writer invalidates entire sparse batch")
	_check(ld.history_length() == 1 and ld.undo().ok,
		"only competing commit appears in canonical history")
	_check(ld.set_locked(ll, true).ok, "layer lock setup")
	var locked: Dictionary = SPARSE.apply(bridge, ld, ll, ld.revision,
		[_job(0, 0, PackedInt32Array([1, 1]), 0xFFFFFFFF)])
	_check(not locked.ok and locked.code == "LOCKED", "locked layer rejected")

	lazy_bytes.resize(8 * 8 * 4)
	lazy_bytes[0] = 123
	var lazy: Dictionary = _fixture()
	var lazy_doc: DrawingDocument = lazy.doc
	var lazy_layer: String = lazy.layer
	var digest: String = DrawingRasterTile.digest_rgba8(lazy_bytes, 8)
	_check(lazy_doc.register_lazy_chunk(lazy_layer, 1, 0, "lazy", digest,
		Callable(self, "_fetch")).ok, "lazy tile registered")
	var lazy_jobs: Array[Dictionary] = [
		_job(0, 0, PackedInt32Array([1, 1]), 0xFF445566),
		_job(1, 0, PackedInt32Array([0, 0]), 0x00112233)]
	var snapshot: int = lazy_doc.revision
	var missing: Dictionary = SPARSE.apply(bridge, lazy_doc, lazy_layer,
		snapshot, lazy_jobs)
	_check(not missing.ok and missing.code == "MISSING_TILE" and
		lazy_doc.revision == snapshot, "missing second source aborts all tiles")
	lazy_state = 1
	var corrupt: Dictionary = SPARSE.apply(bridge, lazy_doc, lazy_layer,
		snapshot, lazy_jobs)
	_check(not corrupt.ok and corrupt.code == "CORRUPT_TILE",
		"corrupt second source refuses whole batch")
	lazy_state = 2
	var recovered: Dictionary = SPARSE.apply(bridge, lazy_doc, lazy_layer,
		snapshot, lazy_jobs)
	_check(recovered.ok and recovered.changed == 2 and
		_pixel(lazy_doc, lazy_layer, 8, 0) == 0x00112233,
		"verified lazy source can be repaired and committed atomically")
	_check(lazy_doc.undo().ok and _pixel(lazy_doc, lazy_layer, 8, 0) == 123,
		"undo restores original lazily loaded pixel")

	var far: Dictionary = _fixture(16)
	var fx: int = 562949953421312
	var fy: int = -fx
	var far_jobs: Array[Dictionary] = [
		_job(fx, fy, PackedInt32Array([3, 4]), 0x00112233),
		_job(fx + 1, fy, PackedInt32Array([0, 5]), 0x00665544)]
	var far_result: Dictionary = SPARSE.apply(bridge, far.doc, far.layer,
		far.doc.revision, far_jobs)
	_check(far_result.ok and far_result.changed == 2 and
		_pixel(far.doc, far.layer, fx * 16 + 3, fy * 16 + 4) == 0x00112233,
		"far signed 64-bit tile coordinates round-trip without floats")
	_check(far_result.dirty_tiles.size() == 2 and far.doc.undo().ok,
		"far dirty bounds and single undo are preserved")

	# A verified stored transparent pixel retains hidden RGB on no-op
	# source-over and clears exactly on an explicit erase.
	var hidden: Dictionary = _fixture()
	var hidden_edit: DrawingEditSession = hidden.doc.begin_edit(hidden.layer,
		hidden.doc.revision).value
	_check(hidden_edit.fill_rect(Rect2i(4, 5, 1, 1), 0x00112233).ok and
		hidden_edit.commit().ok, "hidden-RGB fixture published")
	var hidden_source: PackedByteArray = hidden.doc.request_chunk_at(
		hidden.layer, 0, 0).value.to_rgba8()
	var hidden_wire: PackedByteArray = bridge.apply_sparse_checked(hidden_source,
		PackedInt32Array([4, 5]), PackedByteArray(), 8, 8, 0x00000000, 0)
	_check(hidden_wire.size() == 4 and hidden_wire.decode_u32(0) == 0,
		"zero-alpha source-over preserves original hidden RGB bytes")
	var erased: Dictionary = SPARSE.apply(bridge, hidden.doc, hidden.layer,
		hidden.doc.revision, [_job(0, 0, PackedInt32Array([4, 5]), 0, 1)])
	_check(erased.ok and erased.changed == 1 and
		_pixel(hidden.doc, hidden.layer, 4, 5) == 0 and hidden.doc.undo().ok and
		_pixel(hidden.doc, hidden.layer, 4, 5) == 0x00112233,
		"sparse clear and undo restore exact hidden RGBA8")

	# Compare native return byte counts and GDScript staging/commit costs.
	# This is diagnostic: no production GDExtension is installed in either app.
	var benchmark: Dictionary = {}
	for side: int in [32, 64, 128]:
		var full_samples: Array[int] = []
		var sparse_samples: Array[int] = []
		var output_bytes: int = 0
		for repetition: int in range(5):
			for mode: int in [0, 1] if repetition % 2 == 0 else [1, 0]:
				var f: Dictionary = _fixture(side)
				var job: Array[Dictionary] = [_job(0, 0,
					PackedInt32Array([side / 2, side / 2]), 0x804488CC)]
				var started: int = Time.get_ticks_usec()
				var outcome: Dictionary = FULL.apply(bridge, f.doc, f.layer,
					f.doc.revision, job) if mode == 0 else SPARSE.apply(bridge,
					f.doc, f.layer, f.doc.revision, job)
				var elapsed: int = Time.get_ticks_usec() - started
				_check(outcome.ok and outcome.changed == 1 and
					_pixel(f.doc, f.layer, side / 2, side / 2) == 0x804488CC,
					"benchmark exact sparse/full output %d/%d/%d" % [side, repetition, mode])
				if mode == 0:
					full_samples.append(elapsed)
				else:
					sparse_samples.append(elapsed)
					output_bytes = outcome.native_return_bytes
		full_samples.sort()
		sparse_samples.sort()
		benchmark[str(side)] = {"full_median_us": full_samples[2],
			"sparse_median_us": sparse_samples[2], "sparse_output_bytes": output_bytes,
			"full_output_bytes": side * side * 4, "samples_per_mode": 5}
	print("T068_SPARSE_TIMING: ", JSON.stringify(benchmark))

	rng.seed = 0x68006822
	for case: int in range(32):
		var a: Dictionary = _fixture(8)
		var b: Dictionary = _fixture(8)
		var random_jobs: Array[Dictionary] = []
		for tile_index: int in range(3):
			var px: int = rng.randi_range(0, 7)
			var py: int = rng.randi_range(0, 7)
			var color: int = rng.randi() | 0x40000000
			var op: int = case % 3
			var eligibility: PackedByteArray = PackedByteArray()
			if case % 2 == 0:
				eligibility.resize(64)
				eligibility[py * 8 + px] = 1
			random_jobs.append(_job(tile_index, 0,
				PackedInt32Array([px, py, px, py]), color, op, eligibility))
		var rev_a: int = a.doc.revision
		var rev_b: int = b.doc.revision
		var whole_result: Dictionary = FULL.apply(bridge, a.doc, a.layer,
			rev_a, random_jobs)
		var sparse_result: Dictionary = SPARSE.apply(bridge, b.doc, b.layer,
			rev_b, random_jobs)
		_check(whole_result.ok and sparse_result.ok and
			whole_result.changed == sparse_result.changed,
			"random whole/sparse commit parity %d" % case)
		var exact: bool = true
		for tile_index: int in range(3):
			var coordinate: PackedInt32Array = random_jobs[tile_index].points
			if _pixel(a.doc, a.layer, tile_index * 8 + coordinate[0], coordinate[1]) != \
					_pixel(b.doc, b.layer, tile_index * 8 + coordinate[0], coordinate[1]):
				exact = false
		_check(exact and whole_result.dirty_tiles == sparse_result.dirty_tiles,
			"random byte-exact pixel and dirty bounds %d" % case)
		var history_ok: bool = a.doc.history_length() == b.doc.history_length()
		if whole_result.changed == 0:
			history_ok = history_ok and a.doc.history_length() == 0
		else:
			history_ok = history_ok and a.doc.history_length() == 1 and 				a.doc.undo().ok and b.doc.undo().ok and 				a.doc.redo().ok and b.doc.redo().ok
		_check(history_ok, "random one-step or no-op history parity %d" % case)

	bridge.free()
	print("T068_SPARSE_PASSED: ", checks, " checks") if failures == 0 else \
		print("T068_SPARSE_FAILED: ", failures, "/", checks)
	quit(0 if failures == 0 else 1)
