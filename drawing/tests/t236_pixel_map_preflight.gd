extends SceneTree
## T-236: preflight direct pixel-map edits and reject reentrant inputs/source bytes.

const HIDDEN: int = 0x00335577
const VISIBLE: int = 0xff3366aa
const OTHER: int = 0xff778899
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(_layer_id: String, _tile_key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_READ", "Unexpected lazy source callback")


class ReentrantDocument:
	extends DrawingDocument
	var mode: String = ""
	var reads: int = 0
	var before_ref: Dictionary[String, int] = {}
	var after_ref: Dictionary[String, int] = {}
	var first_source: DrawingRasterTile

	func _resolve_chunk(layer_id: String, tile_key: String) -> DrawingResult:
		reads += 1
		if reads == 2:
			match mode:
				"before":
					before_ref["0,0"] = OTHER
				"after":
					after_ref["0,0"] = OTHER
				"later_after":
					after_ref["64,0"] = OTHER
				"source":
					first_source.set_rgba(3, 0, OTHER)
		return super._resolve_chunk(layer_id, tile_key)


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("T236_PIXEL_PREFLIGHT_FAILED: " + label)


func invalid_case(label: String, before: Dictionary[String, int],
		after: Dictionary[String, int], code: String) -> void:
	var doc: CountingDocument = CountingDocument.new("t236-invalid", 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var stamp: int = doc.revision
	var result: DrawingResult = doc._publish_edit(layer, stamp, before, after)
	check(not result.ok and result.code == code, label + " rejects with " + code)
	check(doc.reads == 0 and doc.revision == stamp,
		label + " validates complete map before any source callback")
	check(doc._native_raster_store == null and doc._nodes[layer].tiles.is_empty() and
		doc.history_length() == 0, label + " does not attach Rust or publish")


func make_reentrant(mode: String) -> Dictionary:
	var doc: ReentrantDocument = ReentrantDocument.new("t236-" + mode, 64)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var first: DrawingRasterTile = DrawingRasterTile.new(64)
	first.set_rgba(3, 0, HIDDEN)
	doc._nodes[layer].tiles["0,0"] = first
	doc.first_source = first
	doc.before_ref = {"0,0": 0, "64,0": 0}
	doc.after_ref = {"0,0": VISIBLE, "64,0": HIDDEN}
	doc.mode = mode
	return {"doc": doc, "layer": layer}


func native_matches(doc: DrawingDocument, layer: String, tile_x: int) -> bool:
	if doc._native_raster_store == null:
		return false
	var tile_key: String = "%d,0" % tile_x
	var resident: DrawingResult = doc.request_chunk(layer, tile_key)
	var bytes: PackedByteArray = resident.value.to_rgba8() if resident.ok and resident.value != null \
		else PackedByteArray()
	if bytes.is_empty():
		bytes.resize(64 * 64 * 4)
	var native: Dictionary = doc._native_raster_store.call("read_tile", layer, tile_x, 0, false)
	return resident.ok and bool(native.get("ok", false)) and native.get("bytes", PackedByteArray()) == bytes


func test_reentrant(mode: String) -> void:
	var fixture: Dictionary = make_reentrant(mode)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var stamp: int = doc.revision
	var result: DrawingResult = doc._publish_edit(layer, stamp, doc.before_ref, doc.after_ref)
	check(not result.ok and result.code == "STALE_PIXEL", mode + " rejects reentrant mutation")
	check(doc.reads == 2 and doc.revision == stamp and doc._native_raster_store == null,
		mode + " reaches second tile but does not attach or commit")
	check(doc.history_length() == 0 and not doc._nodes[layer].tiles.has("1,0") and
		int(doc.read_pixel(layer, 0, 0).value) == 0,
		mode + " publishes no requested edits")


func test_success() -> void:
	var fixture: Dictionary = make_reentrant("")
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var stamp: int = doc.revision
	var result: DrawingResult = doc._publish_edit(layer, stamp, doc.before_ref, doc.after_ref)
	check(result.ok and doc._native_raster_store != null and doc.revision == stamp + 1,
		"valid multi-tile pixel-map attaches native authority")
	check(result.ok and result.delta.native_history_token > 0 and result.delta.tile_stride == 64,
		"valid pixel-map produces one native reversible history token")
	check(native_matches(doc, layer, 0) and native_matches(doc, layer, 1),
		"native pixels agree with document including alpha-zero hidden RGB")
	check(int(doc.read_pixel(layer, 3, 0).value) == HIDDEN and
		int(doc.read_pixel(layer, 64, 0).value) == HIDDEN,
		"unmodified source and newly painted hidden RGB stay exact")
	check(doc.undo().ok and int(doc.read_pixel(layer, 0, 0).value) == 0 and
		int(doc.read_pixel(layer, 64, 0).value) == 0,
		"native Undo restores both tiles")
	check(doc.redo().ok and native_matches(doc, layer, 0) and native_matches(doc, layer, 1),
		"native Redo restores both canonical tile bytes")
	var untracked: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"1,0": 0}, {"1,0": OTHER}, false)
	check(untracked.ok and untracked.delta.native_history_token == 0 and
		native_matches(doc, layer, 0), "untracked follow-up stays native without a new token")
	var path: String = ProjectSettings.globalize_path(
		"user://t236-" + DrawingDocument.new_id() + ".drawing")
	check(DrawingFileIO.save(doc, path).ok, "native pixel-map document saves")
	var reopened: DrawingResult = DrawingFileIO.open(path)
	check(reopened.ok and reopened.value != null and
		int((reopened.value as DrawingDocument).read_pixel(layer, 64, 0).value) == HIDDEN,
		"portable Save/Open preserves hidden RGB after pixel-map edit")
	DirAccess.remove_absolute(path)

	# Atlas owns the history cursor, but the same native delta must replay
	# without adding local history or sacrificing hidden RGB.
	var host_fixture: Dictionary = make_reentrant("")
	var host: ReentrantDocument = host_fixture.doc
	var host_layer: String = host_fixture.layer
	check(host.set_external_history(true).ok, "external history mode enabled")
	var host_edit: DrawingResult = host._publish_edit(
		host_layer, host.revision, host.before_ref, host.after_ref)
	check(host_edit.ok and host_edit.delta.native_history_token > 0 and
		host.history_length() == 0, "Atlas-style commit returns native detached delta")
	if host_edit.ok:
		var delta: DrawingDelta = host_edit.delta.detached_copy()
		check(host.replay_delta(delta, true).ok and
			int(host.read_pixel(host_layer, 64, 0).value) == 0,
			"external Undo replays exact native history")
		check(host.replay_delta(delta, false).ok and
			int(host.read_pixel(host_layer, 64, 0).value) == HIDDEN and
			native_matches(host, host_layer, 1),
			"external Redo restores alpha-zero RGB and native parity")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native extension loaded")
	invalid_case("later noncanonical key", {"0,0": 0, "01,0": 0},
		{"0,0": VISIBLE, "01,0": HIDDEN}, "COORD")
	invalid_case("missing later original", {"0,0": 0},
		{"0,0": VISIBLE, "64,0": HIDDEN}, "STALE_PIXEL")
	invalid_case("invalid later replacement", {"0,0": 0, "64,0": 1},
		{"0,0": VISIBLE, "64,0": -1}, "RGBA")
	for mode: String in ["before", "after", "later_after", "source"]:
		test_reentrant(mode)
	test_success()
	if failures == 0:
		print("T236_PIXEL_PREFLIGHT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T236_PIXEL_PREFLIGHT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
