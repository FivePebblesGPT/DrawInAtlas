extends SceneTree

# Isolated, headless, same-input stage-to-publication timing comparison.
# All pixel correctness checks happen outside the measured intervals.
const SIDES: Array[int] = [32, 128, 256]
const GESTURES: Array[String] = ["short", "crossing"]
const TRIALS: int = 6
const WARMUP: int = 2
const BRUSH_WIDTH: float = 4.0
const PAINT: int = 0x8044aacc

var checks: int = 0
var failures: int = 0


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T068_SCALAR_PUBLICATION_FAIL: ", label)


static func _samples(side: int, gesture: String) -> PackedVector2Array:
	if gesture == "short":
		return PackedVector2Array([
			Vector2(3.5, float(side) / 2.0 + 0.5),
			Vector2(float(side) - 3.5, float(side) / 2.0 + 0.5)])
	return PackedVector2Array([
		Vector2(float(side) * 0.25 + 0.5, float(side) * 0.25 + 0.5),
		Vector2(float(side) * 0.75 + 0.5, float(side) * 0.75 + 0.5),
		Vector2(float(side) * 0.25 + 0.5, float(side) * 0.75 + 0.5),
		Vector2(float(side) * 0.75 + 0.5, float(side) * 0.25 + 0.5)])


static func _packed_path(samples: PackedVector2Array) -> PackedByteArray:
	var raw: PackedByteArray = PackedByteArray()
	raw.resize(samples.size() * 16)
	for index: int in range(samples.size()):
		raw.encode_double(index * 16, samples[index].x)
		raw.encode_double(index * 16 + 8, samples[index].y)
	return raw


static func _new_document(side: int, name: String) -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new(name, side)
	var created: DrawingResult = doc.create_layer(DrawingLayerNode.RASTER, "Pixels")
	if not created.ok:
		return {"ok": false}
	var layer: String = String(created.value)
	var begun: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not begun.ok:
		return {"ok": false}
	var edit: DrawingEditSession = begun.value
	var filled: DrawingResult = edit.fill_rect(Rect2i(1, 1, 1, 1), 0x00112233)
	if not filled.ok or not edit.commit().ok:
		return {"ok": false}
	return {"ok": true, "doc": doc, "layer": layer}


static func _tile(doc: DrawingDocument, layer: String, side: int) -> PackedByteArray:
	var result: DrawingResult = doc.request_chunk_at(layer, 0, 0)
	if result.ok and result.value is DrawingRasterTile:
		return (result.value as DrawingRasterTile).to_rgba8()
	var empty: PackedByteArray = PackedByteArray()
	empty.resize(side * side * 4)
	return empty


static func _decode_sparse(source: PackedByteArray, payload: PackedByteArray,
		side: int) -> Dictionary:
	if payload.size() < 4 or (payload.size() - 4) % 12 != 0:
		return {"ok": false}
	var count: int = payload.decode_u32(0)
	if count == 0 or count > side * side or payload.size() != 4 + count * 12:
		return {"ok": false}
	var recovered: PackedByteArray = source.duplicate()
	var deltas: Array[Dictionary] = []
	var previous: int = -1
	for index: int in range(count):
		var offset: int = 4 + index * 12
		var pixel: int = payload.decode_u32(offset)
		if pixel <= previous or pixel >= side * side:
			return {"ok": false}
		previous = pixel
		var before: int = payload.decode_u32(offset + 4)
		var after: int = payload.decode_u32(offset + 8)
		if source.decode_u32(pixel * 4) != before or before == after:
			return {"ok": false}
		recovered.encode_u32(pixel * 4, after)
		deltas.append({"x": pixel % side, "y": pixel / side,
			"before": before, "after": after})
	return {"ok": true, "bytes": recovered, "deltas": deltas}


static func _distribution(values: Array) -> Dictionary:
	var ordered: Array = values.duplicate()
	ordered.sort()
	return {"trials": ordered.size(), "min_us": ordered[0],
		"median_us": ordered[ordered.size() / 2], "max_us": ordered[ordered.size() - 1]}


