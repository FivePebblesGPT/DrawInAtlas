extends "res://scalar_publication.gd"

# Research-only 512/1024/2048 storage-tile publication screen. A separate
# entrypoint keeps the earlier six-workload publication evidence unchanged.
const LARGE_SIDES: Array[int] = [512, 1024, 2048]
const LARGE_TRIALS: int = 4
const LARGE_WARMUPS: int = 1
const PHASES: Array[String] = ["godot_stage", "godot_commit", "native_call",
	"native_decode", "native_stage", "native_commit", "godot_total", "native_total"]


static func _hash(raw: PackedByteArray) -> String:
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(raw)
	return digest.finish().hex_encode()


# The research GDExtension explicitly caps caller capacity at 65,536 deltas.
# Passing side² exceeds that contract for 512² and larger tiles, even when
# the stroke itself changes only a few thousand pixels.
func _native_trial_large(bridge: Object, native: Dictionary, source: PackedByteArray,
		selection: PackedByteArray, points: PackedByteArray, side: int,
		paint: PackedByteArray, expected: PackedByteArray) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var payload: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, selection, points, side, BRUSH_WIDTH, paint, 0, 65536)
	var call_us: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	var decoded: Dictionary = _decode_sparse(source, payload, side)
	var decode_us: int = Time.get_ticks_usec() - start
	if not decoded.get("ok", false) or decoded.get("bytes", PackedByteArray()) != expected:
		return {"ok": false}
	start = Time.get_ticks_usec()
	var begun: DrawingResult = native.doc.begin_edit(native.layer, native.doc.revision)
	var staged: bool = begun.ok
	if staged:
		var edit: DrawingEditSession = begun.value
		for delta: Dictionary in decoded.deltas:
			if not edit._stage(delta.x, delta.y, delta.after, null,
					false, false, delta.before).ok:
				staged = false
				break
	var stage_us: int = Time.get_ticks_usec() - start
	if not staged:
		return {"ok": false}
	start = Time.get_ticks_usec()
	var published: DrawingResult = begun.value.commit()
	var commit_us: int = Time.get_ticks_usec() - start
	return {"ok": published.ok, "payload": payload, "decoded": decoded,
		"native_call": call_us, "native_decode": decode_us,
		"native_stage": stage_us, "native_commit": commit_us}


