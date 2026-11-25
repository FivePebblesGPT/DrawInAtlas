extends SceneTree
## Physical sparse manifests authorize verified sources on demand, not at Open.

const STRIDE: int = 64
const HIDDEN: int = 0x00112233
const INK: int = 0xff987654
var checks: int = 0
var failures: int = 0
var fetches: int = 0
var corrupt: bool = false
var bytes: PackedByteArray


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("T316_FAILED: " + label)


func fetch(_ref: String) -> PackedByteArray:
	fetches += 1
	return PackedByteArray([1]) if corrupt else bytes


func matches(doc: DrawingDocument, layer: String, key: String) -> bool:
	var store: Object = doc._native_raster_store
	if store == null:
		return false
	var coords: PackedStringArray = key.split(",")
	return bool(store.call("has_source", layer, int(coords[0]), int(coords[1]), doc.revision)) and \
		store.call("read_tile", layer, int(coords[0]), int(coords[1]), false).get("bytes") == bytes and \
		doc._native_source_matches(layer, key, doc._nodes[layer].tiles.get(key))


func run() -> void:
	check(ClassDB.class_exists("DrawingNativeTiles"), "required native extension")
	var original: DrawingDocument = DrawingDocument.new("sparse", STRIDE)
	original.create_layer(DrawingLayerNode.RASTER, "Ink", "root", "ink")
	original.create_layer(DrawingLayerNode.RASTER, "Hidden", "root", "hidden")
	var tile: DrawingRasterTile = DrawingRasterTile.new(STRIDE)
	tile.set_rgba(1, 2, HIDDEN)
	tile.set_rgba(3, 4, INK)
	bytes = tile.to_rgba8()
	var digest: String = DrawingRasterTile.digest_rgba8(bytes, STRIDE)
	for descriptor: Array in [["ink", -1, 2], ["ink", 5, -7], ["hidden", 2, -3]]:
		check(original.register_lazy_chunk(descriptor[0], descriptor[1], descriptor[2], digest, digest, fetch).ok, "register sparse source")
	original.set_visibility("hidden", false)
	original.set_locked("hidden", true)
	var encoded: DrawingResult = DrawingBundleManifest.encode(original)
	check(encoded.ok, "physical sparse manifest encoded")
	var opened: DrawingResult = DrawingBundleManifest.decode(encoded.value["bytes"], fetch)
	check(opened.ok, "physical sparse manifest opened")
	if not opened.ok:
		quit(1)
		return
	var doc: DrawingDocument = opened.value
	var saved: int = doc.revision
	check(fetches == 0 and doc._native_raster_store == null and doc._pending_tiles.size() == 3, "open performs no pixel I/O or native allocation")
	check(doc.export_manifest().ok and fetches == 0, "untouched manifest export stays lazy")
	corrupt = true
	check(not doc.request_chunk("ink", "-1,2").ok and doc._native_raster_store == null and doc._pending_tiles.size() == 3, "corrupt first source stays pending without owner")
	corrupt = false
	check(doc.request_chunk("ink", "-1,2").ok and matches(doc, "ink", "-1,2"), "first verified tile immediately native-owned")
	check(doc._pending_tiles.size() == 2 and fetches == 2 and doc.revision == saved and not doc.is_dirty() and doc.history_length() == 0, "first read is not an edit and leaves neighbors lazy")
	check(int(doc.read_pixel("ink", -STRIDE + 1, 2 * STRIDE + 2).value) == HIDDEN and fetches == 2, "cached signed hidden RGB exact, no redundant fetch")
	var projected: DrawingRasterTile = doc._nodes["ink"].tiles["-1,2"]
	projected.set_rgba(1, 2, 0x00445566)
	check(not doc.export_manifest().ok and not doc.export_subtree("ink").ok, "save/copy rejects unauthorized mutation before paint")
	projected.set_rgba(1, 2, HIDDEN)
	check(doc.export_manifest().ok, "restored projection permits metadata export")
	var store: Object = doc._native_raster_store
	var edit: DrawingEditSession = doc.begin_edit("ink", doc.revision).value
	check(edit.fill_rect(Rect2i(-STRIDE + 1, 2 * STRIDE + 2, 1, 1), INK).ok and edit.commit().ok, "native edit of fetched tile")
	check(doc._native_raster_store == store and doc.history_length() == 1, "first edit retains native owner")
	store = doc._native_raster_store
	var before: Dictionary = store.call("stats")
	check(doc.request_chunk("hidden", "2,-3").ok and matches(doc, "hidden", "2,-3"), "locked/hidden late tile admitted at current revision")
	var after: Dictionary = store.call("stats")
	check(int(after["undo"]) == int(before["undo"]) and int(after["revision"]) == int(before["revision"]) and doc._pending_tiles.size() == 1, "late read retains unrelated history and remaining lazy tile")
	check(doc.undo().ok and matches(doc, "ink", "-1,2") and not doc.is_dirty(), "undo restores original native bytes and clean state")
	check(doc.redo().ok and doc.undo().ok, "redo/undo survives late source admission")
	check(doc.set_locked("hidden", false).ok and doc.set_visibility("hidden", true).ok, "unlock and show before recorded removal")
	check(doc.remove_subtree("hidden", true).ok and bool(store.call("is_layer_parked", "hidden")), "loaded source parks on structural remove")
	check(doc.undo().ok and matches(doc, "hidden", "2,-3"), "structural restore retains exact bytes")
	check(doc.request_chunk("ink", "5,-7").ok and matches(doc, "ink", "5,-7") and doc._pending_tiles.is_empty(), "last sparse tile independently admitted")
	# A removed unresolved subtree can become native-owned after its Undo.
	# Redo must park the now-authorized bytes rather than treating it as an
	# unreferenced subtree or restoring an obsolete pending descriptor.
	for first_read: bool in [false, true]:
		var replay: DrawingDocument = DrawingBundleManifest.decode(encoded.value["bytes"], fetch).value
		if first_read:
			check(replay.request_chunk("ink", "-1,2").ok, "mixed resident/pending subtree")
		check(replay.remove_subtree("ink", true).ok and replay.undo().ok, "remove and undo with pending source")
		check(replay.request_chunk("ink", "5,-7").ok and matches(replay, "ink", "5,-7"), "read restored pending source")
		var replay_store: Object = replay._native_raster_store
		var replay_revision: int = replay.revision
		var replay_cursor: int = replay.history_position()
		var late_tile: DrawingRasterTile = replay._nodes["ink"].tiles["5,-7"]
		late_tile.set_rgba(1, 2, 0x00445566)
		check(not replay.redo().ok and replay.revision == replay_revision and replay.history_position() == replay_cursor and replay._nodes.has("ink"), "reject altered late source before park")
		late_tile.set_rgba(1, 2, HIDDEN)
		check(bool(replay_store.call("set_layer_editable", "ink", true)), "prepare native busy counterfactual")
		var active: Dictionary = replay_store.call("begin_edit", "ink", replay_revision, false)
		check(bool(active.get("ok", false)), "hold native edit during structural redo")
		var rejected_redo: DrawingResult = replay.redo()
		check(not rejected_redo.ok and replay.revision == replay_revision and replay.history_position() == replay_cursor and (replay._events[replay_cursor]["pending"] as Dictionary).has("ink:5,-7"), "busy native park leaves original history snapshot unpromoted")
		check(bool(replay_store.call("discard_edit", int(active.get("transaction", 0)))), "release native edit")
		check(replay.redo().ok and bool(replay_store.call("is_layer_parked", "ink")), "redo parks late source")
		var reads: int = fetches
		check(replay.undo().ok and matches(replay, "ink", "5,-7") and replay.request_chunk("ink", "5,-7").ok and fetches == reads, "undo restores late source without refetch")
		check(replay.redo().ok and replay.undo().ok and matches(replay, "ink", "5,-7"), "repeat structural replay exact")
	# Inject a conflicting authorization to exercise the native admission
	# failure path independently of malformed/corrupt provider output.
	var conflict: DrawingDocument = DrawingBundleManifest.decode(encoded.value["bytes"], fetch).value
	check(conflict.request_chunk("ink", "-1,2").ok, "bootstrap conflict fixture")
	var conflict_store: Object = conflict._native_raster_store
	check(bool(conflict_store.call("import_source", "ink", 5, -7, conflict.revision, bytes)), "inject duplicate native identity")
	var conflict_revision: int = conflict.revision
	var rejected: DrawingResult = conflict.request_chunk("ink", "5,-7")
	check(not rejected.ok and rejected.code == "NATIVE_SOURCE" and conflict._pending_tiles.has("ink:5,-7") and not conflict._nodes["ink"].tiles.has("5,-7"), "native rejection leaves pending source and projection untouched")
	check(conflict._native_raster_store == conflict_store and conflict.revision == conflict_revision and conflict.history_length() == 0 and matches(conflict, "ink", "-1,2"), "native rejection preserves previous owner and exact source")
	# The first actual native stroke initializes the store before fetching.
	var painted: DrawingDocument = DrawingBundleManifest.decode(encoded.value["bytes"], fetch).value
	var session: DrawingEditSession = painted.begin_edit("ink", painted.revision).value
	var brush: Object = ClassDB.instantiate("DrawingNativeBrush")
	check(session.begin_native_stroke(brush, FileAccess.get_file_as_string("res://addons/drawing/brushes/hard_round.myb"), 8.0, INK, Rect2i(-64, 128, 64, 64), true).ok, "first actual native stroke starts on lazy source")
	var stroke_store: Object = painted._native_raster_store
	check(session.paint_path_native(PackedVector2Array([Vector2(-58, 140), Vector2(-48, 140)]), INK, false, null).ok, "stroke admits source inside active Rust transaction")
	check(matches(painted, "ink", "-1,2") and bool(stroke_store.call("has_active_edit")), "committed source exact during detached preview")
	check(painted.request_chunk("hidden", "2,-3").ok and matches(painted, "hidden", "2,-3"), "unrelated source can resolve while stroke active")
	var committed: DrawingResult = session.commit()
	check(committed.ok and committed.delta != null and committed.delta.native_history_token > 0 and painted._native_raster_store == stroke_store, "native stroke commits with retained token")
	check(painted.undo().ok and matches(painted, "ink", "-1,2") and matches(painted, "hidden", "2,-3"), "native undo restores exact original and unrelated source")
	check(painted.redo().ok, "native redo succeeds")
	# A provider may make a valid metadata edit before returning bytes. The
	# response is obsolete and must not initialize a native source owner.
	var reentrant: Dictionary = {"doc": null, "change": true}
	var provider: Callable = func(_ref: String) -> PackedByteArray:
		if reentrant["change"]:
			reentrant["change"] = false
			(reentrant["doc"] as DrawingDocument).set_locked("ink", true)
		return bytes
	var changed: DrawingDocument = DrawingBundleManifest.decode(encoded.value["bytes"], provider).value
	reentrant["doc"] = changed
	var stale: DrawingResult = changed.request_chunk("ink", "-1,2")
	check(not stale.ok and stale.code == "STALE_REVISION" and changed._native_raster_store == null and changed._pending_tiles.has("ink:-1,2"), "reentrant obsolete fetch cannot publish native source")
	check(changed.request_chunk("ink", "-1,2").ok and matches(changed, "ink", "-1,2"), "correct retry authorizes current revision")
	reentrant["doc"] = null
	print("T316_NATIVE_SPARSE_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		print("T316_NATIVE_SPARSE_PASSED")
	quit(0 if failures == 0 else 1)
