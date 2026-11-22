extends SceneTree
## T-237: detached tile-history descriptors must be frozen before lazy callbacks.

const STRIDE: int = 64
const HIDDEN: int = 0x00335577
const INK: int = 0xff224466
const OTHER: int = 0xff778899
var checks: int = 0
var failures: int = 0


class CountingDocument:
	extends DrawingDocument
	var reads: int = 0

	func _resolve_chunk(_layer_id: String, _key: String) -> DrawingResult:
		reads += 1
		return DrawingResult.failure("LAZY_READ", "Invalid replay must not resolve a source")


class ReentrantDocument:
	extends DrawingDocument
	var reads: int = 0
	var mode: String = ""
	var delta_ref: DrawingDelta

	func _resolve_chunk(layer_id: String, key: String) -> DrawingResult:
		reads += 1
		if reads == 1 and delta_ref != null:
			match mode:
				"later_expected":
					var zeroes: PackedByteArray = PackedByteArray()
					zeroes.resize(STRIDE * STRIDE * 4)
					delta_ref.before_tiles["0,0"] = zeroes
				"later_replacement":
					var altered: PackedByteArray = delta_ref.after_tiles["0,0"].duplicate()
					altered.encode_u32(0, OTHER)
					delta_ref.after_tiles["0,0"] = altered
				"remove_later":
					delta_ref.after_tiles.erase("0,0")
				"insert_later":
					delta_ref.before_tiles["1,0"] = PackedByteArray()
					delta_ref.after_tiles["1,0"] = PackedByteArray()
				"token":
					delta_ref.native_history_token = 42
				"stride":
					delta_ref.tile_stride = 128
		return super._resolve_chunk(layer_id, key)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T237_HISTORY_PREFLIGHT_FAILED: " + label)


func full_tile(first_pixel: int, second_pixel: int = 0) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(STRIDE * STRIDE * 4)
	bytes.encode_u32(0, first_pixel)
	bytes.encode_u32(4, second_pixel)
	return bytes