func _large_case(bridge: Object, side: int) -> Dictionary:
	var gesture: String = "long_horizontal"
	var samples: PackedVector2Array = _samples(side, "short")
	var points: PackedByteArray = _packed_path(samples)
	var selection: PackedByteArray = PackedByteArray()
	selection.resize(side * side)
	selection.fill(1)
	var paint: PackedByteArray = PackedByteArray([0xcc, 0xaa, 0x44, 0x80])

	# An independent Godot edit produces the entire expected RGBA8 tile before
	# either measured path runs. No timing includes this oracle generation.
	var oracle: Dictionary = _new_document(side, "large-oracle")
	_check(oracle.get("ok", false), "large oracle initialized %d" % side)
	if not oracle.get("ok", false):
		return {}
	var source: PackedByteArray = _tile(oracle.doc, oracle.layer, side)
	var oracle_stroke: Dictionary = _godot_trial(oracle, samples)
	_check(oracle_stroke.get("ok", false), "large oracle published %d" % side)
	if not oracle_stroke.get("ok", false):
		return {}
	var expected: PackedByteArray = _tile(oracle.doc, oracle.layer, side)
	# The temporary native bridge fails closed above its explicit delta cap
	# or when the caller cannot fit this stroke. Neither may touch source.
	_check(bridge.apply_scalar_brush_sparse(source, selection, points, side,
		BRUSH_WIDTH, paint, 0, side * side).is_empty() and
		bridge.apply_scalar_brush_sparse(source, selection, points, side,
		BRUSH_WIDTH, paint, 0, 1).is_empty() and
		_tile(oracle.doc, oracle.layer, side) == expected,
		"large invalid native capacity fails closed %d" % side)
	var expected_hash: String = _hash(expected)
	var samples_us: Array[Dictionary] = []
	var timings: Dictionary = {}
	for phase: String in PHASES:
		timings[phase] = []
	var expected_changed: int = -1
	var expected_wire: int = -1

	for trial: int in range(LARGE_TRIALS + LARGE_WARMUPS):
		var godot: Dictionary = _new_document(side, "large-godot")
		var native: Dictionary = _new_document(side, "large-native")
		_check(godot.get("ok", false) and native.get("ok", false),
			"large fresh documents %d/%d" % [side, trial])
		if not godot.get("ok", false) or not native.get("ok", false):
			return {}
		_check(_tile(godot.doc, godot.layer, side) == source and
			_tile(native.doc, native.layer, side) == source,
			"large exact source snapshots %d/%d" % [side, trial])
		var godot_first: bool = trial % 2 == 0
		var canonical: Dictionary
		var sparse: Dictionary
		if godot_first:
			canonical = _godot_trial(godot, samples)
			sparse = _native_trial_large(bridge, native, source, selection, points, side,
				paint, expected)
		else:
			sparse = _native_trial_large(bridge, native, source, selection, points, side,
				paint, expected)
			canonical = _godot_trial(godot, samples)
		_check(canonical.get("ok", false) and sparse.get("ok", false),
			"large matched paths %d/%d" % [side, trial])
		if not canonical.get("ok", false) or not sparse.get("ok", false):
			return {}
		var wire: PackedByteArray = sparse.payload
		var count: int = sparse.decoded.deltas.size()
		_check(count > 0 and wire.size() == 4 + count * 12,
			"large sparse wire %d/%d" % [side, trial])
		if expected_changed < 0:
			expected_changed = count
			expected_wire = wire.size()
		_check(count == expected_changed and wire.size() == expected_wire,
			"large deterministic sparse records %d/%d" % [side, trial])
		_check(_tile(godot.doc, godot.layer, side) == expected and
			_tile(native.doc, native.layer, side) == expected,
			"large exact published pixels %d/%d" % [side, trial])
		_check(godot.doc.revision == native.doc.revision,
			"large single revision %d/%d" % [side, trial])
		_check(native.doc.undo().ok and _tile(native.doc, native.layer, side) == source,
			"large native undo %d/%d" % [side, trial])
		_check(native.doc.redo().ok and _tile(native.doc, native.layer, side) == expected,
			"large native redo %d/%d" % [side, trial])
		if trial < LARGE_WARMUPS:
			continue
		var row: Dictionary = {"trial": trial - LARGE_WARMUPS,
			"order": "godot_first" if godot_first else "native_first"}
		for phase: String in ["godot_stage", "godot_commit"]:
			row[phase] = canonical[phase]
		for phase: String in ["native_call", "native_decode", "native_stage", "native_commit"]:
			row[phase] = sparse[phase]
		row["godot_total"] = row.godot_stage + row.godot_commit
		row["native_total"] = row.native_call + row.native_decode + row.native_stage + row.native_commit
		samples_us.append(row)
		for phase: String in PHASES:
			timings[phase].append(row[phase])
	var distributions: Dictionary = {}
	for phase: String in PHASES:
		distributions[phase] = _distribution(timings[phase])
	return {"side": side, "gesture": gesture, "source_bytes": side * side * 4,
		"path_bytes": points.size(), "changed": expected_changed,
		"sparse_bytes": expected_wire, "canonical_sha256": expected_hash,
		"samples_us": samples_us, "measurements_us": distributions}


func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in large-tile extension")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_scalar_brush_sparse"),
		"large-tile sparse native method")
	if bridge == null:
		quit(1)
		return
	var results: Array[Dictionary] = []
	for side: int in LARGE_SIDES:
		var result: Dictionary = _large_case(bridge, side)
		if result.is_empty():
			break
		results.append(result)
	bridge.free()
	if failures == 0 and results.size() == LARGE_SIDES.size():
		print("T068_LARGE_PUBLICATION_TIMING: " + JSON.stringify(results))
		print("T068_LARGE_PUBLICATION_PASSED: %d checks" % checks)
	else:
		printerr("T068_LARGE_PUBLICATION_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and results.size() == LARGE_SIDES.size() else 1)