# The independent Godot oracle is computed once per workload before timing.
# The native sparse output must match it BEFORE any staging or publication.
func _godot_trial(reference: Dictionary, samples: PackedVector2Array) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var begun: DrawingResult = reference.doc.begin_edit(reference.layer, reference.doc.revision)
	var painted: DrawingResult = begun.value.paint_path(samples, PAINT, BRUSH_WIDTH) if begun.ok else DrawingResult.failure("BEGIN", "No reference edit")
	var stage_us: int = Time.get_ticks_usec() - start
	if not begun.ok or not painted.ok:
		return {"ok": false}
	start = Time.get_ticks_usec()
	var committed: DrawingResult = begun.value.commit()
	var commit_us: int = Time.get_ticks_usec() - start
	return {"ok": committed.ok, "godot_stage": stage_us,
		"godot_commit": commit_us}


func _native_trial(bridge: Object, native: Dictionary, source: PackedByteArray,
		selection: PackedByteArray, points: PackedByteArray, side: int,
		paint: PackedByteArray, expected: PackedByteArray) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var payload: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, selection, points, side, BRUSH_WIDTH, paint, 0, side * side)
	var call_us: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var decoded: Dictionary = _decode_sparse(source, payload, side)
	var decode_us: int = Time.get_ticks_usec() - start
	if not decoded.get("ok", false) or decoded.get("bytes", PackedByteArray()) != expected:
		return {"ok": false}
	start = Time.get_ticks_usec()
	var staging_result: DrawingResult = native.doc.begin_edit(native.layer, native.doc.revision)
	var staged: bool = staging_result.ok
	if staged:
		var edit: DrawingEditSession = staging_result.value
		for delta: Dictionary in decoded.deltas:
			if not edit._stage(delta.x, delta.y, delta.after, null,
					false, false, delta.before).ok:
				staged = false
				break
	var stage_us: int = Time.get_ticks_usec() - start
	if not staged:
		return {"ok": false}
	start = Time.get_ticks_usec()
	var published: DrawingResult = staging_result.value.commit()
	var commit_us: int = Time.get_ticks_usec() - start
	return {"ok": published.ok, "payload": payload, "decoded": decoded,
		"native_call": call_us, "native_decode": decode_us,
		"native_stage": stage_us, "native_commit": commit_us}


