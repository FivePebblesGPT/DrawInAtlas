extends SceneTree
## T-148: detached Undo/Redo after native ownership disappears or becomes stale
## must reauthorize through Rust before publishing any document tile bytes.

const STRIDE: int = 64
const INK: int = 0xff3456ab
const CLIP: Rect2i = Rect2i(-64, -64, 128, 128)
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T148_BOOTSTRAP_FAILED: " + label)


func source(document: DrawingDocument, layer: String, key: String) -> PackedByteArray:
	var loaded: DrawingResult = document.request_chunk(layer, key)
	if not loaded.ok or loaded.value == null:
		return PackedByteArray()
	return (loaded.value as DrawingRasterTile).to_rgba8()


func paint(document: DrawingDocument, layer: String, y: float) -> DrawingResult:
	var opened: DrawingResult = document.begin_edit(layer, document.revision)
	if not opened.ok:
		return opened
	var session: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var started: DrawingResult = session.begin_native_stroke(
		brush, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"), 8.0, INK, CLIP, true)
	if not started.ok:
		return started
	var stamped: DrawingResult = session.paint_path_native(PackedVector2Array([
		Vector2(-20.5, y), Vector2(12.5, y)]), INK, false, null)
	if not stamped.ok:
		return stamped
	return session.commit()


func make_document(name: String) -> Dictionary:
	var document: DrawingDocument = DrawingDocument.new(name, STRIDE)
	var layer: String = str(document.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var seed: PackedByteArray = PackedByteArray()
	seed.resize(STRIDE * STRIDE * 4)
	seed.encode_u32(0, 0x00123456)
	document._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, seed)
	var stroke: DrawingResult = paint(document, layer, 12.5)
	check(stroke.ok and stroke.delta != null and stroke.delta.native_history_token > 0,
		name + ": native Brush produces tokenized source")
	return {"document": document, "layer": layer, "seed": seed}


func check_canonical(document: DrawingDocument, layer: String, key: String, label: String) -> void:
	if document._native_raster_store == null:
		check(false, label + ": native canonical store must be attached")
		return
	var coords: PackedStringArray = key.split(",")
	var native: Dictionary = document._native_raster_store.call("read_tile", layer,
		int(coords[0]), int(coords[1]), false)
	var bytes: PackedByteArray = source(document, layer, key)
	var native_bytes: PackedByteArray = native.get("bytes", PackedByteArray())
	if bytes.is_empty():
		bytes.resize(STRIDE * STRIDE * 4)
	check(bool(native.get("ok", false)) and native_bytes == bytes,
		label + ": Rust canonical source matches document RGBA8")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles") and
		ClassDB.class_exists("DrawingNativeBrush"), "required real Rust extension is loaded")
	var absent: Dictionary = make_document("absent")
	var doc: DrawingDocument = absent["document"]
	var layer: String = absent["layer"]
	var original: Object = doc._native_raster_store
	var committed_negative: PackedByteArray = source(doc, layer, "-1,0")
	var committed_positive: PackedByteArray = source(doc, layer, "0,0")
	# A loaded/transported document can retain host history snapshots without
	# the ephemeral Rust store or its opaque history tokens.
	doc._native_raster_store = null
	var before_revision: int = doc.revision
	var undone: DrawingResult = doc.undo()
	check(undone.ok, "missing-store detached Undo accepted by fresh Rust store")
	check(doc.revision == before_revision + 1 and doc._native_raster_store != null and
		doc._native_raster_store != original and
		int(doc._native_raster_store.call("stats").get("revision", -1)) == doc.revision,
		"new Rust authority published at same revision")
	check(source(doc, layer, "-1,0") == absent["seed"] and
		source(doc, layer, "0,0").is_empty(),
		"missing-store Undo restores hidden RGB and removes blank source tile")
	check_canonical(doc, layer, "-1,0", "after missing-store Undo")
	check_canonical(doc, layer, "0,0", "after missing-store Undo")
	var recovered: Object = doc._native_raster_store
	check(doc.redo().ok and doc._native_raster_store == recovered,
		"detached Redo preserves recovered store")
	check(source(doc, layer, "-1,0") == committed_negative and
		source(doc, layer, "0,0") == committed_positive,
		"missing-store Redo restores exact signed source tiles")
	check_canonical(doc, layer, "-1,0", "after Redo")
	check_canonical(doc, layer, "0,0", "after Redo")
	var fresh: DrawingResult = paint(doc, layer, 30.5)
	check(fresh.ok and fresh.delta != null and fresh.delta.native_history_token > 0 and
		doc._native_raster_store == recovered,
		"new Brush uses recovered canonical source without store rebase")
	check(doc.undo().ok and doc.redo().ok and doc._native_raster_store == recovered,
		"new native Brush history remains valid after recovery")

	var stale: Dictionary = make_document("stale")
	var stale_doc: DrawingDocument = stale["document"]
	var stale_layer: String = stale["layer"]
	var discarded: Object = stale_doc._native_raster_store
	# Simulate an external producer advancing the document revision without
	# updating this old store. Native replay must not mutate the stale owner.
	stale_doc.revision += 1
	var stale_revision: int = stale_doc.revision
	var detached_result: DrawingResult = stale_doc.undo()
	check(detached_result.ok, "stale-store detached Undo uses new native authority")
	check(stale_doc._native_raster_store != discarded and
		int(discarded.call("stats").get("revision", -1)) == stale_revision - 1,
		"recovery leaves discarded stale Rust store untouched")
	check(int(stale_doc._native_raster_store.call("stats").get("revision", -1)) == stale_doc.revision and
		stale_doc.revision == stale_revision + 1,
		"stale-store recovery shares document revision")
	check_canonical(stale_doc, stale_layer, "-1,0", "after stale-store Undo")
	check(stale_doc.redo().ok and paint(stale_doc, stale_layer, 35.5).ok,
		"stale-store Redo and fresh Brush do not rebase recovered store")

	var ahead: Dictionary = make_document("ahead")
	var ahead_doc: DrawingDocument = ahead["document"]
	var ahead_layer: String = ahead["layer"]
	var ahead_store: Object = ahead_doc._native_raster_store
	var ahead_revision: int = ahead_doc.revision
	var ahead_bytes: PackedByteArray = source(ahead_doc, ahead_layer, "-1,0")
	check(ahead_store.call("advance_metadata_revision", ahead_revision, false),
		"native store deliberately advanced past document for negative control")
	check(not ahead_doc.undo().ok, "native-ahead authority rejects older detached snapshot")
	check(ahead_doc._native_raster_store == ahead_store and
		ahead_doc.revision == ahead_revision and
		source(ahead_doc, ahead_layer, "-1,0") == ahead_bytes,
		"ahead-store rejection preserves current Rust attachment and Godot bytes")
	ahead_doc.revision += 1
	check(ahead_doc.undo().ok and ahead_doc._native_raster_store == ahead_store,
		"replay succeeds once document revision catches up to Rust")

	var rejected: Dictionary = make_document("rejected")
	var rejected_doc: DrawingDocument = rejected["document"]
	var rejected_layer: String = rejected["layer"]
	var original_source: PackedByteArray = source(rejected_doc, rejected_layer, "-1,0")
	rejected_doc._native_raster_store = null
	var corrupt: PackedByteArray = original_source.duplicate()
	corrupt.encode_u32(0, 0xff0000ff)
	rejected_doc._nodes[rejected_layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, corrupt)
	var reject_revision: int = rejected_doc.revision
	check(not rejected_doc.undo().ok, "tampered source fails before native bootstrap")
	check(rejected_doc._native_raster_store == null and rejected_doc.revision == reject_revision and
		source(rejected_doc, rejected_layer, "-1,0") == corrupt,
		"rejected replay changes neither native attachment nor pixels")
	rejected_doc._nodes[rejected_layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(
		STRIDE, original_source)
	check(rejected_doc.undo().ok and rejected_doc._native_raster_store != null,
		"corrected source can retry through Rust without losing history")
	check_canonical(rejected_doc, rejected_layer, "-1,0", "after recovered retry")

	var noop: Dictionary = make_document("native-rejected")
	var noop_doc: DrawingDocument = noop["document"]
	var noop_layer: String = noop["layer"]
	var noop_source: PackedByteArray = source(noop_doc, noop_layer, "-1,0")
	var noop_delta: DrawingDelta = (noop_doc._events[0]["delta"] as DrawingDelta).detached_copy()
	# A syntactically valid but unchanged replacement is rejected by Rust
	# after the provisional source imports, not by Godot's source preflight.
	noop_delta.before_tiles = noop_delta.after_tiles.duplicate(true)
	noop_doc._native_raster_store = null
	var noop_revision: int = noop_doc.revision
	check(not noop_doc._replay_native_tile_delta(noop_delta, true).ok,
		"Rust rejects a no-op detached replay after provisional imports")
	check(noop_doc._native_raster_store == null and noop_doc.revision == noop_revision and
		source(noop_doc, noop_layer, "-1,0") == noop_source,
		"native rejection never attaches provisional tiles or publishes pixels")
	check(noop_doc.undo().ok and noop_doc._native_raster_store != null,
		"valid history remains replayable after rejected provisional transaction")
	check_canonical(noop_doc, noop_layer, "-1,0", "after native rejection retry")

	if failures == 0:
		print("T148_BOOTSTRAP_PASSED checks=%d failures=0" % checks)
	else:
		print("T148_BOOTSTRAP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
