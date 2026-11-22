extends SceneTree
## T-165: an attached but divergent Rust store must not be bypassed by
## ordinary direct raster publication, regardless of history ownership.

const STRIDE: int = 64
const INK: int = 0xff735531
const HIDDEN: int = 0x00123456
var checks: int = 0
var failures: int = 0

class BumpingLoader:
	extends RefCounted
	var store: Object
	var revision: int
	var calls: int = 0
	var bytes: PackedByteArray

	func fetch(_ref: String) -> PackedByteArray:
		calls += 1
		# The external fetch callback can advance the native store without
		# touching the Godot document. Publication must recheck on return.
		store.call("advance_metadata_revision", revision, true)
		return bytes


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T165_FENCE_FAILED: " + label)


func paint(doc: DrawingDocument, layer: String) -> DrawingResult:
	var opened: DrawingResult = doc.begin_edit(layer, doc.revision)
	if not opened.ok:
		return opened
	var edit: DrawingEditSession = opened.value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	var configured: DrawingResult = edit.begin_native_stroke(brush,
		FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"),
		8.0, INK, Rect2i(-32, -32, 96, 96), true)
	if not configured.ok:
		edit.cancel()
		return configured
	var stroke: DrawingResult = edit.paint_path_native(
		PackedVector2Array([Vector2(4, 7), Vector2(11, 7)]), INK, false, null)
	if not stroke.ok:
		edit.cancel()
		return stroke
	return edit.commit()


func new_painted_doc() -> Dictionary:
	var doc: DrawingDocument = DrawingDocument.new("t165-" + DrawingDocument.new_id(), STRIDE)
	var layer: String = str(doc.create_layer(DrawingLayerNode.RASTER, "Ink").value)
	var painted: DrawingResult = paint(doc, layer)
	check(painted.ok and painted.delta != null and
		painted.delta.native_history_token > 0, "real Hokusai native source and token")
	return {"doc": doc, "layer": layer, "token":
		painted.delta.native_history_token if painted.ok else 0}


func run_divergence(ahead: bool, tile_local: bool, record_history: bool) -> void:
	var created: Dictionary = new_painted_doc()
	var doc: DrawingDocument = created["doc"]
	var layer: String = created["layer"]
	var token: int = created["token"]
	var store: Object = doc._native_raster_store
	var base: int = doc.revision
	var base_bytes: PackedByteArray = (store.call("read_tile", layer, 0, 0, false)
		as Dictionary).get("bytes", PackedByteArray())
	var label: String = ("ahead" if ahead else "behind") + ("-tile" if tile_local else "-pixel")
	if ahead:
		check(store.call("advance_metadata_revision", base, true), label + " create native-ahead authority")
	else:
		# Simulate an external host revision that was not bridged to Rust.
		doc.revision += 1
	var rev: int = doc.revision
	var native_rev: int = int(store.call("stats").get("revision", -1))
	check(rev != native_rev, label + " native/document revisions differ")
	var dirty: Dictionary = doc._dirty_tiles.duplicate(true)
	var history_length: int = doc.history_length()
	var history_position: int = doc.history_position()
	var epoch: int = doc.display_source_epoch
	var expected_pixel: int = int(doc.read_pixel(layer, 32, 30).value)
	check(expected_pixel == 0, label + " source pixel is transparent")
	var result: DrawingResult
	if tile_local:
		var sources: Dictionary[String, Variant] = {
			"0,0": doc._nodes[layer].tiles.get("0,0")}
		var patches: Dictionary[String, Dictionary] = {
			"0,0": {30 * STRIDE + 32: HIDDEN}}
		result = doc._publish_tile_edit(layer, rev, patches, sources, record_history)
	else:
		result = doc._publish_edit(layer, rev, {"32,30": 0},
			{"32,30": HIDDEN}, record_history)
	check(not result.ok and result.code == "STALE_REVISION", label + " rejects divergent attachment")
	check(doc.revision == rev and int(store.call("stats").get("revision", -1)) == native_rev,
		label + " neither revision advances")
	check(doc._native_raster_store == store and doc._dirty_tiles == dirty and
		doc.display_source_epoch == epoch and
		doc.history_length() == history_length and doc.history_position() == history_position,
		label + " preserves ownership, dirty state, epoch and history")
	check(int(doc.read_pixel(layer, 32, 30).value) == 0 and
		(store.call("read_tile", layer, 0, 0, false) as Dictionary).get("bytes") == base_bytes,
		label + " cannot publish a Godot-only tile")
	check(store.call("has_history_token", token, native_rev, true),
		label + " retains native history token")
	if not ahead:
		# A checked recovery explicitly rebases the old native authority. It
		# is separate from the failed publication and invalidates stale tokens.
		check(doc._native_store_for_edit(doc.revision) == store and
			int(store.call("stats").get("revision", -1)) == doc.revision,
			label + " explicit native rebase can recover")
		var retry: DrawingResult = doc._publish_edit(layer, doc.revision,
			{"32,30": 0}, {"32,30": HIDDEN}, record_history)
		check(retry.ok and int(store.call("stats").get("revision", -1)) == doc.revision and
			int(doc.read_pixel(layer, 32, 30).value) == HIDDEN,
			label + " retry publishes through native Rust")