func invalid_case(label: String, before: Dictionary[String, PackedByteArray],
		after: Dictionary[String, PackedByteArray], error: String) -> void:
	var doc: CountingDocument = CountingDocument.new("t237-invalid", STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var old_revision: int = doc.revision
	var delta: DrawingDelta = DrawingDelta.from_owned_tile_bytes(layer, STRIDE, before, after)
	var result: DrawingResult = doc.replay_delta(delta, false)
	check(not result.ok and result.code == error, label + " rejects correct input code")
	check(doc.reads == 0, label + " rejects before any source callback")
	check(doc.revision == old_revision and doc._native_raster_store == null and
		doc.history_length() == 0 and doc._nodes[layer].tiles.is_empty(),
		label + " does not mutate document or attach Rust")


func make_reentrant(mode: String, external: bool = false) -> Dictionary:
	var doc: ReentrantDocument = ReentrantDocument.new("t237-" + mode, STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	if external:
		check(doc.set_external_history(true).ok, "Atlas-style history enabled")
	var original: PackedByteArray = full_tile(HIDDEN)
	var first_after: PackedByteArray = full_tile(HIDDEN, INK)
	var second_after: PackedByteArray = full_tile(INK)
	doc._nodes[layer].tiles["-1,0"] = DrawingRasterTile.from_rgba8(STRIDE, original)
	var delta: DrawingDelta = DrawingDelta.from_owned_tile_bytes(layer, STRIDE,
		{"-1,0": original, "0,0": PackedByteArray()},
		{"-1,0": first_after, "0,0": second_after})
	doc.delta_ref = delta
	doc.mode = mode
	return {"doc": doc, "layer": layer, "delta": delta,
		"original": original, "first": first_after, "second": second_after}


func test_reentrant(mode: String) -> void:
	var fixture: Dictionary = make_reentrant(mode)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var previous: int = doc.revision
	var result: DrawingResult = doc.replay_delta(fixture.delta, false)
	check(not result.ok and result.code == "STALE_PIXEL", mode + " rejects changed snapshot")
	check(doc.reads == 2 and doc.revision == previous and doc._native_raster_store == null,
		mode + " rejects before native commit despite successful source callbacks")
	check(doc._nodes[layer].tiles.size() == 1 and
		(doc._nodes[layer].tiles["-1,0"] as DrawingRasterTile).to_rgba8() == fixture.original,
		mode + " leaves exact source bytes intact")


func test_success() -> void:
	var fixture: Dictionary = make_reentrant("", true)
	var doc: ReentrantDocument = fixture.doc
	var layer: String = fixture.layer
	var delta: DrawingDelta = fixture.delta
	var original_revision: int = doc.revision
	var published: DrawingResult = doc.replay_delta(delta, false)
	check(published.ok and doc._native_raster_store != null and doc.revision == original_revision + 1,
		"valid detached replay bootstraps Rust authority")
	check(doc.history_length() == 0 and doc._native_raster_store.call("stats")["revision"] == doc.revision,
		"Atlas-style replay leaves local history empty and revisions aligned")
	check(int(doc.read_pixel(layer, -64, 0).value) == HIDDEN and
		int(doc.read_pixel(layer, -63, 0).value) == INK and
		int(doc.read_pixel(layer, 0, 0).value) == INK,
		"signed hidden RGB and two tiles are preserved exactly")
	if published.ok:
		var native: Object = doc._native_raster_store
		var first: Dictionary = native.call("read_tile", layer, -1, 0, false)
		var second: Dictionary = native.call("read_tile", layer, 0, 0, false)
		check(bool(first.get("ok", false)) and first.get("bytes") == fixture.first and
			bool(second.get("ok", false)) and second.get("bytes") == fixture.second,
			"Rust owns exact detached replacement buffers")
		check(doc.replay_delta(delta, true).ok and doc._native_raster_store == native and
			int(doc.read_pixel(layer, -64, 0).value) == HIDDEN and
			int(doc.read_pixel(layer, -63, 0).value) == 0 and
			int(doc.read_pixel(layer, 0, 0).value) == 0,
			"detached Undo reuses Rust and restores source bytes")
		check(doc.replay_delta(delta, false).ok and
			int(doc.read_pixel(layer, -63, 0).value) == INK,
			"detached Redo restores exact signed RGBA8")
		var malformed: DrawingDelta = delta.detached_copy()
		malformed.after_tiles["0,0"] = PackedByteArray([1, 2, 3])
		var prior_reads: int = doc.reads
		var prior_revision: int = doc.revision
		var rejected: DrawingResult = doc.replay_delta(malformed, true)
		check(not rejected.ok and rejected.code == "RGBA",
			"malformed later Undo tile is rejected with existing Rust attachment")
		check(doc.reads == prior_reads and doc._native_raster_store == native and
			doc.revision == prior_revision,
			"attached native Undo preflight consumes neither sources nor revision")
		check(int(doc.read_pixel(layer, -63, 0).value) == INK and
			int(native.call("stats").get("revision", -1)) == prior_revision,
			"rejected replay keeps byte-exact native source and history")
		var path: String = ProjectSettings.globalize_path("user://t237-" +
			DrawingDocument.new_id() + ".drawing")
		check(DrawingFileIO.save(doc, path).ok, "native replay Save succeeds")
		var reopened: DrawingResult = DrawingFileIO.open(path)
		check(reopened.ok and reopened.value != null and
			int((reopened.value as DrawingDocument).read_pixel(layer, -64, 0).value) == HIDDEN,
			"Save/Open preserves alpha-zero RGB after detached replay")
		DirAccess.remove_absolute(path)


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "real native tile extension loaded")
	invalid_case("later invalid key",
		{"-1,0": PackedByteArray(), "01,0": PackedByteArray()},
		{"-1,0": full_tile(INK), "01,0": full_tile(INK)}, "COORD")
	invalid_case("later short replacement",
		{"-1,0": PackedByteArray(), "0,0": PackedByteArray()},
		{"-1,0": full_tile(INK), "0,0": PackedByteArray([1, 2, 3])}, "RGBA")
	invalid_case("later missing original",
		{"-1,0": PackedByteArray(), "1,0": PackedByteArray()},
		{"-1,0": full_tile(INK), "0,0": full_tile(INK)}, "HISTORY_TARGET")
	for mode: String in ["later_expected", "later_replacement", "remove_later", "insert_later", "token", "stride"]:
		test_reentrant(mode)
	test_success()
	if failures == 0:
		print("T237_HISTORY_PREFLIGHT_PASSED checks=%d failures=0" % checks)
	else:
		printerr("T237_HISTORY_PREFLIGHT_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