func _case(bridge: Object, side: int, gesture: String) -> Dictionary:
	var samples: PackedVector2Array = _samples(side, gesture)
	var points: PackedByteArray = _packed_path(samples)
	var selection: PackedByteArray = PackedByteArray()
	selection.resize(side * side)
	selection.fill(1)
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])
	var phases: Array[String] = ["godot_stage", "godot_commit", "native_call",
		"native_decode", "native_stage", "native_commit", "godot_total", "native_total"]
	var buckets: Dictionary = {}
	for phase: String in phases:
		buckets[phase] = []
	var paired_samples: Array[Dictionary] = []
	# Compute and retain a complete trusted canonical result before any native
	# publication, even on trials when native timing executes first.
	var oracle: Dictionary = _new_document(side, "oracle")
	_check(oracle.get("ok", false), "independent canonical oracle document %d/%s" % [side, gesture])
	if not oracle.get("ok", false):
		return {}
	var oracle_source: PackedByteArray = _tile(oracle.doc, oracle.layer, side)
	var oracle_paint: Dictionary = _godot_trial(oracle, samples)
	_check(oracle_paint.get("ok", false), "independent canonical oracle painted %d/%s" % [side, gesture])
	if not oracle_paint.get("ok", false):
		return {}
	var expected: PackedByteArray = _tile(oracle.doc, oracle.layer, side)
	var wire_bytes: int = -1
	var changed: int = -1
	for trial: int in range(WARMUP + TRIALS):
		var reference: Dictionary = _new_document(side, "reference")
		var native: Dictionary = _new_document(side, "native")
		_check(reference.get("ok", false) and native.get("ok", false),
			"fresh identical documents %d/%s/%d" % [side, gesture, trial])
		if not reference.get("ok", false) or not native.get("ok", false):
			return {}
		var source: PackedByteArray = _tile(native.doc, native.layer, side)
		_check(source == _tile(reference.doc, reference.layer, side) and
			source == oracle_source and
			source.size() == side * side * 4 and source.decode_u32((side + 1) * 4) == 0x00112233,
			"identical canonical hidden-RGB source %d/%s/%d" % [side, gesture, trial])
		# Counterbalance execution order including both warmups. The two paths
		# still receive independent, freshly seeded source documents.
		var godot_first: bool = trial % 2 == 0
		var godot_result: Dictionary
		var native_result: Dictionary
		if godot_first:
			godot_result = _godot_trial(reference, samples)
			native_result = _native_trial(bridge, native, source, selection, points, side, paint, expected)
		else:
			native_result = _native_trial(bridge, native, source, selection, points, side, paint, expected)
			godot_result = _godot_trial(reference, samples)
		_check(godot_result.get("ok", false) and native_result.get("ok", false),
			"matched paths complete %d/%s/%d" % [side, gesture, trial])
		if not godot_result.get("ok", false) or not native_result.get("ok", false):
			return {}
		_check(_tile(reference.doc, reference.layer, side) == expected,
			"fresh canonical output matches oracle %d/%s/%d" % [side, gesture, trial])
		var decoded: Dictionary = native_result.decoded
		var payload: PackedByteArray = native_result.payload
		_check(decoded.bytes == expected,
			"independent complete native byte oracle %d/%s/%d" % [side, gesture, trial])
		if decoded.bytes != expected:
			return {}
		var count: int = decoded.deltas.size()
		_check(payload.size() == 4 + 12 * count and count > 0,
			"bounded nonempty native wire %d/%s/%d" % [side, gesture, trial])
		if trial == 0:
			wire_bytes = payload.size()
			changed = count
		else:
			_check(payload.size() == wire_bytes and count == changed,
				"stable changed set %d/%s/%d" % [side, gesture, trial])
		_check(native.doc.revision == reference.doc.revision,
			"single atomic native publication %d/%s/%d" % [side, gesture, trial])
		_check(_tile(native.doc, native.layer, side) == expected,
			"native committed tile parity %d/%s/%d" % [side, gesture, trial])
		_check(native.doc.undo().ok and _tile(native.doc, native.layer, side) == source,
			"native undo exact original %d/%s/%d" % [side, gesture, trial])
		_check(native.doc.redo().ok and _tile(native.doc, native.layer, side) == expected,
			"native redo exact published bytes %d/%s/%d" % [side, gesture, trial])
		if trial >= WARMUP:
			var record: Dictionary = {"trial": trial - WARMUP,
				"order": "godot_first" if godot_first else "native_first"}
			for phase: String in ["godot_stage", "godot_commit"]:
				record[phase] = godot_result[phase]
			for phase: String in ["native_call", "native_decode", "native_stage", "native_commit"]:
				record[phase] = native_result[phase]
			record["godot_total"] = record.godot_stage + record.godot_commit
			record["native_total"] = record.native_call + record.native_decode + record.native_stage + record.native_commit
			paired_samples.append(record)
			for phase: String in phases:
				buckets[phase].append(record[phase])
	var distributions: Dictionary = {}
	for phase: String in phases:
		distributions[phase] = _distribution(buckets[phase])
	return {"side": side, "gesture": gesture, "source_bytes": side * side * 4,
		"path_bytes": points.size(), "changed": changed, "sparse_bytes": wire_bytes,
		"samples_us": paired_samples, "measurements_us": distributions}

func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in test extension loaded")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_scalar_brush_sparse"),
		"isolated native brush registered")
	if bridge == null:
		quit(1)
		return
	var results: Array[Dictionary] = []
	for side: int in SIDES:
		for gesture: String in GESTURES:
			var observation: Dictionary = _case(bridge, side, gesture)
			if observation.is_empty():
				break
			results.append(observation)
		if results.size() != (SIDES.find(side) + 1) * GESTURES.size():
			break
	bridge.free()
	if failures == 0 and results.size() == SIDES.size() * GESTURES.size():
		print("T068_SCALAR_PUBLICATION_TIMING: " + JSON.stringify(results))
		print("T068_SCALAR_PUBLICATION_PASSED: %d checks" % checks)
	else:
		printerr("T068_SCALAR_PUBLICATION_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and results.size() == SIDES.size() * GESTURES.size() else 1)