func run_reentrant_source() -> void:
	var created: Dictionary = new_painted_doc()
	var doc: DrawingDocument = created["doc"]
	var layer: String = created["layer"]
	var store: Object = doc._native_raster_store
	var token: int = created["token"]
	var revision: int = doc.revision
	var source: PackedByteArray = (store.call("read_tile", layer, 0, 0, false)
		as Dictionary).get("bytes", PackedByteArray())
	var loader: BumpingLoader = BumpingLoader.new()
	loader.store = store
	loader.revision = revision
	loader.bytes.resize(STRIDE * STRIDE * 4)
	check(doc.register_lazy_chunk(layer, 2, 0, "loader-source",
		DrawingRasterTile.digest_rgba8(loader.bytes, STRIDE),
		Callable(loader, "fetch")).ok, "register a lazy source beside native Ink")
	var dirty: Dictionary = doc._dirty_tiles.duplicate(true)
	var history: int = doc.history_length()
	var outcome: DrawingResult = doc._publish_edit(layer, doc.revision,
		{"130,0": 0}, {"130,0": HIDDEN}, true)
	check(loader.calls == 1 and int(store.call("stats").get("revision", -1)) == revision + 1,
		"lazy loader really advanced native revision during source preflight")
	check(not outcome.ok and outcome.code == "STALE_REVISION" and doc.revision == revision,
		"final preflight rejects newly divergent native authority")
	check(doc._dirty_tiles == dirty and doc.history_length() == history and
		int(doc.read_pixel(layer, 130, 0).value) == 0,
		"rejected reentrant publish cannot dirty pixels or append history")
	check((store.call("read_tile", layer, 0, 0, false) as Dictionary).get("bytes") == source and
		store.call("has_history_token", token, revision + 1, true),
		"reentrant failure preserves unrelated Rust source and token")


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeBrush") and
		ClassDB.class_exists("DrawingNativeTiles"), "required native extension loaded")
	run_divergence(true, false, true)
	run_divergence(true, true, false)
	run_divergence(false, false, false)
	run_divergence(false, true, true)
	run_reentrant_source()
	# First direct pixel publication now acquires Rust rather than waiting
	# for a Brush gesture; it must still preserve exact hidden RGBA8.
	var legacy: DrawingDocument = DrawingDocument.new("t165-legacy", STRIDE)
	var layer: String = str(legacy.create_layer(DrawingLayerNode.RASTER, "Legacy").value)
	var nonnative: DrawingResult = legacy._publish_edit(layer, legacy.revision,
		{"-2,4": 0}, {"-2,4": HIDDEN}, false)
	check(nonnative.ok and legacy._native_raster_store != null and
		nonnative.delta.tile_stride == STRIDE and
		int(legacy.read_pixel(layer, -2, 4).value) == HIDDEN,
		"first direct pixel publication adopts exact native RGBA8")
	# At the correctly synchronized boundary, both direct formats retain the
	# existing checked adoption contract and full native RGBA8.
	var normal: Dictionary = new_painted_doc()
	var doc: DrawingDocument = normal["doc"]
	var live_layer: String = normal["layer"]
	var store: Object = doc._native_raster_store
	var direct: DrawingResult = doc._publish_edit(live_layer, doc.revision,
		{"32,30": 0}, {"32,30": HIDDEN}, false)
	check(direct.ok and int(store.call("stats").get("revision", -1)) == doc.revision,
		"in-sync untracked pixels are adopted by native")
	var sources: Dictionary[String, Variant] = {
		"0,0": doc._nodes[live_layer].tiles.get("0,0")}
	var patches: Dictionary[String, Dictionary] = {
		"0,0": {30 * STRIDE + 33: HIDDEN}}
	var tile_edit: DrawingResult = doc._publish_tile_edit(
		live_layer, doc.revision, patches, sources, true)
	check(tile_edit.ok and tile_edit.delta.native_history_token > 0 and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"in-sync recorded tile patches are native-authoritative")
	check((store.call("read_tile", live_layer, 0, 0, false) as Dictionary)
		.get("bytes", PackedByteArray()).decode_u32((30 * STRIDE + 32) * 4) == HIDDEN and
		int(doc.read_pixel(live_layer, 33, 30).value) == HIDDEN,
		"mixed direct edits retain hidden RGB")
	check(doc.undo().ok and doc.redo().ok and
		int(store.call("stats").get("revision", -1)) == doc.revision,
		"native Undo/Redo remains exact after recorded tile publication")
	print("T165_FENCE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0 and checks >= 49:
		print("T165_FENCE_PASSED (%d checks; 0 failed)" % checks)
	quit(1 if failures else 0)
