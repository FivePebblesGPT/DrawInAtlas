extends SceneTree
## T-235: direct tile-local patch preflight and reentrant descriptor/source guards.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff3366aa
const OTHER: int = 0xff778899
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(_layer_id: String, _key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_READ", "Unexpected source callback")


class ReentrantDocument:
	extends DrawingDocument
	var mode: String = ""
	var reads: int = 0
	var patches_ref: Dictionary[String, Dictionary] = {}
	var sources_ref: Dictionary[String, Variant] = {}
	var first_source: DrawingRasterTile

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		if mode == "patch" and reads == 1:
			patches_ref["1,0"] = {0: OTHER}
		elif mode == "source_keys" and reads == 1:
			sources_ref["8,0"] = null
		elif mode == "source_pixels" and key == "1,0" and first_source != null:
			first_source.set_rgba(1, 0, OTHER)
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T235_TILE_PREFLIGHT_FAILED: " + label)


func make_counting() -> Dictionary:
	var doc: CountingDocument = CountingDocument.new("t235-invalid", 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	return {"doc": doc, "layer": layer}


func test_invalid(label: String, patches: Dictionary[String, Dictionary],
		sources: Dictionary[String, Variant], code: String) -> void:
	var context: Dictionary = make_counting()
	var doc: CountingDocument = context.doc
	var base: int = doc.revision
	var outcome: DrawingResult = doc._publish_tile_edit(context.layer, base, patches, sources)
	check(not outcome.ok and outcome.code == code, label + " returns " + code)
	check(doc.reads == 0 and doc.revision == base and doc._native_raster_store == null,
		label + " rejects before any lazy source read or native attachment")
	check(doc._nodes[context.layer].tiles.is_empty() and doc.history_length() == 0,
		label + " leaves raster and history untouched")


func make_reentrant(mode: String) -> Dictionary:
	var doc: ReentrantDocument = ReentrantDocument.new("t235-" + mode, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var first: DrawingRasterTile = DrawingRasterTile.new(64)
	first.set_rgba(3, 0, HIDDEN)
	doc._nodes[layer].tiles["0,0"] = first
	doc.first_source = first
	doc.mode = mode
	doc.patches_ref = {"0,0": {0: VISIBLE}, "1,0": {0: HIDDEN}}
	doc.sources_ref = {"0,0": first, "1,0": null}
	return {"doc": doc, "layer": layer, "first": first}


func verify_native(doc: DrawingDocument, layer: String, key: String) -> bool:
	var owner: Object = doc._native_raster_store
	if owner == null:
		return false
	var parts: PackedStringArray = key.split(",")
	var native: Dictionary = owner.call("read_tile", layer, int(parts[0]), int(parts[1]), false)
	var source: DrawingResult = doc.request_chunk(layer, key)
	if not bool(native.get("ok", false)) or not source.ok:
		return false
	var expected: PackedByteArray = source.value.to_rgba8() if source.value != null else PackedByteArray()
	if expected.is_empty():
		expected.resize(64 * 64 * 4)
	return native.get("bytes", PackedByteArray()) == expected


func test_reentrant(mode: String) -> void:
	var context: Dictionary = make_reentrant(mode)
	var doc: ReentrantDocument = context.doc
	var layer: String = context.layer
	var base: int = doc.revision
	var attempt: DrawingResult = doc._publish_tile_edit(layer, base, doc.patches_ref, doc.sources_ref)
	check(not attempt.ok and attempt.code == "STALE_PIXEL", mode + " refuses mutated input/source")
	check(doc.revision == base and doc._native_raster_store == null and doc.history_length() == 0,
		mode + " commits no revision, history, or native attachment")
	check(int(doc.read_pixel(layer, 0, 0).value) == 0 and
		int(doc.read_pixel(layer, 64, 0).value) == 0,
		mode + " publishes neither requested pixel")
	check(doc.reads >= 1, mode + " exercised the lazy source boundary")


func test_success() -> void:
	var context: Dictionary = make_reentrant("")
	var doc: ReentrantDocument = context.doc
	var layer: String = context.layer
	var base: int = doc.revision
	# Sessions are allowed to have source snapshots for unmodified tiles.
	doc.sources_ref["8,0"] = null
	var result: DrawingResult = doc._publish_tile_edit(layer, base, doc.patches_ref, doc.sources_ref)
	check(result.ok and doc._native_raster_store != null, "valid signed tile transaction attaches Rust")
	check(result.ok and doc.sources_ref.has("8,0"),
		"unchanged verified source entries do not reject an otherwise valid transaction")
	check(result.ok and result.delta.native_history_token > 0 and doc.revision == base + 1,
		"recorded native history preserves one atomic revision")
	check(verify_native(doc, layer, "0,0") and verify_native(doc, layer, "1,0"),
		"valid tiles match canonical Rust RGBA8 including hidden RGB")
	check(int(doc.read_pixel(layer, 3, 0).value) == HIDDEN and
		int(doc.read_pixel(layer, 64, 0).value) == HIDDEN,
		"untouched transparent hidden RGB and new alpha-zero pixel remain exact")
	check(doc.undo().ok and int(doc.read_pixel(layer, 0, 0).value) == 0 and
		int(doc.read_pixel(layer, 64, 0).value) == 0,
		"native Undo restores both tiles")
	check(doc.redo().ok and int(doc.read_pixel(layer, 0, 0).value) == VISIBLE and
		int(doc.read_pixel(layer, 64, 0).value) == HIDDEN,
		"native Redo restores both tiles")
	var followup: DrawingResult = doc._publish_tile_edit(layer, doc.revision,
		{"0,0": {1: OTHER}}, {"0,0": doc._nodes[layer].tiles["0,0"]}, false)
	check(followup.ok and followup.delta.native_history_token == 0,
		"untracked follow-up uses same native owner without Undo token")
	check(verify_native(doc, layer, "0,0") and verify_native(doc, layer, "1,0"),
		"untracked follow-up keeps canonical native tile parity")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real compiled native extension loaded")
	var original: Dictionary[String, Dictionary] = {"0,0": {0: VISIBLE}}
	var two_sources: Dictionary[String, Variant] = {"0,0": null, "1,0": null}
	var invalid_key: Dictionary[String, Dictionary] = original.duplicate()
	invalid_key["01,0"] = {0: HIDDEN}
	test_invalid("noncanonical later tile", invalid_key,
		{"0,0": null, "01,0": null}, "COORD")
	var bad_index: Dictionary[String, Dictionary] = original.duplicate()
	bad_index["1,0"] = {-1: HIDDEN}
	test_invalid("negative later pixel index", bad_index, two_sources, "COORD")
	var bad_rgba: Dictionary[String, Dictionary] = original.duplicate()
	bad_rgba["1,0"] = {0: 0x100000000}
	test_invalid("oversized later RGBA8", bad_rgba, two_sources, "RGBA")
	var absent_source: Dictionary[String, Dictionary] = original.duplicate()
	absent_source["1,0"] = {0: HIDDEN}
	test_invalid("missing later source", absent_source, {"0,0": null}, "STALE_PIXEL")
	for mode: String in ["patch", "source_keys", "source_pixels"]:
		test_reentrant(mode)
	test_success()
	if failures == 0:
		print("T235_TILE_PREFLIGHT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T235_TILE_PREFLIGHT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
