extends "res://scalar_test.gd"

# Explicit-load native sparse brush: publication safety is owned by DrawingDocument.
# This checks real bridge output, rather than a forged dictionary of deltas.

static func _sha256(raw: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(raw)
	return hash.finish().hex_encode()


func _stage_records(edit: DrawingEditSession, deltas: Array) -> bool:
	for delta: Dictionary in deltas:
		if not edit._stage(delta.x, delta.y, delta.after, null,
				false, false, delta.before).ok:
			return false
	return true


func _run_case(bridge: Object, scenario: String) -> Dictionary:
	var state: Dictionary = _document("native-atomic-" + scenario)
	var doc: DrawingDocument = state.doc
	var layer: String = state.layer
	_check(_seed(doc, layer), scenario + ": hidden-RGB source seed")
	var source: PackedByteArray = _tile(doc, layer)
	var original_source: PackedByteArray = source.duplicate()
	var source_revision: int = doc.revision
	var source_history: int = doc.history_length()
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(256)
	mask.fill(1)
	var samples: PackedVector2Array = PackedVector2Array([
		Vector2(2.5, 3.5), Vector2(12.5, 11.5), Vector2(2.5, 3.5)])
	var payload: PackedByteArray = bridge.apply_scalar_brush_sparse(
		source, mask, _path(samples), 16, 4.0,
		PackedByteArray([0xcc, 0xaa, 0x44, 0x80]), 0, 256)
	var parsed: Dictionary = _source_after(source, payload)
	_check(parsed.get("ok", false) and parsed.deltas.size() == 63,
		scenario + ": checked native sparse payload")
	if not parsed.get("ok", false):
		return {}
	var canonical: Dictionary = _document("atomic-oracle-" + scenario)
	_check(_seed(canonical.doc, canonical.layer), scenario + ": independent oracle seed")
	var oracle_edit: DrawingEditSession = canonical.doc.begin_edit(
		canonical.layer, canonical.doc.revision).value
	_check(oracle_edit.paint_path(samples, 0x8044aacc, 4.0).ok and
		oracle_edit.commit().ok and parsed.bytes == _tile(canonical.doc, canonical.layer),
		scenario + ": full canonical pixel parity before publication")

	var expected_source: PackedByteArray = source.duplicate()
	var winner: int = 0xff445566
	if scenario == "cancel":
		var edit: DrawingEditSession = doc.begin_edit(layer, source_revision).value
		_check(_stage_records(edit, parsed.deltas) and edit.change_count() == 63,
			"cancel: native delta staged privately")
		edit.cancel()
		_check(not edit.commit().ok and doc.revision == source_revision and
			_tile(doc, layer) == source and doc.history_length() == source_history,
			"cancel: closed gesture has no content or history effects")
		var retry: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
		_check(_stage_records(retry, parsed.deltas) and retry.commit().ok and
			_tile(doc, layer) == parsed.bytes,
			"cancel: same native result can be retried against unchanged source")
		_check(doc.undo().ok and _tile(doc, layer) == source and
			doc.redo().ok and _tile(doc, layer) == parsed.bytes,
			"cancel: retried native stroke is one undoable transaction")
	elif scenario == "stale_before":
		var competitor: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
		_check(competitor.fill_rect(Rect2i(3, 3, 1, 1), winner).ok and
			competitor.commit().ok, "stale_before: competing edit commits")
		expected_source = _tile(doc, layer)
		var stale: DrawingResult = doc.begin_edit(layer, source_revision)
		_check(not stale.ok and stale.code == "STALE_REVISION" and
			_tile(doc, layer) == expected_source,
			"stale_before: revision mismatch rejects native publication")
		# Even if the caller incorrectly retries at the new revision, the native
		# before bytes must be checked by the canonical commit, not trusted.
		var retried: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
		_check(_stage_records(retried, parsed.deltas),
			"stale_before: reject only after complete detached staging")
		var rejected: DrawingResult = retried.commit()
		_check(not rejected.ok and rejected.code == "STALE_PIXEL" and
			_tile(doc, layer) == expected_source and
			doc.history_length() == source_history + 1,
			"stale_before: changed source pixel aborts entire native publication")
		_check(doc.undo().ok and _tile(doc, layer) == source,
			"stale_before: only the competing edit enters history")
	elif scenario == "stale_during":
		var staging: DrawingEditSession = doc.begin_edit(layer, source_revision).value
		_check(_stage_records(staging, parsed.deltas),
			"stale_during: native output staged at snapshot revision")
		var competitor: DrawingEditSession = doc.begin_edit(layer, doc.revision).value
		_check(competitor.fill_rect(Rect2i(15, 15, 1, 1), winner).ok and
			competitor.commit().ok, "stale_during: unrelated edit wins race")
		expected_source = _tile(doc, layer)
		var rejected: DrawingResult = staging.commit()
		_check(not rejected.ok and rejected.code == "STALE_REVISION" and
			_tile(doc, layer) == expected_source and
			doc.history_length() == source_history + 1,
			"stale_during: no partial writes when revision changes after staging")
		_check(doc.undo().ok and _tile(doc, layer) == source,
			"stale_during: winner remains separately undoable")
	elif scenario == "forged_before":
		var staged: DrawingEditSession = doc.begin_edit(layer, source_revision).value
		var mutated: Array[Dictionary] = parsed.deltas.duplicate(true)
		mutated[0].before = int(mutated[0].before) ^ 1
		_check(_stage_records(staged, mutated),
			"forged_before: detached staging alone is not a source-authenticity check")
		var rejected: DrawingResult = staged.commit()
		_check(not rejected.ok and rejected.code == "STALE_PIXEL" and
			_tile(doc, layer) == source and doc.revision == source_revision and
			doc.history_length() == source_history,
			"forged_before: wrong native original rejects atomic commit")
	else:
		_check(false, "unknown case")
		return {}
	_check(source == original_source,
		scenario + ": caller-owned original bytes stay immutable")
	return {"name": scenario, "changed": parsed.deltas.size(),
		"payload_bytes": payload.size(), "source_sha256": _sha256(source),
		"canonical_sha256": _sha256(parsed.bytes),
		"checks_after": checks}


func _initialize() -> void:
	var extension: GDExtension = load("res://native/t068.gdextension")
	_check(extension != null, "explicit opt-in atomicity bridge loaded")
	var bridge: Object = ClassDB.instantiate("T068RasterBench")
	_check(bridge != null and bridge.has_method("apply_scalar_brush_sparse"),
		"native checked sparse entrypoint registered")
	if bridge == null:
		quit(1)
		return
	var results: Array[Dictionary] = []
	for scenario: String in ["cancel", "stale_before", "stale_during", "forged_before"]:
		var observation: Dictionary = _run_case(bridge, scenario)
		if observation.is_empty():
			break
		results.append(observation)
	bridge.free()
	if failures == 0 and results.size() == 4:
		print("T068_SCALAR_ATOMICITY_EVIDENCE: " + JSON.stringify(results))
		print("T068_SCALAR_ATOMICITY_PASSED: %d checks" % checks)
	else:
		printerr("T068_SCALAR_ATOMICITY_FAILED: %d/%d" % [failures, checks])
	quit(0 if failures == 0 and results.size() == 4 else 1)
